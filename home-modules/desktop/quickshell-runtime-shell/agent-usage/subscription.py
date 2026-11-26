#!/usr/bin/env python3
"""Produce a QuickShell subscription usage record for Kimi Code or Z.ai."""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener, urlopen


class UsageUnavailable(Exception):
    pass


def reset_time(value):
    try:
        if isinstance(value, (int, float)) or str(value).isdigit():
            return datetime.fromtimestamp(float(value) / 1000, timezone.utc).isoformat()
        timestamp = datetime.fromisoformat(value)
        return timestamp.isoformat() if timestamp.tzinfo else timestamp.replace(tzinfo=timezone.utc).isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return ""


def meter(label, value, resets_at):
    if not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0:
        return None
    return {"label": label, "percent": min(value, 1), "resetsAt": reset_time(resets_at)}


def kimi_usage():
    # The CLI's authenticated loopback API handles the managed OAuth login,
    # including renewal. Port 0 lets the OS assign a port for this query.
    command = ["kimi", "web", "--host", "127.0.0.1", "--port", "0", "--no-open", "--log-level", "error"]
    with tempfile.TemporaryDirectory(prefix="quickshell-kimi-usage-") as cwd:
        with subprocess.Popen(command, cwd=cwd, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    # The shared refresh service runs with a CPU quota and may
                    # be scanning the other providers while Kimi starts.
                    deadline = time.monotonic() + 30
                    banner = b""
                    match = None
                    while selector.select(max(0, deadline - time.monotonic())) and len(banner) < 16384:
                        chunk = os.read(process.stdout.fileno(), 4096)
                        if not chunk:
                            break
                        banner += chunk
                        match = re.search(rb"http://127\.0\.0\.1:(\d+)/#token=([\w.-]+)\r?\n", banner)
                        if match or time.monotonic() >= deadline:
                            break
                if not match:
                    raise UsageUnavailable("Could not start Kimi Code's local usage API.")
                port, token = (part.decode("ascii") for part in match.groups())
                request = Request(f"http://127.0.0.1:{port}/api/v1/oauth/usage",
                                  headers={"Authorization": "Bearer " + token})
                with build_opener(ProxyHandler({})).open(request, timeout=18) as response:
                    data = json.load(response)["data"]
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()

    if data.get("kind") != "ok":
        message = str(data.get("message", "")).lower()
        if data.get("status") in (401, 403) or "login" in message or "refresh token" in message:
            raise UsageUnavailable("Run `kimi login` to renew the Kimi Code subscription login.")
        raise UsageUnavailable("Kimi Code could not fetch subscription usage.")
    return kimi_limits(data), ""


def kimi_limits(data):
    limits = []
    # Older CLI versions expose rows; newer versions return named windows.
    quota = data.get("quota") or {}
    windows = quota.get("usages") or {}
    for key, label in (("limit7d", "Weekly (7-day)"), ("limit5h", "Session (5-hour)"),
                       ("monthCode", "Monthly coding"), ("monthTotal", "Monthly total")):
        entry = windows.get(key) or {}
        limits.append(meter(label, entry.get("usedRatio"), entry.get("resetAt")))
    if not any(limits):
        for row in [*(data.get("limits") or []), data.get("summary")]:
            if not isinstance(row, dict):
                continue
            window = row.get("window")
            if isinstance(window, dict):
                window = f"{window.get('duration', '')} {window.get('unit', '')}"
            window = str(window or row.get("name") or "")
            if re.search(r"week|7\s*[- ]?\s*d", window, re.I):
                label = "Weekly (7-day)"
            elif re.search(r"5\s*[- ]?\s*h", window, re.I):
                label = "Session (5-hour)"
            else:
                label = str(row.get("name") or window)
            used, limit = row.get("used"), row.get("limit")
            if label and isinstance(used, (int, float)) and isinstance(limit, (int, float)) and limit > 0:
                limits.append(meter(label, used / limit, row.get("reset_at")))
    return [entry for entry in limits if entry is not None]


def zai_usage():
    token = os.environ.get("ZAI_API_KEY", "")
    if not token:
        ref = os.environ.get("ZAI_API_KEY_REF")
        try:
            token = subprocess.check_output(["op", "read", ref], text=True, timeout=12,
                                            stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL).strip() if ref else ""
        except (OSError, subprocess.SubprocessError):
            token = ""
        if not token:
            raise UsageUnavailable("Unlock 1Password to read the Z.ai Coding Plan key.")
    url = "https://api.z.ai/api/monitor/usage/quota/limit"
    request = Request(url, headers={"Accept": "application/json"})
    request.add_unredirected_header("Authorization", token)
    try:
        with urlopen(request, timeout=10) as response:
            data = json.load(response)["data"]
    except HTTPError as error:
        if error.code in (401, 403):
            raise UsageUnavailable("Z.ai rejected the Coding Plan key.") from None
        raise
    return zai_limits(data), str(data.get("level") or "")


def zai_limits(data):
    limits = []
    labels = {("TOKENS_LIMIT", 6): "Weekly (7-day)", ("TOKENS_LIMIT", 3): "Session (5-hour)",
              ("TIME_LIMIT", 5): "Monthly MCP usage"}
    for entry in data.get("limits") or []:
        if not isinstance(entry, dict):
            continue
        label = labels.get((entry.get("type"), entry.get("unit")))
        percent = entry.get("percentage")
        if label and isinstance(percent, (int, float)):
            limits.append(meter(label, percent / 100, entry.get("nextResetTime")))
    return [entry for entry in limits if entry is not None]


def collect(agent, configured, fetch, force):
    now = datetime.now(timezone.utc)
    record = {"schemaVersion": 1, "id": agent, "name": {"kimi": "Kimi Code", "zai": "Z.ai"}[agent],
              "ready": configured, "hasLocalStats": False, "updatedAt": now.isoformat(), "limits": []}
    if not configured:
        return record

    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-runtime-shell" / "agent-usage"
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / f"{agent}-subscription.json"
    try:
        cached = json.loads(path.read_text())
    except (OSError, ValueError):
        cached = {}
    if cached and not force and time.time() - cached.get("fetchedAt", 0) < 60:
        return cached["record"]

    try:
        limits, plan = fetch()
        if not limits:
            raise UsageUnavailable("The provider returned no usage limits.")
    except (UsageUnavailable, OSError, ValueError, TypeError, KeyError) as error:
        previous = cached.get("record", {})
        record["limits"] = [limit for limit in previous.get("limits", [])
                            if not limit["resetsAt"] or datetime.fromisoformat(limit["resetsAt"]) > now]
        record["tierLabel"] = previous.get("tierLabel", "")
        record["updatedAt"] = previous.get("updatedAt", record["updatedAt"])
        record["usageStatusText"] = "Usage temporarily unavailable"
        record["authHelpText"] = str(error) if isinstance(error, UsageUnavailable) else "Could not refresh subscription usage."
        return record

    record.update(limits=limits, tierLabel=plan)
    with tempfile.NamedTemporaryFile(mode="w", dir=cache, delete=False) as tmp:
        try:
            json.dump({"fetchedAt": time.time(), "record": record}, tmp)
            tmp.close()
            Path(tmp.name).replace(path)
        finally:
            Path(tmp.name).unlink(missing_ok=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("agent", choices=("kimi", "zai"))
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limits-only", action="store_true")
    args = parser.parse_args()
    if args.agent == "kimi":
        home = Path(os.environ.get("KIMI_CODE_HOME") or Path.home() / ".kimi-code")
        configured = bool(shutil.which("kimi") and (home / "config.toml").exists())
        fetch = kimi_usage
    else:
        configured = bool(os.environ.get("ZAI_API_KEY") or (os.environ.get("ZAI_API_KEY_REF") and shutil.which("op")))
        fetch = zai_usage
    print(json.dumps(collect(args.agent, configured, fetch, args.force), separators=(",", ":")))


if __name__ == "__main__":
    main()
