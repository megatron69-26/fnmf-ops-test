#!/bin/bash
set -e
echo "================================================================================"
echo "    FNMF BACKEND TEST LOG VIEWER (BEST-EFFORT MASKED DEFENSE-IN-DEPTH)         "
echo "================================================================================"
echo "Date: $(date)"
echo "Tệp nguồn: /data/data/com.termux/files/home/backend_test.log"
echo ""
echo "CẢNH BÁO BẢO MẬT & GIỚI HẠN KỸ THUẬT:"
echo "Trình xem log áp dụng regex tự động để che các mẫu nhạy cảm (JWT, mật khẩu, key)."
echo "Do regex là giải pháp lọc văn bản tốt nhất có thể (best-effort), nó KHÔNG THỂ"
echo "đảm bảo toán học 100% việc che mọi bí mật bất quy tắc xuất hiện trong tương lai."
echo "Khuyến cáo: Luôn giữ Semaphore trên localhost và không xuất log này ra công khai."
echo "================================================================================"
echo ""

ADB="adb.exe"

# Pull last 70 lines from phone
RAW_LOG=$("$ADB" -s R3CM8105TPA shell "run-as com.termux tail -n 70 /data/data/com.termux/files/home/backend_test.log" 2>/dev/null || true)

# Apply thorough multi-layer redaction filters
echo "$RAW_LOG" | sed -E \
  -e 's/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/[REDACTED_JWT_TOKEN]/g' \
  -e 's/([aA]uthorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED_TOKEN]/g' \
  -e 's/([pP]assword[:=][[:space:]]*)[^& ,;"]+/\1[REDACTED]/g' \
  -e 's/"password"[[:space:]]*:[[:space:]]*"[^"]+"/"password":"[REDACTED]"/g' \
  -e 's/TEST_DATASOURCE_PASSWORD=[^& ,;]*/TEST_DATASOURCE_PASSWORD=[REDACTED]/g' \
  -e 's/TEST_JWT_SECRET=[^& ,;]*/TEST_JWT_SECRET=[REDACTED]/g' \
  -e 's/(jwt\.secret[[:space:]]*=[[:space:]]*)[^& ,;]+/\1[REDACTED]/g' \
  -e 's/([aA]pi[kK]ey[:=][[:space:]]*)[^& ,;"]+/\1[REDACTED_KEY]/g' \
  -e 's/(key=[a-zA-Z0-9_-]{8,})/key=[REDACTED_KEY]/g' \
  -e 's/(hash-secret[[:space:]]*=[[:space:]]*)[^& ,;]+/\1[REDACTED]/g' \
  -e 's/(vnpay\.hash-secret=[^& ,;]*)/vnpay.hash-secret=[REDACTED]/g'

echo ""
echo "================================================================================"
echo "                             KẾT THÚC BẢN XEM LOG                               "
echo "================================================================================"
