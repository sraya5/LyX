@echo off
:: ============================================================
::  LyX_2.4_installer.cmd
::  Source: https://lyx.srayaa.com/install/windows
::  Wrote by Sraya Ansbacher with Claude ai.
::
::  Same as installer.cmd but also downloads the latest
::  LyX 2.4.x installer into the "files" folder before
::  launching Install-MiKTeX-LyX.ps1.
::
::  Expected folder layout:
::
::    (any folder)\
::        LyX_2.4_installer.cmd      <-- THIS file
::        files\
::            Install-MiKTeX-LyX.ps1
::            preferences
::            user.bind
::            he_IL.dic
::            he_IL.aff
::            LyX-24*-x64.exe      (downloaded automatically)
::            basic-miktex-*-x64.exe   (optional)
:: ============================================================

setlocal EnableDelayedExpansion

set "SCRIPT_ROOT=%~dp0"
set "FILES_DIR=%SCRIPT_ROOT%files"
set "PS1_PATH=%FILES_DIR%\Install-MiKTeX-LyX.ps1"
set "BASE_URL=https://lyx.srayaa.com/install/windows/files"

:: ---  Download any missing script files  ------------------------------------
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

:: ---  Download LyX 2.4 installer if not already in files folder  ------------
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$dest = '%FILES_DIR%';" ^
    "$existing = Get-ChildItem $dest -Filter 'LyX-24*-x64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
    "if ($existing) { Write-Host ('  [SKIP] LyX 2.4 installer already exists: ' + $existing.Name); exit 0 }" ^
    "Write-Host '  Resolving LyX 2.4 installer from FTP...';" ^
    "$wc = New-Object System.Net.WebClient;" ^
    "try {" ^
    "    $ftpBase = 'https://ftp.lip6.fr/pub/lyx/bin/';" ^
    "    $html = $wc.DownloadString($ftpBase);" ^
    "    $vers = [System.Text.RegularExpressions.Regex]::Matches($html, 'href=""(2\.4\.\d+)\/""') |" ^
    "            Sort-Object { [version]$_.Groups[1].Value } | Select-Object -Last 1;" ^
    "    if (-not $vers) { throw 'No LyX 2.4.x folder found on FTP.' }" ^
    "    $verDir = $ftpBase + $vers.Groups[1].Value + '/';" ^
    "    $dirHtml = $wc.DownloadString($verDir);" ^
    "    $file = [System.Text.RegularExpressions.Regex]::Matches($dirHtml, 'LyX-24\d*-Installer-\d+-x64\.exe') |" ^
    "            Select-Object -Last 1;" ^
    "    if (-not $file) { throw 'No LyX 2.4 x64 installer found.' }" ^
    "    $url = $verDir + $file.Value;" ^
    "    $out = Join-Path $dest $file.Value;" ^
    "    Write-Host ('  Downloading ' + $file.Value + '...');" ^
    "    $wc.DownloadFile($url, $out);" ^
    "    Write-Host ('  [OK]  ' + $file.Value) -ForegroundColor Green" ^
    "} catch {" ^
    "    Write-Host ('  [ERR] ' + $_.Exception.Message) -ForegroundColor Red; exit 1" ^
    "}"

if !errorlevel! neq 0 (
    echo.
    echo  [ERROR] Could not download LyX 2.4 installer. Check your internet connection.
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
echo   Starting MiKTeX + LyX Installer  (LyX 2.4)
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
