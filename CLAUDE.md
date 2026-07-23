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
Uninstall.ps1 / Uninstall.bat       Full removal -- see "Uninstall" below
manifest.json                        Declares current version + the file list install.ps1 deploys
lib/PythonCheck.ps1                 Python+pip detection, shared by install.ps1 and app/launcher.ps1
lib/CreateShortcut.ps1              Standalone .lnk creation helper, called both by install.ps1 (PowerShell)
                                     and app/startup.py (Python, via subprocess) -- .lnk is a COM format,
                                     not something Python's stdlib can write, so this is the one place
                                     both callers share instead of duplicating the WScript.Shell dance
lib/StopRunningInstance.ps1          Shared "stop the running instance" helper, called both by install.ps1
                                     (before overwriting vendor/ or app/) and Uninstall.ps1 (before deleting
                                     everything) -- see "Install.ps1 dual mode" below for why this needs a
                                     poll-for-exit rather than a fixed sleep
app/main.py                         Entry point -- see "Concurrency model" below
app/config.py                       config.json load/save (%LOCALAPPDATA%\py-sensor\config.json),
                                     schema below, creates the file with defaults on first read if missing
app/server.py                       ThreadingHTTPServer + handler, API below
app/sensors/                        Registry (see "Adding a sensor" below)
app/tray.py                         pystray tray icon + menu (Settings / Open dashboard / Check for Updates /
                                     Uninstall / Exit)
app/settings_ui.py                  Tkinter Settings window
app/startup.py                      Create/remove the Startup-folder shortcut
app/updater.py                      GitHub-Releases-based update check/apply -- see "Update mechanism" below
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
  Uninstall.ps1 / Uninstall.bat     <- full removal, deployed alongside everything else - see "Uninstall"
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
`0`, indistinguishable from "not given"). When one is supplied and `config.json` doesn't exist yet, a small
Python snippet does the actual write — it imports the just-deployed `app/config.py` and calls its real
`load_config()`/`save_config()` rather than re-implementing the default schema in PowerShell, so this can't
drift out of sync with config.py as that schema evolves. That snippet is written to a real temp `.py` file
and run with a plain file path, never passed inline via `python -c "<code>"` — PowerShell mangles embedded
double-quotes when building a native command line from a string argument (`cfg["port"]` arrived at Python
as `cfg[port]`, a real bug hit while building this), and a file sidesteps that whole class of quoting
problem. The same "write to a real temp file, never pass code inline" rule is why `Uninstall.ps1`'s
detached self-delete step (below) does the same thing instead of a `-Command` string.

`install.ps1 -Ref <tag>` (default `main`) is what makes the same script double as both installer and
updater: `app/updater.py`'s `apply_update()` calls it with a specific released tag instead of the default
branch, so an update always installs exactly what that release published rather than whatever's since
landed on `main`. `$RawBase` is built from `-Ref`, so every fetch (manifest, app files, the shared lib
scripts) transparently comes from that ref in remote mode; local-checkout mode ignores `-Ref` entirely
(there's no "ref" for files already on disk).

## Update mechanism (app/updater.py)

Checks GitHub's **Releases** API (`/repos/.../releases/latest`), not just whatever's on `main` — an update
always corresponds to a real, deliberately published version. See "How to ship a release" below for the
half of this that's a manual process, not code.

- `check_for_update()` fetches the latest release, compares its `tag_name` against the installed
  `app/version.txt` (written by install.ps1 at deploy time), and returns the release dict if it's newer —
  or `None` on any network hiccup, no release, or a dev checkout (see below). Version comparison tolerates
  a `v` prefix on either side (`_parse_version` strips it) since GitHub tags conventionally have one but
  `manifest.json`'s own `version` field doesn't.
- `apply_update(release)` re-downloads `install.ps1` fresh from that release's own tag (not `main`, in case
  `main` has moved on since) to a real temp file, then runs it with `-Ref <tag>` in a **visible** console
  (`CREATE_NEW_CONSOLE`) — visible deliberately, since this is an explicit user-initiated action ("update
  now"), not a silent background one, so there's somewhere for progress/errors to actually show up. It
  reuses every bit of install.ps1's already-hardened machinery (stop the running instance, retry pip)
  rather than re-implementing file deployment in Python a second time.
- `main.py` runs a background thread that checks once ~10s after startup, then every 24h for as long as
  the process lives. A background find only ever *notifies* (a Tkinter yes/no "update now?") — applying
  always needs an explicit click, per the "no silent/unattended system changes" rule below. A silent
  background check would also mean a "you're up to date" popup once a day out of nowhere, which is why
  that confirmation only happens from the tray's **Check for Updates...** (a manual, user-initiated check).
- `is_dev_checkout()` (checks for `app_dir().parent/.git`) blocks updating a dev checkout the same way
  l10-manager's updater.py already guards this — without it, running `main.py` straight from this repo
  looks exactly like a very old install (no `version.txt`), and an "update" would silently overwrite this
  checkout's own uncommitted files.

## Uninstall (Uninstall.ps1 / Uninstall.bat)

Deployed into the install root by install.ps1 like everything else — never downloaded fresh at uninstall
time, since removing the tool shouldn't need internet access at all.

- Stops the running instance (`lib/StopRunningInstance.ps1`), removes the Startup-folder shortcut, then
  deletes the entire install folder, itself included.
- **Self-delete mechanics**: a running script can't delete its own containing folder from within the same
  process (Windows holds it open while it executes), so the last step writes a tiny cleanup script to a
  *real temp file* — `Start-Sleep` then `Remove-Item -Recurse` on the install dir, then delete itself —
  and launches that detached. Written to a file rather than an inline `-Command` string for the same
  quoting-safety reason as the config-seeding snippet above.
- **Dev-checkout guard**: refuses to run at all if `$PSScriptRoot\.git` exists, since this same file also
  lives in the git repo (not just the deployed copy) — without this, someone running `Uninstall.ps1`
  straight from a clone would delete their own working tree. `main.py`'s tray-triggered uninstall has the
  matching Python-side guard (`updater.is_dev_checkout()`) before it ever launches `Uninstall.ps1`.
- `-Confirmed` skips the interactive `Read-Host` prompt — only ever passed by `main.py`'s tray callback,
  which already got its own yes/no from a Tkinter dialog before launching it; a direct double-click of
  `Uninstall.ps1`/`Uninstall.bat` always confirms interactively instead.

## How to ship a release

The update mechanism only finds something when a real GitHub Release exists for it to find — a git tag by
itself isn't enough (the Releases API only returns published Releases). To ship a version that
`app/updater.py` will actually detect:

1. Bump `manifest.json`'s `"version"` (plain `x.y.z`, no `v` prefix) and commit/push it along with whatever
   code changed.
2. Create a GitHub Release tagged `v<version>` (matching that manifest version) at that commit — via
   `gh release create v0.3.0 --title "..." --notes "..."` or GitHub's web UI ("Draft a new release").
   Nothing in this repo does this automatically; it's a deliberate manual step, same spirit as everything
   else here being explicit rather than automatic.

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

## Crash logging (`%LOCALAPPDATA%\py-sensor\py-sensor.log`)

Runs under `pythonw.exe`, which has no console — an uncaught exception anywhere is otherwise invisible,
with nothing to diagnose it by. `main.py`'s `_setup_crash_logging()` covers all three places one could
happen: `sys.excepthook` (main thread), `threading.excepthook` (background threads — the update-check
loop), and `root.report_callback_exception` (Tk widget callbacks — Settings' Save button, tray menu
actions). Tkinter already catches an exception raised inside a callback and routes it through
`report_callback_exception` without crashing the mainloop (confirmed by test, not just assumed) — this
override just makes that landing somewhere durable instead of nowhere. `main()`/`quit_app()` also log a
plain startup/exit line, so the log can distinguish a clean exit from an abrupt one (e.g. `Stop-Process
-Force` during a reinstall/update — or, while testing this repo's own install/uninstall flow repeatedly,
from another running instance getting killed out from under whoever had it open at the time).

`settings_ui.py`'s Save button separately wraps just the `startup.enable()`/`disable()` call (the one
subprocess call in that whole path, and so the one most likely to genuinely fail) in its own try/except —
a shortcut-creation hiccup shows a specific error and still saves everything else, rather than surfacing as
a generic logged exception with no explanation to the user in the moment.

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
