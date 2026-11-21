#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash macos/build.sh
out="dist/ElitePadStudio.app/Contents"; mkdir -p "$out/MacOS" "$out/Resources/bin" build/mac
cp macos/Window.swift build/mac/main.swift
swiftc -swift-version 5 build/mac/main.swift macos/{Advanced,Style,Pad}.swift -o "$out/MacOS/EliteWindow"
cp macos/bin/{elite-radio,libusb.dylib} "$out/Resources/bin/"
cp macos/{editor,window_rpc,advanced,live_light}.py macos/artwork/ElitePad.icns "$out/Resources/"
: "${XBOX_FIRMWARE:?Supply your own FW_ACC_00U.bin}"
test "$(shasum -a 256 "$XBOX_FIRMWARE"|cut -d' ' -f1)" = 48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66
cp "$XBOX_FIRMWARE" "$out/Resources/firmware.bin"
cp macos/Info.plist "$out/"
codesign --force --deep --sign - "${out%/Contents}"
