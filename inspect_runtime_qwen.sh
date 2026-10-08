#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== 1. ADB DEVICES ==="
"$ADB" devices

echo "=== 2. TERMUX PROCESSES ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ps -ef"

echo "=== 3. TERMUX FILES IN HOME ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ls -la /data/data/com.termux/files/home"

echo "=== 4. LISTENING PORTS & NETSTAT ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/netstat -tuln 2>/dev/null" || true

echo "=== 5. LLAMA-SERVER CHECK ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux ps -ef | grep llama | grep -v grep" || true
