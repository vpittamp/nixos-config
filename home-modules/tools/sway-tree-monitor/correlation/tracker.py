"""User Action Correlation Tracker

Correlates tree change events with user actions (keypresses, window focus)
within a temporal window to determine causality.

Temporal Window:
- 500ms window after user action to capture immediate effects
- Tracks both primary effects (direct) and cascade chains (indirect)

Correlation Confidence:
- Temporal proximity: 40% (closer in time = higher confidence)
- Semantic relevance: 30% (action type matches effect)
- Exclusivity: 20% (only one action in window)
- Cascade strength: 10% (how many effects in chain)
"""

import time
from collections import deque
from typing import Optional, List, Tuple
from dataclasses import dataclass, field

from ..models import UserAction, EventCorrelation, ActionType


@dataclass
class ActionWindow:
    """
    Tracks a user action and its temporal window for correlation.

    Attributes:
        action: The user action (keypress, click, etc.)
        timestamp_ms: When the action occurred
        window_end_ms: When the correlation window closes (action + 500ms)
        correlated_events: List of event IDs that were correlated with this action
    """
    action: UserAction
    timestamp_ms: int
    window_end_ms: int
    correlated_events: List[int] = field(default_factory=list)

    def is_active(self, current_time_ms: int) -> bool:
        """Check if this action's correlation window is still active"""
        return current_time_ms <= self.window_end_ms

    def add_correlation(self, event_id: int) -> None:
        """Record that an event was correlated with this action"""
        self.correlated_events.append(event_id)


class CorrelationTracker:
    """
    Tracks user actions and correlates them with tree change events.

    Algorithm:
    1. Maintain rolling window of recent user actions (last 5 seconds)
    2. When tree event occurs, check all active action windows (≤500ms old)
    3. Calculate confidence score for each potential correlation
    4. Return correlations sorted by confidence

    Performance:
    - O(1) action tracking
    - O(n) event correlation where n = active windows (typically 1-3)
    - Memory: ~100 bytes per action, 5s retention = ~500 actions max
    """

    def __init__(self, correlation_window_ms: int = 500, retention_period_ms: int = 5000):
        """
        Initialize correlation tracker.

        Args:
            correlation_window_ms: Time window for correlating events with actions (default: 500ms)
            retention_period_ms: How long to keep action history (default: 5000ms)
        """
        self.correlation_window_ms = correlation_window_ms
        self.retention_period_ms = retention_period_ms

        # Rolling deque of recent actions (time-ordered)
        self.action_history: deque[ActionWindow] = deque(maxlen=100)

        # Stats
        self._total_actions = 0
        self._total_correlations = 0
        self._correlation_id_counter = 0
        self._last_cleanup_ms = int(time.time() * 1000)

    def track_action(self, action: UserAction) -> None:
        """
        Track a user action for future correlation.

        Args:
            action: User action (keypress, click, etc.)
        """
        current_time_ms = int(time.time() * 1000)

        # Clean up old actions periodically
        if current_time_ms - self._last_cleanup_ms > 1000:  # Every 1s
            self._cleanup_old_actions(current_time_ms)

        # Create action window
        window = ActionWindow(
            action=action,
            timestamp_ms=action.timestamp_ms,
            window_end_ms=action.timestamp_ms + self.correlation_window_ms
        )

        self.action_history.append(window)
        self._total_actions += 1

    def correlate_event(
        self,
        event_id: int,
        event_type: str,
        event_timestamp_ms: int,
        affected_window_ids: Optional[List[int]] = None
    ) -> List[EventCorrelation]:
        """
        Find user actions that may have caused this tree event.

        Args:
            event_id: Unique event identifier
            event_type: Type of event (e.g., "window::new", "workspace::focus")
            event_timestamp_ms: When the event occurred
            affected_window_ids: List of window IDs affected by this event

        Returns:
            List of correlations sorted by confidence (highest first)
        """
        correlations = []

        # Find all active action windows at event time
        for window in self.action_history:
            # Skip if action is after event (causality violation)
            if window.timestamp_ms > event_timestamp_ms:
                continue

            # Skip if action is outside correlation window
            time_delta_ms = event_timestamp_ms - window.timestamp_ms
            if time_delta_ms > self.correlation_window_ms:
                continue

            # Calculate confidence (will be refined by scoring.py)
            # For now, just use temporal proximity
            confidence = self._calculate_temporal_confidence(time_delta_ms)

            # Create correlation
            self._correlation_id_counter += 1
            correlation = EventCorrelation(
                correlation_id=self._correlation_id_counter,
                user_action=window.action,
                tree_event_id=event_id,
                time_delta_ms=time_delta_ms,
                confidence_score=confidence,
                confidence_factors={
                    'temporal': confidence * 100,
                    'semantic': 0.0,  # Not yet implemented
                    'exclusivity': 0.0,  # Not yet implemented
                    'cascade': 0.0  # Not yet implemented
                },
                cascade_level=0
            )

            correlations.append(correlation)
            window.add_correlation(event_id)
            self._total_correlations += 1

        # Sort by confidence (highest first)
        correlations.sort(key=lambda c: c.confidence_score, reverse=True)

        return correlations

    def _calculate_temporal_confidence(self, time_delta_ms: int) -> float:
        """
        Calculate confidence based on temporal proximity.

        Scoring:
        - 0-100ms: 1.0 (very likely)
        - 100-250ms: 0.8 (likely)
        - 250-400ms: 0.5 (possible)
        - 400-500ms: 0.3 (unlikely but possible)

        Args:
            time_delta_ms: Time between action and event

        Returns:
            Confidence score [0.0, 1.0]
        """
        if time_delta_ms <= 100:
            return 1.0
        elif time_delta_ms <= 250:
            return 0.8
        elif time_delta_ms <= 400:
            return 0.5
        else:
            return 0.3

    def _cleanup_old_actions(self, current_time_ms: int) -> None:
        """Remove actions older than retention period"""
        cutoff_time_ms = current_time_ms - self.retention_period_ms

        # Remove old actions from front of deque
        while self.action_history and self.action_history[0].timestamp_ms < cutoff_time_ms:
            self.action_history.popleft()

        self._last_cleanup_ms = current_time_ms

    def stats(self) -> dict:
        """Get correlation tracker statistics"""
        return {
            'total_actions_tracked': self._total_actions,
            'total_correlations_made': self._total_correlations,
            'active_action_windows': len(self.action_history),
            'correlation_window_ms': self.correlation_window_ms,
            'retention_period_ms': self.retention_period_ms
        }
