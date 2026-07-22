"""Tkinter Settings window.

Single instance -- calling open_settings() again while one is already open
just brings the existing window forward instead of creating a second one
(guards against a double-click on the tray menu item, or the tray callback
firing twice before the Tk thread catches up).
"""

import tkinter as tk
from tkinter import messagebox, ttk

import startup
from sensors import SENSORS

_window = None


def open_settings(cfg, on_save):
    global _window
    if _window is not None and _window.winfo_exists():
        _window.lift()
        _window.focus_force()
        return

    win = tk.Toplevel()
    _window = win
    win.title("py-sensor Settings")
    win.resizable(False, False)

    def on_close():
        global _window
        _window = None
        win.destroy()

    win.protocol("WM_DELETE_WINDOW", on_close)

    pad = {"padx": 12, "pady": 6}

    # --- Sensors ---
    sensors_frame = ttk.LabelFrame(win, text="Sensors")
    sensors_frame.pack(fill="x", **pad)
    sensor_vars = {}
    for name, sensor in SENSORS.items():
        var = tk.BooleanVar(value=cfg["sensors"].get(name, {}).get("enabled", True))
        sensor_vars[name] = var
        ttk.Checkbutton(sensors_frame, text=sensor.label, variable=var).pack(anchor="w", padx=8, pady=2)

    # --- Server ---
    server_frame = ttk.LabelFrame(win, text="Server")
    server_frame.pack(fill="x", **pad)
    ttk.Label(server_frame, text="Port:").grid(row=0, column=0, sticky="w", padx=8, pady=6)
    port_var = tk.StringVar(value=str(cfg["port"]))
    ttk.Entry(server_frame, textvariable=port_var, width=8).grid(row=0, column=1, sticky="w", pady=6)

    startup_var = tk.BooleanVar(value=startup.is_enabled())
    ttk.Checkbutton(server_frame, text="Launch at startup", variable=startup_var).grid(
        row=1, column=0, columnspan=2, sticky="w", padx=8, pady=(0, 6)
    )

    # --- Home Assistant (scaffold only -- no push logic yet, see CLAUDE.md) ---
    ha_frame = ttk.LabelFrame(win, text="Home Assistant (coming soon)")
    ha_frame.pack(fill="x", **pad)
    ha_enabled_var = tk.BooleanVar(value=cfg["home_assistant"].get("enabled", False))
    ttk.Checkbutton(
        ha_frame, text="Push sensor state to Home Assistant", variable=ha_enabled_var, state="disabled"
    ).grid(row=0, column=0, columnspan=2, sticky="w", padx=8, pady=(6, 2))

    ttk.Label(ha_frame, text="URL:").grid(row=1, column=0, sticky="w", padx=8, pady=2)
    ha_url_var = tk.StringVar(value=cfg["home_assistant"].get("url", ""))
    ttk.Entry(ha_frame, textvariable=ha_url_var, width=30, state="disabled").grid(
        row=1, column=1, sticky="w", padx=(0, 8), pady=2
    )

    ttk.Label(ha_frame, text="Token:").grid(row=2, column=0, sticky="w", padx=8, pady=(2, 6))
    ha_token_var = tk.StringVar(value=cfg["home_assistant"].get("token", ""))
    ttk.Entry(ha_frame, textvariable=ha_token_var, width=30, show="*", state="disabled").grid(
        row=2, column=1, sticky="w", padx=(0, 8), pady=(2, 6)
    )

    # --- Buttons ---
    button_frame = ttk.Frame(win)
    button_frame.pack(fill="x", **pad)

    def on_save_click():
        try:
            port = int(port_var.get())
            if not (1 <= port <= 65535):
                raise ValueError
        except ValueError:
            messagebox.showerror("py-sensor", "Port must be a number between 1 and 65535.", parent=win)
            return

        new_cfg = {
            "port": port,
            "sensors": {name: {"enabled": var.get()} for name, var in sensor_vars.items()},
            "launch_at_startup": startup_var.get(),
            "home_assistant": {
                "enabled": ha_enabled_var.get(),
                "url": ha_url_var.get(),
                "token": ha_token_var.get(),
            },
        }

        if startup_var.get():
            startup.enable()
        else:
            startup.disable()

        on_save(new_cfg)
        on_close()

    ttk.Button(button_frame, text="Save", command=on_save_click).pack(side="right", padx=(6, 0))
    ttk.Button(button_frame, text="Cancel", command=on_close).pack(side="right")

    win.attributes("-topmost", True)
    win.after(100, lambda: win.attributes("-topmost", False))
