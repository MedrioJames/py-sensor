"""py-sensor entry point.

Concurrency model: Tk owns the main thread (a withdrawn root running
mainloop()), with the HTTP server and the tray icon each on their own daemon
thread. Tray menu callbacks marshal onto the Tk thread via root.after(0, ...)
before touching Tk widgets or shared state -- see tray.py.
"""

import tkinter as tk

import config as config_module
import settings_ui
from server import ServerController
from tray import TrayIcon

server = ServerController()


def main():
    cfg = config_module.load_config()
    server.start(cfg["port"])

    root = tk.Tk()
    root.withdraw()

    def open_settings():
        current_cfg = config_module.load_config()
        settings_ui.open_settings(current_cfg, on_save=apply_settings)

    def apply_settings(new_cfg):
        old_port = server.port
        config_module.save_config(new_cfg)
        if new_cfg["port"] != old_port:
            server.restart(new_cfg["port"])

    def quit_app():
        tray.stop()
        server.stop()
        root.quit()

    tray = TrayIcon(root, get_port=lambda: server.port, open_settings=open_settings, quit_app=quit_app)
    tray.start()

    root.mainloop()


if __name__ == "__main__":
    main()
