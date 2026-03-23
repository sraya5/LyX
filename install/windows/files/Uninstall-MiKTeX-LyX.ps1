# ============================================================
#  Uninstall-MiKTeX-LyX.ps1
#  Source: https://lyx.srayaa.com/install/windows
#  Wrote by Sraya Ansbacher with Claude ai.
#
#  Silent removal of MiKTeX and LyX (no GUI popups)
#  Handles locked files by killing related processes first
#  Run as Administrator in PowerShell
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "SilentlyContinue"

# ── Helpers ─────────────────────────────────────────────────

function Write-Header ($text) {
    Write-Host "`n===  $text  ===" -ForegroundColor Cyan
}

function Remove-SafeItem ($path) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
        Write-Host "  [DEL]  $path" -ForegroundColor Yellow
    } else {
        Write-Host "  [SKIP] $path  (not found)" -ForegroundColor DarkGray
    }
}

# Kill all processes whose path is inside a given folder
function Stop-ProcessesInFolder ($folderPath) {
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $procPath = $_.MainModule.FileName
            if ($procPath -and $procPath -like "$folderPath*") {
                Write-Host "  [KILL] $($_.Name)  (PID $($_.Id))  ->  $procPath" -ForegroundColor Red
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

# Kill processes by name list
function Stop-ByName ($names) {
    foreach ($n in $names) {
        $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            Write-Host "  [KILL] $($p.Name)  (PID $($p.Id))" -ForegroundColor Red
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# Force-delete a folder, retrying after a short wait if first attempt fails
function Remove-FolderForce ($path) {
    if (-not (Test-Path $path)) {
        Write-Host "  [SKIP] $path  (not found)" -ForegroundColor DarkGray
        return
    }

    # Kill anything running from inside that folder first
    Stop-ProcessesInFolder $path
    Start-Sleep -Seconds 2

    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path $path) {
        Write-Host "  [RETRY] First delete attempt failed, trying robocopy empty-folder trick..." -ForegroundColor DarkYellow

        # Robocopy trick: mirror an empty temp dir onto the target, then delete
        $emptyDir = Join-Path $env:TEMP ("empty_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        robocopy $emptyDir $path /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $path) {
        Write-Host "  [WARN] Could not fully delete: $path  (files may still be locked)" -ForegroundColor Red
    } else {
        Write-Host "  [DEL]  $path" -ForegroundColor Yellow
    }
}

# Run every uninstaller found for $displayName, fully silently
function Invoke-AllUninstallers ($displayName) {
    $searchPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $entries = Get-ItemProperty $searchPaths -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$displayName*" }

    if (-not $entries) {
        Write-Host "  [SKIP] No '$displayName' entries found in registry." -ForegroundColor DarkGray
        return
    }

    foreach ($entry in $entries) {
        $uninstStr = $entry.UninstallString
        if (-not $uninstStr) { continue }

        Write-Host "  [FOUND] $($entry.DisplayName)" -ForegroundColor Green
        Write-Host "          $uninstStr" -ForegroundColor DarkGray

        try {
            if ($uninstStr -match "MsiExec|msiexec") {
                # ── MSI-based ────────────────────────────────────────────
                if ($uninstStr -match "(\{[A-F0-9\-]+\})") {
                    $prodCode = $Matches[1]
                    Write-Host "  [MSI] Removing $prodCode silently ..." -ForegroundColor Yellow
                    $p = Start-Process "msiexec.exe" `
                        -ArgumentList "/x `"$prodCode`" /qn /norestart REBOOT=ReallySuppress" `
                        -Wait -PassThru -WindowStyle Hidden
                    Write-Host "  [MSI] Exit code: $($p.ExitCode)" -ForegroundColor DarkGray
                }

            } elseif ($uninstStr -match "miktex-console\.exe") {
                # ── MiKTeX special case ──────────────────────────────────
                # miktex-console.exe always opens a GUI. Use miktexsetup.exe
                # which is in the same bin folder and supports --unattended.
                if ($uninstStr -match '^"([^"]+)"') {
                    $consolePath = $Matches[1]
                } else {
                    $consolePath = ($uninstStr -split " ")[0]
                }
                $binDir  = Split-Path $consolePath -Parent
                $setupExe = Join-Path $binDir "miktexsetup.exe"

                if (Test-Path $setupExe) {
                    Write-Host "  [MIKTEX] Running miktexsetup --unattended uninstall ..." -ForegroundColor Yellow
                    $p = Start-Process -FilePath $setupExe `
                             -ArgumentList "--unattended uninstall" `
                             -PassThru -WindowStyle Hidden
                    # Wait up to 120 seconds, then kill if still running
                    $p | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
                    if (-not $p.HasExited) {
                        Write-Host "  [TIMEOUT] miktexsetup did not finish - killing process." -ForegroundColor Red
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    }
                    Write-Host "  [MIKTEX] Exit code: $($p.ExitCode)" -ForegroundColor DarkGray
                } else {
                    Write-Host "  [MIKTEX] miktexsetup.exe not found at $setupExe" -ForegroundColor Red
                    Write-Host "  [MIKTEX] Skipping uninstaller - will rely on manual folder/registry cleanup below." -ForegroundColor Yellow
                }

            } else {
                # ── Generic EXE (NSIS / Inno Setup / etc.) ───────────────
                if ($uninstStr -match '^"([^"]+)"(.*)') {
                    $exe  = $Matches[1]
                    $args = $Matches[2].Trim()
                } else {
                    $parts = $uninstStr -split " ", 2
                    $exe   = $parts[0]
                    $args  = if ($parts.Count -gt 1) { $parts[1] } else { "" }
                }

                # Append silent flags if not already present
                if ($args -notmatch "/S|/silent|/SILENT|/quiet|/VERYSILENT") {
                    $args = "/S /VERYSILENT /NORESTART $args".Trim()
                }

                Write-Host "  [EXE] $exe $args ..." -ForegroundColor Yellow
                $p = Start-Process -FilePath $exe -ArgumentList $args `
                         -Wait -PassThru -WindowStyle Hidden
                Write-Host "  [EXE] Exit code: $($p.ExitCode)" -ForegroundColor DarkGray
            }

            Write-Host "  [OK]  Done: $($entry.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Uninstaller failed: $_" -ForegroundColor Red
        }
    }
}

# Delete all Uninstall registry keys whose DisplayName matches $pattern
function Remove-UninstallKeys ($pattern) {
    $bases = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like "*$pattern*") {
                Write-Host "  [REG DEL] $($_.PSPath)" -ForegroundColor Yellow
                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ── Resolve user profile ─────────────────────────────────────
$realUser = (Get-CimInstance Win32_ComputerSystem).UserName
$userHome = if ($realUser) {
    "C:\Users\$($realUser.Split('\')[-1])"
} else {
    $env:USERPROFILE
}

$Roaming  = "$userHome\AppData\Roaming"
$Local    = "$userHome\AppData\Local"
$Programs = "$userHome\AppData\Local\Programs"
$PF       = "C:\Program Files"
$PF86     = "C:\Program Files (x86)"

Write-Host "`nUser profile resolved to: $userHome" -ForegroundColor Magenta


# ════════════════════════════════════════════════════════════
#  STEP 1 — Kill all LyX & MiKTeX processes BEFORE uninstalling
# ════════════════════════════════════════════════════════════
Write-Header "Killing LyX and MiKTeX processes"

Stop-ByName @(
    "lyx", "lyxclient",
    "miktex", "miktex-console", "miktexsetup",
    "latex", "pdflatex", "xelatex", "lualatex",
    "bibtex", "biber", "makeindex",
    "texworks", "yap"
)

# Also kill anything running from LyX or MiKTeX folders
Stop-ProcessesInFolder "$PF\LyX"
Stop-ProcessesInFolder "$PF86\LyX"
Stop-ProcessesInFolder "$PF\MiKTeX"
Stop-ProcessesInFolder "$PF86\MiKTeX"
Stop-ProcessesInFolder "$Programs\LyX"
Stop-ProcessesInFolder "$Programs\MiKTeX"

# Kill by folder wildcard (handles "LyX 2.3", "LyX 2.4", etc.)
Get-ChildItem "$PF\LyX*", "$PF86\LyX*" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-ProcessesInFolder $_.FullName
}

Start-Sleep -Seconds 2


# ════════════════════════════════════════════════════════════
#  STEP 2 — Uninstall LyX
# ════════════════════════════════════════════════════════════
Write-Header "Uninstalling LyX (silent)"
Invoke-AllUninstallers "LyX"

# Wait for uninstaller to finish releasing file handles
Start-Sleep -Seconds 3

Write-Header "Removing LyX folders (including locked LyX 2.*)"

# Use parent dir + -Filter so "LyX 2.5", "LyX 2.4" etc. are all found correctly
foreach ($base in @($PF, $PF86, $Programs)) {
    if (Test-Path $base) {
        Get-ChildItem -Path $base -Filter "LyX*" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-FolderForce $_.FullName }
    }
}

Remove-SafeItem "$Roaming\LyX*"
Remove-SafeItem "$Local\LyX*"

Write-Header "Removing LyX registry keys"
Remove-UninstallKeys "LyX"
foreach ($key in @("HKCU:\SOFTWARE\LyX","HKLM:\SOFTWARE\LyX","HKLM:\SOFTWARE\WOW6432Node\LyX")) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force
        Write-Host "  [REG DEL] $key" -ForegroundColor Yellow
    }
}


# ════════════════════════════════════════════════════════════
#  STEP 3 — Uninstall MiKTeX
# ════════════════════════════════════════════════════════════
Write-Header "Uninstalling MiKTeX (silent, no GUI)"
Invoke-AllUninstallers "MiKTeX"

Start-Sleep -Seconds 3

Write-Header "Removing MiKTeX folders"
foreach ($base in @($PF, $PF86, $Programs)) {
    if (Test-Path $base) {
        Get-ChildItem -Path $base -Filter "MiKTeX*" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-FolderForce $_.FullName }
    }
}
Remove-SafeItem "$Roaming\MiKTeX"
Remove-SafeItem "$Roaming\TUG"
Remove-SafeItem "$Local\MiKTeX"
Remove-SafeItem "C:\ProgramData\MiKTeX"

Write-Header "Removing MiKTeX registry keys"
Remove-UninstallKeys "MiKTeX"
foreach ($key in @(
    "HKCU:\SOFTWARE\MiKTeX.org", "HKCU:\SOFTWARE\MiKTeX",
    "HKLM:\SOFTWARE\MiKTeX.org", "HKLM:\SOFTWARE\MiKTeX",
    "HKLM:\SOFTWARE\WOW6432Node\MiKTeX.org", "HKLM:\SOFTWARE\WOW6432Node\MiKTeX"
)) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force
        Write-Host "  [REG DEL] $key" -ForegroundColor Yellow
    }
}


# ════════════════════════════════════════════════════════════
#  STEP 4 — PATH clean-up
# ════════════════════════════════════════════════════════════
Write-Header "Cleaning PATH environment variables"
foreach ($target in @("Machine", "User")) {
    $current = [System.Environment]::GetEnvironmentVariable("PATH", $target)
    if ($current) {
        $cleaned = ($current -split ";" | Where-Object { $_ -notmatch "MiKTeX|LyX" }) -join ";"
        if ($cleaned -ne $current) {
            [System.Environment]::SetEnvironmentVariable("PATH", $cleaned, $target)
            Write-Host "  [PATH] Cleaned $target PATH." -ForegroundColor Yellow
        }
    }
}


# ════════════════════════════════════════════════════════════
#  STEP 5 — Verification
# ════════════════════════════════════════════════════════════
Write-Header "Verification"

$remaining = Get-ItemProperty (
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
) -ErrorAction SilentlyContinue |
Where-Object { $_.DisplayName -like "*MiKTeX*" -or $_.DisplayName -like "*LyX*" }

if ($remaining) {
    Write-Host "  [WARN] Still present in Add/Remove Programs:" -ForegroundColor Red
    $remaining | ForEach-Object { Write-Host "    - $($_.DisplayName)  [$($_.PSPath)]" -ForegroundColor Red }
} else {
    Write-Host "  [OK] No MiKTeX or LyX entries remain in Add/Remove Programs." -ForegroundColor Green
}

$leftoverFolders = foreach ($base in @($PF, $PF86, $Programs)) {
    if (Test-Path $base) {
        Get-ChildItem -Path $base -Filter "LyX*"    -Directory -ErrorAction SilentlyContinue
        Get-ChildItem -Path $base -Filter "MiKTeX*" -Directory -ErrorAction SilentlyContinue
    }
}

if ($leftoverFolders) {
    Write-Host "  [WARN] These folders still exist:" -ForegroundColor Red
    $leftoverFolders | ForEach-Object { Write-Host "    - $($_.FullName)" -ForegroundColor Red }
} else {
    Write-Host "  [OK] No leftover program folders found." -ForegroundColor Green
}


# ════════════════════════════════════════════════════════════
#  Done
# ════════════════════════════════════════════════════════════
Write-Host "`n[DONE]  Uninstall complete.  A reboot is recommended to finish cleanup." -ForegroundColor Green
