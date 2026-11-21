#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
build_tools="$sdk/build-tools/34.0.0"
android="$sdk/platforms/android-34/android.jar"
jdk="$(/usr/libexec/java_home -v 11)"
mkdir -p build/classes build/dex
"$build_tools/aapt2" compile --dir res -o build/resources.zip
"$build_tools/aapt2" link --manifest AndroidManifest.xml -A assets -I "$android" \
    -o build/base.apk build/resources.zip
"$jdk/bin/javac" -source 8 -target 8 -encoding UTF-8 \
    -bootclasspath "$android:$build_tools/core-lambda-stubs.jar" \
    -d build/classes src/local/pi5/elite/*.java
"$jdk/bin/jar" cf build/classes.jar -C build/classes .
"$jdk/bin/java" -cp "$build_tools/lib/d8.jar" com.android.tools.r8.D8 \
    --min-api 28 --lib "$android" --output build/dex build/classes.jar
(cd build/dex && /usr/bin/zip -q -0 ../base.apk classes.dex)
"$build_tools/zipalign" -f 4 build/base.apk build/aligned.apk
"$build_tools/apksigner" sign --ks "$HOME/.android/debug.keystore" \
    --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android \
    --out build/elite-profiles.apk build/aligned.apk
"$build_tools/apksigner" verify --verbose build/elite-profiles.apk
