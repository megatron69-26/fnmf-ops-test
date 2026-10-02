#!/bin/bash
set -e
echo "=========================================================="
echo "    FNMF BACKEND TEST LOG VIEWER (MASKED SENSITIVE INFO)  "
echo "=========================================================="
echo "Date: $(date)"
echo "Tệp log: /data/data/com.termux/files/home/backend_test.log"
echo "Chính sách: Toàn bộ JWT token, Secret, Mật khẩu đều được che [REDACTED]"
echo "=========================================================="
echo ""

ADB="adb.exe"

# Pull last 60 lines and apply regex masking
RAW_LOG=$("$ADB" -s R3CM8105TPA shell "run-as com.termux tail -n 60 /data/data/com.termux/files/home/backend_test.log")

# Apply sed masks
echo "$RAW_LOG" | sed -E \
  -e 's/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/[REDACTED_JWT_TOKEN]/g' \
  -e 's/password=[^& ,]*/password=[REDACTED]/g' \
  -e 's/TEST_DATASOURCE_PASSWORD=[^& ,]*/TEST_DATASOURCE_PASSWORD=[REDACTED]/g' \
  -e 's/TEST_JWT_SECRET=[^& ,]*/TEST_JWT_SECRET=[REDACTED]/g' \
  -e 's/key=[a-zA-Z0-9_-]{8,}/key=[REDACTED_KEY]/g' \
  -e 's/Authorization: Bearer [^ ]*/Authorization: Bearer [REDACTED_TOKEN]/g'

echo ""
echo "=========================================================="
echo "                   KẾT THÚC XEM LOG                      "
echo "=========================================================="
