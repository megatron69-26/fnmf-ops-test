#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== KEYS IN .env.test ON PHONE ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux cat /data/data/com.termux/files/home/.env.test" | sed -E 's/=(.+)/=[REDACTED]/'
