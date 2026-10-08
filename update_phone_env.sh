#!/bin/bash
set -euo pipefail

export ANDROID_USER_HOME="C:/Users/khoid/.android"
export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
ADB="adb.exe"
DEVICE="R3CM8105TPA"
TERMUX_BASH="/data/data/com.termux/files/usr/bin/bash"

NEW_JWT_SECRET="${1:-${ROTATED_JWT_SECRET:-}}"
if [ -z "$NEW_JWT_SECRET" ]; then
    echo "Lỗi: Cần truyền secret mới qua đối số hoặc biến môi trường ROTATED_JWT_SECRET!" >&2
    exit 1
fi

echo "=== CẬP NHẬT TEST_JWT_SECRET TRÊN NOTE 10+ ==="
echo "LƯU Ý: Đổi TEST_JWT_SECRET sẽ làm mọi JWT token test cũ bị vô hiệu hóa (testers cần login lại)."

# Read current .env.test and update TEST_JWT_SECRET
"$ADB" -s "$DEVICE" shell "run-as com.termux $TERMUX_BASH -c '
ENV_FILE=/data/data/com.termux/files/home/.env.test
if [ ! -f \"\$ENV_FILE\" ]; then
    echo \"Lỗi: \$ENV_FILE không tồn tại!\" >&2
    exit 1
fi

# Backup current .env.test
cp -f \"\$ENV_FILE\" \"\${ENV_FILE}.bak\"

# Replace or add TEST_JWT_SECRET
if grep -q \"^TEST_JWT_SECRET=\" \"\$ENV_FILE\"; then
    sed -i \"s/^TEST_JWT_SECRET=.*/TEST_JWT_SECRET=${NEW_JWT_SECRET}/\" \"\$ENV_FILE\"
else
    echo \"TEST_JWT_SECRET=${NEW_JWT_SECRET}\" >> \"\$ENV_FILE\"
fi

echo \"Đã cập nhật .env.test thành công.\"
'"

echo "=== DANH SÁCH BIẾN TRONG .env.test (ĐÃ CHE GIÁ TRỊ) ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux $TERMUX_BASH -c '
cat /data/data/com.termux/files/home/.env.test | sed -E \"s/=.*/=[REDACTED]/\"
'"
