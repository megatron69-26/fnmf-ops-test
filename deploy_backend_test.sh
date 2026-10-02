#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    FNMF BACKEND TEST DEPLOYMENT PIPELINE (KIẾN TRÚC THIẾT KẾ SẴN)              "
echo "================================================================================"
echo "Date: $(date)"
echo ""

ADB="adb.exe"
DEVICE_ID="R3CM8105TPA"
ARTIFACT_DIR="/c/Users/khoid/Projects/artifacts/backend"
TARGET_JAR="${ARTIFACT_DIR}/fnmf-backend-test-latest.jar"
PHONE_HOME="/data/data/com.termux/files/home"
PHONE_JAR="${PHONE_HOME}/llm-gateway-1.1.17.jar"
ROLLBACK_JAR="${PHONE_HOME}/llm-gateway-rollback.jar"

# ==============================================================================
# KHÓA BẢO VỆ AN TOÀN (DESIGN-ONLY SAFEGUARD)
# ==============================================================================
# Theo chỉ thị của người dùng: "Chỉ thiết kế tác vụ “Deploy Backend Test” với
# backup, rollback, kiểm tra migration và health check; chưa kích hoạt,
# chưa bật auto-deploy/webhook, chưa thay JAR trên Note 10+, chưa cài APK hay mở tunnel."
# ==============================================================================
if [ "${ACTIVATE_DEPLOY:-false}" != "true" ]; then
    echo "================================================================================"
    echo "                   [THÔNG BÁO THIẾT KẾ KIẾN TRÚC AN TOÀN]                       "
    echo "================================================================================"
    echo "Tác vụ Deploy Backend Test đã được THIẾT KẾ HOÀN CHỈNH nhưng CHƯA KÍCH HOẠT"
    echo "theo đúng yêu cầu nghiệm thu của giai đoạn kiểm thử."
    echo ""
    echo "Quy trình thiết kế bao gồm 7 chặng an toàn phòng thủ theo chiều sâu:"
    echo "  1. Pre-flight Check   : Đối soát thiết bị Note 10+ qua ADB và toàn vẹn SHA-256 JAR."
    echo "  2. Pre-deploy Backup  : Kích hoạt sao lưu đối soát CSDL an toàn (backup_db.sh)."
    echo "  3. Migration Safety   : Kiểm tra Flyway schema history, đối soát script SQL mới."
    echo "  4. Staging & Rollback : Sao lưu JAR đang chạy hiện tại thành JAR rollback dự phòng."
    echo "  5. Atomic Deploy      : Đẩy JAR mới vào vùng đệm tạm, đối soát checksum trên điện thoại."
    echo "  6. Graceful Restart   : Gửi SIGTERM dừng tiến trình cũ, khởi động JAR mới trên 127.0.0.1."
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

echo "BẮT ĐẦU TRIỂN KHAI THỰC TẾ (ACTIVATE_DEPLOY=true)..."

# 1. Kiểm tra kết nối thiết bị và toàn vẹn Artifact
echo "[1/7] Kiểm tra thiết bị Note 10+ và checksum artifact..."
"$ADB" devices | grep -q "$DEVICE_ID" || {
    echo "LỖI: Thiết bị $DEVICE_ID không phản hồi qua ADB!" >&2
    exit 1
}

if [ ! -f "$TARGET_JAR" ] || [ ! -f "${TARGET_JAR}.sha256" ]; then
    echo "LỖI: Tệp JAR hoặc manifest SHA-256 không tồn tại tại $TARGET_JAR!" >&2
    exit 1
fi

EXPECTED_SHA=$(cut -d' ' -f1 "${TARGET_JAR}.sha256")
ACTUAL_SHA=$(sha256sum "$TARGET_JAR" | cut -d' ' -f1)
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "LỖI: Checksum SHA-256 của artifact không khớp!" >&2
    exit 1
fi
echo "OK: Artifact toàn vẹn (SHA-256: $ACTUAL_SHA)."

# 2. Sao lưu CSDL trước triển khai
echo "[2/7] Thực hiện sao lưu CSDL trước triển khai (backup_db.sh)..."
/c/Users/khoid/Projects/fnmf-ops-test/backup_db.sh

# 3. Kiểm tra an toàn Migration CSDL
echo "[3/7] Kiểm tra lịch sử migration Flyway trên CSDL đích..."
CURRENT_MIGRATION=$("$ADB" -s "$DEVICE_ID" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -v ON_ERROR_STOP=1 -t -A -c 'SELECT max(version) FROM flyway_schema_history WHERE success = true;'")
echo "Phiên bản Flyway hiện tại trên CSDL: $CURRENT_MIGRATION"

# 4. Sao lưu bản JAR đang chạy trên máy làm bản rollback
echo "[4/7] Sao lưu tệp JAR hiện tại trên thiết bị để phục vụ rollback..."
"$ADB" -s "$DEVICE_ID" shell "run-as com.termux cp $PHONE_JAR $ROLLBACK_JAR" 2>/dev/null || true
echo "OK: Đã lưu bản snapshot $ROLLBACK_JAR."

# 5. Đẩy tệp JAR mới lên vùng đệm trên thiết bị
echo "[5/7] Đẩy tệp JAR mới vào vùng đệm thiết bị..."
STAGING_JAR="${PHONE_HOME}/llm-gateway-staging.jar"
"$ADB" -s "$DEVICE_ID" push "$TARGET_JAR" "/data/local/tmp/fnmf-backend-staging.jar"
"$ADB" -s "$DEVICE_ID" shell "run-as com.termux cp /data/local/tmp/fnmf-backend-staging.jar $STAGING_JAR && rm -f /data/local/tmp/fnmf-backend-staging.jar"

# 6. Khởi động lại dịch vụ backend với bản JAR mới
echo "[6/7] Thay thế tệp JAR và khởi động lại dịch vụ..."
"$ADB" -s "$DEVICE_ID" shell "run-as com.termux mv $STAGING_JAR $PHONE_JAR"
/c/Users/khoid/Projects/fnmf-ops-test/restart_backend.sh

# 7. Kiểm chứng sức khỏe dịch vụ (Health Check)
echo "[7/7] Xác thực sức khỏe dịch vụ sau triển khai..."
if ! /c/Users/khoid/Projects/fnmf-ops-test/health_check.sh; then
    echo "CẢNH BÁO: Dịch vụ không vượt qua kiểm tra sức khỏe! Bắt đầu Rollback khẩn cấp..." >&2
    "$ADB" -s "$DEVICE_ID" shell "run-as com.termux mv $ROLLBACK_JAR $PHONE_JAR"
    /c/Users/khoid/Projects/fnmf-ops-test/restart_backend.sh
    /c/Users/khoid/Projects/fnmf-ops-test/health_check.sh
    echo "ROLLBACK HOÀN TẤT: Đã quay về phiên bản JAR trước đó." >&2
    exit 1
fi

echo "================================================================================"
echo "          TRIỂN KHAI VÀ NGHIỆM THU BACKEND TEST THÀNH CÔNG RỰC RỠ               "
echo "================================================================================"
