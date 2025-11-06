"""Notification status block implementation using swaync-client."""

import subprocess
import json
import logging
from dataclasses import dataclass
from typing import Optional

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


@dataclass
class NotificationState:
    """Current notification state from SwayNC."""

    count: int              # Number of notifications
    dnd: bool               # Do Not Disturb enabled
    inhibited: bool         # Notifications inhibited

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state.

        Maps to different icons based on notification count and DND/inhibited state:
        - notification: Has active notifications
        - none: No notifications
        - dnd-notification: DND with notifications
        - dnd-none: DND without notifications
        - inhibited-notification: Inhibited with notifications
        - inhibited-none: Inhibited without notifications
        """
        has_notifications = self.count > 0

        if self.inhibited:
            # Inhibited state
            if has_notifications:
                return "󰂛"  # nf-md-bell_off_outline (inhibited with notifications)
            else:
                return "󰂚"  # nf-md-bell_off (inhibited without notifications)
        elif self.dnd:
            # Do Not Disturb state
            if has_notifications:
                return "󰂠"  # nf-md-bell_sleep (DND with notifications)
            else:
                return "󰂛"  # nf-md-bell_off_outline (DND without notifications)
        else:
            # Normal state
            if has_notifications:
                return "󰂚"  # nf-md-bell_ring (active notifications)
            else:
                return "󰂜"  # nf-md-bell_outline (no notifications)

    def get_color(self, config: Config) -> str:
        """Get color based on state."""
        # Use theme colors if available, otherwise defaults
        try:
            if self.dnd or self.inhibited:
                return config.theme.volume.muted  # Reuse muted color for DND/inhibited
            elif self.count > 0:
                return config.theme.battery.warning  # Reuse warning color for active notifications
            else:
                return config.theme.datetime.normal
        except AttributeError:
            # Fallback colors if theme attributes don't exist
            if self.dnd or self.inhibited:
                return "#999999"
            elif self.count > 0:
                return "#FFA500"
            else:
                return "#FFFFFF"

    def to_status_block(self, config: Config) -> StatusBlock:
        """Convert to status block."""
        icon = self.get_icon()
        color = self.get_color(config)

        # Show count if there are notifications
        if self.count > 0:
            full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.count}"
            short_text = f"{self.count}"
        else:
            full_text = f"<span font='{config.icon_font}'>{icon}</span>"
            short_text = ""

        return StatusBlock(
            name="notification",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango"
        )


def get_notification_state() -> Optional[NotificationState]:
    """Query current notification state via swaync-client.

    Returns:
        NotificationState if successful, None if swaync-client unavailable or error

    Raises:
        None - errors are logged and None is returned
    """
    try:
        # Query notification state with swaync-client
        # -swb = subscribe with binary output (JSON format)
        result = subprocess.run(
            ["swaync-client", "-swb"],
            capture_output=True,
            text=True,
            timeout=1,
            check=True
        )

        # Parse JSON output
        data = json.loads(result.stdout.strip())

        # Extract state fields
        # Format: {"text":"","alt":"","tooltip":"","class":"","percentage":""}
        # The class field contains state: "dnd", "inhibited", "notification", "none", etc.
        state_class = data.get("class", "none")

        # Parse notification count from text field (if present)
        text = data.get("text", "")
        try:
            count = int(text) if text and text.isdigit() else 0
        except (ValueError, TypeError):
            count = 0

        # Determine DND and inhibited states from class
        dnd = "dnd" in state_class
        inhibited = "inhibited" in state_class

        # Check if there are notifications
        has_notifications = "notification" in state_class or count > 0

        return NotificationState(
            count=count,
            dnd=dnd,
            inhibited=inhibited
        )

    except subprocess.TimeoutExpired:
        logger.error("swaync-client timed out")
        return None
    except subprocess.CalledProcessError as e:
        logger.error(f"swaync-client failed: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse swaync-client JSON: {e}")
        return None
    except FileNotFoundError:
        logger.debug("swaync-client not found (SwayNC not installed?)")
        return None
    except Exception as e:
        logger.error(f"Unexpected error querying notification state: {e}")
        return None
