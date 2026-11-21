// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <atomic>
#include <functional>
#include <string>

class Bytes;

void serveProfiles(
    std::atomic<bool>& stopping,
    std::function<std::string()> list,
    std::function<bool(const std::string&)> validToken,
    std::function<std::string(const std::string&, const Bytes&, Bytes&)> exchange, std::function<std::string(const std::string&,int)> monitor, std::function<bool()> pair
);
