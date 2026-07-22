"""Local HTTP API.

Bound to 127.0.0.1 only -- never reachable from another device on the
network. Each request reads config + sensor state fresh (config.load_config()
re-reads the on-disk file, sensor.check() re-reads the registry) -- there's
no cached/background-polled state to fall out of sync with reality.
"""

import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import config as config_module
from sensors import SENSORS


def _sensor_state(name, sensor, cfg):
    enabled = cfg["sensors"].get(name, {}).get("enabled", True)
    active = sensor.check() if enabled else None
    return {"enabled": enabled, "active": active}


def _state_snapshot(cfg):
    sensors = {}
    any_active = False
    for name, sensor in SENSORS.items():
        state = _sensor_state(name, sensor, cfg)
        sensors[name] = state
        if state["active"]:
            any_active = True
    return {"ok": True, "sensors": sensors, "active": any_active}


class Handler(BaseHTTPRequestHandler):
    def _api_key_ok(self, cfg):
        required = cfg.get("api_key", "")
        if not required:
            return True  # zero-config default: no key set, no auth required
        supplied = self.headers.get("X-Api-Key")
        if not supplied:
            query = urllib.parse.urlparse(self.path).query
            supplied = urllib.parse.parse_qs(query).get("key", [None])[0]
        return supplied == required


    def _send_json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):  # CORS preflight
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "X-Api-Key")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        cfg = config_module.load_config()

        if not self._api_key_ok(cfg):
            self._send_json(401, {"ok": False, "error": "invalid or missing API key"})
            return

        if path == "/api/state":
            self._send_json(200, _state_snapshot(cfg))
            return

        if path.startswith("/api/sensors/"):
            name = path[len("/api/sensors/"):]
            sensor = SENSORS.get(name)
            if sensor is None:
                self._send_json(404, {"ok": False, "error": f"unknown sensor '{name}'"})
                return
            self._send_json(200, _sensor_state(name, sensor, cfg))
            return

        self._send_json(404, {"ok": False, "error": "not found"})

    def log_message(self, format, *args):
        pass  # keep the console quiet -- remove this override for request logs


class ServerController:
    """Owns the currently-running HTTP server. start()/stop()/restart() are
    called from the Tk thread (settings save, app exit); the server itself
    serves on its own daemon thread so it never blocks the Tk mainloop."""

    def __init__(self):
        self._server = None
        self._thread = None
        self._port = None

    def start(self, port):
        if self._server is not None:
            raise RuntimeError("server already running")
        self._server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self._port = port
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    def stop(self):
        if self._server is None:
            return
        self._server.shutdown()
        self._server.server_close()
        self._server = None
        self._thread = None

    def restart(self, port):
        self.stop()
        self.start(port)

    @property
    def port(self):
        return self._port
