#!/system/bin/sh
# GPL-2.0-or-later. Shared by the Android runtime scripts.
dir=/data/local/xbox-pi5

worker_pid() {
    local p
    [ -r "$dir/xow.pid" ] || return 1
    p=$(cat "$dir/xow.pid")
    case "$p" in ''|*[!0-9]*) return 1;; esac
    [ "$(readlink "/proc/$p/exe" 2>/dev/null)" = "$dir/xow" ] || return 1
    printf '%s\n' "$p"
}

supervisor_pid() {
    local p
    [ -r "$dir/supervisor.pid" ] || return 1
    p=$(cat "$dir/supervisor.pid")
    case "$p" in ''|*[!0-9]*) return 1;; esac
    [ "$(readlink "/proc/$p/exe" 2>/dev/null)" = /system/bin/sh ] || return 1
    tr '\000' '\n' < "/proc/$p/cmdline" 2>/dev/null | grep -Fxq "$dir/supervisor.sh" || return 1
    printf '%s\n' "$p"
}

stop_worker() {
    local p i
    p=$(worker_pid) || { rm -f "$dir/xow.pid"; return 0; }
    kill -TERM "$p" 2>/dev/null || true
    for i in 1 2 3 4 5; do
        [ "$(worker_pid 2>/dev/null)" = "$p" ] || break
        sleep 1
    done
    # Only the verified executable from our own directory may be forced down.
    if [ "$(worker_pid 2>/dev/null)" = "$p" ]; then kill -KILL "$p" 2>/dev/null || true; fi
    rm -f "$dir/xow.pid"
}
