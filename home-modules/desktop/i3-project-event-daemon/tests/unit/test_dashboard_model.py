"""Unit tests for daemon dashboard model invariants."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path

import pytest


PACKAGE_ROOT = Path(__file__).parent.parent.parent

if "i3_project_daemon" not in sys.modules:
    package_spec = importlib.util.spec_from_file_location(
        "i3_project_daemon",
        PACKAGE_ROOT / "__init__.py",
        submodule_search_locations=[str(PACKAGE_ROOT)],
    )
    package_module = importlib.util.module_from_spec(package_spec)
    sys.modules["i3_project_daemon"] = package_module
    assert package_spec.loader is not None
    package_spec.loader.exec_module(package_module)


dashboard_model = importlib.import_module("i3_project_daemon.services.dashboard_model")

validate_dashboard_payload = dashboard_model.validate_dashboard_payload
dashboard_event_type_for_state_change = dashboard_model.dashboard_event_type_for_state_change
dashboard_changed_keys_for_event = dashboard_model.dashboard_changed_keys_for_event
dashboard_event_payload_from_snapshot = dashboard_model.dashboard_event_payload_from_snapshot
build_dashboard_projects = dashboard_model.build_dashboard_projects
build_dashboard_snapshot_payload = dashboard_model.build_dashboard_snapshot_payload
advance_dashboard_event_state = dashboard_model.advance_dashboard_event_state
dashboard_event_notification = dashboard_model.dashboard_event_notification
dashboard_invalidated_payload = dashboard_model.dashboard_invalidated_payload


def _project_builder_callbacks(*, override_windows=None):
    override_windows = set(override_windows or [])

    def canonical_project_name(value, *, project_path=None):
        _ = project_path
        return str(value or "").strip()

    def normalize_target_host(value):
        return str(value or "local").strip() or "local"

    def parse_context_key_target_host(value):
        text = str(value or "")
        if "::host::" in text:
            return text.rsplit("::host::", 1)[1]
        return ""

    def target_host_from_context_payload(context, *, project_name=""):
        _ = project_name
        return normalize_target_host((context or {}).get("target_host") or "local")

    def transport_kind_for_target_host(value):
        return "local" if normalize_target_host(value) == "local" else "ssh"

    return {
        "canonical_project_name": canonical_project_name,
        "normalize_target_host": normalize_target_host,
        "parse_context_key_target_host": parse_context_key_target_host,
        "target_host_from_context_payload": target_host_from_context_payload,
        "local_host_alias": lambda: "local",
        "execution_mode_for_target_host": lambda value: "local" if normalize_target_host(value) == "local" else "ssh",
        "build_target_context_key": lambda project_name, target_host: f"{project_name}::{target_host}",
        "transport_kind_for_target_host": transport_kind_for_target_host,
        "window_matches_focus_override": lambda **kwargs: int(kwargs.get("window_id") or 0) in override_windows,
        "build_window_focus_target": lambda **kwargs: {
            "kind": "window",
            "window_id": int(kwargs.get("window_id") or 0),
            "project_name": str(kwargs.get("project_name") or ""),
            "target_variant": str(kwargs.get("target_variant") or ""),
            "connection_key": str(kwargs.get("connection_key") or ""),
        },
    }


def test_validate_dashboard_payload_accepts_single_daemon_current_row() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
            "current_workspace_name": "1",
        },
        "current_ai_session_key": "session-current",
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "focused": True,
                "is_current_host": True,
            },
            {
                "session_key": "session-background",
                "is_current_window": False,
                "source": "herdr",
                "focused": False,
                "is_current_host": True,
            },
        ],
        "projects": [
            {
                "windows": [
                    {"id": 101, "focused": True},
                    {"id": 202, "focused": False},
                ],
            },
        ],
        "outputs": [
            {
                "workspaces": [
                    {"name": "1", "focused": True},
                    {"name": "2", "focused": False},
                ],
            },
        ],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is True
    assert result["issues"] == []
    assert result["warnings"] == []


def test_build_dashboard_projects_groups_windows_and_shapes_session_rows() -> None:
    runtime_snapshot = {
        "focused_window_id": 101,
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "target_host": "local",
        },
        "tracked_windows": [
            {
                "window_id": 101,
                "title": "Editor",
                "app_name": "terminal",
                "project": "vpittamp/nixos-config:main",
                "target_host": "local",
                "connection_key": "local@ryzen",
                "workspace": "2",
                "visible": True,
            },
            {
                "window_id": 202,
                "title": "Remote",
                "class": "Alacritty",
                "project": "vpittamp/nixos-config:main",
                "target_host": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "workspace": "1",
                "hidden": True,
            },
        ],
    }
    sessions = [
        {
            "session_key": "session-current",
            "window_id": 101,
            "source": "herdr",
            "tool": "codex",
            "agent_status": "working",
            "pane_id": "pane-1",
            "pane_label": "agent",
            "is_current_window": True,
            "pane_active": True,
            "window_active": True,
        },
        {
            "session_key": "session-hidden",
            "window_id": 202,
            "source": "herdr",
            "tool": "claude",
            "agent_status": "idle",
        },
    ]

    projects = build_dashboard_projects(
        runtime_snapshot,
        sessions,
        **_project_builder_callbacks(override_windows={202}),
    )

    assert [project["target_host"] for project in projects] == ["local", "ryzen"]
    local_project = projects[0]
    remote_project = projects[1]
    assert local_project["is_active"] is True
    assert local_project["focused"] is True
    assert local_project["window_count"] == 1
    assert local_project["windows"][0]["focus_target"]["window_id"] == 101
    assert local_project["windows"][0]["sessions"][0]["session_key"] == "session-current"
    assert local_project["windows"][0]["sessions"][0]["transport_kind"] == "local"
    assert remote_project["visible_window_count"] == 1
    assert remote_project["hidden_window_count"] == 0
    assert remote_project["windows"][0]["visible"] is True
    assert remote_project["windows"][0]["hidden"] is False


def test_build_dashboard_projects_sorts_windows_by_workspace_and_app() -> None:
    runtime_snapshot = {
        "focused_window_id": 0,
        "active_context": {},
        "tracked_windows": [
            {"window_id": 3, "project": "global", "workspace": "scratchpad", "app_name": "zeta"},
            {"window_id": 2, "project": "global", "workspace": "10", "app_name": "beta"},
            {"window_id": 1, "project": "global", "workspace": "2", "app_name": "alpha"},
        ],
    }

    projects = build_dashboard_projects(
        runtime_snapshot,
        [],
        **_project_builder_callbacks(),
    )

    assert [window["id"] for window in projects[0]["windows"]] == [1, 2, 3]


def test_validate_dashboard_payload_rejects_duplicate_current_rows() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
        },
        "current_ai_session_key": "session-current",
        "active_ai_sessions": [
            {"session_key": "session-current", "is_current_window": True},
            {"session_key": "session-other", "is_current_window": True},
        ],
        "projects": [{"windows": [{"id": 101, "focused": True}]}],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "current_session_row_not_unique" in result["issues"]


def test_validate_dashboard_payload_warns_on_transient_window_focus_rows() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
            "current_workspace_name": "2",
        },
        "current_ai_session_key": "session-current",
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "focused": True,
                "is_current_host": True,
            },
        ],
        "projects": [
            {
                "windows": [
                    {"id": 202, "focused": True, "is_current_window": False},
                    {"id": 101, "focused": True, "is_current_window": True},
                ],
            },
        ],
        "outputs": [{"workspaces": [{"name": "2", "focused": True}]}],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is True
    assert result["issues"] == []
    assert "duplicate_focused_windows" in result["warnings"]
    assert "focused_window_row_mismatch" in result["warnings"]


def test_validate_dashboard_payload_rejects_remote_herdr_focus_mismatch() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-local",
            "current_window_id": 101,
        },
        "current_ai_session_key": "session-local",
        "active_ai_sessions": [
            {
                "session_key": "session-local",
                "is_current_window": True,
                "source": "herdr",
                "focused": False,
                "is_current_host": True,
            },
            {
                "session_key": "session-remote",
                "is_current_window": False,
                "source": "herdr",
                "focused": True,
                "is_current_host": False,
            },
        ],
        "projects": [{"windows": [{"id": 101, "focused": True}]}],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "remote_herdr_focus_mismatch" in result["issues"]


def test_dashboard_event_type_maps_legacy_invalidations_to_typed_events() -> None:
    assert dashboard_event_type_for_state_change("focus_changed") == "focus.changed"
    assert dashboard_event_type_for_state_change("window::focus") == "window.changed"
    assert dashboard_event_type_for_state_change("workspace.focus") == "workspace.changed"
    assert dashboard_event_type_for_state_change("display-profile-applied") == "display.changed"
    assert dashboard_event_type_for_state_change("ai_session_herdr_changed") == "herdr.changed"
    assert dashboard_event_type_for_state_change("agent_session_changed") == "session.changed"
    assert dashboard_event_type_for_state_change("worktree_changed") == "session.changed"
    assert dashboard_event_type_for_state_change("unknown") == "dashboard.invalidated"


def test_dashboard_changed_keys_follow_typed_event_contract() -> None:
    assert dashboard_changed_keys_for_event("focus_changed") == ["focus_state", "outputs", "projects"]
    assert dashboard_changed_keys_for_event("window_changed") == ["focus_state", "projects", "tracked_windows"]
    assert dashboard_changed_keys_for_event("display_changed") == ["outputs", "active_outputs", "display_layout"]
    assert dashboard_changed_keys_for_event("ai_session_herdr_changed") == [
        "focus_state",
        "active_ai_sessions",
        "active_ai_sessions_mru",
        "current_ai_session_key",
        "herdr",
        "ai_monitor_metrics",
    ]
    assert dashboard_changed_keys_for_event("dashboard_invalidated") == ["dashboard"]


def test_advance_dashboard_event_state_updates_generations_by_typed_event() -> None:
    focus_state = advance_dashboard_event_state(
        event_type="focus_changed",
        snapshot_version=10,
        session_generation=20,
        display_generation=30,
        focus_generation=40,
    )
    assert focus_state["event_type"] == "focus.changed"
    assert focus_state["changed_keys"] == ["focus_state", "outputs", "projects"]
    assert focus_state["snapshot_version"] == 11
    assert focus_state["session_generation"] == 20
    assert focus_state["display_generation"] == 30
    assert focus_state["focus_generation"] == 41
    assert focus_state["invalidate_worktree_cache"] is False

    herdr_state = advance_dashboard_event_state(
        event_type="ai_session_herdr_changed",
        snapshot_version=10,
        session_generation=20,
        display_generation=30,
        focus_generation=40,
    )
    assert herdr_state["event_type"] == "herdr.changed"
    assert herdr_state["snapshot_version"] == 11
    assert herdr_state["session_generation"] == 21
    assert herdr_state["focus_generation"] == 41

    display_state = advance_dashboard_event_state(
        event_type="display_changed",
        snapshot_version=10,
        session_generation=20,
        display_generation=30,
        focus_generation=40,
    )
    assert display_state["event_type"] == "display.changed"
    assert display_state["display_generation"] == 31
    assert display_state["focus_generation"] == 40

    worktree_state = advance_dashboard_event_state(
        event_type="worktree_changed",
        snapshot_version=10,
        session_generation=20,
        display_generation=30,
        focus_generation=40,
    )
    assert worktree_state["event_type"] == "session.changed"
    assert worktree_state["invalidate_worktree_cache"] is True


def test_dashboard_event_notification_wraps_payload_with_generation_metadata() -> None:
    state = advance_dashboard_event_state(
        event_type="focus_changed",
        snapshot_version=10,
        session_generation=20,
        display_generation=30,
        focus_generation=40,
    )

    notification = dashboard_event_notification(
        state=state,
        payload={"focus_state": {"current_window_id": 101}},
        timestamp=123.5,
    )

    assert notification["jsonrpc"] == "2.0"
    assert notification["method"] == "focus.changed"
    assert notification["params"]["generation"] == 11
    assert notification["params"]["schema_version"] == "i3pm.dashboard.event.v1"
    assert notification["params"]["payload"] == {"focus_state": {"current_window_id": 101}}


def test_dashboard_invalidated_payload_preserves_generation_context() -> None:
    payload = dashboard_invalidated_payload(
        error=RuntimeError("bad payload"),
        snapshot_version=11,
        session_generation=21,
        display_generation=31,
        focus_generation=41,
    )

    assert payload == {
        "status": "invalidated",
        "schema_version": "i3pm.dashboard.v2",
        "snapshot_version": 11,
        "session_generation": 21,
        "display_generation": 31,
        "focus_generation": 41,
        "error": "bad payload",
    }


def test_dashboard_event_payload_contains_common_metadata_and_changed_models_only() -> None:
    snapshot = {
        "status": "ok",
        "schema_version": "i3pm.dashboard.v2",
        "timestamp": 12345,
        "snapshot_version": 7,
        "session_generation": 3,
        "display_generation": 2,
        "focus_generation": 5,
        "total_windows": 8,
        "window_count": 8,
        "project_count": 2,
        "worktree_count": 4,
        "state_health": {"ok": True},
        "dashboard_invariants": {"ok": True},
        "focus_state": {"current_window_id": 101},
        "projects": [{"name": "demo"}],
        "outputs": [{"name": "eDP-1"}],
        "active_ai_sessions": [{"session_key": "session-a"}],
    }

    payload = dashboard_event_payload_from_snapshot(snapshot, ["focus_state", "projects"])

    assert payload["snapshot_version"] == 7
    assert payload["focus_state"] == {"current_window_id": 101}
    assert payload["projects"] == [{"name": "demo"}]
    assert "outputs" not in payload
    assert "active_ai_sessions" not in payload


def test_build_dashboard_snapshot_payload_shapes_metrics_and_herdr_summary() -> None:
    runtime_snapshot = {
        "active_project": "global",
        "active_context": {"qualified_name": "vpittamp/nixos-config:main"},
        "active_terminal": {"available": True},
        "outputs": [{"name": "DP-1", "workspaces": [{"name": "1", "focused": True}]}],
        "active_outputs": ["DP-1"],
        "total_windows": 1,
        "tracked_windows": [{"id": 101}],
        "state_health": {"ok": True},
        "launch_stats": {"pending": 0},
        "scratchpad": {"visible": False},
        "current_ai_session_key": "session-current",
        "herdr": {
            "herdr_generation": 11,
            "local_herdr_generation": 7,
            "remote_herdr_generation": {"ryzen": 4},
            "status": {"running": True},
            "workspaces": [{"id": "space-1"}],
            "tabs": [{"id": "tab-1"}],
            "panes": [{"id": "pane-1"}],
            "agents": [{"id": "agent-1"}],
            "errors": [],
        },
    }
    sessions = [
        {
            "session_key": "session-current",
            "is_current_window": True,
            "agent_status": "working",
            "source": "herdr",
            "focused": True,
            "is_current_host": True,
        },
        {
            "session_key": "session-done",
            "is_current_window": False,
            "agent_status": "done",
        },
    ]

    payload = build_dashboard_snapshot_payload(
        runtime_snapshot=runtime_snapshot,
        display_snapshot={"outputs": ["DP-1"]},
        projects=[{"windows": [{"id": 101, "focused": True}]}],
        worktrees=[{"qualified_name": "vpittamp/nixos-config:main"}],
        sessions=sessions,
        focus_state={
            "current_session_key": "session-current",
            "current_window_id": 101,
            "current_workspace_name": "1",
        },
        herdr_spaces=[{"id": "space-1", "pane_count": 1}],
        launches=[{"launch_id": "launch-1"}],
        snapshot_version=12,
        session_generation=8,
        display_generation=3,
        focus_generation=5,
        timestamp=12345,
    )

    assert payload["schema_version"] == "i3pm.dashboard.v2"
    assert payload["dashboard_invariants"]["ok"] is True
    assert payload["project_count"] == 1
    assert payload["worktree_count"] == 1
    assert payload["herdr"]["local_herdr_generation"] == 7
    assert payload["herdr"]["spaces"] == [{"id": "space-1", "pane_count": 1}]
    assert payload["ai_monitor_metrics"] == {
        "active_sessions": 2,
        "working_sessions": 1,
        "attention_sessions": 0,
        "done_sessions": 1,
        "idle_sessions": 0,
        "unknown_sessions": 0,
    }


def test_build_dashboard_snapshot_payload_fails_fast_on_invariant_violation() -> None:
    with pytest.raises(RuntimeError, match="current_session_key_not_unique"):
        build_dashboard_snapshot_payload(
            runtime_snapshot={"current_ai_session_key": "session-missing"},
            display_snapshot={},
            projects=[],
            worktrees=[],
            sessions=[],
            focus_state={"current_session_key": "session-missing"},
            herdr_spaces=[],
            launches=[],
            snapshot_version=1,
            session_generation=1,
            display_generation=1,
            focus_generation=1,
            timestamp=12345,
        )
