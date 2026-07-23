# py-sensor

A tiny Windows background tool that reports live facts about your computer — starting with whether the
microphone or camera is currently in use — over a local HTTP API, so other tools on the same PC (a
dashboard, a script, eventually Home Assistant) can poll it.

Nothing leaves your machine: the server only listens on `127.0.0.1`, so it's never reachable from another
device on your network.

## Install

**Option A — download and double-click** (recommended): grab [`PySensor-Setup.bat`](PySensor-Setup.bat)
and double-click it. No need to open PowerShell yourself first — the file does that for you.

**Option B — copy/paste one-liner**: open PowerShell (Start menu → search "PowerShell") and paste this in:

```powershell
$p = "$env:TEMP\py-sensor-install.ps1"; iwr https://raw.githubusercontent.com/MedrioJames/py-sensor/main/install.ps1 -OutFile $p; powershell -ExecutionPolicy Bypass -File $p
```

Both options download the setup script to a real file and run it from disk, rather than piping it
straight into evaluation — deliberately avoiding the "fileless" execution pattern that security tooling
(rightly) treats as suspicious.

Either way, the installer will:

1. Check that a real Python 3 is installed (and guide you through installing it if not — it deliberately
   avoids the Microsoft Store's `python.exe`, which looks like Python but isn't).
2. Install itself to `%LOCALAPPDATA%\py-sensor` — no admin rights needed.
3. Install its one small dependency (the tray-icon library) into a private folder just for py-sensor —
   never your system-wide Python packages.
4. Create a shortcut so it starts automatically next time you log in (you can turn this off later from
   the tray icon's Settings), plus a "Start py-sensor" shortcut for launching it manually.
5. Start it right away.

Once running, look for its icon in your system tray (near the clock, may be under the "^" overflow arrow).
Right-click it for **Settings**, **Check for Updates**, **Uninstall**, or **Exit**.

### Installing with a specific port/API key

`install.ps1` takes two optional parameters, for a tool (like DayHUD) that wants to hand a user a
ready-to-go install rather than making them configure a port/key by hand afterward:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Port 8899 -ApiKey <a-generated-key>
```

These only ever seed a *brand-new* `config.json` — they're ignored if one already exists, so re-running
the installer to pick up a code update never overrides settings you (or Settings) already changed.

## Settings

- Enable/disable individual sensors (mic, camera).
- Change the port the local server listens on (default `8765`).
- Set or generate an API key (see "API" below) — blank by default, meaning no key is required.
- Turn "launch at startup" on or off.
- A Home Assistant section exists but is currently just a placeholder — that integration isn't built yet.

## API

- `GET http://127.0.0.1:8765/api/state`

  ```json
  {
    "ok": true,
    "sensors": {
      "mic": { "enabled": true, "active": false },
      "cam": { "enabled": true, "active": true }
    },
    "active": true
  }
  ```

  `active` is `null` for a disabled sensor (so you can tell "disabled" apart from "not currently in
  use"). The top-level `active` is true if *any enabled* sensor is active.

- `GET http://127.0.0.1:8765/api/sensors/mic` / `.../cam` — same shape as one entry of `sensors` above,
  for polling a single device. 404 for any other sensor name.

Every field is computed fresh on each request — there's no background polling loop and nothing to fall
out of sync.

### API key

If Settings has an API key set, every request above must include it, either as a query parameter —
`?key=<your-key>` (simplest for browser-based polling, since it doesn't trigger a CORS preflight) — or an
`X-Api-Key` header. A missing or wrong key gets a `401`. Leave it blank (the default) to allow any local
app to poll without one, same as before this existed.

## Updates

py-sensor checks GitHub for a newer released version shortly after it starts, and once a day after that
while it keeps running — you'll only ever see a prompt if one's actually found, never a "you're up to
date" popup out of nowhere. You can also check any time from the tray icon's **Check for Updates...**.
Either way, updating always asks first; nothing installs itself without you clicking "Update now."

## Uninstall

Right-click the tray icon → **Uninstall py-sensor...**, confirm, and it removes everything: stops the
running instance, deletes the Startup shortcut, and removes the whole `%LOCALAPPDATA%\py-sensor` folder.

If the app isn't running (or won't start), you can do the same thing directly: open
`%LOCALAPPDATA%\py-sensor` and double-click `Uninstall.bat`.
