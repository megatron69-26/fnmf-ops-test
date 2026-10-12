#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

NGROK=/data/data/com.termux/files/usr/bin/ngrok
CHROOT=/data/data/com.termux/files/usr/bin/termux-chroot
CURL=/data/data/com.termux/files/usr/bin/curl
CONFIG=/data/user/0/com.termux/.config/ngrok/ngrok.yml
DNS_CONFIG=/data/data/com.termux/files/home/ngrok_dns.yml
DOMAIN=trading-concave-await.ngrok-free.dev
GATEWAY=http://127.0.0.1:8084

if [ ! -x "$NGROK" ] || [ ! -x "$CHROOT" ] || [ ! -r "$CONFIG" ] || [ ! -r "$DNS_CONFIG" ]; then
    echo 'ngrok agent or local authtoken configuration is missing.' >&2
    exit 1
fi

if ! "$CURL" -fsS --max-time 5 "$GATEWAY/actuator/health" >/dev/null; then
    echo 'Gateway/backend health check failed; refusing to publish a dead endpoint.' >&2
    exit 1
fi

# Only the allowlisted gateway is exposed. No Qwen, PostgreSQL or backend port.
# The stock Linux ngrok binary expects /etc/resolv.conf. Termux-chroot binds
# Termux's resolver file there without exposing additional services.
exec "$CHROOT" "$NGROK" http 127.0.0.1:8084 --url "https://$DOMAIN" --config "$CONFIG" --config "$DNS_CONFIG" --log stdout --log-level info
