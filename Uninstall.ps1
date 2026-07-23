# py-sensor - Uninstall
#
# Fully removes py-sensor from this computer: stops the running instance,
# removes the Startup-folder shortcut, then deletes this entire install
# folder (including this script itself - see the note near the bottom for
# why that's a detached step). Lives inside the install folder itself
# (%LOCALAPPDATA%\py-sensor\Uninstall.ps1), deployed there by install.ps1
# like every other app file - never downloaded fresh, since uninstalling
# shouldn't need internet access at all.
#
# -Confirmed skips the interactive prompt below - only ever passed when the
# tray icon's "Uninstall py-sensor..." menu item already got a yes/no answer
# from the user via its own Tkinter dialog. A double-click of this file (or
# Uninstall.bat next to it) always confirms interactively instead.

param(
    [switch]$Confirmed
)

$ErrorActionPreference = 'Stop'
$installDir = $PSScriptRoot
$appDir = Join-Path $installDir 'app'

# Refuse to run against a git checkout (this file also sits in the repo
# itself, not just the deployed install) - the exact same is_dev_checkout()
# guard app/updater.py uses, applied here because $installDir is about to be
# recursively deleted below and a checkout is never something that's safe
# to blow away.
if (Test-Path (Join-Path $installDir '.git')) {
    Write-Host ""
    Write-Host "  Refusing to run: '$installDir' looks like a git checkout, not a deployed" -ForegroundColor Red
    Write-Host "  install - this would delete your repo. Run the copy under %LOCALAPPDATA%\py-sensor instead." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Clear-Host
Write-Host ""
Write-Host "  py-sensor - Uninstall" -ForegroundColor Cyan
Write-Host "  ----------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""

if (-not $Confirmed) {
    Write-Host "  This will completely remove py-sensor from this computer:" -ForegroundColor Yellow
    Write-Host "    - stop it if it's currently running"
    Write-Host "    - remove its Startup-at-login shortcut"
    Write-Host "    - delete $installDir (including all settings)"
    Write-Host ""
    $answer = Read-Host "  Type YES to continue, or press Enter to cancel"
    if ($answer -ne 'YES') {
        Write-Host ""
        Write-Host "  Cancelled - nothing was removed." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

. (Join-Path $installDir 'lib\StopRunningInstance.ps1')
if (Stop-PySensorInstance -AppDir $appDir) {
    Write-Host "  Stopped the running py-sensor." -ForegroundColor DarkGray
}

$startupShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\py-sensor.lnk'
if (Test-Path $startupShortcut) {
    Remove-Item $startupShortcut -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed the Startup shortcut." -ForegroundColor DarkGray
}

Write-Host "  Removing $installDir ..." -ForegroundColor DarkGray

# This script (and Uninstall.bat next to it) live inside $installDir, so they
# can't delete their own containing folder from within this still-running
# process - Windows keeps a handle open on a script file while it's actively
# executing. Written to a real temp file (never passed as an inline -Command
# string - the `python -c` double-quote mangling bug hit earlier this repo's
# life is exactly the class of problem that pattern invites) so a detached
# process can wait for this one to fully exit, then delete everything,
# itself included.
$tmpCleanup = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName() + '.ps1')
$cleanupScript = @"
Start-Sleep -Seconds 2
# A single delete attempt right after the 2-second wait isn't always enough -
# testing this for real hit a case where some file under vendor/ was still
# briefly locked (well after Stop-PySensorInstance's own poll-for-exit
# returned), the exact same class of transient-lock race install.ps1's pip
# step already had to work around. Retry a few times rather than trust one
# fixed delay.
for (`$attempt = 1; `$attempt -le 5; `$attempt++) {
    Remove-Item -LiteralPath '$installDir' -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath '$installDir')) { break }
    Start-Sleep -Seconds 1
}
Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@
Set-Content -Path $tmpCleanup -Value $cleanupScript -Encoding UTF8

$systemPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $systemPowerShell -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-File', $tmpCleanup) -WindowStyle Hidden

Write-Host ""
Write-Host "  All done - py-sensor is uninstalled." -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2
