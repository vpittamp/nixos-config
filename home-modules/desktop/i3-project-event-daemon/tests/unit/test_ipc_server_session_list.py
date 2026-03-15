"""Unit tests for daemon-owned AI session list field propagation."""

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


ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")

IPCServer = ipc_server_module.IPCServer


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
    }


def make_local_payload():
    return {
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
                "native_session_id": "native-1",
                "session_id": "session-1",
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


@pytest.mark.asyncio
async def test_session_list_preserves_turn_owner_and_activity_substate(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    local_payload = make_local_payload()

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    def fake_load_json_file(path):
        path_str = str(path)
        if path_str.endswith("otel-ai-sessions.json"):
            return local_payload
        if path_str.endswith("remote-otel-sink.json"):
            return {"sources": {}}
        return {}

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
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


@pytest.mark.asyncio
async def test_remote_local_session_uses_ssh_attach_focus_mode(server, monkeypatch):
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
    local_payload = {"sessions": []}
    remote_payload = {
        "sources": {
            "vpittamp@thinkpad:22": {
                "host_name": "thinkpad",
                "received_at": 0,
                "sessions": [
                    {
                        "tool": "codex",
                        "project_name": "vpittamp/nixos-config:main",
                        "project": "vpittamp/nixos-config:main",
                        "display_project": "vpittamp/nixos-config:main",
                        "surface_kind": "tmux-pane",
                        "pane_label": "main",
                        "updated_at": "2026-03-14T15:00:00Z",
                        "stage": "idle",
                        "stage_rank": 0,
                        "stage_label": "Idle",
                        "stage_class": "idle",
                        "stage_visual_state": "idle",
                        "needs_user_action": False,
                        "output_ready": False,
                        "output_unseen": False,
                        "review_pending": False,
                        "session_phase": "idle",
                        "session_phase_label": "Idle",
                        "turn_owner": "user",
                        "turn_owner_label": "User",
                        "activity_substate": "idle",
                        "activity_substate_label": "Idle",
                        "is_streaming": False,
                        "pending_tools": 0,
                        "identity_source": "pane",
                        "native_session_id": "remote-native-1",
                        "session_id": "remote-session-1",
                        "trace_id": "remote-trace-1",
                        "pid": 54321,
                        "process_running": True,
                        "pulse_working": False,
                        "last_activity_at": "2026-03-14T15:00:00Z",
                        "activity_age_seconds": 1,
                        "activity_age_label": "now",
                        "activity_freshness": "fresh",
                        "status_reason": "remote",
                        "terminal_context": {
                            "window_id": 30,
                            "terminal_anchor_id": "remote-anchor",
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
                ],
            }
        }
    }

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

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["connection_key"] == "local@thinkpad"
    assert session["focus_connection_key"] == "vpittamp@thinkpad:22"
    assert session["focus_mode"] == "ssh_attach"


@pytest.mark.asyncio
async def test_remote_ssh_session_bound_to_local_window_uses_local_focus(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["tracked_windows"][0].update({
        "id": 175,
        "window_id": 175,
        "project": "PittampalliOrg/stacks:main",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
        "terminal_anchor_id": "remote-ssh-anchor",
        "focused": False,
    })
    local_payload = {"sessions": []}
    remote_payload = {
        "sources": {
            "vpittamp@ryzen:22": {
                "host_name": "ryzen",
                "received_at": 0,
                "sessions": [
                    {
                        "tool": "codex",
                        "project_name": "PittampalliOrg/stacks:main",
                        "project": "PittampalliOrg/stacks:main",
                        "display_project": "PittampalliOrg/stacks:main",
                        "surface_kind": "terminal-window",
                        "pane_label": "main",
                        "updated_at": "2026-03-14T15:00:00Z",
                        "stage": "idle",
                        "stage_rank": 0,
                        "stage_label": "Idle",
                        "stage_class": "idle",
                        "stage_visual_state": "idle",
                        "needs_user_action": False,
                        "output_ready": False,
                        "output_unseen": False,
                        "review_pending": False,
                        "session_phase": "idle",
                        "session_phase_label": "Idle",
                        "turn_owner": "user",
                        "turn_owner_label": "User",
                        "activity_substate": "idle",
                        "activity_substate_label": "Idle",
                        "is_streaming": False,
                        "pending_tools": 0,
                        "identity_source": "pane",
                        "native_session_id": "remote-ssh-native",
                        "session_id": "remote-ssh-session",
                        "trace_id": "remote-ssh-trace",
                        "pid": 54321,
                        "process_running": True,
                        "pulse_working": False,
                        "last_activity_at": "2026-03-14T15:00:00Z",
                        "activity_age_seconds": 1,
                        "activity_age_label": "now",
                        "activity_freshness": "fresh",
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
                            "window_active": True,
                        },
                    }
                ],
            }
        }
    }

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

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["window_id"] == 175
    assert session["is_current_host"] is True
    assert session["focus_mode"] == "local"


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
    local_payload = {"sessions": []}
    remote_payload = {
        "sources": {
            "local@thinkpad": {
                "host_name": "thinkpad",
                "received_at": 0,
                "sessions": [
                    {
                        "tool": "codex",
                        "project_name": "vpittamp/nixos-config:main",
                        "project": "vpittamp/nixos-config:main",
                        "display_project": "vpittamp/nixos-config:main",
                        "surface_kind": "tmux-pane",
                        "surface_key": "surface-remote",
                        "pane_label": "main",
                        "updated_at": "2026-03-14T15:00:00Z",
                        "stage": "idle",
                        "stage_rank": 0,
                        "stage_label": "Idle",
                        "session_phase": "idle",
                        "session_phase_label": "Idle",
                        "turn_owner": "user",
                        "turn_owner_label": "User",
                        "activity_substate": "idle",
                        "activity_substate_label": "Idle",
                        "identity_source": "pane",
                        "native_session_id": "remote-native-1",
                        "session_id": "remote-session-1",
                        "terminal_context": {
                            "execution_mode": "local",
                            "connection_key": "local@thinkpad",
                            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                            "host_name": "thinkpad",
                            "tmux_session": "i3pm-nixos-config-main",
                            "tmux_window": "0:main",
                            "tmux_pane": "%0",
                        },
                    }
                ],
            }
        }
    }

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

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["window_id"] == 211
    assert session["focus_mode"] == "ssh_attach"
    assert session["focus_execution_mode"] == "ssh"
    assert session["focus_connection_key"] == "vpittamp@thinkpad:22"


@pytest.mark.asyncio
async def test_session_list_refreshes_current_host_tmux_focus_state(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    local_payload = {
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
                "native_session_id": "native-main",
                "session_id": "session-main",
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
                "native_session_id": "native-raw",
                "session_id": "session-raw",
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

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

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

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_load_json_file", fake_load_json_file)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_load_live_tmux_focus_state", fake_tmux_focus)

    result = await server._session_list({})

    assert result["total"] == 2
    sessions_by_pane = {
        session["tmux_pane"]: session
        for session in result["sessions"]
    }
    assert sessions_by_pane["%0"]["window_active"] is True
    assert sessions_by_pane["%1"]["window_active"] is True
    assert sessions_by_pane["%0"]["pane_active"] is False
    assert sessions_by_pane["%1"]["pane_active"] is True
    assert sessions_by_pane["%1"]["is_current_window"] is True
    assert sessions_by_pane["%0"]["is_current_window"] is False


@pytest.mark.asyncio
async def test_dashboard_snapshot_marks_remote_window_focused_from_current_session(server, monkeypatch):
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
    }
    sessions = [
        {
            "session_key": "session-remote-current",
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

    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    server._display_snapshot = AsyncMock(return_value={"outputs": []})
    server._build_dashboard_worktrees = AsyncMock(return_value=[])
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._dashboard_snapshot({})

    assert result["current_ai_session_key"] == "session-remote-current"
    window = result["projects"][0]["windows"][0]
    assert window["focused"] is True
    assert window["visible"] is True
    assert window["hidden"] is False
