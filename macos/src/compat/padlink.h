/*
 * xow-mac - Xbox Wireless Adapter driver for macOS
 * Copyright (C) 2026
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

#include <cstdint>

/*
 * Wire protocol between the xow-mac daemon (C++) and xowmac-padhost
 * (Swift/CoreHID), over a unix domain socket. The padhost owns the
 * virtual HID gamepads; the daemon owns the wireless dongle.
 *
 * All fields little endian. Fixed 20-byte messages.
 */

#define PADLINK_SOCKET "/tmp/xowmac-padhost.sock"

#define PADLINK_CREATE 1
#define PADLINK_DESTROY 2
#define PADLINK_INPUT 3

/* Button bit indices (Xbox One S bluetooth HID order, matches SDL) */
#define PADLINK_BTN_A 0
#define PADLINK_BTN_B 1
#define PADLINK_BTN_X 2
#define PADLINK_BTN_Y 3
#define PADLINK_BTN_LB 4
#define PADLINK_BTN_RB 5
#define PADLINK_BTN_LS 6
#define PADLINK_BTN_RS 7
#define PADLINK_BTN_MENU 8
#define PADLINK_BTN_VIEW 9
#define PADLINK_BTN_GUIDE 10
#define PADLINK_BTN_DPAD_UP 11
#define PADLINK_BTN_DPAD_DOWN 12
#define PADLINK_BTN_DPAD_LEFT 13
#define PADLINK_BTN_DPAD_RIGHT 14

#pragma pack(push, 1)
struct PadLinkMessage
{
    uint8_t type;
    uint8_t pad;
    uint16_t buttons;
    int16_t stickLeftX, stickLeftY;
    int16_t stickRightX, stickRightY;
    uint16_t triggerLeft, triggerRight; // 0..1023
    uint8_t hat; // 0 = neutral, 1..8 = N, NE, E, SE, S, SW, W, NW
    uint8_t reserved[3];
};
#pragma pack(pop)

static_assert(sizeof(PadLinkMessage) == 20, "PadLinkMessage must be 20 bytes");
