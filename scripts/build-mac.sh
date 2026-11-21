#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
bash macos/build.sh
out="dist/ElitePadStudio.app/Contents"; mkdir -p "$out/MacOS" "$out/Resources/bin" build/mac
cp macos/Window.swift build/mac/main.swift
swiftc -target "$(uname -m)-apple-macosx${MACOSX_DEPLOYMENT_TARGET}" -swift-version 5 build/mac/main.swift macos/{Advanced,Style,Pad}.swift -o "$out/MacOS/EliteWindow"
cp macos/bin/{elite-radio,libusb.dylib} "$out/Resources/bin/"
cp macos/{editor,window_rpc,advanced,live_light}.py macos/artwork/ElitePad.icns "$out/Resources/"
rm -f "$out/Resources/firmware.bin"
if [[ -n "${XBOX_FIRMWARE:-}" ]]; then
  test "$(shasum -a 256 "$XBOX_FIRMWARE"|cut -d' ' -f1)" = 48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66
  cp "$XBOX_FIRMWARE" "$out/Resources/firmware.bin"
fi
cp macos/Info.plist "$out/"
codesign --force --deep --sign - "${out%/Contents}"
