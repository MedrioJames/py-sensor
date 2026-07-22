# py-sensor - Setup
#
# Builds the one, self-contained py-sensor install at %LOCALAPPDATA%\py-sensor.
# Runs from the copy-paste one-liner (downloads this file, then runs it with
# -File), from PySensor-Setup.bat, or directly from a local clone of this
# repo for development/testing - all three are handled below, mirroring
# l10-manager's install.ps1 dual-mode pattern exactly.

$ErrorActionPreference = 'Stop'

# --- Repo / mode detection -------------------------------------------------

$RepoOwner = 'MedrioJames'
$RepoName = 'py-sensor'
$Branch = 'main'
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

$LocalRoot = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'manifest.json'))) {
    $LocalRoot = $PSScriptRoot
}

function Get-RepoBytes {
    # ",$bytes" (comma-prefixed) forces PowerShell to return the byte array
    # as-is rather than unrolling it - without this, a zero-length array (an
    # empty file) comes back as $null to the caller, which then crashes
    # WriteAllBytes. Same gotcha l10-manager's install.ps1 hit for real.
    param([string]$RelativePath)
    if ($LocalRoot) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $LocalRoot $RelativePath))
        return , $bytes
    }
    $tmp = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName())
    Invoke-WebRequest -Uri "$RawBase/$RelativePath" -OutFile $tmp -TimeoutSec 30
    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return , $bytes
}

function Get-Manifest {
    if ($LocalRoot) {
        return Get-Content (Join-Path $LocalRoot 'manifest.json') -Raw | ConvertFrom-Json
    }
    return Invoke-RestMethod -Uri "$RawBase/manifest.json" -TimeoutSec 15
}

# --- Banner ---------------------------------------------------------------

Clear-Host
Write-Host ""
Write-Host "  py-sensor - Setup" -ForegroundColor Cyan
Write-Host "  ----------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""

$manifest = Get-Manifest
Write-Host "  Version $($manifest.version)" -ForegroundColor DarkGray
Write-Host ""

# --- Step 1: Python + pip ---------------------------------------------

Write-Host "  Step 1 of 3 - Checking Python" -ForegroundColor Cyan
Write-Host ""

if ($LocalRoot) {
    . (Join-Path $LocalRoot 'lib\PythonCheck.ps1')
} else {
    # install.ps1 is always launched via `-File` under -ExecutionPolicy Bypass
    # (see PySensor-Setup.bat / the README one-liner) rather than piped into
    # iex, so the whole process already runs under Bypass - dot-sourcing a
    # downloaded file here works fine and doesn't need an in-memory eval
    # trick. Deliberately avoiding fileless script evaluation (ScriptBlock::
    # Create/iex on downloaded text): it's a heavily-signatured pattern for
    # security tooling, even when the content itself is benign.
    $tmpLib = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName() + '.ps1')
    Invoke-WebRequest -Uri "$RawBase/lib/PythonCheck.ps1" -OutFile $tmpLib -TimeoutSec 30
    . $tmpLib
    Remove-Item $tmpLib -Force -ErrorAction SilentlyContinue
}

$showMessage = {
    param($m)
    Write-Host ""
    Write-Host "  $m" -ForegroundColor Yellow
    Write-Host ""
}
$confirm = {
    param($m)
    (Read-Host "  $m [press Enter to continue, or type 'cancel' to stop]") -ne 'cancel'
}

$python = Resolve-Python -ShowMessage $showMessage -Confirm $confirm
if (-not $python) {
    Write-Host ""
    Write-Host "  Setup cancelled - Python is required to continue." -ForegroundColor Red
    exit 1
}
Write-Host "  Python looks good ($($python.PythonExe))" -ForegroundColor Green

if (-not (Test-Pip -PythonExe $python.PythonExe)) {
    Write-Host ""
    Write-Host "  pip isn't working alongside this Python install." -ForegroundColor Red
    Write-Host "  Reinstalling Python from python.org (which bundles pip by default) should fix this." -ForegroundColor Red
    exit 1
}
Write-Host "  pip looks good" -ForegroundColor Green
Write-Host ""

# --- Step 2: build the install folder ------------------------------------

Write-Host "  Step 2 of 3 - Installing to %LOCALAPPDATA%\py-sensor" -ForegroundColor Cyan
Write-Host ""

$installDir = Join-Path $env:LOCALAPPDATA 'py-sensor'
$appDir = Join-Path $installDir 'app'
$libDir = Join-Path $installDir 'lib'
$vendorDir = Join-Path $installDir 'vendor'

foreach ($dir in @($installDir, $appDir, $libDir, $vendorDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

foreach ($file in $manifest.app_files) {
    Write-Host "    - $($file.dest)" -ForegroundColor DarkGray
    $destPath = Join-Path $installDir $file.dest
    $destDir = Split-Path $destPath -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $bytes = Get-RepoBytes $file.src
    [System.IO.File]::WriteAllBytes($destPath, $bytes)
}

Set-Content -Path (Join-Path $appDir 'version.txt') -Value $manifest.version -NoNewline

Write-Host "    - installing the tray-icon component (pystray) into a private folder just for py-sensor..." -ForegroundColor DarkGray
& $python.PythonExe -m pip install --upgrade --target $vendorDir pystray
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  pip install failed - check your internet connection and try again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Install folder ready." -ForegroundColor Green
Write-Host ""

# --- Step 3: shortcuts + launch -------------------------------------------

Write-Host "  Step 3 of 3 - Shortcuts" -ForegroundColor Cyan
Write-Host ""

$systemPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launcherPath = Join-Path $appDir 'launcher.ps1'
$launchArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPath`""

$wshell = New-Object -ComObject WScript.Shell

$startShortcut = $wshell.CreateShortcut((Join-Path $installDir 'Start py-sensor.lnk'))
$startShortcut.TargetPath = $systemPowerShell
$startShortcut.Arguments = $launchArgs
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Description = "Start py-sensor"
$startShortcut.Save()

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
$startupShortcut = $wshell.CreateShortcut((Join-Path $startupDir 'py-sensor.lnk'))
$startupShortcut.TargetPath = $systemPowerShell
$startupShortcut.Arguments = $launchArgs
$startupShortcut.WorkingDirectory = $installDir
$startupShortcut.Description = "Start py-sensor"
$startupShortcut.Save()

Write-Host "  Shortcuts created - py-sensor will start automatically at login." -ForegroundColor Green
Write-Host "  (Turn this off any time from the tray icon's Settings.)" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Starting py-sensor now..." -ForegroundColor Cyan
Start-Process -FilePath $systemPowerShell -ArgumentList $launchArgs -WorkingDirectory $installDir

Write-Host ""
Write-Host "  All done! Look for the py-sensor icon in your system tray (near the clock)." -ForegroundColor White
Write-Host "  Installed at: $installDir" -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 3
