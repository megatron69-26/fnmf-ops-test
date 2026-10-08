#!/data/data/com.termux/files/usr/bin/sh
set -eu

PID_FILE=/data/data/com.termux/files/home/fnmf-public-quick-tunnel.pid
if [ ! -f "$PID_FILE" ]; then
    echo 'No FNMF Quick Tunnel PID file'
    exit 0
fi
parent_pid=$(cat "$PID_FILE")
case "$parent_pid" in ''|*[!0-9]*) echo 'Invalid PID file' >&2; exit 1;; esac

parent_args=$(/system/bin/ps -A -o PID,ARGS | awk -v p="$parent_pid" '$1 == p { $1=""; print }')
case "$parent_args" in
    *fnmf-cloudflared-arm64*'--url http://127.0.0.1:8084'*) ;;
    *) echo 'PID no longer belongs to the FNMF tunnel; refusing to kill it' >&2; exit 1;;
esac

child_pid=$(/system/bin/ps -A -o PID,PPID,ARGS | awk -v p="$parent_pid" '$2 == p && $3 == "fnmf-cloudflared-arm64" { print $1 }')
if [ -n "$child_pid" ]; then
    kill -15 "$child_pid"
fi
kill -15 "$parent_pid" 2>/dev/null || :
echo 'FNMF Quick Tunnel stop requested'
