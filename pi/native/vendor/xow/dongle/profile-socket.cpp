// SPDX-License-Identifier: GPL-2.0-or-later
#include "profile-socket.h"
#include "../utils/bytes.h"
#include "../utils/log.h"

#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <fstream>
#include <poll.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

namespace {
constexpr char SOCKET_NAME[] = "pi5.elite.profiles.v1";
constexpr size_t MAX_REQUEST = 64;
constexpr int POLL_MS = 200;

enum class Access { denied, readOnly, readWrite };

Access peerAccess(int fd)
{
    struct ucred cred = {};
    socklen_t size = sizeof(cred);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &size) != 0 ||
        size != sizeof(cred)) return Access::denied;
    if (cred.uid == 0 || cred.uid == 2000) return Access::readOnly;
    if (cred.uid < 10000) return Access::denied;

    std::ifstream packages("/data/system/packages.list");
    std::string line;
    bool found = false;
    while (std::getline(packages, line)) {
        std::istringstream row(line);
        std::string name;
        unsigned int uid;
        if (!(row >> name >> uid) || uid != cred.uid) continue;
        if (name != "local.pi5.elite") return Access::denied;
        found = true;
    }
    return found && packages.eof() ? Access::readWrite : Access::denied;
}

// Read or write exactly one piece of the local framing. A half-written request
// cannot hold this single-client radio transaction open indefinitely.
bool transfer(int fd, uint8_t* buffer, size_t length, short event,
              const std::atomic<bool>& stopping)
{
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
    while (length > 0) {
        if (stopping.load() || std::chrono::steady_clock::now() >= deadline) return false;
        pollfd descriptor{fd, event, 0};
        int result = poll(&descriptor, 1, POLL_MS);
        if (result == 0 || (result < 0 && errno == EINTR)) continue;
        if (result < 0 || !(descriptor.revents & event)) return false;
        ssize_t count = event == POLLIN
            ? recv(fd, buffer, length, 0)
            : send(fd, buffer, length, MSG_NOSIGNAL);
        if (count < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (count <= 0) return false;
        buffer += count;
        length -= static_cast<size_t>(count);
    }
    return true;
}

bool allowed(const Bytes& frame, Access access)
{
    if (frame.size() < 5 || frame[0] != 0x4d || frame[1] != 0x10 ||
        frame[2] == 0 || frame[3] != frame.size() - 4) return false;

    uint8_t op = frame[4];
    if (op == 1 || op == 2) {
        if (frame.size() < 7 || frame[5] < 0x20 || frame[5] > 0x2b) return false;
        size_t size = frame[5] % 2 == 0 ? 56 : 43;
        if (frame[6] != size) return false;
        return op == 2 ? frame.size() == 7
                       : access == Access::readWrite && frame.size() == 7 + size;
    }
    if (access != Access::readWrite) return false;
    if(op==4)return frame.size()==37; if(op==5)return frame.size()==5;
    if (op == 3) return frame.size() == 5;
    return op == 7 && frame.size() == 6 && frame[5] == 0;
}

struct Callbacks {
    std::function<std::string()> list;
    std::function<bool(const std::string&)> validToken;
    std::function<std::string(const std::string&, const Bytes&, Bytes&)> exchange;
    std::function<std::string(const std::string&,int)> monitor;std::function<bool()> pair;
};

void serveClient(int fd, Access access, const Callbacks& handlers,
                 const std::atomic<bool>& stopping)
{
    std::string bound;
    uint8_t header[3];
    while (transfer(fd, header, sizeof(header), POLLIN, stopping)) {
        size_t size = (static_cast<size_t>(header[1]) << 8) | header[2];
        if (size > MAX_REQUEST) return;
        Bytes body(size);
        if (!transfer(fd, body.raw(), body.size(), POLLIN, stopping)) return;

        std::string error;
        std::string text;
        Bytes radio;
        if (header[0] == 1 && size == 0) {
            text = handlers.list();
        } else if (header[0] == 2 && size > 0) {
            bound.clear();
            std::string token(body.begin(), body.end());
            if (handlers.validToken(token)) bound = token;
            else error = "手柄已断开，请刷新后重选";
        } else if (header[0]==6 && size==0 && access==Access::readWrite) {if(!handlers.pair())error="配对失败";
        } else if (!bound.empty() && ((header[0]==4 && size==0) || (header[0]==5 && access==Access::readWrite && size==1 && body[0]<4))) {
           text=handlers.monitor(bound,header[0]==4?-1:int(body[0]));if(text.compare(0,3,"OK ")==0)text=text.substr(3);else error=text;
        } else if (header[0] == 3 && !bound.empty() && allowed(body, access)) {
            error = handlers.exchange(bound, body, radio);
        } else {
            error = "不支持的配置请求或权限不足";
        }

        if (!error.empty()) text = error;
        bool binary = error.empty() && header[0] == 3;
        size_t responseSize = binary ? radio.size() : text.size();
        if (responseSize > 65535) return;
        std::vector<uint8_t> response{
            static_cast<uint8_t>(error.empty() ? 0 : 1),
            static_cast<uint8_t>(responseSize >> 8),
            static_cast<uint8_t>(responseSize)
        };
        if (binary) response.insert(response.end(), radio.begin(), radio.end());
        else response.insert(response.end(), text.begin(), text.end());
        if (!transfer(fd, response.data(), response.size(), POLLOUT, stopping)) return;
    }
}
} // namespace

void serveProfiles(std::atomic<bool>& stopping, std::function<std::string()> list,
                   std::function<bool(const std::string&)> validToken,
                   std::function<std::string(const std::string&, const Bytes&, Bytes&)> exchange, std::function<std::string(const std::string&,int)> monitor, std::function<bool()> pair)
{
    int server = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (server < 0) {
        Log::error("Profile socket creation failed: %s", strerror(errno));
        return;
    }

    sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    // Abstract names include the leading zero but no trailing terminator.
    static_assert(sizeof(SOCKET_NAME) <= sizeof(address.sun_path), "name too long");
    memcpy(address.sun_path + 1, SOCKET_NAME, sizeof(SOCKET_NAME) - 1);
    socklen_t addressSize = offsetof(sockaddr_un, sun_path) + sizeof(SOCKET_NAME);
    if (bind(server, reinterpret_cast<sockaddr*>(&address), addressSize) < 0 ||
        listen(server, 4) < 0) {
        Log::error("Profile socket bind/listen failed: %s", strerror(errno));
        close(server);
        return;
    }
    Log::info("Elite profile socket ready");
    const Callbacks handlers{std::move(list), std::move(validToken), std::move(exchange),std::move(monitor),std::move(pair)};
    while (!stopping.load()) {
        pollfd descriptor{server, POLLIN, 0};
        int result = poll(&descriptor, 1, POLL_MS);
        if (result == 0 || (result < 0 && errno == EINTR)) continue;
        if (result < 0 || !(descriptor.revents & POLLIN)) break;
        int client = accept4(server, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
        if (client < 0) {
            if (errno == EAGAIN || errno == EINTR) continue;
            break;
        }
        Access access = peerAccess(client);
        if (access != Access::denied) serveClient(client, access, handlers, stopping);
        close(client);
    }
    close(server);
}
