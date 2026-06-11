"""Daemon-owned focus view-model state and selection rules."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shlex
import time
from typing import Any, Awaitable, Callable, Dict, Iterable, List, Optional, Set, Tuple

from ..models.window_command import CommandBatch


FOCUS_STATE_SCHEMA_VERSION = "i3pm.focus_state.v2"
FOCUS_INTENT_METHODS = {
    "herdr.pane.focus",
    "herdr.remote.pane.focus",
    "herdr.workspace.focus",
    "window.focus",
    "window.focus_fast",
    "workspace.focus",
    "workspace.focus_fast",
}

logger = logging.getLogger(__name__)


class FocusService:
    """Own focus overrides and dashboard focus view-model construction."""

    def __init__(
        self,
        *,
        normalize_connection_key: Callable[[str], str],
        schema_version: str = FOCUS_STATE_SCHEMA_VERSION,
        sway_available: Optional[Callable[[], bool]] = None,
        run_sway_command: Optional[Callable[[str], Awaitable[Any]]] = None,
        sway_command_succeeded: Optional[Callable[[Any], bool]] = None,
        get_sway_workspaces: Optional[Callable[[], Awaitable[Any]]] = None,
        get_sway_tree: Optional[Callable[[], Awaitable[Any]]] = None,
        send_tick_barrier: Optional[Callable[[str], Awaitable[None]]] = None,
        notify_state_change: Optional[Callable[[str], Awaitable[None]]] = None,
        window_is_locally_tracked: Optional[Callable[[int], Awaitable[bool]]] = None,
        connection_target_is_current_host: Optional[Callable[[str], bool]] = None,
        local_host: Optional[Callable[[], str]] = None,
        window_map_snapshot: Optional[Callable[[], Awaitable[Dict[Any, Any]]]] = None,
        remote_daemon_request: Optional[Callable[..., Awaitable[Dict[str, Any]]]] = None,
        parse_remote_target: Optional[Callable[[str, str], Tuple[str, str, int]]] = None,
        remote_run_command: Optional[Callable[..., Awaitable[Any]]] = None,
        switch_runtime_context: Optional[Callable[[str, str, str], Awaitable[Dict[str, Any]]]] = None,
        get_window_transition_state: Optional[Callable[[int], Awaitable[Dict[str, Any]]]] = None,
        build_window_focus_transition: Optional[Callable[..., Dict[str, Any]]] = None,
        get_saved_window_state: Optional[Callable[[int], Awaitable[Any]]] = None,
        window_matches_transition_target: Optional[Callable[[Dict[str, Any]], Awaitable[bool]]] = None,
        verify_window_focus: Optional[Callable[[int], Awaitable[Dict[str, Any]]]] = None,
        focus_state_provider: Optional[Callable[[Optional[Dict[str, Any]]], Awaitable[Dict[str, Any]]]] = None,
    ) -> None:
        self._normalize_connection_key = normalize_connection_key
        self.schema_version = schema_version
        self._sway_available = sway_available
        self._run_sway_command = run_sway_command
        self._sway_command_succeeded = sway_command_succeeded
        self._get_sway_workspaces = get_sway_workspaces
        self._get_sway_tree = get_sway_tree
        self._send_tick_barrier = send_tick_barrier
        self._notify_state_change = notify_state_change
        self._window_is_locally_tracked = window_is_locally_tracked
        self._connection_target_is_current_host = connection_target_is_current_host
        self._local_host = local_host
        self._window_map_snapshot = window_map_snapshot
        self._remote_daemon_request = remote_daemon_request
        self._parse_remote_target = parse_remote_target
        self._remote_run_command = remote_run_command
        self._switch_runtime_context = switch_runtime_context
        self._get_window_transition_state = get_window_transition_state
        self._build_window_focus_transition = build_window_focus_transition
        self._get_saved_window_state = get_saved_window_state
        self._window_matches_transition_target = window_matches_transition_target
        self._verify_window_focus = verify_window_focus
        self._focus_state_provider = focus_state_provider
        self.session_override_key: str = ""
        self.window_override: Dict[str, Any] = {"window_id": 0, "connection_key": ""}
        self.pending_intent_id: str = ""
        self.focus_intent: Dict[str, Any] = {}
        self.user_intent_epoch: int = 0

    def _workspace_focus_ready(self) -> bool:
        return bool(
            self._sway_available
            and self._sway_available()
            and self._run_sway_command
            and self._sway_command_succeeded
        )

    @staticmethod
    def _workspace_ref(params: Dict[str, Any]) -> str:
        workspace = params.get("workspace")
        if workspace is None:
            raise ValueError("workspace is required")
        workspace_ref = str(workspace).strip()
        if not workspace_ref:
            raise ValueError("workspace must not be empty")
        return workspace_ref

    async def focus_workspace_fast(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Low-latency workspace focus path for click-driven UI actions."""
        if not self._workspace_focus_ready():
            raise RuntimeError("Sway connection is unavailable")

        workspace_ref = self._workspace_ref(params)
        command = f"workspace number {workspace_ref}"
        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        result = await self._run_sway_command(command)
        if not self._sway_command_succeeded(result):
            return {
                "success": False,
                "workspace": workspace_ref,
                "error": f"command_failed:{command}",
                "fallback_method": "workspace.focus",
            }

        self.set_pending_intent("")
        if self._notify_state_change:
            await self._notify_state_change("focus_changed")
        return {"success": True, "workspace": workspace_ref, "fast": True}

    async def focus_workspace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Focus a workspace through the daemon-owned Sway connection."""
        if not self._workspace_focus_ready():
            raise RuntimeError("Sway connection is unavailable")

        workspace_ref = self._workspace_ref(params)
        command = f"workspace number {workspace_ref}"
        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        result = await self._run_sway_command(command)
        if not self._sway_command_succeeded(result):
            return {"success": False, "workspace": workspace_ref, "error": f"command_failed:{command}"}

        if self._send_tick_barrier:
            await self._send_tick_barrier(f"i3pm:workspace-focus:{workspace_ref}")
        self.set_pending_intent("")

        focused_workspace = await self.focused_workspace_name()
        if focused_workspace != workspace_ref:
            matched = await self.wait_for_workspace_focus(workspace_ref, timeout_s=0.5)
            if not matched:
                return {
                    "success": False,
                    "workspace": workspace_ref,
                    "focused_workspace": focused_workspace,
                    "error": f"focus_verification_failed:{workspace_ref}",
                }

        if self._notify_state_change:
            await self._notify_state_change("focus_changed")
        return {"success": True, "workspace": workspace_ref}

    async def focused_workspace_name(self) -> str:
        """Return the currently focused workspace name, if available."""
        if not self._sway_available or not self._sway_available() or not self._get_sway_workspaces:
            return ""
        try:
            workspaces = await self._get_sway_workspaces()
        except Exception:
            return ""

        for workspace in workspaces:
            if bool(getattr(workspace, "focused", False)):
                return str(getattr(workspace, "name", "") or "").strip()
        return ""

    async def wait_for_workspace_focus(self, workspace_ref: str, *, timeout_s: float) -> bool:
        """Wait briefly for Sway to report the requested focused workspace."""
        deadline = time.monotonic() + max(timeout_s, 0.0)
        target = str(workspace_ref or "").strip()
        if not target:
            return False

        while time.monotonic() < deadline:
            focused = await self.focused_workspace_name()
            if focused == target:
                return True
            await asyncio.sleep(0.02)

        return await self.focused_workspace_name() == target

    def _window_focus_ready(self) -> bool:
        return bool(
            self._sway_available
            and self._sway_available()
            and self._run_sway_command
            and self._sway_command_succeeded
        )

    def connection_target_is_current_host(self, connection_key: str) -> bool:
        """Return whether an SSH connection target resolves back to this host."""
        if self._connection_target_is_current_host:
            return bool(self._connection_target_is_current_host(connection_key))
        if not (self._parse_remote_target and self._local_host):
            return False
        try:
            _remote_user, remote_host, _remote_port = self._parse_remote_target("", connection_key)
            normalized_remote_host = str(remote_host or "").strip().lower()
            normalized_local_host = str(self._local_host() or "").strip().lower()
            return bool(normalized_remote_host and normalized_remote_host == normalized_local_host)
        except Exception as exc:
            logger.debug("Failed to resolve connection target host for %s: %s", connection_key, exc)
            return False

    @staticmethod
    def _window_field(window_info: Any, field_name: str) -> int:
        if isinstance(window_info, dict):
            return int(window_info.get(field_name, 0) or 0)
        return int(getattr(window_info, field_name, 0) or 0)

    async def window_is_locally_tracked(self, window_id: int) -> bool:
        """Return whether a target window exists in this host's tracked window map."""
        if self._window_is_locally_tracked:
            return bool(await self._window_is_locally_tracked(int(window_id or 0)))
        if not self._window_map_snapshot:
            return False

        target = int(window_id or 0)
        if target <= 0:
            return False
        try:
            tracked_windows = await self._window_map_snapshot()
        except Exception as exc:
            logger.debug("Failed to read tracked windows while resolving local focus target: %s", exc)
            return False
        if not isinstance(tracked_windows, dict):
            return False
        if target in tracked_windows or str(target) in tracked_windows:
            return True
        for window_info in tracked_windows.values():
            if self._window_field(window_info, "window_id") == target:
                return True
            if self._window_field(window_info, "con_id") == target:
                return True
        return False

    async def focus_window(
        self,
        *,
        window_id: int,
        project_name: str = "",
        target_variant: str = "",
        connection_key: str = "",
        attempts: int = 3,
        delay_s: float = 0.12,
    ) -> Dict[str, Any]:
        """Project-aware window focus flow owned by the focus service."""
        if int(window_id or 0) <= 0:
            raise ValueError("window_id must be a positive integer")
        if not (
            (self._window_is_locally_tracked or self._window_map_snapshot)
            and (self._connection_target_is_current_host or (self._parse_remote_target and self._local_host))
            and (self._remote_daemon_request or self._parse_remote_target)
            and self._switch_runtime_context
            and (self._get_window_transition_state or self._get_sway_tree)
            and (self._window_matches_transition_target or self._get_window_transition_state or self._get_sway_tree)
            and (self._verify_window_focus or self._get_sway_tree)
            and self._focus_state_provider
        ):
            raise RuntimeError("Window focus dependencies are unavailable")

        target_variant_normalized = str(target_variant or "").strip().lower()
        normalized_connection_key = str(connection_key or "").strip()
        normalized_project_name = str(project_name or "").strip()
        local_window_target = await self.window_is_locally_tracked(int(window_id))
        connection_targets_current_host = self.connection_target_is_current_host(normalized_connection_key)
        should_remote_handoff = (
            target_variant_normalized == "ssh"
            and not connection_targets_current_host
            and not local_window_target
        )
        if should_remote_handoff:
            remote_handoff = await self.remote_daemon_request(
                connection_key=normalized_connection_key,
                method="window.focus",
                params={
                    "window_id": int(window_id),
                    "project_name": normalized_project_name,
                    "target_variant": "local",
                    "connection_key": normalized_connection_key,
                },
            )
            remote_host = str(remote_handoff.get("remote_host") or "").strip()
            remote_result = remote_handoff.get("result")
            if remote_host:
                remote_success = bool(remote_handoff.get("success", False))
                if isinstance(remote_result, dict) and "success" in remote_result:
                    remote_success = remote_success and bool(remote_result.get("success", False))
                remote_focus_state_after = (
                    dict(remote_result.get("focus_state_after") or {})
                    if isinstance(remote_result, dict) and isinstance(remote_result.get("focus_state_after"), dict)
                    else {}
                )
                remote_verification = (
                    remote_result.get("verification")
                    if isinstance(remote_result, dict) and isinstance(remote_result.get("verification"), dict)
                    else {}
                )
                current_session_key_after = (
                    str(remote_result.get("current_session_key_after") or "").strip()
                    if isinstance(remote_result, dict)
                    else ""
                )
                if not current_session_key_after:
                    current_session_key_after = str(remote_focus_state_after.get("current_session_key") or "").strip()
                focused_window_id_after = (
                    int(remote_result.get("focused_window_id_after") or 0)
                    if isinstance(remote_result, dict)
                    else 0
                )
                if focused_window_id_after <= 0:
                    focused_window_id_after = int(remote_focus_state_after.get("current_window_id") or 0)
                if focused_window_id_after <= 0 and isinstance(remote_verification, dict):
                    focused_window_id_after = int(remote_verification.get("focused_window_id") or 0)

                if remote_success:
                    self.set_focus_overrides(
                        session_key=current_session_key_after,
                        window_id=int(window_id),
                        connection_key=normalized_connection_key,
                    )

                return {
                    "success": remote_success,
                    "window_id": int(window_id),
                    "project_name": normalized_project_name,
                    "target_variant": "ssh",
                    "connection_key": normalized_connection_key,
                    "switched_context": False,
                    "remote_handoff": remote_handoff,
                    "focus_target_host": remote_host,
                    "current_session_key_after": current_session_key_after,
                    "focused_window_id_after": focused_window_id_after,
                    "focus_state_after": remote_focus_state_after,
                    "verification": (
                        remote_verification
                        if isinstance(remote_verification, dict) and remote_verification
                        else {
                            "success": remote_success,
                            "reason": str(remote_handoff.get("reason") or "remote_handoff"),
                        }
                    ),
                }

        if not self._window_focus_ready():
            raise RuntimeError("Sway connection is unavailable")

        runtime_target_variant = target_variant_normalized
        runtime_connection_key = normalized_connection_key
        if target_variant_normalized == "ssh" and (
            local_window_target or connection_targets_current_host
        ):
            runtime_target_variant = ""
            runtime_connection_key = ""

        switch_result = await self._switch_runtime_context(
            normalized_project_name,
            runtime_target_variant,
            runtime_connection_key,
        )
        last_error = ""
        verification: Dict[str, Any] = {
            "success": False,
            "reason": "focus_failed",
            "window_id": int(window_id),
            "focused_window_id": 0,
        }

        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        assert self._send_tick_barrier is not None

        for _ in range(max(int(attempts), 1)):
            try:
                transition_state = await self.get_window_transition_state(int(window_id))
                if not bool(transition_state.get("exists", False)):
                    last_error = "window_not_found"
                    await asyncio.sleep(delay_s)
                    continue
                transition = self.build_window_focus_transition(
                    window_id=int(window_id),
                    state=transition_state,
                )
                logger.info(
                    "window.focus transition=%s window=%s current_ws=%s target_ws=%s scratchpad=%s floating=%s fullscreen=%s",
                    transition.get("kind"),
                    int(window_id),
                    str(transition_state.get("current_workspace") or ""),
                    str((transition.get("expected") or {}).get("workspace_name") or ""),
                    bool(transition_state.get("in_scratchpad", False)),
                    bool((transition.get("expected") or {}).get("floating", False)),
                    int((transition.get("expected") or {}).get("fullscreen_mode", 0) or 0),
                )
                focus_result = await self._run_sway_command("; ".join(transition.get("commands") or []))
                if not self._sway_command_succeeded(focus_result):
                    last_error = "focus_failed"
                    await asyncio.sleep(delay_s)
                    continue
                await self._send_tick_barrier(f"i3pm:focus-window:{int(window_id)}")
                verification = await self.verify_window_focus(int(window_id))
                if bool(verification.get("success", False)) and await self.window_matches_transition_target(
                    dict(transition.get("expected") or {})
                ):
                    focus_state_after = await self._focus_state_provider({})
                    self.set_focus_overrides(
                        session_key=str(focus_state_after.get("current_session_key") or "").strip(),
                        window_id=int(window_id),
                        connection_key=normalized_connection_key,
                    )
                    return {
                        "success": True,
                        "window_id": int(window_id),
                        "project_name": normalized_project_name,
                        "target_variant": str(target_variant or "").strip(),
                        "connection_key": normalized_connection_key,
                        "switched_context": bool(switch_result.get("switched", False)),
                        "current_session_key_after": str(focus_state_after.get("current_session_key") or "").strip(),
                        "focused_window_id_after": int(focus_state_after.get("current_window_id") or 0),
                        "focus_state_after": focus_state_after,
                        "verification": verification,
                    }
                last_error = str(verification.get("reason") or "window_focus_unverified")
                if last_error == "ok":
                    last_error = "window_state_mismatch"
            except Exception as e:
                last_error = str(e)
            await asyncio.sleep(delay_s)

        focus_state_after = await self._focus_state_provider({})
        return {
            "success": False,
            "window_id": int(window_id),
            "project_name": normalized_project_name,
            "target_variant": str(target_variant or "").strip(),
            "connection_key": normalized_connection_key,
            "switched_context": bool(switch_result.get("switched", False)),
            "error": last_error or "focus_failed",
            "current_session_key_after": str(focus_state_after.get("current_session_key") or "").strip(),
            "focused_window_id_after": int(focus_state_after.get("current_window_id") or 0),
            "focus_state_after": focus_state_after,
            "verification": verification,
        }

    async def focus_window_fast(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Low-latency local window focus path for click-driven UI actions."""
        if not self._window_focus_ready():
            raise RuntimeError("Sway connection is unavailable")
        if not (
            (self._window_is_locally_tracked or self._window_map_snapshot)
            and (self._connection_target_is_current_host or (self._parse_remote_target and self._local_host))
            and (self._get_window_transition_state or self._get_sway_tree)
        ):
            raise RuntimeError("Window focus dependencies are unavailable")

        window_id = int(params.get("window_id") or 0)
        if window_id <= 0:
            raise ValueError("window_id must be a positive integer")

        target_variant = str(params.get("target_variant") or "").strip().lower()
        connection_key = str(params.get("connection_key") or "").strip()
        if target_variant == "ssh":
            local_window_target = await self.window_is_locally_tracked(window_id)
            connection_targets_current_host = self.connection_target_is_current_host(connection_key)
            if not local_window_target and not connection_targets_current_host:
                return {
                    "success": False,
                    "window_id": int(window_id),
                    "reason": "remote_target_not_fast_focusable",
                    "fallback_method": "window.focus",
                }

        session_key = str(params.get("session_key") or "").strip()
        direct_command = f"[con_id={window_id}] focus"
        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        direct_result = await self._run_sway_command(direct_command)
        if self._sway_command_succeeded(direct_result):
            self.set_focus_overrides(
                session_key=session_key,
                window_id=int(window_id),
                connection_key=connection_key,
            )
            if self._notify_state_change:
                await self._notify_state_change("focus_changed")
            return {
                "success": True,
                "window_id": int(window_id),
                "fast": True,
                "direct": True,
                "command": direct_command,
                "transition": "direct_focus",
            }

        transition_state = await self.get_window_transition_state(window_id)
        if not bool(transition_state.get("exists", False)):
            return {
                "success": False,
                "window_id": int(window_id),
                "reason": "window_not_found",
                "fallback_method": "window.focus",
            }

        transition = self.build_window_focus_transition(
            window_id=window_id,
            state=transition_state,
        )
        command = "; ".join(transition.get("commands") or [])
        if not command:
            return {
                "success": False,
                "window_id": int(window_id),
                "reason": "empty_focus_command",
                "fallback_method": "window.focus",
            }

        result = await self._run_sway_command(command)
        if not self._sway_command_succeeded(result):
            return {
                "success": False,
                "window_id": int(window_id),
                "reason": f"command_failed:{command}",
                "fallback_method": "window.focus",
            }

        self.set_focus_overrides(
            session_key=session_key,
            window_id=int(window_id),
            connection_key=connection_key,
        )
        if self._notify_state_change:
            await self._notify_state_change("focus_changed")
        return {
            "success": True,
            "window_id": int(window_id),
            "fast": True,
            "command": command,
            "transition": str(transition.get("kind") or ""),
        }

    async def remote_daemon_request(
        self,
        *,
        connection_key: str,
        method: str,
        params: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Execute a daemon JSON-RPC call on a remote host over SSH."""
        if self._remote_daemon_request:
            return await self._remote_daemon_request(
                connection_key=connection_key,
                method=method,
                params=params,
            )
        if not self._parse_remote_target:
            raise RuntimeError("Remote focus transport dependencies are unavailable")

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

        if self._remote_run_command:
            result = await self._remote_run_command(
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
        else:
            from ..subprocess_utils import run_command
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

        parsed = self.extract_json_payload(str(getattr(result, "stdout", "") or ""))
        transport_success = int(getattr(result, "returncode", 1) or 0) == 0
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
            "stdout": str(getattr(result, "stdout", "") or "").strip(),
            "stderr": str(getattr(result, "stderr", "") or "").strip(),
            "result": parsed,
        }

    @staticmethod
    def extract_json_payload(raw_output: str) -> Optional[Any]:
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

    @staticmethod
    def find_focused_tree_node(node: Any) -> Optional[Any]:
        """Recursively find the currently focused tree node."""
        if bool(getattr(node, "focused", False)):
            return node
        for child in list(getattr(node, "nodes", []) or []):
            match = FocusService.find_focused_tree_node(child)
            if match is not None:
                return match
        for child in list(getattr(node, "floating_nodes", []) or []):
            match = FocusService.find_focused_tree_node(child)
            if match is not None:
                return match
        return None

    @staticmethod
    def find_tree_node_by_id(node: Any, target_id: int) -> Optional[Any]:
        """Recursively walk a Sway tree node to find a container by id."""
        if getattr(node, "id", None) == target_id:
            return node
        for child in list(getattr(node, "nodes", []) or []):
            match = FocusService.find_tree_node_by_id(child, target_id)
            if match is not None:
                return match
        for child in list(getattr(node, "floating_nodes", []) or []):
            match = FocusService.find_tree_node_by_id(child, target_id)
            if match is not None:
                return match
        return None

    @staticmethod
    def container_is_in_scratchpad(container: Any) -> bool:
        """Return whether a container is currently attached to the scratchpad tree."""
        parent = container
        while parent:
            scratchpad_state = str(getattr(parent, "scratchpad_state", "") or "").strip().lower()
            if scratchpad_state and scratchpad_state != "none":
                return True
            parent = getattr(parent, "parent", None)
        return False

    @staticmethod
    def workspace_switch_command(workspace_name: str) -> str:
        """Build a safe workspace switch command for an arbitrary workspace name."""
        return f"workspace {shlex.quote(str(workspace_name or '').strip())}"

    @staticmethod
    def empty_window_transition_state(window_id: int) -> Dict[str, Any]:
        """Return the empty transition state for an unavailable or missing window."""
        return {
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

    async def get_window_transition_state(self, window_id: int) -> Dict[str, Any]:
        """Return live and tracked state used to plan a focus transition."""
        if self._get_window_transition_state:
            return await self._get_window_transition_state(int(window_id or 0))

        empty_state = self.empty_window_transition_state(int(window_id or 0))
        if not self._get_sway_tree:
            return empty_state
        if self._sway_available and not self._sway_available():
            return empty_state

        try:
            tree = await self._get_sway_tree()
            focused = self.find_focused_tree_node(tree)
            current_workspace = ""
            if focused is not None:
                focused_workspace = focused.workspace()
                current_workspace = str(getattr(focused_workspace, "name", "") or "").strip()

            node = self.find_tree_node_by_id(tree, int(window_id or 0))
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
            if self._get_saved_window_state:
                try:
                    saved_state = await self._get_saved_window_state(int(window_id or 0))
                except Exception as exc:
                    logger.debug("Failed to load tracked window state for %s: %s", window_id, exc)

            return {
                "exists": True,
                "window_id": int(window_id or 0),
                "current_workspace": current_workspace,
                "workspace_name": workspace_name,
                "workspace_number": workspace_number,
                "in_scratchpad": bool(
                    workspace_name == "__i3_scratch" or self.container_is_in_scratchpad(node)
                ),
                "floating": floating,
                "floating_state": floating_state,
                "fullscreen_mode": fullscreen_mode,
                "geometry": geometry,
                "saved_state": saved_state if isinstance(saved_state, dict) else None,
                "node": node,
            }
        except Exception as exc:
            logger.debug("Failed to inspect transition state for window %s: %s", window_id, exc)
            return empty_state

    def build_window_focus_transition(
        self,
        *,
        window_id: int,
        state: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Plan the commands and expected final state for focusing a window."""
        if self._build_window_focus_transition:
            return self._build_window_focus_transition(window_id=window_id, state=state)

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
            # The saved floating=True is an artifact of scratchpad state; default to tiled.
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
                commands.append(self.workspace_switch_command(expected_workspace_name))
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

    async def focused_window_id(self) -> int:
        """Return the currently focused Sway container id."""
        if not self._get_sway_tree:
            return 0
        if self._sway_available and not self._sway_available():
            return 0
        try:
            tree = await self._get_sway_tree()
            node = self.find_focused_tree_node(tree)
            return int(getattr(node, "id", 0) or 0) if node is not None else 0
        except Exception as exc:
            logger.debug("Failed to resolve focused window id: %s", exc)
            return 0

    async def verify_window_focus(self, window_id: int) -> Dict[str, Any]:
        """Verify that the requested window owns current Sway focus."""
        if self._verify_window_focus:
            return await self._verify_window_focus(int(window_id or 0))
        focused_window_id = await self.focused_window_id()
        success = int(focused_window_id or 0) == int(window_id or 0)
        return {
            "success": success,
            "window_id": int(window_id or 0),
            "focused_window_id": int(focused_window_id or 0),
            "reason": "ok" if success else "focused_window_mismatch",
        }

    async def window_matches_transition_target(self, expected: Dict[str, Any]) -> bool:
        """Verify the focused window converged to the planned visible state."""
        if self._window_matches_transition_target:
            return await self._window_matches_transition_target(expected)
        if not (self._get_window_transition_state or self._get_sway_tree):
            return False
        state = await self.get_window_transition_state(int(expected.get("window_id") or 0))
        if not bool(state.get("exists", False)):
            return False
        if bool(state.get("in_scratchpad", False)) != bool(expected.get("in_scratchpad", False)):
            return False
        if bool(state.get("floating", False)) != bool(expected.get("floating", False)):
            return False
        return int(state.get("fullscreen_mode", 0) or 0) == int(expected.get("fullscreen_mode", 0) or 0)

    async def window_action(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a deterministic daemon-owned action against a window."""
        if not self._window_focus_ready():
            raise RuntimeError("Sway connection is unavailable")

        window_id = int(params.get("window_id") or 0)
        if window_id <= 0:
            raise ValueError("window_id must be a positive integer")

        action = str(params.get("action") or "").strip().lower()
        if not action:
            raise ValueError("action is required")

        if action == "focus":
            return await self.focus_window(
                window_id=window_id,
                project_name=str(params.get("project_name") or "").strip(),
                target_variant=str(params.get("target_variant") or "").strip().lower(),
                connection_key=str(params.get("connection_key") or "").strip(),
                attempts=int(params.get("attempts") or 3),
                delay_s=float(params.get("delay_s") or 0.12),
            )

        action_map = {
            "kill": [f"[con_id={window_id}] kill"],
            "floating_toggle": [f"[con_id={window_id}] floating toggle"],
            "fullscreen_toggle": [f"[con_id={window_id}] fullscreen toggle"],
            "move_scratchpad": [f"[con_id={window_id}] move scratchpad"],
            "move_left": [f"[con_id={window_id}] move left"],
            "move_right": [f"[con_id={window_id}] move right"],
            "move_up": [f"[con_id={window_id}] move up"],
            "move_down": [f"[con_id={window_id}] move down"],
            "layout_stacking": [f"[con_id={window_id}] focus", "layout stacking"],
            "layout_tabbed": [f"[con_id={window_id}] focus", "layout tabbed"],
            "layout_toggle_split": [f"[con_id={window_id}] focus", "layout toggle split"],
            "split_h": [f"[con_id={window_id}] focus", "split h"],
            "split_v": [f"[con_id={window_id}] focus", "split v"],
        }
        if action not in action_map:
            raise ValueError(f"Unsupported window action: {action}")

        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        for command in action_map[action]:
            result = await self._run_sway_command(command)
            if not self._sway_command_succeeded(result):
                return {
                    "success": False,
                    "window_id": window_id,
                    "action": action,
                    "error": f"command_failed:{command}",
                }

        if self._send_tick_barrier:
            await self._send_tick_barrier(f"i3pm:window-action:{action}:{window_id}")
        return {"success": True, "window_id": window_id, "action": action}

    def set_focus_overrides(
        self,
        *,
        session_key: str = "",
        window_id: int = 0,
        connection_key: str = "",
    ) -> None:
        """Persist the last successful daemon-owned focus target."""
        self.session_override_key = str(session_key or "").strip()
        self.window_override = {
            "window_id": int(window_id or 0),
            "connection_key": self._normalize_connection_key(str(connection_key or "").strip()),
        }
        self.pending_intent_id = ""

    def set_window_override(
        self,
        *,
        window_id: int = 0,
        connection_key: str = "",
    ) -> None:
        """Persist a normalized explicit window focus target."""
        self.window_override = {
            "window_id": int(window_id or 0),
            "connection_key": self._normalize_connection_key(str(connection_key or "").strip()),
        }

    def set_pending_intent(self, intent_id: str) -> None:
        """Persist the daemon-owned pending focus intent identifier."""
        normalized_intent_id = str(intent_id or "").strip()
        self.pending_intent_id = normalized_intent_id
        if normalized_intent_id:
            self.focus_intent = {
                "intent_id": normalized_intent_id,
                "kind": "",
                "target_key": "",
                "state": "pending",
                "created_at": 0.0,
                "generation": 0,
            }

    @staticmethod
    def focus_intent_methods() -> Set[str]:
        """Return JSON-RPC methods that participate in focus intent state."""
        return set(FOCUS_INTENT_METHODS)

    @staticmethod
    def focus_intent_kind_and_target(
        *,
        method: str,
        params: Dict[str, Any],
    ) -> Tuple[str, str]:
        """Map a click-driven focus method to the formal focus intent contract."""
        normalized_method = str(method or "").strip()
        if normalized_method in {"window.focus", "window.focus_fast"}:
            return ("window_focus", str(int(params.get("window_id") or 0)))
        if normalized_method in {"workspace.focus", "workspace.focus_fast"}:
            return ("workspace_focus", str(params.get("workspace") or "").strip())
        if normalized_method in {"herdr.pane.focus", "herdr.remote.pane.focus"}:
            host = str(params.get("host") or params.get("ssh_target") or "").strip()
            pane_id = str(params.get("pane_id") or "").strip()
            return ("herdr_pane_focus", f"{host}:{pane_id}" if host else pane_id)
        if normalized_method == "herdr.workspace.focus":
            return ("herdr_workspace_focus", str(params.get("workspace_id") or "").strip())
        return ("", "")

    def begin_user_focus_intent(
        self,
        *,
        intent_id: str,
        method: str,
        params: Dict[str, Any],
        created_at: float,
        generation: int,
    ) -> Dict[str, Any]:
        """Begin a focus intent for a click-driven JSON-RPC method."""
        normalized_method = str(method or "").strip()
        if normalized_method not in FOCUS_INTENT_METHODS:
            return {}
        intent_kind, target_key = self.focus_intent_kind_and_target(
            method=normalized_method,
            params=params,
        )
        return self.begin_focus_intent(
            intent_id=intent_id,
            kind=intent_kind,
            target_key=target_key,
            created_at=created_at,
            generation=generation,
        )

    def advance_user_intent(
        self,
        *,
        method: str,
        params: Optional[Dict[str, Any]] = None,
        created_at: float = 0.0,
    ) -> int:
        """Record a new top-level user intent and begin any matching focus intent."""
        self.user_intent_epoch += 1
        payload = params or {}
        self.begin_user_focus_intent(
            intent_id=f"intent-{self.user_intent_epoch}",
            method=method,
            params=payload,
            created_at=created_at or time.time(),
            generation=self.user_intent_epoch,
        )
        return self.user_intent_epoch

    def user_intent_is_current(self, intent_epoch: int) -> bool:
        """Return whether an async action still matches the latest explicit user intent."""
        epoch = int(intent_epoch or 0)
        return epoch <= 0 or epoch == self.user_intent_epoch

    def finalize_focus_intent_for_result(
        self,
        *,
        method: str,
        intent_epoch: int,
        result: Any,
    ) -> Dict[str, Any]:
        """Confirm or fail the focus intent associated with a handled request."""
        normalized_method = str(method or "").strip()
        normalized_epoch = int(intent_epoch or 0)
        if normalized_method not in FOCUS_INTENT_METHODS or normalized_epoch <= 0:
            return {}

        success = True
        reason = "ok"
        if isinstance(result, dict):
            success = bool(result.get("success", True))
            verification = result.get("verification")
            verification_reason = (
                str(verification.get("reason") or "").strip()
                if isinstance(verification, dict)
                else ""
            )
            reason = str(
                result.get("reason")
                or result.get("error")
                or verification_reason
                or ""
            ).strip() or ("ok" if success else "failed")
        return self.finish_focus_intent(
            intent_id=f"intent-{normalized_epoch}",
            state="confirmed" if success else "failed",
            reason=reason,
        )

    def fail_focus_intent_for_exception(
        self,
        *,
        method: str,
        intent_epoch: int,
        reason: str,
    ) -> Dict[str, Any]:
        """Mark an active focus intent failed when request handling raises."""
        normalized_method = str(method or "").strip()
        normalized_epoch = int(intent_epoch or 0)
        if normalized_method not in FOCUS_INTENT_METHODS or normalized_epoch <= 0:
            return {}
        return self.finish_focus_intent(
            intent_id=f"intent-{normalized_epoch}",
            state="failed",
            reason=str(reason or "exception").strip(),
        )

    def begin_focus_intent(
        self,
        *,
        intent_id: str,
        kind: str,
        target_key: str,
        created_at: float,
        generation: int,
    ) -> Dict[str, Any]:
        """Record a daemon-owned focus intent in pending state."""
        normalized_intent_id = str(intent_id or "").strip()
        if not normalized_intent_id:
            self.pending_intent_id = ""
            self.focus_intent = {}
            return {}
        self.pending_intent_id = normalized_intent_id
        self.focus_intent = {
            "intent_id": normalized_intent_id,
            "kind": str(kind or "").strip(),
            "target_key": str(target_key or "").strip(),
            "state": "pending",
            "created_at": float(created_at or 0.0),
            "generation": int(generation or 0),
        }
        return self.focus_intent_payload()

    def finish_focus_intent(
        self,
        *,
        intent_id: str,
        state: str,
        reason: str = "",
    ) -> Dict[str, Any]:
        """Transition the active focus intent to confirmed or failed."""
        normalized_intent_id = str(intent_id or "").strip()
        if not normalized_intent_id:
            return self.focus_intent_payload()
        current_intent_id = str(self.focus_intent.get("intent_id") or "").strip()
        if current_intent_id and current_intent_id != normalized_intent_id:
            return self.focus_intent_payload()
        if not current_intent_id:
            self.focus_intent = {
                "intent_id": normalized_intent_id,
                "kind": "",
                "target_key": "",
                "state": "pending",
                "created_at": 0.0,
                "generation": 0,
            }
        resolved_state = str(state or "").strip()
        if resolved_state not in {"confirmed", "failed"}:
            resolved_state = "failed"
        self.focus_intent["state"] = resolved_state
        self.focus_intent["reason"] = str(reason or "").strip()
        if str(self.pending_intent_id or "").strip() == normalized_intent_id:
            self.pending_intent_id = ""
        return self.focus_intent_payload()

    def focus_intent_payload(self) -> Dict[str, Any]:
        """Return the current focus intent without exposing mutable internals."""
        if not self.focus_intent:
            return {}
        return {
            "intent_id": str(self.focus_intent.get("intent_id") or "").strip(),
            "kind": str(self.focus_intent.get("kind") or "").strip(),
            "target_key": str(self.focus_intent.get("target_key") or "").strip(),
            "state": str(self.focus_intent.get("state") or "").strip(),
            "created_at": float(self.focus_intent.get("created_at") or 0.0),
            "generation": int(self.focus_intent.get("generation") or 0),
            "reason": str(self.focus_intent.get("reason") or "").strip(),
        }

    def clear_focus_overrides(self) -> None:
        """Clear session/window overrides and any pending focus intent."""
        self.session_override_key = ""
        self.window_override = {"window_id": 0, "connection_key": ""}
        self.pending_intent_id = ""

    def clear_session_override(self) -> None:
        """Clear only the session override while preserving explicit window focus."""
        self.session_override_key = ""

    def clear_if_session_matches(self, session_key: str) -> bool:
        """Clear all focus overrides when the current session override was closed."""
        target_key = str(session_key or "").strip()
        if target_key and str(self.session_override_key or "").strip() == target_key:
            self.clear_focus_overrides()
            return True
        return False

    def prune_invalid_overrides(
        self,
        *,
        live_session_keys: Iterable[str],
        live_window_ids: Iterable[int],
        stale_window_ids: Iterable[int],
    ) -> Dict[str, bool]:
        """Drop focus overrides that no longer resolve to live daemon state."""
        normalized_session_keys = {
            str(session_key or "").strip()
            for session_key in live_session_keys
            if str(session_key or "").strip()
        }
        normalized_live_window_ids = {
            int(window_id or 0)
            for window_id in live_window_ids
            if int(window_id or 0) > 0
        }
        normalized_stale_window_ids = {
            int(window_id or 0)
            for window_id in stale_window_ids
            if int(window_id or 0) > 0
        }

        cleared_session_override = False
        session_override_key = str(self.session_override_key or "").strip()
        if session_override_key and session_override_key not in normalized_session_keys:
            self.session_override_key = ""
            cleared_session_override = True

        cleared_window_override = False
        override_window_id = int(self.window_override.get("window_id") or 0)
        if override_window_id > 0 and (
            override_window_id not in normalized_live_window_ids
            or override_window_id in normalized_stale_window_ids
        ):
            self.set_window_override(window_id=0, connection_key="")
            cleared_window_override = True

        return {
            "cleared_session_override": cleared_session_override,
            "cleared_window_override": cleared_window_override,
        }

    def override_payload(self) -> Dict[str, Any]:
        """Return diagnostic focus override state without exposing mutable internals."""
        return {
            "session_key": str(self.session_override_key or "").strip(),
            "window_id": int(self.window_override.get("window_id") or 0),
            "connection_key": str(self.window_override.get("connection_key") or "").strip(),
        }

    def current_session_override_key(
        self,
        sessions: List[Dict[str, Any]],
        *,
        focused_window_id: int = 0,
    ) -> str:
        """Return the daemon-owned current-session override if it still resolves."""
        del focused_window_id
        override_key = str(self.session_override_key or "").strip()
        if not override_key:
            return ""
        match = next(
            (
                session for session in sessions
                if isinstance(session, dict)
                and str(session.get("session_key") or "").strip() == override_key
            ),
            None,
        )
        if isinstance(match, dict):
            return override_key
        self.session_override_key = ""
        return ""

    def window_matches_focus_override(
        self,
        *,
        window_id: int,
        connection_key: str,
    ) -> bool:
        """Return whether a window matches the last successful focus target."""
        override_window_id = int(self.window_override.get("window_id") or 0)
        if override_window_id <= 0 or override_window_id != int(window_id or 0):
            return False
        override_connection_key = self._normalize_connection_key(
            str(self.window_override.get("connection_key") or "").strip()
        )
        return override_connection_key == self._normalize_connection_key(str(connection_key or "").strip())

    def select_current_session_key(
        self,
        sessions: List[Dict[str, Any]],
        *,
        focused_window_id: int,
    ) -> str:
        """Return the single session key that owns current focus."""
        override_key = self.current_session_override_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        if override_key:
            override_session = next(
                (
                    session for session in sessions
                    if isinstance(session, dict)
                    and str(session.get("session_key") or "").strip() == override_key
                ),
                None,
            )
            if (
                isinstance(override_session, dict)
                and str(override_session.get("source") or "").strip() == "herdr"
                and bool(override_session.get("focused", False))
            ):
                return override_key

        local_herdr_focused = next(
            (
                str(session.get("session_key") or "").strip()
                for session in sessions
                if isinstance(session, dict)
                and str(session.get("source") or "").strip() == "herdr"
                and bool(session.get("focused", False))
                and bool(session.get("is_current_host", False))
                and str(session.get("session_key") or "").strip()
            ),
            "",
        )
        if local_herdr_focused:
            return local_herdr_focused

        remote_herdr_focused = next(
            (
                str(session.get("session_key") or "").strip()
                for session in sessions
                if isinstance(session, dict)
                and str(session.get("source") or "").strip() == "herdr"
                and bool(session.get("focused", False))
                and str(session.get("session_key") or "").strip()
            ),
            "",
        )
        if remote_herdr_focused:
            return remote_herdr_focused

        if focused_window_id > 0:
            window_sessions = [
                session for session in sessions
                if int(session.get("window_id") or 0) == focused_window_id
                and bool(session.get("is_current_host", False))
            ]
            if window_sessions:
                override_match = next(
                    (
                        str(session.get("session_key") or "").strip()
                        for session in window_sessions
                        if str(session.get("session_key") or "").strip() == override_key
                    ),
                    "",
                )
                if override_match:
                    return override_match

                if override_key:
                    self.session_override_key = ""
                    self.window_override = {"window_id": 0, "connection_key": ""}

                exact_match = next(
                    (
                        str(session.get("session_key") or "")
                        for session in window_sessions
                        if bool(session.get("window_active", False))
                        and bool(session.get("pane_active", False))
                    ),
                    "",
                )
                if exact_match:
                    return exact_match

                return str(window_sessions[0].get("session_key") or "")

            override_window_id = int(self.window_override.get("window_id") or 0)
            if override_key and override_window_id > 0 and override_window_id == focused_window_id:
                return override_key

            if override_key:
                self.session_override_key = ""
                self.window_override = {"window_id": 0, "connection_key": ""}
                return ""

        if override_key:
            return override_key

        return ""

    @staticmethod
    def mark_current_session(
        sessions: List[Dict[str, Any]],
        *,
        current_session_key: str,
    ) -> None:
        """Normalize is_current_window so exactly one rendered session is current."""
        current_key = str(current_session_key or "").strip()
        for session in sessions:
            if not isinstance(session, dict):
                continue
            session["is_current_window"] = bool(
                current_key
                and str(session.get("session_key") or "").strip() == current_key
            )

    @staticmethod
    def session_matches_current(
        session: Dict[str, Any],
        *,
        current_session_key: str,
        focused_window_id: int,
    ) -> bool:
        """Return whether a session currently owns the visible interaction surface."""
        session_key = str(session.get("session_key") or "").strip()
        if session_key and session_key == str(current_session_key or "").strip():
            return True
        return bool(
            int(session.get("window_id") or 0) == focused_window_id
            and focused_window_id > 0
            and bool(session.get("pane_active", False))
        )

    def build_focus_state_payload(
        self,
        runtime_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
        *,
        generation: int,
    ) -> Dict[str, Any]:
        """Build the daemon-owned focus view model consumed by dashboard clients."""
        focused_window_id = int(runtime_snapshot.get("focused_window_id") or 0)
        current_session_key = str(runtime_snapshot.get("current_session_key") or "").strip()
        active_session = next(
            (
                session for session in sessions
                if isinstance(session, dict)
                and str(session.get("session_key") or "").strip() == current_session_key
            ),
            {},
        )
        if not isinstance(active_session, dict):
            active_session = {}
        active_context = runtime_snapshot.get("active_context", {}) if isinstance(runtime_snapshot, dict) else {}
        current_workspace_name = ""
        fallback_workspace_name = ""
        for output in runtime_snapshot.get("outputs", []) or []:
            if not isinstance(output, dict):
                continue
            output_current = str(output.get("current_workspace") or "").strip()
            for workspace in output.get("workspaces", []) or []:
                if not isinstance(workspace, dict):
                    continue
                name = str(workspace.get("name") or "").strip()
                if bool(workspace.get("focused", False)):
                    current_workspace_name = name or output_current
                    break
                if not fallback_workspace_name and output_current and name == output_current:
                    fallback_workspace_name = name or output_current
            if current_workspace_name:
                break
        if not current_workspace_name:
            current_workspace_name = fallback_workspace_name
        return {
            "success": True,
            "schema_version": self.schema_version,
            "generation": int(generation or 0),
            "current_session_key": current_session_key,
            "current_window_id": focused_window_id,
            "current_workspace_name": current_workspace_name,
            "current_herdr_pane_id": str(active_session.get("pane_id") or "").strip(),
            "current_herdr_host": str(
                active_session.get("host_name")
                or active_session.get("herdr_host")
                or ""
            ).strip(),
            "pending_intent_id": str(self.pending_intent_id or "").strip(),
            "focus_intent": self.focus_intent_payload(),
            "active_context": active_context if isinstance(active_context, dict) else {},
            "active_session": {
                "session_key": str(active_session.get("session_key") or "").strip(),
                "herdr_session": str(active_session.get("herdr_session") or "").strip(),
                "workspace_id": str(active_session.get("workspace_id") or "").strip(),
                "tab_id": str(active_session.get("tab_id") or "").strip(),
                "pane_id": str(active_session.get("pane_id") or "").strip(),
                "terminal_id": str(active_session.get("terminal_id") or "").strip(),
                "agent": str(active_session.get("agent") or "").strip(),
                "agent_status": str(active_session.get("agent_status") or "").strip(),
                "focused": bool(active_session.get("focused", False)),
                "window_id": int(active_session.get("window_id") or 0),
                "project_name": str(active_session.get("project_name") or active_session.get("project") or "").strip(),
                "execution_mode": str(active_session.get("execution_mode") or "").strip(),
                "connection_key": str(active_session.get("connection_key") or "").strip(),
                "focus_connection_key": str(active_session.get("focus_connection_key") or "").strip(),
                "host_name": str(active_session.get("host_name") or "").strip(),
            },
        }
