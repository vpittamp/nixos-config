"""Unit tests for daemon-owned AI session list field propagation."""

from __future__ import annotations

import copy
import importlib
import importlib.util
import sys
import time
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


ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")
models_module = importlib.import_module("i3_project_daemon.models")

IPCServer = ipc_server_module.IPCServer
WindowInfo = models_module.WindowInfo


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self):
        self.state = SimpleNamespace(
            active_project="global",
            window_map={},
            launch_registry=DummyLaunchRegistry(),
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def make_runtime_snapshot():
    return {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "tracked_windows": [
            {
                "id": 101,
                "window_id": 101,
                "project": "vpittamp/nixos-config:main",
                "execution_mode": "local",
                "connection_key": "local@thinkpad",
                "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                "terminal_anchor_id": "terminal-anchor",
                "focused": True,
                "hidden": False,
            }
        ],
        "sessions": [],
        "current_ai_session_key": "",
        "focused_window_id": 101,
    }


def make_runtime_session(overrides: dict | None = None) -> dict:
    session = {
        "session_key": "session-1",
        "render_session_key": "session-1",
        "surface_key": "surface-local-1",
        "tool": "codex",
        "project_name": "vpittamp/nixos-config:main",
        "project": "vpittamp/nixos-config:main",
        "display_project": "vpittamp/nixos-config:main",
        "window_project": "vpittamp/nixos-config:main",
        "focus_project": "vpittamp/nixos-config:main",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        "focus_execution_mode": "local",
        "focus_connection_key": "local@thinkpad",
        "host_name": "thinkpad",
        "window_id": 101,
        "terminal_anchor_id": "terminal-anchor",
        "pane_label": "main",
        "session_phase": "working",
        "session_phase_label": "Working",
        "turn_owner": "llm",
        "turn_owner_label": "LLM",
        "activity_substate": "thinking",
        "activity_substate_label": "Thinking",
        "status_reason": "event:codex.websocket_event",
        "availability_state": "remote_bridge_bound",
        "focusability_reason": "exact_remote_bridge_bound",
        "focus_mode": "remote_bridge_bound",
        "is_current_host": True,
        "is_current_window": True,
        "window_active": True,
        "pane_active": True,
        "focusable": True,
        "identity_phase": "canonical",
        "native_session_id": "native-1",
        "session_id": "session-1",
        "process_running": True,
        "activity_age_seconds": 1,
        "activity_freshness": "fresh",
        "focus_target": {
            "method": "session.focus",
            "params": {"session_key": "session-1"},
        },
        "terminal_context": {
            "window_id": 101,
            "terminal_anchor_id": "terminal-anchor",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "host_name": "thinkpad",
            "pane_title": "main",
            "pane_active": True,
            "window_active": True,
            "tmux_session": "i3pm-vpittamp-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        "tmux_session": "i3pm-vpittamp-nixos-config-main",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
    }
    if not overrides:
        return session
    merged = copy.deepcopy(session)
    overrides = copy.deepcopy(overrides)
    terminal_context_overrides = overrides.pop("terminal_context", None)
    merged.update(overrides)
    if isinstance(terminal_context_overrides, dict):
        merged_terminal_context = dict(merged.get("terminal_context") or {})
        merged_terminal_context.update(terminal_context_overrides)
        merged["terminal_context"] = merged_terminal_context
    focus_target = merged.get("focus_target")
    if isinstance(focus_target, dict):
        params = dict(focus_target.get("params") or {})
        params["session_key"] = str(merged.get("session_key") or "")
        focus_target["params"] = params
    return merged


@pytest.mark.asyncio
async def test_runtime_snapshot_keeps_transient_unbound_window_visible(server, monkeypatch):
    tracked_window = WindowInfo(
        window_id=101,
        con_id=101,
        window_class="com.mitchellh.ghostty",
        window_title="Ghostty",
        window_instance="ghostty",
        app_identifier="terminal",
        project="vpittamp/nixos-config:main",
        marks=["scoped:terminal:vpittamp/nixos-config:main:101"],
        scope="scoped",
        workspace="1",
        output="eDP-1",
        binding_state="transient_unbound",
        last_workspace="1",
        last_output="eDP-1",
    )

    async def fake_context_get_active(_params):
        return {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        }

    async def fake_window_map_snapshot():
        return {101: tracked_window}

    server._get_window_tree = AsyncMock(return_value={
        "outputs": [
            {
                "name": "eDP-1",
                "active": True,
                "primary": True,
                "geometry": {},
                "current_workspace": "1",
                "workspaces": [
                    {
                        "number": 1,
                        "name": "1",
                        "focused": True,
                        "visible": True,
                        "output": "eDP-1",
                        "windows": [],
                    }
                ],
            }
        ],
        "total_windows": 0,
        "cached": False,
    })
    monkeypatch.setattr(server, "_context_get_active", fake_context_get_active)
    monkeypatch.setattr(server.state_manager, "get_window_map_snapshot", fake_window_map_snapshot, raising=False)
    monkeypatch.setattr(server, "_get_reusable_context_terminal_window", AsyncMock(return_value=None))
    monkeypatch.setattr(server, "_get_launch_stats", AsyncMock(return_value={}))

    snapshot = await server._runtime_snapshot({})

    assert snapshot["total_windows"] == 1
    assert snapshot["tracked_windows"][0]["binding_state"] == "transient_unbound"
    assert snapshot["tracked_windows"][0]["visible"] is True
    assert snapshot["tracked_windows"][0]["hidden"] is False
    assert snapshot["tracked_windows"][0]["workspace"] == "1"
    assert snapshot["outputs"][0]["workspaces"][0]["windows"][0]["id"] == 101
    assert snapshot["outputs"][0]["workspaces"][0]["windows"][0]["binding_state"] == "transient_unbound"


def make_local_payload():
    return {
        "schema_version": "11",
        "sessions": [
            {
                "tool": "codex",
                "project_name": "vpittamp/nixos-config:main",
                "project": "vpittamp/nixos-config:main",
                "display_project": "vpittamp/nixos-config:main",
                "surface_kind": "terminal-window",
                "pane_label": "main",
                "updated_at": "2026-03-14T15:00:00Z",
                "stage": "thinking",
                "stage_rank": 50,
                "stage_label": "Thinking",
                "stage_class": "working",
                "stage_visual_state": "working",
                "needs_user_action": False,
                "output_ready": False,
                "output_unseen": False,
                "llm_stopped": False,
                "terminal_state": "",
                "terminal_state_at": "",
                "terminal_state_label": "",
                "terminal_state_source": "",
                "review_pending": False,
                "session_phase": "working",
                "session_phase_label": "Working",
                "turn_owner": "llm",
                "turn_owner_label": "LLM",
                "activity_substate": "thinking",
                "activity_substate_label": "Thinking",
                "is_streaming": False,
                "pending_tools": 0,
                "identity_source": "pane",
                "identity_phase": "canonical",
                "native_session_id": "native-1",
                "session_id": "session-1",
                "context_fingerprint": "abc123def456",
                "trace_id": "trace-1",
                "pid": 12345,
                "process_running": True,
                "pulse_working": True,
                "last_activity_at": "2026-03-14T15:00:00Z",
                "activity_age_seconds": 1,
                "activity_age_label": "now",
                "activity_freshness": "fresh",
                "status_reason": "event:codex.websocket_event",
                "terminal_context": {
                    "window_id": 101,
                    "terminal_anchor_id": "terminal-anchor",
                    "execution_mode": "local",
                    "connection_key": "local@thinkpad",
                    "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                    "host_name": "thinkpad",
                    "pane_title": "main",
                    "pane_active": True,
                    "window_active": True,
                    "tmux_session": "i3pm-vpittamp-nixos-config-main",
                    "tmux_window": "0:main",
                    "tmux_pane": "%0",
                },
            }
        ]
    }


def test_select_current_session_key_ignores_stale_override_when_focus_moves_windows(server):
    server._set_focus_overrides(
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

    current_session_key = server._select_current_session_key(
        sessions,
        focused_window_id=146,
    )

    assert current_session_key == "session-new"
    assert server._focus_session_override_key == ""


def test_select_current_session_key_clears_override_when_focus_moves_to_non_session_window(server):
    server._set_focus_overrides(
        session_key="session-remote",
        window_id=29,
        connection_key="vpittamp@ryzen:22",
    )
    sessions = [
        {
            "session_key": "session-remote",
            "window_id": 29,
            "is_current_host": True,
            "window_active": False,
            "pane_active": True,
        }
    ]

    current_session_key = server._select_current_session_key(
        sessions,
        focused_window_id=32,
    )

    assert current_session_key == ""
    assert server._focus_session_override_key == ""
    assert server._focus_window_override == {"window_id": 0, "connection_key": ""}


def test_select_current_session_key_preserves_override_when_focused_window_still_matches(server):
    server._set_focus_overrides(
        session_key="session-remote",
        window_id=29,
        connection_key="vpittamp@ryzen:22",
    )
    sessions = [
        {
            "session_key": "session-remote",
            "window_id": 31,
            "is_current_host": True,
            "window_active": False,
            "pane_active": False,
        }
    ]

    current_session_key = server._select_current_session_key(
        sessions,
        focused_window_id=29,
    )

    assert current_session_key == "session-remote"
    assert server._focus_session_override_key == "session-remote"


@pytest.mark.asyncio
async def test_session_list_preserves_turn_owner_and_activity_substate(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    session = make_runtime_session()
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_ai_session_key"] = session["session_key"]

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["session_phase"] == "working"
    assert session["turn_owner"] == "llm"
    assert session["turn_owner_label"] == "LLM"
    assert session["activity_substate"] == "thinking"
    assert session["activity_substate_label"] == "Thinking"
    assert session["is_current_window"] is True
    assert session["focus_target"]["method"] == "session.focus"
    assert result["current_session_key"] == session["session_key"]
    assert session["availability_state"] == "remote_bridge_bound"
    assert session["focusability_reason"] == "exact_remote_bridge_bound"


@pytest.mark.asyncio
async def test_session_list_preserves_explicit_stopped_phase(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    session = make_runtime_session({
        "stage": "output_ready",
        "stage_rank": 1,
        "stage_label": "Ready",
        "stage_class": "stage-output_ready",
        "stage_visual_state": "completed",
        "output_ready": True,
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-14T15:00:02Z",
        "terminal_state_label": "Stopped",
        "terminal_state_source": "codex_notify",
        "provider_stop_signal": "agent-turn-complete",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "output_ready",
        "activity_substate_label": "Ready",
        "status_reason": "event:ag_ui.run_finished",
    })

    async def fake_runtime_snapshot(_params):
        snapshot = copy.deepcopy(runtime_snapshot)
        sessions = [copy.deepcopy(session)]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in snapshot.get("tracked_windows", [])
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = server._select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        server._mark_current_session(sessions, current_session_key=current_session_key)
        server._apply_session_attention_state(
            sessions,
            focused_window_id=focused_window_id,
            current_session_key=current_session_key,
        )
        snapshot["sessions"] = sessions
        snapshot["current_ai_session_key"] = current_session_key
        snapshot["focused_window_id"] = focused_window_id
        return snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["session_phase"] == "stopped"
    assert session["session_phase_label"] == "Stopped"
    assert session["stopped_notification_pending"] is True
    assert session["llm_stopped"] is True
    assert session["terminal_state"] == "explicit_complete"
    assert session["terminal_state_at"] == "2026-03-14T15:00:02Z"
    assert session["terminal_state_label"] == "Stopped"
    assert session["terminal_state_source"] == "codex_notify"
    assert session["provider_stop_signal"] == "agent-turn-complete"


@pytest.mark.asyncio
async def test_session_list_preserves_claude_explicit_stopped_phase(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    session = make_runtime_session({
        "tool": "claude-code",
        "stage": "output_ready",
        "stage_rank": 1,
        "stage_label": "Ready",
        "stage_class": "stage-output_ready",
        "stage_visual_state": "completed",
        "output_ready": True,
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-20T14:22:10Z",
        "terminal_state_label": "Stopped",
        "terminal_state_source": "claude_stop_hook",
        "provider_stop_signal": "Stop",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "output_ready",
        "activity_substate_label": "Ready",
        "status_reason": "event:ag_ui.run_finished",
    })

    async def fake_runtime_snapshot(_params):
        snapshot = copy.deepcopy(runtime_snapshot)
        sessions = [copy.deepcopy(session)]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in snapshot.get("tracked_windows", [])
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = server._select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        server._mark_current_session(sessions, current_session_key=current_session_key)
        server._apply_session_attention_state(
            sessions,
            focused_window_id=focused_window_id,
            current_session_key=current_session_key,
        )
        snapshot["sessions"] = sessions
        snapshot["current_ai_session_key"] = current_session_key
        snapshot["focused_window_id"] = focused_window_id
        return snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["tool"] == "claude-code"
    assert session["session_phase"] == "stopped"
    assert session["session_phase_label"] == "Stopped"
    assert session["stopped_notification_pending"] is True
    assert session["llm_stopped"] is True
    assert session["terminal_state"] == "explicit_complete"
    assert session["terminal_state_at"] == "2026-03-20T14:22:10Z"
    assert session["terminal_state_label"] == "Stopped"
    assert session["terminal_state_source"] == "claude_stop_hook"
    assert session["provider_stop_signal"] == "Stop"


@pytest.mark.asyncio
async def test_session_list_acknowledges_background_stopped_session_on_focus(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            **runtime_snapshot["tracked_windows"][0],
            "focused": False,
        },
        {
            "id": 202,
            "window_id": 202,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "terminal_anchor_id": "other-terminal-anchor",
            "focused": True,
            "hidden": False,
        },
    ]
    session = make_runtime_session({
        "stage": "output_ready",
        "stage_rank": 1,
        "stage_label": "Ready",
        "stage_class": "stage-output_ready",
        "stage_visual_state": "completed",
        "output_ready": True,
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-14T15:00:02Z",
        "terminal_state_label": "Stopped",
        "terminal_state_source": "codex_notify",
        "provider_stop_signal": "agent-turn-complete",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "output_ready",
        "activity_substate_label": "Ready",
        "status_reason": "event:ag_ui.run_finished",
    })

    async def fake_runtime_snapshot(_params):
        snapshot = copy.deepcopy(runtime_snapshot)
        sessions = [copy.deepcopy(session)]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in snapshot.get("tracked_windows", [])
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = server._select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        server._mark_current_session(sessions, current_session_key=current_session_key)
        server._apply_session_attention_state(
            sessions,
            focused_window_id=focused_window_id,
            current_session_key=current_session_key,
        )
        snapshot["sessions"] = sessions
        snapshot["current_ai_session_key"] = current_session_key
        snapshot["focused_window_id"] = focused_window_id
        return snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    initial = await server._session_list({})
    initial_session = initial["sessions"][0]
    assert initial_session["session_phase"] == "stopped"
    assert initial_session["stopped_notification_pending"] is True

    runtime_snapshot["tracked_windows"][0]["focused"] = True
    runtime_snapshot["tracked_windows"][1]["focused"] = False
    acknowledged = await server._session_list({})
    acknowledged_session = acknowledged["sessions"][0]
    assert acknowledged_session["session_phase"] == "done"
    assert acknowledged_session["session_phase_label"] == "Done"
    assert acknowledged_session["stopped_notification_pending"] is False


@pytest.mark.asyncio
async def test_session_list_stopped_current_session_requires_leave_and_return_to_acknowledge(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            **runtime_snapshot["tracked_windows"][0],
            "focused": True,
        },
        {
            "id": 202,
            "window_id": 202,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "terminal_anchor_id": "other-terminal-anchor",
            "focused": False,
            "hidden": False,
        },
    ]
    session = make_runtime_session({
        "stage": "output_ready",
        "stage_rank": 1,
        "stage_label": "Ready",
        "stage_class": "stage-output_ready",
        "stage_visual_state": "completed",
        "output_ready": True,
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-14T15:00:02Z",
        "terminal_state_label": "Stopped",
        "terminal_state_source": "codex_notify",
        "provider_stop_signal": "agent-turn-complete",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "output_ready",
        "activity_substate_label": "Ready",
        "status_reason": "event:ag_ui.run_finished",
    })

    async def fake_runtime_snapshot(_params):
        snapshot = copy.deepcopy(runtime_snapshot)
        sessions = [copy.deepcopy(session)]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in snapshot.get("tracked_windows", [])
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = server._select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        server._mark_current_session(sessions, current_session_key=current_session_key)
        server._apply_session_attention_state(
            sessions,
            focused_window_id=focused_window_id,
            current_session_key=current_session_key,
        )
        snapshot["sessions"] = sessions
        snapshot["current_ai_session_key"] = current_session_key
        snapshot["focused_window_id"] = focused_window_id
        return snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    initial = await server._session_list({})
    initial_session = initial["sessions"][0]
    assert initial_session["session_phase"] == "stopped"
    assert initial_session["stopped_notification_pending"] is True

    runtime_snapshot["tracked_windows"][0]["focused"] = False
    runtime_snapshot["tracked_windows"][1]["focused"] = True
    away = await server._session_list({})
    away_session = away["sessions"][0]
    assert away_session["session_phase"] == "stopped"
    assert away_session["stopped_notification_pending"] is True

    runtime_snapshot["tracked_windows"][0]["focused"] = True
    runtime_snapshot["tracked_windows"][1]["focused"] = False
    returned = await server._session_list({})
    returned_session = returned["sessions"][0]
    assert returned_session["session_phase"] == "done"
    assert returned_session["session_phase_label"] == "Done"
    assert returned_session["stopped_notification_pending"] is False


@pytest.mark.asyncio
async def test_session_list_explicit_focus_acknowledgement_persists_until_new_stop_boundary(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            **runtime_snapshot["tracked_windows"][0],
            "focused": False,
        },
        {
            "id": 202,
            "window_id": 202,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "terminal_anchor_id": "other-terminal-anchor",
            "focused": True,
            "hidden": False,
        },
    ]
    session = make_runtime_session({
        "stage": "output_ready",
        "stage_rank": 1,
        "stage_label": "Ready",
        "stage_class": "stage-output_ready",
        "stage_visual_state": "completed",
        "output_ready": True,
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-21T15:52:47.780000+00:00",
        "terminal_state_label": "Stopped",
        "terminal_state_source": "claude_stop_hook",
        "provider_stop_signal": "run-stopped",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "output_ready",
        "activity_substate_label": "Ready",
        "status_reason": "event:ag_ui.run_finished",
    })

    async def fake_runtime_snapshot(_params):
        snapshot = copy.deepcopy(runtime_snapshot)
        sessions = [copy.deepcopy(session)]
        focused_window_id = next(
            (
                int(window.get("id") or 0)
                for window in snapshot.get("tracked_windows", [])
                if isinstance(window, dict) and bool(window.get("focused", False))
            ),
            0,
        )
        current_session_key = server._select_current_session_key(
            sessions,
            focused_window_id=focused_window_id,
        )
        server._mark_current_session(sessions, current_session_key=current_session_key)
        server._apply_session_attention_state(
            sessions,
            focused_window_id=focused_window_id,
            current_session_key=current_session_key,
        )
        snapshot["sessions"] = sessions
        snapshot["current_ai_session_key"] = current_session_key
        snapshot["focused_window_id"] = focused_window_id
        return snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "thinkpad")

    initial = await server._session_list({})
    initial_session = initial["sessions"][0]
    assert initial_session["session_phase"] == "stopped"
    assert initial_session["stopped_notification_pending"] is True

    assert server._acknowledge_stopped_session_notification(initial_session) is True

    acknowledged = await server._session_list({})
    acknowledged_session = acknowledged["sessions"][0]
    assert acknowledged_session["session_phase"] == "done"
    assert acknowledged_session["session_phase_label"] == "Done"
    assert acknowledged_session["stopped_notification_pending"] is False

    session["terminal_state_at"] = "2026-03-21T16:04:12.000000+00:00"
    newer_boundary = await server._session_list({})
    newer_boundary_session = newer_boundary["sessions"][0]
    assert newer_boundary_session["session_phase"] == "stopped"
    assert newer_boundary_session["session_phase_label"] == "Stopped"
    assert newer_boundary_session["stopped_notification_pending"] is True


@pytest.mark.asyncio
async def test_remote_local_session_uses_exact_remote_bridge_focus_mode(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["active_context"].update({
        "execution_mode": "local",
        "connection_key": "local@ryzen",
    })
    runtime_snapshot["tracked_windows"][0].update({
        "execution_mode": "local",
        "connection_key": "local@ryzen",
        "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
    })
    session = make_runtime_session({
        "session_key": "session-remote-local",
        "render_session_key": "session-remote-local",
        "surface_key": "surface-remote-local",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@thinkpad:22",
        "host_name": "thinkpad",
        "window_id": 0,
        "availability_state": "remote_bridge_attachable",
        "focusability_reason": "exact_remote_tmux_attachable",
        "focus_mode": "remote_bridge_attachable",
        "is_current_host": False,
        "is_current_window": False,
        "window_active": False,
        "pane_active": False,
        "session_phase": "idle",
        "session_phase_label": "Idle",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "idle",
        "activity_substate_label": "Idle",
        "status_reason": "remote",
        "terminal_context": {
            "window_id": 30,
            "terminal_anchor_id": "remote-anchor",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "host_name": "thinkpad",
            "pane_title": "main",
            "pane_active": False,
            "window_active": False,
            "tmux_session": "i3pm-vpittamp-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
    })
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_ai_session_key"] = ""

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["connection_key"] == "local@thinkpad"
    assert session["focus_connection_key"] == "vpittamp@thinkpad:22"
    assert session["focus_mode"] == "remote_bridge_attachable"
    assert session["availability_state"] == "remote_bridge_attachable"
    assert session["focusability_reason"] == "exact_remote_tmux_attachable"


@pytest.mark.asyncio
async def test_remote_ssh_session_bound_to_local_window_uses_remote_bridge_focus(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"][0].update({
        "id": 175,
        "window_id": 175,
        "project": "PittampalliOrg/stacks:main",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "terminal_anchor_id": "remote-ssh-anchor",
        "remote_surface_key": "surface-remote-ssh",
        "remote_session_key": "codex|surface-remote-ssh|PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "remote_tmux_server_key": "/run/user/1000/tmux-1000/default",
        "remote_tmux_session": "i3pm-stacks-main",
        "remote_tmux_window": "0:main",
        "remote_tmux_pane": "%9",
        "focused": False,
    })
    session = make_runtime_session({
        "session_key": "codex|surface-remote-ssh|PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "render_session_key": "codex|surface-remote-ssh|PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "surface_key": "surface-remote-ssh",
        "project_name": "PittampalliOrg/stacks:main",
        "project": "PittampalliOrg/stacks:main",
        "display_project": "PittampalliOrg/stacks:main",
        "window_project": "PittampalliOrg/stacks:main",
        "focus_project": "PittampalliOrg/stacks:main",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@ryzen:22",
        "host_name": "ryzen",
        "window_id": 175,
        "availability_state": "remote_bridge_bound",
        "focusability_reason": "exact_remote_bridge_bound",
        "focus_mode": "remote_bridge_bound",
        "is_current_host": True,
        "is_current_window": False,
        "window_active": False,
        "pane_active": True,
        "session_phase": "idle",
        "session_phase_label": "Idle",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "idle",
        "activity_substate_label": "Idle",
        "status_reason": "remote",
        "terminal_context": {
            "window_id": 175,
            "terminal_anchor_id": "remote-ssh-anchor",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
            "host_name": "ryzen",
            "pane_title": "main",
            "pane_active": True,
            "window_active": False,
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-stacks-main",
            "tmux_window": "0:main",
            "tmux_pane": "%9",
        },
        "tmux_session": "i3pm-stacks-main",
        "tmux_window": "0:main",
        "tmux_pane": "%9",
    })
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_ai_session_key"] = ""

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["window_id"] == 175
    assert session["is_current_host"] is True
    assert session["focus_mode"] == "remote_bridge_bound"


@pytest.mark.asyncio
async def test_remote_session_binds_to_local_bridge_window_by_surface_key(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            "id": 211,
            "window_id": 211,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@thinkpad:22",
            "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@thinkpad:22",
            "terminal_anchor_id": "bridge-anchor",
            "terminal_role": "remote-session:123456789abc",
            "remote_session_key": "codex|surface-remote|vpittamp/nixos-config:main::local::local@thinkpad",
            "remote_surface_key": "surface-remote",
            "focused": False,
            "hidden": False,
        }
    ]
    session = make_runtime_session({
        "session_key": "codex|surface-remote|vpittamp/nixos-config:main::local::local@thinkpad",
        "render_session_key": "codex|surface-remote|vpittamp/nixos-config:main::local::local@thinkpad",
        "surface_key": "surface-remote",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@thinkpad:22",
        "host_name": "thinkpad",
        "window_id": 211,
        "availability_state": "remote_bridge_bound",
        "focusability_reason": "exact_remote_bridge_bound",
        "focus_mode": "remote_bridge_bound",
        "is_current_host": True,
        "is_current_window": False,
        "window_active": False,
        "pane_active": True,
        "session_phase": "idle",
        "session_phase_label": "Idle",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "idle",
        "activity_substate_label": "Idle",
        "terminal_context": {
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "host_name": "thinkpad",
            "tmux_session": "i3pm-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        "tmux_session": "i3pm-nixos-config-main",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
    })
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_ai_session_key"] = ""

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["window_id"] == 211
    assert session["focus_mode"] == "remote_bridge_bound"
    assert session["focus_execution_mode"] == "ssh"
    assert session["focus_connection_key"] == "vpittamp@thinkpad:22"


@pytest.mark.asyncio
async def test_session_list_marks_stale_remote_sources(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@ryzen",
        },
        "tracked_windows": [],
    }
    session = make_runtime_session({
        "session_key": "session-remote-stale",
        "render_session_key": "session-remote-stale",
        "surface_key": "surface-remote-stale",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@thinkpad:22",
        "host_name": "thinkpad",
        "window_id": 0,
        "availability_state": "unavailable",
        "focusability_reason": "stale_remote_source",
        "focus_mode": "unavailable",
        "is_current_host": False,
        "is_current_window": False,
        "window_active": False,
        "pane_active": False,
        "session_phase": "stale_source",
        "session_phase_label": "Stale source",
        "turn_owner": "llm",
        "turn_owner_label": "LLM",
        "activity_substate": "thinking",
        "activity_substate_label": "Thinking",
        "process_running": True,
        "status_reason": "process_keepalive",
        "remote_source_stale": True,
        "terminal_context": {
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "host_name": "thinkpad",
            "terminal_anchor_id": "remote-anchor",
            "tmux_session": "i3pm-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        "tmux_session": "i3pm-nixos-config-main",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
    })
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_ai_session_key"] = ""
    runtime_snapshot["focused_window_id"] = 0

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    session = result["sessions"][0]
    assert session["session_phase"] == "stale_source"
    assert session["session_phase_label"] == "Stale source"
    assert session["focus_mode"] == "unavailable"


@pytest.mark.asyncio
async def test_session_cleanup_closes_stale_remote_bridge_windows(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            "id": 211,
            "window_id": 211,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@thinkpad:22",
            "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@thinkpad:22",
            "terminal_anchor_id": "bridge-anchor",
            "terminal_role": "remote-session:123456789abc",
            "remote_session_key": "session-remote",
            "remote_surface_key": "surface-remote",
            "remote_tmux_server_key": "/tmp/tmux-1000/default",
            "remote_tmux_session": "i3pm-old",
            "remote_tmux_window": "0:main",
            "remote_tmux_pane": "%0",
            "focused": False,
            "hidden": True,
        }
    ]
    local_payload = {"sessions": []}
    remote_payload = {"sources": {}}

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    def fake_load_json_file(path):
        path_str = str(path)
        if path_str.endswith("otel-ai-sessions.json"):
            return local_payload
        if path_str.endswith("remote-otel-sink.json"):
            return remote_payload
        return {}

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")
    server._close_managed_window = AsyncMock(return_value=True)
    server.state_manager.remove_window = AsyncMock()

    result = await server._session_cleanup({})

    assert result["success"] is True
    assert result["cleaned_up"] == 1
    assert result["windows_cleaned"] == [{
        "window_id": 211,
        "closed": True,
        "reason": "missing_remote_session",
    }]
    server._close_managed_window.assert_awaited_once_with(211)
    server.state_manager.remove_window.assert_awaited_once_with(211)


@pytest.mark.asyncio
async def test_session_cleanup_reports_but_does_not_close_stale_remote_source_bridge(server):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            "id": 211,
            "window_id": 211,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@thinkpad:22",
            "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@thinkpad:22",
            "remote_session_key": "session-remote",
            "remote_surface_key": "surface-remote",
            "remote_tmux_server_key": "/tmp/tmux-1000/default",
            "remote_tmux_session": "i3pm-old",
            "remote_tmux_window": "0:main",
            "remote_tmux_pane": "%0",
        }
    ]
    sessions = [{
        "session_key": "session-remote",
        "surface_key": "surface-remote",
        "focus_mode": "remote_bridge_attachable",
        "remote_source_stale": True,
        "terminal_context": {
            "tmux_server_key": "/tmp/tmux-1000/default",
            "tmux_session": "i3pm-old",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        "tmux_session": "i3pm-old",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
    }]
    server._close_managed_window = AsyncMock(return_value=True)
    server.state_manager.remove_window = AsyncMock()

    cleanup = await server._reconcile_session_runtime_state(
        runtime_snapshot,
        sessions,
        close_windows=True,
    )

    assert cleanup["stale_bridge_count"] == 1
    assert cleanup["cleaned_window_count"] == 0
    assert cleanup["stale_bridges"][0]["reason"] == "stale_remote_source"
    server._close_managed_window.assert_not_awaited()
    server.state_manager.remove_window.assert_not_awaited()


@pytest.mark.asyncio
async def test_session_doctor_reports_bridge_diagnostics(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"] = [
        {
            "id": 211,
            "window_id": 211,
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@thinkpad:22",
            "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@thinkpad:22",
            "remote_session_key": "session-remote",
            "remote_surface_key": "surface-remote",
            "remote_tmux_server_key": "/tmp/tmux-1000/default",
            "remote_tmux_session": "i3pm-remote",
            "remote_tmux_window": "0:main",
            "remote_tmux_pane": "%0",
            "focused": False,
            "hidden": True,
        }
    ]
    sessions = [
        {
            "session_key": "session-remote",
            "surface_key": "surface-remote",
            "availability_state": "remote_bridge_bound",
            "focusability_reason": "exact_remote_bridge_bound",
            "focus_mode": "remote_bridge_bound",
            "window_id": 211,
            "is_current_host": True,
            "terminal_context": {
                "tmux_server_key": "/tmp/tmux-1000/default",
                "tmux_session": "i3pm-remote",
                "tmux_window": "0:main",
                "tmux_pane": "%0",
            },
            "tmux_session": "i3pm-remote",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        }
    ]

    runtime_snapshot["sessions"] = sessions
    runtime_snapshot["current_ai_session_key"] = "session-remote"
    runtime_snapshot["focused_window_id"] = 0
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._session_doctor({})

    assert result["success"] is True
    assert result["session_count"] == 1
    assert result["bridge_window_count"] == 1
    assert result["bridge_windows"][0]["matched_session_key"] == "session-remote"
    assert result["bridge_windows"][0]["mismatch_reason"] == ""
    assert result["sessions"][0]["availability_state"] == "remote_bridge_bound"
    assert result["sessions"][0]["focusability_reason"] == "exact_remote_bridge_bound"


def test_load_session_items_refreshes_current_host_tmux_focus_state(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    local_payload = {
        "schema_version": "11",
        "sessions": [
            {
                "tool": "codex",
                "project_name": "vpittamp/nixos-config:main",
                "project": "vpittamp/nixos-config:main",
                "display_project": "vpittamp/nixos-config:main",
                "surface_kind": "tmux-pane",
                "pane_label": "0:main %0",
                "updated_at": "2026-03-14T15:00:00Z",
                "stage": "thinking",
                "stage_rank": 50,
                "stage_label": "Thinking",
                "session_phase": "working",
                "session_phase_label": "Working",
                "turn_owner": "llm",
                "turn_owner_label": "LLM",
                "identity_phase": "canonical",
                "native_session_id": "native-main",
                "session_id": "session-main",
                "context_fingerprint": "f-main",
                "activity_substate": "thinking",
                "activity_substate_label": "Thinking",
                "pending_tools": 0,
                "process_running": True,
                "terminal_context": {
                    "window_id": 101,
                    "terminal_anchor_id": "terminal-anchor",
                    "execution_mode": "local",
                    "connection_key": "local@thinkpad",
                    "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                    "host_name": "thinkpad",
                    "pane_active": True,
                    "window_active": False,
                    "tmux_session": "i3pm-vpittamp-nixos-config-main",
                    "tmux_window": "0:main",
                    "tmux_pane": "%0",
                },
            },
            {
                "tool": "codex",
                "project_name": "vpittamp/nixos-config:main",
                "project": "vpittamp/nixos-config:main",
                "display_project": "vpittamp/nixos-config:main",
                "surface_kind": "tmux-pane",
                "pane_label": "1:codex-raw %1",
                "updated_at": "2026-03-14T15:00:01Z",
                "stage": "thinking",
                "stage_rank": 50,
                "stage_label": "Thinking",
                "session_phase": "working",
                "session_phase_label": "Working",
                "turn_owner": "llm",
                "turn_owner_label": "LLM",
                "identity_phase": "canonical",
                "native_session_id": "native-raw",
                "session_id": "session-raw",
                "context_fingerprint": "f-raw",
                "activity_substate": "thinking",
                "activity_substate_label": "Thinking",
                "pending_tools": 0,
                "process_running": True,
                "terminal_context": {
                    "window_id": 101,
                    "terminal_anchor_id": "terminal-anchor",
                    "execution_mode": "local",
                    "connection_key": "local@thinkpad",
                    "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                    "host_name": "thinkpad",
                    "pane_active": True,
                    "window_active": False,
                    "tmux_session": "i3pm-vpittamp-nixos-config-main",
                    "tmux_window": "1:codex-raw",
                    "tmux_pane": "%1",
                },
            },
        ]
    }

    def fake_load_json_file(path):
        path_str = str(path)
        if path_str.endswith("otel-ai-sessions.json"):
            return local_payload
        if path_str.endswith("remote-otel-sink.json"):
            return {"sources": {}}
        return {}

    def fake_tmux_focus(_tmux_sessions):
        return {
            ("", "i3pm-vpittamp-nixos-config-main", "0:main", "%0"): {
                "pane_active": False,
                "window_active": False,
            },
            ("", "i3pm-vpittamp-nixos-config-main", "1:codex-raw", "%1"): {
                "pane_active": True,
                "window_active": True,
            },
        }

    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_load_live_tmux_focus_state", fake_tmux_focus)

    sessions = server._load_session_items(runtime_snapshot)

    sessions_by_pane = {
        session["tmux_pane"]: session
        for session in sessions
    }
    assert sessions_by_pane["%0"]["window_active"] is True
    assert sessions_by_pane["%1"]["window_active"] is True
    assert sessions_by_pane["%0"]["pane_active"] is False
    assert sessions_by_pane["%1"]["pane_active"] is True


def test_load_session_items_reuses_cache_when_inputs_are_unchanged(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    local_payload = {
        "schema_version": "11",
        "sessions": [make_local_payload()["sessions"][0]],
    }
    load_calls: list[str] = []
    normalize_calls: list[str] = []

    def fake_load_json_file(path):
        path_str = str(path)
        load_calls.append(path_str)
        if path_str.endswith("otel-ai-sessions.json"):
            return local_payload
        if path_str.endswith("remote-otel-sink.json"):
            return {"sources": {}}
        return {}

    original_normalize = server._normalize_session_items

    def fake_normalize_session_items(*args, **kwargs):
        normalize_calls.append("normalize")
        return original_normalize(*args, **kwargs)

    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_load_live_tmux_focus_state", lambda _tmux_sessions: {})
    monkeypatch.setattr(server, "_normalize_session_items", fake_normalize_session_items)

    first = server._load_session_items(runtime_snapshot)
    second = server._load_session_items(runtime_snapshot)

    assert len(first) == len(second) == 1
    assert normalize_calls == ["normalize"]
    assert len(load_calls) == 2


def test_load_session_items_prefers_canonical_identity_on_same_tmux_surface(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    local_payload = {
        "schema_version": "11",
        "sessions": [
            {
                **make_local_payload()["sessions"][0],
                "surface_kind": "tmux-pane",
                "identity_phase": "provisional",
                "canonicalization_blocker": "missing_native_session_id",
                "native_session_id": "native-1",
                "session_id": "codex:pid:12345",
                "context_fingerprint": "",
            },
            {
                **make_local_payload()["sessions"][0],
                "surface_kind": "tmux-pane",
                "identity_phase": "canonical",
                "canonicalization_blocker": "",
                "native_session_id": "native-1",
                "session_id": "codex:native-1:abc123def456",
                "context_fingerprint": "abc123def456",
                "updated_at": "2026-03-14T15:00:02Z",
            },
        ],
    }

    def fake_load_json_file(path):
        path_str = str(path)
        if path_str.endswith("otel-ai-sessions.json"):
            return local_payload
        if path_str.endswith("remote-otel-sink.json"):
            return {"sources": {}}
        return {}

    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_load_live_tmux_focus_state", lambda _tmux_sessions: {})

    sessions = server._load_session_items(runtime_snapshot)

    assert len(sessions) == 1
    assert sessions[0]["identity_phase"] == "canonical"
    assert sessions[0]["canonicalization_blocker"] == ""
    assert sessions[0]["session_id"] == "codex:native-1:abc123def456"


@pytest.mark.asyncio
async def test_dashboard_snapshot_marks_remote_window_focused_from_current_session(server, monkeypatch):
    sessions = [
        {
            "session_key": "session-remote-current",
            "render_session_key": "session-remote-current",
            "window_id": 175,
            "window_active": True,
            "pane_active": True,
            "is_current_window": True,
            "project_name": "PittampalliOrg/stacks:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "focus_connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
            "tool": "codex",
            "pane_label": "main",
            "session_phase": "working",
            "turn_owner": "llm",
            "turn_owner_label": "LLM",
            "activity_substate": "thinking",
            "activity_substate_label": "Thinking",
        },
    ]
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [
            {
                "id": 175,
                "window_id": 175,
                "project": "PittampalliOrg/stacks:main",
                "execution_mode": "ssh",
                "connection_key": "vpittamp@ryzen:22",
                "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
                "focused": False,
                "visible": False,
                "hidden": True,
                "title": "Ghostty",
                "app_key": "ghostty",
                "app_name": "Ghostty",
                "scope": "scoped",
                "workspace": "11:stacks",
                "output": "DP-1",
            },
        ],
        "total_windows": 1,
        "state_health": {},
        "launch_stats": {},
        "scratchpad": {},
        "active_terminal": {},
        "sessions": sessions,
        "current_ai_session_key": "session-remote-current",
        "focused_window_id": 175,
    }

    server._display_snapshot = AsyncMock(return_value={"outputs": []})
    server._build_dashboard_worktrees = AsyncMock(return_value=[])
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._dashboard_snapshot({})

    assert result["current_ai_session_key"] == "session-remote-current"
    window = result["projects"][0]["windows"][0]
    assert window["focused"] is True
    assert window["visible"] is True
    assert window["hidden"] is False
