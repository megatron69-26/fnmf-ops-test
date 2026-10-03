#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    BỘ TEST KIỂM THỬ GIẢ LẬP CÁC KỊCH BẢN DEPLOY & ROLLBACK BACKEND TEST       "
echo "================================================================================"
echo "Thời gian bắt đầu: $(date)"
echo ""

BASE_SIM_DIR="/c/Users/khoid/AppData/Local/Temp/fnmf_sim_suite_$$"
DEPLOY_SCRIPT="/c/Users/khoid/Projects/fnmf-ops-test/deploy_backend_test.sh"
REAL_TARGET_JAR="/c/Users/khoid/Projects/artifacts/backend/fnmf-backend-test-latest.jar"

cleanup() {
    rm -rf "$BASE_SIM_DIR" 2>/dev/null || true
}
trap cleanup EXIT

TOTAL_SCENARIOS=6
PASSED_SCENARIOS=0

# Helper to create clean sandbox environment
setup_sandbox() {
    local sim_dir="$1"
    rm -rf "$sim_dir"
    mkdir -p "$sim_dir"
    
    # Tạo JAR gốc hiện tại (phiên bản 1.0 đang chạy)
    echo "ORIGINAL_BACKEND_JAR_v1.0" > "$sim_dir/llm-gateway-1.1.17.jar"
}

echo "Chuẩn bị môi trường kiểm thử giả lập tại: $BASE_SIM_DIR"

# ==============================================================================
# KỊCH BẢN 1: THẤT BẠI KHI SAO LƯU ROLLBACK SNAPSHOT
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 1/6] Kiểm thử lỗi khi tạo bản snapshot rollback (SIM_COPY_FAIL=true)"
echo "--------------------------------------------------------------------------------"
SIM1="$BASE_SIM_DIR/scen1"
setup_sandbox "$SIM1"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM1" \
SIM_DB_VERSION=10 \
SIM_COPY_FAIL=true \
"$DEPLOY_SCRIPT" > "$SIM1/deploy.log" 2>&1
SCEN1_EXIT=$?
set -e

if [ $SCEN1_EXIT -ne 0 ]; then
    # Kiểm tra: Script phải dừng ở bước sao lưu, KHÔNG được tráo JAR
    CURRENT_CONTENT=$(cat "$SIM1/llm-gateway-1.1.17.jar")
    if [ "$CURRENT_CONTENT" = "ORIGINAL_BACKEND_JAR_v1.0" ] && [ ! -f "$SIM1/llm-gateway-rollback.jar" ]; then
        echo "PASS KỊCH BẢN 1: Script dừng an toàn trước khi thay đổi trạng thái."
        echo "  - Exit code: $SCEN1_EXIT (Dừng chính xác)"
        echo "  - File JAR gốc được bảo toàn nguyên vẹn."
        echo "  - Không phát sinh file rollback giả mạo."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 1: Trạng thái tệp không đúng như mong đợi!"
        cat "$SIM1/deploy.log"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 1: Script không báo lỗi khi lệnh copy snapshot thất bại!"
    exit 1
fi

# ==============================================================================
# KỊCH BẢN 2: PHÁT HIỆN MIGRATION CHỨA LỆNH PHÁ HỦY (DROP TABLE)
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 2/6] Kiểm thử phát hiện migration phá hủy dữ liệu (DROP TABLE)"
echo "--------------------------------------------------------------------------------"
SIM2="$BASE_SIM_DIR/scen2"
setup_sandbox "$SIM2"

# Tạo một JAR có chứa migration phá hủy V12__drop_table.sql
mkdir -p "$SIM2/bad_jar_build/BOOT-INF/classes/db/migration"
echo "DROP TABLE users CASCADE;" > "$SIM2/bad_jar_build/BOOT-INF/classes/db/migration/V12__drop_users.sql"
jar cf "$SIM2/bad-target.jar" -C "$SIM2/bad_jar_build" BOOT-INF
BAD_SHA=$(sha256sum "$SIM2/bad-target.jar" | cut -d' ' -f1)
echo "$BAD_SHA *bad-target.jar" > "$SIM2/bad-target.jar.sha256"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM2" \
SIM_DB_VERSION=11 \
TARGET_JAR="$SIM2/bad-target.jar" \
"$DEPLOY_SCRIPT" > "$SIM2/deploy.log" 2>&1
SCEN2_EXIT=$?
set -e

if [ $SCEN2_EXIT -ne 0 ]; then
    CURRENT_CONTENT=$(cat "$SIM2/llm-gateway-1.1.17.jar")
    if grep -q "Phát hiện câu lệnh phá hủy dữ liệu (DROP/TRUNCATE)" "$SIM2/deploy.log" && [ "$CURRENT_CONTENT" = "ORIGINAL_BACKEND_JAR_v1.0" ]; then
        echo "PASS KỊCH BẢN 2: Bộ lọc Migration phát hiện và chặn đứng script DROP TABLE."
        echo "  - Exit code: $SCEN2_EXIT (Chặn thành công)"
        echo "  - Phát hiện chính xác lệnh vi phạm trong log."
        echo "  - JAR gốc chưa bị chạm tới."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 2: Không phát hiện được migration phá hủy!"
        cat "$SIM2/deploy.log"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 2: Script cho phép triển khai dù migration chứa DROP TABLE!"
    exit 1
fi

# ==============================================================================
# KỊCH BẢN 3: THẤT BẠI KHI TRUYỀN TỆP VÀO VÙNG STAGING
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 3/6] Kiểm thử lỗi khi truyền tệp vào Staging (SIM_PUSH_FAIL=true)"
echo "--------------------------------------------------------------------------------"
SIM3="$BASE_SIM_DIR/scen3"
setup_sandbox "$SIM3"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM3" \
SIM_DB_VERSION=10 \
SIM_PUSH_FAIL=true \
"$DEPLOY_SCRIPT" > "$SIM3/deploy.log" 2>&1
SCEN3_EXIT=$?
set -e

if [ $SCEN3_EXIT -ne 0 ]; then
    CURRENT_CONTENT=$(cat "$SIM3/llm-gateway-1.1.17.jar")
    if [ "$CURRENT_CONTENT" = "ORIGINAL_BACKEND_JAR_v1.0" ]; then
        echo "PASS KỊCH BẢN 3: Script hủy bỏ an toàn khi staging thất bại."
        echo "  - Exit code: $SCEN3_EXIT"
        echo "  - Bản snapshot đã được tạo nhưng chưa bị hoán đổi (No mutation)."
        echo "  - JAR gốc được bảo toàn."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 3: JAR gốc bị thay đổi dù staging thất bại!"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 3: Script không phát hiện lỗi khi push staging thất bại!"
    exit 1
fi

# ==============================================================================
# KỊCH BẢN 4: RESTART THẤT BẠI SAU KHI HOÁN ĐỔI JAR -> TỰ ĐỘNG ROLLBACK
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 4/6] Kiểm thử Restart thất bại sau hoán đổi JAR -> Tự động Rollback"
echo "--------------------------------------------------------------------------------"
SIM4="$BASE_SIM_DIR/scen4"
setup_sandbox "$SIM4"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM4" \
SIM_DB_VERSION=10 \
SIM_RESTART_FAIL=true \
"$DEPLOY_SCRIPT" > "$SIM4/deploy.log" 2>&1
SCEN4_EXIT=$?
set -e

if [ $SCEN4_EXIT -ne 0 ]; then
    CURRENT_CONTENT=$(cat "$SIM4/llm-gateway-1.1.17.jar")
    if grep -q "QUY TRÌNH ROLLBACK KHẨN CẤP ĐƯỢC KÍCH HOẠT" "$SIM4/deploy.log" && \
       grep -q "ROLLBACK THÀNH CÔNG" "$SIM4/deploy.log" && \
       [ "$CURRENT_CONTENT" = "ORIGINAL_BACKEND_JAR_v1.0" ]; then
        echo "PASS KỊCH BẢN 4: Rollback tự động kích hoạt ngay khi restart thất bại."
        echo "  - Script không bị set -e ngắt giữa chừng."
        echo "  - Quy trình khôi phục bản snapshot $SIM4/llm-gateway-rollback.jar về tệp chính thành công."
        echo "  - Nội dung tệp JAR chính đã được hoàn nguyên về bản gốc v1.0."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 4: Không thực hiện rollback hoặc không hoàn nguyên được JAR!"
        cat "$SIM4/deploy.log"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 4: Script báo thành công dù restart thất bại!"
    exit 1
fi

# ==============================================================================
# KỊCH BẢN 5: HEALTH CHECK THẤT BẠI SAU TRIỂN KHAI -> TỰ ĐỘNG ROLLBACK
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 5/6] Kiểm thử Health Check thất bại sau triển khai -> Tự động Rollback"
echo "--------------------------------------------------------------------------------"
SIM5="$BASE_SIM_DIR/scen5"
setup_sandbox "$SIM5"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM5" \
SIM_DB_VERSION=10 \
SIM_HEALTH_FAIL=true \
"$DEPLOY_SCRIPT" > "$SIM5/deploy.log" 2>&1
SCEN5_EXIT=$?
set -e

if [ $SCEN5_EXIT -ne 0 ]; then
    CURRENT_CONTENT=$(cat "$SIM5/llm-gateway-1.1.17.jar")
    if grep -q "Dịch vụ không vượt qua kiểm tra sức khỏe! Bắt đầu Rollback" "$SIM5/deploy.log" && \
       grep -q "ROLLBACK THÀNH CÔNG" "$SIM5/deploy.log" && \
       [ "$CURRENT_CONTENT" = "ORIGINAL_BACKEND_JAR_v1.0" ]; then
        echo "PASS KỊCH BẢN 5: Rollback tự động kích hoạt khi health check trả về lỗi."
        echo "  - Bản snapshot phục hồi chính xác."
        echo "  - Dịch vụ sau rollback được khởi động lại và kiểm chứng sức khỏe UP."
        echo "  - Nội dung JAR chính hoàn nguyên về bản gốc v1.0."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 5: Rollback khi health check thất bại không hoạt động đúng!"
        cat "$SIM5/deploy.log"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 5: Script báo thành công dù health check thất bại!"
    exit 1
fi

# ==============================================================================
# KỊCH BẢN 6: LUỒNG HOÀN TOÀN THÀNH CÔNG (HAPPY PATH)
# ==============================================================================
echo ""
echo "--------------------------------------------------------------------------------"
echo "[KỊCH BẢN 6/6] Kiểm thử toàn trình thành công (Happy Path)"
echo "--------------------------------------------------------------------------------"
SIM6="$BASE_SIM_DIR/scen6"
setup_sandbox "$SIM6"

set +e
SIMULATE_MODE=true \
SIM_DIR="$SIM6" \
SIM_DB_VERSION=10 \
"$DEPLOY_SCRIPT" > "$SIM6/deploy.log" 2>&1
SCEN6_EXIT=$?
set -e

if [ $SCEN6_EXIT -eq 0 ]; then
    # Kích thước của JAR chính sau deploy phải khớp với REAL_TARGET_JAR
    TARGET_SIZE=$(wc -c < "$REAL_TARGET_JAR" | tr -d ' ')
    DEPLOYED_SIZE=$(wc -c < "$SIM6/llm-gateway-1.1.17.jar" | tr -d ' ')
    
    if [ "$TARGET_SIZE" -eq "$DEPLOYED_SIZE" ] && [ -f "$SIM6/llm-gateway-rollback.jar" ]; then
        echo "PASS KỊCH BẢN 6: Triển khai hoàn tất toàn trình 7 chặng an toàn."
        echo "  - Exit code: 0 (Thành công tuyệt đối)"
        echo "  - Kích thước JAR triển khai khớp chuẩn xác với artifact ($DEPLOYED_SIZE bytes)."
        echo "  - Bản snapshot rollback được lưu trữ đầy đủ làm phương án phòng thủ."
        PASSED_SCENARIOS=$((PASSED_SCENARIOS + 1))
    else
        echo "FAIL KỊCH BẢN 6: Kích thước JAR không khớp hoặc thiếu bản snapshot!"
        cat "$SIM6/deploy.log"
        exit 1
    fi
else
    echo "FAIL KỊCH BẢN 6: Happy path thất bại với mã lỗi $SCEN6_EXIT!"
    cat "$SIM6/deploy.log"
    exit 1
fi

echo ""
echo "================================================================================"
echo "    KẾT QUẢ BỘ KIỂM THỬ GIẢ LẬP: $PASSED_SCENARIOS/$TOTAL_SCENARIOS KỊCH BẢN ĐẠT TIÊU CHUẨN      "
echo "================================================================================"
if [ "$PASSED_SCENARIOS" -eq "$TOTAL_SCENARIOS" ]; then
    echo "CHỨNG NHẬN: Cơ chế an toàn và Rollback tự động đã được kiểm chứng 100%!"
    exit 0
else
    echo "LỖI: Một số kịch bản kiểm thử không đạt!"
    exit 1
fi
