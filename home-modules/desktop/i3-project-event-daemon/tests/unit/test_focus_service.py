"""Unit tests for daemon-owned focus service selection and view model."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

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


def make_action_service(
    *,
    sway_available=True,
    command_result=None,
    workspaces=None,
    notify_state_change=None,
    send_tick_barrier=None,
) -> FocusService:
    return FocusService(
        normalize_connection_key=normalize_connection_key,
        sway_available=lambda: sway_available,
        run_sway_command=AsyncMock(return_value=command_result if command_result is not None else [SimpleNamespace(success=True)]),
        sway_command_succeeded=lambda result: all(bool(getattr(item, "success", False)) for item in result),
        get_sway_workspaces=AsyncMock(return_value=workspaces if workspaces is not None else []),
        send_tick_barrier=send_tick_barrier or AsyncMock(return_value=None),
        notify_state_change=notify_state_change or AsyncMock(return_value=None),
    )


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


def test_clear_if_session_matches_clears_focus_overrides() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-a",
        window_id=77,
        connection_key="LOCAL@THINKPAD",
    )

    assert service.clear_if_session_matches("session-b") is False
    assert service.override_payload() == {
        "session_key": "session-a",
        "window_id": 77,
        "connection_key": "local@thinkpad",
    }

    assert service.clear_if_session_matches("session-a") is True
    assert service.override_payload() == {
        "session_key": "",
        "window_id": 0,
        "connection_key": "",
    }


def test_prune_invalid_overrides_reports_cleared_state() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-old",
        window_id=404,
        connection_key="local@thinkpad",
    )

    result = service.prune_invalid_overrides(
        live_session_keys=["session-new"],
        live_window_ids=[101, 202],
        stale_window_ids=[404],
    )

    assert result == {
        "cleared_session_override": True,
        "cleared_window_override": True,
    }
    assert service.override_payload() == {
        "session_key": "",
        "window_id": 0,
        "connection_key": "",
    }


def test_build_focus_state_payload_uses_daemon_focus_fields() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-7",
        kind="window_focus",
        target_key="101",
        created_at=123.5,
        generation=7,
    )
    runtime_snapshot = {
        "active_context": {"connection_key": "local@thinkpad"},
        "current_session_key": "session-current",
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

    assert result["schema_version"] == "i3pm.focus_state.v2"
    assert result["generation"] == 42
    assert result["current_session_key"] == "session-current"
    assert "current_ai_session_key" not in result
    assert result["current_window_id"] == 101
    assert "focused_window_id" not in result
    assert result["current_workspace_name"] == "2"
    assert result["current_herdr_pane_id"] == "pane-1"
    assert result["current_herdr_host"] == "thinkpad"
    assert result["pending_intent_id"] == "intent-7"
    assert result["focus_intent"] == {
        "intent_id": "intent-7",
        "kind": "window_focus",
        "target_key": "101",
        "state": "pending",
        "created_at": 123.5,
        "generation": 7,
        "reason": "",
    }
    assert result["active_session"]["agent"] == "codex"


def test_build_focus_state_payload_prefers_focused_workspace_over_output_current_fallback() -> None:
    service = make_service()
    runtime_snapshot = {
        "active_context": {"connection_key": "local@thinkpad"},
        "current_session_key": "",
        "focused_window_id": 0,
        "outputs": [
            {
                "name": "DP-7",
                "current_workspace": "1",
                "workspaces": [
                    {"name": "1", "focused": False, "visible": True},
                ],
            },
            {
                "name": "eDP-1",
                "current_workspace": "2",
                "workspaces": [
                    {"name": "2", "focused": True, "visible": False},
                ],
            },
        ],
    }

    result = service.build_focus_state_payload(runtime_snapshot, [], generation=5)

    assert result["current_workspace_name"] == "2"


@pytest.mark.asyncio
async def test_focus_workspace_fast_notifies_without_verification() -> None:
    notify_state_change = AsyncMock(return_value=None)
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_action_service(
        notify_state_change=notify_state_change,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.focus_workspace_fast({"workspace": "3"})

    assert result == {"success": True, "workspace": "3", "fast": True}
    service._run_sway_command.assert_awaited_once_with("workspace number 3")
    send_tick_barrier.assert_not_awaited()
    notify_state_change.assert_awaited_once_with("focus_changed")


@pytest.mark.asyncio
async def test_focus_workspace_waits_for_confirmed_workspace() -> None:
    notify_state_change = AsyncMock(return_value=None)
    send_tick_barrier = AsyncMock(return_value=None)
    get_workspaces = AsyncMock(
        side_effect=[
            [SimpleNamespace(name="1", focused=True), SimpleNamespace(name="3", focused=False)],
            [SimpleNamespace(name="1", focused=False), SimpleNamespace(name="3", focused=True)],
        ]
    )
    service = make_action_service(
        notify_state_change=notify_state_change,
        send_tick_barrier=send_tick_barrier,
    )
    service._get_sway_workspaces = get_workspaces

    result = await service.focus_workspace({"workspace": "3"})

    assert result == {"success": True, "workspace": "3"}
    service._run_sway_command.assert_awaited_once_with("workspace number 3")
    send_tick_barrier.assert_awaited_once_with("i3pm:workspace-focus:3")
    notify_state_change.assert_awaited_once_with("focus_changed")


@pytest.mark.asyncio
async def test_focus_workspace_returns_failure_when_command_fails() -> None:
    service = make_action_service(command_result=[SimpleNamespace(success=False)])

    result = await service.focus_workspace({"workspace": "3"})

    assert result == {
        "success": False,
        "workspace": "3",
        "error": "command_failed:workspace number 3",
    }


@pytest.mark.asyncio
async def test_focus_workspace_requires_sway_connection() -> None:
    service = make_action_service(sway_available=False)

    with pytest.raises(RuntimeError, match="Sway connection is unavailable"):
        await service.focus_workspace_fast({"workspace": "3"})


def test_focus_intent_transitions_pending_to_confirmed() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-8",
        kind="workspace_focus",
        target_key="2",
        created_at=200.0,
        generation=8,
    )

    result = service.finish_focus_intent(
        intent_id="intent-8",
        state="confirmed",
        reason="ok",
    )

    assert service.pending_intent_id == ""
    assert result["state"] == "confirmed"
    assert result["intent_id"] == "intent-8"
    assert result["kind"] == "workspace_focus"
    assert result["target_key"] == "2"
    assert result["reason"] == "ok"


def test_focus_intent_transitions_pending_to_failed() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-9",
        kind="herdr_pane_focus",
        target_key="ryzen:pane-1",
        created_at=300.0,
        generation=9,
    )

    result = service.finish_focus_intent(
        intent_id="intent-9",
        state="failed",
        reason="remote_transport_failed",
    )

    assert service.pending_intent_id == ""
    assert result["state"] == "failed"
    assert result["reason"] == "remote_transport_failed"
