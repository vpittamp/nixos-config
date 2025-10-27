"""Launch Registry for IPC Launch Context.

This module manages pending application launches awaiting correlation with new windows.
Each pending launch represents a notification sent by the launcher wrapper before executing
an application, containing project context and expected window properties.

Feature 041: IPC Launch Context - T008
"""

import asyncio
import logging
import time
from typing import Dict, Optional

from ..models import (
    PendingLaunch,
    LaunchWindowInfo,
    LaunchRegistryStats,
)

logger = logging.getLogger(__name__)


class LaunchRegistry:
    """
    Manages pending launches with automatic expiration.

    The registry stores launch notifications from the wrapper script and provides
    correlation queries for newly created windows. Launches expire after a configurable
    timeout (default 5 seconds) to prevent unbounded memory growth.

    Feature 041: IPC Launch Context - T008
    Security (T048): Resource limits prevent DoS via excessive launch notifications
    """

    MAX_PENDING_LAUNCHES = 1000  # Security: Prevent unbounded growth (T048)

    def __init__(self, timeout: float = 5.0):
        """
        Initialize launch registry.

        Args:
            timeout: Launch expiration timeout in seconds (default: 5.0)
        """
        self._launches: Dict[str, PendingLaunch] = {}
        self._timeout = timeout

        # Statistics counters
        self._total_notifications = 0
        self._total_matched = 0
        self._total_expired = 0
        self._total_failed_correlation = 0

        logger.info(f"LaunchRegistry initialized with timeout={timeout}s, max_pending={self.MAX_PENDING_LAUNCHES}")

    async def add(self, launch: PendingLaunch) -> str:
        """
        Add a pending launch to the registry.

        Triggers automatic cleanup of expired launches before adding.

        Args:
            launch: PendingLaunch to register

        Returns:
            str: Launch ID (for reference/logging)

        Raises:
            RuntimeError: If maximum pending launches limit reached (security: T048)
        """
        # Cleanup expired launches first
        await self._cleanup_expired()

        # Security T048: Check resource limit to prevent DoS
        if len(self._launches) >= self.MAX_PENDING_LAUNCHES:
            logger.error(
                f"Launch registry at maximum capacity ({self.MAX_PENDING_LAUNCHES}). "
                f"Rejecting launch notification for {launch.app_name}"
            )
            raise RuntimeError(
                f"Maximum pending launches ({self.MAX_PENDING_LAUNCHES}) reached. "
                "Too many pending launches. Wait for existing launches to expire or match."
            )

        # Generate unique launch ID
        launch_id = f"{launch.app_name}-{launch.timestamp}"

        # Store launch
        self._launches[launch_id] = launch
        self._total_notifications += 1

        logger.info(
            f"Registered launch: {launch_id} for project {launch.project_name} "
            f"(expected_class={launch.expected_class}, workspace={launch.workspace_number})"
        )
        logger.debug(f"Pending launches: {len(self._launches)}")

        return launch_id

    async def find_match(self, window: LaunchWindowInfo) -> Optional[PendingLaunch]:
        """
        Find the best matching pending launch for a window.

        Searches through unmatched pending launches and returns the one with
        highest correlation confidence above threshold. Marks the matched
        launch to prevent double-matching.

        Feature 041: T027, T028, T029 - Enhanced with rapid launch diagnostics

        Args:
            window: Window information from i3 window::new event

        Returns:
            PendingLaunch if match found, None otherwise
        """
        # Get unmatched launches
        candidates = [
            launch for launch in self._launches.values()
            if not launch.matched
        ]

        if not candidates:
            logger.debug(f"No pending launches for window {window.window_id} ({window.window_class})")
            self._total_failed_correlation += 1
            return None

        # T029: Diagnostic logging for rapid launch scenarios
        app_counts = {}
        for launch in candidates:
            app_counts[launch.app_name] = app_counts.get(launch.app_name, 0) + 1

        logger.debug(f"Searching {len(candidates)} pending launches for window {window.window_id}")

        # Log if multiple launches for same app (rapid launch scenario)
        for app_name, count in app_counts.items():
            if count > 1:
                logger.info(
                    f"Multiple pending launches for {app_name}: {count} instances "
                    f"(rapid launch scenario detected)"
                )

        # Find best match (correlation logic will be in window_correlator.py)
        # For now, use simple class matching with first-match-wins
        from .window_correlator import calculate_confidence

        best_match: Optional[PendingLaunch] = None
        best_confidence = 0.0  # Start at 0.0
        threshold = 0.6  # MEDIUM threshold

        # T029: Track timing information for diagnostics
        correlation_start = time.time()
        candidate_scores = []

        for launch in candidates:
            # T039: calculate_confidence now returns (confidence, signals) tuple
            confidence, signals = calculate_confidence(launch, window)
            time_delta = window.timestamp - launch.timestamp

            # Store for diagnostic logging with signals from correlation
            candidate_scores.append({
                "app": launch.app_name,
                "project": launch.project_name,
                "confidence": confidence,
                "time_delta": time_delta,
                "workspace_match": signals.get("workspace_match", False),
                "signals": signals,  # T040: Include full signals for diagnostics
            })

            # Accept if confidence >= threshold and better than current best
            if confidence >= threshold and confidence > best_confidence:
                best_match = launch
                best_confidence = confidence
                logger.debug(
                    f"Potential match: {launch.app_name} → {launch.project_name} "
                    f"(confidence={confidence:.2f})"
                )

        correlation_time = (time.time() - correlation_start) * 1000  # Convert to ms

        # Mark as matched if found
        if best_match:
            best_match.matched = True
            self._total_matched += 1

            # T029: Enhanced logging with timing and signal details
            time_delta = window.timestamp - best_match.timestamp
            workspace_match = best_match.workspace_number == window.workspace_number

            logger.info(
                f"Matched window {window.window_id} ({window.window_class}) to "
                f"launch {best_match.app_name} → {best_match.project_name} "
                f"(confidence={best_confidence:.2f})"
            )

            # Log detailed correlation info for rapid launch scenarios
            if len(candidates) > 1:
                logger.info(
                    f"Best match: {best_match.app_name} → {best_match.project_name} "
                    f"with confidence {best_confidence:.2f} "
                    f"(time_delta={time_delta:.3f}s, workspace_match={workspace_match})"
                )
                logger.debug(
                    f"Correlation candidates: {candidate_scores} "
                    f"(correlation_time={correlation_time:.2f}ms)"
                )
        else:
            self._total_failed_correlation += 1
            logger.warning(
                f"No matching launch for window {window.window_id} ({window.window_class}). "
                f"Pending launches: {[f'{l.app_name}[{l.expected_class}]' for l in candidates]}"
            )

        return best_match

    async def _cleanup_expired(self) -> None:
        """Remove launches older than timeout."""
        now = time.time()
        expired_ids = [
            launch_id
            for launch_id, launch in self._launches.items()
            if launch.is_expired(now, self._timeout)
        ]

        for launch_id in expired_ids:
            launch = self._launches.pop(launch_id)
            self._total_expired += 1
            logger.warning(
                f"Launch expired: {launch.app_name} for project {launch.project_name} "
                f"(age={launch.age(now):.2f}s)"
            )

        if expired_ids:
            logger.debug(f"Cleaned up {len(expired_ids)} expired launches")

    def get_stats(self) -> LaunchRegistryStats:
        """
        Get registry statistics for diagnostics.

        Returns:
            LaunchRegistryStats with current state and historical counters
        """
        total_pending = len(self._launches)
        unmatched_pending = sum(1 for l in self._launches.values() if not l.matched)

        return LaunchRegistryStats(
            total_pending=total_pending,
            unmatched_pending=unmatched_pending,
            total_notifications=self._total_notifications,
            total_matched=self._total_matched,
            total_expired=self._total_expired,
            total_failed_correlation=self._total_failed_correlation,
        )

    async def get_pending_launches(self, include_matched: bool = False) -> list:
        """
        Get list of pending launches for debugging.

        Args:
            include_matched: If True, include already-matched launches

        Returns:
            List of pending launch dictionaries with age calculation
        """
        now = time.time()
        launches = []

        for launch_id, launch in self._launches.items():
            if not include_matched and launch.matched:
                continue

            launches.append({
                "launch_id": launch_id,
                "app_name": launch.app_name,
                "project_name": launch.project_name,
                "expected_class": launch.expected_class,
                "workspace_number": launch.workspace_number,
                "matched": launch.matched,
                "age": launch.age(now),
                "timestamp": launch.timestamp,
            })

        return launches
