"""Integration tests for i3 IPC connection and event subscriptions (Feature 039: T036).

Tests verify that all 4 required i3 event subscriptions (window, workspace, output, tick)
are active and functional.
"""

import pytest
import asyncio
from typing import List
from datetime import datetime

from tests.i3_project_daemon.fixtures.mock_i3 import (
    MockI3Connection,
    MockI3Event,
    MockI3Container,
    create_ghost_window,
    create_workspace,
    create_output,
)


class EventSubscriptionTracker:
    """Tracks event subscription status for testing."""

    def __init__(self):
        """Initialize tracker."""
        self.subscriptions: List[str] = []
        self.event_counts: dict[str, int] = {
            "window": 0,
            "workspace": 0,
            "output": 0,
            "tick": 0,
        }
        self.last_event_time: dict[str, datetime | None] = {
            "window": None,
            "workspace": None,
            "output": None,
            "tick": None,
        }
        self.last_event_change: dict[str, str | None] = {
            "window": None,
            "workspace": None,
            "output": None,
            "tick": None,
        }

    async def on_window_event(self, event, container=None):
        """Handle window events."""
        self.event_counts["window"] += 1
        self.last_event_time["window"] = datetime.now()
        self.last_event_change["window"] = event.change

    async def on_workspace_event(self, event, container=None):
        """Handle workspace events."""
        self.event_counts["workspace"] += 1
        self.last_event_time["workspace"] = datetime.now()
        self.last_event_change["workspace"] = event.change

    async def on_output_event(self, event, container=None):
        """Handle output events."""
        self.event_counts["output"] += 1
        self.last_event_time["output"] = datetime.now()
        self.last_event_change["output"] = event.change

    async def on_tick_event(self, event, container=None):
        """Handle tick events."""
        self.event_counts["tick"] += 1
        self.last_event_time["tick"] = datetime.now()
        self.last_event_change["tick"] = event.change


@pytest.fixture
def i3_connection():
    """Create mock i3 connection."""
    return MockI3Connection()


@pytest.fixture
def event_tracker():
    """Create event subscription tracker."""
    return EventSubscriptionTracker()


@pytest.mark.asyncio
async def test_all_event_subscriptions_registered(i3_connection, event_tracker):
    """Test that all 4 required event subscriptions can be registered.

    Success Criteria (SC-001): 100% of window::new events detected
    Functional Requirement (FR-008): Daemon validates event subscriptions on startup
    """
    # Register all 4 event types
    i3_connection.on("window::new", event_tracker.on_window_event)
    i3_connection.on("window::close", event_tracker.on_window_event)
    i3_connection.on("window::focus", event_tracker.on_window_event)
    i3_connection.on("workspace::focus", event_tracker.on_workspace_event)
    i3_connection.on("output::connect", event_tracker.on_output_event)
    i3_connection.on("tick", event_tracker.on_tick_event)

    # Subscribe to events
    await i3_connection.subscribe(["window", "workspace", "output", "tick"])

    # Verify subscriptions
    assert "window" in i3_connection._subscriptions
    assert "workspace" in i3_connection._subscriptions
    assert "output" in i3_connection._subscriptions
    assert "tick" in i3_connection._subscriptions

    # Verify all 4 subscriptions are active
    assert len(i3_connection._subscriptions) == 4


@pytest.mark.asyncio
async def test_window_new_event_detection(i3_connection, event_tracker):
    """Test that window::new events are detected and processed.

    Success Criteria (SC-001): 100% window::new events captured
    Performance Target: <50ms detection latency
    """
    # Register window event handler
    i3_connection.on("window::new", event_tracker.on_window_event)
    await i3_connection.subscribe(["window"])

    # Emit window::new event
    window = create_ghost_window(window_id=14680068, pid=823199)
    event = MockI3Event(
        event_type="window",
        change="new",
        container=window
    )

    start_time = datetime.now()
    await i3_connection.emit_event(event)
    end_time = datetime.now()

    # Verify event was detected
    assert event_tracker.event_counts["window"] == 1
    assert event_tracker.last_event_change["window"] == "new"
    assert event_tracker.last_event_time["window"] is not None

    # Verify detection latency <50ms
    latency_ms = (end_time - start_time).total_seconds() * 1000
    assert latency_ms < 50, f"Detection latency {latency_ms}ms exceeds 50ms target"


@pytest.mark.asyncio
async def test_workspace_events_detection(i3_connection, event_tracker):
    """Test that workspace events are detected."""
    # Register workspace event handler
    i3_connection.on("workspace::focus", event_tracker.on_workspace_event)
    await i3_connection.subscribe(["workspace"])

    # Emit workspace::focus event
    workspace = create_workspace(num=2, name="2:code", visible=True)
    event = MockI3Event(
        event_type="workspace",
        change="focus",
        current=workspace
    )

    await i3_connection.emit_event(event)

    # Verify event was detected
    assert event_tracker.event_counts["workspace"] == 1
    assert event_tracker.last_event_change["workspace"] == "focus"


@pytest.mark.asyncio
async def test_output_events_detection(i3_connection, event_tracker):
    """Test that output events are detected."""
    # Register output event handler
    i3_connection.on("output::connect", event_tracker.on_output_event)
    await i3_connection.subscribe(["output"])

    # Emit output::connect event
    output = create_output(name="HDMI-2", active=True)
    event = MockI3Event(
        event_type="output",
        change="connect",
        current=output
    )

    await i3_connection.emit_event(event)

    # Verify event was detected
    assert event_tracker.event_counts["output"] == 1
    assert event_tracker.last_event_change["output"] == "connect"


@pytest.mark.asyncio
async def test_tick_events_detection(i3_connection, event_tracker):
    """Test that tick events are detected."""
    # Register tick event handler
    i3_connection.on("tick", event_tracker.on_tick_event)
    await i3_connection.subscribe(["tick"])

    # Emit tick event
    event = MockI3Event(
        event_type="tick",
        change="tick"
    )

    await i3_connection.emit_event(event)

    # Verify event was detected
    assert event_tracker.event_counts["tick"] == 1


@pytest.mark.asyncio
async def test_multiple_window_events_counted(i3_connection, event_tracker):
    """Test that multiple window events are counted correctly."""
    # Register window event handler
    i3_connection.on("window::new", event_tracker.on_window_event)
    i3_connection.on("window::close", event_tracker.on_window_event)
    i3_connection.on("window::focus", event_tracker.on_window_event)
    await i3_connection.subscribe(["window"])

    # Emit 10 window events
    for i in range(10):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(
            event_type="window",
            change="new",
            container=window
        )
        await i3_connection.emit_event(event)

    # Verify all events were counted
    assert event_tracker.event_counts["window"] == 10


@pytest.mark.asyncio
async def test_event_subscription_validation_startup(i3_connection, event_tracker):
    """Test event subscription validation on daemon startup.

    Functional Requirement (FR-008): Verify all 4 event subscriptions active
    """
    # Register all event handlers
    i3_connection.on("window::new", event_tracker.on_window_event)
    i3_connection.on("workspace::focus", event_tracker.on_workspace_event)
    i3_connection.on("output::connect", event_tracker.on_output_event)
    i3_connection.on("tick", event_tracker.on_tick_event)

    # Subscribe to all events
    await i3_connection.subscribe(["window", "workspace", "output", "tick"])

    # Simulate startup validation
    required_subscriptions = ["window", "workspace", "output", "tick"]
    active_subscriptions = i3_connection._subscriptions

    # Verify all required subscriptions are active
    for subscription in required_subscriptions:
        assert subscription in active_subscriptions, \
            f"Required subscription '{subscription}' is not active"

    # Verify exactly 4 subscriptions (no extras)
    assert len(active_subscriptions) == 4


@pytest.mark.asyncio
async def test_rapid_event_stream_handling(i3_connection, event_tracker):
    """Test handling of rapid event stream (stress test).

    Success Criteria (SC-012): 50 concurrent window creations processed
    Performance Target: <100ms per event
    """
    # Register event handler
    i3_connection.on("window::new", event_tracker.on_window_event)
    await i3_connection.subscribe(["window"])

    # Emit 50 rapid window::new events
    start_time = datetime.now()
    for i in range(50):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(
            event_type="window",
            change="new",
            container=window
        )
        await i3_connection.emit_event(event)

    end_time = datetime.now()

    # Verify all events were processed
    assert event_tracker.event_counts["window"] == 50

    # Verify average processing time <100ms per event
    total_time_ms = (end_time - start_time).total_seconds() * 1000
    avg_time_per_event_ms = total_time_ms / 50
    assert avg_time_per_event_ms < 100, \
        f"Average event processing time {avg_time_per_event_ms}ms exceeds 100ms target"


@pytest.mark.asyncio
async def test_event_subscription_persistence_after_error(i3_connection, event_tracker):
    """Test that event subscriptions remain active after handler errors."""
    # Create handler that raises on first call
    call_count = 0

    async def error_handler(event, container=None):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise RuntimeError("Simulated handler error")

    # Register error-prone handler
    i3_connection.on("window::new", error_handler)
    await i3_connection.subscribe(["window"])

    # Emit event that will cause error
    window = create_ghost_window()
    event = MockI3Event(event_type="window", change="new", container=window)

    try:
        await i3_connection.emit_event(event)
    except RuntimeError:
        pass  # Expected error

    # Verify subscription still active
    assert "window" in i3_connection._subscriptions

    # Emit second event (should succeed)
    await i3_connection.emit_event(event)

    # Verify second event was processed
    assert call_count == 2
