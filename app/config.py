"""config.json load/save.

Lives at %LOCALAPPDATA%\\py-sensor\\config.json -- separate from the app code
so re-running install.ps1 to pick up a code update never touches it, and so
a manual `python app/main.py` run from a dev checkout and the installed copy
share the same settings.
"""

import json
import os
import threading
from pathlib import Path

from sensors import SENSORS

CONFIG_DIR = Path(os.environ["LOCALAPPDATA"]) / "py-sensor"
CONFIG_PATH = CONFIG_DIR / "config.json"

DEFAULT_PORT = 8765

_lock = threading.Lock()


def _defaults() -> dict:
    return {
        "port": DEFAULT_PORT,
        "sensors": {name: {"enabled": True} for name in SENSORS},
        "launch_at_startup": True,
        "home_assistant": {
            # Scaffold only -- no push logic yet. See CLAUDE.md.
            "enabled": False,
            "url": "",
            "token": "",
        },
    }


def _merge_defaults(cfg: dict) -> dict:
    """Fills in any keys missing from an on-disk config (e.g. after adding a
    new sensor or a new top-level setting) without disturbing what's there."""
    merged = _defaults()
    merged["port"] = cfg.get("port", merged["port"])
    merged["launch_at_startup"] = cfg.get("launch_at_startup", merged["launch_at_startup"])

    on_disk_sensors = cfg.get("sensors", {})
    for name in merged["sensors"]:
        if name in on_disk_sensors and "enabled" in on_disk_sensors[name]:
            merged["sensors"][name]["enabled"] = bool(on_disk_sensors[name]["enabled"])

    on_disk_ha = cfg.get("home_assistant", {})
    for key in merged["home_assistant"]:
        if key in on_disk_ha:
            merged["home_assistant"][key] = on_disk_ha[key]

    return merged


def load_config() -> dict:
    with _lock:
        if not CONFIG_PATH.exists():
            cfg = _defaults()
            _write(cfg)
            return cfg
        try:
            cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            cfg = {}
        return _merge_defaults(cfg)


def save_config(cfg: dict) -> None:
    with _lock:
        _write(cfg)


def _write(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
