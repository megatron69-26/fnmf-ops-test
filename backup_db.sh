#!/bin/bash
set -e
echo "================================================================================"
echo "    FNMF DATABASE SECURE BACKUP & VERIFIED RESTORE RECONCILIATION              "
echo "================================================================================"
echo "Date: $(date)"

ADB="adb.exe"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DUMP_NAME="sec_dump_${TIMESTAMP}.tmp"
VERIFY_DB_NAME="fnmf_test_verify_${TIMESTAMP}"
BACKUP_DIR="/c/Users/khoid/AppData/Local/fnmf-backups"
DEST_FILE="$BACKUP_DIR/fnmf_test_backup_${TIMESTAMP}.sql"

# Cleanup trap: Ensures transient phone files and transient DB are dropped on any exit/error
cleanup() {
    EXIT_CODE=$?
    echo ""
    echo "[DỌN DẸP] Đảm bảo dọn sạch tài nguyên tạm trên Note 10+..."
    "$ADB" -s R3CM8105TPA shell "run-as com.termux rm -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME" 2>/dev/null || true
    if [ -n "$VERIFY_DB_NAME" ]; then
        "$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/dropdb --if-exists $VERIFY_DB_NAME" 2>/dev/null || true
    fi
    if [ $EXIT_CODE -ne 0 ]; then
        echo "CẢNH BÁO: Tác vụ kết thúc với mã lỗi $EXIT_CODE!" >&2
    fi
}
trap cleanup EXIT

# 1. Assert device is connected
echo "[1/6] Kiểm tra kết nối Galaxy Note 10+ qua ADB..."
"$ADB" devices | grep -q "R3CM8105TPA" || {
    echo "LỖI: Không tìm thấy thiết bị R3CM8105TPA qua ADB!" >&2
    exit 1
}
echo "OK: Thiết bị đã kết nối."

# 2. Query original metrics from fnmf_test
echo "[2/6] Thu thập số liệu đối soát từ database gốc (fnmf_test)..."
ORIG_METRICS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F ',' -c 'SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM wallets), (SELECT count(*) FROM flyway_schema_history), (SELECT count(*) FROM holdings), (SELECT count(*) FROM watchlists);'" 2>/dev/null || true)

if [ -z "$ORIG_METRICS" ]; then
    echo "LỖI: Không thể truy vấn số liệu từ database gốc fnmf_test!" >&2
    exit 1
fi
echo "Số liệu DB gốc (users,wallets,flyway,holdings,watchlists): $ORIG_METRICS"
IFS=',' read -r ORIG_USERS ORIG_WALLETS ORIG_FLYWAY ORIG_HOLDINGS ORIG_WATCHLISTS <<< "$ORIG_METRICS"

# 3. Prepare directory and generate dump in Termux private app sandbox
echo "[3/6] Xuất bản dump an toàn trong sandbox riêng Termux (không ghi vào /sdcard/)..."
mkdir -p "$BACKUP_DIR"
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/pg_dump -U fnmf_test_user -d fnmf_test -F p -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME"

# 4. Stream dump over ADB pipe directly to laptop
echo "[4/6] Truyền luồng dữ liệu bảo mật trực tiếp về laptop qua ADB pipe..."
"$ADB" -s R3CM8105TPA exec-out "run-as com.termux cat /data/data/com.termux/files/home/$TEMP_DUMP_NAME" > "$DEST_FILE"
"$ADB" -s R3CM8105TPA shell "run-as com.termux rm -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME"

FILE_SIZE=$(stat -c%s "$DEST_FILE" 2>/dev/null || wc -c < "$DEST_FILE")
if [ "$FILE_SIZE" -lt 5000 ]; then
    echo "LỖI: Bản dump quá nhỏ ($FILE_SIZE bytes), có thể đã xảy ra sự cố truyền dữ liệu!" >&2
    exit 1
fi
SHA256_HASH=$(sha256sum "$DEST_FILE" | cut -d' ' -f1)

echo "================================================================================"
echo "THÔNG TIN BẢN SAO LƯU CHÍNH THỨC TRÊN LAPTOP:"
echo "Đường dẫn: $DEST_FILE"
echo "Kích thước: $FILE_SIZE bytes"
echo "Mã băm SHA-256: $SHA256_HASH"
echo "================================================================================"

# 5. Restore into transient DB with strict ON_ERROR_STOP=1
echo "[5/6] Khởi tạo DB tạm và phục hồi bản dump với cờ ON_ERROR_STOP=1..."
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/createdb -O fnmf_test_user $VERIFY_DB_NAME"

# Pipe backup into verification DB with ON_ERROR_STOP=1
cat "$DEST_FILE" | "$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -v ON_ERROR_STOP=1 -d $VERIFY_DB_NAME -U fnmf_test_user -q"

# 6. Programmatically reconcile counts between original and restored DB
echo "[6/6] Đối soát tự động số lượng bản ghi giữa DB gốc và DB phục hồi..."
REST_METRICS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d $VERIFY_DB_NAME -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F ',' -c 'SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM wallets), (SELECT count(*) FROM flyway_schema_history), (SELECT count(*) FROM holdings), (SELECT count(*) FROM watchlists);'" 2>/dev/null || true)

echo "Số liệu DB phục hồi: $REST_METRICS"
IFS=',' read -r REST_USERS REST_WALLETS REST_FLYWAY REST_HOLDINGS REST_WATCHLISTS <<< "$REST_METRICS"

MISMATCH=""
[ "$ORIG_USERS" -ne "$REST_USERS" ] && MISMATCH="$MISMATCH users(gốc=$ORIG_USERS,phụchồi=$REST_USERS)"
[ "$ORIG_WALLETS" -ne "$REST_WALLETS" ] && MISMATCH="$MISMATCH wallets(gốc=$ORIG_WALLETS,phụchồi=$REST_WALLETS)"
[ "$ORIG_FLYWAY" -ne "$REST_FLYWAY" ] && MISMATCH="$MISMATCH flyway(gốc=$ORIG_FLYWAY,phụchồi=$REST_FLYWAY)"
[ "$ORIG_HOLDINGS" -ne "$REST_HOLDINGS" ] && MISMATCH="$MISMATCH holdings(gốc=$ORIG_HOLDINGS,phụchồi=$REST_HOLDINGS)"
[ "$ORIG_WATCHLISTS" -ne "$REST_WATCHLISTS" ] && MISMATCH="$MISMATCH watchlists(gốc=$ORIG_WATCHLISTS,phụchồi=$REST_WATCHLISTS)"

if [ -n "$MISMATCH" ]; then
    echo "LỖI ĐỐI SOÁT PHỤC HỒI: Dữ liệu phục hồi không khớp hoàn toàn với DB gốc:$MISMATCH" >&2
    exit 1
fi

echo "ĐỐI SOÁT THÀNH CÔNG: Mọi bảng cốt lõi (users, wallets, holdings, watchlists, flyway migrations) đều khớp 100%!"
echo "================================================================================"
echo "          XÁC MINH PHỤC HỒI TOÀN VẸN (RECOVERY FULLY RECONCILED)                "
echo "================================================================================"
