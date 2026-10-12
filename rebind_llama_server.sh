#!/bin/bash
set -euo pipefail

if [ "${FNMF_ALLOW_LEGACY_LLAMA_HTTP:-false}" != "true" ]; then
    echo 'Disabled: scheduled Qwen CLI mode must not expose llama-server HTTP port 8080.' >&2
    exit 1
fi

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"
TERMUX_BASH="/data/data/com.termux/files/usr/bin/bash"

echo "=== 1. KIỂM TRA TIẾN TRÌNH LLAMA-SERVER HIỆN TẠI ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ps -ef | grep llama-server | grep -v grep" || true

echo "=== 2. TẠO SCRIPT QUẢN LÝ START_QWEN.SH BIND CHẶT 127.0.0.1 ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux $TERMUX_BASH -c '
cat << \"EOF\" > /data/data/com.termux/files/home/start_qwen.sh
#!/data/data/com.termux/files/usr/bin/bash
PID_FILE=/data/data/com.termux/files/home/qwen.pid
LOG_FILE=/data/data/com.termux/files/home/qwen_server.log
MODEL_PATH=/data/data/com.termux/files/home/models/qwen2.5-1.5b-instruct-q4_k_m.gguf

if [ -f \"\$PID_FILE\" ]; then
    OLD_PID=\$(cat \"\$PID_FILE\" 2>/dev/null || true)
    if [ -n \"\$OLD_PID\" ] && kill -0 \"\$OLD_PID\" 2>/dev/null; then
        echo \"Dừng Qwen PID \$OLD_PID...\"
        kill -15 \"\$OLD_PID\" 2>/dev/null || true
        sleep 2
        kill -9 \"\$OLD_PID\" 2>/dev/null || true
    fi
    rm -f \"\$PID_FILE\"
fi

pkill -9 -f llama-server 2>/dev/null || true
sleep 1

echo \"Khởi chạy llama-server bind 127.0.0.1:8080 (cô lập loopback)...\"
nohup /data/data/com.termux/files/usr/bin/llama-server \
  -m \"\$MODEL_PATH\" \
  --host 127.0.0.1 \
  --port 8080 \
  -c 4096 \
  -t 6 > \"\$LOG_FILE\" 2>&1 &

NEW_PID=\$!
echo \$NEW_PID > \"\$PID_FILE\"
echo \"Qwen llama-server started with PID \$NEW_PID on 127.0.0.1:8080\"
EOF
chmod +x /data/data/com.termux/files/home/start_qwen.sh
'"

echo "=== 3. THỰC THI KHỞI ĐỘNG LẠI QWEN BIND 127.0.0.1 ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/home/start_qwen.sh"

echo "=== 4. CHỜ VÀ XÁC MINH SỨC KHỎE QWEN (LOOPBACK) ==="
MAX_WAIT=20
WAIT_COUNT=0
IS_READY=false
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    HEALTH=$("$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 2 http://127.0.0.1:8080/health" 2>/dev/null || true)
    if echo "$HEALTH" | grep -q '"status":"ok"'; then
        IS_READY=true
        echo "Qwen đã sẵn sàng trên 127.0.0.1:8080 sau ${WAIT_COUNT}s: $HEALTH"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ "$IS_READY" != "true" ]; then
    echo "LỖI: Qwen không khởi động thành công sau ${MAX_WAIT}s!" >&2
    exit 1
fi

echo "=== 5. KIỂM TRA CMDLINE VÀ TIẾN TRÌNH ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ps -ef | grep llama-server | grep -v grep"

echo "=== 6. LẤY IP LAN CỦA NOTE 10+ VÀ KIỂM TRA CHẶN TỪ LAN ==="
PHONE_IP=$("$ADB" -s "$DEVICE" shell "ip -f inet addr show wlan0 2>/dev/null" | awk '/inet / {print $2}' | cut -d/ -f1 | tr -d '\r\n ' || true)
echo "IP LAN của Note 10+ (wlan0): '$PHONE_IP'"

if [ -n "$PHONE_IP" ]; then
    echo "Thử nghiệm kết nối từ laptop tới http://$PHONE_IP:8080/health (kỳ vọng: THẤT BẠI/BỊ TỪ CHỐI):"
    set +e
    curl -s -m 3 "http://$PHONE_IP:8080/health"
    CURL_EXIT=$?
    set -e
    if [ $CURL_EXIT -ne 0 ]; then
        echo "XÁC NHẬN AN TOÀN: Kết nối từ LAN tới http://$PHONE_IP:8080 bị từ chối / timeout (Exit code: $CURL_EXIT)!"
    else
        echo "CẢNH BÁO NGUY HIỂM: http://$PHONE_IP:8080 vẫn có thể truy cập được từ LAN!" >&2
        exit 1
    fi
else
    echo "Thiết bị không kết nối Wi-Fi (wlan0 không có IP). Không có nguy cơ mở cổng LAN."
fi
