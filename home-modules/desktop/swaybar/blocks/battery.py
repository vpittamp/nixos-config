"""Battery status block implementation using UPower D-Bus."""

import logging
from dataclasses import dataclass
from typing import Optional
from enum import Enum

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)

# Import pydbus lazily to handle missing dependency gracefully
try:
    from pydbus import SystemBus
    PYDBUS_AVAILABLE = True
except ImportError:
    PYDBUS_AVAILABLE = False
    logger.warning("pydbus not available - battery status will not work")


class BatteryStatus(Enum):
    """Battery charging status from UPower."""
    UNKNOWN = 0
    CHARGING = 1
    DISCHARGING = 2
    EMPTY = 3
    FULLY_CHARGED = 4
    PENDING_CHARGE = 5
    PENDING_DISCHARGE = 6


@dataclass
class BatteryState:
    """Current battery state."""

    percentage: int                      # Charge level (0-100)
    status: BatteryStatus                # Charging status
    time_to_empty: Optional[int] = None  # Seconds until empty (if discharging)
    time_to_full: Optional[int] = None   # Seconds until full (if charging)
    present: bool = True                 # Battery present flag

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state."""
        if self.status == BatteryStatus.CHARGING:
            return "󰂄"  # nf-md-battery_charging
        elif self.percentage >= 90:
            return "󰁹"  # nf-md-battery_90
        elif self.percentage >= 70:
            return "󰂂"  # nf-md-battery_70
        elif self.percentage >= 50:
            return "󰂀"  # nf-md-battery_50
        elif self.percentage >= 30:
            return "󰁾"  # nf-md-battery_30
        elif self.percentage >= 10:
            return "󰁼"  # nf-md-battery_10
        else:
            return "󰂃"  # nf-md-battery_alert

    def get_color(self, config: Config) -> str:
        """Get color based on state."""
        if self.status == BatteryStatus.CHARGING:
            return config.theme.battery.charging
        elif self.percentage >= 50:
            return config.theme.battery.high
        elif self.percentage >= 20:
            return config.theme.battery.medium
        else:
            return config.theme.battery.low

    def get_tooltip(self) -> str:
        """Get detailed tooltip text."""
        if self.time_to_empty is not None and self.time_to_empty > 0:
            hours, remainder = divmod(self.time_to_empty, 3600)
            minutes, _ = divmod(remainder, 60)
            return f"{self.percentage}% - {hours}h {minutes}m remaining"
        elif self.time_to_full is not None and self.time_to_full > 0:
            hours, remainder = divmod(self.time_to_full, 3600)
            minutes, _ = divmod(remainder, 60)
            return f"{self.percentage}% - {hours}h {minutes}m until full"
        else:
            return f"{self.percentage}% - {self.status.name.replace('_', ' ').lower()}"

    def to_status_block(self, config: Config) -> Optional[StatusBlock]:
        """Convert to status block (None if battery not present)."""
        if not self.present:
            return None

        icon = self.get_icon()
        color = self.get_color(config)
        full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.percentage}%"
        short_text = f"{self.percentage}%"

        return StatusBlock(
            name="battery",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango",
            urgent=(self.percentage < 10 and self.status == BatteryStatus.DISCHARGING)
        )


def get_battery_state() -> Optional[BatteryState]:
    """Query current battery state via UPower D-Bus.

    Returns:
        BatteryState if battery present, None if no battery or error

    Raises:
        None - errors are logged and None is returned
    """
    if not PYDBUS_AVAILABLE:
        return None

    try:
        bus = SystemBus()

        # Query UPower battery device
        # Path may vary: /org/freedesktop/UPower/devices/battery_BAT0, battery_BAT1, etc.
        upower = bus.get("org.freedesktop.UPower")

        # Enumerate devices to find battery
        devices = upower.EnumerateDevices()
        battery_path = None

        for device_path in devices:
            if "battery" in device_path.lower():
                battery_path = device_path
                break

        if not battery_path:
            logger.debug("No battery device found - desktop system?")
            return None

        # Get battery properties
        battery = bus.get("org.freedesktop.UPower", battery_path)

        # Check if battery is present
        if not battery.IsPresent:
            logger.debug("Battery not present")
            return None

        percentage = int(battery.Percentage)
        state = BatteryStatus(battery.State)
        time_to_empty = int(battery.TimeToEmpty) if battery.TimeToEmpty > 0 else None
        time_to_full = int(battery.TimeToFull) if battery.TimeToFull > 0 else None

        return BatteryState(
            percentage=percentage,
            status=state,
            time_to_empty=time_to_empty,
            time_to_full=time_to_full,
            present=True
        )

    except Exception as e:
        logger.error(f"Failed to query battery state: {e}")
        return None
