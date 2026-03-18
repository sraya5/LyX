@echo off
:: ============================================================
::  Uninstall-MiKTeX-LyX.cmd
::  Double-click to run the PowerShell uninstaller as Admin.
::  Place this file in the SAME folder as:
::      Uninstall-MiKTeX-LyX.ps1
:: ============================================================

:: ── Auto-elevate to Administrator ───────────────────────────
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ── Run the PowerShell script (bypass execution policy) ─────
echo.
echo  =========================================
echo   MiKTeX ^& LyX Uninstaller
echo  =========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Uninstall-MiKTeX-LyX.ps1"

echo.
echo  =========================================
echo   Done. Press any key to close...
echo  =========================================
pause >nul
