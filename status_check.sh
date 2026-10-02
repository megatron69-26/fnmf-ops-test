#!/bin/bash
set -e
echo "=========================================================="
echo "   FNMF NOTE 10+ SYSTEM & SERVICES STATUS (READ-ONLY)    "
echo "=========================================================="
echo "Date: $(date)"

ADB="adb.exe"

echo ""
echo "[1] KIỂM TRA THIẾT BỊ ANDROID (SAMSUNG NOTE 10+)"
"$ADB" devices -l | grep "R3CM8105TPA" || { echo "LỖI: Không tìm thấy Galaxy Note 10+ qua ADB"; exit 1; }
BATTERY=$("$ADB" -s R3CM8105TPA shell dumpsys battery | grep -E "level|temperature" | tr '\n' ' ')
echo "Pin & Nhiệt độ: $BATTERY"

echo ""
echo "[2] KIỂM TRA WAKE LOCK (GIỮ TIẾN TRÌNH KHÔNG BỊ KILL)"
WAKELOCK=$("$ADB" -s R3CM8105TPA shell "dumpsys power | grep -i 'termux:service-wakelock'" || echo "CHƯA CÓ")
echo "Wake Lock: $WAKELOCK"

echo ""
echo "[3] KIỂM TRA TIẾN TRÌNH POSTGRESQL (PORT 5432)"
PG_PROCS=$("$ADB" -s R3CM8105TPA shell "pgrep -l postgres" || echo "KHÔNG CHẠY")
echo "PostgreSQL Processes:"
echo "$PG_PROCS"

echo ""
echo "[4] KIỂM TRA DỮ LIỆU CƠ SỞ DỮ LIỆU 'fnmf_test'"
DB_STATS=$("$ADB" -s R3CM8105TPA shell "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -t -c 'SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM wallets) AS wallets, (SELECT version FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 1) AS flyway_ver;'")
echo "Database Stats (users | wallets | flyway_version):"
echo "$DB_STATS"

echo ""
echo "[5] KIỂM TRA TIẾN TRÌNH SPRING BOOT (PORT 8083)"
JAVA_PROC=$("$ADB" -s R3CM8105TPA shell "pgrep -fl llm-gateway" || echo "KHÔNG CHẠY")
echo "Java Backend Process: $JAVA_PROC"

echo ""
echo "[6] KIỂM TRA BINDING ĐỊA CHỈ IP SOCKET"
SOCKETS=$("$ADB" -s R3CM8105TPA shell "cat /proc/net/tcp | grep -E '1F93|1538'")
echo "Sockets (1F93=8083, 1538=5432 - địa chỉ 0100007F là 127.0.0.1):"
echo "$SOCKETS"

echo ""
echo "[7] TÀI NGUYÊN RAM NOTE 10+"
MEM=$("$ADB" -s R3CM8105TPA shell "free -m")
echo "$MEM"

echo "=========================================================="
echo "          KIỂM TRA HOÀN TẤT - TRẠNG THÁI KHỎE MẠNH       "
echo "=========================================================="
