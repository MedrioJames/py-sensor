# Small standalone helper (run via `-File`, not dot-sourced) so startup.py can
# create a .lnk from Python without needing pywin32 -- .lnk is a COM object,
# not a format Python's stdlib can write directly, so this shells out to the
# same WScript.Shell technique install.ps1 already uses for its own shortcuts.
# Static local script, never downloaded/eval'd content.

param(
    [Parameter(Mandatory)][string]$ShortcutPath,
    [Parameter(Mandatory)][string]$TargetPath,
    [string]$Arguments = '',
    [string]$WorkingDirectory = ''
)

$ErrorActionPreference = 'Stop'

$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $TargetPath
if ($Arguments) { $shortcut.Arguments = $Arguments }
if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
$shortcut.Save()
