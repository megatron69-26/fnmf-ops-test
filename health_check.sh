#!/bin/bash
set -e
echo "=== FNMF Note 10+ Backend Health Check ==="
echo "Date: $(date)"
echo "Checking ADB connection..."
ADB="/c/Users/khoid/AppData/Local/Android/Sdk/platform-tools/adb.exe"
if [ ! -f "$ADB" ]; then
    ADB="adb.exe"
fi

"$ADB" devices

echo "Checking Actuator Health on Note 10+ (127.0.0.1:8083)..."
HEALTH_OUT=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8083/actuator/health")
echo "Actuator Health: $HEALTH_OUT"

echo "Checking 5 Binance Assets Catalog (/api/stocks)..."
STOCKS_OUT=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s http://127.0.0.1:8083/api/stocks")
echo "Stock Catalog: $STOCKS_OUT"

echo "=== Health Check Complete ==="
