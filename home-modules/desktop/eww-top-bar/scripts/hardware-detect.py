#!/usr/bin/env python3
"""Hardware detection for Eww top bar widgets

Returns JSON with hardware capabilities:
- battery: true if /sys/class/power_supply/BAT* exists
- bluetooth: true if bluez D-Bus interface available
- thermal: true if /sys/class/thermal/thermal_zone* exists
"""
import json
import os
from pathlib import Path


def detect_battery() -> bool:
    """Check for battery hardware via /sys/class/power_supply/BAT*"""
    try:
        power_supply_path = Path("/sys/class/power_supply")
        if not power_supply_path.exists():
            return False
        return any(power_supply_path.glob("BAT*"))
    except Exception:
        return False


def detect_bluetooth() -> bool:
    """Check for bluetooth hardware via bluez D-Bus interface"""
    try:
        import pydbus
        bus = pydbus.SystemBus()
        # Try to access bluez service
        bluez = bus.get("org.bluez", "/")
        return True
    except Exception:
        return False


def detect_thermal() -> bool:
    """Check for thermal sensors via /sys/class/thermal/thermal_zone*"""
    try:
        thermal_path = Path("/sys/class/thermal")
        if not thermal_path.exists():
            return False
        return any(thermal_path.glob("thermal_zone*"))
    except Exception:
        return False


if __name__ == "__main__":
    capabilities = {
        "battery": detect_battery(),
        "bluetooth": detect_bluetooth(),
        "thermal": detect_thermal(),
    }
    print(json.dumps(capabilities))
