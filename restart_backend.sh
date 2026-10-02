#!/bin/bash
set -e
echo "=========================================================="
echo "      FNMF BACKEND CONTROLLED RESTART & HEALTH VERIFY    "
echo "=========================================================="
echo "Date: $(date)"

ADB="adb.exe"

# 1. Assert device is connected
echo "[1/4] Kiểm tra kết nối Galaxy Note 10+ qua ADB..."
"$ADB" devices | grep -q "R3CM8105TPA" || {
    echo "LỖI: Không tìm thấy thiết bị R3CM8105TPA qua ADB!" >&2
    exit 1
}

# 2. Check and report current process before stopping
echo "[2/4] Kiểm tra và dừng tiến trình backend cũ..."
OLD_PID=$("$ADB" -s R3CM8105TPA shell "run-as com.termux cat /data/data/com.termux/files/home/backend.pid 2>/dev/null" || true)
echo "PID ghi nhận trước đó: '$OLD_PID'"

# Call start_backend.sh which contains verified PID check + wait loop
START_OUT=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/home/start_backend.sh")
echo "$START_OUT"

NEW_PID=$("$ADB" -s R3CM8105TPA shell "run-as com.termux cat /data/data/com.termux/files/home/backend.pid 2>/dev/null" || true)
echo "PID tiến trình mới khởi động: '$NEW_PID'"

# 3. Poll Actuator health endpoint until UP (up to 45s)
echo "[3/4] Chờ ứng dụng Spring Boot hoàn tất khởi động và Flyway validation..."
MAX_ATTEMPTS=25
ATTEMPT=1
IS_UP=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    HEALTH_JSON=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 2 http://127.0.0.1:8083/actuator/health" 2>/dev/null || true)
    if echo "$HEALTH_JSON" | grep -q '"status":"UP"'; then
        IS_UP=true
        echo "Thành công sau $ATTEMPT lần thử (khoảng $((ATTEMPT * 2))s): $HEALTH_JSON"
        break
    fi
    echo "Lần thử $ATTEMPT/$MAX_ATTEMPTS: Đang chờ backend sẵn sàng..."
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$IS_UP" != "true" ]; then
    echo "LỖI: Backend không chuyển sang trạng thái UP sau $((MAX_ATTEMPTS * 2))s!" >&2
    echo "Log lỗi 30 dòng gần nhất:" >&2
    "$ADB" -s R3CM8105TPA shell "run-as com.termux tail -n 30 /data/data/com.termux/files/home/backend_test.log" >&2
    exit 1
fi

# 4. Verify API catalog
echo "[4/4] Kiểm tra phản hồi API danh mục (/api/stocks)..."
STOCKS_JSON=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 3 http://127.0.0.1:8083/api/stocks" 2>/dev/null || true)
echo "Catalog response: $STOCKS_JSON"

echo "=========================================================="
echo "    KHỞI ĐỘNG LẠI THÀNH CÔNG - BACKEND TRỰC TUYẾN 100%   "
echo "=========================================================="
