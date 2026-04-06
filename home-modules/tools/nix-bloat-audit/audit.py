#!/usr/bin/env python3
"""Rank installed NixOS/Home Manager packages by size and observed usage."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import math
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SYSTEM_SOURCE_REF = "nixosConfigurations.{host}.config.environment.systemPackages"
HOME_SOURCE_REF = "nixosConfigurations.{host}.config.home-manager.users.vpittamp.home.packages"

LOG_DIR_NAME = "nix-usage-audit"
SHELL_LOG_NAME = "shell-commands.tsv"
DESKTOP_LOG_NAME = "desktop-launches.tsv"

SHELL_WRAPPERS = {
    "sudo",
    "command",
    "builtin",
    "env",
    "noglob",
    "nohup",
    "time",
    "nice",
    "ionice",
    "chrt",
    "setsid",
}

COMMAND_BLACKLIST = {
    "cd",
    "exit",
    "fg",
    "bg",
    "jobs",
    "history",
    "clear",
}

CATEGORY_RULES = [
    ("browser", {"firefox", "chromium", "google-chrome", "google-chrome-beta", "google-chrome-unstable", "firefoxpwa"}),
    ("git-ui", {"gitkraken", "gittyup", "lazygit"}),
    ("file-manager", {"yazi", "ranger", "lf", "thunar"}),
    ("terminal", {"ghostty", "alacritty", "foot", "konsole"}),
    ("remote-access", {"rustdesk", "rustdesk-flutter", "remmina", "wayvnc", "wlvncc", "moonlight-qt", "moonlight-ryzen-desktop"}),
    ("ai-tools", {"claude", "codex", "gemini", "goose-cli", "goose-desktop", "openai", "opencode", "openshell"}),
    ("kubernetes", {"kubectl", "k9s", "helm", "headlamp", "argocd", "vcluster", "kind", "skaffold", "talosctl", "minikube"}),
]


def run_command(cmd: list[str], *, cwd: Path | None = None, stdin: str | None = None) -> str:
    completed = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(cmd)}\n{completed.stderr.strip()}"
        )
    return completed.stdout


def detect_repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()

    for env_name in ("FLAKE_ROOT", "NH_OS_FLAKE", "NH_FLAKE"):
        value = os.environ.get(env_name)
        if value:
            path = Path(value).expanduser()
            if (path / "flake.nix").exists():
                return path.resolve()

    try:
        git_root = run_command(["git", "rev-parse", "--show-toplevel"], cwd=Path.cwd()).strip()
    except RuntimeError:
        git_root = ""
    if git_root:
        path = Path(git_root)
        if (path / "flake.nix").exists():
            return path.resolve()

    candidate = Path("/etc/nixos")
    if (candidate / "flake.nix").exists():
        return candidate.resolve()

    raise RuntimeError("unable to locate flake root; pass --repo-root")


def detect_host(explicit: str | None) -> str:
    if explicit:
        return explicit
    env_host = os.environ.get("HOSTNAME")
    if env_host:
        return env_host.split(".")[0]
    return socket.gethostname().split(".")[0]


def nix_eval_paths(repo_root: Path, host: str, attr_path: str) -> list[str]:
    expr = f"paths: builtins.map (p: p.outPath) paths"
    cmd = [
        "nix",
        "eval",
        "--json",
        "--read-only",
        "--option",
        "eval-cache",
        "false",
        f".#nixosConfigurations.{host}.{attr_path}",
        "--apply",
        expr,
    ]
    output = run_command(cmd, cwd=repo_root)
    data = json.loads(output)
    return [path for path in data if isinstance(path, str)]


def nix_path_info(paths: list[str]) -> dict[str, dict[str, Any]]:
    if not paths:
        return {}

    all_info: dict[str, dict[str, Any]] = {}
    batch_size = 64
    for index in range(0, len(paths), batch_size):
        chunk = paths[index : index + batch_size]
        output = run_command(
            [
                "nix",
                "path-info",
                "--json",
                "--json-format",
                "1",
                "--closure-size",
                "--stdin",
            ],
            stdin="\n".join(chunk) + "\n",
        )
        all_info.update(json.loads(output))
    return all_info


def current_system_closure_size() -> int | None:
    try:
        output = run_command(
            [
                "nix",
                "path-info",
                "--json",
                "--json-format",
                "1",
                "--closure-size",
                "/run/current-system",
            ]
        )
    except RuntimeError:
        return None

    payload = json.loads(output)
    for value in payload.values():
        if value and value.get("closureSize") is not None:
            return value["closureSize"]
    return None


def normalize_package_key(name: str) -> str:
    value = name
    if value.startswith("/nix/store/"):
        value = Path(value).name
    if re.match(r"^[a-z0-9]{32}-", value):
        value = value.split("-", 1)[1]
    match = re.match(r"^(.*?)-\d[\w.+-]*$", value)
    if match:
        value = match.group(1)
    return value


def human_size(size_bytes: int | None) -> str:
    if size_bytes is None:
        return "-"
    if size_bytes < 1024:
        return f"{size_bytes} B"
    units = ["KiB", "MiB", "GiB", "TiB"]
    value = float(size_bytes)
    for unit in units:
        value /= 1024.0
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
    return f"{value:.1f} TiB"


def isoformat_epoch(epoch: int | None) -> str | None:
    if epoch is None:
        return None
    return dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).isoformat()


def parse_shell_command(command: str) -> str | None:
    text = command.strip()
    if not text:
        return None
    try:
        parts = shlex.split(text, comments=False, posix=True)
    except ValueError:
        parts = text.split()

    if not parts:
        return None

    index = 0
    while index < len(parts):
        token = parts[index]
        if "=" in token and not token.startswith(("/", "./", "../")) and not token.startswith("-"):
            index += 1
            continue
        if token in SHELL_WRAPPERS:
            index += 1
            if token == "env":
                while index < len(parts) and "=" in parts[index]:
                    index += 1
            continue
        if token in {"bash", "sh", "zsh", "fish"} and "-c" in parts[index + 1 :]:
            return None
        break

    if index >= len(parts):
        return None

    token = parts[index]
    token = os.path.basename(token)
    if token in COMMAND_BLACKLIST:
        return None
    return token


def read_tsv(path: Path) -> list[list[str]]:
    if not path.exists():
        return []
    rows: list[list[str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            rows.append(line.split("\t"))
    return rows


def state_dir() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    return base / LOG_DIR_NAME


def collect_shell_usage(cutoff_epoch: int) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    path = state_dir() / SHELL_LOG_NAME
    usage: dict[str, dict[str, Any]] = {}
    earliest = None
    latest = None

    for row in read_tsv(path):
        if len(row) < 4:
            continue
        try:
            event_epoch = int(row[0])
        except ValueError:
            continue
        earliest = event_epoch if earliest is None else min(earliest, event_epoch)
        latest = event_epoch if latest is None else max(latest, event_epoch)
        if event_epoch < cutoff_epoch:
            continue
        command_name = parse_shell_command(row[3])
        if not command_name:
            continue
        info = usage.setdefault(command_name, {"count": 0, "last_used_at": None})
        info["count"] += 1
        info["last_used_at"] = max(info["last_used_at"] or 0, event_epoch)

    return usage, {
        "path": str(path),
        "exists": path.exists(),
        "first_seen_at": isoformat_epoch(earliest),
        "last_seen_at": isoformat_epoch(latest),
    }


def collect_desktop_usage(cutoff_epoch: int) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    path = state_dir() / DESKTOP_LOG_NAME
    usage: dict[str, dict[str, Any]] = {}
    earliest = None
    latest = None

    for row in read_tsv(path):
        if len(row) < 4:
            continue
        try:
            event_epoch = int(row[0])
        except ValueError:
            continue
        earliest = event_epoch if earliest is None else min(earliest, event_epoch)
        latest = event_epoch if latest is None else max(latest, event_epoch)
        if event_epoch < cutoff_epoch:
            continue
        package_hint = row[3].strip()
        app_name = row[2].strip()
        key = normalize_package_key(package_hint) if package_hint else f"desktop:{app_name.lower()}"
        info = usage.setdefault(key, {"count": 0, "last_used_at": None, "apps": set()})
        info["count"] += 1
        info["last_used_at"] = max(info["last_used_at"] or 0, event_epoch)
        if app_name:
            info["apps"].add(app_name)

    return usage, {
        "path": str(path),
        "exists": path.exists(),
        "first_seen_at": isoformat_epoch(earliest),
        "last_seen_at": isoformat_epoch(latest),
    }


def executable_index(paths: list[str]) -> dict[str, set[str]]:
    mapping: dict[str, set[str]] = {}
    for path in paths:
        bin_dir = Path(path) / "bin"
        commands: set[str] = set()
        if bin_dir.is_dir():
            for child in bin_dir.iterdir():
                if child.is_file() and os.access(child, os.X_OK):
                    commands.add(child.name)
        mapping[path] = commands
    return mapping


@dataclass
class PackageRecord:
    store_path: str
    package_name: str
    package_key: str
    origins: set[str] = field(default_factory=set)
    source_refs: set[str] = field(default_factory=set)
    commands: set[str] = field(default_factory=set)
    closure_size: int | None = None
    nar_size: int | None = None
    category: str = "other"
    shell_count: int = 0
    desktop_count: int = 0
    usage_count: int = 0
    last_used_epoch: int | None = None
    desktop_apps: set[str] = field(default_factory=set)
    recommendation: str = "unknown"
    confidence: str = "low"
    notes: list[str] = field(default_factory=list)


def infer_category(package_key: str) -> str:
    for category, members in CATEGORY_RULES:
        if package_key in members:
            return category
    return "other"


def build_package_records(
    *,
    system_paths: list[str],
    home_paths: list[str],
    path_info: dict[str, dict[str, Any]],
    command_index: dict[str, set[str]],
    shell_usage: dict[str, dict[str, Any]],
    desktop_usage: dict[str, dict[str, Any]],
    host: str,
) -> list[PackageRecord]:
    records: dict[str, PackageRecord] = {}

    def ensure_record(path: str) -> PackageRecord:
        if path not in records:
            store_name = Path(path).name
            package_name = store_name.split("-", 1)[1] if "-" in store_name else store_name
            record = PackageRecord(
                store_path=path,
                package_name=package_name,
                package_key=normalize_package_key(store_name),
            )
            info = path_info.get(path) or {}
            record.closure_size = info.get("closureSize")
            record.nar_size = info.get("narSize")
            record.commands = command_index.get(path, set())
            record.category = infer_category(record.package_key)
            records[path] = record
        return records[path]

    for path in system_paths:
        record = ensure_record(path)
        record.origins.add("system")
        record.source_refs.add(SYSTEM_SOURCE_REF.format(host=host))

    for path in home_paths:
        record = ensure_record(path)
        record.origins.add("home")
        record.source_refs.add(HOME_SOURCE_REF.format(host=host))

    category_members: dict[str, list[PackageRecord]] = collections.defaultdict(list)
    for record in records.values():
        for command in record.commands:
            usage = shell_usage.get(command)
            if not usage:
                continue
            record.shell_count += usage["count"]
            event_epoch = usage.get("last_used_at")
            if event_epoch is not None:
                record.last_used_epoch = max(record.last_used_epoch or 0, event_epoch)

        desktop = desktop_usage.get(record.package_key)
        if desktop:
            record.desktop_count += desktop["count"]
            record.desktop_apps.update(desktop.get("apps", set()))
            event_epoch = desktop.get("last_used_at")
            if event_epoch is not None:
                record.last_used_epoch = max(record.last_used_epoch or 0, event_epoch)

        record.usage_count = record.shell_count + record.desktop_count
        category_members[record.category].append(record)

    for category, members in category_members.items():
        if category == "other" or len(members) < 2:
            continue
        members_sorted = sorted(members, key=lambda item: item.closure_size or 0, reverse=True)
        names = ", ".join(member.package_key for member in members_sorted[:4])
        for member in members:
            member.notes.append(f"shared-category:{category} ({names})")

    return list(records.values())


def telemetry_horizon_days(metadata: dict[str, Any], fallback_days: int) -> int:
    first_seen = metadata.get("first_seen_at")
    last_seen = metadata.get("last_seen_at")
    if not first_seen or not last_seen:
        return 0
    start = dt.datetime.fromisoformat(first_seen)
    end = dt.datetime.fromisoformat(last_seen)
    observed = max(0, math.ceil((end - start).total_seconds() / 86400))
    return min(observed or 1, fallback_days)


def score_recommendation(record: PackageRecord, telemetry_days: int) -> None:
    size = record.closure_size or 0
    large = size >= 500 * 1024 * 1024
    medium = size >= 200 * 1024 * 1024

    if record.usage_count > 0:
        record.recommendation = "keep"
        record.confidence = "high"
        if record.desktop_count and record.shell_count == 0:
            record.notes.append("desktop-only usage observed")
        return

    if telemetry_days >= 14 and large:
        record.recommendation = "likely-removable"
        record.confidence = "high"
        record.notes.append("no shell or desktop usage in a mature telemetry window")
        return

    if telemetry_days >= 7 and (large or medium):
        record.recommendation = "review"
        record.confidence = "medium"
        record.notes.append("no observed usage in the current telemetry window")
        return

    if large:
        record.recommendation = "review"
        record.confidence = "low"
        record.notes.append("large closure, but telemetry window is still short")
        return

    record.recommendation = "unknown"
    record.confidence = "low"
    record.notes.append("not enough evidence yet")


def collect_service_entries(days: int) -> list[dict[str, Any]]:
    if shutil.which("systemctl") is None:
        return []

    cutoff = f"{days} days ago"
    entries: list[dict[str, Any]] = []
    candidates = [
        ("system", "tailscaled.service"),
        ("user", "sunshine.service"),
        ("user", "rustdesk.service"),
        ("user", "wayvnc-dp1.service"),
        ("user", "wayvnc-hdmi.service"),
        ("user", "i3-project-daemon.service"),
    ]

    for scope, unit in candidates:
        base = ["systemctl"]
        journal = ["journalctl"]
        if scope == "user":
            base.append("--user")
            journal.append("--user")

        show_cmd = base + ["show", unit, "--property=UnitFileState,ActiveState,ActiveEnterTimestamp", "--value"]
        completed = subprocess.run(show_cmd, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            continue
        values = [line.strip() for line in completed.stdout.splitlines()]
        if len(values) < 3:
            continue

        active_enter = values[2] or None
        start_count_cmd = journal + ["-u", unit, "--since", cutoff, "-g", "Started", "--no-pager", "--output", "short-unix"]
        journal_output = subprocess.run(start_count_cmd, capture_output=True, text=True, check=False).stdout
        starts = sum(1 for line in journal_output.splitlines() if line.strip())

        entries.append(
            {
                "item_type": "service",
                "name": unit,
                "origin": scope,
                "scope": scope,
                "unit_file_state": values[0],
                "active_state": values[1],
                "usage_count": starts,
                "last_used_at": active_enter,
                "recommendation": "review" if values[0] == "enabled" and starts == 0 else "keep",
                "confidence": "low" if starts == 0 else "medium",
                "notes": ["service activity is inferred from start events, not interactive launches"],
            }
        )

    return entries


def format_table(records: list[dict[str, Any]], limit: int) -> str:
    headers = ["recommendation", "size", "usage", "last_used", "name", "origin", "notes"]
    rows = []
    for item in records[:limit]:
        notes = ", ".join(item.get("notes", [])[:2])
        rows.append(
            [
                item.get("recommendation", "-"),
                human_size(item.get("estimated_closure_size")),
                str(item.get("usage_count", 0)),
                item.get("last_used_at", "-") or "-",
                item.get("name", "-"),
                item.get("origin", "-"),
                notes,
            ]
        )

    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    rendered = [
        "  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)),
        "  ".join("-" * widths[index] for index in range(len(headers))),
    ]
    for row in rows:
        rendered.append("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))
    return "\n".join(rendered)


def main() -> int:
    parser = argparse.ArgumentParser(description="Rank installed Nix packages by size and observed usage.")
    parser.add_argument("--host", help="flake host to analyze; defaults to the current hostname")
    parser.add_argument("--repo-root", help="path to the nixos flake root")
    parser.add_argument("--days", type=int, default=30, help="usage window in days (default: 30)")
    parser.add_argument("--limit", type=int, default=40, help="maximum rows in table output")
    parser.add_argument("--format", choices=("table", "json"), default="table", help="output format")
    args = parser.parse_args()

    repo_root = detect_repo_root(args.repo_root)
    host = detect_host(args.host)
    cutoff_epoch = int(dt.datetime.now(tz=dt.timezone.utc).timestamp()) - args.days * 86400

    system_paths = nix_eval_paths(repo_root, host, "config.environment.systemPackages")
    home_paths = nix_eval_paths(repo_root, host, "config.home-manager.users.vpittamp.home.packages")

    unique_paths = sorted(set(system_paths) | set(home_paths))
    info = nix_path_info(unique_paths)
    commands = executable_index(unique_paths)
    shell_usage, shell_metadata = collect_shell_usage(cutoff_epoch)
    desktop_usage, desktop_metadata = collect_desktop_usage(cutoff_epoch)

    records = build_package_records(
        system_paths=system_paths,
        home_paths=home_paths,
        path_info=info,
        command_index=commands,
        shell_usage=shell_usage,
        desktop_usage=desktop_usage,
        host=host,
    )

    telemetry_days = max(
        telemetry_horizon_days(shell_metadata, args.days),
        telemetry_horizon_days(desktop_metadata, args.days),
    )

    for record in records:
        score_recommendation(record, telemetry_days)

    records.sort(
        key=lambda item: (
            {"likely-removable": 0, "review": 1, "unknown": 2, "keep": 3}.get(item.recommendation, 4),
            -(item.closure_size or 0),
            item.package_key,
        )
    )

    package_items = [
        {
            "host": host,
            "generated_at": dt.datetime.now(tz=dt.timezone.utc).isoformat(),
            "item_type": "package",
            "name": record.package_name,
            "package_key": record.package_key,
            "origin": "+".join(sorted(record.origins)),
            "source_ref": sorted(record.source_refs),
            "store_path": record.store_path,
            "estimated_closure_size": record.closure_size,
            "nar_size": record.nar_size,
            "usage_count": record.usage_count,
            "shell_count": record.shell_count,
            "desktop_count": record.desktop_count,
            "last_used_at": isoformat_epoch(record.last_used_epoch),
            "evidence_sources": [source for source, count in (("shell", record.shell_count), ("desktop", record.desktop_count)) if count > 0],
            "recommendation": record.recommendation,
            "confidence": record.confidence,
            "category": record.category,
            "commands": sorted(record.commands),
            "desktop_apps": sorted(record.desktop_apps),
            "notes": record.notes,
        }
        for record in records
    ]

    service_items = collect_service_entries(args.days)

    payload = {
        "host": host,
        "generated_at": dt.datetime.now(tz=dt.timezone.utc).isoformat(),
        "repo_root": str(repo_root),
        "window_days": args.days,
        "telemetry_window_days_observed": telemetry_days,
        "telemetry_sources": {
            "shell": shell_metadata,
            "desktop": desktop_metadata,
        },
        "summary": {
            "system_package_count": len(set(system_paths)),
            "home_package_count": len(set(home_paths)),
            "package_record_count": len(package_items),
            "service_record_count": len(service_items),
            "current_system_closure_size": current_system_closure_size(),
        },
        "items": package_items + service_items,
    }

    if args.format == "json":
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    print(f"Host: {host}")
    print(f"Repo: {repo_root}")
    print(f"Window: {args.days} days (observed telemetry horizon: {telemetry_days} days)")
    print(
        "Telemetry:"
        f" shell={'present' if shell_metadata['exists'] else 'missing'}"
        f", desktop={'present' if desktop_metadata['exists'] else 'missing'}"
    )
    print(f"Current system closure: {human_size(payload['summary']['current_system_closure_size'])}")
    print("")
    print(format_table(package_items, args.limit))
    if service_items:
        print("")
        print("Services")
        print(format_table(service_items, min(args.limit, len(service_items))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
