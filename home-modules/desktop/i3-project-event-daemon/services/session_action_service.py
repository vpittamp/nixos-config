"""Session action helpers for tmux-backed AI sessions."""

from __future__ import annotations

import shlex
import subprocess
from typing import Any, Awaitable, Callable, Dict, List, Tuple


class SessionActionService:
    """Run low-level tmux actions for daemon-owned session commands."""

    def __init__(
        self,
        *,
        parse_remote_target: Callable[[str, str], Tuple[str, str, int]],
        connection_target_is_current_host: Callable[[str], bool],
        run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        self._parse_remote_target = parse_remote_target
        self._connection_target_is_current_host = connection_target_is_current_host
        self._run_command = run_command

    @staticmethod
    def tmux_command_prefix(tmux_socket: str = "") -> str:
        socket_path = str(tmux_socket or "").strip()
        if socket_path:
            return f"tmux -S {shlex.quote(socket_path)}"
        return "tmux"

    def select_tmux_target(
        self,
        *,
        execution_mode: str,
        tmux_session: str,
        tmux_window: str,
        tmux_pane: str = "",
        remote_target: str = "",
        connection_key: str = "",
        tmux_socket: str = "",
    ) -> Dict[str, Any]:
        """Select a tmux window/pane locally or over SSH."""
        if not tmux_session or not tmux_window:
            return {
                "success": False,
                "reason": "missing_tmux_target",
            }

        tmux_cmd = self.tmux_command_prefix(tmux_socket)
        tmux_window_index = str(tmux_window or "").split(":", 1)[0].strip() or str(tmux_window or "").strip()
        select_script = (
            f"{tmux_cmd} select-window -t {shlex.quote(f'{tmux_session}:{tmux_window_index}')} >/dev/null 2>&1"
        )
        if tmux_pane:
            select_script += f" && {tmux_cmd} select-pane -t {shlex.quote(tmux_pane)} >/dev/null 2>&1"

        if execution_mode == "ssh" and not self._connection_target_is_current_host(connection_key):
            remote_user, remote_host, remote_port = self._parse_remote_target(remote_target, connection_key)
            if not remote_host:
                return {
                    "success": False,
                    "reason": "missing_remote_target",
                }
            destination = f"{remote_user}@{remote_host}" if remote_user else remote_host
            result = self._run_command(
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=2",
                    "-p",
                    str(remote_port),
                    destination,
                    f"bash -lc {shlex.quote(select_script)}",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            return {
                "success": result.returncode == 0,
                "reason": "ok" if result.returncode == 0 else "remote_tmux_select_failed",
                "stderr": str(result.stderr or "").strip(),
            }

        result = self._run_command(
            ["bash", "-lc", select_script],
            capture_output=True,
            text=True,
            check=False,
        )
        return {
            "success": result.returncode == 0,
            "reason": "ok" if result.returncode == 0 else "local_tmux_select_failed",
            "stderr": str(result.stderr or "").strip(),
        }

    def verify_tmux_target(
        self,
        *,
        execution_mode: str,
        tmux_session: str,
        tmux_window: str,
        tmux_pane: str,
        remote_target: str = "",
        connection_key: str = "",
        tmux_socket: str = "",
    ) -> Dict[str, Any]:
        """Verify the active tmux pane for a target session/window."""
        if not tmux_session or not tmux_window or not tmux_pane:
            return {
                "success": False,
                "reason": "missing_tmux_target",
            }

        tmux_cmd = self.tmux_command_prefix(tmux_socket)
        tmux_window_index = str(tmux_window or "").split(":", 1)[0].strip() or str(tmux_window or "").strip()
        verify_script = (
            f"{tmux_cmd} list-panes -t {shlex.quote(f'{tmux_session}:{tmux_window_index}')} "
            "-F '#{pane_active} #{pane_id}' | "
            "awk '$1 == 1 { print $2; exit }'"
        )

        if execution_mode == "ssh" and not self._connection_target_is_current_host(connection_key):
            remote_user, remote_host, remote_port = self._parse_remote_target(remote_target, connection_key)
            if not remote_host:
                return {
                    "success": False,
                    "reason": "missing_remote_target",
                }
            destination = f"{remote_user}@{remote_host}" if remote_user else remote_host
            result = self._run_command(
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=2",
                    "-p",
                    str(remote_port),
                    destination,
                    f"bash -lc {shlex.quote(verify_script)}",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        else:
            result = self._run_command(
                ["bash", "-lc", verify_script],
                capture_output=True,
                text=True,
                check=False,
            )

        active_pane = str(result.stdout or "").strip()
        success = result.returncode == 0 and active_pane == str(tmux_pane or "").strip()
        return {
            "success": success,
            "reason": "ok" if success else "tmux_target_mismatch",
            "tmux_session": tmux_session,
            "tmux_window": tmux_window,
            "tmux_pane": str(tmux_pane or "").strip(),
            "active_tmux_pane": active_pane,
            "stderr": str(result.stderr or "").strip(),
        }

    def kill_tmux_pane(
        self,
        *,
        execution_mode: str,
        tmux_pane: str,
        remote_target: str = "",
        connection_key: str = "",
        tmux_socket: str = "",
    ) -> Dict[str, Any]:
        """Kill a tmux pane locally or over SSH."""
        pane_id = str(tmux_pane or "").strip()
        if not pane_id:
            return {
                "success": False,
                "reason": "missing_tmux_pane",
                "stderr": "",
            }

        tmux_cmd = self.tmux_command_prefix(tmux_socket)
        kill_script = f"{tmux_cmd} kill-pane -t {shlex.quote(pane_id)} >/dev/null 2>&1"

        if execution_mode == "ssh" and not self._connection_target_is_current_host(connection_key):
            remote_user, remote_host, remote_port = self._parse_remote_target(remote_target, connection_key)
            if not remote_host:
                return {
                    "success": False,
                    "reason": "missing_remote_target",
                    "stderr": "",
                }
            destination = f"{remote_user}@{remote_host}" if remote_user else remote_host
            result = self._run_command(
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=2",
                    "-p",
                    str(remote_port),
                    destination,
                    f"bash -lc {shlex.quote(kill_script)}",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            return {
                "success": result.returncode == 0,
                "reason": "ok" if result.returncode == 0 else "remote_tmux_kill_failed",
                "stderr": str(result.stderr or "").strip(),
            }

        result = self._run_command(
            ["bash", "-lc", kill_script],
            capture_output=True,
            text=True,
            check=False,
        )
        return {
            "success": result.returncode == 0,
            "reason": "ok" if result.returncode == 0 else "local_tmux_kill_failed",
            "stderr": str(result.stderr or "").strip(),
        }

    async def focus_session(
        self,
        *,
        session_key: str,
        sessions: List[Dict[str, Any]],
        intent_epoch: int,
        record_session_seen: Callable[[str], Any],
        acknowledge_stopped_session: Callable[[Dict[str, Any]], Any],
        acknowledge_user_input_session: Callable[[Dict[str, Any]], Any],
        focus_remote_session_attach: Callable[..., Awaitable[Dict[str, Any]]],
        focus_local_session_attach: Callable[..., Awaitable[Dict[str, Any]]],
        window_focus: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        wait_for_session_focus: Callable[..., Awaitable[Dict[str, Any]]],
        focus_state: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
        set_focus_overrides: Callable[..., Any],
    ) -> Dict[str, Any]:
        """Focus an AI session by daemon-owned session key."""
        normalized_key = str(session_key or "").strip()
        if not normalized_key:
            raise ValueError("session_key is required")

        session = next(
            (
                item for item in sessions
                if isinstance(item, dict)
                and str(item.get("session_key") or "").strip() == normalized_key
            ),
            None,
        )
        if not isinstance(session, dict):
            raise RuntimeError(f"Unknown session_key: {normalized_key}")

        record_session_seen(normalized_key)
        acknowledge_stopped_session(session)
        acknowledge_user_input_session(session)

        window_id = int(session.get("window_id") or 0)
        focus_mode = str(session.get("focus_mode") or "").strip() or "unavailable"
        if window_id <= 0 and focus_mode not in {"remote_bridge_bound", "remote_bridge_attachable", "local_tmux_attachable"}:
            raise RuntimeError(f"Session {normalized_key} is not focusable")

        if focus_mode in {"remote_bridge_bound", "remote_bridge_attachable"}:
            return await focus_remote_session_attach(
                session_key=normalized_key,
                session=session,
                intent_epoch=int(intent_epoch or 0),
            )
        if focus_mode == "local_tmux_attachable":
            return await focus_local_session_attach(
                session_key=normalized_key,
                session=session,
                intent_epoch=int(intent_epoch or 0),
            )

        focus_result = await window_focus({
            "window_id": window_id,
            "project_name": str(session.get("focus_project") or session.get("project_name") or "").strip(),
            "target_variant": str(session.get("focus_execution_mode") or session.get("execution_mode") or "").strip(),
            "connection_key": str(session.get("focus_connection_key") or session.get("connection_key") or "").strip(),
        })
        terminal_context = session.get("terminal_context") or {}
        if not isinstance(terminal_context, dict):
            terminal_context = {}
        tmux_result: Dict[str, Any] = {
            "success": False,
            "reason": "not_applicable",
        }
        tmux_session = str(session.get("tmux_session") or terminal_context.get("tmux_session") or "").strip()
        tmux_window = str(session.get("tmux_window") or terminal_context.get("tmux_window") or "").strip()
        tmux_pane = str(session.get("tmux_pane") or terminal_context.get("tmux_pane") or "").strip()
        tmux_socket = str(terminal_context.get("tmux_socket") or "").strip()
        if tmux_session and tmux_window:
            tmux_result = self.select_tmux_target(
                execution_mode=str(session.get("execution_mode") or terminal_context.get("execution_mode") or "local").strip() or "local",
                tmux_session=tmux_session,
                tmux_window=tmux_window,
                tmux_pane=tmux_pane,
                remote_target=str(terminal_context.get("remote_target") or "").strip(),
                connection_key=str(session.get("connection_key") or terminal_context.get("connection_key") or "").strip(),
                tmux_socket=tmux_socket,
            )
        overall_success = bool(focus_result.get("success", False)) and (
            not (tmux_session and tmux_window) or bool(tmux_result.get("success", False))
        )
        uses_window_only_identity = not bool(tmux_session and tmux_window and tmux_pane)
        verification: Dict[str, Any] = {
            "success": False,
            "reason": "focus_failed",
            "session_key": normalized_key,
            "current_session_key": "",
        }
        if overall_success:
            if tmux_session and tmux_window and tmux_pane and bool(tmux_result.get("success", False)):
                tmux_verification = self.verify_tmux_target(
                    execution_mode=str(session.get("execution_mode") or terminal_context.get("execution_mode") or "local").strip() or "local",
                    tmux_session=tmux_session,
                    tmux_window=tmux_window,
                    tmux_pane=tmux_pane,
                    remote_target=str(terminal_context.get("remote_target") or "").strip(),
                    connection_key=str(session.get("connection_key") or terminal_context.get("connection_key") or "").strip(),
                    tmux_socket=tmux_socket,
                )
                verification = {
                    "success": bool(tmux_verification.get("success", False)),
                    "reason": str(tmux_verification.get("reason") or "tmux_target_mismatch"),
                    "session_key": normalized_key,
                    "current_session_key": normalized_key if bool(tmux_verification.get("success", False)) else "",
                    "verification_source": "tmux",
                    "active_tmux_pane": str(tmux_verification.get("active_tmux_pane") or "").strip(),
                    "tmux_pane": str(tmux_verification.get("tmux_pane") or "").strip(),
                }
            else:
                if uses_window_only_identity:
                    set_focus_overrides(
                        session_key=normalized_key,
                        window_id=int(window_id),
                        connection_key=str(
                            session.get("focus_connection_key")
                            or session.get("connection_key")
                            or ""
                        ).strip(),
                    )
                verification = await wait_for_session_focus(normalized_key)
            overall_success = overall_success and bool(verification.get("success", False))
        focus_state_after = await focus_state({})
        if overall_success:
            set_focus_overrides(
                session_key=normalized_key,
                window_id=int(window_id),
                connection_key=str(session.get("focus_connection_key") or session.get("connection_key") or "").strip(),
            )
        return {
            "success": overall_success,
            "session_key": normalized_key,
            "window_id": window_id,
            "surface_key": str(session.get("surface_key") or "").strip(),
            "conflict_state": str(session.get("conflict_state") or "").strip(),
            "focus_mode": "local_window",
            "focus_target_host": "",
            "focus": focus_result,
            "current_ai_session_key_after": str(focus_state_after.get("current_ai_session_key") or "").strip(),
            "focused_window_id_after": int(focus_state_after.get("focused_window_id") or 0),
            "focus_state_after": focus_state_after,
            "tmux": tmux_result,
            "verification": verification,
        }

    async def close_session(
        self,
        *,
        session_key: str,
        sessions: List[Dict[str, Any]],
        close_managed_window: Callable[[int], Awaitable[bool]],
        clear_focus_if_session_matches: Callable[[str], bool],
        notify_state_change: Callable[[str], Awaitable[Any]],
    ) -> Dict[str, Any]:
        """Close a daemon-owned AI session through tmux or a managed-window fallback."""
        normalized_key = str(session_key or "").strip()
        if not normalized_key:
            raise ValueError("session_key is required")

        session = next(
            (
                item for item in sessions
                if isinstance(item, dict)
                and str(item.get("session_key") or "").strip() == normalized_key
            ),
            None,
        )
        if not isinstance(session, dict):
            return {
                "success": False,
                "session_key": normalized_key,
                "reason": "session_not_found",
                "close_mode": "",
                "closed_window_id": 0,
                "killed_tmux_pane": "",
            }

        terminal_context = session.get("terminal_context") or {}
        if not isinstance(terminal_context, dict):
            terminal_context = {}

        tmux_session = str(session.get("tmux_session") or terminal_context.get("tmux_session") or "").strip()
        tmux_window = str(session.get("tmux_window") or terminal_context.get("tmux_window") or "").strip()
        tmux_pane = str(session.get("tmux_pane") or terminal_context.get("tmux_pane") or "").strip()
        tmux_socket = str(terminal_context.get("tmux_socket") or "").strip()
        connection_hint = str(
            (
                session.get("source_connection_key")
                if not bool(session.get("source_is_current_host", False))
                else ""
            )
            or session.get("focus_connection_key")
            or session.get("connection_key")
            or terminal_context.get("remote_target")
            or terminal_context.get("connection_key")
            or ""
        ).strip()
        remote_target = str(terminal_context.get("remote_target") or connection_hint).strip()
        target_is_current_host = self._connection_target_is_current_host(connection_hint)

        if tmux_session and tmux_window and tmux_pane:
            tmux_result = self.kill_tmux_pane(
                execution_mode="local" if target_is_current_host else "ssh",
                tmux_pane=tmux_pane,
                remote_target=remote_target,
                connection_key=connection_hint,
                tmux_socket=tmux_socket,
            )
            success = bool(tmux_result.get("success", False))
            if success:
                clear_focus_if_session_matches(normalized_key)
                await notify_state_change("ai_session_close")
            return {
                "success": success,
                "session_key": normalized_key,
                "reason": str(tmux_result.get("reason") or ("ok" if success else "tmux_close_failed")),
                "close_mode": "local_tmux_pane" if target_is_current_host else "remote_tmux_pane",
                "closed_window_id": 0,
                "killed_tmux_pane": tmux_pane,
                "tmux_session": tmux_session,
                "tmux_window": tmux_window,
                "connection_key": connection_hint,
                "stderr": str(tmux_result.get("stderr") or "").strip(),
            }

        window_id = int(session.get("bridge_window_id") or session.get("window_id") or 0)
        if window_id <= 0:
            return {
                "success": False,
                "session_key": normalized_key,
                "reason": "missing_close_target",
                "close_mode": "",
                "closed_window_id": 0,
                "killed_tmux_pane": "",
            }

        closed = await close_managed_window(window_id)
        if closed:
            clear_focus_if_session_matches(normalized_key)
            await notify_state_change("ai_session_close")
        return {
            "success": bool(closed),
            "session_key": normalized_key,
            "reason": "ok" if closed else "window_close_failed",
            "close_mode": "local_window_fallback",
            "closed_window_id": window_id,
            "killed_tmux_pane": "",
            "connection_key": connection_hint,
        }
