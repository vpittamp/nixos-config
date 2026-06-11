"""Herdr service boundary for Herdr snapshots, actions, and event subscriptions."""

from __future__ import annotations

import asyncio
import copy
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import time
from pathlib import Path, PurePath
from typing import Any, Awaitable, Callable, Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)

HERDR_EVENT_SUBSCRIPTION_TYPES = (
    "workspace.created",
    "workspace.updated",
    "workspace.renamed",
    "workspace.closed",
    "workspace.focused",
    "tab.created",
    "tab.closed",
    "tab.focused",
    "tab.renamed",
    "pane.created",
    "pane.closed",
    "pane.focused",
    "pane.exited",
    "pane.agent_detected",
)

RETIRED_SESSION_LIFECYCLE_FIELDS = {
    "session_phase",
    "session_phase_label",
    "turn_owner",
    "turn_owner_label",
    "activity_substate",
    "activity_substate_label",
    "stage_visual_state",
    "needs_user_action",
    "output_ready",
    "output_unseen",
    "review_pending",
    "status_reason",
}


class HerdrService:
    """Own local Herdr event subscription lifecycle and notification coalescing."""

    def __init__(
        self,
        *,
        notify_state_change: Callable[[str], Awaitable[None]],
        invalidate_snapshot_cache: Optional[Callable[[], None]] = None,
        socket_env_var: str = "I3PM_HERDR_SOCKET",
        subscription_initial_backoff: float = 0.5,
        subscription_max_backoff: float = 30.0,
        notify_delay: float = 0.05,
        snapshot_cache_ttl: float = 0.5,
        remote_snapshot_cache_ttl: float = 10.0,
        normalize_project_path: Optional[Callable[[Optional[str]], Optional[str]]] = None,
        resolve_worktree_for_path: Optional[Callable[[Optional[str]], Optional[Dict[str, str]]]] = None,
        parse_remote_target: Optional[Callable[[str], Tuple[str, str, int]]] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
        load_remote_targets: Optional[Callable[[], List[Dict[str, str]]]] = None,
        local_host: Optional[Callable[[], str]] = None,
        project_for_cwd: Optional[Callable[[str], Dict[str, str]]] = None,
    ) -> None:
        self._notify_state_change = notify_state_change
        self._external_invalidate_snapshot_cache = invalidate_snapshot_cache
        self._socket_env_var = socket_env_var
        self.subscription_initial_backoff = subscription_initial_backoff
        self.subscription_max_backoff = subscription_max_backoff
        self.notify_delay = notify_delay
        self.subscription_task: Optional[asyncio.Task] = None
        self.remote_subscription_tasks: Dict[str, asyncio.Task] = {}
        self.notify_task: Optional[asyncio.Task] = None
        self.local_herdr_generation: int = 0
        self.remote_herdr_generation: Dict[str, int] = {}
        self.snapshot_cache: Dict[str, Any] = {}
        self.snapshot_cache_time: float = 0.0
        self.snapshot_cache_ttl: float = snapshot_cache_ttl
        self.remote_snapshot_cache_ttl: float = remote_snapshot_cache_ttl
        self.remote_targets_cache: List[Dict[str, str]] = []
        self.remote_targets_cache_signature: Tuple[Any, ...] = ("", False, 0, 0)
        self.git_metadata_cache: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
        self._normalize_project_path = normalize_project_path or self._default_normalize_project_path
        self._resolve_worktree_for_path = resolve_worktree_for_path
        self._parse_remote_target = parse_remote_target or self._default_parse_remote_target
        self._normalize_connection_key = normalize_connection_key or self._default_normalize_connection_key
        self._load_remote_targets = load_remote_targets
        self._local_host = local_host
        self._project_for_cwd = project_for_cwd

    @staticmethod
    def _default_normalize_project_path(value: Optional[str]) -> Optional[str]:
        text = str(value or "").strip()
        if not text:
            return None
        return str(Path(text).expanduser())

    @staticmethod
    def _default_normalize_connection_key(value: str) -> str:
        return str(value or "").strip().lower()

    def configured_remote_targets(self) -> List[Dict[str, str]]:
        """Return daemon-configured remote Herdr targets for merged snapshots."""
        if self._load_remote_targets is None:
            return self.load_remote_targets()
        return self._load_remote_targets()

    def configured_local_host(self) -> str:
        """Return the daemon host key used for local Herdr rows."""
        if self._local_host is not None:
            return self._local_host()
        return str(os.environ.get("HOSTNAME") or os.uname().nodename or "").strip()

    def configured_project_for_cwd(self) -> Callable[[str], Dict[str, str]]:
        """Return the project resolver used while normalizing Herdr rows."""
        return self._project_for_cwd or self.project_for_cwd

    @staticmethod
    def _default_parse_remote_target(value: str) -> Tuple[str, str, int]:
        text = str(value or "").strip()
        if not text:
            return ("", "", 22)
        user = ""
        host_port = text
        if "@" in host_port:
            user, host_port = host_port.split("@", 1)
        host = host_port
        port = 22
        if ":" in host_port and not host_port.startswith("["):
            host, raw_port = host_port.rsplit(":", 1)
            try:
                port = int(raw_port or 22)
            except ValueError:
                port = 22
        return (user.strip(), host.strip(), port)

    @staticmethod
    def normalize_host_key(host: Any) -> str:
        """Normalize a Herdr host key for generation tracking."""
        return str(host or "").strip().lower()

    def project_for_cwd(self, cwd: str) -> Dict[str, str]:
        """Resolve a Herdr CWD into the project identity used by session rows."""
        discovered: Optional[Dict[str, str]] = None
        if self._resolve_worktree_for_path is not None:
            discovered = self._resolve_worktree_for_path(cwd)
        if discovered:
            return {
                "project_name": str(discovered.get("qualified_name") or "").strip(),
                "project_path": str(discovered.get("path") or "").strip(),
            }
        normalized = self._normalize_project_path(cwd) or str(cwd or "").strip()
        return {
            "project_name": "global",
            "project_path": normalized,
        }

    def bump_local_generation(self) -> int:
        """Advance and return the local Herdr generation."""
        self.local_herdr_generation += 1
        return self.local_herdr_generation

    def bump_remote_generation(self, host: Any) -> int:
        """Advance and return a remote Herdr host generation."""
        host_key = self.normalize_host_key(host)
        if not host_key:
            return 0
        generation = int(self.remote_herdr_generation.get(host_key, 0)) + 1
        self.remote_herdr_generation[host_key] = generation
        return generation

    def remote_generation_for(self, host: Any) -> int:
        """Return the current generation for a remote Herdr host."""
        host_key = self.normalize_host_key(host)
        if not host_key:
            return 0
        return int(self.remote_herdr_generation.get(host_key, 0))

    def remote_subscription_key(self, target: Dict[str, str]) -> str:
        """Return a stable task key for a remote Herdr proxy subscription."""
        connection_key = str(target.get("connection_key") or "").strip().lower()
        if connection_key:
            return connection_key
        ssh_target = str(target.get("ssh_target") or "").strip().lower()
        if ssh_target:
            return ssh_target
        return self.normalize_host_key(target.get("host"))

    def remote_generations_snapshot(self) -> Dict[str, int]:
        """Return a copy of remote Herdr host generations."""
        return {
            str(host): int(generation)
            for host, generation in self.remote_herdr_generation.items()
        }

    def generations_snapshot(self) -> Dict[str, Any]:
        """Return local and remote Herdr generation counters."""
        return {
            "local_herdr_generation": int(self.local_herdr_generation),
            "remote_herdr_generation": self.remote_generations_snapshot(),
        }

    def cache_ttl(self, *, has_remote_targets: bool) -> float:
        """Return the active Herdr snapshot cache TTL."""
        if has_remote_targets:
            return float(self.remote_snapshot_cache_ttl)
        return float(self.snapshot_cache_ttl)

    def cached_snapshot(
        self,
        *,
        now: float,
        has_remote_targets: bool,
    ) -> Optional[Dict[str, Any]]:
        """Return a copy of a valid cached Herdr snapshot."""
        if not self.snapshot_cache:
            return None
        if now - self.snapshot_cache_time > self.cache_ttl(has_remote_targets=has_remote_targets):
            return None
        return copy.deepcopy(self.snapshot_cache)

    def store_snapshot(self, snapshot: Dict[str, Any], *, now: float) -> Dict[str, Any]:
        """Store and return a defensive copy of a Herdr snapshot."""
        self.snapshot_cache = copy.deepcopy(snapshot)
        self.snapshot_cache_time = float(now)
        return copy.deepcopy(self.snapshot_cache)

    def touch_snapshot_cache(self, *, now: float) -> None:
        """Refresh the cache timestamp after in-place cache reconciliation."""
        self.snapshot_cache_time = float(now)

    def invalidate_snapshot_cache(self) -> None:
        """Clear cached Herdr snapshots so the next read fetches fresh state."""
        self.snapshot_cache = {}
        self.snapshot_cache_time = 0.0
        if self._external_invalidate_snapshot_cache is not None:
            self._external_invalidate_snapshot_cache()

    def clear_git_metadata_cache(self) -> None:
        """Clear cached git metadata used to enrich Herdr spaces."""
        self.git_metadata_cache.clear()

    def apply_remote_focus_cache(
        self,
        *,
        target: Dict[str, str],
        pane_id: str,
        normalize_connection_key: Callable[[str], str],
        now: float,
    ) -> Dict[str, Any]:
        """Optimistically reflect remote pane focus in the cached Herdr snapshot."""
        pane_key = str(pane_id or "").strip()
        if not pane_key or not self.snapshot_cache:
            return {
                "updated": False,
                "focused_session_key": "",
                "connection_key": "",
            }

        host = self.normalize_host_key(target.get("host"))
        ssh_target = str(target.get("ssh_target") or "").strip()
        connection_key = normalize_connection_key(
            str(target.get("connection_key") or "").strip()
        )

        def matches_remote(item: Dict[str, Any]) -> bool:
            item_host = self.normalize_host_key(
                item.get("herdr_host") or item.get("host_name") or item.get("host")
            )
            item_ssh = str(item.get("ssh_target") or item.get("remote_target") or "").strip()
            item_connection = normalize_connection_key(str(item.get("connection_key") or "").strip())
            if host and item_host == host:
                return True
            if ssh_target and item_ssh == ssh_target:
                return True
            return bool(connection_key and item_connection == connection_key)

        focused_session_key = ""
        updated = False
        for collection_name in ("sessions", "panes", "agents"):
            rows = self.snapshot_cache.get(collection_name)
            if not isinstance(rows, list):
                continue
            for row in rows:
                if not isinstance(row, dict) or not matches_remote(row):
                    continue
                focused = str(row.get("pane_id") or "").strip() == pane_key
                row["focused"] = focused
                row["is_current_window"] = focused
                row["window_active"] = focused
                row["pane_active"] = focused
                updated = True
                if focused and collection_name == "sessions":
                    focused_session_key = str(
                        row.get("session_key") or row.get("herdr_session") or ""
                    ).strip()

        remote_snapshots = self.snapshot_cache.get("remote_snapshots")
        if isinstance(remote_snapshots, list):
            for remote_snapshot in remote_snapshots:
                if not isinstance(remote_snapshot, dict):
                    continue
                snapshot_target = {
                    "host": str(remote_snapshot.get("host") or "").strip(),
                    "ssh_target": str(remote_snapshot.get("ssh_target") or "").strip(),
                    "connection_key": normalize_connection_key(
                        str(remote_snapshot.get("connection_key") or "").strip()
                    ),
                }
                if not matches_remote(snapshot_target):
                    continue
                for collection_name in ("sessions", "panes", "agents"):
                    rows = remote_snapshot.get(collection_name)
                    if not isinstance(rows, list):
                        continue
                    for row in rows:
                        if not isinstance(row, dict):
                            continue
                        row["focused"] = str(row.get("pane_id") or "").strip() == pane_key
                        updated = True

        if updated:
            self.touch_snapshot_cache(now=now)

        return {
            "updated": updated,
            "focused_session_key": focused_session_key,
            "connection_key": connection_key,
        }

    def remote_targets_file(self) -> Path:
        """Return the configured remote Herdr target file path."""
        configured = str(os.environ.get("I3PM_HERDR_REMOTE_TARGETS_FILE") or "").strip()
        if configured:
            return Path(configured).expanduser()
        return Path.home() / ".config/i3/herdr-remote-targets.json"

    @staticmethod
    def file_signature(path: Path) -> Tuple[bool, int, int]:
        """Return a cheap file signature for remote target cache invalidation."""
        try:
            stat = path.stat()
        except OSError:
            return (False, 0, 0)
        return (True, int(stat.st_mtime_ns), int(stat.st_size))

    def connection_key_for_target(
        self,
        ssh_target: str,
        explicit: str = "",
        *,
        parse_remote_target: Optional[Callable[[str], Tuple[str, str, int]]] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
    ) -> str:
        """Return a normalized connection key for a remote Herdr target."""
        parse_target = parse_remote_target or self._parse_remote_target
        normalize_key = normalize_connection_key or self._normalize_connection_key
        explicit_key = str(explicit or "").strip()
        if explicit_key:
            return normalize_key(explicit_key)
        user, host, port = parse_target(ssh_target)
        if not host:
            return "unknown"
        user = user or os.environ.get("USER") or "vpittamp"
        return normalize_key(f"{user}@{host}:{port or 22}")

    def load_remote_targets(
        self,
        *,
        parse_remote_target: Optional[Callable[[str], Tuple[str, str, int]]] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
    ) -> List[Dict[str, str]]:
        """Load and normalize configured remote Herdr targets."""
        parse_target = parse_remote_target or self._parse_remote_target
        normalize_key = normalize_connection_key or self._normalize_connection_key
        path = self.remote_targets_file()
        env_payload = str(os.environ.get("I3PM_HERDR_REMOTE_TARGETS") or "").strip()
        signature = (env_payload, *self.file_signature(path))
        if signature == self.remote_targets_cache_signature:
            return [dict(item) for item in self.remote_targets_cache]

        raw_targets: Any = []
        if env_payload:
            try:
                parsed = json.loads(env_payload)
                if isinstance(parsed, list):
                    raw_targets = parsed
            except json.JSONDecodeError:
                logger.warning("Ignoring invalid I3PM_HERDR_REMOTE_TARGETS JSON")
        elif path.exists():
            try:
                with path.open("r", encoding="utf-8") as handle:
                    parsed = json.load(handle)
                if isinstance(parsed, list):
                    raw_targets = parsed
            except (OSError, json.JSONDecodeError) as exc:
                logger.warning("Ignoring invalid Herdr remote target config %s: %s", path, exc)

        targets: List[Dict[str, str]] = []
        seen: set[str] = set()
        for item in raw_targets if isinstance(raw_targets, list) else []:
            if not isinstance(item, dict):
                continue
            host = str(item.get("host") or "").strip().lower()
            ssh_target = str(item.get("ssh_target") or item.get("sshTarget") or host).strip()
            if not ssh_target:
                continue
            if not host:
                _user, parsed_host, _port = parse_target(ssh_target)
                host = parsed_host.lower()
            connection_key = self.connection_key_for_target(
                ssh_target,
                str(item.get("connection_key") or item.get("connectionKey") or ""),
                parse_remote_target=parse_target,
                normalize_connection_key=normalize_key,
            )
            dedupe_key = connection_key if connection_key != "unknown" else ssh_target.lower()
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            targets.append({
                "host": host or ssh_target.lower(),
                "ssh_target": ssh_target,
                "connection_key": connection_key,
            })

        self.remote_targets_cache_signature = signature
        self.remote_targets_cache = [dict(item) for item in targets]
        return [dict(item) for item in targets]

    def resolve_remote_action_target(
        self,
        params: Dict[str, Any],
        *,
        targets: List[Dict[str, str]],
        parse_remote_target: Optional[Callable[[str], Tuple[str, str, int]]] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
    ) -> Dict[str, str]:
        """Resolve a remote Herdr action target from request params and config."""
        parse_target = parse_remote_target or self._parse_remote_target
        normalize_key = normalize_connection_key or self._normalize_connection_key
        host = str(params.get("host") or params.get("herdr_host") or "").strip().lower()
        ssh_target = str(params.get("ssh_target") or params.get("remote_target") or "").strip()
        connection_key = normalize_key(str(params.get("connection_key") or "").strip())

        for target in targets:
            target_host = str(target.get("host") or "").strip().lower()
            target_ssh = str(target.get("ssh_target") or "").strip()
            target_connection = normalize_key(str(target.get("connection_key") or "").strip())
            if ssh_target and target_ssh == ssh_target:
                return dict(target)
            if connection_key and target_connection == connection_key:
                return dict(target)
            if host and target_host == host:
                return dict(target)

        if ssh_target:
            return {
                "host": host or ssh_target.lower(),
                "ssh_target": ssh_target,
                "connection_key": connection_key or self.connection_key_for_target(
                    ssh_target,
                    parse_remote_target=parse_target,
                    normalize_connection_key=normalize_key,
                ),
            }

        raise ValueError("ssh_target is required for remote Herdr pane focus")

    @staticmethod
    def result_array(payload: Dict[str, Any], key: str) -> List[Dict[str, Any]]:
        """Return a normalized object array from a Herdr JSON payload."""
        result = payload.get("result") if isinstance(payload, dict) else {}
        if not isinstance(result, dict):
            result = {}
        rows = result.get(key, [])
        if not isinstance(rows, list):
            return []
        return [dict(item) for item in rows if isinstance(item, dict)]

    @staticmethod
    def worktree_result_array(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Return normalized Herdr worktree rows with source metadata filled in."""
        result = payload.get("result") if isinstance(payload, dict) else {}
        if not isinstance(result, dict):
            result = {}
        source = result.get("source")
        if not isinstance(source, dict):
            source = {}
        rows = result.get("worktrees", [])
        if not isinstance(rows, list):
            return []

        normalized: List[Dict[str, Any]] = []
        for item in rows:
            if not isinstance(item, dict):
                continue
            row = dict(item)
            if not str(row.get("workspace_id") or "").strip() and str(row.get("open_workspace_id") or "").strip():
                row["workspace_id"] = str(row.get("open_workspace_id") or "").strip()
            row.setdefault("repo_key", source.get("repo_key"))
            row.setdefault("repo_name", source.get("repo_name"))
            row.setdefault("repo_root", source.get("repo_root"))
            row.setdefault("checkout_path", row.get("path"))
            if str(row.get("branch") or "").strip() and not str(row.get("branch_label") or "").strip():
                row["branch_label"] = str(row.get("branch") or "").strip()
            normalized.append(row)
        return normalized

    @staticmethod
    def normalize_repo_url(value: Any) -> str:
        """Normalize common git remote URLs into a stable repository key."""
        text = str(value or "").strip()
        if not text:
            return ""
        if text.endswith(".git"):
            text = text[:-4]
        github_ssh = re.match(r"^git@github\.com:(?P<path>[^/]+/.+)$", text)
        if github_ssh:
            return github_ssh.group("path").strip("/")
        github_https = re.match(r"^https://github\.com/(?P<path>[^/]+/.+)$", text)
        if github_https:
            return github_https.group("path").strip("/")
        return text.rstrip("/")

    def git_run(
        self,
        path: str,
        args: List[str],
        *,
        ssh_target: str = "",
        timeout: float = 0.75,
    ) -> str:
        """Run a bounded git metadata command locally or on a Herdr remote."""
        if not str(path or "").strip():
            return ""

        command: List[str]
        if ssh_target:
            remote_args = " ".join(shlex.quote(part) for part in ["git", "-C", path, *args])
            command = self.ssh_command_prefix(ssh_target) + [remote_args]
        else:
            normalized = self._normalize_project_path(path)
            if not normalized or not Path(normalized).exists():
                return ""
            command = ["git", "-C", normalized, *args]

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return ""
        if result.returncode != 0:
            return ""
        return str(result.stdout or "").strip()

    def path_is_git_worktree(self, path: Any, *, ssh_target: str = "") -> bool:
        """Return whether a path is inside a git worktree."""
        value = str(path or "").strip()
        if not value:
            return False
        return self.git_run(
            value,
            ["rev-parse", "--is-inside-work-tree"],
            ssh_target=ssh_target,
        ).lower() == "true"

    def effective_cwd(self, row: Dict[str, Any], *, ssh_target: str = "") -> str:
        """Prefer Herdr foreground CWD only when it resolves to a git worktree."""
        cwd = str(row.get("cwd") or "").strip()
        foreground_cwd = str(row.get("foreground_cwd") or "").strip()
        if foreground_cwd and self.path_is_git_worktree(foreground_cwd, ssh_target=ssh_target):
            return foreground_cwd
        if cwd and self.path_is_git_worktree(cwd, ssh_target=ssh_target):
            return cwd
        return foreground_cwd or cwd

    def git_branch(self, path: Any, *, ssh_target: str = "") -> str:
        """Return the current branch name or detached commit label for a path."""
        value = str(path or "").strip()
        if not value:
            return ""
        branch = self.git_run(value, ["branch", "--show-current"], ssh_target=ssh_target)
        if branch:
            return branch
        branch = self.git_run(value, ["symbolic-ref", "--short", "HEAD"], ssh_target=ssh_target)
        if branch:
            return branch
        branch = self.git_run(value, ["rev-parse", "--abbrev-ref", "HEAD"], ssh_target=ssh_target)
        if branch and branch != "HEAD":
            return branch
        return self.git_run(value, ["rev-parse", "--short", "HEAD"], ssh_target=ssh_target)

    def git_space_metadata(
        self,
        path: Any,
        *,
        ssh_target: str = "",
        normalize_connection_key: Callable[[str], str],
    ) -> Dict[str, Any]:
        """Return git metadata used to group and label Herdr spaces."""
        value = str(path or "").strip()
        if not value:
            return {}
        cache_key = (
            normalize_connection_key(ssh_target) if ssh_target else "local",
            ssh_target,
            value,
        )
        if cache_key in self.git_metadata_cache:
            return dict(self.git_metadata_cache[cache_key])

        if not self.path_is_git_worktree(value, ssh_target=ssh_target):
            self.git_metadata_cache[cache_key] = {}
            return {}

        checkout_path = self.git_run(value, ["rev-parse", "--show-toplevel"], ssh_target=ssh_target)
        if not checkout_path:
            self.git_metadata_cache[cache_key] = {}
            return {}

        common_dir = self.git_run(value, ["rev-parse", "--git-common-dir"], ssh_target=ssh_target)
        if common_dir and not common_dir.startswith("/"):
            common_dir = str(PurePath(checkout_path) / common_dir)
        repo_root = common_dir or checkout_path
        if repo_root.endswith("/.git"):
            repo_root = repo_root[:-5]
        origin = self.git_run(value, ["config", "--get", "remote.origin.url"], ssh_target=ssh_target)
        repo_key = self.normalize_repo_url(origin) or repo_root
        if repo_key and not repo_key.startswith("/") and "/" in repo_key:
            repo_name = repo_key.rstrip("/").rsplit("/", 1)[-1]
        else:
            repo_root_parts = [part for part in repo_root.rstrip("/").split("/") if part]
            if repo_root_parts and repo_root_parts[-1] in {".bare", ".git"} and len(repo_root_parts) >= 2:
                repo_name = repo_root_parts[-2]
            else:
                repo_name = checkout_path.rstrip("/").rsplit("/", 1)[-1]
        metadata = {
            "repo_key": repo_key,
            "repo_name": repo_name,
            "repo_root": repo_root,
            "checkout_path": checkout_path,
            "is_linked_worktree": False,
            "branch_label": self.git_branch(value, ssh_target=ssh_target),
        }
        self.git_metadata_cache[cache_key] = metadata
        return dict(metadata)

    @staticmethod
    def normalize_agent_status(value: Any, *, preserve_raw: bool = False) -> str:
        """Normalize Herdr agent status while preserving raw labels when requested."""
        raw = str(value or "").strip()
        if preserve_raw:
            return raw or "unknown"
        status = raw.lower()
        if status in {"working", "blocked", "done", "idle", "unknown"}:
            return status
        return "unknown"

    @staticmethod
    def agent_status_state(value: Any) -> str:
        """Map Herdr and display status variants to dashboard status states."""
        raw = str(value or "").strip().lower()
        normalized = re.sub(r"[^a-z0-9]+", "_", raw).strip("_")
        if normalized in {"blocked", "needs_input", "needsinput", "waiting_input", "waiting_for_input"}:
            return "blocked"
        if normalized in {"done", "complete", "completed", "success", "succeeded", "finished"}:
            return "done"
        if normalized in {"working", "running", "thinking", "streaming", "tool_running", "busy"}:
            return "working"
        if normalized in {"idle", "ready"}:
            return "idle"
        return "unknown"

    @classmethod
    def agent_status_rank(cls, value: Any) -> int:
        """Return display priority for a Herdr agent status."""
        priority = {
            "unknown": 0,
            "idle": 1,
            "working": 2,
            "done": 3,
            "blocked": 4,
        }
        return priority.get(cls.agent_status_state(value), 0)

    @staticmethod
    def normalize_text_field(value: Any) -> str:
        """Normalize optional Herdr text fields."""
        return str(value or "").strip()

    @classmethod
    def normalize_state_labels(cls, value: Any) -> Dict[str, str]:
        """Normalize Herdr state label maps by canonical status state."""
        if not isinstance(value, dict):
            return {}
        labels: Dict[str, str] = {}
        for key, label in value.items():
            state = cls.agent_status_state(key)
            text = cls.normalize_text_field(label)
            if state == "unknown" or not text:
                continue
            labels[state] = text
        return labels

    def annotate_rows(
        self,
        rows: List[Dict[str, Any]],
        *,
        host: str,
        execution_mode: str,
        connection_key: str,
        ssh_target: str = "",
        is_remote: bool = False,
        normalize_connection_key: Callable[[str], str],
        overwrite_context: bool = False,
    ) -> List[Dict[str, Any]]:
        """Add normalized host/execution fields to Herdr rows."""
        annotated: List[Dict[str, Any]] = []
        host_key = self.normalize_host_key(host)
        normalized_connection = normalize_connection_key(connection_key)
        for row in rows:
            item = dict(row)
            context_fields = {
                "host_name": host_key,
                "herdr_host": host_key,
                "target_host": host_key,
                "execution_mode": execution_mode,
                "connection_key": normalized_connection,
                "ssh_target": ssh_target,
                "remote_target": ssh_target,
                "is_remote_herdr": bool(is_remote),
                "is_current_host": not bool(is_remote),
            }
            if overwrite_context:
                item.update(context_fields)
            else:
                for key, value in context_fields.items():
                    item.setdefault(key, value)
            annotated.append(item)
        return annotated

    @staticmethod
    def session_key(row: Dict[str, Any], host: str = "") -> str:
        """Build the stable dashboard session key for a Herdr row."""
        prefix = "herdr"
        normalized_host = re.sub(r"[^a-z0-9._:-]+", "-", str(host or "").strip().lower()).strip("-")
        if normalized_host:
            prefix = f"{prefix}:{normalized_host}"
        pane_id = str(row.get("pane_id") or "").strip()
        if pane_id:
            return f"{prefix}:pane:{pane_id}"
        terminal_id = str(row.get("terminal_id") or "").strip()
        if terminal_id:
            return f"{prefix}:terminal:{terminal_id}"
        tab_id = str(row.get("tab_id") or "").strip()
        if tab_id:
            return f"{prefix}:tab:{tab_id}"
        workspace_id = str(row.get("workspace_id") or "").strip()
        if workspace_id:
            return f"{prefix}:workspace:{workspace_id}"
        return f"{prefix}:unknown"

    def normalize_session_row(
        self,
        row: Dict[str, Any],
        *,
        remote_target: Optional[Dict[str, str]] = None,
        local_host: str,
        normalize_connection_key: Callable[[str], str],
        project_for_cwd: Callable[[str], Dict[str, str]],
    ) -> Dict[str, Any]:
        """Normalize one Herdr pane or agent row into the dashboard session model."""
        pane_id = str(row.get("pane_id") or "").strip()
        tab_id = str(row.get("tab_id") or "").strip()
        workspace_id = str(row.get("workspace_id") or "").strip()
        terminal_id = str(row.get("terminal_id") or "").strip()
        cwd = str(row.get("cwd") or "").strip()
        foreground_cwd = str(row.get("foreground_cwd") or "").strip()
        agent = str(row.get("agent") or "").strip()
        is_remote = isinstance(remote_target, dict)
        host_key = self.normalize_host_key(
            remote_target.get("host") if is_remote and remote_target else local_host
        )
        ssh_target = str(remote_target.get("ssh_target") or "").strip() if is_remote and remote_target else ""
        effective_cwd = self.effective_cwd(row, ssh_target=ssh_target)
        project = project_for_cwd(effective_cwd)
        git_metadata = self.git_space_metadata(
            effective_cwd,
            ssh_target=ssh_target,
            normalize_connection_key=normalize_connection_key,
        )
        project_name = str(project.get("project_name") or "global").strip() or "global"
        connection_key = (
            str(remote_target.get("connection_key") or "").strip()
            if is_remote and remote_target
            else normalize_connection_key(f"local@{self.normalize_host_key(local_host)}")
        )
        agent_status = self.normalize_agent_status(
            row.get("agent_status"),
            preserve_raw=is_remote,
        )
        display_agent = self.normalize_text_field(row.get("display_agent"))
        custom_status = self.normalize_text_field(row.get("custom_status"))
        state_labels = self.normalize_state_labels(row.get("state_labels"))
        session_key = self.session_key(row, host_key if is_remote else "")

        normalized = {
            key: value
            for key, value in dict(row).items()
            if key not in RETIRED_SESSION_LIFECYCLE_FIELDS
        }
        normalized.update({
            "schema": "herdr.ai_session.v1",
            "source": "herdr",
            "herdr_session": session_key,
            "session_key": session_key,
            "render_session_key": session_key,
            "agent": agent,
            "tool": agent,
            "display_tool": agent or "herdr",
            "display_agent": display_agent,
            "custom_status": custom_status,
            "state_labels": state_labels,
            "agent_status": agent_status,
            "focused": bool(row.get("focused", False)),
            "is_current_window": bool(row.get("focused", False)),
            "window_active": bool(row.get("focused", False)),
            "pane_active": bool(row.get("focused", False)),
            "workspace_id": workspace_id,
            "tab_id": tab_id,
            "pane_id": pane_id,
            "terminal_id": terminal_id,
            "cwd": cwd,
            "foreground_cwd": foreground_cwd,
            "working_dir": effective_cwd,
            "project_name": project_name,
            "project": project_name,
            "project_path": str(project.get("project_path") or "").strip(),
            "project_label": project_name.rsplit("/", 1)[-1] if project_name != "global" else "global",
            "repo_key": str(git_metadata.get("repo_key") or "").strip(),
            "repo_name": str(git_metadata.get("repo_name") or "").strip(),
            "repo_root": str(git_metadata.get("repo_root") or "").strip(),
            "checkout_path": str(git_metadata.get("checkout_path") or "").strip(),
            "is_linked_worktree": bool(git_metadata.get("is_linked_worktree", False)),
            "branch_label": str(git_metadata.get("branch_label") or "").strip(),
            "execution_mode": "ssh" if is_remote else "local",
            "connection_key": normalize_connection_key(connection_key),
            "host_name": host_key,
            "herdr_host": host_key,
            "ssh_target": ssh_target,
            "remote_target": ssh_target,
            "target_host": host_key,
            "is_remote_herdr": bool(is_remote),
            "is_current_host": not bool(is_remote),
            "focus_mode": "remote_herdr_attach" if is_remote else "herdr_pane",
            "availability_state": "remote_herdr_attachable" if is_remote else "local_window",
            "pane_label": pane_id,
            "pane_title": agent or pane_id,
            "focus_target": {
                "method": "herdr.remote.pane.focus",
                "params": {
                    "pane_id": pane_id,
                    "host": host_key,
                    "ssh_target": ssh_target,
                    "connection_key": normalize_connection_key(connection_key),
                    "app_name": "herdr",
                },
            } if is_remote else ({
                "method": "herdr.pane.focus",
                "params": {"pane_id": pane_id},
            } if pane_id else {}),
            "close_target": {} if is_remote else ({
                "method": "herdr.pane.close",
                "params": {"pane_id": pane_id},
            } if pane_id else {}),
            "workspace_focus_target": {
                "method": "herdr.workspace.focus",
                "params": {"workspace_id": workspace_id},
            } if workspace_id and not is_remote else {},
            "tab_focus_target": {
                "method": "herdr.tab.focus",
                "params": {"tab_id": tab_id},
            } if tab_id and not is_remote else {},
        })
        return normalized

    def normalize_sessions(
        self,
        snapshot: Dict[str, Any],
        *,
        remote_target: Optional[Dict[str, str]] = None,
        local_host: str,
        normalize_connection_key: Callable[[str], str],
        project_for_cwd: Callable[[str], Dict[str, str]],
    ) -> List[Dict[str, Any]]:
        """Normalize Herdr agents and panes into dashboard session rows."""
        panes_by_id = {
            str(item.get("pane_id") or "").strip(): dict(item)
            for item in snapshot.get("panes", [])
            if isinstance(item, dict) and str(item.get("pane_id") or "").strip()
        }
        agents = [
            item for item in snapshot.get("agents", [])
            if isinstance(item, dict)
        ]
        rows: List[Dict[str, Any]] = []
        seen: set[str] = set()
        for agent in agents:
            pane_id = str(agent.get("pane_id") or "").strip()
            merged = dict(panes_by_id.get(pane_id, {}))
            merged.update(agent)
            session = self.normalize_session_row(
                merged,
                remote_target=remote_target,
                local_host=local_host,
                normalize_connection_key=normalize_connection_key,
                project_for_cwd=project_for_cwd,
            )
            key = str(session.get("session_key") or "").strip()
            if key and key not in seen:
                seen.add(key)
                rows.append(session)

        for pane_id, pane in panes_by_id.items():
            if pane_id in seen:
                continue
            if not str(pane.get("agent") or "").strip():
                continue
            session = self.normalize_session_row(
                pane,
                remote_target=remote_target,
                local_host=local_host,
                normalize_connection_key=normalize_connection_key,
                project_for_cwd=project_for_cwd,
            )
            key = str(session.get("session_key") or "").strip()
            if key and key not in seen:
                seen.add(key)
                rows.append(session)

        focused_hosts: set[str] = set()
        for session in rows:
            host_key = str(session.get("herdr_host") or session.get("host_name") or "").strip().lower()
            if not bool(session.get("focused", False)):
                continue
            if host_key in focused_hosts:
                session["focused"] = False
                session["is_current_window"] = False
                session["window_active"] = False
                session["pane_active"] = False
                continue
            focused_hosts.add(host_key)

        rows.sort(key=lambda item: (
            not bool(item.get("focused", False)),
            str(item.get("herdr_host") or ""),
            str(item.get("project_name") or ""),
            str(item.get("agent") or ""),
            str(item.get("pane_id") or ""),
        ))
        return rows

    async def remote_snapshot(
        self,
        target: Dict[str, str],
        *,
        local_host: str,
        normalize_connection_key: Callable[[str], str],
        project_for_cwd: Callable[[str], Dict[str, str]],
    ) -> Dict[str, Any]:
        """Fetch and normalize one remote Herdr host snapshot through its i3pm proxy."""
        self.clear_git_metadata_cache()
        proxy_payload = await self.run_proxy_json(target, ["snapshot", "--json"])
        host = str(target.get("host") or "").strip()
        ssh_target = str(target.get("ssh_target") or "").strip()
        connection_key = str(target.get("connection_key") or "").strip()
        if not bool(proxy_payload.get("success", False)):
            error_entry = {
                "remote": True,
                "host": host,
                "ssh_target": ssh_target,
                "connection_key": connection_key,
                "command": proxy_payload.get("command"),
                "error": proxy_payload.get("error") or proxy_payload.get("stderr") or proxy_payload.get("stdout"),
                "returncode": proxy_payload.get("returncode"),
            }
            return {
                "success": False,
                "remote": True,
                "host": host,
                "ssh_target": ssh_target,
                "connection_key": connection_key,
                "herdr_generation": self.remote_generation_for(host),
                "status": proxy_payload,
                "agents": [],
                "panes": [],
                "workspaces": [],
                "tabs": [],
                "worktrees": [],
                "sessions": [],
                "errors": [error_entry],
            }

        snapshot = {
            "success": True,
            "remote": True,
            "host": host,
            "ssh_target": ssh_target,
            "connection_key": connection_key,
            "herdr_generation": self.bump_remote_generation(host),
            "proxy_schema_version": str(proxy_payload.get("schema_version") or ""),
            "proxy_protocol_version": int(proxy_payload.get("protocol_version") or 0),
            "status": proxy_payload.get("status", {}),
            "agents": self.annotate_rows(
                [item for item in proxy_payload.get("agents", []) or [] if isinstance(item, dict)],
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
                overwrite_context=True,
            ),
            "panes": self.annotate_rows(
                [item for item in proxy_payload.get("panes", []) or [] if isinstance(item, dict)],
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
                overwrite_context=True,
            ),
            "workspaces": self.annotate_rows(
                [item for item in proxy_payload.get("workspaces", []) or [] if isinstance(item, dict)],
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
                overwrite_context=True,
            ),
            "tabs": self.annotate_rows(
                [item for item in proxy_payload.get("tabs", []) or [] if isinstance(item, dict)],
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
                overwrite_context=True,
            ),
            "worktrees": self.annotate_rows(
                [item for item in proxy_payload.get("worktrees", []) or [] if isinstance(item, dict)],
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
                overwrite_context=True,
            ),
            "errors": [
                item for item in proxy_payload.get("errors", []) or []
                if isinstance(item, dict)
            ],
        }
        snapshot["sessions"] = self.normalize_sessions(
            snapshot,
            remote_target=target,
            local_host=local_host,
            normalize_connection_key=normalize_connection_key,
            project_for_cwd=project_for_cwd,
        )
        return snapshot

    async def local_snapshot(
        self,
        *,
        local_host: str,
        normalize_connection_key: Callable[[str], str],
        project_for_cwd: Callable[[str], Dict[str, str]],
    ) -> Dict[str, Any]:
        """Fetch and normalize the local Herdr host snapshot."""
        self.clear_git_metadata_cache()
        status_payload, agent_payload, pane_payload, workspace_payload, tab_payload, worktree_payload = await asyncio.gather(
            self.run_json(["status", "--json"]),
            self.run_json(["agent", "list"]),
            self.run_json(["pane", "list"]),
            self.run_json(["workspace", "list"]),
            self.run_json(["tab", "list"]),
            self.run_json(["worktree", "list"]),
        )
        host_key = self.normalize_host_key(local_host)
        local_connection_key = normalize_connection_key(f"local@{host_key}")
        generations = self.generations_snapshot()
        payloads = [
            status_payload,
            agent_payload,
            pane_payload,
            workspace_payload,
            tab_payload,
            worktree_payload,
        ]
        snapshot = {
            "success": bool(status_payload.get("success", False)),
            "herdr_generation": generations["local_herdr_generation"],
            "local_herdr_generation": generations["local_herdr_generation"],
            "remote_herdr_generation": generations["remote_herdr_generation"],
            "status": status_payload,
            "agents": self.annotate_rows(
                self.result_array(agent_payload, "agents"),
                host=host_key,
                execution_mode="local",
                connection_key=local_connection_key,
                normalize_connection_key=normalize_connection_key,
            ),
            "panes": self.annotate_rows(
                self.result_array(pane_payload, "panes"),
                host=host_key,
                execution_mode="local",
                connection_key=local_connection_key,
                normalize_connection_key=normalize_connection_key,
            ),
            "workspaces": self.annotate_rows(
                self.result_array(workspace_payload, "workspaces"),
                host=host_key,
                execution_mode="local",
                connection_key=local_connection_key,
                normalize_connection_key=normalize_connection_key,
            ),
            "tabs": self.annotate_rows(
                self.result_array(tab_payload, "tabs"),
                host=host_key,
                execution_mode="local",
                connection_key=local_connection_key,
                normalize_connection_key=normalize_connection_key,
            ),
            "worktrees": self.annotate_rows(
                self.worktree_result_array(worktree_payload),
                host=host_key,
                execution_mode="local",
                connection_key=local_connection_key,
                normalize_connection_key=normalize_connection_key,
            ),
            "errors": [
                {
                    "command": payload.get("command"),
                    "error": payload.get("error") or payload.get("stderr") or payload.get("stdout"),
                    "returncode": payload.get("returncode"),
                }
                for payload in payloads
                if not bool(payload.get("success", False))
            ],
        }
        snapshot["sessions"] = self.normalize_sessions(
            snapshot,
            local_host=host_key,
            normalize_connection_key=normalize_connection_key,
            project_for_cwd=project_for_cwd,
        )
        return snapshot

    async def proxy_snapshot(
        self,
        params: Optional[Dict[str, Any]] = None,
        *,
        local_host: Optional[str] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
        project_for_cwd: Optional[Callable[[str], Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        """Return a local-only compact snapshot for remote i3pm Herdr proxy clients."""
        resolved_local_host = local_host or self.configured_local_host()
        resolved_normalize_connection_key = normalize_connection_key or self._normalize_connection_key
        resolved_project_for_cwd = project_for_cwd or self.configured_project_for_cwd()
        snapshot = await self.local_snapshot(
            local_host=resolved_local_host,
            normalize_connection_key=resolved_normalize_connection_key,
            project_for_cwd=resolved_project_for_cwd,
        )
        snapshot.update({
            "schema_version": "i3pm.herdr_proxy.v1",
            "protocol_version": 1,
            "proxy_host": self.normalize_host_key(resolved_local_host),
            "generated_at": int(time.time()),
            "refresh": bool((params or {}).get("refresh", False)),
        })
        return snapshot

    async def proxy_pane_focus(
        self,
        params: Dict[str, Any],
        *,
        local_host: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Focus a local Herdr pane for remote proxy clients."""
        resolved_local_host = local_host or self.configured_local_host()
        result = await self.pane_focus(params)
        result["schema_version"] = "i3pm.herdr_proxy.v1"
        result["protocol_version"] = 1
        result["proxy_host"] = self.normalize_host_key(resolved_local_host)
        return result

    async def snapshot(
        self,
        params: Optional[Dict[str, Any]] = None,
        *,
        remote_targets: Optional[List[Dict[str, str]]] = None,
        local_host: Optional[str] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
        project_for_cwd: Optional[Callable[[str], Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        """Return local Herdr state merged with configured remote hosts."""
        params = params or {}
        resolved_remote_targets = remote_targets if remote_targets is not None else self.configured_remote_targets()
        resolved_local_host = local_host or self.configured_local_host()
        resolved_normalize_connection_key = normalize_connection_key or self._normalize_connection_key
        resolved_project_for_cwd = project_for_cwd or self.configured_project_for_cwd()
        use_cache = not bool(params.get("refresh", False))
        now = time.time()
        if use_cache:
            cached_snapshot = self.cached_snapshot(
                now=now,
                has_remote_targets=bool(resolved_remote_targets),
            )
            if cached_snapshot is not None:
                return cached_snapshot

        snapshot = await self.local_snapshot(
            local_host=resolved_local_host,
            normalize_connection_key=resolved_normalize_connection_key,
            project_for_cwd=resolved_project_for_cwd,
        )

        remote_snapshots = await asyncio.gather(
            *(
                self.remote_snapshot(
                    target,
                    local_host=resolved_local_host,
                    normalize_connection_key=resolved_normalize_connection_key,
                    project_for_cwd=resolved_project_for_cwd,
                )
                for target in resolved_remote_targets
            ),
            return_exceptions=True,
        )

        normalized_remote_snapshots: List[Dict[str, Any]] = []
        for index, remote_snapshot in enumerate(remote_snapshots):
            target = resolved_remote_targets[index]
            if isinstance(remote_snapshot, Exception):
                error_entry = {
                    "remote": True,
                    "host": str(target.get("host") or "").strip(),
                    "ssh_target": str(target.get("ssh_target") or "").strip(),
                    "connection_key": str(target.get("connection_key") or "").strip(),
                    "command": [
                        "ssh",
                        str(target.get("ssh_target") or "").strip(),
                        "i3pm",
                        "herdr-proxy",
                        "snapshot",
                        "--json",
                    ],
                    "error": str(remote_snapshot),
                    "returncode": None,
                }
                snapshot["errors"].append(error_entry)
                normalized_remote_snapshots.append({
                    "success": False,
                    "remote": True,
                    "host": error_entry["host"],
                    "ssh_target": error_entry["ssh_target"],
                    "connection_key": error_entry["connection_key"],
                    "herdr_generation": self.remote_generation_for(error_entry["host"]),
                    "errors": [error_entry],
                    "sessions": [],
                })
                continue
            if not isinstance(remote_snapshot, dict):
                continue
            normalized_remote_snapshots.append(remote_snapshot)
            snapshot["agents"].extend(remote_snapshot.get("agents", []) or [])
            snapshot["panes"].extend(remote_snapshot.get("panes", []) or [])
            snapshot["workspaces"].extend(remote_snapshot.get("workspaces", []) or [])
            snapshot["tabs"].extend(remote_snapshot.get("tabs", []) or [])
            snapshot["worktrees"].extend(remote_snapshot.get("worktrees", []) or [])
            snapshot["sessions"].extend([
                session for session in remote_snapshot.get("sessions", []) or []
                if isinstance(session, dict)
            ])
            snapshot["errors"].extend(remote_snapshot.get("errors", []) or [])

        snapshot["remote_targets"] = resolved_remote_targets
        snapshot["remote_snapshots"] = normalized_remote_snapshots
        snapshot["remote_herdr_generation"] = self.remote_generations_snapshot()
        snapshot["remote_errors"] = [
            error for error in snapshot.get("errors", [])
            if isinstance(error, dict) and bool(error.get("remote", False))
        ]
        snapshot["sessions"].sort(key=lambda item: (
            not bool(item.get("focused", False)),
            0 if bool(item.get("is_current_host", False)) else 1,
            str(item.get("herdr_host") or ""),
            str(item.get("project_name") or ""),
            str(item.get("agent") or ""),
            str(item.get("pane_id") or ""),
        ))
        return self.store_snapshot(snapshot, now=now)

    async def pane_focus(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a local Herdr pane and invalidate local Herdr state."""
        pane_id = str(params.get("pane_id") or "").strip()
        if not pane_id:
            raise ValueError("pane_id is required")
        result = await self.run_json(["agent", "focus", pane_id])
        if bool(result.get("success", False)):
            self.bump_local_generation()
            self.invalidate_snapshot_cache()
        return {"success": bool(result.get("success", False)), "pane_id": pane_id, "herdr": result}

    async def pane_close(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Close a local Herdr pane and invalidate local Herdr state."""
        pane_id = str(params.get("pane_id") or "").strip()
        if not pane_id:
            raise ValueError("pane_id is required")
        result = await self.run_json(["pane", "close", pane_id])
        if bool(result.get("success", False)):
            self.bump_local_generation()
        self.invalidate_snapshot_cache()
        return {"success": bool(result.get("success", False)), "pane_id": pane_id, "herdr": result}

    async def workspace_focus(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a local Herdr workspace and invalidate local Herdr state."""
        workspace_id = str(params.get("workspace_id") or "").strip()
        if not workspace_id:
            raise ValueError("workspace_id is required")
        result = await self.run_json(["workspace", "focus", workspace_id])
        if bool(result.get("success", False)):
            self.bump_local_generation()
            self.invalidate_snapshot_cache()
        return {
            "success": bool(result.get("success", False)),
            "workspace_id": workspace_id,
            "herdr": result,
        }

    async def tab_focus(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a local Herdr tab and invalidate local Herdr state."""
        tab_id = str(params.get("tab_id") or "").strip()
        if not tab_id:
            raise ValueError("tab_id is required")
        result = await self.run_json(["tab", "focus", tab_id])
        if bool(result.get("success", False)):
            self.bump_local_generation()
            self.invalidate_snapshot_cache()
        return {"success": bool(result.get("success", False)), "tab_id": tab_id, "herdr": result}

    async def remote_pane_focus(
        self,
        params: Dict[str, Any],
        *,
        targets: Optional[List[Dict[str, str]]] = None,
        parse_remote_target: Optional[Callable[[str], Tuple[str, str, int]]] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
        launch_open: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        set_focus_overrides: Callable[..., None],
    ) -> Dict[str, Any]:
        """Focus a remote Herdr pane and reuse the configured local Herdr app."""
        resolved_targets = targets if targets is not None else self.configured_remote_targets()
        normalize_key = normalize_connection_key or self._normalize_connection_key
        pane_id = str(params.get("pane_id") or "").strip()
        if not pane_id:
            raise ValueError("pane_id is required")

        target = self.resolve_remote_action_target(
            params,
            targets=resolved_targets,
            parse_remote_target=parse_remote_target,
            normalize_connection_key=normalize_key,
        )
        focus_result = await self.run_proxy_json(target, ["focus", pane_id, "--json"])
        if bool(focus_result.get("success", False)):
            self.bump_remote_generation(target.get("host"))
            cache_result = self.apply_remote_focus_cache(
                target=target,
                pane_id=pane_id,
                normalize_connection_key=normalize_key,
                now=time.time(),
            )
            focused_session_key = str(cache_result.get("focused_session_key") or "").strip()
            if focused_session_key:
                set_focus_overrides(
                    session_key=focused_session_key,
                    window_id=0,
                    connection_key=str(cache_result.get("connection_key") or "").strip(),
                )

        launch_result = await launch_open({
            "app_name": str(params.get("app_name") or "herdr").strip() or "herdr",
            "__intent_epoch": int(params.get("__intent_epoch") or 0),
            "focus_fast": True,
        })
        await self._notify_state_change("ai_session_herdr_changed")

        return {
            "success": bool(focus_result.get("success", False)) and bool(launch_result.get("success", False)),
            "pane_id": pane_id,
            "host": str(target.get("host") or "").strip(),
            "ssh_target": str(target.get("ssh_target") or "").strip(),
            "connection_key": str(target.get("connection_key") or "").strip(),
            "herdr": focus_result,
            "launch": launch_result,
        }

    def build_spaces(
        self,
        herdr_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
        *,
        local_host: Optional[str] = None,
        normalize_connection_key: Optional[Callable[[str], str]] = None,
    ) -> List[Dict[str, Any]]:
        """Build Herdr workspace/project rows for the persistent sidebar."""
        resolved_normalize_connection_key = normalize_connection_key or self._normalize_connection_key
        local_host = self.normalize_host_key(local_host or self.configured_local_host())
        spaces: Dict[str, Dict[str, Any]] = {}

        def host_key_for(item: Dict[str, Any]) -> str:
            return str(
                item.get("herdr_host")
                or item.get("host_name")
                or item.get("host")
                or local_host
            ).strip().lower() or local_host

        def workspace_id_for(item: Dict[str, Any]) -> str:
            return str(
                item.get("workspace_id")
                or item.get("workspace")
                or item.get("id")
                or ""
            ).strip()

        def text_field(item: Dict[str, Any], *keys: str) -> str:
            for key in keys:
                value = str(item.get(key) or "").strip()
                if value:
                    return value
            return ""

        def bool_field(item: Dict[str, Any], *keys: str) -> bool:
            for key in keys:
                if key in item:
                    return bool(item.get(key, False))
            return False

        def int_field(item: Dict[str, Any], *keys: str) -> int:
            for key in keys:
                value = item.get(key)
                if value is None:
                    continue
                try:
                    return int(value)
                except (TypeError, ValueError):
                    continue
            return 0

        def worktree_metadata_for(item: Dict[str, Any]) -> Dict[str, Any]:
            is_remote = bool(item.get("is_remote_herdr", False)) or str(item.get("execution_mode") or "") == "ssh"
            ssh_target = text_field(item, "ssh_target", "remote_target") if is_remote else ""
            nested = item.get("worktree")
            if not isinstance(nested, dict):
                nested = {}

            has_materialized_metadata = bool(
                text_field(
                    item,
                    "repo_key",
                    "repoKey",
                    "repo_name",
                    "repoName",
                    "repo_root",
                    "repoRoot",
                    "checkout_path",
                    "checkoutPath",
                    "branch_label",
                    "branchLabel",
                    "branch",
                )
                or text_field(
                    nested,
                    "repo_key",
                    "repoKey",
                    "repo_name",
                    "repoName",
                    "repo_root",
                    "repoRoot",
                    "checkout_path",
                    "checkoutPath",
                    "branch_label",
                    "branchLabel",
                    "branch",
                )
            )
            effective_cwd = (
                self.effective_cwd(item, ssh_target=ssh_target)
                if (not is_remote and not has_materialized_metadata)
                else ""
            )
            computed = self.git_space_metadata(
                effective_cwd,
                normalize_connection_key=resolved_normalize_connection_key,
            ) if effective_cwd else {}
            merged = dict(computed)
            merged.update(nested)
            for key in [
                "repo_key",
                "repoKey",
                "repo_name",
                "repoName",
                "repo_root",
                "repoRoot",
                "checkout_path",
                "checkoutPath",
                "is_linked_worktree",
                "isLinkedWorktree",
                "branch",
                "branch_label",
                "branchLabel",
                "path",
                "workspace_id",
            ]:
                if key in item:
                    merged[key] = item.get(key)

            checkout_path = text_field(
                merged,
                "checkout_path",
                "checkoutPath",
                "path",
                "worktree_path",
                "worktreePath",
            )
            return {
                "repo_key": text_field(merged, "repo_key", "repoKey", "repository_key", "repositoryKey"),
                "repo_name": text_field(merged, "repo_name", "repoName", "repository", "repository_name"),
                "repo_root": text_field(merged, "repo_root", "repoRoot", "root", "repository_root"),
                "checkout_path": checkout_path,
                "is_linked_worktree": bool_field(merged, "is_linked_worktree", "isLinkedWorktree", "linked", "is_linked"),
                "branch_label": text_field(merged, "branch_label", "branchLabel", "branch"),
            }

        def workspace_label_for(item: Dict[str, Any], workspace_id: str) -> str:
            label = str(
                item.get("label")
                or item.get("name")
                or item.get("title")
                or item.get("workspace_name")
                or ""
            ).strip()
            return label or workspace_id or "Workspace"

        def worktree_enrichment_index() -> Dict[Tuple[str, str], Dict[str, Any]]:
            index: Dict[Tuple[str, str], Dict[str, Any]] = {}
            for raw in herdr_snapshot.get("worktrees", []) or []:
                if not isinstance(raw, dict):
                    continue
                host_key = host_key_for(raw)
                workspace_id = workspace_id_for(raw)
                metadata = worktree_metadata_for(raw)
                branch_label = text_field(raw, "branch_label", "branchLabel", "branch") or metadata["branch_label"]
                enriched = {**metadata, "branch_label": branch_label}
                for key in [
                    workspace_id,
                    metadata["checkout_path"],
                    f"{metadata['repo_key']}::{metadata['checkout_path']}",
                    f"{metadata['repo_key']}::{branch_label}",
                ]:
                    normalized_key = str(key or "").strip()
                    if normalized_key:
                        index[(host_key, normalized_key)] = enriched
            return index

        worktree_index = worktree_enrichment_index()

        def enrich_worktree(host_key: str, workspace_id: str, metadata: Dict[str, Any]) -> Dict[str, Any]:
            enriched = dict(metadata)
            for key in [
                workspace_id,
                metadata.get("checkout_path", ""),
                f"{metadata.get('repo_key', '')}::{metadata.get('checkout_path', '')}",
                f"{metadata.get('repo_key', '')}::{metadata.get('branch_label', '')}",
            ]:
                candidate = worktree_index.get((host_key, str(key or "").strip()))
                if not candidate:
                    continue
                for field, value in candidate.items():
                    if value and not enriched.get(field):
                        enriched[field] = value
            return enriched

        def ensure_space(
            *,
            host_key: str,
            workspace_id: str,
            label: str,
            execution_mode: str,
            is_current_host: bool,
            focused: bool = False,
            focus_target: Optional[Dict[str, Any]] = None,
            label_source: str = "fallback",
            workspace_number: int = 0,
            active_tab_id: str = "",
            worktree_metadata: Optional[Dict[str, Any]] = None,
        ) -> Dict[str, Any]:
            normalized_workspace = workspace_id or "unknown"
            space_key = f"herdr:{host_key}:workspace:{normalized_workspace}"
            metadata = worktree_metadata or {}
            existing = spaces.get(space_key)
            if existing is None:
                existing = {
                    "space_key": space_key,
                    "host_key": host_key,
                    "host_label": host_key,
                    "workspace_id": workspace_id,
                    "workspace_number": int(workspace_number or 0),
                    "active_tab_id": str(active_tab_id or "").strip(),
                    "label": label,
                    "focused": bool(focused),
                    "agent_status": "unknown",
                    "agent_count": 0,
                    "pane_count": 0,
                    "tab_count": 0,
                    "project_name": "global",
                    "execution_mode": execution_mode,
                    "is_current_host": bool(is_current_host),
                    "group_key": "",
                    "repo_key": str(metadata.get("repo_key") or "").strip(),
                    "repo_name": str(metadata.get("repo_name") or "").strip(),
                    "repo_root": str(metadata.get("repo_root") or "").strip(),
                    "checkout_path": str(metadata.get("checkout_path") or "").strip(),
                    "is_linked_worktree": bool(metadata.get("is_linked_worktree", False)),
                    "is_group_parent": False,
                    "group_member_count": 1,
                    "branch_label": str(metadata.get("branch_label") or "").strip(),
                    "_label_source": label_source,
                }
                if focus_target:
                    existing["focus_target"] = focus_target
                spaces[space_key] = existing
            else:
                existing["focused"] = bool(existing.get("focused", False)) or bool(focused)
                existing_label_source = str(existing.get("_label_source") or "fallback")
                label_is_workspace = label_source == "workspace"
                existing_is_workspace = existing_label_source == "workspace"
                if label and (
                    not str(existing.get("label") or "").strip()
                    or (label_is_workspace and not existing_is_workspace)
                ):
                    existing["label"] = label
                    existing["_label_source"] = label_source
                if focus_target and not existing.get("focus_target"):
                    existing["focus_target"] = focus_target
                if workspace_number and not int(existing.get("workspace_number") or 0):
                    existing["workspace_number"] = int(workspace_number)
                if active_tab_id and not str(existing.get("active_tab_id") or "").strip():
                    existing["active_tab_id"] = active_tab_id
                for key in ["repo_key", "repo_name", "repo_root", "checkout_path", "branch_label"]:
                    value = str(metadata.get(key) or "").strip()
                    if value and not str(existing.get(key) or "").strip():
                        existing[key] = value
                if metadata.get("is_linked_worktree"):
                    existing["is_linked_worktree"] = True
            return existing

        workspaces = [
            item for item in herdr_snapshot.get("workspaces", []) or []
            if isinstance(item, dict)
        ]
        for workspace in workspaces:
            host_key = host_key_for(workspace)
            workspace_id = workspace_id_for(workspace)
            is_remote = bool(workspace.get("is_remote_herdr", False))
            execution_mode = str(workspace.get("execution_mode") or ("ssh" if is_remote else "local")).strip() or "local"
            focus_target = None
            if workspace_id and not is_remote:
                focus_target = {
                    "method": "herdr.workspace.focus",
                    "params": {"workspace_id": workspace_id},
                }
            metadata = enrich_worktree(host_key, workspace_id, worktree_metadata_for(workspace))
            ensure_space(
                host_key=host_key,
                workspace_id=workspace_id,
                label=workspace_label_for(workspace, workspace_id),
                execution_mode=execution_mode,
                is_current_host=not is_remote,
                focused=bool(workspace.get("focused", False)),
                focus_target=focus_target,
                label_source="workspace",
                workspace_number=int_field(workspace, "workspace_number", "number", "index"),
                active_tab_id=text_field(workspace, "active_tab_id", "activeTabId", "current_tab_id", "focused_tab_id"),
                worktree_metadata=metadata,
            )

        herdr_sessions = [
            session for session in sessions
            if isinstance(session, dict)
            and (
                str(session.get("source") or "").strip() == "herdr"
                or str(session.get("pane_id") or "").strip()
            )
        ]
        for session in herdr_sessions:
            host_key = host_key_for(session)
            workspace_id = workspace_id_for(session)
            project_name = str(session.get("project_name") or session.get("project") or "global").strip() or "global"
            label = project_name.rsplit("/", 1)[-1] if project_name != "global" else workspace_id or "Workspace"
            is_remote = bool(session.get("is_remote_herdr", False))
            metadata = enrich_worktree(host_key, workspace_id, worktree_metadata_for(session))
            space = ensure_space(
                host_key=host_key,
                workspace_id=workspace_id,
                label=label,
                execution_mode=str(session.get("execution_mode") or ("ssh" if is_remote else "local")).strip() or "local",
                is_current_host=bool(session.get("is_current_host", not is_remote)),
                focused=bool(session.get("focused", False)),
                label_source="session",
                worktree_metadata=metadata,
            )
            current_status = str(space.get("agent_status") or "unknown").strip()
            candidate_status = self.agent_status_state(session.get("agent_status"))
            if self.agent_status_rank(candidate_status) > self.agent_status_rank(current_status):
                space["agent_status"] = candidate_status
            if bool(session.get("focused", False)) or str(space.get("project_name") or "global") == "global":
                space["project_name"] = project_name

        for space in spaces.values():
            host_key = str(space.get("host_key") or "").strip().lower()
            workspace_id = str(space.get("workspace_id") or "").strip()

            matching_sessions = [
                session for session in herdr_sessions
                if host_key_for(session) == host_key and workspace_id_for(session) == workspace_id
            ]
            matching_panes = [
                pane for pane in herdr_snapshot.get("panes", []) or []
                if isinstance(pane, dict)
                and host_key_for(pane) == host_key
                and workspace_id_for(pane) == workspace_id
            ]
            matching_tabs = [
                tab for tab in herdr_snapshot.get("tabs", []) or []
                if isinstance(tab, dict)
                and host_key_for(tab) == host_key
                and workspace_id_for(tab) == workspace_id
            ]
            matching_agents = [
                agent for agent in herdr_snapshot.get("agents", []) or []
                if isinstance(agent, dict)
                and host_key_for(agent) == host_key
                and workspace_id_for(agent) == workspace_id
            ]

            space["agent_count"] = max(len(matching_sessions), len(matching_agents))
            space["pane_count"] = len(matching_panes)
            space["tab_count"] = len(matching_tabs)
            if not str(space.get("project_name") or "").strip():
                space["project_name"] = "global"

        has_agent_spaces = any(int(space.get("agent_count", 0) or 0) > 0 for space in spaces.values())
        if has_agent_spaces:
            agent_group_keys = {
                f"{space.get('host_key')}:{str(space.get('repo_key') or '').strip()}"
                for space in spaces.values()
                if int(space.get("agent_count", 0) or 0) > 0
                and str(space.get("repo_key") or "").strip()
                and str(space.get("checkout_path") or "").strip()
            }
            spaces = {
                key: space
                for key, space in spaces.items()
                if int(space.get("agent_count", 0) or 0) > 0
                or (
                    not bool(space.get("is_linked_worktree", False))
                    and f"{space.get('host_key')}:{str(space.get('repo_key') or '').strip()}" in agent_group_keys
                )
            }

        group_counts: Dict[str, int] = {}
        group_has_parent: Dict[str, bool] = {}
        group_has_child: Dict[str, bool] = {}
        for space in spaces.values():
            repo_key = str(space.get("repo_key") or "").strip()
            checkout_path = str(space.get("checkout_path") or "").strip()
            if not repo_key or not checkout_path:
                continue
            candidate_group = f"{space.get('host_key')}:{repo_key}"
            group_counts[candidate_group] = group_counts.get(candidate_group, 0) + 1
            if bool(space.get("is_linked_worktree", False)):
                group_has_child[candidate_group] = True
            else:
                group_has_parent[candidate_group] = True

        for space in spaces.values():
            repo_key = str(space.get("repo_key") or "").strip()
            checkout_path = str(space.get("checkout_path") or "").strip()
            candidate_group = f"{space.get('host_key')}:{repo_key}" if repo_key and checkout_path else ""
            if (
                candidate_group
                and group_counts.get(candidate_group, 0) > 1
                and group_has_parent.get(candidate_group, False)
                and group_has_child.get(candidate_group, False)
            ):
                space["group_key"] = candidate_group
                space["group_member_count"] = group_counts[candidate_group]
                space["is_group_parent"] = not bool(space.get("is_linked_worktree", False))
            else:
                space["group_key"] = ""
                space["group_member_count"] = 1
                space["is_group_parent"] = False

        focused_session_space_keys = []
        for session in herdr_sessions:
            if not bool(session.get("focused", False)):
                continue
            host_key = host_key_for(session)
            workspace_id = workspace_id_for(session)
            normalized_workspace = workspace_id or "unknown"
            focused_session_space_keys.append(f"herdr:{host_key}:workspace:{normalized_workspace}")

        selected_focused_space = next(
            (space_key for space_key in focused_session_space_keys if space_key in spaces),
            None,
        )
        if selected_focused_space is None:
            focused_spaces = [
                str(space.get("space_key") or "")
                for space in spaces.values()
                if bool(space.get("focused", False))
            ]
            selected_focused_space = next(
                (
                    space_key for space_key in focused_spaces
                    if bool(spaces.get(space_key, {}).get("is_current_host", False))
                ),
                focused_spaces[0] if focused_spaces else None,
            )

        for space in spaces.values():
            space["focused"] = (
                bool(selected_focused_space)
                and str(space.get("space_key") or "") == selected_focused_space
            )
            space.pop("_label_source", None)

        return sorted(spaces.values(), key=lambda item: (
            not bool(item.get("focused", False)),
            0 if bool(item.get("is_current_host", False)) else 1,
            str(item.get("host_key") or ""),
            str(item.get("group_key") or str(item.get("space_key") or "")),
            1 if bool(item.get("is_linked_worktree", False)) else 0,
            str(item.get("label") or ""),
            str(item.get("workspace_id") or ""),
        ))


    @staticmethod
    def ssh_command_prefix(ssh_target: str) -> List[str]:
        """Return the deterministic SSH transport prefix for remote Herdr calls."""
        return [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=1",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=1",
            "-o", "ServerAliveCountMax=1",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=30s",
            "-o", "ControlPath=/tmp/i3pm-herdr-ssh-%C",
            ssh_target,
        ]

    @staticmethod
    def _json_payload_from_completed_process(
        result: subprocess.CompletedProcess[str],
        *,
        command: List[str],
    ) -> Dict[str, Any]:
        stdout = str(result.stdout or "").strip()
        stderr = str(result.stderr or "").strip()
        payload: Dict[str, Any] = {}
        if stdout:
            try:
                parsed = json.loads(stdout)
                if isinstance(parsed, dict):
                    payload = parsed
            except json.JSONDecodeError:
                payload = {}

        payload.setdefault("success", result.returncode == 0)
        payload.setdefault("returncode", result.returncode)
        payload.setdefault("stdout", stdout)
        payload.setdefault("stderr", stderr)
        payload.setdefault("command", command)
        return payload

    async def run_json(self, args: List[str], timeout: float = 2.0) -> Dict[str, Any]:
        """Run a local Herdr CLI command that returns a single JSON object."""
        command = ["herdr", *args]
        if not shutil.which("herdr"):
            return {
                "success": False,
                "error": "herdr_not_found",
                "command": command,
            }

        def run() -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )

        try:
            result = await asyncio.to_thread(run)
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "timeout",
                "command": command,
            }

        return self._json_payload_from_completed_process(result, command=command)

    async def run_proxy_json(
        self,
        target: Dict[str, str],
        args: List[str],
        timeout: float = 2.5,
    ) -> Dict[str, Any]:
        """Run the remote host's i3pm Herdr proxy over one bounded SSH command."""
        ssh_target = str(target.get("ssh_target") or "").strip()
        fallback_command = ["ssh", ssh_target, "i3pm", "herdr-proxy", *args]
        if not ssh_target:
            return {
                "success": False,
                "error": "missing_ssh_target",
                "command": ["ssh", "", "i3pm", "herdr-proxy", *args],
            }
        if not shutil.which("ssh"):
            return {
                "success": False,
                "error": "ssh_not_found",
                "command": fallback_command,
            }

        command = self.ssh_command_prefix(ssh_target) + ["i3pm", "herdr-proxy", *args]

        def run() -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )

        try:
            result = await asyncio.to_thread(run)
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "timeout",
                "command": fallback_command,
            }

        payload = self._json_payload_from_completed_process(
            result,
            command=fallback_command,
        )
        payload.setdefault("herdr_host", str(target.get("host") or "").strip())
        payload.setdefault("ssh_target", ssh_target)
        payload.setdefault("connection_key", str(target.get("connection_key") or "").strip())
        return payload

    def socket_path(self) -> Path:
        """Return the local Herdr API socket path."""
        override = str(os.environ.get(self._socket_env_var) or "").strip()
        if override:
            return Path(os.path.expanduser(override))
        return Path.home() / ".config" / "herdr" / "herdr.sock"

    def event_subscribe_payload(self) -> Dict[str, Any]:
        """Return the JSON-RPC payload for Herdr's event stream API."""
        return {
            "id": "i3pm-herdr-events",
            "method": "events.subscribe",
            "params": {
                "subscriptions": [
                    {"type": event_type}
                    for event_type in HERDR_EVENT_SUBSCRIPTION_TYPES
                ],
            },
        }

    async def write_json_line(
        self,
        writer: asyncio.StreamWriter,
        payload: Dict[str, Any],
    ) -> None:
        writer.write(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
        await writer.drain()

    async def read_json_line(
        self,
        reader: asyncio.StreamReader,
        *,
        timeout: Optional[float] = None,
    ) -> Dict[str, Any]:
        if timeout:
            line = await asyncio.wait_for(reader.readline(), timeout=timeout)
        else:
            line = await reader.readline()
        if not line:
            raise ConnectionError("Herdr event stream closed")
        payload = json.loads(line.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Herdr event stream returned non-object JSON")
        return payload

    async def connect_subscription_once(self) -> None:
        """Connect once to the local Herdr event stream and process events until close."""
        socket_path = self.socket_path()
        reader, writer = await asyncio.open_unix_connection(str(socket_path))
        try:
            request = self.event_subscribe_payload()
            await self.write_json_line(writer, request)
            ack = await self.read_json_line(reader, timeout=3.0)
            result = ack.get("result") if isinstance(ack, dict) else {}
            if (
                ack.get("id") != request["id"]
                or not isinstance(result, dict)
                or result.get("type") != "subscription_started"
            ):
                raise RuntimeError(f"Herdr event subscription failed: {ack}")
            logger.info("Subscribed to local Herdr events at %s", socket_path)

            while True:
                event = await self.read_json_line(reader)
                await self.handle_subscription_event(event)
        finally:
            writer.close()
            await self._close_writer(writer)

    async def run_subscription(self) -> None:
        """Maintain a local Herdr event subscription with bounded reconnect backoff."""
        backoff = self.subscription_initial_backoff
        while True:
            try:
                await self.connect_subscription_once()
                backoff = self.subscription_initial_backoff
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.debug("Local Herdr event subscription unavailable: %s", exc)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, self.subscription_max_backoff)

    def start_subscription(self) -> None:
        """Start local and configured remote Herdr event subscription tasks."""
        if self.subscription_task and not self.subscription_task.done():
            pass
        else:
            self.subscription_task = asyncio.create_task(
                self.run_subscription(),
                name="i3pm-herdr-event-subscription",
            )
        self.sync_remote_proxy_subscriptions(self.load_remote_targets())

    def sync_remote_proxy_subscriptions(self, targets: List[Dict[str, str]]) -> None:
        """Ensure one remote Herdr proxy event stream task per configured target."""
        desired_keys: Set[str] = set()
        for target in targets:
            key = self.remote_subscription_key(target)
            if not key:
                continue
            desired_keys.add(key)
            existing = self.remote_subscription_tasks.get(key)
            if existing is not None and not existing.done():
                continue
            self.remote_subscription_tasks[key] = asyncio.create_task(
                self.run_remote_proxy_subscription(dict(target)),
                name=f"i3pm-herdr-remote-proxy-{key}",
            )

        for key, task in list(self.remote_subscription_tasks.items()):
            if key in desired_keys:
                continue
            self.remote_subscription_tasks.pop(key, None)
            if not task.done():
                task.cancel()

    async def stop_subscription(self) -> None:
        """Cancel Herdr event subscription and pending notification tasks."""
        notify_task = self.notify_task
        self.notify_task = None
        if notify_task and not notify_task.done():
            notify_task.cancel()
            await asyncio.gather(notify_task, return_exceptions=True)

        task = self.subscription_task
        self.subscription_task = None
        if not task or task.done():
            pass
        else:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

        remote_tasks = list(self.remote_subscription_tasks.values())
        self.remote_subscription_tasks = {}
        for remote_task in remote_tasks:
            if not remote_task.done():
                remote_task.cancel()
        if remote_tasks:
            await asyncio.gather(*remote_tasks, return_exceptions=True)

    async def connect_remote_proxy_subscription_once(self, target: Dict[str, str]) -> None:
        """Connect once to a remote i3pm Herdr proxy event stream over SSH."""
        ssh_target = str(target.get("ssh_target") or "").strip()
        if not ssh_target:
            raise ValueError("ssh_target is required for remote Herdr proxy events")
        command = self.ssh_command_prefix(ssh_target) + ["i3pm", "herdr-proxy", "events", "--jsonl"]
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            if process.stdout is None:
                raise RuntimeError("remote Herdr proxy stream missing stdout")
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                payload = json.loads(line.decode("utf-8"))
                if not isinstance(payload, dict):
                    continue
                await self.handle_remote_proxy_event(target, payload)
            returncode = await process.wait()
            if returncode != 0:
                raise RuntimeError(f"remote Herdr proxy stream exited with {returncode}")
        finally:
            if process.returncode is None:
                process.terminate()
                try:
                    await asyncio.wait_for(process.wait(), timeout=1.0)
                except TimeoutError:
                    process.kill()
                    await process.wait()

    async def run_remote_proxy_subscription(self, target: Dict[str, str]) -> None:
        """Maintain one remote Herdr proxy event stream with bounded reconnect backoff."""
        backoff = self.subscription_initial_backoff
        host = self.normalize_host_key(target.get("host") or target.get("ssh_target"))
        while True:
            try:
                await self.connect_remote_proxy_subscription_once(target)
                backoff = self.subscription_initial_backoff
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.debug("Remote Herdr proxy subscription unavailable for %s: %s", host, exc)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, self.subscription_max_backoff)

    async def handle_remote_proxy_event(self, target: Dict[str, str], event: Dict[str, Any]) -> None:
        """Invalidate Herdr-derived dashboard state after a remote proxy event."""
        if not isinstance(event, dict):
            return
        if str(event.get("schema_version") or "") != "i3pm.herdr_proxy.event.v1":
            return
        self.bump_remote_generation(target.get("host") or target.get("ssh_target"))
        self.invalidate_snapshot_cache()
        self.schedule_state_change_notification()

    async def handle_subscription_event(self, event: Dict[str, Any]) -> None:
        """Invalidate Herdr-derived dashboard state after a local Herdr event."""
        if not isinstance(event, dict):
            return
        self.bump_local_generation()
        self.invalidate_snapshot_cache()
        self.schedule_state_change_notification()

    def schedule_state_change_notification(self) -> None:
        """Coalesce bursts of local Herdr socket events into one dashboard update."""
        task = self.notify_task
        if task is not None and not task.done():
            return

        async def notify_later() -> None:
            try:
                delay = max(0.0, float(self.notify_delay))
                if delay > 0:
                    await asyncio.sleep(delay)
                await self._notify_state_change("ai_session_herdr_changed")
            except asyncio.CancelledError:
                raise
            finally:
                current = self.notify_task
                if current is task_ref:
                    self.notify_task = None

        task_ref = asyncio.create_task(
            notify_later(),
            name="i3pm-herdr-event-notify",
        )
        self.notify_task = task_ref

    @staticmethod
    async def _close_writer(writer: asyncio.StreamWriter) -> None:
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout=0.5)
        except TimeoutError:
            logger.debug("Timed out waiting for Herdr event socket to close; continuing")
