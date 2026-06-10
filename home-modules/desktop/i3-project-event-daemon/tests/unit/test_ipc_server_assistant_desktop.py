"""Unit tests for assistant desktop RPC helpers and shared event delivery."""

from __future__ import annotations

import importlib
import importlib.util
import json
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


class _DummyWriter:
    def __init__(self, on_drain=None):
        self.on_drain = on_drain
        self.buffer = []

    def write(self, data):
        self.buffer.append(data)

    async def drain(self):
        if self.on_drain is not None:
            await self.on_drain()


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


@pytest.mark.asyncio
async def test_notify_state_change_handles_subscriber_set_mutation(server):
    async def remove_second():
        server.state_change_subscribers.discard(second_writer)

    first_writer = _DummyWriter(on_drain=remove_second)
    second_writer = _DummyWriter()
    server.dashboard_service.subscribers = {first_writer, second_writer}
    server.state_change_subscribers = server.dashboard_service.subscribers
    server.dashboard_service.event_payload = AsyncMock(return_value={
        "schema_version": "i3pm.dashboard.v2",
        "snapshot_version": 1,
        "focus_state": {},
        "active_ai_sessions": [],
    })

    await server.notify_state_change("agent_session_changed")

    assert len(first_writer.buffer) == 1
    assert len(second_writer.buffer) == 1
    notification = json.loads(first_writer.buffer[0].decode("utf-8"))
    params = notification["params"]
    assert notification["method"] == "session.changed"
    assert params["schema_version"] == "i3pm.dashboard.event.v1"
    assert params["type"] == "agent_session_changed"
    assert params["event_type"] == "session.changed"
    assert params["generation"] == params["snapshot_version"]
    assert params["session_generation"] == 1
    assert params["focus_generation"] == 1
    assert params["changed_keys"] == [
        "focus_state",
        "active_ai_sessions",
        "current_ai_session_key",
        "worktrees",
    ]
    assert params["payload"]["schema_version"] == "i3pm.dashboard.v2"
    server.dashboard_service.event_payload.assert_awaited_once_with(params["changed_keys"])


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
