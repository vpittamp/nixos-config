# Research: Device Control Tools for Eww Integration

**Feature**: 116-use-eww-device
**Date**: 2025-12-13

## Overview

This document captures research on the CLI tools and best practices for implementing device controls in Eww widgets. The focus is on real-time updates with minimal polling overhead.

---

## 1. Volume Control (WirePlumber/wpctl)

### Decision
Use `wpctl` for all audio control operations with PipeWire/WirePlumber backend.

### Rationale
- Native PipeWire tool, no legacy PulseAudio dependencies
- Simple percentage-based API
- Supports device enumeration and switching

### Key Commands

```bash
# Get volume percentage
wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -oP 'Volume: \K[\d.]+' | awk '{print int($1*100)}'

# Set volume (0-100%)
wpctl set-volume @DEFAULT_SINK@ 0.75          # 75%
wpctl set-volume @DEFAULT_SINK@ 5%+           # +5%
wpctl set-volume @DEFAULT_SINK@ 5%-           # -5%
wpctl set-volume --limit 1.0 @DEFAULT_SINK@ 10%+  # Cap at 100%

# Mute toggle
wpctl set-mute @DEFAULT_SINK@ toggle

# List devices
wpctl status

# Switch output device
wpctl set-default <device_id>
```

### Update Strategy
- **Polling**: 1s interval for defpoll
- **Event-driven alternative**: Monitor PipeWire D-Bus signals (more complex)

---

## 2. Brightness Control (brightnessctl)

### Decision
Use `brightnessctl` for both display and keyboard backlight control.

### Rationale
- Works without X11 (pure sysfs)
- Supports device enumeration
- Percentage-based API

### Key Commands

```bash
# Get brightness percentage
brightnessctl get | awk -v max=$(brightnessctl max) '{printf "%.0f", ($1/max)*100}'
# Or simpler:
brightnessctl -P get                           # Built-in percentage mode

# Set brightness
brightnessctl set 50%                          # Absolute
brightnessctl set 5%+                          # Relative increase
brightnessctl set 5%-                          # Relative decrease

# List devices
brightnessctl -l

# Control specific device
brightnessctl -d intel_backlight set 75%       # Display
brightnessctl -d tpacpi::kbd_backlight set 2   # Keyboard (ThinkPad)
```

### ThinkPad Device Names
- Display: `intel_backlight` or `amdgpu_bl0`
- Keyboard: `tpacpi::kbd_backlight`

### M1 Device Names
- Display: `apple-panel-bl`
- Keyboard: `kbd_backlight`

### Update Strategy
- **Polling**: 2s interval (brightness changes infrequently)

---

## 3. Bluetooth Control (bluetoothctl + D-Bus)

### Decision
Use `bluetoothctl` for commands, D-Bus for real-time status.

### Rationale
- `bluetoothctl` is non-interactive for commands
- D-Bus provides event-driven updates without polling

### Key Commands

```bash
# Get power state
bluetoothctl show | grep "Powered:" | awk '{print $2}'

# Toggle power
bluetoothctl power on
bluetoothctl power off

# List paired devices
bluetoothctl devices Paired

# Get device connection status
bluetoothctl info <MAC> | grep "Connected:" | awk '{print $2}'

# Connect/disconnect
bluetoothctl connect <MAC>
bluetoothctl disconnect <MAC>
```

### D-Bus Monitoring (Event-Driven)

```bash
# Monitor all Bluetooth events
gdbus monitor --system --dest org.bluez | grep -E "Connected|Powered"
```

### Update Strategy
- **Event-driven**: D-Bus subscription via deflisten script
- **Fallback polling**: 3s interval

---

## 4. Battery Status (UPower)

### Decision
Use UPower D-Bus interface for real-time battery monitoring.

### Rationale
- Event-driven updates on charge/discharge
- Standard freedesktop interface
- Rich data (percentage, state, time remaining)

### Key Commands

```bash
# Get battery percentage
upower -i $(upower -e | grep BAT) | grep percentage | awk '{print $2}' | tr -d '%'

# Get charging state
upower -i $(upower -e | grep BAT) | grep state | awk '{print $2}'

# Get time remaining
upower -i $(upower -e | grep BAT) | grep "time to" | awk '{print $4, $5}'
```

### D-Bus Monitoring

```bash
# Monitor battery changes
gdbus monitor --system --dest org.freedesktop.UPower \
  --object-path /org/freedesktop/UPower/devices/battery_BAT0
```

### Update Strategy
- **Event-driven**: D-Bus subscription
- Fallback polling: 5s interval

---

## 5. Power Profiles (TLP)

### Decision
Use TLP CLI for ThinkPad (TLP is already configured), check for power-profiles-daemon as alternative.

### Rationale
- TLP is already installed on ThinkPad configuration
- power-profiles-daemon may be available on other systems
- Note: TLP and power-profiles-daemon conflict; only one active

### Key Commands (TLP)

```bash
# Get current mode (based on AC/battery)
tlp-stat -s | grep "Mode:" | awk '{print $2}'

# Force AC mode (performance)
sudo tlp ac

# Force battery mode (power-saver)
sudo tlp bat

# Auto mode
sudo tlp start
```

### Alternative (power-profiles-daemon)

```bash
# Get current profile
powerprofilesctl get

# Set profile
powerprofilesctl set balanced
powerprofilesctl set power-saver
powerprofilesctl set performance
```

### Update Strategy
- **Polling**: 5s interval (profiles change infrequently)
- Check which tool is available at runtime

---

## 6. Thermal Monitoring (lm_sensors)

### Decision
Use `sensors -j` for JSON output, poll at 2s intervals.

### Rationale
- Native JSON output simplifies parsing
- Widely available on all systems
- Consistent interface across AMD/Intel

### Key Commands

```bash
# Get all sensors as JSON
sensors -j

# Parse CPU temperature
sensors -j | jq '.. | objects | select(.temp1_input) | .temp1_input | floor' | head -1

# Get fan speeds
sensors | grep -i "fan" | awk '{print $2}'
```

### ThinkPad Sensors
- CPU: `coretemp-isa-0000` or `thinkpad-isa-0000`
- Fan: `thinkpad-isa-0000` (fan1_input)

### Ryzen Sensors
- CPU: `k10temp-pci-00c3` (Tctl, Tccd1)
- No integrated fan control (external)

### Update Strategy
- **Polling**: 2s interval (temperature changes slowly)

---

## 7. Network Status (nmcli)

### Decision
Use `nmcli` for status, `nmcli monitor` for events.

### Rationale
- NetworkManager is already enabled
- Event-driven monitoring available
- Rich WiFi information (SSID, signal strength)

### Key Commands

```bash
# Get current WiFi SSID
nmcli -t -f active,ssid dev wifi | grep "^yes" | cut -d: -f2

# Get connection type
nmcli -t -f TYPE connection show --active | head -1

# Get WiFi signal strength
nmcli dev wifi list | grep "^\*" | awk '{print $(NF-1)}'

# Get Tailscale status
tailscale status --json | jq -r '.Self.Online'
```

### Event Monitoring

```bash
# Monitor connection changes
nmcli monitor
```

### Update Strategy
- **Event-driven**: nmcli monitor with deflisten
- Fallback polling: 5s interval

---

## Hardware Detection Strategy

### Runtime Detection Pattern

```nix
# In Eww backend script
hasBattery = builtins.pathExists "/sys/class/power_supply/BAT0";
hasBrightness = builtins.pathExists "/sys/class/backlight";
hasBluetooth = config.hardware.bluetooth.enable;
hasThermalSensors = builtins.pathExists "/sys/class/hwmon";
```

### Python Detection

```python
import os
from pathlib import Path

def detect_hardware():
    return {
        "battery": Path("/sys/class/power_supply/BAT0").exists(),
        "brightness": any(Path("/sys/class/backlight").iterdir()),
        "bluetooth": Path("/sys/class/bluetooth").exists(),
        "thermal": any(Path("/sys/class/hwmon").iterdir()),
        "wifi": Path("/sys/class/net/wlan0").exists() or
                Path("/sys/class/net/wlp0s20f3").exists(),
    }
```

---

## Eww Architecture Recommendations

### Tier 1: Top Bar (Quick Controls)
- Use defpoll with short intervals (1-2s)
- Click handlers expand to reveal sliders
- Click-outside-to-close via eventbox

### Tier 2: Monitoring Panel (Full Dashboard)
- Use defpoll with run-while (only when tab visible)
- Longer intervals (3-5s) for detailed data
- Keyboard navigation support

### Backend Script Structure

```python
#!/usr/bin/env python3
"""Unified device backend for Eww widgets."""

import json
import subprocess
from dataclasses import dataclass, asdict

@dataclass
class DeviceState:
    volume: int
    volume_muted: bool
    brightness: int | None
    keyboard_brightness: int | None
    bluetooth_enabled: bool
    bluetooth_devices: list
    battery_percent: int | None
    battery_charging: bool | None
    battery_time: str | None
    power_profile: str | None
    cpu_temp: int | None
    fan_speed: int | None
    wifi_ssid: str | None
    tailscale_connected: bool

def get_device_state() -> DeviceState:
    # Query all devices and return unified state
    pass

if __name__ == "__main__":
    state = get_device_state()
    print(json.dumps(asdict(state)))
```

---

## Alternatives Considered

### pavucontrol for Volume
- Rejected: GTK app (~1GB with dependencies), not suitable for Eww integration

### blueman for Bluetooth
- Rejected: GTK app (~800MB), better to use bluetoothctl directly

### powerstat for Battery
- Rejected: Not as widely available as UPower

### hwinfo for Thermals
- Rejected: Heavier than lm_sensors, no JSON output

---

## Sources

- WirePlumber wpctl: https://pipewire.pages.freedesktop.org/wireplumber/tools/wpctl.html
- brightnessctl: https://github.com/Hummer12007/brightnessctl
- BlueZ D-Bus: https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc
- UPower D-Bus: https://upower.freedesktop.org/docs/UPower.html
- TLP Documentation: https://linrunner.de/tlp/
- lm_sensors: https://github.com/lm-sensors/lm-sensors
- NetworkManager nmcli: https://networkmanager.dev/docs/api/latest/nmcli.html
