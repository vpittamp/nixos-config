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
