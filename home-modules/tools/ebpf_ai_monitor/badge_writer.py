"""Badge file management for eww panel integration.

This module handles writing and managing badge files that are consumed
by the eww monitoring panel. Badge files provide visual state information
about AI agent processes.

File Format:
    JSON files at $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
    Must match the existing badge-state.json contract for compatibility.

Architecture:
    - Atomic writes using temp file + rename
    - Files owned by target user (chown after write)
    - Automatic deletion on process exit
"""

import json
import logging
import os
import tempfile
import time
from pathlib import Path
from typing import Optional

from .models import BadgeState, MonitoredProcess, ProcessState

logger = logging.getLogger(__name__)


class BadgeWriter:
    """Manages badge files for eww panel integration.

    This class handles:
    - Creating the badge directory if needed
    - Atomic file writes (temp + rename)
    - Proper file ownership (chown to target user)
    - Badge deletion on process exit
    - Notification count tracking

    Example:
        >>> writer = BadgeWriter(
        ...     badge_dir=Path("/run/user/1000/i3pm-badges"),
        ...     uid=1000,
        ...     gid=1000,
        ... )
        >>> writer.write_badge(process)
        >>> writer.delete_badge(window_id=12345)
    """

    def __init__(
        self,
        badge_dir: Path,
        uid: int,
        gid: int,
    ):
        """Initialize badge writer.

        Args:
            badge_dir: Directory for badge files.
            uid: User ID for file ownership.
            gid: Group ID for file ownership.
        """
        self.badge_dir = badge_dir
        self.uid = uid
        self.gid = gid

        # Track notification counts per window
        self._counts: dict[int, int] = {}

        # Ensure badge directory exists
        self._ensure_directory()

    def _ensure_directory(self) -> None:
        """Create badge directory if it doesn't exist."""
        if not self.badge_dir.exists():
            logger.info("Creating badge directory: %s", self.badge_dir)
            self.badge_dir.mkdir(parents=True, exist_ok=True)
            os.chown(self.badge_dir, self.uid, self.gid)
            os.chmod(self.badge_dir, 0o755)

    def _get_badge_path(self, window_id: int) -> Path:
        """Get path for a badge file.

        Args:
            window_id: Sway window ID.

        Returns:
            Path to badge file.
        """
        return self.badge_dir / f"{window_id}.json"

    def write_badge(
        self,
        process: MonitoredProcess,
        increment_count: bool = False,
    ) -> bool:
        """Write badge file for a process.

        Uses atomic write pattern: write to temp file, then rename.
        Sets file ownership to target user after write.

        Args:
            process: MonitoredProcess to write badge for.
            increment_count: If True, increment the notification count.

        Returns:
            True if badge was written successfully.
        """
        window_id = process.window_id

        # Get or initialize count
        if window_id not in self._counts:
            self._counts[window_id] = 1
        elif increment_count:
            self._counts[window_id] = min(self._counts[window_id] + 1, 9999)

        # Create badge state
        badge = BadgeState.from_monitored_process(process)
        badge.count = self._counts[window_id]

        # Convert to JSON
        badge_json = badge.model_dump_json(indent=2)

        try:
            badge_path = self._get_badge_path(window_id)

            # Atomic write: temp file + rename
            fd, temp_path = tempfile.mkstemp(
                dir=self.badge_dir,
                prefix=".badge_",
                suffix=".json.tmp",
            )
            try:
                os.write(fd, badge_json.encode("utf-8"))
                os.write(fd, b"\n")
                os.fsync(fd)
            finally:
                os.close(fd)

            # Set ownership before rename
            os.chown(temp_path, self.uid, self.gid)
            os.chmod(temp_path, 0o644)

            # Atomic rename
            os.rename(temp_path, badge_path)

            logger.debug(
                "Badge written: window=%d, state=%s, count=%d",
                window_id,
                badge.state,
                badge.count,
            )
            return True

        except OSError as e:
            logger.error("Failed to write badge for window %d: %s", window_id, e)
            # Clean up temp file if it exists
            try:
                if 'temp_path' in locals():
                    os.unlink(temp_path)
            except OSError:
                pass
            return False

    def delete_badge(self, window_id: int) -> bool:
        """Delete badge file for a window.

        Args:
            window_id: Sway window ID.

        Returns:
            True if badge was deleted (or didn't exist).
        """
        badge_path = self._get_badge_path(window_id)

        try:
            if badge_path.exists():
                badge_path.unlink()
                logger.debug("Badge deleted: window=%d", window_id)

            # Clean up count tracking
            self._counts.pop(window_id, None)
            return True

        except OSError as e:
            logger.error("Failed to delete badge for window %d: %s", window_id, e)
            return False

    def update_needs_attention(
        self,
        window_id: int,
        needs_attention: bool,
    ) -> bool:
        """Update the needs_attention flag for an existing badge.

        Args:
            window_id: Sway window ID.
            needs_attention: New value for needs_attention flag.

        Returns:
            True if badge was updated successfully.
        """
        badge_path = self._get_badge_path(window_id)

        try:
            if not badge_path.exists():
                logger.warning("Badge not found for window %d", window_id)
                return False

            # Read existing badge
            content = badge_path.read_text()
            data = json.loads(content)

            # Update flag
            data["needs_attention"] = needs_attention
            data["timestamp"] = time.time()

            # Write back atomically
            fd, temp_path = tempfile.mkstemp(
                dir=self.badge_dir,
                prefix=".badge_",
                suffix=".json.tmp",
            )
            try:
                os.write(fd, json.dumps(data, indent=2).encode("utf-8"))
                os.write(fd, b"\n")
                os.fsync(fd)
            finally:
                os.close(fd)

            os.chown(temp_path, self.uid, self.gid)
            os.chmod(temp_path, 0o644)
            os.rename(temp_path, badge_path)

            logger.debug(
                "Badge needs_attention updated: window=%d, needs_attention=%s",
                window_id,
                needs_attention,
            )
            return True

        except (OSError, json.JSONDecodeError) as e:
            logger.error(
                "Failed to update needs_attention for window %d: %s",
                window_id,
                e,
            )
            return False

    def get_count(self, window_id: int) -> int:
        """Get current notification count for a window.

        Args:
            window_id: Sway window ID.

        Returns:
            Current count (defaults to 1 if not tracked).
        """
        return self._counts.get(window_id, 1)

    def increment_count(self, window_id: int) -> int:
        """Increment and return notification count for a window.

        Args:
            window_id: Sway window ID.

        Returns:
            New count value.
        """
        if window_id not in self._counts:
            self._counts[window_id] = 1
        else:
            self._counts[window_id] = min(self._counts[window_id] + 1, 9999)
        return self._counts[window_id]

    def scan_existing_badges(self) -> dict[int, BadgeState]:
        """Scan badge directory for existing badge files.

        Useful for state recovery on daemon restart.

        Returns:
            Dict mapping window_id to BadgeState.
        """
        badges = {}

        if not self.badge_dir.exists():
            return badges

        for badge_file in self.badge_dir.glob("*.json"):
            try:
                window_id = int(badge_file.stem)
                content = badge_file.read_text()
                data = json.loads(content)
                badge = BadgeState.model_validate(data)
                badges[window_id] = badge

                # Restore count tracking
                self._counts[window_id] = badge.count

                logger.debug(
                    "Found existing badge: window=%d, state=%s",
                    window_id,
                    badge.state,
                )

            except (ValueError, json.JSONDecodeError, Exception) as e:
                logger.warning("Invalid badge file %s: %s", badge_file, e)
                continue

        logger.info("Found %d existing badge files", len(badges))
        return badges
