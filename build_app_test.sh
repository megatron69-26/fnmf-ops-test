#!/bin/bash
set -euo pipefail

echo "================================================================================"
echo "    FNMF ANDROID APP TEST BUILD & TEST PIPELINE (GIT-BASED AUTOMATION)          "
echo "================================================================================"
echo "Thời gian bắt đầu: $(date)"

EXPECTED_COMMIT="ebf2fdd55d3e57f3c5428585c1e23821d10a30e0"
WORKSPACE_DIR="/c/Users/khoid/Projects/build-workspaces/app-test"
ARTIFACT_DIR="/c/Users/khoid/Projects/artifacts/app"
GIT_REMOTE_SRC="https://github.com/megatron69-26/fnmf-app-test.git"
GIT_LOCAL_SRC="/c/Users/khoid/Projects/fnmf-app-test"

mkdir -p "$WORKSPACE_DIR"
mkdir -p "$ARTIFACT_DIR"

RAW_LOG="${ARTIFACT_DIR}/build_app_raw.log"
MASKED_LOG="${ARTIFACT_DIR}/build_app_masked.log"
rm -f "$RAW_LOG" "$MASKED_LOG"

mask_secrets() {
    sed -E \
      -e 's/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/[REDACTED_JWT_TOKEN]/g' \
      -e 's/([aA]uthorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED_TOKEN]/g' \
      -e 's/([pP]assword[:=][[:space:]]*)[^& ,;"]+/\1[REDACTED]/g' \
      -e 's/"password"[[:space:]]*:[[:space:]]*"[^"]+"/"password":"[REDACTED]"/g' \
      -e 's/RELEASE_STORE_PASSWORD=[^& ,;]*/RELEASE_STORE_PASSWORD=[REDACTED]/g' \
      -e 's/RELEASE_KEY_PASSWORD=[^& ,;]*/RELEASE_KEY_PASSWORD=[REDACTED]/g' \
      -e 's/([aA]pi[kK]ey[:=][[:space:]]*)[^& ,;"]+/\1[REDACTED_KEY]/g' \
      -e 's/(key=[a-zA-Z0-9_-]{8,})/key=[REDACTED_KEY]/g'
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
echo "XÁC NHẬN: Commit SHA hoàn toàn chính xác ($ACTUAL_COMMIT)."

echo "[3/6] Thiết lập toolchain (JDK 17 Eclipse Adoptium & Android SDK)..."
export JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
export ANDROID_HOME="C:/Users/khoid/AppData/Local/Android/Sdk"
export ANDROID_SDK_ROOT="C:/Users/khoid/AppData/Local/Android/Sdk"
export TEMP="C:\Users\khoid\AppData\Local\Temp"
export TMP="C:\Users\khoid\AppData\Local\Temp"
export USERPROFILE="C:\Users\khoid"
export PATH="/usr/bin:$JAVA_HOME/bin:$PATH"

if [ ! -f "local.properties" ]; then
    echo "Tạo local.properties trỏ đến Android SDK..."
    echo 'sdk.dir=C\:\\Users\\khoid\\AppData\\Local\\Android\\Sdk' > local.properties
fi

chmod +x gradlew

echo "[4/6] Chạy toàn bộ Unit tests (./gradlew testDebugUnitTest)..."
./gradlew --no-daemon testDebugUnitTest 2>&1 | tee -a "$RAW_LOG"

echo "[5/6] Đối soát kết quả kiểm thử từ JUnit XML Reports..."
TEST_RESULTS_DIR="$WORKSPACE_DIR/app/build/test-results/testDebugUnitTest"
if [ ! -d "$TEST_RESULTS_DIR" ]; then
    echo "LỖI: Không tìm thấy thư mục test-results!" >&2
    exit 1
fi

TOTAL_TESTS=0
TOTAL_FAILURES=0
TOTAL_ERRORS=0
TOTAL_SKIPPED=0
SUITE_COUNT=0

for xml in "$TEST_RESULTS_DIR"/TEST-*.xml; do
    if [ -f "$xml" ]; then
        SUITE_COUNT=$((SUITE_COUNT + 1))
        RUN=$(sed -n 's/.*tests="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)
        FAIL=$(sed -n 's/.*failures="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)
        ERR=$(sed -n 's/.*errors="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)
        SKIP=$(sed -n 's/.*skipped="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)
        
        [ -n "$RUN" ] && TOTAL_TESTS=$((TOTAL_TESTS + RUN))
        [ -n "$FAIL" ] && TOTAL_FAILURES=$((TOTAL_FAILURES + FAIL))
        [ -n "$ERR" ] && TOTAL_ERRORS=$((TOTAL_ERRORS + ERR))
        [ -n "$SKIP" ] && TOTAL_SKIPPED=$((TOTAL_SKIPPED + SKIP))
    fi
done

echo "=========================================================="
echo "KẾT QUẢ KIỂM THỬ ANDROID APP TEST:"
echo " - Tổng số suites: $SUITE_COUNT"
echo " - Tổng số bài test đã chạy: $TOTAL_TESTS"
echo " - Thất bại (Failures): $TOTAL_FAILURES"
echo " - Lỗi (Errors): $TOTAL_ERRORS"
echo " - Bỏ qua (Skipped): $TOTAL_SKIPPED"
echo "=========================================================="

if [ "$TOTAL_TESTS" -eq 0 ] || [ "$TOTAL_FAILURES" -ne 0 ] || [ "$TOTAL_ERRORS" -ne 0 ]; then
    echo "LỖI: Kiểm thử Android App không đạt tiêu chuẩn (Suites: $SUITE_COUNT, Tests: $TOTAL_TESTS, Failures: $TOTAL_FAILURES, Errors: $TOTAL_ERRORS)!" >&2
    exit 1
fi

echo "[6/6] Build APK (assembleDebug) và tính SHA-256..."
./gradlew --no-daemon assembleDebug 2>&1 | tee -a "$RAW_LOG"

SOURCE_APK="$WORKSPACE_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$SOURCE_APK" ]; then
    echo "LỖI: Tệp APK đầu ra không tồn tại tại $SOURCE_APK!" >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_APK_NAME="fnmf-app-debug-ebf2fdd_${TIMESTAMP}.apk"
DEST_APK="$ARTIFACT_DIR/$TARGET_APK_NAME"
LATEST_LINK="$ARTIFACT_DIR/fnmf-app-debug-latest.apk"

cp "$SOURCE_APK" "$DEST_APK"
cp "$SOURCE_APK" "$LATEST_LINK"

APK_SHA256=$(sha256sum "$DEST_APK" | cut -d' ' -f1)
echo "$APK_SHA256 *$TARGET_APK_NAME" > "${DEST_APK}.sha256"
echo "$APK_SHA256 *fnmf-app-debug-latest.apk" > "${LATEST_LINK}.sha256"

APK_SIZE=$(wc -c < "$DEST_APK")

echo "================================================================================"
echo "    KẾT QUẢ BUILD ANDROID APP TEST THÀNH CÔNG                                   "
echo "================================================================================"
echo "Nguồn Git Remote: $GIT_REMOTE_SRC"
echo "Commit Git      : $ACTUAL_COMMIT"
echo "Số bài test đạt : $TOTAL_TESTS tests / $SUITE_COUNT suites (0 failures, 0 errors, $TOTAL_SKIPPED skipped)"
echo "Tệp Artifact    : $DEST_APK"
echo "Dung lượng APK  : $APK_SIZE bytes"
echo "Checksum SHA256 : $APK_SHA256"
echo "Tệp Log đã che  : $MASKED_LOG"
echo "================================================================================"
