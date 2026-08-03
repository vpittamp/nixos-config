"""Unit tests for shared daemon event delivery."""

from __future__ import annotations

import ast
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


def _tree_cache_invalidating_subscriptions(source_path):
    """Event names daemon.py subscribes to its invalidate_tree_cache handler."""
    events = set()
    for node in ast.walk(ast.parse(source_path.read_text(encoding="utf-8"))):
        if not isinstance(node, ast.Call) or len(node.args) != 2:
            continue
        func = node.func
        if not (isinstance(func, ast.Attribute) and func.attr == "subscribe"):
            continue
        event, handler = node.args
        if (
            isinstance(event, ast.Constant)
            and isinstance(event.value, str)
            and isinstance(handler, ast.Name)
            and handler.id == "invalidate_tree_cache"
        ):
            events.add(event.value)
    return events


def _handler_notify_events(source_path):
    """Map each event handlers.py notifies for to whether it drops the tree cache."""
    notified = {}
    for node in ast.walk(ast.parse(source_path.read_text(encoding="utf-8"))):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = func.id if isinstance(func, ast.Name) else getattr(func, "attr", "")
        if name != "_invalidate_cache_and_notify" or len(node.args) < 2:
            continue
        event = node.args[1]
        if not (isinstance(event, ast.Constant) and isinstance(event.value, str)):
            continue
        invalidate_tree = True
        for keyword in node.keywords:
            if keyword.arg == "invalidate_tree" and isinstance(keyword.value, ast.Constant):
                invalidate_tree = bool(keyword.value.value)
        notified[event.value] = notified.get(event.value, False) or invalidate_tree
    return notified


def _record_sleeps(server, monkeypatch, *, arrivals=()):
    """Record each coalescing wait, queueing one batch of events per wait."""
    slept = []
    queued = [set(batch) for batch in arrivals]

    async def fake_sleep(duration):
        slept.append(duration)
        if queued:
            server._dashboard_notify_pending |= queued.pop(0)

    monkeypatch.setattr(ipc_server_module.asyncio, "sleep", fake_sleep)
    return slept


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


def test_notify_coalesce_delay_uses_middle_tier_for_agent_session_batches():
    # herdr/agent rows are expensive by changed-keys (they hydrate git) but the
    # services that queue them never drop the window-tree cache, so the rebuild
    # is the warm one (~0.03s measured, vs ~0.11s cold). The wide window made an
    # agent status change wait ~8x the rebuild it was protecting against.
    fast = ipc_server_module.FAST_DASHBOARD_NOTIFY_COALESCE_S
    medium = ipc_server_module.MEDIUM_DASHBOARD_NOTIFY_COALESCE_S
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S
    assert fast < medium < slow

    for event in ("ai_session_herdr_changed", "ai_session_git_changed", "agent_session_changed"):
        assert IPCServer._notify_coalesce_delay({event}) == medium, event


def test_notify_coalesce_delay_stays_wide_for_cold_rebuild_batches():
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S

    # A full invalidation rebuilds everything by definition.
    assert IPCServer._notify_coalesce_delay({"dashboard_invalidated"}) == slow
    # `i3pm monitors reassign` / hotplug: the burst that the wide window exists for.
    assert IPCServer._notify_coalesce_delay({"display_layout_changed"}) == slow
    # Worktree refreshes are the other cache: the handler invalidates the
    # worktree cache before notifying, and the payload carries the ~100KB array.
    assert IPCServer._notify_coalesce_delay({"worktree_changed"}) == slow


def test_notify_coalesce_delay_takes_the_widest_window_in_a_mixed_batch():
    # The payload is the union of every member's changed keys, so the batch
    # costs whatever its most expensive member costs.
    medium = ipc_server_module.MEDIUM_DASHBOARD_NOTIFY_COALESCE_S
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S

    assert IPCServer._notify_coalesce_delay(
        {"workspace::focus", "window::focus", "ai_session_herdr_changed"}
    ) == medium
    assert IPCServer._notify_coalesce_delay(
        {"ai_session_herdr_changed", "window::close"}
    ) == slow
    assert IPCServer._notify_coalesce_delay(
        {"workspace::focus", "ai_session_git_changed", "display_layout_changed"}
    ) == slow
    # An empty batch has nothing to size against; stay conservative.
    assert IPCServer._notify_coalesce_delay(set()) == slow


def test_tree_cache_invalidating_events_match_daemon_subscriptions():
    # ipc_server keeps its own copy of the list (importing daemon would be
    # circular). This fails if daemon.py's invalidate_tree_cache subscriptions
    # change, so the tier that protects cold rebuilds cannot silently drift.
    subscribed = _tree_cache_invalidating_subscriptions(PACKAGE_ROOT / "daemon.py")

    assert subscribed, "no invalidate_tree_cache subscriptions found in daemon.py"
    assert subscribed == set(ipc_server_module.TREE_CACHE_INVALIDATING_STATE_EVENTS)


def test_no_event_that_drops_the_tree_cache_drains_faster_than_slow():
    # The real invariant behind the tiers: an event whose handler drops the
    # window-tree cache rebuilds cold and must keep the wide window. handlers.py
    # invalidates on every event it notifies for unless it passes
    # invalidate_tree=False, so this catches a new fast/medium event too.
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S
    notified = _handler_notify_events(PACKAGE_ROOT / "handlers.py")

    assert "window::close" in notified, "handlers.py notify calls not found"
    for event, invalidates_tree in sorted(notified.items()):
        if invalidates_tree:
            assert IPCServer._notify_coalesce_delay({event}) == slow, event


@pytest.mark.asyncio
async def test_drain_gives_an_upgraded_batch_the_rest_of_the_wider_window(server, monkeypatch):
    # A focus batch that grows an agent event mid-wait must not fire the more
    # expensive rebuild on the fast schedule — it waits out the medium window.
    fast = ipc_server_module.FAST_DASHBOARD_NOTIFY_COALESCE_S
    medium = ipc_server_module.MEDIUM_DASHBOARD_NOTIFY_COALESCE_S
    slept = _record_sleeps(server, monkeypatch, arrivals=[{"ai_session_herdr_changed"}])

    server._dashboard_notify_pending = {"window::focus", "workspace::focus"}
    server.notify_state_change = AsyncMock()
    await server._drain_scheduled_state_notifications()

    assert slept == [pytest.approx(fast), pytest.approx(medium - fast)]
    assert sum(slept) == pytest.approx(medium)


@pytest.mark.asyncio
async def test_drain_upgrade_path_walks_all_three_tiers(server, monkeypatch):
    # fast -> medium -> slow: re-checking only once would have fired the cold
    # rebuild after 60ms, which is what the wide window exists to prevent.
    fast = ipc_server_module.FAST_DASHBOARD_NOTIFY_COALESCE_S
    medium = ipc_server_module.MEDIUM_DASHBOARD_NOTIFY_COALESCE_S
    slow = ipc_server_module.SLOW_DASHBOARD_NOTIFY_COALESCE_S
    slept = _record_sleeps(
        server,
        monkeypatch,
        arrivals=[{"ai_session_herdr_changed"}, {"workspace::move"}],
    )

    server._dashboard_notify_pending = {"window::focus"}
    server.notify_state_change = AsyncMock()
    await server._drain_scheduled_state_notifications()

    assert slept == [
        pytest.approx(fast),
        pytest.approx(medium - fast),
        pytest.approx(slow - medium),
    ]
    assert sum(slept) == pytest.approx(slow)
    server.notify_state_change.assert_awaited_once_with(
        {"window::focus", "ai_session_herdr_changed", "workspace::move"}
    )


@pytest.mark.asyncio
async def test_drain_does_not_extend_a_batch_that_stays_in_its_tier(server, monkeypatch):
    medium = ipc_server_module.MEDIUM_DASHBOARD_NOTIFY_COALESCE_S
    slept = _record_sleeps(server, monkeypatch, arrivals=[{"agent_session_changed"}])

    server._dashboard_notify_pending = {"ai_session_herdr_changed"}
    server.notify_state_change = AsyncMock()
    await server._drain_scheduled_state_notifications()

    assert slept == [pytest.approx(medium)]


@pytest.mark.asyncio
async def test_drain_loop_readds_pending_keys_when_notify_raises(server):
    server._dashboard_notify_pending = {"focus_changed", "window::close"}
    server.notify_state_change = AsyncMock(side_effect=RuntimeError("boom"))

    with pytest.raises(RuntimeError):
        await server._drain_scheduled_state_notifications()

    # The batch is re-queued so the next drain retries instead of losing it.
    assert server._dashboard_notify_pending == {"focus_changed", "window::close"}
