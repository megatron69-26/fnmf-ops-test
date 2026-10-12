#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_HOME=/data/data/com.termux/files/home
START_SCRIPT="$APP_HOME/start_public_ngrok.sh"
PID_FILE="$APP_HOME/fnmf_public_ngrok.pid"
LOG_FILE="$APP_HOME/fnmf_public_ngrok.log"

if [ ! -x "$START_SCRIPT" ]; then
    echo 'ngrok starter missing or not executable' >&2
    exit 1
fi

if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "ngrok already running (PID $old_pid)"
        exit 0
    fi
fi

nohup "$START_SCRIPT" > "$LOG_FILE" 2>&1 < /dev/null &
new_pid=$!
echo "$new_pid" > "$PID_FILE"
sleep 3
if ! kill -0 "$new_pid" 2>/dev/null; then
    echo 'ngrok failed to start; inspect local log' >&2
    exit 1
fi
echo "ngrok started (PID $new_pid)"
