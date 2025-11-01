"""Volume status block implementation using pactl."""

import subprocess
import re
import logging
from dataclasses import dataclass
from typing import Optional

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


@dataclass
class VolumeState:
    """Current audio volume state."""

    level: int              # Volume level (0-100)
    muted: bool             # Mute state
    sink_name: str          # Audio sink/device name

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state."""
        if self.muted:
            return "󰝟"  # nf-md-volume_mute
        elif self.level >= 70:
            return "󰕾"  # nf-md-volume_high
        elif self.level >= 30:
            return "󰖀"  # nf-md-volume_medium
        else:
            return "󰕿"  # nf-md-volume_low

    def get_color(self, config: Config) -> str:
        """Get color based on state."""
        if self.muted:
            return config.theme.volume.muted
        return config.theme.volume.normal

    def to_status_block(self, config: Config) -> StatusBlock:
        """Convert to status block."""
        icon = self.get_icon()
        color = self.get_color(config)
        full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.level}%"
        short_text = f"{self.level}%"

        return StatusBlock(
            name="volume",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango"
        )


def get_volume_state() -> Optional[VolumeState]:
    """Query current volume state via pactl.

    Returns:
        VolumeState if successful, None if pactl unavailable or error

    Raises:
        None - errors are logged and None is returned
    """
    try:
        # Query default sink info
        result = subprocess.run(
            ["pactl", "list", "sinks"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True
        )

        output = result.stdout

        # Find active/default sink (first sink in output)
        # Parse volume percentage
        volume_match = re.search(r'Volume:.*?(\d+)%', output)
        if not volume_match:
            logger.error("Failed to parse volume percentage from pactl output")
            return None

        volume = int(volume_match.group(1))

        # Parse mute state
        mute_match = re.search(r'Mute: (yes|no)', output)
        if not mute_match:
            logger.error("Failed to parse mute state from pactl output")
            return None

        muted = mute_match.group(1) == "yes"

        # Parse sink name
        name_match = re.search(r'Name: (.+)', output)
        sink_name = name_match.group(1) if name_match else "default"

        return VolumeState(
            level=volume,
            muted=muted,
            sink_name=sink_name
        )

    except subprocess.TimeoutExpired:
        logger.error("pactl command timed out")
        return None
    except subprocess.CalledProcessError as e:
        logger.error(f"pactl command failed: {e.stderr}")
        return None
    except FileNotFoundError:
        logger.error("pactl not found - PulseAudio/PipeWire not installed?")
        return None
    except Exception as e:
        logger.error(f"Unexpected error querying volume: {e}")
        return None
