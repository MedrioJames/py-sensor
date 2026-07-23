"""System tray icon (pystray).

Runs pystray's Icon.run() on its own daemon thread (on Windows this is safe --
pystray's Win32 backend is just a hidden window pumping its own message loop,
which works fine off the main thread; only macOS's Cocoa backend requires the
main thread). Menu callbacks fire on that thread, so anything touching a
Tkinter widget or app-wide state is marshaled onto the Tk thread via
`root.after(0, ...)` -- never call into Tk directly from here.
"""

import threading
import webbrowser

import pystray
from PIL import Image, ImageDraw


def _make_icon_image():
    """Generates a computer/monitor glyph at runtime -- no shipped .ico/.png
    asset to keep in sync as the app evolves. Deliberately not a microphone:
    py-sensor monitors the computer as a whole (mic/cam are just the first
    two sensors), so the icon shouldn't over-represent one of them -- a
    monitor reads as "this machine," which stays accurate as more sensors get
    added later. An earlier mic-glyph version is why this one was checked at
    actual tray size (~16px) before shipping it, same as that one was."""
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    circle_box = (4, 4, size - 4, size - 4)
    draw.ellipse(circle_box, fill=(37, 99, 235, 255))
    circle_cy = (circle_box[1] + circle_box[3]) / 2

    white = (255, 255, 255, 255)
    cx = size / 2

    screen_w, screen_h = size * 0.48, size * 0.34
    neck_w, neck_h = size * 0.09, size * 0.07
    foot_w, foot_h = size * 0.30, size * 0.045

    # Center the whole glyph (screen+neck+foot stacked) on the circle's own
    # center, rather than the screen alone on a fixed offset -- an earlier
    # version did the latter, which left the glyph sitting visibly above
    # center once the neck+foot were added below it.
    total_h = screen_h + neck_h + foot_h
    top = circle_cy - total_h / 2

    # Screen
    screen_box = (cx - screen_w / 2, top, cx + screen_w / 2, top + screen_h)
    draw.rounded_rectangle(screen_box, radius=size * 0.035, fill=white)

    # Neck
    neck_top = top + screen_h
    draw.rectangle((cx - neck_w / 2, neck_top, cx + neck_w / 2, neck_top + neck_h), fill=white)

    # Foot
    foot_top = neck_top + neck_h
    draw.rounded_rectangle(
        (cx - foot_w / 2, foot_top, cx + foot_w / 2, foot_top + foot_h), radius=foot_h / 2, fill=white
    )
    return img


class TrayIcon:
    def __init__(self, root, get_port, open_settings, check_for_updates, uninstall, quit_app):
        self._root = root
        self._get_port = get_port
        self._open_settings = open_settings
        self._check_for_updates = check_for_updates
        self._uninstall = uninstall
        self._quit_app = quit_app
        self._icon = pystray.Icon(
            "py-sensor",
            _make_icon_image(),
            "py-sensor",
            menu=pystray.Menu(
                pystray.MenuItem("Settings...", self._on_settings),
                pystray.MenuItem("Open dashboard", self._on_open_dashboard),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Check for Updates...", self._on_check_for_updates),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Uninstall py-sensor...", self._on_uninstall),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Exit", self._on_exit),
            ),
        )
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self._icon.run, daemon=True)
        self._thread.start()

    def stop(self):
        self._icon.stop()

    def _on_settings(self, icon, item):
        self._root.after(0, self._open_settings)

    def _on_open_dashboard(self, icon, item):
        url = f"http://127.0.0.1:{self._get_port()}/api/state"
        self._root.after(0, lambda: webbrowser.open(url))

    def _on_check_for_updates(self, icon, item):
        self._root.after(0, self._check_for_updates)

    def _on_uninstall(self, icon, item):
        self._root.after(0, self._uninstall)

    def _on_exit(self, icon, item):
        self._root.after(0, self._quit_app)
