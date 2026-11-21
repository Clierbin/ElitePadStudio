#!/system/bin/sh
# GPL-2.0-or-later. One receiver, bounded retries, no USB bus/port power changes.
set -u
export PATH=/system/bin:/vendor/bin
. /data/local/xbox-pi5/runtime-common.sh
umask 077
cd "$dir" || exit 1
exec 9>"$dir/supervisor.lock"
# Android mksh marks exec-opened FDs close-on-exec; explicitly pass it to flock.
flock -n 9 9>&9 || exit 0
printf '%s\n' "$$" > "$dir/supervisor.pid"
active_key=
attempts=0
next_try=0
healthy_since=0
started_at=0
announced=0
wireless_recovery_used=0
wireless_verified=0

monotime() { local t rest; read t rest < /proc/uptime; printf '%s\n' "${t%%.*}"; }
log() {
    if [ -f "$dir/supervisor.log" ] && [ "$(wc -c < "$dir/supervisor.log")" -gt 262144 ]; then
        mv -f "$dir/supervisor.log" "$dir/supervisor.log.1"
    fi
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$dir/supervisor.log"
}
state() {
    printf 'state=%s\nreceiver=%s\nattempts=%s\nworker_pid=%s\nsupervisor_pid=%s\n' \
      "$1" "$active_key" "$attempts" "$(worker_pid 2>/dev/null || true)" "$$" > "$dir/state.tmp"
    mv "$dir/state.tmp" "$dir/state"
}
receiver_key() {
    local d v p bus dev
    for d in /sys/bus/usb/devices/*; do
        [ -r "$d/idVendor" ] || continue
        read v < "$d/idVendor" || continue
        [ "$v" = 045e ] || continue
        read p < "$d/idProduct" || continue
        case "$p" in 02fe|02e6|091e) ;; *) continue;; esac
        read bus < "$d/busnum" || continue
        read dev < "$d/devnum" || continue
        printf '%s:%s:%s\n' "${d##*/}" "$bus" "$dev"
        return
    done
}
cleanup() {
    trap - EXIT
    log 'supervisor stopping'
    stop_worker
    state stopped
    [ "$(cat "$dir/supervisor.pid" 2>/dev/null)" != "$$" ] || rm -f "$dir/supervisor.pid"
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP
# Avoid Android tombstones growing after repeated initialization failures.
ulimit -c 0
stop_worker
log "supervisor started pid=$$ boot_id=$(cat /proc/sys/kernel/random/boot_id)"
state waiting_receiver
while :; do
    now=$(monotime)
    current_key=$(receiver_key)
    if [ "$current_key" != "$active_key" ]; then
        [ -z "$active_key" ] || log "receiver removed/re-enumerated old=$active_key new=$current_key"
        stop_worker
        active_key=$current_key
        attempts=0
        next_try=$((now + 2))
        healthy_since=0
        announced=0
        wireless_recovery_used=0
        wireless_verified=0
        if [ -z "$active_key" ]; then state waiting_receiver
        else log "receiver detected key=$active_key"; state settling; fi
    fi
    if [ -z "$active_key" ]; then sleep 1; continue; fi
    if p=$(worker_pid); then
        if grep -q "Controller '[0-9][0-9]*' connected" "$dir/xow.log"; then
            wireless_verified=1
        fi
        if [ "$announced" -eq 0 ]; then
            if grep -q 'Dongle initialized' "$dir/xow.log"; then
                announced=1
                healthy_since=$now
                state ready
                log "receiver ready worker_pid=$p key=$active_key"
            elif [ $((now - started_at)) -ge 30 ]; then
                log "initialization timeout worker_pid=$p"
                stop_worker
                state retry_wait
                next_try=$((now + 10))
            fi
        elif [ "$wireless_verified" -eq 0 ] &&
             [ "$wireless_recovery_used" -eq 0 ] &&
             [ $((now - healthy_since)) -ge 20 ]; then
            # An initialized radio can still fail to associate after power-on.
            # Retry once per physical insertion, only before its first connection.
            wireless_recovery_used=1
            log "no controller associated after 20s; one-time wireless reinitialization key=$active_key"
            stop_worker
            announced=0
            healthy_since=0
            next_try=$((now + 2))
            state retry_wait
        elif [ "$attempts" -ne 0 ] && [ $((now - healthy_since)) -ge 60 ]; then
            attempts=0
            state ready
        fi
        sleep 1
        continue
    fi
    if [ "$announced" -ne 0 ]; then
        log "worker exited unexpectedly key=$active_key"
        announced=0
        next_try=$((now + 3))
        state retry_wait
    fi
    if [ "$attempts" -ge 3 ]; then
        if [ "$attempts" -eq 3 ]; then
            log "initialization failed three times; waiting for receiver unplug/replug key=$active_key"
            attempts=4
            state waiting_replug
        fi
        sleep 2
        continue
    fi
    if [ "$now" -lt "$next_try" ]; then sleep 1; continue; fi
    attempts=$((attempts + 1))
    started_at=$now
    announced=0
    [ ! -f "$dir/xow.log.1" ] || mv -f "$dir/xow.log.1" "$dir/xow.log.2"
    [ ! -f "$dir/xow.log" ] || mv -f "$dir/xow.log" "$dir/xow.log.1"
    # Close the singleton lock FD in the worker, so a stuck worker cannot retain it.
    env LD_LIBRARY_PATH="$dir" XOW_COMPATIBILITY=1 XOW_FIRMWARE="$dir/xow_dongle.bin" \
      "$dir/xow" >"$dir/xow.log" 2>&1 </dev/null 9>&- &
    printf '%s\n' "$!" > "$dir/xow.pid"
    log "worker launched pid=$(cat "$dir/xow.pid") attempt=$attempts key=$active_key"
    state initializing
    next_try=$((now + 10))
    sleep 1
done
