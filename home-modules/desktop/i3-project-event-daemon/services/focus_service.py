"""Daemon-owned focus view-model state and selection rules."""

from __future__ import annotations

from typing import Any, Callable, Dict, List


FOCUS_STATE_SCHEMA_VERSION = "i3pm.focus_state.v1"


class FocusService:
    """Own focus overrides and dashboard focus view-model construction."""

    def __init__(
        self,
        *,
        normalize_connection_key: Callable[[str], str],
        schema_version: str = FOCUS_STATE_SCHEMA_VERSION,
    ) -> None:
        self._normalize_connection_key = normalize_connection_key
        self.schema_version = schema_version
        self.session_override_key: str = ""
        self.window_override: Dict[str, Any] = {"window_id": 0, "connection_key": ""}
        self.pending_intent_id: str = ""

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
        self.pending_intent_id = str(intent_id or "").strip()

    def clear_focus_overrides(self) -> None:
        """Clear session/window overrides and any pending focus intent."""
        self.session_override_key = ""
        self.window_override = {"window_id": 0, "connection_key": ""}
        self.pending_intent_id = ""

    def clear_session_override(self) -> None:
        """Clear only the session override while preserving explicit window focus."""
        self.session_override_key = ""

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
        current_session_key = str(runtime_snapshot.get("current_ai_session_key") or "").strip()
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
        for output in runtime_snapshot.get("outputs", []) or []:
            if not isinstance(output, dict):
                continue
            output_current = str(output.get("current_workspace") or "").strip()
            for workspace in output.get("workspaces", []) or []:
                if not isinstance(workspace, dict):
                    continue
                name = str(workspace.get("name") or "").strip()
                if bool(workspace.get("focused", False)) or (output_current and name == output_current):
                    current_workspace_name = name or output_current
                    break
            if current_workspace_name:
                break
        return {
            "success": True,
            "schema_version": self.schema_version,
            "generation": int(generation or 0),
            "current_session_key": current_session_key,
            "current_ai_session_key": current_session_key,
            "current_window_id": focused_window_id,
            "focused_window_id": focused_window_id,
            "current_workspace_name": current_workspace_name,
            "current_herdr_pane_id": str(
                active_session.get("pane_id")
                or active_session.get("tmux_pane")
                or ""
            ).strip(),
            "current_herdr_host": str(
                active_session.get("host_name")
                or active_session.get("herdr_host")
                or ""
            ).strip(),
            "pending_intent_id": str(self.pending_intent_id or "").strip(),
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
                "tmux_session": str(active_session.get("tmux_session") or "").strip(),
                "tmux_window": str(active_session.get("tmux_window") or "").strip(),
                "tmux_pane": str(active_session.get("tmux_pane") or "").strip(),
            },
        }
