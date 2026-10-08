#!/bin/bash
set -euo pipefail

VERIFY_DIR="/c/Users/khoid/AppData/Local/Temp/fnmf_release_verify_$$"
mkdir -p "$VERIFY_DIR/backend" "$VERIFY_DIR/app"

cleanup() {
    rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

echo "=== 1. KIỂM TRA COMMIT CỦA TAG TRÊN GITHUB REMOTE ==="
BACKEND_PEELED=$(cd /c/Users/khoid/Projects/fnmf-backend-test && git ls-remote origin 'refs/tags/v1.2.2-pre^{}' | awk '{print $1}')
if [ -z "$BACKEND_PEELED" ]; then
    BACKEND_PEELED=$(cd /c/Users/khoid/Projects/fnmf-backend-test && git ls-remote origin 'refs/tags/v1.2.2-pre' | awk '{print $1}')
fi
echo "Backend remote tag commit: $BACKEND_PEELED"
echo "Kỳ vọng commit backend   : 6a146815871f83ff6704c99e04462384f17c16a5"
if [ "$BACKEND_PEELED" = "6a146815871f83ff6704c99e04462384f17c16a5" ]; then
    echo "OK: Tag backend trỏ chính xác commit 6a14681!"
else
    echo "LỖI: Tag backend không khớp commit kỳ vọng!" >&2
    exit 1
fi

APP_PEELED=$(cd /c/Users/khoid/Projects/fnmf-app-test && git ls-remote origin 'refs/tags/v1.1.30-pre^{}' | awk '{print $1}')
if [ -z "$APP_PEELED" ]; then
    APP_PEELED=$(cd /c/Users/khoid/Projects/fnmf-app-test && git ls-remote origin 'refs/tags/v1.1.30-pre' | awk '{print $1}')
fi
echo "App remote tag commit    : $APP_PEELED"
echo "Kỳ vọng commit app        : 89330f0740722dbdc6a19b56ebae4fcb75010a82"
if [ "$APP_PEELED" = "89330f0740722dbdc6a19b56ebae4fcb75010a82" ]; then
    echo "OK: Tag app trỏ chính xác commit 89330f0!"
else
    echo "LỖI: Tag app không khớp commit kỳ vọng!" >&2
    exit 1
fi

echo ""
echo "=== 2. TẢI VỀ VÀ KIỂM TRA HASH ARTIFACT BACKEND TỪ GITHUB RELEASE ==="
cd "$VERIFY_DIR/backend"
gh release download v1.2.2-pre --repo megatron69-26/fnmf-backend-test
ls -lh
sha256sum -c *.sha256

echo ""
echo "=== 3. TẢI VỀ VÀ KIỂM TRA HASH ARTIFACT APP TỪ GITHUB RELEASE ==="
cd "$VERIFY_DIR/app"
gh release download v1.1.30-pre --repo megatron69-26/fnmf-app-test
ls -lh
sha256sum -c *.sha256

echo ""
echo "=== 4. THÔNG TIN METADATA CỦA HAI PRERELEASE TRÊN GITHUB ==="
gh release view v1.2.2-pre --repo megatron69-26/fnmf-backend-test --json isPrerelease,tagName,targetCommitish,url,assets
gh release view v1.1.30-pre --repo megatron69-26/fnmf-app-test --json isPrerelease,tagName,targetCommitish,url,assets

echo ""
echo "=== 5. KIỂM TRA TÍNH RIÊNG TƯ (PRIVATE) CỦA HAI REPO ==="
gh repo view megatron69-26/fnmf-backend-test --json visibility,isPrivate
gh repo view megatron69-26/fnmf-app-test --json visibility,isPrivate

echo ""
echo "=========================================================="
echo "   TẤT CẢ KIỂM TRA ĐỐI SOÁT GITHUB PRERELEASE HOÀN TẤT    "
echo "=========================================================="
