"""Herdr service boundary for local event subscription and cache invalidation."""

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
from pathlib import Path, PurePath
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

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
    ) -> None:
        self._notify_state_change = notify_state_change
        self._external_invalidate_snapshot_cache = invalidate_snapshot_cache
        self._socket_env_var = socket_env_var
        self.subscription_initial_backoff = subscription_initial_backoff
        self.subscription_max_backoff = subscription_max_backoff
        self.notify_delay = notify_delay
        self.subscription_task: Optional[asyncio.Task] = None
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

    @staticmethod
    def _default_normalize_project_path(value: Optional[str]) -> Optional[str]:
        text = str(value or "").strip()
        if not text:
            return None
        return str(Path(text).expanduser())

    @staticmethod
    def normalize_host_key(host: Any) -> str:
        """Normalize a Herdr host key for generation tracking."""
        return str(host or "").strip().lower()

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
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> str:
        """Return a normalized connection key for a remote Herdr target."""
        explicit_key = str(explicit or "").strip()
        if explicit_key:
            return normalize_connection_key(explicit_key)
        user, host, port = parse_remote_target(ssh_target)
        if not host:
            return "unknown"
        user = user or os.environ.get("USER") or "vpittamp"
        return normalize_connection_key(f"{user}@{host}:{port or 22}")

    def load_remote_targets(
        self,
        *,
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> List[Dict[str, str]]:
        """Load and normalize configured remote Herdr targets."""
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
                _user, parsed_host, _port = parse_remote_target(ssh_target)
                host = parsed_host.lower()
            connection_key = self.connection_key_for_target(
                ssh_target,
                str(item.get("connection_key") or item.get("connectionKey") or ""),
                parse_remote_target=parse_remote_target,
                normalize_connection_key=normalize_connection_key,
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
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> Dict[str, str]:
        """Resolve a remote Herdr action target from request params and config."""
        host = str(params.get("host") or params.get("herdr_host") or "").strip().lower()
        ssh_target = str(params.get("ssh_target") or params.get("remote_target") or "").strip()
        connection_key = normalize_connection_key(str(params.get("connection_key") or "").strip())

        for target in targets:
            target_host = str(target.get("host") or "").strip().lower()
            target_ssh = str(target.get("ssh_target") or "").strip()
            target_connection = normalize_connection_key(str(target.get("connection_key") or "").strip())
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
                    parse_remote_target=parse_remote_target,
                    normalize_connection_key=normalize_connection_key,
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
    ) -> List[Dict[str, Any]]:
        """Add normalized host/execution fields to Herdr rows."""
        annotated: List[Dict[str, Any]] = []
        host_key = self.normalize_host_key(host)
        normalized_connection = normalize_connection_key(connection_key)
        for row in rows:
            item = dict(row)
            item.setdefault("host_name", host_key)
            item.setdefault("herdr_host", host_key)
            item.setdefault("target_host", host_key)
            item.setdefault("execution_mode", execution_mode)
            item.setdefault("connection_key", normalized_connection)
            item.setdefault("ssh_target", ssh_target)
            item.setdefault("remote_target", ssh_target)
            item.setdefault("is_remote_herdr", bool(is_remote))
            item.setdefault("is_current_host", not bool(is_remote))
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

        normalized = dict(row)
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
        """Fetch and normalize one remote Herdr host snapshot."""
        self.clear_git_metadata_cache()
        status_payload = await self.run_ssh_json(target, ["status", "--json"])
        agent_payload = await self.run_ssh_json(target, ["agent", "list"])
        pane_payload = await self.run_ssh_json(target, ["pane", "list"])
        workspace_payload = await self.run_ssh_json(target, ["workspace", "list"])
        tab_payload = await self.run_ssh_json(target, ["tab", "list"])
        worktree_payload = await self.run_ssh_json(target, ["worktree", "list"])
        payloads = [
            status_payload,
            agent_payload,
            pane_payload,
            workspace_payload,
            tab_payload,
            worktree_payload,
        ]
        host = str(target.get("host") or "").strip()
        ssh_target = str(target.get("ssh_target") or "").strip()
        connection_key = str(target.get("connection_key") or "").strip()
        errors = [
            {
                "remote": True,
                "host": host,
                "ssh_target": ssh_target,
                "connection_key": connection_key,
                "command": payload.get("command"),
                "error": payload.get("error") or payload.get("stderr") or payload.get("stdout"),
                "returncode": payload.get("returncode"),
            }
            for payload in payloads
            if not bool(payload.get("success", False))
        ]
        if not bool(status_payload.get("success", False)):
            return {
                "success": False,
                "remote": True,
                "host": host,
                "ssh_target": ssh_target,
                "connection_key": connection_key,
                "herdr_generation": self.remote_generation_for(host),
                "status": status_payload,
                "agents": [],
                "panes": [],
                "workspaces": [],
                "tabs": [],
                "worktrees": [],
                "sessions": [],
                "errors": errors,
            }

        snapshot = {
            "success": True,
            "remote": True,
            "host": host,
            "ssh_target": ssh_target,
            "connection_key": connection_key,
            "herdr_generation": self.bump_remote_generation(host),
            "status": status_payload,
            "agents": self.annotate_rows(
                self.result_array(agent_payload, "agents"),
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
            ),
            "panes": self.annotate_rows(
                self.result_array(pane_payload, "panes"),
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
            ),
            "workspaces": self.annotate_rows(
                self.result_array(workspace_payload, "workspaces"),
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
            ),
            "tabs": self.annotate_rows(
                self.result_array(tab_payload, "tabs"),
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
            ),
            "worktrees": self.annotate_rows(
                self.worktree_result_array(worktree_payload),
                host=host,
                execution_mode="ssh",
                connection_key=connection_key,
                ssh_target=ssh_target,
                is_remote=True,
                normalize_connection_key=normalize_connection_key,
            ),
            "errors": errors,
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

    async def run_ssh_json(
        self,
        target: Dict[str, str],
        args: List[str],
        timeout: float = 2.5,
    ) -> Dict[str, Any]:
        """Run a Herdr command on a remote host over SSH."""
        ssh_target = str(target.get("ssh_target") or "").strip()
        fallback_command = ["ssh", ssh_target, "herdr", *args]
        if not ssh_target:
            return {
                "success": False,
                "error": "missing_ssh_target",
                "command": ["ssh", "", "herdr", *args],
            }
        if not shutil.which("ssh"):
            return {
                "success": False,
                "error": "ssh_not_found",
                "command": fallback_command,
            }

        command = self.ssh_command_prefix(ssh_target) + ["herdr", *args]

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
        """Start the local Herdr event subscription task."""
        if self.subscription_task and not self.subscription_task.done():
            return
        self.subscription_task = asyncio.create_task(
            self.run_subscription(),
            name="i3pm-herdr-event-subscription",
        )

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
            return
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

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
