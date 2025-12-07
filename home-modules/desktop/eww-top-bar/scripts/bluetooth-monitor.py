#!/usr/bin/env python3
"""Bluetooth monitoring for Eww top bar widgets

Listens to BlueZ D-Bus events for bluetooth adapter and device state changes
and outputs JSON with connection state for deflisten consumption.

Output format:
{
  "state": "connected",  // "connected", "enabled", "disabled"
  "device_count": 2      // Number of connected devices
}

Usage:
  python3 bluetooth-monitor.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import sys
import time
from typing import Optional

try:
    from pydbus import SystemBus
    from gi.repository import GLib
except ImportError:
    print(json.dumps({"state": "disabled", "device_count": 0, "error": "pydbus not available"}))
    sys.exit(1)


class BluetoothMonitor:
    """Monitor Bluetooth state via BlueZ D-Bus interface"""

    def __init__(self):
        self.bus = SystemBus()
        self.state = "disabled"
        self.device_count = 0
        self.adapter_path = None
        self._last_update = 0
        self._pending_update = None
        self._debounce_ms = 500  # Debounce updates to prevent CPU spin

        try:
            # Connect to BlueZ
            self.bluez = self.bus.get("org.bluez", "/")
            self._find_adapter()
        except Exception as e:
            print(json.dumps({"state": "disabled", "device_count": 0, "error": f"BlueZ not available: {e}"}))
            sys.exit(1)

    def _find_adapter(self):
        """Find the first Bluetooth adapter"""
        try:
            # Get managed objects from BlueZ
            managed_objects = self.bluez.GetManagedObjects()

            # Find first adapter (interface: org.bluez.Adapter1)
            for path, interfaces in managed_objects.items():
                if "org.bluez.Adapter1" in interfaces:
                    self.adapter_path = path
                    self.adapter = self.bus.get("org.bluez", path)
                    break

            if not self.adapter_path:
                print(json.dumps({"state": "disabled", "device_count": 0, "error": "No Bluetooth adapter found"}))
                sys.exit(1)

            # Get initial state
            self._update_state()

            # Subscribe to property changes on adapter
            self.adapter.onPropertiesChanged = self._on_adapter_properties_changed

            # Subscribe to interface additions/removals (for device connections)
            self.bluez.onInterfacesAdded = self._on_interfaces_added
            self.bluez.onInterfacesRemoved = self._on_interfaces_removed

        except Exception as e:
            print(json.dumps({"state": "disabled", "device_count": 0, "error": f"Adapter enumeration failed: {e}"}))
            sys.exit(1)

    def _update_state(self):
        """Update Bluetooth state from D-Bus properties"""
        try:
            # Check if adapter is powered on
            powered = self.adapter.Powered

            if not powered:
                self.state = "disabled"
                self.device_count = 0
            else:
                # Count connected devices
                managed_objects = self.bluez.GetManagedObjects()
                connected_devices = 0

                for path, interfaces in managed_objects.items():
                    if "org.bluez.Device1" in interfaces:
                        device = interfaces["org.bluez.Device1"]
                        if device.get("Connected", False):
                            connected_devices += 1

                self.device_count = connected_devices
                self.state = "connected" if connected_devices > 0 else "enabled"

            # Output current state
            self._output_state()

        except Exception as e:
            print(json.dumps({"state": "disabled", "device_count": 0, "error": f"State update failed: {e}"}), flush=True)

    def _schedule_update(self):
        """Schedule a debounced state update to prevent CPU spin from rapid events"""
        now = time.monotonic() * 1000  # ms
        elapsed = now - self._last_update

        if elapsed >= self._debounce_ms:
            # Enough time passed, update immediately
            self._last_update = now
            self._update_state()
        elif self._pending_update is None:
            # Schedule update for later
            delay_ms = int(self._debounce_ms - elapsed)
            self._pending_update = GLib.timeout_add(delay_ms, self._do_pending_update)

    def _do_pending_update(self):
        """Execute pending update"""
        self._pending_update = None
        self._last_update = time.monotonic() * 1000
        self._update_state()
        return False  # Don't repeat

    def _on_adapter_properties_changed(self, interface, changed_properties, invalidated_properties):
        """Handle adapter property changes (e.g., Powered on/off)"""
        if "Powered" in changed_properties:
            self._schedule_update()

    def _on_interfaces_added(self, path, interfaces):
        """Handle new interfaces (e.g., device connected)"""
        if "org.bluez.Device1" in interfaces:
            self._schedule_update()

    def _on_interfaces_removed(self, path, interfaces):
        """Handle removed interfaces (e.g., device disconnected)"""
        if "org.bluez.Device1" in interfaces:
            self._schedule_update()

    def _output_state(self):
        """Output current Bluetooth state as JSON"""
        state = {
            "state": self.state,
            "device_count": self.device_count
        }
        print(json.dumps(state), flush=True)

    def run(self):
        """Start GLib main loop to listen for D-Bus events"""
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            loop.quit()


if __name__ == "__main__":
    monitor = BluetoothMonitor()
    monitor.run()
