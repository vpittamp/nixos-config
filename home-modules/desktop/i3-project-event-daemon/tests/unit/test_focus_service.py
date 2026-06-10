"""Unit tests for daemon-owned focus service selection and view model."""

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


focus_service_module = importlib.import_module("i3_project_daemon.services.focus_service")

FocusService = focus_service_module.FocusService


def normalize_connection_key(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    if text.startswith("local@"):
        return text
    return text.lower()


def make_service() -> FocusService:
    return FocusService(normalize_connection_key=normalize_connection_key)


def test_select_current_session_key_clears_stale_window_override() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-old",
        window_id=133,
        connection_key="local@thinkpad",
    )
    sessions = [
        {
            "session_key": "session-old",
            "window_id": 133,
            "is_current_host": True,
            "window_active": False,
            "pane_active": True,
        },
        {
            "session_key": "session-new",
            "window_id": 146,
            "is_current_host": True,
            "window_active": True,
            "pane_active": False,
        },
    ]

    result = service.select_current_session_key(sessions, focused_window_id=146)

    assert result == "session-new"
    assert service.session_override_key == ""
    assert service.window_override == {"window_id": 0, "connection_key": ""}


def test_select_current_session_key_prefers_focused_remote_herdr_override() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="herdr:ryzen:pane:w1-1",
        window_id=0,
        connection_key="vpittamp@ryzen:22",
    )
    sessions = [
        {
            "session_key": "herdr:thinkpad:pane:w0-1",
            "source": "herdr",
            "focused": True,
            "is_current_host": True,
        },
        {
            "session_key": "herdr:ryzen:pane:w1-1",
            "source": "herdr",
            "focused": True,
            "is_current_host": False,
        },
    ]

    result = service.select_current_session_key(sessions, focused_window_id=0)

    assert result == "herdr:ryzen:pane:w1-1"


def test_mark_current_session_produces_single_current_row() -> None:
    service = make_service()
    sessions = [
        {"session_key": "session-a", "is_current_window": True},
        {"session_key": "session-b", "is_current_window": True},
    ]

    service.mark_current_session(sessions, current_session_key="session-b")

    assert [session["is_current_window"] for session in sessions] == [False, True]


def test_build_focus_state_payload_uses_daemon_focus_fields() -> None:
    service = make_service()
    service.pending_intent_id = "intent-7"
    runtime_snapshot = {
        "active_context": {"connection_key": "local@thinkpad"},
        "current_ai_session_key": "session-current",
        "focused_window_id": 101,
        "outputs": [
            {
                "current_workspace": "2",
                "workspaces": [
                    {"name": "1", "focused": False},
                    {"name": "2", "focused": True},
                ],
            }
        ],
    }
    sessions = [
        {
            "session_key": "session-current",
            "pane_id": "pane-1",
            "host_name": "thinkpad",
            "agent": "codex",
            "window_id": 101,
        }
    ]

    result = service.build_focus_state_payload(
        runtime_snapshot,
        sessions,
        generation=42,
    )

    assert result["schema_version"] == "i3pm.focus_state.v1"
    assert result["generation"] == 42
    assert result["current_session_key"] == "session-current"
    assert result["current_window_id"] == 101
    assert result["current_workspace_name"] == "2"
    assert result["current_herdr_pane_id"] == "pane-1"
    assert result["current_herdr_host"] == "thinkpad"
    assert result["pending_intent_id"] == "intent-7"
    assert result["active_session"]["agent"] == "codex"
