"""
Monitoring Panel Data Backend Script

Queries i3pm daemon for window/workspace/project state and outputs JSON for Eww consumption.

Usage:
    python3 -m i3_project_manager.cli.monitoring_data                   # Windows view (default)
    python3 -m i3_project_manager.cli.monitoring_data --mode projects   # Projects view
    python3 -m i3_project_manager.cli.monitoring_data --mode apps       # Apps view
    python3 -m i3_project_manager.cli.monitoring_data --mode tailscale  # Tailscale view
    python3 -m i3_project_manager.cli.monitoring_data --mode events     # Events view
    python3 -m i3_project_manager.cli.monitoring_data --mode health     # Health view
    python3 -m i3_project_manager.cli.monitoring_data --mode traces     # Window traces view (Feature 101)
    python3 -m i3_project_manager.cli.monitoring_data --listen          # Stream mode (deflisten)

Output: Single-line JSON to stdout (see contracts/eww-defpoll.md)

Performance: <50ms execution time for typical workload (20-30 windows)

Stream Mode (--listen):
    - Subscribes to Sway window/workspace/output events
    - Outputs JSON on every state change (<100ms latency)
    - Includes heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff
    - Graceful shutdown on SIGTERM/SIGPIPE
"""

import argparse
import asyncio
import hashlib
import json
import logging
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Literal

# Pydantic for data validation (Feature 092)
from pydantic import BaseModel, Field

# Import daemon client from core module
from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

# Feature 097: Import models and utilities for project hierarchy
from i3_project_manager.models.project_config import (
    ProjectConfig,
    SourceType,
    ProjectStatus,
    GitMetadata,
    RepositoryWithWorktrees,
    PanelProjectsData,
)
from i3_project_manager.services.git_utils import (
    detect_orphaned_worktrees,
    get_bare_repository_path,
    format_relative_time,
)

# Import i3ipc for event subscriptions in listen mode
try:
    from i3ipc.aio import Connection as I3Connection
except ImportError:
    I3Connection = None  # Gracefully handle missing i3ipc in one-shot mode

# Feature 095 Enhancement: Animated spinner frames for "working" state badges
# Braille dot spinner: elegant, modern, 10 frames cycling every 120ms
SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
SPINNER_INTERVAL_MS = 120  # milliseconds per frame


def get_spinner_frame() -> str:
    """Get current spinner frame based on time.

    Uses millisecond precision to determine which frame to show.
    Frame changes every SPINNER_INTERVAL_MS milliseconds.
    """
    ms = int(time.time() * 1000)
    idx = (ms // SPINNER_INTERVAL_MS) % len(SPINNER_FRAMES)
    return SPINNER_FRAMES[idx]


# Feature 095: File-based badge state directory
# Badge state files are written by claude-hooks scripts and read by this script
# Format: $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
BADGE_STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "i3pm-badges"

# Feature 123: OTEL AI sessions file path
# Written by otel-ai-monitor service, read here to include in monitoring_data output
OTEL_SESSIONS_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "otel-ai-sessions.json"
AI_SESSION_MRU_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-session-mru.json"
AI_SESSION_PIN_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-session-pins.json"
AI_SESSION_NOTIFY_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-session-notify-state.json"
AI_MONITOR_METRICS_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-monitor-metrics.json"
AI_SESSION_REVIEW_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-session-review.json"
AI_SESSION_SEEN_EVENTS_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "ai-session-seen-events.jsonl"

# Feature 101: Active worktree configuration file
ACTIVE_WORKTREE_FILE = Path.home() / ".config" / "i3" / "active-worktree.json"

# Feature 107: inotify watcher for immediate badge detection (<15ms latency)
# Uses subprocess inotifywait to avoid adding Python dependencies
INOTIFYWAIT_CMD = "inotifywait"  # Requires inotify-tools package

# Remote sesh/tmux session discovery cache (for SSH project window augmentation)
REMOTE_SESH_CACHE_TTL_SECONDS = 15
REMOTE_SESH_CACHE: Dict[str, Dict[str, Any]] = {}
REMOTE_OTEL_SINK_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "eww-monitoring-panel" / "remote-otel-sink.json"
REMOTE_OTEL_SOURCE_STALE_SECONDS = float(
    os.environ.get("I3PM_MONITORING_REMOTE_OTEL_STALE_SECONDS", "20")
)
REMOTE_OTEL_SINK_CACHE: Dict[str, Any] = {
    "mtime_ns": None,
    "size": None,
    "payload": {},
}
DISCOVERED_TMUX_PROJECT_HINT_CACHE: Dict[str, Any] = {
    "mtime_ns": None,
    "size": None,
    "mapping": {},
}
OTEL_WINDOW_RESOLUTION_CACHE_TTL_SECONDS = 5.0
OTEL_WINDOW_RESOLUTION_CACHE: Dict[str, Dict[str, Any]] = {}


def _normalize_session_name_key(value: str) -> str:
    """Normalize session names so separator variants map to one logical key."""
    from i3_project_manager.core.identity import normalize_session_name_key
    return normalize_session_name_key(value)


def load_badge_state_from_files() -> Dict[str, Any]:
    """Load badge state from filesystem.

    Feature 095: File-based badge tracking without daemon dependency.
    Reads JSON files from $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json

    Returns:
        Dict mapping window_id (string) to badge metadata
    """
    badge_state: Dict[str, Any] = {}

    if not BADGE_STATE_DIR.exists():
        return badge_state

    for badge_file in BADGE_STATE_DIR.glob("*.json"):
        try:
            with open(badge_file, "r") as f:
                badge_data = json.load(f)
                window_id = badge_file.stem  # filename without .json extension
                badge_state[window_id] = badge_data
                logger.debug(f"Feature 095: Loaded badge for window {window_id}: {badge_data.get('state', 'unknown')}")
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Feature 095: Failed to read badge file {badge_file}: {e}")
            continue

    return badge_state


def load_otel_sessions() -> Dict[str, Any]:
    """Load OTEL AI sessions from JSON file.

    Feature 123: Reads session data written by otel-ai-monitor service.
    This is used by EWW monitoring panel for window badge rendering.

    Feature 136: Also returns sessions_by_window for efficient lookup.
    Global/orphaned sessions are intentionally suppressed to enforce
    project-scoped session visibility.

    Returns:
        Dict with 'sessions' list, 'has_working' boolean, and
        'sessions_by_window' dict.
    """
    default_result = {
        "schema_version": "4",
        "sessions": [],
        "has_working": False,
        "timestamp": 0,
        "updated_at": "",
        "sessions_by_window": {},
    }

    if not OTEL_SESSIONS_FILE.exists():
        return default_result

    try:
        with open(OTEL_SESSIONS_FILE, "r") as f:
            data = json.load(f)
            # Validate expected structure
            sessions = data.get("sessions", [])
            has_working = data.get("has_working", False)
            timestamp = data.get("timestamp", 0)
            updated_at = data.get("updated_at", "")
            schema_version = str(data.get("schema_version", "1"))
            sessions_by_window = data.get("sessions_by_window", {})

            return {
                "sessions": sessions,
                "has_working": has_working,
                "timestamp": timestamp,
                "updated_at": updated_at,
                "schema_version": schema_version,
                "sessions_by_window": sessions_by_window,
            }
    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Feature 123: Failed to read OTEL sessions file: {e}")
        return default_result


def _remote_otel_merge_enabled() -> bool:
    """Whether deterministic remote OTEL sink merge is enabled."""
    raw = str(os.environ.get("I3PM_MONITORING_REMOTE_OTEL", "auto") or "auto").strip().lower()
    if raw in {"0", "false", "no", "off"}:
        return False
    if raw in {"1", "true", "yes", "on"}:
        return True
    # Auto mode: disable during pytest to keep unit tests deterministic/fast.
    if os.environ.get("PYTEST_CURRENT_TEST"):
        return False
    return True


def _parse_ssh_connection_key(connection_key: str) -> Optional[Dict[str, Any]]:
    """Parse normalized ssh connection key into ssh target fields."""
    raw = str(connection_key or "").strip()
    if not raw or raw.startswith("local@") or raw in {"unknown", "global"}:
        return None

    m = re.match(r"^(?:(?P<user>[^@:\s]+)@)?(?P<host>[^:\s]+)(?::(?P<port>\d+))?$", raw)
    if not m:
        return None

    host = str(m.group("host") or "").strip()
    if not host:
        return None

    user = str(m.group("user") or "").strip()
    port_raw = str(m.group("port") or "").strip()
    try:
        port = int(port_raw) if port_raw else 22
    except ValueError:
        port = 22

    target = f"{user}@{host}" if user else host
    return {
        "target": target,
        "host": host,
        "user": user,
        "port": port,
        "connection_key": _normalize_connection_key(raw),
    }


def _load_remote_otel_sink() -> Dict[str, Any]:
    """Load deterministic remote OTEL sink payload."""
    if not REMOTE_OTEL_SINK_FILE.exists():
        REMOTE_OTEL_SINK_CACHE.update({
            "mtime_ns": None,
            "size": None,
            "payload": {},
        })
        return {}
    try:
        stat_result = REMOTE_OTEL_SINK_FILE.stat()
        cached_mtime = REMOTE_OTEL_SINK_CACHE.get("mtime_ns")
        cached_size = REMOTE_OTEL_SINK_CACHE.get("size")
        if (
            cached_mtime == stat_result.st_mtime_ns
            and cached_size == stat_result.st_size
        ):
            cached_payload = REMOTE_OTEL_SINK_CACHE.get("payload")
            if isinstance(cached_payload, dict):
                return dict(cached_payload)
        with open(REMOTE_OTEL_SINK_FILE, "r") as f:
            payload = json.load(f)
            if isinstance(payload, dict):
                REMOTE_OTEL_SINK_CACHE.update({
                    "mtime_ns": stat_result.st_mtime_ns,
                    "size": stat_result.st_size,
                    "payload": dict(payload),
                })
                return payload
    except (json.JSONDecodeError, IOError, OSError):
        return {}
    return {}


def _window_candidates_cache_fingerprint(window_candidates: Optional[List[Dict[str, Any]]]) -> str:
    """Build a stable cache fingerprint for current window candidates."""
    candidates = window_candidates or []
    items: List[List[str]] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        items.append([
            str(_safe_int(candidate.get("id"), 0)),
            str(candidate.get("project") or ""),
            str(candidate.get("execution_mode") or ""),
            str(candidate.get("connection_key") or ""),
            str(candidate.get("context_key") or ""),
        ])
    raw = json.dumps(items, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def _window_resolution_cache_key(
    session: Dict[str, Any],
    *,
    candidates_fingerprint: str,
) -> str:
    """Build cache key for OTEL session -> window resolution."""
    terminal_context = session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}
    payload = {
        "tool": str(session.get("tool") or ""),
        "project": str(session.get("project") or ""),
        "project_path": str(session.get("project_path") or ""),
        "native_session_id": str(session.get("native_session_id") or ""),
        "session_id": str(session.get("session_id") or ""),
        "context_fingerprint": str(session.get("context_fingerprint") or ""),
        "trace_id": str(session.get("trace_id") or ""),
        "execution_mode": str(session.get("execution_mode") or terminal_context.get("execution_mode") or ""),
        "connection_key": str(session.get("connection_key") or terminal_context.get("connection_key") or ""),
        "context_key": str(session.get("context_key") or terminal_context.get("context_key") or ""),
        "tmux_session": str(terminal_context.get("tmux_session") or session.get("tmux_session") or ""),
        "tmux_window": str(terminal_context.get("tmux_window") or session.get("tmux_window") or ""),
        "tmux_pane": str(terminal_context.get("tmux_pane") or session.get("tmux_pane") or ""),
        "pty": str(terminal_context.get("pty") or session.get("pty") or ""),
        "window_id": _safe_int(session.get("window_id", terminal_context.get("window_id")), 0),
        "candidates": candidates_fingerprint,
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def _get_cached_window_resolution(cache_key: str) -> tuple[bool, Optional[int]]:
    """Return cached window resolution result when still fresh."""
    now = time.time()
    expired = [
        key
        for key, value in OTEL_WINDOW_RESOLUTION_CACHE.items()
        if now - float(value.get("updated_at", 0.0) or 0.0) > OTEL_WINDOW_RESOLUTION_CACHE_TTL_SECONDS
    ]
    for key in expired:
        OTEL_WINDOW_RESOLUTION_CACHE.pop(key, None)

    entry = OTEL_WINDOW_RESOLUTION_CACHE.get(cache_key)
    if not isinstance(entry, dict):
        return False, None

    window_id = _safe_int(entry.get("window_id"), 0)
    return True, window_id if window_id > 0 else None


def _store_cached_window_resolution(cache_key: str, window_id: Optional[int]) -> None:
    """Store window resolution result for a short TTL."""
    OTEL_WINDOW_RESOLUTION_CACHE[cache_key] = {
        "window_id": int(window_id) if window_id is not None else 0,
        "updated_at": time.time(),
    }


def _connection_key_aliases(value: str) -> set[str]:
    """Build equivalent normalized aliases for an SSH connection key."""
    aliases: set[str] = set()
    raw = str(value or "").strip()
    if not raw:
        return aliases

    normalized = _normalize_connection_key(raw)
    if normalized and normalized not in {"unknown", "global"}:
        aliases.add(normalized)

    parsed = _parse_ssh_connection_key(raw)
    if not parsed:
        return aliases

    user = str(parsed.get("user") or "").strip()
    host = str(parsed.get("host") or "").strip().lower()
    port = int(parsed.get("port") or 22)
    if not host:
        return aliases

    host_aliases = {host}
    if "." in host:
        host_aliases.add(host.split(".", 1)[0])

    for host_alias in host_aliases:
        base_target = f"{user}@{host_alias}" if user else host_alias
        aliases.add(_normalize_connection_key(base_target))
        aliases.add(_normalize_connection_key(f"{base_target}:{port}"))
        if port == 22:
            aliases.add(_normalize_connection_key(f"{base_target}:22"))
    return {alias for alias in aliases if alias and alias not in {"unknown", "global"}}


def _match_remote_otel_sink_source(
    sink_payload: Dict[str, Any],
    normalized_connection_key: str,
) -> Dict[str, Any]:
    """Resolve remote sink source for the requested normalized connection key."""
    sources = sink_payload.get("sources", {})
    if not isinstance(sources, dict):
        return {}

    direct = sources.get(normalized_connection_key)
    if isinstance(direct, dict):
        return direct

    target_aliases = _connection_key_aliases(normalized_connection_key)
    if normalized_connection_key:
        target_aliases.add(_normalize_connection_key(normalized_connection_key))

    for key, source in sources.items():
        if not isinstance(source, dict):
            continue
        source_aliases = _connection_key_aliases(str(key or ""))
        source_aliases.update(
            _connection_key_aliases(str(source.get("connection_key") or ""))
        )
        if target_aliases.intersection(source_aliases):
            return source
    return {}


def _normalize_remote_otel_session(
    session: Dict[str, Any],
    connection_key: str,
    host: str,
    remote_target: str,
    *,
    source_stale: bool = False,
    source_age_seconds: int = 0,
) -> Dict[str, Any]:
    """Ensure remote OTEL session has canonical SSH identity metadata."""
    normalized = dict(session)
    terminal_context = normalized.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}
    raw_context_key = str(
        terminal_context.get("context_key") or normalized.get("context_key") or ""
    ).strip()
    canonical_context_key = ""
    if raw_context_key:
        parsed_context = _parse_context_key(raw_context_key)
        qualified_name = str(parsed_context.get("qualified_name") or "").strip()
        parsed_mode = _normalize_execution_mode(
            parsed_context.get("execution_mode"),
            default="",
        )
        parsed_connection = str(parsed_context.get("connection_key") or "").strip()
        if (
            qualified_name
            and parsed_mode == "ssh"
            and parsed_connection
            and _connection_keys_equivalent(parsed_connection, connection_key)
        ):
            canonical_context_key = f"{qualified_name}::ssh::{connection_key}"

    normalized["execution_mode"] = "ssh"
    normalized["connection_key"] = connection_key
    if canonical_context_key:
        normalized["context_key"] = canonical_context_key
    else:
        normalized.pop("context_key", None)

    terminal_context["execution_mode"] = "ssh"
    terminal_context["connection_key"] = connection_key
    if canonical_context_key:
        terminal_context["context_key"] = canonical_context_key
    else:
        terminal_context.pop("context_key", None)
    terminal_context["remote_target"] = terminal_context.get("remote_target") or remote_target
    terminal_context["host_name"] = terminal_context.get("host_name") or host
    normalized["terminal_context"] = terminal_context
    normalized["remote_source_stale"] = bool(source_stale)
    normalized["remote_source_age_seconds"] = int(max(0, source_age_seconds))
    return normalized


def _load_remote_otel_sessions_for_connection(
    connection_key: str,
    *,
    sink_payload: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """Load remote OTEL sessions from deterministic sink state."""
    parsed = _parse_ssh_connection_key(connection_key)
    if not parsed:
        return []

    normalized_key = str(parsed["connection_key"])
    sink_payload = sink_payload if isinstance(sink_payload, dict) else _load_remote_otel_sink()
    source = _match_remote_otel_sink_source(sink_payload, normalized_key)
    if not source:
        return []

    raw_sessions = source.get("sessions", [])
    if not isinstance(raw_sessions, list):
        return []

    now_ts = time.time()
    source_received = float(source.get("received_at", 0.0) or 0.0)
    source_age = (
        int(max(0.0, now_ts - source_received))
        if source_received > 0
        else int(REMOTE_OTEL_SOURCE_STALE_SECONDS + 1)
    )
    source_stale = source_received <= 0 or source_age > REMOTE_OTEL_SOURCE_STALE_SECONDS

    host_name = str(source.get("host_name") or parsed["host"])
    remote_target = str(source.get("remote_target") or f"{parsed['target']}:{parsed['port']}")

    merged: List[Dict[str, Any]] = []
    for item in raw_sessions:
        if not isinstance(item, dict):
            continue
        normalized_item = _normalize_remote_otel_session(
            item,
            connection_key=normalized_key,
            host=host_name,
            remote_target=remote_target,
            source_stale=source_stale,
            source_age_seconds=source_age,
        )
        if not _session_tracking_contract_ok(normalized_item):
            continue
        merged.append(normalized_item)
    return merged


def _load_remote_otel_sessions_for_windows(
    window_candidates: Optional[List[Dict[str, Any]]],
) -> List[Dict[str, Any]]:
    """Fetch and merge remote OTEL sessions for active SSH window identities."""
    if not _remote_otel_merge_enabled():
        return []
    if not window_candidates:
        return []

    connection_keys: List[str] = []
    seen: set[str] = set()
    for candidate in window_candidates:
        if str(candidate.get("execution_mode") or "").strip().lower() != "ssh":
            continue
        raw_connection = str(candidate.get("connection_key") or "").strip()
        if not raw_connection:
            continue
        normalized_connection = _normalize_connection_key(raw_connection)
        if normalized_connection in {"unknown", "global"} or normalized_connection.startswith("local@"):
            continue
        if normalized_connection in seen:
            continue
        seen.add(normalized_connection)
        connection_keys.append(normalized_connection)

    sink_payload = _load_remote_otel_sink()
    merged: List[Dict[str, Any]] = []
    for connection_key in connection_keys:
        merged.extend(
            _load_remote_otel_sessions_for_connection(
                connection_key,
                sink_payload=sink_payload,
            )
        )

    # Best-effort dedupe by native session identity and terminal location.
    deduped: Dict[str, Dict[str, Any]] = {}
    for session in merged:
        terminal_context = session.get("terminal_context", {}) or {}
        if not isinstance(terminal_context, dict):
            terminal_context = {}
        key_parts = [
            str(session.get("tool") or ""),
            str(session.get("native_session_id") or ""),
            str(session.get("connection_key") or ""),
            str(terminal_context.get("tmux_pane") or ""),
            str(terminal_context.get("pty") or ""),
            str(session.get("session_id") or ""),
        ]
        dedupe_key = "|".join(key_parts)
        existing = deduped.get(dedupe_key)
        if existing is None or str(session.get("updated_at") or "") >= str(existing.get("updated_at") or ""):
            deduped[dedupe_key] = session

    return list(deduped.values())


def load_ai_session_mru() -> List[str]:
    """Load AI session MRU order from runtime state file."""
    if not AI_SESSION_MRU_FILE.exists():
        return []
    try:
        with open(AI_SESSION_MRU_FILE, "r") as f:
            payload = json.load(f)
            if isinstance(payload, list):
                return [str(item) for item in payload if isinstance(item, str) and item.strip()]
    except (json.JSONDecodeError, IOError):
        return []
    return []


def load_ai_session_pins() -> List[str]:
    """Load pinned AI session keys from runtime state file."""
    if not AI_SESSION_PIN_FILE.exists():
        return []
    try:
        with open(AI_SESSION_PIN_FILE, "r") as f:
            payload = json.load(f)
            if isinstance(payload, list):
                return [str(item) for item in payload if isinstance(item, str) and item.strip()]
    except (json.JSONDecodeError, IOError):
        return []
    return []


def emit_ai_state_transition_notifications(active_sessions: List[Dict[str, Any]]) -> None:
    """Notify on meaningful transitions with debounce."""
    try:
        now_ts = time.time()
        cache: Dict[str, Any] = {}
        if AI_SESSION_NOTIFY_FILE.exists():
            try:
                with open(AI_SESSION_NOTIFY_FILE, "r") as f:
                    loaded_cache = json.load(f)
                    if isinstance(loaded_cache, dict):
                        cache = loaded_cache
            except (json.JSONDecodeError, IOError, ValueError, TypeError):
                cache = {}

        sessions_cache = cache.get("sessions", {})
        if not isinstance(sessions_cache, dict):
            sessions_cache = {}
        last_global_notification = float(cache.get("last_global_notification", 0.0) or 0.0)

        current_keys = {str(s.get("session_key") or "") for s in active_sessions if str(s.get("session_key") or "")}
        # Drop stale cache entries to keep file bounded.
        sessions_cache = {k: v for k, v in sessions_cache.items() if k in current_keys}

        debounce_seconds = 12.0
        for session in active_sessions:
            key = str(session.get("session_key") or "")
            if not key:
                continue
            current_state = str(session.get("stage") or session.get("otel_state") or "idle")
            previous_entry = sessions_cache.get(key, {}) if isinstance(sessions_cache.get(key), dict) else {}
            previous_state = str(previous_entry.get("state") or "")
            last_notified = float(previous_entry.get("last_notified", 0.0) or 0.0)

            should_notify = (
                previous_state in {"starting", "thinking", "tool_running", "streaming"}
                and current_state in {"waiting_input", "attention", "output_ready"}
                and (now_ts - max(last_notified, last_global_notification)) >= debounce_seconds
            )
            if should_notify:
                tool = str(session.get("display_tool") or session.get("tool") or "AI")
                project = str(session.get("display_project") or session.get("project") or "unknown")
                target = str(session.get("display_target") or "")
                if current_state == "waiting_input":
                    summary = "Waiting on you"
                elif current_state == "attention":
                    summary = "Needs attention"
                else:
                    summary = str(session.get("stage_label") or "Ready")
                details = project + (f" · {target}" if target else "")
                subprocess.run(
                    ["notify-send", "-u", "normal", f"{tool}: {summary}", details],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                last_notified = now_ts
                last_global_notification = now_ts

            sessions_cache[key] = {
                "state": current_state,
                "last_seen": now_ts,
                "last_notified": last_notified,
            }

        cache = {
            "sessions": sessions_cache,
            "last_global_notification": last_global_notification,
            "updated_at": now_ts,
        }
        _atomic_write_json(AI_SESSION_NOTIFY_FILE, cache)
    except Exception as exc:
        logger.debug(f"AI transition notification update failed: {exc}")


def load_ai_monitor_metrics() -> Dict[str, Any]:
    """Load persisted AI focus metrics."""
    default_metrics = {
        "focus_attempts": 0,
        "focus_success": 0,
        "focus_fail": 0,
        "focus_success_rate": 0.0,
        "last_focus": {},
        "review_pending_sessions": 0,
        "output_ready_sessions": 0,
        "stage_tool_running_sessions": 0,
        "stage_streaming_sessions": 0,
        "stage_waiting_sessions": 0,
        "stage_from_native": 0,
        "stage_from_process": 0,
        "stage_from_review": 0,
        "stale_source_sessions": 0,
    }
    if not AI_MONITOR_METRICS_FILE.exists():
        return default_metrics
    try:
        with open(AI_MONITOR_METRICS_FILE, "r") as f:
            data = json.load(f)
            attempts = int(data.get("focus_attempts", 0) or 0)
            success = int(data.get("focus_success", 0) or 0)
            fail = int(data.get("focus_fail", 0) or 0)
            rate = (success / attempts) if attempts > 0 else 0.0
            return {
                "focus_attempts": attempts,
                "focus_success": success,
                "focus_fail": fail,
                "focus_success_rate": round(rate, 3),
                "last_focus": data.get("last_focus", {}) if isinstance(data.get("last_focus", {}), dict) else {},
                "review_pending_sessions": int(data.get("review_pending_sessions", 0) or 0),
                "output_ready_sessions": int(data.get("output_ready_sessions", 0) or 0),
                "stage_tool_running_sessions": int(data.get("stage_tool_running_sessions", 0) or 0),
                "stage_streaming_sessions": int(data.get("stage_streaming_sessions", 0) or 0),
                "stage_waiting_sessions": int(data.get("stage_waiting_sessions", 0) or 0),
                "stage_from_native": int(data.get("stage_from_native", 0) or 0),
                "stage_from_process": int(data.get("stage_from_process", 0) or 0),
                "stage_from_review": int(data.get("stage_from_review", 0) or 0),
                "stale_source_sessions": int(data.get("stale_source_sessions", 0) or 0),
            }
    except (json.JSONDecodeError, IOError, ValueError, TypeError):
        return default_metrics


def _atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    """Atomically write JSON payload to disk with per-write temp files."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Optional[Path] = None
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=str(path.parent),
        )
        temp_path = Path(tmp_name)
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f, separators=(",", ":"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, path)
        temp_path = None
    finally:
        if temp_path and temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


def load_ai_session_review_state() -> Dict[str, Any]:
    """Load finished/unseen AI session ledger."""
    default_state: Dict[str, Any] = {
        "schema_version": "1",
        "sessions": {},
        "updated_at": int(time.time()),
    }
    if not AI_SESSION_REVIEW_FILE.exists():
        return default_state
    try:
        with open(AI_SESSION_REVIEW_FILE, "r") as f:
            payload = json.load(f)
        if not isinstance(payload, dict):
            return default_state
        sessions = payload.get("sessions", {})
        if not isinstance(sessions, dict):
            sessions = {}
        # Keep only dict entries with non-empty keys to bound damage from
        # malformed runtime files.
        sessions = {
            str(key): value
            for key, value in sessions.items()
            if str(key).strip() and isinstance(value, dict)
        }
        return {
            "schema_version": str(payload.get("schema_version", "1")),
            "sessions": sessions,
            "updated_at": int(payload.get("updated_at", int(time.time())) or int(time.time())),
        }
    except (json.JSONDecodeError, IOError, ValueError, TypeError):
        return default_state


def save_ai_session_review_state(state: Dict[str, Any]) -> None:
    """Persist finished/unseen AI session ledger."""
    sessions_raw = state.get("sessions", {}) if isinstance(state, dict) else {}
    sessions = sessions_raw if isinstance(sessions_raw, dict) else {}
    payload = {
        "schema_version": "1",
        "sessions": sessions,
        "updated_at": int(time.time()),
    }
    _atomic_write_json(AI_SESSION_REVIEW_FILE, payload)


def consume_ai_session_seen_events() -> List[Dict[str, Any]]:
    """Read and clear AI session seen acknowledgements (JSONL)."""
    if not AI_SESSION_SEEN_EVENTS_FILE.exists():
        return []

    events: List[Dict[str, Any]] = []
    try:
        with open(AI_SESSION_SEEN_EVENTS_FILE, "r") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(item, dict):
                    continue
                session_key = str(item.get("session_key") or "").strip()
                if not session_key:
                    continue
                events.append({
                    "session_key": session_key,
                    "timestamp": int(item.get("timestamp", int(time.time())) or int(time.time())),
                    "finish_marker": str(item.get("finish_marker") or "").strip(),
                })
    except IOError:
        return []

    # IMPORTANT: Don't rewrite an empty file every refresh. In listen mode the
    # file path is watched by inotify; unconditional truncation creates a
    # self-triggering event loop that floods Eww updates.
    if events:
        try:
            AI_SESSION_SEEN_EVENTS_FILE.unlink(missing_ok=True)
        except TypeError:
            # Python < 3.8 compatibility fallback (defensive).
            try:
                if AI_SESSION_SEEN_EVENTS_FILE.exists():
                    AI_SESSION_SEEN_EVENTS_FILE.unlink()
            except OSError:
                pass
        except OSError:
            # Best-effort fallback if unlink fails on a busy filesystem.
            try:
                with open(AI_SESSION_SEEN_EVENTS_FILE, "w") as f:
                    f.write("")
            except IOError:
                pass

    return events


async def create_badge_watcher() -> Optional[asyncio.subprocess.Process]:
    """Create inotify watcher subprocess for badge directory and OTEL sessions file.

    Feature 107: Uses inotifywait for immediate badge file detection (<15ms latency).
    Feature 123: Also watches OTEL sessions file for AI state changes.
    Falls back to polling if inotifywait is not available.

    Returns:
        Subprocess process if inotifywait available, None otherwise.
    """
    import shutil

    # Check if inotifywait is available
    if not shutil.which(INOTIFYWAIT_CMD):
        logger.warning("Feature 107: inotifywait not found, falling back to polling")
        return None

    # Ensure badge directory exists before watching
    BADGE_STATE_DIR.mkdir(parents=True, exist_ok=True)

    # Build list of paths to watch
    watch_paths = [str(BADGE_STATE_DIR)]
    # Feature 123: Also watch OTEL sessions file for AI state changes
    # IMPORTANT: Watch the PARENT DIRECTORY, not the file itself!
    # output.py uses atomic writes (temp file + rename), which generates
    # inotify events on the directory, not the file being replaced.
    if OTEL_SESSIONS_FILE.parent.exists():
        watch_paths.append(str(OTEL_SESSIONS_FILE.parent))
    
    # Watch the active-worktree.json directory for immediate project switch detection
    if ACTIVE_WORKTREE_FILE.parent.exists():
        if str(ACTIVE_WORKTREE_FILE.parent) not in watch_paths:
            watch_paths.append(str(ACTIVE_WORKTREE_FILE.parent))
    if AI_SESSION_MRU_FILE.parent.exists():
        if str(AI_SESSION_MRU_FILE.parent) not in watch_paths:
            watch_paths.append(str(AI_SESSION_MRU_FILE.parent))
    if AI_SESSION_PIN_FILE.parent.exists():
        if str(AI_SESSION_PIN_FILE.parent) not in watch_paths:
            watch_paths.append(str(AI_SESSION_PIN_FILE.parent))
    if AI_MONITOR_METRICS_FILE.parent.exists():
        if str(AI_MONITOR_METRICS_FILE.parent) not in watch_paths:
            watch_paths.append(str(AI_MONITOR_METRICS_FILE.parent))
    if AI_SESSION_REVIEW_FILE.parent.exists():
        if str(AI_SESSION_REVIEW_FILE.parent) not in watch_paths:
            watch_paths.append(str(AI_SESSION_REVIEW_FILE.parent))
    if REMOTE_OTEL_SINK_FILE.parent.exists():
        if str(REMOTE_OTEL_SINK_FILE.parent) not in watch_paths:
            watch_paths.append(str(REMOTE_OTEL_SINK_FILE.parent))

    try:
        # inotifywait in monitor mode (-m) outputs events as they happen
        # -e create,modify,delete watches for file changes
        # -q quiet mode (no startup message)
        # --format outputs watched path, event type, and filename
        # Feature 135: %w included to distinguish badge dir events from XDG_RUNTIME_DIR events
        process = await asyncio.create_subprocess_exec(
            INOTIFYWAIT_CMD,
            "-m",           # Monitor mode (continuous)
            "-q",           # Quiet (no initial watching message)
            "-e", "create,modify,delete,moved_to",
            "--format", "%w|%e|%f",  # Watched path, event type, filename (pipe-delimited)
            *watch_paths,   # Watch badge dir and OTEL sessions parent dir
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        logger.info(f"Feature 107/123: Started inotify watcher on {watch_paths} (pid={process.pid})")
        return process
    except Exception as e:
        logger.warning(f"Feature 107: Failed to start inotify watcher: {e}")
        return None


async def read_inotify_events(
    process: asyncio.subprocess.Process,
    on_badge_change: asyncio.Event,
) -> None:
    """Read inotify events from subprocess and signal badge changes.

    Feature 107: Runs as background task, sets event when badge files change.
    Feature 135: Filter events from XDG_RUNTIME_DIR to only OTEL sessions file.

    Args:
        process: inotifywait subprocess
        on_badge_change: Event to set when badge file changes detected
    """
    if process.stdout is None:
        return

    # Get paths for filtering
    otel_filename = OTEL_SESSIONS_FILE.name  # "otel-ai-sessions.json"
    otel_tmp_filename = otel_filename.replace(".json", ".tmp")  # "otel-ai-sessions.tmp"
    active_worktree_filename = ACTIVE_WORKTREE_FILE.name
    active_worktree_tmp_filename = active_worktree_filename.replace(".json", ".tmp")
    mru_filename = AI_SESSION_MRU_FILE.name
    mru_tmp_filename = mru_filename + ".tmp"
    pin_filename = AI_SESSION_PIN_FILE.name
    pin_tmp_filename = pin_filename + ".tmp"
    metrics_filename = AI_MONITOR_METRICS_FILE.name
    metrics_tmp_filename = metrics_filename + ".tmp"
    review_filename = AI_SESSION_REVIEW_FILE.name
    review_tmp_filename = review_filename + ".tmp"
    seen_events_filename = AI_SESSION_SEEN_EVENTS_FILE.name
    seen_events_tmp_filename = seen_events_filename + ".tmp"
    remote_otel_sink_filename = REMOTE_OTEL_SINK_FILE.name
    remote_otel_sink_tmp_filename = remote_otel_sink_filename + ".tmp"
    badge_dir_path = str(BADGE_STATE_DIR)

    try:
        while True:
            line = await process.stdout.readline()
            if not line:
                # EOF - process terminated
                logger.warning("Feature 107: inotifywait process terminated")
                break

            # Parse event line: "watched_path|EVENT_TYPE|filename"
            event_line = line.decode().strip()
            if not event_line:
                continue

            # Split into watched path, event type, and filename
            parts = event_line.split("|")
            if len(parts) < 3:
                continue

            watched_path, event_type, filename = parts[0], parts[1], parts[2]

            # Feature 135: Filter based on watched path
            # Events from badge dir are always relevant
            # Events from XDG_RUNTIME_DIR (OTEL sessions parent) must match specific files
            is_badge_dir = watched_path.rstrip("/") == badge_dir_path.rstrip("/")
            is_otel_file = filename in (otel_filename, otel_tmp_filename)
            is_active_worktree_file = filename in (active_worktree_filename, active_worktree_tmp_filename)
            is_mru_file = filename in (mru_filename, mru_tmp_filename)
            is_pin_file = filename in (pin_filename, pin_tmp_filename)
            is_metrics_file = filename in (metrics_filename, metrics_tmp_filename)
            is_review_file = filename in (review_filename, review_tmp_filename)
            is_seen_events_file = filename in (seen_events_filename, seen_events_tmp_filename)
            is_remote_otel_sink_file = filename in (remote_otel_sink_filename, remote_otel_sink_tmp_filename)

            if is_badge_dir or is_otel_file or is_active_worktree_file or is_mru_file or is_pin_file or is_metrics_file or is_review_file or is_seen_events_file or is_remote_otel_sink_file:
                logger.debug(f"Feature 107/135: inotify event: {watched_path} {event_type} {filename}")
                on_badge_change.set()
            # Else: ignore unrelated files in XDG_RUNTIME_DIR (pulse, dbus, etc.)

    except asyncio.CancelledError:
        logger.debug("Feature 107: inotify reader cancelled")
        raise
    except Exception as e:
        logger.warning(f"Feature 107: Error reading inotify events: {e}")


# Icon resolution - loads from application-registry.json and pwa-registry.json
# Uses XDG icon theme lookup for icon names (like "firefox" -> /usr/share/icons/.../firefox.png)
_icon_registry: Optional[Dict[str, str]] = None
_icon_cache: Dict[str, str] = {}
APP_REGISTRY_PATH = Path.home() / ".config/i3/application-registry.json"
PWA_REGISTRY_PATH = Path.home() / ".config/i3/pwa-registry.json"

# Icon search directories for manual fallback
ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
ICON_EXTENSIONS = (".svg", ".png", ".xpm")

# Try to import XDG icon theme lookup
try:
    from xdg.IconTheme import getIconPath
except ImportError:
    getIconPath = None


# Service Registry for Health Monitoring (Feature 088)
# Defines all monitored systemd services categorized by functional role
SERVICE_REGISTRY = {
    "core": [
        {
            # Feature 117: Converted to user service (no longer socket-activated)
            "name": "i3-project-daemon",
            "display_name": "i3 Project Daemon",
            "is_user_service": True,
            "socket_activated": False,
            "socket_name": None,
            "conditional": False,
            "description": "Window management and project context daemon",
        },
        {
            "name": "workspace-preview-daemon",
            "display_name": "Workspace Preview Daemon",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace preview data provider for Eww workspace bar",
        },
        {
            "name": "sway-tree-monitor",
            "display_name": "Sway Tree Monitor",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Real-time Sway tree diff monitoring daemon",
        },
    ],
    "ui": [
        {
            "name": "eww-top-bar",
            "display_name": "Eww Top Bar",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "System metrics and status bar",
        },
        {
            "name": "eww-workspace-bar",
            "display_name": "Eww Workspace Bar",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace navigation and project preview bar",
        },
        {
            "name": "eww-monitoring-panel",
            "display_name": "Eww Monitoring Panel",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Window/project/health monitoring panel",
        },
        {
            "name": "eww-quick-panel",
            "display_name": "Eww Quick Panel",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Quick settings panel",
        },
        {
            "name": "swaync",
            "display_name": "SwayNC",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Notification center",
        },
        {
            "name": "sov",
            "display_name": "Sway Overview (sov)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Workspace overview visualization",
        },
        {
            "name": "elephant",
            "display_name": "Elephant Launcher",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Application launcher (Walker backend)",
        },
    ],
    # T039: Removed i3wsr (legacy service - not installed/used)
    "system": [
        {
            "name": "sway-config-manager",
            "display_name": "Sway Config Manager",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Hot-reloadable Sway configuration manager",
        },
        {
            # Feature 117: Audio services for bare metal machines
            "name": "pipewire",
            "display_name": "PipeWire",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "Audio/video server daemon",
        },
        {
            "name": "wireplumber",
            "display_name": "WirePlumber",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": False,
            "description": "PipeWire session manager",
        },
    ],
    "optional": [
        {
            "name": "wayvnc@HEADLESS-1",
            "display_name": "WayVNC (Display 1)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple", "local+1vnc", "local+2vnc"],
            "description": "VNC server for virtual display 1",
        },
        {
            "name": "wayvnc@HEADLESS-2",
            "display_name": "WayVNC (Display 2)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["dual", "triple", "local+2vnc"],
            "description": "VNC server for virtual display 2",
        },
        {
            "name": "wayvnc@HEADLESS-3",
            "display_name": "WayVNC (Display 3)",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["triple"],
            "description": "VNC server for virtual display 3 (Hetzner only)",
        },
        {
            "name": "tailscale-rtp-default-sink",
            "display_name": "Tailscale RTP Audio Sink",
            "is_user_service": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple"],
            "description": "Set PipeWire default sink to Tailscale RTP (headless only)",
        },
    ],
}


# =============================================================================
# Feature 092: Event Logging - Data Models
# =============================================================================

# Event type literals for Sway IPC events
EventType = Literal[
    "window::new",
    "window::close",
    "window::focus",
    "window::move",
    "window::floating",
    "window::fullscreen_mode",
    "window::title",
    "window::mark",
    "window::urgent",
    "workspace::focus",
    "workspace::init",
    "workspace::empty",
    "workspace::move",
    "workspace::rename",
    "workspace::urgent",
    "workspace::reload",
    "output::unspecified",
    "binding::run",
    "mode::change",
    "shutdown::exit",
    "tick::manual",
]


class SwayEventPayload(BaseModel):
    """
    Raw Sway IPC event payload (varies by event type).

    Common fields:
    - container: Window/workspace/output container data
    - change: Type of change that occurred
    - current: Current state (for workspace/output focus events)
    - old: Previous state (for workspace/output focus events)
    """
    # Window events
    container: Optional[Dict[str, Any]] = None

    # Workspace events
    current: Optional[Dict[str, Any]] = None
    old: Optional[Dict[str, Any]] = None

    # Binding events
    binding: Optional[Dict[str, Any]] = None

    # Mode events
    change: Optional[str] = None
    pango_markup: Optional[bool] = None

    # Raw event data (catch-all)
    raw: Dict[str, Any] = Field(default_factory=dict)


class EventEnrichment(BaseModel):
    """
    i3pm daemon metadata enrichment for window-related events.

    Only populated for window::* events when i3pm daemon is available.
    """
    # Window identification
    window_id: Optional[int] = None
    pid: Optional[int] = None

    # App registry metadata
    app_name: Optional[str] = None  # From I3PM_APP_NAME or app registry
    app_id: Optional[str] = None    # Full app ID with instance suffix
    icon_path: Optional[str] = None  # Resolved icon file path

    # Project association
    project_name: Optional[str] = None  # i3pm project name
    scope: Optional[Literal["scoped", "global"]] = None

    # Workspace context
    workspace_number: Optional[int] = None
    workspace_name: Optional[str] = None
    output_name: Optional[str] = None

    # PWA detection
    is_pwa: bool = False  # True if workspace >= 50

    # Enrichment metadata
    daemon_available: bool = True  # False if i3pm daemon unreachable
    enrichment_latency_ms: Optional[float] = None  # Time to query daemon


class Event(BaseModel):
    """
    Complete event record with timestamp, type, payload, and enrichment.

    This is the primary data structure stored in the event buffer and
    sent to the Eww UI for display.
    """
    # Core event data
    timestamp: float  # Unix timestamp (seconds since epoch)
    timestamp_friendly: str  # Human-friendly relative time ("5s ago")
    event_type: EventType  # Sway event type (e.g., "window::new")
    change_type: Optional[str] = None  # Sub-type for some events

    # Event payload
    payload: SwayEventPayload

    # i3pm enrichment (optional)
    enrichment: Optional[EventEnrichment] = None

    # Display metadata
    icon: str  # Nerd Font icon for event type
    color: str  # Catppuccin Mocha color hex code

    # Feature 102: Event source indicator (T017)
    source: Literal["sway", "i3pm"] = "sway"  # Event source (sway IPC or i3pm internal)

    # Categorization - Feature 102: Added i3pm categories (T017)
    category: Literal["window", "workspace", "output", "binding", "mode", "system",
                      "project", "visibility", "scratchpad", "launch", "state", "command", "trace"]

    # Feature 102 (T028): Trace cross-reference
    trace_id: Optional[str] = None  # Active trace ID if event is part of a trace
    correlation_id: Optional[str] = None  # Causality chain identifier
    causality_depth: int = 0  # Nesting depth in causality chain

    # Feature 102 T066-T067: Cross-reference validity indicators
    trace_evicted: bool = False  # True if trace_id references a trace no longer in buffer
    parent_missing: bool = False  # True if correlation_id set but parent event not in current view

    # Feature 102 T052: Event performance metrics
    processing_duration_ms: float = 0.0  # Event handler processing time (daemon events only)

    # Filtering support
    searchable_text: str  # Concatenated text for search


class EventsViewData(BaseModel):
    """
    Complete response for events view mode.

    Sent from Python backend to Eww frontend via deflisten streaming.
    """
    # Response status
    status: Literal["ok", "error"]
    error: Optional[str] = None

    # Event data
    events: List[Event] = Field(default_factory=list)

    # Feature 102 T053: Events sorted by duration (slowest first) for sort-by-duration UI
    events_by_duration: List[Event] = Field(default_factory=list)

    # Metadata
    event_count: int = 0  # Total events in buffer
    filtered_count: Optional[int] = None  # Count after filtering
    oldest_timestamp: Optional[float] = None
    newest_timestamp: Optional[float] = None

    # Feature 102 T054: Aggregate performance statistics
    avg_duration_ms: float = 0.0  # Average processing time across events
    slow_event_count: int = 0  # Events with duration > 100ms
    critical_event_count: int = 0  # Events with duration > 500ms

    # Feature 102 T064-T065: Burst handling statistics (from daemon EventBuffer)
    burst_active: bool = False  # Currently in burst mode (>100 events/sec)
    burst_collapsed_current: int = 0  # Events collapsed in current burst
    total_bursts: int = 0  # Total burst periods detected
    total_collapsed: int = 0  # Total events collapsed across all bursts

    # System state
    daemon_available: bool = True  # i3pm daemon reachability
    ipc_connected: bool = True  # Sway IPC connection status

    # Timestamps
    timestamp: float  # Query execution time
    timestamp_friendly: str  # Human-friendly time


class EventBuffer:
    """
    Circular buffer for event storage with automatic FIFO eviction.

    Uses Python deque with maxlen for O(1) append and automatic eviction.
    Thread-safe for single-writer scenarios (event loop).
    """

    def __init__(self, max_size: int = 500):
        """
        Initialize event buffer.

        Args:
            max_size: Maximum number of events to retain (default 500)
        """
        self._buffer: deque[Event] = deque(maxlen=max_size)
        self._max_size = max_size

    def append(self, event: Event) -> None:
        """
        Add event to buffer (automatically evicts oldest if full).

        Args:
            event: Event to append
        """
        self._buffer.append(event)

    def get_all(self, refresh_timestamps: bool = False) -> List[Event]:
        """
        Get all buffered events (oldest first, newest last).

        Args:
            refresh_timestamps: If True, recalculate timestamp_friendly for all events

        Returns:
            List of events in chronological order
        """
        events = list(self._buffer)

        if refresh_timestamps:
            # Refresh timestamp_friendly for all events based on current time
            for event in events:
                event.timestamp_friendly = format_friendly_timestamp(event.timestamp)

        return events

    def clear(self) -> None:
        """Clear all events from buffer."""
        self._buffer.clear()

    def size(self) -> int:
        """Get current buffer size."""
        return len(self._buffer)

    @property
    def max_size(self) -> int:
        """Get maximum buffer capacity."""
        return self._max_size

    def get_performance_stats(self) -> Dict[str, Any]:
        """Get aggregate performance statistics for events in buffer.

        Feature 102 T054: Calculate average duration and count slow events.

        Returns:
            Dict with avg_duration_ms, slow_event_count, critical_event_count
        """
        events = list(self._buffer)
        if not events:
            return {
                "avg_duration_ms": 0.0,
                "slow_event_count": 0,
                "critical_event_count": 0,
            }

        # Calculate average duration (only for events with non-zero duration)
        durations = [e.processing_duration_ms for e in events if e.processing_duration_ms > 0]
        avg_duration = sum(durations) / len(durations) if durations else 0.0

        # Count slow events (>100ms) and critical events (>500ms)
        slow_count = sum(1 for e in events if e.processing_duration_ms > 100)
        critical_count = sum(1 for e in events if e.processing_duration_ms > 500)

        return {
            "avg_duration_ms": round(avg_duration, 2),
            "slow_event_count": slow_count,
            "critical_event_count": critical_count,
        }


# Event icon mapping with Nerd Font icons and Catppuccin Mocha colors
# Feature 102: Added i3pm internal events with distinct source indicator
EVENT_ICONS = {
    # Window events (Sway)
    "window::new": {"icon": "󰖲", "color": "#89b4fa", "source": "sway"},  # Blue
    "window::close": {"icon": "󰖶", "color": "#f38ba8", "source": "sway"},  # Red
    "window::focus": {"icon": "󰋁", "color": "#74c7ec", "source": "sway"},  # Sapphire
    "window::blur": {"icon": "󰋀", "color": "#6c7086", "source": "sway"},  # Overlay - Feature 102
    "window::move": {"icon": "󰁔", "color": "#fab387", "source": "sway"},  # Peach
    "window::floating": {"icon": "󰉈", "color": "#f9e2af", "source": "sway"},  # Yellow
    "window::fullscreen_mode": {"icon": "󰊓", "color": "#cba6f7", "source": "sway"},  # Mauve
    "window::title": {"icon": "󰓹", "color": "#a6adc8", "source": "sway"},  # Subtext
    "window::mark": {"icon": "󰃀", "color": "#94e2d5", "source": "sway"},  # Teal
    "window::urgent": {"icon": "󰀪", "color": "#f38ba8", "source": "sway"},  # Red

    # Workspace events (Sway)
    "workspace::focus": {"icon": "󱂬", "color": "#94e2d5", "source": "sway"},  # Teal
    "workspace::init": {"icon": "󰐭", "color": "#a6e3a1", "source": "sway"},  # Green
    "workspace::empty": {"icon": "󰭀", "color": "#6c7086", "source": "sway"},  # Overlay
    "workspace::move": {"icon": "󰁔", "color": "#fab387", "source": "sway"},  # Peach
    "workspace::rename": {"icon": "󰑕", "color": "#89dceb", "source": "sway"},  # Sky
    "workspace::urgent": {"icon": "󰀪", "color": "#f38ba8", "source": "sway"},  # Red
    "workspace::reload": {"icon": "󰑓", "color": "#a6e3a1", "source": "sway"},  # Green

    # Output events (Sway - enhanced with Feature 102)
    "output::unspecified": {"icon": "󰍹", "color": "#cba6f7", "source": "sway"},  # Mauve
    "output::connected": {"icon": "󰍹", "color": "#a6e3a1", "source": "sway"},  # Green - Feature 102
    "output::disconnected": {"icon": "󰍺", "color": "#f38ba8", "source": "sway"},  # Red - Feature 102
    "output::profile_changed": {"icon": "󰄫", "color": "#89dceb", "source": "sway"},  # Sky - Feature 102

    # Binding/mode events (Sway)
    "binding::run": {"icon": "󰌌", "color": "#f9e2af", "source": "sway"},  # Yellow
    "mode::change": {"icon": "󰘧", "color": "#89dceb", "source": "sway"},  # Sky

    # System events (Sway)
    "shutdown::exit": {"icon": "󰚌", "color": "#f38ba8", "source": "sway"},  # Red
    "tick::manual": {"icon": "󰥔", "color": "#6c7086", "source": "sway"},  # Overlay

    # =========================================================================
    # Feature 102: i3pm Internal Events
    # These events are generated by the i3pm daemon, not raw Sway IPC
    # All use Peach (#fab387) or Mauve (#cba6f7) for i3pm distinction
    # =========================================================================

    # Project events (i3pm)
    "project::switch": {"icon": "󰒍", "color": "#fab387", "source": "i3pm"},  # Peach - project switch
    "project::clear": {"icon": "󰆴", "color": "#fab387", "source": "i3pm"},  # Peach - clear project

    # Visibility events (i3pm)
    "visibility::hidden": {"icon": "󰈈", "color": "#cba6f7", "source": "i3pm"},  # Mauve - window hidden
    "visibility::shown": {"icon": "󰈉", "color": "#a6e3a1", "source": "i3pm"},  # Green - window shown
    "scratchpad::move": {"icon": "󰘓", "color": "#cba6f7", "source": "i3pm"},  # Mauve - scratchpad move

    # Command events (i3pm - Feature 102)
    "command::queued": {"icon": "󰒲", "color": "#89dceb", "source": "i3pm"},  # Sky - queued
    "command::executed": {"icon": "󰑮", "color": "#a6e3a1", "source": "i3pm"},  # Green - executed
    "command::result": {"icon": "󰄬", "color": "#94e2d5", "source": "i3pm"},  # Teal - result
    "command::batch": {"icon": "󱁤", "color": "#f9e2af", "source": "i3pm"},  # Yellow - batch

    # Launch events (i3pm)
    "launch::intent": {"icon": "󰐊", "color": "#89b4fa", "source": "i3pm"},  # Blue - intent
    "launch::notification": {"icon": "󰗗", "color": "#89dceb", "source": "i3pm"},  # Sky - notification
    "launch::env_injected": {"icon": "󰆼", "color": "#94e2d5", "source": "i3pm"},  # Teal - env injected
    "launch::correlated": {"icon": "󰄾", "color": "#a6e3a1", "source": "i3pm"},  # Green - correlated

    # State events (i3pm)
    "state::saved": {"icon": "󰆓", "color": "#a6e3a1", "source": "i3pm"},  # Green - saved
    "state::loaded": {"icon": "󰈔", "color": "#89b4fa", "source": "i3pm"},  # Blue - loaded
    "state::conflict": {"icon": "󰆘", "color": "#f38ba8", "source": "i3pm"},  # Red - conflict

    # Mark events (i3pm)
    "mark::added": {"icon": "󰃀", "color": "#94e2d5", "source": "i3pm"},  # Teal - added
    "mark::removed": {"icon": "󰃁", "color": "#6c7086", "source": "i3pm"},  # Overlay - removed

    # Environment events (i3pm)
    "env::detected": {"icon": "󰆼", "color": "#89dceb", "source": "i3pm"},  # Sky - detected
    "env::changed": {"icon": "󰆻", "color": "#f9e2af", "source": "i3pm"},  # Yellow - changed

    # Trace events (i3pm)
    "trace::start": {"icon": "󰙨", "color": "#a6e3a1", "source": "i3pm"},  # Green - start
    "trace::stop": {"icon": "󰙧", "color": "#f38ba8", "source": "i3pm"},  # Red - stop
    "trace::snapshot": {"icon": "󰄄", "color": "#89dceb", "source": "i3pm"},  # Sky - snapshot
}


def _resolve_icon_name(icon_name: str) -> str:
    """Resolve icon name to full file path using XDG lookup."""
    if not icon_name:
        return ""

    # Check cache first
    cache_key = icon_name.lower()
    if cache_key in _icon_cache:
        return _icon_cache[cache_key]

    # If it's already an absolute path, verify it exists
    candidate = Path(icon_name)
    if candidate.is_absolute() and candidate.exists():
        _icon_cache[cache_key] = str(candidate)
        return str(candidate)

    # Try XDG icon theme lookup (resolves names like "firefox")
    if getIconPath:
        themed = getIconPath(icon_name, 48)
        if themed:
            resolved = str(Path(themed))
            _icon_cache[cache_key] = resolved
            return resolved

    # Manual search through icon directories as fallback
    for directory in ICON_SEARCH_DIRS:
        if not directory.exists():
            continue
        for ext in ICON_EXTENSIONS:
            probe = directory / f"{icon_name}{ext}"
            if probe.exists():
                resolved = str(probe)
                _icon_cache[cache_key] = resolved
                return resolved

    # Not found - cache empty string
    _icon_cache[cache_key] = ""
    return ""


def get_icon_registry() -> Dict[str, str]:
    """Get or load the icon registry mapping app names to resolved icon paths."""
    global _icon_registry
    if _icon_registry is not None:
        return _icon_registry

    _icon_registry = {}

    # Load from application-registry.json
    if APP_REGISTRY_PATH.exists():
        try:
            with open(APP_REGISTRY_PATH) as f:
                data = json.load(f)
                for app in data.get("applications", []):
                    name = app.get("name", "").lower()
                    icon = app.get("icon", "")
                    if name and icon:
                        # Resolve icon name to full path
                        _icon_registry[name] = _resolve_icon_name(icon)
        except Exception:
            pass

    # Load from pwa-registry.json
    if PWA_REGISTRY_PATH.exists():
        try:
            with open(PWA_REGISTRY_PATH) as f:
                data = json.load(f)
                for pwa in data.get("pwas", []):
                    # PWAs use ULID-based app_id (e.g., "WebApp-01JCYF8Z2M")
                    ulid = pwa.get("ulid", "")
                    icon = pwa.get("icon", "")
                    if ulid and icon:
                        _icon_registry[f"webapp-{ulid}".lower()] = _resolve_icon_name(icon)
        except Exception:
            pass

    return _icon_registry


def resolve_icon(app_id: str, window_class: str = "") -> str:
    """Resolve icon path for an app_id or window class."""
    registry = get_icon_registry()

    # Try exact app_id match first
    if app_id:
        app_id_lower = app_id.lower()
        if app_id_lower in registry:
            return registry[app_id_lower]

        # Extract base app name (e.g., "terminal-nixos-123456" -> "terminal")
        base_name = app_id.split("-")[0].lower() if "-" in app_id else app_id_lower
        if base_name in registry:
            return registry[base_name]

    # Try window_class as fallback
    if window_class:
        class_lower = window_class.lower()
        if class_lower in registry:
            return registry[class_lower]

    return ""

# Configure logging (stderr only - stdout is for JSON)
_log_level_name = os.environ.get("I3PM_MONITORING_DATA_LOG_LEVEL", "WARNING").upper()
_log_level = getattr(logging, _log_level_name, logging.WARNING)
logging.basicConfig(
    level=_log_level,
    format="[%(asctime)s] %(levelname)s: %(message)s",
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

# Shutdown flag for graceful exit
shutdown_requested = False


def handle_shutdown_signal(signum, frame):
    """Handle SIGTERM/SIGINT for graceful shutdown."""
    global shutdown_requested
    logger.info(f"Received signal {signum}, initiating graceful shutdown")
    shutdown_requested = True


def setup_signal_handlers():
    """Configure signal handlers for graceful shutdown."""
    signal.signal(signal.SIGTERM, handle_shutdown_signal)
    signal.signal(signal.SIGINT, handle_shutdown_signal)
    # Handle broken pipe (Eww closes while we're writing)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def get_window_state_classes(window: Dict[str, Any]) -> str:
    """
    Generate space-separated CSS class string for window states.

    This moves conditional class logic from Yuck to Python for:
    - Better testability (Python unit tests)
    - Cleaner Yuck code (no nested ternaries)
    - No Nix escaping issues with empty strings
    - Separation of concerns (data transformation in backend)

    Args:
        window: Window data from daemon (Sway IPC format)

    Returns:
        Space-separated string of CSS classes (e.g., "window-floating window-hidden")
    """
    classes = []

    if window.get("floating", False):
        classes.append("window-floating")
    if window.get("hidden", False):
        classes.append("window-hidden")
    if window.get("focused", False):
        classes.append("window-focused")
    # UX Enhancement: Activity Pulse Glow for urgent windows
    if window.get("urgent", False):
        classes.append("window-urgent")

    return " ".join(classes)


def escape_pango(text: str) -> str:
    """
    Escape special characters for Pango markup.

    Args:
        text: Raw text string

    Returns:
        Pango-safe string with escaped special chars
    """
    return (text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))


def colorize_json_value(value: Any, indent_level: int = 1) -> str:
    """
    Recursively colorize a JSON value with Pango markup.

    Color scheme (Catppuccin Mocha):
    - Keys: Blue (#89b4fa)
    - Strings: Green (#a6e3a1)
    - Numbers: Peach (#fab387)
    - Booleans: Yellow (#f9e2af)
    - Null: Gray (#6c7086)
    - Punctuation: Subtext (#a6adc8)

    Args:
        value: Python value to colorize (dict, list, str, int, bool, None)
        indent_level: Current indentation level

    Returns:
        Pango markup string
    """
    indent = "  " * indent_level

    if isinstance(value, dict):
        if not value:
            return '<span foreground="#a6adc8">{}</span>'

        lines = ['<span foreground="#a6adc8">{</span>']
        items = list(value.items())
        for i, (key, val) in enumerate(items):
            key_colored = f'<span foreground="#89b4fa">"{escape_pango(key)}"</span>'
            value_colored = colorize_json_value(val, indent_level + 1)
            comma = '<span foreground="#a6adc8">,</span>' if i < len(items) - 1 else ''
            lines.append(f'{indent}{key_colored}<span foreground="#a6adc8">: </span>{value_colored}{comma}')

        lines.append(("  " * (indent_level - 1)) + '<span foreground="#a6adc8">}</span>')
        return '\n'.join(lines)

    elif isinstance(value, list):
        if not value:
            return '<span foreground="#a6adc8">[]</span>'

        lines = ['<span foreground="#a6adc8">[</span>']
        for i, item in enumerate(value):
            value_colored = colorize_json_value(item, indent_level + 1)
            comma = '<span foreground="#a6adc8">,</span>' if i < len(value) - 1 else ''
            lines.append(f'{indent}{value_colored}{comma}')

        lines.append(("  " * (indent_level - 1)) + '<span foreground="#a6adc8">]</span>')
        return '\n'.join(lines)

    elif isinstance(value, str):
        return f'<span foreground="#a6e3a1">"{escape_pango(value)}"</span>'

    elif isinstance(value, bool):
        return f'<span foreground="#f9e2af">{str(value).lower()}</span>'

    elif value is None:
        return '<span foreground="#6c7086">null</span>'

    elif isinstance(value, (int, float)):
        return f'<span foreground="#fab387">{value}</span>'

    else:
        # Fallback for unknown types
        return f'<span foreground="#cdd6f4">{escape_pango(str(value))}</span>'


def colorize_json_pango(data: Dict[str, Any]) -> str:
    """
    Generate Pango markup for syntax-highlighted JSON representation.

    Uses Catppuccin Mocha color scheme for consistent theming with the panel.

    Args:
        data: Dictionary to colorize as JSON

    Returns:
        Pango markup string with syntax highlighting
    """
    return colorize_json_value(data, indent_level=1)


# Feature 136: State priority for sorting multiple AI badges per window
# Higher priority sessions appear first in the badge list
_OTEL_STATE_PRIORITY = {
    "attention": 4,  # Highest - needs user action
    "working": 3,
    "completed": 2,
    "idle": 1,
}
_AI_STAGE_LABELS = {
    "starting": "Starting",
    "thinking": "Thinking",
    "tool_running": "Tool",
    "streaming": "Streaming",
    "waiting_input": "Waiting",
    "attention": "Attention",
    "output_ready": "Ready",
    "idle": "Idle",
}
_AI_STAGE_RANKS = {
    "attention": 7,
    "waiting_input": 6,
    "tool_running": 5,
    "streaming": 4,
    "thinking": 3,
    "starting": 2,
    "output_ready": 1,
    "idle": 0,
}
_AI_STAGE_VISUAL_STATES = {
    "starting": "working",
    "thinking": "working",
    "tool_running": "working",
    "streaming": "working",
    "waiting_input": "attention",
    "attention": "attention",
    "output_ready": "completed",
    "idle": "idle",
}
_AI_STAGE_GLYPHS = {
    "starting": "◔",
    "thinking": "⋯",
    "tool_running": "⛭",
    "streaming": "⇢",
    "waiting_input": "✋",
    "attention": "!",
    "output_ready": "✓",
    "idle": "·",
}
_OTEL_VISIBLE_BADGE_STATES = {"working", "attention", "completed", "idle"}
_OTEL_ACTIVE_SESSION_STATES = {"working", "attention", "completed", "idle"}
_AI_SESSION_STALE_THRESHOLD_SECONDS = 15 * 60
_AI_SESSION_REVIEW_TTL_SECONDS = 24 * 60 * 60
_AI_SESSION_REVIEW_MAX_ENTRIES = 512
# Grace before treating a disappeared active session as finished-unseen.
# Keep short so users quickly see completed work even when terminal traces end abruptly.
_AI_SESSION_REVIEW_DISAPPEAR_GRACE_SECONDS = 8

_OTEL_TOOL_LABELS = {
    "claude-code": "Claude Code",
    "codex": "Codex CLI",
    "gemini": "Gemini CLI",
}

_AI_TRACKABLE_TOOLS = {"claude-code", "codex", "gemini"}


def _parse_timestamp_to_epoch(timestamp: str) -> Optional[float]:
    """Best-effort parse for OTEL ISO timestamps."""
    raw = str(timestamp or "").strip()
    if not raw:
        return None
    try:
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        return datetime.fromisoformat(raw).timestamp()
    except ValueError:
        return None


def _identity_confidence_level(value: str) -> str:
    """Map raw identity confidence values into coarse UX levels."""
    raw = str(value or "").strip().lower()
    if raw in {"native", "high"}:
        return "high"
    if raw in {"contextual", "medium", "derived"}:
        return "medium"
    return "low"


def _normalize_user_action_reason(value: Any) -> str:
    raw = str(value or "").strip().lower()
    if raw in {"permission", "auth", "rate_limit", "max_tokens", "error"}:
        return raw
    return ""


def _session_status_detail(session: Dict[str, Any]) -> str:
    detail = str(session.get("stage_detail") or "").strip()
    if detail:
        if bool(session.get("remote_source_stale", False)) and "source stale" not in detail.lower():
            return f"{detail} · Source stale"
        return detail
    reason = str(session.get("status_reason") or "").strip()
    if not reason:
        return "Source stale" if bool(session.get("remote_source_stale", False)) else ""
    lowered = reason.lower()
    if lowered == "process_detected":
        detail = "Process detected"
    elif lowered == "process_keepalive":
        detail = "Still active"
    elif lowered == "trace_correlated":
        detail = "Trace connected"
    elif lowered == "quiet_period_expired":
        detail = "Response finished"
    elif lowered == "completed_timeout":
        detail = "Session idle"
    elif lowered == "finished_unseen_retained":
        detail = "Unread output retained"
    elif lowered == "metrics_heartbeat_created":
        detail = "Heartbeat detected"
    elif lowered == "remote_source_stale":
        detail = "Source stale"
    elif lowered.startswith("event:"):
        event_name = lowered.split("event:", 1)[1]
        if "permission" in event_name:
            detail = "Waiting on permission"
        elif "tool_start" in event_name:
            detail = "Tool started"
        elif "tool_complete" in event_name or "tool_result" in event_name:
            detail = "Tool completed"
        elif "stream" in event_name:
            detail = "Streaming response"
        elif "api_request" in event_name:
            detail = "Model request active"
        elif "user_prompt" in event_name:
            detail = "Prompt sent"
        else:
            detail = reason.replace("_", " ").strip().capitalize()
    else:
        detail = reason.replace("_", " ").strip().capitalize()
    if bool(session.get("remote_source_stale", False)) and "source stale" not in detail.lower():
        return f"{detail} · Source stale"
    return detail


def _format_activity_age(seconds: int) -> str:
    age = max(0, int(seconds))
    if age < 60:
        return f"{age}s ago"
    if age < 3600:
        return f"{age // 60}m ago"
    if age < 86400:
        return f"{age // 3600}h ago"
    return f"{age // 86400}d ago"


def _normalize_stage_fields(session: Dict[str, Any], *, now_epoch: Optional[float] = None) -> Dict[str, Any]:
    """Return canonical stage fields from exporter payloads or local fallback derivation."""
    now_epoch = time.time() if now_epoch is None else now_epoch
    state = str(session.get("otel_state") or session.get("state") or "idle").strip().lower()
    review_pending = bool(session.get("review_pending", False) or session.get("output_unseen", False))
    pending_tools = int(session.get("pending_tools", 0) or 0)
    is_streaming = bool(session.get("is_streaming", False))
    status_reason = str(session.get("status_reason") or "").strip().lower()
    updated_epoch = _parse_timestamp_to_epoch(str(session.get("updated_at") or "")) or now_epoch
    activity_age_seconds = max(0, int(now_epoch - updated_epoch))
    if bool(session.get("remote_source_stale", False)):
        activity_age_seconds = max(
            activity_age_seconds,
            int(session.get("remote_source_age_seconds", 0) or 0),
        )
    user_action_reason = _normalize_user_action_reason(session.get("user_action_reason"))
    stage = str(session.get("stage") or "").strip().lower()

    if not user_action_reason:
        if "permission" in status_reason:
            user_action_reason = "permission"
        elif "max_tokens" in status_reason:
            user_action_reason = "max_tokens"
        elif state == "attention":
            user_action_reason = "error"

    if not stage:
        if review_pending:
            stage = "output_ready"
        elif user_action_reason == "permission":
            stage = "waiting_input"
        elif user_action_reason or state == "attention":
            stage = "attention"
        elif pending_tools > 0:
            stage = "tool_running"
        elif is_streaming:
            stage = "streaming"
        elif state == "completed":
            stage = "output_ready"
        elif state == "working" and status_reason in {"process_detected", "metrics_heartbeat_created"}:
            stage = "starting"
        elif state == "working":
            stage = "thinking"
        else:
            stage = "idle"

    stage_label = str(session.get("stage_label") or _AI_STAGE_LABELS.get(stage, "Idle"))
    detail = _session_status_detail(session)
    output_ready = bool(session.get("output_ready", stage == "output_ready" or state == "completed" or review_pending))
    output_unseen = bool(session.get("output_unseen", review_pending))
    needs_user_action = bool(
        session.get("needs_user_action", stage in {"waiting_input", "attention"})
    )
    stage_class = str(session.get("stage_class") or f"stage-{stage}")
    stage_visual_state = str(session.get("stage_visual_state") or _AI_STAGE_VISUAL_STATES.get(stage, "idle"))
    stage_rank = int(session.get("stage_rank", _AI_STAGE_RANKS.get(stage, 0)) or 0)
    activity_freshness = str(session.get("activity_freshness") or "").strip().lower()
    if activity_freshness not in {"fresh", "warm", "stale"}:
        if (
            bool(session.get("remote_source_stale", False))
            or bool(session.get("stale", False))
            or activity_age_seconds > _AI_SESSION_STALE_THRESHOLD_SECONDS
        ):
            activity_freshness = "stale"
        elif activity_age_seconds > 90:
            activity_freshness = "warm"
        else:
            activity_freshness = "fresh"

    identity_source = str(session.get("identity_source") or "").strip().lower()
    if not identity_source:
        confidence = str(session.get("identity_confidence") or "").strip().lower()
        if confidence in {"native", "high"} or str(session.get("native_session_id") or "").strip():
            identity_source = "native"
        elif confidence == "pid":
            identity_source = "pid"
        elif confidence == "pane":
            identity_source = "pane"
        elif confidence == "review":
            identity_source = "review"
        else:
            identity_source = "heuristic"

    lifecycle_source = str(session.get("lifecycle_source") or "").strip().lower()
    if not lifecycle_source:
        if status_reason in {"metrics_heartbeat_created", "process_keepalive"}:
            lifecycle_source = "heartbeat"
        elif identity_source == "review":
            lifecycle_source = "review"
        elif str(session.get("trace_id") or "").strip() or str(session.get("native_session_id") or "").strip():
            lifecycle_source = "trace"
        else:
            lifecycle_source = "process"

    return {
        "stage": stage,
        "stage_label": stage_label,
        "stage_detail": detail,
        "stage_class": stage_class,
        "stage_visual_state": stage_visual_state,
        "stage_rank": stage_rank,
        "stage_glyph": str(session.get("stage_glyph") or _AI_STAGE_GLYPHS.get(stage, "·")),
        "needs_user_action": needs_user_action,
        "user_action_reason": user_action_reason,
        "output_ready": output_ready,
        "output_unseen": output_unseen,
        "activity_freshness": activity_freshness,
        "activity_age_seconds": activity_age_seconds,
        "activity_age_label": _format_activity_age(activity_age_seconds),
        "identity_source": identity_source,
        "lifecycle_source": lifecycle_source,
    }


def _session_terminal_anchor(session: Dict[str, Any]) -> str:
    """Return canonical terminal anchor key for deterministic session tracking."""
    terminal_context = session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}
    tmux_pane = str(
        session.get("tmux_pane")
        or terminal_context.get("tmux_pane")
        or ""
    ).strip()
    if tmux_pane:
        return f"pane:{tmux_pane}"

    pty = str(
        session.get("pty")
        or terminal_context.get("pty")
        or ""
    ).strip()
    if pty:
        return f"pty:{pty}"
    return ""


def _session_tracking_contract_ok(session: Dict[str, Any]) -> bool:
    """
    Enforce deterministic tracking contract for AI sessions.

    A session is eligible only when:
    - tool is one of supported AI CLIs
    - execution identity is concrete (local/ssh + connection key)
    - terminal anchor is concrete (tmux pane or pty)
    """
    tool = str(session.get("tool") or "").strip().lower()
    if tool not in _AI_TRACKABLE_TOOLS:
        return False

    identity = _resolve_session_execution_identity(session, default_mode="local")
    mode = str(identity.get("execution_mode") or "").strip()
    connection = str(identity.get("connection_key") or "").strip()
    if mode not in {"local", "ssh"}:
        return False
    if not connection or connection in {"unknown", "global"}:
        return False

    return bool(_session_terminal_anchor(session))


def _otel_badge_merge_key(session: Dict[str, Any]) -> str:
    """
    Build a stable dedupe key for badge sessions.

    OTEL monitor can emit multiple native session records for the same real
    terminal pane over time (for example, repeated `codex exec` runs). For the
    window badge UX we want one indicator per terminal context, not one per
    historical native session id.
    """
    terminal_context = session.get("terminal_context", {}) or {}
    tool = str(session.get("tool", "unknown") or "unknown")

    native_session_id = str(session.get("native_session_id") or "")
    collision_group_id = str(session.get("collision_group_id") or "")
    context_fingerprint = str(session.get("context_fingerprint") or "")
    window_id = session.get("window_id", terminal_context.get("window_id"))
    pane = str(terminal_context.get("tmux_pane") or "")
    pty = str(terminal_context.get("pty") or "")

    # Highest-priority dedupe scope: tool + concrete terminal context.
    # This keeps one badge per pane/pty even when many native session ids exist.
    if pane:
        return f"tool={tool}|pane={pane}"
    if pty:
        return f"tool={tool}|pty={pty}"
    if window_id is not None:
        return f"tool={tool}|window={window_id}"

    # If no terminal context is known, fall back to native grouping.
    if collision_group_id or native_session_id:
        native_key = (
            f"tool={tool}|group={collision_group_id}"
            if collision_group_id
            else f"tool={tool}|native={native_session_id}"
        )
        if context_fingerprint:
            return f"{native_key}|context={context_fingerprint}"
        return native_key

    session_id = str(session.get("session_id") or "")
    if session_id:
        return f"tool={tool}|session={session_id}"

    pid = session.get("pid")

    if pid is not None and window_id is not None:
        return f"tool={tool}|pid={pid}|window={window_id}"
    if pid is not None and pane:
        return f"tool={tool}|pid={pid}|pane={pane}"
    if pid is not None and pty:
        return f"tool={tool}|pid={pid}|pty={pty}"

    return f"tool={tool}|fallback={json.dumps(session, sort_keys=True, default=str)}"


def _otel_badge_score(session: Dict[str, Any]) -> tuple[int, int, int, str]:
    """
    Score which duplicate candidate is the best canonical badge.

    Preference order:
      1) native-identified records
      2) records with trace_id
      3) higher urgency state
      4) most recent updated_at (ISO string compare)
    """
    identity_confidence = str(session.get("identity_confidence") or "").strip().lower()
    is_native = int(identity_confidence == "native" or bool(session.get("native_session_id")))
    has_trace = int(bool(session.get("trace_id")))
    state_rank = _OTEL_STATE_PRIORITY.get(str(session.get("state", "idle")), 0)
    updated_at = str(session.get("updated_at") or "")
    return (is_native, has_trace, state_rank, updated_at)


def _coalesce_otel_badge_sessions(
    otel_sessions: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Collapse duplicate OTEL sessions for badge rendering."""
    if not otel_sessions:
        return []

    merged: Dict[str, Dict[str, Any]] = {}
    for session in otel_sessions:
        key = _otel_badge_merge_key(session)
        existing = merged.get(key)
        if existing is None:
            merged[key] = dict(session)
            continue

        # Keep the stronger base record.
        if _otel_badge_score(session) > _otel_badge_score(existing):
            base = dict(session)
            other = existing
        else:
            base = existing
            other = session

        # Merge fields that are useful even if only present in one variant.
        if not base.get("trace_id") and other.get("trace_id"):
            base["trace_id"] = other.get("trace_id")
        if not base.get("session_id") and other.get("session_id"):
            base["session_id"] = other.get("session_id")
        if not base.get("native_session_id") and other.get("native_session_id"):
            base["native_session_id"] = other.get("native_session_id")
        if not base.get("context_fingerprint") and other.get("context_fingerprint"):
            base["context_fingerprint"] = other.get("context_fingerprint")
        if not base.get("collision_group_id") and other.get("collision_group_id"):
            base["collision_group_id"] = other.get("collision_group_id")
        if not base.get("window_id") and other.get("window_id"):
            base["window_id"] = other.get("window_id")
        if not base.get("execution_mode") and other.get("execution_mode"):
            base["execution_mode"] = other.get("execution_mode")
        if not base.get("connection_key") and other.get("connection_key"):
            base["connection_key"] = other.get("connection_key")
        if not base.get("context_key") and other.get("context_key"):
            base["context_key"] = other.get("context_key")

        base_context = base.get("terminal_context", {}) or {}
        other_context = other.get("terminal_context", {}) or {}
        for ctx_key in (
            "window_id",
            "tmux_session",
            "tmux_window",
            "tmux_pane",
            "pty",
            "host_name",
            "execution_mode",
            "connection_key",
            "context_key",
            "remote_target",
        ):
            if not base_context.get(ctx_key) and other_context.get(ctx_key):
                base_context[ctx_key] = other_context.get(ctx_key)
        base["terminal_context"] = base_context

        base["pending_tools"] = max(
            int(base.get("pending_tools", 0) or 0),
            int(other.get("pending_tools", 0) or 0),
        )
        base["is_streaming"] = bool(base.get("is_streaming", False) or other.get("is_streaming", False))
        merged[key] = base

    return list(merged.values())


def _safe_int(value: Any, default: int = 0) -> int:
    """Best-effort integer conversion."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _normalize_execution_mode(value: Any, default: str = "local") -> str:
    """Normalize execution mode to local/ssh/global with configurable fallback."""
    mode = str(value or "").strip().lower()
    if mode in {"local", "ssh", "global"}:
        return mode
    return default


def _extract_context_key_from_marks(marks: Any) -> str:
    """Extract ctx:<context_key> mark value when present."""
    if not isinstance(marks, list):
        return ""
    for mark in marks:
        raw = str(mark or "").strip()
        if raw.startswith("ctx:") and len(raw) > 4:
            return raw[4:]
    return ""


def _parse_context_key(value: Any) -> Dict[str, str]:
    """Parse context key format '<qualified>::<mode>::<connection>'."""
    raw = str(value or "").strip()
    parsed = {
        "context_key": raw,
        "qualified_name": "",
        "execution_mode": "",
        "connection_key": "",
    }
    if not raw:
        return parsed

    parts = raw.split("::")
    if len(parts) < 3:
        return parsed

    connection_key = str(parts[-1]).strip()
    execution_mode = _normalize_execution_mode(parts[-2], default="")
    qualified_name = "::".join(parts[:-2]).strip()
    if not execution_mode:
        return parsed

    parsed["qualified_name"] = qualified_name
    parsed["execution_mode"] = execution_mode
    parsed["connection_key"] = connection_key
    return parsed


def _identity_from_mode_connection(
    execution_mode: Any,
    connection_key: Any = "",
    host_alias: str = "",
) -> Dict[str, str]:
    """
    Build canonical identity fields from mode + connection key.

    This is the normalized counterpart to _connection_identity(remote_enabled,...)
    when execution metadata is already known.
    """
    mode = _normalize_execution_mode(execution_mode, default="local")
    if mode not in {"local", "ssh"}:
        mode = "local"

    raw_connection = str(connection_key or "").strip()
    if raw_connection in {"unknown", "global"}:
        raw_connection = ""
    if mode == "local":
        normalized_connection = (
            _normalize_connection_key(raw_connection)
            if raw_connection
            else _local_connection_key()
        )
        alias = (
            str(
                os.environ.get("I3PM_LOCAL_HOST_ALIAS")
                or os.environ.get("HOSTNAME")
                or socket.gethostname()
            ).strip().lower()
            or "localhost"
        )
    else:
        normalized_connection = (
            _normalize_connection_key(raw_connection)
            if raw_connection
            else _normalize_connection_key(host_alias or "unknown")
        )
        alias = str(host_alias or "").strip() or normalized_connection or "unknown"

    return {
        "execution_mode": mode,
        "connection_key": normalized_connection,
        "host_alias": alias,
        "identity_key": f"{mode}:{normalized_connection}",
    }


def _resolve_window_execution_identity(
    window: Dict[str, Any],
    *,
    remote_profile: Optional[Dict[str, Any]] = None,
    remote_env_cache: Optional[Dict[int, Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """
    Resolve canonical execution identity for a daemon window payload.

    Priority:
      1) Explicit daemon metadata (execution_mode/connection_key/context_key/remote_*)
      2) ctx:<context_key> sway mark
      3) Compatibility fallback via /proc I3PM_REMOTE_* (cached)
    """
    remote_profile = remote_profile or {}

    mode = _normalize_execution_mode(
        window.get("execution_mode") or window.get("i3pm_execution_mode"),
        default="",
    )
    connection_key = str(
        window.get("connection_key") or window.get("i3pm_connection_key") or ""
    ).strip()
    context_key = str(window.get("context_key") or window.get("i3pm_context_key") or "").strip()
    if not context_key:
        context_key = _extract_context_key_from_marks(window.get("marks", []))
    parsed_context = _parse_context_key(context_key)
    if not mode:
        mode = parsed_context.get("execution_mode", "")
    if not connection_key:
        connection_key = parsed_context.get("connection_key", "")

    remote_enabled_raw = window.get("remote_enabled")
    if remote_enabled_raw is None:
        remote_enabled_raw = window.get("i3pm_remote_enabled")
    if remote_enabled_raw is None:
        remote_enabled_raw = window.get("project_remote_enabled")

    remote_target = str(
        window.get("remote_target")
        or window.get("i3pm_remote_target")
        or window.get("project_remote_target")
        or ""
    ).strip()
    remote_user = str(window.get("remote_user") or window.get("i3pm_remote_user") or "").strip()
    remote_host = str(window.get("remote_host") or window.get("i3pm_remote_host") or "").strip()
    remote_port = window.get("remote_port")
    if remote_port in (None, ""):
        remote_port = window.get("i3pm_remote_port")
    remote_dir = str(
        window.get("remote_dir")
        or window.get("i3pm_remote_dir")
        or window.get("project_remote_dir")
        or ""
    ).strip()
    remote_session_name = str(
        window.get("remote_session_name") or window.get("i3pm_remote_session_name") or ""
    ).strip()

    has_direct_identity_hint = bool(
        mode
        or connection_key
        or context_key
        or remote_enabled_raw is not None
        or remote_target
        or remote_host
        or remote_user
        or remote_port
    )

    if not has_direct_identity_hint and remote_env_cache is not None:
        pid_int = _safe_int(window.get("pid"), 0)
        if pid_int > 0:
            env = remote_env_cache.get(pid_int)
            if env is None:
                env = _read_window_remote_env(pid_int)
                remote_env_cache[pid_int] = env
            if env:
                if remote_enabled_raw is None:
                    remote_enabled_raw = env.get("I3PM_REMOTE_ENABLED")
                if not remote_user:
                    remote_user = str(env.get("I3PM_REMOTE_USER") or "").strip()
                if not remote_host:
                    remote_host = str(env.get("I3PM_REMOTE_HOST") or "").strip()
                if not remote_port:
                    remote_port = env.get("I3PM_REMOTE_PORT")
                if not remote_dir:
                    remote_dir = str(env.get("I3PM_REMOTE_DIR") or "").strip()
                if not remote_session_name:
                    remote_session_name = str(env.get("I3PM_REMOTE_SESSION_NAME") or "").strip()

    profile_target = _format_remote_target(
        remote_profile.get("user", ""),
        remote_profile.get("host", ""),
        remote_profile.get("port", 22),
    )
    if not remote_target:
        remote_target = _format_remote_target(remote_user, remote_host, remote_port or 22)
    if not remote_target:
        remote_target = profile_target
    if not remote_dir:
        remote_dir = str(remote_profile.get("remote_dir", "")).strip()

    remote_enabled = _is_truthy(remote_enabled_raw)
    if mode == "ssh":
        remote_enabled = True
    elif mode == "local":
        remote_enabled = False
    elif remote_enabled:
        mode = "ssh"
    elif connection_key:
        mode = "local" if connection_key.startswith("local@") else "ssh"
    else:
        mode = "local"

    if mode == "ssh" and not connection_key:
        connection_key = _normalize_connection_key(remote_target or remote_host or "unknown")
    if mode == "local" and not connection_key:
        connection_key = _local_connection_key()

    identity = _identity_from_mode_connection(
        mode,
        connection_key,
        host_alias=remote_target if mode == "ssh" else "",
    )

    if mode == "ssh" and not remote_target:
        remote_target = str(identity.get("host_alias", "")).strip()

    return {
        "execution_mode": identity["execution_mode"],
        "connection_key": identity["connection_key"],
        "identity_key": identity["identity_key"],
        "host_alias": identity["host_alias"],
        "context_key": context_key,
        "remote_enabled": mode == "ssh",
        "remote_target": remote_target,
        "remote_dir": remote_dir,
        "remote_session_name": remote_session_name,
    }


def _resolve_session_execution_identity(
    session: Dict[str, Any],
    *,
    window_data: Optional[Dict[str, Any]] = None,
    default_mode: str = "local",
) -> Dict[str, str]:
    """Resolve canonical execution identity for an OTEL session payload."""
    terminal_context = session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}
    window_data = window_data or {}

    mode = _normalize_execution_mode(
        session.get("execution_mode")
        or terminal_context.get("execution_mode")
        or window_data.get("execution_mode"),
        default="",
    )
    connection_key = str(
        session.get("connection_key")
        or terminal_context.get("connection_key")
        or window_data.get("connection_key")
        or ""
    ).strip()
    context_key = str(
        session.get("context_key")
        or terminal_context.get("context_key")
        or window_data.get("context_key")
        or ""
    ).strip()
    parsed_context = _parse_context_key(context_key)
    if not mode:
        mode = parsed_context.get("execution_mode", "")
    if not connection_key:
        connection_key = parsed_context.get("connection_key", "")

    remote_enabled = _is_truthy(
        session.get("remote_enabled") or terminal_context.get("remote_enabled")
    )
    host_name = str(
        terminal_context.get("host_name")
        or session.get("host_name")
        or window_data.get("host_alias")
        or ""
    ).strip()
    remote_target = str(
        session.get("remote_target")
        or terminal_context.get("remote_target")
        or window_data.get("project_remote_target")
        or ""
    ).strip()

    if not mode:
        if remote_enabled:
            mode = "ssh"
        elif connection_key:
            mode = "local" if connection_key.startswith("local@") else "ssh"
        else:
            mode = _normalize_execution_mode(default_mode, default="local")

    if mode not in {"local", "ssh"}:
        mode = _normalize_execution_mode(default_mode, default="local")

    if not connection_key:
        if mode == "ssh":
            connection_key = _normalize_connection_key(remote_target or host_name or "unknown")
        else:
            connection_key = _local_connection_key()

    identity = _identity_from_mode_connection(
        mode,
        connection_key,
        host_alias=remote_target or host_name,
    )
    identity["context_key"] = context_key
    return identity


def _collect_output_window_candidates(outputs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Collect normalized window candidates for OTEL session window-id resolution."""
    candidates: List[Dict[str, Any]] = []
    remote_env_cache: Dict[int, Dict[str, str]] = {}

    for output in outputs:
        for workspace in output.get("workspaces", []):
            for window in workspace.get("windows", []):
                window_id = _safe_int(window.get("id"), 0)
                if window_id == 0:
                    continue
                project_name = str(window.get("project") or "").strip()

                identity = _resolve_window_execution_identity(
                    window,
                    remote_env_cache=remote_env_cache,
                )
                candidates.append(
                    {
                        "id": window_id,
                        "project": project_name,
                        "focused": bool(window.get("focused", False)),
                        "hidden": bool(window.get("hidden", False)),
                        "floating": bool(window.get("floating", False)),
                        "class": str(window.get("class") or ""),
                        "app_id": str(window.get("app_id") or ""),
                        "app_name": str(window.get("app_name") or ""),
                        "display_name": str(window.get("display_name") or ""),
                        "title": str(window.get("title") or ""),
                        "marks": list(window.get("marks") or []) if isinstance(window.get("marks"), list) else [],
                        "execution_mode": str(identity.get("execution_mode") or ""),
                        "connection_key": str(identity.get("connection_key") or ""),
                        "identity_key": str(identity.get("identity_key") or ""),
                        "context_key": str(identity.get("context_key") or ""),
                        "remote_session_name": str(identity.get("remote_session_name") or ""),
                    }
                )

    return candidates


def _window_terminal_preference_rank(candidate: Dict[str, Any]) -> int:
    """
    Rank window candidates for deterministic AI session targeting.

    Prefer normal project terminals over scratchpad terminals when both share
    the same identity/project scope.
    """
    app_id = str(candidate.get("app_id") or "").strip().lower()
    display_name = str(candidate.get("display_name") or "").strip().lower()
    title = str(candidate.get("title") or "").strip().lower()
    marks_raw = candidate.get("marks") or []
    marks: List[str] = [str(mark).strip().lower() for mark in marks_raw if str(mark).strip()]

    is_scratchpad = (
        "scratchpad" in app_id
        or "scratchpad" in display_name
        or "scratchpad" in title
        or any(mark.startswith("scoped:scratchpad-terminal:") for mark in marks)
    )
    is_primary_terminal = (
        app_id.startswith("terminal-")
        or any(mark.startswith("scoped:terminal:") for mark in marks)
    )

    if is_primary_terminal and not is_scratchpad:
        return 2
    if not is_scratchpad:
        return 1
    return 0


def _session_project_candidates(raw_project: Any) -> tuple[set[str], set[str]]:
    """Return exact/prefix project candidates from OTEL project identifiers."""
    exact: set[str] = set()
    prefixes: set[str] = set()

    project_value = str(raw_project or "").strip()
    if not project_value:
        return exact, prefixes

    # Already normalized worktree/project identifiers.
    if "/" in project_value:
        if ":" in project_value:
            exact.add(project_value)
            prefixes.add(project_value.split(":", 1)[0])
        else:
            prefixes.add(project_value)

    # Absolute/tilde path format: ~/repos/<account>/<repo>/<branch>...
    if project_value.startswith("/") or project_value.startswith("~"):
        path_parts = Path(project_value).expanduser().parts
        for idx, part in enumerate(path_parts):
            if part != "repos":
                continue
            if idx + 3 >= len(path_parts):
                continue
            account = str(path_parts[idx + 1]).strip()
            repo = str(path_parts[idx + 2]).strip()
            branch = str(path_parts[idx + 3]).strip()
            if not account or not repo:
                continue
            prefixes.add(f"{account}/{repo}")
            if branch:
                exact.add(f"{account}/{repo}:{branch}")
            break

    return exact, prefixes


def _normalize_session_project_from_path(session: Dict[str, Any]) -> Dict[str, Any]:
    """Prefer project identifier derived from project_path when mismatched/stale."""
    normalized = dict(session)
    project_raw = str(normalized.get("project") or "").strip()
    project_path_raw = str(normalized.get("project_path") or "").strip()
    if not project_path_raw:
        return normalized

    path_exact, path_prefixes = _session_project_candidates(project_path_raw)
    if not path_exact and not path_prefixes:
        return normalized

    current_exact, current_prefixes = _session_project_candidates(project_raw)
    # If current project is absent or doesn't align with path-derived identity,
    # replace it with a deterministic exact candidate from project_path.
    aligned = bool(
        (path_exact and current_exact and len(path_exact.intersection(current_exact)) > 0)
        or (
            path_prefixes
            and current_prefixes
            and len(path_prefixes.intersection(current_prefixes)) > 0
        )
    )
    if aligned:
        return normalized

    if path_exact:
        normalized["project"] = sorted(path_exact)[0]
    elif path_prefixes:
        normalized["project"] = sorted(path_prefixes)[0]
    return normalized


def _tmux_session_project_hints() -> Dict[str, str]:
    """Map normalized tmux session names to unique discovered worktree projects."""
    repos_file = Path.home() / ".config" / "i3" / "repos.json"
    if not repos_file.exists():
        DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
            "mtime_ns": None,
            "size": None,
            "mapping": {},
        })
        return {}

    try:
        stat_result = repos_file.stat()
        if (
            DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mtime_ns") == stat_result.st_mtime_ns
            and DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("size") == stat_result.st_size
        ):
            cached_mapping = DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mapping")
            if isinstance(cached_mapping, dict):
                return dict(cached_mapping)
    except OSError:
        return {}

    discovered = load_discovered_repositories()
    repositories = discovered.get("repositories", []) if isinstance(discovered, dict) else []
    hints: Dict[str, set[str]] = {}

    for repo in repositories:
        if not isinstance(repo, dict):
            continue
        for wt in repo.get("worktrees", []):
            if not isinstance(wt, dict):
                continue
            qualified_name = str(wt.get("qualified_name") or "").strip()
            if not qualified_name:
                continue
            suffix_key = _normalize_session_name_key(_project_session_suffix(qualified_name))
            if not suffix_key:
                continue
            hints.setdefault(suffix_key, set()).add(qualified_name)

    mapping = {
        suffix_key: sorted(qualified_names)[0]
        for suffix_key, qualified_names in hints.items()
        if len(qualified_names) == 1
    }
    DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
        "mtime_ns": stat_result.st_mtime_ns,
        "size": stat_result.st_size,
        "mapping": dict(mapping),
    })
    return mapping


def _resolve_session_project_labels(
    session: Dict[str, Any],
    *,
    window_project: str = "",
) -> Dict[str, str]:
    """Resolve display vs. focus project labels for a session.

    `session_project` is what the AI session is actually operating on.
    `focus_project` is the project context required to reveal/focus the owning
    window. They may differ for hidden/shared terminals or remote SSH anchors.
    """
    upstream_session_project = str(session.get("session_project") or "").strip()
    upstream_display_project = str(session.get("display_project") or "").strip()
    upstream_focus_project = str(session.get("focus_project") or "").strip()
    upstream_window_project = str(session.get("window_project") or "").strip()
    upstream_project_source = str(session.get("project_source") or "").strip()
    if any(
        [
            upstream_session_project,
            upstream_display_project,
            upstream_focus_project,
            upstream_window_project,
            upstream_project_source,
        ]
    ):
        resolved_window_project = str(window_project or "").strip() or upstream_window_project
        session_project = upstream_session_project or str(session.get("project") or "").strip()
        display_project = (
            upstream_display_project
            or session_project
            or resolved_window_project
            or str(session.get("project") or "").strip()
            or "unknown"
        )
        focus_project = resolved_window_project or upstream_focus_project or session_project or ""
        project_source = upstream_project_source or ("session" if session_project else "window_fallback")
        return {
            "session_project": session_project,
            "window_project": resolved_window_project,
            "focus_project": focus_project,
            "display_project": display_project,
            "project_source": project_source,
        }

    normalized_session = _normalize_session_project_from_path(session)
    session_project = str(normalized_session.get("project") or "").strip()
    raw_session_project = str(session.get("project") or "").strip()
    project_path = str(normalized_session.get("project_path") or "").strip()
    window_project = str(window_project or "").strip()

    terminal_context = normalized_session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}

    context_key = str(
        normalized_session.get("context_key")
        or terminal_context.get("context_key")
        or ""
    ).strip()
    parsed_context = _parse_context_key(context_key)
    context_project = str(parsed_context.get("qualified_name") or "").strip()

    tmux_session_key = _normalize_session_name_key(
        terminal_context.get("tmux_session") or session.get("tmux_session") or ""
    )
    tmux_project = _tmux_session_project_hints().get(tmux_session_key, "")

    def _projects_align(left: str, right: str) -> bool:
        if not left or not right:
            return False
        left_exact, left_prefixes = _session_project_candidates(left)
        right_exact, right_prefixes = _session_project_candidates(right)
        return bool(
            (left_exact and right_exact and left_exact.intersection(right_exact))
            or (left_prefixes and right_prefixes and left_prefixes.intersection(right_prefixes))
        )

    def _project_matches_tmux(project_name: str) -> bool:
        if not project_name or not tmux_session_key:
            return False
        suffix = _normalize_session_name_key(_project_session_suffix(project_name))
        return bool(suffix and suffix == tmux_session_key)

    session_project_source = "window_fallback"
    session_project_trusted = False

    if session_project:
        session_project_source = "session"
        session_project_trusted = False

    if project_path:
        session_project_source = "path"
        session_project_trusted = True

    if context_project:
        if not session_project or not _projects_align(session_project, context_project):
            session_project = context_project
        session_project_source = "context"
        session_project_trusted = True

    if tmux_project:
        if not session_project or not _projects_align(session_project, tmux_project):
            session_project = tmux_project
        if not context_project or not _projects_align(context_project, tmux_project):
            session_project_source = "tmux_discovered"
            session_project_trusted = True

    if session_project and not session_project_trusted and _project_matches_tmux(session_project):
        session_project_source = "tmux"
        session_project_trusted = True

    if not session_project and window_project:
        session_project = window_project
        session_project_source = "window_fallback"
        session_project_trusted = False

    if (
        session_project
        and not session_project_trusted
        and window_project
        and not _projects_align(session_project, window_project)
        and _project_matches_tmux(window_project)
        and not _project_matches_tmux(session_project)
    ):
        session_project = window_project
        session_project_source = "tmux_window_fallback"

    if (
        session_project
        and raw_session_project
        and session_project_source == "session"
        and _projects_align(session_project, window_project)
    ):
        session_project_trusted = True

    display_project = session_project or window_project or "unknown"
    focus_project = window_project or session_project or ""

    return {
        "session_project": session_project or "",
        "window_project": window_project,
        "focus_project": focus_project,
        "display_project": display_project,
        "project_source": session_project_source,
    }


def _resolve_otel_session_window_id(
    session: Dict[str, Any],
    outputs: List[Dict[str, Any]],
    window_candidates: Optional[List[Dict[str, Any]]] = None,
) -> Optional[int]:
    """Best-effort mapping when OTEL session lacks explicit window_id."""
    terminal_context = session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}
    parsed_context = _parse_context_key(
        session.get("context_key") or terminal_context.get("context_key") or ""
    )

    exact_candidates: set[str] = set()
    prefix_candidates: set[str] = set()
    for source in (session.get("project"), session.get("project_path")):
        exact, prefixes = _session_project_candidates(source)
        exact_candidates.update(exact)
        prefix_candidates.update(prefixes)

    context_qualified = str(parsed_context.get("qualified_name") or "").strip()
    if context_qualified:
        if ":" in context_qualified:
            exact_candidates.add(context_qualified)
            prefix_candidates.add(context_qualified.split(":", 1)[0])
        else:
            prefix_candidates.add(context_qualified)

    candidates = window_candidates if window_candidates is not None else _collect_output_window_candidates(outputs)

    raw_session_connection = str(
        session.get("connection_key")
        or terminal_context.get("connection_key")
        or parsed_context.get("connection_key")
        or ""
    ).strip()
    raw_session_context = str(
        session.get("context_key") or terminal_context.get("context_key") or ""
    ).strip()
    has_explicit_identity = bool(raw_session_context or raw_session_connection)

    session_mode = _normalize_execution_mode(
        session.get("execution_mode") or terminal_context.get("execution_mode"),
        default="",
    )
    if not session_mode:
        session_mode = str(parsed_context.get("execution_mode") or "").strip()
    session_identity = _resolve_session_execution_identity(session, default_mode="local")
    session_connection = str(session_identity.get("connection_key") or "").strip()
    session_context = str(session_identity.get("context_key") or "").strip()
    session_tmux_session_key = _normalize_session_name_key(
        terminal_context.get("tmux_session") or session.get("tmux_session") or ""
    )

    def _identity_compatible(candidate: Dict[str, Any]) -> bool:
        window_mode = str(candidate.get("execution_mode") or "").strip()
        window_connection = str(candidate.get("connection_key") or "").strip()
        window_context = str(candidate.get("context_key") or "").strip()

        if session_context and window_context and session_context != window_context:
            return False
        if session_mode and window_mode and session_mode != window_mode:
            return False
        if (
            session_connection
            and window_connection
            and not _connection_keys_equivalent(session_connection, window_connection)
        ):
            return False
        return True

    # Deterministic tmux-session mapping for remote windows when project/context
    # metadata is absent or stale. When tmux identity is present, it is
    # authoritative; we never fall back to project heuristics if this lookup
    # is ambiguous or missing.
    if session_tmux_session_key:
        identity_candidates: List[Dict[str, Any]] = [
            candidate for candidate in candidates if _identity_compatible(candidate)
        ]
        tmux_hint_exact: set[str] = set()
        tmux_hint_prefixes: set[str] = set()

        # Derive project hints from tmux session suffix (e.g. "stacks/main" ->
        # "PittampalliOrg/stacks:main") even when daemon windows lack explicit
        # remote_session_name metadata.
        for candidate in identity_candidates:
            candidate_project = str(candidate.get("project") or "").strip()
            if not candidate_project:
                continue
            candidate_suffix = _normalize_session_name_key(
                _project_session_suffix(candidate_project)
            )
            if not candidate_suffix or candidate_suffix != session_tmux_session_key:
                continue
            candidate_exact, candidate_prefixes = _session_project_candidates(candidate_project)
            tmux_hint_exact.update(candidate_exact)
            tmux_hint_prefixes.update(candidate_prefixes)

        tmux_matches: List[int] = []
        tmux_nonfocusable_match_found = False
        for candidate in identity_candidates:
            candidate_tmux_session_key = _normalize_session_name_key(
                candidate.get("remote_session_name") or ""
            )
            if (
                not candidate_tmux_session_key
                or candidate_tmux_session_key != session_tmux_session_key
            ):
                continue
            candidate_project = str(candidate.get("project") or "").strip()
            if candidate_project:
                candidate_exact, candidate_prefixes = _session_project_candidates(candidate_project)
                tmux_hint_exact.update(candidate_exact)
                tmux_hint_prefixes.update(candidate_prefixes)
            candidate_window_id = _safe_int(candidate.get("id"), 0)
            if candidate_window_id > 0:
                tmux_matches.append(candidate_window_id)
            else:
                tmux_nonfocusable_match_found = True

        if tmux_hint_exact or tmux_hint_prefixes:
            exact_candidates = set(tmux_hint_exact)
            prefix_candidates = set(tmux_hint_prefixes)

        if len(tmux_matches) == 1:
            return tmux_matches[0]

        tmux_metadata_available_focusable = False
        tmux_metadata_available_nonfocusable = False
        for candidate in identity_candidates:
            candidate_tmux_session_key = _normalize_session_name_key(
                candidate.get("remote_session_name") or ""
            )
            if not candidate_tmux_session_key:
                continue
            if tmux_hint_exact or tmux_hint_prefixes:
                candidate_project = str(candidate.get("project") or "").strip()
                if not candidate_project:
                    continue
                in_scope = (
                    candidate_project in tmux_hint_exact
                    or any(
                        candidate_project == prefix
                        or candidate_project.startswith(prefix + ":")
                        for prefix in tmux_hint_prefixes
                    )
                )
                if not in_scope:
                    continue
            candidate_window_id = _safe_int(candidate.get("id"), 0)
            if candidate_window_id > 0:
                tmux_metadata_available_focusable = True
            else:
                tmux_metadata_available_nonfocusable = True

        if tmux_metadata_available_focusable:
            upstream_window_project = str(
                session.get("focus_project") or session.get("window_project") or ""
            ).strip()
            if upstream_window_project:
                upstream_exact, upstream_prefixes = _session_project_candidates(
                    upstream_window_project
                )
                preferred_window_id: Optional[int] = None
                preferred_score: Optional[tuple[int, int, int, int, int]] = None
                for candidate in identity_candidates:
                    candidate_window_id = _safe_int(candidate.get("id"), 0)
                    candidate_project = str(candidate.get("project") or "").strip()
                    if candidate_window_id <= 0 or not candidate_project:
                        continue
                    if not (
                        candidate_project in upstream_exact
                        or any(
                            candidate_project == prefix
                            or candidate_project.startswith(prefix + ":")
                            for prefix in upstream_prefixes
                        )
                    ):
                        continue
                    score = (
                        _window_terminal_preference_rank(candidate),
                        int(bool(candidate.get("focused", False))),
                        int(not bool(candidate.get("hidden", False))),
                        int(not bool(candidate.get("floating", False))),
                        candidate_window_id,
                    )
                    if preferred_score is None or score > preferred_score:
                        preferred_score = score
                        preferred_window_id = candidate_window_id
                if preferred_window_id is not None:
                    return preferred_window_id
            return None
        # Synthetic remote-session rows (negative IDs) cannot be focused directly,
        # but when they are the only tmux metadata source they can still provide
        # project hints. If metadata exists and does not match, do not fall back.
        if tmux_metadata_available_nonfocusable and not tmux_nonfocusable_match_found:
            return None

    # Strict identity-only fallback:
    # When project/tmux metadata is missing or stale, map by identity only if
    # there is exactly one compatible candidate window. Otherwise do not guess.
    identity_only_candidates: List[int] = []
    if has_explicit_identity:
        for candidate in candidates:
            if not _identity_compatible(candidate):
                continue
            candidate_window_id = _safe_int(candidate.get("id"), 0)
            if candidate_window_id > 0:
                identity_only_candidates.append(candidate_window_id)
    unique_identity_only_window_id: Optional[int] = (
        identity_only_candidates[0] if len(identity_only_candidates) == 1 else None
    )

    best_window_id: Optional[int] = None
    best_score: Optional[tuple[int, int, int, int, int, int, int, int]] = None
    for candidate in candidates:
        window_project = str(candidate.get("project") or "").strip()
        if not window_project:
            continue

        match_rank = 0
        if window_project in exact_candidates:
            match_rank = 2
        elif any(
            window_project == prefix or window_project.startswith(prefix + ":")
            for prefix in prefix_candidates
        ):
            match_rank = 1

        window_mode = str(candidate.get("execution_mode") or "").strip()
        window_connection = str(candidate.get("connection_key") or "").strip()
        window_context = str(candidate.get("context_key") or "").strip()

        # Hard filters when session identity is explicit.
        if session_context and window_context and session_context != window_context:
            continue
        if session_mode and window_mode and session_mode != window_mode:
            continue
        if (
            session_connection
            and window_connection
            and not _connection_keys_equivalent(session_connection, window_connection)
        ):
            continue

        if match_rank == 0:
            if not has_explicit_identity:
                continue
            # Deterministic only: never pick among multiple identity-compatible
            # windows on the same remote/local context.
            if unique_identity_only_window_id is None:
                continue
            window_id = _safe_int(candidate.get("id"), 0)
            if window_id != unique_identity_only_window_id:
                continue
            match_rank = 1

        identity_rank = 0
        if session_context and window_context and session_context == window_context:
            identity_rank = 3
        elif session_mode and window_mode and session_mode == window_mode:
            if (
                session_connection
                and window_connection
                and _connection_keys_equivalent(session_connection, window_connection)
            ):
                identity_rank = 2
            else:
                identity_rank = 1

        window_id = _safe_int(candidate.get("id"), 0)
        if window_id == 0:
            continue

        terminal_preference = _window_terminal_preference_rank(candidate)
        score = (
            match_rank,
            identity_rank,
            terminal_preference,
            int(bool(candidate.get("focused", False))),
            int(not bool(candidate.get("hidden", False))),
            int(str(candidate.get("class") or "") != "remote-sesh"),
            int(not bool(candidate.get("floating", False))),
            int(window_id),
        )
        if best_score is None or score > best_score:
            best_score = score
            best_window_id = window_id

    return best_window_id


def _connection_keys_equivalent(left: Any, right: Any) -> bool:
    """Return True when two connection keys refer to the same endpoint."""
    left_raw = str(left or "").strip()
    right_raw = str(right or "").strip()
    if not left_raw or not right_raw:
        return False

    left_norm = _normalize_connection_key(left_raw)
    right_norm = _normalize_connection_key(right_raw)
    if left_norm == right_norm:
        return True

    left_aliases = _connection_key_aliases(left_norm)
    right_aliases = _connection_key_aliases(right_norm)
    if not left_aliases:
        left_aliases = {left_norm}
    if not right_aliases:
        right_aliases = {right_norm}
    return bool(left_aliases.intersection(right_aliases))


def _window_tracking_identity(window: Dict[str, Any]) -> Dict[str, str]:
    """Extract normalized execution identity from transformed window payload."""
    mode = _normalize_execution_mode(
        window.get("i3pm_execution_mode") or window.get("execution_mode"),
        default="",
    )
    connection_key = str(
        window.get("i3pm_connection_key") or window.get("connection_key") or ""
    ).strip()
    context_key = str(
        window.get("i3pm_context_key") or window.get("context_key") or ""
    ).strip()

    parsed_context = _parse_context_key(context_key)
    if not mode:
        mode = str(parsed_context.get("execution_mode") or "").strip()
    if not connection_key:
        connection_key = str(parsed_context.get("connection_key") or "").strip()

    if connection_key:
        connection_key = _normalize_connection_key(connection_key)

    return {
        "execution_mode": mode,
        "connection_key": connection_key,
        "context_key": context_key,
    }


def _window_matches_session_identity(
    window: Dict[str, Any],
    *,
    session_identity: Optional[Dict[str, Any]] = None,
    execution_mode: Any = "",
    connection_key: Any = "",
    context_key: Any = "",
) -> bool:
    """Require identity-safe matching between a session/review entry and window."""
    target_mode = _normalize_execution_mode(
        (
            (session_identity or {}).get("execution_mode")
            if isinstance(session_identity, dict)
            else execution_mode
        ),
        default="",
    )
    target_connection = str(
        (
            (session_identity or {}).get("connection_key")
            if isinstance(session_identity, dict)
            else connection_key
        )
        or ""
    ).strip()
    target_context = str(
        (
            (session_identity or {}).get("context_key")
            if isinstance(session_identity, dict)
            else context_key
        )
        or ""
    ).strip()

    parsed_target = _parse_context_key(target_context)
    if not target_mode:
        target_mode = str(parsed_target.get("execution_mode") or "").strip()
    if not target_connection:
        target_connection = str(parsed_target.get("connection_key") or "").strip()
    if target_connection:
        target_connection = _normalize_connection_key(target_connection)

    window_identity = _window_tracking_identity(window)
    window_mode = str(window_identity.get("execution_mode") or "").strip()
    window_connection = str(window_identity.get("connection_key") or "").strip()
    window_context = str(window_identity.get("context_key") or "").strip()

    if target_context and window_context and target_context != window_context:
        return False
    if target_mode and window_mode and target_mode != window_mode:
        return False
    if target_connection and window_connection and not _connection_keys_equivalent(target_connection, window_connection):
        return False
    return True


def _window_matches_session_binding(window: Dict[str, Any], session: Dict[str, Any]) -> bool:
    """Allow project/tmux affinity to preserve explicit window bindings when shell context is stale."""
    if not _window_is_ai_terminal_candidate(window):
        return False

    session_identity = _resolve_session_execution_identity(session, default_mode="local")
    if _window_matches_session_identity(window, session_identity=session_identity):
        return True

    window_identity = _window_tracking_identity(window)
    window_mode = str(window_identity.get("execution_mode") or "").strip()
    window_connection = str(window_identity.get("connection_key") or "").strip()
    session_mode = str(session_identity.get("execution_mode") or "").strip()
    session_connection = str(session_identity.get("connection_key") or "").strip()
    if session_mode and window_mode and session_mode != window_mode:
        return False
    if (
        session_connection
        and window_connection
        and not _connection_keys_equivalent(session_connection, window_connection)
    ):
        return False

    window_project = str(window.get("project") or "").strip()
    if not window_project:
        return False

    exact_candidates: set[str] = set()
    prefix_candidates: set[str] = set()
    terminal_context = session.get("terminal_context", {}) or {}
    if not isinstance(terminal_context, dict):
        terminal_context = {}

    for source in (
        session.get("focus_project"),
        session.get("window_project"),
        session.get("session_project"),
        session.get("display_project"),
        session.get("project"),
        session.get("project_path"),
    ):
        exact, prefixes = _session_project_candidates(source)
        exact_candidates.update(exact)
        prefix_candidates.update(prefixes)

    for raw_context in (
        session.get("focus_context_key"),
        session.get("context_key"),
        terminal_context.get("context_key"),
    ):
        parsed_context = _parse_context_key(str(raw_context or ""))
        qualified_name = str(parsed_context.get("qualified_name") or "").strip()
        if not qualified_name:
            continue
        if ":" in qualified_name:
            exact_candidates.add(qualified_name)
            prefix_candidates.add(qualified_name.split(":", 1)[0])
        else:
            prefix_candidates.add(qualified_name)

    if window_project in exact_candidates:
        return True
    if any(
        window_project == prefix or window_project.startswith(prefix + ":")
        for prefix in prefix_candidates
    ):
        return True

    tmux_session_key = _normalize_session_name_key(
        terminal_context.get("tmux_session") or session.get("tmux_session") or ""
    )
    if tmux_session_key:
        candidate_tmux_key = _normalize_session_name_key(
            window.get("remote_session_name") or _project_session_suffix(window_project)
        )
        if candidate_tmux_key and candidate_tmux_key == tmux_session_key:
            return True

    return False


def _window_is_ai_terminal_candidate(window: Dict[str, Any]) -> bool:
    """Only allow AI tracking on terminal-capable windows (Ghostty/tmux proxies)."""
    class_name = str(window.get("class") or "").strip().lower()
    app_id = str(window.get("app_id") or "").strip().lower()
    app_name = str(window.get("app_name") or "").strip().lower()
    display_name = str(window.get("display_name") or "").strip().lower()

    fields_present = any([class_name, app_id, app_name, display_name])
    if not fields_present:
        # Unit-test fixtures may omit app metadata.
        return True

    values = [class_name, app_id, app_name, display_name]
    if any("ghostty" in value for value in values if value):
        return True
    if any(value == "remote-sesh" for value in values if value):
        return True
    return False


def _build_active_session_key(
    *,
    tool: str,
    project: str,
    window_id: int,
    tmux_pane: str = "",
    pty: str = "",
    tmux_window: str = "",
    native_session_id: str = "",
    session_id: str = "",
    context_fingerprint: str = "",
) -> str:
    """Build canonical active-session key across badges/rail/review state."""
    key_parts = [
        f"tool={tool or 'unknown'}",
        f"project={project or '-'}",
        f"window={window_id}",
    ]
    if tmux_pane:
        key_parts.append(f"pane={tmux_pane}")
    elif pty:
        key_parts.append(f"pty={pty}")
    elif tmux_window:
        key_parts.append(f"tmux_window={tmux_window}")
    else:
        if native_session_id:
            key_parts.append(f"native={native_session_id}")
        elif session_id:
            key_parts.append(f"session={session_id}")
        if context_fingerprint:
            key_parts.append(f"context={context_fingerprint}")
    return "|".join(key_parts)


def _session_updated_epoch(session: Dict[str, Any], now_epoch: Optional[int] = None) -> int:
    """Resolve session updated-at timestamp as epoch seconds."""
    now_epoch = int(time.time()) if now_epoch is None else int(now_epoch)
    updated_at = str(session.get("updated_at") or "").strip()
    parsed = _parse_timestamp_to_epoch(updated_at)
    if parsed is None:
        return now_epoch
    return int(parsed)


def _build_review_finish_marker(session: Dict[str, Any]) -> str:
    """Build deterministic marker for a single completion cycle."""
    key = str(session.get("session_key") or "").strip()
    state_seq = _safe_int(session.get("state_seq"), 0)
    updated_at = str(session.get("updated_at") or "").strip()
    status_reason = str(session.get("status_reason") or "").strip()
    marker_src = f"{key}|{state_seq}|{updated_at}|{status_reason}"
    if not key:
        return ""
    return hashlib.sha1(marker_src.encode("utf-8")).hexdigest()


def _session_anchor_key(session: Dict[str, Any]) -> str:
    """Build a stable execution+terminal anchor for live/review dedupe."""
    if not isinstance(session, dict):
        return ""

    tool = str(session.get("tool") or "unknown").strip() or "unknown"
    execution_mode = _normalize_execution_mode(session.get("execution_mode"), default="")
    connection_key = str(session.get("connection_key") or "").strip()
    context_key = str(session.get("context_key") or "").strip()
    parsed_context = _parse_context_key(context_key)
    if not execution_mode:
        execution_mode = str(parsed_context.get("execution_mode") or "").strip()
    if not connection_key:
        connection_key = str(parsed_context.get("connection_key") or "").strip()
    if connection_key:
        connection_key = _normalize_connection_key(connection_key)

    tmux_session = str(session.get("tmux_session") or "").strip()
    tmux_window = str(session.get("tmux_window") or "").strip()
    tmux_pane = str(session.get("tmux_pane") or "").strip()
    pty = str(session.get("pty") or "").strip()
    window_id = _safe_int(session.get("window_id"), 0)

    key_parts = [
        f"tool={tool}",
        f"mode={execution_mode or '-'}",
        f"conn={connection_key or '-'}",
    ]
    normalized_tmux_session = _normalize_session_name_key(tmux_session)
    if tmux_pane:
        key_parts.append(f"pane={tmux_pane}")
        if normalized_tmux_session:
            key_parts.append(f"tmux_session={normalized_tmux_session}")
    elif pty:
        key_parts.append(f"pty={pty}")
    elif tmux_window:
        if normalized_tmux_session:
            key_parts.append(f"tmux_session={normalized_tmux_session}")
        key_parts.append(f"tmux_window={tmux_window}")
    elif normalized_tmux_session:
        key_parts.append(f"tmux_session={normalized_tmux_session}")
    elif window_id > 0:
        key_parts.append(f"window={window_id}")
    else:
        return ""

    return "|".join(key_parts)


def _list_tmux_active_panes_by_session() -> Dict[str, str]:
    """
    Return most-recent active pane per tmux session.

    Uses client activity timestamps to approximate what pane the user most
    recently inspected manually.
    """
    try:
        result = subprocess.run(
            [
                "tmux",
                "list-clients",
                "-F",
                "#{session_name}|#{pane_id}|#{client_activity}",
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.25,
        )
    except Exception:
        return {}

    if result.returncode != 0:
        return {}

    by_session: Dict[str, tuple[int, str]] = {}
    for raw in result.stdout.splitlines():
        parts = raw.strip().split("|")
        if len(parts) < 3:
            continue
        session_name, pane_id, activity_raw = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if not session_name or not pane_id:
            continue
        activity = _safe_int(activity_raw, 0)
        existing = by_session.get(session_name)
        if existing is None or activity >= existing[0]:
            by_session[session_name] = (activity, pane_id)

    return {session_name: pane for session_name, (_, pane) in by_session.items()}


def _build_otel_badges(
    otel_sessions: Optional[List[Dict[str, Any]]],
    window_project: str = "",
    window_data: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """
    Build OTEL badges array for multi-indicator display.

    Feature 136: Replaces _merge_badge_with_otel(). Returns an array of badges
    for all AI sessions associated with a window, sorted by state priority.

    Args:
        otel_sessions: List of OTEL session info for this window (may be None or empty)
        window_project: Canonical project label from owning window context

    Returns:
        List of badge dicts with otel_state, otel_tool, session_id, etc.
        Sorted by state priority, limited to active states (ATTENTION/WORKING).
    """
    if not otel_sessions:
        return []

    badges = []
    now_epoch = time.time()
    window_data = window_data or {}
    focus_identity = _window_tracking_identity(window_data) if isinstance(window_data, dict) else {}
    for session in _coalesce_otel_badge_sessions(otel_sessions):
        if not _session_tracking_contract_ok(session):
            continue
        state = str(session.get("state", "idle") or "idle").strip().lower()
        if state not in _OTEL_VISIBLE_BADGE_STATES:
            continue

        terminal_context = session.get("terminal_context", {}) or {}
        window_id_raw = session.get("window_id", terminal_context.get("window_id"))
        window_id_int = _safe_int(window_id_raw, 0)
        identity_raw = str(session.get("identity_confidence") or "")
        confidence_level = _identity_confidence_level(identity_raw)
        updated_epoch = _parse_timestamp_to_epoch(str(session.get("updated_at") or ""))
        stale_age_seconds = int(max(0.0, now_epoch - updated_epoch)) if updated_epoch else 0
        stale = state in {"idle", "completed"} and stale_age_seconds >= _AI_SESSION_STALE_THRESHOLD_SECONDS
        stage_fields = _normalize_stage_fields(
            {
                **session,
                "otel_state": state,
                "stale": stale,
                "stale_age_seconds": stale_age_seconds,
            },
            now_epoch=now_epoch,
        )
        stale_age_seconds = max(
            stale_age_seconds,
            int(stage_fields.get("activity_age_seconds") or stale_age_seconds),
        )
        stale = bool(stale or stage_fields.get("activity_freshness") == "stale")
        tool = str(session.get("tool", "unknown") or "unknown")
        project_labels = _resolve_session_project_labels(
            session,
            window_project=window_project,
        )
        session_project = str(project_labels.get("session_project") or "").strip()
        display_project = str(project_labels.get("display_project") or "").strip()
        focus_project = str(project_labels.get("focus_project") or "").strip()
        project_source = str(project_labels.get("project_source") or "window_fallback")
        tmux_session = str(terminal_context.get("tmux_session") or "")
        tmux_window = str(terminal_context.get("tmux_window") or "")
        tmux_pane = str(terminal_context.get("tmux_pane") or "")
        pty = str(terminal_context.get("pty") or "")
        native_session_id = str(session.get("native_session_id") or "")
        session_id = str(session.get("session_id") or "")
        context_fingerprint = str(session.get("context_fingerprint") or "")
        identity = _resolve_session_execution_identity(session)
        focus_execution_mode = str(focus_identity.get("execution_mode") or identity.get("execution_mode") or "local")
        focus_connection_key = str(focus_identity.get("connection_key") or identity.get("connection_key") or "")
        focus_context_key = str(focus_identity.get("context_key") or "")
        badge = {
            "badge_key": _otel_badge_merge_key(session),
            "session_key": _build_active_session_key(
                tool=tool,
                project=session_project or display_project,
                window_id=window_id_int,
                tmux_pane=tmux_pane,
                pty=pty,
                tmux_window=tmux_window,
                native_session_id=native_session_id,
                session_id=session_id,
                context_fingerprint=context_fingerprint,
            ),
            "session_id": session_id,
            "native_session_id": native_session_id,
            "context_fingerprint": context_fingerprint,
            "collision_group_id": str(session.get("collision_group_id") or ""),
            "identity_confidence": identity_raw,
            "confidence_level": confidence_level,
            "otel_state": state,
            "otel_tool": tool,
            "project": session_project or display_project,
            "session_project": session_project,
            "window_project": window_project,
            "focus_project": focus_project,
            "display_project": display_project,
            "project_source": project_source,
            "project_path": str(session.get("project_path") or ""),
            "pid": session.get("pid"),
            "trace_id": session.get("trace_id"),
            "pending_tools": session.get("pending_tools", 0),
            "is_streaming": session.get("is_streaming", False),
            "state_seq": _safe_int(session.get("state_seq"), 0),
            "status_reason": str(session.get("status_reason") or ""),
            "stage": str(stage_fields.get("stage") or "idle"),
            "stage_label": str(stage_fields.get("stage_label") or "Idle"),
            "stage_detail": str(stage_fields.get("stage_detail") or ""),
            "stage_class": str(stage_fields.get("stage_class") or "stage-idle"),
            "stage_visual_state": str(stage_fields.get("stage_visual_state") or "idle"),
            "stage_rank": int(stage_fields.get("stage_rank") or 0),
            "stage_glyph": str(stage_fields.get("stage_glyph") or _AI_STAGE_GLYPHS.get(str(stage_fields.get("stage") or "idle"), "·")),
            "needs_user_action": bool(stage_fields.get("needs_user_action", False)),
            "user_action_reason": str(stage_fields.get("user_action_reason") or ""),
            "output_ready": bool(stage_fields.get("output_ready", False)),
            "output_unseen": bool(stage_fields.get("output_unseen", False)),
            "activity_freshness": str(stage_fields.get("activity_freshness") or "fresh"),
            "activity_age_seconds": int(stage_fields.get("activity_age_seconds") or stale_age_seconds),
            "activity_age_label": str(stage_fields.get("activity_age_label") or _format_activity_age(stale_age_seconds)),
            "identity_source": str(stage_fields.get("identity_source") or ""),
            "lifecycle_source": str(stage_fields.get("lifecycle_source") or ""),
            "stale": stale,
            "stale_age_seconds": stale_age_seconds,
            "remote_source_stale": bool(session.get("remote_source_stale", False)),
            "remote_source_age_seconds": int(session.get("remote_source_age_seconds", 0) or 0),
            "execution_mode": str(identity.get("execution_mode") or "local"),
            "connection_key": str(identity.get("connection_key") or ""),
            "identity_key": str(identity.get("identity_key") or ""),
            "context_key": str(identity.get("context_key") or ""),
            "host_alias": str(identity.get("host_alias") or ""),
            "focus_execution_mode": focus_execution_mode,
            "focus_connection_key": focus_connection_key,
            "focus_context_key": focus_context_key,
            "host_name": str(
                terminal_context.get("host_name")
                or session.get("host_name")
                or ""
            ),
            # Feature: AI badge click-to-focus context (window + tmux pane/session)
            "window_id": window_id_int if window_id_int != 0 else window_id_raw,
            "tmux_session": tmux_session,
            "tmux_window": tmux_window,
            "tmux_pane": tmux_pane,
            "pty": pty,
            "review_pending": False,
            "review_state": "normal",
            "finished_at": None,
            "seen_at": None,
            "synthetic": False,
        }
        badges.append(badge)

    # Sort by state priority (highest first)
    badges.sort(
        key=lambda b: (
            int(b.get("stage_rank", 0) or 0),
            _OTEL_STATE_PRIORITY.get(b.get("otel_state", "idle"), 0),
        ),
        reverse=True
    )

    return badges


def _build_active_ai_sessions(
    otel_sessions: Optional[List[Dict[str, Any]]],
    window_lookup: Optional[Dict[int, Dict[str, Any]]] = None,
    active_project_name: str = "",
    focused_window_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """
    Build a canonical list of active AI sessions for fast switching.

    This list is separate from per-window badge rendering:
    - includes completed sessions so users can jump back quickly
    - emits a collision-safe session_key for duplicate native session IDs
    - is sorted for keyboard cycling and visual scanning
    """
    if not otel_sessions:
        return []

    window_lookup = window_lookup or {}
    merged_by_key: Dict[str, tuple[Dict[str, Any], Dict[str, Any]]] = {}
    now_epoch = time.time()

    for raw_session in _coalesce_otel_badge_sessions(otel_sessions):
        if not _session_tracking_contract_ok(raw_session):
            continue
        state = str(raw_session.get("state", "idle") or "idle").strip().lower()
        if state not in _OTEL_ACTIVE_SESSION_STATES:
            continue

        terminal_context = raw_session.get("terminal_context", {}) or {}
        window_id = raw_session.get("window_id", terminal_context.get("window_id"))
        try:
            window_id_int = int(window_id)
        except (TypeError, ValueError):
            # Focus/switch actions require a concrete window target.
            continue

        window_data = window_lookup.get(window_id_int, {})
        if not window_data:
            # Ignore stale OTEL records that point to windows no longer present
            # in the current daemon snapshot.
            continue
        if not _window_matches_session_binding(window_data, raw_session):
            continue
        project_labels = _resolve_session_project_labels(
            raw_session,
            window_project=str(window_data.get("project") or ""),
        )
        session_project = str(project_labels.get("session_project") or "").strip()
        display_project = str(project_labels.get("display_project") or "").strip()
        focus_project = str(project_labels.get("focus_project") or "").strip()
        project_source = str(project_labels.get("project_source") or "window_fallback")
        tool = str(raw_session.get("tool", "unknown") or "unknown").strip() or "unknown"

        tmux_session = str(terminal_context.get("tmux_session") or "")
        tmux_window = str(terminal_context.get("tmux_window") or "")
        tmux_pane = str(terminal_context.get("tmux_pane") or "")
        pty = str(terminal_context.get("pty") or "")
        host_name = str(terminal_context.get("host_name") or raw_session.get("host_name") or "")

        native_session_id = str(raw_session.get("native_session_id") or "")
        session_id = str(raw_session.get("session_id") or "")
        context_fingerprint = str(raw_session.get("context_fingerprint") or "")
        identity_raw = str(raw_session.get("identity_confidence") or "")
        confidence_level = _identity_confidence_level(identity_raw)
        updated_at = str(raw_session.get("updated_at") or "")
        updated_epoch = _parse_timestamp_to_epoch(updated_at)
        pending_tools = int(raw_session.get("pending_tools", 0) or 0)
        is_streaming = bool(raw_session.get("is_streaming", False))
        stale_age_seconds = int(max(0.0, now_epoch - updated_epoch)) if updated_epoch else 0
        stale = state in {"idle", "completed"} and stale_age_seconds >= _AI_SESSION_STALE_THRESHOLD_SECONDS
        stage_fields = _normalize_stage_fields(
            {
                **raw_session,
                "otel_state": state,
                "review_pending": False,
                "stale": stale,
                "stale_age_seconds": stale_age_seconds,
            },
            now_epoch=now_epoch,
        )
        stale_age_seconds = max(
            stale_age_seconds,
            int(stage_fields.get("activity_age_seconds") or stale_age_seconds),
        )
        stale = bool(stale or stage_fields.get("activity_freshness") == "stale")

        session_key = _build_active_session_key(
            tool=tool,
            project=session_project or display_project,
            window_id=window_id_int,
            tmux_pane=tmux_pane,
            pty=pty,
            tmux_window=tmux_window,
            native_session_id=native_session_id,
            session_id=session_id,
            context_fingerprint=context_fingerprint,
        )

        display_target = f"win {window_id_int}"
        if tmux_pane:
            display_target = f"pane {tmux_pane}"
        elif tmux_window:
            display_target = f"tmux {tmux_window}"
        elif pty:
            display_target = pty

        identity = _resolve_session_execution_identity(
            raw_session,
            window_data=window_data,
        )
        focus_identity = _window_tracking_identity(window_data)
        execution_mode = str(identity.get("execution_mode") or "local")
        focus_execution_mode = str(focus_identity.get("execution_mode") or execution_mode or "local")
        focus_connection_key = str(focus_identity.get("connection_key") or identity.get("connection_key") or "")
        focus_context_key = str(focus_identity.get("context_key") or "")

        session_payload = {
            "session_key": session_key,
            "display_tool": _OTEL_TOOL_LABELS.get(tool, tool if tool else "Unknown"),
            "display_project": display_project,
            "display_target": display_target,
            "otel_state": state,
            "project": session_project or display_project,
            "session_project": session_project,
            "window_project": str(window_data.get("project") or ""),
            "focus_project": focus_project,
            "project_source": project_source,
            "project_path": str(raw_session.get("project_path") or ""),
            "window_id": window_id_int,
            "execution_mode": execution_mode,
            "connection_key": str(identity.get("connection_key") or ""),
            "identity_key": str(identity.get("identity_key") or ""),
            "context_key": str(identity.get("context_key") or ""),
            "host_alias": str(identity.get("host_alias") or ""),
            "focus_execution_mode": focus_execution_mode,
            "focus_connection_key": focus_connection_key,
            "focus_context_key": focus_context_key,
            "tmux_session": tmux_session,
            "tmux_window": tmux_window,
            "tmux_pane": tmux_pane,
            "pty": pty,
            "host_name": host_name,
            "native_session_id": native_session_id,
            "session_id": session_id,
            "context_fingerprint": context_fingerprint,
            "identity_confidence": identity_raw,
            "confidence_level": confidence_level,
            "trace_id": str(raw_session.get("trace_id") or ""),
            "pending_tools": pending_tools,
            "is_streaming": is_streaming,
            "state_seq": _safe_int(raw_session.get("state_seq"), 0),
            "status_reason": str(raw_session.get("status_reason") or ""),
            "stage": str(stage_fields.get("stage") or "idle"),
            "stage_label": str(stage_fields.get("stage_label") or "Idle"),
            "stage_detail": str(stage_fields.get("stage_detail") or ""),
            "stage_class": str(stage_fields.get("stage_class") or "stage-idle"),
            "stage_visual_state": str(stage_fields.get("stage_visual_state") or "idle"),
            "stage_rank": int(stage_fields.get("stage_rank") or 0),
            "stage_glyph": str(stage_fields.get("stage_glyph") or _AI_STAGE_GLYPHS.get(str(stage_fields.get("stage") or "idle"), "·")),
            "needs_user_action": bool(stage_fields.get("needs_user_action", False)),
            "user_action_reason": str(stage_fields.get("user_action_reason") or ""),
            "output_ready": bool(stage_fields.get("output_ready", False)),
            "output_unseen": bool(stage_fields.get("output_unseen", False)),
            "activity_freshness": str(stage_fields.get("activity_freshness") or "fresh"),
            "activity_age_seconds": int(stage_fields.get("activity_age_seconds") or stale_age_seconds),
            "activity_age_label": str(stage_fields.get("activity_age_label") or _format_activity_age(stale_age_seconds)),
            "identity_source": str(stage_fields.get("identity_source") or ""),
            "lifecycle_source": str(stage_fields.get("lifecycle_source") or ""),
            "updated_at": updated_at,
            "stale": stale,
            "stale_age_seconds": stale_age_seconds,
            "remote_source_stale": bool(raw_session.get("remote_source_stale", False)),
            "remote_source_age_seconds": int(raw_session.get("remote_source_age_seconds", 0) or 0),
            "pinned": False,
            "priority_score": int(stage_fields.get("stage_rank") or _OTEL_STATE_PRIORITY.get(state, 0)),
            "tool": tool,
            "review_pending": False,
            "review_state": "normal",
            "finished_at": None,
            "seen_at": None,
            "synthetic": False,
        }

        existing = merged_by_key.get(session_key)
        if existing is None:
            merged_by_key[session_key] = (dict(raw_session), session_payload)
            continue

        existing_raw, _ = existing
        if _otel_badge_score(raw_session) > _otel_badge_score(existing_raw):
            merged_by_key[session_key] = (dict(raw_session), session_payload)

    active_sessions = [payload for _, payload in merged_by_key.values()]
    active_sessions.sort(
        key=lambda session: (
            int(focused_window_id is not None and session.get("window_id") == focused_window_id),
            int(
                bool(active_project_name)
                and str(session.get("display_project") or session.get("project") or "").strip() == active_project_name
            ),
            int(session.get("stage_rank", 0) or 0),
            str(session.get("updated_at") or ""),
            str(session.get("session_key") or ""),
        ),
        reverse=True,
    )
    return active_sessions


def _apply_ai_session_mru_order(
    active_sessions: List[Dict[str, Any]],
    mru_keys: Optional[List[str]] = None,
) -> List[Dict[str, Any]]:
    """Return active sessions reordered by MRU key list."""
    if not active_sessions:
        return []
    mru_keys = mru_keys or []
    if not mru_keys:
        return list(active_sessions)

    by_key = {
        str(session.get("session_key") or ""): session
        for session in active_sessions
        if str(session.get("session_key") or "")
    }
    ordered: List[Dict[str, Any]] = []
    used: set[str] = set()

    for key in mru_keys:
        session = by_key.get(str(key))
        if session is None:
            continue
        ordered.append(session)
        used.add(str(key))

    for session in active_sessions:
        key = str(session.get("session_key") or "")
        if not key or key in used:
            continue
        ordered.append(session)

    return ordered


def _apply_pinned_session_order(
    active_sessions: List[Dict[str, Any]],
    pinned_keys: Optional[List[str]] = None,
) -> List[Dict[str, Any]]:
    """Keep pinned sessions first while preserving relative order."""
    if not active_sessions:
        return []
    pinned_set = {str(key) for key in (pinned_keys or []) if str(key)}

    pinned_items: List[Dict[str, Any]] = []
    unpinned_items: List[Dict[str, Any]] = []
    for session in active_sessions:
        key = str(session.get("session_key") or "")
        if key and key in pinned_set:
            pinned_items.append(session)
        else:
            unpinned_items.append(session)
    return pinned_items + unpinned_items


def _review_entry_is_pending(entry: Dict[str, Any]) -> bool:
    finish_marker = str(entry.get("finish_marker") or "")
    seen_marker = str(entry.get("seen_marker") or "")
    return bool(finish_marker and seen_marker != finish_marker)


def _update_review_entry_from_session(
    entry: Dict[str, Any],
    session: Dict[str, Any],
    now_epoch: int,
) -> tuple[Dict[str, Any], bool]:
    """Apply current session metadata to review ledger entry."""
    changed = False
    state = str(session.get("otel_state") or "idle")
    marker = _build_review_finish_marker(session)
    finished_at = _session_updated_epoch(session, now_epoch)

    def _assign(key: str, value: Any) -> None:
        nonlocal changed
        if entry.get(key) != value:
            entry[key] = value
            changed = True

    _assign("project", str(session.get("project") or ""))
    _assign("session_project", str(session.get("session_project") or session.get("project") or ""))
    _assign("window_project", str(session.get("window_project") or ""))
    _assign("focus_project", str(session.get("focus_project") or session.get("window_project") or session.get("project") or ""))
    _assign("display_project", str(session.get("display_project") or session.get("project") or ""))
    _assign("project_source", str(session.get("project_source") or "window_fallback"))
    _assign("window_id", _safe_int(session.get("window_id"), 0))
    _assign("execution_mode", str(session.get("execution_mode") or "local"))
    _assign("connection_key", str(session.get("connection_key") or ""))
    _assign("identity_key", str(session.get("identity_key") or ""))
    _assign("context_key", str(session.get("context_key") or ""))
    _assign("host_alias", str(session.get("host_alias") or ""))
    _assign("focus_execution_mode", str(session.get("focus_execution_mode") or session.get("execution_mode") or "local"))
    _assign("focus_connection_key", str(session.get("focus_connection_key") or session.get("connection_key") or ""))
    _assign("focus_context_key", str(session.get("focus_context_key") or ""))
    _assign("tmux_session", str(session.get("tmux_session") or ""))
    _assign("tmux_window", str(session.get("tmux_window") or ""))
    _assign("tmux_pane", str(session.get("tmux_pane") or ""))
    _assign("pty", str(session.get("pty") or ""))
    _assign("tool", str(session.get("tool") or "unknown"))
    _assign("display_tool", str(session.get("display_tool") or _OTEL_TOOL_LABELS.get(str(session.get("tool") or "unknown"), str(session.get("tool") or "unknown"))))
    _assign("display_target", str(session.get("display_target") or ""))
    previous_state = str(entry.get("last_state") or "").strip().lower()
    _assign("last_state", state)
    if state == "completed" and marker:
        if str(entry.get("finish_marker") or "") != marker:
            _assign("finish_marker", marker)
            _assign("finished_at", finished_at)
            # New completion cycle should require fresh acknowledgement.
            if str(entry.get("seen_marker") or "") == marker:
                _assign("seen_at", finished_at)
            _assign("expires_at", finished_at + _AI_SESSION_REVIEW_TTL_SECONDS)
    elif state == "idle" and marker:
        # Idle-only sessions (for example, process-heartbeat placeholders) should
        # not create review work. Initialize finish markers on idle only when this
        # session was previously active/completing and we do not already have a
        # completion marker.
        if not str(entry.get("finish_marker") or "") and previous_state in {"working", "attention", "completed"}:
            _assign("finish_marker", marker)
            _assign("finished_at", finished_at)
            _assign("expires_at", finished_at + _AI_SESSION_REVIEW_TTL_SECONDS)
    elif state in {"working", "attention"}:
        finish_marker = str(entry.get("finish_marker") or "")
        seen_marker = str(entry.get("seen_marker") or "")
        if finish_marker and seen_marker != finish_marker:
            _assign("seen_marker", finish_marker)
            _assign("seen_at", now_epoch)

    # Keep a write timestamp only when meaningful review-state fields changed.
    if changed:
        entry["updated_at"] = now_epoch

    return entry, changed


def _apply_review_lifecycle(
    active_sessions: List[Dict[str, Any]],
    window_lookup: Dict[int, Dict[str, Any]],
    focused_window_id: Optional[int],
) -> tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Enrich sessions with finished/unseen review lifecycle + synthetic retention.
    """
    review_state = load_ai_session_review_state()
    review_sessions_raw = review_state.get("sessions", {})
    review_sessions: Dict[str, Dict[str, Any]] = (
        {str(k): v for k, v in review_sessions_raw.items() if str(k).strip() and isinstance(v, dict)}
        if isinstance(review_sessions_raw, dict)
        else {}
    )
    now_epoch = int(time.time())
    changed = False
    live_anchor_keys = {
        anchor_key
        for anchor_key in (_session_anchor_key(session) for session in active_sessions)
        if anchor_key
    }

    # Apply explicit "seen" events emitted by focus actions.
    for event in consume_ai_session_seen_events():
        key = str(event.get("session_key") or "").strip()
        if not key:
            continue
        entry = review_sessions.get(key)
        if not isinstance(entry, dict):
            continue
        finish_marker = str(entry.get("finish_marker") or "")
        requested_marker = str(event.get("finish_marker") or "")
        if not finish_marker:
            continue
        if requested_marker and requested_marker != finish_marker:
            continue
        ts = _safe_int(event.get("timestamp"), now_epoch)
        if str(entry.get("seen_marker") or "") != finish_marker:
            entry["seen_marker"] = finish_marker
            entry["seen_at"] = ts
            entry["updated_at"] = ts
            changed = True

    live_keys: set[str] = set()
    for session in active_sessions:
        key = str(session.get("session_key") or "").strip()
        if not key:
            continue
        live_keys.add(key)
        state = str(session.get("otel_state") or "idle")
        if state not in _OTEL_ACTIVE_SESSION_STATES:
            continue
        entry = dict(review_sessions.get(key, {}))
        entry, entry_changed = _update_review_entry_from_session(entry, session, now_epoch)
        review_sessions[key] = entry
        changed = changed or entry_changed

    # Passive "seen" detection for manual focus navigation.
    if focused_window_id is not None:
        focused_window = window_lookup.get(focused_window_id, {})
        focused_candidates = [
            (key, entry)
            for key, entry in review_sessions.items()
            if _review_entry_is_pending(entry)
            and _safe_int(entry.get("window_id"), 0) == focused_window_id
            and isinstance(focused_window, dict)
            and _window_matches_session_binding(focused_window, entry)
        ]
        if focused_candidates:
            requires_tmux = any(str(entry.get("tmux_pane") or "") for _, entry in focused_candidates)
            tmux_active_by_session = _list_tmux_active_panes_by_session() if requires_tmux else {}
            for _, entry in focused_candidates:
                finish_marker = str(entry.get("finish_marker") or "")
                if not finish_marker:
                    continue
                target_pane = str(entry.get("tmux_pane") or "")
                if target_pane:
                    session_name = str(entry.get("tmux_session") or "")
                    if not session_name:
                        continue
                    if tmux_active_by_session.get(session_name) != target_pane:
                        continue
                entry["seen_marker"] = finish_marker
                entry["seen_at"] = now_epoch
                entry["updated_at"] = now_epoch
                changed = True

    # If a session disappears without a terminal completion event, preserve it
    # as finished-unseen after a short grace period.
    for key, entry in review_sessions.items():
        if key in live_keys:
            continue
        if _safe_int(entry.get("finished_at"), 0) > 0:
            continue

        last_state = str(entry.get("last_state") or "").strip().lower()
        if last_state not in _OTEL_ACTIVE_SESSION_STATES:
            continue

        last_update = _safe_int(entry.get("updated_at"), 0)
        if last_update <= 0:
            continue
        if now_epoch - last_update < _AI_SESSION_REVIEW_DISAPPEAR_GRACE_SECONDS:
            continue

        finish_marker = str(entry.get("finish_marker") or "")
        if not finish_marker:
            marker_basis = "|".join([
                key,
                str(_safe_int(entry.get("window_id"), 0)),
                str(entry.get("tmux_pane") or ""),
                str(last_update),
            ])
            finish_marker = hashlib.sha1(marker_basis.encode("utf-8")).hexdigest()
            entry["finish_marker"] = finish_marker

        entry["finished_at"] = last_update
        entry["expires_at"] = last_update + _AI_SESSION_REVIEW_TTL_SECONDS
        if last_state in {"working", "attention"}:
            entry["last_state"] = "idle"
        if str(entry.get("seen_marker") or "") == finish_marker:
            entry["seen_at"] = last_update
        entry["updated_at"] = now_epoch
        changed = True

    # Prune expired or non-actionable entries, then synthesize unseen sessions
    # for contexts where OTEL session already disappeared.
    synthetic_sessions: List[Dict[str, Any]] = []
    delete_keys: List[str] = []
    for key, entry in review_sessions.items():
        finished_at = _safe_int(entry.get("finished_at"), 0)
        if finished_at <= 0:
            continue
        expires_at = _safe_int(entry.get("expires_at"), finished_at + _AI_SESSION_REVIEW_TTL_SECONDS)
        if expires_at <= now_epoch:
            delete_keys.append(key)
            changed = True
            continue

        if not _review_entry_is_pending(entry):
            continue

        window_id = _safe_int(entry.get("window_id"), 0)
        window_data = window_lookup.get(window_id)
        if window_id <= 0 or not isinstance(window_data, dict):
            # Unactionable orphan: drop instead of retaining forever.
            delete_keys.append(key)
            changed = True
            continue
        if not _window_matches_session_binding(window_data, entry):
            delete_keys.append(key)
            changed = True
            continue
        if key in live_keys:
            continue
        if _session_anchor_key(entry) in live_anchor_keys:
            continue

        state = str(entry.get("last_state") or "completed").strip().lower()
        if state not in {"completed", "idle"}:
            state = "completed"
        tool = str(entry.get("tool") or "unknown").strip() or "unknown"
        project = str(entry.get("project") or entry.get("session_project") or "unknown")
        window_project = str(entry.get("window_project") or window_data.get("project") or "")
        focus_project = str(entry.get("focus_project") or window_project or project)
        tmux_session = str(entry.get("tmux_session") or "")
        tmux_window = str(entry.get("tmux_window") or "")
        tmux_pane = str(entry.get("tmux_pane") or "")
        pty = str(entry.get("pty") or "")
        execution_mode = str(entry.get("execution_mode") or "local").strip().lower()
        if execution_mode not in {"local", "ssh"}:
            execution_mode = "local"
        connection_key = str(entry.get("connection_key") or "")
        identity_key = str(entry.get("identity_key") or "")
        context_key = str(entry.get("context_key") or "")
        host_alias = str(entry.get("host_alias") or "")
        focus_execution_mode = str(entry.get("focus_execution_mode") or execution_mode)
        focus_connection_key = str(entry.get("focus_connection_key") or connection_key)
        focus_context_key = str(entry.get("focus_context_key") or "")
        display_target = str(entry.get("display_target") or "")
        if not display_target:
            if tmux_pane:
                display_target = f"pane {tmux_pane}"
            elif tmux_window:
                display_target = f"tmux {tmux_window}"
            elif pty:
                display_target = pty
            else:
                display_target = f"win {window_id}"

        stale_age_seconds = max(0, now_epoch - finished_at)
        stage = "output_ready"
        synthetic_sessions.append({
            "session_key": key,
            "display_tool": str(entry.get("display_tool") or _OTEL_TOOL_LABELS.get(tool, tool)),
            "display_project": str(entry.get("display_project") or project),
            "display_target": display_target,
            "otel_state": state,
            "stage": stage,
            "stage_label": _AI_STAGE_LABELS[stage],
            "stage_detail": "Unread output retained",
            "stage_class": f"stage-{stage}",
            "stage_visual_state": "completed",
            "stage_rank": _AI_STAGE_RANKS[stage],
            "stage_glyph": _AI_STAGE_GLYPHS[stage],
            "needs_user_action": False,
            "user_action_reason": "",
            "output_ready": True,
            "output_unseen": True,
            "activity_freshness": "stale" if stale_age_seconds >= _AI_SESSION_STALE_THRESHOLD_SECONDS else "warm",
            "activity_age_seconds": stale_age_seconds,
            "activity_age_label": _format_activity_age(stale_age_seconds),
            "identity_source": "review",
            "lifecycle_source": "review",
            "project": project,
            "session_project": project,
            "window_project": window_project,
            "focus_project": focus_project,
            "project_source": str(entry.get("project_source") or "review"),
            "window_id": window_id,
            "execution_mode": execution_mode,
            "connection_key": connection_key,
            "identity_key": identity_key,
            "context_key": context_key,
            "host_alias": host_alias,
            "focus_execution_mode": focus_execution_mode,
            "focus_connection_key": focus_connection_key,
            "focus_context_key": focus_context_key,
            "tmux_session": tmux_session,
            "tmux_window": tmux_window,
            "tmux_pane": tmux_pane,
            "pty": pty,
            "host_name": "",
            "native_session_id": "",
            "session_id": "",
            "context_fingerprint": "",
            "identity_confidence": "review",
            "confidence_level": "low",
            "trace_id": "",
            "pending_tools": 0,
            "is_streaming": False,
            "state_seq": 0,
            "status_reason": "finished_unseen_retained",
            "updated_at": datetime.fromtimestamp(finished_at).isoformat(),
            "stale": state in {"idle", "completed"} and stale_age_seconds >= _AI_SESSION_STALE_THRESHOLD_SECONDS,
            "stale_age_seconds": stale_age_seconds,
            "pinned": False,
            "priority_score": _OTEL_STATE_PRIORITY.get(state, 0),
            "tool": tool,
            "review_pending": True,
            "review_state": "finished_unseen",
            "finished_at": finished_at,
            "seen_at": None,
            "synthetic": True,
        })

    for key in delete_keys:
        review_sessions.pop(key, None)

    sessions_out = list(active_sessions) + synthetic_sessions
    for session in sessions_out:
        key = str(session.get("session_key") or "").strip()
        entry = review_sessions.get(key, {})
        pending = _review_entry_is_pending(entry) if isinstance(entry, dict) else False
        finish_marker = str(entry.get("finish_marker") or "") if isinstance(entry, dict) else ""
        session["review_pending"] = pending
        session["review_state"] = "finished_unseen" if pending else "normal"
        session["finish_marker"] = finish_marker
        finished_at = _safe_int(entry.get("finished_at"), 0) if isinstance(entry, dict) else 0
        session["finished_at"] = finished_at if finished_at > 0 else None
        seen_at = _safe_int(entry.get("seen_at"), 0) if isinstance(entry, dict) else 0
        session["seen_at"] = seen_at if seen_at > 0 else None
        stage_fields = _normalize_stage_fields(session, now_epoch=float(now_epoch))
        session.update(stage_fields)
        session["priority_score"] = int(stage_fields.get("stage_rank") or session.get("priority_score") or 0)

    # Keep bounded review file size while preserving actionable pending items.
    if len(review_sessions) > _AI_SESSION_REVIEW_MAX_ENTRIES:
        ranked = sorted(
            review_sessions.items(),
            key=lambda item: (
                int(_review_entry_is_pending(item[1])),
                _safe_int(item[1].get("finished_at"), 0),
                _safe_int(item[1].get("updated_at"), 0),
            ),
            reverse=True,
        )
        keep_keys = {key for key, _ in ranked[:_AI_SESSION_REVIEW_MAX_ENTRIES]}
        review_sessions = {key: value for key, value in review_sessions.items() if key in keep_keys}
        changed = True

    if changed:
        save_ai_session_review_state({
            "schema_version": "1",
            "sessions": review_sessions,
            "updated_at": now_epoch,
        })

    return sessions_out, review_sessions


def _merge_review_state_into_window_badges(
    all_windows: List[Dict[str, Any]],
    sessions: List[Dict[str, Any]],
) -> None:
    """Annotate per-window OTEL badges with review lifecycle flags."""
    by_session_key = {
        str(session.get("session_key") or ""): session
        for session in sessions
        if str(session.get("session_key") or "")
    }
    synthetic_by_window: Dict[int, List[Dict[str, Any]]] = {}
    for session in sessions:
        if not bool(session.get("synthetic")):
            continue
        window_id = _safe_int(session.get("window_id"), 0)
        if window_id <= 0:
            continue
        synthetic_by_window.setdefault(window_id, []).append(session)

    for window in all_windows:
        window_id = _safe_int(window.get("id"), 0)
        badges = window.get("otel_badges", [])
        if not isinstance(badges, list):
            badges = []

        badge_keys: set[str] = set()
        badge_anchor_keys: set[str] = set()
        for badge in badges:
            if not isinstance(badge, dict):
                continue
            key = str(badge.get("session_key") or "").strip()
            if key:
                badge_keys.add(key)
            anchor_key = _session_anchor_key(badge)
            if anchor_key:
                badge_anchor_keys.add(anchor_key)
            session = by_session_key.get(key)
            if session is None:
                badge.setdefault("review_pending", False)
                badge.setdefault("review_state", "normal")
                badge.setdefault("finished_at", None)
                badge.setdefault("seen_at", None)
                badge.setdefault("synthetic", False)
                continue
            badge["review_pending"] = bool(session.get("review_pending", False))
            badge["review_state"] = str(session.get("review_state") or "normal")
            badge["finished_at"] = session.get("finished_at")
            badge["seen_at"] = session.get("seen_at")
            badge["synthetic"] = bool(session.get("synthetic", False))
            for field in (
                "stage",
                "stage_label",
                "stage_detail",
                "stage_class",
                "stage_visual_state",
                "stage_rank",
                "stage_glyph",
                "needs_user_action",
                "user_action_reason",
                "output_ready",
                "output_unseen",
                "activity_freshness",
                "activity_age_seconds",
                "activity_age_label",
                "identity_source",
                "lifecycle_source",
            ):
                if field in session:
                    badge[field] = session.get(field)

        for session in synthetic_by_window.get(window_id, []):
            key = str(session.get("session_key") or "")
            anchor_key = _session_anchor_key(session)
            if not key or key in badge_keys or (anchor_key and anchor_key in badge_anchor_keys):
                continue
            tool = str(session.get("tool") or "unknown")
            state = str(session.get("otel_state") or "completed")
            badges.append({
                "badge_key": f"review:{key}",
                "session_key": key,
                "session_id": "",
                "native_session_id": "",
                "context_fingerprint": "",
                "collision_group_id": "",
                "identity_confidence": "review",
                "confidence_level": "low",
                "otel_state": state,
                "stage": str(session.get("stage") or "output_ready"),
                "stage_label": str(session.get("stage_label") or "Ready"),
                "stage_detail": str(session.get("stage_detail") or "Unread output retained"),
                "stage_class": str(session.get("stage_class") or "stage-output_ready"),
                "stage_visual_state": str(session.get("stage_visual_state") or "completed"),
                "stage_rank": int(session.get("stage_rank") or _AI_STAGE_RANKS["output_ready"]),
                "stage_glyph": str(session.get("stage_glyph") or _AI_STAGE_GLYPHS["output_ready"]),
                "needs_user_action": False,
                "user_action_reason": "",
                "output_ready": True,
                "output_unseen": True,
                "activity_freshness": str(session.get("activity_freshness") or "warm"),
                "activity_age_seconds": _safe_int(session.get("activity_age_seconds"), 0),
                "activity_age_label": str(session.get("activity_age_label") or _format_activity_age(_safe_int(session.get("activity_age_seconds"), 0))),
                "identity_source": "review",
                "lifecycle_source": "review",
                "otel_tool": tool,
                "project": str(session.get("project") or window.get("project") or ""),
                "pid": None,
                "trace_id": "",
                "pending_tools": 0,
                "is_streaming": False,
                "state_seq": 0,
                "status_reason": "finished_unseen_retained",
                "stale": bool(session.get("stale", False)),
                "stale_age_seconds": _safe_int(session.get("stale_age_seconds"), 0),
                "execution_mode": str(session.get("execution_mode") or "local"),
                "connection_key": str(session.get("connection_key") or ""),
                "identity_key": str(session.get("identity_key") or ""),
                "context_key": str(session.get("context_key") or ""),
                "host_alias": str(session.get("host_alias") or ""),
                "focus_execution_mode": str(session.get("focus_execution_mode") or session.get("execution_mode") or "local"),
                "focus_connection_key": str(session.get("focus_connection_key") or session.get("connection_key") or ""),
                "focus_context_key": str(session.get("focus_context_key") or ""),
                "host_name": "",
                "window_id": window_id,
                "session_project": str(session.get("session_project") or session.get("project") or ""),
                "window_project": str(session.get("window_project") or window.get("project") or ""),
                "focus_project": str(
                    session.get("focus_project")
                    or session.get("window_project")
                    or window.get("project")
                    or session.get("project")
                    or ""
                ),
                "display_project": str(session.get("display_project") or session.get("project") or ""),
                "project_source": str(session.get("project_source") or "review"),
                "tmux_session": str(session.get("tmux_session") or ""),
                "tmux_window": str(session.get("tmux_window") or ""),
                "tmux_pane": str(session.get("tmux_pane") or ""),
                "pty": str(session.get("pty") or ""),
                "review_pending": True,
                "review_state": "finished_unseen",
                "finished_at": session.get("finished_at"),
                "seen_at": None,
                "synthetic": True,
            })
            if anchor_key:
                badge_anchor_keys.add(anchor_key)

        badges.sort(
            key=lambda b: (
                int(bool(b.get("review_pending", False))),
                _OTEL_STATE_PRIORITY.get(str(b.get("otel_state") or "idle"), 0),
                _safe_int(b.get("finished_at"), 0),
            ),
            reverse=True,
        )
        window["otel_badges"] = [badge for badge in badges if _should_render_otel_badge(badge)]


def _active_ai_session_sort_rank(session: Dict[str, Any]) -> int:
    """Sort rank for active AI rail with finished-unseen support."""
    return int(session.get("stage_rank", 0) or 0)


def _should_render_ai_session(session: Dict[str, Any]) -> bool:
    """Visible rail sessions: active work, pending review, or pinned."""
    stage = str(session.get("stage") or "").strip().lower()
    if stage in {"starting", "thinking", "tool_running", "streaming", "waiting_input", "attention"}:
        return True
    if bool(session.get("output_unseen", False) or session.get("review_pending", False)):
        return True
    if bool(session.get("pinned", False)):
        return True
    return False


def _should_render_otel_badge(badge: Dict[str, Any]) -> bool:
    """Visible window badges: active work or pending review."""
    stage = str(badge.get("stage") or "").strip().lower()
    if stage in {"starting", "thinking", "tool_running", "streaming", "waiting_input", "attention"}:
        return True
    return bool(badge.get("output_unseen", False) or badge.get("review_pending", False))


def transform_window(
    window: Dict[str, Any],
    badge_state: Optional[Dict[str, Any]] = None,
    otel_sessions_by_window: Optional[Dict[int, List[Dict[str, Any]]]] = None
) -> Dict[str, Any]:
    """
    Transform daemon window data to Eww-friendly schema.

    Args:
        window: Window data from daemon (Sway IPC format)
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)
        otel_sessions_by_window: Optional dict mapping window IDs (as int) to LIST of OTEL sessions
                     (Feature 136: Multi-indicator support - multiple AI sessions per window)

    Returns:
        WindowInfo dict matching data-model.md specification
    """
    app_id = window.get("app_id", "")
    window_class = window.get("class", "")

    app_name = window_class if window_class else app_id if app_id else "unknown"

    # Use full app_id as display_name (user preference)
    display_name = app_id if app_id else window_class if window_class else "unknown"

    # Resolve icon from app registry
    icon_path = resolve_icon(app_id, window_class)

    # Derive scope from marks - check if any mark starts with "scoped:"
    # Feature 101: Unified mark format - scratchpad terminals also use scoped: prefix
    marks = window.get("marks", [])
    is_scoped_window = any(str(m).startswith("scoped:") for m in marks)
    scope = "scoped" if is_scoped_window else "global"

    # PWA detection - workspaces 50+ are PWAs per CLAUDE.md specification
    # Note: workspace field may be string (including "scratchpad") or int from daemon
    workspace_raw = window.get("workspace", 1)
    try:
        workspace_num = int(workspace_raw) if workspace_raw else 1
    except (ValueError, TypeError):
        # Handle "scratchpad" or other non-numeric workspace values
        workspace_num = 0
    is_pwa = workspace_num >= 50

    # Generate composite state classes (floating, hidden, focused)
    state_classes = get_window_state_classes(window)

    # Get geometry for detail view
    geometry = window.get("geometry", {})

    # Build window data dict
    window_data = {
        "id": window.get("id", 0),
        "pid": window.get("pid", 0),
        "app_id": app_id,
        "app_name": app_name,
        "display_name": display_name,
        "class": window.get("class", ""),
        "instance": window.get("instance", ""),
        # Keep full title; Eww widget handles runtime truncation based on row width.
        "title": window.get("title", ""),
        "full_title": window.get("title", ""),  # Keep full title for detail view
        "project": window.get("project", ""),
        "scope": scope,
        "icon_path": icon_path,
        "workspace": workspace_raw,  # Keep original value ("scratchpad", "1", etc.)
        "workspace_number": workspace_num,  # Numeric workspace for badges
        "output": window.get("output", ""),
        "marks": window.get("marks", []),
        # Preserve daemon-provided execution metadata for identity-safe grouping.
        "i3pm_execution_mode": str(window.get("execution_mode") or ""),
        "i3pm_connection_key": str(window.get("connection_key") or ""),
        "i3pm_context_key": str(window.get("context_key") or ""),
        "i3pm_remote_enabled": window.get("remote_enabled"),
        "i3pm_remote_target": str(window.get("remote_target") or ""),
        "i3pm_remote_user": str(window.get("remote_user") or ""),
        "i3pm_remote_host": str(window.get("remote_host") or ""),
        "i3pm_remote_port": window.get("remote_port"),
        "i3pm_remote_dir": str(window.get("remote_dir") or ""),
        "i3pm_remote_session_name": str(window.get("remote_session_name") or ""),
        "floating": window.get("floating", False),
        "hidden": window.get("hidden", False),
        "focused": window.get("focused", False),
        "fullscreen": window.get("fullscreen", False),
        "is_pwa": is_pwa,
        "state_classes": state_classes,
        # Geometry for detail view
        "geometry_x": geometry.get("x", 0),
        "geometry_y": geometry.get("y", 0),
        "geometry_width": geometry.get("width", 0),
        "geometry_height": geometry.get("height", 0),
        # Feature 095: Notification badge data (if present)
        # badge_state is dict mapping window ID (string) to {"count": "1", "timestamp": ..., "source": "..."}
        "badge": badge_state.get(str(window.get("id", 0)), {}) if badge_state else {},
        # Feature 136: OTEL badges array for multi-indicator display
        # otel_sessions_by_window maps window_id (int) to LIST of session dicts
        "otel_badges": _build_otel_badges(
            otel_sessions_by_window.get(window.get("id", 0)) if otel_sessions_by_window else None,
            str(window.get("project") or ""),
            window_data=window,
        ),
    }

    # Generate Pango-markup colorized JSON for hover tooltip
    # Include all fields except redundant/computed ones
    json_data = {
        "id": window_data["id"],
        "pid": window_data["pid"],
        "app_id": window_data["app_id"],
        "class": window_data["class"],
        "instance": window_data["instance"],
        "title": window_data["full_title"],
        "project": window_data["project"],
        "scope": window_data["scope"],
        "workspace": window_data["workspace"],
        "output": window_data["output"],
        "floating": window_data["floating"],
        "focused": window_data["focused"],
        "hidden": window_data["hidden"],
        "fullscreen": window_data["fullscreen"],
        "is_pwa": window_data["is_pwa"],
        "geometry": {
            "x": window_data["geometry_x"],
            "y": window_data["geometry_y"],
            "width": window_data["geometry_width"],
            "height": window_data["geometry_height"]
        },
        "marks": window_data["marks"]
    }

    # Note: json_repr, json_plain, json_base64 removed to reduce output size from ~200KB to ~20KB
    # These were causing "channel closed" errors due to large data transfers
    # If needed for copy functionality, generate on-demand via separate endpoint

    return window_data


def transform_workspace(
    workspace: Dict[str, Any],
    monitor_name: str,
    badge_state: Optional[Dict[str, Any]] = None,
    otel_sessions_by_window: Optional[Dict[int, List[Dict[str, Any]]]] = None
) -> Dict[str, Any]:
    """
    Transform daemon workspace data to Eww-friendly schema.

    Args:
        workspace: Workspace data from daemon
        monitor_name: Parent monitor name
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)
        otel_sessions_by_window: Optional dict mapping window IDs (as int) to LIST of OTEL sessions
                     (Feature 136: Multi-indicator support)

    Returns:
        WorkspaceInfo dict matching data-model.md specification
    """
    windows = workspace.get("windows", [])
    transformed_windows = [transform_window(w, badge_state, otel_sessions_by_window) for w in windows]

    return {
        "number": workspace.get("num", workspace.get("number", 1)),
        "name": workspace.get("name", ""),
        "visible": workspace.get("visible", False),
        "focused": workspace.get("focused", False),
        "monitor": monitor_name,
        "window_count": len(transformed_windows),
        "windows": transformed_windows,
    }


def transform_monitor(
    output: Dict[str, Any],
    badge_state: Optional[Dict[str, Any]] = None,
    otel_sessions_by_window: Optional[Dict[int, List[Dict[str, Any]]]] = None
) -> Dict[str, Any]:
    """
    Transform daemon output/monitor data to Eww-friendly schema.

    Args:
        output: Output data from daemon (contains name, active status, workspaces)
        badge_state: Optional dict mapping window IDs (as strings) to badge metadata
                     (Feature 095: Visual Notification Badges)
        otel_sessions_by_window: Optional dict mapping window IDs (as int) to LIST of OTEL sessions
                     (Feature 136: Multi-indicator support)

    Returns:
        MonitorInfo dict matching data-model.md specification
    """
    monitor_name = output.get("name", "unknown")
    workspaces = output.get("workspaces", [])
    transformed_workspaces = [transform_workspace(ws, monitor_name, badge_state, otel_sessions_by_window) for ws in workspaces]

    # Determine if monitor has focused workspace
    has_focused = any(ws["focused"] for ws in transformed_workspaces)

    return {
        "name": monitor_name,
        "active": output.get("active", True),
        "focused": has_focused,
        "workspaces": transformed_workspaces,
    }


def validate_and_count(monitors: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Validate transformed data and compute summary counts.

    Args:
        monitors: List of transformed MonitorInfo dicts

    Returns:
        Dict with keys: monitor_count, workspace_count, window_count
    """
    monitor_count = len(monitors)
    workspace_count = sum(len(m["workspaces"]) for m in monitors)
    window_count = sum(
        ws["window_count"] for m in monitors for ws in m["workspaces"]
    )

    return {
        "monitor_count": monitor_count,
        "workspace_count": workspace_count,
        "window_count": window_count,
    }


def format_friendly_timestamp(timestamp: float) -> str:
    """
    Format Unix timestamp as friendly relative time.

    Args:
        timestamp: Unix timestamp (seconds since epoch)

    Returns:
        Human-friendly string like "Just now", "5 seconds ago", "2 minutes ago"
    """
    now = time.time()
    diff = int(now - timestamp)

    if diff < 5:
        return "Just now"
    elif diff < 60:
        return f"{diff} seconds ago"
    elif diff < 120:
        return "1 minute ago"
    elif diff < 3600:
        minutes = diff // 60
        return f"{minutes} minutes ago"
    elif diff < 7200:
        return "1 hour ago"
    elif diff < 86400:
        hours = diff // 3600
        return f"{hours} hours ago"
    else:
        days = diff // 86400
        return f"{days} day{'s' if days > 1 else ''} ago"


def _format_json_with_syntax_highlighting(data: Dict[str, Any]) -> str:
    """
    Format JSON with syntax highlighting using Pango markup (Feature 094: T021).

    Uses Catppuccin Mocha colors:
    - Keys: Blue (#89b4fa)
    - Strings: Green (#a6e3a1)
    - Numbers: Peach (#fab387)
    - Booleans: Yellow (#f9e2af)
    - Null: Subtext (#a6adc8)

    Args:
        data: Dictionary to format

    Returns:
        Pango markup string with syntax-highlighted JSON
    """
    import re

    # Pretty-print JSON with indentation
    json_str = json.dumps(data, indent=2, ensure_ascii=False)

    # Catppuccin Mocha colors
    COLOR_KEY = "#89b4fa"      # Blue
    COLOR_STRING = "#a6e3a1"   # Green
    COLOR_NUMBER = "#fab387"   # Peach
    COLOR_BOOLEAN = "#f9e2af"  # Yellow
    COLOR_NULL = "#a6adc8"     # Subtext

    # Escape XML special characters first
    json_str = json_str.replace("&", "&amp;")
    json_str = json_str.replace("<", "&lt;")
    json_str = json_str.replace(">", "&gt;")

    # Color JSON keys (property names in quotes before colon)
    json_str = re.sub(
        r'"([^"]+)"\s*:',
        rf'<span foreground="{COLOR_KEY}">"\1"</span>:',
        json_str
    )

    # Color string values (quotes not followed by colon)
    # This matches strings that are not keys
    def color_string_value(match):
        # Check if this string is followed by a colon (would be a key)
        full_text = match.string
        end_pos = match.end()
        # Look ahead to see if there's a colon after whitespace
        remaining = full_text[end_pos:].lstrip()
        if remaining.startswith(':'):
            return match.group(0)  # Don't color keys again
        return f'<span foreground="{COLOR_STRING}">{match.group(0)}</span>'

    json_str = re.sub(r'"[^"]*"', color_string_value, json_str)

    # Color numbers
    json_str = re.sub(
        r'\b(\d+\.?\d*)\b',
        rf'<span foreground="{COLOR_NUMBER}">\1</span>',
        json_str
    )

    # Color booleans
    json_str = re.sub(
        r'\b(true|false)\b',
        rf'<span foreground="{COLOR_BOOLEAN}">\1</span>',
        json_str
    )

    # Color null
    json_str = re.sub(
        r'\bnull\b',
        rf'<span foreground="{COLOR_NULL}">null</span>',
        json_str
    )

    return json_str


def _is_truthy(value: Any) -> bool:
    """Parse common truthy string/bool values."""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _format_remote_target(user: str, host: str, port: Any) -> str:
    """Format user/host/port into a compact SSH target string."""
    host = str(host or "").strip()
    if not host:
        return ""
    user = str(user or "").strip()
    user_part = f"{user}@" if user else ""
    port_part = str(port or 22).strip()
    return f"{user_part}{host}:{port_part}"


def _read_window_remote_env(pid: Any) -> Dict[str, str]:
    """
    Read I3PM remote environment variables from /proc/<pid>/environ.

    Returns only keys with prefix I3PM_REMOTE_ to keep parsing lightweight.
    """
    try:
        pid_int = int(pid)
    except (TypeError, ValueError):
        return {}

    if pid_int <= 0:
        return {}

    environ_path = Path("/proc") / str(pid_int) / "environ"
    try:
        raw = environ_path.read_bytes()
    except OSError:
        return {}

    remote_env: Dict[str, str] = {}
    for entry in raw.split(b"\0"):
        if not entry or b"=" not in entry:
            continue
        key_b, value_b = entry.split(b"=", 1)
        if not key_b.startswith(b"I3PM_REMOTE_"):
            continue
        try:
            key = key_b.decode("utf-8", errors="ignore")
            value = value_b.decode("utf-8", errors="ignore")
        except Exception:
            continue
        remote_env[key] = value

    return remote_env


def _normalize_remote_path(path: str, remote_user: str = "") -> str:
    """Normalize a filesystem path for stable comparisons."""
    raw = str(path or "").strip()
    if not raw:
        return ""

    # Expand home-shortcuts so profile paths like ~/repos/... match sesh output.
    if raw == "~":
        user = str(remote_user or os.environ.get("USER", "")).strip()
        raw = f"/home/{user}" if user else str(Path.home())
    elif raw.startswith("~/"):
        user = str(remote_user or os.environ.get("USER", "")).strip()
        home_prefix = f"/home/{user}" if user else str(Path.home())
        raw = f"{home_prefix}/{raw[2:]}"

    normalized = raw.rstrip("/")
    return normalized if normalized else "/"


def _extract_json_array(payload: str) -> List[Dict[str, Any]]:
    """Best-effort parse JSON array from noisy SSH command output."""
    text = str(payload or "").strip()
    if not text:
        return []

    try:
        parsed = json.loads(text)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
    except json.JSONDecodeError:
        pass

    start = text.find("[")
    end = text.rfind("]")
    if start < 0 or end <= start:
        return []
    try:
        parsed = json.loads(text[start:end + 1])
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
    except json.JSONDecodeError:
        return []

    return []


def _remote_profile_cache_key(profile: Dict[str, Any]) -> str:
    """Build a cache key for remote host/user/port."""
    host = str(profile.get("host", "")).strip()
    user = str(profile.get("user", "")).strip()
    port = str(profile.get("port", 22)).strip()
    return f"{user}@{host}:{port}"


def _fetch_remote_tmux_sessions(profile: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Fetch remote tmux-backed sesh entries via SSH.

    Returns list of dicts:
    [{"name": str, "path": str, "attached": bool, "windows": int}]
    """
    host = str(profile.get("host", "")).strip()
    user = str(profile.get("user", "")).strip()
    try:
        port = int(profile.get("port", 22))
    except (TypeError, ValueError):
        port = 22

    if not host:
        return []

    cache_key = _remote_profile_cache_key(profile)
    now = time.time()
    cached = REMOTE_SESH_CACHE.get(cache_key)
    if cached and (now - float(cached.get("timestamp", 0))) < REMOTE_SESH_CACHE_TTL_SECONDS:
        return list(cached.get("sessions", []))

    target = f"{user}@{host}" if user else host
    cmd: List[str] = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=2",
        "-o",
        "ServerAliveInterval=5",
        "-o",
        "ServerAliveCountMax=1",
    ]
    if port != 22:
        cmd.extend(["-p", str(port)])
    cmd.append(target)
    cmd.append("bash -lc 'command -v sesh >/dev/null 2>&1 && sesh list -j || echo []'")

    sessions: List[Dict[str, Any]] = []
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=6,
            check=True,
        )
        payload = _extract_json_array(result.stdout)
        for item in payload:
            if str(item.get("Src", "")).strip() != "tmux":
                continue
            name = str(item.get("Name", "")).strip()
            path = str(item.get("Path", "")).strip()
            if not name or not path:
                continue
            try:
                window_count = int(item.get("Windows", 0))
            except (TypeError, ValueError):
                window_count = 0
            sessions.append(
                {
                    "name": name,
                    "path": path,
                    "attached": bool(item.get("Attached", False)),
                    "windows": window_count,
                }
            )
    except Exception as e:
        logger.debug(f"Remote session fetch failed for {target}: {e}")
        sessions = []

    REMOTE_SESH_CACHE[cache_key] = {
        "timestamp": now,
        "sessions": sessions,
    }
    return sessions


def _build_remote_session_window(
    project_name: str,
    remote_target: str,
    remote_dir: str,
    session: Dict[str, Any],
    otel_sessions: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Create synthetic window payload for a remote tmux/sesh session."""
    seed = f"{project_name}|{remote_target}|{session.get('name', '')}"
    digest = hashlib.sha1(seed.encode("utf-8")).hexdigest()
    synthetic_id = -(10_000_000 + (int(digest[:12], 16) % 900_000_000))

    session_name = str(session.get("name", "")).strip()
    session_windows = int(session.get("windows", 0))
    attached = bool(session.get("attached", False))
    summary = f"tmux: {session_name}"
    if session_windows > 0:
        summary = f"{summary} • {session_windows} win"
    if attached:
        summary = f"{summary} • attached"

    identity = _connection_identity(True, remote_target)
    window_focus_data = {
        "project": project_name,
        "execution_mode": identity["execution_mode"],
        "connection_key": identity["connection_key"],
        "context_key": "",
    }

    return {
        "id": synthetic_id,
        "pid": 0,
        "app_id": "remote-sesh",
        "app_name": "remote-sesh",
        "display_name": f"ssh:{session_name}",
        "class": "remote-sesh",
        "instance": session_name,
        "title": summary,
        "full_title": summary,
        "project": project_name,
        "scope": "scoped",
        "icon_path": "",
        "workspace": "ssh",
        "workspace_number": 0,
        "output": "remote",
        "marks": [],
        "floating": False,
        "hidden": False,
        "focused": False,
        "fullscreen": False,
        "is_pwa": False,
        "state_classes": "window-remote-session",
        "geometry_x": 0,
        "geometry_y": 0,
        "geometry_width": 0,
        "geometry_height": 0,
        "badge": {},
        "otel_badges": _build_otel_badges(otel_sessions, project_name, window_data=window_focus_data),
        "project_remote_enabled": True,
        "project_remote_target": remote_target,
        "project_remote_dir": remote_dir,
        "execution_mode": identity["execution_mode"],
        "host_alias": identity["host_alias"],
        "connection_key": identity["connection_key"],
        "identity_key": identity["identity_key"],
        "is_remote_session": True,
        "remote_session_name": session_name,
        "remote_session_summary": summary,
        "monitor_name": "remote",
        "workspace_name": "ssh",
    }


def _project_session_suffix(project_name: str) -> str:
    """
    Convert qualified project name to common sesh/tmux name suffix.

    Example:
      PittampalliOrg/stacks:main -> stacks/main
    """
    name = str(project_name or "").strip()
    if not name:
        return ""
    if ":" not in name:
        return ""
    repo_part, branch = name.split(":", 1)
    repo_name = repo_part.split("/")[-1]
    if not repo_name or not branch:
        return ""
    return f"{repo_name}/{branch}"


def _session_matches_profile(
    project_name: str,
    profile: Dict[str, Any],
    session: Dict[str, Any],
) -> bool:
    """Match a remote tmux session to a project profile using path + suffix heuristics."""
    remote_user = str(profile.get("user", "")).strip()
    remote_dir = _normalize_remote_path(str(profile.get("remote_dir", "")), remote_user)
    session_path = _normalize_remote_path(str(session.get("path", "")), remote_user)
    if remote_dir and session_path and session_path == remote_dir:
        return True

    # Handle prefix/symlink variations where sesh may report a resolved path.
    if remote_dir and session_path:
        if session_path.endswith(remote_dir) or remote_dir.endswith(session_path):
            return True

    suffix = _project_session_suffix(project_name)
    session_name = str(session.get("name", "")).strip()
    if suffix and session_name.endswith(suffix):
        return True

    # Accept common legacy/new naming variants (e.g. stacks/main vs stacks_main).
    if (
        suffix
        and _normalize_session_name_key(session_name)
        == _normalize_session_name_key(suffix)
    ):
        return True

    return False


def _normalize_connection_key(value: str) -> str:
    """Normalize connection identity for stable, collision-resistant IDs."""
    raw = str(value or "").strip().lower()
    if not raw:
        return "unknown"
    return re.sub(r"[^a-z0-9@._:-]+", "-", raw)


def _local_connection_key() -> str:
    """Return a stable local-host identity used in project card IDs."""
    host = (
        os.environ.get("I3PM_LOCAL_HOST_ALIAS")
        or os.environ.get("HOSTNAME")
        or socket.gethostname()
    )
    host = str(host).strip().lower() or "localhost"
    return f"local@{_normalize_connection_key(host)}"


def _connection_identity(remote_enabled: bool, remote_target: str = "") -> Dict[str, str]:
    """
    Build canonical execution identity fields for project/worktree cards.

    Returns:
      - execution_mode: local|ssh
      - host_alias: local host alias or ssh target
      - connection_key: normalized connection identity
      - identity_key: execution_mode:connection_key
    """
    if remote_enabled:
        host_alias = str(remote_target or "").strip() or "unknown"
        connection_key = _normalize_connection_key(host_alias)
        execution_mode = "ssh"
    else:
        host_alias = (
            str(os.environ.get("I3PM_LOCAL_HOST_ALIAS") or os.environ.get("HOSTNAME") or socket.gethostname())
            .strip()
            .lower()
            or "localhost"
        )
        connection_key = _local_connection_key()
        execution_mode = "local"

    return {
        "execution_mode": execution_mode,
        "host_alias": host_alias,
        "connection_key": connection_key,
        "identity_key": f"{execution_mode}:{connection_key}",
    }


def _project_card_key(project_name: str, remote_enabled: bool, remote_target: str = "") -> str:
    """Build a stable project-card identifier for local/SSH split cards."""
    identity = _connection_identity(remote_enabled, remote_target)
    variant = "ssh" if identity.get("execution_mode") == "ssh" else "local"
    return f"{project_name}::{variant}::{identity['connection_key']}"


def _project_card_key_for_identity(project_name: str, identity: Dict[str, str]) -> str:
    """Build a stable project-card identifier from canonical identity payload."""
    mode = _normalize_execution_mode(identity.get("execution_mode"), default="local")
    if mode not in {"local", "ssh"}:
        mode = "local"
    variant = "ssh" if mode == "ssh" else "local"
    connection_key = str(identity.get("connection_key") or "").strip()
    if not connection_key:
        connection_key = _local_connection_key() if variant == "local" else "unknown"
    return f"{project_name}::{variant}::{connection_key}"


def _create_project_entry(
    *,
    project_name: str,
    remote_enabled: bool,
    remote_target: str = "",
    remote_directory: str = "",
    remote_profile_enabled: bool = False,
    remote_profile_target: str = "",
    remote_profile_directory: str = "",
    identity: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    """Create a project card entry for the windows overview."""
    home_str = str(Path.home())
    identity = identity or _connection_identity(remote_enabled, remote_target)
    variant = "ssh" if str(identity.get("execution_mode") or "") == "ssh" else "local"
    remote_enabled = variant == "ssh"
    remote_directory_display = remote_directory.replace(home_str, "~") if remote_directory else ""
    remote_profile_directory_display = (
        remote_profile_directory.replace(home_str, "~") if remote_profile_directory else ""
    )

    return {
        "card_id": _project_card_key_for_identity(project_name, identity),
        "name": project_name,
        "scope": "scoped",
        "variant": variant,
        "execution_mode": identity["execution_mode"],
        "host_alias": identity["host_alias"],
        "connection_key": identity["connection_key"],
        "identity_key": identity["identity_key"],
        "variant_label": "SSH" if variant == "ssh" else "LOCAL",
        "window_count": 0,
        # Active remote status (for badges) is based on actual window env.
        "remote_enabled": remote_enabled,
        "remote_target": remote_target,
        "remote_directory": remote_directory,
        "remote_directory_display": remote_directory_display,
        # Keep configured profile metadata available for debugging/tooltips.
        "remote_profile_enabled": remote_profile_enabled,
        "remote_profile_target": remote_profile_target,
        "remote_profile_directory": remote_profile_directory,
        "remote_profile_directory_display": remote_profile_directory_display,
        "has_local_variant": False,
        "has_remote_variant": False,
        "windows": [],
    }


def _refresh_variant_flags(projects: List[Dict[str, Any]]) -> None:
    """Mark whether each project has a paired local/SSH variant card."""
    variants_by_name: Dict[str, set[str]] = {}
    for project in projects:
        name = str(project.get("name", "")).strip()
        variant = str(project.get("variant", "")).strip()
        if not name or not variant:
            continue
        variants_by_name.setdefault(name, set()).add(variant)

    for project in projects:
        name = str(project.get("name", "")).strip()
        variants = variants_by_name.get(name, set())
        project["has_local_variant"] = "local" in variants
        project["has_remote_variant"] = "ssh" in variants


def _augment_projects_with_remote_sessions(
    projects_dict: Dict[str, Dict[str, Any]],
    remote_profiles: Optional[Dict[str, Dict[str, Any]]],
    otel_sessions: Optional[List[Dict[str, Any]]] = None,
) -> None:
    """
    Add synthetic window items for remote SSH tmux/sesh sessions.

    This makes active remote sessions visible even when no local Sway window is
    currently attached to them.
    """
    if not isinstance(remote_profiles, dict):
        return

    for project_name, profile in remote_profiles.items():
        if not isinstance(profile, dict) or not bool(profile.get("enabled", False)):
            continue

        remote_user = str(profile.get("user", "")).strip()
        remote_dir = _normalize_remote_path(str(profile.get("remote_dir", "")), remote_user)
        if not remote_dir:
            continue

        remote_target = _format_remote_target(
            profile.get("user", ""),
            profile.get("host", ""),
            profile.get("port", 22),
        )

        remote_sessions = _fetch_remote_tmux_sessions(profile)
        matching_sessions = [s for s in remote_sessions if _session_matches_profile(project_name, profile, s)]
        if not matching_sessions:
            continue

        remote_key = _project_card_key(project_name, True, remote_target)
        if remote_key not in projects_dict:
            projects_dict[remote_key] = _create_project_entry(
                project_name=project_name,
                remote_enabled=True,
                remote_target=remote_target,
                remote_directory=remote_dir,
                remote_profile_enabled=True,
                remote_profile_target=remote_target,
                remote_profile_directory=remote_dir,
            )

        project_entry = projects_dict[remote_key]
        project_entry["remote_enabled"] = True
        if remote_target:
            project_entry["remote_target"] = remote_target
        project_entry["remote_directory"] = remote_dir
        project_entry["remote_directory_display"] = remote_dir.replace(str(Path.home()), "~")

        existing_ids = {int(w.get("id", 0)) for w in project_entry.get("windows", [])}
        existing_session_names = {
            _normalize_session_name_key(str(w.get("remote_session_name", "")).strip())
            for w in project_entry.get("windows", [])
            if str(w.get("remote_session_name", "")).strip()
        }
        for session in matching_sessions:
            synthetic_window = _build_remote_session_window(
                project_name,
                remote_target,
                remote_dir,
                session,
                None,
            )
            synthetic_id = int(synthetic_window["id"])
            synthetic_session_name = _normalize_session_name_key(
                str(synthetic_window.get("remote_session_name", "")).strip()
            )
            if synthetic_session_name and synthetic_session_name in existing_session_names:
                continue
            if synthetic_id in existing_ids:
                continue
            project_entry["windows"].append(synthetic_window)
            existing_ids.add(synthetic_id)
            if synthetic_session_name:
                existing_session_names.add(synthetic_session_name)

        project_entry["window_count"] = len(project_entry.get("windows", []))


def transform_to_project_view(
    monitors: List[Dict[str, Any]],
    remote_profiles: Optional[Dict[str, Dict[str, Any]]] = None,
    otel_sessions: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    """
    Transform monitor-based hierarchy to project-based view.

    Groups all windows by their project association, creating a flat structure:
    projects → windows (with workspace/monitor metadata)

    Args:
        monitors: List of MonitorInfo dicts from transform_monitor()

    Returns:
        List of ProjectInfo dicts with structure:
        [
            {
                "name": "nixos",
                "scope": "scoped",
                "window_count": 5,
                "windows": [...]
            },
            {
                "name": "Global Windows",
                "scope": "global",
                "window_count": 3,
                "windows": [...]
            }
        ]
    """
    # Collect all windows from all monitors/workspaces
    all_windows = []
    for monitor in monitors:
        for workspace in monitor["workspaces"]:
            for window in workspace["windows"]:
                # Add monitor and workspace metadata to window
                window_with_meta = window.copy()
                window_with_meta["monitor_name"] = monitor["name"]
                window_with_meta["workspace_name"] = workspace["name"]
                window_with_meta["workspace_number"] = workspace["number"]
                all_windows.append(window_with_meta)

    # Group windows by project
    projects_dict: Dict[str, Dict[str, Any]] = {}
    global_windows = []
    remote_env_cache: Dict[int, Dict[str, str]] = {}

    for window in all_windows:
        if window["scope"] == "scoped" and window["project"]:
            project_name = window["project"]
            remote_profile = (remote_profiles or {}).get(project_name)
            profile_enabled = isinstance(remote_profile, dict) and bool(remote_profile.get("enabled", False))
            profile_target = ""
            profile_directory = ""
            if profile_enabled:
                profile_target = _format_remote_target(
                    remote_profile.get("user", ""),
                    remote_profile.get("host", ""),
                    remote_profile.get("port", 22),
                )
                profile_directory = str(remote_profile.get("remote_dir", ""))

            identity = _resolve_window_execution_identity(
                window,
                remote_profile=remote_profile if isinstance(remote_profile, dict) else None,
                remote_env_cache=remote_env_cache,
            )
            window_remote_enabled = bool(identity.get("remote_enabled", False))
            window_remote_target = str(identity.get("remote_target") or "")
            window_remote_directory = str(identity.get("remote_dir") or "")
            window_remote_session_name = str(identity.get("remote_session_name") or "")

            window["project_remote_enabled"] = window_remote_enabled
            window["project_remote_target"] = window_remote_target
            window["project_remote_dir"] = window_remote_directory
            if window_remote_session_name:
                window["remote_session_name"] = window_remote_session_name
            window["execution_mode"] = identity["execution_mode"]
            window["host_alias"] = identity["host_alias"]
            window["connection_key"] = identity["connection_key"]
            window["identity_key"] = identity["identity_key"]
            window["context_key"] = str(identity.get("context_key") or "")

            project_key = _project_card_key_for_identity(project_name, identity)
            if project_key not in projects_dict:
                projects_dict[project_key] = _create_project_entry(
                    project_name=project_name,
                    remote_enabled=window_remote_enabled,
                    remote_target=window_remote_target,
                    remote_directory=window_remote_directory,
                    remote_profile_enabled=profile_enabled,
                    remote_profile_target=profile_target,
                    remote_profile_directory=profile_directory,
                    identity=identity,
                )

            project_entry = projects_dict[project_key]
            if window_remote_enabled and not project_entry.get("remote_enabled"):
                # Keep project-level active remote metadata in sync if first
                # confirmed remote window arrives later.
                project_entry["remote_enabled"] = True
                project_entry["remote_target"] = window_remote_target
                project_identity = identity
                project_entry["execution_mode"] = project_identity["execution_mode"]
                project_entry["host_alias"] = project_identity["host_alias"]
                project_entry["connection_key"] = project_identity["connection_key"]
                project_entry["identity_key"] = project_identity["identity_key"]
                project_entry["card_id"] = _project_card_key_for_identity(project_name, project_identity)
                project_entry["remote_directory"] = window_remote_directory
                project_entry["remote_directory_display"] = (
                    window_remote_directory.replace(str(Path.home()), "~")
                    if window_remote_directory
                    else ""
                )
            project_entry["windows"].append(window)
            project_entry["window_count"] += 1
        else:
            window["project_remote_enabled"] = False
            window["project_remote_target"] = ""
            window["project_remote_dir"] = ""
            global_identity = _connection_identity(False, "")
            window["execution_mode"] = global_identity["execution_mode"]
            window["host_alias"] = global_identity["host_alias"]
            window["connection_key"] = global_identity["connection_key"]
            window["identity_key"] = global_identity["identity_key"]
            window["context_key"] = ""
            global_windows.append(window)

    # Augment project windows with remote tmux/sesh sessions for SSH projects.
    _augment_projects_with_remote_sessions(projects_dict, remote_profiles, otel_sessions)

    # Convert dict to sorted list:
    # 1) project name alphabetical
    # 2) local card before ssh card for the same project
    variant_rank = {"local": 0, "ssh": 1, "global": 2}
    projects = sorted(
        projects_dict.values(),
        key=lambda p: (
            str(p.get("name", "")).lower(),
            variant_rank.get(str(p.get("variant", "")), 9),
            str(p.get("card_id", "")),
        ),
    )

    # Add global windows as a separate "project" at the end
    if global_windows:
        projects.append({
            "card_id": "global::windows",
            "name": "Global Windows",
            "scope": "global",
            "variant": "global",
            "variant_label": "GLOBAL",
            "execution_mode": "global",
            "host_alias": "global",
            "connection_key": "global",
            "identity_key": "global:global",
            "window_count": len(global_windows),
            "remote_enabled": False,
            "remote_target": "",
            "remote_directory": "",
            "remote_directory_display": "",
            "remote_profile_enabled": False,
            "remote_profile_target": "",
            "remote_profile_directory": "",
            "remote_profile_directory_display": "",
            "has_local_variant": False,
            "has_remote_variant": False,
            "windows": global_windows
        })

    _refresh_variant_flags(projects)

    return projects


async def query_monitoring_data() -> Dict[str, Any]:
    """
    Query i3pm daemon for monitoring panel data.

    Implements contracts/daemon-query.md specification:
    - Connect to daemon via DaemonClient
    - Call get_window_tree() method
    - Transform response to Eww-friendly schema
    - Handle errors gracefully

    Returns:
        MonitoringPanelState dict with status, monitors, counts, timestamp, error

    Error Handling:
        - Daemon unavailable: Return error state with helpful message
        - Timeout: Return error state with timeout message
        - Unexpected errors: Log and return generic error state
    """
    try:
        # Get daemon socket path from environment (defaults to user runtime dir)
        # Feature 085: Support system service socket path via I3PM_DAEMON_SOCKET env var
        import os
        socket_path_str = os.environ.get("I3PM_DAEMON_SOCKET")
        socket_path = Path(socket_path_str) if socket_path_str else None

        # Create daemon client with 4.0s timeout (increased from 2.0s to accommodate
        # large window trees with per-window /proc environ reads)
        client = DaemonClient(socket_path=socket_path, timeout=4.0)

        # Connect to daemon
        await client.connect()

        # Query window tree (monitors → workspaces → windows hierarchy)
        tree_data = await client.get_window_tree()

        # UX Enhancement: Query active project for highlighting
        active_project = await client.get_active_project()

        # Feature 095: Load badge state from filesystem (file-based, no daemon)
        # Badge files are written by claude-hooks scripts in $XDG_RUNTIME_DIR/i3pm-badges/
        badge_state = load_badge_state_from_files()
        logger.debug(f"Feature 095: Loaded {len(badge_state)} badges from filesystem")

        # Feature 117: Stale badge cleanup during refresh cycle
        # Remove badges for windows that no longer exist (orphan cleanup)
        # Remove badges older than 5 minutes (TTL cleanup)
        valid_window_ids = set()
        for output in tree_data.get("outputs", []):
            for ws in output.get("workspaces", []):
                for win in ws.get("windows", []):
                    win_id = win.get("id")
                    if win_id:
                        valid_window_ids.add(int(win_id))

        # Orphan cleanup: remove badges for non-existent windows
        orphan_count = 0
        for window_id_str in list(badge_state.keys()):
            try:
                window_id = int(window_id_str)
                if window_id not in valid_window_ids:
                    badge_file = BADGE_STATE_DIR / f"{window_id}.json"
                    if badge_file.exists():
                        badge_file.unlink()
                        del badge_state[window_id_str]
                        orphan_count += 1
                        logger.info(f"[Feature 117] Removed orphaned badge for window {window_id}")
            except (ValueError, OSError) as e:
                logger.warning(f"[Feature 117] Error cleaning orphan badge {window_id_str}: {e}")

        # TTL cleanup: remove badges older than 5 minutes (300 seconds)
        MAX_BADGE_AGE = 300
        now = time.time()
        ttl_count = 0
        for window_id_str in list(badge_state.keys()):
            badge = badge_state.get(window_id_str, {})
            timestamp = badge.get("timestamp", 0)
            age = now - timestamp
            if age > MAX_BADGE_AGE:
                try:
                    badge_file = BADGE_STATE_DIR / f"{window_id_str}.json"
                    if badge_file.exists():
                        badge_file.unlink()
                        del badge_state[window_id_str]
                        ttl_count += 1
                        logger.info(f"[Feature 117] Removed stale badge {window_id_str} (age: {age:.0f}s)")
                except OSError as e:
                    logger.warning(f"[Feature 117] Error cleaning stale badge {window_id_str}: {e}")

        if orphan_count > 0 or ttl_count > 0:
            logger.debug(f"[Feature 117] Badge cleanup: {orphan_count} orphans, {ttl_count} stale removed")

        # Close connection (stateless pattern per research.md Decision 4)
        await client.close()

        # Feature 123/136: Load OTEL sessions BEFORE transforms to build lookup dict
        # Feature 136: Changed to List to support multiple AI sessions per window
        otel_sessions = load_otel_sessions()
        outputs = tree_data.get("outputs", [])
        window_candidates = _collect_output_window_candidates(outputs)
        window_candidates_by_id: Dict[int, Dict[str, Any]] = {}
        for candidate in window_candidates:
            cid = _safe_int(candidate.get("id"), 0)
            if cid > 0:
                window_candidates_by_id[cid] = candidate
        window_candidates_fingerprint = _window_candidates_cache_fingerprint(window_candidates)
        remote_otel_sessions = _load_remote_otel_sessions_for_windows(window_candidates)
        merged_otel_raw_sessions: List[Dict[str, Any]] = []
        for raw_session in otel_sessions.get("sessions", []):
            if isinstance(raw_session, dict):
                merged_otel_raw_sessions.append(dict(raw_session))
        merged_otel_raw_sessions.extend(remote_otel_sessions)
        resolved_otel_sessions: List[Dict[str, Any]] = []
        for raw_session in merged_otel_raw_sessions:
            session = _normalize_session_project_from_path(raw_session)
            terminal_context = session.get("terminal_context", {}) or {}
            if not isinstance(terminal_context, dict):
                terminal_context = {}

            window_id_raw = session.get("window_id", terminal_context.get("window_id"))
            window_id_int = _safe_int(window_id_raw, 0)
            resolved_window_id: Optional[int] = None
            if window_id_int != 0:
                existing_candidate = window_candidates_by_id.get(window_id_int, {})
                if isinstance(existing_candidate, dict) and existing_candidate:
                    if _window_matches_session_binding(existing_candidate, session):
                        resolved_window_id = window_id_int

            if resolved_window_id is None:
                cache_key = _window_resolution_cache_key(
                    session,
                    candidates_fingerprint=window_candidates_fingerprint,
                )
                cache_hit, cached_window_id = _get_cached_window_resolution(cache_key)
                if cache_hit:
                    resolved_window_id = cached_window_id
                else:
                    resolved_window_id = _resolve_otel_session_window_id(
                        session,
                        outputs,
                        window_candidates=window_candidates,
                    )
                    _store_cached_window_resolution(cache_key, resolved_window_id)

            if resolved_window_id is not None:
                session["window_id"] = resolved_window_id
                terminal_context["window_id"] = resolved_window_id
                session["terminal_context"] = terminal_context
                if window_id_int != 0 and window_id_int != resolved_window_id:
                    logger.debug(
                        "Feature 139: remapped OTEL window_id %s -> %s: session=%s",
                        window_id_int,
                        resolved_window_id,
                        str(session.get("native_session_id") or session.get("session_id") or ""),
                    )
                elif window_id_int == 0:
                    logger.debug(
                        "Feature 139: resolved missing OTEL window_id via project mapping: session=%s window=%s",
                        str(session.get("native_session_id") or session.get("session_id") or ""),
                        resolved_window_id,
                    )
            elif window_id_int != 0:
                session["window_id"] = window_id_int
                terminal_context["window_id"] = window_id_int
                session["terminal_context"] = terminal_context
            resolved_otel_sessions.append(session)

        otel_sessions_runtime = dict(otel_sessions)
        otel_sessions_runtime["sessions"] = resolved_otel_sessions
        otel_sessions_runtime["has_working"] = any(
            str(session.get("state") or "").strip().lower() == "working"
            for session in resolved_otel_sessions
        )

        otel_sessions_by_window: Dict[int, List[Dict[str, Any]]] = {}
        per_window_seen: Dict[int, Dict[str, Dict[str, Any]]] = {}
        for session in resolved_otel_sessions:
            identity_confidence = str(session.get("identity_confidence") or "").strip().lower()
            native_session_id = str(session.get("native_session_id") or "").strip()
            if not native_session_id or identity_confidence != "native":
                continue

            terminal_context = session.get("terminal_context", {}) or {}
            window_id = session.get("window_id", terminal_context.get("window_id"))
            if window_id is None:
                continue
            try:
                window_id_int = int(window_id)
            except (TypeError, ValueError):
                continue

            window_candidate = window_candidates_by_id.get(window_id_int, {})
            if not isinstance(window_candidate, dict):
                continue
            if not _window_matches_session_binding(window_candidate, session):
                continue

            window_seen = per_window_seen.setdefault(window_id_int, {})
            dedupe_key = _otel_badge_merge_key(session)
            existing = window_seen.get(dedupe_key)
            if existing is None or _otel_badge_score(session) > _otel_badge_score(existing):
                window_seen[dedupe_key] = session

        for window_id, seen in per_window_seen.items():
            otel_sessions_by_window[window_id] = list(seen.values())

        # Transform daemon response to Eww schema
        monitors = [transform_monitor(output, badge_state, otel_sessions_by_window) for output in outputs]

        # Validate and compute summary counts
        counts = validate_and_count(monitors)

        # Transform to project-based view (default view).
        # Overlay SSH remote metadata so window view can surface remote worktree context.
        remote_profiles = load_worktree_remote_profiles()
        projects = transform_to_project_view(monitors, remote_profiles, resolved_otel_sessions)
        active_identity = load_active_worktree_identity()

        # UX Enhancement: Add is_active flag to each project
        active_qualified_name = str(active_identity.get("qualified_name", "")).strip()
        active_identity_key = str(active_identity.get("identity_key", "")).strip()
        active_mode = str(active_identity.get("execution_mode", "")).strip()

        for project in projects:
            project_name = str(project.get("name", "")).strip()
            variant = str(project.get("variant", "")).strip()
            project_identity = str(project.get("identity_key", "")).strip()

            if variant == "global":
                project["is_active"] = not active_qualified_name and (active_project in {None, "", "global"})
                continue

            # Prefer active-worktree identity as the source of truth for variant cards.
            if active_qualified_name:
                if project_name != active_qualified_name:
                    project["is_active"] = False
                    continue

                if project_identity and active_identity_key:
                    project["is_active"] = project_identity == active_identity_key
                    continue

                # Backward-compatibility fallback for older active-worktree payloads.
                if variant in {"local", "ssh"} and active_mode in {"local", "ssh"}:
                    project["is_active"] = variant == active_mode
                else:
                    project["is_active"] = True
                continue

            # Legacy fallback path when active-worktree context is unavailable.
            if project_name != active_project:
                project["is_active"] = False
                continue

            if project_identity and active_identity_key:
                project["is_active"] = project_identity == active_identity_key
                continue

            if variant in {"local", "ssh"} and active_mode in {"local", "ssh"}:
                project["is_active"] = variant == active_mode
            else:
                project["is_active"] = True

        # Create flat list of all windows for easy ID lookup in detail view
        all_windows = []
        for project in projects:
            all_windows.extend(project.get("windows", []))

        window_lookup: Dict[int, Dict[str, Any]] = {}
        focused_window_id: Optional[int] = None
        for window in all_windows:
            window_id = window.get("id")
            try:
                window_id_int = int(window_id)
            except (TypeError, ValueError):
                continue
            window_lookup[window_id_int] = window
            if bool(window.get("focused", False)):
                focused_window_id = window_id_int

        active_ai_sessions = _build_active_ai_sessions(
            resolved_otel_sessions,
            window_lookup=window_lookup,
            active_project_name=active_qualified_name,
            focused_window_id=focused_window_id,
        )
        active_ai_sessions, _review_sessions = _apply_review_lifecycle(
            active_ai_sessions,
            window_lookup=window_lookup,
            focused_window_id=focused_window_id,
        )
        active_ai_sessions.sort(
            key=lambda session: (
                int(focused_window_id is not None and session.get("window_id") == focused_window_id),
                int(bool(active_qualified_name) and str(session.get("project", "")).strip() == active_qualified_name),
                _active_ai_session_sort_rank(session),
                str(session.get("updated_at") or ""),
                str(session.get("session_key") or ""),
            ),
            reverse=True,
        )
        _merge_review_state_into_window_badges(all_windows, active_ai_sessions)
        pinned_session_keys = load_ai_session_pins()
        pinned_session_set = {str(key) for key in pinned_session_keys if str(key)}
        for session in active_ai_sessions:
            key = str(session.get("session_key") or "")
            session["pinned"] = key in pinned_session_set
        active_ai_sessions = [
            session for session in active_ai_sessions if _should_render_ai_session(session)
        ]
        active_ai_sessions = _apply_pinned_session_order(active_ai_sessions, pinned_session_keys)
        active_ai_sessions_mru = _apply_ai_session_mru_order(
            active_ai_sessions,
            load_ai_session_mru(),
        )
        active_ai_sessions_mru = _apply_pinned_session_order(active_ai_sessions_mru, pinned_session_keys)
        emit_ai_state_transition_notifications(active_ai_sessions)
        ai_metrics = load_ai_monitor_metrics()
        ai_metrics.update({
            "active_sessions": len(active_ai_sessions),
            "working_sessions": sum(1 for s in active_ai_sessions if str(s.get("stage")) in {"starting", "thinking", "tool_running", "streaming"}),
            "attention_sessions": sum(1 for s in active_ai_sessions if str(s.get("stage")) in {"waiting_input", "attention"}),
            "review_pending_sessions": sum(1 for s in active_ai_sessions if bool(s.get("output_unseen") or s.get("review_pending"))),
            "stale_sessions": sum(1 for s in active_ai_sessions if bool(s.get("stale"))),
            "pinned_sessions": sum(1 for s in active_ai_sessions if bool(s.get("pinned"))),
            "output_ready_sessions": sum(1 for s in active_ai_sessions if bool(s.get("output_ready"))),
            "stage_tool_running_sessions": sum(1 for s in active_ai_sessions if str(s.get("stage")) == "tool_running"),
            "stage_streaming_sessions": sum(1 for s in active_ai_sessions if str(s.get("stage")) == "streaming"),
            "stage_waiting_sessions": sum(1 for s in active_ai_sessions if str(s.get("stage")) == "waiting_input"),
            "stage_from_native": sum(1 for s in active_ai_sessions if str(s.get("identity_source") or "") == "native"),
            "stage_from_process": sum(1 for s in active_ai_sessions if str(s.get("identity_source") or "") in {"pid", "pane", "heuristic"}),
            "stage_from_review": sum(1 for s in active_ai_sessions if str(s.get("identity_source") or "") == "review"),
            "stale_source_sessions": sum(1 for s in active_ai_sessions if bool(s.get("remote_source_stale"))),
            "window_fallback_project": sum(
                1
                for s in active_ai_sessions
                if str(s.get("project_source") or "") in {"window_fallback", "tmux_window_fallback"}
            ),
            "remote_relabel_prevented": sum(
                1
                for s in active_ai_sessions
                if str(s.get("execution_mode") or "") == "ssh"
                and str(s.get("window_project") or "").strip()
                and str(s.get("display_project") or "").strip()
                and str(s.get("window_project") or "").strip()
                != str(s.get("display_project") or "").strip()
            ),
            "missing_context_sessions": sum(
                1
                for s in active_ai_sessions
                if not str(s.get("context_key") or "").strip()
                and not str(s.get("project_path") or "").strip()
                and not str(s.get("session_project") or "").strip()
            ),
        })

        # NOTE: Workspace pills removed from UI - workspaces list no longer needed

        # Get current timestamp for friendly formatting
        current_timestamp = time.time()
        friendly_time = format_friendly_timestamp(current_timestamp)

        # Feature 095 Enhancement: Check if any badges are in "working" state
        # This is used to trigger more frequent updates for spinner animation
        has_working_badge = any(
            badge.get("state") == "working"
            for badge in badge_state.values()
        ) if badge_state else False

        # Feature 117 Enhancement: Collect all windows with AI session badges
        # This provides a pre-computed list for the Active AI Sessions bar in EWW
        # Includes all badge states: working, stopped+needs_attention, stopped+idle
        # Visual state is determined by: state, needs_attention fields
        ai_sessions = []
        for window in all_windows:
            badge = window.get("badge", {})
            # Include window if it has any badge (any state = active AI session)
            if badge:
                ai_sessions.append({
                    "id": window.get("id"),
                    "project": window.get("project", ""),
                    "title": window.get("title", ""),
                    "app_id": window.get("app_id", ""),
                    "workspace_number": window.get("workspace_number", 0),
                    "source": badge.get("source", "ai"),  # claude-code, codex, etc.
                    # Badge state info for visual styling
                    "state": badge.get("state", "unknown"),  # working, stopped
                    "needs_attention": badge.get("needs_attention", False),
                    "count": badge.get("count", 0),  # Number of completions
                    "session_started": badge.get("session_started", 0),
                })

        # NOTE: otel_sessions already loaded before transforms (line ~1550)

        # Return success state with project-based view
        # NOTE: Removed for payload optimization:
        # - all_windows (~11KB) - detail view disabled
        # - workspaces (~700B) - workspace pills removed
        # - counts - count badges removed from UI
        return {
            "status": "ok",
            "projects": projects,
            "active_project": active_project,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None,
            # Feature 095 Enhancement: Animated spinner frame
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": has_working_badge or otel_sessions_runtime.get("has_working", False),
            # Feature 117 Enhancement: Pre-computed list for Active AI Sessions bar
            "ai_sessions": ai_sessions,
            # Feature 138: Canonical active AI sessions rail + keyboard switching
            "active_ai_sessions": active_ai_sessions,
            # Feature 139: MRU-ordered list for rapid Alt+Tab-style switching.
            "active_ai_sessions_mru": active_ai_sessions_mru,
            "ai_monitor_metrics": ai_metrics,
            # Feature 123: OTEL AI sessions for window badge rendering
            "otel_sessions": otel_sessions_runtime,
        }

    except DaemonError as e:
        # Expected errors: socket not found, timeout, connection lost
        logger.warning(f"Daemon error: {e}")
        error_timestamp = time.time()
        # Still try to load OTEL sessions even on daemon error
        otel_sessions = load_otel_sessions()
        return {
            "status": "error",
            "projects": [],
            "active_project": None,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": str(e),
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": otel_sessions.get("has_working", False),
            "ai_sessions": [],
            "active_ai_sessions": [],
            "active_ai_sessions_mru": [],
            "ai_monitor_metrics": load_ai_monitor_metrics(),
            "otel_sessions": otel_sessions,
        }

    except Exception as e:
        # Unexpected errors: log for debugging
        logger.error(f"Unexpected error querying daemon: {e}", exc_info=True)
        error_timestamp = time.time()
        # Still try to load OTEL sessions even on unexpected error
        otel_sessions = load_otel_sessions()
        return {
            "status": "error",
            "projects": [],
            "active_project": None,
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Unexpected error: {type(e).__name__}: {e}",
            "spinner_frame": get_spinner_frame(),
            "has_working_badge": otel_sessions.get("has_working", False),
            "ai_sessions": [],
            "active_ai_sessions": [],
            "active_ai_sessions_mru": [],
            "ai_monitor_metrics": load_ai_monitor_metrics(),
            "otel_sessions": otel_sessions,
        }


def get_projects_hierarchy(projects_dir: Optional[Path] = None) -> PanelProjectsData:
    """
    Build hierarchical project structure for monitoring panel (Feature 097 T035).

    Groups projects by bare_repo_path:
    - Repository projects: First project registered for each bare repo
    - Worktree projects: Nested under their parent repository
    - Standalone projects: Non-git or simple repos
    - Orphaned worktrees: Worktrees with missing parent Repository Project

    Args:
        projects_dir: Directory containing project JSON files (default: ~/.config/i3/projects/)

    Returns:
        PanelProjectsData with repository_projects, standalone_projects, orphaned_worktrees

    Tasks:
        T034: Group projects by bare_repo_path using detect_orphaned_worktrees()
        T035: Return PanelProjectsData structure
        T036: Calculate worktree_count per Repository Project
        T037: Calculate has_dirty aggregation (bubble-up from worktrees to parent)
    """
    projects_dir = projects_dir or Path.home() / ".config/i3/projects"

    if not projects_dir.exists():
        return PanelProjectsData()

    # Load all project configs
    # Pass edit_mode=True context to skip uniqueness/existence validators (they're for creation, not loading)
    load_context = {"edit_mode": True}
    all_projects: List[ProjectConfig] = []
    for project_file in projects_dir.glob("*.json"):
        try:
            with open(project_file, 'r') as f:
                data = json.load(f)
            # Parse with Pydantic model, skip creation-time validators
            project = ProjectConfig.model_validate(data, context=load_context)
            all_projects.append(project)
        except Exception as e:
            logger.warning(f"Feature 097: Skipping invalid project file {project_file}: {e}")
            continue

    # T034: Detect orphaned worktrees using git_utils
    orphaned = detect_orphaned_worktrees(all_projects)
    orphaned_names = {p.name for p in orphaned}

    # Separate projects by source_type
    repository_projects: Dict[str, RepositoryWithWorktrees] = {}  # bare_repo_path -> RepositoryWithWorktrees
    standalone_projects: List[ProjectConfig] = []
    worktree_projects: List[ProjectConfig] = []

    for project in all_projects:
        if project.name in orphaned_names:
            # Skip orphans here, they're already in the orphaned list
            continue

        if project.source_type == SourceType.REPOSITORY:
            # T035: Create RepositoryWithWorktrees container
            if project.bare_repo_path:
                repository_projects[project.bare_repo_path] = RepositoryWithWorktrees(
                    project=project,
                    worktree_count=0,
                    has_dirty=not (project.git_metadata.is_clean if project.git_metadata else True),
                    is_expanded=True,
                    worktrees=[]
                )
        elif project.source_type == SourceType.WORKTREE:
            worktree_projects.append(project)
        else:  # standalone
            standalone_projects.append(project)

    # T036: Nest worktrees under their parent repository and calculate worktree_count
    for worktree in worktree_projects:
        if worktree.bare_repo_path and worktree.bare_repo_path in repository_projects:
            repo_container = repository_projects[worktree.bare_repo_path]
            repo_container.worktrees.append(worktree)
            repo_container.worktree_count = len(repo_container.worktrees)

            # T037: has_dirty bubble-up (if worktree is dirty, parent shows dirty)
            worktree_dirty = not (worktree.git_metadata.is_clean if worktree.git_metadata else True)
            if worktree_dirty:
                repo_container.has_dirty = True
        else:
            # Worktree without matching repository - this shouldn't happen if detect_orphaned_worktrees worked
            # but handle gracefully by adding to orphans
            orphaned.append(worktree)

    # Sort repository projects by name
    sorted_repos = sorted(
        repository_projects.values(),
        key=lambda r: r.project.name
    )

    # Sort worktrees within each repository by name
    for repo in sorted_repos:
        repo.worktrees = sorted(repo.worktrees, key=lambda w: w.name)

    # Sort standalone and orphaned projects by name
    standalone_projects.sort(key=lambda p: p.name)
    orphaned.sort(key=lambda p: p.name)

    return PanelProjectsData(
        repository_projects=sorted_repos,
        standalone_projects=standalone_projects,
        orphaned_worktrees=orphaned,
        active_project=None  # Set by caller after getting active project
    )


def load_discovered_repositories() -> Dict[str, List[Dict[str, Any]]]:
    """Load discovered bare repositories from repos.json.

    Feature 100 T055: Load bare repositories discovered via `i3pm discover`
    and convert them to a format compatible with the Projects tab.

    Returns:
        Dict with "repositories" list (bare repos with worktrees nested)
    """
    repos_file = Path.home() / ".config" / "i3" / "repos.json"
    remote_profiles = load_worktree_remote_profiles()

    if not repos_file.exists():
        logger.debug("Feature 100: No repos.json found, skipping bare repo discovery")
        return {"repositories": [], "last_discovery": None}

    try:
        with open(repos_file, "r") as f:
            repos_data = json.load(f)

        repositories = repos_data.get("repositories", [])
        last_discovery = repos_data.get("last_discovery")

        # Convert each discovered repo to project-compatible format
        for repo in repositories:
            # Generate qualified name for the repository
            repo["qualified_name"] = f"{repo['account']}/{repo['name']}"

            # Add source_type for UI display
            repo["source_type"] = "bare_repository"
            repo["source_type_badge"] = "📂"

            # Add display fields
            repo["display_name"] = repo.get("display_name") or repo["name"]
            repo["directory"] = repo["path"]
            repo["directory_display"] = repo["path"].replace(str(Path.home()), "~")

            # Mark worktrees with their qualified names
            for wt in repo.get("worktrees", []):
                wt["qualified_name"] = f"{repo['account']}/{repo['name']}:{wt['branch']}"
                wt["source_type"] = "worktree"
                wt["source_type_badge"] = "🌿"
                wt["parent_repo"] = repo["qualified_name"]
                wt["directory_display"] = wt["path"].replace(str(Path.home()), "~")

                # Feature 087: Overlay optional SSH remote profile for each worktree.
                remote_profile = remote_profiles.get(wt["qualified_name"])
                wt["remote"] = remote_profile if remote_profile else None
                wt["remote_enabled"] = remote_profile is not None
                if remote_profile:
                    remote_dir = str(remote_profile.get("remote_dir", ""))
                    wt["remote_directory_display"] = remote_dir.replace(str(Path.home()), "~")
                    wt["remote_target"] = (
                        f"{remote_profile.get('user', '')}@"
                        f"{remote_profile.get('host', '')}:"
                        f"{remote_profile.get('port', 22)}"
                    )
                else:
                    wt["remote_directory_display"] = ""
                    wt["remote_target"] = ""

        logger.debug(f"Feature 100: Loaded {len(repositories)} discovered bare repositories")
        return {"repositories": repositories, "last_discovery": last_discovery}

    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Feature 100: Failed to load repos.json: {e}")
        return {"repositories": [], "last_discovery": None}


def load_worktree_remote_profiles() -> Dict[str, Dict[str, Any]]:
    """Load enabled worktree SSH remote profiles keyed by qualified_name."""
    profiles_file = Path.home() / ".config" / "i3" / "worktree-remote-profiles.json"
    if not profiles_file.exists():
        return {}

    try:
        with open(profiles_file, "r") as f:
            data = json.load(f)

        raw_profiles = data.get("profiles", {})
        if not isinstance(raw_profiles, dict):
            return {}

        normalized: Dict[str, Dict[str, Any]] = {}
        for qualified_name, profile in raw_profiles.items():
            if not isinstance(qualified_name, str) or not isinstance(profile, dict):
                continue

            enabled_raw = profile.get("enabled", True)
            if isinstance(enabled_raw, str):
                enabled = enabled_raw.strip().lower() in {"1", "true", "yes", "on"}
            else:
                enabled = bool(enabled_raw)
            if not enabled:
                continue

            remote_dir = str(profile.get("remote_dir") or profile.get("working_dir") or "").strip()
            if not remote_dir:
                continue

            try:
                port = int(profile.get("port", 22))
            except (TypeError, ValueError):
                port = 22

            normalized[qualified_name] = {
                "enabled": True,
                "host": str(profile.get("host") or "ryzen").strip(),
                "user": str(profile.get("user") or os.environ.get("USER", "")).strip(),
                "port": port,
                "remote_dir": remote_dir,
            }

        return normalized
    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Feature 087: Failed to load worktree remote profiles: {e}")
        return {}


def load_active_worktree_identity() -> Dict[str, Any]:
    """Return canonical active worktree identity fields for card activation."""
    default_identity = {
        "qualified_name": "",
        "execution_mode": "global",
        "host_alias": "global",
        "connection_key": "global",
        "identity_key": "global:global",
        "context_key": "",
        "remote_enabled": False,
    }

    if not ACTIVE_WORKTREE_FILE.exists():
        return default_identity

    try:
        with open(ACTIVE_WORKTREE_FILE, "r") as f:
            data = json.load(f)

        qualified_name = str(data.get("qualified_name", "")).strip()
        remote = data.get("remote")
        remote_enabled = isinstance(remote, dict) and bool(remote.get("enabled", False))
        execution_mode = str(data.get("execution_mode", "")).strip()
        host_alias = str(data.get("host_alias", "")).strip()
        connection_key = str(data.get("connection_key", "")).strip()
        identity_key = str(data.get("identity_key", "")).strip()
        context_key = str(data.get("context_key", "")).strip()

        if execution_mode not in {"local", "ssh"}:
            if qualified_name:
                execution_mode = "ssh" if remote_enabled else "local"
            else:
                execution_mode = "global"

        if not host_alias:
            if execution_mode == "ssh" and isinstance(remote, dict):
                host = str(remote.get("host") or "").strip()
                user = str(remote.get("user") or "").strip()
                host_alias = f"{user}@{host}" if user and host else host or "unknown"
            elif execution_mode == "local":
                host_alias = (
                    str(
                        os.environ.get("I3PM_LOCAL_HOST_ALIAS")
                        or os.environ.get("HOSTNAME")
                        or socket.gethostname()
                    )
                    .strip()
                    .lower()
                    or "localhost"
                )
            else:
                host_alias = "global"

        if not connection_key:
            if execution_mode == "ssh" and isinstance(remote, dict):
                host = str(remote.get("host") or "").strip()
                user = str(remote.get("user") or "").strip()
                port_raw = remote.get("port", 22)
                try:
                    port = int(port_raw)
                except (TypeError, ValueError):
                    port = 22
                raw_connection_key = f"{user}@{host}:{port}" if user else f"{host}:{port}"
                connection_key = _normalize_connection_key(raw_connection_key)
            elif execution_mode == "local":
                connection_key = _local_connection_key()
            else:
                connection_key = "global"

        if not identity_key:
            identity_key = f"{execution_mode}:{connection_key}"

        if not context_key and qualified_name and execution_mode in {"local", "ssh"}:
            context_key = f"{qualified_name}::{execution_mode}::{connection_key}"

        return {
            "qualified_name": qualified_name,
            "execution_mode": execution_mode,
            "host_alias": host_alias,
            "connection_key": connection_key,
            "identity_key": identity_key,
            "context_key": context_key,
            "remote_enabled": remote_enabled,
        }
    except (json.JSONDecodeError, IOError) as e:
        logger.debug(f"Feature 087: Failed to read active-worktree identity: {e}")

    return default_identity


async def query_projects_data() -> Dict[str, Any]:
    """
    Query projects view data using bare repository discovery.

    Feature 100: Reads from repos.json (populated by `i3pm discover`) and returns:
    - Hierarchical: repositories with nested worktrees
    - Qualified names: account/repo and account/repo:branch
    - Git status indicators (dirty, ahead/behind)

    Returns repository list with worktrees and current active project.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Feature 100: Load discovered bare repositories from repos.json
        discovered_repos = load_discovered_repositories()
        repositories = discovered_repos.get("repositories", [])
        last_discovery = discovered_repos.get("last_discovery")

        # Get active project (uses qualified name like vpittamp/nixos:main)
        # Prefer daemon query to avoid spawning i3pm/deno every poll cycle.
        active_project = None
        try:
            socket_path_str = os.environ.get("I3PM_DAEMON_SOCKET")
            socket_path = Path(socket_path_str) if socket_path_str else None
            daemon_client = DaemonClient(socket_path=socket_path, timeout=2.0)
            await daemon_client.connect()
            try:
                active_project = await daemon_client.get_active_project()
            finally:
                await daemon_client.close()
        except Exception:
            # Fallback for edge cases where daemon query is temporarily unavailable.
            try:
                result = subprocess.run(
                    ["i3pm", "project", "current"],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                if result.returncode == 0:
                    active_project = result.stdout.strip()
            except subprocess.TimeoutExpired:
                pass

        # Enhance repositories with UI fields
        for repo in repositories:
            qualified_name = repo.get("qualified_name", f"{repo['account']}/{repo['name']}")
            repo["is_active"] = (active_project == qualified_name)
            repo["icon"] = "📂"  # Bare repository icon
            repo["display_name"] = repo.get("display_name") or repo["name"]

            # Calculate aggregate stats for the repo
            worktrees = repo.get("worktrees", [])
            repo["worktree_count"] = len(worktrees)
            repo["has_dirty_worktrees"] = any(not wt.get("is_clean", True) for wt in worktrees)

            # Enhance each worktree
            for wt in worktrees:
                wt_qualified = f"{qualified_name}:{wt['branch']}"
                wt["qualified_name"] = wt_qualified
                wt["is_active"] = (active_project == wt_qualified)
                wt["display_name"] = wt["branch"]
                wt["directory_display"] = wt.get("path", "").replace(str(Path.home()), "~")
                wt["remote_enabled"] = bool(wt.get("remote_enabled", False))

                remote_profile = wt.get("remote")
                if isinstance(remote_profile, dict) and wt["remote_enabled"]:
                    remote_dir = str(remote_profile.get("remote_dir", ""))
                    wt["remote_directory_display"] = remote_dir.replace(str(Path.home()), "~")
                    wt["remote_target"] = (
                        f"{remote_profile.get('user', '')}@"
                        f"{remote_profile.get('host', '')}:"
                        f"{remote_profile.get('port', 22)}"
                    )
                    wt["remote_host"] = remote_profile.get("host", "")
                    wt["remote_user"] = remote_profile.get("user", "")
                    wt["remote_port"] = remote_profile.get("port", 22)
                else:
                    wt["remote"] = None
                    wt["remote_directory_display"] = ""
                    wt["remote_target"] = ""
                    wt["remote_host"] = ""
                    wt["remote_user"] = ""
                    wt["remote_port"] = 22

                # Feature 109: Parse branch number from branch name (e.g., "108-show-worktree" -> "108")
                branch = wt.get("branch", "")
                branch_number = ""
                branch_description = branch
                # Pattern: number-description (e.g., 108-show-worktree-card-detail)
                match = re.match(r'^(\d{2,4})[-_](.+)$', branch)
                if match:
                    branch_number = match.group(1)
                    # Convert description: "show-worktree-card" -> "Show Worktree Card"
                    branch_description = match.group(2).replace('-', ' ').replace('_', ' ').title()
                wt["branch_number"] = branch_number
                wt["branch_description"] = branch_description
                wt["has_branch_number"] = bool(branch_number)

                # Git status indicators
                wt["git_is_dirty"] = not wt.get("is_clean", True)
                wt["git_dirty_indicator"] = "●" if wt["git_is_dirty"] else ""
                wt["git_ahead"] = wt.get("ahead", 0)
                wt["git_behind"] = wt.get("behind", 0)

                # Sync status
                sync_parts = []
                if wt["git_ahead"] > 0:
                    sync_parts.append(f"↑{wt['git_ahead']}")
                if wt["git_behind"] > 0:
                    sync_parts.append(f"↓{wt['git_behind']}")
                wt["git_sync_indicator"] = " ".join(sync_parts)

                # Feature 108 T015-T017: Enhanced status indicators
                # T016: Merge status (skip for main/master branches)
                wt["git_is_merged"] = wt.get("is_merged", False)
                wt["git_merged_indicator"] = "✓" if wt["git_is_merged"] else ""

                # T017: Conflict status
                wt["git_has_conflicts"] = wt.get("has_conflicts", False)
                wt["git_conflict_indicator"] = "⚠" if wt["git_has_conflicts"] else ""

                # Feature 108 T024-T026 (US2): Detailed status for tooltips
                wt["git_staged_count"] = wt.get("staged_count", 0)
                wt["git_modified_count"] = wt.get("modified_count", 0)
                wt["git_untracked_count"] = wt.get("untracked_count", 0)

                # Feature 108 T025: Last commit info
                last_ts = wt.get("last_commit_timestamp", 0)
                wt["git_last_commit_relative"] = format_relative_time(last_ts) if last_ts > 0 else ""
                wt["git_last_commit_message"] = wt.get("last_commit_message", "")[:50]

                # Feature 108 T031: Stale status
                wt["git_is_stale"] = wt.get("is_stale", False)
                wt["git_stale_indicator"] = "💤" if wt["git_is_stale"] else ""

                # Feature 108 T026: Build comprehensive tooltip
                tooltip_parts = []
                tooltip_parts.append(f"Branch: {wt['branch']}")
                tooltip_parts.append(f"Commit: {wt.get('commit', 'unknown')}")
                if wt["git_last_commit_relative"]:
                    tooltip_parts[-1] += f" ({wt['git_last_commit_relative']})"
                if wt["git_last_commit_message"]:
                    tooltip_parts.append(f"Message: {wt['git_last_commit_message']}")

                # Status breakdown
                status_parts = []
                if wt["git_staged_count"] > 0:
                    status_parts.append(f"{wt['git_staged_count']} staged")
                if wt["git_modified_count"] > 0:
                    status_parts.append(f"{wt['git_modified_count']} modified")
                if wt["git_untracked_count"] > 0:
                    status_parts.append(f"{wt['git_untracked_count']} untracked")
                if status_parts:
                    tooltip_parts.append(f"Status: {', '.join(status_parts)}")
                elif wt.get("is_clean", True):
                    tooltip_parts.append("Status: clean")

                # Sync info
                if wt["git_ahead"] > 0 or wt["git_behind"] > 0:
                    sync_desc = []
                    if wt["git_ahead"] > 0:
                        sync_desc.append(f"{wt['git_ahead']} to push")
                    if wt["git_behind"] > 0:
                        sync_desc.append(f"{wt['git_behind']} to pull")
                    tooltip_parts.append(f"Sync: {', '.join(sync_desc)}")

                # Merge/stale/conflict status
                if wt["git_is_merged"]:
                    tooltip_parts.append("Merged: ✓ merged into main")
                if wt["git_is_stale"]:
                    tooltip_parts.append("Stale: no activity in 30+ days")
                if wt["git_has_conflicts"]:
                    tooltip_parts.append("⚠ Has unresolved merge conflicts")

                wt["git_status_tooltip"] = "\\n".join(tooltip_parts)

        # Count totals
        total_worktrees = sum(len(r.get("worktrees", [])) for r in repositories)

        return {
            "status": "ok",
            # Feature 100: Primary data is discovered_repositories
            "discovered_repositories": repositories,
            "last_discovery": last_discovery,
            "repo_count": len(repositories),
            "worktree_count": total_worktrees,
            "active_project": active_project,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        logger.error(f"Error querying projects data: {e}", exc_info=True)
        return {
            "status": "error",
            "discovered_repositories": [],
            "last_discovery": None,
            "repo_count": 0,
            "worktree_count": 0,
            "active_project": None,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Projects query failed: {type(e).__name__}: {e}"
        }


async def query_apps_data() -> Dict[str, Any]:
    """
    Query apps view data.

    Returns app registry with configuration and runtime state.
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    try:
        # Read application registry JSON file directly (Feature 094)
        # The i3pm apps list --json flag doesn't work, so we read the file directly
        registry_path = Path.home() / ".config/i3/application-registry.json"

        if not registry_path.exists():
            apps = []
        else:
            try:
                with open(registry_path, 'r') as f:
                    registry_data = json.load(f)
                    apps = registry_data.get("applications", [])
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Failed to parse application registry: {e}")
                apps = []

        # Enhance with runtime state (running instances)
        # Query current windows to match app names
        try:
            client = DaemonClient()
            tree_data = await client.get_window_tree()
            await client.close()

            # Build map of app_name -> window IDs
            app_windows = {}
            for output in tree_data.get("outputs", []):
                for workspace in output.get("workspaces", []):
                    for window in workspace.get("windows", []):
                        app_name = window.get("app_name", "unknown")
                        if app_name not in app_windows:
                            app_windows[app_name] = []
                        app_windows[app_name].append(window.get("id"))

            # Add runtime info to apps
            for app in apps:
                app_name = app.get("name", "")
                app["running_instances"] = len(app_windows.get(app_name, []))
                app["window_ids"] = app_windows.get(app_name, [])

        except Exception as e:
            logger.warning(f"Could not query window state for apps: {e}")
            # Apps will just not have runtime info

        return {
            "status": "ok",
            "apps": apps,
            "app_count": len(apps),
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": None
        }

    except Exception as e:
        return {
            "status": "error",
            "apps": [],
            "app_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": friendly_time,
            "error": f"Apps query failed: {type(e).__name__}: {e}"
        }


# Health Monitoring Helper Functions (Feature 088)

def read_monitor_profile() -> str:
    """
    Read current monitor profile from ~/.config/sway/monitor-profile.current.

    Returns:
        Current profile name (e.g., "local-only", "dual", "triple") or "unknown"
    """
    profile_file = Path.home() / ".config/sway/monitor-profile.current"
    try:
        if profile_file.exists():
            return profile_file.read_text().strip()
    except Exception as e:
        logging.warning(f"Failed to read monitor profile: {e}")
    return "unknown"


def get_monitored_services(monitor_profile: str) -> List[Dict[str, Any]]:
    """
    Get list of services to monitor based on current monitor profile.

    Filters conditional services based on their condition_profiles list.

    Args:
        monitor_profile: Current monitor profile name

    Returns:
        Flat list of service definitions to monitor
    """
    services = []

    for category, service_list in SERVICE_REGISTRY.items():
        for service_def in service_list:
            # Include non-conditional services always
            if not service_def.get("conditional", False):
                services.append({**service_def, "category": category})
                continue

            # For conditional services, check if profile matches
            condition_profiles = service_def.get("condition_profiles", [])
            if monitor_profile in condition_profiles:
                services.append({**service_def, "category": category})

    return services


def classify_health_state(
    load_state: str,
    active_state: str,
    sub_state: str,
    unit_file_state: str,
    restart_count: int,
    is_conditional: bool,
    should_be_active: bool
) -> str:
    """
    Classify service health state based on systemd properties.

    Args:
        load_state: Service load state (loaded/not-found/error/masked)
        active_state: Service active state (active/inactive/failed/etc.)
        sub_state: Service sub-state (running/dead/exited/failed/etc.)
        unit_file_state: Service unit file state (enabled/disabled/static/masked)
        restart_count: Number of service restarts (NRestarts)
        is_conditional: Whether service is mode-dependent
        should_be_active: Whether service should be active in current profile

    Returns:
        Health state: healthy/degraded/critical/disabled/unknown
    """
    # Not found or load error
    if load_state in ["not-found", "error"]:
        return "unknown"

    # Intentionally disabled or masked
    if unit_file_state in ["disabled", "masked"]:
        return "disabled"

    # Conditional service not active in current profile
    if is_conditional and not should_be_active:
        return "disabled"

    # Failed state
    if active_state == "failed":
        return "critical"

    # Active and running normally
    if active_state == "active" and sub_state == "running":
        # Check for excessive restarts (degraded health indicator)
        if restart_count >= 3:
            return "degraded"
        return "healthy"

    # Active but not running (e.g., oneshot completed, socket listening)
    if active_state == "active" and sub_state in ["exited", "dead", "listening"]:
        return "healthy"  # Normal for oneshot services and sockets

    # Inactive (not started yet or stopped)
    if active_state == "inactive":
        return "disabled"

    # Activating or deactivating (transient state)
    if active_state in ["activating", "deactivating"]:
        return "degraded"

    # Unknown state
    return "unknown"


def format_uptime(uptime_seconds: int) -> str:
    """
    Convert uptime in seconds to human-friendly format.

    Args:
        uptime_seconds: Uptime in seconds

    Returns:
        Human-friendly string (e.g., "5h 23m", "2d 3h", "45s")
    """
    if uptime_seconds <= 0:
        return "not running"

    if uptime_seconds < 60:
        return f"{uptime_seconds}s"
    elif uptime_seconds < 3600:
        minutes = uptime_seconds // 60
        return f"{minutes}m"
    elif uptime_seconds < 86400:
        hours = uptime_seconds // 3600
        minutes = (uptime_seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    else:
        days = uptime_seconds // 86400
        hours = (uptime_seconds % 86400) // 3600
        return f"{days}d {hours}h"


def get_status_icon(health_state: str) -> str:
    """
    Map health state to status icon for UI display.

    Args:
        health_state: Health state (healthy/degraded/critical/disabled/unknown)

    Returns:
        Status icon (✓/⚠/✗/○/?)
    """
    icon_map = {
        "healthy": "✓",
        "degraded": "⚠",
        "critical": "✗",
        "disabled": "○",
        "unknown": "?"
    }
    return icon_map.get(health_state, "?")


def parse_systemctl_output(stdout: str) -> Dict[str, str]:
    """
    Parse KEY=VALUE format from systemctl show command into dict.

    Args:
        stdout: Output from systemctl show command

    Returns:
        Dictionary of property key-value pairs
    """
    properties = {}
    for line in stdout.strip().split("\n"):
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return properties


def safe_int(value: str, default: int = 0) -> int:
    """
    Safely convert a string to int, handling systemctl's '[not set]' values.

    Args:
        value: String value from systemctl (may be '[not set]')
        default: Default value if conversion fails

    Returns:
        Integer value or default
    """
    if not value or value == "[not set]" or value.strip() == "":
        return default
    try:
        return int(value)
    except ValueError:
        return default


def calculate_uptime(active_enter_timestamp: str) -> int:
    """
    Calculate service uptime in seconds from ActiveEnterTimestamp.

    Args:
        active_enter_timestamp: Timestamp string from systemctl (e.g., "Sat 2025-11-22 10:54:38 EST")

    Returns:
        Uptime in seconds (0 if service not active or timestamp invalid)
    """
    if not active_enter_timestamp or active_enter_timestamp == "":
        return 0

    try:
        # Parse timestamp - format: "Day YYYY-MM-DD HH:MM:SS TZ"
        # Note: This is a simplified parser - may need adjustment for locale variations
        from datetime import datetime
        import re

        # Remove day of week and timezone for simpler parsing
        # Example: "Sat 2025-11-22 10:54:38 EST" -> "2025-11-22 10:54:38"
        match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', active_enter_timestamp)
        if not match:
            return 0

        timestamp_str = match.group(1)
        start_time = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
        current_time = datetime.now()

        uptime_seconds = int((current_time - start_time).total_seconds())
        return max(0, uptime_seconds)  # Ensure non-negative

    except Exception as e:
        logging.warning(f"Failed to parse timestamp '{active_enter_timestamp}': {e}")
        return 0


def query_service_health(
    service_name: str,
    is_user_service: bool,
    socket_name: Optional[str] = None
) -> Dict[str, str]:
    """
    Query systemctl for service properties and return health data.

    Queries: LoadState, ActiveState, SubState, UnitFileState, MainPID, TriggeredBy,
             MemoryCurrent, NRestarts, ActiveEnterTimestamp (Feature 088 US2)

    Args:
        service_name: Service name (e.g., "eww-top-bar.service")
        is_user_service: True for user services (--user flag)
        socket_name: Socket unit name if socket-activated

    Returns:
        Dictionary of systemctl properties
    """
    # Add .service suffix if not present
    if not service_name.endswith(".service"):
        service_name = f"{service_name}.service"

    # Build systemctl command (Feature 088: Added MemoryCurrent, NRestarts, ActiveEnterTimestamp for US2)
    cmd = ["systemctl"]
    if is_user_service:
        cmd.append("--user")

    cmd.extend([
        "show",
        service_name,
        "-p", "LoadState,ActiveState,SubState,UnitFileState,MainPID,TriggeredBy,MemoryCurrent,NRestarts,ActiveEnterTimestamp",
        "--no-pager"
    ])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=2
        )

        properties = parse_systemctl_output(result.stdout)

        # If socket-activated and service is inactive, check socket status
        if socket_name and properties.get("TriggeredBy") == socket_name:
            socket_cmd = ["systemctl"]
            if is_user_service:
                socket_cmd.append("--user")

            socket_cmd.extend([
                "show",
                socket_name,
                "-p", "LoadState,ActiveState,SubState",
                "--no-pager"
            ])

            socket_result = subprocess.run(
                socket_cmd,
                capture_output=True,
                text=True,
                timeout=2
            )

            socket_props = parse_systemctl_output(socket_result.stdout)

            # If socket is active, service is healthy (even if inactive)
            if socket_props.get("ActiveState") == "active":
                properties["_socket_active"] = "true"

        return properties

    except subprocess.TimeoutExpired:
        logging.error(f"Timeout querying {service_name}")
        return {
            "LoadState": "error",
            "ActiveState": "unknown",
            "SubState": "unknown",
            "UnitFileState": "unknown",
            "MainPID": "0",
            "TriggeredBy": ""
        }
    except Exception as e:
        logging.error(f"Error querying {service_name}: {e}")
        return {
            "LoadState": "not-found",
            "ActiveState": "inactive",
            "SubState": "dead",
            "UnitFileState": "not-found",
            "MainPID": "0",
            "TriggeredBy": ""
        }


def build_service_health(
    service_def: Dict[str, Any],
    systemctl_props: Dict[str, str],
    monitor_profile: str
) -> Dict[str, Any]:
    """
    Construct ServiceHealth object from service definition and systemctl properties.

    Args:
        service_def: Service definition from registry (includes category)
        systemctl_props: Properties from systemctl show command
        monitor_profile: Current monitor profile

    Returns:
        ServiceHealth dictionary matching data-model.md schema
    """
    # Extract systemctl properties with defaults
    load_state = systemctl_props.get("LoadState", "unknown")
    active_state = systemctl_props.get("ActiveState", "unknown")
    sub_state = systemctl_props.get("SubState", "unknown")
    unit_file_state = systemctl_props.get("UnitFileState", "unknown")
    main_pid = safe_int(systemctl_props.get("MainPID", "0"), 0)
    restart_count = safe_int(systemctl_props.get("NRestarts", "0"), 0)

    # Feature 088 US2: Calculate uptime and memory usage
    active_enter_timestamp = systemctl_props.get("ActiveEnterTimestamp", "")
    uptime_seconds = calculate_uptime(active_enter_timestamp)
    uptime_friendly = format_uptime(uptime_seconds)

    # Convert memory from bytes to MB (handle [not set] gracefully)
    memory_bytes = safe_int(systemctl_props.get("MemoryCurrent", "0"), 0)
    memory_usage_mb = round(memory_bytes / 1024 / 1024, 1) if memory_bytes > 0 else 0.0

    # Determine if service should be active in current profile
    is_conditional = service_def.get("conditional", False)
    condition_profiles = service_def.get("condition_profiles", [])
    should_be_active = monitor_profile in condition_profiles if is_conditional else True

    # Classify health state
    health_state = classify_health_state(
        load_state=load_state,
        active_state=active_state,
        sub_state=sub_state,
        unit_file_state=unit_file_state,
        restart_count=restart_count,
        is_conditional=is_conditional,
        should_be_active=should_be_active
    )

    # Build ServiceHealth object
    service_health = {
        "service_name": service_def["name"],
        "display_name": service_def["display_name"],
        "category": service_def["category"],
        "description": service_def["description"],
        "is_user_service": service_def["is_user_service"],
        "is_socket_activated": service_def.get("socket_activated", False),
        "socket_name": service_def.get("socket_name"),
        "is_conditional": is_conditional,
        "condition_profiles": condition_profiles if is_conditional else None,
        "load_state": load_state,
        "active_state": active_state,
        "sub_state": sub_state,
        "unit_file_state": unit_file_state,
        "health_state": health_state,
        "main_pid": main_pid,
        "uptime_seconds": uptime_seconds,  # Feature 088 US2
        "memory_usage_mb": memory_usage_mb,  # Feature 088 US2
        "restart_count": restart_count,
        "last_active_time": active_enter_timestamp if active_enter_timestamp else None,  # Feature 088 US2
        "status_icon": get_status_icon(health_state),
        "uptime_friendly": uptime_friendly,  # Feature 088 US2
        "can_restart": health_state not in ["disabled"] and load_state != "not-found"
    }

    return service_health


def build_system_health(
    categories: List[Dict[str, Any]],
    monitor_profile: str
) -> Dict[str, Any]:
    """
    Aggregate category health into SystemHealth response with timestamp.

    Args:
        categories: List of ServiceCategory dicts
        monitor_profile: Current monitor profile

    Returns:
        SystemHealth dictionary matching data-model.md schema
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    # Calculate aggregate counts
    total_services = 0
    healthy_count = 0
    degraded_count = 0
    critical_count = 0
    disabled_count = 0
    unknown_count = 0

    for category in categories:
        total_services += category["total_count"]
        healthy_count += category["healthy_count"]
        degraded_count += category["degraded_count"]
        critical_count += category["critical_count"]
        disabled_count += category["disabled_count"]
        unknown_count += category["unknown_count"]

    # Determine overall system health
    if critical_count > 0:
        system_health = "critical"
    elif degraded_count > 0:
        system_health = "degraded"
    elif unknown_count > 0:
        system_health = "mixed"
    elif total_services == disabled_count:
        system_health = "mixed"
    else:
        system_health = "healthy"

    return {
        "timestamp": current_timestamp,
        "timestamp_friendly": friendly_time,
        "monitoring_functional": True,
        "current_monitor_profile": monitor_profile,
        "total_services": total_services,
        "healthy_count": healthy_count,
        "degraded_count": degraded_count,
        "critical_count": critical_count,
        "disabled_count": disabled_count,
        "unknown_count": unknown_count,
        "categories": categories,
        "system_health": system_health,
        "error": None
    }


async def query_health_data() -> Dict[str, Any]:
    """
    Query system health view data.

    Returns comprehensive service health monitoring data (Feature 088).
    Queries all systemd services from SERVICE_REGISTRY and returns structured health data.
    """
    try:
        # T036: Log health query start
        logging.info("Feature 088: Starting health query")

        # Read current monitor profile
        monitor_profile = read_monitor_profile()
        logging.info(f"Feature 088: Monitor profile: {monitor_profile}")

        # Get list of services to monitor based on profile
        monitored_services = get_monitored_services(monitor_profile)

        # Query health for each service
        service_health_list = []
        for service_def in monitored_services:
            systemctl_props = query_service_health(
                service_name=service_def["name"],
                is_user_service=service_def["is_user_service"],
                socket_name=service_def.get("socket_name")
            )

            service_health = build_service_health(
                service_def=service_def,
                systemctl_props=systemctl_props,
                monitor_profile=monitor_profile
            )

            service_health_list.append(service_health)

        # Group services by category
        categories_dict = {
            "core": {"category_name": "core", "display_name": "Core Daemons", "services": []},
            "ui": {"category_name": "ui", "display_name": "UI Services", "services": []},
            "system": {"category_name": "system", "display_name": "System Services", "services": []},
            "optional": {"category_name": "optional", "display_name": "Optional Services", "services": []}
        }

        for service_health in service_health_list:
            category_name = service_health["category"]
            categories_dict[category_name]["services"].append(service_health)

        # Calculate category-level health metrics
        categories = []
        for category_name, category_data in categories_dict.items():
            services = category_data["services"]

            # Count health states
            healthy_count = sum(1 for s in services if s["health_state"] == "healthy")
            degraded_count = sum(1 for s in services if s["health_state"] == "degraded")
            critical_count = sum(1 for s in services if s["health_state"] == "critical")
            disabled_count = sum(1 for s in services if s["health_state"] == "disabled")
            unknown_count = sum(1 for s in services if s["health_state"] == "unknown")

            # Determine category health
            if critical_count > 0:
                category_health = "critical"
            elif degraded_count > 0:
                category_health = "degraded"
            elif unknown_count > 0:
                category_health = "mixed"
            elif len(services) == disabled_count:
                category_health = "disabled"
            elif len(services) == healthy_count:
                category_health = "healthy"
            else:
                category_health = "mixed"

            categories.append({
                "category_name": category_name,
                "display_name": category_data["display_name"],
                "services": services,
                "total_count": len(services),
                "healthy_count": healthy_count,
                "degraded_count": degraded_count,
                "critical_count": critical_count,
                "disabled_count": disabled_count,
                "unknown_count": unknown_count,
                "category_health": category_health
            })

        # Build system health response
        system_health = build_system_health(categories, monitor_profile)

        # T036: Log successful health query
        logging.info(f"Feature 088: Health query complete - {system_health['total_services']} services, system health: {system_health['system_health']}")

        return {
            "status": "ok",
            "health": system_health,
            "timestamp": system_health["timestamp"],
            "timestamp_friendly": system_health["timestamp_friendly"],
            "error": None
        }

    except Exception as e:
        # T035: Error handling with logging
        logging.error(f"Feature 088: Health query failed: {type(e).__name__}: {e}")
        current_timestamp = time.time()
        return {
            "status": "error",
            "health": {
                "timestamp": current_timestamp,
                "timestamp_friendly": format_friendly_timestamp(current_timestamp),
                "monitoring_functional": False,
                "current_monitor_profile": "unknown",
                "total_services": 0,
                "healthy_count": 0,
                "degraded_count": 0,
                "critical_count": 0,
                "disabled_count": 0,
                "unknown_count": 0,
                "categories": [],
                "system_health": "critical",
                "error": f"Health query failed: {type(e).__name__}: {e}"
            },
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Health query failed: {type(e).__name__}: {e}"
        }


def _count_kubectl_rows(resource: str, namespaces: List[str], timeout_seconds: int = 3) -> Dict[str, Any]:
    """
    Count kubernetes resources with bounded command execution.

    Returns:
        {"count": int, "error": Optional[str]}
    """
    count = 0
    errors: List[str] = []

    namespace_targets = namespaces if namespaces else ["-A"]

    for namespace in namespace_targets:
        cmd = ["kubectl"]
        if namespace == "-A":
            cmd.extend(["get", resource, "-A", "--no-headers"])
        else:
            cmd.extend(["-n", namespace, "get", resource, "--no-headers"])

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired:
            errors.append(f"kubectl get {resource} timed out")
            continue
        except Exception as e:
            errors.append(f"kubectl get {resource} failed: {type(e).__name__}: {e}")
            continue

        if result.returncode != 0:
            message = (result.stderr or result.stdout or "").strip().splitlines()
            first_line = message[0] if message else f"exit={result.returncode}"
            errors.append(f"kubectl get {resource}: {first_line}")
            continue

        rows = [
            line for line in result.stdout.splitlines()
            if line.strip() and not line.startswith("No resources found")
        ]
        count += len(rows)

    return {
        "count": count,
        "error": "; ".join(errors) if errors else None,
    }


def _query_kubernetes_summary(namespaces: List[str]) -> Dict[str, Any]:
    """Query kubernetes summary metrics for tailscale tab."""
    scope = ",".join(namespaces) if namespaces else "all"

    summary = {
        "available": False,
        "context": "",
        "namespace_scope": scope,
        "ingress_count": 0,
        "service_count": 0,
        "deployment_count": 0,
        "daemonset_count": 0,
        "pod_count": 0,
        "error": None,
    }

    if not shutil.which("kubectl"):
        summary["error"] = "kubectl not found"
        return summary

    try:
        ctx_result = subprocess.run(
            ["kubectl", "config", "current-context"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except subprocess.TimeoutExpired:
        summary["error"] = "kubectl current-context timed out"
        return summary
    except Exception as e:
        summary["error"] = f"kubectl current-context failed: {type(e).__name__}: {e}"
        return summary

    if ctx_result.returncode != 0:
        ctx_error = (ctx_result.stderr or ctx_result.stdout or "").strip()
        summary["error"] = f"kubectl context unavailable: {ctx_error or 'unknown error'}"
        return summary

    summary["context"] = ctx_result.stdout.strip()

    ingress = _count_kubectl_rows("ingress", namespaces)
    services = _count_kubectl_rows("services", namespaces)
    deployments = _count_kubectl_rows("deployments", namespaces)
    daemonsets = _count_kubectl_rows("daemonsets", namespaces)
    pods = _count_kubectl_rows("pods", namespaces)

    summary["ingress_count"] = ingress["count"]
    summary["service_count"] = services["count"]
    summary["deployment_count"] = deployments["count"]
    summary["daemonset_count"] = daemonsets["count"]
    summary["pod_count"] = pods["count"]

    errors = [
        item["error"] for item in [ingress, services, deployments, daemonsets, pods]
        if item["error"]
    ]
    if errors:
        summary["error"] = "; ".join(errors)
        summary["available"] = False
    else:
        summary["available"] = True

    return summary


async def query_tailscale_data() -> Dict[str, Any]:
    """
    Query tailscale/network + kubernetes summary data.

    Local-first implementation:
    - tailscale status --json
    - systemctl is-active tailscaled
    - kubectl summary counts (bounded timeouts)
    """
    current_timestamp = time.time()
    friendly_time = format_friendly_timestamp(current_timestamp)

    issues: List[str] = []
    tailscale_status_ok = False
    service_status_ok = False

    tailscale_json: Dict[str, Any] = {}
    tailscale_available = shutil.which("tailscale") is not None

    if tailscale_available:
        try:
            tailscale_result = subprocess.run(
                ["tailscale", "status", "--json"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            if tailscale_result.returncode == 0:
                tailscale_json = json.loads(tailscale_result.stdout or "{}")
                tailscale_status_ok = True
            else:
                message = (tailscale_result.stderr or tailscale_result.stdout or "").strip().splitlines()
                issues.append(f"tailscale status failed: {message[0] if message else 'unknown error'}")
        except subprocess.TimeoutExpired:
            issues.append("tailscale status timed out")
        except json.JSONDecodeError:
            issues.append("tailscale status returned invalid JSON")
        except Exception as e:
            issues.append(f"tailscale status failed: {type(e).__name__}: {e}")
    else:
        issues.append("tailscale command not found")

    service = {
        "tailscaled_active": False,
        "tailscaled_state": "unknown",
    }

    if shutil.which("systemctl"):
        try:
            service_result = subprocess.run(
                ["systemctl", "is-active", "tailscaled"],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
            service_state = (service_result.stdout or service_result.stderr or "").strip() or "unknown"
            service["tailscaled_state"] = service_state
            service["tailscaled_active"] = service_result.returncode == 0 and service_state == "active"
            service_status_ok = True
        except subprocess.TimeoutExpired:
            issues.append("systemctl tailscaled query timed out")
        except Exception as e:
            issues.append(f"systemctl tailscaled query failed: {type(e).__name__}: {e}")
    else:
        issues.append("systemctl not found")

    self_data = {
        "hostname": "",
        "dns_name": "",
        "online": False,
        "tailscale_ips": [],
        "tailnet": "",
        "exit_node": False,
        "backend_state": "",
        "health_messages": [],
    }
    peers = {
        "total": 0,
        "online": 0,
        "offline": 0,
        "tagged": 0,
        "direct": 0,
        "all": [],
    }

    if tailscale_status_ok:
        self_node = tailscale_json.get("Self") or {}
        current_tailnet = tailscale_json.get("CurrentTailnet") or {}
        peer_map = tailscale_json.get("Peer") or {}
        health_messages = tailscale_json.get("Health") or []

        self_ips = self_node.get("TailscaleIPs", []) if isinstance(self_node.get("TailscaleIPs"), list) else []
        self_ip = ""
        for addr in self_ips:
            if "." in str(addr) and not self_ip:
                self_ip = str(addr)
        self_data = {
            "hostname": str(self_node.get("HostName", "")),
            "dns_name": str(self_node.get("DNSName", "")).rstrip("."),
            "online": bool(self_node.get("Online", False)),
            "tailscale_ips": self_ips,
            "ip": self_ip,
            "tailnet": str(current_tailnet.get("Name", "")),
            "exit_node": bool(self_node.get("ExitNode", False)),
            "backend_state": str(tailscale_json.get("BackendState", "")),
            "health_messages": [str(m) for m in health_messages if str(m).strip()],
        }

        if isinstance(peer_map, dict):
            from datetime import datetime, timezone

            def _relative_expiry(expiry_str: str) -> str:
                """Compute relative key expiry like 'in 109d' or 'expired 3d ago'."""
                if not expiry_str:
                    return ""
                try:
                    exp = datetime.fromisoformat(expiry_str.replace("Z", "+00:00"))
                    now = datetime.now(timezone.utc)
                    delta = exp - now
                    days = delta.days
                    if days > 0:
                        return f"in {days}d"
                    elif days == 0:
                        return "today"
                    else:
                        return f"expired {abs(days)}d ago"
                except (ValueError, TypeError):
                    return ""

            peer_list = []
            for peer in peer_map.values():
                if not isinstance(peer, dict):
                    continue
                hostname = str(peer.get("HostName", "")).strip()
                dns_name = str(peer.get("DNSName", "")).rstrip(".")
                ips = peer.get("TailscaleIPs", [])
                ip = ""
                ip6 = ""
                if isinstance(ips, list):
                    for addr in ips:
                        addr_str = str(addr)
                        if ":" in addr_str and not ip6:
                            ip6 = addr_str
                        elif "." in addr_str and not ip:
                            ip = addr_str
                tags = peer.get("Tags") or []
                if not isinstance(tags, list):
                    tags = []
                tags = [str(t) for t in tags]
                cur_addr = str(peer.get("CurAddr", "") or "")
                relay = str(peer.get("Relay", "") or "")
                peer_list.append({
                    "hostname": hostname or dns_name or "unknown",
                    "dns_name": dns_name,
                    "online": bool(peer.get("Online", False)),
                    "ip": ip,
                    "ip6": ip6,
                    "os": str(peer.get("OS", "") or ""),
                    "tags": tags,
                    "tags_str": ",".join(tags),
                    "is_tagged": len(tags) > 0,
                    "connection": "direct" if cur_addr else "relay",
                    "cur_addr": cur_addr,
                    "relay": relay,
                    "key_expiry": _relative_expiry(peer.get("KeyExpiry", "")),
                    "exit_node": bool(peer.get("ExitNode", False)),
                    "active": bool(peer.get("Active", False)),
                })

            online_count = sum(1 for p in peer_list if p["online"])
            tagged_count = sum(1 for p in peer_list if p["is_tagged"])
            direct_count = sum(1 for p in peer_list if p["connection"] == "direct")
            peers = {
                "total": len(peer_list),
                "online": online_count,
                "offline": len(peer_list) - online_count,
                "tagged": tagged_count,
                "direct": direct_count,
                "all": sorted(
                    peer_list,
                    key=lambda p: (not p["online"], p["hostname"].lower()),
                ),
            }
        else:
            issues.append("tailscale peer map missing")

    namespaces_env = os.environ.get("EWW_TAILSCALE_K8S_NAMESPACES", "")
    namespaces = [ns.strip() for ns in namespaces_env.split(",") if ns.strip()]
    kubernetes = _query_kubernetes_summary(namespaces)
    if kubernetes.get("error"):
        issues.append(f"kubernetes summary unavailable: {kubernetes['error']}")

    if not tailscale_status_ok and not service_status_ok:
        status = "error"
    elif issues:
        status = "partial"
    else:
        status = "ok"

    kubernetes_actions_available = bool(kubernetes.get("available"))

    return {
        "status": status,
        "timestamp": current_timestamp,
        "timestamp_friendly": friendly_time,
        "self": self_data,
        "service": service,
        "peers": peers,
        "kubernetes": kubernetes,
        "api": {
            "enabled": False,
            "status": "disabled",
        },
        "actions": {
            "reconnect": tailscale_available,
            "restart_service": False,
            "set_exit_node": False,
            "k8s_rollout_restart": kubernetes_actions_available,
            "k8s_restart_daemonset": kubernetes_actions_available,
        },
        "error": "; ".join(issues) if issues else None,
    }


async def query_traces_data() -> Dict[str, Any]:
    """
    Query window traces view data (Feature 101).

    Returns list of active and stopped traces from the daemon's WindowTracer.
    Each trace contains:
    - trace_id: Unique identifier
    - window_id: Sway window ID being traced
    - matcher: Pattern used to match windows
    - is_active: Whether trace is still running
    - event_count: Number of events recorded
    - duration_seconds: Time since trace started
    - started_at: ISO timestamp

    Returns:
        Dict with status, traces list, and metadata
    """
    current_timestamp = time.time()
    # Feature 117: User socket only (daemon runs as user service)
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    default_socket = f"{runtime_dir}/i3-project-daemon/ipc.sock"
    socket_path = os.environ.get("I3PM_DAEMON_SOCKET", default_socket)

    try:
        logging.info("Feature 101: Starting traces query")

        # Connect to daemon and query traces
        client = DaemonClient(socket_path=socket_path, timeout=2.0)
        await client.connect()

        try:
            result = await client.call("trace.list", {})
            traces = result.get("traces", [])
            count = result.get("count", len(traces))
        finally:
            await client.close()

        # Format each trace for display
        formatted_traces = []
        for trace in traces:
            formatted_traces.append({
                "trace_id": trace.get("trace_id", ""),
                "window_id": trace.get("window_id"),
                "matcher": trace.get("matcher", {}),
                "matcher_display": " ".join(f"{k}={v}" for k, v in trace.get("matcher", {}).items()),
                "is_active": trace.get("is_active", False),
                "event_count": trace.get("event_count", 0),
                "duration_seconds": trace.get("duration_seconds", 0.0),
                "duration_display": f"{trace.get('duration_seconds', 0.0):.1f}s",
                "started_at": trace.get("started_at", ""),
                "status_icon": "🔴" if trace.get("is_active") else "⏹",
                "status_label": "ACTIVE" if trace.get("is_active") else "STOPPED"
            })

        return {
            "status": "ok",
            "traces": formatted_traces,
            "trace_count": count,
            "active_count": sum(1 for t in formatted_traces if t["is_active"]),
            "stopped_count": sum(1 for t in formatted_traces if not t["is_active"]),
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp)
        }

    except DaemonError as e:
        logging.error(f"Feature 101: Daemon error querying traces: {e}")
        return {
            "status": "error",
            "traces": [],
            "trace_count": 0,
            "active_count": 0,
            "stopped_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Daemon error: {e}"
        }
    except Exception as e:
        logging.exception(f"Feature 101: Failed to query traces: {e}")
        return {
            "status": "error",
            "traces": [],
            "trace_count": 0,
            "active_count": 0,
            "stopped_count": 0,
            "timestamp": current_timestamp,
            "timestamp_friendly": format_friendly_timestamp(current_timestamp),
            "error": f"Query failed: {type(e).__name__}: {e}"
        }


async def stream_monitoring_data():
    """
    Stream monitoring data to stdout on daemon events (deflisten mode).

    Features:
    - Feature 123: Subscribes to daemon state changes (not Sway directly)
      This eliminates the double Sway IPC subscription overhead.
      Daemon caches window tree and notifies when state changes.
    - Feature 107: Uses inotify for immediate badge detection (<15ms latency)
    - Outputs JSON on every event (<100ms latency)
    - Heartbeat every 5s to detect stale connections
    - Automatic reconnection with exponential backoff (1s, 2s, 4s, max 10s)
    - Graceful shutdown on SIGTERM/SIGINT/SIGPIPE

    Exit codes:
        0: Graceful shutdown (signal received)
        1: Fatal error (cannot recover)
    """
    from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

    setup_signal_handlers()
    logger.info("Starting event stream mode (deflisten) - Feature 123: Using daemon subscription")

    reconnect_delay = 1.0  # Start with 1s delay
    max_reconnect_delay = 10.0
    last_update = 0.0
    # Feature 123: Increased heartbeat from 5s to 30s since daemon subscription
    # handles real-time events. Heartbeat is only a fallback for missed events.
    heartbeat_interval = 30.0

    # Feature 107: Start inotify watcher for badge directory
    badge_watcher_process: Optional[asyncio.subprocess.Process] = None
    badge_change_event = asyncio.Event()
    inotify_reader_task: Optional[asyncio.Task] = None
    use_inotify = True  # Will be set to False if inotifywait unavailable

    try:
        badge_watcher_process = await create_badge_watcher()
        if badge_watcher_process:
            inotify_reader_task = asyncio.create_task(
                read_inotify_events(badge_watcher_process, badge_change_event)
            )
            logger.info("Feature 107: inotify watcher active for badge detection")
        else:
            use_inotify = False
            logger.info("Feature 107: Falling back to polling for badge detection")
    except Exception as e:
        logger.warning(f"Feature 107: Failed to start inotify: {e}, using polling")
        use_inotify = False

    while not shutdown_requested:
        try:
            # Feature 123: Connect to daemon for state change subscription
            logger.info("Feature 123: Connecting to daemon for state change subscription...")
            daemon_client = DaemonClient(timeout=10.0)
            await daemon_client.connect()
            logger.info("Feature 123: Connected to daemon")

            # Reset reconnect delay on successful connection
            reconnect_delay = 1.0

            # Query and output initial state
            data = await query_monitoring_data()
            initial_json = json.dumps(data, separators=(",", ":"))
            print(initial_json, flush=True)
            last_update = time.time()
            logger.info("Sent initial state")

            # OPTIMIZATION: Change detection - track last payload hash to skip duplicates
            import hashlib
            last_payload_hash = hashlib.md5(initial_json.encode()).hexdigest()
            # Feature 123: Store last payload for heartbeat (avoid re-query)
            last_payload_json = initial_json

            # Feature 123: Daemon state change event for triggering refresh
            daemon_state_change_event = asyncio.Event()

            # Feature 095 Enhancement: Track if we have working badges for spinner animation
            has_working_badge = False

            async def refresh_and_output():
                """Query daemon and output updated JSON with change detection."""
                nonlocal last_update, has_working_badge, last_payload_hash, last_payload_json
                try:
                    data = await query_monitoring_data()
                    # Track if we have working badges to enable spinner updates
                    has_working_badge = data.get("has_working_badge", False)

                    # OPTIMIZATION: Change detection - skip if payload unchanged
                    payload_json = json.dumps(data, separators=(",", ":"))
                    payload_hash = hashlib.md5(payload_json.encode()).hexdigest()

                    if payload_hash != last_payload_hash:
                        print(payload_json, flush=True)
                        last_payload_hash = payload_hash
                        last_payload_json = payload_json  # Feature 123: Store for heartbeat
                        last_update = time.time()
                        logger.debug(f"Output updated (hash changed)")
                    else:
                        logger.debug(f"Skipped output (no change)")
                except Exception as e:
                    logger.warning(f"Error refreshing data: {e}")

            # Feature 123: Subscribe to daemon state changes
            # This creates a background task that sets daemon_state_change_event when notified
            async def daemon_subscription_task():
                """Background task to receive daemon state change notifications."""
                try:
                    async for event in daemon_client.subscribe_state_changes():
                        if shutdown_requested:
                            break
                        event_type = event.get("type", "unknown")
                        logger.debug(f"Feature 123: Daemon state change: {event_type}")
                        daemon_state_change_event.set()
                except DaemonError as e:
                    logger.warning(f"Feature 123: Daemon subscription error: {e}")
                except asyncio.CancelledError:
                    pass
                except Exception as e:
                    logger.error(f"Feature 123: Unexpected daemon subscription error: {e}")

            # Start daemon subscription task
            subscription_task = asyncio.create_task(daemon_subscription_task())
            logger.info("Feature 123: Subscribed to daemon state changes")

            # Feature 095 Enhancement: Spinner animation interval (120ms)
            # Only used when has_working_badge is True
            spinner_interval = SPINNER_INTERVAL_MS / 1000.0  # Convert to seconds
            last_spinner_update = time.time()

            # Feature 107: Polling fallback interval (500ms when inotify unavailable)
            # Only used when inotify is not available
            polling_fallback_interval = 0.5  # 500ms
            last_polling_check = time.time()

            # Feature 123: Simple event-driven loop using asyncio.sleep
            # The daemon_subscription_task sets daemon_state_change_event when updates arrive.
            # We use short sleeps and check the event flag - much lower overhead than asyncio.wait()
            while not shutdown_requested:
                current_time = time.time()

                # Feature 123: Check for daemon state change notification
                if daemon_state_change_event.is_set():
                    daemon_state_change_event.clear()
                    logger.debug("Feature 123: Daemon state change triggered refresh")
                    await refresh_and_output()

                # Feature 107: Check for inotify-triggered badge changes
                elif use_inotify and badge_change_event.is_set():
                    badge_change_event.clear()
                    logger.debug("Feature 107: inotify triggered badge refresh")
                    await refresh_and_output()

                # Feature 107: Polling fallback when inotify unavailable
                elif not use_inotify and not has_working_badge:
                    if (current_time - last_polling_check) >= polling_fallback_interval:
                        badge_state = load_badge_state_from_files()
                        if any(b.get("state") == "working" for b in badge_state.values()):
                            logger.debug("Feature 095: Detected working badge from file (polling), triggering refresh")
                            await refresh_and_output()
                        last_polling_check = current_time

                # Feature 095 Enhancement: Spinner animation is now handled by EWW defpoll
                # (spinner_frame and spinner_opacity), so we don't need to refresh here.
                # This prevents 20 updates/second which caused hover flickering.

                # Send heartbeat if no updates in last N seconds (normal mode)
                # Feature 123: Heartbeat doesn't re-query daemon since subscription handles events.
                # Just output last known state to keep EWW deflisten alive.
                elif current_time - last_update > heartbeat_interval:
                    logger.debug("Sending heartbeat (no query)")
                    # Output last known state without re-querying daemon
                    print(last_payload_json, flush=True)
                    last_update = current_time

                # Feature 123: Sleep duration - daemon subscription handles real-time events
                # Use asyncio.wait to wake up instantly when an event is set, 
                # falling back to 1.0s timeout to maintain loop consistency.
                wait_tasks = [asyncio.create_task(daemon_state_change_event.wait())]
                if use_inotify:
                    wait_tasks.append(asyncio.create_task(badge_change_event.wait()))
                
                done, pending = await asyncio.wait(
                    wait_tasks, 
                    timeout=1.0, 
                    return_when=asyncio.FIRST_COMPLETED
                )
                for task in pending:
                    task.cancel()

            # Cleanup subscription task
            subscription_task.cancel()
            try:
                await subscription_task
            except asyncio.CancelledError:
                pass
            await daemon_client.close()

        except DaemonError as e:
            # Feature 123: Handle daemon connection/subscription errors
            logger.warning(f"Feature 123: Daemon error: {e}, reconnecting in {reconnect_delay}s")
            await asyncio.sleep(reconnect_delay)
            # Exponential backoff
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

        except ConnectionError as e:
            logger.warning(f"Connection lost: {e}, reconnecting in {reconnect_delay}s")
            await asyncio.sleep(reconnect_delay)
            # Exponential backoff
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

        except Exception as e:
            logger.error(f"Unexpected error in stream loop: {e}", exc_info=True)
            await asyncio.sleep(reconnect_delay)
            reconnect_delay = min(reconnect_delay * 2, max_reconnect_delay)

    # Feature 107: Cleanup inotify watcher
    if inotify_reader_task:
        inotify_reader_task.cancel()
        try:
            await inotify_reader_task
        except asyncio.CancelledError:
            pass
    if badge_watcher_process:
        try:
            if badge_watcher_process.returncode is None:
                badge_watcher_process.terminate()
            await badge_watcher_process.wait()
            logger.info("Feature 107: inotify watcher stopped")
        except ProcessLookupError:
            logger.debug("Feature 107: inotify watcher already exited")

    logger.info("Shutdown complete")
    sys.exit(0)


# =============================================================================
# Feature 092: Event Logging - Backend Implementation
# =============================================================================

# Global event buffer (initialized on first stream)
_event_buffer: Optional[EventBuffer] = None


async def query_events_data() -> Dict[str, Any]:
    """
    Query events data (one-shot mode).

    Returns current event buffer state. Buffer must be initialized by stream mode first.

    Returns:
        EventsViewData as dict (Pydantic model_dump)
    """
    global _event_buffer

    current_time = time.time()

    # If buffer not initialized, return empty state
    if _event_buffer is None:
        view_data = EventsViewData(
            status="ok",
            events=[],
            event_count=0,
            oldest_timestamp=None,
            newest_timestamp=None,
            daemon_available=True,
            ipc_connected=False,
            timestamp=current_time,
            timestamp_friendly=format_friendly_timestamp(current_time),
        )
        return view_data.model_dump(mode="json")

    # Get all events from buffer (refresh timestamps for accurate display)
    events = _event_buffer.get_all(refresh_timestamps=True)

    # Feature 102 T066-T067: Compute cross-reference validity
    # Build sets of valid trace_ids and correlation_ids (root events only)
    valid_trace_ids: set = set()
    root_correlation_ids: set = set()
    for event in events:
        if event.trace_id:
            valid_trace_ids.add(event.trace_id)
        # Root events have correlation_id but causality_depth == 0
        if event.correlation_id and event.causality_depth == 0:
            root_correlation_ids.add(event.correlation_id)

    # Mark events with evicted traces or missing parents
    for event in events:
        # T066: Check if trace_id references a trace not in current view
        # (This is a simplified check - ideally we'd query daemon for trace existence)
        # For now, we mark as evicted if trace_id is set but not in valid_trace_ids
        # Actually, all events with trace_id should be in valid_trace_ids by construction
        # So we skip this for now - the trace_evicted field is for future daemon integration

        # T067: Check if event has parent correlation but parent is missing
        if event.correlation_id and event.causality_depth > 0:
            if event.correlation_id not in root_correlation_ids:
                event.parent_missing = True

    # Feature 102 T053: Create duration-sorted list (slowest first)
    events_by_duration = sorted(
        events,
        key=lambda e: e.processing_duration_ms,
        reverse=True  # Slowest first
    )

    view_data = EventsViewData(
        status="ok",
        events=events,
        events_by_duration=events_by_duration,
        event_count=len(events),
        oldest_timestamp=events[0].timestamp if events else None,
        newest_timestamp=events[-1].timestamp if events else None,
        daemon_available=True,
        ipc_connected=True,
        timestamp=current_time,
        timestamp_friendly=format_friendly_timestamp(current_time),
    )

    return view_data.model_dump(mode="json")


async def stream_events():
    """
    Stream events (deflisten mode) - Feature 092.

    Subscribes to Sway IPC window/workspace/output events and outputs JSON to stdout.
    Similar architecture to stream_monitoring_data() but focused on event logging.
    """
    global _event_buffer

    # Initialize buffer
    _event_buffer = EventBuffer(max_size=500)

    # Setup signal handlers for graceful shutdown
    shutdown_event = asyncio.Event()

    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating shutdown")
        shutdown_event.set()

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Connect to Sway IPC
    try:
        conn = await I3Connection(auto_reconnect=True).connect()
        logger.info("Connected to Sway IPC for event streaming")
    except Exception as e:
        logger.critical(f"Failed to connect to Sway IPC: {e}")
        error_time = time.time()
        error_data = EventsViewData(
            status="error",
            error=f"Sway IPC connection failed: {e}",
            events=[],
            event_count=0,
            daemon_available=False,
            ipc_connected=False,
            timestamp=error_time,
            timestamp_friendly=format_friendly_timestamp(error_time),
        )
        print(json.dumps(error_data.model_dump(mode="json"), separators=(",", ":")))
        sys.exit(1)

    # Event handlers
    def create_event_from_sway(event_type: EventType, change_type: str, sway_payload: Dict[str, Any]) -> Event:
        """Helper to create Event from Sway IPC event."""
        current_time = time.time()

        # Get icon, color, and source from EVENT_ICONS (Feature 102: T017)
        icon_data = EVENT_ICONS.get(event_type, {"icon": "󰀄", "color": "#a6adc8", "source": "sway"})
        icon = icon_data["icon"]
        color = icon_data["color"]
        source = icon_data.get("source", "sway")  # Default to "sway" for backwards compatibility

        # Determine category - Feature 102: Added i3pm categories (T017)
        if event_type.startswith("window::"):
            category = "window"
        elif event_type.startswith("workspace::"):
            category = "workspace"
        elif event_type.startswith("output::"):
            category = "output"
        elif event_type.startswith("binding::"):
            category = "binding"
        elif event_type.startswith("mode::"):
            category = "mode"
        elif event_type.startswith("project::"):
            category = "project"
        elif event_type.startswith("visibility::"):
            category = "visibility"
        elif event_type.startswith("scratchpad::"):
            category = "scratchpad"
        elif event_type.startswith("launch::"):
            category = "launch"
        elif event_type.startswith("state::"):
            category = "state"
        elif event_type.startswith("command::"):
            category = "command"
        elif event_type.startswith("trace::"):
            category = "trace"
        else:
            category = "system"

        # Build searchable text (basic version)
        searchable_parts = [event_type, change_type]
        if "container" in sway_payload and sway_payload["container"]:
            container = sway_payload["container"]
            searchable_parts.append(container.get("app_id", ""))
            searchable_parts.append(container.get("name", ""))
        if "current" in sway_payload and sway_payload["current"]:
            searchable_parts.append(str(sway_payload["current"].get("num", "")))

        searchable_text = " ".join(filter(None, searchable_parts))

        # Create payload model
        payload = SwayEventPayload(**sway_payload)

        # Feature 102 (T028): Extract trace cross-reference fields
        trace_id = sway_payload.get("trace_id")
        correlation_id = sway_payload.get("correlation_id")
        causality_depth = sway_payload.get("causality_depth", 0)

        # Feature 102 T052: Extract processing duration from daemon events
        processing_duration_ms = sway_payload.get("processing_duration_ms", 0.0)

        return Event(
            timestamp=current_time,
            timestamp_friendly=format_friendly_timestamp(current_time),
            event_type=event_type,
            change_type=change_type,
            payload=payload,
            enrichment=None,  # TODO: Add daemon enrichment in future iteration
            icon=icon,
            color=color,
            source=source,  # Feature 102: T017
            category=category,
            trace_id=trace_id,  # Feature 102: T028
            correlation_id=correlation_id,  # Feature 102: T028
            causality_depth=causality_depth,  # Feature 102: T028
            processing_duration_ms=processing_duration_ms,  # Feature 102: T052
            searchable_text=searchable_text,
        )

    def on_window_event(conn, event):
        """Handle window events."""
        try:
            change = event.change
            event_type = f"window::{change}"

            # Extract payload
            # Note: hasattr returns True even if the attribute is None, so we need to also check for None
            sway_payload = {
                "container": event.container.ipc_data if hasattr(event, "container") and event.container is not None else None,
                "change": change,
            }

            # Create and buffer event
            evt = create_event_from_sway(event_type, change, sway_payload)
            _event_buffer.append(evt)

            # Output immediately (refresh timestamps for accurate display)
            current_output_time = time.time()
            events_with_fresh_timestamps = _event_buffer.get_all(refresh_timestamps=True)
            perf_stats = _event_buffer.get_performance_stats()  # Feature 102 T054
            view_data = EventsViewData(
                status="ok",
                events=events_with_fresh_timestamps,
                event_count=_event_buffer.size(),
                oldest_timestamp=events_with_fresh_timestamps[0].timestamp if _event_buffer.size() > 0 else None,
                newest_timestamp=events_with_fresh_timestamps[-1].timestamp if _event_buffer.size() > 0 else None,
                avg_duration_ms=perf_stats["avg_duration_ms"],
                slow_event_count=perf_stats["slow_event_count"],
                critical_event_count=perf_stats["critical_event_count"],
                daemon_available=True,
                ipc_connected=True,
                timestamp=current_output_time,
                timestamp_friendly=format_friendly_timestamp(current_output_time),
            )
            print(json.dumps(view_data.model_dump(mode="json"), separators=(",", ":")), flush=True)

        except Exception as e:
            logger.error(f"Error handling window event: {e}", exc_info=True)

    def on_workspace_event(conn, event):
        """Handle workspace events."""
        try:
            change = event.change
            event_type = f"workspace::{change}"

            # Extract payload
            # Note: hasattr returns True even if the attribute is None, so we need to also check for None
            sway_payload = {
                "current": event.current.ipc_data if hasattr(event, "current") and event.current is not None else None,
                "old": event.old.ipc_data if hasattr(event, "old") and event.old is not None else None,
                "change": change,
            }

            # Create and buffer event
            evt = create_event_from_sway(event_type, change, sway_payload)
            _event_buffer.append(evt)

            # Output immediately (refresh timestamps for accurate display)
            current_output_time = time.time()
            events_with_fresh_timestamps = _event_buffer.get_all(refresh_timestamps=True)
            perf_stats = _event_buffer.get_performance_stats()  # Feature 102 T054
            view_data = EventsViewData(
                status="ok",
                events=events_with_fresh_timestamps,
                event_count=_event_buffer.size(),
                oldest_timestamp=events_with_fresh_timestamps[0].timestamp if _event_buffer.size() > 0 else None,
                newest_timestamp=events_with_fresh_timestamps[-1].timestamp if _event_buffer.size() > 0 else None,
                avg_duration_ms=perf_stats["avg_duration_ms"],
                slow_event_count=perf_stats["slow_event_count"],
                critical_event_count=perf_stats["critical_event_count"],
                daemon_available=True,
                ipc_connected=True,
                timestamp=current_output_time,
                timestamp_friendly=format_friendly_timestamp(current_output_time),
            )
            print(json.dumps(view_data.model_dump(mode="json"), separators=(",", ":")), flush=True)

        except Exception as e:
            logger.error(f"Error handling workspace event: {e}", exc_info=True)

    # Subscribe to events
    conn.on("window", on_window_event)
    conn.on("workspace", on_workspace_event)

    logger.info("Event subscriptions active, streaming to stdout")

    # Keep running until shutdown
    try:
        await shutdown_event.wait()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    finally:
        logger.info("Shutting down event stream")
        await conn.close()
        sys.exit(0)


async def main():
    """
    Main entry point for backend script.

    Modes:
    - windows (default): Window/project hierarchy view
    - projects: Project list view
    - apps: Application registry view
    - tailscale: Tailscale + Kubernetes status view
    - health: System health view
    - events: Sway IPC event log view (Feature 092)
    - traces: Window traces view (Feature 101)
    - Stream (--listen): Continuous event stream (deflisten mode)

    Exit codes:
        0: Success (status: "ok" or graceful shutdown)
        1: Error (status: "error" or fatal error)
    """
    # Parse arguments
    parser = argparse.ArgumentParser(description="Monitoring panel data backend")
    parser.add_argument(
        "--mode",
        choices=["windows", "projects", "apps", "tailscale", "health", "events", "traces"],
        default="windows",
        help="View mode (default: windows)"
    )
    parser.add_argument(
        "--listen",
        action="store_true",
        help="Stream mode (deflisten) - works with windows and events modes"
    )
    args = parser.parse_args()

    # Stream mode (for windows or events view)
    if args.listen:
        if args.mode == "windows":
            await stream_monitoring_data()
            return
        elif args.mode == "events":
            await stream_events()
            return
        else:
            logger.error(f"--listen flag only works with windows or events mode, got: {args.mode}")
            sys.exit(1)

    # One-shot mode - route to appropriate query function
    try:
        if args.mode == "windows":
            data = await query_monitoring_data()
        elif args.mode == "projects":
            data = await query_projects_data()
        elif args.mode == "apps":
            data = await query_apps_data()
        elif args.mode == "tailscale":
            data = await query_tailscale_data()
        elif args.mode == "health":
            data = await query_health_data()
        elif args.mode == "events":
            data = await query_events_data()
        elif args.mode == "traces":
            data = await query_traces_data()
        else:
            raise ValueError(f"Unknown mode: {args.mode}")

        # Output single-line JSON (no formatting for Eww parsing performance)
        # Use separators parameter to minimize output size
        print(json.dumps(data, separators=(",", ":")))

        # Exit with appropriate code
        # "partial" = valid data with degraded subsystems → exit 0 so EWW gets clean JSON
        # Only "error" (no usable data at all) exits non-zero to trigger the shell fallback
        sys.exit(0 if data.get("status") != "error" else 1)

    except Exception as e:
        # Catastrophic failure - output error JSON and exit with error code
        logger.critical(f"Fatal error in main(): {e}", exc_info=True)
        error_timestamp = time.time()
        error_data = {
            "status": "error",
            "data": {},
            "timestamp": error_timestamp,
            "timestamp_friendly": format_friendly_timestamp(error_timestamp),
            "error": f"Fatal error: {type(e).__name__}: {e}",
        }
        print(json.dumps(error_data, separators=(",", ":")))
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
# Feature 095 Enhancement build marker: 1764104128
