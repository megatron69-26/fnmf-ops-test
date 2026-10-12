#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ "${FNMF_ALLOW_LEGACY_LLAMA_HTTP:-false}" != "true" ]; then
    echo 'Disabled: scheduled Qwen CLI mode must not expose llama-server HTTP port 8080.' >&2
    exit 1
fi

APP_HOME=/data/data/com.termux/files/home
LLAMA=/data/data/com.termux/files/usr/bin/llama-server
CURL=/data/data/com.termux/files/usr/bin/curl
SHA256SUM=/data/data/com.termux/files/usr/bin/sha256sum
NEW_MODEL="$APP_HOME/models/Qwen3.5-4B-Q4_K_M.gguf"
OLD_MODEL="$APP_HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
PID_FILE="$APP_HOME/qwen.pid"
LOG_FILE="$APP_HOME/qwen_server.log"
EXPECTED_SHA=00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4

if [ ! -r "$NEW_MODEL" ] || [ ! -r "$OLD_MODEL" ]; then
    echo 'Missing new model or rollback model' >&2
    exit 1
fi
ACTUAL_SHA=$($SHA256SUM "$NEW_MODEL")
if [ "${ACTUAL_SHA%% *}" != "$EXPECTED_SHA" ]; then
    echo 'New model SHA-256 mismatch; refusing to switch' >&2
    exit 1
fi

health_ok() {
    "$CURL" -fsS -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"status":"ok"'
}

wait_for_health() {
    local pid=$1
    local attempt
    for attempt in $(seq 1 45); do
        if health_ok; then return 0; fi
        if ! kill -0 "$pid" 2>/dev/null; then return 1; fi
        sleep 2
    done
    return 1
}

start_model() {
    local model=$1
    local alias=$2
    local threads=$3
    nohup "$LLAMA" -m "$model" --alias "$alias" --host 127.0.0.1 --port 8080 \
        -c 4096 -t "$threads" -np 1 --reasoning off > "$LOG_FILE" 2>&1 < /dev/null &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    if wait_for_health "$pid"; then
        echo "Model online at 127.0.0.1:8080 (PID $pid, alias $alias)"
        return 0
    fi
    kill -15 "$pid" 2>/dev/null || true
    for attempt in $(seq 1 30); do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo 'Failed model did not stop; manual intervention required' >&2
        exit 1
    fi
    echo "Model failed to become healthy (PID $pid)" >&2
    return 1
}

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        CMDLINE=$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline")
        case "$CMDLINE" in
            *llama-server*--port\ 8080*) ;;
            *) echo "PID file points to another process: $OLD_PID" >&2; exit 1 ;;
        esac
        kill -15 "$OLD_PID"
        for attempt in $(seq 1 30); do
            if ! kill -0 "$OLD_PID" 2>/dev/null; then break; fi
            sleep 1
        done
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo 'Old model did not stop cleanly; refusing to replace it' >&2
            exit 1
        fi
    fi
fi

if health_ok; then
    echo 'Port 8080 already has an unmanaged healthy server; refusing to replace it' >&2
    exit 1
fi

if start_model "$NEW_MODEL" qwen3.5-4b 6; then
    exit 0
fi

echo 'Rolling back to Qwen2.5-1.5B' >&2
start_model "$OLD_MODEL" qwen2.5-1.5b-instruct 6
exit 1
