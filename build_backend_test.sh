#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    FNMF BACKEND TEST BUILD & TEST PIPELINE (GIT ORIGIN AUTOMATION)             "
echo "================================================================================"
echo "Thời gian bắt đầu: $(date)"

EXPECTED_COMMIT="${EXPECTED_COMMIT:-6a146815871f83ff6704c99e04462384f17c16a5}"
WORKSPACE_DIR="/c/Users/khoid/Projects/build-workspaces/backend-test"
ARTIFACT_DIR="/c/Users/khoid/Projects/artifacts/backend"
GIT_REMOTE_SRC="https://github.com/megatron69-26/fnmf-backend-test.git"
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

# Trap đảm bảo mọi trường hợp thoát (kể cả lỗi) đều mã hóa log thô và xóa file gốc
cleanup_logs() {
    if [ -f "$RAW_LOG" ]; then
        echo "DỌN DẸP LOG: Tự động lọc bí mật và xóa tệp log thô (bảo vệ ngay cả khi build lỗi)..."
        mask_secrets < "$RAW_LOG" > "$MASKED_LOG" 2>/dev/null || true
        rm -f "$RAW_LOG"
    fi
}
trap cleanup_logs EXIT

echo "[1/6] Chuẩn bị workspace độc lập ngoài repo..."
echo "Workspace: $WORKSPACE_DIR"
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=""

if [ ! -d "$WORKSPACE_DIR/.git" ]; then
    echo "Khởi tạo clone trực tiếp từ GitHub Remote ($GIT_REMOTE_SRC)..."
    git clone "$GIT_REMOTE_SRC" "$WORKSPACE_DIR" || git clone "$GIT_LOCAL_SRC" "$WORKSPACE_DIR"
fi

cd "$WORKSPACE_DIR"
git remote set-url origin "$GIT_REMOTE_SRC" 2>/dev/null || true

echo "[2/6] Kéo bản mới trực tiếp từ GitHub Remote (git fetch origin main)..."
git fetch origin main
git checkout "$EXPECTED_COMMIT"

ACTUAL_COMMIT=$(git rev-parse HEAD)
echo "Commit thực tế: $ACTUAL_COMMIT"
echo "Commit kỳ vọng: $EXPECTED_COMMIT"

if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
    echo "LỖI: Commit SHA không khớp! Dừng quy trình ngay lập tức." >&2
    exit 1
fi
echo "XÁC NHẬN: Đã kéo từ origin và xác thực SHA thành công ($ACTUAL_COMMIT)."

echo "[3/6] Thiết lập toolchain (JDK 17 Eclipse Adoptium & Maven 3.9.16)..."
export JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
export PATH="/usr/bin:/c/tools/apache-maven-3.9.16/bin:$PATH"
export TEMP="C:\Users\khoid\AppData\Local\Temp"
export TMP="C:\Users\khoid\AppData\Local\Temp"
export USERPROFILE="C:\Users\khoid"
export MAVEN_OPTS="-Djava.io.tmpdir=C:/Users/khoid/AppData/Local/Temp"

mvn.cmd -v | tee -a "$RAW_LOG"

BYTEBUDDY_AGENT="C:/Users/khoid/.m2/repository/net/bytebuddy/byte-buddy-agent/1.14.19/byte-buddy-agent-1.14.19.jar"
echo "Sử dụng ByteBuddy Agent: $BYTEBUDDY_AGENT"

echo "[4/6] Chạy toàn bộ Unit & Integration tests (mvn.cmd clean test)..."
mvn.cmd clean test "-DargLine=-javaagent:$BYTEBUDDY_AGENT -Djava.io.tmpdir=C:/Users/khoid/AppData/Local/Temp" 2>&1 | tee -a "$RAW_LOG"

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
SHORT_COMMIT=$(echo "$ACTUAL_COMMIT" | cut -c1-7)
TARGET_JAR_NAME="fnmf-backend-test-${SHORT_COMMIT}_${TIMESTAMP}.jar"
DEST_JAR="$ARTIFACT_DIR/$TARGET_JAR_NAME"
LATEST_LINK="$ARTIFACT_DIR/fnmf-backend-test-latest.jar"

cp "$SOURCE_JAR" "$DEST_JAR"
cp "$SOURCE_JAR" "$LATEST_LINK"

JAR_SHA256=$(sha256sum "$DEST_JAR" | cut -d' ' -f1)
echo "$JAR_SHA256 *$TARGET_JAR_NAME" > "${DEST_JAR}.sha256"
echo "$JAR_SHA256 *fnmf-backend-test-latest.jar" > "${LATEST_LINK}.sha256"

JAR_SIZE=$(wc -c < "$DEST_JAR")

echo "================================================================================"
echo "    KẾT QUẢ BUILD BACKEND TEST THÀNH CÔNG                                       "
echo "================================================================================"
echo "Nguồn Git Remote: $GIT_REMOTE_SRC"
echo "Commit Git      : $ACTUAL_COMMIT"
echo "Số bài test đạt : $TOTAL_TESTS tests / $SUITE_COUNT suites (0 failures, 0 errors, $TOTAL_SKIPPED skipped)"
echo "Tệp Artifact    : $DEST_JAR"
echo "Dung lượng JAR  : $JAR_SIZE bytes"
echo "Checksum SHA256 : $JAR_SHA256"
echo "Tệp Log đã che  : $MASKED_LOG"
echo "================================================================================"
