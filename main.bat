@echo off
setlocal enabledelayedexpansion

:: ========== Configuration ==========
set names[0]=NA Virginia
set hosts[0]=dynamodb.us-east-1.amazonaws.com

set names[1]=NA Chicago
set hosts[1]=dynamodb.us-east-2.amazonaws.com

set names[2]=NA San Jose
set hosts[2]=dynamodb.us-west-1.amazonaws.com

set names[3]=NA Portland
set hosts[3]=dynamodb.us-west-2.amazonaws.com

:: Temp files
set "tmpfile=us_wg_servers.txt"
set "finalfile=results.csv"
set "sortedfile=results_sorted.csv"
type nul > %tmpfile%
type nul > %finalfile%

:: ========== Filter Unique US WireGuard Hostnames ==========
for /f "tokens=1" %%A in ('mullvad relay list ^| findstr "us-" ^| findstr "wg"') do (
    set "hostname=%%A"
    for /f "tokens=2 delims=-" %%C in ("%%A") do (
        set "city=%%C"
        findstr /i "!city!" %tmpfile% >nul
        if errorlevel 1 (
            echo %%A>>%tmpfile%
        )
    )
)

:: ========== Filter All US WireGuard Servers for Specific Cities ==========
::for /f "tokens=1" %%A in ('mullvad relay list ^| findstr /i "us-" ^| findstr "wg"') do (
::    set "hostname=%%A"
::    echo !hostname! | findstr /i "us-nyc us-qas us-was us-rag" >nul
::    if !errorlevel! == 0 (
::        echo %%A>>%tmpfile%
::    )
::)


:: ========== Start Test ==========
echo Hostname,NA Virginia,NA Chicago,NA San Jose,NA Portland,Overall Average>>%finalfile%

for /f %%S in (%tmpfile%) do (
    set "server=%%S"
    echo.
    echo [0m==== [96mTesting [95m!server! [0m====
    mullvad relay set location !server! >nul

    call :WaitForConnection
    call :TestServer !server!
)

:: ========== Sort Results ==========
echo.
echo Sorting results...
powershell -Command "Import-Csv -Path '%finalfile%' | Sort-Object {[double]($_.'Overall Average')} | Export-Csv -Path '%sortedfile%' -NoTypeInformation"

:: ========== Display Table ==========
echo.
echo ======= Final Results (Sorted) =======
powershell -Command "Import-Csv -Path '%sortedfile%' | Format-Table -AutoSize"

goto :EOF

:: ========== Wait Until VPN is Connected ==========
:WaitForConnection
echo [92mWaiting for [93mMullvad [92mconnection...[0m
:retry
timeout /t 2 >nul
set connected=no
for /f "tokens=*" %%C in ('mullvad status') do (
    if "%%C"=="Connected" (
        set connected=yes
    )
)
if "!connected!"=="no" goto retry
echo [92mMullvad has been connected.[0m
exit /b

:: ========== TestServer <hostname> ==========
:TestServer
set "hostname=%1"
set result=%hostname%
set total=0

for /L %%i in (0,1,3) do (
    set "region=!names[%%i]!"
    set "host=!hosts[%%i]!"

    call :GetIP !host!
    set "ip=!resolved_ip!"

    if defined ip (
        call echo [96mTesting [95m%%region%% [93m!ip![0m
        set sum=0

        for /L %%j in (1,1,5) do (
            for /f "tokens=6 delims== " %%A in ('ping -n 1 !ip! ^| findstr /i "Average"') do (
                set latency=%%A
                set latency=!latency:ms=!
                echo     [93mPing [94m%%j: [96m!latency! ms[0m
                set /a sum+=!latency!
            )
        )

        set /a avg=sum / 5
        set /a total+=avg
        echo.
        echo     [92m!region! Average: [91m!avg! ms
        echo =================================
        set result=!result!,!avg!
    ) else (
        echo     Failed to resolve !host! — skipping...
        set result=!result!,9999
        set /a total+=9999
    )
)

set /a overall=total / 4
set result=!result!,!overall!
echo !result!>>%finalfile%
exit /b

:: ========== GetIP <hostname> ==========
:GetIP
set "resolved_ip="
for /f "tokens=2 delims=[]" %%I in ('ping -n 1 %1 ^| findstr /i "["') do (
    set "resolved_ip=%%I"
)
exit /b
