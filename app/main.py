"""py-sensor entry point.

Concurrency model: Tk owns the main thread (a withdrawn root running
mainloop()), with the HTTP server and the tray icon each on their own daemon
thread. Tray menu callbacks marshal onto the Tk thread via root.after(0, ...)
before touching Tk widgets or shared state -- see tray.py.
"""

import logging
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

import config as config_module
import settings_ui
import updater
from server import ServerController
from tray import TrayIcon

UPDATE_CHECK_STARTUP_DELAY_SECONDS = 10
UPDATE_CHECK_INTERVAL_SECONDS = 24 * 60 * 60
LOG_PATH = Path(os.environ["LOCALAPPDATA"]) / "py-sensor" / "py-sensor.log"

server = ServerController()


def _setup_crash_logging():
    """Runs under pythonw.exe, which has no console -- an uncaught exception
    anywhere (main thread, a background thread, or a Tk widget callback) is
    otherwise completely invisible, with nothing to diagnose it by. Logs all
    three to a real file instead."""
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=LOG_PATH,
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(threadName)s] %(message)s",
    )

    def log_main_thread_exception(exc_type, exc_value, exc_tb):
        logging.critical("Unhandled exception on the main thread", exc_info=(exc_type, exc_value, exc_tb))

    sys.excepthook = log_main_thread_exception

    def log_background_thread_exception(args):
        logging.critical(
            "Unhandled exception on thread %r",
            args.thread.name if args.thread else "?",
            exc_info=(args.exc_type, args.exc_value, args.exc_traceback),
        )

    threading.excepthook = log_background_thread_exception


def main():
    _setup_crash_logging()
    logging.info("py-sensor starting (v%s)", updater.local_version())

    cfg = config_module.load_config()
    server.start(cfg["port"])

    root = tk.Tk()
    root.withdraw()

    def log_tk_callback_exception(exc_type, exc_value, exc_tb):
        logging.critical("Unhandled exception in a Tk callback", exc_info=(exc_type, exc_value, exc_tb))

    root.report_callback_exception = log_tk_callback_exception

    def open_settings():
        current_cfg = config_module.load_config()
        settings_ui.open_settings(current_cfg, on_save=apply_settings)

    def apply_settings(new_cfg):
        old_port = server.port
        config_module.save_config(new_cfg)
        if new_cfg["port"] != old_port:
            server.restart(new_cfg["port"])

    def quit_app():
        logging.info("py-sensor exiting (Exit/Update/Uninstall)")
        tray.stop()
        server.stop()
        root.quit()

    def prompt_update_available(release):
        tag = release.get("tag_name", "?")
        if messagebox.askyesno(
            "py-sensor", f"A new version of py-sensor is available: {tag}.\n\nUpdate now?"
        ):
            try:
                updater.apply_update(release)
            except Exception as exc:
                messagebox.showerror("py-sensor", f"Couldn't start the update:\n{exc}")
                return
            quit_app()

    def check_for_updates_manual():
        release = updater.check_for_update()
        if release:
            prompt_update_available(release)
        else:
            messagebox.showinfo("py-sensor", f"You're up to date (v{updater.local_version()}).")

    def background_update_loop():
        # Runs once shortly after startup, then once a day for as long as
        # the app keeps running. Only ever *notifies* on a background find --
        # applying always requires the user's explicit yes, matching this
        # project's "no silent/unattended system changes" rule; a manual
        # check (above) additionally confirms "you're up to date" when
        # there's nothing new, which a silent background check deliberately
        # doesn't do (that would mean a popup once a day, every day).
        time.sleep(UPDATE_CHECK_STARTUP_DELAY_SECONDS)
        while True:
            release = updater.check_for_update()
            if release:
                root.after(0, lambda r=release: prompt_update_available(r))
            time.sleep(UPDATE_CHECK_INTERVAL_SECONDS)

    def uninstall():
        if updater.is_dev_checkout():
            messagebox.showinfo(
                "py-sensor",
                "Uninstall isn't available when running from a dev checkout "
                "(this would delete the git repo, not an install). Run the "
                "installed copy under %LOCALAPPDATA%\\py-sensor instead.",
            )
            return
        if not messagebox.askyesno(
            "py-sensor",
            "This will completely remove py-sensor from this computer, "
            "including all settings. This can't be undone.\n\nContinue?",
        ):
            return
        install_dir = Path(__file__).resolve().parent.parent
        uninstall_script = install_dir / "Uninstall.ps1"
        subprocess.Popen(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(uninstall_script),
                "-Confirmed",
            ],
            creationflags=subprocess.CREATE_NEW_CONSOLE,
        )
        quit_app()

    tray = TrayIcon(
        root,
        get_port=lambda: server.port,
        open_settings=open_settings,
        check_for_updates=check_for_updates_manual,
        uninstall=uninstall,
        quit_app=quit_app,
    )
    tray.start()

    threading.Thread(target=background_update_loop, daemon=True).start()

    root.mainloop()


if __name__ == "__main__":
    main()
