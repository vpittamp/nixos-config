"""Dashboard payload model helpers and invariants."""

from __future__ import annotations

from typing import Any, Dict, List


DASHBOARD_SCHEMA_VERSION = "i3pm.dashboard.v2"
DASHBOARD_EVENT_SCHEMA_VERSION = "i3pm.dashboard.event.v1"


def dashboard_event_type_for_state_change(event_type: str) -> str:
    """Map daemon invalidations to the typed dashboard event contract."""
    normalized = str(event_type or "dashboard_invalidated").strip() or "dashboard_invalidated"
    compact = normalized.replace("::", "_").replace(".", "_").replace("-", "_")
    if compact.startswith("focus"):
        return "focus.changed"
    if compact.startswith("window"):
        return "window.changed"
    if compact.startswith("workspace"):
        return "workspace.changed"
    if compact.startswith("display") or compact.startswith("output") or compact.startswith("profile"):
        return "display.changed"
    if "herdr" in compact:
        return "herdr.changed"
    if compact.startswith("ai_session") or compact.startswith("agent_session") or compact.startswith("session"):
        return "session.changed"
    if compact.startswith("project") or compact.startswith("worktree"):
        return "session.changed"
    return "dashboard.invalidated"


def dashboard_changed_keys_for_event(event_type: str) -> List[str]:
    """Return coarse dashboard model keys affected by a typed dashboard event."""
    typed_event = dashboard_event_type_for_state_change(event_type)
    if typed_event == "focus.changed":
        return ["focus_state", "outputs", "projects"]
    if typed_event == "window.changed":
        return ["focus_state", "projects", "tracked_windows"]
    if typed_event == "workspace.changed":
        return ["focus_state", "outputs", "projects"]
    if typed_event == "session.changed":
        return [
            "focus_state",
            "active_ai_sessions",
            "active_ai_sessions_mru",
            "current_ai_session_key",
            "worktrees",
            "ai_monitor_metrics",
        ]
    if typed_event == "herdr.changed":
        return [
            "focus_state",
            "active_ai_sessions",
            "active_ai_sessions_mru",
            "current_ai_session_key",
            "herdr",
            "ai_monitor_metrics",
        ]
    if typed_event == "display.changed":
        return ["outputs", "active_outputs", "display_layout"]
    return ["dashboard"]


def dashboard_event_payload_from_snapshot(
    snapshot: Dict[str, Any],
    changed_keys: List[str],
    *,
    schema_version: str = DASHBOARD_SCHEMA_VERSION,
) -> Dict[str, Any]:
    """Build a partial dashboard payload for a typed state-change event."""
    payload: Dict[str, Any] = {
        "status": snapshot.get("status", "ok"),
        "schema_version": snapshot.get("schema_version", schema_version),
        "timestamp": snapshot.get("timestamp"),
        "snapshot_version": snapshot.get("snapshot_version"),
        "session_generation": snapshot.get("session_generation"),
        "display_generation": snapshot.get("display_generation"),
        "focus_generation": snapshot.get("focus_generation"),
        "total_windows": snapshot.get("total_windows"),
        "window_count": snapshot.get("window_count"),
        "project_count": snapshot.get("project_count"),
        "worktree_count": snapshot.get("worktree_count"),
        "state_health": snapshot.get("state_health", {}),
        "dashboard_invariants": snapshot.get("dashboard_invariants", {}),
    }
    for key in changed_keys:
        if key in snapshot:
            payload[key] = snapshot[key]
    return payload


def validate_dashboard_payload(
    payload: Dict[str, Any],
    *,
    schema_version: str = DASHBOARD_SCHEMA_VERSION,
) -> Dict[str, Any]:
    """Validate dashboard focus invariants before the payload leaves the daemon."""
    issues: List[str] = []
    warnings: List[str] = []
    if str(payload.get("schema_version") or "").strip() != schema_version:
        issues.append("schema_version_mismatch")

    focus_state = payload.get("focus_state")
    if not isinstance(focus_state, dict):
        focus_state = {}
        issues.append("missing_focus_state")

    current_key = str(
        focus_state.get("current_session_key")
        or focus_state.get("current_ai_session_key")
        or payload.get("current_ai_session_key")
        or ""
    ).strip()
    sessions = [
        session for session in payload.get("active_ai_sessions", []) or []
        if isinstance(session, dict)
    ]
    current_rows = [
        session for session in sessions
        if bool(session.get("is_current_window", False))
    ]
    matching_rows = [
        session for session in sessions
        if current_key and str(session.get("session_key") or "").strip() == current_key
    ]
    if current_key:
        if len(matching_rows) != 1:
            issues.append("current_session_key_not_unique")
        if len(current_rows) != 1:
            issues.append("current_session_row_not_unique")
        elif str(current_rows[0].get("session_key") or "").strip() != current_key:
            issues.append("current_session_row_mismatch")
    elif current_rows:
        issues.append("current_session_row_without_key")

    window_rows: List[Dict[str, Any]] = []
    for project in payload.get("projects", []) or []:
        if not isinstance(project, dict):
            continue
        for window in project.get("windows", []) or []:
            if isinstance(window, dict):
                window_rows.append(window)
    focused_windows = [window for window in window_rows if bool(window.get("focused", False))]
    if len(focused_windows) > 1:
        warnings.append("duplicate_focused_windows")
    focus_window_id = int(focus_state.get("current_window_id") or focus_state.get("focused_window_id") or 0)
    current_window_rows = [
        window for window in window_rows
        if focus_window_id > 0
        and (
            bool(window.get("is_current_window", False))
            or int(window.get("id") or window.get("window_id") or 0) == focus_window_id
        )
    ]
    current_window_ids = {
        int(window.get("id") or window.get("window_id") or 0)
        for window in current_window_rows
    }
    if focus_window_id > 0 and current_window_rows and current_window_ids != {focus_window_id}:
        issues.append("current_window_row_mismatch")
    if focused_windows and focus_window_id > 0:
        focused_row_id = int(focused_windows[0].get("id") or focused_windows[0].get("window_id") or 0)
        if focused_row_id != focus_window_id:
            warnings.append("focused_window_row_mismatch")

    focused_workspaces = []
    for output in payload.get("outputs", []) or []:
        if not isinstance(output, dict):
            continue
        for workspace in output.get("workspaces", []) or []:
            if isinstance(workspace, dict) and bool(workspace.get("focused", False)):
                focused_workspaces.append(workspace)
    if len(focused_workspaces) > 1:
        issues.append("duplicate_focused_workspaces")

    remote_focused = [
        session for session in sessions
        if str(session.get("source") or "").strip() == "herdr"
        and bool(session.get("focused", False))
        and not bool(session.get("is_current_host", False))
        and str(session.get("session_key") or "").strip()
    ]
    if remote_focused and current_key:
        remote_keys = {str(session.get("session_key") or "").strip() for session in remote_focused}
        if current_key not in remote_keys:
            issues.append("remote_herdr_focus_mismatch")

    return {
        "ok": not issues,
        "issues": issues,
        "warnings": warnings,
        "schema_version": schema_version,
    }
