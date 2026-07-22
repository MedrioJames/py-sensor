# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**py-sensor** — a small Windows background tool for James Reynolds that reports live facts about his
work computer (starting with mic/camera-in-use) over a local-only HTTP API, so other tools (a personal
dashboard, eventually Home Assistant) can poll it. Split out of a one-file prototype
(`DayHUD/mic-cam-detector.py`) so it can be installed/updated/reused independently of DayHUD.

Sibling project `l10-manager` (`C:\Google Drive\Development\Python\l10-manager`) established the
install/update *approach* this repo follows: guided Python detection that dodges the Microsoft Store
`python.exe` stub, a never-silent confirmed install flow, and a firm rule against `iex`/`eval()` on
downloaded content (Medrio Security flagged that pattern as malware-like before). Read its CLAUDE.md
"Design constraints" section before changing install.ps1/launcher.ps1/lib — the reasoning there mostly
carries over unchanged.

## Commands

```bash
# Run directly from this checkout (fast iteration, no install needed) --
# requires pystray on the path already (see "Local dev setup" below)
python app/main.py

# Build the real install at %LOCALAPPDATA%\py-sensor + Startup shortcut
PySensor-Setup.bat
# (or, equivalently: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1)
```

### Local dev setup

`app/main.py` imports `pystray`/`PIL`, which aren't stdlib. When running from the checkout (not the
installed copy), install them into your own interpreter or venv first: `python -m pip install pystray`.
The installed copy gets these from `vendor/` via `PYTHONPATH` (see launcher.ps1) instead.

## Architecture

```
install.ps1 / PySensor-Setup.bat   Dual-mode installer -> %LOCALAPPDATA%\py-sensor (see below)
manifest.json                        Declares current version + the file list install.ps1 deploys
lib/PythonCheck.ps1                 Python+pip detection, shared by install.ps1 and app/launcher.ps1
lib/CreateShortcut.ps1              Standalone .lnk creation helper, called both by install.ps1 (PowerShell)
                                     and app/startup.py (Python, via subprocess) -- .lnk is a COM format,
                                     not something Python's stdlib can write, so this is the one place
                                     both callers share instead of duplicating the WScript.Shell dance
app/main.py                         Entry point -- see "Concurrency model" below
app/config.py                       config.json load/save (%LOCALAPPDATA%\py-sensor\config.json),
                                     schema below, creates the file with defaults on first read if missing
app/server.py                       ThreadingHTTPServer + handler, API below
app/sensors/                        Registry (see "Adding a sensor" below)
app/tray.py                         pystray tray icon + menu (Settings / Open dashboard / Exit)
app/settings_ui.py                  Tkinter Settings window
app/startup.py                      Create/remove the Startup-folder shortcut
app/launcher.ps1                    Checks Python+pip, sets PYTHONPATH to vendor/, launches pythonw hidden
```

### Install layout (what install.ps1 produces)

```
%LOCALAPPDATA%\py-sensor\
  app\            <- deployed per manifest.json's app_files each time install.ps1 runs (code, replaceable)
  lib\            <- deployed per manifest.json's app_files
  vendor\         <- pip --target install of pystray (+ Pillow/etc, whatever pip resolves) - never
                     the global site-packages, never a bare `pip install` typed by the user
  config.json     <- app/config.py creates it with defaults the first time it's read if missing, and never
                     overwrites an existing one. install.ps1 only ever writes to it once, at that same
                     first-creation moment, to apply -Port/-ApiKey if given (see below) - a re-run against
                     an existing config.json touches nothing, which is what makes re-running install.ps1
                     (to pick up a code change) safe for settings.
  Start py-sensor.lnk               <- manual launch
%APPDATA%\...\Startup\py-sensor.lnk <- auto-launch at login (created by install.ps1; toggled by
                                        Settings -> app/startup.py after that)
```

### Install.ps1 dual mode (ported from l10-manager)

Exactly mirrors `l10-manager/install.ps1`'s `$LocalRoot` pattern: if `manifest.json` exists alongside the
running script, it's a local checkout — read files/manifest straight off disk. Otherwise (downloaded
standalone to `%TEMP%` by `PySensor-Setup.bat` or the README one-liner), fetch both from
`https://raw.githubusercontent.com/MedrioJames/py-sensor/main/`. `Get-RepoBytes` abstracts the two byte
sources so the file-writing loop over `manifest.app_files` is identical either way — including the
comma-prefixed `,$bytes` return (forces PowerShell to keep a byte array intact instead of unrolling it;
l10-manager hit this for real with a zero-length file). `PySensor-Setup.bat` always downloads `install.ps1`
fresh (matching `L10-Manager-Setup.bat` exactly), so double-clicking it after cloning the repo still tests
the *published* version, not local edits — to test local changes, run `install.ps1` directly from the
checkout instead.

`install.ps1 -Port <n> -ApiKey <key>` exists so a caller (DayHUD) can generate a personalized installer per
user rather than making them hand-configure a port/key afterward. Both are plain optional string params
(int-parsed/validated in PowerShell, not typed `[int]` — an unsupplied `[int]` param silently defaults to
`0`, indistinguishable from "not given"). When one is supplied and `config.json` doesn't exist yet, a short
inline `python -c` snippet does the actual write — it imports the just-deployed `app/config.py` and calls
its real `load_config()`/`save_config()` rather than re-implementing the default schema in PowerShell, so
this can't drift out of sync with config.py as that schema evolves.

## Concurrency model

Three things want to own the process, and only one can have the main thread:

- **Tk** needs a mainloop to show the Settings window.
- **pystray**'s `Icon.run()` blocks and pumps its own message loop.
- **`ThreadingHTTPServer`** needs to serve forever.

Resolution (`app/main.py`): Tk owns the main thread (a `Tk()` root, `withdraw()`-ed immediately since
there's no always-visible window), with the server and the tray icon each running on their own daemon
thread. **pystray's `Icon.run()` runs fine off the main thread on Windows** — its Win32 backend is just a
hidden window pumping `GetMessage`/`DispatchMessage`, which works on any thread; only macOS's Cocoa
backend actually requires the main thread. Tray menu callbacks fire on pystray's thread, so anything that
touches a Tk widget or shared app state marshals onto the Tk thread via `root.after(0, ...)` — see
`tray.py`. This is the same marshaling pattern l10-manager's updater already uses for its background
download-progress callbacks.

Settings changes take effect immediately without a restart for anything sensor-related (server.py reads
config + sensor state fresh on every request — see below); only a **port** change stops and restarts the
HTTP server (`ServerController.restart()`), since that requires rebinding the socket.

## API (server.py)

- `GET /api/state` → `{"ok": true, "sensors": {"mic": {"enabled": bool, "active": bool|null}, "cam": {...}}, "active": bool}`
  — `active` at the top level is true if any *enabled* sensor is active. Main polling endpoint.
- `GET /api/sensors/<name>` → single-sensor detail; 404 for an unknown name.
- Bound to `127.0.0.1` only, permissive CORS (`Access-Control-Allow-Origin: *`) + `OPTIONS` preflight —
  same posture as the original DayHUD prototype. A disabled sensor reports `"active": null` rather than
  being omitted, so a client can tell "disabled" apart from "not in use."
- No background polling loop anywhere — every field is computed fresh per request (registry reads for
  mic/cam are cheap). This was a deliberate property of the original prototype worth preserving: nothing
  can fall out of sync with reality.
- **API key (optional).** If `config.json`'s `api_key` is non-empty, `Handler._api_key_ok()` requires it on
  every request via `?key=...` or an `X-Api-Key` header (checked before routing, so an unknown path with a
  bad key still gets a 401, not a 404 — deliberately doesn't leak route existence to an unauthenticated
  caller). Empty `api_key` (the default) means no auth at all, preserving the original zero-config prototype
  behavior for anyone running py-sensor standalone. This exists specifically so wildcard CORS doesn't mean
  "any web page on the machine can read mic/cam state" — a per-install random key (DayHUD generates one
  client-side per download, see "Not built yet" below) is a real secret, unlike tightening CORS to a fixed
  origin, which was considered and rejected as strictly weaker here (DayHUD's origin isn't necessarily
  fixed/knowable in advance, and it wouldn't stop other things running as the same OS user anyway).
  `do_OPTIONS` declares `Access-Control-Allow-Headers: X-Api-Key` so a browser client using the header form
  isn't blocked by preflight; the query-param form skips preflight entirely and is the simpler choice for a
  browser-based poller like DayHUD.

## Adding a sensor

1. Write a module under `app/sensors/` with a zero-arg function returning `bool` (True = active).
2. Register it in `app/sensors/__init__.py`'s `SENSORS` dict: `"name": Sensor(label="...", check=...)`.

That's it — `config.py`'s defaults, `server.py`'s routes, and `settings_ui.py`'s checkbox list all iterate
`SENSORS` rather than hardcoding `mic`/`cam`, so a new sensor needs no other changes.

## Design constraints

Carried over from l10-manager, with one deliberate deviation:

- **Windows-only for now.** Cross-platform is a later phase, same as L10.
- **No silent/unattended system changes.** Anything touching the machine (installing Python, installing
  pystray, creating the Startup shortcut) is explicit and confirmed as part of the one setup run the user
  deliberately started — never something that happens later without the user having asked for it.
- **No fileless script evaluation.** Never `iex`/`ScriptBlock::Create` on downloaded text — this exact
  pattern got flagged by Medrio Security once already. Everything here is a real file on disk before it's
  ever executed.
- **Deviation from L10: pip is allowed here**, scoped to a private `vendor/` folder that pip's `--target`
  writes to (never global site-packages, never a command the user types themselves). L10's app-template is
  stdlib-only specifically to avoid a pip-install step; for py-sensor, a hand-rolled ctypes/Win32 tray icon
  was judged not worth the reliability cost versus the small, well-established `pystray` package. This was
  a considered trade-off (confirmed with James) — if you're tempted to "fix" this back to stdlib-only,
  that's why it isn't already that way.

## Not built yet

- **In-app self-updater.** The repo is now public at `github.com/MedrioJames/py-sensor` and install.ps1 can
  fetch a fresh install from it (see "Install.ps1 dual mode" above), but nothing checks for updates *while
  py-sensor is already running* — that's a separate piece from the fresh-install path. When building it,
  port `l10-manager/app-template/updater.py` (manifest-version-compare + `apply_update()` pattern) and wire
  a check into `tray.py`'s menu or `main.py`'s startup, same as L10's Help > Check for Updates.
- **Home Assistant push.** `config.json`'s `home_assistant` block and Settings' grayed-out section are
  scaffolding only — no push logic exists. When building it: a background thread that posts to HA's REST
  API on sensor state *change* (not a poll loop) is the natural fit, given the "no unnecessary polling"
  principle already established for the sensors themselves.
- **DayHUD integration.** DayHUD's "Download the script" button still points at the old
  `mic-cam-detector.py` prototype (embedded as a JS string in `Index.html`, handed to the user via a Blob
  download — see that repo's `Index.html` around `MIC_CAM_SCRIPT`/`downloadTextFile_`). The plan: DayHUD
  generates a random per-install API key + picks a port client-side, then hands the user a customized
  `PySensor-Setup.bat` whose one invocation line becomes
  `powershell -File install.ps1 -Port <port> -ApiKey <key>` (both params already exist on this side — see
  "Install.ps1 dual mode" above); DayHUD then polls `/api/state` with that same key going forward. DayHUD's
  status-check code also needs to move from `http://127.0.0.1:8765/state` (flat `{mic,cam,active}`) to
  `/api/state` (nested `{sensors:{mic:{...},cam:{...}},active}`). None of this is built on DayHUD's side yet
  — don't touch the DayHUD repo as a side effect of work here; it's a separate follow-up conversation.
