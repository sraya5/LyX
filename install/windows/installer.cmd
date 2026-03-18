@echo off
:: ============================================================
::  Run-Installer.cmd
::  Double-click this file to launch Install-MiKTeX-LyX.ps1
::  with administrator privileges and an unrestricted
::  execution policy.
::
::  Expected folder layout:
::
::    (any folder)\
::        Run-Installer.cmd        <-- THIS file
::        files\
::            Install-MiKTeX-LyX.ps1
::            preferences
::            user.bind
::            he_IL.dic
::            he_IL.aff
::            basic-miktex-*-x64.exe   (optional)
::            LyX-*-x64.exe            (optional)
:: ============================================================

setlocal EnableDelayedExpansion

:: ---  Resolve the "files" sub-folder relative to this .cmd  ----------------
set "SCRIPT_ROOT=%~dp0"
set "PS1_PATH=%SCRIPT_ROOT%files\Install-MiKTeX-LyX.ps1"

if not exist "%PS1_PATH%" (
    echo.
    echo  [ERROR] Cannot find the PowerShell script at:
    echo          %PS1_PATH%
    echo.
    echo  Make sure Install-MiKTeX-LyX.ps1 is inside a sub-folder
    echo  called "files" that sits next to this .cmd file.
    echo.
    pause
    exit /b 1
)

:: ---  Self-elevate to Administrator if not already  ------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  Requesting administrator privileges...
    powershell -NoProfile -Command ^
        "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: ---  Launch PowerShell with -ExecutionPolicy Bypass  ----------------------
echo.
echo  ==========================================================
echo   Starting MiKTeX + LyX Installer
echo   Script : %PS1_PATH%
echo  ==========================================================
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%PS1_PATH%"

if %errorlevel% neq 0 (
    echo.
    echo  [WARNING] Script finished with exit code %errorlevel%.
    echo  Check the output above for details.
    echo.
    pause
) else (
    echo.
    echo  [DONE] Script completed successfully.
    echo.
    pause
)

endlocal
