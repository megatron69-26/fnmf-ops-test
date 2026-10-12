#!/data/data/com.termux/files/usr/bin/sh
set -eu

APP_HOME=/data/data/com.termux/files/home
NODE=/data/data/com.termux/files/usr/bin/node
GATEWAY="$APP_HOME/fnmf_public_api_gateway.js"
PID_FILE="$APP_HOME/fnmf_public_api_gateway.pid"
LOG_FILE="$APP_HOME/fnmf_public_api_gateway.log"

if [ ! -r "$GATEWAY" ]; then
    echo 'Gateway script missing' >&2
    exit 1
fi
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Gateway already running (PID $old_pid)"
        exit 0
    fi
fi

FNMF_PUBLIC_REGISTRATION=true nohup "$NODE" "$GATEWAY" > "$LOG_FILE" 2>&1 < /dev/null &
gateway_pid=$!
echo "$gateway_pid" > "$PID_FILE"
sleep 1
if ! kill -0 "$gateway_pid" 2>/dev/null; then
    echo 'Gateway failed to start; inspect local log' >&2
    exit 1
fi
echo "Gateway started on 127.0.0.1:8084 (PID $gateway_pid)"
