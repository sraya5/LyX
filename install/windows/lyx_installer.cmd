@echo off
:: ============================================================
::  LyX_installer.cmd
::  Source: https://lyx.srayaa.com/install/windows
::  Wrote by Sraya Ansbacher with Claude ai.
::
::  Double-click this file to launch Install-MiKTeX-LyX.ps1
::  with administrator privileges and an unrestricted
::  execution policy.
::
::  If the "files" sub-folder is missing, the required files
::  are downloaded automatically from:
::  https://lyx.srayaa.com/install/windows/files
::
::  Expected folder layout:
::
::    (any folder)\
::        LyX_installer.cmd.cmd            <-- THIS file
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

set "SCRIPT_ROOT=%~dp0"
set "FILES_DIR=%SCRIPT_ROOT%files"
set "PS1_PATH=%FILES_DIR%\Install-MiKTeX-LyX.ps1"
set "BASE_URL=https://lyx.srayaa.com/install/windows/files"

:: ---  Download any missing files  ------------------------------------------
set "NEED_DOWNLOAD=0"
for %%F in (Install-MiKTeX-LyX.ps1 preferences user.bind he_IL.dic he_IL.aff) do (
    if not exist "%FILES_DIR%\%%F" set "NEED_DOWNLOAD=1"
)

if "%NEED_DOWNLOAD%"=="1" (
    echo.
    echo  [INFO] One or more required files are missing - downloading from:
    echo         %BASE_URL%
    echo.

    if not exist "%FILES_DIR%" mkdir "%FILES_DIR%"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$baseUrl = '%BASE_URL%'; $dest = '%FILES_DIR%';" ^
        "$files = @('Install-MiKTeX-LyX.ps1','preferences','user.bind','he_IL.dic','he_IL.aff');" ^
        "$wc = New-Object System.Net.WebClient;" ^
        "foreach ($f in $files) {" ^
        "    $out = Join-Path $dest $f;" ^
        "    if (Test-Path $out) { Write-Host ('  [SKIP] ' + $f + ' (already exists)'); continue }" ^
        "    $url = $baseUrl + '/' + $f;" ^
        "    Write-Host ('  Downloading ' + $f + '...');" ^
        "    try { $wc.DownloadFile($url, $out); Write-Host ('  [OK]  ' + $f) -ForegroundColor Green }" ^
        "    catch { Write-Host ('  [ERR] ' + $f + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }" ^
        "}"

    if !errorlevel! neq 0 (
        echo.
        echo  [ERROR] Download failed. Check your internet connection and try again.
        echo.
        pause
        exit /b 1
    )

    echo.
    echo  [OK]  All files are ready.
    echo.
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
