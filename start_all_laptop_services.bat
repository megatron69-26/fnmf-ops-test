@echo off
echo ================================================================================
echo        FNMF TEST SUITE - KHOI DONG DONG BO TAT CA DICH VU TREN LAPTOP
echo ================================================================================
echo.

set "ANDROID_USER_HOME=C:\Users\khoid\.android"
set "PATH=C:\Program Files\Git\bin;C:\Users\khoid\AppData\Local\Android\Sdk\platform-tools;%PATH%"

echo [1/4] Kiem tra ket noi Galaxy Note 10+ qua ADB...
adb.exe devices -l | findstr "R3CM8105TPA"
if %errorlevel% neq 0 (
    echo [CANH BAO] Chua phat hien Galaxy Note 10+ (R3CM8105TPA).
    echo           Vui long cam cap USB va mo khoa man hinh Note 10+.
) else (
    echo [OK] Galaxy Note 10+ da ket noi qua ADB.
    echo [OK] Thiet lap adb forward tcp:8083 tcp:8083 de ket noi backend loopback tren Note 10+...
    adb.exe forward tcp:8083 tcp:8083
)

echo [2/4] Khoi chay Semaphore CI/CD (Port 3000)...
start /min "Semaphore Service" "C:\Users\khoid\AppData\Local\semaphore\start_semaphore.bat"

echo [3/4] Khoi chay Grafana Monitoring (Port 3001)...
start /min "Grafana Service" "C:\Users\khoid\AppData\Local\grafana-v11.2.2\start_grafana.bat"

echo [4/4] Khoi chay Dashy FNMF Control Center (Port 4000)...
start /min "Dashy Service" "C:\Users\khoid\AppData\Local\dashy\start_dashy.bat"

echo.
echo ================================================================================
echo                    TAT CA DICH VU DA DUOC KHOI DONG TREN LAPTOP
echo ================================================================================
echo  * Dashy Homepage  : http://127.0.0.1:4000
echo  * Semaphore CI/CD : http://127.0.0.1:3000
echo  * Grafana Metrics : http://127.0.0.1:3001
echo  * Backend Actuator: http://127.0.0.1:8083 (via Note 10+)
echo ================================================================================
