#!/bin/bash
set -e
echo "=========================================================="
echo "   FNMF BACKEND HEALTH CHECK (STRICT ASSERTION)          "
echo "=========================================================="
echo "Date: $(date)"

ADB="adb.exe"

# 1. Assert device is connected
echo "[1/3] Kiểm tra kết nối Galaxy Note 10+ qua ADB..."
"$ADB" devices | grep -q "R3CM8105TPA" || {
    echo "LỖI: Galaxy Note 10+ (R3CM8105TPA) không phản hồi qua ADB!" >&2
    exit 1
}
echo "OK: Thiết bị đã kết nối."

# 2. Query Actuator health with strict assertion
echo "[2/3] Kiểm tra Spring Boot Actuator Health (127.0.0.1:8083)..."
HEALTH_JSON=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 5 http://127.0.0.1:8083/actuator/health" 2>/dev/null || true)
echo "Phản hồi Actuator: $HEALTH_JSON"

# Strict assertion
if echo "$HEALTH_JSON" | grep -q '"status":"UP"'; then
    echo "KIỂM CHỨNG ĐẠT: Backend báo status=UP."
else
    echo "KIỂM CHỨNG THẤT BẠI: Backend không trả về status=UP!" >&2
    exit 1
fi

# 3. Query stock catalog with strict asset verification
echo "[3/3] Kiểm tra API danh mục cổ phiếu (/api/stocks)..."
STOCKS_JSON=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 5 http://127.0.0.1:8083/api/stocks" 2>/dev/null || true)
echo "Phản hồi danh mục: $STOCKS_JSON"

MISSING_ASSETS=""
for ASSET in "BNBUSDT" "SOLUSDT" "XRPUSDT" "ADAUSDT" "DOGEUSDT"; do
    if ! echo "$STOCKS_JSON" | grep -q "\"$ASSET\""; then
        MISSING_ASSETS="$MISSING_ASSETS $ASSET"
    fi
done

if [ -n "$MISSING_ASSETS" ]; then
    echo "KIỂM CHỨNG THẤT BẠI: Thiếu các mã tài sản trong danh mục:$MISSING_ASSETS" >&2
    exit 1
fi
echo "KIỂM CHỨNG ĐẠT: Xác nhận đầy đủ 5/5 tài sản Binance (BNBUSDT, SOLUSDT, XRPUSDT, ADAUSDT, DOGEUSDT)."

echo "=========================================================="
echo "          TẤT CẢ KIỂM TRA ĐẠT TIÊU CHUẨN (HEALTHY)        "
echo "=========================================================="
