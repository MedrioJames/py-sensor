# Entry point used both by the Startup-folder shortcut (auto-launch at
# login) and "Start py-sensor.lnk" (manual launch). Runs silently on success
# -- the tray icon appearing IS the success feedback, unlike L10 Manager's
# splash window (a foreground app the user is waiting to see). Only pops a
# message box if something's actually wrong and needs the user's attention.

$ErrorActionPreference = 'Stop'
$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = Split-Path -Parent $appDir
. (Join-Path $installDir 'lib\PythonCheck.ps1')

Add-Type -AssemblyName System.Windows.Forms

function Show-Message {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message, "py-sensor",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Confirm-Prompt {
    param([string]$Message)
    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message, "py-sensor",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    return $result -eq [System.Windows.Forms.DialogResult]::OK
}

# --- Python + pip check ---
$python = Resolve-Python -ShowMessage ${function:Show-Message} -Confirm ${function:Confirm-Prompt}

if (-not $python) {
    Show-Message "py-sensor can't run without Python. It will not start this time."
    exit 1
}

if (-not (Test-Pip -PythonExe $python.PythonExe)) {
    Show-Message ("py-sensor needs a working pip alongside Python, but couldn't find one.`r`n`r`n" +
        "Reinstalling Python from python.org (which bundles pip by default) should fix this.")
    exit 1
}

# --- Launch the app ---
# vendor/ holds pystray + its dependencies, installed there (not the global
# site-packages) by install.ps1 -- PYTHONPATH is how main.py finds them.
$env:PYTHONPATH = Join-Path $installDir 'vendor'

$mainScript = Join-Path $appDir 'main.py'
$exe = if ($python.PythonwExe) { $python.PythonwExe } else { $python.PythonExe }
Start-Process -FilePath $exe -ArgumentList "`"$mainScript`"" -WorkingDirectory $appDir
