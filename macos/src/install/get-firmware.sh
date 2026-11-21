#!/bin/sh
# Downloads the official Xbox Wireless Adapter firmware from Microsoft's
# Windows driver package on Windows Update. The firmware is NOT
# redistributable (Microsoft Terms of Use), so it must be fetched at
# install time by the end user.
set -e

TARGET="${1:-firmware/xow_dongle.bin}"
URL='http://download.windowsupdate.com/c/msdownload/update/driver/drvs/2017/07/1cd6a87c-623f-4407-a52d-c31be49e925c_e19f60808bdcbfbd3c3df6be3e71ffc52e43261e.cab'
SHA256='48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66'

command -v cabextract > /dev/null || {
    echo 'cabextract is required: brew install cabextract' >&2
    exit 1
}

echo 'This script downloads the official Xbox Wireless Adapter firmware'
echo 'from Microsoft. By continuing you accept the Microsoft Terms of Use:'
echo 'https://www.microsoft.com/en-us/legal/terms-of-use'

TMPDIR_FW="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FW"' EXIT

curl -fsSL -o "$TMPDIR_FW/driver.cab" "$URL"
cabextract -q -F FW_ACC_00U.bin -d "$TMPDIR_FW" "$TMPDIR_FW/driver.cab"

echo "$SHA256  $TMPDIR_FW/FW_ACC_00U.bin" | shasum -a 256 -c - > /dev/null || {
    echo 'Firmware checksum mismatch, aborting' >&2
    exit 1
}

mkdir -p "$(dirname "$TARGET")"
mv "$TMPDIR_FW/FW_ACC_00U.bin" "$TARGET"
echo "Firmware installed at $TARGET"
