"""Manage the Startup-folder shortcut that auto-launches py-sensor at login.

The shortcut's presence *is* the setting -- config.json's launch_at_startup
value only reflects what Settings showed when it was last saved; is_enabled()
is the source of truth, and settings_ui.py re-reads it each time the window
opens so it can't drift from reality.
"""

import os
import subprocess
from pathlib import Path

STARTUP_DIR = (
    Path(os.environ["APPDATA"]) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
)
SHORTCUT_NAME = "py-sensor.lnk"


def _app_dir() -> Path:
    return Path(__file__).resolve().parent


def _shortcut_path() -> Path:
    return STARTUP_DIR / SHORTCUT_NAME


def is_enabled() -> bool:
    return _shortcut_path().exists()


def enable() -> None:
    if is_enabled():
        return

    launcher = _app_dir() / "launcher.ps1"
    create_script = _app_dir().parent / "lib" / "CreateShortcut.ps1"
    system_powershell = (
        Path(os.environ["WINDIR"]) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
    )

    STARTUP_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            str(system_powershell),
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", str(create_script),
            "-ShortcutPath", str(_shortcut_path()),
            "-TargetPath", str(system_powershell),
            "-Arguments", f'-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{launcher}"',
            "-WorkingDirectory", str(_app_dir()),
        ],
        check=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )


def disable() -> None:
    path = _shortcut_path()
    if path.exists():
        path.unlink()
