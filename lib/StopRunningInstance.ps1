# Shared "stop the currently running py-sensor" helper. Used by both
# install.ps1 (before overwriting vendor/ or app/ files out from under a live
# process) and Uninstall.ps1 (before deleting everything). Dot-sourced by
# both, same pattern as lib/PythonCheck.ps1.

function Stop-PySensorInstance {
    <#
      Finds any python.exe/pythonw.exe running this install's app/main.py and
      force-stops it, then waits for the OS to actually finish tearing the
      process down - Stop-Process returns once termination is requested, but
      Windows can take a moment longer to release file/DLL handles (e.g. a
      loaded PIL .pyd under vendor/), which showed up for real as a flaky
      pip failure right after reinstalling with only a fixed sleep here.
    #>
    # Returns $true if it found (and stopped) a running instance, $false if
    # there was nothing to stop - so callers can print an accurate message.
    param(
        [Parameter(Mandatory)][string]$AppDir
    )

    $runningInstance = Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" |
        Where-Object { $_.CommandLine -like "*$AppDir\main.py*" }
    if (-not $runningInstance) { return $false }

    $stoppedIds = $runningInstance | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $_.ProcessId
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        $stillRunning = $stoppedIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
        if (-not $stillRunning) { break }
        Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Milliseconds 500
    return $true
}
