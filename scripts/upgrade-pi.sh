#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_SERIAL:?Set ANDROID_SERIAL to your Pi adb transport}"
a(){ "${ADB:-adb}" -s "$ANDROID_SERIAL" "$@"; }
[[ "$(a shell getprop ro.product.device | tr -d '\r')" == rpi5 ]]
[[ "$(a shell id -u | tr -d '\r')" == 0 ]] || { echo 'Reconnect with adb root on your own Pi first.' >&2; exit 1; }
old=310a11c6a8dc9177698ac6eb447b4ffb23c07d7b43b29363e0dbbe553a5af8a5
dir=/data/local/xbox-pi5
backup=xow.before-wireless-profiles
if [[ "${1:-upgrade}" == rollback ]]; then
 a shell "set -eu; cd $dir; test \"\$(sha256sum $backup|cut -d' ' -f1)\" = $old; cp -p $backup xow.next; sh control.sh stop; mv xow.next xow; sh control.sh start";exit
fi
[[ "${1:-upgrade}" == upgrade ]]
a shell "set -eu; cd $dir; test -f /vendor/etc/init/xbox-pi5.rc; test -s xow_dongle.bin; if [ ! -e $backup ]; then test \"\$(sha256sum xow|cut -d' ' -f1)\" = $old; cp -p xow $backup; fi; test \"\$(sha256sum $backup|cut -d' ' -f1)\" = $old"
a install -r dist/elite-profiles.apk
a push dist/xow "$dir/xow.next"
digest=$(shasum -a 256 dist/xow | cut -d' ' -f1)
a shell "set -eu; cd $dir; test \"\$(sha256sum xow.next|cut -d' ' -f1)\" = $digest; chmod 700 xow.next; sh control.sh stop; mv xow.next xow; sh control.sh start"
