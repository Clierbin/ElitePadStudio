#!/bin/bash
set -eu
cd "$(dirname "$0")"
S=../pi/native/vendor/libusb
mkdir -p bin .build/libusb-1.0
cp "$S/libusb/libusb.h" .build/libusb-1.0/
clang -dynamiclib -install_name @loader_path/libusb.dylib -I"$S/Xcode" -I"$S/libusb" "$S"/libusb/*.c "$S"/libusb/os/{darwin_usb,events_posix,threads_posix}.c -framework IOKit -framework CoreFoundation -framework Security -o bin/libusb.dylib
clang++ -std=c++17 -O2 -I.build -DVERSION='"mac-elite-1"' -DFIRMWARE='"firmware.bin"' src/main.cpp src/{controller,dongle,utils}/*.cpp bin/libusb.dylib -o bin/elite-radio
