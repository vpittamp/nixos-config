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

        # Use the canonical launch anchor when available so status/spec/window
        # correlation all speak the same deterministic identity.
        launch_id = (
            str(launch.launch_id or "").strip()
            or str(launch.terminal_anchor_id or "").strip()
            or f"{launch.app_name}-{launch.timestamp}"
        )
        launch.launch_id = launch_id

        # Store launch
        self._launches[launch_id] = launch
        self._total_notifications += 1

        logger.info(
            f"Registered launch: {launch_id} for project {launch.project_name} "
            f"(expected_class={launch.expected_class}, workspace={launch.workspace_number})"
        )
        logger.debug(f"Pending launches: {len(self._launches)}")

        return launch_id

    async def find_by_terminal_anchor(self, terminal_anchor_id: str) -> Optional[PendingLaunch]:
        """Return the pending launch registered for an exact terminal anchor."""
        await self._cleanup_expired()
        target = str(terminal_anchor_id or "").strip()
        if not target:
            return None

        for launch in self._launches.values():
            if str(launch.terminal_anchor_id or "").strip() != target:
                continue
            if not launch.matched:
                launch.matched = True
                self._total_matched += 1
            return launch
        return None

    async def get_by_terminal_anchor(self, terminal_anchor_id: str) -> Optional[PendingLaunch]:
        """Return a pending launch by exact anchor without mutating match state."""
        await self._cleanup_expired()
        target = str(terminal_anchor_id or "").strip()
        if not target:
            return None
        for launch in self._launches.values():
            if str(launch.terminal_anchor_id or "").strip() == target:
                return launch
        return None

    async def find_by_window_signature(self, window: LaunchWindowInfo) -> Optional[PendingLaunch]:
        """Match a window to one pending launch using exact managed signatures only."""
        await self._cleanup_expired()

        candidates = [launch for launch in self._launches.values() if not launch.matched]
        if not candidates:
            return None

        matches = [launch for launch in candidates if self._launch_matches_window(launch, window)]
        if not matches:
            return None

        workspace_matches = [
            launch for launch in matches
            if launch.workspace_number == window.workspace_number
        ]
        if len(workspace_matches) == 1:
            matched = workspace_matches[0]
        elif len(matches) == 1:
            matched = matches[0]
        else:
            logger.error(
                "Ambiguous pending launch match for window %s (%s/%s): %s",
                window.window_id,
                window.window_class,
                window.window_instance,
                [
                    {
                        "app_name": launch.app_name,
                        "project_name": launch.project_name,
                        "workspace_number": launch.workspace_number,
                        "expected_class": launch.expected_class,
                    }
                    for launch in matches
                ],
            )
            return None

        matched.matched = True
        self._total_matched += 1
        return matched

    def _launch_matches_window(self, launch: PendingLaunch, window: LaunchWindowInfo) -> bool:
        from .window_identifier import match_pwa_instance, match_window_class

        actual_instance = str(window.window_instance or "")
        pwa_domains = list(launch.pwa_match_domains or [])
        if pwa_domains and match_pwa_instance(
            launch.expected_class,
            window.window_class,
            actual_instance,
            pwa_domains=pwa_domains,
        ):
            return True

        matched, _ = match_window_class(
            launch.expected_class,
            window.window_class,
            actual_instance,
        )
        return matched

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
            total_failed_correlation=0,
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
