"""Cascade Chain Tracking for Secondary/Tertiary Effects

Tracks chains of window state changes to identify primary effects
vs cascade effects (secondary, tertiary).

Example Cascade:
1. User presses Mod+Enter (WINDOW_OPEN)
2. Primary Effect: window::new event (workspace creates container)
3. Secondary Effect: workspace::focus event (new window gets focus)
4. Tertiary Effect: window::focus event (focus changes from old to new)

Each effect in the cascade has decreasing confidence as causality becomes
more indirect.
"""

import time
from collections import deque
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class CascadeChain:
    """
    Represents a chain of cascading effects.

    Attributes:
        primary_event_id: ID of the primary effect (direct result of user action)
        secondary_event_ids: IDs of secondary effects (immediate cascades)
        tertiary_event_ids: IDs of tertiary effects (second-order cascades)
        timestamp_ms: When the cascade chain started
        completed: Whether the cascade chain is complete (no more effects expected)
    """
    primary_event_id: int
    secondary_event_ids: List[int]
    tertiary_event_ids: List[int]
    timestamp_ms: int
    completed: bool = False


class CascadeTracker:
    """
    Tracks cascade chains of window state changes.

    Algorithm:
    1. When an event has a high-confidence correlation, mark it as primary
    2. Track subsequent events within 200ms as potential secondary effects
    3. Track events 200-400ms after primary as tertiary effects
    4. Close cascade chain after 500ms or when no more effects occur

    Performance:
    - O(1) cascade tracking
    - O(n) depth calculation where n = active cascades (typically 1-2)
    - Memory: ~200 bytes per cascade, 5s retention = minimal
    """

    def __init__(self, cascade_window_ms: int = 500):
        """
        Initialize cascade tracker.

        Args:
            cascade_window_ms: Time window for tracking cascades (default: 500ms)
        """
        self.cascade_window_ms = cascade_window_ms
        self.active_cascades: deque[CascadeChain] = deque(maxlen=50)
        self._total_cascades = 0

    def start_cascade(self, primary_event_id: int) -> None:
        """
        Start tracking a new cascade chain.

        Args:
            primary_event_id: ID of the primary effect event
        """
        cascade = CascadeChain(
            primary_event_id=primary_event_id,
            secondary_event_ids=[],
            tertiary_event_ids=[],
            timestamp_ms=int(time.time() * 1000)
        )
        self.active_cascades.append(cascade)
        self._total_cascades += 1

    def add_to_cascade(self, event_id: int, event_timestamp_ms: int) -> Optional[int]:
        """
        Add an event to an active cascade chain if applicable.

        Args:
            event_id: ID of the event to add
            event_timestamp_ms: When the event occurred

        Returns:
            Cascade depth (0=primary, 1=secondary, 2=tertiary) or None if not part of cascade
        """
        # Find the most recent active cascade
        for cascade in reversed(self.active_cascades):
            if cascade.completed:
                continue

            time_delta_ms = event_timestamp_ms - cascade.timestamp_ms

            # Check if event is within cascade window
            if time_delta_ms > self.cascade_window_ms:
                cascade.completed = True
                continue

            # Determine cascade depth based on timing
            if time_delta_ms <= 200:
                # Secondary effect (immediate cascade)
                cascade.secondary_event_ids.append(event_id)
                return 1
            elif time_delta_ms <= 400:
                # Tertiary effect (second-order cascade)
                cascade.tertiary_event_ids.append(event_id)
                return 2
            else:
                # Beyond typical cascade timing, mark as completed
                cascade.completed = True

        return None  # Not part of any cascade

    def get_cascade_depth(self, event_id: int) -> int:
        """
        Get cascade depth for a given event.

        Args:
            event_id: ID of the event

        Returns:
            Cascade depth (0=primary, 1=secondary, 2=tertiary, 3+=very indirect)
        """
        for cascade in self.active_cascades:
            if cascade.primary_event_id == event_id:
                return 0
            elif event_id in cascade.secondary_event_ids:
                return 1
            elif event_id in cascade.tertiary_event_ids:
                return 2

        return 0  # Default to primary if not found

    def cleanup_old_cascades(self, current_time_ms: int) -> None:
        """
        Remove old completed cascades.

        Args:
            current_time_ms: Current timestamp
        """
        cutoff_time_ms = current_time_ms - 5000  # Keep cascades for 5 seconds

        # Remove old cascades from front of deque
        while self.active_cascades and self.active_cascades[0].timestamp_ms < cutoff_time_ms:
            self.active_cascades.popleft()

    def stats(self) -> dict:
        """Get cascade tracker statistics"""
        return {
            'total_cascades_tracked': self._total_cascades,
            'active_cascades': len([c for c in self.active_cascades if not c.completed]),
            'completed_cascades': len([c for c in self.active_cascades if c.completed]),
            'cascade_window_ms': self.cascade_window_ms
        }
