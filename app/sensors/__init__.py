"""Sensor registry.

To add a new sensor: write a module with a zero-arg function returning bool
(True = active/in-use), then register it below. config.py, server.py, and
settings_ui.py all iterate this dict rather than hardcoding sensor names, so
that's the only place a new sensor needs to be wired in.
"""

from dataclasses import dataclass
from typing import Callable, Dict

from . import mic_cam


@dataclass(frozen=True)
class Sensor:
    label: str
    check: Callable[[], bool]


SENSORS: Dict[str, Sensor] = {
    "mic": Sensor(label="Microphone", check=mic_cam.mic_active),
    "cam": Sensor(label="Camera", check=mic_cam.cam_active),
}
