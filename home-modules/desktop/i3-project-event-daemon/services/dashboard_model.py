"""Dashboard payload model helpers and invariants."""

from __future__ import annotations

import re

from typing import Any, Callable, Dict, List, Tuple


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
    sessions_by_window: Dict[int, List[Dict[str, Any]]] = {}
    for session in sessions:
        if not isinstance(session, dict):
            continue
        window_id = int(session.get("window_id") or 0)
        if window_id <= 0:
            continue
        sessions_by_window.setdefault(window_id, []).append(session)

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
        session_items: List[Dict[str, Any]] = []
        for session in sessions_by_window.get(window_id, []):
            if not isinstance(session, dict):
                continue
            session_target_host = normalize_target_host(
                session.get("target_host")
                or session.get("host_name")
                or target_host
            )
            session_items.append({
                "session_key": str(session.get("session_key") or ""),
                "focus_target": dict(session.get("focus_target") or {}),
                "close_target": dict(session.get("close_target") or {}),
                "source": str(session.get("source") or "").strip(),
                "agent": str(session.get("agent") or "").strip(),
                "tool": str(session.get("tool") or ""),
                "display_tool": str(session.get("display_tool") or session.get("tool") or ""),
                "agent_status": str(session.get("agent_status") or "unknown").strip() or "unknown",
                "pane_id": str(session.get("pane_id") or "").strip(),
                "tab_id": str(session.get("tab_id") or "").strip(),
                "workspace_id": str(session.get("workspace_id") or "").strip(),
                "terminal_id": str(session.get("terminal_id") or "").strip(),
                "cwd": str(session.get("cwd") or "").strip(),
                "foreground_cwd": str(session.get("foreground_cwd") or "").strip(),
                "pane_label": str(session.get("pane_label") or session.get("pane_title") or session.get("pane_id") or "").strip(),
                "is_current_window": bool(session.get("is_current_window", False)),
                "pane_active": bool(session.get("pane_active", False)),
                "window_active": bool(session.get("window_active", False)),
                "target_host": session_target_host,
                "transport_kind": str(
                    session.get("transport_kind")
                    or transport_kind_for_target_host(session_target_host)
                ).strip(),
            })

        session_items.sort(
            key=lambda item: (
                bool(item.get("is_current_window", False)),
                bool(item.get("pane_active", False)),
                str(item.get("agent_status") or ""),
                str(item.get("pane_label") or ""),
                str(item.get("session_key") or ""),
            ),
            reverse=True,
        )
        has_active_session = any(
            bool(item.get("window_active", False)) or bool(item.get("pane_active", False))
            for item in session_items
        )
        matches_focus_override = window_matches_focus_override(
            window_id=window_id,
            connection_key=str(window.get("connection_key") or "").strip(),
        )
        derived_focused = focused_window_id > 0 and window_id == focused_window_id
        derived_visible = bool(window.get("visible", False)) or has_active_session or matches_focus_override
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
            "ai_session_count": 0,
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
        entry["ai_session_count"] = int(entry["ai_session_count"]) + len(session_items)
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
            "scope": str(window.get("scope") or "").strip(),
            "focus_target": build_window_focus_target(
                window_id=window_id,
                project_name=project_name,
                target_variant=execution_mode,
                connection_key=str(window.get("connection_key") or "").strip(),
            ),
            "sessions": session_items,
            "ai_session_count": len(session_items),
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


def build_dashboard_worktree_rows(
    *,
    runtime_snapshot: Dict[str, Any],
    repositories: List[Dict[str, Any]],
    usage_map: Dict[str, Dict[str, Any]],
    runtime_windows: List[Dict[str, Any]],
    active_target_host: str,
    canonical_project_name: Callable[..., str],
    get_worktree_host_profile: Callable[[str], Dict[str, Any] | None],
) -> List[Dict[str, Any]]:
    """Build sorted dashboard worktree rows from daemon repository/runtime inputs."""
    active_context = runtime_snapshot.get("active_context", {}) if isinstance(runtime_snapshot, dict) else {}
    active_qualified = str(
        active_context.get("qualified_name")
        or active_context.get("project_name")
        or ""
    ).strip()

    window_counts: Dict[str, Dict[str, int]] = {}
    for window in runtime_windows:
        if not isinstance(window, dict):
            continue
        project_name = canonical_project_name(
            window.get("project"),
            project_path=window.get("project_path"),
        )
        if not project_name:
            continue

        counts = window_counts.setdefault(project_name, {
            "scoped_window_count": 0,
            "visible_window_count": 0,
        })
        counts["scoped_window_count"] += 1
        if not bool(window.get("hidden", False)):
            counts["visible_window_count"] += 1

    worktrees: List[Dict[str, Any]] = []
    for repo in repositories:
        if not isinstance(repo, dict):
            continue
        account = str(repo.get("account") or "").strip()
        repo_name = str(repo.get("name") or "").strip()
        display_name = f"{account}/{repo_name}" if account and repo_name else repo_name or account

        for worktree in list(repo.get("worktrees", []) or []):
            if not isinstance(worktree, dict):
                continue
            branch = str(worktree.get("branch") or "").strip()
            qualified_name = f"{account}/{repo_name}:{branch}" if account and repo_name and branch else branch or display_name
            staged = int(worktree.get("staged_count") or 0)
            modified = int(worktree.get("modified_count") or 0)
            untracked = int(worktree.get("untracked_count") or 0)
            dirty_count = staged + modified + untracked
            usage_entry = usage_map.get(qualified_name, {}) if isinstance(usage_map, dict) else {}
            counts = window_counts.get(qualified_name, {})
            host_profile = get_worktree_host_profile(qualified_name)
            host_profile_available = bool(host_profile)
            worktrees.append({
                "qualified_name": qualified_name,
                "repo_display": display_name,
                "repo_name": repo_name,
                "account": account,
                "branch": branch,
                "path": str(worktree.get("path") or ""),
                "is_main": bool(worktree.get("is_main", False)),
                "is_clean": bool(worktree.get("is_clean", False)),
                "is_stale": bool(worktree.get("is_stale", False)),
                "has_conflicts": bool(worktree.get("has_conflicts", False)),
                "ahead": int(worktree.get("ahead") or 0),
                "behind": int(worktree.get("behind") or 0),
                "staged_count": staged,
                "modified_count": modified,
                "untracked_count": untracked,
                "dirty_count": dirty_count,
                "is_active": qualified_name == active_qualified,
                "active_target_host": active_target_host if qualified_name == active_qualified else "",
                "host_profile_available": host_profile_available,
                "host_profile_host": str(host_profile.get("host") or "").strip() if isinstance(host_profile, dict) else "",
                "visible_window_count": int(counts.get("visible_window_count", 0) or 0),
                "scoped_window_count": int(counts.get("scoped_window_count", 0) or 0),
                "last_used_at": int(usage_entry.get("last_used_at", 0) or 0),
                "use_count": int(usage_entry.get("use_count", 0) or 0),
                "last_commit_message": str(worktree.get("last_commit_message") or ""),
            })

    worktrees.sort(
        key=lambda item: (
            0 if bool(item.get("is_active", False)) else 1,
            -int(item.get("visible_window_count", 0) or 0),
            -int(item.get("scoped_window_count", 0) or 0),
            -int(item.get("last_used_at", 0) or 0),
            -int(item.get("use_count", 0) or 0),
            0 if not bool(item.get("is_clean", False)) else 1,
            str(item.get("repo_display") or "").casefold(),
            str(item.get("branch") or "").casefold(),
            str(item.get("qualified_name") or "").casefold(),
        ),
    )
    return worktrees


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
            "current_ai_session_key",
            "worktrees",
        ]
    if typed_event == "herdr.changed":
        return [
            "focus_state",
            "active_ai_sessions",
            "current_ai_session_key",
            "herdr",
        ]
    if typed_event == "display.changed":
        return ["outputs", "active_outputs", "display_layout"]
    return ["dashboard"]


def advance_dashboard_event_state(
    *,
    event_type: str,
    snapshot_version: int,
    session_generation: int,
    display_generation: int,
    focus_generation: int,
) -> Dict[str, Any]:
    """Advance dashboard generations for one typed state-change event."""
    normalized_type = str(event_type or "dashboard_invalidated")
    typed_event_type = dashboard_event_type_for_state_change(normalized_type)
    changed_keys = dashboard_changed_keys_for_event(normalized_type)
    next_snapshot_version = int(snapshot_version or 0) + 1
    next_session_generation = int(session_generation or 0)
    next_display_generation = int(display_generation or 0)
    next_focus_generation = int(focus_generation or 0)
    if typed_event_type in {"session.changed", "herdr.changed"}:
        next_session_generation += 1
    if typed_event_type in {
        "focus.changed",
        "window.changed",
        "workspace.changed",
        "session.changed",
        "herdr.changed",
    }:
        next_focus_generation += 1
    if typed_event_type == "display.changed":
        next_display_generation += 1
    return {
        "type": normalized_type,
        "event_type": typed_event_type,
        "changed_keys": changed_keys,
        "snapshot_version": next_snapshot_version,
        "session_generation": next_session_generation,
        "display_generation": next_display_generation,
        "focus_generation": next_focus_generation,
        "invalidate_worktree_cache": normalized_type.startswith("project") or normalized_type.startswith("worktree"),
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
        "spaces": spaces,
    }


def build_dashboard_snapshot_payload(
    *,
    runtime_snapshot: Dict[str, Any],
    display_snapshot: Dict[str, Any],
    projects: List[Dict[str, Any]],
    worktrees: List[Dict[str, Any]],
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
    current_session_key = str(runtime_snapshot.get("current_ai_session_key") or "").strip()
    payload = {
        "status": "ok",
        "schema_version": schema_version,
        "timestamp": timestamp,
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
        "worktrees": worktrees,
        "worktree_count": len(worktrees),
        "active_ai_sessions": sessions,
        "current_ai_session_key": current_session_key,
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
    if not bool(dashboard_invariants.get("ok", False)):
        raise RuntimeError(
            "dashboard.snapshot invariant violation: "
            + ",".join(str(issue) for issue in dashboard_invariants.get("issues", []) or [])
        )
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
