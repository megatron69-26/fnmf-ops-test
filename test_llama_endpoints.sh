#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== 1. LLAMA-SERVER HEALTH ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8080/health"
echo ""

echo "=== 2. LLAMA-SERVER V1/MODELS ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8080/v1/models"
echo ""

echo "=== 3. SIMPLE COMPLETION TEST VIA LOOPBACK ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in Vietnamese in 2 words\"}],\"max_tokens\":10}'"
echo ""
