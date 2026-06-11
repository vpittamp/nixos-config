"""JSON-RPC IPC server for daemon queries.

Exposes daemon state via UNIX socket with systemd socket activation support.

Updated: 2025-10-22 - Added Deno CLI compatibility (aliases + response formats)
Updated: 2025-10-23 - Added unified event logging for all IPC methods
"""

import asyncio
import hashlib
import json
import logging
import os
import re
import shlex
import socket
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from xdg.DesktopEntry import DesktopEntry
    from xdg.IconTheme import getIconPath
except Exception:  # pragma: no cover
    DesktopEntry = None

    def getIconPath(_icon_name: str, _size: int) -> Optional[str]:
        return None

from .state import StateManager
from .window_rules import WindowRule
from .pattern_resolver import classify_window
from .models import EventEntry
from . import window_filtering  # Feature 037: Window filtering utilities
from .worktree_utils import (
    canonicalize_context_key,
    is_qualified_name,
    parse_context_key,
    parse_mark,
    parse_qualified_name,
)  # Feature 101
from .constants import ConfigPaths  # Feature 101
from .config import atomic_write_json  # Feature 137: Atomic file writes
from .services.window_filter import (
    clear_pid_environ_cache,
    parse_window_environment,
    read_process_environ_with_fallback,
)
from .services.registry_loader import RegistryLoader, RegistryApp
from .services.dashboard_model import (
    DASHBOARD_EVENT_SCHEMA_VERSION,
    DASHBOARD_SCHEMA_VERSION,
    build_dashboard_projects as build_dashboard_project_cards,
)
from .services.daemon_contract_service import DaemonContractService
from .services.dashboard_service import DashboardService
from .services.dashboard_git_service import DashboardGitService
from .services.dashboard_worktree_service import DashboardWorktreeService
from .services.daemon_status_service import DaemonStatusService
from .services.display_service import DisplayService
from .services.focus_service import FocusService
from .services.herdr_service import HerdrService, RETIRED_SESSION_UI_STATE_FIELDS
from .services.launch_service import LaunchService
from .services.worktree_profile_service import WorktreeProfileService
from .models.window_command import CommandBatch

logger = logging.getLogger(__name__)

ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]

DESKTOP_DIRS = [
    Path.home() / ".local/share/i3pm-applications/applications",
    Path.home() / ".local/share/applications",
    Path("/usr/share/applications"),
]

ICON_EXTENSIONS = (".svg", ".png", ".xpm")
APP_REGISTRY_PATH = Path.home() / ".config/i3/application-registry.json"
PWA_REGISTRY_PATH = Path.home() / ".config/i3/pwa-registry.json"
CHROME_SCOPED_TMP_PREFIX = "/tmp/com.google.Chrome.scoped_dir."
FOCUS_STATE_SCHEMA_VERSION = "i3pm.focus_state.v2"

_DISCOVERED_WORKTREE_CACHE: Dict[str, Any] = {
    "file_path": "",
    "mtime_ns": None,
    "size": None,
    "by_path": {},
    "by_qualified_name": {},
}


def _is_transient_chrome_icon_path(path: Path) -> bool:
    """Chrome's scoped-dir icons disappear quickly and cause noisy broken lookups."""
    return str(path).startswith(CHROME_SCOPED_TMP_PREFIX)


def normalize_project_path(value: Optional[str]) -> Optional[str]:
    """Normalize a filesystem path for stable worktree identity lookup."""
    if not value or not isinstance(value, str):
        return None
    try:
        expanded = os.path.expanduser(value.strip())
        if not expanded:
            return None
        return os.path.realpath(expanded)
    except Exception:
        return str(value).strip() or None


def parse_context_key_target_host(value: Optional[str]) -> str:
    """Extract the canonical target host from a canonicalized context key."""
    _project_name, target_host = parse_context_key(value)
    return target_host


def resolve_discovered_worktree(path_value: Optional[str]) -> Optional[Dict[str, str]]:
    """Resolve a canonical worktree entry from `repos.json` by normalized path."""
    cache = _load_discovered_worktree_cache()
    if not cache:
        return None

    normalized = normalize_project_path(path_value)
    if not normalized:
        return None

    entry = cache.get("by_path", {}).get(normalized)
    if not isinstance(entry, dict):
        return None
    return dict(entry)


def resolve_discovered_worktree_name(qualified_name: Optional[str]) -> Optional[Dict[str, str]]:
    """Resolve a canonical worktree entry from `repos.json` by qualified name."""
    cache = _load_discovered_worktree_cache()
    if not cache:
        return None

    normalized_name = str(qualified_name or "").strip()
    if not normalized_name:
        return None

    entry = cache.get("by_qualified_name", {}).get(normalized_name)
    if not isinstance(entry, dict):
        return None
    return dict(entry)


def is_discovered_worktree_name(qualified_name: Optional[str]) -> bool:
    """Return True when the qualified name exists in discovered worktrees."""
    return resolve_discovered_worktree_name(qualified_name) is not None


def discovered_worktree_matches_path(
    qualified_name: Optional[str],
    path_value: Optional[str],
) -> bool:
    """Return True when the qualified name resolves and matches the discovered local path."""
    discovered = resolve_discovered_worktree_name(qualified_name)
    normalized_path = normalize_project_path(path_value)
    if not discovered or not normalized_path:
        return False
    return normalize_project_path(discovered.get("path")) == normalized_path


def _load_discovered_worktree_cache(force_refresh: bool = False) -> Dict[str, Any]:
    """Load discovered worktree identity maps keyed by path and qualified name."""
    repos_file = ConfigPaths.REPOS_FILE
    if not repos_file.exists():
        _DISCOVERED_WORKTREE_CACHE.update({
            "file_path": "",
            "mtime_ns": None,
            "size": None,
            "by_path": {},
            "by_qualified_name": {},
        })
        return {}

    try:
        stat_result = repos_file.stat()
    except OSError:
        return {}

    cached_by_path = _DISCOVERED_WORKTREE_CACHE.get("by_path")
    cached_by_name = _DISCOVERED_WORKTREE_CACHE.get("by_qualified_name")
    cache_valid = (
        not force_refresh
        and str(_DISCOVERED_WORKTREE_CACHE.get("file_path") or "") == str(repos_file)
        and _DISCOVERED_WORKTREE_CACHE.get("mtime_ns") == stat_result.st_mtime_ns
        and _DISCOVERED_WORKTREE_CACHE.get("size") == stat_result.st_size
        and isinstance(cached_by_path, dict)
        and isinstance(cached_by_name, dict)
    )
    if cache_valid:
        return {
            "by_path": dict(cached_by_path),
            "by_qualified_name": dict(cached_by_name),
        }

    try:
        with repos_file.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}

    by_path: Dict[str, Dict[str, str]] = {}
    by_name: Dict[str, Dict[str, str]] = {}
    repositories = payload.get("repositories", []) if isinstance(payload, dict) else []
    for repo in repositories if isinstance(repositories, list) else []:
        if not isinstance(repo, dict):
            continue
        account = str(repo.get("account") or "").strip()
        repo_name = str(repo.get("name") or "").strip()
        repo_qualified = f"{account}/{repo_name}" if account and repo_name else ""
        if not repo_qualified:
            continue
        worktrees = repo.get("worktrees", [])
        if not isinstance(worktrees, list):
            continue
        for worktree in worktrees:
            if not isinstance(worktree, dict):
                continue
            branch = str(worktree.get("branch") or "").strip()
            worktree_path = normalize_project_path(worktree.get("path"))
            if not branch or not worktree_path:
                continue
            entry = {
                "qualified_name": f"{repo_qualified}:{branch}",
                "repo_qualified_name": repo_qualified,
                "account": account,
                "repo_name": repo_name,
                "branch": branch,
                "path": worktree_path,
            }
            by_path[worktree_path] = entry
            by_name[entry["qualified_name"]] = entry

    _DISCOVERED_WORKTREE_CACHE.update({
        "file_path": str(repos_file),
        "mtime_ns": stat_result.st_mtime_ns,
        "size": stat_result.st_size,
        "by_path": by_path,
        "by_qualified_name": by_name,
    })
    return {
        "by_path": dict(by_path),
        "by_qualified_name": dict(by_name),
    }


class DesktopIconIndex:
    """Index curated app/PWA/desktop icons for stable window lookups."""

    def __init__(self) -> None:
        self._by_app_id: Dict[str, Dict[str, str]] = {}
        self._by_pwa_domain: Dict[str, Dict[str, str]] = {}
        self._by_desktop_id: Dict[str, Dict[str, str]] = {}
        self._by_startup_wm: Dict[str, Dict[str, str]] = {}
        self._icon_cache: Dict[str, str] = {}
        self.reload()

    def reload(self) -> None:
        self._by_app_id.clear()
        self._by_pwa_domain.clear()
        self._by_desktop_id.clear()
        self._by_startup_wm.clear()
        self._load_app_registry()
        self._load_pwa_registry()
        self._load_desktop_entries()

    def _store_app_payload(self, key: str, payload: Dict[str, str]) -> None:
        normalized = str(key).strip().lower()
        if not normalized:
            return
        existing = self._by_app_id.get(normalized, {})
        existing_icon = str(existing.get("icon") or "")
        next_icon = str(payload.get("icon") or "")
        if existing_icon and not next_icon:
            return
        self._by_app_id[normalized] = payload

    def _load_app_registry(self) -> None:
        if not APP_REGISTRY_PATH.exists():
            return
        try:
            with open(APP_REGISTRY_PATH, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception:
            return

        for app in data.get("applications", []):
            app_name = str(app.get("name", "")).strip().lower()
            payload = {
                "icon": self._resolve_icon(app.get("icon", "")) or "",
                "name": app.get("display_name", app_name),
            }
            if app_name:
                self._store_app_payload(app_name, payload)

    def _load_pwa_registry(self) -> None:
        if not PWA_REGISTRY_PATH.exists():
            return
        try:
            with open(PWA_REGISTRY_PATH, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception:
            return

        for pwa in data.get("pwas", []):
            payload = {
                "icon": self._resolve_icon(pwa.get("icon", "")) or "",
                "name": pwa.get("name", ""),
            }
            ulid = str(pwa.get("ulid", "")).strip().lower()
            if ulid:
                self._by_app_id[f"webapp-{ulid}"] = payload

            domain = str(pwa.get("domain", "")).strip().lower()
            if domain:
                for alias in {domain, f"www.{domain}"}:
                    self._by_pwa_domain[alias] = payload

    def _lookup_dynamic_pwa_icon(self, key: str) -> Dict[str, str]:
        normalized = str(key).strip().lower()
        if not normalized.startswith("chrome-") or not normalized.endswith("-default"):
            return {}

        dynamic_id = normalized[len("chrome-"):-len("-default")].strip()
        if not dynamic_id:
            return {}

        candidate_ids = [dynamic_id]
        if dynamic_id.endswith("__"):
            candidate_ids.append(dynamic_id[:-2])

        for domain, payload in self._by_pwa_domain.items():
            for candidate in candidate_ids:
                if (
                    candidate == domain
                    or candidate == f"{domain}__"
                    or candidate.startswith(f"{domain}__")
                    or candidate.startswith(f"{domain}-")
                ):
                    return payload
        return {}

    def _load_desktop_entries(self) -> None:
        if DesktopEntry is None:
            return
        for directory in DESKTOP_DIRS:
            if not directory.exists():
                continue
            for entry_path in directory.glob("*.desktop"):
                try:
                    entry = DesktopEntry(str(entry_path))
                except Exception:
                    continue
                payload = {
                    "icon": self._resolve_icon(entry.getIcon()) or "",
                    "name": entry.getName() or entry_path.stem,
                }
                self._by_desktop_id[entry_path.stem.lower()] = payload
                startup = entry.getStartupWMClass()
                if startup:
                    self._by_startup_wm[str(startup).strip().lower()] = payload

    def _resolve_icon(self, icon_name: Optional[str]) -> Optional[str]:
        if not icon_name:
            return None

        cache_key = str(icon_name).strip().lower()
        if cache_key in self._icon_cache:
            cached = self._icon_cache[cache_key]
            return cached or None

        candidate = Path(str(icon_name))
        if candidate.is_absolute() and candidate.exists() and not _is_transient_chrome_icon_path(candidate):
            resolved = str(candidate)
            self._icon_cache[cache_key] = resolved
            return resolved

        themed = getIconPath(str(icon_name), 48)
        if themed:
            resolved = str(Path(themed))
            self._icon_cache[cache_key] = resolved
            return resolved

        for directory in ICON_SEARCH_DIRS:
            if not directory.exists():
                continue
            for ext in ICON_EXTENSIONS:
                probe = directory / f"{icon_name}{ext}"
                if probe.exists():
                    resolved = str(probe)
                    self._icon_cache[cache_key] = resolved
                    return resolved

        self._icon_cache[cache_key] = ""
        return None

    def lookup(
        self,
        *,
        app_key: Optional[str] = None,
        app_id: Optional[str],
        window_class: Optional[str] = None,
        window_instance: Optional[str] = None,
        allow_fallback: bool = True,
    ) -> Dict[str, str]:
        app_key_normalized = str(app_key).strip().lower()
        if app_key_normalized and app_key_normalized in self._by_app_id:
            return self._by_app_id[app_key_normalized]

        if not allow_fallback:
            return {}

        keys = [
            str(value).strip().lower()
            for value in [app_id, window_class, window_instance]
            if value
        ]
        for key in keys:
            if key in self._by_app_id:
                return self._by_app_id[key]
        for key in keys:
            payload = self._lookup_dynamic_pwa_icon(key)
            if payload:
                return payload
        for key in keys:
            if key in self._by_desktop_id:
                return self._by_desktop_id[key]
        for key in keys:
            if key in self._by_startup_wm:
                return self._by_startup_wm[key]
        return {}


def shlex_quote(value: str) -> str:
    """Shell-quote a runtime value for helper scripts."""
    return shlex.quote(str(value))


# JSON-RPC 2.0 Standard Error Codes
PARSE_ERROR = -32700       # Invalid JSON
INVALID_REQUEST = -32600   # Not valid JSON-RPC request
METHOD_NOT_FOUND = -32601  # Method doesn't exist
INVALID_PARAMS = -32602    # Invalid method parameters
INTERNAL_ERROR = -32603    # Server internal error

# Application-specific error codes (Feature 058)
PROJECT_NOT_FOUND = 1001
LAYOUT_NOT_FOUND = 1002
VALIDATION_ERROR = 1003
FILE_IO_ERROR = 1004
I3_IPC_ERROR = 1005


class IPCServer:
    """JSON-RPC IPC server for CLI tool queries."""

    _CLIENT_CLOSE_TIMEOUT_SECONDS = 0.25
    _SERVER_CLOSE_TIMEOUT_SECONDS = 1.0
    _RECONCILE_TASKS_CLOSE_TIMEOUT_SECONDS = 1.0

    def __init__(
        self,
        state_manager: StateManager,
        event_buffer: Optional[Any] = None,
        i3_connection: Optional[Any] = None,
        window_rules_getter: Optional[callable] = None,
        workspace_tracker: Optional[window_filtering.WorkspaceTracker] = None,
        scratchpad_manager: Optional[Any] = None,
        run_raise_manager: Optional[Any] = None,
        mark_manager: Optional[Any] = None,
    ) -> None:
        """Initialize IPC server.

        Args:
            state_manager: StateManager instance for queries
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)
            workspace_tracker: WorkspaceTracker instance for window filtering (Feature 037)
            scratchpad_manager: ScratchpadManager instance for terminal management (Feature 062)
            run_raise_manager: RunRaiseManager instance for run-raise-hide operations (Feature 051)
            mark_manager: MarkManager instance for mark-based app identification (Feature 076)
        """
        self.state_manager = state_manager
        self.event_buffer = event_buffer
        self.i3_connection = i3_connection
        self.window_rules_getter = window_rules_getter
        self.workspace_tracker = workspace_tracker
        self.scratchpad_manager = scratchpad_manager
        self.run_raise_manager = run_raise_manager
        self.mark_manager = mark_manager
        self.server: Optional[asyncio.Server] = None
        self.clients: set[asyncio.StreamWriter] = set()
        self.subscribed_clients: set[asyncio.StreamWriter] = set()  # Feature 017: Event subscriptions
        self.registry_loader = RegistryLoader()
        self.icon_resolver = DesktopIconIndex()
        try:
            self.registry_loader.load()
        except Exception as e:
            logger.warning(f"Failed to load application registry for IPC launch preparation: {e}")

        # Feature 123: Window tree caching for efficient monitoring panel updates
        # Cache invalidated on any Sway event that modifies window/workspace state
        self._window_tree_cache: Optional[Dict[str, Any]] = None
        self._window_tree_cache_time: float = 0.0
        self._window_tree_cache_ttl: float = 15.0  # Max cache age in seconds (fallback if invalidation missed)

        self._worktree_cache_ttl: float = 10.0
        self._git_probe_timeout_seconds: float = 2.5
        self._git_snapshot_ttl_current: float = 3.0
        self._git_snapshot_ttl_visible: float = 8.0
        self._git_snapshot_ttl_background: float = 20.0
        self._git_snapshot_failure_ttl: float = 30.0
        self._active_runtime_context: Optional[Dict[str, Any]] = None
        self.focus_service = FocusService(
            normalize_connection_key=lambda value: self._normalize_connection_key(value),
            schema_version=FOCUS_STATE_SCHEMA_VERSION,
            sway_available=lambda: bool(self.i3_connection and getattr(self.i3_connection, "conn", None)),
            run_sway_command=lambda command: self._sway_ipc_command(command),
            sway_command_succeeded=lambda result: self._sway_command_succeeded(result),
            get_sway_workspaces=lambda: self._sway_get_workspaces(),
            send_tick_barrier=lambda payload: self._send_tick_barrier(payload),
            notify_state_change=lambda event_type: self.notify_state_change(event_type),
            window_is_locally_tracked=lambda window_id: self._window_is_locally_tracked(window_id),
            connection_target_is_current_host=lambda connection_key: self._connection_target_is_current_host(
                connection_key
            ),
            remote_daemon_request=lambda **kwargs: self._remote_daemon_request(**kwargs),
            switch_runtime_context=lambda project_name, target_variant, connection_key: self._switch_runtime_context_if_needed(
                project_name,
                target_variant,
                connection_key,
            ),
            get_window_transition_state=lambda window_id: self._get_window_transition_state(window_id),
            build_window_focus_transition=lambda **kwargs: self._build_window_focus_transition(**kwargs),
            window_matches_transition_target=lambda expected: self._window_matches_transition_target(expected),
            verify_window_focus=lambda window_id: self._verify_window_focus(window_id),
            focus_state_provider=lambda params=None: self._focus_state(params or {}),
        )
        self.dashboard_git_service = DashboardGitService(
            ttl_current=self._git_snapshot_ttl_current,
            ttl_visible=self._git_snapshot_ttl_visible,
            ttl_background=self._git_snapshot_ttl_background,
            ttl_failure=self._git_snapshot_failure_ttl,
            git_probe_timeout_seconds=self._git_probe_timeout_seconds,
        )
        self.dashboard_worktree_service = DashboardWorktreeService(
            repo_list=lambda: self._repo_list({}),
            load_usage_map=self._load_validated_project_usage_map,
            flatten_runtime_windows=lambda runtime_snapshot: self._flatten_runtime_windows(runtime_snapshot),
            cache_fingerprint=self._dashboard_worktree_cache_fingerprint,
            normalize_target_host=self._normalize_target_host,
            local_host_alias=self._local_host_alias,
            canonical_project_name=lambda *args, **kwargs: self._canonical_discovered_project_name(*args, **kwargs),
            get_worktree_host_profile=lambda qualified_name: self._get_worktree_host_profile(qualified_name),
            ttl=self._worktree_cache_ttl,
        )
        self.worktree_profile_service = WorktreeProfileService()
        self.daemon_contract_service = DaemonContractService(
            dashboard_schema_version=DASHBOARD_SCHEMA_VERSION,
            dashboard_event_schema_version=DASHBOARD_EVENT_SCHEMA_VERSION,
            focus_schema_version=FOCUS_STATE_SCHEMA_VERSION,
        )
        self.daemon_status_service = DaemonStatusService(
            state_manager=self.state_manager,
            event_buffer=self.event_buffer,
            i3_connection_provider=lambda: self.i3_connection,
            socket_path_provider=lambda: (
                str(self.server.sockets[0].getsockname())
                if self.server and self.server.sockets
                else "/run/user/1000/i3-project-daemon/ipc.sock"
            ),
            ipc_stats_provider=lambda: self._get_ipc_stats(),
            startup_recovery_provider=lambda: getattr(self, "startup_recovery_result", None),
            reconnection_manager_provider=lambda: getattr(self, "i3_reconnection_manager", None),
        )
        self.display_service = DisplayService(
            notify_state_change=lambda event_type: self.notify_state_change(event_type),
            run_sway_command=lambda command: self._sway_ipc_command(command),
            sway_command_succeeded=lambda result: self._sway_command_succeeded(result),
            send_tick_barrier=lambda payload: self._send_tick_barrier(payload),
            i3_connection=lambda: self.i3_connection,
            monitor_profile_service=lambda: getattr(self, "monitor_profile_service", None),
            display_generation=lambda: self._display_generation,
            snapshot_version=lambda: self._snapshot_version,
        )
        self.launch_service = LaunchService(
            runtime_dir=lambda: self._runtime_dir(),
            load_json_file=lambda path: self._load_json_file(path),
            normalize_target_host=lambda value: self._normalize_target_host(value),
            parse_context_target_host=lambda value: parse_context_key_target_host(value),
            transport_kind_for_target_host=lambda value: self._transport_kind_for_target_host(value),
            local_host_alias=lambda: self._local_host_alias(),
            resolve_terminal_launch_transport=lambda **kwargs: self._resolve_terminal_launch_transport(**kwargs),
            canonical_tmux_socket=lambda: self._canonical_tmux_socket(),
            run_command=lambda *args, **kwargs: subprocess.run(*args, **kwargs),
            repo_root=lambda: self._repo_root(),
            which=lambda command: shutil.which(command),
            window_map_items=lambda: list(self.state_manager.state.window_map.items()),
            get_pending_launch_by_terminal_anchor=(
                lambda terminal_anchor_id: self.state_manager.launch_registry.get_by_terminal_anchor(
                    terminal_anchor_id
                )
            ),
            launch_registry=lambda: self.state_manager.launch_registry,
            require_registry_app=lambda app_name: self._require_registry_app(app_name),
            find_live_window=lambda window_id: self._find_live_sway_window(window_id),
            remove_window=lambda window_id: self.state_manager.remove_window(window_id),
            invalidate_window_tree_cache=lambda: self.invalidate_window_tree_cache(),
        )
        self.herdr_service = HerdrService(
            notify_state_change=lambda event_type: self.notify_state_change(event_type),
            normalize_project_path=normalize_project_path,
            resolve_worktree_for_path=resolve_discovered_worktree,
            parse_remote_target=self._parse_remote_target,
            normalize_connection_key=self._normalize_connection_key,
            local_host=lambda: self._local_host_alias(),
        )
        self.dashboard_service = DashboardService(
            runtime_loader=lambda *args, **kwargs: self._load_reconciled_session_runtime(*args, **kwargs),
            display_snapshot=lambda: self.display_service.snapshot(),
            build_projects=lambda runtime_snapshot, sessions: self._build_dashboard_projects(
                runtime_snapshot,
                sessions,
            ),
            build_worktrees=lambda runtime_snapshot: self._build_dashboard_worktrees(runtime_snapshot),
            build_focus_state=lambda *args, **kwargs: self.focus_service.build_focus_state_payload(
                *args,
                **kwargs,
            ),
            build_herdr_spaces=lambda herdr_snapshot, sessions: self.herdr_service.build_spaces(
                herdr_snapshot,
                sessions,
            ),
            list_launches=lambda **kwargs: self.launch_service.list_statuses(**kwargs),
            invalidate_worktree_cache=self.invalidate_worktree_cache,
        )
        self._malformed_json_count: int = 0
        self._deferred_filter_task: Optional[asyncio.Task] = None
        self._malformed_json_last_at: Optional[str] = None
        self._malformed_json_last_peer: str = ""
        self._malformed_json_last_error: str = ""
        self._malformed_json_by_peer: Dict[str, int] = {}

    @property
    def _snapshot_version(self) -> int:
        return int(self.dashboard_service.snapshot_version)

    @property
    def _session_generation(self) -> int:
        return int(self.dashboard_service.session_generation)

    @property
    def _display_generation(self) -> int:
        return int(self.dashboard_service.display_generation)

    @property
    def _focus_generation(self) -> int:
        return int(self.dashboard_service.focus_generation)

    @classmethod
    async def from_systemd_socket(
        cls,
        state_manager: StateManager,
        event_buffer: Optional[Any] = None,
        i3_connection: Optional[Any] = None,
        window_rules_getter: Optional[callable] = None,
        workspace_tracker: Optional[window_filtering.WorkspaceTracker] = None,
        scratchpad_manager: Optional[Any] = None,
        run_raise_manager: Optional[Any] = None,
        mark_manager: Optional[Any] = None,
    ) -> "IPCServer":
        """Create IPC server using systemd socket activation.

        Args:
            state_manager: StateManager instance
            event_buffer: EventBuffer instance for event history (Feature 017)
            i3_connection: ResilientI3Connection instance for i3 IPC queries (Feature 018)
            window_rules_getter: Callable that returns current window rules list (Feature 021)
            workspace_tracker: WorkspaceTracker instance for window filtering (Feature 037)
            scratchpad_manager: ScratchpadManager instance for terminal management (Feature 062)
            run_raise_manager: RunRaiseManager instance for run-raise-hide operations (Feature 051)
            mark_manager: MarkManager instance for mark-based app identification (Feature 076)

        Returns:
            IPCServer instance with inherited socket
        """
        server = cls(state_manager, event_buffer, i3_connection, window_rules_getter, workspace_tracker, scratchpad_manager, run_raise_manager, mark_manager)

        # Check if systemd passed us a socket
        listen_fds = int(os.environ.get("LISTEN_FDS", 0))
        if listen_fds > 0:
            # Socket FD starts at 3 (0=stdin, 1=stdout, 2=stderr)
            fd = 3
            logger.info(f"Using systemd socket activation (FD {fd})")

            # Create server from existing socket
            sock = socket.socket(fileno=fd)
            await server.start(sock)
        else:
            logger.info("No systemd socket provided, creating new socket")
            await server.start(None)

        return server

    def _error_response(self, request_id: Any, code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Format JSON-RPC error response.

        Args:
            request_id: Request ID from original request
            code: Error code (standard or application-specific)
            message: Error message
            data: Optional additional error data

        Returns:
            JSON-RPC error response dictionary
        """
        error = {"code": code, "message": message}
        if data:
            error["data"] = data
        return {"jsonrpc": "2.0", "error": error, "id": request_id}

    async def start(self, sock: Optional[socket.socket] = None) -> None:
        """Start IPC server.

        Args:
            sock: Existing socket to use (from systemd), or None to create new
        """
        if sock:
            # Use provided socket (from systemd)
            self.server = await asyncio.start_unix_server(
                self._handle_client, sock=sock  # type: ignore
            )
        else:
            # Feature 117: Create new socket at XDG_RUNTIME_DIR (user service)
            runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
            socket_path = Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"
            socket_path.parent.mkdir(parents=True, exist_ok=True)

            # Remove old socket if it exists
            if socket_path.exists():
                socket_path.unlink()

            self.server = await asyncio.start_unix_server(
                self._handle_client, path=str(socket_path)
            )

            # Feature 039 - T110: Security - Set explicit socket permissions
            # Ensure socket is user-only accessible (0600)
            socket_path.chmod(0o600)
            # Ensure parent directory is user-only accessible (0700)
            socket_path.parent.chmod(0o700)

            logger.info(f"IPC server listening on {socket_path} (permissions: 0600)")

        self.start_herdr_event_subscription()

    async def stop(self) -> None:
        """Stop IPC server and close all connections."""
        await self.stop_herdr_event_subscription()
        await self.launch_service.stop_reconcile_tasks(
            timeout=self._RECONCILE_TASKS_CLOSE_TIMEOUT_SECONDS,
        )
        if self.server:
            self.server.close()
            await self._await_with_timeout(
                self.server.wait_closed(),
                timeout=self._SERVER_CLOSE_TIMEOUT_SECONDS,
                timeout_message="Timed out waiting for IPC server socket to close; continuing shutdown",
            )

        # Close all client connections
        if self.clients:
            await asyncio.gather(
                *(self._close_client_writer(writer) for writer in list(self.clients)),
                return_exceptions=True,
            )

        logger.info("IPC server stopped")

    def start_herdr_event_subscription(self) -> None:
        """Start the local Herdr event subscription task."""
        self.herdr_service.start_subscription()

    async def stop_herdr_event_subscription(self) -> None:
        """Cancel the local Herdr event subscription task."""
        await self.herdr_service.stop_subscription()

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        """Handle a client connection.

        Args:
            reader: Stream reader for receiving requests
            writer: Stream writer for sending responses
        """
        self.clients.add(writer)
        addr = writer.get_extra_info("peername")

        try:
            while True:
                # Read JSON-RPC request
                data = await reader.readline()
                if not data:
                    break
                if not data.strip():
                    continue

                try:
                    request = json.loads(data.decode())
                    response = await self._handle_request(request, writer)
                    writer.write(json.dumps(response).encode() + b"\n")
                    await writer.drain()

                except json.JSONDecodeError as e:
                    self._record_malformed_json(addr, e)
                    logger.warning("Ignoring malformed JSON from %s: %s", addr, e)
                    error_response = {
                        "jsonrpc": "2.0",
                        "error": {"code": -32700, "message": "Parse error"},
                        "id": None,
                    }
                    writer.write(json.dumps(error_response).encode() + b"\n")
                    await writer.drain()

        except Exception as e:
            logger.error(f"Error handling client {addr}: {e}", exc_info=True)

        finally:
            self.clients.discard(writer)
            self.subscribed_clients.discard(writer)  # Remove from subscriptions if subscribed
            self.dashboard_service.discard_subscriber(writer)
            await self._close_client_writer(writer)

    async def _close_client_writer(self, writer: asyncio.StreamWriter) -> None:
        """Close a client writer without blocking daemon shutdown indefinitely."""
        try:
            writer.close()
            await self._await_with_timeout(
                writer.wait_closed(),
                timeout=self._CLIENT_CLOSE_TIMEOUT_SECONDS,
                timeout_message=(
                    "Timed out waiting for client "
                    f"{self._format_client_peer(writer.get_extra_info('peername'))} "
                    "to close; continuing shutdown"
                ),
            )
        except Exception as e:
            logger.debug(f"Error closing client connection during shutdown: {e}")

    async def _await_with_timeout(
        self,
        awaitable: Any,
        *,
        timeout: float,
        timeout_message: str,
    ) -> Any:
        """Await an operation with a hard timeout that doesn't block on slow cancellation."""
        task = asyncio.ensure_future(awaitable)
        done, _pending = await asyncio.wait({task}, timeout=timeout)
        if task in done:
            return await task

        task.cancel()

        def _consume_result(fut: asyncio.Future) -> None:
            try:
                fut.result()
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.debug("Background shutdown task failed after timeout", exc_info=True)

        task.add_done_callback(_consume_result)
        logger.debug(timeout_message)
        return None

    def _format_client_peer(self, addr: Any) -> str:
        """Return a compact stable label for a client peer."""
        if addr is None:
            return "<unknown>"
        if isinstance(addr, tuple):
            return ":".join(str(part) for part in addr if part not in (None, ""))
        return str(addr)

    def _record_malformed_json(self, addr: Any, error: Exception) -> None:
        """Track malformed IPC requests for status/debugging."""
        peer = self._format_client_peer(addr)
        self._malformed_json_count += 1
        self._malformed_json_last_at = datetime.now().isoformat()
        self._malformed_json_last_peer = peer
        self._malformed_json_last_error = str(error)
        self._malformed_json_by_peer[peer] = self._malformed_json_by_peer.get(peer, 0) + 1

    def _get_ipc_stats(self) -> Dict[str, Any]:
        """Return lightweight IPC health/debug statistics."""
        top_offenders = sorted(
            self._malformed_json_by_peer.items(),
            key=lambda item: (-item[1], item[0]),
        )[:5]
        return {
            "client_count": len(self.clients),
            "subscribed_client_count": len(self.subscribed_clients),
            "state_change_subscriber_count": len(self.dashboard_service.subscribers),
            "malformed_json_count": self._malformed_json_count,
            "last_malformed_json_at": self._malformed_json_last_at,
            "last_malformed_json_peer": self._malformed_json_last_peer or None,
            "last_malformed_json_error": self._malformed_json_last_error or None,
            "top_malformed_json_peers": [
                {"peer": peer, "count": count}
                for peer, count in top_offenders
            ],
        }

    async def _handle_request(self, request: Dict[str, Any], writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Handle a JSON-RPC request.

        Args:
            request: JSON-RPC request dictionary
            writer: Stream writer for this client connection

        Returns:
            JSON-RPC response dictionary
        """
        method = request.get("method")
        params = request.get("params", {})
        if not isinstance(params, dict):
            params = {}
        else:
            params = dict(params)
        request_id = request.get("id")

        explicit_intent_methods = {
            "context.ensure",
            "herdr.pane.focus",
            "herdr.pane.close",
            "herdr.remote.pane.focus",
            "herdr.workspace.focus",
            "herdr.tab.focus",
            "launch.open",
            "window.focus",
            "window.focus_fast",
            "workspace.focus",
            "workspace.focus_fast",
            "worktree.switch",
            "worktree.clear",
        }
        if isinstance(method, str) and method in explicit_intent_methods:
            params["__intent_epoch"] = self._advance_user_intent_epoch(
                method=method,
                params=params,
            )

        try:
            # Dispatch to handler method
            if method == "get_status":
                result = await self._get_status()
            elif method == "get_active_project":
                result = await self._get_active_project()
            elif method == "context.get_active":
                result = await self._context_get_active(params)
            elif method == "context.current":
                result = await self._context_get_active(params)
            elif method == "context.ensure":
                result = await self._context_ensure(params)
            elif method == "runtime.snapshot":
                result = await self._runtime_snapshot(params)
            elif method == "dashboard.snapshot":
                result = await self._dashboard_snapshot(params)
            elif method == "dashboard.validate":
                result = await self._dashboard_validate(params)
            elif method == "herdr.snapshot":
                result = await self.herdr_service.snapshot(params)
            elif method == "herdr.proxy.snapshot":
                result = await self.herdr_service.proxy_snapshot(params)
            elif method == "herdr.proxy.pane.focus":
                result = await self.herdr_service.proxy_pane_focus(params)
            elif method == "herdr.pane.focus":
                result = await self.herdr_service.pane_focus(params)
            elif method == "herdr.pane.close":
                result = await self.herdr_service.pane_close(params)
            elif method == "herdr.remote.pane.focus":
                result = await self.herdr_service.remote_pane_focus(
                    params,
                    launch_open=self._launch_open,
                    set_focus_overrides=self._set_focus_overrides,
                )
            elif method == "herdr.workspace.focus":
                result = await self.herdr_service.workspace_focus(params)
            elif method == "herdr.tab.focus":
                result = await self.herdr_service.tab_focus(params)
            elif method == "display.snapshot":
                result = await self.display_service.snapshot()
            elif method == "display.apply":
                result = await self.display_service.apply(params)
            elif method == "display.cycle":
                result = await self.display_service.cycle(params)
            elif method == "display.toggle_output":
                result = await self.display_service.toggle_output(params)
            elif method == "display.set_scale":
                result = await self.display_service.set_scale(params)
            elif method == "get_projects":
                result = await self._get_projects()
            elif method == "get_windows":
                # Return hierarchical tree structure (outputs array)
                tree_result = await self._get_window_tree(params)
                result = tree_result.get("outputs", [])
            elif method == "get_events":
                # Return events array (not dict with stats) for CLI
                # Unified event system: Return full event data with source field
                events_result = await self._get_events(params)
                result = events_result.get("events", [])
            elif method == "list_monitors":
                result = await self._list_monitors()
            elif method == "subscribe_events":
                result = await self._subscribe_events(params, writer)
            elif method == "subscribe":  # Feature 058: Workspace mode event subscription
                result = await self._subscribe_events(params, writer)
            elif method == "reload_config":
                result = await self._reload_config()
            elif method == "get_diagnostic_state":
                result = await self._get_diagnostic_state(params)
            elif method == "get_window_rules":
                result = await self._get_window_rules(params)
            elif method == "classify_window":
                result = await self._classify_window(params)
            elif method == "get_window_tree":
                result = await self._get_window_tree(params)

            # Feature 030: Production readiness methods (T016)
            elif method == "daemon.status":
                result = await self._daemon_status()
            elif method == "daemon.events":
                result = await self._daemon_events(params)
            elif method == "daemon.diagnose":
                result = await self._daemon_diagnose(params)
            elif method == "daemon.apps":
                result = await self._daemon_apps(params)
            elif method == "layout.save":
                result = await self._layout_save(params)
            elif method == "layout.restore":
                result = await self._layout_restore(params)
            elif method == "layout.list":
                result = await self._layout_list(params)
            elif method == "layout.delete":
                result = await self._layout_delete(params)
            elif method == "layout.info":
                result = await self._layout_info(params)

            # Feature 033: Workspace-to-monitor mapping methods
            elif method == "get_monitor_config":
                result = await self._get_monitor_config()
            elif method == "validate_monitor_config":
                result = await self._validate_monitor_config(params)
            elif method == "reload_monitor_config":
                result = await self._reload_monitor_config()
            elif method == "reassign_workspaces":
                result = await self._reassign_workspaces(params)
            elif method == "get_monitors":
                result = await self._get_monitors()
            elif method == "get_workspaces":
                result = await self._get_workspaces()
            elif method == "get_system_state":
                result = await self._get_system_state()

            # Feature 037: Window filtering methods
            elif method == "project.hideWindows":
                result = await self._hide_windows(params)
            elif method == "project.restoreWindows":
                result = await self._restore_windows(params)
            elif method == "project.switchWithFiltering":
                result = await self._switch_with_filtering(params)

            # Feature 037 US5: Window visibility methods (T036, T037)
            elif method == "windows.getHidden":
                result = await self._get_hidden_windows(params)
            elif method == "windows.getState":
                result = await self._get_window_state(params)

            # Feature 039: Diagnostic API methods (T087-T092)
            elif method == "health_check":
                result = await self._health_check()
            # Feature 121: Socket health endpoint for diagnostic CLI
            elif method == "get_socket_health":
                result = await self._get_socket_health()
            elif method == "get_window_identity":
                result = await self._get_window_identity_diagnostic(params)
            elif method == "get_window_environment":
                # Feature 058: Phase 3 - Get window environment by PID
                result = await self._get_window_environment(params)
            elif method == "get_workspace_rule":
                result = await self._get_workspace_rule_diagnostic(params)
            elif method == "validate_state":
                result = await self._validate_state_diagnostic()
            elif method == "get_recent_events":
                result = await self._get_recent_events_diagnostic(params)
            elif method == "get_diagnostic_report":
                result = await self._get_diagnostic_report_full(params)

            # Feature 041: IPC Launch Context methods (T010-T012)
            elif method == "prepare_launch":
                result = await self._prepare_launch(params)
            elif method == "launch.preview":
                preview_params = dict(params or {})
                preview_params["dry_run"] = True
                result = await self._prepare_launch(preview_params)
            elif method == "launch.open":
                result = await self._launch_open(params)
            elif method == "launch.status":
                result = await self.launch_service.launch_status(params.get("launch_id", ""))
            elif method == "get_launch_stats":
                result = self.launch_service.launch_stats()
            elif method == "get_pending_launches":
                result = await self.launch_service.pending_launches(
                    include_matched=bool(params.get("include_matched", False))
                )
            elif method == "get_terminal_anchor":
                result = await self.launch_service.terminal_anchor(params.get("terminal_anchor_id", ""))
            elif method == "window.focus":
                result = await self._window_focus(params)
            elif method == "window.focus_fast":
                result = await self._window_focus_fast(params)
            elif method == "window.action":
                result = await self._window_action(params)
            elif method == "session.list":
                result = await self._session_list(params)
            elif method == "focus.state":
                result = await self._focus_state(params)
            elif method == "session.exit":
                result = await self._session_exit(params)

            # Feature 058: Project management methods (T030-T033)
            elif method == "project_create":
                result = await self._project_create(params)
            elif method == "project_list":
                result = await self._project_list(params)
            elif method == "project_get":
                result = await self._project_get(params)
            elif method == "project_update":
                result = await self._project_update(params)
            elif method == "project_delete":
                result = await self._project_delete(params)
            elif method == "project_get_active":
                result = await self._project_get_active(params)
            elif method == "project_set_active":
                result = await self._project_set_active(params)

            # Feature 097: Discovery methods
            elif method == "discover_projects":
                result = await self._discover_projects(params)
            elif method == "list_github_repos":
                result = await self._list_github_repos(params)
            elif method == "get_discovery_config":
                result = await self._get_discovery_config(params)
            elif method == "update_discovery_config":
                result = await self._update_discovery_config(params)
            elif method == "refresh_git_metadata":
                result = await self._refresh_git_metadata(params)

            # Feature 098: Worktree environment integration methods
            elif method == "worktree.list":
                result = await self._worktree_list(params)
            elif method == "worktree.current":
                result = await self._context_get_active(params)
            elif method == "project.refresh":
                result = await self._project_refresh(params)

            # Feature 100: Structured Git Repository Management
            elif method == "account.add":
                result = await self._account_add(params)
            elif method == "account.list":
                result = await self._account_list(params)
            elif method == "clone":
                result = await self._clone(params)
            elif method == "discover":
                result = await self._discover_bare_repos(params)
            elif method == "repo.list":
                result = await self._repo_list(params)
            elif method == "repo.get":
                result = await self._repo_get(params)
            elif method == "worktree.create":
                result = await self._worktree_create(params)
            elif method == "worktree.remove":
                result = await self._worktree_remove(params)
            elif method == "worktree.refresh":
                result = await self._worktree_refresh(params)
            elif method == "worktree.switch":
                # Feature 101: Switch to worktree by qualified name
                result = await self._worktree_switch(params)
            elif method == "worktree.clear":
                # Feature 101: Clear active project (return to global mode)
                result = await self._worktree_clear(params)
            elif method == "worktree.host.set":
                result = await self._worktree_remote_set(params)
            elif method == "worktree.host.get":
                result = await self._worktree_remote_get(params)
            elif method == "worktree.host.unset":
                result = await self._worktree_remote_unset(params)
            elif method == "worktree.host.list":
                result = await self._worktree_remote_list(params)
            elif method == "worktree.host.test":
                result = await self._worktree_remote_test(params)
            elif method == "worktree.remote.set":
                result = await self._worktree_remote_set(params)
            elif method == "worktree.remote.get":
                result = await self._worktree_remote_get(params)
            elif method == "worktree.remote.unset":
                result = await self._worktree_remote_unset(params)
            elif method == "worktree.remote.list":
                result = await self._worktree_remote_list(params)
            elif method == "worktree.remote.test":
                result = await self._worktree_remote_test(params)
            elif method == "worktree.diagnose":
                result = await self._worktree_diagnose(params)

            # Feature 101: Window tracing for debugging
            elif method == "trace.start":
                result = await self._trace_start(params)
            elif method == "trace.start_app":
                result = await self._trace_start_app(params)
            elif method == "trace.stop":
                result = await self._trace_stop(params)
            elif method == "trace.get":
                result = await self._trace_get(params)
            elif method == "trace.list":
                result = await self._trace_list(params)
            elif method == "trace.snapshot":
                result = await self._trace_snapshot(params)

            # Feature 102 T057-T058: Trace template methods
            elif method == "traces.list_templates":
                result = await self._traces_list_templates(params)
            elif method == "traces.start_from_template":
                result = await self._traces_start_from_template(params)

            # Feature 102: Cross-reference and unified event tracing methods
            elif method == "traces.get_cross_reference":
                result = await self._traces_get_cross_reference(params)
            elif method == "events.get_by_trace":
                result = await self._events_get_by_trace(params)
            elif method == "traces.query_window_traces":
                result = await self._traces_query_window_traces(params)
            elif method == "events.get_causality_chain":
                result = await self._events_get_causality_chain(params)

            # Feature 102 T046: Output state IPC method
            elif method == "outputs.get_state":
                result = await self._outputs_get_state(params)
            elif method == "output.configure":
                result = await self._output_configure(params)
            elif method == "output.create_virtual":
                result = await self._output_create_virtual(params)
            elif method == "workspace.move_to_output":
                result = await self._workspace_move_to_output(params)
            elif method == "workspace.focus":
                result = await self._workspace_focus(params)
            elif method == "workspace.focus_fast":
                result = await self._workspace_focus_fast(params)

            # Method aliases for Deno CLI compatibility
            elif method == "list_projects":
                # Convert Project objects to array format for CLI (Feature 030)
                projects = self.state_manager.state.projects
                result = [
                    {
                        "name": proj.name,
                        "display_name": proj.display_name,
                        "icon": proj.icon or "",  # Ensure not null
                        "directory": str(proj.directory),
                        "scoped_classes": list(proj.scoped_classes) if proj.scoped_classes else [],
                        "created_at": 1,  # Placeholder: TODO add created_at to Project model
                        "last_used_at": 1,  # Placeholder: TODO add last_used_at tracking
                    }
                    for proj in projects.values()
                ]
            elif method == "get_current_project":
                # Return full project details for app launcher wrapper script
                result = await self._get_active_project()
            elif method == "list_rules":
                # Return rules array adapted to CLI format
                import uuid
                rules_result = await self._get_window_rules(params)
                rules = rules_result.get("rules", [])
                # Adapt format: pattern -> class_pattern, add rule_id and enabled
                result = [
                    {
                        "rule_id": str(uuid.uuid5(uuid.NAMESPACE_DNS, rule["pattern"])),
                        "class_pattern": rule["pattern"],
                        "scope": rule["scope"],
                        "priority": rule["priority"],
                        "enabled": True,  # TODO: Track enabled state
                    }
                    for rule in rules
                ]

            # Feature 062: Scratchpad terminal methods
            elif method == "scratchpad.toggle":
                result = await self._scratchpad_toggle(params)
            elif method == "scratchpad.launch":
                result = await self._scratchpad_launch(params)
            elif method == "scratchpad.status":
                result = await self._scratchpad_status(params)
            elif method == "scratchpad.close":
                result = await self._scratchpad_close(params)
            elif method == "scratchpad.cleanup":
                result = await self._scratchpad_cleanup(params)

            # Feature 074: Session Management - Focus tracking methods (T030-T031, US1)
            elif method == "project.get_focused_workspace":
                result = await self._project_get_focused_workspace(params)
            elif method == "project.set_focused_workspace":
                result = await self._project_set_focused_workspace(params)

            # Feature 074: Session Management - Config IPC methods (T085-T086)
            elif method == "config.get":
                result = await self._config_get(params)
            elif method == "config.set":
                result = await self._config_set(params)

            # Feature 074: Session Management - State and version methods (T096-T097)
            elif method == "state.get":
                result = await self._state_get(params)
            elif method == "daemon.contract":
                result = await self._daemon_contract(params)
            elif method == "daemon.version":
                result = await self._daemon_version(params)

            # Feature 001: Declarative workspace-to-monitor assignment
            elif method == "monitors.status":
                result = await self._monitors_status(params)
            elif method == "monitors.reassign":
                result = await self._monitors_reassign(params)
            elif method == "monitors.config":
                result = await self._monitors_config(params)

            # Feature 051: Run-raise-hide application launching
            elif method == "app.run":
                result = await self._app_run(params)

            # Feature 099: Window environment variables view
            elif method == "window.get_env":
                result = await self._window_get_env(params)

            # Feature 123: State change subscription for efficient monitoring panel updates
            elif method == "subscribe_state_changes":
                result = await self._subscribe_state_changes(params, writer)

            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                    "id": request_id,
                }

            focus_intent = self._finalize_focus_intent_for_result(
                method=str(method or ""),
                params=params,
                result=result,
            )
            if isinstance(result, dict) and focus_intent:
                result["focus_intent"] = focus_intent
                if str(focus_intent.get("state") or "") == "failed":
                    await self.notify_state_change("focus_changed")
            return {"jsonrpc": "2.0", "result": result, "id": request_id}

        except KeyError as e:
            # Missing required parameter
            logger.warning(f"Missing required parameter in {method}: {e}")
            await self._fail_focus_intent_for_exception(str(method or ""), params, str(e))
            return self._error_response(
                request_id,
                INVALID_PARAMS,
                f"Missing required parameter: {e}",
                {"parameter": str(e)}
            )

        except FileNotFoundError as e:
            # Layout or project file not found
            logger.warning(f"File not found in {method}: {e}")
            await self._fail_focus_intent_for_exception(str(method or ""), params, str(e))
            error_code = LAYOUT_NOT_FOUND if "layout" in str(e).lower() else PROJECT_NOT_FOUND
            return self._error_response(
                request_id,
                error_code,
                str(e),
                {"path": str(e.filename) if hasattr(e, 'filename') else str(e)}
            )

        except ValueError as e:
            # Pydantic validation error or invalid parameters
            logger.warning(f"Validation error in {method}: {e}")
            await self._fail_focus_intent_for_exception(str(method or ""), params, str(e))
            return self._error_response(
                request_id,
                VALIDATION_ERROR,
                f"Validation error: {str(e)}",
                {"details": str(e)}
            )

        except OSError as e:
            # File I/O error
            logger.error(f"File I/O error in {method}: {e}")
            await self._fail_focus_intent_for_exception(str(method or ""), params, str(e))
            return self._error_response(
                request_id,
                FILE_IO_ERROR,
                f"File I/O error: {str(e)}",
                {"errno": e.errno if hasattr(e, 'errno') else None}
            )

        except Exception as e:
            # Unexpected error - check if it's i3 IPC related
            error_type = type(e).__name__
            logger.error(f"Error handling request {method}: {error_type}: {e}")
            await self._fail_focus_intent_for_exception(str(method or ""), params, str(e))

            structured_error = None
            try:
                candidate = json.loads(str(e))
                if isinstance(candidate, dict) and candidate.get("message"):
                    structured_error = candidate
            except Exception:
                structured_error = None

            if structured_error:
                return self._error_response(
                    request_id,
                    int(structured_error.get("code", INTERNAL_ERROR)),
                    str(structured_error.get("message", "Internal server error")),
                    structured_error.get("data"),
                )

            # Check if it's an i3ipc exception
            if 'i3ipc' in error_type.lower() or 'connection' in error_type.lower():
                return self._error_response(
                    request_id,
                    I3_IPC_ERROR,
                    "i3 IPC communication error",
                    {"exception": error_type, "details": str(e)}
                )

            # Generic internal error
            return self._error_response(
                request_id,
                INTERNAL_ERROR,
                "Internal server error",
                {"exception": error_type, "details": str(e)}
            )

    async def _log_ipc_event(
        self,
        event_type: str,
        client_pid: Optional[int] = None,
        params: Optional[Dict[str, Any]] = None,
        result_count: Optional[int] = None,
        project_name: Optional[str] = None,
        old_project: Optional[str] = None,
        new_project: Optional[str] = None,
        windows_affected: Optional[int] = None,
        config_type: Optional[str] = None,
        rules_count: Optional[int] = None,
        duration_ms: float = 0.0,
        error: Optional[str] = None,
    ) -> None:
        """Log an IPC event to the event buffer.

        Feature 102 (T035): Includes correlation_id and causality_depth from context.

        Args:
            event_type: Event type (e.g., "query::status", "project::switch")
            client_pid: Client process ID
            params: Request parameters
            result_count: Number of results returned (for queries)
            project_name: Project name (for project events)
            old_project: Previous project (for switches)
            new_project: New project (for switches)
            windows_affected: Number of windows affected
            config_type: Config type for config events
            rules_count: Number of rules for rule events
            duration_ms: Processing duration
            error: Error message if failed
        """
        if not self.event_buffer:
            return

        # Feature 102 (T035): Get correlation context for causality tracking
        from .services.correlation_service import get_correlation_context
        correlation_id, causality_depth = get_correlation_context()

        entry = EventEntry(
            event_id=self.event_buffer.event_counter,
            event_type=event_type,
            timestamp=datetime.now(),
            source="ipc",
            client_pid=client_pid,
            query_method=event_type if event_type.startswith("query::") else None,
            query_params=params,
            query_result_count=result_count,
            project_name=project_name,
            old_project=old_project,
            new_project=new_project,
            windows_affected=windows_affected,
            config_type=config_type,
            rules_added=rules_count,
            processing_duration_ms=duration_ms,
            error=error,
            correlation_id=correlation_id,  # Feature 102 (T035)
            causality_depth=causality_depth,  # Feature 102 (T035)
        )
        await self.event_buffer.add_event(entry)

    async def _log_i3pm_event(
        self,
        event_type: str,
        *,
        window_id: Optional[int] = None,
        window_class: Optional[str] = None,
        window_title: Optional[str] = None,
        workspace_name: Optional[str] = None,
        project_name: Optional[str] = None,
        old_project: Optional[str] = None,
        new_project: Optional[str] = None,
        windows_affected: Optional[int] = None,
        correlation_id: Optional[str] = None,
        causality_depth: int = 0,
        trace_id: Optional[str] = None,
        command_text: Optional[str] = None,
        command_duration_ms: Optional[float] = None,
        command_success: Optional[bool] = None,
        command_error_msg: Optional[str] = None,
        command_batch_count: Optional[int] = None,
        command_batch_id: Optional[str] = None,
        output_event_type: Optional[str] = None,
        output_name: Optional[str] = None,
        duration_ms: float = 0.0,
        error: Optional[str] = None,
    ) -> None:
        """Log an i3pm internal event to the event buffer.

        Feature 102: i3pm events are distinct from Sway IPC events.
        These are generated by i3pm daemon logic (project switches,
        visibility changes, command execution, etc.).

        Args:
            event_type: Event type (e.g., "project::switch", "visibility::hidden")
            window_id: Window container ID (for window-scoped events)
            window_class: Window class/app_id
            window_title: Window title
            workspace_name: Workspace name
            project_name: Project name
            old_project: Previous project (for project switches)
            new_project: New project (for project switches)
            windows_affected: Number of windows affected
            correlation_id: UUID linking events in a causality chain
            causality_depth: Nesting depth in causality chain (0=root)
            trace_id: Active trace ID if event is part of a trace
            command_text: Sway command text (for command events)
            command_duration_ms: Command execution time
            command_success: Command success status
            command_error_msg: Command error message
            command_batch_count: Number of commands in batch
            command_batch_id: Batch identifier
            output_event_type: Output event subtype
            output_name: Output/monitor name
            duration_ms: Event processing duration
            error: Error message if failed
        """
        if not self.event_buffer:
            return

        entry = EventEntry(
            event_id=self.event_buffer.event_counter,
            event_type=event_type,
            timestamp=datetime.now(),
            source="i3pm",  # Feature 102: i3pm source for internal events
            window_id=window_id,
            window_class=window_class,
            window_title=window_title,
            workspace_name=workspace_name,
            project_name=project_name,
            old_project=old_project,
            new_project=new_project,
            windows_affected=windows_affected,
            # Feature 102: Correlation and causality tracking
            correlation_id=correlation_id,
            causality_depth=causality_depth,
            trace_id=trace_id,
            # Feature 102: Command execution fields
            command_text=command_text,
            command_duration_ms=command_duration_ms,
            command_success=command_success,
            command_error_msg=command_error_msg,
            command_batch_count=command_batch_count,
            command_batch_id=command_batch_id,
            # Feature 102: Output event fields
            output_event_type=output_event_type,
            output_name=output_name,
            processing_duration_ms=duration_ms,
            error=error,
        )
        await self.event_buffer.add_event(entry)

        logger.debug(
            f"[Feature 102] Logged i3pm event: {event_type} "
            f"(correlation={correlation_id[:8] if correlation_id else 'none'}, depth={causality_depth})"
        )

    async def _get_status(self) -> Dict[str, Any]:
        """Get daemon status."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            return await self.daemon_status_service.cli_status()
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::status",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_active_project(self) -> Dict[str, Any]:
        """Get active project info with full project details.

        Returns:
            Dictionary with project details or None values if no active project.
            Format matches what the app launcher wrapper script expects.

        Feature 098: Includes parent_project, branch_metadata, and git_metadata fields.
        """
        project_name = await self.state_manager.get_active_project()

        if project_name is None:
            return {
                "name": None,
                "display_name": None,
                "icon": None,
                "directory": None,
            }

        # Get full project details from state
        projects = self.state_manager.state.projects
        if project_name not in projects:
            logger.warning(f"Active project '{project_name}' not found in state")
            return {
                "name": project_name,
                "display_name": project_name,
                "icon": "",
                "directory": None,
            }

        project = projects[project_name]
        result = {
            "name": project.name,
            "display_name": project.display_name,
            "icon": project.icon or "",
            "directory": str(project.directory),
        }

        # Feature 087: Include remote configuration if present
        if project.remote is not None:
            result["remote"] = project.remote.model_dump()

        # Feature 098: Include source_type, parent_project, branch_metadata, git_metadata
        result["source_type"] = project.source_type.value if hasattr(project, 'source_type') and project.source_type else "local"
        result["status"] = project.status.value if hasattr(project, 'status') and project.status else "active"

        # parent_project (nullable)
        if hasattr(project, 'parent_project') and project.parent_project:
            result["parent_project"] = project.parent_project

        # branch_metadata (nullable object)
        if hasattr(project, 'branch_metadata') and project.branch_metadata:
            result["branch_metadata"] = {
                "number": project.branch_metadata.number,
                "type": project.branch_metadata.type,
                "full_name": project.branch_metadata.full_name,
            }

        # git_metadata (nullable object)
        if hasattr(project, 'git_metadata') and project.git_metadata:
            result["git_metadata"] = {
                "branch": project.git_metadata.current_branch if hasattr(project.git_metadata, 'current_branch') else None,
                "commit": project.git_metadata.commit_hash if hasattr(project.git_metadata, 'commit_hash') else None,
                "is_clean": project.git_metadata.is_clean if hasattr(project.git_metadata, 'is_clean') else None,
                "ahead": project.git_metadata.ahead_count if hasattr(project.git_metadata, 'ahead_count') else None,
                "behind": project.git_metadata.behind_count if hasattr(project.git_metadata, 'behind_count') else None,
            }

        return result

    async def _context_get_active(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return the canonical active runtime context owned by the daemon."""
        active_project = await self.state_manager.get_active_project()
        return self._build_active_context_response(
            self._get_active_runtime_context(active_project=active_project),
            active_project=active_project,
        )

    async def _context_ensure(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Public RPC for daemon-owned context alignment."""
        params = params or {}
        desired_project = str(
            params.get("qualified_name")
            or params.get("project_name")
            or ""
        ).strip()
        requested_target_host = self._resolve_requested_target_host(
            params.get("target_host")
            or params.get("host")
            or params.get("target_variant")
            or params.get("execution_mode")
            or "",
            project_name=desired_project,
        )
        desired_connection_key = self._normalize_connection_key(str(params.get("connection_key") or "").strip())

        if int(params.get("__intent_epoch") or 0) > 0:
            self._clear_focus_overrides()

        if bool(params.get("clear")) or desired_project == "global":
            clear_result = await self._worktree_clear({})
            return {
                "success": True,
                "switched": True,
                "cleared": True,
                "requested_project": "global",
                "requested_target_host": requested_target_host,
                "context": await self._context_get_active({}),
                "previous_project": clear_result.get("previous_project"),
            }

        if not desired_project:
            return {
                "success": True,
                "switched": False,
                "cleared": False,
                "requested_project": "",
                "requested_target_host": requested_target_host,
                "context": await self._context_get_active({}),
            }

        switch_result = await self._switch_runtime_context_if_needed(
            desired_project,
            requested_target_host,
            desired_connection_key,
        )
        context = switch_result.get("context") if isinstance(switch_result, dict) else None
        if not isinstance(context, dict):
            context = await self._context_get_active({})

        return {
            "success": True,
            "switched": bool(switch_result.get("switched", False)) if isinstance(switch_result, dict) else False,
            "cleared": False,
            "requested_project": desired_project,
            "requested_target_host": requested_target_host,
            "context": context,
        }

    async def _get_projects(self) -> Dict[str, Any]:
        """List all projects with window counts.

        Feature 101: Uses repos.json as single source of truth.
        All projects are worktrees (including main branch checkouts).
        """
        from pathlib import Path

        start_time = time.perf_counter()
        error_msg = None
        project_count = 0

        try:
            # Feature 101: Load from repos.json
            repos_file = ConfigPaths.REPOS_FILE
            if not repos_file.exists():
                return {"projects": {}}

            with open(repos_file) as f:
                repos_data = json.load(f)

            result = {}

            for repo in repos_data.get("repositories", []):
                repo_qualified = f"{repo.get('account', '')}/{repo.get('name', '')}"

                for wt in repo.get("worktrees", []):
                    branch = wt.get("branch", "unknown")
                    qualified_name = f"{repo_qualified}:{branch}"

                    # Get window count for this project
                    windows = await self.state_manager.get_windows_by_project(qualified_name)

                    result[qualified_name] = {
                        "display_name": branch,
                        "icon": "🌿",
                        "directory": wt.get("path", ""),
                        "window_count": len(windows),
                        # Feature 101: All projects are worktrees
                        "source_type": "worktree",
                        "status": "active" if Path(wt.get("path", "")).exists() else "missing",
                        "parent_project": repo_qualified,
                        "git_metadata": {
                            "branch": branch,
                            "is_clean": wt.get("is_clean", True),
                            "ahead": wt.get("ahead", 0),
                            "behind": wt.get("behind", 0),
                        },
                    }
                    project_count += 1

            return {"projects": result}
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::projects",
                result_count=project_count,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Query windows with filters."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            project = params.get("project")

            if project:
                windows = await self.state_manager.get_windows_by_project(project)
            else:
                windows = list(self.state_manager.state.window_map.values())

            result = {
                "windows": [
                    {
                        "window_id": w.window_id,
                        "class": w.window_class,
                        "title": w.window_title,
                        "project": w.project,
                        "workspace": w.workspace,
                    }
                    for w in windows
                ]
            }
            return result
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::windows",
                params={"project": params.get("project")} if params.get("project") else None,
                result_count=len(windows) if 'windows' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _project_get_focused_workspace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get the focused workspace for a project (T030, US1, Feature 074).

        Queries the FocusTracker to retrieve which workspace was last focused
        for the specified project. This allows external tools to query focus history.

        Args:
            params: Dictionary with required key:
                - project: Project name to query (string)

        Returns:
            Dictionary with:
                - project: Project name (string)
                - workspace: Focused workspace number (int, 1-70) or None if no history

        Raises:
            KeyError: If 'project' parameter is missing
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project = params["project"]

            # Query FocusTracker for focused workspace
            if hasattr(self.state_manager, 'focus_tracker') and self.state_manager.focus_tracker:
                workspace = await self.state_manager.focus_tracker.get_project_focused_workspace(project)
                logger.debug(f"IPC: get_focused_workspace({project}) → {workspace}")
            else:
                logger.warning("FocusTracker not initialized, returning None")
                workspace = None

            return {
                "project": project,
                "workspace": workspace,
            }

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get_focused_workspace",
                project=params.get("project") if params else None,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _project_set_focused_workspace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Set the focused workspace for a project (T031, US1, Feature 074).

        Manually sets which workspace should be focused when switching to this project.
        This allows external tools or manual intervention to override the automatic
        focus tracking.

        Args:
            params: Dictionary with required keys:
                - project: Project name (string)
                - workspace: Workspace number to focus (int, 1-70)

        Returns:
            Dictionary with:
                - project: Project name (string)
                - workspace: Workspace number that was set (int)
                - success: True if operation succeeded (boolean)

        Raises:
            KeyError: If 'project' or 'workspace' parameter is missing
            ValueError: If workspace number is not in range 1-70
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            requested_project = str(params["project"] or "").strip()
            workspace = params["workspace"]
            project = self._canonical_discovered_project_name(requested_project)
            if not project:
                raise ValueError(f"Unknown discovered worktree project: {requested_project}")

            # Validate workspace number
            if not isinstance(workspace, int) or workspace < 1 or workspace > 70:
                raise ValueError(f"Workspace must be an integer between 1 and 70, got: {workspace}")

            # Set focused workspace via FocusTracker
            if hasattr(self.state_manager, 'focus_tracker') and self.state_manager.focus_tracker:
                await self.state_manager.focus_tracker.track_workspace_focus(project, workspace)
                logger.info(f"IPC: set_focused_workspace({project}, {workspace}) succeeded")
                success = True
            else:
                logger.error("FocusTracker not initialized, cannot set focused workspace")
                success = False

            return {
                "project": project,
                "workspace": workspace,
                "success": success,
            }

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::set_focused_workspace",
                project=params.get("project") if params else None,
                workspace=params.get("workspace") if params else None,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _config_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get session management configuration for a project (T085, US5, Feature 074).

        Returns configuration settings that control auto-save, auto-restore,
        and other session management features for the specified project.

        Args:
            params: Dictionary with required key:
                - project: Project name to query (string)

        Returns:
            Dictionary with:
                - project: Project name (string)
                - auto_save: Auto-save enabled (boolean)
                - auto_restore: Auto-restore enabled (boolean)
                - default_layout: Default layout name (string or None)
                - max_auto_saves: Maximum auto-saves to keep (int)

        Raises:
            KeyError: If 'project' parameter is missing
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project = params["project"]

            # Load project configuration
            from .models.config import ProjectConfiguration
            from pathlib import Path

            try:
                project_dir = Path.home() / "projects" / project
                project_config = ProjectConfiguration(
                    name=project,
                    directory=project_dir
                )
            except Exception as e:
                logger.debug(f"Could not load config for {project}: {e}, using defaults")
                # Use defaults if config cannot be loaded
                project_config = ProjectConfiguration(
                    name=project,
                    directory=Path.home() / "projects" / project
                )

            result = {
                "project": project,
                "auto_save": project_config.auto_save,
                "auto_restore": project_config.auto_restore,
                "default_layout": project_config.default_layout,
                "max_auto_saves": project_config.max_auto_saves
            }

            logger.debug(f"IPC: config.get({project}) → {result}")
            return result

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::get",
                project=params.get("project") if params else None,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _config_set(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Update session management configuration (T086, US5, Feature 074).

        Updates configuration settings for a project (runtime only, not persisted).
        Changes are lost on daemon restart. To persist, edit app-registry-data.nix.

        Args:
            params: Dictionary with:
                - project: Project name (required, string)
                - auto_save: Enable auto-save (optional, boolean)
                - auto_restore: Enable auto-restore (optional, boolean)
                - default_layout: Default layout name (optional, string or None)
                - max_auto_saves: Maximum auto-saves to keep (optional, int 1-100)

        Returns:
            Dictionary with:
                - success: True if operation succeeded (boolean)
                - config: Updated configuration dictionary

        Raises:
            KeyError: If 'project' parameter is missing
            ValueError: If any parameter value is invalid
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project = params["project"]

            # Note: This is a runtime-only configuration update.
            # The actual implementation would need a runtime config store
            # in StateManager. For now, we log the intent and return success.

            # Validate parameters
            if "auto_save" in params and not isinstance(params["auto_save"], bool):
                raise ValueError("auto_save must be a boolean")

            if "auto_restore" in params and not isinstance(params["auto_restore"], bool):
                raise ValueError("auto_restore must be a boolean")

            if "max_auto_saves" in params:
                max_saves = params["max_auto_saves"]
                if not isinstance(max_saves, int) or max_saves < 1 or max_saves > 100:
                    raise ValueError("max_auto_saves must be an integer between 1 and 100")

            # Build updated config (this would be persisted to runtime store)
            updated_config = {
                "project": project,
                "auto_save": params.get("auto_save", True),
                "auto_restore": params.get("auto_restore", False),
                "default_layout": params.get("default_layout"),
                "max_auto_saves": params.get("max_auto_saves", 10)
            }

            logger.info(f"IPC: config.set({project}) → {updated_config}")
            logger.warning("Runtime config updates not persisted - edit app-registry-data.nix for persistence")

            return {
                "success": True,
                "config": updated_config
            }

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::set",
                project=params.get("project") if params else None,
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _state_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get current daemon state including focus tracking (T096, Feature 074).

        Returns complete daemon state with focus dictionaries for projects and workspaces.

        Args:
            params: Empty dictionary (no parameters required)

        Returns:
            Dictionary with:
                - active_project: Current project (string or None)
                - uptime_seconds: Daemon uptime (float)
                - event_count: Total events processed (int)
                - error_count: Total errors (int)
                - window_count: Number of tracked windows (int)
                - workspace_count: Number of tracked workspaces (int)
                - project_focused_workspaces: Project → workspace mapping (dict)
                - workspace_focused_windows: Workspace → window ID mapping (dict)
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            # Get basic stats from state manager
            stats = await self.state_manager.get_stats()

            # Add focus tracking state (Feature 074: T096)
            if hasattr(self.state_manager, 'focus_tracker') and self.state_manager.focus_tracker:
                # Get all project focus data
                project_focused_workspaces = {}
                # Note: We'd need to iterate through known projects
                # For now, get from DaemonState directly
                if hasattr(self.state_manager.state, 'project_focused_workspace'):
                    project_focused_workspaces = self.state_manager.state.project_focused_workspace.copy()

                # Get all workspace focus data
                workspace_focused_windows = {}
                if hasattr(self.state_manager.state, 'workspace_focused_window'):
                    workspace_focused_windows = self.state_manager.state.workspace_focused_window.copy()
            else:
                project_focused_workspaces = {}
                workspace_focused_windows = {}

            result = {
                **stats,  # Include basic stats (active_project, uptime_seconds, etc.)
                "project_focused_workspaces": project_focused_workspaces,
                "workspace_focused_windows": workspace_focused_windows
            }

            logger.debug(f"IPC: state.get() → {len(result)} fields")
            return result

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="state::get",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _daemon_contract(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get the daemon contract marker used by health and rebuild gates."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            result = self.daemon_contract_service.contract_payload()
            logger.debug("IPC: daemon.contract() → %s", result["schema_version"])
            return result

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="daemon::contract",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _daemon_version(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get daemon API version for version negotiation (T097, Feature 074).

        Returns API version information for client compatibility checking.

        Args:
            params: Empty dictionary (no parameters required)

        Returns:
            Dictionary with:
                - version: Daemon version (string, e.g., "1.0.0")
                - api_version: API version (string, e.g., "1.0.0")
                - features: List of supported features (list of strings)
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            result = self.daemon_contract_service.version_payload()

            logger.debug(f"IPC: daemon.version() → {result['version']}")
            return result

        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="daemon::version",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return recent events for diagnostics (Feature 017).

        Feature 029: T017 - Extended to support systemd and proc event sources.

        Args:
            params: Query parameters:
                - limit: Maximum events to return (default 100)
                - event_type: Filter by event type
                - source: Filter by source ("i3", "ipc", "daemon", "systemd", "proc", "all")
                - since_id: Return events since this event_id
                - since: Time specification for systemd queries (e.g., "1 hour ago")

        Returns:
            Dictionary with events list and buffer stats
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            limit = params.get("limit", 100)
            event_type = params.get("event_type")
            source = params.get("source")
            since_id = params.get("since_id")

            # Feature 029: Handle systemd/proc/all sources with unified stream
            if source in ("systemd", "proc", "all"):
                # Unified event stream: merge events from multiple sources
                all_events = []

                # Get buffer events (i3, ipc, daemon, proc)
                # Note: proc events are in event_buffer, not separate storage
                if source in ("all", "proc") or (self.event_buffer and source not in ("systemd",)):
                    if self.event_buffer:
                        buffer_events = self.event_buffer.get_events(
                            limit=limit,
                            event_type=event_type,
                            source=source if source != "all" else None,
                            since_id=since_id
                        )
                        all_events.extend(buffer_events)

                # Get systemd events if requested
                # Feature 029: Run in thread pool to avoid blocking watchdog
                if source in ("systemd", "all"):
                    since = params.get("since", "1 hour ago")
                    systemd_events = await asyncio.to_thread(
                        systemd_query.query_systemd_journal_sync,
                        since=since,
                        limit=limit
                    )
                    all_events.extend(systemd_events)

                # Sort all events by timestamp (chronological order)
                all_events.sort(key=lambda e: e.timestamp)

                # Apply limit after merge
                all_events = all_events[-limit:]

                # Convert to dict
                events_data = self._convert_events_to_dict(all_events)

                return {
                    "events": events_data,
                    "stats": self.event_buffer.get_stats() if self.event_buffer else {
                        "total_events": len(events_data),
                        "buffer_size": 0,
                        "max_size": 0
                    }
                }

            # Original behavior for i3/ipc/daemon sources
            if not self.event_buffer:
                return {"events": [], "stats": {"total_events": 0, "buffer_size": 0, "max_size": 0}}

            # Get events from buffer
            events = self.event_buffer.get_events(limit=limit, event_type=event_type, source=source, since_id=since_id)

            # Convert EventEntry objects to dict
            events_data = self._convert_events_to_dict(events)

            return {
                "events": events_data,
                "stats": self.event_buffer.get_stats()
            }
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::events",
                params={"limit": params.get("limit"), "event_type": params.get("event_type")},
                result_count=len(events) if 'events' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    def _convert_events_to_dict(self, events: list) -> list:
        """Convert EventEntry objects to dictionary format for JSON serialization.

        Feature 029: Helper method to handle all event types (i3, ipc, daemon, systemd, proc).

        Args:
            events: List of EventEntry objects

        Returns:
            List of event dictionaries with all relevant fields
        """
        events_data = []
        for e in events:
            event_dict = {
                "event_id": e.event_id,
                "event_type": e.event_type,
                "timestamp": e.timestamp.isoformat(),
                "source": e.source,
                "processing_duration_ms": e.processing_duration_ms,
            }

            # Add i3/window fields if present
            if e.window_id is not None:
                event_dict["window_id"] = e.window_id
            if e.window_class:
                event_dict["window_class"] = e.window_class
            if e.workspace_name:
                event_dict["workspace_name"] = e.workspace_name
            if e.project_name:
                event_dict["project_name"] = e.project_name
            if e.tick_payload:
                event_dict["tick_payload"] = e.tick_payload
            if e.error:
                event_dict["error"] = e.error

            # Feature 029: Add systemd fields if present
            if e.systemd_unit:
                event_dict["systemd_unit"] = e.systemd_unit
            if e.systemd_message:
                event_dict["systemd_message"] = e.systemd_message
            if e.systemd_pid is not None:
                event_dict["systemd_pid"] = e.systemd_pid
            if e.journal_cursor:
                event_dict["journal_cursor"] = e.journal_cursor

            # Feature 029: Add process fields if present (for future US2 implementation)
            if e.process_pid is not None:
                event_dict["process_pid"] = e.process_pid
            if e.process_name:
                event_dict["process_name"] = e.process_name
            if e.process_cmdline:
                event_dict["process_cmdline"] = e.process_cmdline
            if e.process_parent_pid is not None:
                event_dict["process_parent_pid"] = e.process_parent_pid
            if e.process_start_time is not None:
                event_dict["process_start_time"] = int(e.process_start_time.timestamp() * 1000)

            events_data.append(event_dict)

        return events_data

    async def _list_monitors(self) -> Dict[str, Any]:
        """List all connected monitor clients (Feature 017).

        Returns:
            Dictionary with list of connected monitors
        """
        monitors = []
        for idx, writer in enumerate(self.clients):
            peer = writer.get_extra_info("peername")
            monitors.append({
                "monitor_id": idx,
                "peer": str(peer),
                "subscribed": writer in self.subscribed_clients
            })

        return {
            "monitors": monitors,
            "total_clients": len(self.clients),
            "subscribed_clients": len(self.subscribed_clients)
        }

    async def _subscribe_events(self, params: Dict[str, Any], writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Subscribe/unsubscribe from event stream (Feature 017).

        Args:
            params: Subscription parameters (subscribe: bool)
            writer: Stream writer for this client connection

        Returns:
            Subscription confirmation
        """
        subscribe = params.get("subscribe", True)

        if subscribe:
            self.subscribed_clients.add(writer)
            logger.info(f"Client subscribed to events (total subscribers: {len(self.subscribed_clients)})")
        else:
            self.subscribed_clients.discard(writer)
            logger.info(f"Client unsubscribed from events (total subscribers: {len(self.subscribed_clients)})")

        # Feature 058: Return simple "subscribed" result for workspace mode events
        if subscribe:
            return "subscribed"
        else:
            return "unsubscribed"

    async def broadcast_event(self, event_data: Dict[str, Any]) -> None:
        """Broadcast event notification to all subscribed clients (Feature 017).

        Args:
            event_data: Event data to broadcast
        """
        if not self.subscribed_clients:
            return

        # Feature 058: Use "event" method for workspace panel compatibility
        notification = {
            "jsonrpc": "2.0",
            "method": "event",
            "params": event_data
        }
        message = json.dumps(notification).encode() + b"\n"

        # Send to all subscribed clients
        for writer in list(self.subscribed_clients):
            try:
                writer.write(message)
                await writer.drain()
                logger.debug(f"Successfully sent event to client")
            except Exception as e:
                logger.error(f"Failed to broadcast to client: {e}")
                self.subscribed_clients.discard(writer)

    async def broadcast_event_entry(self, event_entry) -> None:
        """Broadcast EventEntry to all subscribed clients (Feature 017: T019).

        Args:
            event_entry: EventEntry instance to broadcast
        """
        # Convert EventEntry to dict for JSON serialization
        # Include all unified event system fields
        event_data = {
            "event_id": event_entry.event_id,
            "event_type": event_entry.event_type,
            "timestamp": event_entry.timestamp.isoformat(),
            "source": event_entry.source,

            # Window event fields
            "window_id": event_entry.window_id,
            "window_class": event_entry.window_class,
            "window_title": event_entry.window_title,
            "window_instance": event_entry.window_instance,
            "workspace_name": event_entry.workspace_name,

            # Project event fields
            "project_name": event_entry.project_name,
            "project_directory": event_entry.project_directory,
            "old_project": event_entry.old_project,
            "new_project": event_entry.new_project,
            "windows_affected": event_entry.windows_affected,

            # Tick event fields
            "tick_payload": event_entry.tick_payload,

            # Output event fields
            "output_name": event_entry.output_name,
            "output_count": event_entry.output_count,

            # Query event fields
            "query_method": event_entry.query_method,
            "query_params": event_entry.query_params,
            "query_result_count": event_entry.query_result_count,

            # Config event fields
            "config_type": event_entry.config_type,
            "rules_added": event_entry.rules_added,
            "rules_removed": event_entry.rules_removed,

            # Daemon event fields
            "daemon_version": event_entry.daemon_version,
            "i3_socket": event_entry.i3_socket,

            # Systemd event fields (Feature 029)
            "systemd_unit": event_entry.systemd_unit,
            "systemd_message": event_entry.systemd_message,
            "systemd_pid": event_entry.systemd_pid,
            "journal_cursor": event_entry.journal_cursor,

            # Process event fields (Feature 029)
            "process_pid": event_entry.process_pid,
            "process_name": event_entry.process_name,
            "process_cmdline": event_entry.process_cmdline,
            "process_parent_pid": event_entry.process_parent_pid,
            "process_start_time": event_entry.process_start_time.isoformat() if hasattr(event_entry.process_start_time, 'isoformat') else event_entry.process_start_time,

            # Processing metadata
            "processing_duration_ms": event_entry.processing_duration_ms,
            "error": event_entry.error,
        }
        await self.broadcast_event(event_data)

    async def _reload_config(self) -> Dict[str, Any]:
        """Reload project configs from disk."""
        start_time = time.perf_counter()
        error_msg = None

        try:
            # TODO: Implement config reload
            return {"success": True, "message": "Config reloaded"}
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::reload",
                config_type="project_configs",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_diagnostic_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get complete diagnostic snapshot (Feature 018).

        Combines daemon state, projects, windows, events, monitors, and i3 tree
        into a single atomic snapshot for diagnostic capture.

        Args:
            params: Query parameters
                - include_events: bool (default True) - Include event buffer
                - event_limit: int (default 500) - Number of events to include
                - include_tree: bool (default True) - Include i3 tree dump
                - include_monitors: bool (default True) - Include monitor client list

        Returns:
            Dictionary with complete diagnostic state
        """
        import time

        start_time = time.perf_counter()

        # Parse parameters
        include_events = params.get("include_events", True)
        event_limit = params.get("event_limit", 500)
        include_tree = params.get("include_tree", True)
        include_monitors = params.get("include_monitors", True)

        # Gather all state in parallel for performance
        daemon_state = await self._get_status()
        projects_data = await self._get_projects()
        windows_data = await self._get_windows({})

        # Optional components
        events_data = {"events": [], "stats": {}}
        if include_events:
            events_data = await self._get_events({"limit": event_limit})

        monitors_data = {"monitors": [], "total_clients": 0, "subscribed_clients": 0}
        if include_monitors:
            monitors_data = await self._list_monitors()

        # i3 tree dump (requires i3 connection)
        i3_tree = None
        if include_tree and self.i3_connection and self.i3_connection.conn:
            try:
                tree = await self.i3_connection.get_tree()
                # Convert i3ipc tree to dict (recursive)
                i3_tree = self._tree_to_dict(tree)
            except Exception as e:
                logger.error(f"Failed to get i3 tree: {e}")
                i3_tree = {"error": str(e)}

        # Calculate capture duration
        end_time = time.perf_counter()
        capture_duration_ms = (end_time - start_time) * 1000

        return {
            "daemon_state": daemon_state,
            "projects": projects_data["projects"],
            "windows": windows_data["windows"],
            "events": events_data["events"],
            "event_stats": events_data.get("stats", {}),
            "monitors": monitors_data["monitors"],
            "monitor_stats": {
                "total_clients": monitors_data["total_clients"],
                "subscribed_clients": monitors_data["subscribed_clients"]
            },
            "i3_tree": i3_tree,
            "capture_duration_ms": round(capture_duration_ms, 2)
        }

    def _tree_to_dict(self, node: Any) -> Dict[str, Any]:
        """Convert i3ipc tree node to dictionary recursively.

        Args:
            node: i3ipc Con (container) node

        Returns:
            Dictionary representation of tree node
        """
        # Convert basic attributes
        result = {
            "id": node.id,
            "name": node.name,
            "type": node.type,
            "border": node.border,
            "current_border_width": node.current_border_width,
            "layout": node.layout,
            "orientation": node.orientation,
            "percent": node.percent,
            "rect": {
                "x": node.rect.x,
                "y": node.rect.y,
                "width": node.rect.width,
                "height": node.rect.height
            },
            "window_rect": {
                "x": node.window_rect.x,
                "y": node.window_rect.y,
                "width": node.window_rect.width,
                "height": node.window_rect.height
            },
            "deco_rect": {
                "x": node.deco_rect.x,
                "y": node.deco_rect.y,
                "width": node.deco_rect.width,
                "height": node.deco_rect.height
            },
            "geometry": {
                "x": node.geometry.x,
                "y": node.geometry.y,
                "width": node.geometry.width,
                "height": node.geometry.height
            },
            "window": node.window,
            "urgent": node.urgent,
            "focused": node.focused,
            "focus": node.focus,
            "nodes": [],
            "floating_nodes": [],
            "marks": node.marks,
            "fullscreen_mode": node.fullscreen_mode,
            "sticky": node.sticky,
            "floating": node.floating,
            "window_class": getattr(node, 'window_class', None),
            "window_instance": getattr(node, 'window_instance', None),
            "app_id": getattr(node, 'app_id', None),
            "pid": getattr(node, 'pid', None),
            "window_title": getattr(node.window_properties, 'title', None) if hasattr(node, 'window_properties') and node.window_properties else None
        }

        # Recursively convert child nodes
        if hasattr(node, 'nodes') and node.nodes:
            result["nodes"] = [self._tree_to_dict(child) for child in node.nodes]

        if hasattr(node, 'floating_nodes') and node.floating_nodes:
            result["floating_nodes"] = [self._tree_to_dict(child) for child in node.floating_nodes]

        return result

    async def _get_window_rules(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get window rules with optional scope filter (Feature 021: T025).

        Args:
            params: Query parameters with optional scope filter

        Returns:
            Dictionary with rules list and count

        Example:
            Request: {"method": "get_window_rules", "params": {"scope": "scoped"}}
            Response: {"rules": [...], "count": 5}
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            if not self.window_rules_getter:
                return {"rules": [], "count": 0, "error": "Window rules not available"}

            # Get current window rules
            window_rules = self.window_rules_getter()

            # Apply scope filter if provided
            scope_filter = params.get("scope")
            if scope_filter:
                window_rules = [r for r in window_rules if r.scope == scope_filter]

            # Serialize rules to dict
            rules_data = [
                {
                    "pattern": r.pattern_rule.pattern,
                    "scope": r.scope,
                    "priority": r.priority,
                    "workspace": r.workspace,
                    "description": r.pattern_rule.description,
                    "modifier": r.modifier,
                }
                for r in window_rules
            ]

            return {
                "rules": rules_data,
                "count": len(rules_data),
            }
        except Exception as e:
            error_msg = str(e)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::rules",
                params={"scope": params.get("scope")} if params.get("scope") else None,
                result_count=len(rules_data) if 'rules_data' in locals() else 0,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _classify_window(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Classify a window using the 4-level precedence system (Feature 021: T026).

        Args:
            params: Classification parameters
                - window_class (required): Window WM_CLASS
                - window_title (optional): Window title
                - project_name (optional): Active project name

        Returns:
            Classification result with scope, workspace, source

        Example:
            Request: {"method": "classify_window", "params": {"window_class": "Code", "project_name": "nixos"}}
            Response: {"scope": "scoped", "workspace": null, "source": "project", "matched_pattern": null}
        """
        window_class = params.get("window_class")
        if not window_class:
            raise ValueError("window_class parameter is required")

        window_title = params.get("window_title", "")
        project_name = params.get("project_name")

        # Get active project's scoped classes
        active_project_scoped_classes = None
        if project_name and project_name in self.state_manager.state.projects:
            project = self.state_manager.state.projects[project_name]
            active_project_scoped_classes = project.scoped_classes

        # Get window rules
        window_rules = None
        if self.window_rules_getter:
            window_rules = self.window_rules_getter()

        # Get app classification
        app_classification_scoped = list(self.state_manager.state.scoped_classes)
        app_classification_global = list(self.state_manager.state.global_classes)

        # Classify
        classification = classify_window(
            window_class=window_class,
            window_title=window_title,
            active_project_scoped_classes=active_project_scoped_classes,
            window_rules=window_rules,
            app_classification_patterns=None,  # TODO: Extract from app classification
            app_classification_scoped=app_classification_scoped,
            app_classification_global=app_classification_global,
        )

        return classification.to_json()

    # ==========================================================================
    # Feature 123: Window tree caching and state change notifications
    # ==========================================================================

    def invalidate_window_tree_cache(self) -> None:
        """Invalidate the window tree cache.

        Called by event handlers when window/workspace state changes.
        This forces the next get_window_tree() call to query Sway IPC fresh.
        PID environ cache is intentionally preserved here because window move/focus
        events do not imply process environment changes, and clearing it on every
        tree invalidation defeats the short-TTL classification cache.
        """
        if self._window_tree_cache is not None:
            logger.debug("[Feature 123] Window tree cache invalidated")
        self._window_tree_cache = None
        self._window_tree_cache_time = 0.0

    def invalidate_worktree_cache(self) -> None:
        """Invalidate the cached worktree summary used by dashboard snapshots."""
        self.dashboard_worktree_service.invalidate()
        self.dashboard_git_service.clear_snapshot_cache()

    def _canonical_discovered_project_name(
        self,
        project_name: Optional[str],
        *,
        project_path: Optional[str] = None,
    ) -> str:
        """Return the canonical discovered worktree name or an empty string."""
        normalized_name = str(project_name or "").strip()
        if not normalized_name or normalized_name.lower() == "global":
            return ""

        discovered = resolve_discovered_worktree_name(normalized_name)
        if not discovered:
            return ""

        if project_path and not discovered_worktree_matches_path(
            discovered.get("qualified_name"),
            project_path,
        ):
            return ""
        return str(discovered.get("qualified_name") or "").strip()

    def _load_validated_project_usage_map(self) -> Dict[str, Dict[str, Any]]:
        """Load project usage and prune entries that no longer resolve to worktrees."""
        usage_file = ConfigPaths.PROJECT_USAGE_FILE
        data: Dict[str, Any] = {"version": 1, "projects": {}}

        if usage_file.exists():
            try:
                existing_usage = json.loads(usage_file.read_text())
                if isinstance(existing_usage, dict):
                    data.update(existing_usage)
            except Exception as exc:
                logger.debug("dashboard.worktrees could not read project usage map: %s", exc)

        raw_projects = data.get("projects", {})
        if not isinstance(raw_projects, dict):
            raw_projects = {}

        pruned_projects: Dict[str, Dict[str, Any]] = {}
        removed = 0
        for qualified_name, entry in raw_projects.items():
            canonical_name = self._canonical_discovered_project_name(str(qualified_name or "").strip())
            if not canonical_name:
                removed += 1
                continue
            if not isinstance(entry, dict):
                entry = {}
            pruned_projects[canonical_name] = {
                "last_used_at": int(entry.get("last_used_at", 0) or 0),
                "use_count": int(entry.get("use_count", 0) or 0),
            }

        if removed or pruned_projects != raw_projects:
            updated = {
                "version": int(data.get("version", 1) or 1),
                "updated_at": int(time.time()),
                "projects": pruned_projects,
            }
            atomic_write_json(usage_file, updated)
            logger.info("Pruned %s stale project usage entr%s", removed, "y" if removed == 1 else "ies")

        return pruned_projects

    def prune_persisted_project_state(self) -> Dict[str, int]:
        """Prune persisted project state that no longer resolves to discovered worktrees."""
        stats = {
            "usage_removed": 0,
            "focus_removed": 0,
            "active_project_cleared": 0,
            "active_worktree_cleared": 0,
        }

        usage_file = ConfigPaths.PROJECT_USAGE_FILE
        if usage_file.exists():
            before_count = 0
            try:
                existing = json.loads(usage_file.read_text())
                if isinstance(existing, dict) and isinstance(existing.get("projects"), dict):
                    before_count = len(existing.get("projects", {}))
            except Exception:
                before_count = 0
            usage_map = self._load_validated_project_usage_map()
            stats["usage_removed"] = max(0, before_count - len(usage_map))

        focus_tracker = getattr(self.state_manager, "focus_tracker", None)
        if focus_tracker is not None:
            focus_file_exists = False
            try:
                if focus_tracker.project_focus_file.exists():
                    focus_file_exists = True
                    raw_focus = json.loads(focus_tracker.project_focus_file.read_text())
                    before_count = len(raw_focus) if isinstance(raw_focus, dict) else 0
                else:
                    raw_focus = {}
                    before_count = 0
            except Exception:
                raw_focus = {}
                before_count = 0
            pruned_focus = focus_tracker._prune_project_focus_map(raw_focus)
            self.state_manager.state.project_focused_workspace = pruned_focus
            if focus_file_exists or before_count > 0 or pruned_focus:
                focus_tracker.project_focus_file.write_text(json.dumps(pruned_focus, indent=2))
            stats["focus_removed"] = max(0, before_count - len(pruned_focus))

        active_project_file = ConfigPaths.ACTIVE_PROJECT_FILE
        if active_project_file.exists():
            try:
                payload = json.loads(active_project_file.read_text())
            except Exception:
                payload = {}
            project_name = str((payload or {}).get("project_name") or "").strip()
            if project_name and not self._canonical_discovered_project_name(project_name):
                active_project_file.unlink(missing_ok=True)
                stats["active_project_cleared"] = 1
                if getattr(self.state_manager.state, "active_project", None) == project_name:
                    self.state_manager.state.active_project = None

        active_worktree_file = ConfigPaths.ACTIVE_WORKTREE_FILE
        if active_worktree_file.exists():
            try:
                payload = json.loads(active_worktree_file.read_text())
            except Exception:
                payload = {}
            qualified_name = str((payload or {}).get("qualified_name") or "").strip()
            local_directory = str((payload or {}).get("local_directory") or (payload or {}).get("path") or "").strip()
            if (
                not self._canonical_discovered_project_name(qualified_name)
                or not discovered_worktree_matches_path(qualified_name, local_directory)
            ):
                active_worktree_file.unlink(missing_ok=True)
                stats["active_worktree_cleared"] = 1
                self._set_active_runtime_context(None)

        return stats

    @staticmethod
    def _stat_fingerprint(path: Path) -> Tuple[int, int]:
        """Return a cheap file fingerprint tuple for cache coherence checks."""
        try:
            stat_result = path.stat()
        except OSError:
            return (0, 0)
        return (int(stat_result.st_mtime_ns), int(stat_result.st_size))

    def _dashboard_worktree_cache_fingerprint(self, runtime_snapshot: Dict[str, Any]) -> Dict[str, Any]:
        """Build the coherence key for dashboard worktree snapshots."""
        active_context = runtime_snapshot.get("active_context", {}) if isinstance(runtime_snapshot, dict) else {}
        return {
            "active_qualified": str(active_context.get("qualified_name") or active_context.get("project_name") or "").strip(),
            "active_target_host": self._target_host_from_context_payload(
                active_context,
                project_name=str(active_context.get("qualified_name") or active_context.get("project_name") or "").strip(),
            ),
            "repos": self._stat_fingerprint(ConfigPaths.REPOS_FILE),
            "usage": self._stat_fingerprint(ConfigPaths.PROJECT_USAGE_FILE),
        }

    async def _run_git_probe_command(
        self,
        repo_path: Path,
        *args: str,
    ) -> Tuple[int, str, str]:
        """Run a bounded git command for live session/worktree status."""
        return await self.dashboard_git_service.run_git_probe_command(repo_path, *args)

    async def _probe_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
    ) -> Dict[str, Any]:
        """Probe live git state for a specific worktree path."""
        return await self.dashboard_git_service.probe_git_snapshot(
            worktree_path=worktree_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
        )

    async def _refresh_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
        notify: bool,
    ) -> Optional[Dict[str, Any]]:
        """Refresh one worktree's live git snapshot and update cache."""
        return await self.dashboard_git_service.refresh_git_snapshot(
            worktree_path=worktree_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
            notify=notify,
            notify_state_change=self.notify_state_change,
        )

    def _ensure_git_snapshot_refresh(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
    ) -> None:
        """Schedule a background git refresh if one is not already running."""
        self.dashboard_git_service.ensure_git_snapshot_refresh(
            worktree_path=worktree_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
            notify_state_change=self.notify_state_change,
        )

    async def _get_or_schedule_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
        priority: str,
        attribution: str,
    ) -> Optional[Dict[str, Any]]:
        """Return the best available git snapshot, refreshing lazily when possible."""
        return await self.dashboard_git_service.get_or_schedule_git_snapshot(
            worktree_path=worktree_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
            priority=priority,
            attribution=attribution,
            notify_state_change=self.notify_state_change,
        )

    async def _hydrate_runtime_git_state(
        self,
        runtime_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
    ) -> None:
        """Attach live git snapshots to session rows and priority dashboard worktrees."""
        await self.dashboard_git_service.hydrate_runtime_git_state(
            runtime_snapshot,
            sessions,
            build_dashboard_worktrees=self._build_dashboard_worktrees,
            get_or_schedule_git_snapshot=self._get_or_schedule_git_snapshot,
        )

    async def _worktree_refresh(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Invalidate worktree/dashboard caches after CLI-side worktree mutations."""
        _ = params
        self.invalidate_worktree_cache()
        await self.notify_state_change("worktree_changed")
        return {
            "success": True,
            "timestamp": int(time.time()),
        }

    async def _dashboard_event_payload(self, changed_keys: List[str]) -> Dict[str, Any]:
        """Build a partial dashboard payload for a typed state-change event."""
        return await self.dashboard_service.event_payload(changed_keys)

    async def notify_state_change(self, event_type: str = "dashboard_invalidated") -> None:
        """Notify subscribed clients with a typed dashboard event.

        Called by event handlers after processing Sway and service events.
        Subscribers receive typed dashboard events and can refresh or apply the
        daemon-owned payload without subscribing to Sway directly.

        Args:
            event_type: Type of state change event (for debugging)
        """
        await self.dashboard_service.notify_state_change(event_type)

    async def _subscribe_state_changes(self, params: Dict[str, Any], writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Subscribe to state change notifications (Feature 123).

        Adds the client to the state change subscriber set. The client will
        receive JSON-RPC notifications when window/workspace state changes.

        This allows legacy compatibility consumers to subscribe to daemon events
        without owning Sway subscriptions or UI state.

        Args:
            params: Subscription parameters (currently unused)
            writer: Client's stream writer

        Returns:
            dict with subscription status
        """
        return self.dashboard_service.subscribe(writer)

    async def _get_window_tree(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get hierarchical window state tree (Feature 025: T016).

        Queries i3 IPC for complete window state and organizes it hierarchically:
        outputs → workspaces → windows

        Feature 123: Uses caching to avoid redundant Sway IPC queries.
        Cache is invalidated by event handlers when state changes.

        Args:
            params: Query parameters. Supports:
                - force_refresh: bool - Bypass cache and query Sway IPC fresh

        Returns:
            Window tree dict with keys:
                - outputs: List[dict] - Monitor/output nodes
                - total_windows: int - Total window count
                - cached: bool - Whether result was from cache (Feature 123)

        Raises:
            Exception: If i3 connection unavailable or query fails
        """
        if not self.i3_connection or not self.i3_connection.conn:
            raise Exception("i3 connection not available")

        # Feature 123: Check cache first (unless force_refresh requested)
        force_refresh = params.get("force_refresh", False) if params else False
        current_time = time.time()

        if not force_refresh and self._window_tree_cache is not None:
            cache_age = current_time - self._window_tree_cache_time
            if cache_age < self._window_tree_cache_ttl:
                return {**self._window_tree_cache, "cached": True}

        # Retry logic for resilience against Sway IPC corruption
        max_retries = 3
        last_error = None

        for attempt in range(max_retries):
            try:
                # Query i3 IPC for current state using serialized methods
                # to prevent concurrent command socket corruption
                tree = await self.i3_connection.get_tree()
                workspaces = await self._sway_get_workspaces()
                outputs_list = await self.i3_connection.get_outputs()
                break  # Success, exit retry loop
            except Exception as e:
                last_error = e
                logger.warning(f"get_tree attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    # Try to reconnect before next attempt
                    try:
                        logger.info("Attempting i3 connection recovery...")
                        await self.i3_connection.validate_and_reconnect_if_needed()
                        await asyncio.sleep(0.5)  # Brief pause before retry
                    except Exception as reconnect_error:
                        logger.error(f"Reconnection failed: {reconnect_error}")
                else:
                    raise Exception(f"Failed to query i3 window tree after {max_retries} attempts: {last_error}")

        tracked_windows = await self.state_manager.get_window_map_snapshot()
        tracked_windows_by_con_id = {
            int(window_info.con_id): window_info
            for window_info in tracked_windows.values()
            if getattr(window_info, "con_id", 0)
        }

        # Build outputs structure
        outputs = []
        total_windows = 0

        for output in outputs_list:
            if not output.active or output.name.startswith("__"):
                continue  # Skip inactive and special outputs

            # Find current workspace for this output
            current_ws_name = next((ws.name for ws in workspaces if ws.output == output.name and ws.visible), "1")

            output_node = {
                "name": output.name,
                "active": output.active,
                "primary": output.primary,
                "geometry": {
                    "x": output.rect.x,
                    "y": output.rect.y,
                    "width": output.rect.width,
                    "height": output.rect.height,
                },
                "current_workspace": current_ws_name,
                "workspaces": [],
            }

            # Find workspaces on this output
            for ws in workspaces:
                if ws.output != output.name:
                    continue

                workspace_node = {
                    "number": ws.num,
                    "name": ws.name,
                    "focused": ws.focused,
                    "visible": ws.visible,
                    "output": output.name,
                    "windows": [],
                }

                # Find windows in this workspace
                ws_con = self._find_workspace_container(tree, ws.name)
                if ws_con:
                    windows = self._extract_windows_from_container(
                        ws_con,
                        ws.num,
                        output.name,
                        tracked_windows=tracked_windows,
                        tracked_windows_by_con_id=tracked_windows_by_con_id,
                    )
                    workspace_node["windows"] = windows
                    total_windows += len(windows)

                output_node["workspaces"].append(workspace_node)

            outputs.append(output_node)

        # Add scratchpad windows as a special workspace on first output
        # This ensures ALL windows are visible by default (Feature 025 enhancement)
        if outputs and self.workspace_tracker:
            scratchpad_windows_list = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )

            if scratchpad_windows_list:
                scratchpad_windows = []
                for window in scratchpad_windows_list:
                    # Get tracking info for workspace number
                    tracking_info = self.workspace_tracker.windows.get(window.id, {})
                    tracked_workspace = tracking_info.get("workspace_number", -1)

                    # Read I3PM environment variables
                    i3pm_env = await window_filtering.get_window_i3pm_env(
                        window.id, window.pid, window.window
                    )

                    # Get project from marks or I3PM_PROJECT_NAME
                    project = None
                    scope = None
                    for mark in window.marks:
                        if mark.startswith("scoped:") or mark.startswith("global:"):
                            # Feature 101: Use centralized mark parser
                            parsed = parse_mark(mark, window.id)
                            if parsed:
                                scope = parsed.scope
                                project = parsed.project_name
                            break
                    if not project:
                        project = i3pm_env.get("I3PM_PROJECT_NAME")

                    # Build marks list (include project mark for consistency)
                    # Feature 101: Unified mark format - scratchpad terminals also use scoped: prefix
                    marks = list(window.marks)
                    has_project_mark = any(m.startswith("scoped:") or m.startswith("global:") for m in marks)
                    if project and not has_project_mark:
                        # Default to scoped if we don't have scope info
                        marks.append(f"{scope or 'scoped'}:{project}")

                    # Get window class
                    window_class = window.window_class if hasattr(window, 'window_class') and window.window_class else (window.app_id if hasattr(window, 'app_id') else "unknown")

                    # Determine if hidden (scoped to different project)
                    classification = scope if scope in {"scoped", "global"} else "global"
                    hidden = True  # Scratchpad windows are hidden by definition
                    if classification == "global" and window_class and project:
                        if window_class in self.state_manager.state.scoped_classes:
                            classification = "scoped"

                    # Read I3PM_APP_ID from environment
                    app_id = i3pm_env.get("I3PM_APP_ID")
                    app_key = i3pm_env.get("I3PM_APP_NAME") or ""

                    # Feature 101: Format workspace field - include workspace 0 for scratchpad home
                    if tracked_workspace is not None and tracked_workspace > 0:
                        workspace_str = f"scratchpad (tracked: WS {tracked_workspace})"
                    elif tracked_workspace == 0:
                        # Feature 101: Workspace 0 = scratchpad home (deterministic)
                        workspace_str = "scratchpad (home: WS 0)"
                    else:
                        workspace_str = "scratchpad"

                    window_data = {
                        "id": window.id,
                        "pid": window.pid if hasattr(window, 'pid') else None,
                        "app_id": app_id,
                        "app_key": app_key,
                        "class": window_class,
                        "icon_path": "",
                        "instance": window.window_instance if hasattr(window, 'window_instance') else "",
                        "title": window.name or "(no title)",
                        "workspace": workspace_str,
                        "output": outputs[0]["name"],  # Associate with first output
                        "marks": marks,
                        "floating": True,  # Scratchpad windows are always floating
                        "focused": False,  # Can't be focused if in scratchpad
                        "hidden": hidden,
                        "fullscreen": False,
                        "geometry": {
                            "x": window.rect.x if hasattr(window, 'rect') else 0,
                            "y": window.rect.y if hasattr(window, 'rect') else 0,
                            "width": window.rect.width if hasattr(window, 'rect') else 0,
                            "height": window.rect.height if hasattr(window, 'rect') else 0,
                        },
                        "classification": classification,
                        "project": project or "",
                        # Canonical execution identity metadata for monitor-side
                        # local/ssh split grouping without extra /proc scans.
                        "execution_mode": i3pm_env.get("I3PM_EXECUTION_MODE", ""),
                        "connection_key": i3pm_env.get("I3PM_CONNECTION_KEY", ""),
                        "context_key": i3pm_env.get("I3PM_CONTEXT_KEY", ""),
                        "remote_enabled": i3pm_env.get("I3PM_REMOTE_ENABLED", ""),
                        "remote_user": i3pm_env.get("I3PM_REMOTE_USER", ""),
                        "remote_host": i3pm_env.get("I3PM_REMOTE_HOST", ""),
                        "remote_port": i3pm_env.get("I3PM_REMOTE_PORT", ""),
                        "remote_dir": i3pm_env.get("I3PM_REMOTE_DIR", ""),
                        "remote_session_name": i3pm_env.get("I3PM_REMOTE_SESSION_NAME", ""),
                    }
                    tracked_window = tracked_windows.get(int(window.id)) or tracked_windows_by_con_id.get(int(window.id))
                    if tracked_window:
                        window_data.update(self._tracked_window_runtime_fields(tracked_window))
                    if not window_data.get("app_key"):
                        window_data["app_key"] = str(window_data.get("app_name") or "")
                    window_data["icon_path"] = self._resolve_window_icon_path(
                        app_key=str(window_data.get("app_key") or ""),
                        app_id=app_id,
                        window_class=window_class,
                        window_instance=window.window_instance if hasattr(window, "window_instance") else "",
                        allow_fallback=not bool(app_key),
                    )
                    scratchpad_windows.append(window_data)
                    total_windows += 1

                # Add scratchpad as a special workspace on the first output
                scratchpad_workspace = {
                    "number": -1,  # Special workspace number for scratchpad
                    "name": "scratchpad",
                    "focused": False,
                    "visible": False,
                    "output": outputs[0]["name"],
                    "windows": scratchpad_windows,
                }
                outputs[0]["workspaces"].append(scratchpad_workspace)

        # Feature 123: Cache the result for subsequent requests
        result = {
            "outputs": outputs,
            "total_windows": total_windows,
        }
        self._window_tree_cache = result
        self._window_tree_cache_time = time.time()

        return {**result, "cached": False}

    def _tracked_window_runtime_fields(self, tracked_window) -> Dict[str, Any]:
        """Serialize daemon-tracked window runtime fields for tree/snapshot output."""
        return {
            "project": str(getattr(tracked_window, "project", "") or ""),
            "scope": str(getattr(tracked_window, "scope", "") or ""),
            "execution_mode": str(getattr(tracked_window, "execution_mode", "") or ""),
            "connection_key": str(getattr(tracked_window, "connection_key", "") or ""),
            "context_key": str(getattr(tracked_window, "context_key", "") or ""),
            "remote_enabled": "true" if bool(getattr(tracked_window, "remote_enabled", False)) else "",
            "remote_user": str(getattr(tracked_window, "remote_user", "") or ""),
            "remote_host": str(getattr(tracked_window, "remote_host", "") or ""),
            "remote_port": str(getattr(tracked_window, "remote_port", "") or ""),
            "remote_dir": str(getattr(tracked_window, "remote_dir", "") or ""),
            "remote_session_name": str(getattr(tracked_window, "remote_session_name", "") or ""),
            "terminal_anchor_id": str(getattr(tracked_window, "terminal_anchor_id", "") or ""),
            "app_key": str(getattr(tracked_window, "app_identifier", "") or ""),
            "app_name": str(getattr(tracked_window, "app_identifier", "") or ""),
            "binding_state": str(getattr(tracked_window, "binding_state", "") or ""),
            "last_workspace": str(getattr(tracked_window, "last_workspace", "") or ""),
            "last_output": str(getattr(tracked_window, "last_output", "") or ""),
            "last_visible": bool(getattr(tracked_window, "last_visible", True)),
        }

    def _workspace_number_from_label(self, workspace_name: str) -> int:
        """Parse a workspace label into a stable numeric ordering key."""
        workspace = str(workspace_name or "").strip()
        if workspace.lower() == "scratchpad":
            return -1
        match = re.match(r"^(\d+)", workspace)
        if match:
            return int(match.group(1))
        return 0

    def _project_outputs_from_tracked_windows(
        self,
        outputs: List[Dict[str, Any]],
        tracked_windows: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Project workspace windows from canonical tracked window state."""
        projected_outputs: List[Dict[str, Any]] = []
        output_index: Dict[str, Dict[str, Any]] = {}
        workspace_index: Dict[Tuple[str, str], Dict[str, Any]] = {}

        for raw_output in outputs:
            if not isinstance(raw_output, dict):
                continue
            output_name = str(raw_output.get("name") or "").strip()
            projected_output = {
                "name": output_name,
                "active": bool(raw_output.get("active", False)),
                "primary": bool(raw_output.get("primary", False)),
                "geometry": dict(raw_output.get("geometry", {}) or {}),
                "current_workspace": str(raw_output.get("current_workspace") or "").strip(),
                "workspaces": [],
            }
            for raw_workspace in list(raw_output.get("workspaces", []) or []):
                if not isinstance(raw_workspace, dict):
                    continue
                workspace_name = str(raw_workspace.get("name") or "").strip()
                projected_workspace = {
                    "number": int(raw_workspace.get("number") or self._workspace_number_from_label(workspace_name)),
                    "name": workspace_name,
                    "focused": bool(raw_workspace.get("focused", False)),
                    "visible": bool(raw_workspace.get("visible", False)),
                    "output": output_name,
                    "windows": [],
                }
                projected_output["workspaces"].append(projected_workspace)
                workspace_index[(output_name, workspace_name)] = projected_workspace
            projected_outputs.append(projected_output)
            output_index[output_name] = projected_output

        fallback_output_name = str(projected_outputs[0].get("name") or "").strip() if projected_outputs else ""

        for tracked_window in tracked_windows:
            if not isinstance(tracked_window, dict):
                continue
            binding_state = str(tracked_window.get("binding_state") or "").strip() or "bound_workspace"
            workspace_name = str(
                tracked_window.get("workspace")
                or tracked_window.get("last_workspace")
                or ""
            ).strip()
            output_name = str(
                tracked_window.get("output")
                or tracked_window.get("last_output")
                or fallback_output_name
            ).strip()
            if not workspace_name or not output_name:
                continue

            projected_output = output_index.get(output_name)
            if projected_output is None:
                projected_output = {
                    "name": output_name,
                    "active": True,
                    "primary": False,
                    "geometry": {},
                    "current_workspace": "",
                    "workspaces": [],
                }
                projected_outputs.append(projected_output)
                output_index[output_name] = projected_output

            workspace_key = (output_name, workspace_name)
            projected_workspace = workspace_index.get(workspace_key)
            if projected_workspace is None:
                projected_workspace = {
                    "number": self._workspace_number_from_label(workspace_name),
                    "name": workspace_name,
                    "focused": False,
                    "visible": False,
                    "output": output_name,
                    "windows": [],
                }
                projected_output["workspaces"].append(projected_workspace)
                workspace_index[workspace_key] = projected_workspace

            projected_workspace["windows"].append({
                "id": int(tracked_window.get("window_id") or tracked_window.get("id") or 0),
                "title": str(tracked_window.get("title") or "(untitled)"),
                "app_key": str(tracked_window.get("app_key") or ""),
                "app_name": str(tracked_window.get("app_name") or tracked_window.get("window_class") or "window"),
                "icon_path": str(tracked_window.get("icon_path") or "").strip(),
                "project": str(tracked_window.get("project") or "").strip(),
                "scope": str(tracked_window.get("scope") or "").strip(),
                "workspace": workspace_name,
                "output": output_name,
                "focused": bool(tracked_window.get("focused", False)),
                "hidden": binding_state == "scratchpad_hidden",
                "visible": binding_state != "scratchpad_hidden",
                "floating": bool(tracked_window.get("floating", False)),
                "execution_mode": str(tracked_window.get("execution_mode") or "").strip(),
                "connection_key": str(tracked_window.get("connection_key") or "").strip(),
                "context_key": str(tracked_window.get("context_key") or "").strip(),
                "binding_state": binding_state,
            })

        for projected_output in projected_outputs:
            workspaces = list(projected_output.get("workspaces", []) or [])
            workspaces.sort(
                key=lambda workspace: (
                    int(workspace.get("number") or self._workspace_number_from_label(str(workspace.get("name") or ""))),
                    str(workspace.get("name") or ""),
                )
            )
            projected_output["workspaces"] = workspaces

        return projected_outputs

    def _resolve_window_icon_path(
        self,
        *,
        app_key: Optional[str],
        app_id: Optional[str],
        window_class: Optional[str],
        window_instance: Optional[str] = None,
        allow_fallback: bool = True,
    ) -> str:
        """Resolve a window icon using the same app/PWA/desktop sources as the workspace bar."""
        try:
            icon_info = self.icon_resolver.lookup(
                app_key=app_key,
                app_id=app_id,
                window_class=window_class,
                window_instance=window_instance,
                allow_fallback=allow_fallback,
            )
        except Exception:
            logger.debug(
                "Icon lookup failed for app_key=%s app_id=%s class=%s instance=%s",
                app_key,
                app_id,
                window_class,
                window_instance,
                exc_info=True,
            )
            return ""
        return str(icon_info.get("icon") or "")

    def _find_workspace_container(self, tree, workspace_name: str):
        """Find workspace container in i3 tree by name.

        Args:
            tree: i3 tree root node
            workspace_name: Workspace name to find

        Returns:
            Workspace container node or None
        """
        def search(node):
            if node.type == "workspace" and node.name == workspace_name:
                return node
            for child in (node.nodes + node.floating_nodes):
                result = search(child)
                if result:
                    return result
            return None

        return search(tree)

    def _extract_windows_from_container(
        self,
        container,
        workspace_num: int,
        output_name: str,
        *,
        tracked_windows: Optional[Dict[int, Any]] = None,
        tracked_windows_by_con_id: Optional[Dict[int, Any]] = None,
    ) -> list:
        """Extract all windows from container recursively.

        Args:
            container: i3 container node
            workspace_num: Workspace number
            output_name: Output name

        Returns:
            List of window dicts with WindowState-compatible structure
        """
        windows = []
        tracked_windows = tracked_windows or {}
        tracked_windows_by_con_id = tracked_windows_by_con_id or {}

        def extract(node, depth=0):
            # Check if this is an actual window (has X11 window ID or Wayland app_id)
            # X11 windows have node.window > 0, Wayland windows have app_id
            is_x11_window = node.window and node.window > 0
            is_wayland_window = hasattr(node, 'app_id') and node.app_id and not node.window

            if is_x11_window or is_wayland_window:
                # Get project from marks (format: SCOPE:PROJECT:WINDOW_ID)
                project = None
                scope_from_mark = None
                for mark in node.marks:
                    if mark.startswith("scoped:") or mark.startswith("global:"):
                        # Feature 101: Use centralized mark parser
                        parsed = parse_mark(mark, node.id if hasattr(node, 'id') else node.window)
                        if parsed:
                            scope_from_mark = parsed.scope
                            project = parsed.project_name
                        break

                # Get window class (X11 uses window_class, Wayland uses app_id)
                window_class = node.window_class if hasattr(node, 'window_class') and node.window_class else (node.app_id if hasattr(node, 'app_id') else "")

                # Read I3PM_* environment for app_id and worktree metadata.
                # Read directly from the window process when available. Runtime
                # identity for managed windows comes from daemon state, not
                # parent-process traversal.
                env = {}
                if hasattr(node, 'pid') and node.pid:
                    try:
                        from .services.window_filter import read_process_environ
                        env = read_process_environ(node.pid)
                    except (FileNotFoundError, PermissionError) as e:
                        # Process may have exited or we don't have permission
                        logger.debug(f"Failed to read environ for window {node.id if hasattr(node,'id') else node.window} PID {node.pid}: {e}")
                    except Exception as e:
                        logger.error(f"Unexpected error reading environ for window {node.id if hasattr(node,'id') else node.window} PID {node.pid}: {e}", exc_info=True)

                # Fall back to environment project when marks are missing (common regression)
                if not project:
                    project = env.get("I3PM_PROJECT_NAME") or env.get("I3PM_PARENT_PROJECT")
                project = project or ""

                # Determine classification from daemon state
                classification = scope_from_mark or env.get("I3PM_SCOPE") or "global"
                hidden = False
                if window_class:
                    if project and window_class in self.state_manager.state.scoped_classes:
                        classification = "scoped"
                    # Check if window is hidden (not on visible workspace or project mismatch)
                    active_project = self.state_manager.state.active_project
                    if classification == "scoped" and active_project and project != active_project:
                        hidden = True

                # Format workspace as string (CLI expects "1" or "1:name")
                workspace_name = container.name if container.type == "workspace" else ""
                workspace_str = workspace_name if workspace_name else str(workspace_num)

                # Use node.id for Wayland windows (unique identifier), node.window for X11
                window_id = node.window if is_x11_window else node.id
                tracked_window = tracked_windows.get(int(window_id)) or tracked_windows_by_con_id.get(int(node.id))

                # Extract app_id and worktree metadata from already-read env
                app_id = env.get("I3PM_APP_ID")
                app_key = env.get("I3PM_APP_NAME") or ""
                if app_id:
                    logger.debug(f"Found I3PM_APP_ID for window {window_id} PID {node.pid}: {app_id}")
                elif env:
                    i3pm_keys = [k for k in env.keys() if k.startswith('I3PM')]
                    logger.debug(f"No I3PM_APP_ID for window {window_id} PID {node.pid}, I3PM keys: {i3pm_keys}")

                window_data = {
                    "id": window_id,
                    "pid": node.pid if hasattr(node, 'pid') else None,
                    "app_id": app_id,  # I3PM_APP_ID from process environment
                    "app_key": app_key,
                    "class": window_class,
                    "icon_path": "",
                    "instance": node.window_instance or "",
                    "title": node.name or "",
                    "workspace": workspace_str,
                    "output": output_name,
                    "project": project,
                    "scope": classification,
                    # Worktree metadata (Feature 079)
                    "is_worktree": env.get("I3PM_IS_WORKTREE", "false").lower() == "true",
                    "parent_project": env.get("I3PM_PARENT_PROJECT") or None,
                    "branch_type": env.get("I3PM_BRANCH_TYPE") or None,
                    "branch_number": env.get("I3PM_BRANCH_NUMBER") or None,
                    "full_branch_name": env.get("I3PM_FULL_BRANCH_NAME") or None,
                    "marks": node.marks,
                    "floating": node.floating == "user_on",
                    "focused": node.focused,
                    "hidden": hidden,
                    "fullscreen": node.fullscreen_mode > 0,
                    "geometry": {
                        "x": node.rect.x,
                        "y": node.rect.y,
                        "width": node.rect.width,
                        "height": node.rect.height,
                    },
                    # Canonical execution identity metadata for monitor-side
                    # local/ssh split grouping without extra /proc scans.
                    "execution_mode": env.get("I3PM_EXECUTION_MODE", ""),
                    "connection_key": env.get("I3PM_CONNECTION_KEY", ""),
                    "context_key": env.get("I3PM_CONTEXT_KEY", ""),
                    "remote_enabled": env.get("I3PM_REMOTE_ENABLED", ""),
                    "remote_user": env.get("I3PM_REMOTE_USER", ""),
                    "remote_host": env.get("I3PM_REMOTE_HOST", ""),
                    "remote_port": env.get("I3PM_REMOTE_PORT", ""),
                    "remote_dir": env.get("I3PM_REMOTE_DIR", ""),
                    "remote_session_name": env.get("I3PM_REMOTE_SESSION_NAME", ""),
                }
                if tracked_window:
                    window_data.update(self._tracked_window_runtime_fields(tracked_window))
                    if not window_data["project"]:
                        window_data["project"] = str(getattr(tracked_window, "project", "") or "")
                    if not window_data["scope"]:
                        window_data["scope"] = str(getattr(tracked_window, "scope", "") or "")
                if not window_data.get("app_key"):
                    window_data["app_key"] = str(window_data.get("app_name") or "")
                window_data["icon_path"] = self._resolve_window_icon_path(
                    app_key=str(window_data.get("app_key") or ""),
                    app_id=app_id,
                    window_class=window_class,
                    window_instance=node.window_instance or "",
                    allow_fallback=not bool(app_key),
                )
                windows.append(window_data)

            # Recurse into child nodes
            for child in (node.nodes + node.floating_nodes):
                extract(child, depth + 1)

        extract(container)
        return windows

    # ========================================================================
    # Feature 030: Production Readiness Methods (T016)
    # ========================================================================

    async def _daemon_status(self) -> Dict[str, Any]:
        """
        Get comprehensive daemon health and status

        Implements daemon.status JSON-RPC method from daemon-ipc.json

        Feature 030 (T029): Includes recovery status and i3 reconnection stats
        """
        start_time = time.perf_counter()

        try:
            return await self.daemon_status_service.daemon_status()

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_status",
                duration_ms=duration_ms,
            )

    async def _daemon_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Query recent events from circular buffer with filtering

        Implements daemon.events JSON-RPC method from daemon-ipc.json

        Args:
            params: Query parameters
                - source: Filter by event source (i3, systemd, proc, all)
                - event_type: Filter by event type
                - limit: Maximum events to return (default: 20, max: 500)
                - since: ISO timestamp to filter events after
                - correlate: Include correlation analysis
        """
        start_time = time.perf_counter()

        try:
            if not self.event_buffer:
                return {
                    "events": [],
                    "total_events": 0,
                    "buffer_size": 0,
                }

            # Extract parameters
            source_filter = params.get("source", "all")
            event_type_filter = params.get("event_type")
            limit = min(params.get("limit", 20), 500)
            since_str = params.get("since")
            include_correlation = params.get("correlate", False)

            # Parse since timestamp
            since_dt = None
            if since_str:
                try:
                    since_dt = datetime.fromisoformat(since_str.replace('Z', '+00:00'))
                except ValueError:
                    logger.warning(f"Invalid 'since' timestamp: {since_str}")

            # Get events from buffer
            all_events = self.event_buffer.get_events(limit=limit)

            # Apply filters
            filtered_events = []
            for event in all_events:
                # Filter by source
                if source_filter != "all" and event.source != source_filter:
                    continue

                # Filter by event type
                if event_type_filter and event.event_type != event_type_filter:
                    continue

                # Filter by timestamp
                if since_dt and event.timestamp < since_dt:
                    continue

                filtered_events.append(event)

            # Convert to response format
            events_data = []
            for event in filtered_events:
                event_dict = {
                    "event_id": str(event.event_id),
                    "source": event.source,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "data": event.to_dict(),  # Include all event data
                }

                # Add correlation if requested
                if include_correlation and event.correlation_id:
                    event_dict["correlation_id"] = str(event.correlation_id)
                    event_dict["confidence_score"] = event.confidence_score

                events_data.append(event_dict)

            result = {
                "events": events_data,
                "total_events": len(self.event_buffer.buffer),
                "buffer_size": self.event_buffer.max_size,
            }

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_events",
                result_count=len(result.get("events", [])),
                params=params,
                duration_ms=duration_ms,
            )

    async def _daemon_diagnose(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate comprehensive diagnostic snapshot

        Implements daemon.diagnose JSON-RPC method from daemon-ipc.json

        Args:
            params: Diagnostic options
                - include_events: Include recent event history (default: true)
                - include_i3_tree: Include complete i3 window tree (default: true)
                - include_config: Include current configuration (default: true)
        """
        from .monitoring.diagnostics import generate_diagnostic_snapshot

        start_time = time.perf_counter()

        try:
            # Extract parameters
            include_events = params.get("include_events", True)
            include_i3_tree = params.get("include_i3_tree", True)
            include_config = params.get("include_config", True)

            # Generate snapshot
            snapshot = await generate_diagnostic_snapshot(
                include_i3_tree=include_i3_tree,
                include_events=include_events,
                event_limit=100,
                sanitize=True,
            )

            # Get daemon status
            daemon_status = await self._daemon_status()

            # Build diagnostic result
            result = {
                "timestamp": snapshot.timestamp,
                "daemon_status": daemon_status,
            }

            if include_events:
                result["events"] = snapshot.recent_events

            if include_i3_tree:
                result["i3_tree"] = snapshot.i3_tree
                result["i3_outputs"] = snapshot.i3_outputs
                result["i3_workspaces"] = snapshot.i3_workspaces

            if include_config:
                result["projects"] = snapshot.projects
                result["classification_rules"] = snapshot.classification_rules

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_diagnose",
                params=params,
                duration_ms=duration_ms,
            )

    async def _daemon_apps(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get applications currently loaded in daemon's memory

        This method reads the application registry file that the daemon loaded
        at startup, providing visibility into what apps the daemon knows about.

        Implements daemon.apps JSON-RPC method

        Returns:
            Dict containing:
                - applications: List of application entries
                - version: Registry version
                - count: Number of applications
                - registry_path: Path to registry file
        """
        start_time = time.perf_counter()

        try:
            registry_path = Path.home() / ".config" / "i3" / "application-registry.json"

            if not registry_path.exists():
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Application registry not found",
                    "data": {"reason": "registry_file_not_found", "path": str(registry_path)}
                }))

            with open(registry_path, "r") as f:
                registry = json.load(f)

            applications = registry.get("applications", [])
            version = registry.get("version", "unknown")

            # Filter by name if requested
            name_filter = params.get("name")
            if name_filter:
                applications = [app for app in applications if app.get("name") == name_filter]

            # Filter by scope if requested
            scope_filter = params.get("scope")
            if scope_filter:
                applications = [app for app in applications if app.get("scope") == scope_filter]

            # Filter by workspace if requested
            workspace_filter = params.get("workspace")
            if workspace_filter:
                applications = [app for app in applications if app.get("preferred_workspace") == workspace_filter]

            return {
                "applications": applications,
                "version": version,
                "count": len(applications),
                "registry_path": str(registry_path),
            }

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::daemon_apps",
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_save(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Capture and save current workspace layout.

        Feature 074: Session Management - Task T059
        Implements layout.capture JSON-RPC method from contracts/ipc-api.md

        Args:
            params: Save parameters
                - project: Project name (required, lowercase alphanumeric with hyphens)
                - name: Layout name (required, lowercase alphanumeric with hyphens)

        Returns:
            {
                "success": bool,
                "layout_path": str,
                "workspace_count": int,
                "window_count": int,
                "focused_workspace": int
            }

        Raises:
            ValueError: If required params missing or invalid
            RuntimeError: If capture or save fails
        """
        start_time = time.perf_counter()

        try:
            project = params.get("project")
            name = params.get("name")

            # Validate required parameters
            if not project:
                raise ValueError("project parameter is required")
            if not name:
                raise ValueError("name parameter is required")

            # Feature 074: Use new capture system with terminal cwd tracking (T036-T037)
            from .layout.capture import capture_layout
            from .layout.persistence import save_layout

            # Capture current layout
            snapshot = await capture_layout(
                i3_connection=self.i3_connection,
                name=name,
                project=project
            )

            # Save to file
            layout_path = save_layout(snapshot)

            result = {
                "success": True,
                "layout_path": str(layout_path),
                "workspace_count": len(snapshot.workspace_layouts),
                "window_count": snapshot.metadata.get("total_windows", 0),
                "focused_workspace": snapshot.focused_workspace or 1
            }

            logger.info(
                f"Layout captured: {project}/{name} - "
                f"{result['workspace_count']} workspaces, "
                f"{result['window_count']} windows → {layout_path}"
            )

            return result

        except ValueError as e:
            # Invalid params error code
            raise ValueError(str(e))
        except Exception as e:
            logger.error(f"Layout capture failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout capture failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::capture",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_restore(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Restore workspace layout from snapshot.

        Feature 074: Session Management - Task T058
        Implements layout.restore JSON-RPC method from contracts/ipc-api.md
        Uses mark-based correlation for Sway compatibility (US3)

        Args:
            params: Restore parameters
                - project: Project name (required)
                - name: Layout name (required)
                - timeout: Max correlation timeout in seconds (optional, default: 30.0)

        Returns:
            {
                "success": bool,
                "windows_launched": int,
                "windows_matched": int,
                "windows_timeout": int,
                "windows_failed": int,
                "elapsed_seconds": float,
                "correlations": [
                    {
                        "restoration_mark": str,
                        "window_class": str,
                        "status": str,
                        "window_id": int,
                        "correlation_time": float
                    }
                ]
            }

        Raises:
            ValueError: If required params missing
            RuntimeError: If layout not found or restoration fails
        """
        start_time = time.perf_counter()

        try:
            project = params.get("project")
            name = params.get("name")
            timeout = params.get("timeout", 30.0)

            # Validate required parameters
            if not project:
                raise ValueError("project parameter is required")
            if not name:
                raise ValueError("name parameter is required")

            # Feature 075: Use new app-registry-based idempotent restore (T029)
            from .layout.restore import restore_workflow
            from .layout.persistence import load_layout

            # Load layout
            layout = load_layout(name, project)
            if not layout:
                raise FileNotFoundError(f"Layout '{name}' not found for project '{project}'")

            # Restore layout using idempotent workflow
            restore_result = await restore_workflow(
                layout=layout,
                project=project,
                i3_connection=self.i3_connection,
            )

            # Convert RestoreResult to IPC response format
            result = {
                "success": restore_result.status == "success",
                "status": restore_result.status,  # "success", "partial", or "failed"
                "apps_already_running": restore_result.apps_already_running,
                "apps_launched": restore_result.apps_launched,
                "apps_failed": restore_result.apps_failed,
                "elapsed_seconds": restore_result.elapsed_seconds,
                "total_apps": restore_result.total_apps,
                "success_rate": restore_result.success_rate,
                # Legacy fields for backward compatibility (deprecated)
                "windows_launched": len(restore_result.apps_launched),
                "windows_matched": 0,  # Not used in MVP
                "windows_timeout": 0,  # No timeouts in new approach
                "windows_failed": len(restore_result.apps_failed),
            }

            logger.info(
                f"Layout restored: {project}/{name} - "
                f"status={result['status']}, "
                f"{len(result['apps_already_running'])} already running, "
                f"{len(result['apps_launched'])} launched, "
                f"{len(result['apps_failed'])} failed "
                f"({result['elapsed_seconds']:.1f}s, {result['success_rate']:.1f}% success)"
            )

            return result

        except FileNotFoundError as e:
            # Layout not found
            raise RuntimeError(
                f"Layout not found: {params.get('name')} for project {params.get('project')}"
            )
        except ValueError as e:
            # Invalid params
            raise ValueError(str(e))
        except Exception as e:
            logger.error(f"Layout restore failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout restore failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::restore",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        List saved layout snapshots.

        Feature 058: Python Backend Consolidation - User Story 2
        Feature 074: Session Management - Task T084 (include_auto_saves parameter)
        Implements layout_list JSON-RPC method from contracts/layout-api.json

        Args:
            params: List parameters
                - project_name: Project name (required)
                - include_auto_saves: Include auto-saved layouts (optional, default: True)

        Returns:
            {
                "project": str,
                "layouts": [
                    {
                        "layout_name": str,
                        "timestamp": str (ISO 8601),
                        "windows_count": int,
                        "file_path": str,
                        "is_auto_save": bool
                    }
                ],
                "total_count": int
            }

        Raises:
            ValueError: If project_name is missing
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            include_auto_saves = params.get("include_auto_saves", True)

            if not project_name:
                raise ValueError("project_name parameter is required")

            from .layout.persistence import list_layouts

            # Persisted layout metadata lives on disk and does not require i3 IPC.
            all_layouts = list_layouts(project_name)
            layouts = [
                {
                    "layout_name": layout.get("name", ""),
                    "timestamp": layout.get("created_at"),
                    "windows_count": layout.get("total_windows", 0),
                    "file_path": layout.get("file_path", ""),
                }
                for layout in all_layouts
            ]

            # Feature 074: T084 - Filter auto-saves if requested
            if not include_auto_saves:
                layouts = [layout for layout in layouts
                          if not layout.get("layout_name", "").startswith("auto-")]

            # Add is_auto_save flag to each layout (Feature 074: T084)
            for layout in layouts:
                layout["is_auto_save"] = layout.get("layout_name", "").startswith("auto-")

            result = {
                "project": project_name,
                "layouts": layouts,
                "total_count": len(layouts)  # Feature 074: T084
            }

            logger.info(f"Listed layouts: {len(layouts)} found for project {project_name} (include_auto_saves={include_auto_saves})")

            return result

        except ValueError as e:
            raise ValueError(str(e))
        except Exception as e:
            logger.error(f"Layout list failed: {e}", exc_info=True)
            raise RuntimeError(f"Layout list failed: {e}")
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::layout_list",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Delete a saved layout snapshot.

        Feature 058: Python Backend Consolidation - User Story 2
        Implements layout_delete JSON-RPC method from contracts/layout-api.json

        Args:
            params: Delete parameters
                - project_name: Project name (required)
                - layout_name: Layout name (required)

        Returns:
            {
                "deleted": bool,
                "layout_name": str
            }

        Raises:
            ValueError: If required parameters are missing
            LayoutError: If layout not found
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("project_name")
            layout_name = params.get("layout_name")

            if not project_name or not layout_name:
                raise ValueError("project_name and layout_name parameters are required")

            from .layout.persistence import delete_layout
            deleted = delete_layout(layout_name, project_name)

            if not deleted:
                raise RuntimeError(
                    f"Layout not found: {layout_name} for project {project_name}"
                )

            result = {
                "deleted": True,
                "layout_name": layout_name
            }

            logger.info(f"Deleted layout: {project_name}/{layout_name}")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="layout::delete",
                project_name=params.get("project_name"),
                params=params,
                duration_ms=duration_ms,
            )

    async def _layout_info(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get detailed information about a saved layout

        Implements layout.info JSON-RPC method
        Feature 030: Task T048 (CLI info command)

        Args:
            params: Info parameters
                - name: Layout name (required)
                - project: Project name (default: "global")

        Returns:
            Dictionary with detailed layout information
        """
        start_time = time.perf_counter()

        try:
            name = params.get("name")
            project = params.get("project", "global")

            if not name:
                raise ValueError("'name' parameter is required")

            # Import layout module
            from .layout import load_layout

            # Load layout
            snapshot = load_layout(name=name, project=project)

            if not snapshot:
                raise ValueError(f"Layout not found: {name} (project: {project})")

            # Build detailed info
            workspaces = []
            for ws_layout in snapshot.workspace_layouts:
                ws_info = {
                    "workspace_num": ws_layout.workspace_num,
                    "workspace_name": ws_layout.workspace_name if ws_layout.workspace_name else "",
                    "output": ws_layout.output,
                    "window_count": len(ws_layout.windows),
                }
                workspaces.append(ws_info)

            monitors = []
            for monitor in snapshot.monitor_config.monitors:
                mon_info = {
                    "name": monitor.name,
                    "width": monitor.resolution.width if monitor.resolution else 0,
                    "height": monitor.resolution.height if monitor.resolution else 0,
                    "primary": monitor.primary,
                }
                monitors.append(mon_info)

            result = {
                "name": snapshot.name,
                "project": snapshot.project,
                "created_at": snapshot.created_at.isoformat(),
                "total_windows": snapshot.metadata.get("total_windows", 0),
                "total_workspaces": snapshot.metadata.get("total_workspaces", 0),
                "total_monitors": snapshot.metadata.get("total_monitors", 0),
                "workspaces": workspaces,
                "monitors": monitors,
            }

            logger.info(f"Retrieved layout info: {project}/{name}")

            return result

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::layout_info",
                project_name=params.get("project"),
                params=params,
                duration_ms=duration_ms,
            )

    # ======================================================================
    # Feature 033: Declarative Workspace-to-Monitor Mapping Methods
    # ======================================================================

    async def _get_monitor_config(self) -> Dict[str, Any]:
        """Get current workspace-to-monitor configuration.

        Feature 033: T021

        Returns:
            Configuration dict from workspace-monitor-mapping.json
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager

            config_manager = MonitorConfigManager()
            config = config_manager.load_config()

            # Convert Pydantic model to dict for JSON serialization
            return config.model_dump()

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitor config: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitor_config",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _validate_monitor_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Validate workspace-to-monitor configuration file.

        Feature 033: T022

        Args:
            params: Optional params dict with:
                - config_path: str (optional) - Path to config file

        Returns:
            ValidationResult dict with valid, issues, and config fields
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from pathlib import Path
            from .monitor_config_manager import MonitorConfigManager

            # Get config path from params or use default
            config_path_str = params.get("config_path")
            if config_path_str:
                config_path = Path(config_path_str)
            else:
                config_path = MonitorConfigManager.DEFAULT_CONFIG_PATH

            # Validate configuration
            validation_result = MonitorConfigManager.validate_config_file(config_path)

            # Convert Pydantic models to dicts
            result_dict = {
                "valid": validation_result.valid,
                "issues": [issue.model_dump() for issue in validation_result.issues],
                "config": validation_result.config.model_dump() if validation_result.config else None,
            }

            return result_dict

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error validating monitor config: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::validate_monitor",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _reload_monitor_config(self) -> Dict[str, Any]:
        """Reload workspace-to-monitor configuration from disk.

        Feature 033: T023

        Returns:
            Dict with success status and change summary
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager

            config_manager = MonitorConfigManager()

            # Force reload from disk
            new_config = config_manager.load_config(force_reload=True)

            # Get summary of changes (simplified - just report success)
            changes = [
                f"Configuration reloaded from {config_manager.config_path}",
                f"Distribution rules updated for {len(new_config.distribution.model_dump())} monitor configurations",
                f"Workspace preferences: {len(new_config.workspace_preferences)} entries",
            ]

            logger.info(f"Monitor configuration reloaded: {config_manager.config_path}")

            return {
                "success": True,
                "changes": changes,
                "error": None,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error reloading monitor config: {e}")
            return {
                "success": False,
                "changes": [],
                "error": str(e),
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="config::reload_monitor",
                config_type="workspace_monitor_mapping",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _reassign_workspaces(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Migrate workspaces away from unavailable outputs.

        Preserve current workspace placement whenever the workspace is already
        on an enabled output. This keeps runtime organization Sway-native while
        still rescuing workspaces from outputs that are no longer usable.

        Args:
            params: Optional params dict with:
                - dry_run: bool (default False) - Preview without applying

        Returns:
            Dict with success status, assignments_made count, and errors list
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            dry_run = params.get("dry_run", False)

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            outputs = await self.i3_connection.get_outputs()
            from .output_state_manager import load_output_states
            states = load_output_states()
            enabled_outputs = [
                output.name for output in outputs
                if output.active and states.is_output_enabled(output.name)
            ]
            disabled_outputs = [
                output.name for output in outputs
                if output.active and not states.is_output_enabled(output.name)
            ]

            if not enabled_outputs:
                return {
                    "success": False,
                    "assignments_made": 0,
                    "errors": ["No enabled outputs detected"],
                }

            assignments_made = 0
            if not dry_run and disabled_outputs and self.monitor_profile_service:
                before = await self._sway_get_workspaces()
                before_by_name = {workspace.name: workspace.output for workspace in before}
                await self.monitor_profile_service.migrate_workspaces_from_disabled_outputs(
                    self.i3_connection.conn,
                    disabled_outputs,
                    fallback_output=enabled_outputs[0],
                )
                after = await self._sway_get_workspaces()
                assignments_made = sum(
                    1
                    for workspace in after
                    if before_by_name.get(workspace.name) not in (None, workspace.output)
                )

            return {
                "success": True,
                "assignments_made": assignments_made,
                "errors": [],
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error reassigning workspaces: {e}")
            return {
                "success": False,
                "assignments_made": 0,
                "errors": [str(e)],
            }
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="workspace::reassign",
                params=params,
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_monitors(self) -> list[Dict[str, Any]]:
        """Get current monitor/output configurations with roles.

        Feature 033: T032 (User Story 2)

        Returns:
            List of MonitorConfig dicts with name, active, primary, role, rect, current_workspace
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager
            from .workspace_manager import get_monitor_configs
            from .models import MonitorConfig as PydanticMonitorConfig, OutputRect, MonitorRole

            # Get i3 connection
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            i3 = self.i3_connection.conn

            # Get monitor configurations with assigned roles
            config_manager = MonitorConfigManager()
            monitors_dataclass = await get_monitor_configs(i3, config_manager)

            # Convert dataclass instances to Pydantic models for JSON-RPC
            monitors_pydantic = []
            for monitor in monitors_dataclass:
                pydantic_monitor = PydanticMonitorConfig(
                    name=monitor.name,
                    active=monitor.active,
                    primary=monitor.primary,
                    role=MonitorRole(monitor.role) if monitor.role else None,
                    rect=OutputRect(**monitor.rect),
                    current_workspace=None,  # TODO: Query from i3
                )
                monitors_pydantic.append(pydantic_monitor)

            # Convert Pydantic models to dicts for JSON serialization
            return [monitor.model_dump() for monitor in monitors_pydantic]

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitors: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitors",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_workspaces(self) -> list[Dict[str, Any]]:
        """Get current workspace assignments with target roles.

        Feature 033: T033 (User Story 2)

        Returns:
            List of WorkspaceAssignment dicts with workspace_num, output_name, target_role, target_output, source, visible
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .monitor_config_manager import MonitorConfigManager
            from .workspace_manager import get_monitor_configs
            from .models import WorkspaceAssignment, MonitorRole

            # Get i3 connection
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            i3 = self.i3_connection.conn

            # Get monitor configurations with assigned roles
            config_manager = MonitorConfigManager()
            monitors = await get_monitor_configs(i3, config_manager)

            # Build role_map: role -> output_name
            role_map = {monitor.role: monitor.name for monitor in monitors if monitor.role}

            # Get workspace distribution for current monitor count
            distribution = config_manager.get_workspace_distribution(len(monitors))

            # Query i3 for actual workspace assignments
            i3_workspaces = await i3.get_workspaces()

            # Build workspace assignments
            assignments = []
            for ws in i3_workspaces:
                # Determine target role for this workspace
                target_role = None
                target_output = None
                source = "runtime"

                # Check workspace preferences first
                config = config_manager.load_config()
                if ws.num in config.workspace_preferences:
                    target_role = config.workspace_preferences[ws.num]
                    target_output = role_map.get(target_role)
                    source = "explicit"
                else:
                    # Check distribution rules
                    for role, ws_nums in distribution.items():
                        if ws.num in ws_nums:
                            target_role = role
                            target_output = role_map.get(role)
                            source = "default"
                            break

                assignment = WorkspaceAssignment(
                    workspace_num=ws.num,
                    output_name=ws.output,
                    target_role=target_role,
                    target_output=target_output,
                    source=source,
                    visible=ws.visible,
                    window_count=0,  # TODO: Query window count from i3 tree
                )
                assignments.append(assignment)

            # Convert to dicts
            return [assignment.model_dump() for assignment in assignments]

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting workspaces: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::workspaces",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_system_state(self) -> Dict[str, Any]:
        """Get complete monitor system state.

        Feature 033: T034 (User Story 2)

        Combines monitors and workspaces into unified system state.

        Returns:
            MonitorSystemState dict with monitors, workspaces, active_monitor_count, primary_output, last_updated
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            from .models import MonitorSystemState

            # Get monitors and workspaces
            monitors = await self._get_monitors()
            workspaces = await self._get_workspaces()

            # Calculate derived fields
            active_monitor_count = len([m for m in monitors if m["active"]])
            primary_output = next((m["name"] for m in monitors if m["primary"]), None)

            # Build system state
            state = MonitorSystemState(
                monitors=[m for m in monitors],  # Already dicts
                workspaces=[ws for ws in workspaces],  # Already dicts
                active_monitor_count=active_monitor_count,
                primary_output=primary_output,
                last_updated=time.time(),
            )

            return state.model_dump()

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting system state: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::system_state",
                duration_ms=duration_ms,
                error=error_msg,
            )

    # Feature 037: Window filtering methods

    async def _hide_windows(
        self,
        params: Dict[str, Any],
        correlation_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Hide windows for a project (move to scratchpad).

        Args:
            params: {
                "project_name": str  # Project whose windows to hide
            }
            correlation_id: Feature 102 - UUID for causality chain tracking

        Returns:
            {
                "windows_hidden": int,
                "errors": List[str],
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project_name = params.get("project_name")
            if not project_name:
                raise ValueError("project_name parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get i3 tree and find all visible windows for project
            tree = await self.i3_connection.get_tree()
            window_ids_to_hide = []
            # Feature 102: Collect window info for visibility events
            windows_info: List[Dict[str, Any]] = []

            async def collect_project_windows(con):
                # Feature 046: Check for windows using container ID (works for both X11 and Wayland)
                # For Wayland: con.window is None, but con.id exists
                # For X11: both con.window and con.id exist
                if hasattr(con, 'id') and (con.window is not None or (hasattr(con, 'app_id') and con.app_id)):
                    # Feature 103: Use unified mark format SCOPE:APP:PROJECT:WINDOW_ID
                    # Only hide windows with scope="scoped" matching the project
                    # Skip scratchpad-terminal (managed by ScratchpadManager)

                    # DEBUG: Log all windows with marks
                    if con.marks:
                        logger.debug(
                            f"[Feature 103] Scanning window {con.id} for hiding: "
                            f"marks={con.marks}, "
                            f"app_id={getattr(con, 'app_id', None)}, "
                            f"name={getattr(con, 'name', '')[:30]}"
                        )

                    # Feature 103: Parse unified marks
                    from .worktree_utils import parse_mark
                    for mark in con.marks:
                        parsed = parse_mark(mark, con.id)
                        if not parsed:
                            continue

                        # Only hide scoped windows matching this project
                        if parsed.scope == "scoped" and parsed.project_name == project_name:
                            # Feature 103: Skip scratchpad terminals (managed by ScratchpadManager)
                            if parsed.app_name == "scratchpad-terminal":
                                logger.debug(
                                    f"[Feature 103] Skipping scratchpad terminal {con.id} "
                                    f"(managed by ScratchpadManager)"
                                )
                                continue

                            logger.info(
                                f"[Feature 103] Will hide scoped window {con.id} "
                                f"(app: {parsed.app_name}, project: {project_name})"
                            )
                            window_ids_to_hide.append(con.id)
                            # Feature 102: Store window info for visibility event
                            windows_info.append({
                                "window_id": con.id,
                                "window_class": getattr(con, 'app_id', None) or getattr(con, 'window_class', None),
                                "window_title": getattr(con, 'name', None),
                                "app_name": parsed.app_name,
                            })
                            break  # Found matching project mark

                for child in con.nodes:
                    await collect_project_windows(child)
                for child in con.floating_nodes:
                    await collect_project_windows(child)

            await collect_project_windows(tree)

            # Hide windows in batch
            hidden_count, errors = await window_filtering.hide_windows_batch(
                self.i3_connection.conn,
                window_ids_to_hide,
                self.workspace_tracker,
            )

            # Feature 102: Log visibility::hidden events for each hidden window
            if correlation_id:
                for win_info in windows_info:
                    await self._log_i3pm_event(
                        "visibility::hidden",
                        window_id=win_info["window_id"],
                        window_class=win_info["window_class"],
                        window_title=win_info["window_title"],
                        project_name=project_name,
                        correlation_id=correlation_id,
                        causality_depth=1,  # Child of project::switch
                    )

            logger.info(
                f"Hidden {hidden_count} windows for project '{project_name}' "
                f"({len(errors)} errors)"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_hidden": hidden_count,
                "errors": errors,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error hiding windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::hide_windows",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _restore_windows(
        self,
        params: Dict[str, Any],
        correlation_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Restore windows for a project (from scratchpad).

        Args:
            params: {
                "project_name": str,  # Project whose windows to restore
                "workspace": int | None,  # Explicit restore workspace override
                "dry_run": bool = False,  # Validate restore targets without restoring
            }
            correlation_id: Feature 102 - UUID for causality chain tracking

        Returns:
            {
                "windows_restored": int,
                "errors": List[str],
                "blocked_windows": List[Dict[str, Any]],
                "requested_count": int,
                "dry_run": bool,
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            project_name = params.get("project_name")
            workspace_override = params.get("workspace")
            dry_run = bool(params.get("dry_run", False))

            if not project_name:
                raise ValueError("project_name parameter is required")

            if workspace_override is not None:
                try:
                    workspace_override = int(workspace_override)
                except (TypeError, ValueError) as exc:
                    raise ValueError("workspace parameter must be an integer") from exc

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get all scratchpad windows
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )

            # Feature 103: Find windows matching project using unified mark format
            # Format: SCOPE:APP:PROJECT:WINDOW_ID
            # Skip scratchpad-terminal (should stay hidden on project switch)
            window_ids_to_restore = []
            # Feature 102: Collect window info for visibility events
            windows_info: List[Dict[str, Any]] = []

            from .worktree_utils import parse_mark
            for window in scratchpad_windows:
                for mark in window.marks:
                    parsed = parse_mark(mark, window.id)
                    if not parsed:
                        continue

                    # Only restore windows matching this project
                    if parsed.project_name == project_name:
                        # Feature 103: Skip scratchpad terminals
                        # They should remain hidden on project switch (toggle to show manually)
                        if parsed.app_name == "scratchpad-terminal":
                            logger.debug(
                                f"[Feature 103] Skipping scratchpad terminal {window.id} "
                                f"(stays hidden on project switch)"
                            )
                            continue

                        window_ids_to_restore.append(window.id)
                        # Feature 102: Store window info for visibility event
                        windows_info.append({
                            "window_id": window.id,
                            "window_class": getattr(window, 'app_id', None) or getattr(window, 'window_class', None),
                            "window_title": getattr(window, 'name', None),
                            "app_name": parsed.app_name,
                        })
                        logger.debug(
                            f"[Feature 103] Will restore window {window.id} "
                            f"(app: {parsed.app_name}, project: {project_name})"
                        )
                        break  # Found matching project mark

            # Restore windows in batch
            restored_count, errors, blocked_windows = await window_filtering.restore_windows_batch(
                self.i3_connection.conn,
                window_ids_to_restore,
                self.workspace_tracker,
                workspace_override=workspace_override,
                dry_run=dry_run,
            )

            # Feature 102: Log visibility::shown events for each restored window
            if correlation_id and not dry_run:
                for win_info in windows_info:
                    if any(
                        int(blocked.get("window_id") or 0) == int(win_info["window_id"])
                        for blocked in blocked_windows
                    ):
                        continue
                    await self._log_i3pm_event(
                        "visibility::shown",
                        window_id=win_info["window_id"],
                        window_class=win_info["window_class"],
                        window_title=win_info["window_title"],
                        project_name=project_name,
                        correlation_id=correlation_id,
                        causality_depth=1,  # Child of project::switch
                    )

            logger.info(
                f"Restored {restored_count} windows for project '{project_name}' "
                f"({len(errors)} errors, {len(blocked_windows)} blocked, dry_run={dry_run})"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_restored": restored_count,
                "errors": errors,
                "blocked_windows": blocked_windows,
                "requested_count": len(window_ids_to_restore),
                "dry_run": dry_run,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error restoring windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::restore_windows",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _switch_with_filtering(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Switch projects with automatic window filtering.

        Args:
            params: {
                "old_project": str,  # Previous project (windows to hide)
                "new_project": str,  # New project (windows to restore)
            }

        Returns:
            {
                "windows_hidden": int,
                "windows_restored": int,
                "errors": List[str],
                "blocked_windows": List[Dict[str, Any]],
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        # Feature 102: Create correlation_id for causality tracking
        from .services.correlation_service import new_correlation, get_correlation_context, end_correlation
        correlation_id = new_correlation("project::switch")

        try:
            old_project = params.get("old_project", "")
            new_project = params.get("new_project")

            if not new_project:
                raise ValueError("new_project parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            all_errors = []
            blocked_windows: List[Dict[str, Any]] = []

            # Feature 102: Log project::switch event as root (depth 0)
            await self._log_i3pm_event(
                "project::switch",
                old_project=old_project or None,
                new_project=new_project,
                correlation_id=correlation_id,
                causality_depth=0,
            )

            # Phase 1: Hide windows from old project (if any)
            windows_hidden = 0
            if old_project:
                # Feature 062: Hide scratchpad terminal if visible
                if self.scratchpad_manager:
                    try:
                        terminal = self.scratchpad_manager.get_terminal(old_project)
                        if terminal:
                            state = await self.scratchpad_manager.get_terminal_state(old_project)
                            if state == "visible":
                                await self.scratchpad_manager.toggle_terminal(old_project)
                                logger.info(f"Hid scratchpad terminal for project '{old_project}' during project switch")
                                # Feature 102: Log scratchpad::move as child event
                                await self._log_i3pm_event(
                                    "scratchpad::move",
                                    project_name=old_project,
                                    correlation_id=correlation_id,
                                    causality_depth=1,
                                )
                    except Exception as e:
                        logger.warning(f"Failed to hide scratchpad terminal for project '{old_project}': {e}")
                        all_errors.append(f"Scratchpad hide failed: {e}")

                # Feature 102: Pass correlation_id to hide_windows for visibility events
                hide_result = await self._hide_windows(
                    {"project_name": old_project},
                    correlation_id=correlation_id,
                )
                windows_hidden = hide_result["windows_hidden"]
                all_errors.extend(hide_result.get("errors", []))

            # Phase 2: Restore windows for new project
            # Feature 102: Pass correlation_id to restore_windows for visibility events
            restore_result = await self._restore_windows(
                {
                    "project_name": new_project,
                },
                correlation_id=correlation_id,
            )
            windows_restored = restore_result["windows_restored"]
            all_errors.extend(restore_result.get("errors", []))
            blocked_windows = restore_result.get("blocked_windows", [])

            logger.info(
                f"Project switch filtering: {old_project or '(none)'} → {new_project} "
                f"(hidden {windows_hidden}, restored {windows_restored})"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "windows_hidden": windows_hidden,
                "windows_restored": windows_restored,
                "errors": all_errors,
                "blocked_windows": blocked_windows,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error in switch with filtering: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            # Feature 102: End correlation chain
            end_correlation()
            await self._log_ipc_event(
                event_type="project::switch_with_filtering",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_hidden_windows(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get all hidden windows (in scratchpad) grouped by project.

        Feature 037 US5 T036: Provides visibility into hidden windows for debugging
        and manual management. Queries scratchpad windows, reads I3PM_* variables,
        and groups by project name.

        Args:
            params: {
                "project_name": str (optional) # Filter by specific project
                "workspace": int (optional)    # Filter by tracked workspace
                "app_name": str (optional)     # Filter by app name
            }

        Returns:
            {
                "projects": {
                    "<project_name>": [
                        {
                            "window_id": int,
                            "app_name": str,
                            "window_class": str,
                            "window_title": str,
                            "tracked_workspace": int,
                            "floating": bool,
                            "last_seen": float
                        },
                        ...
                    ]
                },
                "total_hidden": int,
                "duration_ms": float
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            if not self.workspace_tracker:
                raise RuntimeError("workspace tracker not available")

            # Get filters
            filter_project = params.get("project_name")
            filter_workspace = params.get("workspace")
            filter_app = params.get("app_name")

            # Get all scratchpad windows
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )

            # Group windows by project
            projects_map = {}
            total_hidden = 0

            for window in scratchpad_windows:
                # Read I3PM_* environment variables
                i3pm_env = await window_filtering.get_window_i3pm_env(window.id, window.pid, window.window)
                project_name = i3pm_env.get("I3PM_PROJECT_NAME", "(unknown)")
                app_name = i3pm_env.get("I3PM_APP_NAME", "unknown")

                # Apply filters
                if filter_project and project_name != filter_project:
                    continue
                if filter_app and app_name != filter_app:
                    continue

                # Get tracking info
                tracking_info = self.workspace_tracker.windows.get(window.id, {})
                tracked_workspace = tracking_info.get("workspace_number", 0)

                if filter_workspace and tracked_workspace != filter_workspace:
                    continue

                # Build window info
                window_info = {
                    "window_id": window.id,
                    "app_name": app_name,
                    "window_class": window.window_class or "unknown",
                    "window_title": window.name or "(no title)",
                    "tracked_workspace": tracked_workspace,
                    "floating": tracking_info.get("floating", False),
                    "last_seen": tracking_info.get("last_seen", 0.0),
                }

                # Add to project group
                if project_name not in projects_map:
                    projects_map[project_name] = []
                projects_map[project_name].append(window_info)
                total_hidden += 1

            logger.debug(
                f"Found {total_hidden} hidden windows across {len(projects_map)} projects"
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            return {
                "projects": projects_map,
                "total_hidden": total_hidden,
                "duration_ms": duration_ms,
            }

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting hidden windows: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="windows::get_hidden",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _get_window_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get comprehensive state for a specific window.

        Feature 037 US5 T037: Provides detailed window inspection for debugging.
        Feature 041 T022: Includes launch correlation metadata if available.
        Shows all I3PM_* variables, tracking state, and i3 window properties.

        Args:
            params: {
                "window_id": int  # Window to inspect
            }

        Returns:
            {
                "window_id": int,
                "visible": bool,  # true if not in scratchpad
                "window_class": str,
                "window_title": str,
                "pid": int,
                "i3pm_env": {
                    "I3PM_PROJECT_NAME": str,
                    "I3PM_APP_NAME": str,
                    "I3PM_SCOPE": str,
                    ... # all I3PM_* variables
                },
                "tracking": {
                    "workspace_number": int,
                    "floating": bool,
                    "geometry": dict,  # Feature 038: x, y, width, height for floating windows
                    "original_scratchpad": bool,  # Feature 038: True if window was in scratchpad before filtering
                    "last_seen": float,
                    "project_name": str,
                    "app_name": str
                },
                "i3_state": {
                    "workspace": int,
                    "output": str,
                    "floating": str,
                    "focused": bool
                },
                "correlation": {  # Feature 041 T022, T040: Optional, only present if matched via launch
                    "matched_via_launch": bool,
                    "launch_id": str,
                    "confidence": float,  # 0.0 - 1.0
                    "confidence_level": str,  # EXACT, HIGH, MEDIUM, LOW
                    "signals_used": {
                        "class_match": bool,
                        "time_delta": float,  # seconds
                        "time_score": float,  # 0.0 - 0.3 time proximity bonus
                        "workspace_match": bool,  # T040: Workspace location match
                        "launch_workspace": int,  # T040: Expected workspace number
                        "window_workspace": int,  # T040: Actual workspace number
                        "workspace_bonus": float  # T040: 0.2 if match, 0.0 otherwise
                    }
                }
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            window_id = params.get("window_id")
            if window_id is None:
                raise ValueError("window_id parameter is required")

            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            # Find window in i3 tree
            tree = await self.i3_connection.get_tree()

            def find_window(con):
                if con.id == window_id:
                    return con
                for child in con.nodes:
                    result = find_window(child)
                    if result:
                        return result
                for child in con.floating_nodes:
                    result = find_window(child)
                    if result:
                        return result
                return None

            window = find_window(tree)
            if not window:
                raise ValueError(f"Window {window_id} not found")

            # Check if in scratchpad
            scratchpad_windows = await window_filtering.get_scratchpad_windows(
                self.i3_connection.conn
            )
            is_visible = window_id not in [w.id for w in scratchpad_windows]

            # Read I3PM_* environment variables
            i3pm_env = await window_filtering.get_window_i3pm_env(window_id, window.pid, window.window)

            # Get tracking info
            tracking_info = self.workspace_tracker.windows.get(window_id, {}) if self.workspace_tracker else {}

            # Feature 041 T022: Get correlation metadata from WindowInfo if available
            window_info = await self.state_manager.get_window(window_id)
            correlation_info = None
            if window_info and window_info.correlation_matched:
                correlation_info = {
                    "matched_via_launch": window_info.correlation_matched,
                    "launch_id": window_info.correlation_launch_id,
                    "confidence": window_info.correlation_confidence,
                    "confidence_level": window_info.correlation_confidence_level,
                    "signals_used": window_info.correlation_signals,
                }

            # Get i3 state
            workspace = window.workspace()
            i3_state = {
                "workspace": workspace.num if workspace else None,
                "output": workspace.ipc_data.get("output") if workspace else None,
                "floating": window.floating,
                "focused": window.focused,
            }

            logger.debug(f"Inspected window {window_id}: visible={is_visible}")

            duration_ms = (time.perf_counter() - start_time) * 1000

            # Feature 041 T022: Include correlation field in response
            result = {
                "window_id": window_id,
                "visible": is_visible,
                "window_class": window.window_class or "unknown",
                "window_title": window.name or "(no title)",
                "pid": window.pid,
                "i3pm_env": i3pm_env,
                "tracking": tracking_info,
                "i3_state": i3_state,
                "duration_ms": duration_ms,
            }

            # Add correlation field only if window was matched via launch
            if correlation_info:
                result["correlation"] = correlation_info

            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting window state: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="windows::get_state",
                duration_ms=duration_ms,
                error=error_msg,
            )

    # ========================================================================
    # Feature 039: Diagnostic API Methods (T087-T092)
    # ========================================================================

    async def _health_check(self) -> Dict[str, Any]:
        """
        Health check method for diagnostic CLI.
        
        Feature 039 - T087
        
        Returns comprehensive daemon health status including:
        - Daemon version and uptime
        - i3 IPC connection status
        - JSON-RPC server status
        - Event subscription details
        - Window tracking stats
        - Overall health assessment
        
        Returns:
            DiagnosticReport with health information
        """
        start_time = time.perf_counter()

        result = self.daemon_status_service.health_check()
        duration_ms = (time.perf_counter() - start_time) * 1000
        
        await self._log_ipc_event(
            event_type="health_check",
            duration_ms=duration_ms
        )

        return result

    async def _get_socket_health(self) -> Dict[str, Any]:
        """
        Get Sway IPC socket health status.

        Feature 121: Implements `i3pm diagnose socket-health` endpoint.

        Returns:
            SocketHealthStatus dict with:
            - status: "healthy", "stale", or "disconnected"
            - socket_path: Current socket path
            - last_validated: ISO8601 timestamp of last validation
            - latency_ms: Round-trip time for health check
            - reconnection_count: Number of reconnections
            - uptime_seconds: Time since last connection
            - error: Error message if not healthy
        """
        start_time = time.perf_counter()

        try:
            return await self.daemon_status_service.socket_health()

        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::get_socket_health",
                duration_ms=duration_ms,
            )

    async def _get_window_identity_diagnostic(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get comprehensive window identity for diagnostic purposes.
        
        Feature 039 - T088
        
        Args:
            params: {"window_id": int}
        
        Returns:
            WindowIdentity with all window properties
        
        Raises:
            Error -32001: Window not found
            Error -32002: Window not tracked by daemon
        """
        start_time = time.perf_counter()
        window_id = params.get("window_id")
        
        if not window_id:
            raise ValueError("window_id parameter required")
        
        # Get window from i3
        if not self.i3_connection or not self.i3_connection.is_connected:
            raise RuntimeError("i3 IPC connection not available")
        
        try:
            tree = await self.i3_connection.get_tree()
            window = tree.find_by_id(window_id)
            
            if not window:
                raise ValueError(f"Window {window_id} not found")
            
            # Get window properties
            window_class = window.window_class or "unknown"
            window_instance = window.window_instance or ""
            window_title = window.name or "(no title)"
            window_pid = window.pid if hasattr(window, 'pid') else None
            
            # Get workspace info
            workspace = window.workspace()
            workspace_number = workspace.num if workspace else None
            workspace_name = workspace.name if workspace else None
            output_name = workspace.ipc_data.get('output') if workspace else None
            
            # Get window state
            is_floating = window.floating != 'auto_off' if hasattr(window, 'floating') else False
            is_focused = window.focused
            
            # Check if window is hidden (in scratchpad)
            is_hidden = False
            parent = window.parent
            while parent:
                if parent.scratchpad_state and parent.scratchpad_state != 'none':
                    is_hidden = True
                    break
                parent = parent.parent
            
            # Get I3PM environment from /proc
            i3pm_env = None
            if window_pid:
                from .services.window_filter import read_process_environ
                env = read_process_environ(window_pid)
                if env:
                    i3pm_env = {
                        "app_id": env.get("I3PM_APP_ID"),
                        "app_name": env.get("I3PM_APP_NAME"),
                        "project_name": env.get("I3PM_PROJECT_NAME"),
                        "scope": env.get("I3PM_SCOPE")
                    }
            
            # Get i3 marks
            i3pm_marks = [m for m in (window.marks or []) if m.startswith("scoped:") or m.startswith("global:") or m.startswith("app:")]
            
            # Get normalized class
            from .services.window_identifier import normalize_class, get_window_identity
            window_class_normalized = normalize_class(window_class)
            
            # Check if tracked by daemon
            tracked_window = self.state_manager.state.window_map.get(window_id)
            matched_app = None
            match_type = "none"
            
            if tracked_window:
                matched_app = getattr(tracked_window, 'app_name', None)
                match_type = getattr(tracked_window, 'match_type', 'tracked')
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            result = {
                "window_id": window_id,
                "window_class": window_class,
                "window_class_normalized": window_class_normalized,
                "window_instance": window_instance,
                "window_title": window_title,
                "window_pid": window_pid,
                "workspace_number": workspace_number,
                "workspace_name": workspace_name,
                "output_name": output_name,
                "is_floating": is_floating,
                "is_focused": is_focused,
                "is_hidden": is_hidden,
                "i3pm_env": i3pm_env,
                "i3pm_marks": i3pm_marks,
                "matched_app": matched_app,
                "match_type": match_type
            }
            
            await self._log_ipc_event(
                event_type="get_window_identity",
                duration_ms=duration_ms,
                params={"window_id": window_id}
            )
            
            return result
            
        except ValueError as e:
            if "not found" in str(e):
                # Return JSON-RPC error -32001
                raise RuntimeError(json.dumps({
                    "code": -32001,
                    "message": "Window not found",
                    "data": {"window_id": window_id}
                }))
            raise
        except Exception as e:
            logger.error(f"Error getting window identity: {e}")
            raise

    async def _get_window_environment(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get I3PM environment variables for a window by PID.

        Feature 058 - Phase 3: Eliminate duplicate environment reading

        Args:
            params: {"pid": int} - Process ID of the window

        Returns:
            Dictionary with I3PM environment variables or None if not available:
            {
                "app_id": str | None,
                "app_name": str | None,
                "project_name": str | None,
                "project_dir": str | None,
                "scope": str | None,
                "target_workspace": int | None,
                "expected_class": str | None
            }

        Raises:
            ValueError: If PID parameter is missing or invalid
        """
        start_time = time.perf_counter()
        pid = params.get("pid")

        if not pid:
            raise ValueError("pid parameter required")

        if not isinstance(pid, int) or pid <= 0:
            raise ValueError(f"Invalid PID: {pid}")

        # Read process environment using existing window_filter module
        from .services.window_filter import read_process_environ
        env = read_process_environ(pid)

        result = {
            "app_id": env.get("I3PM_APP_ID") if env else None,
            "app_name": env.get("I3PM_APP_NAME") if env else None,
            "project_name": env.get("I3PM_PROJECT_NAME") if env else None,
            "project_dir": env.get("I3PM_PROJECT_DIR") if env else None,
            "scope": env.get("I3PM_SCOPE") if env else None,
            "target_workspace": None,
            "expected_class": env.get("I3PM_EXPECTED_CLASS") if env else None
        }

        # Parse target workspace if present
        if env and "I3PM_TARGET_WORKSPACE" in env:
            try:
                result["target_workspace"] = int(env["I3PM_TARGET_WORKSPACE"])
            except (ValueError, TypeError):
                pass  # Invalid workspace value, leave as None

        duration_ms = (time.perf_counter() - start_time) * 1000
        await self._log_ipc_event(
            event_type="get_window_environment",
            duration_ms=duration_ms,
            params={"pid": pid}
        )

        return result

    async def _get_workspace_rule_diagnostic(self, params: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Get workspace assignment rule for an application.
        
        Feature 039 - T089
        
        Args:
            params: {"app_name": str}
        
        Returns:
            WorkspaceRule or None
        
        Raises:
            Error -32003: Application not found in registry
        """
        start_time = time.perf_counter()
        app_name = params.get("app_name")
        
        if not app_name:
            raise ValueError("app_name parameter required")
        
        # Get application registry
        registry_path = Path.home() / ".config" / "i3" / "application-registry.json"
        
        if not registry_path.exists():
            raise RuntimeError(json.dumps({
                "code": -32003,
                "message": "Application not found in registry",
                "data": {"app_name": app_name, "reason": "registry_file_not_found"}
            }))
        
        try:
            with open(registry_path) as f:
                registry = json.load(f)
            
            app_def = registry.get(app_name)
            
            if not app_def:
                raise RuntimeError(json.dumps({
                    "code": -32003,
                    "message": "Application not found in registry",
                    "data": {"app_name": app_name}
                }))
            
            # Build workspace rule response
            result = {
                "app_identifier": app_def.get("expected_class", app_name),
                "matching_strategy": "normalized",  # Default strategy
                "aliases": app_def.get("aliases", []),
                "target_workspace": app_def.get("preferred_workspace"),
                "fallback_behavior": app_def.get("fallback_behavior", "current"),
                "app_name": app_name,
                "description": app_def.get("display_name", app_name)
            }
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            await self._log_ipc_event(
                event_type="get_workspace_rule",
                duration_ms=duration_ms,
                params={"app_name": app_name}
            )
            
            return result
            
        except RuntimeError as e:
            # Re-raise JSON-RPC errors
            if str(e).startswith("{"):
                raise
            raise
        except Exception as e:
            logger.error(f"Error getting workspace rule: {e}")
            raise

    async def _validate_state_diagnostic(self) -> Dict[str, Any]:
        """
        Validate daemon state consistency against i3 IPC.
        
        Feature 039 - T090
        
        Compares daemon's tracked windows with actual i3 window tree
        to detect state drift.
        
        Returns:
            StateValidation with consistency report
        
        Raises:
            Error -32010: i3 IPC connection failed
        """
        start_time = time.perf_counter()
        
        if not self.i3_connection or not self.i3_connection.is_connected:
            raise RuntimeError(json.dumps({
                "code": -32010,
                "message": "i3 IPC connection failed",
                "data": {"reason": "not_connected"}
            }))

        try:
            # Get i3 window tree
            tree = await self.i3_connection.get_tree()
            i3_windows = tree.leaves()
            
            # Get daemon tracked windows
            daemon_windows = self.state_manager.state.window_map
            
            # Compare states
            total_windows_checked = len(i3_windows)
            windows_consistent = 0
            windows_inconsistent = 0
            mismatches = []
            
            for i3_window in i3_windows:
                window_id = i3_window.id
                daemon_window = daemon_windows.get(window_id)
                
                # Check workspace consistency
                i3_workspace = i3_window.workspace()
                i3_workspace_num = i3_workspace.num if i3_workspace else None
                
                if daemon_window:
                    daemon_workspace_num = getattr(daemon_window, 'workspace_number', None)
                    
                    if daemon_workspace_num and daemon_workspace_num != i3_workspace_num:
                        mismatches.append({
                            "window_id": window_id,
                            "property_name": "workspace",
                            "daemon_value": str(daemon_workspace_num),
                            "i3_value": str(i3_workspace_num),
                            "severity": "warning"
                        })
                        windows_inconsistent += 1
                    else:
                        windows_consistent += 1
                else:
                    # Window exists in i3 but not tracked by daemon
                    # This is normal for pre-existing windows, so just count as consistent
                    windows_consistent += 1
            
            is_consistent = windows_inconsistent == 0
            consistency_percentage = round((windows_consistent / total_windows_checked * 100), 1) if total_windows_checked > 0 else 100.0
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            result = {
                "validated_at": datetime.now().isoformat(),
                "total_windows_checked": total_windows_checked,
                "windows_consistent": windows_consistent,
                "windows_inconsistent": windows_inconsistent,
                "mismatches": mismatches,
                "is_consistent": is_consistent,
                "consistency_percentage": consistency_percentage
            }
            
            await self._log_ipc_event(
                event_type="validate_state",
                duration_ms=duration_ms
            )
            
            return result
            
        except Exception as e:
            logger.error(f"Error validating state: {e}")
            raise

    async def _get_recent_events_diagnostic(self, params: Dict[str, Any]) -> list:
        """
        Get recent events from circular buffer.
        
        Feature 039 - T091
        
        Args:
            params: {
                "limit": int (optional, default=50, max=500),
                "event_type": str (optional, filter by type)
            }
        
        Returns:
            List of WindowEvent objects
        
        Raises:
            Error -32004: Invalid limit
        """
        start_time = time.perf_counter()
        
        limit = params.get("limit", 50)
        event_type = params.get("event_type")
        
        # Validate limit
        if limit < 1 or limit > 500:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": "Invalid limit (must be 1-500)",
                "data": {"limit": limit}
            }))
        
        if not self.event_buffer:
            return []
        
        # Get events from buffer
        events = self.event_buffer.get_recent(limit=limit, event_type=event_type)

        # Format events for diagnostic output
        formatted_events = []
        for event in events:
            formatted_event = {
                "event_id": event.event_id,
                "event_type": event.event_type,
                "timestamp": event.timestamp.isoformat() if event.timestamp else '',
                "source": event.source,
                "window_id": event.window_id,
                "window_class": event.window_class,
                "window_title": event.window_title,
                "workspace_name": event.workspace_name,
                "project_name": event.project_name,
                "processing_duration_ms": event.processing_duration_ms,
                "error": event.error
            }
            formatted_events.append(formatted_event)
        
        duration_ms = (time.perf_counter() - start_time) * 1000
        
        await self._log_ipc_event(
            event_type="get_recent_events",
            duration_ms=duration_ms,
            params={"limit": limit, "event_type": event_type}
        )
        
        return formatted_events

    async def _get_diagnostic_report_full(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get complete diagnostic report with all state information.
        
        Feature 039 - T092
        
        Args:
            params: {
                "include_windows": bool (optional, default=False),
                "include_events": bool (optional, default=False),
                "include_validation": bool (optional, default=False)
            }
        
        Returns:
            DiagnosticReport with comprehensive state information
        """
        start_time = time.perf_counter()
        
        include_windows = params.get("include_windows", False)
        include_events = params.get("include_events", False)
        include_validation = params.get("include_validation", False)
        
        # Get base health check
        health_data = await self._health_check()
        
        # Start building report
        report = {
            "generated_at": datetime.now().isoformat(),
            **health_data  # Include all health check data
        }
        
        # Add i3 IPC state
        if self.i3_connection and self.i3_connection.is_connected():
            try:
                tree = await self.i3_connection.get_tree()
                workspaces = await self._sway_get_workspaces()
                outputs = await self.i3_connection.get_outputs()
                
                report["i3_ipc_state"] = {
                    "total_windows": len(tree.leaves()),
                    "total_workspaces": len(workspaces),
                    "total_outputs": len([o for o in outputs if o.active])
                }
            except Exception as e:
                logger.error(f"Error getting i3 state: {e}")
                report["i3_ipc_state"] = {"error": str(e)}
        
        # Include windows if requested
        if include_windows:
            windows = []
            for window_id, window_data in self.state_manager.state.windows.items():
                windows.append({
                    "window_id": window_id,
                    "window_class": getattr(window_data, 'window_class', 'unknown'),
                    "workspace": getattr(window_data, 'workspace_number', None)
                })
            report["tracked_windows"] = windows
        
        # Include events if requested
        if include_events:
            events = await self._get_recent_events_diagnostic({"limit": 100})
            report["recent_events"] = events
        
        # Include validation if requested
        if include_validation:
            validation = await self._validate_state_diagnostic()
            report["state_validation"] = validation
        
        duration_ms = (time.perf_counter() - start_time) * 1000

        await self._log_ipc_event(
            event_type="get_diagnostic_report",
            duration_ms=duration_ms,
            params=params
        )

        return report

    def _require_registry_app(self, app_name: str) -> RegistryApp:
        """Return a registry definition or raise a JSON-RPC-style error."""
        self.registry_loader.ensure_current()
        app = self.registry_loader.get(str(app_name or "").strip())
        if app:
            return app
        raise RuntimeError(json.dumps({
            "code": -32002,
            "message": f"Application '{app_name}' not found in registry",
            "data": {"app_name": app_name, "reason": "app_not_found"}
        }))

    async def _find_live_sway_window(self, window_id: int) -> Optional[Any]:
        """Return a live Sway container by con_id/window_id, or None if missing."""
        target_window_id = int(window_id or 0)
        if target_window_id <= 0:
            return None
        if not self.i3_connection or not self.i3_connection.conn:
            return None

        tree = await self.i3_connection.get_tree()

        def find_window(con):
            if int(getattr(con, "id", 0) or 0) == target_window_id:
                return con
            for child in getattr(con, "nodes", []) or []:
                result = find_window(child)
                if result is not None:
                    return result
            for child in getattr(con, "floating_nodes", []) or []:
                result = find_window(child)
                if result is not None:
                    return result
            return None

        return find_window(tree)

    async def _prepare_launch(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Build a deterministic launch spec and register pending launch state."""
        app_name = str(params.get("app_name") or "").strip()
        if not app_name:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Missing required parameter: app_name",
                "data": {"param": "app_name"}
            }))

        launcher_pid = int(params.get("launcher_pid") or os.getpid())
        if launcher_pid <= 0:
            launcher_pid = os.getpid()

        variant_override = str(
            params.get("context_variant_override")
            or params.get("target_variant")
            or params.get("execution_mode")
            or ""
        ).strip().lower()
        raw_target_host_override = str(
            params.get("target_host")
            or params.get("host")
            or ""
        ).strip()
        target_host_override = (
            self._resolve_requested_target_host(
                raw_target_host_override or variant_override,
                project_name=str(
                    params.get("qualified_name")
                    or params.get("project_name")
                    or ""
                ).strip(),
            )
            if raw_target_host_override
            else ""
        )
        if variant_override and variant_override not in {"local", "ssh"}:
            raise RuntimeError(json.dumps({
                "code": -32602,
                "message": "Invalid context_variant_override",
                "data": {"context_variant_override": variant_override}
            }))

        app = self._require_registry_app(app_name)
        dry_run = bool(params.get("dry_run", False))
        register_launch = bool(params.get("register_launch", True))
        requested_project = str(
            params.get("qualified_name")
            or params.get("project_name")
            or ""
        ).strip()
        active_project = await self.state_manager.get_active_project()
        active_context: Dict[str, Any] = {}

        if app.scope == "scoped" and requested_project:
            resolved = self._find_worktree_by_qualified_name(requested_project)
            active_project = str(resolved["full_qualified_name"] or "").strip()
            active_context = self._build_active_worktree_context(
                active_project,
                resolved["repo_name"],
                resolved["repo"],
                resolved["worktree"],
                target_host=(
                    target_host_override
                    if target_host_override
                    else self._resolve_requested_target_host(variant_override, project_name=active_project)
                ),
            )
        else:
            active_context = self._get_active_runtime_context(active_project=active_project) or {}
        scoped_launch = app.scope == "scoped"
        qualified_name = (
            str(active_context.get("qualified_name") or "").strip()
            if scoped_launch
            else ""
        )
        local_directory = (
            str(
                active_context.get("local_directory")
                or active_context.get("directory")
                or ""
            ).strip()
            if scoped_launch
            else ""
        )
        remote_profile = (
            dict(active_context.get("host_profile") or {})
            if scoped_launch and isinstance(active_context.get("host_profile"), dict)
            else None
        )
        target_host = self._normalize_target_host(
            target_host_override
            or self._target_host_from_context_payload(active_context, project_name=qualified_name)
            or (
                remote_profile.get("host")
                if isinstance(remote_profile, dict) and remote_profile.get("host")
                else self._local_host_alias()
            )
        )

        if app.scope == "scoped" and not qualified_name:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": f"Scoped application '{app_name}' requires an active worktree context",
                "data": {"app_name": app_name}
            }))

        if scoped_launch and active_project and qualified_name != str(active_project).strip():
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": (
                    "Active runtime context is inconsistent; refusing scoped launch until "
                    "context is re-established"
                ),
                "data": {
                    "app_name": app_name,
                    "active_project": str(active_project).strip(),
                    "qualified_name": qualified_name,
                }
            }))

        if not scoped_launch and target_host != self._local_host_alias():
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": (
                    f"Global application '{app_name}' cannot be launched on a non-local host target; "
                    "global apps always run locally"
                ),
                "data": {
                    "app_name": app_name,
                    "scope": app.scope,
                    "target_host": target_host,
                }
            }))

        if qualified_name and target_host != self._local_host_alias():
            remote_profile = self._get_project_remote_profile(qualified_name) if qualified_name else None
            if not remote_profile:
                raise RuntimeError(json.dumps({
                    "code": -32004,
                    "message": f"Project '{qualified_name}' has no configured host profile for '{target_host}'",
                    "data": {"project_name": qualified_name, "target_host": target_host}
                }))
            if self._normalize_target_host(remote_profile.get("host")) != target_host:
                raise RuntimeError(json.dumps({
                    "code": -32004,
                    "message": (
                        f"Project '{qualified_name}' is configured for host "
                        f"'{self._normalize_target_host(remote_profile.get('host'))}', not '{target_host}'"
                    ),
                    "data": {"project_name": qualified_name, "target_host": target_host}
                }))
        else:
            remote_profile = None

        execution_mode = self._execution_mode_for_target_host(target_host)
        if execution_mode == "ssh" and not app.terminal:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": (
                    f"Remote project execution only supports managed terminal launches; "
                    f"'{app_name}' must run locally or in global context"
                ),
                "data": {
                    "app_name": app_name,
                    "project_name": qualified_name,
                    "execution_mode": execution_mode,
                    "ssh_policy": "terminal_only",
                }
            }))

        if qualified_name:
            identity = self._build_worktree_context_identity(
                qualified_name,
                remote_profile,
                target_host=target_host,
            )
            connection_key = identity["connection_key"]
            context_key = identity["context_key"]
            parsed = parse_qualified_name(qualified_name)
            worktree_branch = parsed.branch
            worktree_account = parsed.account
            worktree_repo = parsed.repo
        else:
            connection_key = self._normalize_connection_key(f"local@{self._local_host_alias()}")
            context_key = ""
            worktree_branch = ""
            worktree_account = ""
            worktree_repo = ""

        project_name = qualified_name if app.scope == "scoped" else ""
        remote_session_name_override = str(params.get("remote_session_name_override") or "").strip()
        project_dir = str(remote_profile.get("remote_dir", "")) if remote_profile else local_directory
        local_project_dir = local_directory if project_name else str(Path.home())
        if project_name and execution_mode == "local" and not Path(local_project_dir).is_dir():
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": f"Local project directory is unavailable for '{project_name}'",
                "data": {"project_name": project_name, "project_directory": local_project_dir}
            }))

        session_name = f"{worktree_repo}_{worktree_branch}" if worktree_repo and worktree_branch else ""
        project_display_name = worktree_branch
        substitution_project_dir = project_dir if execution_mode == "ssh" else local_project_dir
        prepared_args = self.launch_service.build_prepared_args(
            parameters=app.parameters,
            project_name=project_name,
            project_dir=substitution_project_dir,
            session_name=session_name,
            project_display_name=project_display_name,
            project_icon="",
            preferred_workspace=app.preferred_workspace,
        )

        launch_identity = self.launch_service.build_launch_identity(
            app_name=app.name,
            project_name=project_name,
            launcher_pid=launcher_pid,
            app_id_override=str(params.get("app_id_override") or "").strip(),
        )
        scoped_terminal_mode = str(getattr(app, "scoped_terminal_mode", "") or "").strip()
        terminal_identity = self.launch_service.build_terminal_identity(
            app=app,
            scoped_launch=scoped_launch,
            project_name=project_name,
            context_key=context_key,
            scoped_terminal_mode=scoped_terminal_mode,
            prepared_args=prepared_args,
        )
        terminal_role = str(terminal_identity.get("terminal_role") or "")
        tmux_session_name = str(terminal_identity.get("tmux_session_name") or "")
        scoped_terminal_command = [
            str(arg)
            for arg in terminal_identity.get("scoped_terminal_command", [])
        ]
        environment = self.launch_service.build_launch_env(
            app_name=app.name,
            scope=app.scope,
            preferred_workspace=app.preferred_workspace,
            expected_class=app.expected_class,
            project_name=project_name,
            project_dir=project_dir if project_name else "",
            local_project_dir=local_project_dir if project_name else "",
            project_display_name=project_display_name,
            execution_mode=execution_mode,
            target_host=target_host if project_name else self._local_host_alias(),
            transport_kind=self._transport_kind_for_target_host(target_host if project_name else self._local_host_alias()),
            connection_key=connection_key,
            context_key=context_key,
            remote_profile=remote_profile,
            launcher_pid=launcher_pid,
            launch_identity=launch_identity,
            terminal_role=terminal_role,
            tmux_session_name=tmux_session_name,
            restore_mark=str(params.get("restore_mark") or "").strip(),
            remote_session_name=remote_session_name_override,
            worktree_branch=worktree_branch,
            worktree_account=worktree_account,
            worktree_repo=worktree_repo,
        )
        launch_strategy = "direct"
        launch_transport = self._resolve_terminal_launch_transport(
            execution_mode=execution_mode,
            connection_key=connection_key,
        )
        terminal_launch: Optional[Dict[str, Any]] = None
        terminal_launch_config = self.launch_service.build_terminal_launch_config(
            app=app,
            scoped_launch=scoped_launch,
            project_name=project_name,
            context_key=context_key,
            connection_key=connection_key,
            launch_transport=launch_transport,
            remote_profile=remote_profile,
            scoped_terminal_mode=scoped_terminal_mode,
            scoped_terminal_command=scoped_terminal_command,
            tmux_session_name=tmux_session_name,
            terminal_role=terminal_role,
            remote_session_name_override=remote_session_name_override,
        )
        launch_strategy = str(terminal_launch_config.get("launch_strategy") or launch_strategy)
        terminal_launch = terminal_launch_config.get("terminal_launch")
        tmux_session_name = str(terminal_launch_config.get("tmux_session_name") or tmux_session_name)

        if dry_run:
            launch = {
                "status": "skipped",
                "reason": "dry_run",
                "launch_id": "",
                "terminal_anchor_id": launch_identity["terminal_anchor_id"],
                "expected_class": app.expected_class,
                "pending_count": self.state_manager.launch_registry.get_stats().total_pending,
            }
        elif not register_launch:
            launch = {
                "status": "deferred",
                "reason": "register_launch_disabled",
                "launch_id": "",
                "terminal_anchor_id": launch_identity["terminal_anchor_id"],
                "expected_class": app.expected_class,
                "pending_count": self.state_manager.launch_registry.get_stats().total_pending,
            }
        else:
            launch = await self.launch_service.register_pending_launch(
                app=app,
                project_name=project_name,
                project_directory=local_project_dir or str(Path.home()),
                launcher_pid=launcher_pid,
                terminal_anchor_id=launch_identity["terminal_anchor_id"],
                preferred_workspace=app.preferred_workspace,
            )

        return {
            "app_name": app.name,
            "command": app.command,
            "args": prepared_args,
            "terminal": bool(app.terminal),
            "scope": app.scope,
            "expected_class": app.expected_class,
            "preferred_workspace": app.preferred_workspace,
            "project_name": project_name,
            "project_directory": project_dir if project_name else "",
            "local_project_directory": local_project_dir if project_name else "",
            "project_display_name": project_display_name,
            "target_host": target_host,
            "transport_kind": self._transport_kind_for_target_host(target_host),
            "connection_key": connection_key,
            "context_key": context_key,
            "launch_strategy": launch_strategy,
            "launch_transport": launch_transport,
            "host_launch_policy": "terminal_only" if execution_mode == "ssh" else "not_applicable",
            "host_profile": remote_profile,
            "terminal_launch": terminal_launch,
            "terminal_role": terminal_role,
            "tmux_session_name": tmux_session_name,
            "environment": environment,
            "launch": launch,
            "terminal_anchor_id": launch_identity["terminal_anchor_id"],
            "app_instance_id": launch_identity["app_instance_id"],
        }

    def _repo_root(self) -> Path:
        """Return the repository root that contains runtime helper scripts."""
        root = Path(__file__).resolve().parents[3]
        if root.name == "lib" and root.parent.exists():
            return root.parent
        return root

    def _runtime_dir(self) -> Path:
        """Return the XDG runtime directory used by daemon-owned helpers."""
        return Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))

    def _canonical_tmux_socket(self) -> str:
        """Return the canonical managed tmux socket path for the current host user."""
        uid = os.getuid()
        return str(self._runtime_dir() / f"tmux-{uid}" / "default")

    def _load_json_file(self, path: Path) -> Dict[str, Any]:
        """Read a JSON object from disk, returning an empty object on failure."""
        try:
            with open(path, "r") as f:
                payload = json.load(f)
            return payload if isinstance(payload, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def _parse_remote_target(self, remote_target: str, connection_key: str = "") -> Tuple[str, str, int]:
        """Parse a user@host:port SSH target into user, host, port."""
        raw = str(remote_target or "").strip() or str(connection_key or "").strip()
        if not raw:
            return "", "", 22
        if raw.startswith("ssh://"):
            raw = raw[len("ssh://") :]
        user_part = ""
        host_port = raw
        if "@" in raw:
            user_part, host_port = raw.split("@", 1)
        host = host_port
        port = 22
        if ":" in host_port:
            host, port_text = host_port.rsplit(":", 1)
            try:
                port = int(port_text)
            except ValueError:
                port = 22
        return user_part.strip(), host.strip(), port

    def _resolve_terminal_launch_transport(
        self,
        *,
        execution_mode: str,
        connection_key: str,
    ) -> str:
        """Return the terminal launch transport for the resolved context."""
        mode = str(execution_mode or "local").strip().lower() or "local"
        if mode != "ssh":
            return "local_helper"
        return "remote_helper"

    def _build_window_focus_target(
        self,
        *,
        window_id: int,
        project_name: str = "",
        target_variant: str = "",
        connection_key: str = "",
    ) -> Dict[str, Any]:
        """Return a daemon-owned focus target for a window entry."""
        return {
            "method": "window.focus",
            "params": {
                "window_id": int(window_id),
                "project_name": str(project_name or "").strip(),
                "target_variant": str(target_variant or "").strip(),
                "connection_key": str(connection_key or "").strip(),
            },
        }

    def _flatten_runtime_windows(self, runtime_snapshot: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Flatten dashboard windows from runtime snapshot outputs/workspaces."""
        flattened: List[Dict[str, Any]] = []
        for output in runtime_snapshot.get("outputs", []) or []:
            if not isinstance(output, dict):
                continue
            for workspace in output.get("workspaces", []) or []:
                if not isinstance(workspace, dict):
                    continue
                for window in workspace.get("windows", []) or []:
                    if isinstance(window, dict):
                        flattened.append(dict(window))
        return flattened

    def _set_focus_overrides(
        self,
        *,
        session_key: str = "",
        window_id: int = 0,
        connection_key: str = "",
    ) -> None:
        """Persist the last successful daemon-owned focus target for dashboard consumers."""
        self.focus_service.set_focus_overrides(
            session_key=session_key,
            window_id=window_id,
            connection_key=connection_key,
        )

    def _clear_focus_overrides(self) -> None:
        """Clear both session and window focus overrides."""
        self.focus_service.clear_focus_overrides()

    def _clear_session_focus_override(self) -> None:
        """Clear the session override while keeping any explicit window target."""
        self.focus_service.clear_session_override()

    def _advance_user_intent_epoch(
        self,
        *,
        method: str,
        params: Optional[Dict[str, Any]] = None,
    ) -> int:
        """Record a new top-level user intent so stale async work can be ignored."""
        payload = params or {}
        intent_epoch = self.focus_service.advance_user_intent(
            method=str(method or "").strip(),
            params=payload,
            created_at=time.time(),
        )
        logger.info(
            "User intent epoch=%s method=%s project=%s variant=%s connection=%s session=%s app=%s",
            intent_epoch,
            str(method or "").strip(),
            str(payload.get("qualified_name") or payload.get("project_name") or "").strip(),
            str(payload.get("target_variant") or payload.get("execution_mode") or "").strip(),
            self._normalize_connection_key(str(payload.get("connection_key") or "").strip()),
            str(payload.get("session_key") or "").strip(),
            str(payload.get("app_name") or "").strip(),
        )
        return intent_epoch

    def _finalize_focus_intent_for_result(
        self,
        *,
        method: str,
        params: Dict[str, Any],
        result: Any,
    ) -> Dict[str, Any]:
        """Confirm or fail the focus intent associated with a handled request."""
        return self.focus_service.finalize_focus_intent_for_result(
            method=method,
            intent_epoch=int(params.get("__intent_epoch") or 0),
            result=result,
        )

    async def _fail_focus_intent_for_exception(
        self,
        method: str,
        params: Dict[str, Any],
        reason: str,
    ) -> None:
        """Mark an active focus intent failed when request handling raises."""
        focus_intent = self.focus_service.fail_focus_intent_for_exception(
            method=method,
            intent_epoch=int(params.get("__intent_epoch") or 0),
            reason=reason,
        )
        if focus_intent:
            await self.notify_state_change("focus_changed")

    def _user_intent_is_current(self, intent_epoch: int) -> bool:
        """Return whether an async action still matches the latest explicit user intent."""
        return self.focus_service.user_intent_is_current(intent_epoch)

    def _stale_intent_result(
        self,
        *,
        session_key: str = "",
        project_name: str = "",
        reason: str,
    ) -> Dict[str, Any]:
        """Return a consistent response when a newer user action supersedes a stale request."""
        logger.info(
            "Ignoring stale user intent for session=%s project=%s reason=%s current_epoch=%s",
            str(session_key or "").strip(),
            str(project_name or "").strip(),
            str(reason or "").strip(),
            self.focus_service.user_intent_epoch,
        )
        return {
            "success": False,
            "reason": str(reason or "superseded_by_newer_user_intent"),
            "session_key": str(session_key or "").strip(),
            "project_name": str(project_name or "").strip(),
            "current_session_key_after": "",
            "focused_window_id_after": 0,
            "focus_state_after": {},
            "verification": {
                "success": False,
                "reason": str(reason or "superseded_by_newer_user_intent"),
                "session_key": str(session_key or "").strip(),
                "current_session_key": "",
            },
        }

    async def _load_reconciled_session_runtime(
        self,
        params: Optional[Dict[str, Any]] = None,
    ) -> Tuple[Dict[str, Any], List[Dict[str, Any]], Dict[str, Any]]:
        """Load runtime + Herdr-native session rows."""
        runtime_snapshot = await self._runtime_snapshot(params or {})
        sessions_raw = runtime_snapshot.get("sessions", [])
        if not isinstance(sessions_raw, list):
            raise RuntimeError("runtime.snapshot contract violation: sessions must be a list")
        sessions = [
            {
                key: value
                for key, value in dict(session).items()
                if key not in RETIRED_SESSION_UI_STATE_FIELDS
            }
            for session in sessions_raw
            if isinstance(session, dict)
        ]
        return runtime_snapshot, sessions, {}

    async def _focus_state(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return canonical focus state for acceptance checks and UI confirmation."""
        runtime_snapshot, sessions, _cleanup = await self._load_reconciled_session_runtime(
            params or {},
        )
        return self.focus_service.build_focus_state_payload(
            runtime_snapshot,
            sessions,
            generation=int(self._focus_generation or self._snapshot_version or 0),
        )

    async def _session_list(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return daemon-owned Herdr AI session data."""
        runtime_snapshot, sessions, _cleanup = await self._load_reconciled_session_runtime(
            params or {},
        )
        focused_window_id = int(runtime_snapshot.get("focused_window_id") or 0)
        current_session_key = str(runtime_snapshot.get("current_session_key") or "").strip()
        return {
            "sessions": sessions,
            "total": len(sessions),
            "current_session_key": current_session_key,
            "focused_window_id": focused_window_id,
        }

    def _build_dashboard_projects(
        self,
        runtime_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Group tracked windows into project cards for the monitoring panel."""
        return build_dashboard_project_cards(
            runtime_snapshot,
            sessions,
            canonical_project_name=self._canonical_discovered_project_name,
            normalize_target_host=self._normalize_target_host,
            parse_context_key_target_host=parse_context_key_target_host,
            target_host_from_context_payload=self._target_host_from_context_payload,
            local_host_alias=self._local_host_alias,
            execution_mode_for_target_host=self._execution_mode_for_target_host,
            build_target_context_key=self._build_target_context_key,
            transport_kind_for_target_host=self._transport_kind_for_target_host,
            window_matches_focus_override=self.focus_service.window_matches_focus_override,
            build_window_focus_target=self._build_window_focus_target,
        )

    async def _build_dashboard_worktrees(
        self,
        runtime_snapshot: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        """Build a compact worktree list for the runtime shell."""
        return await self.dashboard_worktree_service.build_worktrees(runtime_snapshot)

    async def _dashboard_snapshot(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return the daemon-owned dashboard payload consumed by QuickShell."""
        return await self.dashboard_service.snapshot(params or {})

    async def _dashboard_validate(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return dashboard invariant status without requiring clients to know the rules."""
        return await self.dashboard_service.validate(params or {})

    async def _launch_open(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Prepare and execute an application launch entirely inside the daemon."""
        payload = dict(params or {})
        payload.setdefault("launcher_pid", os.getpid())
        payload["register_launch"] = False
        return await self.launch_service.open_launch(
            payload=payload,
            prepare_launch=self._prepare_launch,
            focus_window=self._window_focus,
            focus_window_fast=self._window_focus_fast,
            clear_focus_overrides=self._clear_focus_overrides,
        )

    # ======================
    # Feature 058: Project Management JSON-RPC Handlers (T030-T033)
    # Feature 101: DEPRECATED - These methods work with legacy project JSON files
    #              Use worktree.* methods instead for repos.json-based project management
    # ======================

    async def _project_create(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new project.

        DEPRECATED (Feature 101): Use 'i3pm worktree create' instead.
        This method creates legacy ~/.config/i3/projects/*.json files.

        Args:
            params: {
                "name": str,          # Unique project identifier
                "directory": str,     # Absolute path to project directory
                "display_name": str,  # Human-readable project name
                "icon": str = "📁"    # Project icon (optional)
            }

        Returns:
            Project data (name, directory, display_name, icon, created_at, updated_at)

        Raises:
            VALIDATION_ERROR (1003): Invalid parameters or directory
            FILE_IO_ERROR (1004): Project already exists
        """
        logger.warning("[Feature 101] _project_create is deprecated. Use worktree.create instead.")
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Extract parameters
            name = params.get("name")
            directory = params.get("directory")
            display_name = params.get("display_name")
            icon = params.get("icon", "📁")

            # Validate required parameters
            if not name or not directory or not display_name:
                raise ValueError("Missing required parameters: name, directory, display_name")

            # Create project
            project = service.create(
                name=name,
                directory=directory,
                display_name=display_name,
                icon=icon
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params={"name": name, "directory": directory}
            )

            # Return project data
            result = {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

            # Feature 087: Include remote configuration if present
            if project.remote is not None:
                result["remote"] = project.remote.model_dump()

            return result

        except FileExistsError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{FILE_IO_ERROR}:{str(e)}")

        except ValueError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{VALIDATION_ERROR}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::create",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List all projects.

        Args:
            params: {} (no parameters required)

        Returns:
            {"projects": [Project data...]}
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # List projects
            projects = service.list()

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::list",
                duration_ms=duration_ms,
                result_count=len(projects)
            )

            return {
                "projects": [
                    {
                        "name": p.name,
                        "directory": p.directory,
                        "display_name": p.display_name,
                        "icon": p.icon,
                        "created_at": p.created_at.isoformat(),
                        "updated_at": p.updated_at.isoformat()
                    }
                    for p in projects
                ]
            }

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::list",
                duration_ms=duration_ms,
                error=str(e)
            )
            raise

    async def _project_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get project details.

        Args:
            params: {"name": str}

        Returns:
            Project data

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            # Get project
            project = service.get(name)

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params={"name": name}
            )

            result = {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

            # Feature 087: Include remote configuration if present
            if project.remote is not None:
                result["remote"] = project.remote.model_dump()

            # Feature 098: Include source_type, parent_project, branch_metadata, git_metadata
            result["source_type"] = project.source_type.value if hasattr(project, 'source_type') and project.source_type else "local"
            result["status"] = project.status.value if hasattr(project, 'status') and project.status else "active"

            # parent_project (nullable)
            if hasattr(project, 'parent_project') and project.parent_project:
                result["parent_project"] = project.parent_project

            # branch_metadata (nullable object)
            if hasattr(project, 'branch_metadata') and project.branch_metadata:
                result["branch_metadata"] = {
                    "number": project.branch_metadata.number,
                    "type": project.branch_metadata.type,
                    "full_name": project.branch_metadata.full_name,
                }

            # git_metadata (nullable object)
            if hasattr(project, 'git_metadata') and project.git_metadata:
                result["git_metadata"] = {
                    "branch": project.git_metadata.current_branch if hasattr(project.git_metadata, 'current_branch') else None,
                    "commit": project.git_metadata.commit_hash if hasattr(project.git_metadata, 'commit_hash') else None,
                    "is_clean": project.git_metadata.is_clean if hasattr(project.git_metadata, 'is_clean') else None,
                    "ahead": project.git_metadata.ahead_count if hasattr(project.git_metadata, 'ahead_count') else None,
                    "behind": project.git_metadata.behind_count if hasattr(project.git_metadata, 'behind_count') else None,
                }

            return result

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_update(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Update project metadata.

        Args:
            params: {
                "name": str,              # Project to update
                "directory": str = None,  # New directory (optional)
                "display_name": str = None,  # New display name (optional)
                "icon": str = None        # New icon (optional)
            }

        Returns:
            Updated project data

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
            VALIDATION_ERROR (1003): Invalid parameters
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get parameters
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            directory = params.get("directory")
            display_name = params.get("display_name")
            icon = params.get("icon")

            # Update project
            project = service.update(
                name=name,
                directory=directory,
                display_name=display_name,
                icon=icon
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params={"name": name}
            )

            result = {
                "name": project.name,
                "directory": project.directory,
                "display_name": project.display_name,
                "icon": project.icon,
                "created_at": project.created_at.isoformat(),
                "updated_at": project.updated_at.isoformat()
            }

            # Feature 087: Include remote configuration if present
            if project.remote is not None:
                result["remote"] = project.remote.model_dump()

            return result

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except ValueError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{VALIDATION_ERROR}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::update",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_delete(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Delete a project.

        Args:
            params: {"name": str}

        Returns:
            {"deleted": bool, "name": str}

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name
            name = params.get("name")
            if not name:
                raise ValueError("Missing required parameter: name")

            # Delete project
            deleted = service.delete(name)

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params={"name": name}
            )

            return {
                "deleted": deleted,
                "name": name
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::delete",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_get_active(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get currently active project.

        Args:
            params: {} (no parameters required)

        Returns:
            {"name": str | null}  # null if in global mode
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get active project
            active_name = service.get_active()

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::get_active",
                duration_ms=duration_ms,
                params={"active": active_name}
            )

            return {"name": active_name}

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::get_active",
                duration_ms=duration_ms,
                error=str(e)
            )
            raise

    async def _project_set_active(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Set active project (triggers window filtering).

        Args:
            params: {"name": str | null}  # null to clear (global mode)

        Returns:
            {
                "previous": str | null,
                "current": str | null,
                "filtering_applied": bool
            }

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
        """
        start_time = time.perf_counter()

        try:
            # Import ProjectService
            from .services.project_service import ProjectService
            config_dir = Path.home() / ".config" / "i3"
            service = ProjectService(config_dir, self.state_manager)

            # Get project name (can be None for global mode)
            name = params.get("name")
            if name is not None:
                normalized_name = str(name or "").strip()
                if not self._canonical_discovered_project_name(normalized_name):
                    raise FileNotFoundError(
                        f"Legacy non-worktree project activation is not supported: {normalized_name}"
                    )
                name = normalized_name

            # Set active project
            result = await service.set_active(name)

            # Feature 101: Also update/clear active-worktree.json
            worktree_context_file = config_dir / "active-worktree.json"
            if name is None:
                # Clear context file when going to global mode
                if worktree_context_file.exists():
                    worktree_context_file.unlink()
                    logger.info("Cleared active-worktree.json (global mode)")
                self._set_active_runtime_context(None)
            elif "/" in name and ":" in name:
                # Worktree qualified name - also update active-worktree.json
                from .repos_loader import find_worktree
                worktree = find_worktree(name)
                if worktree:
                    # Parse qualified name parts
                    from .worktree_utils import parse_qualified_name
                    parsed = parse_qualified_name(name)
                    repo_data = {
                        "account": parsed.account,
                        "name": parsed.repo,
                    }
                    worktree_data = {
                        "branch": parsed.branch,
                        "path": worktree.get("path", ""),
                    }
                    # Feature 137: Use atomic write to prevent corruption
                    context = self._build_active_worktree_context(
                        name,
                        parsed.repo_qualified_name,
                        repo_data,
                        worktree_data,
                    )
                    atomic_write_json(worktree_context_file, context)
                    self._set_active_runtime_context(context)
                    logger.info(f"[Feature 101] Updated active-worktree.json for {name}")

            # Trigger window filtering (Feature 037 integration)
            filtering_applied = False
            if self.workspace_tracker:
                try:
                    # Switch projects with filtering
                    old_project = result["previous"] or ""
                    new_project = result["current"]

                    if old_project or new_project:
                        filter_result = await self._switch_with_filtering({
                            "old_project": old_project,
                            "new_project": new_project or "",
                        })
                        filtering_applied = True
                        logger.info(
                            f"Window filtering applied: "
                            f"{filter_result.get('windows_hidden', 0)} hidden, "
                            f"{filter_result.get('windows_restored', 0)} restored"
                        )
                except Exception as e:
                    logger.warning(f"Window filtering failed (non-fatal): {e}")

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params={"name": name, "previous": result["previous"]}
            )

            return {
                "previous": result["previous"],
                "current": result["current"],
                "filtering_applied": filtering_applied
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params={"name": params.get("name")},
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::set_active",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    # Feature 098: Worktree environment integration methods
    # Feature 101: Updated to use repos.json as single source of truth
    async def _worktree_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List all worktree projects for a given parent repository.

        Feature 098: Worktree-Aware Project Environment Integration
        Feature 101: Uses repos.json as single source of truth

        Args:
            params: {
                "parent_project": str  # Qualified repo name (account/repo) or repo name
            }

        Returns:
            {
                "parent": {"name": str, "directory": str},
                "worktrees": [
                    {
                        "name": str,           # Full qualified name: account/repo:branch
                        "display_name": str,   # Branch name or formatted display
                        "directory": str,
                        "icon": str,
                        "status": str,
                        "branch_metadata": {"number": str?, "type": str?, "full_name": str},
                        "git_metadata": {...}
                    }
                ],
                "count": int
            }

        Raises:
            PROJECT_NOT_FOUND (1001): Parent repository doesn't exist
        """
        from pathlib import Path
        from .models.discovery import parse_branch_metadata

        start_time = time.perf_counter()

        try:
            parent_name = params.get("parent_project")
            if not parent_name:
                raise ValueError("parent_project parameter is required")

            # Feature 101: Load from repos.json
            repos_file = ConfigPaths.REPOS_FILE
            if not repos_file.exists():
                raise FileNotFoundError("repos.json not found. Run 'i3pm discover' first.")

            with open(repos_file) as f:
                repos_data = json.load(f)

            # Find the repository by qualified name (account/repo) or just repo name
            repo = None
            for r in repos_data.get("repositories", []):
                r_qualified = f"{r.get('account', '')}/{r.get('name', '')}"
                # Match by qualified name or just repo name
                if r_qualified == parent_name or r.get("name") == parent_name:
                    repo = r
                    break

            if not repo:
                raise FileNotFoundError(f"Repository not found: {parent_name}")

            repo_qualified = f"{repo.get('account', '')}/{repo.get('name', '')}"

            # Build worktree list from repos.json
            worktrees = []
            for wt in repo.get("worktrees", []):
                branch = wt.get("branch", "unknown")
                qualified_name = f"{repo_qualified}:{branch}"

                # Parse branch metadata
                branch_metadata = parse_branch_metadata(branch)

                # Create display name
                if branch_metadata and branch_metadata.number:
                    # Format: "098 - Description"
                    branch_desc = branch
                    if branch_desc.startswith(f"{branch_metadata.number}-"):
                        branch_desc = branch_desc[len(branch_metadata.number) + 1:]
                    display_name = f"{branch_metadata.number} - {branch_desc.replace('-', ' ').replace('_', ' ').title()}"
                else:
                    display_name = branch

                worktree_data = {
                    "name": qualified_name,
                    "display_name": display_name,
                    "directory": wt.get("path", ""),
                    "icon": "🌿",
                    "status": "active" if Path(wt.get("path", "")).exists() else "missing",
                }

                # Include branch_metadata
                if branch_metadata:
                    worktree_data["branch_metadata"] = {
                        "number": branch_metadata.number,
                        "type": branch_metadata.type,
                        "full_name": branch_metadata.full_name,
                    }

                # Include git_metadata from worktree entry (Feature 108: enhanced fields)
                worktree_data["git_metadata"] = {
                    "branch": branch,
                    "commit": wt.get("commit", ""),
                    "is_clean": wt.get("is_clean", True),
                    "ahead": wt.get("ahead", 0),
                    "behind": wt.get("behind", 0),
                    # Feature 108: Enhanced status fields
                    "is_merged": wt.get("is_merged", False),
                    "is_stale": wt.get("is_stale", False),
                    "has_conflicts": wt.get("has_conflicts", False),
                    "staged_count": wt.get("staged_count", 0),
                    "modified_count": wt.get("modified_count", 0),
                    "untracked_count": wt.get("untracked_count", 0),
                    "last_commit_timestamp": wt.get("last_commit_timestamp", 0),
                    "last_commit_message": wt.get("last_commit_message", ""),
                }

                worktrees.append(worktree_data)

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="worktree::list",
                duration_ms=duration_ms,
                params={"parent_project": parent_name, "count": len(worktrees)}
            )

            return {
                "parent": {
                    "name": repo_qualified,
                    "directory": repo.get("path", ""),
                },
                "worktrees": worktrees,
                "count": len(worktrees),
            }

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="worktree::list",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="worktree::list",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    async def _project_refresh(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Re-extract git and branch metadata for an existing project.

        Feature 098: Worktree-Aware Project Environment Integration (FR-009)

        Args:
            params: {
                "name": str  # Project name to refresh
            }

        Returns:
            {
                "success": bool,
                "project": {
                    "name": str,
                    "git_metadata": {...},
                    "branch_metadata": {...}
                },
                "fields_updated": list[str]
            }

        Raises:
            PROJECT_NOT_FOUND (1001): Project doesn't exist
            -32001: Directory missing
        """
        start_time = time.perf_counter()

        try:
            project_name = params.get("name")
            if not project_name:
                raise ValueError("name parameter is required")

            # Import required modules
            from .services.project_service import ProjectService
            from .services.discovery_service import extract_git_metadata
            from .models.discovery import parse_branch_metadata, SourceType

            config_dir = Path.home() / ".config" / "i3"
            project_service = ProjectService(config_dir, self.state_manager)

            # Get existing project
            project = project_service.get(project_name)

            # Check if directory exists
            if not Path(project.directory).exists():
                raise RuntimeError(
                    f"-32001:Cannot refresh project '{project_name}': "
                    f"directory does not exist at {project.directory}"
                )

            # Re-extract git metadata
            git_metadata = await extract_git_metadata(Path(project.directory))

            # Re-parse branch metadata if worktree and git metadata available
            branch_metadata = None
            if project.source_type == SourceType.WORKTREE and git_metadata:
                branch_metadata = parse_branch_metadata(git_metadata.current_branch)

            # Track which fields were updated
            fields_updated = ["updated_at"]
            if git_metadata:
                project.git_metadata = git_metadata
                fields_updated.append("git_metadata")
            if branch_metadata:
                project.branch_metadata = branch_metadata
                fields_updated.append("branch_metadata")

            # Update timestamp and save
            from datetime import datetime
            project.updated_at = datetime.now()
            project.save_to_file(config_dir)

            # Update in-memory state if available
            if project_name in self.state_manager.state.projects:
                self.state_manager.state.projects[project_name] = project

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::refresh",
                duration_ms=duration_ms,
                params={"name": project_name, "fields_updated": fields_updated}
            )

            # Build response
            result = {
                "success": True,
                "project": {
                    "name": project_name,
                },
                "fields_updated": fields_updated,
            }

            if git_metadata:
                result["project"]["git_metadata"] = {
                    "branch": git_metadata.current_branch,
                    "commit": git_metadata.commit_hash,
                    "is_clean": git_metadata.is_clean,
                    "ahead": git_metadata.ahead_count,
                    "behind": git_metadata.behind_count,
                }

            if branch_metadata:
                result["project"]["branch_metadata"] = {
                    "number": branch_metadata.number,
                    "type": branch_metadata.type,
                    "full_name": branch_metadata.full_name,
                }

            return result

        except FileNotFoundError as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::refresh",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise RuntimeError(f"{PROJECT_NOT_FOUND}:{str(e)}")

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::refresh",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            raise

    # Feature 097: Discovery methods
    async def _discover_projects(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Discover git repositories and create/update projects.

        Feature 097: Git-Based Project Discovery and Management

        Args:
            params: {
                "paths": list[str] | None,     # Override scan paths (optional)
                "exclude_patterns": list[str] | None,  # Override excludes (optional)
                "max_depth": int | None,       # Override max depth (optional)
                "dry_run": bool = False        # If true, don't create projects
            }

        Returns:
            {
                "repositories": list[dict],    # Discovered repositories
                "worktrees": list[dict],       # Discovered worktrees
                "skipped": list[dict],         # Skipped paths with reasons
                "errors": list[dict],          # Errors encountered
                "created": int,                # Projects created
                "updated": int,                # Projects updated
                "marked_missing": list[str],   # Projects marked as missing
                "duration_ms": float           # Total discovery time
            }
        """
        start_time = time.perf_counter()

        try:
            # Import discovery and project services
            from .services.discovery_service import discover_projects
            from .services.project_service import ProjectService
            from .models.discovery import ScanConfiguration
            from .config import load_discovery_config

            config_dir = Path.home() / ".config" / "i3"
            project_service = ProjectService(config_dir, self.state_manager)

            # Load default discovery config
            discovery_config_file = config_dir / "discovery-config.json"
            base_config = load_discovery_config(discovery_config_file)

            # Apply parameter overrides
            scan_paths = params.get("paths") or base_config.scan_paths
            exclude_patterns = params.get("exclude_patterns") or base_config.exclude_patterns
            max_depth = params.get("max_depth") or base_config.max_depth
            dry_run = params.get("dry_run", False)
            include_github = params.get("include_github", False)  # T044: GitHub integration

            # Create scan configuration
            scan_config = ScanConfiguration(
                scan_paths=scan_paths,
                exclude_patterns=exclude_patterns,
                max_depth=max_depth
            )

            # Get existing project names for conflict resolution
            existing_names = project_service.get_existing_names()

            # Run discovery
            discovery_result = await discover_projects(scan_config, existing_names)

            # T044: Optionally include GitHub repos
            github_repos = []
            remote_only = []
            if include_github:
                from .services.github_service import list_repos
                from .services.discovery_service import correlate_local_remote

                gh_result = await list_repos()
                if gh_result.success:
                    github_repos = gh_result.repos
                    correlation = correlate_local_remote(
                        discovery_result.repositories,
                        github_repos
                    )
                    remote_only = correlation.remote_only

            # Track statistics
            created_count = 0
            updated_count = 0
            created_projects = []
            updated_projects = []

            if not dry_run:
                # Create/update projects from discovered repositories
                for repo in discovery_result.repositories:
                    existing = project_service.find_by_directory(repo.path)
                    project = await project_service.create_or_update_from_discovery(repo)

                    if existing:
                        updated_count += 1
                        updated_projects.append(project.name)
                    else:
                        created_count += 1
                        created_projects.append(project.name)

                # Create/update projects from discovered worktrees
                for worktree in discovery_result.worktrees:
                    existing = project_service.find_by_directory(worktree.path)
                    project = await project_service.create_or_update_from_discovery(worktree)

                    if existing:
                        updated_count += 1
                        updated_projects.append(project.name)
                    else:
                        created_count += 1
                        created_projects.append(project.name)

                # T044: Create projects from remote-only GitHub repos
                for gh_repo in remote_only:
                    try:
                        project = await project_service.create_from_github_repo(gh_repo)
                        created_count += 1
                        created_projects.append(project.name)
                    except Exception as e:
                        logger.warning(
                            f"[Feature 097] Failed to create remote project {gh_repo.name}: {e}"
                        )

                # Mark missing projects
                marked_missing = await project_service.check_and_mark_missing_projects()
            else:
                marked_missing = []

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="project::discover",
                duration_ms=duration_ms,
                params={
                    "paths": scan_paths,
                    "dry_run": dry_run,
                    "repos_found": len(discovery_result.repositories),
                    "worktrees_found": len(discovery_result.worktrees)
                }
            )

            logger.info(
                f"[Feature 097] Discovery complete: "
                f"{len(discovery_result.repositories)} repos, "
                f"{len(discovery_result.worktrees)} worktrees, "
                f"{created_count} created, {updated_count} updated, "
                f"{len(marked_missing)} marked missing | "
                f"Duration: {duration_ms:.1f}ms"
            )

            # Feature 097 T027: Emit projects_discovered event (if not dry run)
            if not dry_run and (created_count > 0 or updated_count > 0 or len(marked_missing) > 0):
                await self.broadcast_event({
                    "type": "projects_discovered",
                    "created": created_count,
                    "updated": updated_count,
                    "created_projects": created_projects,
                    "updated_projects": updated_projects,
                    "marked_missing": marked_missing,
                    "repositories_found": len(discovery_result.repositories),
                    "worktrees_found": len(discovery_result.worktrees),
                    "duration_ms": duration_ms
                })

            # Build response
            return {
                "repositories": [
                    {
                        "name": r.name,
                        "path": r.path,
                        "is_worktree": r.is_worktree,
                        "inferred_icon": r.inferred_icon,
                        "git_metadata": r.git_metadata.model_dump() if r.git_metadata else None
                    }
                    for r in discovery_result.repositories
                ],
                "worktrees": [
                    {
                        "name": w.name,
                        "path": w.path,
                        "parent_path": w.parent_path,
                        "branch": w.branch,
                        "inferred_icon": w.inferred_icon,
                        "git_metadata": w.git_metadata.model_dump() if w.git_metadata else None
                    }
                    for w in discovery_result.worktrees
                ],
                "skipped": [
                    {"path": s.path, "reason": s.reason}
                    for s in discovery_result.skipped
                ],
                "errors": [
                    {"path": e.path, "error_type": e.error_type, "message": e.message}
                    for e in discovery_result.errors
                ],
                "created": created_count,
                "updated": updated_count,
                "created_projects": created_projects,
                "updated_projects": updated_projects,
                "marked_missing": marked_missing,
                "duration_ms": duration_ms,
                "dry_run": dry_run
            }

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="project::discover",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            logger.error(f"[Feature 097] Discovery failed: {e}")
            raise RuntimeError(f"{INTERNAL_ERROR}:Discovery failed: {str(e)}")

    async def _list_github_repos(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List GitHub repositories using gh CLI.

        Feature 097 T042: List GitHub repos for discovery workflow.

        Args:
            params: {
                "limit": int = 100,             # Max repos to fetch
                "include_private": bool = True,  # Include private repos
                "include_forks": bool = True,    # Include forked repos
                "include_archived": bool = False # Include archived repos
            }

        Returns:
            {
                "success": bool,
                "repos": list[dict],
                "total_count": int,
                "errors": list[dict]
            }
        """
        start_time = time.perf_counter()

        try:
            from .services.github_service import list_repos

            limit = params.get("limit", 100)
            include_private = params.get("include_private", True)
            include_forks = params.get("include_forks", True)
            include_archived = params.get("include_archived", False)

            result = await list_repos(
                limit=limit,
                include_private=include_private,
                include_forks=include_forks,
                include_archived=include_archived
            )

            duration_ms = (time.perf_counter() - start_time) * 1000

            await self._log_ipc_event(
                event_type="github::list_repos",
                duration_ms=duration_ms,
                params={"limit": limit, "count": len(result.repos)}
            )

            return {
                "success": result.success,
                "repos": [
                    {
                        "name": r.name,
                        "full_name": r.full_name,
                        "description": r.description,
                        "clone_url": r.clone_url,
                        "ssh_url": r.ssh_url,
                        "is_private": r.is_private,
                        "is_fork": r.is_fork,
                        "is_archived": r.is_archived,
                        "primary_language": r.primary_language,
                        "pushed_at": r.pushed_at.isoformat() if r.pushed_at else None,
                        "has_local_clone": r.has_local_clone,
                        "local_project_name": r.local_project_name
                    }
                    for r in result.repos
                ],
                "total_count": result.total_count,
                "errors": [
                    {"path": e.path, "error_type": e.error_type, "message": e.message}
                    for e in result.errors
                ]
            }

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="github::list_repos",
                duration_ms=duration_ms,
                params=params,
                error=str(e)
            )
            logger.error(f"[Feature 097] GitHub list failed: {e}")
            raise RuntimeError(f"{INTERNAL_ERROR}:GitHub list failed: {str(e)}")

    async def _get_discovery_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get current discovery configuration.

        Feature 097 T060: Get discovery config for CLI display/editing.

        Returns:
            {
                "scan_paths": list[str],
                "exclude_patterns": list[str],
                "auto_discover_on_startup": bool,
                "max_depth": int
            }
        """
        from .config import load_discovery_config
        from pathlib import Path

        config_file = Path.home() / ".config" / "i3" / "discovery-config.json"
        config = load_discovery_config(config_file)

        return {
            "scan_paths": config.scan_paths,
            "exclude_patterns": config.exclude_patterns,
            "auto_discover_on_startup": config.auto_discover_on_startup,
            "max_depth": config.max_depth
        }

    async def _update_discovery_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Update discovery configuration.

        Feature 097 T061: Update discovery config from CLI.

        Args:
            params: {
                "scan_paths": list[str] (optional),
                "exclude_patterns": list[str] (optional),
                "auto_discover_on_startup": bool (optional),
                "max_depth": int (optional),
                "add_path": str (optional) - add single path,
                "remove_path": str (optional) - remove single path
            }

        Returns:
            {"success": bool, "config": dict}
        """
        import json
        from pathlib import Path
        from .config import load_discovery_config
        from .models.discovery import ScanConfiguration

        config_file = Path.home() / ".config" / "i3" / "discovery-config.json"
        current_config = load_discovery_config(config_file)

        # Build updated values
        scan_paths = list(current_config.scan_paths)
        exclude_patterns = list(current_config.exclude_patterns)
        auto_discover = current_config.auto_discover_on_startup
        max_depth = current_config.max_depth

        # Apply updates
        if "scan_paths" in params:
            scan_paths = params["scan_paths"]
        if "exclude_patterns" in params:
            exclude_patterns = params["exclude_patterns"]
        if "auto_discover_on_startup" in params:
            auto_discover = params["auto_discover_on_startup"]
        if "max_depth" in params:
            max_depth = params["max_depth"]

        # Handle add_path/remove_path
        if "add_path" in params:
            path = params["add_path"]
            if path not in scan_paths:
                scan_paths.append(path)
        if "remove_path" in params:
            path = params["remove_path"]
            if path in scan_paths:
                scan_paths.remove(path)

        # Validate with Pydantic
        new_config = ScanConfiguration(
            scan_paths=scan_paths,
            exclude_patterns=exclude_patterns,
            auto_discover_on_startup=auto_discover,
            max_depth=max_depth
        )

        # Save to file - Feature 137: Use atomic write to prevent corruption
        atomic_write_json(config_file, new_config.model_dump())

        logger.info(f"[Feature 097] Updated discovery config: {len(scan_paths)} paths, auto_discover={auto_discover}")

        return {
            "success": True,
            "config": new_config.model_dump()
        }

    async def _refresh_git_metadata(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Refresh git metadata for a project or all projects.

        Feature 097 T062: Refresh git status without full re-discovery.

        Args:
            params: {
                "project_name": str (optional) - specific project, or None for all
            }

        Returns:
            {"refreshed_count": int, "errors": list[str]}
        """
        from pathlib import Path
        from .services.discovery_service import extract_git_metadata
        from .services.project_service import ProjectService

        start_time = time.perf_counter()

        project_service = ProjectService(
            config_dir=Path.home() / ".config" / "i3",
            state_manager=self.state_manager
        )

        project_name = params.get("project_name")
        refreshed_count = 0
        errors = []

        if project_name:
            # Refresh single project
            try:
                project = project_service.get(project_name)
                if project.source_type in ["local", "worktree"]:
                    git_meta = await extract_git_metadata(project.directory)
                    if git_meta:
                        project.git_metadata = git_meta
                        project.save_to_file(project_service.config_dir)
                        refreshed_count = 1
                else:
                    errors.append(f"Project {project_name} is not a local/worktree project")
            except FileNotFoundError:
                errors.append(f"Project {project_name} not found")
            except Exception as e:
                errors.append(f"Failed to refresh {project_name}: {str(e)}")
        else:
            # Refresh all local/worktree projects
            for project in project_service.list():
                if project.source_type in ["local", "worktree"]:
                    try:
                        git_meta = await extract_git_metadata(project.directory)
                        if git_meta:
                            project.git_metadata = git_meta
                            project.save_to_file(project_service.config_dir)
                            refreshed_count += 1
                    except Exception as e:
                        errors.append(f"Failed to refresh {project.name}: {str(e)}")

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.info(f"[Feature 097] Refreshed git metadata: {refreshed_count} projects in {duration_ms:.1f}ms")

        return {
            "refreshed_count": refreshed_count,
            "errors": errors,
            "duration_ms": duration_ms
        }

    def _read_active_worktree_context(self) -> Optional[Dict[str, Any]]:
        """Read active-worktree context from disk."""
        path = ConfigPaths.ACTIVE_WORKTREE_FILE
        if not path.exists():
            return None
        try:
            with open(path) as f:
                data = json.load(f)
            if isinstance(data, dict):
                qualified_name = str(data.get("qualified_name") or "").strip()
                local_directory = str(data.get("local_directory") or data.get("path") or "").strip()
                if self._canonical_discovered_project_name(qualified_name) and discovered_worktree_matches_path(
                    qualified_name,
                    local_directory,
                ):
                    return data
                path.unlink(missing_ok=True)
                logger.info("Cleared stale active-worktree context for %s", qualified_name or "<empty>")
        except Exception as e:
            logger.debug(f"Failed to read active-worktree context: {e}")
        return None

    def _set_active_runtime_context(self, context: Optional[Dict[str, Any]]) -> None:
        """Persist the daemon-owned active runtime context in memory."""
        if isinstance(context, dict) and str(context.get("qualified_name") or "").strip():
            self._active_runtime_context = dict(context)
        else:
            self._active_runtime_context = None

    def _get_active_runtime_context(
        self,
        *,
        active_project: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        """Return the canonical daemon-owned active runtime context.

        Falls back to the persisted file only to rehydrate daemon memory, and only when
        the persisted qualified_name matches the daemon's active project.
        """
        expected_project = str(
            active_project
            if active_project is not None
            else (self.state_manager.state.active_project or "")
        ).strip()

        in_memory = self._active_runtime_context
        if isinstance(in_memory, dict) and str(in_memory.get("qualified_name") or "").strip():
            memory_project = str(in_memory.get("qualified_name") or "").strip()
            if expected_project and memory_project != expected_project:
                logger.warning(
                    "Discarding mismatched in-memory active context '%s' (expected '%s')",
                    memory_project,
                    expected_project,
                )
                self._active_runtime_context = None
            else:
                return dict(in_memory)

        persisted = self._read_active_worktree_context()
        if isinstance(persisted, dict) and str(persisted.get("qualified_name") or "").strip():
            persisted_project = str(persisted.get("qualified_name") or "").strip()
            if expected_project and persisted_project != expected_project:
                logger.warning(
                    "Ignoring mismatched persisted active context '%s' (expected '%s')",
                    persisted_project,
                    expected_project,
                )
                return None
            self._active_runtime_context = dict(persisted)
            return dict(persisted)

        return None

    def _build_active_context_response(
        self,
        active_context: Optional[Dict[str, Any]],
        *,
        active_project: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Build a canonical context payload for runtime consumers."""
        local_host = self._local_host_alias()
        local_connection_key = self._normalize_connection_key(f"local@{local_host}")
        base = {
            "qualified_name": "",
            "project_name": "",
            "directory": "",
            "local_directory": "",
            "target_host": "global",
            "transport_kind": "global",
            "connection_key": "global",
            "identity_key": "global",
            "context_key": "",
            "host_profile_configured": False,
            "host_profile": None,
            "is_global": True,
            "active_project": str(active_project or "").strip(),
        }

        if isinstance(active_context, dict) and active_context.get("qualified_name"):
            payload = dict(base)
            payload.update({
                "qualified_name": str(active_context.get("qualified_name") or "").strip(),
                "project_name": str(active_context.get("qualified_name") or "").strip(),
                "directory": str(active_context.get("directory") or "").strip(),
                "local_directory": str(
                    active_context.get("local_directory")
                    or active_context.get("directory")
                    or ""
                ).strip(),
                "target_host": self._target_host_from_context_payload(
                    active_context,
                    project_name=str(active_context.get("qualified_name") or ""),
                ),
                "transport_kind": str(active_context.get("transport_kind") or "").strip(),
                "connection_key": str(active_context.get("connection_key") or "").strip(),
                "identity_key": str(active_context.get("identity_key") or "").strip(),
                "context_key": str(active_context.get("context_key") or "").strip(),
                "host_profile": active_context.get("host_profile"),
                "host_profile_configured": bool(
                    isinstance(active_context.get("host_profile"), dict)
                    and active_context["host_profile"].get("enabled", False)
                ),
                "is_global": False,
            })
            if payload["target_host"] == "global":
                payload["target_host"] = local_host
            if payload["transport_kind"] not in {"local_process", "ssh_helper"}:
                payload["transport_kind"] = self._transport_kind_for_target_host(payload["target_host"])
            if not payload["connection_key"]:
                payload["connection_key"] = (
                    self._connection_key_for_target_host(
                        target_host=payload["target_host"],
                        host_profile=payload["host_profile"] if isinstance(payload["host_profile"], dict) else None,
                    )
                    if payload["target_host"] != "global"
                    else local_connection_key
                )
            if not payload["identity_key"]:
                payload["identity_key"] = f'host:{payload["target_host"]}'
            if not payload["context_key"] and payload["qualified_name"]:
                payload["context_key"] = self._build_target_context_key(
                    payload["qualified_name"],
                    payload["target_host"],
                )
            payload["active_project"] = payload["qualified_name"]
            return payload

        if active_project:
            identity = self._build_worktree_context_identity(
                str(active_project),
                None,
                target_host=local_host,
            )
            return {
                **base,
                "qualified_name": str(active_project),
                "project_name": str(active_project),
                "target_host": identity["target_host"],
                "transport_kind": identity["transport_kind"],
                "connection_key": identity["connection_key"],
                "identity_key": identity["identity_key"],
                "context_key": identity["context_key"],
                "is_global": False,
                "active_project": str(active_project),
            }

        return base

    @staticmethod
    def _sway_command_succeeded(result: Any) -> bool:
        """Return true if any sway command reply indicates success."""
        if isinstance(result, list):
            for reply in result:
                success = getattr(reply, "success", None)
                if success is None and isinstance(reply, dict):
                    success = reply.get("success")
                if success is True:
                    return True
        return False

    async def _sway_ipc_command(self, command: str) -> Any:
        """Run a Sway IPC command through the available connection wrapper."""
        if not self.i3_connection:
            raise RuntimeError("Sway connection is unavailable")
        ipc_command = getattr(self.i3_connection, "ipc_command", None)
        if callable(ipc_command):
            return await ipc_command(command)
        conn = getattr(self.i3_connection, "conn", None)
        conn_command = getattr(conn, "command", None)
        if callable(conn_command):
            return await conn_command(command)
        raise RuntimeError("Sway command interface is unavailable")

    async def _sway_get_workspaces(self) -> Any:
        """Read Sway workspaces through the available connection wrapper."""
        if not self.i3_connection:
            raise RuntimeError("Sway connection is unavailable")
        get_workspaces = getattr(self.i3_connection, "get_workspaces", None)
        if callable(get_workspaces):
            return await get_workspaces()
        conn = getattr(self.i3_connection, "conn", None)
        conn_get_workspaces = getattr(conn, "get_workspaces", None)
        if callable(conn_get_workspaces):
            return await conn_get_workspaces()
        raise RuntimeError("Sway workspace interface is unavailable")

    def _find_tree_node_by_id(self, node: Any, target_id: int) -> Optional[Any]:
        """Recursively walk a Sway tree node to find a container by id."""
        if getattr(node, "id", None) == target_id:
            return node
        for child in list(getattr(node, "nodes", []) or []):
            match = self._find_tree_node_by_id(child, target_id)
            if match is not None:
                return match
        for child in list(getattr(node, "floating_nodes", []) or []):
            match = self._find_tree_node_by_id(child, target_id)
            if match is not None:
                return match
        return None

    @staticmethod
    def _container_is_in_scratchpad(container: Any) -> bool:
        """Return whether a container is currently attached to the scratchpad tree."""
        parent = container
        while parent:
            scratchpad_state = str(getattr(parent, "scratchpad_state", "") or "").strip().lower()
            if scratchpad_state and scratchpad_state != "none":
                return True
            parent = getattr(parent, "parent", None)
        return False

    @staticmethod
    def _workspace_switch_command(workspace_name: str) -> str:
        """Build a safe workspace switch command for an arbitrary workspace name."""
        return f"workspace {shlex_quote(str(workspace_name or '').strip())}"

    async def _get_window_transition_state(self, window_id: int) -> Dict[str, Any]:
        """Return live and tracked state used to plan a focus transition."""
        empty_state = {
            "exists": False,
            "window_id": int(window_id or 0),
            "current_workspace": "",
            "workspace_name": "",
            "workspace_number": 0,
            "in_scratchpad": False,
            "floating": False,
            "floating_state": "",
            "fullscreen_mode": 0,
            "geometry": None,
            "saved_state": None,
            "node": None,
        }
        if not self.i3_connection or not getattr(self.i3_connection, "conn", None):
            return empty_state

        try:
            tree = await self.i3_connection.get_tree()
            focused = self._find_focused_tree_node(tree)
            current_workspace = ""
            if focused is not None:
                focused_workspace = focused.workspace()
                current_workspace = str(getattr(focused_workspace, "name", "") or "").strip()

            node = self._find_tree_node_by_id(tree, int(window_id or 0))
            if node is None:
                return empty_state

            workspace = node.workspace()
            workspace_name = str(getattr(workspace, "name", "") or "").strip()
            workspace_number = int(getattr(workspace, "num", 0) or 0) if workspace is not None else 0
            floating_state = str(getattr(node, "floating", "") or "").strip().lower()
            floating = bool(floating_state and not floating_state.endswith("_off"))
            fullscreen_mode = int(getattr(node, "fullscreen_mode", 0) or 0)
            geometry = None
            rect = getattr(node, "rect", None)
            if rect is not None:
                geometry = {
                    "x": int(getattr(rect, "x", 0) or 0),
                    "y": int(getattr(rect, "y", 0) or 0),
                    "width": int(getattr(rect, "width", 0) or 0),
                    "height": int(getattr(rect, "height", 0) or 0),
                }

            saved_state = None
            if self.workspace_tracker:
                try:
                    saved_state = await self.workspace_tracker.get_window_workspace(int(window_id or 0))
                except Exception as e:
                    logger.debug("Failed to load tracked window state for %s: %s", window_id, e)

            return {
                "exists": True,
                "window_id": int(window_id or 0),
                "current_workspace": current_workspace,
                "workspace_name": workspace_name,
                "workspace_number": workspace_number,
                "in_scratchpad": bool(
                    workspace_name == "__i3_scratch" or self._container_is_in_scratchpad(node)
                ),
                "floating": floating,
                "floating_state": floating_state,
                "fullscreen_mode": fullscreen_mode,
                "geometry": geometry,
                "saved_state": saved_state if isinstance(saved_state, dict) else None,
                "node": node,
            }
        except Exception as e:
            logger.debug("Failed to inspect transition state for window %s: %s", window_id, e)
            return empty_state

    def _build_window_focus_transition(
        self,
        *,
        window_id: int,
        state: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Plan the commands and expected final state for focusing a window."""
        selector = f"[con_id={int(window_id)}]"
        saved_state = dict(state.get("saved_state") or {})
        saved_workspace_number = int(saved_state.get("workspace_number") or 0)
        saved_original_scratchpad = bool(saved_state.get("original_scratchpad", False))
        live_workspace_name = str(state.get("workspace_name") or "").strip()
        current_workspace = str(state.get("current_workspace") or "").strip()
        in_scratchpad = bool(state.get("in_scratchpad", False))

        expected_workspace_name = live_workspace_name
        expected_workspace_number = int(state.get("workspace_number") or 0)
        if in_scratchpad and saved_workspace_number > 0 and not saved_original_scratchpad:
            expected_workspace_number = saved_workspace_number
            expected_workspace_name = str(saved_workspace_number)

        if in_scratchpad and not saved_original_scratchpad:
            # Window was tiled before being hidden to scratchpad by the window filter.
            # The saved floating=True is an artifact of scratchpad state — default to tiled.
            expected_floating = False
        else:
            expected_floating = bool(
                saved_state.get("floating", state.get("floating", False))
            )
        expected_fullscreen_mode = int(
            saved_state.get("fullscreen_mode", state.get("fullscreen_mode", 0)) or 0
        )
        expected_geometry = saved_state.get("geometry")
        if not isinstance(expected_geometry, dict):
            expected_geometry = state.get("geometry") if expected_floating else None

        commands: List[str] = []
        if in_scratchpad:
            # Use deterministic 'move to workspace' instead of toggling 'scratchpad show'
            # to avoid race with the window filter which may have already shown the window.
            if expected_workspace_number > 0:
                commands.append(f"workspace number {expected_workspace_number}")
                commands.append(f"{selector} move workspace number {expected_workspace_number}")
            else:
                commands.append(f"{selector} move workspace current")
            if expected_floating:
                commands.append(f"{selector} floating enable")
                if expected_geometry:
                    commands.append(
                        f"{selector} resize set {expected_geometry['width']} px {expected_geometry['height']} px"
                    )
                    commands.append(
                        f"{selector} move position {expected_geometry['x']} px {expected_geometry['y']} px"
                    )
            else:
                commands.append(f"{selector} floating disable")
            if expected_fullscreen_mode > 0:
                commands.append(f"{selector} fullscreen enable")
        else:
            if expected_workspace_name and expected_workspace_name != current_workspace:
                commands.append(self._workspace_switch_command(expected_workspace_name))
            if expected_floating:
                if expected_geometry:
                    commands.extend(CommandBatch.from_window_state(
                        window_id=int(window_id),
                        workspace_num=max(expected_workspace_number, 1),
                        is_floating=True,
                        geometry=expected_geometry,
                        fullscreen_mode=expected_fullscreen_mode,
                    ).to_batched_command().split("; "))
                else:
                    commands.append(f"{selector} floating enable")
                    if expected_fullscreen_mode > 0:
                        commands.append(f"{selector} fullscreen enable")
            else:
                if str(state.get("floating_state") or "").strip():
                    commands.append(f"{selector} floating disable")
                if int(state.get("fullscreen_mode") or 0) > 0 and expected_fullscreen_mode <= 0:
                    commands.append(f"{selector} fullscreen disable")
                elif expected_fullscreen_mode > 0:
                    commands.append(f"{selector} fullscreen enable")

        commands.append(f"{selector} focus")

        transition_kind = "scratchpad_restore" if in_scratchpad else (
            "workspace_switch" if expected_workspace_name and expected_workspace_name != current_workspace else "direct_focus"
        )
        return {
            "kind": transition_kind,
            "commands": commands,
            "expected": {
                "window_id": int(window_id),
                "in_scratchpad": False,
                "floating": expected_floating,
                "fullscreen_mode": expected_fullscreen_mode,
                "workspace_name": expected_workspace_name,
                "workspace_number": expected_workspace_number,
            },
        }

    async def _window_matches_transition_target(self, expected: Dict[str, Any]) -> bool:
        """Verify the focused window converged to the planned visible state."""
        state = await self._get_window_transition_state(int(expected.get("window_id") or 0))
        if not bool(state.get("exists", False)):
            return False
        if bool(state.get("in_scratchpad", False)) != bool(expected.get("in_scratchpad", False)):
            return False
        if bool(state.get("floating", False)) != bool(expected.get("floating", False)):
            return False
        return int(state.get("fullscreen_mode", 0) or 0) == int(expected.get("fullscreen_mode", 0) or 0)

    async def _is_window_in_regular_state(self, window_id: int) -> bool:
        """Check whether a container is focused as a normal tiled window."""
        if not self.i3_connection or not getattr(self.i3_connection, "conn", None):
            return False
        try:
            tree = await self.i3_connection.get_tree()
            node = self._find_tree_node_by_id(tree, int(window_id))
            if node is None:
                return False
            fullscreen_raw = getattr(node, "fullscreen_mode", -1)
            fullscreen_mode = -1 if fullscreen_raw is None else int(fullscreen_raw)
            floating_state = str(getattr(node, "floating", "") or "").strip().lower()
            return fullscreen_mode == 0 and (
                not floating_state or floating_state.endswith("_off")
            )
        except Exception as e:
            logger.debug("Failed to inspect window %s state: %s", window_id, e)
            return False

    async def _send_tick_barrier(self, payload: str) -> None:
        """Flush pending Sway command effects before continuing."""
        if not self.i3_connection or not getattr(self.i3_connection, "conn", None):
            return
        try:
            await self.i3_connection.conn.send_tick(payload)
        except Exception as e:
            logger.debug("Tick barrier failed for %s: %s", payload, e)

    @staticmethod
    def _extract_json_payload(raw_output: str) -> Optional[Any]:
        """Extract a JSON object or array from stdout that may include shell noise."""
        payload = str(raw_output or "").strip()
        if not payload:
            return None

        candidate_indexes = [index for index in (payload.find("{"), payload.find("[")) if index >= 0]
        if candidate_indexes:
            try:
                return json.loads(payload[min(candidate_indexes):])
            except Exception:
                pass

        for line in reversed(payload.splitlines()):
            stripped = str(line or "").strip()
            if not stripped or stripped[0] not in {"{", "["}:
                continue
            try:
                return json.loads(stripped)
            except Exception:
                continue

        return None

    async def _remote_daemon_request(
        self,
        *,
        connection_key: str,
        method: str,
        params: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Execute a daemon JSON-RPC call on a remote host over SSH."""
        remote_user, remote_host, remote_port = self._parse_remote_target("", connection_key)
        if not remote_host:
            return {
                "success": False,
                "reason": "missing_remote_target",
                "remote_host": "",
                "remote_port": 22,
                "stdout": "",
                "stderr": "",
                "result": None,
            }

        resolved_user = remote_user or str(os.environ.get("USER") or "").strip() or "vpittamp"
        payload = json.dumps(params or {}, separators=(",", ":"), sort_keys=True)
        remote_script = (
            f"i3pm daemon call {shlex.quote(method)} "
            f"--params-json {shlex.quote(payload)} --json"
        )
        remote_command = f"bash -lc {shlex.quote(remote_script)}"
        from .subprocess_utils import run_command
        result = await run_command(
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=3",
            "-p",
            str(remote_port),
            f"{resolved_user}@{remote_host}" if resolved_user else remote_host,
            remote_command,
            timeout=15.0,
        )

        parsed = self._extract_json_payload(str(result.stdout or ""))
        transport_success = result.returncode == 0
        remote_success = transport_success and parsed is not None
        if isinstance(parsed, dict) and "success" in parsed:
            remote_success = remote_success and bool(parsed.get("success", False))

        reason = "ok"
        if not transport_success:
            reason = "remote_transport_failed"
        elif parsed is None:
            reason = "invalid_remote_response"
        elif isinstance(parsed, dict) and not bool(parsed.get("success", True)):
            reason = str(parsed.get("reason") or parsed.get("error") or "remote_call_failed")

        return {
            "success": remote_success,
            "reason": reason,
            "remote_user": resolved_user,
            "remote_host": remote_host,
            "remote_port": remote_port,
            "stdout": str(result.stdout or "").strip(),
            "stderr": str(result.stderr or "").strip(),
            "result": parsed,
        }

    def _find_focused_tree_node(self, node: Any) -> Optional[Any]:
        """Recursively find the currently focused tree node."""
        if bool(getattr(node, "focused", False)):
            return node
        for child in list(getattr(node, "nodes", []) or []):
            match = self._find_focused_tree_node(child)
            if match is not None:
                return match
        for child in list(getattr(node, "floating_nodes", []) or []):
            match = self._find_focused_tree_node(child)
            if match is not None:
                return match
        return None

    async def _focused_window_id(self) -> int:
        """Return the currently focused Sway container id."""
        if not self.i3_connection or not getattr(self.i3_connection, "conn", None):
            return 0
        try:
            tree = await self.i3_connection.get_tree()
            node = self._find_focused_tree_node(tree)
            return int(getattr(node, "id", 0) or 0) if node is not None else 0
        except Exception as e:
            logger.debug("Failed to resolve focused window id: %s", e)
            return 0

    async def _verify_window_focus(self, window_id: int) -> Dict[str, Any]:
        """Verify that the requested window owns current Sway focus."""
        focused_window_id = await self._focused_window_id()
        success = int(focused_window_id or 0) == int(window_id or 0)
        return {
            "success": success,
            "window_id": int(window_id or 0),
            "focused_window_id": int(focused_window_id or 0),
            "reason": "ok" if success else "focused_window_mismatch",
        }

    async def _switch_runtime_context_if_needed(
        self,
        project_name: str,
        target_host: str,
        connection_key: str = "",
    ) -> Dict[str, Any]:
        """Align daemon runtime context before a focus/action request."""
        active = await self._context_get_active({})
        current_project = str(active.get("qualified_name") or "global").strip() or "global"
        current_target_host = self._target_host_from_context_payload(active, project_name=current_project)
        current_connection_key = self._normalize_connection_key(str(active.get("connection_key") or "").strip())
        desired_project = str(project_name or "").strip()
        desired_target_host = self._resolve_requested_target_host(target_host, project_name=desired_project)
        desired_connection_key = self._normalize_connection_key(str(connection_key or "").strip())
        if not desired_project:
            desired_project = current_project

        needs_switch = desired_project != current_project
        if desired_project != "global" and desired_target_host != current_target_host:
            needs_switch = True
        if desired_connection_key and desired_connection_key != current_connection_key:
            needs_switch = True
        if not needs_switch:
            return {"switched": False, "context": active}

        if desired_project == "global":
            await self._worktree_clear({})
        else:
            await self._worktree_switch({
                "qualified_name": desired_project,
                "target_host": desired_target_host,
            })
        await self._send_tick_barrier(
            f"i3pm:context-switch:{desired_project}:{desired_target_host or 'auto'}"
        )
        return {"switched": True, "context": await self._context_get_active({})}

    async def _window_focus_fast(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Low-latency local window focus path for click-driven UI actions."""
        return await self.focus_service.focus_window_fast(params)

    async def _focus_window_impl(
        self,
        *,
        window_id: int,
        project_name: str = "",
        target_variant: str = "",
        connection_key: str = "",
        attempts: int = 3,
        delay_s: float = 0.12,
    ) -> Dict[str, Any]:
        """Project-aware focus flow owned by the daemon."""
        return await self.focus_service.focus_window(
            window_id=window_id,
            project_name=project_name,
            target_variant=target_variant,
            connection_key=connection_key,
            attempts=attempts,
            delay_s=delay_s,
        )

    async def _window_focus(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a managed window through the daemon-owned runtime path."""
        window_id = int(params.get("window_id") or 0)
        if window_id <= 0:
            raise ValueError("window_id must be a positive integer")
        return await self._focus_window_impl(
            window_id=window_id,
            project_name=str(params.get("project_name") or "").strip(),
            target_variant=str(params.get("target_variant") or "").strip().lower(),
            connection_key=str(params.get("connection_key") or "").strip(),
            attempts=int(params.get("attempts") or 3),
            delay_s=float(params.get("delay_s") or 0.12),
        )

    async def _window_action(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a deterministic daemon-owned action against a window."""
        return await self.focus_service.window_action(params)

    async def _runtime_snapshot(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return a compact daemon-owned runtime snapshot for UI consumers."""
        params = params or {}
        tree_result = await self._get_window_tree(params)
        active_context = await self._context_get_active({})
        tracked_windows = await self.state_manager.get_window_map_snapshot()
        outputs = tree_result.get("outputs", []) if isinstance(tree_result, dict) else []
        visible_windows_by_id: Dict[int, Dict[str, Any]] = {}
        if isinstance(tree_result, dict):
            for window in self._flatten_runtime_windows(tree_result):
                if not isinstance(window, dict):
                    continue
                window_id = int(window.get("id") or 0)
                if window_id <= 0:
                    continue
                visible_windows_by_id[window_id] = dict(window)
        active_outputs = [
            output.get("name")
            for output in outputs
            if isinstance(output, dict) and output.get("active") and output.get("name")
        ]

        scratchpad_summary: Dict[str, Any] = {
            "available": False,
            "count": 0,
            "context_key": str(active_context.get("context_key") or ""),
        }
        if self.scratchpad_manager:
            try:
                scratchpad_status = await self._scratchpad_status(
                    {"context_key": active_context.get("context_key") or ""}
                )
                terminals = scratchpad_status.get("terminals", [])
                scratchpad_summary = {
                    "available": bool(terminals),
                    "count": int(scratchpad_status.get("count", 0) or 0),
                    "context_key": str(
                        scratchpad_status.get("context_key")
                        or active_context.get("context_key")
                        or ""
                    ),
                    "terminal": terminals[0] if terminals else None,
                }
            except Exception as e:
                logger.debug("runtime.snapshot scratchpad status failed: %s", e)

        tracked_window_list = []
        ssh_tracked_window_count = 0
        scoped_tracked_window_count = 0
        for window_info in tracked_windows.values():
            app_key = str(getattr(window_info, "app_identifier", "") or "")
            window_class = str(getattr(window_info, "window_class", "") or "")
            window_instance = str(getattr(window_info, "window_instance", "") or "")
            window_id = int(getattr(window_info, "window_id", 0) or 0)
            visible_window = visible_windows_by_id.get(window_id, {})
            tracked_binding_state = str(getattr(window_info, "binding_state", "") or "").strip()
            tracked_last_workspace = str(getattr(window_info, "last_workspace", "") or "").strip()
            tracked_last_output = str(getattr(window_info, "last_output", "") or "").strip()
            scope = str(
                visible_window.get("scope")
                or getattr(window_info, "scope", "")
                or "global"
            )
            if visible_window:
                binding_state = "scratchpad_hidden" if bool(visible_window.get("hidden", False)) else "bound_workspace"
            else:
                binding_state = tracked_binding_state or "transient_unbound"
            hidden = binding_state == "scratchpad_hidden"
            visible = binding_state != "scratchpad_hidden"
            icon_path = self._resolve_window_icon_path(
                app_key=str(visible_window.get("app_key") or app_key or ""),
                app_id=visible_window.get("app_id") or app_key,
                window_class=window_class,
                window_instance=window_instance,
                allow_fallback=(not app_key or app_key == window_class),
            )
            if str(getattr(window_info, "execution_mode", "") or "") == "ssh":
                ssh_tracked_window_count += 1
            if scope == "scoped":
                scoped_tracked_window_count += 1
            tracked_window_list.append(
                {
                    "window_id": window_id,
                    "con_id": int(getattr(window_info, "con_id", 0) or 0),
                    "project": str(visible_window.get("project") or getattr(window_info, "project", "") or ""),
                    "scope": scope,
                    "workspace": str(
                        visible_window.get("workspace")
                        or getattr(window_info, "workspace", "")
                        or tracked_last_workspace
                        or ""
                    ),
                    "output": str(
                        visible_window.get("output")
                        or getattr(window_info, "output", "")
                        or tracked_last_output
                        or ""
                    ),
                    "title": str(
                        visible_window.get("title")
                        or getattr(window_info, "window_title", "")
                        or "(untitled)"
                    ),
                    "window_class": window_class,
                    "app_key": str(visible_window.get("app_key") or app_key or ""),
                    "app_name": str(visible_window.get("app_name") or app_key or window_class or "window"),
                    "icon_path": icon_path,
                    "marks": list(getattr(window_info, "marks", []) or []),
                    "target_host": self._normalize_target_host(
                        visible_window.get("target_host")
                        or parse_context_key_target_host(
                            visible_window.get("context_key") or getattr(window_info, "context_key", "")
                        )
                        or self._local_host_alias()
                    ),
                    "transport_kind": str(
                        visible_window.get("transport_kind")
                        or self._transport_kind_for_target_host(
                            visible_window.get("target_host")
                            or parse_context_key_target_host(
                                visible_window.get("context_key") or getattr(window_info, "context_key", "")
                            )
                            or self._local_host_alias()
                        )
                    ),
                    "connection_key": str(
                        visible_window.get("connection_key")
                        or getattr(window_info, "connection_key", "")
                        or ""
                    ),
                    "context_key": str(
                        visible_window.get("context_key")
                        or getattr(window_info, "context_key", "")
                        or ""
                    ),
                    "focused": bool(visible_window.get("focused", False)),
                    "visible": visible,
                    "hidden": hidden,
                    "binding_state": binding_state,
                    "last_workspace": tracked_last_workspace,
                    "last_output": tracked_last_output,
                    "floating": (
                        bool(visible_window.get("floating", False))
                        if visible_window
                        else bool(getattr(window_info, "is_floating", False))
                    ),
                    "terminal_anchor_id": str(getattr(window_info, "terminal_anchor_id", "") or ""),
                    "terminal_role": str(getattr(window_info, "terminal_role", "") or ""),
                    "tmux_session_name": str(getattr(window_info, "tmux_session_name", "") or ""),
                }
            )

        outputs = self._project_outputs_from_tracked_windows(outputs, tracked_window_list)

        active_context_key = str(active_context.get("context_key") or "").strip()
        active_project_name = str(active_context.get("qualified_name") or active_context.get("project_name") or "").strip()
        active_target_host = self._target_host_from_context_payload(
            active_context,
            project_name=active_project_name,
        )
        active_execution_mode = self._execution_mode_for_target_host(active_target_host)
        active_terminal_summary: Dict[str, Any] = {
            "available": False,
            "reusable": False,
            "window_id": 0,
            "project_name": active_project_name,
            "context_key": active_context_key,
            "target_host": active_target_host,
            "transport_kind": self._transport_kind_for_target_host(active_target_host),
            "terminal_role": "project-main",
            "tmux_session_name": "",
            "project_directory": str(active_context.get("directory") or active_context.get("local_directory") or "").strip(),
        }

        existing_terminal = await self.launch_service.get_reusable_context_terminal_window(
            project_name=active_project_name,
            context_key=active_context_key,
            execution_mode=active_execution_mode,
        )
        if existing_terminal is not None:
            active_terminal_summary.update({
                "available": True,
                "reusable": True,
                "window_id": int(getattr(existing_terminal, "window_id", 0) or 0),
                "terminal_role": str(getattr(existing_terminal, "terminal_role", "") or "project-main"),
                "tmux_session_name": (
                    str(getattr(existing_terminal, "tmux_session_name", "") or "").strip()
                    or self.launch_service.build_context_tmux_session_name(
                        project_name=active_project_name,
                        context_key=active_context_key,
                        terminal_role="project-main",
                    )
                ),
            })
        elif active_project_name and active_context_key:
            active_terminal_summary.update({
                "reusable": True,
                "tmux_session_name": self.launch_service.build_context_tmux_session_name(
                    project_name=active_project_name,
                    context_key=active_context_key,
                    terminal_role="project-main",
                ),
            })

        runtime_snapshot = {
            "active_project": active_project_name or None,
            "active_context": active_context,
            "outputs": outputs,
            "active_outputs": active_outputs,
            "total_windows": len(tracked_window_list),
            "cached_window_tree": bool(tree_result.get("cached", False)) if isinstance(tree_result, dict) else False,
            "tracked_windows": tracked_window_list,
            "state_health": {
                "tracked_window_count": len(tracked_window_list),
                "scoped_tracked_window_count": scoped_tracked_window_count,
                "ssh_tracked_window_count": ssh_tracked_window_count,
            },
            "scratchpad": scratchpad_summary,
            "active_terminal": active_terminal_summary,
            "launch_stats": self.launch_service.launch_stats(),
        }
        herdr_snapshot = await self.herdr_service.snapshot({})
        sessions = [
            session for session in herdr_snapshot.get("sessions", [])
            if isinstance(session, dict)
        ]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in self._flatten_runtime_windows(runtime_snapshot)
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = self.focus_service.select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        self.focus_service.mark_current_session(
            sessions,
            current_session_key=current_session_key,
        )
        if not bool(params.get("skip_git_hydration", False)):
            await self._hydrate_runtime_git_state(runtime_snapshot, sessions)
        runtime_snapshot["sessions"] = sessions
        runtime_snapshot["current_session_key"] = current_session_key
        runtime_snapshot["herdr"] = herdr_snapshot
        runtime_snapshot["focused_window_id"] = focused_window_id
        return runtime_snapshot

    async def _session_exit(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Exit the current Sway session through the daemon-owned IPC connection."""
        if not self.i3_connection or not getattr(self.i3_connection, "conn", None):
            raise RuntimeError("Sway connection is unavailable")

        result = await self._sway_ipc_command("exit")
        if not self._sway_command_succeeded(result):
            raise RuntimeError("Sway exit command was rejected")

        return {"success": True}

    def _parse_context_key(self, context_key: str) -> Dict[str, str]:
        """Parse context key into project/target-host tuple."""
        project_name, target_host = parse_context_key(context_key)
        if project_name and target_host:
            return {
                "project_name": project_name,
                "target_host": self._normalize_target_host(target_host),
            }
        return {
            "project_name": "",
            "target_host": self._local_host_alias(),
        }

    async def _resolve_scratchpad_request(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Resolve project/context metadata for scratchpad operations."""
        from pathlib import Path

        project_name = str(params.get("project_name") or "").strip()
        context_key = str(params.get("context_key") or "").strip()
        working_dir_override = params.get("working_dir")
        parsed_context = self._parse_context_key(context_key) if context_key else {
            "project_name": "",
            "target_host": self._local_host_alias(),
        }

        active_project = await self.state_manager.get_active_project()
        active_context = self._get_active_runtime_context(active_project=active_project)

        if not project_name:
            if parsed_context.get("project_name"):
                project_name = str(parsed_context["project_name"])
            elif isinstance(active_context, dict) and active_context.get("qualified_name"):
                project_name = str(active_context.get("qualified_name"))
            elif active_project:
                project_name = active_project
            else:
                project_name = "global"

        if project_name == "global":
            if not context_key:
                target_host = self._local_host_alias()
                connection_key = self._normalize_connection_key(f"local@{target_host}")
                parsed_context = {}
            target_host = self._normalize_target_host(parsed_context.get("target_host"))
            execution_mode = self._execution_mode_for_target_host(target_host)
            connection_key = self._connection_key_for_target_host(target_host=target_host, host_profile=None)
            context_key = ""
            working_dir = Path(str(working_dir_override)) if working_dir_override else Path.home()
            return {
                "project_name": "global",
                "context_key": context_key,
                "target_host": target_host,
                "transport_kind": self._transport_kind_for_target_host(target_host),
                "execution_mode": execution_mode,
                "connection_key": connection_key,
                "remote_profile": None,
                "working_dir": working_dir,
            }

        target_host = self._local_host_alias()
        connection_key = ""
        if context_key:
            parsed_project = parsed_context.get("project_name")
            if parsed_project and parsed_project != project_name:
                raise ValueError(
                    f"context_key project '{parsed_project}' does not match requested project '{project_name}'"
                )
            target_host = self._normalize_target_host(parsed_context.get("target_host"))
        elif (
            isinstance(active_context, dict)
            and active_context.get("qualified_name") == project_name
            and active_context.get("context_key")
        ):
            context_key = str(active_context.get("context_key"))
            target_host = self._normalize_target_host(active_context.get("target_host"))
            connection_key = str(active_context.get("connection_key") or "")
        else:
            target_host = self._local_host_alias()
            identity = self._build_worktree_context_identity(project_name, None, target_host=target_host)
            context_key = identity["context_key"]
            connection_key = identity["connection_key"]

        target_host = self._normalize_target_host(target_host)
        remote_profile = self._get_project_remote_profile(project_name) if target_host != self._local_host_alias() else None
        connection_key = (
            self._normalize_connection_key(connection_key)
            if connection_key
            else self._connection_key_for_target_host(target_host=target_host, host_profile=remote_profile)
        )
        execution_mode = self._execution_mode_for_target_host(target_host)
        context_key = self._build_target_context_key(project_name, target_host)

        if working_dir_override:
            working_dir = Path(str(working_dir_override))
        elif remote_profile:
            working_dir = Path(str(remote_profile.get("remote_dir", "")))
        else:
            working_dir = await self._get_project_working_dir(project_name)

        return {
            "project_name": project_name,
            "context_key": context_key,
            "target_host": target_host,
            "transport_kind": self._transport_kind_for_target_host(target_host),
            "execution_mode": execution_mode,
            "connection_key": connection_key,
            "remote_profile": remote_profile,
            "working_dir": working_dir,
        }

    # Feature 062: Scratchpad terminal management methods
    async def _scratchpad_toggle(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Toggle scratchpad terminal visibility."""
        if not self.scratchpad_manager:
            raise RuntimeError("Scratchpad manager not initialized")

        resolved = await self._resolve_scratchpad_request(params)
        project_name = resolved["project_name"]
        context_key = resolved["context_key"]
        remote_profile = resolved["remote_profile"]
        working_dir = resolved["working_dir"]
        execution_mode = resolved["execution_mode"]
        connection_key = resolved["connection_key"]

        terminal = self.scratchpad_manager.get_terminal(context_key)

        if not terminal:
            terminal = await self.scratchpad_manager.launch_terminal(
                project_name,
                working_dir,
                remote_profile=remote_profile,
                context_key=context_key,
                execution_mode=execution_mode,
                connection_key=connection_key,
            )
            await self.scratchpad_manager.toggle_terminal(context_key)
            return {
                "status": "launched",
                "project_name": project_name,
                "context_key": context_key,
                "execution_mode": execution_mode,
                "connection_key": connection_key,
                "pid": terminal.pid,
                "window_id": terminal.window_id,
                "message": f"Scratchpad terminal launched for context '{context_key}'",
            }

        if not await self.scratchpad_manager.validate_terminal(context_key):
            terminal = await self.scratchpad_manager.launch_terminal(
                project_name,
                working_dir,
                remote_profile=remote_profile,
                context_key=context_key,
                execution_mode=execution_mode,
                connection_key=connection_key,
            )
            await self.scratchpad_manager.toggle_terminal(context_key)
            return {
                "status": "relaunched",
                "project_name": project_name,
                "context_key": context_key,
                "execution_mode": execution_mode,
                "connection_key": connection_key,
                "pid": terminal.pid,
                "window_id": terminal.window_id,
                "message": f"Scratchpad terminal relaunched for context '{context_key}'",
            }

        result_state = await self.scratchpad_manager.toggle_terminal(context_key)
        return {
            "status": result_state,
            "project_name": project_name,
            "context_key": context_key,
            "execution_mode": execution_mode,
            "connection_key": connection_key,
            "window_id": terminal.window_id,
            "message": f"Scratchpad terminal {result_state} for context '{context_key}'",
        }

    async def _scratchpad_launch(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Launch new scratchpad terminal (fails if exists)."""
        if not self.scratchpad_manager:
            raise RuntimeError("Scratchpad manager not initialized")

        resolved = await self._resolve_scratchpad_request(params)
        terminal = await self.scratchpad_manager.launch_terminal(
            resolved["project_name"],
            resolved["working_dir"],
            remote_profile=resolved["remote_profile"],
            context_key=resolved["context_key"],
            execution_mode=resolved["execution_mode"],
            connection_key=resolved["connection_key"],
        )

        return {
            "project_name": terminal.project_name,
            "context_key": terminal.context_key,
            "execution_mode": terminal.execution_mode,
            "connection_key": terminal.connection_key,
            "pid": terminal.pid,
            "window_id": terminal.window_id,
            "mark": terminal.mark,
            "working_dir": str(terminal.working_dir),
            "tmux_session_name": terminal.tmux_session_name,
            "message": f"Scratchpad terminal launched for context '{terminal.context_key}'",
        }

    async def _scratchpad_status(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get status of scratchpad terminals."""
        if not self.scratchpad_manager:
            raise RuntimeError("Scratchpad manager not initialized")

        project_name = params.get("project_name")
        context_key = params.get("context_key")

        tree = await self.scratchpad_manager.sway.get_tree()

        if project_name or context_key:
            resolved = await self._resolve_scratchpad_request(params)
            key = resolved["context_key"]
            terminal = self.scratchpad_manager.get_terminal(key)
            if not terminal:
                return {"terminals": [], "count": 0}

            state = await self.scratchpad_manager.get_terminal_state(key)
            window_exists = tree.find_by_id(terminal.window_id) is not None

            return {
                "terminals": [{
                    "project_name": terminal.project_name,
                    "context_key": terminal.context_key,
                    "execution_mode": terminal.execution_mode,
                    "connection_key": terminal.connection_key,
                    "pid": terminal.pid,
                    "window_id": terminal.window_id,
                    "mark": terminal.mark,
                    "working_dir": str(terminal.working_dir),
                    "tmux_session_name": terminal.tmux_session_name,
                    "state": state or "unknown",
                    "process_running": terminal.is_process_running(),
                    "window_exists": window_exists,
                    "created_at": terminal.created_at,
                    "last_shown_at": terminal.last_shown_at,
                }],
                "count": 1,
            }

        terminals = await self.scratchpad_manager.list_terminals()
        result_terminals = []

        for terminal in terminals:
            state = await self.scratchpad_manager.get_terminal_state(terminal.context_key)
            window_exists = tree.find_by_id(terminal.window_id) is not None
            result_terminals.append({
                "project_name": terminal.project_name,
                "context_key": terminal.context_key,
                "execution_mode": terminal.execution_mode,
                "connection_key": terminal.connection_key,
                "pid": terminal.pid,
                "window_id": terminal.window_id,
                "mark": terminal.mark,
                "working_dir": str(terminal.working_dir),
                "tmux_session_name": terminal.tmux_session_name,
                "state": state or "unknown",
                "process_running": terminal.is_process_running(),
                "window_exists": window_exists,
                "created_at": terminal.created_at,
                "last_shown_at": terminal.last_shown_at,
            })

        return {
            "terminals": result_terminals,
            "count": len(result_terminals),
        }

    async def _scratchpad_close(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Close scratchpad terminal."""
        if not self.scratchpad_manager:
            raise RuntimeError("Scratchpad manager not initialized")

        resolved = await self._resolve_scratchpad_request(params)
        context_key = resolved["context_key"]
        terminal = self.scratchpad_manager.get_terminal(context_key)
        if not terminal:
            raise ValueError(f"No scratchpad terminal found for context: {context_key}")

        await self.scratchpad_manager.sway.command(f'[con_id={terminal.window_id}] kill')
        del self.scratchpad_manager.terminals[context_key]

        return {
            "project_name": terminal.project_name,
            "context_key": context_key,
            "message": f"Scratchpad terminal closed for context '{context_key}'",
        }

    async def _scratchpad_cleanup(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Clean up invalid scratchpad terminals."""
        if not self.scratchpad_manager:
            raise RuntimeError("Scratchpad manager not initialized")

        keys_before = list(self.scratchpad_manager.terminals.keys())
        cleaned_count = await self.scratchpad_manager.cleanup_invalid_terminals()
        keys_after = list(self.scratchpad_manager.terminals.keys())
        keys_cleaned = [k for k in keys_before if k not in keys_after]
        remaining = len(keys_after)

        return {
            "cleaned_up": cleaned_count,
            "remaining": remaining,
            "contexts_cleaned": keys_cleaned,
            "message": f"Cleaned up {cleaned_count} invalid terminal(s), {remaining} terminal(s) remaining",
        }

    # Feature 001: Declarative workspace-to-monitor assignment

    async def _monitors_status(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get current monitor role assignments and workspace distribution.

        Feature 001: T066 (monitors.status RPC handler)

        Returns:
            {
                "monitor_count": int,
                "active_monitors": [
                    {
                        "name": str,           # Output name (e.g., "HEADLESS-1")
                        "role": str,           # Monitor role (primary/secondary/tertiary)
                        "workspaces": [int]    # Workspace numbers on this monitor
                    }
                ],
                "last_reassignment": str | null,  # ISO timestamp or null
                "reassignment_count": int
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            # Get active outputs from Sway IPC
            outputs = await self.i3_connection.get_outputs()
            active_outputs = [o for o in outputs if o.active and not o.name.startswith("__")]

            # Sort by name to get consistent connection order
            # For HEADLESS-1, HEADLESS-2, HEADLESS-3, this gives correct numerical order
            active_outputs.sort(key=lambda o: o.name)

            # Get workspaces from Sway IPC
            workspaces = await self._sway_get_workspaces()

            # Build monitor status with workspace distribution
            active_monitors = []
            for idx, output in enumerate(active_outputs):
                # Infer role from connection order (Feature 001 US1)
                if idx == 0:
                    role = "primary"
                elif idx == 1:
                    role = "secondary"
                else:
                    role = "tertiary"

                # Find workspaces on this output
                output_workspaces = [
                    ws.num for ws in workspaces
                    if ws.output == output.name
                ]
                output_workspaces.sort()

                active_monitors.append({
                    "name": output.name,
                    "role": role,
                    "workspaces": output_workspaces
                })

            # TODO: Load reassignment history from state file
            # For now, return placeholder values
            result = {
                "monitor_count": len(active_monitors),
                "active_monitors": active_monitors,
                "last_reassignment": None,
                "reassignment_count": 0
            }

            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitor status: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitors_status",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _monitors_reassign(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Migrate workspaces away from unavailable outputs.

        Feature 001: T067 (monitors.reassign RPC handler)

        Returns:
            {
                "workspaces_moved": int,
                "duration_ms": float,
                "monitor_assignments": {
                    "primary": str,    # Output name
                    "secondary": str,
                    "tertiary": str
                },
                "moved_details": list  # Details of each move
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            outputs = await self.i3_connection.get_outputs()
            from .output_state_manager import load_output_states
            states = load_output_states()
            enabled_outputs = [
                output.name for output in outputs
                if output.active and states.is_output_enabled(output.name)
            ]
            disabled_outputs = [
                output.name for output in outputs
                if output.active and not states.is_output_enabled(output.name)
            ]

            move_result = {"moved": [], "errors": 0}
            if enabled_outputs:
                before = await self._sway_get_workspaces()
                before_by_name = {workspace.name: workspace.output for workspace in before}

                # Phase 1: collapse workspaces away from any disabled outputs.
                if disabled_outputs and self.monitor_profile_service:
                    await self.monitor_profile_service.migrate_workspaces_from_disabled_outputs(
                        self.i3_connection.conn,
                        disabled_outputs,
                        fallback_output=enabled_outputs[0],
                    )

                # Phase 2: redistribute remaining workspaces to their preferred
                # monitor roles. assign_workspaces_with_monitor_roles only sets
                # the preferred output for future workspace creation; we also
                # call force_move_existing_workspaces to actually relocate any
                # already-open workspaces whose current output differs from the
                # preferred one. Cheap no-op when only one output is enabled.
                try:
                    from .workspace_manager import (
                        assign_workspaces_with_monitor_roles,
                        force_move_existing_workspaces,
                    )
                    await assign_workspaces_with_monitor_roles(self.i3_connection.conn)
                    await force_move_existing_workspaces(self.i3_connection.conn)
                except Exception as exc:
                    logger.warning(
                        f"monitors.reassign redistribute step failed: {exc}"
                    )
                    move_result["errors"] += 1

                after = await self._sway_get_workspaces()
                after_by_name = {workspace.name: workspace.output for workspace in after}
                for workspace_name, previous_output in before_by_name.items():
                    current_output = after_by_name.get(workspace_name, previous_output)
                    if previous_output != current_output:
                        move_result["moved"].append({
                            "workspace": workspace_name,
                            "from": previous_output,
                            "to": current_output,
                        })

            # Load output_preferences for monitor_assignments in response
            from pathlib import Path
            import json
            config_path = Path.home() / ".config" / "sway" / "workspace-assignments.json"
            monitor_assignments = {}
            if config_path.exists():
                with open(config_path) as f:
                    data = json.load(f)
                output_prefs = data.get("output_preferences", {})
                for role in ["primary", "secondary", "tertiary"]:
                    if role in output_prefs and output_prefs[role]:
                        monitor_assignments[role] = output_prefs[role][0]

            duration_ms = (time.perf_counter() - start_time) * 1000

            result = {
                "workspaces_moved": len(move_result.get("moved", [])),
                "duration_ms": duration_ms,
                "monitor_assignments": monitor_assignments,
                "moved_details": move_result.get("moved", []),
                "errors": move_result.get("errors", 0),
            }

            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error reassigning workspaces: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="command::monitors_reassign",
                duration_ms=duration_ms,
                error=error_msg,
            )

    async def _monitors_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get monitor role configuration and workspace assignments.

        Feature 001: T068 (monitors.config RPC handler)

        Returns:
            {
                "output_preferences": {
                    "primary": [str],    # Preferred output names in priority order
                    "secondary": [str],
                    "tertiary": [str]
                },
                "workspace_assignments": [
                    {
                        "preferred_workspace": int,
                        "app_name": str,
                        "preferred_monitor_role": str,  # primary/secondary/tertiary
                        "source": str                    # "app-registry" | "pwa-sites" | "inferred"
                    }
                ]
            }
        """
        start_time = time.perf_counter()
        error_msg = None

        try:
            import json
            from pathlib import Path

            # Load workspace-assignments.json (generated by Feature 001)
            config_path = Path.home() / ".config/sway/workspace-assignments.json"

            if not config_path.exists():
                logger.warning(f"workspace-assignments.json not found at {config_path}")
                return {
                    "output_preferences": {},
                    "workspace_assignments": []
                }

            with open(config_path) as f:
                config_data = json.load(f)

            # Extract workspace assignments
            workspace_assignments = []
            for assignment in config_data.get("assignments", []):
                # Note: JSON uses "monitor_role" field name
                monitor_role = assignment.get("monitor_role")
                workspace_assignments.append({
                    "preferred_workspace": assignment.get("workspace"),
                    "app_name": assignment.get("app_name", "unknown"),
                    "preferred_monitor_role": monitor_role if monitor_role else "inferred",
                    "source": assignment.get("source", "unknown")
                })

            result = {
                "output_preferences": config_data.get("output_preferences", {}),
                "workspace_assignments": workspace_assignments
            }

            return result

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error getting monitor config: {e}")
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self._log_ipc_event(
                event_type="query::monitors_config",
                duration_ms=duration_ms,
                error=error_msg,
            )

    # Feature 051: Run-raise-hide application launching

    async def _app_run(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Run, raise, or hide application based on current state.

        Args:
            params: {
                "app_name": str,         # Application name from registry
                "mode": str,             # "summon" | "hide" | "nohide" (default: "summon")
                "force_launch": bool     # Always launch new instance (default: false)
            }

        Returns:
            {
                "action": str,           # "launched" | "focused" | "moved" | "hidden" | "shown" | "none"
                "window_id": int | null, # Sway container ID (if window exists)
                "focused": bool,         # True if window is now focused
                "message": str           # Human-readable result message
            }

        Raises:
            RuntimeError: If run_raise_manager not initialized
            ValueError: If invalid mode provided
        """
        if not self.run_raise_manager:
            raise RuntimeError("Run-raise manager not initialized")

        # Extract parameters with defaults
        app_name = params.get("app_name")
        if not app_name:
            raise ValueError("Missing required parameter: app_name")

        mode = params.get("mode", "summon")
        force_launch = params.get("force_launch", False)

        # Validate mode
        valid_modes = ["summon", "hide", "nohide"]
        if mode not in valid_modes:
            raise ValueError(f"Invalid mode '{mode}'. Must be one of: {', '.join(valid_modes)}")

        try:
            # Detect current window state
            state_info = await self.run_raise_manager.detect_window_state(app_name)

            # Execute appropriate transition
            result = await self.run_raise_manager.execute_transition(
                app_name=app_name,
                state_info=state_info,
                mode=mode,
                force_launch=force_launch
            )

            return result

        except Exception as e:
            logger.error(f"Failed to run app '{app_name}': {e}", exc_info=True)
            raise RuntimeError(f"Failed to run app '{app_name}': {e}")

    def _get_project_remote_profile(self, project_name: str) -> Optional[Dict[str, Any]]:
        """Get remote profile for project if SSH mode is enabled."""
        if project_name == "global":
            return None

        # Prefer active context when project matches active worktree.
        active_context = self._get_active_runtime_context(
            active_project=str(self.state_manager.state.active_project or "").strip()
        )
        if isinstance(active_context, dict) and active_context.get("qualified_name") == project_name:
            remote = active_context.get("remote")
            if isinstance(remote, dict) and remote.get("enabled"):
                return self._normalize_remote_profile(remote)

        if is_qualified_name(project_name):
            return self._get_worktree_remote_profile(project_name)
        return None

    async def _get_project_working_dir(self, project_name: str) -> Path:
        """Get working directory for project.

        Args:
            project_name: Project qualified name (account/repo:branch) or "global"

        Returns:
            Path to working directory
        """
        from pathlib import Path

        if project_name == "global":
            return Path.home()

        active_context = self._get_active_runtime_context(
            active_project=str(self.state_manager.state.active_project or "").strip()
        )
        if isinstance(active_context, dict) and active_context.get("qualified_name") == project_name:
            local_directory = str(active_context.get("local_directory") or "").strip()
            if local_directory and Path(local_directory).exists():
                return Path(local_directory)

            directory = str(active_context.get("directory") or "").strip()
            if directory and Path(directory).exists():
                return Path(directory)

        if ":" in project_name:
            try:
                resolved = self._find_worktree_by_qualified_name(project_name)
                directory = str(
                    resolved.get("worktree", {}).get("path")
                    or resolved.get("path")
                    or ""
                ).strip()
                if directory and Path(directory).exists():
                    return Path(directory)
            except Exception as e:
                logger.warning("Failed to resolve worktree working dir for '%s': %s", project_name, e)

        # Fallback to home directory
        logger.warning("Could not find working dir for '%s', using $HOME", project_name)
        return Path.home()

    # Feature 099: Window environment variables view
    async def _window_get_env(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get environment variables for a window by PID.

        Feature 099: Window Environment Variables View for Monitoring Panel

        Args:
            params: {
                "pid": int  # Process ID of the window
            }

        Returns:
            {
                "pid": int,
                "i3pm_vars": [{"key": str, "value": str}, ...],  # I3PM_* variables
                "other_vars": [{"key": str, "value": str}, ...],  # Other notable vars
                "error": str | null
            }
        """
        start_time = time.perf_counter()

        pid = params.get("pid")
        if not pid:
            raise ValueError("pid parameter is required")

        try:
            pid = int(pid)
        except (TypeError, ValueError):
            raise ValueError(f"Invalid pid: {pid}")

        try:
            from pathlib import Path

            environ_path = Path(f"/proc/{pid}/environ")
            if not environ_path.exists():
                return {
                    "pid": pid,
                    "i3pm_vars": [],
                    "other_vars": [],
                    "error": f"Process {pid} not found or environ not accessible"
                }

            # Read environment variables
            environ_bytes = environ_path.read_bytes()
            environ_str = environ_bytes.decode("utf-8", errors="ignore")
            env_pairs = environ_str.split("\x00")

            i3pm_vars = []
            other_vars = []

            # Notable non-I3PM variables to include
            notable_keys = {"PWD", "HOME", "USER", "SHELL", "TERM", "DISPLAY", "WAYLAND_DISPLAY",
                           "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "SWAYSOCK"}

            for pair in env_pairs:
                if "=" not in pair:
                    continue
                key, _, value = pair.partition("=")

                if key.startswith("I3PM_"):
                    i3pm_vars.append({"key": key, "value": value})
                elif key in notable_keys:
                    # Truncate long values for display
                    display_value = value if len(value) <= 100 else value[:97] + "..."
                    other_vars.append({"key": key, "value": display_value})

            # Sort I3PM vars by key for consistent display
            i3pm_vars.sort(key=lambda x: x["key"])
            other_vars.sort(key=lambda x: x["key"])

            duration_ms = (time.perf_counter() - start_time) * 1000

            logger.debug(f"[Feature 099] Retrieved env for PID {pid}: "
                        f"{len(i3pm_vars)} I3PM vars, {len(other_vars)} other vars "
                        f"in {duration_ms:.2f}ms")

            return {
                "pid": pid,
                "i3pm_vars": i3pm_vars,
                "other_vars": other_vars,
                "error": None
            }

        except PermissionError:
            return {
                "pid": pid,
                "i3pm_vars": [],
                "other_vars": [],
                "error": f"Permission denied reading environ for PID {pid}"
            }
        except Exception as e:
            logger.error(f"[Feature 099] Error reading environ for PID {pid}: {e}")
            return {
                "pid": pid,
                "i3pm_vars": [],
                "other_vars": [],
                "error": str(e)
            }

    # -------------------------------------------------------------------------
    # Feature 100: Structured Git Repository Management IPC Handlers
    # -------------------------------------------------------------------------

    async def _account_add(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Add a new account configuration.

        Feature 100: Structured Git Repository Management (T012)

        Args:
            params: {
                "name": str,         # GitHub account/org name
                "path": str,         # Base directory path
                "is_default": bool,  # Default account for clone (optional)
                "ssh_host": str      # SSH host alias (optional, default: github.com)
            }

        Returns:
            {"success": bool, "account": {...}}
        """
        import json
        from pathlib import Path

        start_time = time.perf_counter()
        accounts_file = Path.home() / ".config" / "i3" / "accounts.json"

        try:
            name = params.get("name")
            path = params.get("path")

            if not name or not path:
                raise ValueError("name and path parameters are required")

            # Load existing accounts
            accounts = {"version": 1, "accounts": []}
            if accounts_file.exists():
                accounts = json.loads(accounts_file.read_text())

            # Check for duplicate
            for acc in accounts["accounts"]:
                if acc["name"] == name:
                    raise ValueError(f"Account '{name}' already exists")

            # Expand ~ in path
            if path.startswith("~/"):
                path = str(Path.home()) + path[1:]

            # Create directory if needed
            account_dir = Path(path)
            account_dir.mkdir(parents=True, exist_ok=True)

            # Build account config
            account = {
                "name": name,
                "path": path,
                "is_default": params.get("is_default", False),
                "ssh_host": params.get("ssh_host", "github.com"),
            }

            # If new default, clear other defaults
            if account["is_default"]:
                for acc in accounts["accounts"]:
                    acc["is_default"] = False

            # Make first account default
            if not accounts["accounts"]:
                account["is_default"] = True

            accounts["accounts"].append(account)

            # Save
            accounts_file.parent.mkdir(parents=True, exist_ok=True)
            accounts_file.write_text(json.dumps(accounts, indent=2) + "\n")

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 100] Added account '{name}' in {duration_ms:.2f}ms")

            return {"success": True, "account": account}

        except Exception as e:
            logger.error(f"[Feature 100] account.add error: {e}")
            raise

    async def _account_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List configured accounts.

        Feature 100: Structured Git Repository Management (T013)

        Returns:
            {"accounts": [...]}
        """
        import json
        from pathlib import Path

        accounts_file = Path.home() / ".config" / "i3" / "accounts.json"

        try:
            if not accounts_file.exists():
                return {"accounts": []}

            accounts = json.loads(accounts_file.read_text())
            return {"accounts": accounts.get("accounts", [])}

        except Exception as e:
            logger.error(f"[Feature 100] account.list error: {e}")
            raise

    async def _clone(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Clone a repository with bare setup.

        Feature 100: Structured Git Repository Management (T021)

        Args:
            params: {
                "url": str,        # GitHub URL (SSH or HTTPS)
                "account": str     # Override account detection (optional)
            }

        Returns:
            {"success": bool, "path": str, "main_worktree": str}
        """
        import subprocess
        import re
        from pathlib import Path

        start_time = time.perf_counter()

        try:
            url = params.get("url")
            if not url:
                raise ValueError("url parameter is required")

            # Parse URL to get account and repo
            ssh_match = re.match(r"^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$", url)
            https_match = re.match(r"^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$", url)

            if ssh_match:
                detected_account, repo_name = ssh_match.groups()
            elif https_match:
                detected_account, repo_name = https_match.groups()
            else:
                raise ValueError(f"Invalid GitHub URL: {url}")

            account = params.get("account") or detected_account
            base_path = Path.home() / "repos" / account
            repo_path = base_path / repo_name
            bare_path = repo_path / ".bare"

            # Check if exists
            if bare_path.exists():
                raise ValueError(f"Repository already exists at {repo_path}")

            # Create directory
            repo_path.mkdir(parents=True, exist_ok=True)

            # Bare clone
            subprocess.run(
                ["git", "clone", "--bare", url, str(bare_path)],
                capture_output=True, text=True, check=True, timeout=120
            )

            # Create .git pointer
            (repo_path / ".git").write_text("gitdir: ./.bare\n")

            # Get default branch
            default_branch = "main"
            result = subprocess.run(
                ["git", "-C", str(bare_path), "symbolic-ref", "refs/remotes/origin/HEAD"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                ref = result.stdout.strip()
                match = re.match(r"refs/remotes/origin/(.+)", ref)
                if match:
                    default_branch = match.group(1)

            # Create main worktree
            main_path = repo_path / default_branch
            subprocess.run(
                ["git", "-C", str(bare_path), "worktree", "add", str(main_path), default_branch],
                capture_output=True, text=True, check=True, timeout=60
            )

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 100] Cloned {url} to {repo_path} in {duration_ms:.2f}ms")

            return {
                "success": True,
                "path": str(repo_path),
                "main_worktree": str(main_path),
                "default_branch": default_branch,
            }

        except subprocess.CalledProcessError as e:
            logger.error(f"[Feature 100] clone git error: {e.stderr}")
            raise RuntimeError(f"Git command failed: {e.stderr}")
        except Exception as e:
            logger.error(f"[Feature 100] clone error: {e}")
            raise

    async def _discover_bare_repos(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Discover all bare repositories and worktrees.

        Feature 100: Structured Git Repository Management (T031)
        Runs in a thread to avoid blocking the asyncio event loop.

        Returns:
            {"success": bool, "repos": int, "worktrees": int, "duration_ms": int}
        """
        return await asyncio.to_thread(self._discover_bare_repos_sync, params)

    def _discover_bare_repos_sync(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Synchronous implementation of bare repo discovery (runs in thread)."""
        import json
        import subprocess
        from pathlib import Path

        start_time = time.perf_counter()
        accounts_file = Path.home() / ".config" / "i3" / "accounts.json"
        repos_file = ConfigPaths.REPOS_FILE

        try:
            # Load accounts
            if not accounts_file.exists():
                return {"success": False, "error": "No accounts configured"}

            accounts = json.loads(accounts_file.read_text())
            repositories = []
            total_worktrees = 0

            for account in accounts.get("accounts", []):
                account_path = Path(account["path"])
                if account_path.as_posix().startswith("~/"):
                    account_path = Path.home() / account_path.as_posix()[2:]

                if not account_path.exists():
                    continue

                # Scan for repos with .bare directory
                for entry in account_path.iterdir():
                    if not entry.is_dir():
                        continue

                    bare_path = entry / ".bare"
                    if not bare_path.is_dir():
                        continue

                    # Get remote URL
                    result = subprocess.run(
                        ["git", "-C", str(bare_path), "remote", "get-url", "origin"],
                        capture_output=True, text=True
                    )
                    if result.returncode != 0:
                        continue

                    remote_url = result.stdout.strip()

                    # Get default branch
                    default_branch = "main"
                    result = subprocess.run(
                        ["git", "-C", str(bare_path), "symbolic-ref", "refs/remotes/origin/HEAD"],
                        capture_output=True, text=True
                    )
                    if result.returncode == 0:
                        import re
                        match = re.match(r"refs/remotes/origin/(.+)", result.stdout.strip())
                        if match:
                            default_branch = match.group(1)

                    # Get worktrees
                    worktrees = []
                    result = subprocess.run(
                        ["git", "-C", str(bare_path), "worktree", "list", "--porcelain"],
                        capture_output=True, text=True
                    )
                    if result.returncode == 0:
                        entries = result.stdout.split("\n\n")
                        for wt_entry in entries:
                            if not wt_entry.strip():
                                continue
                            wt = {}
                            for line in wt_entry.split("\n"):
                                if line.startswith("worktree "):
                                    wt["path"] = line[9:]
                                elif line.startswith("HEAD "):
                                    wt["commit"] = line[5:]
                                elif line.startswith("branch refs/heads/"):
                                    wt["branch"] = line[18:]

                            if wt.get("path") and not wt["path"].endswith("/.bare"):
                                if not wt.get("branch"):
                                    wt["branch"] = "HEAD"
                                wt["is_main"] = wt.get("branch") in (default_branch, "main", "master")
                                wt["ahead"] = 0
                                wt["behind"] = 0

                                # Feature 108: Get detailed git status for worktree
                                wt_path = wt["path"]
                                status_result = subprocess.run(
                                    ["git", "-C", wt_path, "status", "--porcelain=v1"],
                                    capture_output=True, text=True
                                )
                                staged_count = 0
                                modified_count = 0
                                untracked_count = 0
                                has_conflicts = False
                                if status_result.returncode == 0:
                                    for line in status_result.stdout.splitlines():
                                        if len(line) >= 2:
                                            x, y = line[0], line[1]
                                            # Conflict detection
                                            if x == 'U' or y == 'U' or (x == 'A' and y == 'A') or (x == 'D' and y == 'D'):
                                                has_conflicts = True
                                            if x not in (' ', '?'):
                                                staged_count += 1
                                            if y == 'M':
                                                modified_count += 1
                                            if x == '?' and y == '?':
                                                untracked_count += 1

                                wt["is_clean"] = staged_count == 0 and modified_count == 0
                                wt["staged_count"] = staged_count
                                wt["modified_count"] = modified_count
                                wt["untracked_count"] = untracked_count
                                wt["has_conflicts"] = has_conflicts

                                # Feature 108: Get last commit info
                                log_result = subprocess.run(
                                    ["git", "-C", wt_path, "log", "-1", "--format=%ct|%s"],
                                    capture_output=True, text=True
                                )
                                last_commit_timestamp = 0
                                last_commit_message = ""
                                if log_result.returncode == 0 and log_result.stdout.strip():
                                    parts = log_result.stdout.strip().split("|", 1)
                                    if len(parts) >= 1:
                                        try:
                                            last_commit_timestamp = int(parts[0])
                                        except ValueError:
                                            pass
                                    if len(parts) >= 2:
                                        last_commit_message = parts[1][:80]

                                wt["last_commit_timestamp"] = last_commit_timestamp
                                wt["last_commit_message"] = last_commit_message

                                # Feature 108: Stale detection (30+ days since last commit)
                                import time as time_module
                                is_stale = False
                                if last_commit_timestamp > 0:
                                    days_since = (int(time_module.time()) - last_commit_timestamp) // 86400
                                    is_stale = days_since >= 30
                                wt["is_stale"] = is_stale

                                # Feature 108: Merge detection
                                is_merged = False
                                current_branch = wt.get("branch", "")
                                if current_branch not in ("main", "master", "HEAD"):
                                    for check_branch in [default_branch, "main", "master"]:
                                        merged_result = subprocess.run(
                                            ["git", "-C", str(bare_path), "branch", "--merged", check_branch],
                                            capture_output=True, text=True
                                        )
                                        if merged_result.returncode == 0:
                                            merged_branches = [b.strip().lstrip("* ") for b in merged_result.stdout.splitlines()]
                                            if current_branch in merged_branches:
                                                is_merged = True
                                                break
                                wt["is_merged"] = is_merged

                                worktrees.append(wt)
                                total_worktrees += 1

                    repositories.append({
                        "account": account["name"],
                        "name": entry.name,
                        "path": str(entry),
                        "remote_url": remote_url,
                        "default_branch": default_branch,
                        "worktrees": worktrees,
                        "discovered_at": datetime.now().isoformat(),
                    })

            # Save results
            repos_storage = {
                "version": 1,
                "last_discovery": datetime.now().isoformat(),
                "repositories": repositories,
            }
            repos_file.parent.mkdir(parents=True, exist_ok=True)
            repos_file.write_text(json.dumps(repos_storage, indent=2) + "\n")

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 100] Discovered {len(repositories)} repos, {total_worktrees} worktrees in {duration_ms:.2f}ms")

            return {
                "success": True,
                "repos": len(repositories),
                "worktrees": total_worktrees,
                "duration_ms": int(duration_ms),
            }

        except Exception as e:
            logger.error(f"[Feature 100] discover error: {e}")
            raise

    async def _repo_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List discovered repositories.

        Feature 100: Structured Git Repository Management (T034)

        Returns:
            {"repositories": [...], "total": int}
        """
        import json
        from pathlib import Path

        repos_file = ConfigPaths.REPOS_FILE

        try:
            if not repos_file.exists():
                return {"repositories": [], "total": 0}

            repos = json.loads(repos_file.read_text())
            repositories = repos.get("repositories", [])

            # Filter by account if specified
            account_filter = params.get("account")
            if account_filter:
                repositories = [r for r in repositories if r["account"] == account_filter]

            return {"repositories": repositories, "total": len(repositories)}

        except Exception as e:
            logger.error(f"[Feature 100] repo.list error: {e}")
            raise

    async def _repo_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get details for a specific repository.

        Feature 100: Structured Git Repository Management (T034)

        Args:
            params: {
                "account": str,
                "repo": str
            }

        Returns:
            Repository details or error
        """
        import json
        from pathlib import Path

        repos_file = ConfigPaths.REPOS_FILE

        try:
            account = params.get("account")
            repo_name = params.get("repo")

            if not account or not repo_name:
                raise ValueError("account and repo parameters are required")

            if not repos_file.exists():
                raise FileNotFoundError(f"Repository not found: {account}/{repo_name}")

            repos = json.loads(repos_file.read_text())
            for repo in repos.get("repositories", []):
                if repo["account"] == account and repo["name"] == repo_name:
                    return repo

            raise FileNotFoundError(f"Repository not found: {account}/{repo_name}")

        except Exception as e:
            logger.error(f"[Feature 100] repo.get error: {e}")
            raise

    async def _worktree_create(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new worktree.

        Feature 100: Structured Git Repository Management (T024)

        Args:
            params: {
                "branch": str,      # Branch name for new worktree
                "repo": str,        # Repository qualified name (optional)
                "from": str         # Base branch (optional, default: main)
            }

        Returns:
            {"success": bool, "path": str}
        """
        import subprocess
        from pathlib import Path

        start_time = time.perf_counter()

        try:
            branch = params.get("branch")
            if not branch:
                raise ValueError("branch parameter is required")

            repo_name = params.get("repo")
            from_branch = params.get("from", "main")

            # Find repo path
            if repo_name and "/" in repo_name:
                account, name = repo_name.split("/", 1)
                repo_path = Path.home() / "repos" / account / name
            else:
                raise ValueError("repo parameter with account/repo format required")

            bare_path = repo_path / ".bare"
            if not bare_path.exists():
                raise FileNotFoundError(f"Repository not found: {repo_path}")

            worktree_path = repo_path / branch
            if worktree_path.exists():
                raise ValueError(f"Worktree already exists: {worktree_path}")

            # Create worktree
            subprocess.run(
                ["git", "-C", str(bare_path), "worktree", "add", str(worktree_path), "-b", branch, from_branch],
                capture_output=True, text=True, check=True, timeout=60
            )

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 100] Created worktree '{branch}' at {worktree_path} in {duration_ms:.2f}ms")

            # Feature 101: Auto-discover after worktree creation to update UI
            try:
                await self._discover_bare_repos({})
                logger.info(f"[Feature 101] Auto-discovery completed after worktree creation")
            except Exception as discover_err:
                logger.warning(f"[Feature 101] Auto-discovery failed (non-fatal): {discover_err}")

            return {"success": True, "path": str(worktree_path)}

        except subprocess.CalledProcessError as e:
            logger.error(f"[Feature 100] worktree.create git error: {e.stderr}")
            raise RuntimeError(f"Git command failed: {e.stderr}")
        except Exception as e:
            logger.error(f"[Feature 100] worktree.create error: {e}")
            raise

    async def _worktree_remove(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Remove a worktree.

        Feature 100: Structured Git Repository Management

        Args:
            params: {
                "branch": str,      # Branch name of worktree to remove
                "repo": str,        # Repository qualified name (optional)
                "force": bool       # Force removal with uncommitted changes
            }

        Returns:
            {"success": bool, "removed": str}
        """
        import subprocess
        from pathlib import Path

        start_time = time.perf_counter()

        try:
            branch = params.get("branch")
            if not branch:
                raise ValueError("branch parameter is required")

            # Prevent removing main/master
            if branch in ("main", "master"):
                raise ValueError("Cannot remove main worktree")

            repo_name = params.get("repo")
            force = params.get("force", False)

            # Find repo path
            if repo_name and "/" in repo_name:
                account, name = repo_name.split("/", 1)
                repo_path = Path.home() / "repos" / account / name
            else:
                raise ValueError("repo parameter with account/repo format required")

            bare_path = repo_path / ".bare"
            worktree_path = repo_path / branch

            if not worktree_path.exists():
                raise FileNotFoundError(f"Worktree not found: {worktree_path}")

            # Remove worktree
            cmd = ["git", "-C", str(bare_path), "worktree", "remove"]
            if force:
                cmd.append("--force")
            cmd.append(str(worktree_path))

            subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 100] Removed worktree '{branch}' in {duration_ms:.2f}ms")

            # Feature 101: Auto-discover after worktree removal to update UI
            try:
                await self._discover_bare_repos({})
                logger.info(f"[Feature 101] Auto-discovery completed after worktree removal")
            except Exception as discover_err:
                logger.warning(f"[Feature 101] Auto-discovery failed (non-fatal): {discover_err}")

            return {"success": True, "removed": str(worktree_path)}

        except subprocess.CalledProcessError as e:
            logger.error(f"[Feature 100] worktree.remove git error: {e.stderr}")
            raise RuntimeError(f"Git command failed: {e.stderr}")
        except Exception as e:
            logger.error(f"[Feature 100] worktree.remove error: {e}")
            raise

    def _load_worktree_host_profiles(self) -> Dict[str, Any]:
        """Load worktree host profile mapping from disk."""
        return self.worktree_profile_service.load_host_profiles()

    def _save_worktree_host_profiles(self, data: Dict[str, Any]) -> None:
        """Persist worktree host profile mapping to disk."""
        self.worktree_profile_service.save_host_profiles(data)

    def _normalize_host_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize host profile payload and support legacy aliases."""
        return self.worktree_profile_service.normalize_host_profile(profile)

    def _validate_host_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Validate normalized host profile."""
        return self.worktree_profile_service.validate_host_profile(profile)

    def _find_worktree_by_qualified_name(self, qualified_name: str) -> Dict[str, Any]:
        """Resolve worktree metadata from repos.json."""
        repos_file = ConfigPaths.REPOS_FILE
        if not repos_file.exists():
            raise FileNotFoundError("repos.json not found. Run 'i3pm discover' first.")

        repos_data = json.loads(repos_file.read_text())
        if ":" not in qualified_name:
            raise ValueError(
                "Branch is required in qualified name. Use 'account/repo:branch' format."
            )
        repo_name, branch = qualified_name.rsplit(":", 1)

        repo = None
        for r in repos_data.get("repositories", []):
            r_qualified = f"{r.get('account', '')}/{r.get('name', '')}"
            if r_qualified == repo_name:
                repo = r
                break

        if not repo:
            raise FileNotFoundError(f"Repository not found: {repo_name}")

        worktree = None
        worktrees = repo.get("worktrees", [])
        for wt in worktrees:
            if wt.get("branch") == branch:
                worktree = wt
                break

        if not worktree:
            available_branches = [wt.get("branch") for wt in worktrees]
            raise FileNotFoundError(
                f"Worktree '{branch}' not found in {repo_name}. "
                f"Available branches: {', '.join(available_branches)}"
            )

        full_qualified_name = f"{repo_name}:{worktree.get('branch', branch)}"
        return {
            "repo_name": repo_name,
            "repo": repo,
            "worktree": worktree,
            "full_qualified_name": full_qualified_name,
        }

    def _get_worktree_host_profile(self, qualified_name: str) -> Optional[Dict[str, Any]]:
        """Get normalized host profile for a specific worktree."""
        return self.worktree_profile_service.get_host_profile(qualified_name)

    def _normalize_target_host(self, value: Optional[str]) -> str:
        """Normalize target host aliases for host-targeted worktree contexts."""
        normalized = str(value or "").strip().lower()
        return normalized or self._local_host_alias()

    def _resolve_requested_target_host(
        self,
        value: Optional[str],
        *,
        project_name: str = "",
    ) -> str:
        """Resolve a requested target host, including legacy local/ssh tokens."""
        raw = str(value or "").strip().lower()
        if not raw or raw == "local":
            return self._local_host_alias()
        if raw == "ssh":
            profile = self._get_worktree_host_profile(project_name) if project_name else None
            if isinstance(profile, dict) and profile.get("host"):
                return self._normalize_target_host(profile.get("host"))
            return self._local_host_alias()
        return self._normalize_target_host(raw)

    def _target_host_from_context_payload(
        self,
        context: Optional[Dict[str, Any]],
        *,
        project_name: str = "",
    ) -> str:
        """Derive canonical target_host from a context payload."""
        if not isinstance(context, dict):
            return self._local_host_alias()
        explicit = str(context.get("target_host") or "").strip()
        if explicit:
            return self._normalize_target_host(explicit)
        host_profile = context.get("host_profile") or context.get("remote")
        if isinstance(host_profile, dict) and host_profile.get("host"):
            return self._normalize_target_host(host_profile.get("host"))
        connection_key = str(context.get("connection_key") or "").strip()
        execution_mode = str(context.get("execution_mode") or "").strip().lower()
        if execution_mode == "ssh" and connection_key:
            _user, remote_host, _port = self._parse_remote_target("", connection_key)
            if remote_host:
                return self._normalize_target_host(remote_host)
        if project_name:
            profile = self._get_worktree_host_profile(project_name)
            if isinstance(profile, dict) and profile.get("host") and execution_mode == "ssh":
                return self._normalize_target_host(profile.get("host"))
        return self._local_host_alias()

    def _build_target_context_key(self, project_name: str, target_host: str) -> str:
        """Build the canonical host-targeted context key."""
        return f"{str(project_name or '').strip()}::host::{self._normalize_target_host(target_host)}"

    def _transport_kind_for_target_host(self, target_host: str) -> str:
        """Resolve the runtime transport used to reach a host-targeted context."""
        return "local_process" if self._normalize_target_host(target_host) == self._local_host_alias() else "ssh_helper"

    def _execution_mode_for_target_host(self, target_host: str) -> str:
        """Resolve legacy internal execution mode from the canonical target host."""
        return "local" if self._transport_kind_for_target_host(target_host) == "local_process" else "ssh"

    def _connection_key_for_target_host(
        self,
        *,
        target_host: str,
        host_profile: Optional[Dict[str, Any]],
    ) -> str:
        """Build the runtime connection key for a host-targeted context."""
        normalized_target = self._normalize_target_host(target_host)
        if normalized_target == self._local_host_alias():
            return self._normalize_connection_key(f"local@{normalized_target}")
        if not isinstance(host_profile, dict):
            raise ValueError(f"No host profile configured for target host '{normalized_target}'")
        profile_host = self._normalize_target_host(host_profile.get("host"))
        if profile_host != normalized_target:
            raise ValueError(
                f"Configured host profile '{profile_host}' does not match requested target host '{normalized_target}'"
            )
        user = str(host_profile.get("user") or "").strip()
        port = int(host_profile.get("port", 22) or 22)
        raw_connection_key = f"{user}@{profile_host}:{port}" if user else f"{profile_host}:{port}"
        return self._normalize_connection_key(raw_connection_key)

    def _load_worktree_remote_profiles(self) -> Dict[str, Any]:
        return self.worktree_profile_service.load_remote_profiles()

    def _save_worktree_remote_profiles(self, data: Dict[str, Any]) -> None:
        self.worktree_profile_service.save_remote_profiles(data)

    def _normalize_remote_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        return self.worktree_profile_service.normalize_remote_profile(profile)

    def _validate_remote_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        return self.worktree_profile_service.validate_remote_profile(profile)

    def _get_worktree_remote_profile(self, qualified_name: str) -> Optional[Dict[str, Any]]:
        return self.worktree_profile_service.get_remote_profile(qualified_name)

    def _normalize_connection_key(self, value: str) -> str:
        """Normalize connection identity for stable context keys."""
        raw = str(value or "").strip().lower()
        if not raw:
            return "unknown"
        return re.sub(r"[^a-z0-9@._:-]+", "-", raw)

    def _build_managed_tmux_session_name(self, project_name: str, terminal_anchor_id: str) -> str:
        """Build the canonical managed tmux session name used by launcher helpers."""
        slug = re.sub(r"[^a-z0-9_-]+", "-", str(project_name or "project").strip().lower())
        slug = re.sub(r"-{2,}", "-", slug).strip("-") or "project"
        digest = hashlib.sha1(str(terminal_anchor_id or "").encode()).hexdigest()[:8]
        return f"i3pm-{slug[:24]}-{digest}"

    def _local_host_alias(self) -> str:
        """Resolve local host alias used in local execution mode."""
        host = (
            os.environ.get("I3PM_LOCAL_HOST_ALIAS")
            or os.environ.get("HOSTNAME")
            or socket.gethostname()
        )
        return str(host).strip().lower() or "localhost"

    def _session_host_name(self, session: Dict[str, Any]) -> str:
        """Return a normalized source host name for a session payload."""
        host_name = str(session.get("host_name") or "").strip().lower()
        if host_name:
            return host_name

        connection_key = str(session.get("connection_key") or "").strip().lower()
        if connection_key.startswith("local@"):
            return connection_key.split("@", 1)[1].strip()

        return ""

    def _session_is_current_host(
        self,
        *,
        host_name: str,
        connection_key: str,
    ) -> bool:
        """Return whether a session belongs to the current host."""
        local_host = self._local_host_alias()
        if str(host_name or "").strip().lower() == local_host:
            return True

        normalized_connection = self._normalize_connection_key(connection_key)
        return normalized_connection == self._normalize_connection_key(f"local@{local_host}")

    def _connection_target_is_current_host(self, connection_key: str) -> bool:
        """Return whether an SSH connection target resolves back to this host."""
        _remote_user, remote_host, _remote_port = self._parse_remote_target("", connection_key)
        if not remote_host:
            return False
        return str(remote_host or "").strip().lower() == self._local_host_alias()

    async def _window_is_locally_tracked(self, window_id: int) -> bool:
        """Return whether a target window exists in the current host's tracked window map."""
        target = int(window_id or 0)
        if target <= 0:
            return False
        try:
            tracked_windows = await self.state_manager.get_window_map_snapshot()
        except Exception as exc:
            logger.debug("Failed to read tracked windows while resolving local focus target: %s", exc)
            return False
        if target in tracked_windows:
            return True
        for window_info in tracked_windows.values():
            if int(getattr(window_info, "window_id", 0) or 0) == target:
                return True
            if int(getattr(window_info, "con_id", 0) or 0) == target:
                return True
        return False

    def _remote_focus_target(self, session: Dict[str, Any]) -> Tuple[str, str, int]:
        """Return the SSH destination used for remote session handoff."""
        connection_key = str(
            session.get("focus_connection_key")
            or session.get("connection_key")
            or ""
        ).strip()
        user, host_name, port = self._parse_remote_target("", connection_key)
        if host_name:
            resolved_user = user or str(os.environ.get("USER") or "").strip() or "vpittamp"
            return resolved_user, host_name, port

        host_name = self._session_host_name(session)
        if not host_name:
            return "", "", 22

        user = str(os.environ.get("USER") or "").strip() or "vpittamp"
        return user, host_name, 22

    def _build_worktree_context_identity(
        self,
        full_qualified_name: str,
        host_profile: Optional[Dict[str, Any]],
        *,
        target_host: Optional[str] = None,
    ) -> Dict[str, str]:
        """Build canonical context identity for active-worktree consumers."""
        normalized_target_host = self._normalize_target_host(
            target_host or (host_profile.get("host") if isinstance(host_profile, dict) else "")
        )
        transport_kind = self._transport_kind_for_target_host(normalized_target_host)
        execution_mode = self._execution_mode_for_target_host(normalized_target_host)
        connection_key = self._connection_key_for_target_host(
            target_host=normalized_target_host,
            host_profile=host_profile,
        )
        identity_key = f"host:{normalized_target_host}"
        context_key = self._build_target_context_key(full_qualified_name, normalized_target_host)

        return {
            "target_host": normalized_target_host,
            "transport_kind": transport_kind,
            "execution_mode": execution_mode,
            "host_alias": normalized_target_host,
            "connection_key": connection_key,
            "identity_key": identity_key,
            "context_key": context_key,
        }

    def _build_active_worktree_context(
        self,
        full_qualified_name: str,
        repo_name: str,
        repo: Dict[str, Any],
        worktree: Dict[str, Any],
        *,
        target_host: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Build active-worktree.json payload with canonical host-targeted identity."""
        local_directory = worktree.get("path", "")
        normalized_target_host = self._normalize_target_host(target_host)
        host_profile = (
            self._get_worktree_host_profile(full_qualified_name)
            if normalized_target_host != self._local_host_alias()
            else None
        )
        identity = self._build_worktree_context_identity(
            full_qualified_name,
            host_profile,
            target_host=normalized_target_host,
        )
        effective_directory = (
            str(host_profile.get("directory") or "").strip()
            if isinstance(host_profile, dict) and identity["transport_kind"] == "ssh_helper"
            else local_directory
        )

        context: Dict[str, Any] = {
            "qualified_name": full_qualified_name,
            "repo_qualified_name": repo_name,
            "branch": worktree.get("branch", ""),
            "directory": effective_directory,
            "local_directory": local_directory,
            "account": repo.get("account", ""),
            "repo_name": repo.get("name", ""),
            "host_profile": host_profile if host_profile else None,
        }
        context.update(identity)
        return context

    def _record_project_usage(self, qualified_name: str) -> None:
        """Record project usage for ranking in ':' project list.

        Stores per-project recency/frequency in a small JSON file under
        `~/.config/i3/project-usage.json`.
        """
        try:
            usage_file = ConfigPaths.PROJECT_USAGE_FILE
            usage_file.parent.mkdir(parents=True, exist_ok=True)

            now_s = int(time.time())
            data: Dict[str, Any] = {"version": 1, "updated_at": now_s, "projects": {}}

            try:
                if usage_file.exists():
                    existing = json.loads(usage_file.read_text())
                    if isinstance(existing, dict):
                        projects = existing.get("projects")
                        if isinstance(projects, dict):
                            data["projects"] = projects
            except Exception as e:
                logger.warning(f"[Feature 101] Failed to read project usage (will overwrite): {e}")

            projects = data["projects"]
            entry = projects.get(qualified_name)
            if not isinstance(entry, dict):
                entry = {}

            try:
                prev_count = int(entry.get("use_count", 0))
            except Exception:
                prev_count = 0

            projects[qualified_name] = {"last_used_at": now_s, "use_count": prev_count + 1}
            data["updated_at"] = now_s

            tmp_path = usage_file.with_suffix(f".tmp.{os.getpid()}.{time.time_ns()}")
            try:
                tmp_path.write_text(json.dumps(data, indent=2))
                os.replace(tmp_path, usage_file)
            finally:
                try:
                    if tmp_path.exists():
                        tmp_path.unlink()
                except Exception:
                    pass
        except Exception as e:
            # Best-effort only; never block an otherwise-successful project switch.
            logger.warning(f"[Feature 101] Failed to record project usage for {qualified_name}: {e}")

    async def _deferred_window_filter_retry(
        self,
        *,
        active_project: Optional[str],
        active_context_key: Optional[str],
        log_label: str,
        max_attempts: int = 3,
    ) -> None:
        """Retry window filtering with exponential backoff after initial failure.

        Runs as a background task. Each attempt reconnects the Sway IPC
        connection before retrying the filter. Gives up after max_attempts.
        """
        from .services.tree_cache import initialize_tree_cache
        from .services.window_filter import filter_windows_by_project

        delays = [1.0, 2.0, 4.0]  # exponential backoff seconds
        for attempt in range(max_attempts):
            delay = delays[attempt] if attempt < len(delays) else delays[-1]
            logger.info(
                "[Feature 101] Deferred filter retry %d/%d for '%s' in %.1fs",
                attempt + 1, max_attempts, log_label, delay,
            )
            await asyncio.sleep(delay)

            # Check that the active project hasn't changed since we scheduled
            current_ctx = self._active_runtime_context
            current_project = current_ctx.get("qualified_name") if current_ctx else None
            if current_project != active_project:
                logger.info(
                    "[Feature 101] Deferred filter cancelled: project changed from '%s' to '%s'",
                    active_project, current_project,
                )
                return

            try:
                await self.i3_connection.validate_and_reconnect_if_needed()
                if self.i3_connection.conn:
                    initialize_tree_cache(self.i3_connection.conn, ttl_ms=100.0)

                if not self.i3_connection.conn:
                    logger.warning("[Feature 101] Deferred filter retry %d: no connection", attempt + 1)
                    continue

                filter_result = await filter_windows_by_project(
                    self.i3_connection.conn,
                    active_project,
                    self.workspace_tracker,
                    active_context_key=active_context_key,
                )
                logger.info(
                    "[Feature 101] Deferred filter retry %d succeeded for '%s': %d visible, %d hidden",
                    attempt + 1, log_label,
                    filter_result.get("visible", 0),
                    filter_result.get("hidden", 0),
                )
                return
            except Exception as e:
                logger.warning(
                    "[Feature 101] Deferred filter retry %d failed for '%s': %s: %s",
                    attempt + 1, log_label, type(e).__name__, e,
                )

        logger.error(
            "[Feature 101] All %d deferred filter retries exhausted for '%s'",
            max_attempts, log_label,
        )

    def _schedule_deferred_filter(
        self,
        *,
        active_project: Optional[str],
        active_context_key: Optional[str],
        log_label: str,
    ) -> None:
        """Schedule a background deferred filter retry, cancelling any prior one."""
        if self._deferred_filter_task and not self._deferred_filter_task.done():
            self._deferred_filter_task.cancel()
        self._deferred_filter_task = asyncio.create_task(
            self._deferred_window_filter_retry(
                active_project=active_project,
                active_context_key=active_context_key,
                log_label=log_label,
            )
        )

    async def _apply_project_window_filter(
        self,
        *,
        active_project: Optional[str],
        active_context_key: Optional[str],
        log_label: str,
    ) -> Optional[Dict[str, Any]]:
        """Apply project window filtering with one immediate reconnect retry."""
        if not self.i3_connection or not self.i3_connection.conn:
            logger.warning("[Feature 101] Cannot apply filtering - i3 connection not available")
            return None

        from .services.tree_cache import initialize_tree_cache
        from .services.window_filter import filter_windows_by_project

        logger.info(f"[Feature 101] Applying window filtering for '{log_label}'")
        try:
            filter_result = await filter_windows_by_project(
                self.i3_connection.conn,
                active_project,
                self.workspace_tracker,
                active_context_key=active_context_key,
            )
        except ConnectionError as filter_error:
            logger.warning(
                "[Feature 101] Window filtering hit a stale i3 connection for '%s'; retrying after reconnect",
                log_label,
            )
            try:
                await self.i3_connection.validate_and_reconnect_if_needed()
            except Exception as reconnect_error:
                logger.error(
                    "[Feature 101] Failed to reconnect stale i3 connection while filtering '%s': %s: %s",
                    log_label,
                    type(reconnect_error).__name__,
                    reconnect_error,
                )
                raise filter_error

            if not self.i3_connection.conn:
                raise filter_error

            # Even when validation says the current connection is healthy, the
            # module-level tree cache may still be bound to an older connection.
            # Refresh it before retrying the filter.
            initialize_tree_cache(self.i3_connection.conn, ttl_ms=100.0)
            filter_result = await filter_windows_by_project(
                self.i3_connection.conn,
                active_project,
                self.workspace_tracker,
                active_context_key=active_context_key,
            )
            logger.info(
                "[Feature 101] Window filtering recovered after reconnect for '%s'",
                log_label,
            )

        logger.info(
            f"[Feature 101] Window filtering: {filter_result.get('visible', 0)} visible, "
            f"{filter_result.get('hidden', 0)} hidden"
        )
        return filter_result

    async def _worktree_switch(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Switch to a worktree by qualified name.

        Feature 101: Click-to-switch for discovered worktrees.

        This method:
        1. Looks up the worktree by qualified name from discovery cache
        2. Sets active project to the qualified name
        3. Stores the worktree directory for app launcher context
        4. Applies window filtering based on new project context

        Args:
            params: {
                "qualified_name": str,  # e.g., "vpittamp/nixos-config:main" or "vpittamp/nixos-config"
                "target_host": str      # optional: canonical host target for this switch
            }

        Returns:
            {
                "success": bool,
                "qualified_name": str,
                "directory": str,
                "branch": str,
                "previous_project": str | None
            }
        """
        from pathlib import Path

        start_time = time.perf_counter()

        try:
            qualified_name = params.get("qualified_name")
            if not qualified_name:
                raise ValueError("qualified_name parameter is required")
            target_host = self._resolve_requested_target_host(
                params.get("target_host") or params.get("host") or "",
                project_name=str(qualified_name),
            )
            if int(params.get("__intent_epoch") or 0) > 0:
                self._clear_focus_overrides()

            logger.info(f"[Feature 101] Switching to worktree: {qualified_name}")

            resolved = self._find_worktree_by_qualified_name(qualified_name)
            repo_name = resolved["repo_name"]
            repo = resolved["repo"]
            worktree = resolved["worktree"]
            full_qualified_name = resolved["full_qualified_name"]
            worktree_path = worktree.get("path", "")

            # Get previous project
            previous_project = self.state_manager.state.active_project

            # Set active project to the full qualified name
            await self.state_manager.set_active_project(full_qualified_name)

            # Store the project directory for launcher context
            # This is consumed by the daemon-owned launch surface as I3PM_PROJECT_DIR
            from .config import save_active_project
            from .models import ActiveProjectState

            active_state = ActiveProjectState(
                project_name=full_qualified_name
            )
            # Add project_dir to the state if supported
            if hasattr(active_state, 'project_dir'):
                active_state.project_dir = worktree_path

            config_dir = Path.home() / ".config" / "i3"
            config_file = config_dir / "active-project.json"
            save_active_project(active_state, config_file)

            # Also save the active worktree context for launcher/scratchpad.
            # directory is the target host directory when a non-local host profile is enabled.
            worktree_context_file = config_dir / "active-worktree.json"
            worktree_context = self._build_active_worktree_context(
                full_qualified_name,
                repo_name,
                repo,
                worktree,
                target_host=target_host,
            )
            atomic_write_json(worktree_context_file, worktree_context)
            self._set_active_runtime_context(worktree_context)

            # Apply window filtering based on new project context
            # Feature 137: Wrap in try/except for graceful degradation
            try:
                await self._apply_project_window_filter(
                    active_project=full_qualified_name,
                    active_context_key=worktree_context.get("context_key"),
                    log_label=full_qualified_name,
                )
            except Exception as e:
                import traceback
                logger.error(f"[Feature 101] Window filtering failed for '{full_qualified_name}': {type(e).__name__}: {e}")
                logger.debug(f"[Feature 101] Traceback: {traceback.format_exc()}")
                # Schedule deferred retry so windows eventually get filtered
                self._schedule_deferred_filter(
                    active_project=full_qualified_name,
                    active_context_key=worktree_context.get("context_key"),
                    log_label=full_qualified_name,
                )
                # Notify clients of partial failure - project switched but windows not filtered
                await self.broadcast_event({
                    "type": "error",
                    "action": "window_filter_failed",
                    "project": full_qualified_name,
                    "error": str(e)
                })

            # Broadcast project change event
            await self.broadcast_event({
                "type": "project",
                "action": "switch",
                "project": full_qualified_name
            })

            # Record usage for recency/frequency ranking in ':' project list.
            self._record_project_usage(full_qualified_name)

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 101] Switched to worktree '{full_qualified_name}' in {duration_ms:.2f}ms")

            return {
                "success": True,
                "qualified_name": full_qualified_name,
                "directory": worktree_context.get("directory", worktree_path),
                "local_directory": worktree_path,
                "host_profile": worktree_context.get("host_profile"),
                "target_host": worktree_context.get("target_host"),
                "transport_kind": worktree_context.get("transport_kind"),
                "branch": worktree.get("branch", ""),
                "previous_project": previous_project,
                "duration_ms": duration_ms
            }

        except FileNotFoundError as e:
            logger.error(f"[Feature 101] worktree.switch not found: {e}")
            raise
        except Exception as e:
            logger.error(f"[Feature 101] worktree.switch error: {e}")
            raise

    async def _worktree_clear(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Clear active project (return to global mode).

        Feature 101: Unified project management via worktree architecture.

        This method:
        1. Clears active project state
        2. Removes active-worktree.json context file
        3. Shows all scoped windows (global mode behavior)
        4. Broadcasts project change event

        Args:
            params: {} (no parameters required)

        Returns:
            {
                "success": bool,
                "previous_project": str | None
            }
        """
        from pathlib import Path

        start_time = time.perf_counter()
        if int(params.get("__intent_epoch") or 0) > 0:
            self._clear_focus_overrides()

        try:
            # Get previous project
            previous_project = self.state_manager.state.active_project

            logger.info(f"[Feature 101] Clearing active project (was: {previous_project})")

            # Clear active project in state manager
            await self.state_manager.set_active_project(None)

            # Remove context files
            config_dir = Path.home() / ".config" / "i3"

            # Remove active-project.json
            active_project_file = config_dir / "active-project.json"
            if active_project_file.exists():
                active_project_file.unlink()

            # Remove active-worktree.json
            worktree_context_file = config_dir / "active-worktree.json"
            if worktree_context_file.exists():
                worktree_context_file.unlink()
            self._set_active_runtime_context(None)

            logger.info("[Feature 101] Cleared active project context files")

            # Apply window filtering for global mode (show all scoped windows)
            try:
                await self._apply_project_window_filter(
                    active_project=None,
                    active_context_key=None,
                    log_label="global mode",
                )
            except Exception as e:
                logger.error(f"[Feature 101] Window filtering failed during clear: {type(e).__name__}: {e}")
                self._schedule_deferred_filter(
                    active_project=None,
                    active_context_key=None,
                    log_label="global mode",
                )

            # Broadcast project change event
            await self.broadcast_event({
                "type": "project",
                "action": "clear",
                "project": None
            })

            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(f"[Feature 101] Cleared active project in {duration_ms:.2f}ms")

            return {
                "success": True,
                "previous_project": previous_project,
                "duration_ms": duration_ms
            }

        except Exception as e:
            logger.error(f"[Feature 101] worktree.clear error: {e}")
            raise

    async def _worktree_remote_set(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Set SSH remote profile for a worktree-qualified project."""
        qualified_name = params.get("qualified_name")
        if not qualified_name:
            raise ValueError("qualified_name parameter is required")

        resolved = self._find_worktree_by_qualified_name(str(qualified_name))
        full_qualified_name = resolved["full_qualified_name"]

        existing = self._load_worktree_remote_profiles().get("profiles", {}).get(full_qualified_name, {})
        if not isinstance(existing, dict):
            existing = {}

        raw_profile = {
            "enabled": params.get("enabled", existing.get("enabled", True)),
            "host": params.get("host") or params.get("remote_host") or existing.get("host") or "ryzen",
            "user": params.get("user") or params.get("remote_user") or existing.get("user") or os.environ.get("USER", "vpittamp"),
            "port": params.get("port", existing.get("port", 22)),
            "remote_dir": (
                params.get("remote_dir")
                or params.get("working_dir")
                or params.get("dir")
                or existing.get("remote_dir")
                or existing.get("working_dir")
            ),
        }
        profile = self._validate_remote_profile(raw_profile)

        data = self._load_worktree_remote_profiles()
        profiles = data.get("profiles", {})
        if not isinstance(profiles, dict):
            profiles = {}
        profiles[full_qualified_name] = profile
        data["profiles"] = profiles
        self._save_worktree_remote_profiles(data)

        active_updated = False
        if self.state_manager.state.active_project == full_qualified_name:
            config_dir = Path.home() / ".config" / "i3"
            context = self._build_active_worktree_context(
                full_qualified_name, resolved["repo_name"], resolved["repo"], resolved["worktree"]
            )
            atomic_write_json(config_dir / "active-worktree.json", context)
            self._set_active_runtime_context(context)
            active_updated = True

        return {
            "success": True,
            "qualified_name": full_qualified_name,
            "host_profile": profile,
            "active_context_updated": active_updated,
        }

    async def _worktree_remote_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get SSH remote profile for a worktree-qualified project."""
        qualified_name = params.get("qualified_name")
        if not qualified_name:
            raise ValueError("qualified_name parameter is required")

        resolved = self._find_worktree_by_qualified_name(str(qualified_name))
        full_qualified_name = resolved["full_qualified_name"]

        data = self._load_worktree_remote_profiles()
        profile = data.get("profiles", {}).get(full_qualified_name)
        if isinstance(profile, dict):
            profile = self._normalize_remote_profile(profile)
        else:
            profile = None

        return {
            "success": True,
            "qualified_name": full_qualified_name,
            "configured": profile is not None,
            "host_profile": profile,
        }

    async def _worktree_remote_unset(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Unset SSH remote profile for a worktree-qualified project."""
        qualified_name = params.get("qualified_name")
        if not qualified_name:
            raise ValueError("qualified_name parameter is required")

        resolved = self._find_worktree_by_qualified_name(str(qualified_name))
        full_qualified_name = resolved["full_qualified_name"]

        data = self._load_worktree_remote_profiles()
        profiles = data.get("profiles", {})
        if not isinstance(profiles, dict):
            profiles = {}

        existed = full_qualified_name in profiles
        if existed:
            del profiles[full_qualified_name]
            data["profiles"] = profiles
            self._save_worktree_remote_profiles(data)

        active_updated = False
        if self.state_manager.state.active_project == full_qualified_name:
            config_dir = Path.home() / ".config" / "i3"
            context = self._build_active_worktree_context(
                full_qualified_name, resolved["repo_name"], resolved["repo"], resolved["worktree"]
            )
            atomic_write_json(config_dir / "active-worktree.json", context)
            self._set_active_runtime_context(context)
            active_updated = True

        return {
            "success": True,
            "qualified_name": full_qualified_name,
            "removed": existed,
            "active_context_updated": active_updated,
        }

    async def _worktree_remote_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List all configured worktree SSH remote profiles."""
        data = self._load_worktree_remote_profiles()
        profiles = data.get("profiles", {})
        if not isinstance(profiles, dict):
            profiles = {}

        items = []
        for qualified_name in sorted(profiles.keys()):
            profile = profiles.get(qualified_name)
            if not isinstance(profile, dict):
                continue
            items.append({
                "qualified_name": qualified_name,
                "host_profile": self._normalize_remote_profile(profile),
                "is_active": self.state_manager.state.active_project == qualified_name,
            })

        return {
            "success": True,
            "count": len(items),
            "profiles": items,
        }

    async def _worktree_remote_test(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Test SSH connectivity and remote directory validity for a worktree profile."""
        import shlex
        import subprocess

        qualified_name = params.get("qualified_name")
        if not qualified_name:
            raise ValueError("qualified_name parameter is required")

        resolved = self._find_worktree_by_qualified_name(str(qualified_name))
        full_qualified_name = resolved["full_qualified_name"]

        data = self._load_worktree_remote_profiles()
        stored_profile = data.get("profiles", {}).get(full_qualified_name, {})
        if not isinstance(stored_profile, dict):
            stored_profile = {}

        raw_profile = {
            "enabled": True,
            "host": params.get("host") or params.get("remote_host") or stored_profile.get("host") or "ryzen",
            "user": params.get("user") or params.get("remote_user") or stored_profile.get("user") or os.environ.get("USER", "vpittamp"),
            "port": params.get("port", stored_profile.get("port", 22)),
            "remote_dir": (
                params.get("remote_dir")
                or params.get("working_dir")
                or stored_profile.get("remote_dir")
                or stored_profile.get("working_dir")
            ),
        }
        profile = self._validate_remote_profile(raw_profile)

        ssh_cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]
        if profile["port"] != 22:
            ssh_cmd.extend(["-p", str(profile["port"])])
        ssh_cmd.append(f"{profile['user']}@{profile['host']}")
        remote_check = f"test -d {shlex.quote(profile['remote_dir'])}"
        ssh_cmd.append(remote_check)

        from .subprocess_utils import run_command
        start = time.perf_counter()
        try:
            proc = await run_command(
                *ssh_cmd,
                timeout=10.0,
            )
            duration_ms = int((time.perf_counter() - start) * 1000)
            ok = proc.returncode == 0
            return {
                "success": ok,
                "qualified_name": full_qualified_name,
                "host_profile": profile,
                "duration_ms": duration_ms,
                "returncode": proc.returncode,
                "stderr": proc.stderr.strip(),
                "stdout": proc.stdout.strip(),
                "message": (
                    "Host connectivity and host directory check passed"
                    if ok else
                    "Host connectivity or host directory check failed"
                ),
            }
        except subprocess.TimeoutExpired:
            duration_ms = int((time.perf_counter() - start) * 1000)
            return {
                "success": False,
                "qualified_name": full_qualified_name,
                "host_profile": profile,
                "duration_ms": duration_ms,
                "returncode": None,
                "stderr": "Host test timed out after 10s",
                "stdout": "",
                "message": "Host connectivity test timed out",
            }

    async def _worktree_diagnose(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Diagnose host-target/runtime readiness for a worktree."""
        qualified_name = str(params.get("qualified_name") or "").strip()
        active_context = await self._context_get_active({})

        if not qualified_name:
            qualified_name = str(active_context.get("qualified_name") or "").strip()
        if not qualified_name:
            raise ValueError("qualified_name parameter is required when no active worktree context exists")

        resolved = self._find_worktree_by_qualified_name(qualified_name)
        full_qualified_name = resolved["full_qualified_name"]
        remote_profile = self._get_worktree_remote_profile(full_qualified_name)
        target_identity = self._build_worktree_context_identity(full_qualified_name, remote_profile)

        remote_test = None
        if remote_profile:
            remote_test = await self._worktree_remote_test({"qualified_name": full_qualified_name})

        scratchpad_payload: Dict[str, Any] = {
            "available": False,
            "context_key": target_identity["context_key"],
            "count": 0,
            "terminal": None,
        }
        if self.scratchpad_manager:
            try:
                scratchpad_status = await self._scratchpad_status({
                    "project_name": full_qualified_name,
                    "context_key": target_identity["context_key"],
                })
                terminals = scratchpad_status.get("terminals", [])
                terminal_info = terminals[0] if terminals else None
                scratchpad_payload = {
                    "available": bool(terminal_info),
                    "context_key": target_identity["context_key"],
                    "count": int(scratchpad_status.get("count", 0) or 0),
                    "terminal": terminal_info,
                }
            except Exception as e:
                logger.warning("worktree.diagnose scratchpad status failed for %s: %s", full_qualified_name, e)

        launch_stats = self.launch_service.launch_stats()
        pending_launches = []
        if hasattr(self.state_manager, "launch_registry"):
            pending_launches = await self.state_manager.launch_registry.get_pending_launches(include_matched=True)
        project_pending_launches = [
            {
                "app_name": str(item.get("app_name") or ""),
                "matched": bool(item.get("matched", False)),
                "age": float(item.get("age", 0.0) or 0.0),
            }
            for item in pending_launches
            if str(item.get("project_name") or "") == full_qualified_name
        ]

        readiness_reasons = []
        if not remote_profile:
            readiness_reasons.append("No enabled host profile is configured for this worktree.")
        if remote_test and not remote_test.get("success"):
            readiness_reasons.append(
                str(remote_test.get("stderr") or remote_test.get("message") or "Host connectivity test failed")
            )

        recommended_commands = [
            f"i3pm worktree switch {full_qualified_name}",
            f"i3pm worktree current --json",
        ]
        if remote_profile:
            recommended_commands.append(f"i3pm worktree host test {full_qualified_name}")
            recommended_commands.append(f"i3pm scratchpad toggle --context-key {target_identity['context_key']}")
        else:
            recommended_commands.append(
                f"i3pm worktree host set {full_qualified_name} --host ryzen --user {os.environ.get('USER', 'vpittamp')} --dir <host_dir>"
            )

        return {
            "success": True,
            "qualified_name": full_qualified_name,
            "active_context": {
                "qualified_name": str(active_context.get("qualified_name") or ""),
                "target_host": self._target_host_from_context_payload(
                    active_context,
                    project_name=str(active_context.get("qualified_name") or ""),
                ),
                "transport_kind": str(active_context.get("transport_kind") or "global"),
                "connection_key": str(active_context.get("connection_key") or ""),
                "context_key": str(active_context.get("context_key") or ""),
                "is_global": bool(active_context.get("is_global", False)),
            },
            "target_context": {
                "target_host": target_identity["target_host"],
                "transport_kind": target_identity["transport_kind"],
                "connection_key": target_identity["connection_key"],
                "context_key": target_identity["context_key"],
            },
            "host_profile_configured": bool(remote_profile),
            "host_profile": remote_profile,
            "host_test": remote_test,
            "scratchpad": scratchpad_payload,
            "launch_support": {
                "host_terminal_supported": bool(remote_profile),
                "host_scoped_gui_supported": False,
                "host_policy": "terminal_only",
            },
            "launch_stats": launch_stats,
            "project_pending_launches": project_pending_launches,
            "readiness": {
                "host_ready": bool(remote_profile and (remote_test is None or remote_test.get("success"))),
                "reasons": readiness_reasons,
            },
            "recommended_commands": recommended_commands,
        }

    # =========================================================================
    # Feature 101: Window Tracing for Debugging
    # =========================================================================

    async def _trace_start(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start tracing a window.

        Feature 101: Window tracing for debugging state changes.

        Args:
            params: {
                "id": int (optional) - Window ID to trace
                "class": str (optional) - Window class pattern (regex)
                "title": str (optional) - Window title pattern (regex)
                "pid": int (optional) - Process ID
                "app_id": str (optional) - Wayland app_id pattern (regex)
            }

        Returns:
            {
                "success": bool,
                "trace_id": str,
                "matcher": dict,
                "window_id": int (if window already found)
            }
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        # Build matcher from params
        matcher = {}
        for key in ["id", "class", "title", "pid", "app_id"]:
            if key in params and params[key] is not None:
                matcher[key] = str(params[key])

        if not matcher:
            raise ValueError("At least one matcher criterion required (id, class, title, pid, app_id)")

        # Try to find the window now if we have the tree
        initial_container = None
        window_id = None
        if self.i3_connection and self.i3_connection.conn:
            tree = await self.i3_connection.get_tree()
            for window in tree.leaves():
                # Check if window matches
                if "id" in matcher and window.id == int(matcher["id"]):
                    initial_container = window
                    window_id = window.id
                    break
                elif "class" in matcher:
                    import re
                    window_class = getattr(window, 'app_id', None) or getattr(window, 'window_class', None) or ""
                    if re.search(matcher["class"], window_class, re.IGNORECASE):
                        initial_container = window
                        window_id = window.id
                        break
                elif "title" in matcher:
                    import re
                    title = window.name or ""
                    if re.search(matcher["title"], title, re.IGNORECASE):
                        initial_container = window
                        window_id = window.id
                        break
                elif "pid" in matcher and window.pid == int(matcher["pid"]):
                    initial_container = window
                    window_id = window.id
                    break

        trace_id = await tracer.start_trace(
            matcher=matcher,
            window_id=window_id,
            initial_container=initial_container,
        )

        logger.info(f"[Feature 101] Started trace {trace_id} with matcher {matcher}")

        return {
            "success": True,
            "trace_id": trace_id,
            "matcher": matcher,
            "window_id": window_id,
            "window_found": initial_container is not None,
        }

    async def _trace_start_app(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start tracing for next launch of an app.

        Feature 101: Pre-launch tracing - create a pending trace that activates
        when the specified app is launched. This allows profiling the complete
        window lifecycle from launch intent to window appearance.

        Args:
            params: {
                "app_name": str - Application registry name (e.g., "terminal", "code")
                "timeout": float (optional, default 30.0) - Seconds before pending trace expires
            }

        Returns:
            {
                "success": bool,
                "trace_id": str,
                "app_name": str,
                "status": "pending",
                "timeout": float
            }

        Raises:
            RuntimeError: If tracer not initialized
            ValueError: If app_name not provided or max traces reached
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        app_name = params.get("app_name")
        if not app_name:
            raise ValueError("app_name parameter is required")

        timeout = params.get("timeout", 30.0)
        if not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError("timeout must be a positive number")

        trace_id = await tracer.start_app_trace(
            app_name=app_name,
            timeout=float(timeout),
        )

        logger.info(f"[Feature 101] Started app trace {trace_id} for '{app_name}' (timeout={timeout}s)")

        return {
            "success": True,
            "trace_id": trace_id,
            "app_name": app_name,
            "status": "pending",
            "timeout": timeout,
        }

    async def _trace_stop(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Stop a window trace.

        Args:
            params: {"trace_id": str}

        Returns:
            {
                "success": bool,
                "trace_id": str,
                "event_count": int,
                "duration_seconds": float
            }
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.stop_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        logger.info(f"[Feature 101] Stopped trace {trace_id} ({len(trace.events)} events)")

        return {
            "success": True,
            "trace_id": trace_id,
            "event_count": len(trace.events),
            "duration_seconds": trace.duration_seconds,
        }

    async def _trace_get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get trace data.

        Args:
            params: {
                "trace_id": str,
                "format": "json" | "timeline" (default: "json"),
                "limit": int (optional, default 50 for timeline)
            }

        Returns:
            Full trace data or formatted timeline
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        output_format = params.get("format", "json")
        limit = params.get("limit", 50)

        if output_format == "timeline":
            return {
                "success": True,
                "trace_id": trace_id,
                "format": "timeline",
                "timeline": trace.format_timeline(limit=limit),
            }
        else:
            return {
                "success": True,
                "trace_id": trace_id,
                "format": "json",
                "trace": trace.to_dict(),
            }

    async def _trace_list(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List all traces.

        Args:
            params: {} (no parameters)

        Returns:
            {"traces": List of trace summaries}
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        traces = await tracer.list_traces()

        return {
            "success": True,
            "traces": traces,
            "count": len(traces),
        }

    async def _trace_snapshot(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Take a manual snapshot of a traced window's state.

        Args:
            params: {"trace_id": str}

        Returns:
            {"success": bool}
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        if not trace.window_id or trace.window_id == 0:
            raise ValueError("Trace has no associated window yet")

        # Find the window in the tree
        if not self.i3_connection or not self.i3_connection.conn:
            raise RuntimeError("i3 connection not available")

        tree = await self.i3_connection.get_tree()
        container = tree.find_by_id(trace.window_id)
        if not container:
            raise ValueError(f"Window {trace.window_id} not found in tree")

        success = await tracer.take_snapshot(trace_id, container)

        return {
            "success": success,
            "trace_id": trace_id,
        }

    # =========================================================================
    # Feature 102 T057-T058: Trace Template Methods
    # =========================================================================

    async def _traces_list_templates(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List available trace templates.

        Feature 102 T057: Returns pre-configured trace templates for common debugging scenarios.

        Args:
            params: {} (no parameters)

        Returns:
            {"templates": List of template dictionaries}
        """
        from .services.window_tracer import TRACE_TEMPLATES

        return {
            "success": True,
            "templates": [t.to_dict() for t in TRACE_TEMPLATES],
            "count": len(TRACE_TEMPLATES),
        }

    async def _traces_start_from_template(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start a trace using a template configuration.

        Feature 102 T058: Creates a new trace with pre-configured options from a template.

        Args:
            params: {"template_id": str, "app_name": str (optional, for pre-launch)}

        Returns:
            {"trace_id": str, "template": dict}
        """
        from .services.window_tracer import get_tracer, TRACE_TEMPLATES

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        template_id = params.get("template_id")
        if not template_id:
            raise ValueError("template_id parameter is required")

        # Find template
        template = next((t for t in TRACE_TEMPLATES if t.id == template_id), None)
        if not template:
            raise ValueError(f"Template not found: {template_id}")

        # Handle pre-launch templates
        if template.pre_launch:
            app_name = params.get("app_name")
            if not app_name:
                raise ValueError("app_name parameter is required for pre-launch templates")

            trace_id = await tracer.start_app_trace(app_name)
            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "status": "pending_launch",
                "message": f"Waiting for app '{app_name}' to launch",
            }

        # Handle trace-all-scoped templates
        if template.trace_all_scoped:
            # Start trace on next project switch event
            # For now, return success with instructions
            return {
                "success": True,
                "template": template.to_dict(),
                "status": "ready",
                "message": "Switch projects to capture visibility changes",
            }

        # Handle focus-chain templates - trace currently focused window
        if template.id == "debug-focus-chain":
            # Get focused window
            if not self.i3_connection or not self.i3_connection.conn:
                raise RuntimeError("i3 connection not available")

            tree = await self.i3_connection.get_tree()
            focused = tree.find_focused()
            if not focused:
                raise ValueError("No focused window found")

            # Start trace on focused window
            trace_id = await tracer.start_trace(
                window_id=focused.id,
                source="template",
                matcher={
                    "template_id": template.id,
                    "window_id": focused.id,
                }
            )

            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "window_id": focused.id,
                "status": "active",
            }

        # Default: trace by class if specified in template
        if template.match_class:
            trace_id = await tracer.start_trace(
                class_pattern=template.match_class,
                source="template",
                matcher={
                    "template_id": template.id,
                    "class_pattern": template.match_class,
                }
            )
            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "status": "active",
            }

        raise ValueError(f"Template '{template_id}' requires additional configuration")

    # =========================================================================
    # Feature 102: Cross-Reference and Unified Event Tracing Methods (T025-T027, T033)
    # =========================================================================

    async def _traces_get_cross_reference(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get trace reference for a specific log event.

        Feature 102 (T025): Enables click-to-navigate from Log tab to Traces tab.

        Args:
            params: {"event_id": int}

        Returns:
            {"has_trace": bool, "trace_id"?: str, "trace_event_index"?: int,
             "trace_active"?: bool, "window_id"?: int}
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            return {"has_trace": False, "error": "Window tracer not initialized"}

        if not self.event_buffer:
            return {"has_trace": False, "error": "Event buffer not available"}

        event_id = params.get("event_id")
        if event_id is None:
            raise ValueError("event_id parameter is required")

        result = await tracer.get_cross_reference(event_id, self.event_buffer)
        return result

    async def _events_get_by_trace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get log events covered by a specific trace.

        Feature 102 (T026): Enables viewing all Log tab events for a trace.

        Args:
            params: {"trace_id": str, "limit"?: int}

        Returns:
            {"trace_id": str, "events": list, "total_count": int}
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        if not self.event_buffer:
            raise RuntimeError("Event buffer not available")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        limit = params.get("limit", 50)

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        # Find log events that match the trace's window and time range
        events = []
        for event in self.event_buffer.events:
            # Match by trace_id or window_id within trace time range
            if event.trace_id == trace_id:
                events.append({
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "window_id": event.window_id,
                })
            elif (event.window_id == trace.window_id and
                  trace.started_at <= event.timestamp.timestamp() <= (trace.stopped_at or float('inf'))):
                # Find matching trace event index
                trace_event_index = None
                for i, te in enumerate(trace.events):
                    if abs(te.timestamp - event.timestamp.timestamp()) < 0.01:
                        trace_event_index = i
                        break
                events.append({
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "window_id": event.window_id,
                    "trace_event_index": trace_event_index,
                })

            if len(events) >= limit:
                break

        return {
            "trace_id": trace_id,
            "events": events,
            "total_count": len(events),
        }

    async def _traces_query_window_traces(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List traces with optional log event references.

        Feature 102 (T027): Enhanced trace list with include_log_refs support.

        Args:
            params: {"active_only"?: bool, "include_log_refs"?: bool}

        Returns:
            {"traces": list}
        """
        from .services.window_tracer import get_tracer

        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        active_only = params.get("active_only", False)
        include_log_refs = params.get("include_log_refs", False)

        if include_log_refs:
            traces = await tracer.query_window_traces_with_log_refs(
                active_only=active_only,
                event_buffer=self.event_buffer,
            )
        else:
            traces = await tracer.list_traces()
            if active_only:
                traces = [t for t in traces if t.get("is_active", False)]

        return {
            "traces": traces,
        }

    async def _events_get_causality_chain(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get all events in a causality chain by correlation_id.

        Feature 102 (T033): Enables causality visualization in Log tab.

        Args:
            params: {"correlation_id": str}

        Returns:
            {"correlation_id": str, "root_event_id": int, "event_count": int,
             "duration_ms": float, "depth": int, "summary": str, "events": list}
        """
        if not self.event_buffer:
            raise RuntimeError("Event buffer not available")

        correlation_id = params.get("correlation_id")
        if not correlation_id:
            raise ValueError("correlation_id parameter is required")

        # Find all events with this correlation_id
        events = []
        root_event = None
        max_depth = 0

        for event in self.event_buffer.events:
            if event.correlation_id == correlation_id:
                event_data = {
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "causality_depth": event.causality_depth,
                    "window_id": event.window_id,
                }
                events.append(event_data)

                if event.causality_depth == 0:
                    root_event = event
                max_depth = max(max_depth, event.causality_depth)

        if not events:
            return {
                "correlation_id": correlation_id,
                "root_event_id": None,
                "event_count": 0,
                "duration_ms": 0,
                "depth": 0,
                "summary": "No events found",
                "events": [],
            }

        # Sort by timestamp
        events.sort(key=lambda e: e["timestamp"])

        # Calculate duration
        first_ts = events[0]["timestamp"]
        last_ts = events[-1]["timestamp"]
        from datetime import datetime
        duration_ms = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(first_ts)).total_seconds() * 1000

        # Generate summary
        root_type = root_event.event_type if root_event else "unknown"
        summary = f"{root_type} → {len(events)} events, {duration_ms:.1f}ms"

        return {
            "correlation_id": correlation_id,
            "root_event_id": root_event.event_id if root_event else None,
            "event_count": len(events),
            "duration_ms": duration_ms,
            "depth": max_depth,
            "summary": summary,
            "events": events,
        }

    async def _outputs_get_state(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get current output state from OutputEventService.

        Feature 102 T046: Returns cached output state for all outputs or a specific output.

        Args:
            params: Optional parameters
                - output_name: Specific output name to query (optional)

        Returns:
            Dict with output state information
        """
        return await self.display_service.outputs_state(params)

    async def _output_configure(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Apply a deterministic output configuration command through the daemon."""
        return await self.display_service.configure_output(params)

    async def _output_create_virtual(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Create a virtual output through the daemon-owned Sway connection."""
        return await self.display_service.create_virtual_output(params)

    async def _workspace_move_to_output(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Move a workspace to a target output through the daemon."""
        return await self.display_service.move_workspace_to_output(params)

    async def _workspace_focus_fast(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Low-latency workspace focus path for click-driven UI actions."""
        return await self.focus_service.focus_workspace_fast(params)

    async def _workspace_focus(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a workspace through the daemon-owned Sway connection."""
        return await self.focus_service.focus_workspace(params)

    async def _get_focused_workspace_name(self) -> str:
        """Return the currently focused workspace name, if available."""
        return await self.focus_service.focused_workspace_name()

    async def _wait_for_workspace_focus(self, workspace_ref: str, *, timeout_s: float) -> bool:
        """Wait briefly for Sway to report the requested focused workspace."""
        return await self.focus_service.wait_for_workspace_focus(workspace_ref, timeout_s=timeout_s)
