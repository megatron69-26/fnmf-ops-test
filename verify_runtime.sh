#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== 1. KIỂM TRA ACTUATOR HEALTH ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8083/actuator/health"
echo ""

echo "=== 2. KIỂM TRA API DANH MỤC TÀI SẢN (/api/stocks) ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8083/api/stocks"
echo ""

echo "=== 3. ĐỐI SOÁT HASH SHA-256 JAR TRÊN ĐIỆN THOẠI VÀ ARTIFACT ==="
PHONE_HASH=$("$ADB" -s "$DEVICE" shell "run-as com.termux sha256sum /data/data/com.termux/files/home/llm-gateway-1.1.17.jar" | awk '{print $1}' | tr -d '\r\n ')
ARTIFACT_HASH=$(cut -d' ' -f1 /c/Users/khoid/Projects/artifacts/backend/fnmf-backend-test-6a14681_20261004_035651.jar.sha256 | tr -d '\r\n ')
echo "Hash trên Note 10+: $PHONE_HASH"
echo "Hash của Artifact : $ARTIFACT_HASH"
if [ "$PHONE_HASH" = "$ARTIFACT_HASH" ]; then
    echo "XÁC NHẬN: Mã băm SHA-256 khớp tuyệt đối 100%!"
else
    echo "LỖI: Mã băm không khớp!" >&2
    exit 1
fi

echo "=== 4. THÔNG TIN TIẾN TRÌNH JAVA VÀ PID ==="
PID=$("$ADB" -s "$DEVICE" shell "run-as com.termux cat /data/data/com.termux/files/home/backend.pid" | tr -d '\r\n ')
echo "PID hiện tại: $PID"
"$ADB" -s "$DEVICE" shell "run-as com.termux ps -ef | grep $PID | grep -v grep" || true

echo "=== 5. XÁC MINH BIND LOOPBACK (127.0.0.1) TRÊN NOTE 10+ ==="
# Check Java cmdline arguments for explicit loopback bind
echo "Dòng lệnh tiến trình Java (kiểm tra server.address):"
"$ADB" -s "$DEVICE" shell "run-as com.termux tr '\0' ' ' < /proc/$PID/cmdline"
echo ""

# Check PostgreSQL postgresql.conf listen_addresses
echo "Cấu hình listen_addresses của PostgreSQL:"
"$ADB" -s "$DEVICE" shell "run-as com.termux grep -E 'listen_addresses' /data/data/com.termux/files/home/pgdata/postgresql.conf 2>/dev/null" || true

# Test curl connection from external vs loopback
echo "Thử nghiệm kết nối curl tới 127.0.0.1:8083:"
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -o /dev/null -w 'HTTP Code: %{http_code}\n' http://127.0.0.1:8083/actuator/health"

# Test netstat if installed
echo "Kiểm tra netstat Termux:"
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/netstat -tuln 2>/dev/null" || true

echo "=== 6. KIỂM TRA KHÔNG CÓ TUNNEL ĐANG MỞ ==="
echo "Kiểm tra port forwards trên laptop:"
"$ADB" forward --list

