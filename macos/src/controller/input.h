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

#pragma once

#include "../compat/linux_input.h"

#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <stdexcept>

/*
 * Virtual input device for gamepads (macOS backend).
 *
 * Keeps the exact public API of xow's uinput-based InputDevice so the
 * controller layer stays untouched. The current backend logs input state;
 * the CoreHID virtual-gamepad backend plugs in behind the same interface.
 */
class InputDevice
{
public:
    using FeedbackReceived = std::function<void(
        uint16_t gain,
        ff_effect effect,
        uint8_t replayCount
    )>;

    struct AxisConfig
    {
        int32_t minimum, maximum;
        int32_t fuzz, flat;
    };

    struct DeviceConfig
    {
        uint16_t vendorId, productId;
        uint16_t version;
    };

    InputDevice(FeedbackReceived feedbackReceived);
    virtual ~InputDevice();

    void addKey(uint16_t code);
    void addAxis(uint16_t code, AxisConfig config);
    void addFeedback(uint16_t code);
    void create(std::string name, DeviceConfig config);

    inline void setKey(uint16_t key, bool pressed)
    {
        emitCode(EV_KEY, key, pressed);
    }

    inline void setAxis(uint16_t abs, int32_t value)
    {
        emitCode(EV_ABS, abs, value);
    }

    inline void report()
    {
        emitCode(EV_SYN, SYN_REPORT, 0);
    }

private:
    void emitCode(
        uint16_t type,
        uint16_t code,
        int32_t value
    );

    bool created = false;
    uint8_t padIndex = 0;
    std::string deviceName;

    std::map<uint16_t, bool> keys;
    std::map<uint16_t, int32_t> axes;
    std::map<uint16_t, bool> pendingKeys;
    std::map<uint16_t, int32_t> pendingAxes;

    FeedbackReceived feedbackReceived;
};

class InputException : public std::runtime_error
{
public:
    InputException(std::string message);
};
