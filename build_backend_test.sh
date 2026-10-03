#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    FNMF BACKEND TEST BUILD & TEST PIPELINE (GIT-BASED AUTOMATION)              "
echo "================================================================================"
echo "Thời gian bắt đầu: $(date)"

EXPECTED_COMMIT="20c79b75a2b3decebbfea8d8a71e5fc00c072d9e"
WORKSPACE_DIR="/c/Users/khoid/Projects/build-workspaces/backend-test"
ARTIFACT_DIR="/c/Users/khoid/Projects/artifacts/backend"
GIT_LOCAL_SRC="/c/Users/khoid/Projects/fnmf-backend-test"

mkdir -p "$WORKSPACE_DIR"
mkdir -p "$ARTIFACT_DIR"

RAW_LOG="${ARTIFACT_DIR}/build_backend_raw.log"
MASKED_LOG="${ARTIFACT_DIR}/build_backend_masked.log"
rm -f "$RAW_LOG" "$MASKED_LOG"

mask_secrets() {
    sed -E \
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
}

echo "[1/6] Chuẩn bị workspace độc lập ngoài repo..."
echo "Workspace: $WORKSPACE_DIR"
if [ ! -d "$WORKSPACE_DIR/.git" ]; then
    echo "Khởi tạo clone từ Git repo nguồn ($GIT_LOCAL_SRC)..."
    git clone "$GIT_LOCAL_SRC" "$WORKSPACE_DIR"
fi

cd "$WORKSPACE_DIR"
echo "[2/6] Fetch và Checkout commit chỉ định..."
git fetch "$GIT_LOCAL_SRC" main
git checkout "$EXPECTED_COMMIT"

ACTUAL_COMMIT=$(git rev-parse HEAD)
echo "Commit thực tế: $ACTUAL_COMMIT"
echo "Commit kỳ vọng: $EXPECTED_COMMIT"

if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
    echo "LỖI: Commit SHA không khớp! Dừng quy trình ngay lập tức." >&2
    exit 1
fi
echo "XÁC NHẬN: Commit SHA hoàn toàn chính xác ($ACTUAL_COMMIT)."

echo "[3/6] Thiết lập toolchain (JDK 17 Eclipse Adoptium & Maven 3.9.16)..."
export JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
export PATH="/usr/bin:/c/tools/apache-maven-3.9.16/bin:$PATH"

mvn.cmd -v | tee -a "$RAW_LOG"

BYTEBUDDY_AGENT="C:/Users/khoid/.m2/repository/net/bytebuddy/byte-buddy-agent/1.14.19/byte-buddy-agent-1.14.19.jar"
echo "Sử dụng ByteBuddy Agent: $BYTEBUDDY_AGENT"
mvn.cmd clean test "-DargLine=-javaagent:$BYTEBUDDY_AGENT" 2>&1 | tee -a "$RAW_LOG"

echo "[5/6] Đối soát kết quả kiểm thử từ Surefire Reports..."
SUREFIRE_DIR="$WORKSPACE_DIR/target/surefire-reports"
if [ ! -d "$SUREFIRE_DIR" ]; then
    echo "LỖI: Không tìm thấy thư mục surefire-reports!" >&2
    exit 1
fi

TOTAL_TESTS=0
TOTAL_FAILURES=0
TOTAL_ERRORS=0
TOTAL_SKIPPED=0
SUITE_COUNT=0

for report in "$SUREFIRE_DIR"/*.txt; do
    if [ -f "$report" ]; then
        SUMMARY_LINE=$(grep "Tests run:" "$report" | tail -n 1 || true)
        if [ -n "$SUMMARY_LINE" ]; then
            RUN=$(echo "$SUMMARY_LINE" | sed -n 's/.*Tests run: \([0-9]*\).*/\1/p')
            FAIL=$(echo "$SUMMARY_LINE" | sed -n 's/.*Failures: \([0-9]*\).*/\1/p')
            ERR=$(echo "$SUMMARY_LINE" | sed -n 's/.*Errors: \([0-9]*\).*/\1/p')
            SKIP=$(echo "$SUMMARY_LINE" | sed -n 's/.*Skipped: \([0-9]*\).*/\1/p')
            
            [ -n "$RUN" ] && TOTAL_TESTS=$((TOTAL_TESTS + RUN))
            [ -n "$FAIL" ] && TOTAL_FAILURES=$((TOTAL_FAILURES + FAIL))
            [ -n "$ERR" ] && TOTAL_ERRORS=$((TOTAL_ERRORS + ERR))
            [ -n "$SKIP" ] && TOTAL_SKIPPED=$((TOTAL_SKIPPED + SKIP))
            SUITE_COUNT=$((SUITE_COUNT + 1))
        fi
    fi
done

echo "=========================================================="
echo "KẾT QUẢ KIỂM THỬ BACKEND TEST:"
echo " - Tổng số suites: $SUITE_COUNT"
echo " - Tổng số bài test đã chạy: $TOTAL_TESTS"
echo " - Thất bại (Failures): $TOTAL_FAILURES"
echo " - Lỗi (Errors): $TOTAL_ERRORS"
echo " - Bỏ qua (Skipped): $TOTAL_SKIPPED"
echo "=========================================================="

if [ "$TOTAL_TESTS" -eq 0 ] || [ "$TOTAL_FAILURES" -ne 0 ] || [ "$TOTAL_ERRORS" -ne 0 ]; then
    echo "LỖI: Kiểm thử Backend không đạt tiêu chuẩn (Suites: $SUITE_COUNT, Tests: $TOTAL_TESTS, Failures: $TOTAL_FAILURES, Errors: $TOTAL_ERRORS)!" >&2
    exit 1
fi

echo "[6/6] Đóng gói JAR artifact và tính SHA-256..."
mvn.cmd package -DskipTests 2>&1 | tee -a "$RAW_LOG"

SOURCE_JAR="$WORKSPACE_DIR/target/llm-gateway-1.1.17.jar"
if [ ! -f "$SOURCE_JAR" ]; then
    echo "LỖI: Tệp JAR đầu ra không tồn tại tại $SOURCE_JAR!" >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_JAR_NAME="fnmf-backend-test-20c79b7_${TIMESTAMP}.jar"
DEST_JAR="$ARTIFACT_DIR/$TARGET_JAR_NAME"
LATEST_LINK="$ARTIFACT_DIR/fnmf-backend-test-latest.jar"

cp "$SOURCE_JAR" "$DEST_JAR"
cp "$SOURCE_JAR" "$LATEST_LINK"

JAR_SHA256=$(sha256sum "$DEST_JAR" | cut -d' ' -f1)
echo "$JAR_SHA256 *$TARGET_JAR_NAME" > "${DEST_JAR}.sha256"
echo "$JAR_SHA256 *fnmf-backend-test-latest.jar" > "${LATEST_LINK}.sha256"

JAR_SIZE=$(wc -c < "$DEST_JAR")

echo "Mã hóa và lưu trữ log đã che thông tin nhạy cảm..."
mask_secrets < "$RAW_LOG" > "$MASKED_LOG"
rm -f "$RAW_LOG"

echo "================================================================================"
echo "    KẾT QUẢ BUILD BACKEND TEST THÀNH CÔNG                                       "
echo "================================================================================"
echo "Commit Git      : $ACTUAL_COMMIT"
echo "Số bài test đạt : $TOTAL_TESTS tests / $SUITE_COUNT suites (0 failures, 0 errors, $TOTAL_SKIPPED skipped)"
echo "Tệp Artifact    : $DEST_JAR"
echo "Dung lượng JAR  : $JAR_SIZE bytes"
echo "Checksum SHA256 : $JAR_SHA256"
echo "Tệp Log đã che  : $MASKED_LOG"
echo "================================================================================"
