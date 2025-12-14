"""Badge service for visual notification badges in monitoring panel.

Feature 095: Visual Notification Badges in Monitoring Panel
Feature 117: File-based badge storage as single source of truth

Implements notification-agnostic badge state management with Pydantic models.

Badge States:
- "working": Claude Code is actively processing (shows spinner animation)
- "stopped": Claude Code finished and is waiting for input (shows bell icon)
"""

import json
import logging
import os
import time
from pathlib import Path
from typing import Dict, Optional, Literal
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

# Feature 117: Badge timing constants
BADGE_MIN_AGE_FOR_DISMISS = 1.0  # Minimum age (seconds) before focus dismissal
BADGE_MAX_AGE = 300  # Maximum badge age (5 minutes) for TTL cleanup

# Badge directory path
def get_badge_dir() -> Path:
    """Get the badge directory path from XDG_RUNTIME_DIR."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return Path(runtime_dir) / "i3pm-badges"


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


# ============================================================================
# Feature 117: File-based badge utilities
# ============================================================================

def read_badge_file(window_id: int) -> Optional[WindowBadge]:
    """Read badge from file.

    Args:
        window_id: Sway window container ID

    Returns:
        WindowBadge if file exists and is valid, None otherwise
    """
    badge_dir = get_badge_dir()
    badge_file = badge_dir / f"{window_id}.json"

    if not badge_file.exists():
        return None

    try:
        with open(badge_file, "r") as f:
            data = json.load(f)
        return WindowBadge(**data)
    except (json.JSONDecodeError, Exception) as e:
        logger.warning(f"Failed to read badge file {badge_file}: {e}")
        return None


def write_badge_file(badge: WindowBadge) -> bool:
    """Write badge to file.

    Args:
        badge: WindowBadge to write

    Returns:
        True if successful, False otherwise
    """
    badge_dir = get_badge_dir()
    badge_dir.mkdir(parents=True, exist_ok=True)
    badge_file = badge_dir / f"{badge.window_id}.json"

    try:
        with open(badge_file, "w") as f:
            json.dump(badge.model_dump(), f)
        return True
    except Exception as e:
        logger.error(f"Failed to write badge file {badge_file}: {e}")
        return False


def delete_badge_file(window_id: int) -> bool:
    """Delete badge file.

    Args:
        window_id: Sway window container ID

    Returns:
        True if file was deleted, False if it didn't exist or error occurred
    """
    badge_dir = get_badge_dir()
    badge_file = badge_dir / f"{window_id}.json"

    try:
        if badge_file.exists():
            badge_file.unlink()
            logger.debug(f"[Feature 117] Deleted badge file for window {window_id}")
            return True
        return False
    except Exception as e:
        logger.error(f"Failed to delete badge file {badge_file}: {e}")
        return False


def read_all_badge_files() -> Dict[int, WindowBadge]:
    """Read all badge files from the badge directory.

    Returns:
        Dictionary mapping window_id to WindowBadge
    """
    badge_dir = get_badge_dir()
    badges: Dict[int, WindowBadge] = {}

    if not badge_dir.exists():
        return badges

    for badge_file in badge_dir.glob("*.json"):
        try:
            window_id = int(badge_file.stem)
            with open(badge_file, "r") as f:
                data = json.load(f)
            badges[window_id] = WindowBadge(**data)
        except (ValueError, json.JSONDecodeError, Exception) as e:
            logger.warning(f"Skipping invalid badge file {badge_file}: {e}")

    return badges


def get_badge_age(window_id: int) -> Optional[float]:
    """Get the age of a badge in seconds.

    Args:
        window_id: Sway window container ID

    Returns:
        Age in seconds if badge exists, None otherwise
    """
    badge = read_badge_file(window_id)
    if badge:
        return time.time() - badge.timestamp
    return None


def cleanup_orphaned_badge_files(valid_window_ids: set[int]) -> int:
    """Remove badge files for windows that no longer exist.

    Args:
        valid_window_ids: Set of window IDs from current Sway tree

    Returns:
        Number of orphaned badge files removed
    """
    badge_dir = get_badge_dir()
    removed = 0

    if not badge_dir.exists():
        return 0

    for badge_file in badge_dir.glob("*.json"):
        try:
            window_id = int(badge_file.stem)
            if window_id not in valid_window_ids:
                badge_file.unlink()
                logger.info(f"[Feature 117] Removed orphaned badge for window {window_id}")
                removed += 1
        except (ValueError, Exception) as e:
            logger.warning(f"Error processing badge file {badge_file}: {e}")

    return removed


def cleanup_stale_badge_files() -> int:
    """Remove badge files older than BADGE_MAX_AGE.

    Returns:
        Number of stale badge files removed
    """
    badge_dir = get_badge_dir()
    removed = 0
    now = time.time()

    if not badge_dir.exists():
        return 0

    for badge_file in badge_dir.glob("*.json"):
        try:
            with open(badge_file, "r") as f:
                data = json.load(f)
            timestamp = data.get("timestamp", 0)
            age = now - timestamp

            if age > BADGE_MAX_AGE:
                badge_file.unlink()
                logger.info(f"[Feature 117] Removed stale badge {badge_file.stem} (age: {age:.0f}s)")
                removed += 1
        except (json.JSONDecodeError, Exception) as e:
            logger.warning(f"Error processing badge file {badge_file}: {e}")

    return removed
