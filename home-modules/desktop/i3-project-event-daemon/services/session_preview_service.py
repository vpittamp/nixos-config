"""Session preview view-model shaping."""

from __future__ import annotations

from typing import Any, Dict, Iterable


class SessionPreviewService:
    """Build focus-only session preview payloads from daemon session rows."""

    def build_preview(
        self,
        *,
        params: Dict[str, Any],
        sessions: Iterable[Dict[str, Any]],
    ) -> Dict[str, Any]:
        session_key = str(params.get("session_key") or "").strip()
        if not session_key:
            raise ValueError("session_key is required")

        try:
            lines = int(params.get("lines", 100) or 100)
        except (TypeError, ValueError):
            lines = 100
        lines = max(20, min(lines, 200))

        session = next(
            (
                item for item in sessions
                if isinstance(item, dict)
                and str(item.get("session_key") or "").strip() == session_key
            ),
            None,
        )
        if not isinstance(session, dict):
            raise RuntimeError(f"Unknown session_key: {session_key}")

        terminal_context = session.get("terminal_context") or {}
        if not isinstance(terminal_context, dict):
            terminal_context = {}

        execution_mode = str(session.get("execution_mode") or terminal_context.get("execution_mode") or "local").strip() or "local"
        tmux_session = str(session.get("tmux_session") or terminal_context.get("tmux_session") or "").strip()
        tmux_window = str(session.get("tmux_window") or terminal_context.get("tmux_window") or "").strip()
        tmux_pane = str(session.get("tmux_pane") or terminal_context.get("tmux_pane") or "").strip()
        tmux_socket = str(terminal_context.get("tmux_socket") or "").strip()
        pane_label = str(session.get("pane_label") or session.get("pane_title") or tmux_pane or "").strip()
        focus_mode = str(session.get("focus_mode") or "").strip() or "unavailable"
        availability_state = str(session.get("availability_state") or "").strip()
        focusability_reason = str(session.get("focusability_reason") or "").strip()
        raw_source_is_current_host = session.get("source_is_current_host")
        if raw_source_is_current_host is None:
            raw_source_is_current_host = session.get("is_current_host", False)
        source_is_current_host = bool(raw_source_is_current_host)
        is_herdr_session = (
            str(session.get("source") or "").strip() == "herdr"
            or bool(str(session.get("pane_id") or "").strip())
        )
        has_tmux_identity = bool(tmux_session and tmux_pane)

        preview_mode = "unavailable"
        preview_reason = "missing_tmux_identity"
        message = ""
        is_live = False
        is_remote = not source_is_current_host

        if is_herdr_session:
            preview_mode = "focus_only"
            preview_reason = "herdr_focus_only"
            message = "Focus this Herdr pane to inspect live output."
            is_remote = bool(session.get("is_remote_herdr", False)) or not source_is_current_host
        elif availability_state == "stale_source":
            preview_mode = "unavailable"
            preview_reason = "stale_remote_source"
            message = "The remote session source is stale; refresh Herdr state before inspecting it."
            is_remote = not source_is_current_host
        elif has_tmux_identity:
            preview_mode = "focus_only"
            preview_reason = "herdr_focus_required"
            message = "Live tmux preview has been retired. Focus the corresponding Herdr pane for live inspection."
            is_remote = not source_is_current_host

        return {
            "success": True,
            "session_key": session_key,
            "preview_mode": preview_mode,
            "preview_reason": preview_reason,
            "message": message,
            "lines": lines,
            "is_live": is_live,
            "is_remote": is_remote,
            "tool": str(session.get("tool") or "unknown").strip() or "unknown",
            "project_name": str(session.get("project_name") or session.get("project") or "").strip(),
            "host_name": str(session.get("host_name") or "").strip(),
            "connection_key": str(session.get("connection_key") or "").strip(),
            "focus_connection_key": str(session.get("focus_connection_key") or "").strip(),
            "execution_mode": execution_mode,
            "focus_mode": focus_mode,
            "availability_state": availability_state,
            "focusability_reason": focusability_reason,
            "window_id": int(session.get("window_id") or 0),
            "bridge_window_id": int(session.get("bridge_window_id") or 0),
            "bridge_state": str(session.get("bridge_state") or "").strip(),
            "pane_label": pane_label,
            "pane_title": str(session.get("pane_title") or "").strip(),
            "tmux_socket": tmux_socket,
            "tmux_session": tmux_session,
            "tmux_window": tmux_window,
            "tmux_pane": tmux_pane,
            "remote_user": "",
            "remote_host": "",
            "remote_port": 22,
            "surface_key": str(session.get("surface_key") or "").strip(),
            "session_phase": str(session.get("session_phase") or "").strip(),
            "session_phase_label": str(session.get("session_phase_label") or "").strip(),
            "turn_owner": str(session.get("turn_owner") or "unknown").strip() or "unknown",
            "turn_owner_label": str(session.get("turn_owner_label") or "Unknown").strip() or "Unknown",
            "activity_substate": str(session.get("activity_substate") or session.get("stage") or "idle").strip() or "idle",
            "activity_substate_label": str(
                session.get("activity_substate_label")
                or session.get("stage_label")
                or session.get("stage")
                or "Idle"
            ).strip() or "Idle",
            "status_reason": str(session.get("status_reason") or "").strip(),
        }
