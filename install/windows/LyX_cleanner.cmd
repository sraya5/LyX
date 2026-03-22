@echo off
:: ============================================================
::  Uninstall-MiKTeX-LyX.cmd
::  Double-click to run the PowerShell uninstaller as Admin.
::  Auto-downloads the PS1 if missing.
:: ============================================================

:: ── Auto-elevate to Administrator ───────────────────────────
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ── Ensure the files folder and PS1 script exist ────────────
set "PS1_DIR=%~dp0files"
set "PS1_FILE=%PS1_DIR%\Uninstall-MiKTeX-LyX.ps1"
set "PS1_URL=https://lyx.srayaa.com/install/windows/files/Uninstall-MiKTeX-LyX.ps1"

if not exist "%PS1_DIR%" (
    echo  [INFO] Creating folder: %PS1_DIR%
    mkdir "%PS1_DIR%"
)

if not exist "%PS1_FILE%" (
    echo  [INFO] Script not found. Downloading...
    echo         %PS1_URL%
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "Invoke-WebRequest -Uri '%PS1_URL%' -OutFile '%PS1_FILE%' -UseBasicParsing"
)

:: ── Verify the file actually exists after download attempt ──
if not exist "%PS1_FILE%" (
    echo.
    echo  [ERROR] Could not download the uninstaller script.
    echo          Check your internet connection or download manually:
    echo          %PS1_URL%
    echo          and place it in: %PS1_DIR%
    echo.
    pause
    exit /b 1
)

:: ── Run the PowerShell script ────────────────────────────────
echo.
echo  =========================================
echo   MiKTeX ^& LyX Uninstaller
echo  =========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"

echo.
echo  =========================================
echo   Done. Press any key to close...
echo  =========================================
pause >nul
