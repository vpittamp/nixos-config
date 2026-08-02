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


class _TransportWriter:
    def __init__(self, buffer_size=0):
        self.buffer = []
        self.closed = False
        self.transport = SimpleNamespace(get_write_buffer_size=lambda: buffer_size)

    def write(self, data):
        self.buffer.append(data)

    def close(self):
        self.closed = True


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def test_ipc_stats_reads_dashboard_service_subscriber_count(server):
    writer = _DummyWriter()
    server.dashboard_service.subscribe(writer)  # type: ignore[arg-type]

    stats = server._get_ipc_stats()

    assert stats["state_change_subscriber_count"] == 1
    assert not hasattr(server, "state_change_subscribers")


@pytest.mark.asyncio
async def test_notify_state_change_handles_subscriber_set_mutation(server):
    async def remove_second():
        server.dashboard_service.discard_subscriber(second_writer)

    first_writer = _DummyWriter(on_drain=remove_second)
    second_writer = _DummyWriter()
    server.dashboard_service.subscribers = {first_writer, second_writer}
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
    ]
    assert params["payload"]["schema_version"] == "i3pm.dashboard.v2"
    server.dashboard_service.event_payload.assert_awaited_once_with(params["changed_keys"])


@pytest.mark.asyncio
async def test_broadcast_event_evicts_and_closes_slow_subscriber(server):
    # One wedged subscriber must not stall Sway event processing: the writer
    # over the buffer cap is evicted and closed, everyone else still receives.
    slow_writer = _TransportWriter(buffer_size=2_000_000)
    healthy_writer = _TransportWriter(buffer_size=0)
    server.subscribed_clients = {slow_writer, healthy_writer}

    await server.broadcast_event({"event_type": "window::focus"})

    assert server.subscribed_clients == {healthy_writer}
    assert slow_writer.closed is True
    assert healthy_writer.closed is False
    assert len(healthy_writer.buffer) == 1


def test_notify_coalesce_delay_is_short_for_a_real_workspace_switch():
    # THE case this exists for. Sway emits window::focus alongside every
    # workspace::focus, so the batch that redraws the focused pill always
    # contains both. Classifying by event NAME put window::focus in the
    # window.changed bucket and held the whole batch on the wide window, which
    # left the pill lagging exactly as before.
    fast = ipc_server_module.FAST_DASHBOARD_NOTIFY_COALESCE_S
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S
    assert fast < slow

    assert IPCServer._notify_coalesce_delay({"workspace::focus", "window::focus"}) == fast
    assert IPCServer._notify_coalesce_delay({"workspace::focus"}) == fast
    assert IPCServer._notify_coalesce_delay({"window::focus"}) == fast


def test_notify_coalesce_delay_keeps_tree_invalidating_events_wide():
    # Structural events drop the window-tree cache before the drain, so their
    # rebuild is a cold get_tree + get_workspaces + get_outputs. Draining those
    # every 20ms would turn a monitor hotplug or `i3pm monitors reassign` — which
    # moves every workspace in a burst — into repeated cold rebuilds fighting the
    # commands that caused them for the same Sway connection.
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S

    for event in ("window::new", "window::close", "window::move",
                  "workspace::init", "workspace::empty", "workspace::move"):
        assert IPCServer._notify_coalesce_delay({event}) == slow, event

    # And one structural member is enough to hold a batch that also has focus.
    assert IPCServer._notify_coalesce_delay({"workspace::focus", "workspace::move"}) == slow


def test_notify_coalesce_delay_stays_wide_for_git_bearing_batches():
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S

    # These pull session/herdr rows, which hydrate git via subprocesses.
    assert IPCServer._notify_coalesce_delay({"ai_session_herdr_changed"}) == slow
    assert IPCServer._notify_coalesce_delay({"ai_session_git_changed"}) == slow
    assert IPCServer._notify_coalesce_delay({"dashboard_invalidated"}) == slow
    # One expensive member drags the whole batch to the wide window, because the
    # payload is the union of every member's changed keys.
    assert IPCServer._notify_coalesce_delay({"workspace::focus", "ai_session_herdr_changed"}) == slow


@pytest.mark.asyncio
async def test_drain_loop_readds_pending_keys_when_notify_raises(server):
    server._dashboard_notify_pending = {"focus_changed", "window::close"}
    server.notify_state_change = AsyncMock(side_effect=RuntimeError("boom"))

    with pytest.raises(RuntimeError):
        await server._drain_scheduled_state_notifications()

    # The batch is re-queued so the next drain retries instead of losing it.
    assert server._dashboard_notify_pending == {"focus_changed", "window::close"}
