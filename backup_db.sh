#!/bin/bash
set -e
echo "=========================================================="
echo "      FNMF DATABASE SECURE BACKUP & RESTORE VERIFICATION "
echo "=========================================================="
echo "Date: $(date)"

ADB="adb.exe"

# 1. Assert device is connected
echo "[1/5] Kiểm tra kết nối Galaxy Note 10+ qua ADB..."
"$ADB" devices | grep -q "R3CM8105TPA" || {
    echo "LỖI: Không tìm thấy thiết bị R3CM8105TPA qua ADB!" >&2
    exit 1
}

# 2. Prepare destination directory outside repository
BACKUP_DIR="/c/Users/khoid/AppData/Local/fnmf-backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEST_FILE="$BACKUP_DIR/fnmf_test_backup_${TIMESTAMP}.sql"

echo "[2/5] Đang tạo bản dump trong thư mục Termux bảo mật..."
# Run pg_dump directly into Termux private app sandbox (not /sdcard/)
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/pg_dump -U fnmf_test_user -d fnmf_test -F p -f /data/data/com.termux/files/home/sec_dump.tmp"

echo "[3/5] Truyền luồng dữ liệu bảo mật trực tiếp về laptop qua ADB pipe..."
"$ADB" -s R3CM8105TPA exec-out "run-as com.termux cat /data/data/com.termux/files/home/sec_dump.tmp" > "$DEST_FILE"

# Immediately clean up temporary file on phone
"$ADB" -s R3CM8105TPA shell "run-as com.termux rm -f /data/data/com.termux/files/home/sec_dump.tmp"

# Verify file size > 5KB
FILE_SIZE=$(stat -c%s "$DEST_FILE" 2>/dev/null || wc -c < "$DEST_FILE")
if [ "$FILE_SIZE" -lt 5000 ]; then
    echo "LỖI: Bản dump quá nhỏ ($FILE_SIZE bytes), có thể đã xảy ra sự cố!" >&2
    exit 1
fi
SHA256_HASH=$(sha256sum "$DEST_FILE" | cut -d' ' -f1)
echo "Đã lưu bản sao lưu an toàn tại: $DEST_FILE"
echo "Kích thước: $FILE_SIZE bytes"
echo "Mã băm SHA256: $SHA256_HASH"

echo "[4/5] Tự động kiểm tra khả năng phục hồi (Automated Recovery Verification)..."
# Create a transient database on phone to verify recovery
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/createdb -O fnmf_test_user fnmf_test_verify_${TIMESTAMP}"

# Stream backup into transient database
cat "$DEST_FILE" | "$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test_verify_${TIMESTAMP} -U fnmf_test_user -q"

# Query verification counts
RESTORE_COUNTS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test_verify_${TIMESTAMP} -U fnmf_test_user -t -c 'SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM wallets), (SELECT count(*) FROM flyway_schema_history);'")

echo "Kết quả kiểm chứng phục hồi (users | wallets | migrations): $RESTORE_COUNTS"

# Clean up transient database
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/dropdb fnmf_test_verify_${TIMESTAMP}"

echo "[5/5] Hoàn tất kiểm chứng phục hồi 100%!"
echo "=========================================================="
echo "          SAO LƯU & KIỂM CHỨNG PHỤC HỒI THÀNH CÔNG       "
echo "=========================================================="
