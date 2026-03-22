"""Unit tests for daemon-owned agent harness RPC methods."""

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


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


class _DummyWriter:
    def __init__(self, on_drain=None):
        self.on_drain = on_drain
        self.buffer = []

    def write(self, data):
        self.buffer.append(data)

    async def drain(self):
        if self.on_drain is not None:
            await self.on_drain()


@pytest.mark.asyncio
async def test_agent_session_start_uses_local_context(server, tmp_path):
    context = {
        "execution_mode": "local",
        "directory": str(tmp_path),
        "local_directory": str(tmp_path),
        "context_key": "repo::local::local@host",
    }
    server._context_get_active = AsyncMock(return_value=context)
    server.agent_harness.start_session = AsyncMock(return_value={"session_key": "codex:abc"})
    server.agent_harness.snapshot = AsyncMock(return_value={"sessions": [], "active_session_key": ""})

    result = await server._agent_session_start({})

    assert result["success"] is True
    server.agent_harness.start_session.assert_awaited_once_with(
        cwd=str(tmp_path),
        context=context,
        model=None,
    )


@pytest.mark.asyncio
async def test_agent_session_start_uses_explicit_worktree_target(server, tmp_path):
    active_context = {
        "execution_mode": "local",
        "directory": "/tmp/other-project",
        "local_directory": "/tmp/other-project",
        "context_key": "other::local::local@host",
    }
    target_context = {
        "qualified_name": "vpittamp/nixos-config:main",
        "directory": str(tmp_path),
        "local_directory": str(tmp_path),
        "execution_mode": "local",
        "context_key": "vpittamp/nixos-config:main::local::local@host",
    }
    server._context_get_active = AsyncMock(return_value=active_context)
    server._find_worktree_by_qualified_name = lambda qualified_name: {
        "repo_name": "vpittamp/nixos-config",
        "repo": {"account": "vpittamp", "name": "nixos-config"},
        "worktree": {"branch": "main", "path": str(tmp_path)},
        "full_qualified_name": qualified_name,
    }
    server._build_active_worktree_context = lambda *args, **kwargs: dict(target_context)
    server._record_project_usage = lambda qualified_name: None
    server.agent_harness.start_session = AsyncMock(return_value={"session_key": "codex:abc"})
    server.agent_harness.snapshot = AsyncMock(return_value={"sessions": [], "active_session_key": ""})
    server._build_dashboard_worktrees = AsyncMock(return_value=[])

    result = await server._agent_session_start({"qualified_name": "vpittamp/nixos-config:main"})

    assert result["success"] is True
    server.agent_harness.start_session.assert_awaited_once_with(
        cwd=str(tmp_path),
        context=target_context,
        model=None,
    )


@pytest.mark.asyncio
async def test_agent_session_start_rejects_ssh_context(server):
    server._context_get_active = AsyncMock(return_value={
        "execution_mode": "ssh",
        "directory": "/tmp/project",
        "local_directory": "/tmp/project",
    })

    with pytest.raises(ValueError, match="local contexts only"):
        await server._agent_session_start({})


@pytest.mark.asyncio
async def test_agent_session_send_proxies_to_harness(server):
    server.agent_harness.send_message = AsyncMock(return_value={"session_key": "codex:abc"})
    server._agent_snapshot = AsyncMock(return_value={"sessions": [{"session_key": "codex:abc"}]})

    result = await server._agent_session_send({
        "session_key": "codex:abc",
        "text": "hello",
    })

    assert result["success"] is True
    server.agent_harness.send_message.assert_awaited_once_with("codex:abc", "hello")


@pytest.mark.asyncio
async def test_agent_session_respond_proxies_to_harness(server):
    server.agent_harness.respond_to_approval = AsyncMock(return_value={"session_key": "codex:abc"})
    server._agent_snapshot = AsyncMock(return_value={"sessions": [{"session_key": "codex:abc"}]})

    result = await server._agent_session_respond({
        "session_key": "codex:abc",
        "request_id": "7",
        "decision": "approve",
    })

    assert result["success"] is True
    server.agent_harness.respond_to_approval.assert_awaited_once_with("codex:abc", "7", "approve")


@pytest.mark.asyncio
async def test_notify_state_change_handles_subscriber_set_mutation(server):
    async def remove_second():
        server.state_change_subscribers.discard(second_writer)

    first_writer = _DummyWriter(on_drain=remove_second)
    second_writer = _DummyWriter()
    server.state_change_subscribers = {first_writer, second_writer}

    await server.notify_state_change("agent_session_changed")

    assert len(first_writer.buffer) == 1
    assert len(second_writer.buffer) == 1


@pytest.mark.asyncio
async def test_broadcast_agent_event_handles_subscriber_set_mutation(server):
    async def remove_second():
        server.agent_event_subscribers.discard(second_writer)

    first_writer = _DummyWriter(on_drain=remove_second)
    second_writer = _DummyWriter()
    server.agent_event_subscribers = {first_writer, second_writer}

    await server._broadcast_agent_event({"sequence": 1, "type": "session_updated"})

    assert len(first_writer.buffer) == 1
    assert len(second_writer.buffer) == 1


@pytest.mark.asyncio
async def test_agent_snapshot_includes_available_worktrees(server):
    active_context = {"qualified_name": "vpittamp/nixos-config:main"}
    worktrees = [{"qualified_name": "vpittamp/nixos-config:main"}]
    server.agent_harness.snapshot = AsyncMock(return_value={"sessions": [], "active_session_key": ""})
    server._context_get_active = AsyncMock(return_value=active_context)
    server._build_dashboard_worktrees = AsyncMock(return_value=worktrees)

    result = await server._agent_snapshot({})

    assert result["active_context"] == active_context
    assert result["available_worktrees"] == worktrees


@pytest.mark.asyncio
async def test_assistant_desktop_snapshot_filters_active_context(server):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::local::local@host",
            "connection_key": "local@host",
        },
        "tracked_windows": [
            {
                "window_id": 11,
                "title": "Code",
                "app_name": "code",
                "visible": True,
                "focused": True,
                "workspace": "2",
                "output": "eDP-1",
                "context_key": "vpittamp/nixos-config:main::local::local@host",
            },
            {
                "window_id": 99,
                "title": "Other",
                "app_name": "browser",
                "visible": True,
                "focused": False,
                "workspace": "1",
                "output": "eDP-1",
                "context_key": "other::local::local@host",
            },
        ],
        "sessions": [
            {
                "session_key": "codex:1",
                "title": "First",
                "preview": "hello",
                "session_phase": "done",
                "context": {"context_key": "vpittamp/nixos-config:main::local::local@host"},
            },
            {
                "session_key": "codex:2",
                "title": "Other",
                "preview": "world",
                "session_phase": "done",
                "context": {"context_key": "other::local::local@host"},
            },
        ],
        "focused_window_id": 11,
        "scratchpad": {"available": True, "context_key": "vpittamp/nixos-config:main::local::local@host"},
        "active_terminal": {},
        "active_outputs": ["eDP-1"],
        "outputs": [{"name": "eDP-1", "workspaces": [{"name": "2", "focused": True}]}],
        "launch_stats": {},
    }
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)

    result = await server._assistant_desktop_snapshot({})

    assert result["visible_window_count"] == 1
    assert result["focused_window"]["window_id"] == 11
    assert len(result["sessions"]) == 1
    assert result["sessions"][0]["session_key"] == "codex:1"


@pytest.mark.asyncio
async def test_assistant_desktop_execute_focus_window_calls_window_focus(server):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::local::local@host",
            "connection_key": "local@host",
        },
        "tracked_windows": [
            {
                "window_id": 11,
                "title": "Code - nixos-config",
                "app_name": "code",
                "window_class": "code",
                "project": "vpittamp/nixos-config:main",
                "visible": True,
                "focused": False,
                "context_key": "vpittamp/nixos-config:main::local::local@host",
                "execution_mode": "local",
                "connection_key": "local@host",
            },
        ],
        "sessions": [],
        "focused_window_id": 0,
        "scratchpad": {},
        "active_terminal": {},
        "active_outputs": [],
        "outputs": [],
        "launch_stats": {},
    }
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    server._window_focus = AsyncMock(return_value={"success": True, "window_id": 11})
    server._assistant_desktop_snapshot = AsyncMock(return_value={"desktop_revision": 7})

    result = await server._assistant_desktop_execute({
        "action_kind": "focus_window",
        "query": "code",
    })

    assert result["success"] is True
    assert result["execution_status"] == "executed"
    server._window_focus.assert_awaited_once()


@pytest.mark.asyncio
async def test_assistant_desktop_execute_close_window_requires_confirm(server):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::local::local@host",
            "connection_key": "local@host",
        },
        "tracked_windows": [
            {
                "window_id": 22,
                "title": "Firefox",
                "app_name": "firefox",
                "window_class": "firefox",
                "project": "vpittamp/nixos-config:main",
                "visible": True,
                "focused": False,
                "context_key": "vpittamp/nixos-config:main::local::local@host",
                "execution_mode": "local",
                "connection_key": "local@host",
            },
        ],
        "sessions": [],
        "focused_window_id": 0,
        "scratchpad": {},
        "active_terminal": {},
        "active_outputs": [],
        "outputs": [],
        "launch_stats": {},
    }
    server._runtime_snapshot = AsyncMock(return_value=runtime_snapshot)
    server._window_action = AsyncMock(return_value={"success": True})

    result = await server._assistant_desktop_execute({
        "action_kind": "close_window",
        "query": "firefox",
    })

    assert result["success"] is False
    assert result["execution_status"] == "approval_required"
    server._window_action.assert_not_awaited()
