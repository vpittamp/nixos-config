"""
Unit tests for EventBuffer FIFO eviction (Feature 092 - T013)

Tests circular buffer behavior, FIFO eviction when buffer is full.
"""

import pytest
import time
import sys
from pathlib import Path

# Add home-modules to path for imports
sys.path.insert(0, str(Path(__file__).parents[3] / "home-modules/tools"))

from i3_project_manager.cli.monitoring_data import (
    Event,
    SwayEventPayload,
    EventBuffer,
)


def create_test_event(event_id: int) -> Event:
    """Helper to create test events with unique IDs."""
    return Event(
        timestamp=time.time() + event_id,  # Unique timestamp
        timestamp_friendly=f"Event {event_id}",
        event_type="window::new",
        payload=SwayEventPayload(container={"id": event_id}),
        icon="󰖲",
        color="#89b4fa",
        category="window",
        searchable_text=f"event {event_id}",
    )


class TestEventBuffer:
    """Test EventBuffer circular buffer functionality."""

    def test_buffer_initialization(self):
        """Test buffer initializes with correct max_size."""
        buffer = EventBuffer(max_size=500)
        assert buffer.max_size == 500
        assert buffer.size() == 0

    def test_buffer_custom_size(self):
        """Test buffer with custom max_size."""
        buffer = EventBuffer(max_size=10)
        assert buffer.max_size == 10

    def test_buffer_append_single_event(self):
        """Test appending a single event to buffer."""
        buffer = EventBuffer(max_size=500)
        event = create_test_event(1)

        buffer.append(event)

        assert buffer.size() == 1
        events = buffer.get_all()
        assert len(events) == 1
        assert events[0].searchable_text == "event 1"

    def test_buffer_append_multiple_events(self):
        """Test appending multiple events maintains chronological order."""
        buffer = EventBuffer(max_size=500)

        for i in range(10):
            buffer.append(create_test_event(i))

        assert buffer.size() == 10

        events = buffer.get_all()
        assert len(events) == 10

        # Events should be in chronological order (oldest first, newest last)
        for i in range(10):
            assert events[i].searchable_text == f"event {i}"

    def test_buffer_fifo_eviction(self):
        """Test FIFO eviction when buffer reaches max_size."""
        buffer = EventBuffer(max_size=5)  # Small buffer for easy testing

        # Add 6 events (one more than max_size)
        for i in range(6):
            buffer.append(create_test_event(i))

        # Buffer should still be at max_size
        assert buffer.size() == 5

        # Oldest event (event 0) should be evicted
        events = buffer.get_all()
        assert len(events) == 5

        # First event should now be event 1 (event 0 was evicted)
        assert events[0].searchable_text == "event 1"
        assert events[4].searchable_text == "event 5"

    def test_buffer_fifo_eviction_large_batch(self):
        """Test FIFO eviction with large number of events (501 events, max 500)."""
        buffer = EventBuffer(max_size=500)

        # Add 501 events
        for i in range(501):
            buffer.append(create_test_event(i))

        # Buffer should be at max_size
        assert buffer.size() == 500

        # Oldest event (event 0) should be evicted
        events = buffer.get_all()
        assert len(events) == 500

        # First event should now be event 1
        assert events[0].searchable_text == "event 1"
        # Last event should be event 500
        assert events[499].searchable_text == "event 500"

    def test_buffer_clear(self):
        """Test clearing all events from buffer."""
        buffer = EventBuffer(max_size=500)

        for i in range(10):
            buffer.append(create_test_event(i))

        assert buffer.size() == 10

        buffer.clear()

        assert buffer.size() == 0
        assert len(buffer.get_all()) == 0

    def test_buffer_chronological_order(self):
        """Test that get_all() returns events in chronological order."""
        buffer = EventBuffer(max_size=100)

        # Add events with specific timestamps
        for i in range(20):
            event = create_test_event(i)
            buffer.append(event)
            time.sleep(0.001)  # Ensure unique timestamps

        events = buffer.get_all()

        # Verify chronological order (timestamps should increase)
        for i in range(len(events) - 1):
            assert events[i].timestamp < events[i + 1].timestamp

    def test_buffer_thread_safety_assumption(self):
        """Test that buffer works correctly with single writer (event loop)."""
        # Note: EventBuffer is documented as thread-safe for single-writer scenarios
        # This test validates basic sequential append behavior

        buffer = EventBuffer(max_size=500)

        # Simulate event loop appending events sequentially
        for i in range(100):
            buffer.append(create_test_event(i))

        assert buffer.size() == 100

        # All events should be present and in order
        events = buffer.get_all()
        for i in range(100):
            assert events[i].searchable_text == f"event {i}"
