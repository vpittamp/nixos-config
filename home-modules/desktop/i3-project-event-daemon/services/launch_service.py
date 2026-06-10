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
from typing import Any, Awaitable, Callable, Dict, List, Optional

from ..config import atomic_write_json
from ..worktree_utils import canonicalize_context_key

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
            if self._get_terminal_anchor is None:
                anchor_bound = False
            else:
                anchor_result = await self._get_terminal_anchor({
                    "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
                })
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
            if terminal_anchor_id and not anchor_bound and self._get_terminal_anchor is not None:
                anchor_result = await self._get_terminal_anchor({"terminal_anchor_id": terminal_anchor_id})
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
