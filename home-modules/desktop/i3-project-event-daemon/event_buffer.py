"""Event buffer for storing recent events (Feature 017).

This module provides a circular buffer for event storage,
enabling event history queries and event stream subscriptions.
"""

from collections import deque
from datetime import datetime
from typing import Callable, Deque, List, Optional, Awaitable, Any

from .models import EventEntry


class EventBuffer:
    """Circular buffer for event storage in daemon.

    Stores the last N events in memory for history queries and debugging.
    Events are stored in FIFO order (oldest evicted when full).
    """

    def __init__(self, max_size: int = 500, broadcast_callback: Optional[Callable[[EventEntry], Awaitable[None]]] = None) -> None:
        """Initialize event buffer.

        Args:
            max_size: Maximum number of events to store (default: 500)
            broadcast_callback: Optional async callback to broadcast events to subscribers
        """
        self.events: Deque[EventEntry] = deque(maxlen=max_size)
        self.event_counter: int = 0
        self.max_size: int = max_size
        self.broadcast_callback = broadcast_callback

    async def add_event(self, event: EventEntry) -> None:
        """Add event to buffer (FIFO, oldest evicted) and broadcast to subscribers.

        Args:
            event: EventEntry to add to buffer
        """
        self.events.append(event)
        self.event_counter += 1

        # Broadcast to subscribers if callback is set (Feature 017: T019)
        if self.broadcast_callback:
            await self.broadcast_callback(event)

    def get_events(
        self,
        limit: int = 100,
        event_type: Optional[str] = None,
        since_id: Optional[int] = None
    ) -> List[EventEntry]:
        """Retrieve events with optional filtering.

        Args:
            limit: Maximum number of events to return (default: 100)
            event_type: Filter by event type prefix (e.g., "window", "workspace")
            since_id: Only return events with ID greater than this value

        Returns:
            List of EventEntry objects (most recent first)
        """
        # Filter by event type if specified
        filtered = self.events
        if event_type:
            filtered = [e for e in self.events if e.event_type.startswith(event_type)]
        else:
            filtered = list(self.events)

        # Filter by since_id if specified
        if since_id is not None:
            filtered = [e for e in filtered if e.event_id > since_id]

        # Return most recent N events (reverse chronological order)
        return list(filtered)[-limit:][::-1]

    def get_stats(self) -> dict:
        """Get buffer statistics.

        Returns:
            Dictionary with buffer stats: total_events, buffer_size, max_size
        """
        return {
            "total_events": self.event_counter,
            "buffer_size": len(self.events),
            "max_size": self.max_size
        }

    def clear(self) -> None:
        """Clear all events from buffer."""
        self.events.clear()
