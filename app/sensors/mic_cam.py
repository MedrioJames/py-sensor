"""Microphone/camera-in-use sensors.

Ported from the DayHUD prototype (mic-cam-detector.py). Windows records, per
app, when it last started/stopped using the microphone or camera, under

  HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone
  HKCU\\...\\ConsentStore\\webcam

(and each key's "NonPackaged" child, where ordinary desktop apps register --
Store apps register directly under the parent key). An app is currently using
the device if its LastUsedTimeStop is 0 while LastUsedTimeStart is not.

Deliberately no background polling loop here -- each call re-reads the
registry fresh, so there's nothing to fall out of sync (same reasoning as the
original prototype).

Requires Settings -> Privacy & security -> Camera/Microphone -> the "let
Windows apps access your camera/microphone" history to be enabled (on by
default) -- that's what populates these registry keys at all.
"""

import winreg

_BASE_PATHS = {
    "mic": r"SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone",
    "cam": r"SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam",
}


def _subkey_in_use(key):
    """True if any child under `key` has LastUsedTimeStop == 0 (in use right now)."""
    i = 0
    while True:
        try:
            name = winreg.EnumKey(key, i)
        except OSError:
            break
        i += 1
        try:
            with winreg.OpenKey(key, name) as sub:
                start, _ = winreg.QueryValueEx(sub, "LastUsedTimeStart")
                stop, _ = winreg.QueryValueEx(sub, "LastUsedTimeStop")
                if start and not stop:
                    return True
        except OSError:
            continue  # this subkey doesn't have the usual values -- skip it
    return False


def _device_active(base_path):
    for path in (base_path, base_path + "\\NonPackaged"):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path) as key:
                if _subkey_in_use(key):
                    return True
        except OSError:
            continue  # key doesn't exist on this machine (e.g. no NonPackaged yet)
    return False


def mic_active() -> bool:
    return _device_active(_BASE_PATHS["mic"])


def cam_active() -> bool:
    return _device_active(_BASE_PATHS["cam"])
