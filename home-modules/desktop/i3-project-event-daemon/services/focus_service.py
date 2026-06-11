"""Daemon-owned focus view-model state and selection rules."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Awaitable, Callable, Dict, Iterable, List, Optional, Set, Tuple


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
        send_tick_barrier: Optional[Callable[[str], Awaitable[None]]] = None,
        notify_state_change: Optional[Callable[[str], Awaitable[None]]] = None,
        window_is_locally_tracked: Optional[Callable[[int], Awaitable[bool]]] = None,
        connection_target_is_current_host: Optional[Callable[[str], bool]] = None,
        remote_daemon_request: Optional[Callable[..., Awaitable[Dict[str, Any]]]] = None,
        switch_runtime_context: Optional[Callable[[str, str, str], Awaitable[Dict[str, Any]]]] = None,
        get_window_transition_state: Optional[Callable[[int], Awaitable[Dict[str, Any]]]] = None,
        build_window_focus_transition: Optional[Callable[..., Dict[str, Any]]] = None,
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
        self._send_tick_barrier = send_tick_barrier
        self._notify_state_change = notify_state_change
        self._window_is_locally_tracked = window_is_locally_tracked
        self._connection_target_is_current_host = connection_target_is_current_host
        self._remote_daemon_request = remote_daemon_request
        self._switch_runtime_context = switch_runtime_context
        self._get_window_transition_state = get_window_transition_state
        self._build_window_focus_transition = build_window_focus_transition
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
            self._window_is_locally_tracked
            and self._connection_target_is_current_host
            and self._remote_daemon_request
            and self._switch_runtime_context
            and self._get_window_transition_state
            and self._build_window_focus_transition
            and self._window_matches_transition_target
            and self._verify_window_focus
            and self._focus_state_provider
        ):
            raise RuntimeError("Window focus dependencies are unavailable")

        target_variant_normalized = str(target_variant or "").strip().lower()
        normalized_connection_key = str(connection_key or "").strip()
        normalized_project_name = str(project_name or "").strip()
        local_window_target = await self._window_is_locally_tracked(int(window_id))
        connection_targets_current_host = self._connection_target_is_current_host(normalized_connection_key)
        should_remote_handoff = (
            target_variant_normalized == "ssh"
            and not connection_targets_current_host
            and not local_window_target
        )
        if should_remote_handoff:
            remote_handoff = await self._remote_daemon_request(
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
                transition_state = await self._get_window_transition_state(int(window_id))
                if not bool(transition_state.get("exists", False)):
                    last_error = "window_not_found"
                    await asyncio.sleep(delay_s)
                    continue
                transition = self._build_window_focus_transition(
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
                verification = await self._verify_window_focus(int(window_id))
                if bool(verification.get("success", False)) and await self._window_matches_transition_target(
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
            self._window_is_locally_tracked
            and self._connection_target_is_current_host
            and self._get_window_transition_state
            and self._build_window_focus_transition
        ):
            raise RuntimeError("Window focus dependencies are unavailable")

        window_id = int(params.get("window_id") or 0)
        if window_id <= 0:
            raise ValueError("window_id must be a positive integer")

        target_variant = str(params.get("target_variant") or "").strip().lower()
        connection_key = str(params.get("connection_key") or "").strip()
        if target_variant == "ssh":
            local_window_target = await self._window_is_locally_tracked(window_id)
            connection_targets_current_host = self._connection_target_is_current_host(connection_key)
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

        transition_state = await self._get_window_transition_state(window_id)
        if not bool(transition_state.get("exists", False)):
            return {
                "success": False,
                "window_id": int(window_id),
                "reason": "window_not_found",
                "fallback_method": "window.focus",
            }

        transition = self._build_window_focus_transition(
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
