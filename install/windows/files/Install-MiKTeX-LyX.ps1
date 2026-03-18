#Requires -Version 5.1
# ===========================================================================
#  Install-MiKTeX-LyX.ps1
#
#  Bundled files (same folder as this script):
#      preferences              (LyX preferences file - no extension)
#      user.bind                (LyX key-binding file)
#      he_IL.dic                (Hebrew Hunspell dict  - fallback)
#      he_IL.aff                (Hebrew Hunspell affix - fallback)
#      basic-miktex-*-x64.exe   (optional)
#      LyX-*-x64.exe            (optional)
# ===========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  OUTPUT HELPERS
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Text)
    $line = '=' * 70
    Write-Host ''
    Write-Host $line     -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line     -ForegroundColor Cyan
}
function Write-Step { param([string]$T) Write-Host ''; Write-Host "  >> $T" -ForegroundColor Yellow }
function Write-OK   { param([string]$T) Write-Host "     [OK]  $T" -ForegroundColor Green   }
function Write-Warn { param([string]$T) Write-Host "     [!!]  $T" -ForegroundColor Magenta }
function Write-Err  { param([string]$T) Write-Host "     [ERR] $T" -ForegroundColor Red     }

function Format-Elapsed {
    param([TimeSpan]$ts)
    '{0:D2}:{1:D2}' -f [int][Math]::Floor($ts.TotalMinutes), $ts.Seconds
}

# Pads $Content to exactly fill one box line (inner width = 62 chars).
function Format-BoxLine {
    param([string]$Content)
    '  |' + $Content + (' ' * [Math]::Max(0, 62 - $Content.Length)) + '|'
}

# ---------------------------------------------------------------------------
#  RUN A NATIVE EXE
#  Streams output live with indentation; suppresses MiKTeX security noise.
# ---------------------------------------------------------------------------
function Invoke-Native {
    param([string]$Exe, [string[]]$Args)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Exe @Args 2>&1 |
        Where-Object { $_ -notmatch 'security.risk|elevated.priv' } |
        ForEach-Object { Write-Host "     $_" }
    $ec = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return $ec
}

# ---------------------------------------------------------------------------
#  WIN32 TYPES
# ---------------------------------------------------------------------------

# Prevent sleep  (ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)
Add-Type -Name 'PowerState' -Namespace 'Win32' -MemberDefinition @'
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
'@

# EnumWindows + SendMessage - used to auto-dismiss installer dialogs
Add-Type -Name 'WinMsg' -Namespace 'Win32' -MemberDefinition @'
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_CLOSE = 0x0010;
'@

# Notify running processes of a PATH change
Add-Type -Name 'NativeMethods' -Namespace 'Win32' -MemberDefinition @'
    [DllImport("user32.dll",CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);
'@ -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  AUTO-CLOSE LyX INSTALLER DIALOGS
#  Finds any visible window titled "LyX x.x.x Setup" and closes it.
# ---------------------------------------------------------------------------
function Close-InstallerDialogs {
    [Win32.WinMsg]::EnumWindows({
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        if (-not [Win32.WinMsg]::IsWindowVisible($hWnd)) { return $true }
        $sb = New-Object System.Text.StringBuilder 256
        [Win32.WinMsg]::GetWindowText($hWnd, $sb, 256) | Out-Null
        if ($sb.ToString() -match '^LyX .+ Setup$') {
            [Win32.WinMsg]::SendMessage($hWnd, [Win32.WinMsg]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
}

# ---------------------------------------------------------------------------
#  PATHS
# ---------------------------------------------------------------------------
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalAppData = $env:LOCALAPPDATA
$AppData      = $env:APPDATA
$DownloadsDir = Join-Path $env:USERPROFILE 'Downloads'

$MiKTeXInstallDir = Join-Path $LocalAppData 'Programs\MiKTeX'
$MiKTeXBinDir     = Join-Path $MiKTeXInstallDir 'miktex\bin\x64'
$OldMiKTeXBinDir  = 'C:\Program Files\MiKTeX\miktex\bin\x64'

$BundledPrefs = Join-Path $ScriptDir 'preferences'
$BundledBind  = Join-Path $ScriptDir 'user.bind'
$BundledDic   = Join-Path $ScriptDir 'he_IL.dic'
$BundledAff   = Join-Path $ScriptDir 'he_IL.aff'

$DictUrlDic = 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/he_IL/he_IL.dic'
$DictUrlAff = 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/he_IL/he_IL.aff'

# ---------------------------------------------------------------------------
#  STARTUP
# ---------------------------------------------------------------------------
[Win32.PowerState]::SetThreadExecutionState([Convert]::ToUInt32('80000003', 16)) | Out-Null

$logFile = Join-Path $env:TEMP ("LyX_install-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
Start-Transcript -Path $logFile -Append | Out-Null

$GlobalStart = [System.Diagnostics.Stopwatch]::StartNew()

Clear-Host
Write-Host ''
Write-Host '  +==============================================================+' -ForegroundColor Cyan
Write-Host '  |        MiKTeX + LyX  Automated Installer                     |' -ForegroundColor Cyan
Write-Host (Format-BoxLine ("        " + (Get-Date -Format 'yyyy-MM-dd  HH:mm:ss'))) -ForegroundColor Cyan
Write-Host '  +==============================================================+' -ForegroundColor Cyan
Write-Host ("  Log: " + $logFile) -ForegroundColor DarkCyan
Write-Host ''


# ===========================================================================
#  STEP 0 - Validate ASCII username
# ===========================================================================
if ($env:USERNAME -match '[^\x20-\x7E]') {
    Write-Header 'STEP 0 - Username validation'
    Write-Err "Username '$env:USERNAME' contains non-ASCII characters - this breaks MiKTeX per-user paths."
    Write-Err 'Please rename the Windows account to ASCII-only and re-run.'
    Stop-Transcript | Out-Null; exit 1
}


# ===========================================================================
#  STEP 1 - Install MiKTeX (per-user), configure, update
# ===========================================================================
Write-Header 'STEP 1 - MiKTeX installation and setup'
$stepStart = [System.Diagnostics.Stopwatch]::StartNew()

# --- 1a: Find or download MiKTeX installer ---
function Find-MiKTeXInstaller {
    foreach ($dir in @($ScriptDir, $DownloadsDir)) {
        $f = Get-ChildItem -Path $dir -Filter 'basic-miktex-*-x64.exe' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { Write-OK ("Found MiKTeX installer: " + $f.FullName); return $f.FullName }
    }
    return $null
}

$miktexExe = Find-MiKTeXInstaller
if (-not $miktexExe) {
    Write-Step 'Not found locally - downloading MiKTeX basic installer...'
    $miktexExe = Join-Path $env:TEMP 'basic-miktex-x64.exe'
    try {
        (New-Object System.Net.WebClient).DownloadFile(
            'https://miktex.org/download/ctan/systems/win32/miktex/setup/windows-x64/basic-miktex-x64.exe',
            $miktexExe)
        Write-OK "Downloaded: $miktexExe"
    } catch {
        Write-Err "Download failed: $_"
        Write-Err "Place basic-miktex-*-x64.exe in $ScriptDir or $DownloadsDir"
        Stop-Transcript | Out-Null; exit 1
    }
}

# --- 1b: Install if not already present ---
if (Test-Path (Join-Path $MiKTeXBinDir 'miktexsetup.exe')) {
    Write-Step 'MiKTeX already installed - skipping.'
} else {
    Write-Step "Installing MiKTeX to: $MiKTeXInstallDir"
    $proc = Start-Process -FilePath $miktexExe `
        -ArgumentList @('--unattended', '--private', '--auto-install=yes', "--user-install=$MiKTeXInstallDir") `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Err ("MiKTeX installer failed with code " + $proc.ExitCode)
        Stop-Transcript | Out-Null; exit 1
    }
    Write-OK 'MiKTeX installed successfully.'
}

# --- 1c: Add MiKTeX bin to PATH (session + permanent) ---
if ($env:PATH -notlike "*$MiKTeXBinDir*") {
    $env:PATH = $MiKTeXBinDir + ';' + $env:PATH
    Write-OK 'Added to session PATH.'
}
$userPathKey     = 'HKCU:\Environment'
$currentUserPath = (Get-ItemProperty -Path $userPathKey -Name 'Path' -ErrorAction SilentlyContinue).Path
if (-not $currentUserPath) { $currentUserPath = '' }
if ($currentUserPath -notlike "*$MiKTeXBinDir*") {
    Set-ItemProperty -Path $userPathKey -Name 'Path' `
        -Value ($MiKTeXBinDir + ';' + $currentUserPath) -Type ExpandString -Force
    Write-OK 'Added to permanent user PATH.'
    $r = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null
} else {
    Write-OK 'Already in permanent user PATH.'
}

# --- 1d: Refresh database and update packages ---
$initexmfExe  = Join-Path $MiKTeXBinDir 'initexmf.exe'
$mpmExe       = Join-Path $MiKTeXBinDir 'mpm.exe'
$miktexExeCli = Join-Path $MiKTeXBinDir 'miktex.exe'

if (-not (Test-Path $mpmExe)) {
    Write-Warn 'mpm.exe not found - skipping package operations.'
} else {
    if (Test-Path $initexmfExe) {
        Write-Step 'Refreshing file name database...'
        Invoke-Native -Exe $initexmfExe -Args @('--update-fndb') | Out-Null
        Write-OK 'File name database refreshed.'
    }

    Write-Step 'Checking for package updates (may take a few minutes)...'
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $updateOut = [System.Collections.Generic.List[string]]::new()
    $streamLine = {
        param([string]$line)
        if ($line -match 'security.risk|elevated.priv') { return }
        if ($line -match '\S') { Write-Host "     $line"; $updateOut.Add($line) }
    }
    if (Test-Path $miktexExeCli) {
        & $miktexExeCli packages update 2>&1 | ForEach-Object { & $streamLine "$_" }
    } else {
        & $mpmExe --update-package-database 2>&1 | ForEach-Object { & $streamLine "$_" }
        & $mpmExe --upgrade                 2>&1 | ForEach-Object { & $streamLine "$_" }
    }
    $updateFailed = @($updateOut | Where-Object { $_ -match "Sorry|error|couldn't|failed|resolve" }).Count -gt 0
    $updateOk     = ($LASTEXITCODE -eq 0) -and (-not $updateFailed)
    $ErrorActionPreference = $prev

    if ($updateOk) {
        Write-OK 'Packages up to date.'
    } else {
        Write-Warn 'Update failed (possibly a network issue). To update manually:'
        Write-Warn '  Open MiKTeX Console -> Updates -> Check for updates -> wait -> Update now'
    }
    Write-OK 'MiKTeX setup complete.'
}

$stepStart.Stop()
Write-Step ("Step 1 completed in " + (Format-Elapsed $stepStart.Elapsed))


# ===========================================================================
#  STEP 2 - Install LyX
# ===========================================================================
Write-Header 'STEP 2 - LyX installation'
$stepStart = [System.Diagnostics.Stopwatch]::StartNew()

# --- 2a: Find or download LyX installer ---
function Find-LyXInstaller {
    foreach ($dir in @($ScriptDir, $DownloadsDir)) {
        foreach ($pat in @('LyX-*-x64.exe', 'LyX-*-Installer*.exe', 'LyX*.exe')) {
            $f = Get-ChildItem -Path $dir -Filter $pat -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($f) { Write-OK ("Found LyX installer: " + $f.FullName); return $f.FullName }
        }
    }
    return $null
}

$lyxExe = Find-LyXInstaller
if (-not $lyxExe) {
    Write-Step 'Not found locally - resolving from lyx.org...'
    try {
        $html    = (New-Object System.Net.WebClient).DownloadString('https://www.lyx.org/Download')
        $rxMatch = [System.Text.RegularExpressions.Regex]::Match(
            $html, 'href="([^"]*LyX[^"]*x64[^"]*\.exe)"',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($rxMatch.Success) {
            $url = $rxMatch.Groups[1].Value
            if ($url -notmatch '^https?://') { $url = 'https://www.lyx.org' + $url }
        } else {
            $url = 'https://ftp.lip6.fr/pub/lyx/bin/2.4.3/LyX-2.4.3-Installer-x64.exe'
            Write-Warn 'Could not scrape URL - using fallback.'
        }
        $lyxExe = Join-Path $env:TEMP 'LyX-Installer-x64.exe'
        Write-Step "Downloading from: $url"
        (New-Object System.Net.WebClient).DownloadFile($url, $lyxExe)
        Write-OK 'LyX installer downloaded.'
    } catch {
        Write-Err "Download failed: $_"
        Write-Err "Place LyX-*-x64.exe in $ScriptDir or $DownloadsDir"
        Stop-Transcript | Out-Null; exit 1
    }
}

# --- 2b: Install with time-based progress bar ---
$lyxAlreadyInstalled = @(
    Get-ChildItem 'C:\Program Files\' -Filter 'LyX*' -Directory -ErrorAction SilentlyContinue
).Count -gt 0

if ($lyxAlreadyInstalled) {
    Write-Step 'LyX already installed - skipping.'
} else {
    Write-Step 'Running LyX silent installer...'
    Write-Host ''

    # Block outbound HTTP/HTTPS for the duration of the install so the LyX
    # installer cannot download dictionaries - we deploy them ourselves in Step 3.
    $fwRules = @{ 'LyX-Installer-Block80' = 80; 'LyX-Installer-Block443' = 443 }
    $fwAdded = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $fwRules.Keys) {
        try {
            New-NetFirewallRule -Name $name -DisplayName $name `
                -Direction Outbound -Action Block -Protocol TCP -RemotePort $fwRules[$name] `
                -ErrorAction Stop | Out-Null
            $fwAdded.Add($name)
        } catch { Write-Warn "Could not add firewall rule '$name': $_" }
    }
    if ($fwAdded.Count -eq $fwRules.Count) {
        Write-OK 'Firewall rules added - dictionary download will be skipped.'
    } else {
        Write-Warn 'Some firewall rules could not be added - dictionary download may occur.'
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo($lyxExe, '/S')
        $psi.UseShellExecute = $false
        $lyxProc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Err "Could not launch LyX installer: $_"
        $fwAdded | ForEach-Object { Remove-NetFirewallRule -Name $_ -ErrorAction SilentlyContinue }
        Stop-Transcript | Out-Null; exit 1
    }

    $totalSecs = 300
    $barWidth  = 50
    $timer     = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $lyxProc.HasExited) {
        $pct    = [Math]::Min(99, [int]($timer.Elapsed.TotalSeconds / $totalSecs * 100))
        $filled = [int]($pct / 100.0 * $barWidth)
        $bar    = '[' + ('#' * $filled) + ('-' * ($barWidth - $filled)) + ']'
        Write-Host ("`r     LyX Install  $bar  $pct%  " + (Format-Elapsed $timer.Elapsed)) -NoNewline -ForegroundColor Green
        Close-InstallerDialogs
        Start-Sleep -Seconds 2
    }
    Write-Host ("`r     LyX Install  [" + ('#' * $barWidth) + "]  100%  " + (Format-Elapsed $timer.Elapsed)) -ForegroundColor Green
    $timer.Stop()
    Write-Host ''

    $fwAdded | ForEach-Object { Remove-NetFirewallRule -Name $_ -ErrorAction SilentlyContinue }
    if ($fwAdded.Count -gt 0) { Write-OK 'Firewall rules removed.' }

    if (($null -ne $lyxProc.ExitCode) -and ($lyxProc.ExitCode -ne 0)) {
        Write-Warn ("LyX installer exited with code " + $lyxProc.ExitCode)
    } else {
        Write-OK ("LyX installed in " + (Format-Elapsed $timer.Elapsed))
    }
}

# --- 2c: Detect installed LyX version ---
$lyxInstallDir = Get-ChildItem 'C:\Program Files\' -Filter 'LyX*' -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
if ($lyxInstallDir) {
    $lyxInstalledVersion = if ($lyxInstallDir.Name -match '(\d+\.\d+)') { $Matches[1] } else { '' }
    Write-OK ("Detected LyX: " + $lyxInstallDir.Name + " (v" + $lyxInstalledVersion + ")")
} else {
    $lyxInstalledVersion = ''
    Write-Warn 'Could not detect LyX version from Program Files.'
}

# --- 2d: Resolve LyX user AppData directory ---
$LyXAppDataDir = Get-ChildItem $AppData -Filter 'LyX*' -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1

if (-not $LyXAppDataDir) {
    Write-Step 'AppData not found - running LyX briefly to create it...'
    $lyxBin = Get-ChildItem 'C:\Program Files\LyX*\bin\lyx.exe' -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if ($lyxBin) {
        $p = Start-Process -FilePath $lyxBin.FullName -ArgumentList '-batch' -PassThru
        Start-Sleep -Seconds 10
        if (-not $p.HasExited) { $p.Kill() }
    }
    $LyXAppDataDir = Get-ChildItem $AppData -Filter 'LyX*' -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending | Select-Object -First 1
}

if ($LyXAppDataDir) {
    $LyXUserDir = $LyXAppDataDir.FullName
    Write-OK "LyX user directory: $LyXUserDir"
} else {
    $fallback = 'LyX' + $(if ($lyxInstalledVersion) { $lyxInstalledVersion } else { '2.4' })
    Write-Warn "Could not find LyX AppData - using fallback: $fallback"
    $LyXUserDir = Join-Path $AppData $fallback
    New-Item -ItemType Directory -Force -Path $LyXUserDir | Out-Null
}

$stepStart.Stop()
Write-Step ("Step 2 completed in " + (Format-Elapsed $stepStart.Elapsed))


# ===========================================================================
#  STEP 3 - Settings and preferences
# ===========================================================================
Write-Header 'STEP 3 - Settings and preferences'
$stepStart = [System.Diagnostics.Stopwatch]::StartNew()

# --- 3a: preferences file (MiKTeX path + Format number) ---
Write-Step 'Deploying preferences file...'
if (-not (Test-Path $BundledPrefs)) {
    Write-Err "preferences file not found: $BundledPrefs"
    Stop-Transcript | Out-Null; exit 1
}
$prefsContent = Get-Content -Path $BundledPrefs -Raw -Encoding UTF8
$destPrefs    = Join-Path $LyXUserDir 'preferences'

$oldPathFwd  = $OldMiKTeXBinDir -replace '\\', '/'
$oldPathBack = $OldMiKTeXBinDir
$newPathFwd  = $MiKTeXBinDir    -replace '\\', '/'
Write-Step ("Replacing MiKTeX path:  $oldPathFwd  ->  $newPathFwd")
$prefsContent = $prefsContent -replace [Regex]::Escape($oldPathBack), $newPathFwd
$prefsContent = $prefsContent -replace [Regex]::Escape($oldPathFwd),  $newPathFwd

$lyxFormatMap    = @{ '2.3' = 29; '2.4' = 38; '2.5' = 40 }
$detectedVersion = if ($lyxInstalledVersion -match '^(\d+\.\d+)') { $Matches[1] } else { '' }
if ($detectedVersion -and $lyxFormatMap.ContainsKey($detectedVersion)) {
    $correctFormat = $lyxFormatMap[$detectedVersion]
    $prefsContent  = $prefsContent -replace '(?m)^Format\s+\d+', "Format $correctFormat"
    Write-OK "Preferences Format set to $correctFormat (LyX $detectedVersion)"
} else {
    Write-Warn "Unknown LyX version '$lyxInstalledVersion' - leaving Format number unchanged."
}

Set-Content -Path $destPrefs -Value $prefsContent -Encoding UTF8 -Force
Write-OK "preferences deployed to $destPrefs"

# --- 3b: user.bind ---
Write-Step 'Deploying user.bind...'
if (-not (Test-Path $BundledBind)) {
    Write-Err "user.bind not found: $BundledBind"
    Stop-Transcript | Out-Null; exit 1
}
$bindDir  = Join-Path $LyXUserDir 'bind'
$destBind = Join-Path $bindDir 'user.bind'
if (-not (Test-Path $bindDir)) { New-Item -ItemType Directory -Force -Path $bindDir | Out-Null }
Copy-Item -Path $BundledBind -Destination $destBind -Force
Write-OK "user.bind deployed to $destBind"

# --- 3c: Hebrew dictionaries (he_IL) ---
Write-Step 'Deploying Hebrew dictionaries...'
$dictUserDir = Join-Path $LyXUserDir 'dicts'
if (-not (Test-Path $dictUserDir)) { New-Item -ItemType Directory -Force -Path $dictUserDir | Out-Null }

function Get-Dict {
    param([string]$Url, [string]$Dest, [string]$Fallback, [string]$Label)
    Write-Step "Downloading $Label..."
    try {
        (New-Object System.Net.WebClient).DownloadFile($Url, $Dest)
        Write-OK "$Label downloaded."
        return
    } catch { Write-Warn ("Download failed: " + $_) }
    if (Test-Path $Fallback) {
        Copy-Item -Path $Fallback -Destination $Dest -Force
        Write-OK "Used bundled $Label as fallback."
    } else {
        Write-Err "$Label unavailable - Hebrew spell-check will be missing."
    }
}

Get-Dict -Url $DictUrlDic -Dest (Join-Path $dictUserDir 'he_IL.dic') -Fallback $BundledDic -Label 'he_IL.dic'
Get-Dict -Url $DictUrlAff -Dest (Join-Path $dictUserDir 'he_IL.aff') -Fallback $BundledAff -Label 'he_IL.aff'

# Also copy into the LyX system dicts folder if writable
$sysDict = Get-ChildItem 'C:\Program Files\LyX*\Resources\dicts' -ErrorAction SilentlyContinue |
           Select-Object -First 1
if ($sysDict) {
    foreach ($f in @('he_IL.dic', 'he_IL.aff')) {
        $src = Join-Path $dictUserDir $f
        $dst = Join-Path $sysDict.FullName $f
        if ((Test-Path $src) -and (-not (Test-Path $dst))) {
            try   { Copy-Item $src $dst -Force; Write-OK "Copied $f to system dicts." }
            catch { Write-Warn ("Could not copy to system dicts: " + $_) }
        }
    }
}

$stepStart.Stop()
Write-Step ("Step 3 completed in " + (Format-Elapsed $stepStart.Elapsed))


# ===========================================================================
#  STEP 4 - Test: export test.lyx to PDF and open it
# ===========================================================================
Write-Header 'STEP 4 - Test: export test.lyx to PDF'
$stepStart = [System.Diagnostics.Stopwatch]::StartNew()

$testLyxSrc = Join-Path $ScriptDir 'test.lyx'
if (-not (Test-Path $testLyxSrc)) {
    Write-Step 'test.lyx not found locally - downloading...'
    try {
        (New-Object System.Net.WebClient).DownloadFile('https://lyx.srayaa.com/install/test.lyx', $testLyxSrc)
        Write-OK "Downloaded test.lyx to $testLyxSrc"
    } catch {
        Write-Warn ("Could not download test.lyx: " + $_)
        Write-Warn 'Skipping PDF export test.'
        $testLyxSrc = $null
    }
}

if ($testLyxSrc -and (Test-Path $testLyxSrc)) {
    $lyxBin = Get-ChildItem 'C:\Program Files\LyX*\bin\lyx.exe' -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1

    if (-not $lyxBin) {
        Write-Warn 'lyx.exe not found - cannot export PDF.'
    } else {
        $pdfOut = Join-Path $ScriptDir 'test.pdf'
        if (Test-Path $pdfOut) {
            Remove-Item -Path $pdfOut -Force
            Write-OK 'Deleted existing test.pdf.'
        }
        Write-Step ("Exporting: " + $testLyxSrc)
        Write-Step ("Output   : " + $pdfOut)
        Write-Step 'Running LyX export (this may take a few minutes)...'

        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $exportProc = Start-Process -FilePath $lyxBin.FullName `
            -ArgumentList @('-e', 'pdf4', $testLyxSrc) `
            -Wait -PassThru -WindowStyle Hidden
        $ErrorActionPreference = $prev

        if ($exportProc.ExitCode -ne 0) {
            Write-Warn ("LyX export exited with code " + $exportProc.ExitCode + " - PDF may not have been created.")
        }

        # LyX exports the PDF next to the source; move to ScriptDir if needed
        $autoOutPdf = [System.IO.Path]::ChangeExtension($testLyxSrc, '.pdf')
        if ((Test-Path $autoOutPdf) -and ($autoOutPdf -ne $pdfOut)) {
            Move-Item -Path $autoOutPdf -Destination $pdfOut -Force
        }

        if (Test-Path $pdfOut) {
            Write-OK ("PDF created: " + $pdfOut)
            Write-Step 'Opening PDF...'
            Start-Process $pdfOut
            Write-OK 'PDF opened.'
        } else {
            Write-Warn 'PDF file not found after export - check LyX logs for errors.'
        }
    }
}

$stepStart.Stop()
Write-Step ("Step 4 completed in " + (Format-Elapsed $stepStart.Elapsed))


# ---------------------------------------------------------------------------
#  DONE
# ---------------------------------------------------------------------------
$GlobalStart.Stop()
[Win32.PowerState]::SetThreadExecutionState([Convert]::ToUInt32('80000000', 16)) | Out-Null

$total = Format-Elapsed $GlobalStart.Elapsed
Write-Host ''
Write-Host '  +==============================================================+' -ForegroundColor Green
Write-Host '  |               INSTALLATION COMPLETE                          |' -ForegroundColor Green
Write-Host (Format-BoxLine ("  Total time : " + $total)) -ForegroundColor Green
Write-Host (Format-BoxLine ("  Finished   : " + (Get-Date -Format 'HH:mm:ss  yyyy-MM-dd'))) -ForegroundColor Green
Write-Host '  +==============================================================+' -ForegroundColor Green
Write-Host ''
Write-Host '  Paths:' -ForegroundColor Cyan
Write-Host ("    MiKTeX bin   : " + $MiKTeXBinDir)                         -ForegroundColor White
Write-Host ("    LyX user dir : " + $LyXUserDir)                           -ForegroundColor White
Write-Host ("    preferences  : " + (Join-Path $LyXUserDir 'preferences')) -ForegroundColor White
Write-Host ("    user.bind    : " + $destBind)                             -ForegroundColor White
Write-Host ("    Hebrew dicts : " + $dictUserDir)                          -ForegroundColor White
Write-Host ("    Test PDF     : " + (Join-Path $ScriptDir 'test.pdf'))      -ForegroundColor White
Write-Host ("    Install log  : " + $logFile)                              -ForegroundColor White
Write-Host ''
Write-Host '  Restart LyX to apply all settings.' -ForegroundColor Yellow
Write-Host ''

Stop-Transcript | Out-Null
