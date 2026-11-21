/*
 * Copyright (C) 2019 Medusalix
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#include "dongle.h"
#include "profile-socket.h"
#include "../utils/log.h"
#include <chrono>

Dongle::Dongle(
    std::unique_ptr<UsbDevice> usbDevice
) : Mt76(std::move(usbDevice)), stopThreads(false)
{
    Log::info("Dongle initialized");

    threads.emplace_back(
        &Dongle::readBulkPackets,
        this,
        MT_EP_READ
    );
    threads.emplace_back(
        &Dongle::readBulkPackets,
        this,
        MT_EP_READ_PACKET
    );
    threads.emplace_back(&Dongle::serveProfileSocket, this);
}

Dongle::~Dongle()
{
    stopThreads = true;
    profileWake.notify_all();

    // Wait for all threads to shut down
    for (std::thread &thread : threads)
    {
        if (thread.joinable())
        {
            thread.join();
        }
    }
}

void Dongle::handleControllerConnect(Bytes address)
{
    std::lock_guard<std::mutex> lock(controllerMutex);

    uint8_t wcid = associateClient(address);

    if (wcid == 0)
    {
        Log::error("Failed to associate controller");

        return;
    }

    GipDevice::SendPacket sendPacket = std::bind(
        &Dongle::sendClientPacket,
        this,
        wcid,
        address,
        std::placeholders::_1
    );

    controllers[wcid - 1].reset(new Controller(
        sendPacket,
        "xow/" + Log::formatBytes(address)
    ));
    auto& identity = identities[wcid - 1];
    identity.address = address;identity.diagnosticInit=false;
    // A reconnect must invalidate clients even when the WCID and address are reused.
    auto stamp = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    identity.token = Log::formatBytes(address) + " " + std::to_string(stamp);
    profileWake.notify_all();

    Log::info("Controller '%d' connected", wcid);
}

void Dongle::handleControllerDisconnect(uint8_t wcid)
{
    // Ignore invalid WCIDs
    if (wcid == 0 || wcid > MT_WCID_COUNT)
    {
        return;
    }

    std::lock_guard<std::mutex> lock(controllerMutex);

    // Ignore unconnected controllers
    if (!controllers[wcid - 1])
    {
        return;
    }

    controllers[wcid - 1].reset();
    identities[wcid - 1] = RadioIdentity{};
    profileWake.notify_all();

    if (!removeClient(wcid))
    {
        Log::error("Failed to remove controller");

        return;
    }

    Log::info("Controller '%d' disconnected", wcid);
}

void Dongle::handleControllerPair(Bytes address, const Bytes &packet)
{
    // Ignore invalid packets
    if (packet.size() < sizeof(ReservedFrame))
    {
        return;
    }

    const ReservedFrame *frame = packet.toStruct<ReservedFrame>();

    // Type 0x01 is for pairing requests
    if (frame->type != 0x01)
    {
        return;
    }

    if (!pairClient(address))
    {
        Log::error("Failed to pair controller");

        return;
    }

    if (!setPairingStatus(false))
    {
        Log::error("Failed to disable pairing");

        return;
    }

    Log::debug(
        "Controller paired: %s",
        Log::formatBytes(address).c_str()
    );
}

void Dongle::handleControllerPacket(uint8_t wcid, const Bytes &packet)
{
    // Invalid WCID
    if (wcid == 0 || wcid > MT_WCID_COUNT)
    {
        return;
    }

    // Ignore invalid or empty packets
    if (packet.size() <= sizeof(QosFrame) + sizeof(uint16_t))
    {
        return;
    }

    // Skip 2 bytes of padding
    const Bytes data(packet, sizeof(QosFrame) + sizeof(uint16_t));

    std::lock_guard<std::mutex> lock(controllerMutex);

    // Ignore unconnected controllers
    if (!controllers[wcid - 1])
    {
        return;
    }

    if (!controllers[wcid-1]->eliteFirmware().empty()) controllers[wcid-1]->paddles.accept(data.raw(),data.size());
    if (!controllers[wcid - 1]->handlePacket(data))
    {
        Log::error("Error handling packet for controller '%d'", wcid);
    }
    else if (pendingWcid == wcid && data.size() >= 6 && data[0] == 0x4d)
    {
        captureProfileReply(wcid, data);
    }
}

void Dongle::serveProfileSocket()
{
    serveProfiles(stopThreads,
        [this]() { return listProfilePads(); },
        [this](const std::string& token) {
            std::lock_guard<std::mutex> lock(controllerMutex);
            return profileIndex(token) != controllers.size();
        },
        [this](const std::string& token, const Bytes& request, Bytes& reply) {
            return exchangeProfile(token, request, reply);
        }, [this](const std::string& t,int motor){return monitor(t,motor);},[this](){return setPairingStatus(true);});
}

std::string Dongle::monitor(const std::string& token,int motor){
 std::lock_guard<std::mutex> lock(controllerMutex);auto i=profileIndex(token);if(i==controllers.size())return "ERR 手柄已断开";
 auto& c=*controllers[i];if(motor>=0)return motor<4 && c.pulse(motor)?"OK 1":"ERR 震动指令未发送";
 auto &v=c.live;auto &b=v.buttons;int mask=(b.a<<0)|(b.b<<1)|(b.x<<2)|(b.y<<3)|(b.dpadUp<<4)|(b.dpadDown<<5)|(b.dpadLeft<<6)|(b.dpadRight<<7)|(b.bumperLeft<<8)|(b.bumperRight<<9)|(b.stickLeft<<10)|(b.stickRight<<11)|(b.start<<12)|(b.select<<13)|(c.guide<<14);
 std::string s="OK ";for(int n:{int(c.reports),mask,int(v.triggerLeft),int(v.triggerRight),int(v.stickLeftX),int(v.stickLeftY),int(v.stickRightX),int(v.stickRightY),c.paddles.display(),c.paddles.profile})s+=std::to_string(n)+" ";return s;
}
std::string Dongle::listProfilePads()
{
    std::lock_guard<std::mutex> lock(controllerMutex);
    std::string listing;
    for (size_t i = 0; i < controllers.size(); ++i)
    {
        if (controllers[i] && !controllers[i]->eliteFirmware().empty())
        {
            listing += identities[i].token + " " + controllers[i]->eliteFirmware() + "\n";
        }
    }
    return listing;
}

size_t Dongle::profileIndex(const std::string& token) const
{
    for (size_t i = 0; i < controllers.size(); ++i)
    {
        if (controllers[i] && identities[i].token == token &&
            !controllers[i]->eliteFirmware().empty())
            return i;
    }
    return controllers.size();
}

std::string Dongle::exchangeProfile(const std::string& token, const Bytes& request, Bytes& reply)
{
    std::unique_lock<std::mutex> lock(controllerMutex);
    const size_t index = profileIndex(token);
    if (stopThreads || index == controllers.size()) return "手柄连接已变化，请刷新列表";

    pendingWcid = static_cast<uint8_t>(index + 1);


    if (request[4] == 2 && !identities[index].diagnosticInit)
    {
        identities[index].diagnosticInit = true;
        pendingSequence = 1;
        pendingCommand = 7;
        pendingPage = 0;
        profileReply = Bytes();
        const Bytes init{0x4d,0x10,0x01,0x02,0x07,0x00};
        bool sent = sendClientPacket(pendingWcid, identities[index].address, init);
        Log::info("Profile diag extended report init sent=%d", sent ? 1 : 0);
        profileWake.wait_for(lock, std::chrono::milliseconds(550), [&]() {
            return stopThreads || profileReply.size() != 0 || identities[index].token != token;
        });
        Log::info("Profile diag extended response=%zu game reports=%u",
                  profileReply.size(), 0u);
        if (stopThreads || identities[index].token != token) {
            pendingWcid = 0;
            return "手柄已断开";
        }
    }
    Log::info("Profile diag TX %s", Log::formatBytes(Bytes(request.raw(), 
              request.raw() + std::min<size_t>(7,request.size()))).c_str());
    pendingSequence = request[2];
    pendingCommand = request[4];
    pendingPage = request.size() > 5 ? request[5] : 0;
    profileReply = Bytes();
    if (!sendClientPacket(pendingWcid, identities[index].address, request))
    {
        pendingWcid = 0;
        return "接收器发送失败";
    }

    // Release the controller lock while waiting; game reports continue to flow normally.
    profileWake.wait_for(lock, std::chrono::milliseconds(1400), [&]() {
        return stopThreads || profileReply.size() != 0 || identities[index].token != token;
    });
    pendingWcid = 0;

    if (stopThreads || identities[index].token != token) return "手柄已断开，请重新读取";
    if (profileReply.size() == 0)
    {
        Log::info("Profile reply timed out: controller %u, cmd %02x, seq %02x, page %02x",
                  unsigned(index + 1), pendingCommand, pendingSequence, pendingPage);
        return "手柄未返回无线配置响应";
    }
    reply = std::move(profileReply);
    return {};
}

void Dongle::captureProfileReply(uint8_t wcid, const Bytes& packet)
{
    const size_t end = 4u + packet[3];
    if (wcid != pendingWcid || (packet[1] & ~0x10) != 0 || 
        end < 6 || end > packet.size() || packet[4] != pendingCommand)
        return;
    if ((pendingCommand == 1 || pendingCommand == 2) && packet[5] == 0 &&
        (end < 7 || packet[6] != pendingPage))
        return;
    if (pendingCommand == 2 && (end < 8 || (packet[5] & 0x7f) != 0 || packet[6] != pendingPage || packet[7] != (pendingPage % 2 ? 43 : 56) || end != 8u + packet[7])) return;
    if(pendingCommand==1 && (end!=7 || packet[6]!=pendingPage)) return;
    profileReply = Bytes(packet.raw(), packet.raw() + end);
    profileReply[2]=pendingSequence; if(profileReply[5]==0x80)profileReply[5]=0;
    profileWake.notify_one();
}

void Dongle::handleWlanPacket(const Bytes &packet)
{
    // Ignore invalid or empty packets
    if (packet.size() <= sizeof(RxWi) + sizeof(WlanFrame))
    {
        return;
    }

    const RxWi *rxWi = packet.toStruct<RxWi>();
    const WlanFrame *wlanFrame = packet.toStruct<WlanFrame>(sizeof(RxWi));

    const Bytes source(
        wlanFrame->source,
        wlanFrame->source + macAddress.size()
    );
    const Bytes destination(
        wlanFrame->destination,
        wlanFrame->destination + macAddress.size()
    );

    // Packet has wrong destination address
    if (destination != macAddress)
    {
        return;
    }

    uint8_t type = wlanFrame->frameControl.type;
    uint8_t subtype = wlanFrame->frameControl.subtype;

    if (type == MT_WLAN_MANAGEMENT)
    {
        switch (subtype)
        {
            case MT_WLAN_ASSOCIATION_REQ:
                handleControllerConnect(source);
                break;

            // Only kept for compatibility with 1537 controllers
            // They associate, disassociate and associate again during pairing
            // Disassociations happen without triggering EVT_CLIENT_LOST
            case MT_WLAN_DISASSOCIATION:
                handleControllerDisconnect(rxWi->wcid);
                break;

            // Reserved frames are used for different purposes
            // Most of them are yet to be discovered
            case MT_WLAN_RESERVED:
                const Bytes innerPacket(
                    packet,
                    sizeof(RxWi) + sizeof(WlanFrame)
                );

                handleControllerPair(source, innerPacket);
                break;
        }
    }

    else if (type == MT_WLAN_DATA && subtype == MT_WLAN_QOS_DATA)
    {
        const Bytes innerPacket(
            packet,
            sizeof(RxWi) + sizeof(WlanFrame)
        );

        handleControllerPacket(rxWi->wcid, innerPacket);
    }
}

void Dongle::handleBulkData(const Bytes &data)
{
    // Ignore invalid or empty data
    if (data.size() <= sizeof(RxInfoGeneric) + sizeof(uint32_t))
    {
        return;
    }

    // Skip packet end marker (4 bytes, identical to header)
    const RxInfoGeneric *rxInfo = data.toStruct<RxInfoGeneric>();
    const Bytes packet(data, sizeof(RxInfoGeneric), sizeof(uint32_t));

    if (rxInfo->port == CPU_RX_PORT)
    {
        const RxInfoCommand *info = data.toStruct<RxInfoCommand>();

        switch (info->eventType)
        {
            case EVT_BUTTON_PRESS:
                // Setting the pairing status doesn't require locking the mutex
                setPairingStatus(true);
                break;

            case EVT_PACKET_RX:
                handleWlanPacket(packet);
                break;

            case EVT_CLIENT_LOST:
                // Packet is guaranteed not to be empty
                handleControllerDisconnect(packet[0]);
                break;
        }
    }

    else if (rxInfo->port == WLAN_PORT)
    {
        const RxInfoPacket *info = data.toStruct<RxInfoPacket>();

        if (info->is80211)
        {
            handleWlanPacket(packet);
        }
    }
}

void Dongle::readBulkPackets(uint8_t endpoint)
{
    FixedBytes<USB_MAX_BULK_TRANSFER_SIZE> buffer;

    while (!stopThreads)
    {
        int transferred = usbDevice->bulkRead(endpoint, buffer);

        // Bulk read failed
        if (transferred < 0)
        {
            break;
        }

        if (transferred > 0)
        {
            Bytes data = buffer.toBytes(transferred);

            handleBulkData(data);
        }
    }
}
