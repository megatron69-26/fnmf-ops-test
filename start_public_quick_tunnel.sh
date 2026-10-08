#!/data/data/com.termux/files/usr/bin/sh
set -eu

APP_HOME=/data/data/com.termux/files/home
CLOUDFLARED="$APP_HOME/fnmf-cloudflared-arm64"
PROOT=/data/data/com.termux/files/usr/bin/proot
DNS_CONFIG=/data/data/com.termux/files/usr/etc/resolv.conf
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
PID_FILE="$APP_HOME/fnmf-public-quick-tunnel.pid"
LOG_FILE="$APP_HOME/fnmf-public-quick-tunnel.log"

if [ ! -x "$CLOUDFLARED" ]; then
    echo 'cloudflared binary missing' >&2
    exit 1
fi
if [ ! -x "$PROOT" ] || [ ! -r "$DNS_CONFIG" ] || [ ! -r "$SSL_CERT_FILE" ]; then
    echo 'Termux DNS/CA support missing' >&2
    exit 1
fi
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Quick Tunnel already running (PID $old_pid)"
        exit 0
    fi
fi

# This tunnel exposes only the allowlisted local gateway, never :8083 directly.
nohup "$PROOT" -b "$DNS_CONFIG:/etc/resolv.conf" "$CLOUDFLARED" tunnel --no-autoupdate --url http://127.0.0.1:8084 > "$LOG_FILE" 2>&1 < /dev/null &
tunnel_pid=$!
echo "$tunnel_pid" > "$PID_FILE"
sleep 2
if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    echo 'Quick Tunnel failed to start; inspect local log' >&2
    exit 1
fi
echo "Quick Tunnel process started (PID $tunnel_pid)"
