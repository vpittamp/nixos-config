"""Unit tests for event processor service (Feature 039: T037, T041, T045).

Tests verify FIFO event ordering, metrics tracking, and structured logging.
"""

import pytest
import asyncio
from datetime import datetime
from typing import List

from tests.i3_project_daemon.fixtures.mock_i3 import (
    MockI3Event,
    create_ghost_window,
    create_vscode_window,
)


class MockEventProcessor:
    """Mock event processor for testing event ordering and metrics.

    This will be replaced by the actual event_processor.py implementation.
    For now, it serves as a test specification.
    """

    def __init__(self, buffer_size: int = 500):
        """Initialize event processor."""
        self.buffer_size = buffer_size
        self.event_queue: asyncio.Queue = asyncio.Queue()
        self.event_buffer: List[dict] = []  # Circular buffer
        self.buffer_index = 0

        # Metrics (FR-041)
        self.events_received = 0
        self.events_processed = 0
        self.events_failed = 0
        self.processing_durations: List[float] = []

        # Processing state
        self._processing = False
        self._process_task: asyncio.Task | None = None

    async def enqueue_event(self, event: MockI3Event, container=None):
        """Add event to processing queue."""
        self.events_received += 1
        await self.event_queue.put((event, container, datetime.now()))

    async def start_processing(self):
        """Start event processing loop."""
        self._processing = True
        self._process_task = asyncio.create_task(self._process_loop())

    async def stop_processing(self):
        """Stop event processing loop."""
        self._processing = False
        if self._process_task:
            await self._process_task

    async def _process_loop(self):
        """Process events from queue (FIFO order)."""
        while self._processing or not self.event_queue.empty():
            try:
                # Get event from queue (FIFO)
                event, container, enqueue_time = await asyncio.wait_for(
                    self.event_queue.get(), timeout=0.1
                )

                # Process event
                start_time = datetime.now()
                try:
                    await self._process_event(event, container)
                    self.events_processed += 1
                except Exception as e:
                    self.events_failed += 1
                    raise
                finally:
                    # Track processing duration
                    duration_ms = (datetime.now() - start_time).total_seconds() * 1000
                    self.processing_durations.append(duration_ms)

                    # Add to circular buffer (FR-040)
                    self._add_to_buffer({
                        "event_type": event.event_type,
                        "event_change": event.change,
                        "window_id": container.id if container else None,
                        "window_class": container.window_class if container else None,
                        "timestamp": enqueue_time,
                        "handler_duration_ms": duration_ms,
                        "error": None
                    })

            except asyncio.TimeoutError:
                continue

    async def _process_event(self, event: MockI3Event, container):
        """Process a single event (placeholder for actual logic)."""
        # Simulate processing delay
        await asyncio.sleep(0.001)

    def _add_to_buffer(self, event_data: dict):
        """Add event to circular buffer (FR-040)."""
        if len(self.event_buffer) < self.buffer_size:
            self.event_buffer.append(event_data)
        else:
            # Circular buffer: overwrite oldest
            self.event_buffer[self.buffer_index] = event_data
            self.buffer_index = (self.buffer_index + 1) % self.buffer_size

    def get_recent_events(self, limit: int = 50) -> List[dict]:
        """Get recent events from buffer."""
        if len(self.event_buffer) < self.buffer_size:
            # Buffer not full yet
            return self.event_buffer[-limit:]
        else:
            # Buffer is full, return last N in order
            return [
                self.event_buffer[(self.buffer_index - limit + i) % self.buffer_size]
                for i in range(limit)
            ]

    def get_metrics(self) -> dict:
        """Get processing metrics."""
        return {
            "events_received": self.events_received,
            "events_processed": self.events_processed,
            "events_failed": self.events_failed,
            "avg_processing_duration_ms": (
                sum(self.processing_durations) / len(self.processing_durations)
                if self.processing_durations else 0
            ),
            "max_processing_duration_ms": max(self.processing_durations) if self.processing_durations else 0,
        }


@pytest.fixture
def event_processor():
    """Create mock event processor."""
    return MockEventProcessor(buffer_size=500)


@pytest.mark.asyncio
async def test_fifo_event_ordering(event_processor):
    """Test that events are processed in FIFO order.

    User Story 2 Test Requirement (T037): Verify FIFO processing for rapid events
    """
    # Start processing
    await event_processor.start_processing()

    # Enqueue 10 events rapidly
    windows = []
    for i in range(10):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        windows.append(window)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing to complete
    await asyncio.sleep(0.1)
    await event_processor.stop_processing()

    # Verify all events were processed
    assert event_processor.events_processed == 10

    # Verify FIFO order in circular buffer
    recent_events = event_processor.get_recent_events(limit=10)
    for i, event_data in enumerate(recent_events):
        expected_window_id = 14680068 + i
        assert event_data["window_id"] == expected_window_id, \
            f"Event {i} has wrong window_id: {event_data['window_id']} != {expected_window_id}"


@pytest.mark.asyncio
async def test_concurrent_event_queuing(event_processor):
    """Test that concurrent events are queued correctly."""
    # Start processing
    await event_processor.start_processing()

    # Enqueue events concurrently
    async def enqueue_events(start_id: int, count: int):
        for i in range(count):
            window = create_ghost_window(window_id=start_id + i, pid=823199 + i)
            event = MockI3Event(event_type="window", change="new", container=window)
            await event_processor.enqueue_event(event, window)

    # Run 3 concurrent enqueuers
    await asyncio.gather(
        enqueue_events(1000, 10),
        enqueue_events(2000, 10),
        enqueue_events(3000, 10),
    )

    # Wait for processing
    await asyncio.sleep(0.2)
    await event_processor.stop_processing()

    # Verify all 30 events were processed
    assert event_processor.events_processed == 30
    assert event_processor.events_failed == 0


@pytest.mark.asyncio
async def test_event_metrics_tracking(event_processor):
    """Test that event processing metrics are tracked correctly.

    Functional Requirement (FR-041): Add event processing metrics
    """
    # Start processing
    await event_processor.start_processing()

    # Process 20 events
    for i in range(20):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.2)
    await event_processor.stop_processing()

    # Get metrics
    metrics = event_processor.get_metrics()

    # Verify metrics
    assert metrics["events_received"] == 20
    assert metrics["events_processed"] == 20
    assert metrics["events_failed"] == 0
    assert metrics["avg_processing_duration_ms"] > 0
    assert metrics["max_processing_duration_ms"] > 0


@pytest.mark.asyncio
async def test_circular_event_buffer_size_limit(event_processor):
    """Test that circular buffer respects size limit (500 events).

    Functional Requirement (FR-040): Implement circular event buffer
    """
    # Start processing
    await event_processor.start_processing()

    # Enqueue 600 events (exceeds buffer size of 500)
    for i in range(600):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.5)
    await event_processor.stop_processing()

    # Verify buffer size is exactly 500 (not 600)
    assert len(event_processor.event_buffer) == 500

    # Verify oldest events were overwritten (should contain events 100-599)
    recent_events = event_processor.get_recent_events(limit=500)
    first_event = recent_events[0]
    last_event = recent_events[-1]

    # First event in buffer should be ~event 100 (oldest 100 were overwritten)
    assert first_event["window_id"] >= 14680068 + 100
    # Last event should be event 599
    assert last_event["window_id"] == 14680068 + 599


@pytest.mark.asyncio
async def test_event_buffer_recent_events_ordering(event_processor):
    """Test that get_recent_events returns events in correct order."""
    # Start processing
    await event_processor.start_processing()

    # Enqueue 100 events
    for i in range(100):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.2)
    await event_processor.stop_processing()

    # Get last 10 events
    recent_events = event_processor.get_recent_events(limit=10)

    # Verify they are the last 10 in order
    assert len(recent_events) == 10
    for i, event_data in enumerate(recent_events):
        expected_window_id = 14680068 + 90 + i  # Events 90-99
        assert event_data["window_id"] == expected_window_id


@pytest.mark.asyncio
async def test_event_processing_duration_tracking(event_processor):
    """Test that processing duration is tracked for each event.

    Functional Requirement (FR-041): processing_duration histogram
    """
    # Start processing
    await event_processor.start_processing()

    # Process 10 events
    for i in range(10):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.2)
    await event_processor.stop_processing()

    # Verify duration tracking
    assert len(event_processor.processing_durations) == 10
    for duration in event_processor.processing_durations:
        assert duration > 0  # All should have some duration


@pytest.mark.asyncio
async def test_event_buffer_contains_structured_data(event_processor):
    """Test that event buffer contains structured event data.

    Functional Requirement (FR-045): Structured logging with timestamp, window ID, event type, rule matched
    """
    # Start processing
    await event_processor.start_processing()

    # Process event
    window = create_ghost_window(window_id=14680068, pid=823199)
    event = MockI3Event(event_type="window", change="new", container=window)
    await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.1)
    await event_processor.stop_processing()

    # Get event from buffer
    recent_events = event_processor.get_recent_events(limit=1)
    assert len(recent_events) == 1

    event_data = recent_events[0]

    # Verify structured data fields
    assert "event_type" in event_data
    assert "event_change" in event_data
    assert "window_id" in event_data
    assert "window_class" in event_data
    assert "timestamp" in event_data
    assert "handler_duration_ms" in event_data

    # Verify values
    assert event_data["event_type"] == "window"
    assert event_data["event_change"] == "new"
    assert event_data["window_id"] == 14680068
    assert event_data["window_class"] == "com.mitchellh.ghostty"
    assert isinstance(event_data["timestamp"], datetime)
    assert event_data["handler_duration_ms"] > 0


@pytest.mark.asyncio
async def test_event_processing_performance_target(event_processor):
    """Test that event processing meets <100ms target.

    Performance Target: <100ms event processing latency
    """
    # Start processing
    await event_processor.start_processing()

    # Process 20 events
    for i in range(20):
        window = create_ghost_window(window_id=14680068 + i, pid=823199 + i)
        event = MockI3Event(event_type="window", change="new", container=window)
        await event_processor.enqueue_event(event, window)

    # Wait for processing
    await asyncio.sleep(0.3)
    await event_processor.stop_processing()

    # Verify all events processed
    assert event_processor.events_processed == 20

    # Verify average processing time <100ms
    metrics = event_processor.get_metrics()
    assert metrics["avg_processing_duration_ms"] < 100, \
        f"Average processing time {metrics['avg_processing_duration_ms']}ms exceeds 100ms target"
