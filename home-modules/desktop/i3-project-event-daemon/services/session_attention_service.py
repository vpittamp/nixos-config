"""Session attention and acknowledgement state service."""

from __future__ import annotations

from typing import Any, Dict, List

from .focus_service import FocusService


class SessionAttentionService:
    """Own retained attention state for completed and user-input sessions."""

    def __init__(self) -> None:
        self.stopped_notifications: Dict[str, Dict[str, Any]] = {}
        self.user_input_notifications: Dict[str, Dict[str, Any]] = {}

    @staticmethod
    def stopped_boundary_key(session: Dict[str, Any]) -> str:
        """Return a stable token for the current explicit-stop boundary."""
        terminal_state_at = str(session.get("terminal_state_at") or "").strip()
        if terminal_state_at:
            return terminal_state_at
        updated_at = str(session.get("updated_at") or "").strip()
        if updated_at:
            return updated_at
        state_seq = int(session.get("state_seq") or 0)
        if state_seq > 0:
            return f"state-seq:{state_seq}"
        return str(session.get("session_phase") or "").strip()

    @staticmethod
    def session_has_explicit_stop(session: Dict[str, Any]) -> bool:
        """Return whether a session is on an explicit provider stop boundary."""
        return bool(session.get("llm_stopped", False)) or (
            str(session.get("terminal_state") or "").strip().lower() == "explicit_complete"
        )

    @staticmethod
    def session_has_user_input_boundary(session: Dict[str, Any]) -> bool:
        """Return whether a session is on a retained user-input-required boundary."""
        tool = str(session.get("tool") or "").strip().lower()
        if tool not in {"codex", "claude-code", "antigravity", "antigravity-cli", "gemini", "gemini-cli"}:
            return False
        if str(session.get("notification_boundary_type") or "").strip().lower() != "user_input_required":
            return False
        reason = str(
            session.get("notification_boundary_reason")
            or session.get("user_action_reason")
            or ""
        ).strip().lower()
        return reason in {"elicitation", "permission", "auth", "rate_limit", "max_tokens", "error"}

    @staticmethod
    def user_input_boundary_key(session: Dict[str, Any]) -> str:
        """Return a stable token for the current user-input-required boundary."""
        boundary_at = str(session.get("notification_boundary_at") or "").strip()
        if boundary_at:
            return boundary_at
        updated_at = str(session.get("updated_at") or "").strip()
        if updated_at:
            return updated_at
        state_seq = int(session.get("state_seq") or 0)
        if state_seq > 0:
            return f"state-seq:{state_seq}"
        return str(session.get("session_phase") or "").strip()

    def acknowledge_stopped_session_notification(
        self,
        session: Dict[str, Any],
    ) -> bool:
        """Persist acknowledgement for the current explicit-stop boundary."""
        session_key = str(session.get("session_key") or "").strip()
        if not session_key or not self.session_has_explicit_stop(session):
            return False

        boundary_key = self.stopped_boundary_key(session)
        notification_state = self.stopped_notifications.get(session_key)
        if (
            not isinstance(notification_state, dict)
            or str(notification_state.get("boundary_key") or "") != boundary_key
        ):
            notification_state = {
                "boundary_key": boundary_key,
                "started_current": bool(session.get("is_current_window", False)),
                "left_since_boundary": True,
                "acknowledged": True,
            }
        else:
            notification_state["acknowledged"] = True

        self.stopped_notifications[session_key] = notification_state
        session["stopped_notification_pending"] = False
        session["session_phase"] = "done"
        session["session_phase_label"] = "Done"
        return True

    def acknowledge_user_input_session_notification(
        self,
        session: Dict[str, Any],
    ) -> bool:
        """Persist acknowledgement for the current user-input-required boundary."""
        session_key = str(session.get("session_key") or "").strip()
        if not session_key or not self.session_has_user_input_boundary(session):
            return False

        boundary_key = self.user_input_boundary_key(session)
        notification_state = self.user_input_notifications.get(session_key)
        if (
            not isinstance(notification_state, dict)
            or str(notification_state.get("boundary_key") or "") != boundary_key
        ):
            notification_state = {
                "boundary_key": boundary_key,
                "acknowledged": True,
            }
        else:
            notification_state["acknowledged"] = True

        self.user_input_notifications[session_key] = notification_state
        session["user_input_notification_pending"] = False
        if bool(session.get("process_running", False)):
            session["session_phase"] = "idle"
            session["session_phase_label"] = "Idle"
        else:
            session["session_phase"] = "inactive"
            session["session_phase_label"] = "Inactive"
        return True

    def apply_session_attention_state(
        self,
        sessions: List[Dict[str, Any]],
        *,
        focused_window_id: int,
        current_session_key: str,
    ) -> None:
        """Promote completed background sessions into retained attention states."""
        current_key = str(current_session_key or "").strip()
        active_stopped_keys: set[str] = set()
        active_user_input_keys: set[str] = set()
        for session in sessions:
            if not isinstance(session, dict):
                continue
            session_key = str(session.get("session_key") or "").strip()
            is_current = FocusService.session_matches_current(
                session,
                current_session_key=current_key,
                focused_window_id=focused_window_id,
            )
            explicit_stopped = self.session_has_explicit_stop(session)
            if explicit_stopped and session_key:
                active_stopped_keys.add(session_key)
                boundary_key = self.stopped_boundary_key(session)
                notification_state = self.stopped_notifications.get(session_key)
                if (
                    not isinstance(notification_state, dict)
                    or str(notification_state.get("boundary_key") or "") != boundary_key
                ):
                    notification_state = {
                        "boundary_key": boundary_key,
                        "started_current": is_current,
                        "left_since_boundary": not is_current,
                        "acknowledged": False,
                    }
                else:
                    if not is_current:
                        notification_state["left_since_boundary"] = True
                    elif not bool(notification_state.get("acknowledged", False)) and (
                        not bool(notification_state.get("started_current", False))
                        or bool(notification_state.get("left_since_boundary", False))
                    ):
                        notification_state["acknowledged"] = True

                self.stopped_notifications[session_key] = notification_state
                stopped_notification_pending = not bool(notification_state.get("acknowledged", False))
                session["stopped_notification_pending"] = stopped_notification_pending
                if stopped_notification_pending:
                    session["session_phase"] = "stopped"
                    session["session_phase_label"] = "Stopped"
                else:
                    session["session_phase"] = "done"
                    session["session_phase_label"] = "Done"
                continue

            if self.session_has_user_input_boundary(session) and session_key:
                active_user_input_keys.add(session_key)
                boundary_key = self.user_input_boundary_key(session)
                notification_state = self.user_input_notifications.get(session_key)
                if (
                    not isinstance(notification_state, dict)
                    or str(notification_state.get("boundary_key") or "") != boundary_key
                ):
                    notification_state = {
                        "boundary_key": boundary_key,
                        "acknowledged": is_current,
                    }
                elif is_current:
                    notification_state["acknowledged"] = True

                self.user_input_notifications[session_key] = notification_state
                user_input_notification_pending = not bool(notification_state.get("acknowledged", False))
                session["user_input_notification_pending"] = user_input_notification_pending
                if user_input_notification_pending:
                    session["session_phase"] = "needs_attention"
                    session["session_phase_label"] = "Needs attention"
                elif bool(session.get("process_running", False)):
                    session["session_phase"] = "idle"
                    session["session_phase_label"] = "Idle"
                else:
                    session["session_phase"] = "inactive"
                    session["session_phase_label"] = "Inactive"
                continue

            session["user_input_notification_pending"] = False
            session["stopped_notification_pending"] = False
            phase = str(session.get("session_phase") or "").strip().lower()
            if phase != "done":
                continue
            if is_current:
                session["session_phase"] = "done"
                session["session_phase_label"] = "Done"
            else:
                session["session_phase"] = "needs_attention"
                session["session_phase_label"] = "Needs attention"

        for session_key in list(self.stopped_notifications.keys()):
            if session_key not in active_stopped_keys:
                self.stopped_notifications.pop(session_key, None)
        for session_key in list(self.user_input_notifications.keys()):
            if session_key not in active_user_input_keys:
                self.user_input_notifications.pop(session_key, None)
