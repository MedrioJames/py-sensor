# py-sensor - Setup
#
# Builds the one, self-contained py-sensor install at %LOCALAPPDATA%\py-sensor
# from THIS checkout. There's no GitHub repo yet, so unlike l10-manager's
# install.ps1 this only has the local-checkout code path - add a
# raw.githubusercontent.com fetch branch here (mirroring l10-manager's
# install.ps1/manifest.json) once a repo exists to publish to. See CLAUDE.md.

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

Clear-Host
Write-Host ""
Write-Host "  py-sensor - Setup" -ForegroundColor Cyan
Write-Host "  ----------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""

# --- Step 1: Python + pip -----------------------------------------------

Write-Host "  Step 1 of 3 - Checking Python" -ForegroundColor Cyan
Write-Host ""

. (Join-Path $repoRoot 'lib\PythonCheck.ps1')

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

Write-Host "    - copying app files..." -ForegroundColor DarkGray
Copy-Item -Path (Join-Path $repoRoot 'app\*') -Destination $appDir -Recurse -Force
Get-ChildItem -Path $appDir -Directory -Recurse -Filter '__pycache__' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "    - copying lib files..." -ForegroundColor DarkGray
Copy-Item -Path (Join-Path $repoRoot 'lib\*') -Destination $libDir -Recurse -Force

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
