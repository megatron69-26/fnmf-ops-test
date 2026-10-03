#!/bin/bash
set -euo pipefail

# Helper function to check Flyway migration safety
# Usage: check_migration_safety <target_jar> <current_db_version>

check_migration_safety() {
    local target_jar="$1"
    local current_db_ver="$2"

    echo "=== [KIỂM TRA AN TOÀN MIGRATION FLYWAY] ==="
    echo "Tệp JAR mục tiêu    : $target_jar"
    echo "Phiên bản DB hiện tại: V$current_db_ver"

    # Trích xuất danh sách migration từ JAR
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
        echo "Nguy cơ hạ cấp (downgrade) không tương thích. Dừng triển khai!" >&2
        return 1
    fi

    echo "Số lượng migration mới cần kiểm tra phá hủy: $new_mig_count"

    # 2. Quét các migration mới xem có lệnh phá hủy không
    for mig in "${pending_migrations[@]}"; do
        local mname
        mname=$(basename "$mig")
        echo "  -> Quét kiểm tra $mname..."
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
        # Chuẩn hóa khoảng trắng và bỏ comment
        local normalized
        normalized=$(echo "$content" | sed -e 's/--.*$//g' | tr '\n' ' ' | tr -s ' ')
        if echo "$normalized" | grep -iqE '\bDELETE\s+FROM\s+[a-zA-Z0-9_]+\s*;'; then
            echo "LỖI AN TOÀN MIGRATION: Phát hiện DELETE không có mệnh đề WHERE trong $mname!" >&2
            return 1
        fi
    done

    echo "KẾT QUẢ MIGRATION: An toàn tuyệt đối. Đạt tiêu chuẩn kiểm tra."
    return 0
}

# Test invocation if arguments provided
if [ $# -ge 2 ]; then
    check_migration_safety "$1" "$2"
fi
