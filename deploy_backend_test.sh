#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    FNMF BACKEND TEST DEPLOYMENT PIPELINE (KIẾN TRÚC PHÒNG THỦ & TỰ ĐỘNG HÓA)   "
echo "================================================================================"
echo "Date: $(date)"
echo ""

ADB="adb.exe"
DEVICE_ID="R3CM8105TPA"
ARTIFACT_DIR="/c/Users/khoid/Projects/artifacts/backend"
TARGET_JAR="${TARGET_JAR:-${ARTIFACT_DIR}/fnmf-backend-test-latest.jar}"
BACKUP_SCRIPT="/c/Users/khoid/Projects/fnmf-ops-test/backup_db.sh"
RESTART_SCRIPT="/c/Users/khoid/Projects/fnmf-ops-test/restart_backend.sh"
HEALTH_CHECK_SCRIPT="/c/Users/khoid/Projects/fnmf-ops-test/health_check.sh"

ACTIVATE_DEPLOY="${ACTIVATE_DEPLOY:-false}"
SIMULATE_MODE="${SIMULATE_MODE:-false}"
SIM_DIR="${SIM_DIR:-/c/Users/khoid/AppData/Local/Temp/fnmf_deploy_sim}"

# ==============================================================================
# KHÓA BẢO VỆ AN TOÀN (DESIGN-ONLY SAFEGUARD)
# ==============================================================================
# Theo chỉ thị của người dùng: "Chỉ thiết kế tác vụ “Deploy Backend Test” với
# backup, rollback, kiểm tra migration và health check; chưa kích hoạt,
# chưa bật auto-deploy/webhook, chưa thay JAR trên Note 10+, chưa cài APK hay mở tunnel."
# ==============================================================================
if [ "$ACTIVATE_DEPLOY" != "true" ] && [ "$SIMULATE_MODE" != "true" ]; then
    echo "================================================================================"
    echo "                   [THÔNG BÁO THIẾT KẾ KIẾN TRÚC AN TOÀN]                       "
    echo "================================================================================"
    echo "Tác vụ Deploy Backend Test đã được THIẾT KẾ HOÀN CHỈNH nhưng CHƯA KÍCH HOẠT"
    echo "theo đúng yêu cầu nghiệm thu của giai đoạn kiểm thử."
    echo ""
    echo "Quy trình thiết kế bao gồm 7 chặng an toàn phòng thủ theo chiều sâu:"
    echo "  1. Pre-flight Check   : Đối soát thiết bị Note 10+ qua ADB và toàn vẹn SHA-256 JAR."
    echo "  2. Pre-deploy Backup  : Kích hoạt sao lưu đối soát CSDL an toàn (backup_db.sh)."
    echo "  3. Migration Safety   : Kiểm tra Flyway schema history, đối soát script SQL mới trong JAR."
    echo "  4. Staging & Rollback : Sao lưu JAR đang chạy hiện tại thành JAR rollback dự phòng có kiểm soát."
    echo "  5. Atomic Deploy      : Đẩy JAR mới vào vùng đệm tạm, đối soát checksum trước khi tráo."
    echo "  6. Graceful Restart   : Tráo JAR và khởi động lại; tự động rollback nếu khởi động thất bại."
    echo "  7. Health & Rollback  : Giám sát /actuator/health và /api/stocks; tự động rollback nếu lỗi."
    echo ""
    echo "TRẠNG THÁI HIỆN TẠI:"
    echo "  • Chưa thay đổi tệp JAR trên Note 10+."
    echo "  • Chưa tắt hoặc khởi động lại tiến trình backend đang phục vụ."
    echo "  • Chưa kích hoạt auto-deploy hay webhook tự động."
    echo "  • Để kích hoạt trong tương lai khi có quyết định triển khai chính thức:"
    echo "    Truyền biến môi trường: ACTIVATE_DEPLOY=true"
    echo "================================================================================"
    exit 0
fi

# Thiết lập đường dẫn theo môi trường thực hoặc giả lập
if [ "$SIMULATE_MODE" = "true" ]; then
    echo "================================================================================"
    echo "       ĐANG CHẠY TRONG MÔI TRƯỜNG GIẢ LẬP (SIMULATE_MODE=true)                  "
    echo "================================================================================"
    mkdir -p "$SIM_DIR"
    PHONE_HOME="$SIM_DIR"
    PHONE_JAR="$PHONE_HOME/llm-gateway-1.1.17.jar"
    ROLLBACK_JAR="$PHONE_HOME/llm-gateway-rollback.jar"
    STAGING_JAR="$PHONE_HOME/llm-gateway-staging.jar"
else
    echo "BẮT ĐẦU TRIỂN KHAI THỰC TẾ TRÊN GALAXY NOTE 10+ (ACTIVATE_DEPLOY=true)..."
    PHONE_HOME="/data/data/com.termux/files/home"
    PHONE_JAR="${PHONE_HOME}/llm-gateway-1.1.17.jar"
    ROLLBACK_JAR="${PHONE_HOME}/llm-gateway-rollback.jar"
    STAGING_JAR="${PHONE_HOME}/llm-gateway-staging.jar"
fi

MUTATED="false"
DEPLOY_SUCCESS="false"
ROLLBACK_IN_PROGRESS="false"

# ==============================================================================
# LỚP TRỪU TƯỢNG HÓA THAO TÁC HỆ THỐNG (DEVICE ABSTRACTION LAYER)
# ==============================================================================
if [ "$SIMULATE_MODE" = "true" ]; then
    device_check() {
        if [ "${SIM_DEVICE_OFFLINE:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Thiết bị không phản hồi!" >&2
            return 1
        fi
        return 0
    }
    
    get_db_version() {
        if [ "${SIM_DB_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Kết nối CSDL hoặc đọc bảng Flyway thất bại!" >&2
            return 1
        fi
        local v="${SIM_DB_VERSION:-}"
        if [ -z "$v" ]; then
            echo "LỖI GIẢ LẬP: Biến SIM_DB_VERSION không được thiết lập!" >&2
            return 1
        fi
        echo "$v"
    }
    
    remote_file_exists() {
        local path="$1"
        [ -s "$path" ]
    }
    
    remote_get_size() {
        local path="$1"
        if [ -f "$path" ]; then
            wc -c < "$path" | tr -d ' '
        else
            echo "0"
        fi
    }

    remote_sha256() {
        local path="$1"
        if [ "${SIM_STAGING_CORRUPT:-false}" = "true" ] && [[ "$path" == *"$STAGING_JAR"* ]]; then
            echo "bad_corrupted_device_checksum_hash_val"
            return 0
        fi
        if [ -f "$path" ]; then
            sha256sum "$path" | awk '{print $1}' | tr -d '\r\n '
        else
            echo ""
        fi
    }
    
    remote_copy() {
        local src="$1"
        local dst="$2"
        if [ "$ROLLBACK_IN_PROGRESS" != "true" ] && [ "${SIM_COPY_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Sao chép tệp snapshot thất bại!" >&2
            return 1
        fi
        cp -f "$src" "$dst"
    }
    
    remote_move() {
        local src="$1"
        local dst="$2"
        if [ "${SIM_MOVE_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Di chuyển tệp thất bại (hoán đổi bị lỗi)!" >&2
            rm -f "$dst"
            return 1
        fi
        mv -f "$src" "$dst"
    }
    
    remote_push() {
        local src="$1"
        local dst="$2"
        if [ "${SIM_PUSH_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Truyền tệp vào vùng staging thất bại!" >&2
            return 1
        fi
        cp -f "$src" "$dst"
    }
    
    run_backup() {
        if [ "${SIM_BACKUP_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Sao lưu CSDL thất bại!" >&2
            return 1
        fi
        echo "[GIẢ LẬP] Sao lưu CSDL thành công."
        return 0
    }
    
    run_restart() {
        if [ "$ROLLBACK_IN_PROGRESS" = "true" ]; then
            echo "[GIẢ LẬP] Khởi động lại dịch vụ với bản JAR khôi phục: Thành công."
            return 0
        fi
        if [ "${SIM_RESTART_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Khởi động lại dịch vụ thất bại (tiến trình crash khi nạp JAR mới)!" >&2
            return 1
        fi
        echo "[GIẢ LẬP] Khởi động lại dịch vụ thành công."
        return 0
    }
    
    run_health_check() {
        if [ "$ROLLBACK_IN_PROGRESS" = "true" ]; then
            echo "[GIẢ LẬP] Kiểm tra sức khỏe dịch vụ sau rollback: Trạng thái UP 100%."
            return 0
        fi
        if [ "${SIM_HEALTH_FAIL:-false}" = "true" ]; then
            echo "LỖI GIẢ LẬP: Kiểm tra sức khỏe thất bại (Actuator DOWN hoặc thiếu tài sản)!" >&2
            return 1
        fi
        echo "[GIẢ LẬP] Kiểm tra sức khỏe đạt: Actuator UP, đầy đủ 5/5 tài sản."
        return 0
    }
else
    device_check() {
        "$ADB" devices | grep -q "$DEVICE_ID"
    }
    
    get_db_version() {
        local raw
        if ! raw=$("$ADB" -s "$DEVICE_ID" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -c 'SELECT coalesce(max(version), '\''0'\'') FROM flyway_schema_history WHERE success = true;'" 2>/dev/null); then
            echo "LỖI KẾT NỐI CSDL: Lệnh psql kiểm tra Flyway thất bại!" >&2
            return 1
        fi
        raw=$(echo "$raw" | tr -d '\r\n ')
        local num
        num=$(echo "$raw" | sed -e 's/^V//' | tr -dc '0-9')
        if [ -z "$num" ]; then
            echo "LỖI DỮ LIỆU: Phản hồi phiên bản Flyway không hợp lệ ('$raw')!" >&2
            return 1
        fi
        echo "$num"
    }
    
    remote_file_exists() {
        local path="$1"
        "$ADB" -s "$DEVICE_ID" shell "run-as com.termux test -s '$path'"
    }
    
    remote_get_size() {
        local path="$1"
        local sz
        sz=$("$ADB" -s "$DEVICE_ID" shell "run-as com.termux wc -c < '$path' 2>/dev/null" | tr -d '\r\n ')
        echo "${sz:-0}"
    }

    remote_sha256() {
        local path="$1"
        local sum
        sum=$("$ADB" -s "$DEVICE_ID" shell "run-as com.termux sha256sum '$path' 2>/dev/null" | awk '{print $1}' | tr -d '\r\n ')
        echo "$sum"
    }
    
    remote_copy() {
        local src="$1"
        local dst="$2"
        "$ADB" -s "$DEVICE_ID" shell "run-as com.termux cp -f '$src' '$dst'"
    }
    
    remote_move() {
        local src="$1"
        local dst="$2"
        "$ADB" -s "$DEVICE_ID" shell "run-as com.termux mv -f '$src' '$dst'"
    }
    
    remote_push() {
        local src="$1"
        local dst="$2"
        local tmp="/data/local/tmp/fnmf_push_$$.tmp"
        "$ADB" -s "$DEVICE_ID" push "$src" "$tmp"
        "$ADB" -s "$DEVICE_ID" shell "run-as com.termux cp -f '$tmp' '$dst' && rm -f '$tmp'"
    }
    
    run_backup() {
        "$BACKUP_SCRIPT"
    }
    
    run_restart() {
        "$RESTART_SCRIPT"
    }
    
    run_health_check() {
        "$HEALTH_CHECK_SCRIPT"
    }
fi

# ==============================================================================
# HÀM KIỂM SOÁT AN TOÀN MIGRATION FLYWAY TRONG TỆP JAR
# ==============================================================================
check_migration_safety() {
    local target_jar="$1"
    local current_db_ver="$2"

    echo "Kiểm tra an toàn migration trong tệp JAR: $target_jar"
    echo "Phiên bản CSDL hiện tại: V$current_db_ver"

    # Trích xuất danh sách tệp migration từ JAR
    local entries
    entries=$(unzip -l "$target_jar" 2>/dev/null | awk '{print $4}' | grep -E '(^|/)BOOT-INF/classes/db/migration/V[0-9]+.*\.sql$' | sort -V || true)

    if [ -z "$entries" ]; then
        echo "LƯU Ý: Không tìm thấy tệp migration Flyway nào trong JAR."
        return 0
    fi

    local max_jar_ver=0
    local new_mig_count=0
    local pending_migrations=()

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local fname
        fname=$(basename "$entry")
        local ver
        ver=$(echo "$fname" | sed -n 's/^V\([0-9]*\)__.*/\1/p')
        if [ -n "$ver" ]; then
            if [ "$ver" -gt "$max_jar_ver" ]; then
                max_jar_ver=$ver
            fi
            if [ -n "$current_db_ver" ] && [ "$ver" -gt "$current_db_ver" ]; then
                pending_migrations+=("$entry")
                new_mig_count=$((new_mig_count + 1))
            fi
        fi
    done <<< "$entries"

    echo "Phiên bản migration lớn nhất trong JAR: V$max_jar_ver"

    # 1. Kiểm tra nguy cơ downgrade
    if [ -n "$current_db_ver" ] && [ "$current_db_ver" -gt "$max_jar_ver" ]; then
        echo "LỖI AN TOÀN MIGRATION: Phiên bản CSDL (V$current_db_ver) cao hơn bản trong JAR (V$max_jar_ver)!" >&2
        echo "Nguy cơ hạ cấp (downgrade) không tương thích. Hủy bỏ triển khai!" >&2
        return 1
    fi

    echo "Số lượng migration mới cần kiểm tra phá hủy: $new_mig_count"

    # 2. Quét các migration mới xem có lệnh phá hủy không
    for mig in "${pending_migrations[@]}"; do
        local mname
        mname=$(basename "$mig")
        echo "  -> Đang quét kiểm tra $mname..."
        local content
        content=$(unzip -p "$target_jar" "$mig" 2>/dev/null || true)

        # Quét DROP TABLE / DROP COLUMN / DROP SCHEMA / DROP DATABASE / TRUNCATE
        if echo "$content" | grep -iqE '\bDROP\s+(TABLE|VIEW|SCHEMA|DATABASE|COLUMN)\b|\bTRUNCATE\b|\bALTER\s+TABLE\s+.*\bDROP\s+COLUMN\b'; then
            echo "LỖI AN TOÀN MIGRATION: Phát hiện câu lệnh phá hủy dữ liệu (DROP/TRUNCATE) trong $mname!" >&2
            echo "$content" | grep -inE '\bDROP\s+(TABLE|VIEW|SCHEMA|DATABASE|COLUMN)\b|\bTRUNCATE\b|\bDROP\s+COLUMN\b' >&2
            return 1
        fi

        # Quét DELETE không có WHERE hoặc WHERE 1=1
        if echo "$content" | grep -iqE '\bWHERE\s+1\s*=\s*1\b'; then
            echo "LỖI AN TOÀN MIGRATION: Phát hiện WHERE 1=1 trong $mname!" >&2
            return 1
        fi

        # Kiểm tra DELETE FROM ... ; (không có WHERE)
        local normalized
        normalized=$(echo "$content" | sed -e 's/--.*$//g' | tr '\n' ' ' | tr -s ' ')
        if echo "$normalized" | grep -iqE '\bDELETE\s+FROM\s+[a-zA-Z0-9_]+\s*;'; then
            echo "LỖI AN TOÀN MIGRATION: Phát hiện DELETE không có mệnh đề WHERE trong $mname!" >&2
            return 1
        fi
    done

    echo "KẾT QUẢ MIGRATION: Tất cả migration hợp lệ và an toàn tuyệt đối."
    return 0
}

# ==============================================================================
# HÀM THỰC THI ROLLBACK TỰ ĐỘNG
# ==============================================================================
perform_rollback() {
    ROLLBACK_IN_PROGRESS="true"
    echo "" >&2
    echo "================================================================================" >&2
    echo "           [QUY TRÌNH ROLLBACK KHẨN CẤP ĐƯỢC KÍCH HOẠT]                         " >&2
    echo "================================================================================" >&2
    echo "1. Kiểm tra bản snapshot rollback: $ROLLBACK_JAR..." >&2
    if ! remote_file_exists "$ROLLBACK_JAR"; then
        echo "LỖI NGUY HIỂM: Bản snapshot $ROLLBACK_JAR không tồn tại hoặc rỗng!" >&2
        return 1
    fi
    
    echo "2. Khôi phục JAR từ bản snapshot sang tệp chính ($PHONE_JAR)..." >&2
    if ! remote_copy "$ROLLBACK_JAR" "$PHONE_JAR"; then
        echo "LỖI NGHIÊM TRỌNG: Không thể hoàn nguyên tệp JAR từ bản snapshot!" >&2
        return 1
    fi
    
    echo "3. Khởi động lại dịch vụ backend với bản JAR đã khôi phục..." >&2
    if ! run_restart; then
        echo "CẢNH BÁO: Khởi động lại dịch vụ sau rollback gặp sự cố!" >&2
    fi
    
    echo "4. Xác minh sức khỏe dịch vụ sau khi khôi phục..." >&2
    if run_health_check; then
        echo "================================================================================" >&2
        echo "  ROLLBACK THÀNH CÔNG: Dịch vụ đã trở lại trực tuyến với bản JAR nguyên trạng.  " >&2
        echo "================================================================================" >&2
        return 0
    else
        echo "LỖI: Dịch vụ sau rollback vẫn không phản hồi trạng thái UP!" >&2
        return 1
    fi
}

on_exit() {
    local code=$?
    if [ "$MUTATED" = "true" ] && [ "$DEPLOY_SUCCESS" != "true" ]; then
        echo "" >&2
        echo "================================================================================" >&2
        echo "  [BẢO VỆ PHÒNG THỦ] SCRIPT BỊ NGẮT SAU KHI HOÁN ĐỔI JAR (EXIT CODE: $code)!   " >&2
        echo "================================================================================" >&2
        perform_rollback || true
    fi
}
trap on_exit EXIT

# ==============================================================================
# CHẶNG 1: PRE-FLIGHT CHECK (THIẾT BỊ & CHECKSUM ARTIFACT)
# ==============================================================================
echo "[1/7] Kiểm tra kết nối thiết bị và toàn vẹn SHA-256 của Artifact..."
if ! device_check; then
    echo "LỖI: Thiết bị $DEVICE_ID không phản hồi qua ADB!" >&2
    exit 1
fi

if [ ! -f "$TARGET_JAR" ] || [ ! -f "${TARGET_JAR}.sha256" ]; then
    echo "LỖI: Tệp JAR hoặc manifest SHA-256 không tồn tại tại $TARGET_JAR!" >&2
    exit 1
fi

EXPECTED_SHA=$(cut -d' ' -f1 "${TARGET_JAR}.sha256")
ACTUAL_SHA=$(sha256sum "$TARGET_JAR" | cut -d' ' -f1)
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "LỖI: Checksum SHA-256 của artifact không khớp!" >&2
    echo "  Kỳ vọng: $EXPECTED_SHA" >&2
    echo "  Thực tế: $ACTUAL_SHA" >&2
    exit 1
fi
echo "OK: Artifact toàn vẹn (SHA-256: $ACTUAL_SHA)."

# ==============================================================================
# CHẶNG 2: PRE-DEPLOY BACKUP (SAO LƯU CSDL ĐỐI SOÁT)
# ==============================================================================
echo "[2/7] Thực hiện sao lưu CSDL trước triển khai..."
if ! run_backup; then
    echo "LỖI: Sao lưu CSDL thất bại! Hủy bỏ triển khai trước khi thay đổi trạng thái." >&2
    exit 1
fi

# ==============================================================================
# CHẶNG 3: MIGRATION SAFETY CHECK (ĐỐI SOÁT FLYWAY & CHẶN PHÁ HỦY)
# ==============================================================================
echo "[3/7] Kiểm tra lịch sử migration Flyway và đối soát SQL trong JAR..."
if ! CURRENT_MIGRATION=$(get_db_version); then
    echo "LỖI AN TOÀN (FAIL-CLOSED): Không thể đọc phiên bản Flyway từ CSDL!" >&2
    echo "Dừng quy trình ngay lập tức để bảo vệ an toàn CSDL." >&2
    exit 1
fi

CURRENT_MIGRATION=$(echo "$CURRENT_MIGRATION" | sed -e 's/^V//' | tr -dc '0-9')
if [ -z "$CURRENT_MIGRATION" ]; then
    echo "LỖI AN TOÀN (FAIL-CLOSED): Phiên bản Flyway sau chuẩn hóa rỗng! Hủy bỏ triển khai." >&2
    exit 1
fi
echo "Phiên bản Flyway hiện tại trên CSDL: V$CURRENT_MIGRATION"

if ! check_migration_safety "$TARGET_JAR" "$CURRENT_MIGRATION"; then
    echo "LỖI: Kiểm tra an toàn Migration không đạt! Hủy bỏ triển khai." >&2
    exit 1
fi

# ==============================================================================
# CHẶNG 4: STAGING & ROLLBACK SNAPSHOT (SAO LƯU JAR HIỆN TẠI & ASSERTION)
# ==============================================================================
echo "[4/7] Sao lưu tệp JAR hiện tại trên thiết bị để phục vụ rollback..."
if ! remote_file_exists "$PHONE_JAR"; then
    echo "LỖI: Tệp JAR đang chạy ($PHONE_JAR) không tồn tại hoặc có kích thước 0 byte!" >&2
    echo "Không thể tạo bản snapshot an toàn. Hủy bỏ triển khai!" >&2
    exit 1
fi

ORIG_JAR_SIZE=$(remote_get_size "$PHONE_JAR")
echo "Kích thước tệp JAR gốc: $ORIG_JAR_SIZE bytes"

# Thực hiện sao chép snapshot (KHÔNG DÙNG || true)
if ! remote_copy "$PHONE_JAR" "$ROLLBACK_JAR"; then
    echo "LỖI: Lệnh sao lưu snapshot JAR thất bại!" >&2
    exit 1
fi

# Đối soát kiểm tra snapshot sau khi chép
if ! remote_file_exists "$ROLLBACK_JAR"; then
    echo "LỖI: Tệp snapshot rollback ($ROLLBACK_JAR) không tồn tại sau khi sao lưu!" >&2
    exit 1
fi

ROLLBACK_SIZE=$(remote_get_size "$ROLLBACK_JAR")
if [ "$ROLLBACK_SIZE" -ne "$ORIG_JAR_SIZE" ] || [ "$ROLLBACK_SIZE" -le 0 ]; then
    echo "LỖI: Kích thước bản snapshot ($ROLLBACK_SIZE bytes) không khớp tệp gốc ($ORIG_JAR_SIZE bytes)!" >&2
    exit 1
fi
echo "OK: Đã xác thực bản snapshot rollback toàn vẹn ($ROLLBACK_JAR, $ROLLBACK_SIZE bytes)."

# ==============================================================================
# CHẶNG 5: ATOMIC DEPLOY BUFFERING (ĐẨY JAR MỚI VÀO STAGING & ĐỐI SOÁT)
# ==============================================================================
echo "[5/7] Đẩy tệp JAR mới vào vùng đệm thiết bị (Staging)..."
TARGET_SIZE=$(wc -c < "$TARGET_JAR" | tr -d ' ')

if ! remote_push "$TARGET_JAR" "$STAGING_JAR"; then
    echo "LỖI: Đẩy tệp JAR mới vào staging thất bại!" >&2
    exit 1
fi

STAGING_SIZE=$(remote_get_size "$STAGING_JAR")
if [ "$STAGING_SIZE" -ne "$TARGET_SIZE" ] || [ "$STAGING_SIZE" -le 0 ]; then
    echo "LỖI: Kích thước tệp staging ($STAGING_SIZE bytes) không khớp tệp nguồn ($TARGET_SIZE bytes)!" >&2
    exit 1
fi
echo "OK: Đã xác thực kích thước tệp staging ($STAGING_SIZE bytes)."

echo "Đối soát checksum SHA-256 của tệp staging trên thiết bị..."
STAGING_SHA=$(remote_sha256 "$STAGING_JAR")
if [ -z "$STAGING_SHA" ] || [ "$STAGING_SHA" != "$ACTUAL_SHA" ]; then
    echo "LỖI TOÀN VẸN: Checksum SHA-256 tệp staging trên thiết bị không khớp Artifact!" >&2
    echo "  Kỳ vọng (Artifact): $ACTUAL_SHA" >&2
    echo "  Thực tế (Thiết bị): $STAGING_SHA" >&2
    echo "Phát hiện tệp truyền tải bị lỗi hoặc không toàn vẹn. Hủy bỏ trước khi tráo JAR!" >&2
    exit 1
fi
echo "OK: Checksum SHA-256 trên thiết bị khớp tuyệt đối ($STAGING_SHA)."

# ==============================================================================
# CHẶNG 6: ATOMIC SWAP & RESTART (HOÁN ĐỔI JAR & KHỞI ĐỘNG DỊCH VỤ)
# ==============================================================================
echo "[6/7] Thay thế tệp JAR (Atomic Swap) và khởi động lại dịch vụ..."

# ĐÁNH DẤU HỆ THỐNG BẮT ĐẦU BIẾN ĐỔI (MUTATED=true)
# Mọi lỗi phát sinh từ thời điểm này (kể cả lỗi trong chính lệnh swap) đều kích hoạt rollback!
MUTATED="true"

if ! remote_move "$STAGING_JAR" "$PHONE_JAR"; then
    echo "LỖI: Lệnh hoán đổi tệp staging sang tệp chính thất bại hoặc bị ngắt! Kích hoạt Rollback khẩn cấp..." >&2
    perform_rollback
    exit 1
fi

if ! remote_file_exists "$PHONE_JAR"; then
    echo "LỖI NGHIÊM TRỌNG: Tệp JAR chính ($PHONE_JAR) không tồn tại sau lệnh hoán đổi!" >&2
    perform_rollback
    exit 1
fi

echo "XÁC NHẬN: Tệp JAR trên thiết bị đã được thay thế bằng phiên bản mới."

echo "Tiến hành khởi động lại tiến trình backend..."
if ! run_restart; then
    echo "LỖI: Khởi động lại dịch vụ backend thất bại!" >&2
    perform_rollback
    exit 1
fi

# ==============================================================================
# CHẶNG 7: HEALTH CHECK & ROLLBACK (XÁC THỰC SỨC KHỎE SAU TRIỂN KHAI)
# ==============================================================================
echo "[7/7] Xác thực sức khỏe dịch vụ sau triển khai..."
if ! run_health_check; then
    echo "CẢNH BÁO: Dịch vụ không vượt qua kiểm tra sức khỏe! Bắt đầu Rollback khẩn cấp..." >&2
    perform_rollback
    exit 1
fi

DEPLOY_SUCCESS="true"
echo "================================================================================"
echo "          TRIỂN KHAI VÀ NGHIỆM THU BACKEND TEST THÀNH CÔNG RỰC RỠ               "
echo "================================================================================"
echo "Phiên bản triển khai : $TARGET_JAR"
echo "SHA-256              : $ACTUAL_SHA"
echo "Lịch sử CSDL         : V$CURRENT_MIGRATION (Đã kiểm tra an toàn)"
echo "Bản snapshot dự phòng: $ROLLBACK_JAR"
echo "Trạng thái dịch vụ   : UP (Đầy đủ 5/5 tài sản Binance)"
echo "================================================================================"
