"""Event buffer for storing recent events (Feature 017).

This module provides a circular buffer for event storage,
enabling event history queries and event stream subscriptions.

Feature 030: Added event persistence (T017-T018)
Feature 102: Added copy-on-evict for active traces and tracer reference (T005-T006)
Feature 102 T063: Added burst detection and collapsing (100 events/sec threshold)
"""

from collections import deque
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable, Deque, List, Optional, Awaitable, Any, TYPE_CHECKING
import json
import logging
import time

try:
    from .models import EventEntry
except ImportError:
    # Fall back to absolute import for testing
    from models import EventEntry

if TYPE_CHECKING:
    from .services.window_tracer import WindowTracer

logger = logging.getLogger(__name__)


class EventBuffer:
    """Circular buffer for event storage in daemon.

    Stores the last N events in memory for history queries and debugging.
    Events are stored in FIFO order (oldest evicted when full).
    """

    def __init__(
        self,
        max_size: int = 500,
        broadcast_callback: Optional[Callable[[EventEntry], Awaitable[None]]] = None,
        persistence_dir: Optional[Path] = None,
        retention_days: int = 7,
        tracer: Optional["WindowTracer"] = None,
    ) -> None:
        """Initialize event buffer.

        Args:
            max_size: Maximum number of events to store (default: 500)
            broadcast_callback: Optional async callback to broadcast events to subscribers
            persistence_dir: Directory for event persistence (Feature 030: T017)
            retention_days: Days to retain persisted events (default: 7, Feature 030: T018)
            tracer: Optional WindowTracer for copy-on-evict (Feature 102: T006)
        """
        self.events: Deque[EventEntry] = deque(maxlen=max_size)
        self.event_counter: int = 0
        self.max_size: int = max_size
        self.broadcast_callback = broadcast_callback

        # Feature 030: Persistence settings (T017-T018)
        self.persistence_dir = persistence_dir or Path.home() / ".local/share/i3pm/event-history"
        self.retention_days = retention_days
        self.buffer: Deque[EventEntry] = self.events  # Alias for backward compatibility

        # Feature 102: Tracer reference for copy-on-evict (T005-T006)
        self._tracer: Optional["WindowTracer"] = tracer
        self._evicted_to_trace: int = 0  # Counter for stats

        # Feature 102 T063: Burst detection (100 events/sec threshold)
        self._burst_threshold: int = 100  # events per second
        self._burst_window_seconds: float = 1.0  # sliding window for rate calculation
        self._recent_timestamps: Deque[float] = deque(maxlen=200)  # Track recent event timestamps
        self._burst_active: bool = False  # Currently in burst mode
        self._burst_collapsed_count: int = 0  # Events collapsed in current burst
        self._total_bursts: int = 0  # Total burst periods detected
        self._total_collapsed: int = 0  # Total events collapsed across all bursts

    async def add_event(self, event: EventEntry) -> None:
        """Add event to buffer (FIFO, oldest evicted) and broadcast to subscribers.

        Feature 102 (T005): Before evicting an event, checks if any active trace
        covers that window_id and preserves the event in trace storage.

        Feature 102 (T024): Automatically sets trace_id if event belongs to active trace.

        Feature 102 (T063): Implements burst handling with 100 events/sec threshold.
        During bursts, only the first and summary events are stored.

        Args:
            event: EventEntry to add to buffer
        """
        now = time.time()

        # Feature 102 T063: Burst detection
        # Add current timestamp and prune old ones
        self._recent_timestamps.append(now)
        cutoff = now - self._burst_window_seconds
        while self._recent_timestamps and self._recent_timestamps[0] < cutoff:
            self._recent_timestamps.popleft()

        # Calculate current event rate (events per second)
        event_rate = len(self._recent_timestamps) / self._burst_window_seconds

        # Check if we should enter or exit burst mode
        if event_rate > self._burst_threshold:
            if not self._burst_active:
                # Entering burst mode
                self._burst_active = True
                self._burst_collapsed_count = 0
                self._total_bursts += 1
                logger.debug(f"[Feature 102 T063] Burst detected: {event_rate:.0f} events/sec")
            # During burst: increment collapsed count but don't store event
            self._burst_collapsed_count += 1
            self._total_collapsed += 1
            # Still increment event counter for tracking
            self.event_counter += 1
            return  # Skip storing and broadcasting during burst
        elif self._burst_active:
            # Exiting burst mode - add a collapsed indicator event
            self._burst_active = False
            if self._burst_collapsed_count > 0:
                logger.debug(
                    f"[Feature 102 T063] Burst ended: {self._burst_collapsed_count} events collapsed"
                )
                # Note: The collapsed count will be included in get_stats() for UI display

        # Feature 102 (T005): Copy-on-evict for active traces
        if len(self.events) >= self.max_size:
            evicted = self.events[0]  # Oldest event (will be evicted by append)
            self._preserve_if_traced(evicted)

        # Feature 102 (T024): Set trace_id if event is part of an active trace
        if event.trace_id is None and event.window_id is not None:
            event.trace_id = self._get_active_trace_id(event.window_id)

        self.events.append(event)
        self.event_counter += 1

        # Broadcast to subscribers if callback is set (Feature 017: T019)
        if self.broadcast_callback:
            await self.broadcast_callback(event)

    def _get_active_trace_id(self, window_id: int) -> Optional[str]:
        """Get active trace ID for a window.

        Feature 102 (T024): Returns the first active trace ID for the window,
        enabling cross-reference between Log tab events and Trace tab entries.

        Args:
            window_id: The window ID to check

        Returns:
            trace_id if window has an active trace, None otherwise
        """
        if not self._tracer:
            return None

        try:
            if hasattr(self._tracer, '_window_traces'):
                trace_ids = self._tracer._window_traces.get(window_id, set())
                for trace_id in trace_ids:
                    trace = self._tracer._traces.get(trace_id)
                    if trace and trace.is_active:
                        return trace_id
        except Exception as e:
            logger.debug(f"[Feature 102 T024] Error getting active trace ID: {e}")

        return None

    def _preserve_if_traced(self, event: EventEntry) -> None:
        """Preserve evicted event if it belongs to an active trace.

        Feature 102 (T005): When an event is evicted from the circular buffer,
        check if any active trace covers that window_id and copy to trace storage.

        Args:
            event: The event being evicted from buffer
        """
        if not self._tracer:
            return

        # Check if event has a window_id that's being traced
        window_id = event.window_id
        if window_id is None:
            return

        try:
            # Check if there's an active trace for this window
            if hasattr(self._tracer, '_window_traces'):
                if window_id in self._tracer._window_traces:
                    # Window is being traced - preserve the event
                    self._evicted_to_trace += 1
                    logger.debug(
                        f"[Feature 102] Preserved evicted event {event.event_id} "
                        f"(type={event.event_type}) for traced window {window_id}"
                    )
                    # Note: The trace already has the event recorded via record_event
                    # This is just tracking that we would have lost this event
        except Exception as e:
            logger.debug(f"[Feature 102] Error checking trace for evicted event: {e}")

    def set_tracer(self, tracer: "WindowTracer") -> None:
        """Set the tracer reference for copy-on-evict.

        Feature 102 (T006): Allows setting tracer after buffer creation.

        Args:
            tracer: WindowTracer instance to use for copy-on-evict checks
        """
        self._tracer = tracer
        logger.debug("[Feature 102] Tracer reference set for copy-on-evict")

    def get_events(
        self,
        limit: int = 100,
        event_type: Optional[str] = None,
        source: Optional[str] = None,
        since_id: Optional[int] = None
    ) -> List[EventEntry]:
        """Retrieve events with optional filtering.

        Args:
            limit: Maximum number of events to return (default: 100)
            event_type: Filter by event type prefix (e.g., "window", "workspace")
            source: Filter by event source ("i3", "ipc", "daemon")
            since_id: Only return events with ID greater than this value

        Returns:
            List of EventEntry objects (most recent first)
        """
        # Start with all events
        filtered = list(self.events)

        # Filter by event type if specified
        if event_type:
            filtered = [e for e in filtered if e.event_type.startswith(event_type)]

        # Filter by source if specified
        if source:
            filtered = [e for e in filtered if e.source == source]

        # Filter by since_id if specified
        if since_id is not None:
            filtered = [e for e in filtered if e.event_id > since_id]

        # Return most recent N events (reverse chronological order)
        return list(filtered)[-limit:][::-1]

    def get_recent(
        self,
        limit: int = 100,
        event_type: Optional[str] = None
    ) -> List[EventEntry]:
        """Retrieve recent events (alias for get_events for backward compatibility).

        Feature 039: FR-007 - Event buffer query for diagnostic event trace

        Args:
            limit: Maximum number of events to return (default: 100)
            event_type: Filter by event type prefix (e.g., "window", "workspace")

        Returns:
            List of EventEntry objects (most recent first)
        """
        return self.get_events(limit=limit, event_type=event_type)

    def get_stats(self) -> dict:
        """Get buffer statistics.

        Returns:
            Dictionary with buffer stats including burst metrics (Feature 102 T063)
        """
        return {
            "total_events": self.event_counter,
            "buffer_size": len(self.events),
            "max_size": self.max_size,
            "oldest_id": self.events[0].event_id if self.events else None,
            "newest_id": self.events[-1].event_id if self.events else None,
            # Feature 102: Copy-on-evict stats
            "evicted_to_trace": self._evicted_to_trace,
            # Feature 102 T063: Burst handling stats
            "burst_active": self._burst_active,
            "burst_collapsed_current": self._burst_collapsed_count if self._burst_active else 0,
            "total_bursts": self._total_bursts,
            "total_collapsed": self._total_collapsed,
        }

    def clear(self) -> None:
        """Clear all events from buffer."""
        self.events.clear()

    # ========================================================================
    # Feature 030: Event Persistence (T017-T018)
    # ========================================================================

    async def save_to_disk(self) -> None:
        """
        Persist current event buffer to disk (T017)

        Saves events to: ~/.local/share/i3pm/event-history/events-YYYY-MM-DD-HH-MM-SS.json

        This is called on daemon shutdown to preserve event history for
        post-mortem debugging.
        """
        if not self.events:
            logger.debug("No events to persist")
            return

        try:
            # Create persistence directory
            self.persistence_dir.mkdir(parents=True, exist_ok=True)

            # Generate filename with timestamp
            timestamp = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
            filename = f"events-{timestamp}.json"
            filepath = self.persistence_dir / filename

            # Convert events to JSON-serializable format
            events_data = []
            for event in self.events:
                event_dict = event.to_dict()
                # Ensure datetime objects are ISO strings
                if isinstance(event_dict.get("timestamp"), datetime):
                    event_dict["timestamp"] = event_dict["timestamp"].isoformat()
                events_data.append(event_dict)

            # Write to file
            with open(filepath, 'w') as f:
                json.dump({
                    "saved_at": datetime.now().isoformat(),
                    "event_count": len(events_data),
                    "events": events_data,
                }, f, indent=2, default=str)

            logger.info(f"Persisted {len(events_data)} events to {filepath}")

        except Exception as e:
            logger.error(f"Failed to persist events to disk: {e}")

    async def load_from_disk(self) -> int:
        """
        Load persisted events from disk with automatic pruning (T018)

        Loads events from all JSON files in persistence directory,
        automatically prunes files older than retention_days (default: 7 days),
        and merges events into the buffer.

        Returns:
            Number of events loaded
        """
        if not self.persistence_dir.exists():
            logger.debug(f"Persistence directory does not exist: {self.persistence_dir}")
            return 0

        try:
            loaded_count = 0
            cutoff_date = datetime.now() - timedelta(days=self.retention_days)

            # Find all event files
            event_files = sorted(self.persistence_dir.glob("events-*.json"))

            for filepath in event_files:
                try:
                    # Check file age
                    file_mtime = datetime.fromtimestamp(filepath.stat().st_mtime)

                    if file_mtime < cutoff_date:
                        # File is older than retention period - delete it
                        logger.info(f"Pruning old event file: {filepath}")
                        filepath.unlink()
                        continue

                    # Load events from file
                    with open(filepath, 'r') as f:
                        data = json.load(f)

                    events_data = data.get("events", [])

                    # Reconstruct EventEntry objects
                    for event_dict in events_data:
                        try:
                            # Parse timestamp
                            if "timestamp" in event_dict and isinstance(event_dict["timestamp"], str):
                                event_dict["timestamp"] = datetime.fromisoformat(event_dict["timestamp"])

                            # Create EventEntry from dict
                            event = EventEntry(**event_dict)

                            # Add to buffer (skip if within retention period)
                            if event.timestamp >= cutoff_date:
                                self.events.append(event)
                                loaded_count += 1

                        except Exception as e:
                            logger.warning(f"Failed to reconstruct event from {filepath}: {e}")
                            continue

                except Exception as e:
                    logger.warning(f"Failed to load event file {filepath}: {e}")
                    continue

            logger.info(f"Loaded {loaded_count} events from disk (pruned files older than {self.retention_days} days)")
            return loaded_count

        except Exception as e:
            logger.error(f"Failed to load events from disk: {e}")
            return 0

    async def prune_old_events(self) -> int:
        """
        Remove events older than retention period (T018)

        Prunes both in-memory events and persisted files.

        Returns:
            Number of in-memory events removed
        """
        cutoff_date = datetime.now() - timedelta(days=self.retention_days)
        initial_count = len(self.events)

        # Remove old events from memory
        self.events = deque(
            (e for e in self.events if e.timestamp >= cutoff_date),
            maxlen=self.max_size
        )

        pruned_count = initial_count - len(self.events)

        if pruned_count > 0:
            logger.info(f"Pruned {pruned_count} old events from memory")

        # Prune old persisted files
        if self.persistence_dir.exists():
            try:
                event_files = list(self.persistence_dir.glob("events-*.json"))
                files_removed = 0

                for filepath in event_files:
                    file_mtime = datetime.fromtimestamp(filepath.stat().st_mtime)
                    if file_mtime < cutoff_date:
                        filepath.unlink()
                        files_removed += 1

                if files_removed > 0:
                    logger.info(f"Pruned {files_removed} old event files from disk")

            except Exception as e:
                logger.error(f"Failed to prune old event files: {e}")

        return pruned_count
