# py-sensor - Setup
#
# Builds the one, self-contained py-sensor install at %LOCALAPPDATA%\py-sensor.
# Runs from the copy-paste one-liner (downloads this file, then runs it with
# -File), from PySensor-Setup.bat, or directly from a local clone of this
# repo for development/testing - all three are handled below, mirroring
# l10-manager's install.ps1 dual-mode pattern exactly.
#
# -Port / -ApiKey are optional and exist so a caller like DayHUD can generate
# a customized install for a specific user (its own chosen port, a per-install
# random key) rather than the zero-config defaults - see CLAUDE.md. Both only
# ever seed a config.json that doesn't exist yet; an existing config.json
# (a reinstall/update) is never touched, same as every other setting.
#
# -Ref is what app/updater.py passes when applying an in-app update: a
# specific released tag (e.g. "v0.3.0") to install from, instead of the
# default "main" - so an update always lands exactly what that release
# published, not whatever's since landed on main.

param(
    [string]$Port = '',
    [string]$ApiKey = '',
    [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'

# --- Repo / mode detection -------------------------------------------------

$RepoOwner = 'MedrioJames'
$RepoName = 'py-sensor'
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Ref"

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

function Get-SharedScriptPath {
    # Resolves a lib/*.ps1 to a real local path, downloading it to %TEMP%
    # first if this is a standalone run - returns the path rather than
    # dot-sourcing it directly, because dot-sourcing *inside* a function only
    # adds definitions to that function's own scope in PowerShell, not the
    # caller's; the actual `.` has to happen at the caller's scope, which is
    # why every call site below is `. (Get-SharedScriptPath ...)`, never a
    # dot-source hidden inside this function.
    #
    # install.ps1 is always launched via `-File` under -ExecutionPolicy
    # Bypass (see PySensor-Setup.bat / the README one-liner) rather than
    # piped into iex, so the whole process already runs under Bypass -
    # dot-sourcing a downloaded file here works fine and doesn't need an
    # in-memory eval trick. Deliberately avoiding fileless script evaluation
    # (ScriptBlock::Create/iex on downloaded text): it's a heavily-signatured
    # pattern for security tooling, even when the content itself is benign.
    param([string]$RelativePath)
    if ($LocalRoot) {
        return (Join-Path $LocalRoot $RelativePath)
    }
    $tmpLib = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName() + '.ps1')
    Invoke-WebRequest -Uri "$RawBase/$RelativePath" -OutFile $tmpLib -TimeoutSec 30
    return $tmpLib
}

$pythonCheckPath = Get-SharedScriptPath 'lib\PythonCheck.ps1'
. $pythonCheckPath
if (-not $LocalRoot) { Remove-Item $pythonCheckPath -Force -ErrorAction SilentlyContinue }

$stopInstancePath = Get-SharedScriptPath 'lib\StopRunningInstance.ps1'
. $stopInstancePath
if (-not $LocalRoot) { Remove-Item $stopInstancePath -Force -ErrorAction SilentlyContinue }

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

if ($Port -ne '' -and ($Port -notmatch '^\d+$' -or [int]$Port -lt 1 -or [int]$Port -gt 65535)) {
    Write-Host "  Ignoring invalid -Port value '$Port' (must be 1-65535) - using the default instead." -ForegroundColor Yellow
    $Port = ''
}

$installDir = Join-Path $env:LOCALAPPDATA 'py-sensor'
$appDir = Join-Path $installDir 'app'
$libDir = Join-Path $installDir 'lib'
$vendorDir = Join-Path $installDir 'vendor'
$configPath = Join-Path $installDir 'config.json'

# Stop any already-running py-sensor from a previous install before touching its
# files - otherwise pip's --upgrade can't replace a native DLL under vendor/
# (e.g. PIL's _avif.pyd) while the running process still has it loaded, and
# fails with a confusing WinError 5 "Access is denied" mid-install.
if (Stop-PySensorInstance -AppDir $appDir) {
    Write-Host "    - stopped the currently running py-sensor so its files can be updated" -ForegroundColor DarkGray
}

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

if ((-not (Test-Path $configPath)) -and ($Port -ne '' -or $ApiKey -ne '')) {
    # Reuses config.py's own load/save (rather than duplicating its default
    # schema here in PowerShell) so this stays correct as that schema evolves.
    # Written to a real temp .py file rather than passed inline via `-c` -
    # PowerShell mangles embedded double-quotes when building a native
    # command line from a string argument (cfg["port"] arrived at Python as
    # cfg[port], a real bug hit while testing this), and a file sidesteps
    # that whole class of quoting problem, matching the "run from a real
    # file" pattern already used everywhere else in this repo.
    Write-Host "    - applying the port/API key passed to this installer..." -ForegroundColor DarkGray
    $seedCode = @'
import sys
sys.path.insert(0, sys.argv[3])
import config
cfg = config.load_config()
if sys.argv[1]:
    cfg["port"] = int(sys.argv[1])
if sys.argv[2]:
    cfg["api_key"] = sys.argv[2]
config.save_config(cfg)
'@
    $tmpSeedScript = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName() + '.py')
    Set-Content -Path $tmpSeedScript -Value $seedCode -Encoding UTF8 -NoNewline
    & $python.PythonExe $tmpSeedScript $Port $ApiKey $appDir
    Remove-Item $tmpSeedScript -Force -ErrorAction SilentlyContinue
}

Write-Host "    - installing the tray-icon component (pystray) into a private folder just for py-sensor..." -ForegroundColor DarkGray
$pipAttempts = 3
for ($attempt = 1; $attempt -le $pipAttempts; $attempt++) {
    & $python.PythonExe -m pip install --upgrade --target $vendorDir pystray
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -lt $pipAttempts) {
        Write-Host "    - pip install hit a snag (attempt $attempt of $pipAttempts) - retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}
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
