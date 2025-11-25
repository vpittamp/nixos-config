"""Badge service for visual notification badges in monitoring panel.

Feature 095: Visual Notification Badges in Monitoring Panel
Implements notification-agnostic badge state management with Pydantic models.

Badge States:
- "working": Claude Code is actively processing (shows spinner animation)
- "stopped": Claude Code finished and is waiting for input (shows bell icon)
"""

import time
from typing import Dict, Optional, Literal
from pydantic import BaseModel, Field


# Badge state type - determines visual representation
BadgeStateType = Literal["working", "stopped"]


class WindowBadge(BaseModel):
    """Represents a single window's notification badge state.

    Attributes:
        window_id: Sway window container ID (authoritative key)
        count: Number of pending notifications (1-9999, display as "9+" if >9)
        timestamp: Unix timestamp when badge was created (for cleanup/sorting)
        source: Notification source identifier (claude-code, build, test, generic, etc.)
        state: Badge state - "working" (spinner) or "stopped" (bell icon)
    """

    window_id: int = Field(..., description="Sway window container ID", gt=0)
    count: int = Field(1, description="Number of pending notifications", ge=1, le=9999)
    timestamp: float = Field(..., description="Unix timestamp when badge was created")
    source: str = Field("generic", description="Notification source identifier", min_length=1)
    state: BadgeStateType = Field("stopped", description="Badge state: working or stopped")

    def increment(self) -> None:
        """Increment badge count (capped at 9999 for display overflow protection)."""
        self.count = min(self.count + 1, 9999)

    def display_count(self) -> str:
        """Get display string for badge count.

        Returns:
            Badge count as string: "1", "2", ..., "9", "9+" (for count > 9)
        """
        return "9+" if self.count > 9 else str(self.count)


class BadgeState(BaseModel):
    """Daemon-level badge state manager.

    Stores badge state in-memory as a dictionary mapping Sway window IDs to badge metadata.
    Provides methods for creating, clearing, and querying badges.

    Attributes:
        badges: Dictionary mapping window ID to WindowBadge (O(1) lookup)
    """

    badges: Dict[int, WindowBadge] = Field(default_factory=dict)

    def create_badge(
        self,
        window_id: int,
        source: str = "generic",
        state: BadgeStateType = "stopped"
    ) -> WindowBadge:
        """Create new badge or update existing badge state.

        Args:
            window_id: Sway window container ID
            source: Notification source identifier (defaults to "generic")
            state: Badge state - "working" or "stopped" (defaults to "stopped")

        Returns:
            WindowBadge: Badge state after creation/update
        """
        if window_id in self.badges:
            # Update existing badge state and timestamp
            self.badges[window_id].state = state
            self.badges[window_id].timestamp = time.time()
            # Only increment count when transitioning to "stopped"
            if state == "stopped":
                self.badges[window_id].increment()
        else:
            # Create new badge
            self.badges[window_id] = WindowBadge(
                window_id=window_id,
                timestamp=time.time(),
                source=source,
                state=state
            )
        return self.badges[window_id]

    def set_badge_state(self, window_id: int, state: BadgeStateType) -> Optional[WindowBadge]:
        """Update badge state without creating new badge.

        Args:
            window_id: Sway window container ID
            state: New badge state - "working" or "stopped"

        Returns:
            Optional[WindowBadge]: Updated badge if exists, None otherwise
        """
        badge = self.badges.get(window_id)
        if badge:
            badge.state = state
            badge.timestamp = time.time()
        return badge

    def clear_badge(self, window_id: int, min_age_seconds: float = 0.0) -> int:
        """Remove badge and return cleared count.

        Args:
            window_id: Sway window container ID
            min_age_seconds: Minimum badge age (in seconds) before clearing.
                If badge is younger than this, it won't be cleared. This prevents
                badges from being cleared immediately on focus when the window
                was already focused when the badge was created.
                Default: 0.0 (always clear, for explicit user action like clicking
                "Return to Window" in notification).

        Returns:
            int: Badge count that was cleared (0 if no badge existed or too young)
        """
        badge = self.badges.get(window_id)
        if not badge:
            return 0

        # Check if badge is old enough to clear
        if min_age_seconds > 0:
            age = time.time() - badge.timestamp
            if age < min_age_seconds:
                # Badge is too young, don't clear it yet
                return 0

        # Clear the badge
        self.badges.pop(window_id, None)
        return badge.count

    def has_badge(self, window_id: int) -> bool:
        """Check if window has badge.

        Args:
            window_id: Sway window container ID

        Returns:
            bool: True if window has badge, False otherwise
        """
        return window_id in self.badges

    def get_badge(self, window_id: int) -> Optional[WindowBadge]:
        """Get badge by window ID.

        Args:
            window_id: Sway window container ID

        Returns:
            Optional[WindowBadge]: Badge if exists, None otherwise
        """
        return self.badges.get(window_id)

    def get_all_badges(self) -> list[WindowBadge]:
        """Get all badges for UI rendering.

        Returns:
            list[WindowBadge]: List of all current badges
        """
        return list(self.badges.values())

    def cleanup_orphaned(self, valid_window_ids: set[int]) -> int:
        """Remove badges for windows that no longer exist.

        Args:
            valid_window_ids: Set of window IDs from current Sway tree

        Returns:
            int: Number of orphaned badges removed
        """
        orphaned = [wid for wid in self.badges if wid not in valid_window_ids]
        for wid in orphaned:
            self.badges.pop(wid)
        return len(orphaned)

    def to_eww_format(self) -> Dict[str, dict]:
        """Convert badge state to Eww-friendly JSON format.

        Returns:
            Dict mapping stringified window IDs to badge metadata:
            {
                "12345": {"count": "2", "timestamp": 1732450000.5, "source": "claude-code", "state": "stopped"},
                "67890": {"count": "1", "timestamp": 1732450100.0, "source": "build", "state": "working"}
            }
        """
        return {
            str(window_id): {
                "count": badge.display_count(),
                "timestamp": badge.timestamp,
                "source": badge.source,
                "state": badge.state,
            }
            for window_id, badge in self.badges.items()
        }
