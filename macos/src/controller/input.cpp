/*
 * xow-mac - Xbox Wireless Adapter driver for macOS
 * Copyright (C) 2026
 *
 * Based on xow, Copyright (C) 2019 Medusalix
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
 */

#include "input.h"
#include "../compat/padlink.h"
#include "../utils/log.h"

#include <cstring>
#include <mutex>
#include <sstream>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

/*
 * macOS backend: forwards pad state to xowmac-padhost (the CoreHID
 * virtual gamepad host) over a unix socket. Falls back to logging
 * input changes when the padhost isn't running.
 */

namespace
{
    std::mutex linkMutex;
    int linkSocket = -1;
    uint8_t padsInUse = 0;

    bool linkConnect()
    {
        return false; // Configuration only: never forward gameplay to another process.
        if (linkSocket >= 0)
        {
            return true;
        }

        int sock = socket(AF_UNIX, SOCK_STREAM, 0);

        if (sock < 0)
        {
            return false;
        }

        sockaddr_un address = {};

        address.sun_family = AF_UNIX;
        strncpy(
            address.sun_path,
            PADLINK_SOCKET,
            sizeof(address.sun_path) - 1
        );

        if (connect(
            sock,
            reinterpret_cast<sockaddr*>(&address),
            sizeof(address)
        )) {
            close(sock);

            return false;
        }

        linkSocket = sock;

        Log::info("Connected to padhost at %s", PADLINK_SOCKET);

        return true;
    }

    bool linkSend(const PadLinkMessage &message)
    {
        if (!linkConnect())
        {
            return false;
        }

        if (write(linkSocket, &message, sizeof(message)) != sizeof(message))
        {
            Log::error("Padhost connection lost");

            close(linkSocket);
            linkSocket = -1;

            return false;
        }

        return true;
    }

    const char *keyName(uint16_t code)
    {
        switch (code)
        {
            case BTN_A: return "A";
            case BTN_B: return "B";
            case BTN_X: return "X";
            case BTN_Y: return "Y";
            case BTN_TL: return "LB";
            case BTN_TR: return "RB";
            case BTN_SELECT: return "VIEW";
            case BTN_START: return "MENU";
            case BTN_MODE: return "GUIDE";
            case BTN_THUMBL: return "LS";
            case BTN_THUMBR: return "RS";
            default: return "?";
        }
    }

    const char *axisName(uint16_t code)
    {
        switch (code)
        {
            case ABS_X: return "LX";
            case ABS_Y: return "LY";
            case ABS_RX: return "RX";
            case ABS_RY: return "RY";
            case ABS_Z: return "LT";
            case ABS_RZ: return "RT";
            case ABS_HAT0X: return "DPADX";
            case ABS_HAT0Y: return "DPADY";
            default: return "?";
        }
    }

    uint8_t hatValue(int32_t x, int32_t y)
    {
        if (y < 0) return x < 0 ? 8 : x > 0 ? 2 : 1; // NW, NE, N
        if (y > 0) return x < 0 ? 6 : x > 0 ? 4 : 5; // SW, SE, S
        return x < 0 ? 7 : x > 0 ? 3 : 0;            // W, E, neutral
    }
}

InputDevice::InputDevice(
    FeedbackReceived feedbackReceived
) : feedbackReceived(feedbackReceived) {}

InputDevice::~InputDevice()
{
    if (!created)
    {
        return;
    }

    std::lock_guard<std::mutex> lock(linkMutex);

    PadLinkMessage message = {};

    message.type = PADLINK_DESTROY;
    message.pad = padIndex;

    linkSend(message);
    padsInUse &= ~(1 << padIndex);
}

void InputDevice::addKey(uint16_t code)
{
    keys[code] = false;
}

void InputDevice::addAxis(uint16_t code, AxisConfig config)
{
    axes[code] = 0;
}

void InputDevice::addFeedback(uint16_t code) {}

void InputDevice::create(std::string name, DeviceConfig config)
{
    std::lock_guard<std::mutex> lock(linkMutex);

    // Lowest free pad slot (up to 8 controllers per dongle)
    for (padIndex = 0; padIndex < 8; padIndex++)
    {
        if (!(padsInUse & (1 << padIndex)))
        {
            break;
        }
    }

    padsInUse |= 1 << padIndex;
    deviceName = name + " #" + std::to_string(padIndex + 1);
    created = true;

    Log::info(
        "Virtual device created: '%s' (%04x:%04x, version %04x)",
        deviceName.c_str(),
        config.vendorId,
        config.productId,
        config.version
    );

    PadLinkMessage message = {};

    message.type = PADLINK_CREATE;
    message.pad = padIndex;

    if (!linkSend(message))
    {
        Log::info("Padhost unavailable, logging inputs instead");
    }
}

void InputDevice::emitCode(
    uint16_t type,
    uint16_t code,
    int32_t value
) {
    if (type == EV_KEY)
    {
        pendingKeys[code] = value;

        return;
    }

    if (type == EV_ABS)
    {
        pendingAxes[code] = value;

        return;
    }

    if (type != EV_SYN || !created)
    {
        return;
    }

    // Report: apply pending changes, then publish the full state
    bool changed = false;
    std::ostringstream changes;

    for (auto &pending : pendingKeys)
    {
        if (keys[pending.first] != pending.second)
        {
            keys[pending.first] = pending.second;
            changes << " " << keyName(pending.first)
                << (pending.second ? "+" : "-");
            changed = true;
        }
    }

    for (auto &pending : pendingAxes)
    {
        if (axes[pending.first] != pending.second)
        {
            axes[pending.first] = pending.second;
            changes << " " << axisName(pending.first)
                << "=" << pending.second;
            changed = true;
        }
    }

    pendingKeys.clear();
    pendingAxes.clear();

    if (!changed)
    {
        return;
    }

    PadLinkMessage message = {};

    message.type = PADLINK_INPUT;
    message.pad = padIndex;
    message.buttons =
        (keys[BTN_A] << PADLINK_BTN_A) |
        (keys[BTN_B] << PADLINK_BTN_B) |
        (keys[BTN_X] << PADLINK_BTN_X) |
        (keys[BTN_Y] << PADLINK_BTN_Y) |
        (keys[BTN_TL] << PADLINK_BTN_LB) |
        (keys[BTN_TR] << PADLINK_BTN_RB) |
        (keys[BTN_THUMBL] << PADLINK_BTN_LS) |
        (keys[BTN_THUMBR] << PADLINK_BTN_RS) |
        (keys[BTN_START] << PADLINK_BTN_MENU) |
        (keys[BTN_SELECT] << PADLINK_BTN_VIEW) |
        (keys[BTN_MODE] << PADLINK_BTN_GUIDE) |
        ((axes[ABS_HAT0Y] < 0) << PADLINK_BTN_DPAD_UP) |
        ((axes[ABS_HAT0Y] > 0) << PADLINK_BTN_DPAD_DOWN) |
        ((axes[ABS_HAT0X] < 0) << PADLINK_BTN_DPAD_LEFT) |
        ((axes[ABS_HAT0X] > 0) << PADLINK_BTN_DPAD_RIGHT);
    message.stickLeftX = axes[ABS_X];
    message.stickLeftY = axes[ABS_Y];
    message.stickRightX = axes[ABS_RX];
    message.stickRightY = axes[ABS_RY];
    message.triggerLeft = axes[ABS_Z];
    message.triggerRight = axes[ABS_RZ];
    message.hat = hatValue(axes[ABS_HAT0X], axes[ABS_HAT0Y]);

    std::lock_guard<std::mutex> lock(linkMutex);

    if (!linkSend(message))
    {
        std::string text = changes.str();

        Log::info("[%s]%s", deviceName.c_str(), text.c_str());
    }
}

InputException::InputException(
    std::string message
) : std::runtime_error(message) {}
