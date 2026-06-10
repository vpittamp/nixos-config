"""Launch persistence service for daemon-owned launch specs and status."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from ..config import atomic_write_json


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
