#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

NGROK=/data/data/com.termux/files/usr/bin/ngrok
CURL=/data/data/com.termux/files/usr/bin/curl
CONFIG=/data/user/0/com.termux/.config/ngrok/ngrok.yml
DOMAIN=trading-concave-await.ngrok-free.dev
GATEWAY=http://127.0.0.1:8084

if [ ! -x "$NGROK" ] || [ ! -r "$CONFIG" ]; then
    echo 'ngrok agent or local authtoken configuration is missing.' >&2
    exit 1
fi

if ! "$CURL" -fsS --max-time 5 "$GATEWAY/actuator/health" >/dev/null; then
    echo 'Gateway/backend health check failed; refusing to publish a dead endpoint.' >&2
    exit 1
fi

# Only the allowlisted gateway is exposed. No Qwen, PostgreSQL or backend port.
exec "$NGROK" http 127.0.0.1:8084 --url "https://$DOMAIN" --config "$CONFIG"
