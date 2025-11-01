"""Network status block implementation using NetworkManager D-Bus."""

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
    logger.warning("pydbus not available - network status will not work")


class ConnectionState(Enum):
    """WiFi connection state."""
    CONNECTED = "connected"
    CONNECTING = "connecting"
    DISCONNECTED = "disconnected"
    DISABLED = "disabled"


# NetworkManager device states (from NetworkManager.h)
NM_DEVICE_STATE_UNKNOWN = 0
NM_DEVICE_STATE_UNMANAGED = 10
NM_DEVICE_STATE_UNAVAILABLE = 20
NM_DEVICE_STATE_DISCONNECTED = 30
NM_DEVICE_STATE_PREPARE = 40
NM_DEVICE_STATE_CONFIG = 50
NM_DEVICE_STATE_NEED_AUTH = 60
NM_DEVICE_STATE_IP_CONFIG = 70
NM_DEVICE_STATE_IP_CHECK = 80
NM_DEVICE_STATE_SECONDARIES = 90
NM_DEVICE_STATE_ACTIVATED = 100


@dataclass
class NetworkState:
    """Current WiFi network state."""

    state: ConnectionState
    ssid: Optional[str] = None           # Connected network name
    signal_strength: Optional[int] = None # Signal strength (0-100)
    device_name: str = "wlan0"           # Network device name

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state."""
        if self.state == ConnectionState.DISABLED:
            return "󰖪"  # nf-md-wifi_off
        elif self.state == ConnectionState.DISCONNECTED:
            return "󰤭"  # nf-md-wifi_strength_off
        elif self.signal_strength is not None:
            if self.signal_strength >= 80:
                return "󰤨"  # nf-md-wifi_strength_4
            elif self.signal_strength >= 60:
                return "󰤥"  # nf-md-wifi_strength_3
            elif self.signal_strength >= 40:
                return "󰤢"  # nf-md-wifi_strength_2
            else:
                return "󰤟"  # nf-md-wifi_strength_1
        else:
            return "󰖩"  # nf-md-wifi (generic)

    def get_color(self, config: Config) -> str:
        """Get color based on state."""
        if self.state == ConnectionState.DISCONNECTED:
            return config.theme.network.disconnected
        elif self.state == ConnectionState.DISABLED:
            return config.theme.network.disabled
        elif self.signal_strength is not None and self.signal_strength < 40:
            return config.theme.network.weak
        else:
            return config.theme.network.connected

    def get_tooltip(self) -> str:
        """Get detailed tooltip text."""
        if self.state == ConnectionState.CONNECTED and self.ssid:
            return f"Connected to {self.ssid} ({self.signal_strength}%)"
        elif self.state == ConnectionState.CONNECTING:
            return "Connecting..."
        elif self.state == ConnectionState.DISABLED:
            return "WiFi disabled"
        else:
            return "Disconnected"

    def to_status_block(self, config: Config) -> StatusBlock:
        """Convert to status block."""
        icon = self.get_icon()
        color = self.get_color(config)

        if self.state == ConnectionState.CONNECTED and self.ssid:
            full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.ssid}"
            short_text = self.ssid[:10] + "..." if len(self.ssid) > 10 else self.ssid
        else:
            full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.state.value}"
            short_text = icon

        return StatusBlock(
            name="network",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango"
        )


def get_network_state() -> Optional[NetworkState]:
    """Query current network state via NetworkManager D-Bus.

    Returns:
        NetworkState if successful, None if error

    Raises:
        None - errors are logged and None is returned
    """
    if not PYDBUS_AVAILABLE:
        return NetworkState(state=ConnectionState.DISCONNECTED)

    try:
        bus = SystemBus()
        nm = bus.get("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager")

        # Get wireless device
        devices = nm.GetDevices()
        wifi_device_path = None

        for device_path in devices:
            try:
                device = bus.get("org.freedesktop.NetworkManager", device_path)
                # DeviceType 2 = WiFi
                if device.DeviceType == 2:
                    wifi_device_path = device_path
                    break
            except:
                continue

        if not wifi_device_path:
            logger.debug("No WiFi device found")
            return NetworkState(state=ConnectionState.DISABLED)

        # Get device state
        wifi_device = bus.get("org.freedesktop.NetworkManager", wifi_device_path)
        device_state = wifi_device.State

        # Map device state to connection state
        if device_state == NM_DEVICE_STATE_ACTIVATED:
            # Get active connection info
            active_ap_path = wifi_device.ActiveAccessPoint

            if active_ap_path and active_ap_path != "/":
                try:
                    ap = bus.get("org.freedesktop.NetworkManager", active_ap_path)
                    ssid_bytes = ap.Ssid
                    ssid = bytes(ssid_bytes).decode('utf-8', errors='ignore')
                    signal_strength = int(ap.Strength)

                    return NetworkState(
                        state=ConnectionState.CONNECTED,
                        ssid=ssid,
                        signal_strength=signal_strength,
                        device_name=str(wifi_device.Interface)
                    )
                except Exception as e:
                    logger.error(f"Failed to query access point: {e}")

            return NetworkState(state=ConnectionState.CONNECTED)

        elif device_state in [NM_DEVICE_STATE_PREPARE, NM_DEVICE_STATE_CONFIG, NM_DEVICE_STATE_NEED_AUTH]:
            return NetworkState(state=ConnectionState.CONNECTING)

        elif device_state in [NM_DEVICE_STATE_UNAVAILABLE, NM_DEVICE_STATE_UNMANAGED]:
            return NetworkState(state=ConnectionState.DISABLED)

        else:
            return NetworkState(state=ConnectionState.DISCONNECTED)

    except Exception as e:
        logger.error(f"Failed to query network state: {e}")
        return NetworkState(state=ConnectionState.DISCONNECTED)
