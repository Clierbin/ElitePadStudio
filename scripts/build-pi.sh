#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT to Android NDK r27d}"
bash android/build.sh
cmake -S pi/native -B build/pi -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release
cmake --build build/pi --parallel
mkdir -p dist
stripper=$(find "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt" -name llvm-strip | head -1)
"$stripper" -o dist/xow build/pi/xow
cp android/build/elite-profiles.apk dist/
