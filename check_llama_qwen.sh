#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== CHECK BASHRC ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux cat /data/data/com.termux/files/home/.bashrc" || true

echo "=== CHECK LLAMA_SERVER.LOG ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux tail -n 25 /data/data/com.termux/files/home/llama_server.log" || true

echo "=== CHECK QWEN_SERVER.LOG ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux tail -n 25 /data/data/com.termux/files/home/qwen_server.log" || true

echo "=== CHECK MODELS DIR ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ls -lh /data/data/com.termux/files/home/models" || true

echo "=== CHECK PID 2381 ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ls -l /proc/2381/exe" || true
"$ADB" -s "$DEVICE" shell "run-as com.termux ls -l /proc/2381/cwd" || true
"$ADB" -s "$DEVICE" shell "run-as com.termux tr '\0' ' ' < /proc/2381/cmdline" || true
echo ""
"$ADB" -s "$DEVICE" shell "run-as com.termux which llama-server" || true
"$ADB" -s "$DEVICE" shell "run-as com.termux find /data/data/com.termux/files/usr/bin -name '*llama*'" || true
