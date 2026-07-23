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
    """Generates a microphone glyph at runtime -- no shipped .ico/.png asset
    to keep in sync as the app evolves. An earlier version drew just a
    circle-plus-stem, which at actual tray size (scaled down to ~16px) reads
    as a keyhole, not a mic -- this one adds the stand arc and base a real
    mic glyph needs to stay legible that small."""
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((4, 4, size - 4, size - 4), fill=(37, 99, 235, 255))

    white = (255, 255, 255, 255)
    cx = size / 2

    # Capsule (the mic head)
    cap_w, cap_h = size * 0.20, size * 0.30
    cap_top = size * 0.20
    cap_box = (cx - cap_w / 2, cap_top, cx + cap_w / 2, cap_top + cap_h)
    draw.rounded_rectangle(cap_box, radius=cap_w / 2, fill=white)

    # Stand (open arc cradling the capsule's base)
    r = size * 0.17
    arc_cy = cap_top + cap_h - size * 0.03
    arc_box = (cx - r, arc_cy - r, cx + r, arc_cy + r)
    stroke = max(2, round(size * 0.06))
    draw.arc(arc_box, start=0, end=180, fill=white, width=stroke)

    # Stem + base
    stem_bottom = arc_cy + r + size * 0.08
    draw.line((cx, arc_cy + r, cx, stem_bottom), fill=white, width=stroke)
    base_half = size * 0.10
    draw.line((cx - base_half, stem_bottom, cx + base_half, stem_bottom), fill=white, width=stroke)
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
