"""Update checking/applying for py-sensor.

Stdlib only. Checks GitHub's Releases API (not just whatever's currently on
`main`) so an update always corresponds to a real, deliberately published
version -- see CLAUDE.md's "How to ship a release" section. Deliberately
never executes or evaluates downloaded content directly: applying an update
re-fetches install.ps1 as a real file and runs it with `-File`, the exact
same never-silent, never-eval'd path a fresh install already uses.
"""

import json
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO_OWNER = "MedrioJames"
REPO_NAME = "py-sensor"
RELEASES_API_URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases/latest"
API_TIMEOUT_SECONDS = 5
FILE_TIMEOUT_SECONDS = 30


def app_dir() -> Path:
    return Path(__file__).resolve().parent


def is_dev_checkout() -> bool:
    """True when running straight out of the git repo's app/ folder rather
    than a deployed install's app/ folder -- ports l10-manager's updater.py
    guard against the same real incident: without this, running main.py
    directly from a dev checkout looks exactly like a brand-new install
    running an ancient version (no version.txt), and an update would
    silently overwrite the checkout's own uncommitted source files."""
    return (app_dir().parent / ".git").exists()


def local_version() -> str:
    version_file = app_dir() / "version.txt"
    if version_file.exists():
        return version_file.read_text(encoding="utf-8").strip()
    return "0.0.0"


def _parse_version(v: str) -> tuple:
    parts = []
    for chunk in v.strip().lstrip("vV").split("."):
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def is_newer(remote: str, local: str) -> bool:
    remote_t, local_t = _parse_version(remote), _parse_version(local)
    length = max(len(remote_t), len(local_t))
    remote_t = remote_t + (0,) * (length - len(remote_t))
    local_t = local_t + (0,) * (length - len(local_t))
    return remote_t > local_t


def fetch_latest_release(timeout: float = API_TIMEOUT_SECONDS):
    """Returns the GitHub Releases API's `latest` release dict, or None if
    the repo has no published releases yet (a real 404, not an error)."""
    request = urllib.request.Request(
        RELEASES_API_URL,
        headers={
            # api.github.com 403s an unauthenticated request with no
            # User-Agent at all -- raw.githubusercontent.com (used
            # elsewhere below) doesn't need this.
            "User-Agent": "py-sensor-updater",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def check_for_update():
    """Returns the release dict if a newer one is published (and this isn't
    a dev checkout), else None. Swallows network errors -- a background
    check should never crash the app over a flaky connection."""
    if is_dev_checkout():
        return None
    try:
        release = fetch_latest_release()
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return None
    if not release:
        return None
    remote_version = str(release.get("tag_name", "")).strip()
    if not remote_version or not is_newer(remote_version, local_version()):
        return None
    return release


def apply_update(release) -> None:
    """Re-fetches install.ps1 fresh from the release's own tag (not `main`,
    in case main has since moved on) and runs it with -Ref <tag> -- reuses
    every bit of install.ps1's already-hardened machinery (stop the running
    instance, retry pip) rather than re-implementing file deployment here.
    Only ever downloads to a real file and runs it with -File -- never
    iex/eval, same rule as everywhere else in this repo. Runs in a visible
    console (not hidden) so there's somewhere for an error to show up if
    something goes wrong -- this is triggered by an explicit "update now"
    click, not a silent background action, so showing it stay transparent.

    The caller (main.py) is responsible for quitting the app shortly after
    this returns, so its own file locks release quickly; install.ps1 will
    also force-stop it either way as a fallback (see
    lib/StopRunningInstance.ps1).
    """
    if is_dev_checkout():
        raise RuntimeError(
            "Refusing to self-update a dev checkout - this would overwrite uncommitted local changes."
        )
    tag = release["tag_name"]
    install_url = f"https://raw.githubusercontent.com/{REPO_OWNER}/{REPO_NAME}/{tag}/install.ps1"
    with urllib.request.urlopen(install_url, timeout=FILE_TIMEOUT_SECONDS) as resp:
        installer_bytes = resp.read()

    tmp = tempfile.NamedTemporaryFile(prefix="py-sensor-update-", suffix=".ps1", delete=False)
    try:
        tmp.write(installer_bytes)
    finally:
        tmp.close()

    subprocess.Popen(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            tmp.name,
            "-Ref",
            tag,
        ],
        creationflags=subprocess.CREATE_NEW_CONSOLE,
    )
