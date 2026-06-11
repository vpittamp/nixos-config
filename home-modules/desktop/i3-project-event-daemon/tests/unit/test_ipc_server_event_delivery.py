"""Unit tests for shared daemon event delivery."""

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
