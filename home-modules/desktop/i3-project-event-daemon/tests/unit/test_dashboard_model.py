"""Unit tests for daemon dashboard model invariants."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path


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
