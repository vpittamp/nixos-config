#!/usr/bin/env python3
"""Battery monitoring for Eww top bar widgets

Listens to UPower D-Bus events for battery state changes and outputs JSON
with percentage, charging state, time remaining, and level thresholds.

Output format:
{
  "percentage": 75,
  "charging": false,
  "level": "normal",
  "time_remaining": 7200,
  "time_formatted": "2h 00m",
  "energy_rate": 8.5,
  "energy": 35.2,
  "energy_full": 47.0
}

Features:
- Real-time battery state via D-Bus events
- Time remaining estimate (from UPower)
- Energy rate (watts consumed/charged)
- Desktop notification at 10% and 5% thresholds

Usage:
  python3 battery-monitor.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import subprocess
import sys
from typing import Optional

try:
    from pydbus import SystemBus
    from gi.repository import GLib
except ImportError:
    print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": "pydbus not available"}))
    sys.exit(1)


def format_time(seconds: int) -> str:
    """Format seconds into human-readable time string"""
    if seconds <= 0:
        return "--"

    hours = seconds // 3600
    minutes = (seconds % 3600) // 60

    if hours > 0:
        return f"{hours}h {minutes:02d}m"
    else:
        return f"{minutes}m"


def send_notification(title: str, body: str, urgency: str = "normal", icon: str = "battery-low"):
    """Send desktop notification via notify-send"""
    try:
        subprocess.run([
            "notify-send",
            "-u", urgency,
            "-i", icon,
            "-a", "Battery Monitor",
            title,
            body
        ], check=False, capture_output=True)
    except Exception:
        pass  # Notification failure shouldn't crash the monitor


class BatteryMonitor:
    """Monitor battery state via UPower D-Bus interface"""

    def __init__(self):
        self.bus = SystemBus()
        self.percentage = 0
        self.charging = False
        self.level = "unknown"
        self.time_remaining = 0
        self.energy_rate = 0.0
        self.energy = 0.0
        self.energy_full = 0.0
        self.battery_path = None

        # Track notification state to avoid repeated alerts
        self.notified_10 = False
        self.notified_5 = False

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

            # Get time remaining (seconds)
            if self.charging:
                self.time_remaining = int(self.battery.TimeToFull)
            else:
                self.time_remaining = int(self.battery.TimeToEmpty)

            # Get energy info
            self.energy_rate = round(self.battery.EnergyRate, 1)
            self.energy = round(self.battery.Energy, 1)
            self.energy_full = round(self.battery.EnergyFull, 1)

            # Determine level threshold
            if self.percentage <= 5:
                self.level = "critical"
            elif self.percentage <= 10:
                self.level = "very_low"
            elif self.percentage <= 20:
                self.level = "low"
            elif self.percentage <= 30:
                self.level = "medium"
            else:
                self.level = "normal"

            # Check for low battery notifications (only when discharging)
            self._check_notifications()

            # Output current state
            self._output_state()

        except Exception as e:
            print(json.dumps({"percentage": 0, "charging": False, "level": "unknown", "error": f"State update failed: {e}"}), flush=True)

    def _check_notifications(self):
        """Send notifications at battery thresholds"""
        if self.charging:
            # Reset notification flags when charging
            self.notified_10 = False
            self.notified_5 = False
            return

        # 10% warning
        if self.percentage <= 10 and not self.notified_10:
            self.notified_10 = True
            time_str = format_time(self.time_remaining)
            send_notification(
                "⚠️ Low Battery (10%)",
                f"Battery at {self.percentage}%\nEstimated time remaining: {time_str}\nConsider plugging in.",
                urgency="normal",
                icon="battery-caution"
            )

        # 5% critical warning
        if self.percentage <= 5 and not self.notified_5:
            self.notified_5 = True
            time_str = format_time(self.time_remaining)
            send_notification(
                "🔴 Critical Battery (5%)",
                f"Battery at {self.percentage}%\nEstimated time remaining: {time_str}\nPlug in NOW to avoid data loss!",
                urgency="critical",
                icon="battery-empty"
            )

    def _on_properties_changed(self, interface, changed_properties, invalidated_properties):
        """Handle D-Bus property changes for battery state"""
        # Any property change triggers a full state update
        self._update_state()

    def _output_state(self):
        """Output current battery state as JSON"""
        state = {
            "percentage": self.percentage,
            "charging": self.charging,
            "level": self.level,
            "time_remaining": self.time_remaining,
            "time_formatted": format_time(self.time_remaining),
            "energy_rate": self.energy_rate,
            "energy": self.energy,
            "energy_full": self.energy_full
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
