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
build_dashboard_worktree_rows = dashboard_model.build_dashboard_worktree_rows
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


def _worktree(branch: str, **overrides):
    data = {
        "branch": branch,
        "path": f"/tmp/worktrees/{branch}",
        "is_main": branch == "main",
        "is_clean": True,
        "is_stale": False,
        "has_conflicts": False,
        "ahead": 0,
        "behind": 0,
        "staged_count": 0,
        "modified_count": 0,
        "untracked_count": 0,
        "last_commit_message": f"commit for {branch}",
    }
    data.update(overrides)
    return data


def test_validate_dashboard_payload_accepts_single_daemon_current_row() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
            "current_workspace_name": "1",
        },
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-current",
                "focused": True,
                "is_current_host": True,
            },
            {
                "session_key": "session-background",
                "is_current_window": False,
                "source": "herdr",
                "pane_id": "pane-background",
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
    assert "sessions" not in local_project["windows"][0]
    assert "ai_session_count" not in local_project["windows"][0]
    assert "ai_session_count" not in local_project
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


def test_build_dashboard_worktree_rows_sorts_by_active_visibility_usage_and_dirtyness() -> None:
    rows = build_dashboard_worktree_rows(
        runtime_snapshot={
            "active_context": {
                "qualified_name": "vpittamp/nixos-config:main",
            },
        },
        repositories=[{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [
                _worktree("main"),
                _worktree("feature-visible"),
                _worktree("feature-recent"),
                _worktree("feature-frequent"),
                _worktree("feature-infrequent"),
                _worktree("feature-dirty", is_clean=False, modified_count=2),
                _worktree("feature-clean"),
            ],
        }],
        usage_map={
            "vpittamp/nixos-config:feature-recent": {"last_used_at": 300, "use_count": 1},
            "vpittamp/nixos-config:feature-frequent": {"last_used_at": 200, "use_count": 50},
            "vpittamp/nixos-config:feature-infrequent": {"last_used_at": 200, "use_count": 1},
        },
        runtime_windows=[
            {"project": "vpittamp/nixos-config:feature-visible", "hidden": False},
            {"project": "vpittamp/nixos-config:feature-visible", "hidden": True},
        ],
        active_target_host="local",
        canonical_project_name=lambda value, **_kwargs: str(value or "").strip(),
        get_worktree_host_profile=lambda _qualified_name: None,
    )

    assert [item["qualified_name"] for item in rows] == [
        "vpittamp/nixos-config:main",
        "vpittamp/nixos-config:feature-visible",
        "vpittamp/nixos-config:feature-recent",
        "vpittamp/nixos-config:feature-frequent",
        "vpittamp/nixos-config:feature-infrequent",
        "vpittamp/nixos-config:feature-dirty",
        "vpittamp/nixos-config:feature-clean",
    ]
    visible = rows[1]
    assert visible["visible_window_count"] == 1
    assert visible["scoped_window_count"] == 2
    assert rows[0]["is_active"] is True
    assert rows[0]["active_target_host"] == "local"
    assert rows[5]["dirty_count"] == 2


def test_build_dashboard_worktree_rows_exposes_remote_profile_metadata() -> None:
    rows = build_dashboard_worktree_rows(
        runtime_snapshot={
            "active_context": {
                "qualified_name": "vpittamp/nixos-config:main",
            },
        },
        repositories=[{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [
                _worktree("main"),
                _worktree("feature-local"),
            ],
        }],
        usage_map={},
        runtime_windows=[],
        active_target_host="ryzen",
        canonical_project_name=lambda value, **_kwargs: str(value or "").strip(),
        get_worktree_host_profile=lambda qualified_name: (
            {"enabled": True, "host": "ryzen"}
            if qualified_name == "vpittamp/nixos-config:main"
            else None
        ),
    )

    assert rows[0]["qualified_name"] == "vpittamp/nixos-config:main"
    assert rows[0]["is_active"] is True
    assert rows[0]["active_target_host"] == "ryzen"
    assert rows[0]["host_profile_available"] is True
    assert rows[0]["host_profile_host"] == "ryzen"
    assert rows[1]["host_profile_available"] is False


def test_validate_dashboard_payload_rejects_duplicate_current_rows() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
        },
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-current",
            },
            {
                "session_key": "session-other",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-other",
            },
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
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 101,
            "current_workspace_name": "2",
        },
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-current",
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


def test_validate_dashboard_payload_rejects_workspace_focus_mismatch() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "2",
        },
        "active_ai_sessions": [],
        "projects": [],
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

    assert result["ok"] is False
    assert "current_workspace_row_mismatch" in result["issues"]
    assert "focused_workspace_row_mismatch" in result["issues"]


def test_validate_dashboard_payload_rejects_duplicate_current_workspace_rows() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "2",
        },
        "active_ai_sessions": [],
        "projects": [],
        "outputs": [
            {
                "workspaces": [
                    {"name": "2", "focused": True},
                    {"name": "2", "focused": False},
                ],
            },
        ],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "current_workspace_row_not_unique" in result["issues"]


def test_validate_dashboard_payload_rejects_remote_herdr_focus_mismatch() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-local",
            "current_window_id": 101,
        },
        "active_ai_sessions": [
            {
                "session_key": "session-local",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-local",
                "focused": False,
                "is_current_host": True,
            },
            {
                "session_key": "session-remote",
                "is_current_window": False,
                "source": "herdr",
                "pane_id": "pane-remote",
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


def test_validate_dashboard_payload_rejects_retired_focus_aliases() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_ai_session_key": "session-current",
            "current_window_id": 101,
            "focused_window_id": 101,
        },
        "current_ai_session_key": "session-current",
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
                "pane_id": "pane-current",
            },
        ],
        "projects": [{"windows": [{"id": 101, "is_current_window": True}]}],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "retired_current_ai_session_key" in result["issues"]
    assert "retired_focus_current_ai_session_key" in result["issues"]
    assert "retired_focus_focused_window_id" in result["issues"]


def test_validate_dashboard_payload_rejects_missing_generation() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "",
            "current_window_id": 0,
        },
        "active_ai_sessions": [],
        "projects": [],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "missing_generation" in result["issues"]


def test_validate_dashboard_payload_rejects_generation_mismatch() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 2,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "",
            "current_window_id": 0,
        },
        "active_ai_sessions": [],
        "projects": [],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "generation_snapshot_version_mismatch" in result["issues"]


def test_validate_dashboard_payload_rejects_non_herdr_session_rows() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 0,
        },
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "otel",
                "pane_id": "pane-current",
            },
        ],
        "projects": [],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "non_herdr_ai_session_row" in result["issues"]


def test_validate_dashboard_payload_rejects_herdr_session_without_pane() -> None:
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "generation": 1,
        "snapshot_version": 1,
        "focus_state": {
            "current_session_key": "session-current",
            "current_window_id": 0,
        },
        "active_ai_sessions": [
            {
                "session_key": "session-current",
                "is_current_window": True,
                "source": "herdr",
            },
        ],
        "projects": [],
        "outputs": [],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is False
    assert "herdr_session_without_pane_id" in result["issues"]


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
        "herdr",
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
        "generation": 11,
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
        "generation": 7,
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

    assert payload["generation"] == 7
    assert payload["snapshot_version"] == 7
    assert payload["focus_state"] == {"current_window_id": 101}
    assert payload["projects"] == [{"name": "demo"}]
    assert "outputs" not in payload
    assert "active_ai_sessions" not in payload


def test_build_dashboard_snapshot_payload_shapes_herdr_summary() -> None:
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
        "current_session_key": "session-current",
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
            "pane_id": "pane-current",
            "focused": True,
            "is_current_host": True,
        },
        {
            "session_key": "session-done",
            "is_current_window": False,
            "agent_status": "done",
            "source": "herdr",
            "pane_id": "pane-done",
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
    assert payload["generation"] == 12
    assert payload["snapshot_version"] == 12
    assert "current_ai_session_key" not in payload
    assert payload["dashboard_invariants"]["ok"] is True
    assert payload["project_count"] == 1
    assert payload["worktree_count"] == 1
    assert payload["herdr"]["local_herdr_generation"] == 7
    assert payload["herdr"]["spaces"] == [{"id": "space-1", "pane_count": 1}]


def test_build_dashboard_snapshot_payload_fails_fast_on_invariant_violation() -> None:
    with pytest.raises(RuntimeError, match="current_session_key_not_unique"):
        build_dashboard_snapshot_payload(
            runtime_snapshot={"current_session_key": "session-missing"},
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
