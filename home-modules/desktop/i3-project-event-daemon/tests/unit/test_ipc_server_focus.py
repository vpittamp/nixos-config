"""Unit tests for daemon-owned session/window focus flows."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest


PACKAGE_ROOT = Path(__file__).parent.parent.parent
I3PM_TOOL_ROOT = PACKAGE_ROOT.parent.parent / "tools"

if str(I3PM_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(I3PM_TOOL_ROOT))


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
window_filter_module = importlib.import_module("i3_project_daemon.services.window_filter")
dashboard_model = importlib.import_module("i3_project_daemon.services.dashboard_model")

IPCServer = ipc_server_module.IPCServer
validate_dashboard_payload = dashboard_model.validate_dashboard_payload


class DummyLaunchRegistry:
    def __init__(self):
        self._launches = {}

    def get_stats(self):
        return SimpleNamespace(total_pending=0)

    async def add(self, launch):
        launch_id = f"launch-{len(self._launches) + 1}"
        self._launches[launch_id] = launch
        return launch_id

    async def get_by_terminal_anchor(self, terminal_anchor_id):
        for launch in self._launches.values():
            if str(getattr(launch, "terminal_anchor_id", "") or "").strip() == str(terminal_anchor_id or "").strip():
                return launch
        return None


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

    async def get_window_map_snapshot(self):
        return dict(self.state.window_map)

    async def remove_window(self, _window_id: int):
        return None


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())



@pytest.mark.asyncio
async def test_workspace_focus_waits_for_requested_workspace(server):
    command_mock = AsyncMock(return_value=[SimpleNamespace(success=True, error="")])
    get_workspaces = AsyncMock(side_effect=[
        [SimpleNamespace(name="3", focused=True), SimpleNamespace(name="1", focused=False)],
        [SimpleNamespace(name="1", focused=True), SimpleNamespace(name="3", focused=False)],
    ])
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace(command=command_mock, get_workspaces=get_workspaces))
    server._send_tick_barrier = AsyncMock(return_value=None)

    result = await server._workspace_focus({"workspace": "1"})

    assert result == {"success": True, "workspace": "1"}
    command_mock.assert_awaited_once_with("workspace number 1")
    server._send_tick_barrier.assert_awaited_once_with("i3pm:workspace-focus:1")


@pytest.mark.asyncio
async def test_workspace_focus_returns_failure_when_focus_never_changes(server):
    command_mock = AsyncMock(return_value=[SimpleNamespace(success=True, error="")])
    get_workspaces = AsyncMock(return_value=[SimpleNamespace(name="3", focused=True), SimpleNamespace(name="1", focused=False)])
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace(command=command_mock, get_workspaces=get_workspaces))
    server._send_tick_barrier = AsyncMock(return_value=None)

    result = await server._workspace_focus({"workspace": "1"})

    assert result["success"] is False
    assert result["workspace"] == "1"
    assert result["error"] == "focus_verification_failed:1"


@pytest.mark.asyncio
async def test_workspace_focus_fast_skips_verification_and_notifies(server):
    ipc_command = AsyncMock(return_value=[SimpleNamespace(success=True, error="")])
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace(), ipc_command=ipc_command)
    server._send_tick_barrier = AsyncMock(return_value=None)
    server._wait_for_workspace_focus = AsyncMock(return_value=True)
    server.notify_state_change = AsyncMock(return_value=None)

    result = await server._workspace_focus_fast({"workspace": "1"})

    assert result == {"success": True, "workspace": "1", "fast": True}
    ipc_command.assert_awaited_once_with("workspace number 1")
    server._send_tick_barrier.assert_not_awaited()
    server._wait_for_workspace_focus.assert_not_awaited()
    server.notify_state_change.assert_awaited_once_with("focus_changed")


def test_focus_intent_is_formalized_for_window_focus(server):
    epoch = server._advance_user_intent_epoch(
        method="window.focus_fast",
        params={"window_id": 101},
    )

    focus_intent = server.focus_service.focus_intent_payload()

    assert epoch == 1
    assert focus_intent["intent_id"] == "intent-1"
    assert focus_intent["kind"] == "window_focus"
    assert focus_intent["target_key"] == "101"
    assert focus_intent["state"] == "pending"


def test_focus_intent_finalization_marks_failed_result(server):
    params = {"__intent_epoch": server._advance_user_intent_epoch(
        method="workspace.focus_fast",
        params={"workspace": "9"},
    )}
    result = {
        "success": False,
        "workspace": "9",
        "error": "command_failed:workspace number 9",
    }

    focus_intent = server._finalize_focus_intent_for_result(
        method="workspace.focus_fast",
        params=params,
        result=result,
    )

    assert focus_intent["intent_id"] == "intent-1"
    assert focus_intent["kind"] == "workspace_focus"
    assert focus_intent["target_key"] == "9"
    assert focus_intent["state"] == "failed"
    assert focus_intent["reason"] == "command_failed:workspace number 9"
    assert server.focus_service.pending_intent_id == ""


@pytest.mark.asyncio
async def test_focus_window_remote_handoff_does_not_require_local_sway(server, monkeypatch):
    server.focus_service._connection_target_is_current_host = lambda _connection_key: False
    server.focus_service._remote_daemon_request = AsyncMock(return_value={
        "success": True,
        "reason": "ok",
        "remote_host": "ryzen",
        "result": {
            "success": True,
            "verification": {"success": True, "reason": "ok"},
            "current_session_key_after": "session-remote",
            "focused_window_id_after": 175,
            "focus_state_after": {
                "current_session_key": "session-remote",
                "current_window_id": 175,
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
    server.i3_connection = SimpleNamespace(
        conn=SimpleNamespace(),
        get_tree=AsyncMock(return_value=SimpleNamespace(
            focused=True,
            id=30,
            nodes=[],
            floating_nodes=[],
        )),
    )
    server.focus_service._connection_target_is_current_host = lambda _connection_key: True
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=False)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server.focus_service._get_window_transition_state = AsyncMock(return_value={
        "exists": True,
        "current_workspace": "1",
        "workspace_name": "1",
        "workspace_number": 1,
        "in_scratchpad": False,
        "floating": False,
        "floating_state": "auto_off",
        "fullscreen_mode": 0,
        "saved_state": None,
    })
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_session_key": "session-current",
        "current_window_id": 30,
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
    server._switch_runtime_context_if_needed.assert_awaited_once_with(
        "vpittamp/nixos-config:main",
        "",
        "",
    )


@pytest.mark.asyncio
async def test_focus_window_ssh_target_with_local_window_binding_uses_local_focus(server, monkeypatch):
    server.i3_connection = SimpleNamespace(
        conn=SimpleNamespace(),
        get_tree=AsyncMock(return_value=SimpleNamespace(
            focused=True,
            id=175,
            nodes=[],
            floating_nodes=[],
        )),
    )
    server.focus_service._connection_target_is_current_host = lambda _connection_key: False
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=True)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server.focus_service._get_window_transition_state = AsyncMock(return_value={
        "exists": True,
        "current_workspace": "1",
        "workspace_name": "2",
        "workspace_number": 2,
        "in_scratchpad": False,
        "floating": False,
        "floating_state": "auto_off",
        "fullscreen_mode": 0,
        "saved_state": None,
    })
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_session_key": "session-current",
        "current_window_id": 175,
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
    server._switch_runtime_context_if_needed.assert_awaited_once_with(
        "PittampalliOrg/stacks:main",
        "",
        "",
    )
    assert result["focused_window_id_after"] == 175


@pytest.mark.asyncio
async def test_window_focus_fast_local_target_skips_full_focus_state(server):
    commands = []
    server.i3_connection = SimpleNamespace(
        conn=SimpleNamespace(),
        get_tree=AsyncMock(return_value=SimpleNamespace(
            focused=True,
            id=44,
            nodes=[],
            floating_nodes=[],
        )),
    )
    server.focus_service._connection_target_is_current_host = lambda _connection_key: True
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=True)
    server._send_tick_barrier = AsyncMock(return_value=None)
    server._focus_state = AsyncMock(return_value={})
    server.notify_state_change = AsyncMock(return_value=None)
    server.focus_service._get_window_transition_state = AsyncMock(return_value={
        "exists": True,
        "current_workspace": "1",
        "workspace_name": "1",
        "workspace_number": 1,
        "in_scratchpad": False,
        "floating": False,
        "floating_state": "auto_off",
        "fullscreen_mode": 0,
        "saved_state": None,
    })

    async def ipc_command(cmd):
        commands.append(cmd)
        return [SimpleNamespace(success=True, error="")]

    server.i3_connection.ipc_command = ipc_command

    result = await server._window_focus_fast({
        "window_id": 30,
        "target_variant": "local",
        "connection_key": "local@ryzen",
        "session_key": "session-current",
    })

    assert result["success"] is True
    assert result["fast"] is True
    assert result["direct"] is True
    assert result["window_id"] == 30
    assert len(commands) == 1
    assert commands[0] == "[con_id=30] focus"
    server.focus_service._window_is_locally_tracked.assert_not_awaited()
    server.focus_service._get_window_transition_state.assert_not_awaited()
    server._send_tick_barrier.assert_not_awaited()
    server._focus_state.assert_not_awaited()
    server.notify_state_change.assert_awaited_once_with("focus_changed")


@pytest.mark.asyncio
async def test_window_focus_fast_falls_back_to_transition_when_direct_focus_fails(server):
    commands = []
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace())
    server.focus_service._connection_target_is_current_host = lambda _connection_key: True
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=True)
    server._send_tick_barrier = AsyncMock(return_value=None)
    server._focus_state = AsyncMock(return_value={})
    server.notify_state_change = AsyncMock(return_value=None)
    server.focus_service._get_window_transition_state = AsyncMock(return_value={
        "exists": True,
        "current_workspace": "1",
        "workspace_name": "2",
        "workspace_number": 2,
        "in_scratchpad": False,
        "floating": False,
        "floating_state": "auto_off",
        "fullscreen_mode": 0,
        "saved_state": None,
    })

    async def ipc_command(cmd):
        commands.append(cmd)
        return [SimpleNamespace(success=len(commands) > 1, error="")]

    server.i3_connection.ipc_command = ipc_command

    result = await server._window_focus_fast({
        "window_id": 31,
        "target_variant": "local",
        "connection_key": "local@ryzen",
    })

    assert result["success"] is True
    assert result["fast"] is True
    assert result.get("direct") is not True
    assert commands[0] == "[con_id=31] focus"
    assert commands[1] == "workspace 2; [con_id=31] floating disable; [con_id=31] focus"
    server.focus_service._get_window_transition_state.assert_awaited_once_with(31)
    server.notify_state_change.assert_awaited_once_with("focus_changed")


@pytest.mark.asyncio
async def test_window_focus_fast_rejects_remote_targets(server):
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace(), ipc_command=AsyncMock())
    server.focus_service._connection_target_is_current_host = lambda _connection_key: False
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=False)
    server.focus_service._get_window_transition_state = AsyncMock(return_value={"exists": True})

    result = await server._window_focus_fast({
        "window_id": 175,
        "target_variant": "ssh",
        "connection_key": "vpittamp@ryzen:22",
    })

    assert result["success"] is False
    assert result["reason"] == "remote_target_not_fast_focusable"
    assert result["fallback_method"] == "window.focus"
    server.i3_connection.ipc_command.assert_not_awaited()
    server.focus_service._get_window_transition_state.assert_not_awaited()


@pytest.mark.asyncio
async def test_focus_window_scratchpad_restore_preserves_saved_workspace_and_fullscreen(server):
    commands = []
    server.i3_connection = SimpleNamespace(
        conn=SimpleNamespace(),
        get_tree=AsyncMock(return_value=SimpleNamespace(
            focused=True,
            id=44,
            nodes=[],
            floating_nodes=[],
        )),
    )
    server.focus_service._connection_target_is_current_host = lambda _connection_key: True
    server.focus_service._window_is_locally_tracked = AsyncMock(return_value=True)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    before_restore_state = {
        "exists": True,
        "current_workspace": "1",
        "workspace_name": "__i3_scratch",
        "workspace_number": 0,
        "in_scratchpad": True,
        "floating": True,
        "floating_state": "user_on",
        "fullscreen_mode": 0,
        "saved_state": {
            "workspace_number": 3,
            "floating": False,
            "geometry": None,
            "fullscreen_mode": 1,
            "original_scratchpad": False,
        },
    }
    after_restore_state = {
        **before_restore_state,
        "current_workspace": "3",
        "workspace_name": "3",
        "workspace_number": 3,
        "in_scratchpad": False,
        "floating": False,
        "floating_state": "auto_off",
        "fullscreen_mode": 1,
        "saved_state": None,
    }
    server.focus_service._get_window_transition_state = AsyncMock(side_effect=[
        before_restore_state,
        after_restore_state,
    ])
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_session_key": "",
        "current_window_id": 44,
    })

    async def command(cmd):
        commands.append(cmd)
        return [{"success": True}]

    server.i3_connection.conn.command = command

    result = await server._focus_window_impl(
        window_id=44,
        project_name="vpittamp/nixos-config:main",
        target_variant="local",
        connection_key="local@ryzen",
    )

    assert result["success"] is True
    assert len(commands) == 1
    assert "workspace number 3" in commands[0]
    assert "move workspace number 3" in commands[0]
    assert "fullscreen enable" in commands[0]
    assert "fullscreen disable" not in commands[0]


@pytest.mark.asyncio
async def test_find_context_terminal_window_recovers_context_from_process_env(server, monkeypatch):
    window = SimpleNamespace(
        window_id=44,
        workspace="",
        project="vpittamp/t3code:main",
        context_key="",
        execution_mode="local",
        terminal_role="",
        app_identifier="terminal",
        tmux_session_name="",
        pid=1234,
    )
    server.state_manager.state.window_map[44] = window
    monkeypatch.setattr(
        window_filter_module,
        "read_process_environ_with_fallback",
        lambda pid: {
            "I3PM_PROJECT_NAME": "vpittamp/t3code:main",
            "I3PM_CONTEXT_KEY": "vpittamp/t3code:main::host::ryzen",
            "I3PM_CONTEXT_VARIANT": "ssh",
            "I3PM_TERMINAL_ROLE": "project-main",
            "I3PM_TMUX_SESSION_NAME": "i3pm-vpittamp-t3code-main-f7056320",
            "I3PM_APP_ID": "terminal-vpittamp/t3code:main-1",
            "I3PM_APP_NAME": "terminal",
        },
    )
    monkeypatch.setattr(
        window_filter_module,
        "parse_window_environment",
        lambda _env: SimpleNamespace(
            project_name="vpittamp/t3code:main",
            context_key="vpittamp/t3code:main::host::ryzen",
            terminal_role="project-main",
            tmux_session_name="i3pm-vpittamp-t3code-main-f7056320",
            app_name="terminal",
        ),
    )

    result = server.launch_service.find_context_terminal_window(
        project_name="vpittamp/t3code:main",
        context_key="vpittamp/t3code:main::host::ryzen",
        execution_mode="ssh",
        app_name="terminal",
        terminal_role="project-main",
    )

    assert result is window


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
        "target_host": "ryzen",
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
        "current_session_key": "session-current",
        "focused_window_id": 101,
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
            "pane_id": "pane-1",
        }
    ]
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["schema_version"] == "i3pm.focus_state.v2"
    assert result["current_session_key"] == "session-current"
    assert "current_ai_session_key" not in result
    assert result["current_window_id"] == 101
    assert "focused_window_id" not in result
    assert result["current_herdr_pane_id"] == "pane-1"
    assert result["active_session"]["pane_id"] == "pane-1"
    assert "tmux_session" not in result["active_session"]
    assert "tmux_window" not in result["active_session"]
    assert "tmux_pane" not in result["active_session"]


@pytest.mark.asyncio
async def test_focus_state_clears_verified_remote_override_without_local_ai_focus(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "current_session_key": "",
        "focused_window_id": 404,
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
    server.focus_service.session_override_key = "session-remote-current"
    server.focus_service.set_window_override(window_id=30, connection_key="vpittamp@ryzen:22")
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_session_key"] == ""
    assert result["current_window_id"] == 404
    assert result["active_session"]["session_key"] == ""


@pytest.mark.asyncio
async def test_focus_state_does_not_float_to_remote_session_without_verified_override(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "current_session_key": "",
        "focused_window_id": 404,
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
    ]
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_session_key"] == ""
    assert "current_ai_session_key" not in result
    assert result["active_session"]["session_key"] == ""


@pytest.mark.asyncio
async def test_focus_state_prefers_focused_local_window_over_stale_override(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "current_session_key": "session-local-current",
        "focused_window_id": 101,
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
    server.focus_service.session_override_key = "session-remote-selected"
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._focus_state({})

    assert result["current_session_key"] == "session-local-current"
    assert "current_ai_session_key" not in result
    assert result["active_session"]["host_name"] == "thinkpad"


def test_dashboard_invariants_accept_single_daemon_current_row(server):
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


def test_dashboard_invariants_reject_duplicate_current_rows(server):
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


def test_dashboard_invariants_warn_on_transient_window_focus_rows(server):
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
        "outputs": [
            {
                "workspaces": [
                    {"name": "2", "focused": True},
                ],
            },
        ],
    }

    result = validate_dashboard_payload(payload)

    assert result["ok"] is True
    assert result["issues"] == []
    assert "duplicate_focused_windows" in result["warnings"]
    assert "focused_window_row_mismatch" in result["warnings"]


def test_dashboard_projects_use_authoritative_focused_window_id(server):
    runtime_snapshot = {
        "focused_window_id": 101,
        "active_context": {
            "qualified_name": "global",
            "target_host": "thinkpad",
        },
        "tracked_windows": [
            {
                "window_id": 202,
                "title": "stale focused",
                "app_name": "ghostty",
                "project": "global",
                "workspace": "33",
                "output": "eDP-1",
                "focused": True,
                "visible": True,
                "connection_key": "local@thinkpad",
            },
            {
                "window_id": 101,
                "title": "actual focused",
                "app_name": "chrome",
                "project": "global",
                "workspace": "131",
                "output": "eDP-1",
                "focused": True,
                "visible": True,
                "connection_key": "local@thinkpad",
            },
        ],
    }

    projects = server._build_dashboard_projects(runtime_snapshot, [])
    windows = projects[0]["windows"]

    assert [
        {"id": window["id"], "focused": window["focused"], "is_current_window": window["is_current_window"]}
        for window in windows
    ] == [
        {"id": 202, "focused": False, "is_current_window": False},
        {"id": 101, "focused": True, "is_current_window": True},
    ]


def test_dashboard_invariants_reject_remote_herdr_focus_mismatch(server):
    payload = {
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-local",
            "current_window_id": 101,
        },
        "current_session_key": "session-local",
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
