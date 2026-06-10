"""Launch persistence service for daemon-owned launch specs and status."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, Iterable, List, Optional, Tuple

from ..config import atomic_write_json
from ..models import PendingLaunch
from ..worktree_utils import canonicalize_context_key, parse_qualified_name

logger = logging.getLogger(__name__)


class LaunchService:
    """Own deterministic launch runtime files, specs, and status payloads."""

    def __init__(
        self,
        *,
        runtime_dir: Callable[[], Path],
        load_json_file: Callable[[Path], Dict[str, Any]],
        normalize_target_host: Callable[[Any], str],
        parse_context_target_host: Callable[[Any], str],
        transport_kind_for_target_host: Callable[[Any], str],
        local_host_alias: Callable[[], str],
        resolve_terminal_launch_transport: Optional[Callable[..., str]] = None,
        tmux_command_prefix: Optional[Callable[[str], str]] = None,
        canonical_tmux_socket: Optional[Callable[[], str]] = None,
        resolve_terminal_helper: Optional[Callable[[str], Path]] = None,
        run_command: Optional[Callable[..., subprocess.CompletedProcess[str]]] = None,
        repo_root: Optional[Callable[[], Path]] = None,
        which: Optional[Callable[[str], Optional[str]]] = None,
        schedule_launch_reconcile: Optional[Callable[..., None]] = None,
        get_terminal_anchor: Optional[Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]]] = None,
        window_map_items: Optional[Callable[[], Iterable[Tuple[int, Any]]]] = None,
        get_pending_launch_by_terminal_anchor: Optional[Callable[[str], Awaitable[Any]]] = None,
        launch_registry: Optional[Callable[[], Any]] = None,
        require_registry_app: Optional[Callable[[str], Any]] = None,
        resolve_remote_attach_profile: Optional[Callable[[Dict[str, Any]], Dict[str, Any]]] = None,
        build_remote_attach_runtime_context: Optional[Callable[[Dict[str, Any]], Dict[str, Any]]] = None,
        remote_session_terminal_role: Optional[Callable[[str], str]] = None,
        find_live_window: Optional[Callable[[int], Awaitable[Any]]] = None,
        remove_window: Optional[Callable[[int], Awaitable[Any]]] = None,
        invalidate_window_tree_cache: Optional[Callable[[], None]] = None,
    ) -> None:
        self._runtime_dir = runtime_dir
        self._load_json_file = load_json_file
        self._normalize_target_host = normalize_target_host
        self._parse_context_target_host = parse_context_target_host
        self._transport_kind_for_target_host = transport_kind_for_target_host
        self._local_host_alias = local_host_alias
        self._resolve_terminal_launch_transport = resolve_terminal_launch_transport
        self._tmux_command_prefix = tmux_command_prefix or self._default_tmux_command_prefix
        self._canonical_tmux_socket = canonical_tmux_socket or (lambda: "")
        self._resolve_terminal_helper = resolve_terminal_helper
        self._run_command = run_command or subprocess.run
        self._repo_root = repo_root
        self._which = which or shutil.which
        self._schedule_launch_reconcile_callback = schedule_launch_reconcile
        self._get_terminal_anchor = get_terminal_anchor
        self._window_map_items = window_map_items
        self._get_pending_launch_by_terminal_anchor = get_pending_launch_by_terminal_anchor
        self._launch_registry = launch_registry
        self._require_registry_app = require_registry_app
        self._resolve_remote_attach_profile = resolve_remote_attach_profile
        self._build_remote_attach_runtime_context = build_remote_attach_runtime_context
        self._remote_session_terminal_role = remote_session_terminal_role
        self._find_live_window = find_live_window
        self._remove_window = remove_window
        self._invalidate_window_tree_cache = invalidate_window_tree_cache
        self._launch_reconcile_tasks: Dict[str, asyncio.Task] = {}

    @staticmethod
    def _quote(value: Any) -> str:
        return shlex.quote(str(value))

    @staticmethod
    def _default_tmux_command_prefix(tmux_socket: str = "") -> str:
        socket_path = str(tmux_socket or "").strip()
        if socket_path:
            return f"tmux -S {shlex.quote(socket_path)}"
        return "tmux"

    def runtime_dir(self) -> Path:
        """Return the runtime directory used for deterministic launch specs and status."""
        return self._runtime_dir() / "i3-project-daemon" / "launches"

    def status_file(self, launch_id: str) -> Path:
        """Return the canonical launch-status file for a launch id."""
        return self.runtime_dir() / f"{str(launch_id or '').strip()}.status.json"

    def spec_file(self, launch_id: str) -> Path:
        """Return the canonical launch-spec file for a launch id."""
        return self.runtime_dir() / f"{str(launch_id or '').strip()}.spec.json"

    def read_spec(self, launch_id: str) -> Dict[str, Any]:
        """Return persisted spec for a deterministic launch id."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return {}
        payload = self._load_json_file(self.spec_file(launch_key))
        if not payload:
            return {}
        payload.setdefault("launch_id", launch_key)
        return payload

    def write_spec_payload(
        self,
        *,
        launch_id: str,
        payload: Dict[str, Any],
    ) -> Path:
        """Persist an exact launch payload for reconciliation and diagnostics."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            raise RuntimeError("launch_id is required for launch spec")
        spec_file = self.spec_file(launch_key)
        spec_file.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(spec_file, payload)
        return spec_file

    def write_status(
        self,
        *,
        launch_id: str,
        status: str,
        spec: Optional[Dict[str, Any]] = None,
        error_code: str = "",
        error_message: str = "",
        reason: str = "",
        extra: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Persist deterministic launch status for UI and RPC consumers."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            raise RuntimeError("launch_id is required for launch status")
        payload = {
            "launch_id": launch_key,
            "status": str(status or "").strip() or "queued",
            "error_code": str(error_code or "").strip(),
            "error_message": str(error_message or "").strip(),
            "reason": str(reason or "").strip(),
            "updated_at": int(time.time()),
        }
        if isinstance(spec, dict):
            target_host = (
                spec.get("target_host")
                or self._parse_context_target_host(spec.get("context_key"))
                or ""
            )
            transport_host = (
                spec.get("target_host")
                or self._parse_context_target_host(spec.get("context_key"))
                or self._local_host_alias()
            )
            payload.update({
                "project_name": str(spec.get("project_name") or "").strip(),
                "target_host": self._normalize_target_host(target_host),
                "transport_kind": str(
                    spec.get("transport_kind")
                    or self._transport_kind_for_target_host(transport_host)
                ).strip(),
                "connection_key": str(spec.get("connection_key") or "").strip(),
                "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
                "launch_kind": str(spec.get("launch_kind") or "").strip(),
            })
        if isinstance(extra, dict):
            payload.update(extra)
        status_file = self.status_file(launch_key)
        status_file.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(status_file, payload)
        return payload

    def read_status(self, launch_id: str) -> Dict[str, Any]:
        """Return persisted status for a deterministic launch id."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return {}
        payload = self._load_json_file(self.status_file(launch_key))
        if not payload:
            return {}
        payload.setdefault("launch_id", launch_key)
        return payload

    def list_statuses(self, *, limit: int = 20) -> List[Dict[str, Any]]:
        """Return recent persisted launch statuses for dashboard consumers."""
        runtime_dir = self.runtime_dir()
        if not runtime_dir.exists():
            return []
        items: List[Dict[str, Any]] = []
        for path in sorted(runtime_dir.glob("*.status.json"), key=lambda item: item.stat().st_mtime, reverse=True):
            payload = self._load_json_file(path)
            if payload:
                items.append(payload)
            if len(items) >= max(int(limit), 1):
                break
        return items

    def _registry(self) -> Any:
        if self._launch_registry is None:
            raise RuntimeError("Launch registry is unavailable")
        return self._launch_registry()

    def build_launch_identity(
        self,
        *,
        app_name: str,
        project_name: str,
        launcher_pid: int,
        app_id_override: str = "",
    ) -> Dict[str, str]:
        """Build deterministic launch identity fields shared by launch specs and helpers."""
        anchor = str(app_id_override or "").strip()
        if not anchor:
            anchor = f"{app_name}-{project_name or 'global'}-{launcher_pid}-{int(time.time())}"
        return {
            "app_instance_id": anchor,
            "terminal_anchor_id": anchor,
        }

    def build_context_tmux_session_name(
        self,
        *,
        project_name: str,
        context_key: str,
        terminal_role: str = "project-main",
    ) -> str:
        """Build a stable tmux session name for a project/context terminal."""
        slug = re.sub(r"[^a-z0-9_-]+", "-", str(project_name or "project").strip().lower())
        slug = re.sub(r"-{2,}", "-", slug).strip("-") or "project"
        seed = f"{terminal_role}::{project_name}::{context_key or 'global'}"
        digest = hashlib.sha1(seed.encode("utf-8")).hexdigest()[:8]
        return f"i3pm-{slug[:24]}-{digest}"

    def extract_scoped_terminal_command(
        self,
        *,
        app_name: str,
        prepared_args: List[str],
    ) -> List[str]:
        """Extract the command executed inside Ghostty for scoped terminal apps."""
        args = [str(arg) for arg in prepared_args]
        if len(args) >= 2 and args[0] == "-e":
            return args[1:]

        raise RuntimeError(json.dumps({
            "code": -32004,
            "message": (
                f"Scoped terminal app '{app_name}' must use Ghostty '-e <command>' parameters "
                "for project-aware launches"
            ),
            "data": {
                "app_name": app_name,
                "parameters": args,
            },
        }))

    def substitute_launch_parameter(
        self,
        value: str,
        *,
        project_name: str,
        project_dir: str,
        session_name: str,
        project_display_name: str,
        project_icon: str,
        preferred_workspace: Optional[int],
    ) -> str:
        """Expand supported launch parameter placeholders."""
        rendered = str(value)
        replacements = {
            "$PROJECT_DIR": project_dir,
            "$PROJECT_NAME": project_name,
            "$SESSION_NAME": session_name,
            "$HOME": str(Path.home()),
            "$PROJECT_DISPLAY_NAME": project_display_name,
            "$PROJECT_ICON": project_icon,
            "$WORKSPACE": str(preferred_workspace or ""),
        }
        for needle, replacement in replacements.items():
            rendered = rendered.replace(needle, replacement)
        if "$PROJECT_" in rendered or "$SESSION_NAME" in rendered or "$WORKSPACE" in rendered:
            raise RuntimeError(json.dumps({
                "code": -32004,
                "message": f"Unresolved launch parameter '{value}'",
                "data": {"parameter": value},
            }))
        return rendered

    def build_prepared_args(
        self,
        *,
        parameters: Iterable[Any],
        project_name: str,
        project_dir: str,
        session_name: str,
        project_display_name: str,
        project_icon: str,
        preferred_workspace: Optional[int],
    ) -> List[str]:
        """Render registry launch parameters into executable arguments."""
        return [
            self.substitute_launch_parameter(
                str(parameter),
                project_name=project_name,
                project_dir=project_dir,
                session_name=session_name,
                project_display_name=project_display_name,
                project_icon=project_icon,
                preferred_workspace=preferred_workspace,
            )
            for parameter in parameters
        ]

    def build_launch_env(
        self,
        *,
        app_name: str,
        scope: str,
        preferred_workspace: Optional[int],
        expected_class: str,
        project_name: str,
        project_dir: str,
        local_project_dir: str,
        project_display_name: str,
        execution_mode: str,
        target_host: str,
        transport_kind: str,
        connection_key: str,
        context_key: str,
        remote_profile: Optional[Dict[str, Any]],
        launcher_pid: int,
        launch_identity: Dict[str, str],
        terminal_role: str = "",
        tmux_session_name: str = "",
        restore_mark: str = "",
        remote_session_name: str = "",
        worktree_branch: str = "",
        worktree_account: str = "",
        worktree_repo: str = "",
    ) -> Dict[str, str]:
        """Build the environment passed to daemon-managed launches."""
        env = {
            "I3PM_APP_ID": launch_identity["app_instance_id"],
            "I3PM_TERMINAL_ANCHOR_ID": launch_identity["terminal_anchor_id"],
            "I3PM_TERMINAL_ROLE": terminal_role,
            "I3PM_TMUX_SESSION_NAME": tmux_session_name,
            "I3PM_APP_NAME": app_name,
            "I3PM_PROJECT_NAME": project_name,
            "I3PM_PROJECT_DIR": project_dir,
            "I3PM_LOCAL_PROJECT_DIR": local_project_dir,
            "I3PM_PROJECT_DISPLAY_NAME": project_display_name,
            "I3PM_PROJECT_ICON": "",
            "I3PM_SCOPE": scope,
            "I3PM_ACTIVE": "true" if project_name else "false",
            "I3PM_LAUNCH_TIME": str(int(time.time())),
            "I3PM_LAUNCHER_PID": str(launcher_pid),
            "I3PM_TARGET_WORKSPACE": str(preferred_workspace or ""),
            "I3PM_EXPECTED_CLASS": expected_class,
            "I3PM_TARGET_HOST": target_host,
            "I3PM_TRANSPORT_KIND": transport_kind,
            "I3PM_EXECUTION_MODE": execution_mode,
            "I3PM_CONTEXT_VARIANT": execution_mode,
            "I3PM_CONNECTION_KEY": connection_key,
            "I3PM_CONTEXT_KEY": context_key,
            "I3PM_REMOTE_ENABLED": "true" if execution_mode == "ssh" else "false",
            "I3PM_REMOTE_HOST": "",
            "I3PM_REMOTE_USER": "",
            "I3PM_REMOTE_PORT": "",
            "I3PM_REMOTE_DIR": "",
            "I3PM_REMOTE_SESSION_NAME": remote_session_name,
            "I3PM_LOCAL_HOST_ALIAS": self._local_host_alias(),
            "I3PM_WORKTREE_BRANCH": worktree_branch,
            "I3PM_WORKTREE_ACCOUNT": worktree_account,
            "I3PM_WORKTREE_REPO": worktree_repo,
        }
        if worktree_branch:
            env["I3PM_IS_WORKTREE"] = "true"
            env["I3PM_FULL_BRANCH_NAME"] = worktree_branch
            env["I3PM_GIT_BRANCH"] = worktree_branch
        if tmux_session_name:
            canonical_tmux_socket = self._canonical_tmux_socket()
            env["I3PM_TMUX_SOCKET"] = canonical_tmux_socket
            env["I3PM_TMUX_SERVER_KEY"] = canonical_tmux_socket
        if restore_mark:
            env["I3PM_RESTORE_MARK"] = restore_mark
        if remote_profile and execution_mode == "ssh":
            env["I3PM_REMOTE_HOST"] = str(remote_profile.get("host", ""))
            env["I3PM_REMOTE_USER"] = str(remote_profile.get("user", ""))
            env["I3PM_REMOTE_PORT"] = str(remote_profile.get("port", 22))
            env["I3PM_REMOTE_DIR"] = str(remote_profile.get("remote_dir", ""))

        for key in (
            "DBUS_SESSION_BUS_ADDRESS",
            "DISPLAY",
            "SWAYSOCK",
            "WAYLAND_DISPLAY",
            "XDG_CURRENT_DESKTOP",
            "XDG_RUNTIME_DIR",
            "XDG_SESSION_TYPE",
        ):
            value = str(os.environ.get(key, "") or "").strip()
            if value:
                env[key] = value
        return env

    async def register_pending_launch(
        self,
        *,
        app: Any,
        project_name: str,
        project_directory: str,
        launcher_pid: int,
        terminal_anchor_id: str,
        preferred_workspace: Optional[int],
    ) -> Dict[str, Any]:
        """Register pending launch metadata used to correlate future windows."""
        registry = self._registry()
        stats = registry.get_stats()
        if preferred_workspace is None:
            return {
                "status": "skipped",
                "launch_id": "",
                "terminal_anchor_id": terminal_anchor_id,
                "expected_class": app.expected_class,
                "pending_count": stats.total_pending,
            }

        pending_launch = PendingLaunch(
            app_name=app.name,
            project_name=project_name or "global",
            project_directory=Path(project_directory),
            launcher_pid=launcher_pid,
            workspace_number=preferred_workspace,
            timestamp=time.time(),
            expected_class=app.expected_class,
            pwa_match_domains=list(app.pwa_match_domains or []),
            terminal_anchor_id=terminal_anchor_id,
            matched=False,
        )
        launch_id = await registry.add(pending_launch)
        stats = registry.get_stats()
        return {
            "status": "success",
            "launch_id": launch_id,
            "terminal_anchor_id": terminal_anchor_id,
            "expected_class": app.expected_class,
            "pending_count": stats.total_pending,
        }

    async def register_launch_for_spec(
        self,
        spec: Dict[str, Any],
        *,
        app: Optional[Any] = None,
    ) -> Dict[str, Any]:
        """Register pending launch state and persist the deterministic launch spec."""
        target_app = app
        if target_app is None:
            if self._require_registry_app is None:
                raise RuntimeError("Application registry lookup is unavailable")
            target_app = self._require_registry_app(str(spec.get("app_name") or "").strip())
        registration = await self.register_pending_launch(
            app=target_app,
            project_name=str(spec.get("project_name") or "").strip(),
            project_directory=(
                str(spec.get("local_project_directory") or "").strip()
                or str(Path.home())
            ),
            launcher_pid=int(spec.get("environment", {}).get("I3PM_LAUNCHER_PID") or os.getpid()),
            terminal_anchor_id=str(spec.get("terminal_anchor_id") or "").strip(),
            preferred_workspace=(
                int(spec.get("preferred_workspace"))
                if spec.get("preferred_workspace") is not None
                else None
            ),
        )
        launch_id = str(registration.get("launch_id") or "").strip()
        if launch_id:
            spec["launch"] = {"launch_id": launch_id}
            launch_transport = str(spec.get("launch_transport") or "").strip()
            launch_kind = str(spec.get("launch_kind") or "open_project_terminal").strip()
            if launch_transport == "remote_helper":
                self.write_remote_spec(spec=spec, launch_kind=launch_kind)
            else:
                self.write_local_spec(spec=spec, launch_kind=launch_kind)
        return registration

    def launch_stats(self) -> Dict[str, Any]:
        """Return launch registry statistics as a JSON-serializable payload."""
        stats = self._registry().get_stats()
        return {
            "total_pending": getattr(stats, "total_pending", 0),
            "unmatched_pending": getattr(stats, "unmatched_pending", 0),
            "total_notifications": getattr(stats, "total_notifications", 0),
            "total_matched": getattr(stats, "total_matched", 0),
            "total_expired": getattr(stats, "total_expired", 0),
            "total_failed_correlation": getattr(stats, "total_failed_correlation", 0),
            "match_rate": getattr(stats, "match_rate", 0),
            "expiration_rate": getattr(stats, "expiration_rate", 0),
        }

    async def pending_launches(self, *, include_matched: bool = False) -> Dict[str, Any]:
        """Return pending launches for diagnostics."""
        registry = self._registry()
        launches = await registry.get_pending_launches(include_matched=include_matched)
        return {"launches": launches}

    def find_context_terminal_window(
        self,
        *,
        project_name: str,
        context_key: str,
        execution_mode: str,
        app_name: str = "",
        terminal_role: str = "",
    ) -> Optional[Any]:
        """Return an existing canonical project terminal window for a context if present."""
        if self._window_map_items is None:
            return None

        from .window_filter import parse_window_environment, read_process_environ_with_fallback

        target_project = str(project_name or "").strip()
        target_context = str(context_key or "").strip()
        target_mode = str(execution_mode or "local").strip() or "local"
        target_app = str(app_name or "").strip()
        target_role = str(terminal_role or "").strip()

        if not (target_project and target_context):
            return None

        candidates: List[Any] = []
        for _window_id, window_info in self._window_map_items():
            tracked_project = str(getattr(window_info, "project", "") or "").strip()
            tracked_context = str(getattr(window_info, "context_key", "") or "").strip()
            tracked_mode = str(getattr(window_info, "execution_mode", "") or "local").strip() or "local"
            role = str(getattr(window_info, "terminal_role", "") or "").strip()
            app_identifier = str(getattr(window_info, "app_identifier", "") or "").strip()
            tracked_tmux_session = str(getattr(window_info, "tmux_session_name", "") or "").strip()

            if not tracked_project or not tracked_context or not role or not tracked_tmux_session:
                pid = int(getattr(window_info, "pid", 0) or 0)
                if pid > 0:
                    env = read_process_environ_with_fallback(pid)
                    parsed_env = parse_window_environment(env) if env else None
                    if parsed_env is not None:
                        tracked_project = tracked_project or str(parsed_env.project_name or "").strip()
                        tracked_context = tracked_context or str(parsed_env.context_key or "").strip()
                        role = role or str(parsed_env.terminal_role or "").strip()
                        app_identifier = app_identifier or str(parsed_env.app_name or "").strip()
                        tracked_tmux_session = tracked_tmux_session or str(parsed_env.tmux_session_name or "").strip()
                    tracked_mode = (
                        str(env.get("I3PM_CONTEXT_VARIANT") or "").strip()
                        or tracked_mode
                    )

            if tracked_project != target_project:
                continue
            if tracked_context != target_context:
                continue
            if tracked_mode != target_mode:
                continue

            if target_role:
                if role != target_role:
                    continue
            elif role:
                if role != "project-main":
                    continue
            elif target_app:
                if app_identifier != target_app:
                    continue
            elif app_identifier != "terminal":
                continue

            candidates.append(window_info)

        if not candidates:
            return None

        candidates.sort(
            key=lambda item: (
                0 if str(getattr(item, "workspace", "") or "").strip() else 1,
                int(getattr(item, "window_id", 0) or 0),
            )
        )
        return candidates[0]

    async def get_reusable_context_terminal_window(
        self,
        *,
        project_name: str,
        context_key: str,
        execution_mode: str,
        app_name: str = "",
        terminal_role: str = "",
    ) -> Optional[Any]:
        """Return a reusable terminal only if the tracked window still exists."""
        candidate = self.find_context_terminal_window(
            project_name=project_name,
            context_key=context_key,
            execution_mode=execution_mode,
            app_name=app_name,
            terminal_role=terminal_role,
        )
        if candidate is None:
            return None
        if self._find_live_window is None:
            return candidate

        candidate_window_id = int(getattr(candidate, "window_id", 0) or 0)
        live_window = await self._find_live_window(candidate_window_id)
        if live_window is not None:
            return candidate

        logger.warning(
            "Discarding stale tracked terminal window %s for %s (%s)",
            candidate_window_id,
            project_name,
            context_key,
        )
        if self._remove_window is not None and candidate_window_id > 0:
            await self._remove_window(candidate_window_id)
        if self._invalidate_window_tree_cache is not None:
            self._invalidate_window_tree_cache()
        return None

    def find_context_app_window_candidates(
        self,
        *,
        app: Any,
        project_name: str,
        execution_mode: str,
    ) -> List[Any]:
        """Return tracked app windows that are eligible for single-instance reuse."""
        if self._window_map_items is None:
            return []

        from .window_identifier import match_pwa_instance, match_window_class

        target_project = str(project_name or "").strip()
        target_execution_mode = str(execution_mode or "local").strip() or "local"

        candidates = sorted(
            [window for _window_id, window in self._window_map_items()],
            key=lambda window: getattr(window, "last_focus", None) or getattr(window, "created", None),
            reverse=True,
        )
        matched_candidates: List[Any] = []

        for candidate in candidates:
            candidate_window_id = int(getattr(candidate, "window_id", 0) or 0)
            if candidate_window_id <= 0:
                continue

            candidate_execution_mode = str(getattr(candidate, "execution_mode", "") or "local").strip() or "local"
            if candidate_execution_mode != target_execution_mode:
                continue

            candidate_project = str(getattr(candidate, "project", "") or "").strip()
            if app.scope != "global" and candidate_project != target_project:
                continue

            if bool(app.terminal):
                app_identifier = str(getattr(candidate, "app_identifier", "") or "").strip()
                if app_identifier != app.name:
                    continue

            actual_class = str(getattr(candidate, "window_class", "") or "")
            actual_instance = str(getattr(candidate, "window_instance", "") or "")
            if app.pwa_match_domains and match_pwa_instance(
                app.expected_class,
                actual_class,
                actual_instance,
                pwa_domains=list(app.pwa_match_domains or []),
            ):
                matched = True
            else:
                matched, _ = match_window_class(
                    app.expected_class,
                    actual_class,
                    actual_instance,
                )
            if matched:
                matched_candidates.append(candidate)

        return matched_candidates

    async def get_reusable_context_app_window(
        self,
        *,
        app: Any,
        project_name: str,
        execution_mode: str,
    ) -> Optional[Any]:
        """Return an existing live app window for single-instance launches."""
        candidates = self.find_context_app_window_candidates(
            app=app,
            project_name=project_name,
            execution_mode=execution_mode,
        )
        if self._find_live_window is None:
            return candidates[0] if candidates else None

        stale_window_ids: List[int] = []
        for candidate in candidates:
            candidate_window_id = int(getattr(candidate, "window_id", 0) or 0)
            live_window = await self._find_live_window(candidate_window_id)
            if live_window is not None:
                return candidate
            if candidate_window_id > 0:
                stale_window_ids.append(candidate_window_id)

        for stale_window_id in stale_window_ids:
            logger.warning(
                "Discarding stale tracked app window %s for %s",
                stale_window_id,
                getattr(app, "name", ""),
            )
            if self._remove_window is not None:
                await self._remove_window(stale_window_id)

        if stale_window_ids and self._invalidate_window_tree_cache is not None:
            self._invalidate_window_tree_cache()
        return None

    def build_launch_open_response(
        self,
        *,
        spec: Dict[str, Any],
        launch_result: Dict[str, Any],
        launch_strategy: Optional[str] = None,
        reused_existing: bool = False,
        window_id: int = 0,
        include_spec_window_id: bool = False,
    ) -> Dict[str, Any]:
        """Shape the public response for ``launch.open``."""
        spec_payload: Dict[str, Any] = {
            "app_name": spec.get("app_name"),
            "target_host": spec.get("target_host"),
            "transport_kind": spec.get("transport_kind"),
            "project_name": spec.get("project_name"),
            "context_key": spec.get("context_key"),
            "launch_strategy": launch_strategy if launch_strategy is not None else spec.get("launch_strategy"),
            "terminal_anchor_id": spec.get("terminal_anchor_id"),
            "preferred_workspace": spec.get("preferred_workspace"),
            "tmux_session_name": spec.get("tmux_session_name"),
            "terminal_role": spec.get("terminal_role"),
            "reused_existing": reused_existing,
        }
        normalized_window_id = int(window_id or 0)
        if include_spec_window_id:
            spec_payload["window_id"] = normalized_window_id

        launch_payload = dict(launch_result or {})
        if reused_existing:
            launch_payload.setdefault("success", True)
            launch_payload["reused_existing"] = True
            launch_payload["window_id"] = normalized_window_id

        return {
            "success": True,
            "launch": launch_payload,
            "spec": spec_payload,
        }

    async def open_launch(
        self,
        *,
        payload: Dict[str, Any],
        prepare_launch: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        focus_window: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        focus_window_fast: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        clear_focus_overrides: Callable[[], None],
    ) -> Dict[str, Any]:
        """Prepare, reuse, or execute a launch-open request."""
        spec = await prepare_launch(payload)
        if self._require_registry_app is None:
            raise RuntimeError("LaunchService requires a registry app resolver for launch.open")
        app = self._require_registry_app(str(spec.get("app_name") or "").strip())
        if int(payload.get("__intent_epoch") or 0) > 0 and str(spec.get("project_name") or "").strip():
            clear_focus_overrides()

        reused_existing = False
        reused_window_id = 0
        focus_fast = bool(payload.get("focus_fast", False))

        async def focus_existing_window(existing_window: Any) -> Dict[str, Any]:
            focus_params = {
                "window_id": int(getattr(existing_window, "window_id", 0) or 0),
                "project_name": str(spec.get("project_name") or "").strip(),
                "target_variant": str(spec.get("execution_mode") or "").strip().lower(),
                "connection_key": str(spec.get("connection_key") or "").strip(),
            }
            if focus_fast:
                return await focus_window_fast(focus_params)
            return await focus_window(focus_params)

        terminal_launch = spec.get("terminal_launch") or {}
        terminal_mode = str(terminal_launch.get("mode") or "").strip()
        launch_transport = str(
            spec.get("launch_transport")
            or (
                self._resolve_terminal_launch_transport(
                    execution_mode=str(spec.get("execution_mode") or "local").strip() or "local",
                    connection_key=str(spec.get("connection_key") or "").strip(),
                )
                if self._resolve_terminal_launch_transport is not None
                else "local_helper"
            )
        ).strip() or "local_helper"
        if terminal_mode == "managed_project_terminal":
            existing_window = await self.get_reusable_context_terminal_window(
                project_name=str(spec.get("project_name") or "").strip(),
                context_key=str(spec.get("context_key") or "").strip(),
                execution_mode=str(spec.get("execution_mode") or "local").strip() or "local",
                app_name="terminal",
                terminal_role=str(spec.get("terminal_role") or "project-main").strip(),
            )
            if existing_window is not None and launch_transport == "local_helper":
                probe = self.managed_tmux_session_probe(spec)
                if not bool(probe.get("exists", False) and probe.get("healthy", False)):
                    logger.warning(
                        "Refusing to reuse live terminal window %s for %s because managed session %s is invalid (%s)",
                        int(getattr(existing_window, "window_id", 0) or 0),
                        str(spec.get("context_key") or "").strip(),
                        str(spec.get("tmux_session_name") or "").strip(),
                        str(probe.get("reason") or "unknown"),
                    )
                    existing_window = None
            if existing_window is not None:
                self.dispatch_managed_terminal_command(spec)
                focus_result = await focus_existing_window(existing_window)
                if bool(focus_result.get("success", False)):
                    reused_existing = True
                    reused_window_id = int(focus_result.get("window_id") or 0)
                    return self.build_launch_open_response(
                        spec=spec,
                        launch_result={
                            "success": True,
                            "tmux_session_name": str(spec.get("tmux_session_name") or "").strip(),
                        },
                        launch_strategy="focus_existing_terminal",
                        reused_existing=True,
                        window_id=reused_window_id,
                    )
        elif terminal_mode == "dedicated_scoped_window":
            existing_window = await self.get_reusable_context_terminal_window(
                project_name=str(spec.get("project_name") or "").strip(),
                context_key=str(spec.get("context_key") or "").strip(),
                execution_mode=str(spec.get("execution_mode") or "local").strip() or "local",
                app_name=str(spec.get("app_name") or "").strip(),
                terminal_role=str(spec.get("terminal_role") or "").strip(),
            )
            if existing_window is not None:
                focus_result = await focus_existing_window(existing_window)
                if bool(focus_result.get("success", False)):
                    reused_existing = True
                    reused_window_id = int(focus_result.get("window_id") or 0)
                    return self.build_launch_open_response(
                        spec=spec,
                        launch_result={"success": True},
                        launch_strategy="focus_existing_dedicated_terminal_window",
                        reused_existing=True,
                        window_id=reused_window_id,
                    )
        elif not app.multi_instance and (not app.terminal or not terminal_mode):
            existing_window = await self.get_reusable_context_app_window(
                app=app,
                project_name=str(spec.get("project_name") or "").strip(),
                execution_mode=str(spec.get("execution_mode") or "local").strip() or "local",
            )
            if existing_window is None and not app.terminal:
                self.reap_orphan_app_units(app.name, str(app.command or ""))
            if existing_window is not None:
                focus_result = await focus_existing_window(existing_window)
                if bool(focus_result.get("success", False)):
                    reused_existing = True
                    reused_window_id = int(focus_result.get("window_id") or 0)
                    return self.build_launch_open_response(
                        spec=spec,
                        launch_result={"success": True},
                        launch_strategy="focus_existing_window",
                        reused_existing=True,
                        window_id=reused_window_id,
                        include_spec_window_id=True,
                    )

        spec["launch"] = await self.register_launch_for_spec(spec)
        launch_result = self.execute_launch_spec(spec)
        return self.build_launch_open_response(
            spec=spec,
            launch_result=launch_result,
            reused_existing=reused_existing,
            window_id=reused_window_id,
            include_spec_window_id=True,
        )

    def build_terminal_launch_config(
        self,
        *,
        app: Any,
        scoped_launch: bool,
        project_name: str,
        context_key: str,
        connection_key: str,
        launch_transport: str,
        remote_profile: Optional[Dict[str, Any]],
        scoped_terminal_mode: str,
        scoped_terminal_command: List[str],
        tmux_session_name: str,
        terminal_role: str,
        remote_session_name_override: str,
    ) -> Dict[str, Any]:
        """Build terminal-specific launch strategy and helper payload."""
        launch_strategy = "direct"
        terminal_launch: Optional[Dict[str, Any]] = None
        normalized_tmux_session_name = str(tmux_session_name or "").strip()

        if not (bool(getattr(app, "terminal", False)) and scoped_launch and project_name and context_key):
            return {
                "launch_strategy": launch_strategy,
                "terminal_launch": terminal_launch,
                "tmux_session_name": normalized_tmux_session_name,
            }

        remote_payload = {
            "host": str(remote_profile.get("host", "")) if remote_profile else "",
            "user": str(remote_profile.get("user", "")) if remote_profile else "",
            "port": int(remote_profile.get("port", 22)) if remote_profile else 22,
            "remote_dir": str(remote_profile.get("remote_dir", "")) if remote_profile else "",
        }

        if scoped_terminal_mode == "dedicated_scoped_window":
            launch_strategy = (
                "dedicated_remote_scoped_window"
                if launch_transport == "remote_helper"
                else "dedicated_local_scoped_window"
            )
            terminal_launch = {
                "mode": "dedicated_scoped_window",
                "terminal_role": terminal_role,
                "helper_name": "project-command-launch.sh",
                "helper_args": scoped_terminal_command,
            }
            if launch_transport == "remote_helper":
                terminal_launch["remote"] = remote_payload
        else:
            if not normalized_tmux_session_name:
                normalized_tmux_session_name = self.build_context_tmux_session_name(
                    project_name=project_name or str(getattr(app, "name", "") or "").strip(),
                    context_key=context_key or connection_key,
                    terminal_role=terminal_role or "project-main",
                )
            launch_strategy = (
                "managed_remote_terminal_command"
                if launch_transport == "remote_helper" and scoped_terminal_command
                else "managed_remote_terminal"
                if launch_transport == "remote_helper"
                else "managed_local_terminal_command"
                if scoped_terminal_command
                else "managed_local_terminal"
            )
            terminal_launch = {
                "mode": "managed_project_terminal",
                "tmux_session_name": normalized_tmux_session_name,
                "terminal_role": terminal_role,
                "remote_session_name": remote_session_name_override,
                "helper_name": "project-terminal-launch.sh",
                "helper_args": scoped_terminal_command,
            }
            if launch_transport == "remote_helper":
                terminal_launch["remote"] = remote_payload

        return {
            "launch_strategy": launch_strategy,
            "terminal_launch": terminal_launch,
            "tmux_session_name": normalized_tmux_session_name,
        }

    def build_terminal_identity(
        self,
        *,
        app: Any,
        scoped_launch: bool,
        project_name: str,
        context_key: str,
        scoped_terminal_mode: str,
        prepared_args: List[str],
    ) -> Dict[str, Any]:
        """Build terminal role, tmux session, and scoped command metadata."""
        app_name = str(getattr(app, "name", "") or "").strip()
        app_is_terminal = bool(getattr(app, "terminal", False))
        terminal_role = ""
        tmux_session_name = ""
        scoped_terminal_command: List[str] = []

        if scoped_launch and app_is_terminal and app_name != "terminal":
            scoped_terminal_command = self.extract_scoped_terminal_command(
                app_name=app_name,
                prepared_args=prepared_args,
            )

        if app_is_terminal and scoped_launch and project_name and context_key:
            if scoped_terminal_mode == "dedicated_scoped_window":
                terminal_role = f"project-app:{app_name}"
            else:
                terminal_role = "project-main"
                tmux_session_name = self.build_context_tmux_session_name(
                    project_name=project_name,
                    context_key=context_key,
                    terminal_role=terminal_role,
                )

        return {
            "terminal_role": terminal_role,
            "tmux_session_name": tmux_session_name,
            "scoped_terminal_command": scoped_terminal_command,
        }

    def build_remote_session_attach_spec(
        self,
        *,
        app: Any,
        session: Dict[str, Any],
        attach_profile: Dict[str, Any],
        remote_context: Dict[str, Any],
        launcher_pid: int,
        pending_count: int,
        remote_terminal_role: str,
    ) -> Dict[str, Any]:
        """Build a local SSH terminal launch spec for an exact remote tmux pane."""
        project_name = str(session.get("project_name") or session.get("project") or "").strip()
        if not project_name:
            raise RuntimeError("Remote session is missing project metadata")

        terminal_context = session.get("terminal_context") or {}
        if not isinstance(terminal_context, dict):
            terminal_context = {}

        tmux_session = str(session.get("tmux_session") or terminal_context.get("tmux_session") or "").strip()
        tmux_window = str(session.get("tmux_window") or terminal_context.get("tmux_window") or "").strip()
        tmux_pane = str(session.get("tmux_pane") or terminal_context.get("tmux_pane") or "").strip()
        surface_key = str(session.get("surface_key") or "").strip()
        session_key = str(session.get("session_key") or "").strip()
        if not (tmux_session and tmux_window and tmux_pane and surface_key and session_key):
            raise RuntimeError("Remote session is missing stable tmux identity")

        parsed = parse_qualified_name(project_name)
        remote_profile = dict(remote_context.get("remote") or {})
        project_directory = str(remote_profile.get("remote_dir") or "").strip()
        local_project_directory = ""
        session_name = f"{parsed.repo}_{parsed.branch}" if parsed.repo and parsed.branch else ""
        launch_identity = self.build_launch_identity(
            app_name=str(getattr(app, "name", "") or "").strip(),
            project_name=project_name,
            launcher_pid=launcher_pid,
        )
        prepared_args = self.build_prepared_args(
            parameters=getattr(app, "parameters", []) or [],
            project_name=project_name,
            project_dir=project_directory,
            session_name=session_name,
            project_display_name=parsed.branch,
            project_icon="",
            preferred_workspace=getattr(app, "preferred_workspace", None),
        )
        remote_terminal_role = str(remote_terminal_role or "").strip()
        environment = self.build_launch_env(
            app_name=str(getattr(app, "name", "") or "").strip(),
            scope=str(getattr(app, "scope", "") or "").strip(),
            preferred_workspace=getattr(app, "preferred_workspace", None),
            expected_class=str(getattr(app, "expected_class", "") or "").strip(),
            project_name=project_name,
            project_dir=project_directory,
            local_project_dir=local_project_directory,
            project_display_name=parsed.branch,
            execution_mode="ssh",
            target_host=str(remote_context.get("target_host") or remote_profile.get("host") or "").strip(),
            transport_kind="ssh_helper",
            connection_key=str(remote_context.get("connection_key") or "").strip(),
            context_key=str(remote_context.get("context_key") or "").strip(),
            remote_profile=remote_profile,
            launcher_pid=launcher_pid,
            launch_identity=launch_identity,
            terminal_role=remote_terminal_role,
            tmux_session_name=tmux_session,
            remote_session_name=tmux_session,
            worktree_branch=parsed.branch,
            worktree_account=parsed.account,
            worktree_repo=parsed.repo,
        )
        environment.update({
            "I3PM_CONTEXT_VARIANT": "ssh",
            "I3PM_CONNECTION_KEY": str(attach_profile.get("connection_key") or "").strip(),
            "I3PM_CONTEXT_KEY": str(remote_context.get("context_key") or "").strip(),
            "I3PM_REMOTE_ENABLED": "true",
            "I3PM_REMOTE_HOST": str(attach_profile.get("remote_host") or "").strip(),
            "I3PM_REMOTE_USER": str(attach_profile.get("remote_user") or "").strip(),
            "I3PM_REMOTE_PORT": str(int(attach_profile.get("remote_port", 22) or 22)),
            "I3PM_REMOTE_DIR": str(attach_profile.get("remote_dir") or "").strip(),
            "I3PM_TERMINAL_ROLE": remote_terminal_role,
            "I3PM_TMUX_SESSION_NAME": tmux_session,
            "I3PM_REMOTE_SESSION_NAME": tmux_session,
            "I3PM_REMOTE_SESSION_KEY": session_key,
            "I3PM_REMOTE_SURFACE_KEY": surface_key,
            "I3PM_REMOTE_CONNECTION_KEY": str(session.get("connection_key") or "").strip(),
            "I3PM_REMOTE_TMUX_SOCKET": str(terminal_context.get("tmux_socket") or "").strip(),
            "I3PM_REMOTE_TMUX_SERVER_KEY": (
                str(terminal_context.get("tmux_server_key") or terminal_context.get("tmux_socket") or "").strip()
            ),
            "I3PM_REMOTE_TMUX_SESSION": tmux_session,
            "I3PM_REMOTE_TMUX_WINDOW": tmux_window,
            "I3PM_REMOTE_TMUX_PANE": tmux_pane,
        })

        return {
            "app_name": str(getattr(app, "name", "") or "").strip(),
            "command": getattr(app, "command", ""),
            "args": prepared_args,
            "terminal": bool(getattr(app, "terminal", False)),
            "scope": str(getattr(app, "scope", "") or "").strip(),
            "expected_class": str(getattr(app, "expected_class", "") or "").strip(),
            "preferred_workspace": getattr(app, "preferred_workspace", None),
            "project_name": project_name,
            "project_directory": project_directory,
            "local_project_directory": local_project_directory,
            "project_display_name": parsed.branch,
            "execution_mode": "ssh",
            "connection_key": str(remote_context.get("connection_key") or "").strip(),
            "context_key": str(remote_context.get("context_key") or "").strip(),
            "launch_strategy": "managed_remote_terminal",
            "launch_transport": "remote_helper",
            "ssh_policy": "terminal_only",
            "remote_profile": remote_profile,
            "terminal_launch": {
                "mode": "managed_project_terminal",
                "tmux_session_name": tmux_session,
                "terminal_role": remote_terminal_role,
                "remote_session_name": tmux_session,
                "helper_name": "project-terminal-launch.sh",
                "helper_args": [],
                "remote": {
                    "host": str(attach_profile.get("remote_host") or ""),
                    "user": str(attach_profile.get("remote_user") or ""),
                    "port": int(attach_profile.get("remote_port", 22) or 22),
                    "remote_dir": str(attach_profile.get("remote_dir") or ""),
                },
                "remote_attach": {
                    "tmux_socket": str(terminal_context.get("tmux_socket") or "").strip(),
                    "tmux_server_key": str(
                        terminal_context.get("tmux_server_key")
                        or terminal_context.get("tmux_socket")
                        or ""
                    ).strip(),
                    "tmux_session": tmux_session,
                    "tmux_window": tmux_window,
                    "tmux_pane": tmux_pane,
                },
            },
            "terminal_role": remote_terminal_role,
            "tmux_session_name": tmux_session,
            "environment": environment,
            "launch": {
                "status": "deferred",
                "reason": "register_launch_disabled",
                "launch_id": "",
                "terminal_anchor_id": launch_identity["terminal_anchor_id"],
                "expected_class": str(getattr(app, "expected_class", "") or "").strip(),
                "pending_count": pending_count,
            },
            "terminal_anchor_id": launch_identity["terminal_anchor_id"],
            "app_instance_id": launch_identity["app_instance_id"],
        }

    def prepare_remote_session_attach_spec(
        self,
        session: Dict[str, Any],
        *,
        attach_profile: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Resolve daemon context and build the exact local SSH bridge launch spec."""
        project_name = str(session.get("project_name") or session.get("project") or "").strip()
        if not project_name:
            raise RuntimeError("Remote session is missing project metadata")

        if self._build_remote_attach_runtime_context is None:
            raise RuntimeError("Remote attach context resolver is unavailable")
        if self._require_registry_app is None:
            raise RuntimeError("Registry app resolver is unavailable")

        if attach_profile is None:
            if self._resolve_remote_attach_profile is None:
                raise RuntimeError("Remote attach profile resolver is unavailable")
            attach_profile = self._resolve_remote_attach_profile(session)
        else:
            attach_profile = dict(attach_profile)
            attach_profile.setdefault("project_name", project_name)
            attach_profile.setdefault(
                "remote_profile",
                {
                    "enabled": True,
                    "host": str(attach_profile.get("remote_host") or "").strip(),
                    "user": str(attach_profile.get("remote_user") or "").strip(),
                    "port": int(attach_profile.get("remote_port", 22) or 22),
                    "remote_dir": str(attach_profile.get("remote_dir") or "").strip(),
                },
            )

        remote_context = self._build_remote_attach_runtime_context(attach_profile)
        app = self._require_registry_app("terminal")
        pending_count = 0
        if self._launch_registry is not None:
            pending_count = int(getattr(self._launch_registry().get_stats(), "total_pending", 0) or 0)
        remote_terminal_role = ""
        if self._remote_session_terminal_role is not None:
            remote_terminal_role = self._remote_session_terminal_role(
                str(remote_context.get("context_key") or "").strip()
            )
        return self.build_remote_session_attach_spec(
            app=app,
            session=session,
            attach_profile=attach_profile,
            remote_context=remote_context,
            launcher_pid=os.getpid(),
            pending_count=pending_count,
            remote_terminal_role=remote_terminal_role,
        )

    def write_remote_spec(
        self,
        *,
        spec: Dict[str, Any],
        launch_kind: str,
    ) -> Path:
        """Persist the exact remote launch payload consumed by the remote launcher."""
        launch = spec.get("launch") or {}
        launch_id = str(launch.get("launch_id") or "").strip()
        if not launch_id:
            raise RuntimeError("remote launch requires a registered launch_id")
        payload = {
            "launch_id": launch_id,
            "launch_kind": str(launch_kind or "").strip(),
            "project_name": str(spec.get("project_name") or "").strip(),
            "target_host": self._normalize_target_host(
                spec.get("target_host") or self._parse_context_target_host(spec.get("context_key"))
            ),
            "transport_kind": str(spec.get("transport_kind") or "").strip(),
            "connection_key": str(spec.get("connection_key") or "").strip(),
            "project_directory": str(spec.get("project_directory") or "").strip(),
            "local_project_directory": str(spec.get("local_project_directory") or "").strip(),
            "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
            "tmux_session_name": str(spec.get("tmux_session_name") or "").strip(),
            "terminal_launch": dict(spec.get("terminal_launch") or {}),
            "environment": dict(spec.get("environment") or {}),
            "launch_transport": str(spec.get("launch_transport") or "").strip(),
            "status_file": str(self.status_file(launch_id)),
        }
        self.write_status(
            launch_id=launch_id,
            status="queued",
            spec=payload,
            reason="queued",
        )
        return self.write_spec_payload(launch_id=launch_id, payload=payload)

    def write_local_spec(
        self,
        *,
        spec: Dict[str, Any],
        launch_kind: str,
    ) -> Path:
        """Persist the exact local launch payload consumed by managed terminal reconciliation."""
        launch = spec.get("launch") or {}
        launch_id = str(launch.get("launch_id") or "").strip()
        if not launch_id:
            raise RuntimeError("local launch requires a registered launch_id")
        payload = {
            "launch_id": launch_id,
            "launch_kind": str(launch_kind or "").strip(),
            "project_name": str(spec.get("project_name") or "").strip(),
            "target_host": self._normalize_target_host(
                spec.get("target_host") or self._parse_context_target_host(spec.get("context_key"))
            ),
            "transport_kind": str(spec.get("transport_kind") or "").strip(),
            "connection_key": str(spec.get("connection_key") or "").strip(),
            "project_directory": str(spec.get("project_directory") or "").strip(),
            "local_project_directory": str(spec.get("local_project_directory") or "").strip(),
            "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
            "tmux_session_name": str(spec.get("tmux_session_name") or "").strip(),
            "terminal_role": str(spec.get("terminal_role") or "").strip(),
            "terminal_launch": dict(spec.get("terminal_launch") or {}),
            "environment": dict(spec.get("environment") or {}),
            "launch_transport": str(spec.get("launch_transport") or "").strip(),
            "status_file": str(self.status_file(launch_id)),
        }
        self.write_status(
            launch_id=launch_id,
            status="queued",
            spec=payload,
            reason="queued",
        )
        return self.write_spec_payload(launch_id=launch_id, payload=payload)

    def build_remote_terminal_helper_script(self, spec: Dict[str, Any]) -> Path:
        """Create a thin deterministic helper script for managed SSH terminals."""
        terminal_launch = spec.get("terminal_launch") or {}
        remote = terminal_launch.get("remote") or {}
        remote_attach = terminal_launch.get("remote_attach") or {}
        if not isinstance(remote, dict):
            remote = {}
        if not isinstance(remote_attach, dict):
            remote_attach = {}

        execution_mode = str(spec.get("execution_mode") or "local").strip() or "local"
        connection_key = str(spec.get("connection_key") or "").strip()
        if self._resolve_terminal_launch_transport is not None:
            transport = self._resolve_terminal_launch_transport(
                execution_mode=execution_mode,
                connection_key=connection_key,
            )
            if transport != "remote_helper":
                raise RuntimeError("Remote terminal helper is invalid for current-host or local launch contexts")

        terminal_mode = str(terminal_launch.get("mode") or "").strip()
        tmux_session_name = str(terminal_launch.get("tmux_session_name") or "").strip()
        helper_name = str(
            terminal_launch.get("helper_name")
            or terminal_launch.get("remote_helper")
            or "project-terminal-launch.sh"
        ).strip()
        helper_args = [str(arg) for arg in (terminal_launch.get("helper_args") or [])]
        remote_dir = str(remote.get("remote_dir") or "").strip()
        remote_user = str(remote.get("user") or "").strip()
        remote_host = str(remote.get("host") or "").strip()
        remote_port = int(remote.get("port", 22) or 22)
        requires_remote_dir = not bool(remote_attach)
        if not (remote_user and remote_host and helper_name):
            raise RuntimeError("Remote terminal launch requires a complete SSH profile")
        if requires_remote_dir and not remote_dir:
            raise RuntimeError("Remote terminal launch requires a complete SSH profile")
        if terminal_mode == "managed_project_terminal" and not tmux_session_name:
            raise RuntimeError("Managed remote terminal launch requires tmux_session_name")

        runtime_dir = self._runtime_dir()
        runtime_dir.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(prefix="i3pm-remote-launch.", suffix=".sh", dir=str(runtime_dir))
        helper_path = Path(temp_name)
        env_items = [
            (str(key), str(value))
            for key, value in (spec.get("environment") or {}).items()
        ]
        env_exports = "\n".join(
            f"export {key}={self._quote(value)}"
            for key, value in env_items
        )
        tmux_session = str(remote_attach.get("tmux_session") or "").strip()
        tmux_window = str(remote_attach.get("tmux_window") or "").strip()
        tmux_pane = str(remote_attach.get("tmux_pane") or "").strip()
        tmux_socket = str(remote_attach.get("tmux_socket") or "").strip()
        if remote_attach:
            tmux_cmd = self._tmux_command_prefix(tmux_socket)
            tmux_window_index = str(tmux_window or "").split(":", 1)[0].strip() or tmux_window
            remote_invocation_lines = [
                "set -euo pipefail",
                f"{tmux_cmd} has-session -t {shlex.quote(tmux_session)} >/dev/null 2>&1",
                f"{tmux_cmd} select-window -t {shlex.quote(f'{tmux_session}:{tmux_window_index}')} >/dev/null 2>&1 || true",
                (
                    f"{tmux_cmd} select-pane -t {shlex.quote(tmux_pane)} >/dev/null 2>&1 || true"
                    if tmux_pane else "true"
                ),
                f"exec env TMUX= {tmux_cmd} attach-session -t {shlex.quote(tmux_session)}",
            ]
            if remote_dir:
                remote_invocation_lines.insert(1, f"cd {shlex.quote(remote_dir)}")
            remote_invocation_script = "\n".join(remote_invocation_lines)
            remote_env_invocation = (
                "env "
                + " ".join(self._quote(f"{key}={value}") for key, value in env_items)
                + " bash -lc "
                + self._quote(remote_invocation_script)
            )
        else:
            remote_env_invocation = " ".join(
                self._quote(part)
                for part in [
                    "env",
                    *[f"{key}={value}" for key, value in env_items],
                    helper_name,
                    remote_dir,
                    *helper_args,
                ]
            )
        remote_script = f"""#!/usr/bin/env bash
set -euo pipefail
{env_exports}
session_name={self._quote(tmux_session_name)}
remote_dir={self._quote(remote_dir)}
if ! ssh -tt -o BatchMode=yes -o ConnectTimeout=2 -p {remote_port} {self._quote(f"{remote_user}@{remote_host}")} {remote_env_invocation}; then
  echo
  echo "[i3pm] Remote terminal launch failed."
  echo "[i3pm] Press Enter to close..."
  read -r
fi
rm -f -- "$0" >/dev/null 2>&1 || true
"""
        try:
            with os.fdopen(fd, "w") as handle:
                handle.write(remote_script)
            helper_path.chmod(0o700)
        except Exception:
            try:
                helper_path.unlink()
            except OSError:
                pass
            raise
        return helper_path

    def managed_tmux_command_shell(
        self,
        *,
        session_name: str,
        tmux_socket: str,
        working_dir: str,
        command_args: List[str],
        environment: Dict[str, str],
    ) -> str:
        """Build a shell snippet that opens a command in the canonical project tmux session."""
        if not session_name or not working_dir or not command_args:
            raise RuntimeError("Managed tmux command dispatch requires session_name, working_dir, and command_args")

        tmux_cmd = self._tmux_command_prefix(tmux_socket or self._canonical_tmux_socket())
        env_lines = []
        for key, value in environment.items():
            if not str(key).startswith("I3PM_"):
                continue
            env_lines.append(
                f"{tmux_cmd} set-environment -t {shlex.quote(session_name)} {shlex.quote(str(key))} {shlex.quote(str(value))}"
            )
        command_string = " ".join(shlex.quote(str(arg)) for arg in command_args)
        window_name = Path(str(command_args[0])).name or "cmd"
        script_lines = [
            "set -euo pipefail",
            f"if ! {tmux_cmd} has-session -t {shlex.quote(session_name)} 2>/dev/null; then exit 1; fi",
        ]
        script_lines.extend(env_lines)
        script_lines.append(
            f"{tmux_cmd} new-window -t {shlex.quote(session_name)} -c {shlex.quote(working_dir)} -n {shlex.quote(window_name[:24] or 'cmd')} \"exec {command_string}\""
        )
        return "\n".join(script_lines)

    def dispatch_managed_terminal_command(self, spec: Dict[str, Any]) -> Dict[str, Any]:
        """Run a scoped terminal command inside the canonical project tmux session."""
        terminal_launch = spec.get("terminal_launch") or {}
        helper_args = [str(arg) for arg in (terminal_launch.get("helper_args") or [])]
        if not helper_args:
            return {
                "success": True,
                "reason": "no_command",
            }

        tmux_session_name = str(terminal_launch.get("tmux_session_name") or spec.get("tmux_session_name") or "").strip()
        execution_mode = str(spec.get("execution_mode") or "local").strip() or "local"
        connection_key = str(spec.get("connection_key") or "").strip()
        environment = {
            str(key): str(value)
            for key, value in (spec.get("environment") or {}).items()
        }
        tmux_socket = str(environment.get("I3PM_TMUX_SOCKET") or "").strip() or self._canonical_tmux_socket()
        launch_transport = str(spec.get("launch_transport") or "").strip()
        if not launch_transport and self._resolve_terminal_launch_transport is not None:
            launch_transport = str(
                self._resolve_terminal_launch_transport(
                    execution_mode=execution_mode,
                    connection_key=connection_key,
                )
            ).strip()
        launch_transport = launch_transport or "local_helper"
        if launch_transport == "remote_helper":
            if self._resolve_terminal_helper is None:
                raise RuntimeError("Terminal helper resolver is unavailable")
            launch_id = str((spec.get("launch") or {}).get("launch_id") or "").strip()
            if not launch_id:
                synthetic_launch_id = f"dispatch-{hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]}"
                spec["launch"] = {"launch_id": synthetic_launch_id}
                launch_id = synthetic_launch_id
            spec["launch_kind"] = "open_scoped_command"
            spec_file = self.write_remote_spec(spec=spec, launch_kind="open_scoped_command")
            helper_path = self._resolve_terminal_helper("project-remote-launch.py")
            unit_name = (
                f"i3pm-remote-dispatch-{re.sub(r'[^a-zA-Z0-9_.-]+', '-', str(spec.get('app_name') or 'cmd'))}"
                f"-{os.getpid()}-{int(time.time())}"
            )
            result = self._run_command(
                [
                    "systemd-run",
                    "--user",
                    "--quiet",
                    "--collect",
                    "--unit",
                    unit_name,
                    str(helper_path),
                    str(spec_file),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                self.write_status(
                    launch_id=launch_id,
                    status="failed",
                    spec=spec,
                    error_code="remote_command_dispatch_start_failed",
                    error_message=detail or "remote launcher dispatch error",
                )
                raise RuntimeError(f"Managed remote terminal command failed: {detail or 'remote launcher dispatch error'}")
            self.write_status(
                launch_id=launch_id,
                status="starting_remote_command",
                spec=spec,
            )
            return {
                "success": True,
                "reason": "queued",
                "launch_id": launch_id,
                "unit_name": unit_name,
            }

        local_project_dir = str(spec.get("local_project_directory") or "").strip()
        if not local_project_dir:
            raise RuntimeError("Managed local terminal command dispatch requires local_project_directory")
        dispatch_script = self.managed_tmux_command_shell(
            session_name=tmux_session_name,
            tmux_socket=tmux_socket,
            working_dir=local_project_dir,
            command_args=helper_args,
            environment=environment,
        )
        result = self._run_command(
            ["bash", "-lc", dispatch_script],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise RuntimeError(f"Managed local terminal command failed: {detail or 'tmux dispatch error'}")
        return {
            "success": True,
            "reason": "ok",
        }

    def managed_tmux_session_probe(self, spec: Dict[str, Any]) -> Dict[str, Any]:
        """Inspect managed tmux session health for a deterministic launch spec."""
        tmux_session_name = str(spec.get("tmux_session_name") or "").strip()
        if not tmux_session_name:
            return {
                "exists": False,
                "healthy": False,
                "reason": "missing_session_name",
            }
        environment = spec.get("environment") or {}
        tmux_socket = str(environment.get("I3PM_TMUX_SOCKET") or spec.get("tmux_socket") or "").strip()
        if not tmux_socket:
            tmux_socket = self._canonical_tmux_socket()
        expected_context = str(spec.get("context_key") or "").strip()
        expected_role = str(spec.get("terminal_role") or "").strip()
        expected_server_key = str(environment.get("I3PM_TMUX_SERVER_KEY") or tmux_socket).strip()
        tmux_cmd = [
            "tmux",
            "-S",
            tmux_socket,
        ]

        def _tmux_stdout(*args: str) -> str:
            result = self._run_command(
                [*tmux_cmd, *args],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError((result.stderr or result.stdout or "").strip() or "tmux error")
            return (result.stdout or "").strip()

        has_session = self._run_command(
            [*tmux_cmd, "has-session", "-t", tmux_session_name],
            capture_output=True,
            text=True,
            check=False,
        )
        if has_session.returncode != 0:
            return {
                "exists": False,
                "healthy": False,
                "reason": "missing_session",
                "tmux_session_name": tmux_session_name,
                "tmux_socket": tmux_socket,
            }

        def _read_option(option_name: str) -> str:
            try:
                return _tmux_stdout("show-options", "-t", tmux_session_name, "-qv", option_name)
            except RuntimeError:
                return ""

        metadata = {
            "managed": _read_option("@i3pm_managed"),
            "context_key": canonicalize_context_key(_read_option("@i3pm_context_key")),
            "terminal_role": _read_option("@i3pm_terminal_role"),
            "tmux_server_key": _read_option("@i3pm_tmux_server_key"),
            "schema_version": _read_option("@i3pm_schema_version"),
        }
        healthy = True
        reason = "healthy"
        normalized_expected_context = canonicalize_context_key(expected_context)
        if metadata["managed"] != "1":
            healthy = False
            reason = "unmanaged"
        elif normalized_expected_context and metadata["context_key"] != normalized_expected_context:
            healthy = False
            reason = "context_mismatch"
        elif expected_role and metadata["terminal_role"] and metadata["terminal_role"] != expected_role:
            healthy = False
            reason = "role_mismatch"
        elif metadata["tmux_server_key"] and metadata["tmux_server_key"] != expected_server_key:
            healthy = False
            reason = "server_key_mismatch"
        elif metadata["schema_version"] and metadata["schema_version"] != "1":
            healthy = False
            reason = "schema_mismatch"
        return {
            "exists": True,
            "healthy": healthy,
            "reason": reason,
            "tmux_session_name": tmux_session_name,
            "tmux_socket": tmux_socket,
            "metadata": metadata,
        }

    async def reconcile_launch_runtime_status(
        self,
        launch_id: str,
        *,
        anchor_bound: Optional[bool] = None,
    ) -> Dict[str, Any]:
        """Advance a persisted launch status using tmux metadata and anchor binding."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return {}
        status = self.read_status(launch_key)
        if not status:
            return {}
        if str(status.get("status") or "").strip() == "failed":
            return status
        spec = self.read_spec(launch_key)
        if not spec:
            return status
        terminal_launch = spec.get("terminal_launch") or {}
        if str(terminal_launch.get("mode") or "").strip() != "managed_project_terminal":
            return status
        if str(spec.get("launch_transport") or "").strip() == "remote_helper":
            return status
        if anchor_bound is None:
            anchor_result = await self.terminal_anchor(str(spec.get("terminal_anchor_id") or "").strip())
            anchor_bound = bool(anchor_result.get("matched", False) and int(anchor_result.get("window_id") or 0) > 0)
        probe = self.managed_tmux_session_probe(spec)
        current_status = str(status.get("status") or "").strip() or "queued"
        transitional_states = {"queued", "starting_terminal", "session_validating", "waiting_window"}
        if not probe.get("exists", False):
            if current_status in {"queued", "starting_terminal"}:
                return self.write_status(
                    launch_id=launch_key,
                    status="starting_terminal",
                    spec=spec,
                    reason="starting_terminal",
                )
            return status
        if not probe.get("healthy", False):
            if current_status in transitional_states:
                next_status = "waiting_window" if anchor_bound is False else "session_validating"
                if anchor_bound:
                    next_status = "session_validating"
                return self.write_status(
                    launch_id=launch_key,
                    status=next_status,
                    spec=spec,
                    reason=str(probe.get("reason") or next_status),
                    extra={
                        "tmux_session_exists": True,
                        "tmux_session_healthy": False,
                        "tmux_session_name": str(probe.get("tmux_session_name") or ""),
                        "tmux_socket": str(probe.get("tmux_socket") or ""),
                        "anchor_bound": bool(anchor_bound),
                    },
                )
            return self.write_status(
                launch_id=launch_key,
                status="failed",
                spec=spec,
                reason=str(probe.get("reason") or "invalid_managed_session"),
                error_code="invalid_managed_session",
                error_message=str(probe.get("reason") or "managed tmux metadata mismatch"),
                extra={
                    "tmux_session_exists": True,
                    "tmux_session_healthy": False,
                },
            )
        next_status = "running" if anchor_bound else "reusable_headless"
        reason = "window_bound" if anchor_bound else "headless_reusable"
        if current_status in {"queued", "starting_terminal", "session_validating"} and not anchor_bound:
            next_status = "waiting_window"
            reason = "waiting_window"
        return self.write_status(
            launch_id=launch_key,
            status=next_status,
            spec=spec,
            reason=reason,
            extra={
                "tmux_session_exists": True,
                "tmux_session_healthy": True,
                "tmux_session_name": str(probe.get("tmux_session_name") or ""),
                "tmux_socket": str(probe.get("tmux_socket") or ""),
                "anchor_bound": bool(anchor_bound),
            },
        )

    async def run_launch_reconcile_loop(
        self,
        launch_id: str,
        *,
        anchor_bound: Optional[bool],
        attempts: int,
        delay_s: float,
    ) -> None:
        """Drive a deterministic launch to a terminal state without client polling."""
        try:
            last_result: Dict[str, Any] = {}
            for attempt in range(max(int(attempts), 1)):
                result = await self.reconcile_launch_runtime_status(
                    launch_id,
                    anchor_bound=anchor_bound,
                )
                last_result = result
                status_value = str(result.get("status") or "").strip()
                if status_value in {"running", "reusable_headless", "failed"}:
                    return
                if attempt + 1 < max(int(attempts), 1):
                    await asyncio.sleep(delay_s)
            spec = self.read_spec(launch_id)
            probe = self.managed_tmux_session_probe(spec)
            status_value = str(last_result.get("status") or "").strip()
            if spec and status_value in {"queued", "starting_terminal", "session_validating", "waiting_window"}:
                self.write_status(
                    launch_id=launch_id,
                    status="failed",
                    spec=spec,
                    reason=str(probe.get("reason") or "launch_reconcile_timeout"),
                    error_code="invalid_managed_session" if probe.get("exists", False) else "managed_session_missing",
                    error_message=str(probe.get("reason") or "managed session did not become healthy in time"),
                    extra={
                        "tmux_session_exists": bool(probe.get("exists", False)),
                        "tmux_session_healthy": bool(probe.get("healthy", False)),
                        "tmux_session_name": str(probe.get("tmux_session_name") or ""),
                        "tmux_socket": str(probe.get("tmux_socket") or ""),
                        "anchor_bound": bool(anchor_bound),
                    },
                )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.debug("Launch reconcile loop failed for %s: %s", launch_id, exc)
        finally:
            task = self._launch_reconcile_tasks.get(launch_id)
            if task is asyncio.current_task():
                self._launch_reconcile_tasks.pop(launch_id, None)

    def schedule_launch_reconcile(
        self,
        launch_id: str,
        *,
        anchor_bound: Optional[bool],
        attempts: int = 25,
        delay_s: float = 0.2,
    ) -> None:
        """Ensure a bounded daemon task reconciles launch status without external polling."""
        if self._schedule_launch_reconcile_callback is not None:
            self._schedule_launch_reconcile_callback(
                launch_id,
                anchor_bound=anchor_bound,
                attempts=attempts,
                delay_s=delay_s,
            )
            return

        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return
        existing = self._launch_reconcile_tasks.get(launch_key)
        if existing is not None and not existing.done():
            return
        self._launch_reconcile_tasks[launch_key] = asyncio.create_task(
            self.run_launch_reconcile_loop(
                launch_key,
                anchor_bound=anchor_bound,
                attempts=attempts,
                delay_s=delay_s,
            ),
            name=f"launch-reconcile:{launch_key}",
        )

    async def stop_reconcile_tasks(self, *, timeout: float = 2.0) -> bool:
        """Cancel service-owned reconcile tasks during daemon shutdown."""
        tasks = list(self._launch_reconcile_tasks.values())
        for task in tasks:
            task.cancel()
        if not tasks:
            return True
        try:
            await asyncio.wait_for(
                asyncio.gather(*tasks, return_exceptions=True),
                timeout=max(float(timeout), 0.1),
            )
            return True
        except asyncio.TimeoutError:
            logger.warning("Timed out waiting for launch reconcile tasks to stop; continuing shutdown")
            return False
        finally:
            self._launch_reconcile_tasks.clear()

    async def mark_launch_window_bound(
        self,
        *,
        launch_id: str,
        window_id: int,
        terminal_anchor_id: str = "",
    ) -> Dict[str, Any]:
        """Mark a terminal launch as running once a window is bound."""
        result = await self.reconcile_launch_runtime_status(launch_id, anchor_bound=True)
        if not result:
            return {}
        if str(result.get("status") or "").strip() == "failed":
            return result
        if str(result.get("status") or "").strip() == "running":
            return result
        spec = self.read_spec(launch_id)
        terminal_launch = (spec or {}).get("terminal_launch") or {}
        if str(terminal_launch.get("mode") or "").strip() != "managed_project_terminal":
            return self.write_status(
                launch_id=launch_id,
                status="running",
                spec=spec or None,
                reason="window_bound",
                extra={
                    "window_id": int(window_id or 0),
                    "anchor_bound": True,
                    "terminal_anchor_id": str(terminal_anchor_id or result.get("terminal_anchor_id") or "").strip(),
                },
            )
        probe = self.managed_tmux_session_probe(spec or {})
        for _attempt in range(5):
            if bool(probe.get("exists", False) and probe.get("healthy", False)):
                break
            await asyncio.sleep(0.2)
            probe = self.managed_tmux_session_probe(spec or {})
        if not bool(probe.get("exists", False) and probe.get("healthy", False)):
            self.schedule_launch_reconcile(launch_id, anchor_bound=True, attempts=25, delay_s=0.2)
            return result
        return self.write_status(
            launch_id=launch_id,
            status="running",
            spec=spec or None,
            reason="window_bound",
            extra={
                "window_id": int(window_id or 0),
                "anchor_bound": True,
                "terminal_anchor_id": str(terminal_anchor_id or result.get("terminal_anchor_id") or "").strip(),
                "tmux_session_exists": True,
                "tmux_session_healthy": True,
                "tmux_session_name": str(probe.get("tmux_session_name") or ""),
                "tmux_socket": str(probe.get("tmux_socket") or ""),
            },
        )

    async def mark_launch_window_closed(self, window_info: Any) -> Dict[str, Any]:
        """Reconcile a managed-terminal launch after its client window closes."""
        launch_id = str(getattr(window_info, "correlation_launch_id", "") or "").strip()
        if not launch_id:
            return {}
        result = await self.reconcile_launch_runtime_status(launch_id, anchor_bound=False)
        if str(result.get("status") or "").strip() not in {"reusable_headless", "failed"}:
            self.schedule_launch_reconcile(launch_id, anchor_bound=False, attempts=20, delay_s=0.2)
        return result

    async def launch_status(self, launch_id: str) -> Dict[str, Any]:
        """Return deterministic launch status for a registered launch id."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            raise ValueError("launch_id is required")
        status = await self.reconcile_launch_runtime_status(launch_key)
        if not status:
            status = self.read_status(launch_key)
        if not status:
            return {
                "success": False,
                "launch_id": launch_key,
                "status": "unknown",
                "reason": "launch_not_found",
            }
        status["success"] = str(status.get("status") or "").strip() not in {"failed", "unknown"}
        return status

    async def wait_for_launch_status(
        self,
        launch_id: str,
        *,
        terminal_anchor_id: str = "",
        attempts: int = 50,
        delay_s: float = 0.2,
    ) -> Dict[str, Any]:
        """Poll persisted launch status until a deterministic terminal state is reached."""
        launch_key = str(launch_id or "").strip()
        current: Dict[str, Any] = {
            "success": False,
            "launch_id": launch_key,
            "status": "unknown",
            "reason": "launch_not_found",
        }
        anchor_bound = False
        for attempt in range(max(int(attempts), 1)):
            current = await self.launch_status(launch_key)
            if terminal_anchor_id and not anchor_bound:
                anchor_result = await self.terminal_anchor(terminal_anchor_id)
                anchor_bound = bool(anchor_result.get("matched", False) and int(anchor_result.get("window_id") or 0) > 0)
            status_value = str(current.get("status") or "").strip()
            if status_value == "failed":
                current["success"] = False
                current["reason"] = str(current.get("error_code") or "launch_failed")
                current["anchor_bound"] = anchor_bound
                return current
            if status_value in {"running", "attaching_tmux"} and (not terminal_anchor_id or anchor_bound):
                current["success"] = True
                current["reason"] = "ok"
                current["anchor_bound"] = anchor_bound
                return current
            if status_value == "reusable_headless":
                current["success"] = True
                current["reason"] = str(current.get("reason") or "headless_reusable")
                current["anchor_bound"] = anchor_bound
                return current
            if attempt + 1 < max(int(attempts), 1):
                await asyncio.sleep(delay_s)
        current["success"] = False
        current["reason"] = "launch_status_timeout"
        current["anchor_bound"] = anchor_bound
        return current

    async def terminal_anchor(self, terminal_anchor_id: str) -> Dict[str, Any]:
        """Resolve canonical terminal anchor state from daemon-owned launch/window tracking."""
        anchor = str(terminal_anchor_id or "").strip()
        if not anchor:
            raise ValueError("'terminal_anchor_id' is required")

        if self._get_terminal_anchor is not None:
            return await self._get_terminal_anchor({"terminal_anchor_id": anchor})

        if self._window_map_items is not None:
            for window_id, window_info in self._window_map_items():
                if str(getattr(window_info, "terminal_anchor_id", "") or "").strip() != anchor:
                    continue

                return {
                    "terminal_anchor_id": anchor,
                    "window_id": window_id,
                    "project_name": getattr(window_info, "project", None),
                    "app_name": getattr(window_info, "app_identifier", None),
                    "workspace": getattr(window_info, "workspace", None),
                    "terminal_role": getattr(window_info, "terminal_role", ""),
                    "tmux_session_name": getattr(window_info, "tmux_session_name", ""),
                    "matched": True,
                    "binding": "window_map",
                }

        pending_launch = None
        if self._get_pending_launch_by_terminal_anchor is not None:
            pending_launch = await self._get_pending_launch_by_terminal_anchor(anchor)
        if pending_launch:
            return {
                "launch_id": str(getattr(pending_launch, "launch_id", "") or "").strip(),
                "terminal_anchor_id": anchor,
                "window_id": None,
                "project_name": pending_launch.project_name,
                "app_name": pending_launch.app_name,
                "workspace": pending_launch.workspace_number,
                "matched": False,
                "binding": "pending",
            }

        return {
            "terminal_anchor_id": anchor,
            "window_id": None,
            "error": "not_found",
            "matched": False,
        }

    async def wait_for_terminal_window(
        self,
        terminal_anchor_id: str,
        *,
        attempts: int = 30,
        delay_s: float = 0.2,
    ) -> Dict[str, Any]:
        """Poll launch/window tracking until a terminal anchor resolves to a window."""
        anchor = str(terminal_anchor_id or "").strip()
        result: Dict[str, Any] = {
            "matched": False,
            "window_id": 0,
            "terminal_anchor_id": anchor,
        }
        for attempt in range(max(int(attempts), 1)):
            result = await self.terminal_anchor(anchor)
            window_id = int(result.get("window_id") or 0)
            if bool(result.get("matched", False)) and window_id > 0:
                return result
            if attempt + 1 < max(int(attempts), 1):
                await asyncio.sleep(delay_s)
        return result

    def resolve_terminal_helper(self, helper_name: str) -> Path:
        """Resolve installed terminal helpers, with a repo fallback for local development."""
        helper_dir = os.environ.get("I3PM_TERMINAL_HELPER_DIR", "").strip()
        if helper_dir:
            packaged_helper = Path(helper_dir) / helper_name
            if packaged_helper.is_file():
                return packaged_helper

        local_helper = Path.home() / ".local" / "bin" / helper_name
        if local_helper.is_file():
            return local_helper

        helper_path = self._which(helper_name)
        if helper_path:
            return Path(helper_path)

        if self._repo_root is not None:
            repo_helper = self._repo_root() / "scripts" / helper_name
            if repo_helper.is_file():
                return repo_helper

        raise RuntimeError(f"Terminal helper not found: {helper_name}")

    def _terminal_helper(self, helper_name: str) -> Path:
        if self._resolve_terminal_helper is not None:
            return self._resolve_terminal_helper(helper_name)
        return self.resolve_terminal_helper(helper_name)

    def reap_orphan_app_units(self, app_name: str, app_command: str) -> None:
        """Stop orphan systemd user units left behind by a previous launch of this app."""
        systemctl = self._which("systemctl") or "/run/current-system/sw/bin/systemctl"
        binary = os.path.basename(str(app_command or "").strip())
        sanitized_command = re.sub(r"[^a-zA-Z0-9_.-]+", "-", binary) if binary else ""
        sanitized_app = re.sub(r"[^a-zA-Z0-9_.-]+", "-", str(app_name or "")).strip("-")

        prefixes: list[tuple[str, str]] = []
        if sanitized_command:
            prefixes.append((f"app-{sanitized_command}-", ".scope"))
        if sanitized_app:
            prefixes.append((f"i3pm-launch-{sanitized_app}-", ".service"))

        if not prefixes:
            return

        try:
            result = self._run_command(
                [
                    systemctl,
                    "--user",
                    "list-units",
                    "--all",
                    "--no-legend",
                    "--plain",
                    "--type=scope,service",
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            logger.warning(
                "Failed to enumerate user units while reaping orphans for %s: %s",
                app_name,
                exc,
            )
            return

        units_to_stop: list[str] = []
        for line in result.stdout.splitlines():
            unit = line.split(maxsplit=1)[0].strip() if line.strip() else ""
            if not unit:
                continue
            for prefix, suffix in prefixes:
                if unit.startswith(prefix) and unit.endswith(suffix):
                    units_to_stop.append(unit)
                    break

        for unit in units_to_stop:
            try:
                self._run_command(
                    [systemctl, "--user", "stop", unit],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=10,
                )
                logger.info(
                    "Reaped orphan unit %s before relaunching %s",
                    unit,
                    app_name,
                )
            except (OSError, subprocess.SubprocessError) as exc:
                logger.warning("Failed to stop orphan unit %s: %s", unit, exc)

    def execute_launch_spec(self, spec: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a daemon-prepared launch spec via systemd-run."""
        app_name = str(spec.get("app_name") or "").strip()
        command = str(spec.get("command") or "").strip()
        args = [str(arg) for arg in (spec.get("args") or [])]
        shell_command = ""
        execution_mode = str(spec.get("execution_mode") or "local").strip() or "local"
        connection_key = str(spec.get("connection_key") or "").strip()
        local_project_dir = str(spec.get("local_project_directory") or "").strip()
        environment = {
            str(key): str(value)
            for key, value in (spec.get("environment") or {}).items()
        }
        terminal_launch = spec.get("terminal_launch") or {}
        terminal_mode = str(terminal_launch.get("mode") or "").strip()
        helper_name = str(terminal_launch.get("helper_name") or "").strip()
        helper_args = [str(arg) for arg in (terminal_launch.get("helper_args") or [])]
        launch_transport = str(spec.get("launch_transport") or "").strip()
        if not launch_transport and self._resolve_terminal_launch_transport is not None:
            launch_transport = str(
                self._resolve_terminal_launch_transport(
                    execution_mode=execution_mode,
                    connection_key=connection_key,
                )
            ).strip()
        launch_transport = launch_transport or "local_helper"

        if app_name == "k9s":
            kubeconfig_path = Path.home() / ".kube" / "stacks" / "config"
            if not kubeconfig_path.is_file():
                sync_cmd = self._which("sync-stacks-kubeconfigs")
                if not sync_cmd:
                    raise RuntimeError("Expected kubeconfig not found and sync-stacks-kubeconfigs is unavailable")
                self._run_command([sync_cmd], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if not kubeconfig_path.is_file():
                    raise RuntimeError("Expected kubeconfig not found after sync")
            environment["KUBECONFIG"] = str(kubeconfig_path)

        launch_id = str((spec.get("launch") or {}).get("launch_id") or "").strip()

        if terminal_mode == "managed_project_terminal" and launch_transport == "local_helper":
            if not local_project_dir:
                raise RuntimeError("Managed local terminal launch requires local_project_directory")
            launch_script = self._terminal_helper(helper_name or "project-terminal-launch.sh")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), local_project_dir, *helper_args]
                )
            )
        elif terminal_mode == "managed_project_terminal" and launch_transport == "remote_helper":
            spec["launch_kind"] = (
                "attach_ai_session"
                if bool((terminal_launch.get("remote_attach") or {}))
                else "open_project_terminal"
            )
            spec_file = self.write_remote_spec(spec=spec, launch_kind=str(spec.get("launch_kind") or "open_project_terminal"))
            launch_script = self._terminal_helper("project-remote-launch.py")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), str(spec_file)]
                )
            )
        elif terminal_mode == "dedicated_scoped_window" and launch_transport == "local_helper":
            if not local_project_dir:
                raise RuntimeError("Dedicated scoped terminal launch requires local_project_directory")
            launch_script = self._terminal_helper(helper_name or "project-command-launch.sh")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), local_project_dir, *helper_args]
                )
            )
        elif terminal_mode == "dedicated_scoped_window" and launch_transport == "remote_helper":
            spec["launch_kind"] = "open_project_terminal"
            spec_file = self.write_remote_spec(spec=spec, launch_kind="open_project_terminal")
            launch_script = self._terminal_helper("project-remote-launch.py")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), str(spec_file)]
                )
            )
        elif terminal_mode == "scoped_terminal_command" and launch_transport == "local_helper":
            if not local_project_dir:
                raise RuntimeError("Scoped local terminal launch requires local_project_directory")
            launch_script = self._terminal_helper(helper_name or "project-command-launch.sh")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), local_project_dir, *helper_args]
                )
            )
        elif terminal_mode == "scoped_terminal_command" and launch_transport == "remote_helper":
            spec["launch_kind"] = "open_project_terminal"
            spec_file = self.write_remote_spec(spec=spec, launch_kind="open_project_terminal")
            launch_script = self._terminal_helper("project-remote-launch.py")
            shell_command = (
                f"exec {shlex.quote(command)} -e "
                + " ".join(
                    shlex.quote(part)
                    for part in [str(launch_script), str(spec_file)]
                )
            )
        elif execution_mode == "ssh":
            raise RuntimeError("Remote project execution only supports daemon-managed terminal launches")

        if not command:
            raise RuntimeError("Launch spec is missing command")
        if self._which(command) is None and not Path(command).exists():
            raise RuntimeError(f"Command not found: {command}")

        workdir = Path.home()
        if launch_transport == "local_helper" and local_project_dir:
            workdir = Path(local_project_dir)

        resolved_command = self._which(command) or command
        direct_pwa_launch = (
            execution_mode == "local"
            and not terminal_mode
            and Path(resolved_command).name == "launch-pwa-by-name"
        )

        if direct_pwa_launch:
            env_prefix = [
                "env",
                *[
                    f"{key}={value}"
                    for key, value in environment.items()
                ],
            ]
            shell_command = " ".join(
                shlex.quote(part)
                for part in [*env_prefix, resolved_command, *args]
            )
            result = self._run_command(
                ["swaymsg", "--quiet", f"exec {shell_command}"],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                if launch_id:
                    self.write_status(
                        launch_id=launch_id,
                        status="failed",
                        spec=spec,
                        reason="launch_start_failed",
                        error_code="launch_start_failed",
                        error_message=detail or "swaymsg exec error",
                    )
                raise RuntimeError(f"Detached PWA launch failed: {detail or 'swaymsg exec error'}")
            if launch_id:
                self.write_status(
                    launch_id=launch_id,
                    status="waiting_window",
                    spec=spec,
                    reason="waiting_window",
                )
            return {
                "success": True,
                "pid": 0,
                "launch_id": launch_id,
                "status": self.read_status(launch_id) if launch_id else {},
            }

        unit_name = f"i3pm-launch-{re.sub(r'[^a-zA-Z0-9_.-]+', '-', app_name or 'app')}-{os.getpid()}-{int(time.time())}"
        systemd_cmd = [
            "systemd-run",
            "--user",
            "--quiet",
            "--collect",
            "--unit",
            unit_name,
            "--working-directory",
            str(workdir),
        ]
        if terminal_mode == "managed_project_terminal" and launch_transport == "local_helper":
            # This path may create the shared tmux server. Keep unit teardown from
            # reaping that server and every pane attached to the canonical socket.
            systemd_cmd.append("--property=KillMode=process")
        for key, value in environment.items():
            systemd_cmd.extend(["--setenv", f"{key}={value}"])
        if shell_command:
            systemd_cmd.extend(["bash", "-lc", shell_command])
        else:
            systemd_cmd.append(command)
            systemd_cmd.extend(args)

        if launch_id:
            self.write_status(
                launch_id=launch_id,
                status="starting_terminal",
                spec=spec,
                reason="starting_terminal",
            )
        result = self._run_command(systemd_cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            if launch_id:
                self.write_status(
                    launch_id=launch_id,
                    status="failed",
                    spec=spec,
                    reason="launch_start_failed",
                    error_code="launch_start_failed",
                    error_message=detail or "systemd-run error",
                )
            raise RuntimeError(f"Detached launch failed: {detail or 'systemd-run error'}")

        if launch_id:
            if terminal_mode == "managed_project_terminal":
                self.write_status(
                    launch_id=launch_id,
                    status="session_validating",
                    spec=spec,
                    reason="session_validating",
                )
                if launch_transport == "local_helper":
                    self.schedule_launch_reconcile(launch_id, anchor_bound=None, attempts=30, delay_s=0.2)
            else:
                self.write_status(
                    launch_id=launch_id,
                    status="waiting_window",
                    spec=spec,
                    reason="waiting_window",
                )

        return {
            "success": True,
            "unit_name": unit_name,
            "launch_id": launch_id,
            "status": self.read_status(launch_id) if launch_id else {},
        }
