#!/bin/bash
set -euo pipefail

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
VERIFICATION_PASSED="false"

# Cleanup trap: Runs unconditionally on script exit.
# Drops transient DB, deletes phone dump, and quarantines backup file if verification failed.
cleanup() {
    EXIT_CODE=$?
    echo ""
    echo "[DỌN DẸP] Đang dọn dẹp tài nguyên tạm..."
    "$ADB" -s R3CM8105TPA shell "run-as com.termux rm -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME" 2>/dev/null || true
    if [ -n "$VERIFY_DB_NAME" ]; then
        "$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/dropdb --if-exists $VERIFY_DB_NAME" 2>/dev/null || true
    fi

    if [ "$VERIFICATION_PASSED" != "true" ] && [ -f "$DEST_FILE" ]; then
        echo "CẢNH BÁO BẢO TOÀN: Xác minh phục hồi thất bại hoặc bị ngắt quãng!" >&2
        echo "Tệp sao lưu bị loại khỏi danh sách hợp lệ: ${DEST_FILE}.FAILED_VERIFICATION" >&2
        mv "$DEST_FILE" "${DEST_FILE}.FAILED_VERIFICATION" 2>/dev/null || true
    fi

    if [ $EXIT_CODE -ne 0 ]; then
        echo "KẾT THÚC: Tác vụ dừng với mã lỗi $EXIT_CODE!" >&2
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

# 2. Query original metrics and content sample from fnmf_test
echo "[2/6] Thu thập số liệu đối soát và mẫu dữ liệu từ database gốc (fnmf_test)..."
ORIG_METRICS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F ',' -c 'SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema = '\''public'\''), (SELECT count(*) FROM users), (SELECT count(*) FROM wallets), (SELECT count(*) FROM flyway_schema_history), (SELECT count(*) FROM holdings), (SELECT count(*) FROM watchlists);'")

# Validate exact format: 6 comma-separated integers
METRICS_REGEX='^[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+$'
if [[ ! "$ORIG_METRICS" =~ $METRICS_REGEX ]]; then
    echo "LỖI: Phản hồi số liệu DB gốc không đúng định dạng (Nhận được: '$ORIG_METRICS')!" >&2
    exit 1
fi
echo "Số liệu DB gốc (tables,users,wallets,flyway,holdings,watchlists): $ORIG_METRICS"

ORIG_SAMPLES=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F '|' -c 'SELECT (SELECT id || '\'':'\'' || lower(email) FROM users ORDER BY id LIMIT 1), (SELECT id || '\'':'\'' || balance_usd FROM wallets ORDER BY id LIMIT 1), (SELECT version || '\'':'\'' || script FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 1);'")
echo "Mẫu dữ liệu DB gốc (user_sample | wallet_sample | flyway_sample): $ORIG_SAMPLES"

# 3. Export dump into Termux private app sandbox (never /sdcard/)
echo "[3/6] Xuất bản dump trong sandbox riêng Termux (không chạm /sdcard/)..."
mkdir -p "$BACKUP_DIR"
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/pg_dump -U fnmf_test_user -d fnmf_test -F p -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME"

# 4. Stream dump over ADB pipe directly to laptop
echo "[4/6] Truyền luồng dữ liệu bảo mật trực tiếp về laptop qua ADB pipe..."
"$ADB" -s R3CM8105TPA exec-out "run-as com.termux cat /data/data/com.termux/files/home/$TEMP_DUMP_NAME" > "$DEST_FILE"
"$ADB" -s R3CM8105TPA shell "run-as com.termux rm -f /data/data/com.termux/files/home/$TEMP_DUMP_NAME"

FILE_SIZE=$(stat -c%s "$DEST_FILE" 2>/dev/null || wc -c < "$DEST_FILE")
if [ "$FILE_SIZE" -lt 5000 ]; then
    echo "LỖI: Bản dump quá nhỏ ($FILE_SIZE bytes), nghi ngờ dữ liệu hỏng!" >&2
    exit 1
fi
SHA256_HASH=$(sha256sum "$DEST_FILE" | cut -d' ' -f1)

echo "================================================================================"
echo "BẢN SAO LƯU TẠM THỜI ĐÃ TẢI VỀ (CHỜ KIỂM CHỨNG PHỤC HỒI):"
echo "Đường dẫn: $DEST_FILE"
echo "Kích thước: $FILE_SIZE bytes"
echo "Mã băm SHA-256: $SHA256_HASH"
echo "================================================================================"

# 5. Restore into transient DB with strict ON_ERROR_STOP=1
echo "[5/6] Khởi tạo DB tạm ($VERIFY_DB_NAME) và nạp dữ liệu với ON_ERROR_STOP=1..."
"$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/createdb -O fnmf_test_user $VERIFY_DB_NAME"

# Pipe dump file from laptop to phone psql
cat "$DEST_FILE" | "$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -v ON_ERROR_STOP=1 -d $VERIFY_DB_NAME -U fnmf_test_user -q"

# 6. Programmatically reconcile metrics and content samples between original and restored DB
echo "[6/6] Đối soát tự động số lượng và nội dung mẫu giữa DB gốc và DB phục hồi..."
REST_METRICS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d $VERIFY_DB_NAME -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F ',' -c 'SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema = '\''public'\''), (SELECT count(*) FROM users), (SELECT count(*) FROM wallets), (SELECT count(*) FROM flyway_schema_history), (SELECT count(*) FROM holdings), (SELECT count(*) FROM watchlists);'")

if [[ ! "$REST_METRICS" =~ $METRICS_REGEX ]]; then
    echo "LỖI: Phản hồi số liệu DB phục hồi không đúng định dạng (Nhận được: '$REST_METRICS')!" >&2
    exit 1
fi
echo "Số liệu DB phục hồi: $REST_METRICS"

REST_SAMPLES=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d $VERIFY_DB_NAME -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -F '|' -c 'SELECT (SELECT id || '\'':'\'' || lower(email) FROM users ORDER BY id LIMIT 1), (SELECT id || '\'':'\'' || balance_usd FROM wallets ORDER BY id LIMIT 1), (SELECT version || '\'':'\'' || script FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 1);'")
echo "Mẫu dữ liệu DB phục hồi: $REST_SAMPLES"

# Strict comparisons
if [ "$ORIG_METRICS" != "$REST_METRICS" ]; then
    echo "LỖI ĐỐI SOÁT: Số liệu bảng và hàng không khớp! (Gốc: $ORIG_METRICS, Phục hồi: $REST_METRICS)" >&2
    exit 1
fi

if [ "$ORIG_SAMPLES" != "$REST_SAMPLES" ]; then
    echo "LỖI ĐỐI SOÁT: Mẫu dữ liệu nội dung không khớp! (Gốc: $ORIG_SAMPLES, Phục hồi: $REST_SAMPLES)" >&2
    exit 1
fi

# Mark verification as passed!
VERIFICATION_PASSED="true"

echo "================================================================================"
echo "KẾT QUẢ: KIỂM TRA PHỤC HỒI CƠ BẢN ĐẠT TIÊU CHUẨN."
echo "Phạm vi kiểm tra đã chứng minh:"
echo " - Cấu trúc bảng schema public ($ORIG_METRICS)."
echo " - Số lượng bản ghi các bảng cốt lõi (users, wallets, holdings, watchlists, flyway)."
echo " - Tính toàn vẹn nội dung mẫu (tài khoản user, số dư ví, script Flyway mới nhất)."
echo "Bản sao lưu chính thức được công nhận hợp lệ tại:"
echo " -> $DEST_FILE ($FILE_SIZE bytes, SHA256: $SHA256_HASH)"
echo "================================================================================"
