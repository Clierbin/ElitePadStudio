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

#include "controller.h"
#include "../utils/log.h"

#include <cstdlib>
#include <cmath>
#include "../compat/linux_input.h"

// Configuration for the compatibility mode
#define COMPATIBILITY_ENV "XOW_COMPATIBILITY"
#define COMPATIBILITY_NAME "Microsoft X-Box 360 pad"
#define COMPATIBILITY_PID 0x028e
#define COMPATIBILITY_VERSION 0x0104

// Accessories use IDs greater than zero
#define DEVICE_ID_CONTROLLER 0
#define DEVICE_NAME "Xbox One Wireless Controller"

#define INPUT_STICK_FUZZ 255
#define INPUT_STICK_FLAT 4095
#define INPUT_TRIGGER_FUZZ 3
#define INPUT_TRIGGER_FLAT 63

#define RUMBLE_MAX_POWER 100
#define RUMBLE_DELAY std::chrono::milliseconds(10)

Controller::Controller(
    SendPacket sendPacket
) : GipDevice(sendPacket),
    inputDevice(std::bind(
        &Controller::inputFeedbackReceived,
        this,
        std::placeholders::_1,
        std::placeholders::_2,
        std::placeholders::_3
    )),
    stopRumbleThread(false) {}

Controller::~Controller()
{
    stopRumbleThread = true;
    rumbleCondition.notify_one();

    if (rumbleThread.joinable())
    {
        rumbleThread.join();
    }


}

void Controller::deviceAnnounced(uint8_t id, const AnnounceData *announce)
{
    Log::info("Device announced, product id: %04x", announce->productId);
    Log::debug(
        "Firmware version: %d.%d.%d.%d",
        announce->firmwareVersion.major,
        announce->firmwareVersion.minor,
        announce->firmwareVersion.build,
        announce->firmwareVersion.revision
    );
    Log::debug(
        "Hardware version: %d.%d.%d.%d",
        announce->hardwareVersion.major,
        announce->hardwareVersion.minor,
        announce->hardwareVersion.build,
        announce->hardwareVersion.revision
    );

    if(fw.empty()) initInput(announce);
    if (announce->vendorId==0x45e && announce->productId==0xb00) { auto v=announce->firmwareVersion; fw=std::to_string(v.major)+"."+std::to_string(v.minor)+"."+std::to_string(v.build)+"."+std::to_string(v.revision); }
}

void Controller::statusReceived(uint8_t id, const StatusData *status)
{
    const std::string levels[] = { "empty", "low", "medium", "full" };

    uint8_t type = status->batteryType;
    uint8_t level = status->batteryLevel;

    // Controller is charging or level hasn't changed
    if (type == BATT_TYPE_CHARGING || level == batteryLevel)
    {
        return;
    }

    Log::info("Battery level: %s", levels[level].c_str());

    batteryLevel = level;
}

void Controller::guideButtonPressed(const GuideButtonData *button)
{ guide=button->pressed;
}

void Controller::serialNumberReceived(const SerialData *serial)
{
    const std::string number(
        serial->serialNumber,
        sizeof(serial->serialNumber)
    );

    Log::info("Serial number: %s", number.c_str());
}

void Controller::inputReceived(const InputData *input)
{ live=*input; ++reports;
}

void Controller::initInput(const AnnounceData *announce)
{
    LedModeData ledMode = {};

    // Dim the LED a little bit, like the original driver
    // Brightness ranges from 0x00 to 0x20
    ledMode.mode = LED_ON;
    ledMode.brightness = 0x14;

    if (!setPowerMode(DEVICE_ID_CONTROLLER, POWER_ON))
    {
        Log::error("Failed to set initial power mode");

        return;
    }

    if (!setLedMode(ledMode))
    {
        Log::error("Failed to set initial LED mode");

        return;
    }

    if (!requestSerialNumber())
    {
        Log::error("Failed to request serial number");

        return;
    }


}

void Controller::processRumble()
{
    RumbleData rumble = {};
    std::unique_lock<std::mutex> lock(rumbleMutex);

    while (!stopRumbleThread)
    {
        rumbleCondition.wait(lock);

        while (rumbleBuffer.get(rumble))
        {
            performRumble(rumble);

            // Delay rumble to work around firmware bug
            std::this_thread::sleep_for(RUMBLE_DELAY);
        }
    }
}

void Controller::inputFeedbackReceived(
    uint16_t gain,
    ff_effect effect,
    uint8_t replayCount
) {
    // Ignore other types of force feedback
    if (effect.type != FF_RUMBLE)
    {
        return;
    }

    Log::debug(
        "Rumble count: %d, duration: %d, delay: %d",
        replayCount,
        effect.replay.length,
        effect.replay.delay
    );

    RumbleData rumble = {};

    rumble.setRight = true;
    rumble.setLeft = true;
    rumble.setRightTrigger = true;
    rumble.setLeftTrigger = true;

    if (replayCount == 0 || gain == 0)
    {
        rumbleBuffer.put(rumble);
        rumbleCondition.notify_one();

        return;
    }

    Log::debug(
        "Rumble strong: %d, weak: %d, direction: %d",
        effect.u.rumble.strong_magnitude,
        effect.u.rumble.weak_magnitude,
        effect.direction
    );

    // Apply force feedback gain
    uint16_t weak = static_cast<uint32_t>(
        effect.u.rumble.strong_magnitude
    ) * gain / 0xffff;
    uint16_t strong = static_cast<uint32_t>(
        effect.u.rumble.weak_magnitude
    ) * gain / 0xffff;

    // Map effect's magnitudes to rumble power
    rumble.left = weak * RUMBLE_MAX_POWER / 0xffff;
    rumble.right = strong * RUMBLE_MAX_POWER / 0xffff;

    // Upper half of the controller (from left to right)
    if (effect.direction >= 0x4000 && effect.direction <= 0xc000)
    {
        // Angle shifted by an eighth of a full circle
        float angle = static_cast<float>(effect.direction) / 0xffff - 0.125;
        float left = sin(2 * M_PI * angle);
        float right = cos(2 * M_PI * angle);
        uint8_t maxPower = rumble.left > rumble.right ?
            rumble.left :
            rumble.right;

        // Limit values to left and right areas
        left = left > 0 ? left : 0;
        right = right < 0 ? -right : 0;

        // The trigger motors are very strong
        rumble.leftTrigger = left * maxPower / 2;
        rumble.rightTrigger = right * maxPower / 2;
    }

    uint16_t duration = effect.replay.length / 10;
    uint16_t delay = effect.replay.delay / 10;

    // Use maximum duration if not specified or out of range
    if (duration == 0x00 || duration > 0xff)
    {
        duration = 0xff;
    }

    if (delay > 0xff)
    {
        delay = 0xff;
    }

    // Time in multiples of 10 ms
    rumble.duration = duration;
    rumble.delay = delay;
    rumble.repeat = replayCount - 1;

    rumbleBuffer.put(rumble);
    rumbleCondition.notify_one();
}
