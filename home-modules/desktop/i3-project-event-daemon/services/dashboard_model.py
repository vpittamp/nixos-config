"""Dashboard payload model helpers and invariants."""

from __future__ import annotations

import logging
import re

from typing import Any, Callable, Dict, Iterable, List, Tuple


logger = logging.getLogger(__name__)

DASHBOARD_SCHEMA_VERSION = "i3pm.dashboard.v2"
DASHBOARD_EVENT_SCHEMA_VERSION = "i3pm.dashboard.event.v1"


def dashboard_workspace_sort_key(value: Any) -> Tuple[int, str]:
    """Return the stable dashboard sort key for workspace labels."""
    workspace = str(value or "").strip()
    if workspace.lower().startswith("scratchpad"):
        return (1_000_000, workspace)
    match = re.match(r"^(\d+)", workspace)
    if match:
        return (int(match.group(1)), workspace)
    if not workspace:
        return (999_999, "")
    return (500_000, workspace)


def build_dashboard_projects(
    runtime_snapshot: Dict[str, Any],
    sessions: List[Dict[str, Any]],
    *,
    canonical_project_name: Callable[..., str],
    normalize_target_host: Callable[[Any], str],
    parse_context_key_target_host: Callable[[Any], str],
    target_host_from_context_payload: Callable[..., str],
    local_host_alias: Callable[[], str],
    execution_mode_for_target_host: Callable[[str], str],
    build_target_context_key: Callable[[str, str], str],
    transport_kind_for_target_host: Callable[[Any], str],
    window_matches_focus_override: Callable[..., bool],
    build_window_focus_target: Callable[..., Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Group tracked windows into dashboard project cards."""
    active_context = runtime_snapshot.get("active_context", {}) if isinstance(runtime_snapshot, dict) else {}
    active_project_name = str(
        active_context.get("qualified_name")
        or active_context.get("project_name")
        or ""
    ).strip()
    active_target_host = target_host_from_context_payload(
        active_context,
        project_name=active_project_name,
    )
    focused_window_id = int(runtime_snapshot.get("focused_window_id") or 0)
    grouped: Dict[str, Dict[str, Any]] = {}
    for window in list(runtime_snapshot.get("tracked_windows", []) or []):
        if not isinstance(window, dict):
            continue
        window_id = int(window.get("window_id") or window.get("id") or 0)
        if window_id <= 0:
            continue
        raw_project_name = str(window.get("project") or "global").strip() or "global"
        project_name = canonical_project_name(
            raw_project_name,
            project_path=window.get("project_path"),
        ) or "global"
        target_host = normalize_target_host(
            window.get("target_host")
            or parse_context_key_target_host(window.get("context_key"))
            or local_host_alias()
        )
        execution_mode = str(window.get("execution_mode") or execution_mode_for_target_host(target_host)).strip() or "local"
        group_key = project_name if project_name == "global" else build_target_context_key(project_name, target_host)
        hidden = bool(window.get("hidden", False))
        matches_focus_override = window_matches_focus_override(
            window_id=window_id,
            connection_key=str(window.get("connection_key") or "").strip(),
        )
        derived_focused = focused_window_id > 0 and window_id == focused_window_id
        derived_visible = bool(window.get("visible", False)) or derived_focused or matches_focus_override
        derived_hidden = bool(hidden and not derived_visible)

        entry = grouped.setdefault(group_key, {
            "project": project_name,
            "display_project": project_name,
            "target_host": target_host,
            "transport_kind": transport_kind_for_target_host(target_host),
            "focused": False,
            "windows": [],
            "visible_window_count": 0,
            "hidden_window_count": 0,
            "is_active": (
                project_name == active_project_name
                and target_host == active_target_host
            ),
        })
        entry["focused"] = bool(entry["focused"]) or derived_focused
        if derived_hidden:
            entry["hidden_window_count"] = int(entry["hidden_window_count"]) + 1
        else:
            entry["visible_window_count"] = int(entry["visible_window_count"]) + 1
        entry["windows"].append({
            "id": window_id,
            "title": str(window.get("title") or "(untitled)"),
            "app_key": str(window.get("app_key") or ""),
            "app_name": str(window.get("app_name") or window.get("class") or "window"),
            "icon_path": str(window.get("icon_path") or "").strip(),
            "project": project_name,
            "target_host": target_host,
            "transport_kind": transport_kind_for_target_host(target_host),
            "connection_key": str(window.get("connection_key") or "").strip(),
            "workspace": str(window.get("workspace") or "").strip(),
            "output": str(window.get("output") or "").strip(),
            "focused": derived_focused,
            "is_current_window": focused_window_id > 0 and window_id == focused_window_id,
            "visible": derived_visible,
            "hidden": derived_hidden,
            "floating": bool(window.get("floating", False)),
            "last_focus_at": float(window.get("last_focus_at") or 0.0),
            "scope": str(window.get("scope") or "").strip(),
            "focus_target": build_window_focus_target(
                window_id=window_id,
                project_name=project_name,
                target_variant=execution_mode,
                connection_key=str(window.get("connection_key") or "").strip(),
            ),
        })

    projects = list(grouped.values())
    for project in projects:
        project_windows = list(project.get("windows", []) or [])
        project_windows.sort(
            key=lambda item: (
                dashboard_workspace_sort_key(item.get("workspace")),
                str(item.get("app_name") or item.get("app_key") or "").casefold(),
                int(item.get("id") or 0),
                str(item.get("title") or "").casefold(),
            ),
        )
        project["windows"] = project_windows
        project["window_count"] = len(project.get("windows", []))
    projects.sort(
        key=lambda item: (
            str(item.get("project") or "global").strip().lower() == "global",
            str(item.get("project") or "").casefold(),
            str(item.get("target_host") or "").casefold(),
        ),
    )
    return projects


def dashboard_event_type_for_state_change(event_type: str) -> str:
    """Map daemon invalidations to the typed dashboard event contract."""
    normalized = str(event_type or "dashboard_invalidated").strip() or "dashboard_invalidated"
    compact = normalized.replace("::", "_").replace(".", "_").replace("-", "_")
    if compact == "workspace_focus":
        return "focus.changed"
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
        return ["focus_state"]
    if typed_event == "window.changed":
        keys = ["focus_state", "projects", "tracked_windows"]
        # Window add/remove/move changes per-workspace membership, window
        # counts, and icon sets — all carried in `outputs`. Refresh `outputs`
        # for those so the bottom-bar workspace pills stay live instead of
        # drifting until the next full snapshot (and eventually falling back
        # to the stale compositor workspace list). Pure focus/title changes
        # don't touch membership, so they stay lightweight (no 35KB `outputs`
        # blob shipped on every window focus).
        normalized = (
            str(event_type or "")
            .replace("::", "_")
            .replace(".", "_")
            .replace("-", "_")
            .lower()
        )
        if any(token in normalized for token in ("new", "close", "move")):
            keys.append("outputs")
        return keys
    if typed_event == "workspace.changed":
        return ["focus_state", "outputs", "projects"]
    if typed_event == "session.changed":
        # `worktrees` used to be appended here for worktree/project events. The
        # array (~100KB, over half the payload) was built from the `repos.json`
        # inventory and had no renderer; it is no longer part of the payload at
        # all, so there is nothing extra for those events to ship.
        return ["focus_state", "active_ai_sessions"]
    if typed_event == "herdr.changed":
        return [
            "focus_state",
            "active_ai_sessions",
            "herdr",
        ]
    if typed_event == "display.changed":
        return ["outputs", "active_outputs", "display_layout"]
    return ["dashboard"]


def dashboard_changed_keys_for_events(event_types: Iterable[str]) -> List[str]:
    """Union of changed keys across a coalesced batch of events (order-stable).

    Coalescing several pending invalidations into one notification must not drop
    any consumer's update. Collapsing a batch to a single representative event
    (e.g. a window::close + workspace::empty + focus switch all collapsing to
    "focus_changed") would ship only ["focus_state"] and leave `outputs` stale —
    the emptied workspace pill would linger until the next membership change.
    Returning the union keeps every affected key in the delta.
    """
    union: List[str] = []
    for event_type in event_types:
        for key in dashboard_changed_keys_for_event(event_type):
            if key not in union:
                union.append(key)
    return union or ["dashboard"]


def _batch_representative_event(event_types: List[str]) -> str:
    """Pick the raw event that best represents a coalesced batch.

    A full invalidation dominates; otherwise prefer the event whose typed delta
    carries the most keys, so the envelope's method/type reflect the heaviest
    change. (Correctness no longer depends on this choice — changed_keys and the
    generation bumps are unioned across the whole batch — it only shapes the
    human-facing event_type.)
    """
    for event_type in event_types:
        if dashboard_event_type_for_state_change(event_type) == "dashboard.invalidated":
            return event_type
    return max(
        event_types,
        key=lambda event_type: (len(dashboard_changed_keys_for_event(event_type)), event_type),
    )


def advance_dashboard_event_state(
    *,
    event_type: str,
    snapshot_version: int,
    session_generation: int,
    display_generation: int,
    focus_generation: int,
) -> Dict[str, Any]:
    """Advance dashboard generations for one typed state-change event."""
    return advance_dashboard_event_state_for_batch(
        event_types=[str(event_type or "dashboard_invalidated")],
        snapshot_version=snapshot_version,
        session_generation=session_generation,
        display_generation=display_generation,
        focus_generation=focus_generation,
    )


def advance_dashboard_event_state_for_batch(
    *,
    event_types: Iterable[str],
    snapshot_version: int,
    session_generation: int,
    display_generation: int,
    focus_generation: int,
) -> Dict[str, Any]:
    """Advance dashboard generations for a coalesced batch of events.

    changed_keys is the union of every pending event's keys, and each generation
    counter is bumped if ANY event in the batch would bump it — so coalescing is
    lossless. A single-event batch reduces exactly to the prior per-event
    behaviour.
    """
    types = [str(event_type or "dashboard_invalidated") for event_type in event_types]
    if not types:
        types = ["dashboard_invalidated"]
    typed_events = [dashboard_event_type_for_state_change(event_type) for event_type in types]
    changed_keys = dashboard_changed_keys_for_events(types)
    representative = _batch_representative_event(types)
    typed_representative = dashboard_event_type_for_state_change(representative)

    next_snapshot_version = int(snapshot_version or 0) + 1
    next_session_generation = int(session_generation or 0)
    next_display_generation = int(display_generation or 0)
    next_focus_generation = int(focus_generation or 0)
    if any(typed in {"session.changed", "herdr.changed"} for typed in typed_events):
        next_session_generation += 1
    if any(
        typed in {
            "focus.changed",
            "window.changed",
            "workspace.changed",
            "session.changed",
            "herdr.changed",
        }
        for typed in typed_events
    ):
        next_focus_generation += 1
    if any(typed == "display.changed" for typed in typed_events):
        next_display_generation += 1
    return {
        "type": representative,
        "event_type": typed_representative,
        "changed_keys": changed_keys,
        "snapshot_version": next_snapshot_version,
        "session_generation": next_session_generation,
        "display_generation": next_display_generation,
        "focus_generation": next_focus_generation,
        "invalidate_worktree_cache": any(
            event_type.startswith("project") or event_type.startswith("worktree")
            for event_type in types
        ),
    }


def dashboard_invalidated_payload(
    *,
    error: Exception,
    snapshot_version: int,
    session_generation: int,
    display_generation: int,
    focus_generation: int,
    schema_version: str = DASHBOARD_SCHEMA_VERSION,
) -> Dict[str, Any]:
    """Build the fallback payload when a typed delta cannot be constructed."""
    return {
        "status": "invalidated",
        "schema_version": schema_version,
        "generation": snapshot_version,
        "snapshot_version": snapshot_version,
        "session_generation": session_generation,
        "display_generation": display_generation,
        "focus_generation": focus_generation,
        "error": str(error),
    }


def dashboard_event_notification(
    *,
    state: Dict[str, Any],
    payload: Dict[str, Any],
    timestamp: float,
    event_schema_version: str = DASHBOARD_EVENT_SCHEMA_VERSION,
) -> Dict[str, Any]:
    """Build a JSON-RPC dashboard event notification envelope."""
    return {
        "jsonrpc": "2.0",
        "method": str(state.get("event_type") or "dashboard.invalidated"),
        "params": {
            "type": str(state.get("type") or "dashboard_invalidated"),
            "schema_version": event_schema_version,
            "event_type": str(state.get("event_type") or "dashboard.invalidated"),
            "generation": int(state.get("snapshot_version") or 0),
            "changed_keys": list(state.get("changed_keys", []) or []),
            "payload": payload,
            "timestamp": timestamp,
            "snapshot_version": int(state.get("snapshot_version") or 0),
            "session_generation": int(state.get("session_generation") or 0),
            "display_generation": int(state.get("display_generation") or 0),
            "focus_generation": int(state.get("focus_generation") or 0),
        },
    }


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
        "generation": snapshot.get("generation", snapshot.get("snapshot_version")),
        "snapshot_version": snapshot.get("snapshot_version"),
        "session_generation": snapshot.get("session_generation"),
        "display_generation": snapshot.get("display_generation"),
        "focus_generation": snapshot.get("focus_generation"),
        "total_windows": snapshot.get("total_windows"),
        "window_count": snapshot.get("window_count"),
        "project_count": snapshot.get("project_count"),
        "state_health": snapshot.get("state_health", {}),
        "dashboard_invariants": snapshot.get("dashboard_invariants", {}),
    }
    for key in changed_keys:
        if key in snapshot:
            payload[key] = snapshot[key]
    return payload


def _herdr_host_summaries(herdr_snapshot: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Project per-host health for dashboard consumers (panel group headers).

    Session rows already carry their host key, so the shell can compute
    membership and counts itself; what it cannot see is whether each remote
    proxy is reachable, because ``remote_snapshots``/``remote_errors`` were
    never part of the dashboard payload. Entries are keyed by the same
    normalized host key sessions expose as ``host_name``/``herdr_host``.
    Health is only ever reported from real data: a host with no snapshot
    entry simply does not appear here (the shell renders no dot rather than
    a false red).
    """
    hosts: List[Dict[str, Any]] = []
    sessions = [
        session for session in herdr_snapshot.get("sessions", []) or []
        if isinstance(session, dict)
    ]
    local_sessions = [s for s in sessions if bool(s.get("is_current_host", False))]
    local_host = ""
    for session in local_sessions:
        local_host = str(
            session.get("herdr_host") or session.get("host_name") or ""
        ).strip()
        if local_host:
            break
    hosts.append({
        "host": local_host,
        "is_current_host": True,
        "healthy": True,
        "agents": len(local_sessions),
        "error": "",
    })
    for remote in herdr_snapshot.get("remote_snapshots", []) or []:
        if not isinstance(remote, dict):
            continue
        host = str(remote.get("host") or "").strip()
        if not host:
            continue
        errors = [
            error for error in remote.get("errors", []) or []
            if isinstance(error, dict)
        ]
        first_error = str(errors[0].get("error") or "").strip() if errors else ""
        hosts.append({
            "host": host,
            "is_current_host": False,
            "healthy": bool(remote.get("success", False)),
            "agents": len([
                session for session in remote.get("sessions", []) or []
                if isinstance(session, dict)
            ]),
            "error": first_error,
        })
    return hosts


def build_herdr_dashboard_summary(
    herdr_snapshot: Dict[str, Any],
    *,
    spaces: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Build the compact Herdr summary embedded in dashboard snapshots."""
    if not isinstance(herdr_snapshot, dict):
        herdr_snapshot = {}
    return {
        "herdr_generation": int(herdr_snapshot.get("herdr_generation") or 0),
        "local_herdr_generation": int(herdr_snapshot.get("local_herdr_generation") or 0),
        "remote_herdr_generation": herdr_snapshot.get("remote_herdr_generation", {}),
        "status": herdr_snapshot.get("status", {}),
        "workspace_count": len(herdr_snapshot.get("workspaces", []) or []),
        "tab_count": len(herdr_snapshot.get("tabs", []) or []),
        "pane_count": len(herdr_snapshot.get("panes", []) or []),
        "agent_count": len(herdr_snapshot.get("agents", []) or []),
        "errors": herdr_snapshot.get("errors", []),
        "hosts": _herdr_host_summaries(herdr_snapshot),
        "spaces": spaces,
    }


def build_dashboard_snapshot_payload(
    *,
    runtime_snapshot: Dict[str, Any],
    display_snapshot: Dict[str, Any],
    projects: List[Dict[str, Any]],
    sessions: List[Dict[str, Any]],
    focus_state: Dict[str, Any],
    herdr_spaces: List[Dict[str, Any]],
    launches: List[Dict[str, Any]],
    snapshot_version: int,
    session_generation: int,
    display_generation: int,
    focus_generation: int,
    timestamp: int,
    schema_version: str = DASHBOARD_SCHEMA_VERSION,
) -> Dict[str, Any]:
    """Assemble and validate the daemon dashboard snapshot payload."""
    herdr_snapshot = runtime_snapshot.get("herdr", {}) if isinstance(runtime_snapshot, dict) else {}
    if not isinstance(herdr_snapshot, dict):
        herdr_snapshot = {}
    payload = {
        "status": "ok",
        "schema_version": schema_version,
        "timestamp": timestamp,
        "generation": snapshot_version,
        "snapshot_version": snapshot_version,
        "session_generation": session_generation,
        "display_generation": display_generation,
        "focus_generation": focus_generation,
        "active_project": runtime_snapshot.get("active_project"),
        "active_context": runtime_snapshot.get("active_context", {}),
        "active_terminal": runtime_snapshot.get("active_terminal", {}),
        "outputs": runtime_snapshot.get("outputs", []),
        "active_outputs": runtime_snapshot.get("active_outputs", []),
        "display_layout": display_snapshot,
        "total_windows": int(runtime_snapshot.get("total_windows", 0) or 0),
        "window_count": int(runtime_snapshot.get("total_windows", 0) or 0),
        "tracked_windows": runtime_snapshot.get("tracked_windows", []),
        "state_health": runtime_snapshot.get("state_health", {}),
        "launch_stats": runtime_snapshot.get("launch_stats", {}),
        "launches": launches,
        "scratchpad": runtime_snapshot.get("scratchpad", {}),
        "projects": projects,
        "project_count": len(projects),
        # No `worktrees`/`worktree_count`: the array was the `repos.json`
        # inventory rendered verbatim, nothing in the shell ever read it, and
        # the inventory is gone.
        "active_ai_sessions": sessions,
        "focus_state": focus_state,
        "herdr": build_herdr_dashboard_summary(
            herdr_snapshot,
            spaces=herdr_spaces,
        ),
    }
    dashboard_invariants = validate_dashboard_payload(
        payload,
        schema_version=schema_version,
    )
    payload["dashboard_invariants"] = dashboard_invariants
    # Degrade gracefully — NEVER blank the whole dashboard on an invariant.
    # Return the payload (with dashboard_invariants embedded) plus a status flag
    # so the panel renders best-effort; the QuickShell client already surfaces
    # the issues as a warning (checkDashboardFocusInvariants). Previously any
    # single tripped invariant (e.g. a focused remote herdr session after a
    # daemon restart) raised here and blanked the entire panel.
    payload["dashboard_status"] = (
        "ok" if bool(dashboard_invariants.get("ok", False)) else "degraded"
    )
    return payload


_current_workspace_row_invariant_active = False


def _note_current_workspace_row_invariant(
    *,
    tripped: bool,
    workspace_name: str,
    output_names: List[str],
    duplicate_rows: List[Dict[str, Any]],
) -> None:
    """Log the duplicate-workspace invariant once per transition into degraded.

    The invariant silently degrades dashboard_status otherwise; logging on the
    transition (not per snapshot) keeps the journal usable without spam.
    """
    global _current_workspace_row_invariant_active
    if not tripped:
        _current_workspace_row_invariant_active = False
        return
    if _current_workspace_row_invariant_active:
        return
    _current_workspace_row_invariant_active = True
    logger.warning(
        "Dashboard degraded: current_workspace_row_not_unique for workspace %r "
        "(outputs: %s, matching rows: %s)",
        workspace_name,
        output_names,
        duplicate_rows,
    )


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
    generation_raw = payload.get("generation")
    snapshot_version_raw = payload.get("snapshot_version")
    try:
        generation = int(generation_raw)
    except (TypeError, ValueError):
        generation = -1
        issues.append("missing_generation")
    try:
        snapshot_version = int(snapshot_version_raw)
    except (TypeError, ValueError):
        snapshot_version = -1
        issues.append("missing_snapshot_version")
    if generation >= 0 and snapshot_version >= 0 and generation != snapshot_version:
        issues.append("generation_snapshot_version_mismatch")
    if "current_ai_session_key" in payload:
        issues.append("retired_current_ai_session_key")

    focus_state = payload.get("focus_state")
    if not isinstance(focus_state, dict):
        focus_state = {}
        issues.append("missing_focus_state")
    else:
        if "current_ai_session_key" in focus_state:
            issues.append("retired_focus_current_ai_session_key")
        if "focused_window_id" in focus_state:
            issues.append("retired_focus_focused_window_id")

    current_key = str(
        focus_state.get("current_session_key")
        or ""
    ).strip()
    sessions = [
        session for session in payload.get("active_ai_sessions", []) or []
        if isinstance(session, dict)
    ]
    for session in sessions:
        session_key = str(session.get("session_key") or "").strip()
        if not session_key:
            continue
        if str(session.get("source") or "").strip() != "herdr":
            issues.append("non_herdr_ai_session_row")
            break
        if not str(session.get("pane_id") or "").strip():
            issues.append("herdr_session_without_pane_id")
            break
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

    # `herdr_focused` is a verbatim copy of Herdr's own per-pane focus flag,
    # independent of sway focus. Herdr guarantees at most one focused pane per
    # host and normalize_sessions re-enforces that per host, so more than one
    # row claiming it (or a non-Herdr row carrying it at all) means the shell
    # could highlight two return targets. Warnings only, never issues — see the
    # remote_herdr_focus_mismatch note below: raising a hint like this as a hard
    # invariant blanked the whole snapshot.
    herdr_focused_hosts: List[str] = []
    foreign_herdr_focused = False
    for session in sessions:
        if not bool(session.get("herdr_focused", False)):
            continue
        if str(session.get("source") or "").strip() != "herdr":
            foreign_herdr_focused = True
            continue
        herdr_focused_hosts.append(
            str(session.get("herdr_host") or session.get("host_name") or "").strip().lower()
        )
    if foreign_herdr_focused:
        warnings.append("non_herdr_row_with_herdr_focused")
    if len(herdr_focused_hosts) != len(set(herdr_focused_hosts)):
        warnings.append("duplicate_herdr_focused_sessions")

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
    focus_window_id = int(focus_state.get("current_window_id") or 0)
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

    workspace_rows: List[Dict[str, Any]] = []
    workspace_row_outputs: List[str] = []
    output_names: List[str] = []
    focused_workspaces = []
    for output in payload.get("outputs", []) or []:
        if not isinstance(output, dict):
            continue
        output_name = str(output.get("name") or "").strip()
        output_names.append(output_name)
        for workspace in output.get("workspaces", []) or []:
            if not isinstance(workspace, dict):
                continue
            workspace_rows.append(workspace)
            workspace_row_outputs.append(output_name)
            if bool(workspace.get("focused", False)):
                focused_workspaces.append(workspace)
    if len(focused_workspaces) > 1:
        issues.append("duplicate_focused_workspaces")
    current_workspace_name = str(focus_state.get("current_workspace_name") or "").strip()
    duplicate_workspace_rows: List[Dict[str, Any]] = []
    if current_workspace_name and workspace_rows:
        matching_current_workspaces = [
            workspace for workspace in workspace_rows
            if str(workspace.get("name") or workspace.get("workspace_name") or "").strip()
            == current_workspace_name
        ]
        if len(matching_current_workspaces) != 1:
            issues.append("current_workspace_row_not_unique")
            duplicate_workspace_rows = [
                {
                    "output": workspace_row_outputs[index],
                    "workspace": str(
                        workspace.get("name")
                        or workspace.get("workspace_name")
                        or ""
                    ).strip(),
                    "focused": bool(workspace.get("focused", False)),
                }
                for index, workspace in enumerate(workspace_rows)
                if str(workspace.get("name") or workspace.get("workspace_name") or "").strip()
                == current_workspace_name
            ]
        elif not bool(matching_current_workspaces[0].get("focused", False)):
            issues.append("current_workspace_row_mismatch")
        if len(focused_workspaces) == 1:
            focused_workspace_name = str(
                focused_workspaces[0].get("name")
                or focused_workspaces[0].get("workspace_name")
                or ""
            ).strip()
            if focused_workspace_name != current_workspace_name:
                issues.append("focused_workspace_row_mismatch")
        elif not focused_workspaces:
            issues.append("current_workspace_focus_missing")

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
            # Non-fatal: a remote herdr session reports focused=True from ITS OWN
            # host's herdr (e.g. ryzen's focused pane), which is independent of
            # this host's current_session_key — the user can be focused on a local
            # session while a remote session stays focused remotely. Raising this
            # as a hard invariant blanked the WHOLE dashboard snapshot whenever a
            # remote agent was focused (e.g. right after a daemon restart), so
            # surface it as a warning instead of failing the snapshot.
            warnings.append("remote_herdr_focus_mismatch")

    _note_current_workspace_row_invariant(
        tripped="current_workspace_row_not_unique" in issues,
        workspace_name=current_workspace_name,
        output_names=output_names,
        duplicate_rows=duplicate_workspace_rows,
    )

    return {
        "ok": not issues,
        "issues": issues,
        "warnings": warnings,
        "schema_version": schema_version,
    }
