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

#pragma once

#include "mt76.h"
#include "../controller/controller.h"

#include <cstdint>
#include <array>
#include <atomic>
#include <thread>
#include <mutex>

// Microsoft's vendor ID
#define DONGLE_VID 0x045e

// Product IDs for both versions of the dongle
#define DONGLE_PID_OLD 0x02e6
#define DONGLE_PID_NEW 0x02fe

// Product ID for Microsoft Surface Book 2 built-in dongle
#define DONGLE_PID_SURFACE 0x091e

/*
 * Handles received 802.11 packets
 * Delegates GIP (Game Input Protocol) packets to controllers
 */
class Dongle : public Mt76
{
public:
    Dongle(std::unique_ptr<UsbDevice> usbDevice);
    ~Dongle();

    using Mt76::setPairingStatus;

private:
    /* Packet handling */
    void handleControllerConnect(Bytes address);
    void handleControllerDisconnect(uint8_t wcid);
    void handleControllerPair(Bytes address, const Bytes &packet);
    void handleControllerPacket(uint8_t wcid, const Bytes &packet);
    void handleWlanPacket(const Bytes &packet);
    void handleBulkData(const Bytes &data);
    void readBulkPackets(uint8_t endpoint);
public:
    std::string monitor(const std::string&,int);
    std::string listProfilePads();
    size_t profileIndex(const std::string& token) const;
    std::string exchangeProfile(const std::string& token, const Bytes& request, Bytes& reply);
private:
    void captureProfileReply(uint8_t wcid, const Bytes& packet);

    std::vector<std::thread> threads;
    std::atomic<bool> stopThreads;

    std::mutex controllerMutex;
    std::array<std::unique_ptr<Controller>, MT_WCID_COUNT> controllers;
    struct RadioIdentity
    {
        Bytes address;
        std::string token;
        bool diagnosticInit = false;
    };
    std::array<RadioIdentity, MT_WCID_COUNT> identities;

    // Single configuration client; all these fields are protected by controllerMutex.
    std::condition_variable profileWake;
    uint8_t pendingWcid = 0;
    uint8_t pendingSequence = 0;
    uint8_t pendingCommand = 0;
    uint8_t pendingPage = 0;
    Bytes profileReply;
    unsigned diagBudget = 0;
    unsigned gameplayPackets = 0;
};
