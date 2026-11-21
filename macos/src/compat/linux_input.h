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
 * Minimal subset of <linux/input.h> / <linux/uinput.h> used by the
 * controller layer, so the GIP -> input mapping code from xow compiles
 * unchanged on macOS. Values match the Linux input event codes.
 */

#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_ABS 0x03

#define SYN_REPORT 0

#define BTN_A 0x130
#define BTN_B 0x131
#define BTN_X 0x133
#define BTN_Y 0x134
#define BTN_TL 0x136
#define BTN_TR 0x137
#define BTN_SELECT 0x13a
#define BTN_START 0x13b
#define BTN_MODE 0x13c
#define BTN_THUMBL 0x13d
#define BTN_THUMBR 0x13e

#define ABS_X 0x00
#define ABS_Y 0x01
#define ABS_Z 0x02
#define ABS_RX 0x03
#define ABS_RY 0x04
#define ABS_RZ 0x05
#define ABS_HAT0X 0x10
#define ABS_HAT0Y 0x11

#define FF_RUMBLE 0x50

struct ff_replay
{
    uint16_t length;
    uint16_t delay;
};

struct ff_trigger
{
    uint16_t button;
    uint16_t interval;
};

struct ff_rumble_effect
{
    uint16_t strong_magnitude;
    uint16_t weak_magnitude;
};

struct ff_effect
{
    uint16_t type;
    int16_t id;
    uint16_t direction;
    ff_trigger trigger;
    ff_replay replay;

    union
    {
        ff_rumble_effect rumble;
    } u;
};
