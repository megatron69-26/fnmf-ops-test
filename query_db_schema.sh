#!/bin/bash
set -euo pipefail

export PATH="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools:$PATH"
export ANDROID_USER_HOME="C:/Users/khoid/.android"
ADB="adb.exe"
DEVICE="R3CM8105TPA"

echo "=== 1. DATABASE TABLES IN FNMF_TEST ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -c '\dt'"

echo "=== 2. SCHEMA OF NEWS_AI_CACHE IF EXISTS ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -c '\d news_ai_cache'" || true

echo "=== 3. ROW COUNT OF NEWS_AI_CACHE ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -c 'SELECT count(*) FROM news_ai_cache;'" || true

echo "=== 4. SAMPLE ROWS FROM NEWS_AI_CACHE ==="
"$ADB" -s "$DEVICE" shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -c 'SELECT id, title, article_url, created_at, analyzed_at FROM news_ai_cache ORDER BY id DESC LIMIT 3;'" || true
