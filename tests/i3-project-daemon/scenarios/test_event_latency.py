"""Scenario tests for event detection latency (Feature 039: T038).

Tests measure time from window::new event emission to processing completion,
verifying <50ms detection latency requirement.
"""

import pytest
import asyncio
from datetime import datetime, timedelta
from typing import List

from tests.i3_project_daemon.fixtures.mock_i3 import (
    MockI3Connection,
    MockI3Event,
    create_ghost_window,
    create_vscode_window,
)


class LatencyTracker:
    """Tracks event processing latency for testing."""

    def __init__(self):
        """Initialize latency tracker."""
        self.event_timestamps: dict[int, datetime] = {}  # window_id -> emit time
        self.processing_timestamps: dict[int, datetime] = {}  # window_id -> process time
        self.latencies_ms: List[float] = []

    def record_event_emission(self, window_id: int):
        """Record when event was emitted."""
        self.event_timestamps[window_id] = datetime.now()

    async def process_event(self, event, container=None):
        """Process event and record latency."""
        if container:
            process_time = datetime.now()
            self.processing_timestamps[container.id] = process_time

            # Calculate latency
            if container.id in self.event_timestamps:
                emit_time = self.event_timestamps[container.id]
                latency = (process_time - emit_time).total_seconds() * 1000
                self.latencies_ms.append(latency)

    def get_average_latency_ms(self) -> float:
        """Get average latency in milliseconds."""
        if not self.latencies_ms:
            return 0.0
        return sum(self.latencies_ms) / len(self.latencies_ms)

    def get_max_latency_ms(self) -> float:
        """Get maximum latency in milliseconds."""
        if not self.latencies_ms:
            return 0.0
        return max(self.latencies_ms)

    def get_p95_latency_ms(self) -> float:
        """Get 95th percentile latency in milliseconds."""
        if not self.latencies_ms:
            return 0.0
        sorted_latencies = sorted(self.latencies_ms)
        p95_index = int(len(sorted_latencies) * 0.95)
        return sorted_latencies[p95_index] if p95_index < len(sorted_latencies) else sorted_latencies[-1]


@pytest.fixture
def i3_connection():
    """Create mock i3 connection."""
    return MockI3Connection()


@pytest.fixture
def latency_tracker():
    """Create latency tracker."""
    return LatencyTracker()


@pytest.mark.asyncio
async def test_single_event_detection_latency(i3_connection, latency_tracker):
    """Test latency for single window::new event detection.

    Success Criteria (SC-001): 100% window::new events detected
    Performance Target: <50ms detection latency
    """
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit single window::new event
    window = create_ghost_window(window_id=14680068, pid=823199)
    latency_tracker.record_event_emission(window.id)

    event = MockI3Event(event_type="window", change="new", container=window)
    await i3_connection.emit_event(event)

    # Verify event was detected
    assert window.id in latency_tracker.processing_timestamps

    # Verify latency <50ms
    avg_latency = latency_tracker.get_average_latency_ms()
    assert avg_latency < 50, f"Detection latency {avg_latency}ms exceeds 50ms target"


@pytest.mark.asyncio
async def test_average_latency_under_load(i3_connection, latency_tracker):
    """Test average latency with 20+ concurrent window creations.

    Performance Target: <100ms event processing latency under load
    """
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit 20 window::new events rapidly
    for i in range(20):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        latency_tracker.record_event_emission(window.id)

        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)

    # Verify all events processed
    assert len(latency_tracker.latencies_ms) == 20

    # Verify average latency <100ms
    avg_latency = latency_tracker.get_average_latency_ms()
    assert avg_latency < 100, f"Average latency {avg_latency}ms exceeds 100ms target under load"


@pytest.mark.asyncio
async def test_p95_latency_target(i3_connection, latency_tracker):
    """Test 95th percentile latency remains low.

    Performance Target: 95% of events processed in <100ms
    """
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit 100 events for statistical significance
    for i in range(100):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        latency_tracker.record_event_emission(window.id)

        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)

    # Verify all events processed
    assert len(latency_tracker.latencies_ms) == 100

    # Verify p95 latency <100ms
    p95_latency = latency_tracker.get_p95_latency_ms()
    assert p95_latency < 100, f"P95 latency {p95_latency}ms exceeds 100ms target"


@pytest.mark.asyncio
async def test_stress_test_50_concurrent_windows(i3_connection, latency_tracker):
    """Test latency with 50 concurrent window creations (stress test).

    Success Criteria (SC-012): 50 concurrent window creations processed
    Performance Target: Maintain <100ms average latency
    """
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit 50 rapid window::new events
    for i in range(50):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        latency_tracker.record_event_emission(window.id)

        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)

    # Verify all events processed
    assert len(latency_tracker.latencies_ms) == 50

    # Verify average latency <100ms even under stress
    avg_latency = latency_tracker.get_average_latency_ms()
    assert avg_latency < 100, f"Stress test avg latency {avg_latency}ms exceeds 100ms target"


@pytest.mark.asyncio
async def test_latency_consistency_across_event_types(i3_connection, latency_tracker):
    """Test that latency is consistent for different window types."""
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit events for different window types
    windows = [
        create_ghost_window(window_id=14680068, pid=823199),
        create_vscode_window(window_id=37748739, pid=823200),
    ]

    for window in windows:
        latency_tracker.record_event_emission(window.id)
        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)

    # Verify all events processed
    assert len(latency_tracker.latencies_ms) == len(windows)

    # Verify all latencies <50ms
    for latency in latency_tracker.latencies_ms:
        assert latency < 50, f"Window type latency {latency}ms exceeds 50ms target"


@pytest.mark.asyncio
async def test_latency_with_rapid_sequential_events(i3_connection, latency_tracker):
    """Test latency when events arrive in rapid succession (no delays)."""
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit 10 events with no delay
    for i in range(10):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        latency_tracker.record_event_emission(window.id)
        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)
        # No await here - truly rapid

    # Verify all events processed
    assert len(latency_tracker.latencies_ms) == 10

    # Verify max latency <50ms (all events should be fast)
    max_latency = latency_tracker.get_max_latency_ms()
    assert max_latency < 50, f"Max latency {max_latency}ms exceeds 50ms target in rapid sequence"


@pytest.mark.asyncio
async def test_end_to_end_latency_from_event_to_completion(i3_connection, latency_tracker):
    """Test complete end-to-end latency including all processing steps.

    This tests the full pipeline latency from event emission to handler completion.
    """
    # Track completion time
    completion_times: dict[int, datetime] = {}

    async def complete_handler(event, container=None):
        """Handler that simulates full processing."""
        # First record in latency tracker
        await latency_tracker.process_event(event, container)

        # Simulate workspace assignment and marking (typical processing)
        await asyncio.sleep(0.001)  # Simulate i3 command execution

        # Record completion
        if container:
            completion_times[container.id] = datetime.now()

    # Register complete handler
    i3_connection.on("window::new", complete_handler)
    await i3_connection.subscribe(["window"])

    # Emit event
    window = create_ghost_window(window_id=14680068, pid=823199)
    emit_time = datetime.now()

    event = MockI3Event(event_type="window", change="new", container=window)
    await i3_connection.emit_event(event)

    # Calculate end-to-end latency
    completion_time = completion_times[window.id]
    end_to_end_latency_ms = (completion_time - emit_time).total_seconds() * 1000

    # Verify end-to-end latency <100ms
    assert end_to_end_latency_ms < 100, \
        f"End-to-end latency {end_to_end_latency_ms}ms exceeds 100ms target"


@pytest.mark.asyncio
async def test_latency_metrics_accuracy(i3_connection, latency_tracker):
    """Test that latency measurements are accurate and consistent."""
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit 5 events with controlled timing
    for i in range(5):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        latency_tracker.record_event_emission(window.id)
        event = MockI3Event(event_type="window", change="new", container=window)
        await i3_connection.emit_event(event)

    # Verify latencies are reasonable and non-zero
    assert len(latency_tracker.latencies_ms) == 5
    for latency in latency_tracker.latencies_ms:
        assert latency > 0, "Latency should be positive"
        assert latency < 1000, f"Latency {latency}ms seems unreasonably high"

    # Verify average is within expected range
    avg_latency = latency_tracker.get_average_latency_ms()
    assert 0 < avg_latency < 100, f"Average latency {avg_latency}ms out of expected range"


@pytest.mark.asyncio
async def test_zero_latency_impossible(i3_connection, latency_tracker):
    """Test that latency is never exactly zero (sanity check)."""
    # Register event handler
    i3_connection.on("window::new", latency_tracker.process_event)
    await i3_connection.subscribe(["window"])

    # Emit event
    window = create_ghost_window(window_id=14680068, pid=823199)
    latency_tracker.record_event_emission(window.id)
    event = MockI3Event(event_type="window", change="new", container=window)
    await i3_connection.emit_event(event)

    # Verify latency is positive (even if small)
    assert len(latency_tracker.latencies_ms) == 1
    latency = latency_tracker.latencies_ms[0]
    assert latency > 0, "Latency should always be positive (processing takes time)"
