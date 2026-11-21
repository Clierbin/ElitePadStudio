#!/system/bin/sh
set -eu
. /data/local/xbox-pi5/runtime-common.sh
case "${1:-status}" in
  start)
    if p=$(supervisor_pid); then printf 'supervisor already running pid=%s\n' "$p"; exit 0; fi
    if [ -n "$(getprop init.svc.xbox_pi5)" ]; then
      setprop ctl.start xbox_pi5
      printf 'Android init service start requested\n'
    else
      if [ -f "$dir/supervisor.log" ] && [ "$(wc -c < "$dir/supervisor.log")" -gt 262144 ]; then
        mv -f "$dir/supervisor.log" "$dir/supervisor.log.1"
      fi
      nohup /system/bin/sh "$dir/supervisor.sh" >>"$dir/supervisor.log" 2>&1 </dev/null &
      printf 'manual supervisor start requested pid=%s\n' "$!"
    fi
    ;;
  stop)
    [ -z "$(getprop init.svc.xbox_pi5)" ] || setprop ctl.stop xbox_pi5
    if p=$(supervisor_pid); then
      kill -TERM "$p" 2>/dev/null || true
      for i in 1 2 3 4 5 6 7 8; do
        [ "$(supervisor_pid 2>/dev/null)" = "$p" ] || break
        sleep 1
      done
      if [ "$(supervisor_pid 2>/dev/null)" = "$p" ]; then kill -KILL "$p" 2>/dev/null || true; fi
    fi
    stop_worker
    printf 'supervisor and worker stopped\n'
    ;;
  pair)
    p=$(worker_pid) || { printf 'worker is not running\n' >&2; exit 1; }
    grep -q 'Dongle initialized' "$dir/xow.log" || { printf 'dongle not initialized\n' >&2; exit 1; }
    kill -USR1 "$p"
    printf 'pairing requested\n'
    ;;
  enable)
    [ -f /vendor/etc/init/xbox-pi5.rc ] || { printf 'install the reviewed init configuration first\n' >&2; exit 1; }
    setprop persist.vendor.xbox_pi5.enabled 1
    printf 'autostart enabled; init config is loaded on reboot\n'
    ;;
  disable)
    setprop persist.vendor.xbox_pi5.enabled 0
    sh "$dir/control.sh" stop
    printf 'autostart disabled\n'
    ;;
  status)
    printf 'autostart=%s init_service=%s\n' "$(getprop persist.vendor.xbox_pi5.enabled)" "$(getprop init.svc.xbox_pi5)"
    if p=$(supervisor_pid); then printf 'supervisor running pid=%s\n' "$p"; else printf 'supervisor not running\n'; fi
    if p=$(worker_pid); then printf 'worker running pid=%s\n' "$p"; else printf 'worker not running\n'; fi
    [ ! -f "$dir/state" ] || cat "$dir/state"
    [ ! -f "$dir/xow.log" ] || tail -n 20 "$dir/xow.log"
    ;;
  *) printf 'usage: control.sh start|stop|pair|status|enable|disable\n' >&2; exit 2 ;;
esac
