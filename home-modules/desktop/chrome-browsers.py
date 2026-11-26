"""chrome-browsers: which host each Claude-in-Chrome browser runs on.

list_connected_browsers names browsers "Browser N" and never says which
machine they are on. Each extension does store its own bridgeDeviceId (and
the hostname its native host reported) in Chrome's extension LevelDB, so
this script reads that store on every host and prints host -> deviceId.

  chrome-browsers            table for the whole fleet (ssh to each host)
  chrome-browsers --json     same, machine readable
  chrome-browsers --local    this host only (what the fleet scan runs remotely)

The fleet scan also copies a prompt-ready summary to the clipboard of the
host it runs on (wl-copy), so it can be pasted straight into a Claude prompt.
--no-copy skips that.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

import plyvel

EXTENSION_ID = "fcoeoabgfenejglbffodgkkbkcdhcgfn"
FLEET = ["ryzen", "thinkpad", "surface", "surface-pro"]
SSH = "@ssh@"
WL_COPY = "@wlcopy@"
CHROME_ROOTS = ["google-chrome", "google-chrome-beta", "google-chrome-unstable", "chromium"]
KEYS = {
    "bridgeDeviceId": "device_id",
    "bridgeDisplayName": "name",
    "bridgeDefaultDisplayName": "default_name",
}


def decode(raw):
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return raw.decode("utf-8", errors="replace")


def read_store(store):
    # Chrome holds the LOCK file while it runs; read a copy instead.
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "db"
        shutil.copytree(store, copy, ignore=shutil.ignore_patterns("LOCK"))
        db = plyvel.DB(str(copy))
        try:
            found = {}
            for key, field in KEYS.items():
                value = db.get(key.encode())
                if value is not None:
                    found[field] = decode(value)
            return found
        finally:
            db.close()


def scan_local():
    host = socket.gethostname().split(".")[0]
    rows = []
    config = Path.home() / ".config"
    for root in CHROME_ROOTS:
        for store in sorted(config.glob(f"{root}/*/Local Extension Settings/{EXTENSION_ID}")):
            try:
                found = read_store(store)
            except Exception as exc:  # a corrupt store must not hide the others
                rows.append({"host": host, "browser": root, "profile": store.parent.parent.name,
                             "error": str(exc)})
                continue
            if "device_id" not in found:
                continue
            rows.append({"host": host, "browser": root, "profile": store.parent.parent.name, **found})
    return rows


def scan_remote(alias):
    try:
        proc = subprocess.run(
            [SSH, "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias,
             "chrome-browsers --local --json"],
            capture_output=True, text=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        return [{"host": alias, "error": "ssh timed out"}]
    if proc.returncode == 127 or "command not found" in proc.stderr:
        return [{"host": alias, "error": "chrome-browsers not deployed there yet"}]
    if proc.returncode != 0:
        reason = (proc.stderr.strip().splitlines() or ["ssh failed"])[-1]
        return [{"host": alias, "error": reason}]
    rows = json.loads(proc.stdout or "[]")
    for row in rows:
        row["host"] = alias
    return rows or [{"host": alias, "note": "no Claude-in-Chrome extension"}]


def scan_fleet():
    me = socket.gethostname().split(".")[0]
    rows = []
    for alias in FLEET:
        if alias == me:
            rows.extend(scan_local() or [{"host": alias, "note": "no Claude-in-Chrome extension"}])
        else:
            rows.extend(scan_remote(alias))
    return rows


def print_table(rows):
    print(f"{'HOST':<12} {'DEVICE ID':<38} {'NAME':<16} PROFILE")
    for row in rows:
        if "device_id" not in row:
            print(f"{row['host']:<12} {'-':<38} {'-':<16} ({row.get('error') or row.get('note')})")
            continue
        name = row.get("name") or row.get("default_name") or "-"
        profile = f"{row['browser']}/{row['profile']}"
        print(f"{row['host']:<12} {row['device_id']:<38} {name:<16} {profile}")


def prompt_text(rows):
    lines = ["Claude-in-Chrome browsers by host (deviceId for select_browser;",
             "only ids that also appear in list_connected_browsers are live):"]
    for row in rows:
        if "device_id" in row:
            lines.append(f"- {row['host']}: {row['device_id']} ({row['browser']}/{row['profile']})")
        else:
            lines.append(f"- {row['host']}: none ({row.get('error') or row.get('note')})")
    return "\n".join(lines) + "\n"


def copy_to_clipboard(text):
    if not os.environ.get("WAYLAND_DISPLAY"):
        return "no Wayland session, clipboard not set"
    try:
        # wl-copy forks a server that keeps serving the selection; hand it no
        # stdout/stderr, or a caller reading our output waits on it forever.
        subprocess.run([WL_COPY], input=text, text=True, check=True, timeout=5,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        return f"clipboard copy failed: {exc}"
    return "copied to clipboard"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument("--local", action="store_true", help="this host only")
    parser.add_argument("--no-copy", action="store_true", help="do not copy the summary to the clipboard")
    args = parser.parse_args()

    rows = scan_local() if args.local else scan_fleet()
    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    else:
        print_table(rows)
    if not args.local and not args.no_copy:
        sys.stdout.flush()
        print(f"\n({copy_to_clipboard(prompt_text(rows))})", file=sys.stderr)
    return 1 if any("error" in row for row in rows) and not args.local else 0


if __name__ == "__main__":
    sys.exit(main())
