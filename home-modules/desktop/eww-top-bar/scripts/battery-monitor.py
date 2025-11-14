#!/usr/bin/env python3
"""Battery monitoring for Eww top bar widgets

Listens to UPower D-Bus events for battery state changes and outputs JSON
with percentage, charging state, and level thresholds for deflisten consumption.

Output format:
{
  "percentage": 75,
  "charging": false,
  "level": "normal"  // "critical" (<20%), "low" (20-50%), "normal" (>50%)
}

Usage:
  python3 battery-monitor.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import sys
from typing import Optional

try:
    from pydbus import SystemBus
    from gi.repository import GLib
except ImportError:
    print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": "pydbus not available"}))
    sys.exit(1)


class BatteryMonitor:
    """Monitor battery state via UPower D-Bus interface"""

    def __init__(self):
        self.bus = SystemBus()
        self.percentage = 0
        self.charging = False
        self.level = "unknown"
        self.battery_path = None

        try:
            # Connect to UPower
            self.upower = self.bus.get("org.freedesktop.UPower", "/org/freedesktop/UPower")
            self._find_battery_device()
        except Exception as e:
            print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": f"UPower not available: {e}"}))
            sys.exit(1)

    def _find_battery_device(self):
        """Find the first battery device from UPower"""
        try:
            # Get list of all power devices
            devices = self.upower.EnumerateDevices()

            # Find first battery device (Type=2 means battery)
            for device_path in devices:
                device = self.bus.get("org.freedesktop.UPower", device_path)
                if device.Type == 2:  # Battery type
                    self.battery_path = device_path
                    self.battery = device
                    break

            if not self.battery_path:
                print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": "No battery device found"}))
                sys.exit(1)

            # Get initial state
            self._update_state()

            # Subscribe to property changes
            self.battery.onPropertiesChanged = self._on_properties_changed

        except Exception as e:
            print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": f"Battery enumeration failed: {e}"}))
            sys.exit(1)

    def _update_state(self):
        """Update battery state from D-Bus properties"""
        try:
            # Get battery percentage (0-100)
            self.percentage = int(self.battery.Percentage)

            # Get charging state (State: 1=charging, 2=discharging, 4=fully-charged)
            state = self.battery.State
            self.charging = state in (1, 4)  # Charging or fully charged

            # Determine level threshold
            if self.percentage < 20:
                self.level = "critical"
            elif self.percentage < 50:
                self.level = "low"
            else:
                self.level = "normal"

            # Output current state
            self._output_state()

        except Exception as e:
            print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": f"State update failed: {e}"}), flush=True)

    def _on_properties_changed(self, interface, changed_properties, invalidated_properties):
        """Handle D-Bus property changes for battery state"""
        # Any property change triggers a full state update
        self._update_state()

    def _output_state(self):
        """Output current battery state as JSON"""
        state = {
            "percentage": self.percentage,
            "charging": self.charging,
            "level": self.level
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
    monitor = BatteryMonitor()
    monitor.run()
