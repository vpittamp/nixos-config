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
async def test_session_focus_remote_session_uses_exact_remote_bridge_path(server, monkeypatch):
    remote_session = {
        "session_key": "session-remote",
        "window_id": 0,
        "focus_mode": "remote_bridge_attachable",
        "focus_connection_key": "local@thinkpad",
        "connection_key": "local@thinkpad",
        "surface_key": "surface-remote",
        "conflict_state": "",
    }
    server._session_list = AsyncMock(return_value={"sessions": [remote_session]})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)
    server._focus_remote_session_attach = AsyncMock(return_value={
        "success": True,
        "focus_mode": "remote_bridge_bound",
        "focus_target_host": "thinkpad",
        "verification": {"success": True, "reason": "ok"},
        "current_ai_session_key_after": "session-remote",
        "focused_window_id_after": 30,
    })

    result = await server._session_focus({"session_key": "session-remote"})

    assert result["success"] is True
    assert result["focus_mode"] == "remote_bridge_bound"
    assert result["focus_target_host"] == "thinkpad"
    assert result["verification"]["success"] is True
    assert result["current_ai_session_key_after"] == "session-remote"
    assert result["focused_window_id_after"] == 30
    server._focus_remote_session_attach.assert_awaited_once()


@pytest.mark.asyncio
async def test_session_focus_acknowledges_current_stopped_boundary_before_remote_attach(server, monkeypatch):
    remote_session = {
        "session_key": "session-remote-stopped",
        "window_id": 0,
        "focus_mode": "remote_bridge_attachable",
        "focus_connection_key": "vpittamp@ryzen:22",
        "connection_key": "vpittamp@ryzen:22",
        "surface_key": "surface-remote-stopped",
        "conflict_state": "",
        "llm_stopped": True,
        "terminal_state": "explicit_complete",
        "terminal_state_at": "2026-03-21T15:52:47.780000+00:00",
        "session_phase": "stopped",
        "session_phase_label": "Stopped",
        "is_current_window": False,
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(remote_session)]})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)
    server._focus_remote_session_attach = AsyncMock(return_value={
        "success": True,
        "focus_mode": "remote_bridge_bound",
        "focus_target_host": "ryzen",
        "verification": {"success": True, "reason": "ok"},
        "current_ai_session_key_after": "session-remote-stopped",
        "focused_window_id_after": 198,
    })

    result = await server._session_focus({"session_key": "session-remote-stopped"})

    assert result["success"] is True
    assert server._stopped_session_notifications["session-remote-stopped"] == {
        "boundary_key": "2026-03-21T15:52:47.780000+00:00",
        "started_current": False,
        "left_since_boundary": True,
        "acknowledged": True,
    }
    server._focus_remote_session_attach.assert_awaited_once()


@pytest.mark.asyncio
async def test_session_focus_acknowledges_current_user_input_boundary_before_remote_attach(server, monkeypatch):
    remote_session = {
        "session_key": "session-remote-waiting",
        "tool": "claude-code",
        "window_id": 0,
        "focus_mode": "remote_bridge_attachable",
        "focus_connection_key": "vpittamp@ryzen:22",
        "connection_key": "vpittamp@ryzen:22",
        "surface_key": "surface-remote-waiting",
        "conflict_state": "",
        "process_running": True,
        "session_phase": "needs_attention",
        "session_phase_label": "Needs attention",
        "notification_boundary_type": "user_input_required",
        "notification_boundary_reason": "elicitation",
        "notification_boundary_source": "claude_notification",
        "notification_boundary_at": "2026-03-21T19:20:12.000000+00:00",
        "is_current_window": False,
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(remote_session)]})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)
    server._focus_remote_session_attach = AsyncMock(return_value={
        "success": True,
        "focus_mode": "remote_bridge_bound",
        "focus_target_host": "ryzen",
        "verification": {"success": True, "reason": "ok"},
        "current_ai_session_key_after": "session-remote-waiting",
        "focused_window_id_after": 198,
    })

    result = await server._session_focus({"session_key": "session-remote-waiting"})

    assert result["success"] is True
    assert server._user_input_session_notifications["session-remote-waiting"] == {
        "boundary_key": "2026-03-21T19:20:12.000000+00:00",
        "acknowledged": True,
    }
    server._focus_remote_session_attach.assert_awaited_once()


@pytest.mark.asyncio
async def test_session_focus_remote_session_aborts_when_superseded_by_newer_intent(server, monkeypatch):
    remote_session = {
        "session_key": "session-remote",
        "window_id": 0,
        "focus_mode": "remote_bridge_attachable",
        "focus_connection_key": "vpittamp@ryzen:22",
        "connection_key": "vpittamp@ryzen:22",
        "project_name": "vpittamp/nixos-config:main",
        "surface_key": "surface-remote",
        "conflict_state": "",
    }
    server._session_list = AsyncMock(return_value={"sessions": [remote_session]})
    monkeypatch.setattr(server, "_record_ai_session_seen", lambda _session_key: None)
    server._user_intent_epoch = 2
    server._resolve_remote_attach_profile = lambda _session: (_ for _ in ()).throw(AssertionError("should not resolve attach profile"))

    result = await server._session_focus({
        "session_key": "session-remote",
        "__intent_epoch": 1,
    })

    assert result["success"] is False
    assert result["reason"] == "superseded_before_remote_attach"


@pytest.mark.asyncio
async def test_session_focus_local_requires_verified_current_session(server, monkeypatch):
    local_session = {
        "session_key": "session-local",
        "window_id": 101,
        "focus_mode": "local_window",
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
        "focus_mode": "local_window",
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
async def test_session_close_local_tmux_kills_tracked_pane(server):
    local_session = {
        "session_key": "session-local-pane",
        "focus_connection_key": "local@thinkpad",
        "connection_key": "local@thinkpad",
        "source_is_current_host": True,
        "tmux_session": "i3pm-local",
        "tmux_window": "0:main",
        "tmux_pane": "%7",
        "terminal_context": {
            "tmux_socket": "/tmp/tmux-local",
        },
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(local_session)]})
    server._kill_tmux_pane = Mock(return_value={"success": True, "reason": "ok", "stderr": ""})
    server.notify_state_change = AsyncMock()
    server._set_focus_overrides(session_key="session-local-pane", window_id=12, connection_key="local@thinkpad")
    server._connection_target_is_current_host = lambda connection_key: connection_key == "local@thinkpad"

    result = await server._session_close({"session_key": "session-local-pane"})

    assert result["success"] is True
    assert result["close_mode"] == "local_tmux_pane"
    assert result["killed_tmux_pane"] == "%7"
    server._kill_tmux_pane.assert_called_once_with(
        execution_mode="local",
        tmux_pane="%7",
        remote_target="local@thinkpad",
        connection_key="local@thinkpad",
        tmux_socket="/tmp/tmux-local",
    )
    server.notify_state_change.assert_awaited_once_with("ai_session_close")
    assert server._focus_session_override_key == ""


@pytest.mark.asyncio
async def test_session_close_remote_tmux_uses_source_connection_key(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "focus_connection_key": "vpittamp@ryzen:22",
        "source_connection_key": "vpittamp@ryzen:22",
        "connection_key": "local@ryzen",
        "source_is_current_host": False,
        "tmux_session": "i3pm-remote",
        "tmux_window": "2:claude",
        "tmux_pane": "%5",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "remote_target": "vpittamp@ryzen:22",
        },
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(remote_session)]})
    server._kill_tmux_pane = Mock(return_value={"success": True, "reason": "ok", "stderr": ""})
    server.notify_state_change = AsyncMock()
    server._connection_target_is_current_host = lambda _connection_key: False

    result = await server._session_close({"session_key": "session-remote-pane"})

    assert result["success"] is True
    assert result["close_mode"] == "remote_tmux_pane"
    server._kill_tmux_pane.assert_called_once_with(
        execution_mode="ssh",
        tmux_pane="%5",
        remote_target="vpittamp@ryzen:22",
        connection_key="vpittamp@ryzen:22",
        tmux_socket="/run/user/1000/tmux-1000/default",
    )
    server.notify_state_change.assert_awaited_once_with("ai_session_close")


@pytest.mark.asyncio
async def test_session_close_falls_back_to_managed_window_when_tmux_identity_missing(server):
    window_only_session = {
        "session_key": "session-window-only",
        "window_id": 44,
        "bridge_window_id": 55,
        "focus_connection_key": "local@thinkpad",
        "connection_key": "local@thinkpad",
        "terminal_context": {},
    }
    server._session_list = AsyncMock(return_value={"sessions": [dict(window_only_session)]})
    server._close_managed_window = AsyncMock(return_value=True)
    server.notify_state_change = AsyncMock()

    result = await server._session_close({"session_key": "session-window-only"})

    assert result["success"] is True
    assert result["close_mode"] == "local_window_fallback"
    assert result["closed_window_id"] == 55
    server._close_managed_window.assert_awaited_once_with(55)
    server.notify_state_change.assert_awaited_once_with("ai_session_close")


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
    server._window_is_locally_tracked = AsyncMock(return_value=False)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server._get_window_transition_state = AsyncMock(return_value={
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
    server._window_matches_transition_target = AsyncMock(return_value=True)
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
    server._switch_runtime_context_if_needed.assert_awaited_once_with(
        "vpittamp/nixos-config:main",
        "",
        "",
    )


@pytest.mark.asyncio
async def test_focus_window_ssh_target_with_local_window_binding_uses_local_focus(server, monkeypatch):
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace())
    server._connection_target_is_current_host = lambda _connection_key: False
    server._window_is_locally_tracked = AsyncMock(return_value=True)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server._get_window_transition_state = AsyncMock(return_value={
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
    server._window_matches_transition_target = AsyncMock(return_value=True)
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
    server._switch_runtime_context_if_needed.assert_awaited_once_with(
        "PittampalliOrg/stacks:main",
        "",
        "",
    )
    assert result["focused_window_id_after"] == 175


@pytest.mark.asyncio
async def test_focus_window_scratchpad_restore_preserves_saved_workspace_and_fullscreen(server):
    commands = []
    server.i3_connection = SimpleNamespace(conn=SimpleNamespace())
    server._connection_target_is_current_host = lambda _connection_key: True
    server._window_is_locally_tracked = AsyncMock(return_value=True)
    server._switch_runtime_context_if_needed = AsyncMock(return_value={"switched": False})
    server._send_tick_barrier = AsyncMock()
    server._get_window_transition_state = AsyncMock(return_value={
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
    })
    server._window_matches_transition_target = AsyncMock(return_value=True)
    server._verify_window_focus = AsyncMock(return_value={"success": True, "reason": "ok"})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "",
        "focused_window_id": 44,
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
    assert "scratchpad show" in commands[0]
    assert "move workspace number 3" in commands[0]
    assert "fullscreen enable" in commands[0]
    assert "fullscreen disable" not in commands[0]


@pytest.mark.asyncio
async def test_session_focus_tmux_target_uses_tmux_verification(server, monkeypatch):
    local_session = {
        "session_key": "session-local-pane",
        "window_id": 101,
        "focus_mode": "local_window",
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
async def test_focus_remote_session_attach_tmux_target_sets_override_without_wait(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "conflict_state": "",
        "host_name": "ryzen",
        "tmux_session": "i3pm-remote",
        "tmux_window": "1:codex-raw",
        "tmux_pane": "%11",
        "terminal_context": {
            "tmux_socket": "/tmp/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {"host": "ryzen"}
    server._switch_to_explicit_remote_context = AsyncMock()
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": "PittampalliOrg/workflow-builder:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "execution_mode": "ssh",
    })
    server._get_reusable_context_terminal_window = AsyncMock(return_value=SimpleNamespace(
        window_id=20,
        terminal_role="remote-session:abc123",
        remote_surface_key="surface-remote-pane",
        remote_session_key="session-remote-pane",
    ))
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "session-stale",
        "focused_window_id_after": 20,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "session-stale",
            "focused_window_id": 20,
        },
    })
    server._wait_for_launch_status = AsyncMock(side_effect=AssertionError("should not wait"))
    server._wait_for_session_focus = AsyncMock(return_value={"success": False, "reason": "should_not_run"})
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 20,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    assert result["verification"]["verification_source"] == "remote_launcher"
    assert result["verification"]["success"] is True
    assert result["current_ai_session_key_after"] == "session-remote-pane"
    assert result["focus"]["current_ai_session_key_after"] == "session-remote-pane"
    assert result["focus"]["focus_state_after"]["current_ai_session_key"] == "session-remote-pane"
    assert result["launch_status"]["status"] == "reused_existing"
    assert server._focus_session_override_key == "session-remote-pane"
    assert server._focus_window_override["window_id"] == 20
    server._wait_for_session_focus.assert_not_awaited()


@pytest.mark.asyncio
async def test_focus_remote_session_attach_replaces_stale_bridge_before_relaunch(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "conflict_state": "",
        "host_name": "ryzen",
        "tmux_session": "i3pm-remote",
        "tmux_window": "1:codex-raw",
        "tmux_pane": "%11",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {"host": "ryzen"}
    server._switch_to_explicit_remote_context = AsyncMock()
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": "PittampalliOrg/workflow-builder:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "terminal_anchor_id": "bridge-anchor",
        "execution_mode": "ssh",
    })
    server._get_reusable_context_terminal_window = AsyncMock(return_value=SimpleNamespace(
        window_id=20,
        remote_surface_key="surface-remote-pane",
        remote_session_key="session-remote-pane",
        remote_tmux_server_key="/tmp/tmux-1000/default",
        remote_tmux_session="i3pm-old",
        remote_tmux_window="0:main",
        remote_tmux_pane="%0",
    ))
    server._close_managed_window = AsyncMock(return_value=True)
    server.state_manager.remove_window = AsyncMock()
    server._register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    server._execute_launch_spec = lambda _spec: {"success": True}
    server._wait_for_terminal_window = AsyncMock(return_value={"window_id": 44})
    server._wait_for_launch_status = AsyncMock(return_value={"success": True, "launch_id": "launch-1", "status": "attaching_tmux", "reason": "ok"})
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "session-stale",
        "focused_window_id_after": 44,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "session-stale",
            "focused_window_id": 44,
        },
    })
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 44,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    assert result["launch"]["reused_existing"] is False
    assert result["launch_status"]["status"] == "attaching_tmux"
    server._close_managed_window.assert_awaited_once_with(20)
    server.state_manager.remove_window.assert_awaited_once_with(20)
    server._register_launch_for_spec.assert_awaited_once()


@pytest.mark.asyncio
async def test_focus_remote_session_attach_launches_new_exact_bridge_when_project_main_exists(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "conflict_state": "",
        "host_name": "ryzen",
        "tmux_session": "i3pm-vpittamp-t3code-main-f7056320",
        "tmux_window": "0:main",
        "tmux_pane": "%3",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {
        "remote_host": "ryzen",
        "remote_user": "vpittamp",
        "remote_port": 22,
        "remote_dir": "/home/vpittamp/repos/vpittamp/t3code/main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
    }
    server._switch_to_explicit_remote_context = AsyncMock()
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": "vpittamp/t3code:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "tmux_session_name": "i3pm-vpittamp-t3code-main-f7056320",
        "terminal_anchor_id": "bridge-anchor",
        "execution_mode": "ssh",
    })
    server._get_reusable_context_terminal_window = AsyncMock(return_value=None)
    server._register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    server._execute_launch_spec = lambda _spec: {"success": True}
    server._wait_for_terminal_window = AsyncMock(return_value={"window_id": 44})
    server._wait_for_launch_status = AsyncMock(return_value={"success": True, "launch_id": "launch-1", "status": "attaching_tmux", "reason": "ok"})
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "",
        "focused_window_id_after": 44,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "",
            "focused_window_id": 44,
        },
    })
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 44,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    assert result["window_id"] == 44
    assert result["launch"]["reused_existing"] is False
    assert result["launch_status"]["status"] == "attaching_tmux"


@pytest.mark.asyncio
async def test_focus_remote_session_attach_focuses_local_bridge_without_project_context_switch(server):
    remote_project = "PittampalliOrg/workflow-builder:104-create-coding-agent"
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "project_name": remote_project,
        "project": remote_project,
        "conflict_state": "",
        "host_name": "ryzen",
        "tmux_session": "i3pm-pittampalliorg-workflow--919ce57f",
        "tmux_window": "0:main",
        "tmux_pane": "%2",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {
        "project_name": remote_project,
        "remote_host": "ryzen",
        "remote_user": "vpittamp",
        "remote_port": 22,
        "remote_dir": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/104-create-coding-agent",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": f"{remote_project}::ssh::vpittamp@ryzen:22",
    }
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": remote_project,
        "connection_key": "vpittamp@ryzen:22",
        "context_key": f"{remote_project}::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "tmux_session_name": "i3pm-pittampalliorg-workflow--919ce57f",
        "terminal_anchor_id": "bridge-anchor",
        "execution_mode": "ssh",
    })
    server._get_reusable_context_terminal_window = AsyncMock(return_value=None)
    server._register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    server._execute_launch_spec = lambda _spec: {"success": True}
    server._wait_for_terminal_window = AsyncMock(return_value={"window_id": 44})
    server._wait_for_launch_status = AsyncMock(return_value={
        "success": True,
        "launch_id": "launch-1",
        "status": "attaching_tmux",
        "reason": "ok",
    })
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "",
        "focused_window_id_after": 44,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "",
            "focused_window_id": 44,
        },
    })
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 44,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    server._window_focus.assert_awaited_once_with({
        "window_id": 44,
        "project_name": remote_project,
        "target_variant": "ssh",
        "connection_key": "vpittamp@ryzen:22",
    })
    assert result["focus_mode"] == "remote_bridge_bound"


@pytest.mark.asyncio
async def test_focus_remote_session_attach_prefers_already_bound_window(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "conflict_state": "",
        "host_name": "ryzen",
        "window_id": 39,
        "bridge_window_id": 39,
        "tmux_session": "i3pm-pittampalliorg-workflow--919ce57f",
        "tmux_window": "0:main",
        "tmux_pane": "%2",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {
        "remote_host": "ryzen",
        "remote_user": "vpittamp",
        "remote_port": 22,
        "remote_dir": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
    }
    server._switch_to_explicit_remote_context = AsyncMock()
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": "PittampalliOrg/workflow-builder:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "tmux_session_name": "i3pm-pittampalliorg-workflow--919ce57f",
        "execution_mode": "ssh",
    })
    server.state_manager.state.window_map[39] = SimpleNamespace(
        window_id=39,
        terminal_role="remote-session:abc123",
        remote_surface_key="surface-remote-pane",
        remote_session_key="session-remote-pane",
        remote_tmux_session="i3pm-pittampalliorg-workflow--919ce57f",
        remote_tmux_window="0:main",
        remote_tmux_pane="%2",
    )
    server._find_live_sway_window = AsyncMock(return_value=SimpleNamespace(id=39))
    server._get_reusable_context_terminal_window = AsyncMock(side_effect=AssertionError("unexpected lookup"))
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "",
        "focused_window_id_after": 39,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "",
            "focused_window_id": 39,
        },
    })
    server._select_tmux_target = lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "stderr": "",
    }
    server._verify_tmux_target = lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "active_tmux_pane": "%2",
        "tmux_pane": "%2",
    }
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 39,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    assert result["window_id"] == 39
    assert result["launch"]["reused_existing"] is True
    assert result["launch"]["reused_terminal_role"] == "remote-session:abc123"


@pytest.mark.asyncio
async def test_focus_remote_session_attach_relaunches_live_window_without_exact_bridge_identity(server):
    remote_session = {
        "session_key": "session-remote-pane",
        "surface_key": "surface-remote-pane",
        "conflict_state": "",
        "host_name": "ryzen",
        "window_id": 44,
        "bridge_window_id": 44,
        "tmux_session": "i3pm-vpittamp-t3code-main-f7056320",
        "tmux_window": "0:main",
        "tmux_pane": "%3",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
        },
    }
    server._resolve_remote_attach_profile = lambda _session: {
        "remote_host": "ryzen",
        "remote_user": "vpittamp",
        "remote_port": 22,
        "remote_dir": "/home/vpittamp/repos/vpittamp/t3code/main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
    }
    server._switch_to_explicit_remote_context = AsyncMock()
    server._build_remote_session_attach_spec = AsyncMock(return_value={
        "app_name": "terminal",
        "project_name": "vpittamp/t3code:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
        "terminal_role": "remote-session:abc123",
        "tmux_session_name": "i3pm-vpittamp-t3code-main-f7056320",
        "terminal_anchor_id": "bridge-anchor",
        "execution_mode": "ssh",
    })
    server._find_live_sway_window = AsyncMock(return_value=SimpleNamespace(id=44))
    server._get_reusable_context_terminal_window = AsyncMock(side_effect=AssertionError("unexpected lookup"))
    server._close_managed_window = AsyncMock(return_value=True)
    server.state_manager.remove_window = AsyncMock()
    server._register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    server._execute_launch_spec = lambda _spec: {"success": True}
    server._wait_for_terminal_window = AsyncMock(return_value={"window_id": 44})
    server._wait_for_launch_status = AsyncMock(return_value={"success": True, "launch_id": "launch-1", "status": "attaching_tmux", "reason": "ok"})
    server._window_focus = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key_after": "",
        "focused_window_id_after": 44,
        "focus_state_after": {
            "success": True,
            "current_ai_session_key": "",
            "focused_window_id": 44,
        },
    })
    server._select_tmux_target = lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "stderr": "",
    }
    server._verify_tmux_target = lambda **_kwargs: {
        "success": True,
        "reason": "ok",
        "active_tmux_pane": "%3",
        "tmux_pane": "%3",
    }
    server._focus_state = AsyncMock(return_value={
        "success": True,
        "current_ai_session_key": "session-remote-pane",
        "focused_window_id": 44,
    })

    result = await server._focus_remote_session_attach(
        session_key="session-remote-pane",
        session=remote_session,
    )

    assert result["success"] is True
    assert result["window_id"] == 44
    assert result["launch"]["reused_existing"] is False
    assert result["launch"]["replaced_stale_bridge"] is True


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
        ipc_server_module,
        "read_process_environ_with_fallback",
        lambda pid: {
            "I3PM_PROJECT_NAME": "vpittamp/t3code:main",
            "I3PM_CONTEXT_KEY": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
            "I3PM_CONTEXT_VARIANT": "ssh",
            "I3PM_TERMINAL_ROLE": "project-main",
            "I3PM_TMUX_SESSION_NAME": "i3pm-vpittamp-t3code-main-f7056320",
            "I3PM_APP_ID": "terminal-vpittamp/t3code:main-1",
            "I3PM_APP_NAME": "terminal",
        },
    )
    monkeypatch.setattr(
        ipc_server_module,
        "parse_window_environment",
        lambda _env: SimpleNamespace(
            project_name="vpittamp/t3code:main",
            context_key="vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
            terminal_role="project-main",
            tmux_session_name="i3pm-vpittamp-t3code-main-f7056320",
            app_name="terminal",
        ),
    )

    result = server._find_context_terminal_window(
        project_name="vpittamp/t3code:main",
        context_key="vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
        execution_mode="ssh",
        app_name="terminal",
        terminal_role="project-main",
    )

    assert result is window


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
async def test_focus_state_clears_verified_remote_override_without_local_ai_focus(server, monkeypatch):
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
    server._focus_session_override_key = "session-remote-current"
    server._focus_window_override = {"window_id": 30, "connection_key": "vpittamp@ryzen:22"}
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_ai_session_key"] == ""
    assert result["focused_window_id"] == 404
    assert result["active_session"]["session_key"] == ""


@pytest.mark.asyncio
async def test_focus_state_does_not_float_to_remote_session_without_verified_override(server, monkeypatch):
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
    ]
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    monkeypatch.setattr(server, "_load_session_items", lambda _snapshot: sessions)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))

    result = await server._focus_state({})

    assert result["success"] is True
    assert result["current_ai_session_key"] == ""
    assert result["active_session"]["session_key"] == ""


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
