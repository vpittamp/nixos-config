"""Event processing service for i3 window management (Feature 039: T039-T045).

Provides:
- Async event queue with FIFO processing
- Circular event buffer (500 events) for diagnostic replay
- Event processing metrics tracking
- Structured logging with timestamps
- Event queuing for early events before daemon initialization

This service centralizes all event processing logic and provides
comprehensive metrics for the diagnostic tooling.
"""

import asyncio
import logging
from collections import deque
from datetime import datetime
from typing import Any, Callable, Coroutine, Deque, List, Optional
from dataclasses import dataclass, field

from ..models import WindowEvent

logger = logging.getLogger(__name__)


@dataclass
class EventMetrics:
    """Event processing metrics (Feature 039: FR-041)."""

    events_received: int = 0
    events_processed: int = 0
    events_failed: int = 0
    processing_durations_ms: List[float] = field(default_factory=list)

    def record_received(self) -> None:
        """Increment events received counter."""
        self.events_received += 1

    def record_processed(self, duration_ms: float) -> None:
        """Record successful processing with duration."""
        self.events_processed += 1
        self.processing_durations_ms.append(duration_ms)

    def record_failed(self) -> None:
        """Increment events failed counter."""
        self.events_failed += 1

    def get_average_duration_ms(self) -> float:
        """Get average processing duration in milliseconds."""
        if not self.processing_durations_ms:
            return 0.0
        return sum(self.processing_durations_ms) / len(self.processing_durations_ms)

    def get_max_duration_ms(self) -> float:
        """Get maximum processing duration in milliseconds."""
        if not self.processing_durations_ms:
            return 0.0
        return max(self.processing_durations_ms)

    def get_p95_duration_ms(self) -> float:
        """Get 95th percentile processing duration."""
        if not self.processing_durations_ms:
            return 0.0
        sorted_durations = sorted(self.processing_durations_ms)
        p95_index = int(len(sorted_durations) * 0.95)
        return sorted_durations[min(p95_index, len(sorted_durations) - 1)]

    def to_dict(self) -> dict:
        """Convert metrics to dictionary for reporting."""
        return {
            "events_received": self.events_received,
            "events_processed": self.events_processed,
            "events_failed": self.events_failed,
            "average_duration_ms": self.get_average_duration_ms(),
            "max_duration_ms": self.get_max_duration_ms(),
            "p95_duration_ms": self.get_p95_duration_ms(),
        }


@dataclass
class QueuedEvent:
    """Event queued for processing."""

    event: Any
    container: Any
    enqueue_time: datetime
    handler: Callable[[Any, Any], Coroutine[Any, Any, Optional[WindowEvent]]]


class EventProcessor:
    """Central event processing service (Feature 039: US2).

    Handles:
    - Async event queuing with FIFO ordering
    - Circular buffer for event history (500 events)
    - Processing metrics tracking
    - Structured logging
    - Early event queuing before initialization
    """

    def __init__(self, buffer_size: int = 500):
        """Initialize event processor.

        Args:
            buffer_size: Maximum events in circular buffer (default 500)
        """
        self.buffer_size = buffer_size

        # Event queue (FIFO)
        self._event_queue: asyncio.Queue[QueuedEvent] = asyncio.Queue()

        # Circular event buffer for diagnostics (Feature 039: FR-040)
        self._event_buffer: Deque[WindowEvent] = deque(maxlen=buffer_size)

        # Metrics tracking (Feature 039: FR-041)
        self._metrics = EventMetrics()

        # Processing state
        self._processing = False
        self._process_task: Optional[asyncio.Task] = None
        self._initialized = False

        # Early event queue (Feature 039: FR-044)
        self._early_events: List[QueuedEvent] = []

    async def initialize(self) -> None:
        """Mark processor as initialized and process early events.

        Feature 039: FR-044 - Implement event queuing for early events
        """
        self._initialized = True

        # Process any early events that were queued
        if self._early_events:
            logger.info(f"Processing {len(self._early_events)} early events")
            for queued_event in self._early_events:
                await self._event_queue.put(queued_event)
            self._early_events.clear()

    async def enqueue_event(
        self,
        event: Any,
        container: Any,
        handler: Callable[[Any, Any], Coroutine[Any, Any, Optional[WindowEvent]]],
    ) -> None:
        """Enqueue event for processing.

        Args:
            event: i3 event object
            container: i3 container object (window, workspace, etc.)
            handler: Async handler function to process the event

        Feature 039: FR-044 - Queue early events before initialization
        """
        self._metrics.record_received()

        queued_event = QueuedEvent(
            event=event,
            container=container,
            enqueue_time=datetime.now(),
            handler=handler,
        )

        if not self._initialized:
            # Queue early events until initialization complete
            logger.debug(
                f"Queuing early event: {event.change if hasattr(event, 'change') else 'unknown'}"
            )
            self._early_events.append(queued_event)
        else:
            await self._event_queue.put(queued_event)

    async def start_processing(self) -> None:
        """Start event processing loop."""
        if self._processing:
            logger.warning("Event processor already running")
            return

        logger.info("Starting event processor")
        self._processing = True
        self._process_task = asyncio.create_task(self._process_loop())

    async def stop_processing(self) -> None:
        """Stop event processing loop."""
        if not self._processing:
            return

        logger.info("Stopping event processor")
        self._processing = False

        if self._process_task:
            await self._process_task
            self._process_task = None

    async def _process_loop(self) -> None:
        """Main event processing loop (FIFO order).

        Feature 039: T037 - FIFO processing for rapid events
        """
        while self._processing:
            try:
                # Get next event from queue (FIFO)
                queued_event = await asyncio.wait_for(
                    self._event_queue.get(), timeout=0.1
                )

                # Process event
                await self._process_single_event(queued_event)

            except asyncio.TimeoutError:
                # No events in queue, continue
                continue
            except Exception as e:
                logger.error(f"Event processing loop error: {e}", exc_info=True)

        # Drain remaining events when stopping
        while not self._event_queue.empty():
            try:
                queued_event = await asyncio.wait_for(
                    self._event_queue.get(), timeout=0.01
                )
                await self._process_single_event(queued_event)
            except asyncio.TimeoutError:
                break

    async def _process_single_event(self, queued_event: QueuedEvent) -> None:
        """Process a single event and track metrics.

        Feature 039: FR-041 - Track processing duration
        Feature 039: FR-045 - Structured logging
        """
        start_time = datetime.now()
        error: Optional[str] = None
        stack_trace: Optional[str] = None

        try:
            # Call event handler
            window_event = await queued_event.handler(
                queued_event.event, queued_event.container
            )

            # Calculate duration
            duration_ms = (datetime.now() - start_time).total_seconds() * 1000

            # Record success metrics
            self._metrics.record_processed(duration_ms)

            # If handler returned WindowEvent, use it; otherwise create basic one
            if window_event:
                window_event.handler_duration_ms = duration_ms
                self._add_to_buffer(window_event)
            else:
                # Create basic WindowEvent for logging
                event_type = getattr(queued_event.event, "event_type", "unknown")
                event_change = getattr(queued_event.event, "change", "unknown")

                basic_event = WindowEvent(
                    event_type=event_type,
                    event_change=event_change,
                    timestamp=queued_event.enqueue_time,
                    handler_duration_ms=duration_ms,
                )
                self._add_to_buffer(basic_event)

            # Structured logging (Feature 039: FR-045)
            self._log_event_processing(queued_event, duration_ms, error=None)

        except Exception as e:
            # Calculate duration even for failed events
            duration_ms = (datetime.now() - start_time).total_seconds() * 1000

            # Record failure metrics
            self._metrics.record_failed()

            # Capture error details
            error = str(e)
            import traceback
            stack_trace = traceback.format_exc()

            # Create error WindowEvent
            event_type = getattr(queued_event.event, "event_type", "unknown")
            event_change = getattr(queued_event.event, "change", "unknown")

            error_event = WindowEvent(
                event_type=event_type,
                event_change=event_change,
                timestamp=queued_event.enqueue_time,
                handler_duration_ms=duration_ms,
                error=error,
                stack_trace=stack_trace,
            )
            self._add_to_buffer(error_event)

            # Structured logging for errors
            self._log_event_processing(queued_event, duration_ms, error=error)

            logger.error(f"Event processing failed: {error}", exc_info=True)

    def _add_to_buffer(self, window_event: WindowEvent) -> None:
        """Add event to circular buffer.

        Feature 039: FR-040 - Circular event buffer (500 events)
        """
        self._event_buffer.append(window_event)

    def _log_event_processing(
        self,
        queued_event: QueuedEvent,
        duration_ms: float,
        error: Optional[str],
    ) -> None:
        """Structured logging for event processing.

        Feature 039: FR-045 - Structured logging with timestamp, window ID, event type, rule matched
        """
        event = queued_event.event
        container = queued_event.container

        # Extract event details
        event_type = getattr(event, "event_type", "unknown")
        event_change = getattr(event, "change", "unknown")
        window_id = getattr(container, "id", None) if container else None
        window_class = getattr(container, "window_class", None) if container else None

        # Log with structured data
        if error:
            logger.error(
                f"Event processing failed",
                extra={
                    "event_type": event_type,
                    "event_change": event_change,
                    "window_id": window_id,
                    "window_class": window_class,
                    "duration_ms": duration_ms,
                    "enqueue_time": queued_event.enqueue_time.isoformat(),
                    "error": error,
                },
            )
        else:
            logger.debug(
                f"Event processed: {event_type}::{event_change}",
                extra={
                    "event_type": event_type,
                    "event_change": event_change,
                    "window_id": window_id,
                    "window_class": window_class,
                    "duration_ms": duration_ms,
                    "enqueue_time": queued_event.enqueue_time.isoformat(),
                },
            )

    def get_recent_events(self, limit: int = 50) -> List[WindowEvent]:
        """Get recent events from circular buffer.

        Args:
            limit: Maximum number of events to return

        Returns:
            List of recent WindowEvent objects (newest last)
        """
        if limit >= len(self._event_buffer):
            return list(self._event_buffer)
        else:
            # Return last N events
            return list(self._event_buffer)[-limit:]

    def get_metrics(self) -> dict:
        """Get event processing metrics.

        Returns:
            Dictionary with metrics for diagnostic reporting
        """
        return self._metrics.to_dict()

    def get_queue_size(self) -> int:
        """Get current event queue size."""
        return self._event_queue.qsize()

    def get_buffer_size(self) -> int:
        """Get current number of events in buffer."""
        return len(self._event_buffer)

    def get_early_event_count(self) -> int:
        """Get number of early events waiting for initialization."""
        return len(self._early_events)
