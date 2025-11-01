"""Bluetooth status block implementation using BlueZ D-Bus."""

import logging
from dataclasses import dataclass
from typing import Optional, List

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)

# Import pydbus lazily to handle missing dependency gracefully
try:
    from pydbus import SystemBus
    PYDBUS_AVAILABLE = True
except ImportError:
    PYDBUS_AVAILABLE = False
    logger.warning("pydbus not available - bluetooth status will not work")


@dataclass
class BluetoothDevice:
    """A paired/connected Bluetooth device."""
    name: str
    address: str
    connected: bool


@dataclass
class BluetoothState:
    """Current Bluetooth state."""

    enabled: bool
    devices: List[BluetoothDevice]
    adapter_name: str = "hci0"

    @property
    def connected_count(self) -> int:
        """Number of connected devices."""
        return sum(1 for dev in self.devices if dev.connected)

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state."""
        if not self.enabled:
            return "󰂲"  # nf-md-bluetooth_off
        elif self.connected_count > 0:
            return "󰂱"  # nf-md-bluetooth_connected
        else:
            return "󰂯"  # nf-md-bluetooth

    def get_color(self, config: Config) -> str:
        """Get color based on state."""
        if not self.enabled:
            return config.theme.bluetooth.disabled
        elif self.connected_count > 0:
            return config.theme.bluetooth.connected
        else:
            return config.theme.bluetooth.enabled

    def get_tooltip(self) -> str:
        """Get detailed tooltip text."""
        if not self.enabled:
            return "Bluetooth disabled"
        elif self.connected_count > 0:
            device_names = [dev.name for dev in self.devices if dev.connected]
            return f"Connected: {', '.join(device_names)}"
        else:
            return "Bluetooth enabled (no devices)"

    def to_status_block(self, config: Config) -> Optional[StatusBlock]:
        """Convert to status block."""
        icon = self.get_icon()
        color = self.get_color(config)

        if self.connected_count > 0:
            full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.connected_count}"
            short_text = f"{self.connected_count}"
        else:
            full_text = f"<span font='{config.icon_font}'>{icon}</span>"
            short_text = icon

        return StatusBlock(
            name="bluetooth",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango"
        )


def get_connected_devices(bus: "SystemBus", adapter_path: str) -> List[BluetoothDevice]:
    """Get list of connected Bluetooth devices.

    Args:
        bus: D-Bus system bus
        adapter_path: Path to BlueZ adapter (e.g., /org/bluez/hci0)

    Returns:
        List of BluetoothDevice objects
    """
    devices = []

    try:
        # Get object manager to enumerate devices
        obj_manager = bus.get("org.bluez", "/")

        # Get all managed objects
        managed_objects = obj_manager.GetManagedObjects()

        for path, interfaces in managed_objects.items():
            # Check if this is a device under our adapter
            if "org.bluez.Device1" in interfaces and path.startswith(adapter_path):
                device_props = interfaces["org.bluez.Device1"]

                name = device_props.get("Name", "Unknown Device")
                address = device_props.get("Address", "00:00:00:00:00:00")
                connected = device_props.get("Connected", False)

                devices.append(BluetoothDevice(
                    name=name,
                    address=address,
                    connected=connected
                ))

    except Exception as e:
        logger.error(f"Failed to enumerate Bluetooth devices: {e}")

    return devices


def get_bluetooth_state() -> Optional[BluetoothState]:
    """Query current Bluetooth state via BlueZ D-Bus.

    Returns:
        BluetoothState if adapter present, None if no adapter or error

    Raises:
        None - errors are logged and None is returned
    """
    if not PYDBUS_AVAILABLE:
        return None

    try:
        bus = SystemBus()

        # Try to get default Bluetooth adapter (hci0)
        adapter_path = "/org/bluez/hci0"

        try:
            adapter = bus.get("org.bluez", adapter_path)
        except Exception:
            # No adapter found - desktop without Bluetooth?
            logger.debug("No Bluetooth adapter found (hci0)")
            return None

        # Get adapter properties
        powered = adapter.Powered

        # Get connected devices
        devices = get_connected_devices(bus, adapter_path) if powered else []

        return BluetoothState(
            enabled=powered,
            devices=devices,
            adapter_name="hci0"
        )

    except Exception as e:
        logger.error(f"Failed to query Bluetooth state: {e}")
        return None
