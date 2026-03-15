"""Unit tests for daemon-owned session/window focus flows."""

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


@pytest.mark.asyncio
async def test_session_focus_remote_handoff_uses_remote_daemon_request(server, monkeypatch):
    remote_session = {
        "session_key": "session-remote",
        "window_id": 0,
        "focus_mode": "remote_handoff",
        "focus_connection_key": "vpittamp@ryzen:22",
        "connection_key": "local@ryzen",
        "surface_key": "surface-remote",
        "conflict_state": "",
    }
    server._session_list = AsyncMock(return_value={"sessions": [remote_session]})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)
    monkeypatch.setattr(server, "_remote_daemon_request", lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "remote_host": "ryzen",
        "result": {
            "success": True,
            "tmux": {"success": True, "reason": "ok"},
            "verification": {"success": True, "reason": "ok"},
            "current_ai_session_key_after": "session-remote",
            "focused_window_id_after": 30,
            "focus_state_after": {
                "current_ai_session_key": "session-remote",
                "focused_window_id": 30,
            },
        },
    })

    result = await server._session_focus({"session_key": "session-remote"})

    assert result["success"] is True
    assert result["focus_mode"] == "remote_handoff"
    assert result["focus_target_host"] == "ryzen"
    assert result["verification"]["success"] is True
    assert result["current_ai_session_key_after"] == "session-remote"
    assert result["focused_window_id_after"] == 30


@pytest.mark.asyncio
async def test_session_focus_local_requires_verified_current_session(server, monkeypatch):
    local_session = {
        "session_key": "session-local",
        "window_id": 101,
        "focus_mode": "local",
        "focus_project": "vpittamp/nixos-config:main",
        "focus_execution_mode": "local",
        "focus_connection_key": "local@thinkpad",
        "connection_key": "local@thinkpad",
        "surface_key": "surface-local",
        "conflict_state": "",
        "terminal_context": {},
    }
    first_list = {"sessions": [dict(local_session)]}
    second_list = {"sessions": [dict(local_session, is_current_window=False)]}
    server._session_list = AsyncMock(side_effect=[first_list] + [second_list] * 8)
    server._window_focus = AsyncMock(return_value={"success": True, "verification": {"success": True}})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "",
        "focused_window_id": 101,
    })
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)

    result = await server._session_focus({"session_key": "session-local"})

    assert result["success"] is False
    assert result["verification"]["reason"] == "current_session_mismatch"


@pytest.mark.asyncio
async def test_session_focus_window_only_identity_sets_override_before_wait(server, monkeypatch):
    local_session = {
        "session_key": "session-window-only",
        "window_id": 146,
        "focus_mode": "local",
        "focus_project": "PittampalliOrg/workflow-builder:main",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@ryzen:22",
        "connection_key": "vpittamp@ryzen:22",
        "surface_key": "surface-window-only",
        "conflict_state": "",
        "terminal_context": {},
        "tmux_session": "",
        "tmux_window": "",
        "tmux_pane": "",
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(local_session)]})
    server._window_focus = AsyncMock(return_value={"success": True, "verification": {"success": True}})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)

    async def fake_wait(session_key, *, attempts=8, delay_s=0.2):
        assert session_key == "session-window-only"
        assert server._focus_session_override_key == "session-window-only"
        assert server._focus_window_override["window_id"] == 146
        return {
            "success": True,
            "reason": "ok",
            "session_key": session_key,
            "current_session_key": session_key,
        }

    server._wait_for_session_focus = AsyncMock(side_effect=fake_wait)
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-window-only",
        "focused_window_id": 146,
    })

    result = await server._session_focus({"session_key": "session-window-only"})

    assert result["success"] is True
    assert result["verification"]["success"] is True
    assert result["current_ai_session_key_after"] == "session-window-only"


@pytest.mark.asyncio
async def test_focus_window_remote_handoff_does_not_require_local_sway(server, monkeypatch):
    server._connection_target_is_current_host = lambda _connection_key: False
    monkeypatch.setattr(server, "_remote_daemon_request", lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "remote_host": "ryzen",
        "result": {
            "success": True,
            "verification": {"success": True, "reason": "ok"},
            "current_ai_session_key_after": "session-remote",
            "focused_window_id_after": 175,
            "focus_state_after": {
                "current_ai_session_key": "session-remote",
                "focused_window_id": 175,
            },
        },
    })

    result = await server._focus_window_impl(
        window_id=175,
        project_name="PittampalliOrg/stacks:main",
        target_variant="ssh",
        connection_key="vpittamp@ryzen:22",
    )

    assert result["success"] is True
    assert result["focus_target_host"] == "ryzen"
    assert result["verification"]["success"] is True
    assert result["focused_window_id_after"] == 175


@pytest.mark.asyncio
async def test_focus_window_ssh_context_on_current_host_uses_local_focus(server, monkeypatch):
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace())
    server._connection_target_is_current_host = lambda _connection_key: True
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server._is_window_in_regular_state = AsyncMock(return_value=True)
    server._verify_window_focus = AsyncMock(return_value={"success": True, "reason": "ok"})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-current",
        "focused_window_id": 30,
    })
    server._remote_daemon_request = lambda **_kwargs: (_ for _ in ()).throw(AssertionError("unexpected remote handoff"))

    async def command(_cmd):
        return [{"success": True}]

    server.i3_connection.conn.command = command

    result = await server._focus_window_impl(
        window_id=30,
        project_name="vpittamp/nixos-config:main",
        target_variant="ssh",
        connection_key="vpittamp@ryzen:22",
    )

    assert result["success"] is True
    assert result["target_variant"] == "ssh"
    assert result["verification"]["success"] is True
    assert result["focused_window_id_after"] == 30


@pytest.mark.asyncio
async def test_focus_window_ssh_target_with_local_window_binding_uses_local_focus(server, monkeypatch):
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace())
    server._connection_target_is_current_host = lambda _connection_key: False
    server._window_is_locally_tracked = AsyncMock(return_value=True)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server._is_window_in_regular_state = AsyncMock(return_value=True)
    server._verify_window_focus = AsyncMock(return_value={"success": True, "reason": "ok"})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-current",
        "focused_window_id": 175,
    })
    server._remote_daemon_request = lambda **_kwargs: (_ for _ in ()).throw(AssertionError("unexpected remote handoff"))

    async def command(_cmd):
        return [{"success": True}]

    server.i3_connection.conn.command = command

    result = await server._focus_window_impl(
        window_id=175,
        project_name="PittampalliOrg/stacks:main",
        target_variant="ssh",
        connection_key="vpittamp@ryzen:22",
    )

    assert result["success"] is True
    assert result["target_variant"] == "ssh"
    assert result["verification"]["success"] is True
    assert result["focused_window_id_after"] == 175


@pytest.mark.asyncio
async def test_session_focus_tmux_target_uses_tmux_verification(server, monkeypatch):
    local_session = {
        "session_key": "session-local-pane",
        "window_id": 101,
        "focus_mode": "local",
        "focus_project": "vpittamp/nixos-config:main",
        "focus_execution_mode": "local",
        "focus_connection_key": "local@ryzen",
        "connection_key": "local@ryzen",
        "surface_key": "surface-local-pane",
        "conflict_state": "",
        "execution_mode": "local",
        "tmux_session": "i3pm-vpittamp-nixos-config-ma-83466f26",
        "tmux_window": "1:codex-raw",
        "tmux_pane": "%1",
        "terminal_context": {},
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(local_session)]})
    server._window_focus = AsyncMock(return_value={"success": True, "verification": {"success": True}})
    server._select_tmux_target = lambda **_kwargs: {"success": True, "reason": "ok", "stderr": ""}
    server._verify_tmux_target = lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "active_tmux_pane": "%1",
        "tmux_pane": "%1",
    }
    server._wait_for_session_focus = AsyncMock(return_value={"success": False, "reason": "should_not_run"})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-local-pane",
        "focused_window_id": 101,
    })
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)

    result = await server._session_focus({"session_key": "session-local-pane"})

    assert result["success"] is True
    assert result["verification"]["verification_source"] == "tmux"
    assert result["verification"]["success"] is True
    assert result["current_ai_session_key_after"] == "session-local-pane"


@pytest.mark.asyncio
async def test_select_tmux_target_uses_local_socket_for_current_host_ssh_context(server, monkeypatch):
    commands = []

    class _Result:
        def __init__(self):
            self.returncode = 0
            self.stdout = ""
            self.stderr = ""

    server._connection_target_is_current_host = lambda _connection_key: True

    def fake_run(args, **_kwargs):
        commands.append(args)
        return _Result()

    monkeypatch.setattr(ipc_server_module.subprocess, "run", fake_run)

    result = server._select_tmux_target(
        execution_mode="ssh",
        tmux_session="i3pm-test",
        tmux_window="1:codex-raw",
        tmux_pane="%3",
        remote_target="vpittamp@ryzen:22",
        connection_key="vpittamp@ryzen:22",
        tmux_socket="/tmp/tmux-1000/default",
    )

    assert result["success"] is True
    assert commands == [[
        "bash",
        "-lc",
        "tmux -S /tmp/tmux-1000/default select-window -t i3pm-test:1 >/dev/null 2>&1 && tmux -S /tmp/tmux-1000/default select-pane -t %3 >/dev/null 2>&1",
    ]]


@pytest.mark.asyncio
async def test_switch_runtime_context_requires_connection_key_match(server):
    server._context_get_active = AsyncMock(return_value={
        "qualified_name": "PittampalliOrg/stacks:main",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@thinkstation:22",
    })
    server._worktree_switch = AsyncMock()
    server._send_tick_barrier = AsyncMock()

    switched_context = {
        "qualified_name": "PittampalliOrg/stacks:main",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
    }
    server._context_get_active = AsyncMock(side_effect=[
        {
            "qualified_name": "PittampalliOrg/stacks:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@thinkstation:22",
        },
        switched_context,
    ])
    server._worktree_switch = AsyncMock(return_value={"success": True})

    result = await server._switch_runtime_context_if_needed(
        "PittampalliOrg/stacks:main",
        "ssh",
        "vpittamp@ryzen:22",
    )

    assert result["switched"] is True
    server._worktree_switch.assert_awaited_once_with({
        "qualified_name": "PittampalliOrg/stacks:main",
        "prefer_local": False,
    })
    assert result["context"]["connection_key"] == "vpittamp@ryzen:22"


@pytest.mark.asyncio
async def test_focus_state_reports_current_session_and_window(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [
            {"id": 101, "window_id": 101, "focused": True},
        ],
    }
    sessions = [
        {
            "session_key": "session-current",
            "window_id": 101,
            "window_active": True,
            "pane_active": True,
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "focus_connection_key": "local@thinkpad",
            "host_name": "thinkpad",
            "is_current_host": True,
            "tmux_session": "i3pm-test",
            "tmux_window": "0:main",
            "tmux_pane": "%1",
        }
    ]
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_ai_session_key"] == "session-current"
    assert result["focused_window_id"] == 101
    assert result["active_session"]["tmux_pane"] == "%1"


@pytest.mark.asyncio
async def test_focus_state_uses_unique_remote_active_session_without_local_ai_focus(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [
            {"id": 404, "window_id": 404, "focused": True},
        ],
    }
    sessions = [
        {
            "session_key": "session-remote-current",
            "window_id": 30,
            "window_active": True,
            "pane_active": True,
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@ryzen",
            "focus_connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
            "is_current_host": False,
            "tmux_session": "i3pm-test-remote",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        {
            "session_key": "session-remote-background",
            "window_id": 31,
            "window_active": False,
            "pane_active": False,
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "focus_connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
            "is_current_host": False,
            "tmux_session": "i3pm-test-remote",
            "tmux_window": "1:aux",
            "tmux_pane": "%1",
        },
    ]
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_ai_session_key"] == "session-remote-current"
    assert result["focused_window_id"] == 404
    assert result["active_session"]["host_name"] == "ryzen"


@pytest.mark.asyncio
async def test_focus_state_prefers_focused_local_window_over_stale_override(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [
            {"id": 101, "window_id": 101, "focused": True},
        ],
    }
    sessions = [
        {
            "session_key": "session-local-current",
            "window_id": 101,
            "window_active": True,
            "pane_active": True,
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "focus_connection_key": "local@thinkpad",
            "host_name": "thinkpad",
            "is_current_host": True,
        },
        {
            "session_key": "session-remote-selected",
            "window_id": 30,
            "window_active": True,
            "pane_active": True,
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@ryzen",
            "focus_connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
            "is_current_host": False,
        },
    ]
    server._focus_session_override_key = "session-remote-selected"
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._focus_state({})

    assert result["current_ai_session_key"] == "session-local-current"
    assert result["active_session"]["host_name"] == "thinkpad"
