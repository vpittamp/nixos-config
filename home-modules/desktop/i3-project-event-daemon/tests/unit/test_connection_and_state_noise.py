from __future__ import annotations

import asyncio
import importlib
import importlib.util
import json
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


connection_module = importlib.import_module("i3_project_daemon.connection")
ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")
state_module = importlib.import_module("i3_project_daemon.state")
models_module = importlib.import_module("i3_project_daemon.models")
tree_cache_module = importlib.import_module("i3_project_daemon.services.tree_cache")
window_filter_module = importlib.import_module("i3_project_daemon.services.window_filter")


@pytest.mark.asyncio
async def test_validate_and_reconnect_returns_false_for_healthy_connection(tmp_path, monkeypatch):
    socket_path = tmp_path / "sway-ipc.test.sock"
    socket_path.write_text("")
    monkeypatch.setenv("SWAYSOCK", str(socket_path))
    monkeypatch.setenv("I3SOCK", str(socket_path))

    connection = connection_module.ResilientI3Connection(SimpleNamespace())
    healthy_conn = SimpleNamespace(get_tree=AsyncMock())
    connection.conn = healthy_conn

    reconnected = await connection.validate_and_reconnect_if_needed()

    assert reconnected is False
    healthy_conn.get_tree.assert_awaited_once()


@pytest.mark.asyncio
async def test_update_window_accepts_title_alias_without_warning():
    state_manager = state_module.StateManager()
    window = models_module.WindowInfo(
        window_id=101,
        con_id=101,
        window_class="google-chrome",
        window_title="Old Title",
        window_instance="google-chrome",
        app_identifier="google-chrome",
    )

    await state_manager.add_window(window)
    await state_manager.update_window(101, title="New Title")

    updated = await state_manager.get_window(101)
    assert updated is not None
    assert updated.window_title == "New Title"


class _DummyWriter:
    def __init__(self, peername=("local", 0), wait_closed_delay: float = 0):
        self.peername = peername
        self.wait_closed_delay = wait_closed_delay
        self.buffer = bytearray()
        self.closed = False

    def get_extra_info(self, name):
        if name == "peername":
            return self.peername
        return None

    def write(self, data):
        self.buffer.extend(data)

    async def drain(self):
        return None

    def close(self):
        self.closed = True

    async def wait_closed(self):
        if self.wait_closed_delay:
            await asyncio.sleep(self.wait_closed_delay)
        return None


@pytest.mark.asyncio
async def test_ipc_server_tracks_malformed_json_in_status():
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    reader = asyncio.StreamReader()
    writer = _DummyWriter(peername=("tester", 9999))

    reader.feed_data(b"{bad json}\n")
    reader.feed_eof()

    await server._handle_client(reader, writer)

    response = json.loads(writer.buffer.decode().strip())
    assert response["error"]["code"] == -32700

    status = await server._get_status()
    ipc_stats = status["ipc_stats"]
    assert ipc_stats["malformed_json_count"] == 1
    assert ipc_stats["last_malformed_json_peer"] == "tester:9999"
    assert ipc_stats["last_malformed_json_error"] is not None
    assert ipc_stats["top_malformed_json_peers"] == [{"peer": "tester:9999", "count": 1}]


@pytest.mark.asyncio
async def test_ipc_server_stop_does_not_block_on_slow_client_close():
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    slow_writer = _DummyWriter(wait_closed_delay=10)
    server.clients.add(slow_writer)

    await asyncio.wait_for(server.stop(), timeout=1.0)

    assert slow_writer.closed is True


class _SlowServer:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True

    async def wait_closed(self):
        await asyncio.sleep(10)


async def _stubborn_close(stop_event: asyncio.Event):
    while True:
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            if stop_event.is_set():
                return
            continue


@pytest.mark.asyncio
async def test_ipc_server_stop_does_not_block_on_slow_server_close():
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    slow_server = _SlowServer()
    server.server = slow_server

    await asyncio.wait_for(server.stop(), timeout=2.0)

    assert slow_server.closed is True


def test_invalidate_window_tree_cache_preserves_pid_environ_cache(monkeypatch):
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    server._window_tree_cache = {"cached": True}
    server._window_tree_cache_time = 123.0
    clear_pid_cache = Mock()
    monkeypatch.setattr(ipc_server_module, "clear_pid_environ_cache", clear_pid_cache)

    server.invalidate_window_tree_cache()

    assert server._window_tree_cache is None
    assert server._window_tree_cache_time == 0.0
    clear_pid_cache.assert_not_called()


@pytest.mark.asyncio
async def test_ipc_server_await_with_timeout_does_not_block_on_stubborn_coro():
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    stop_event = asyncio.Event()
    stubborn_task = asyncio.create_task(_stubborn_close(stop_event))

    started = asyncio.get_running_loop().time()
    await server._await_with_timeout(
        stubborn_task,
        timeout=0.05,
        timeout_message="timeout",
    )
    elapsed = asyncio.get_running_loop().time() - started
    stop_event.set()
    stubborn_task.cancel()
    await stubborn_task

    assert elapsed < 0.5


@pytest.mark.asyncio
async def test_apply_project_window_filter_retries_after_reconnect(monkeypatch):
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    stale_conn = SimpleNamespace(name="stale")
    fresh_conn = SimpleNamespace(name="fresh")

    async def reconnect():
        server.i3_connection.conn = fresh_conn
        return True

    server.i3_connection = SimpleNamespace(
        conn=stale_conn,
        validate_and_reconnect_if_needed=AsyncMock(side_effect=reconnect),
    )

    filter_calls = []

    async def fake_filter_windows_by_project(conn, active_project, workspace_tracker, active_context_key=None):
        filter_calls.append((conn, active_project, active_context_key))
        if len(filter_calls) == 1:
            raise ConnectionError("stale tree")
        return {"visible": 3, "hidden": 2}

    initialize_tree_cache = Mock()
    monkeypatch.setattr(window_filter_module, "filter_windows_by_project", fake_filter_windows_by_project)
    monkeypatch.setattr(tree_cache_module, "initialize_tree_cache", initialize_tree_cache)

    result = await server._apply_project_window_filter(
        active_project="vpittamp/nixos-config:main",
        active_context_key="vpittamp/nixos-config:main::host::ryzen",
        log_label="vpittamp/nixos-config:main",
    )

    assert result == {"visible": 3, "hidden": 2}
    assert filter_calls == [
        (stale_conn, "vpittamp/nixos-config:main", "vpittamp/nixos-config:main::host::ryzen"),
        (fresh_conn, "vpittamp/nixos-config:main", "vpittamp/nixos-config:main::host::ryzen"),
    ]
    server.i3_connection.validate_and_reconnect_if_needed.assert_awaited_once()
    initialize_tree_cache.assert_called_once_with(fresh_conn, ttl_ms=100.0)


@pytest.mark.asyncio
async def test_apply_project_window_filter_refreshes_cache_without_reconnect(monkeypatch):
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    current_conn = SimpleNamespace(name="current")
    server.i3_connection = SimpleNamespace(
        conn=current_conn,
        validate_and_reconnect_if_needed=AsyncMock(return_value=False),
    )

    filter_calls = []

    async def fake_filter_windows_by_project(conn, active_project, workspace_tracker, active_context_key=None):
        filter_calls.append((conn, active_project, active_context_key))
        if len(filter_calls) == 1:
            raise ConnectionError("stale tree cache")
        return {"visible": 1, "hidden": 4}

    initialize_tree_cache = Mock()
    monkeypatch.setattr(window_filter_module, "filter_windows_by_project", fake_filter_windows_by_project)
    monkeypatch.setattr(tree_cache_module, "initialize_tree_cache", initialize_tree_cache)

    result = await server._apply_project_window_filter(
        active_project="vpittamp/nixos-config:main",
        active_context_key="vpittamp/nixos-config:main::host::ryzen",
        log_label="vpittamp/nixos-config:main",
    )

    assert result == {"visible": 1, "hidden": 4}
    assert filter_calls == [
        (current_conn, "vpittamp/nixos-config:main", "vpittamp/nixos-config:main::host::ryzen"),
        (current_conn, "vpittamp/nixos-config:main", "vpittamp/nixos-config:main::host::ryzen"),
    ]
    server.i3_connection.validate_and_reconnect_if_needed.assert_awaited_once()
    initialize_tree_cache.assert_called_once_with(current_conn, ttl_ms=100.0)


@pytest.mark.asyncio
async def test_apply_project_window_filter_raises_when_connection_unavailable_after_reconnect(monkeypatch):
    state_manager = state_module.StateManager()
    server = ipc_server_module.IPCServer(state_manager)
    stale_conn = SimpleNamespace(name="stale")

    async def reconnect_fails():
        server.i3_connection.conn = None
        return False

    server.i3_connection = SimpleNamespace(
        conn=stale_conn,
        validate_and_reconnect_if_needed=AsyncMock(side_effect=reconnect_fails),
    )

    filter_calls = []

    async def fake_filter_windows_by_project(conn, active_project, workspace_tracker, active_context_key=None):
        filter_calls.append((conn, active_project, active_context_key))
        raise ConnectionError("stale tree")

    initialize_tree_cache = Mock()
    monkeypatch.setattr(window_filter_module, "filter_windows_by_project", fake_filter_windows_by_project)
    monkeypatch.setattr(tree_cache_module, "initialize_tree_cache", initialize_tree_cache)

    with pytest.raises(ConnectionError, match="stale tree"):
        await server._apply_project_window_filter(
            active_project="vpittamp/nixos-config:main",
            active_context_key="vpittamp/nixos-config:main::host::ryzen",
            log_label="vpittamp/nixos-config:main",
        )

    server.i3_connection.validate_and_reconnect_if_needed.assert_awaited_once()
    assert filter_calls == [
        (stale_conn, "vpittamp/nixos-config:main", "vpittamp/nixos-config:main::host::ryzen"),
    ]
    initialize_tree_cache.assert_not_called()
