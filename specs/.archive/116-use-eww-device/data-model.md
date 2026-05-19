# Data Model: Eww Device Controls

**Feature**: 116-use-eww-device
**Date**: 2025-12-13

## Overview

This document defines the data structures used by the device control backend and Eww widgets. All data is stateless (queried in real-time from system).

---

## Core Entities

### DeviceState

Root entity representing the complete state of all device controls.

```python
@dataclass
class DeviceState:
    """Complete device state for Eww widget consumption."""

    # Audio
    volume: VolumeState

    # Display (laptop only)
    brightness: BrightnessState | None

    # Bluetooth
    bluetooth: BluetoothState

    # Power (laptop only)
    battery: BatteryState | None
    power_profile: PowerProfileState | None

    # Thermal
    thermal: ThermalState

    # Network
    network: NetworkState

    # Hardware detection flags
    hardware: HardwareCapabilities
```

---

### VolumeState

Audio volume and output device information.

```python
@dataclass
class VolumeState:
    """Audio volume state."""

    volume: int              # 0-100 percentage
    muted: bool              # True if muted
    icon: str                # Nerd font icon based on level

    # Output device
    current_device: str      # Active output device name
    devices: list[AudioDevice]  # Available output devices

@dataclass
class AudioDevice:
    """Audio output device."""

    id: int                  # WirePlumber device ID
    name: str                # Display name
    type: str                # "speaker" | "headphones" | "bluetooth"
    active: bool             # Currently selected
```

**Icon Mapping**:
| Volume Level | Muted | Icon |
|-------------|-------|------|
| 0           | -     | 󰝟    |
| 1-33        | No    | 󰕿    |
| 34-66       | No    | 󰖀    |
| 67-100      | No    | 󰕾    |
| Any         | Yes   | 󰝟    |

---

### BrightnessState

Display and keyboard backlight brightness (laptop only).

```python
@dataclass
class BrightnessState:
    """Brightness state for displays and keyboard."""

    # Display brightness
    display: int             # 0-100 percentage
    display_device: str      # e.g., "intel_backlight"

    # Keyboard backlight (optional)
    keyboard: int | None     # 0-100 percentage or None if unavailable
    keyboard_device: str | None  # e.g., "tpacpi::kbd_backlight"
```

**Device Detection**:
- ThinkPad display: `intel_backlight`
- ThinkPad keyboard: `tpacpi::kbd_backlight`
- M1 display: `apple-panel-bl`
- M1 keyboard: `kbd_backlight`

---

### BluetoothState

Bluetooth adapter and paired device information.

```python
@dataclass
class BluetoothState:
    """Bluetooth adapter and device state."""

    enabled: bool            # Adapter power state
    scanning: bool           # Currently scanning
    devices: list[BluetoothDevice]  # Paired devices

@dataclass
class BluetoothDevice:
    """Paired Bluetooth device."""

    mac: str                 # MAC address
    name: str                # Device name
    type: str                # "headphones" | "keyboard" | "mouse" | "speaker" | "other"
    connected: bool          # Currently connected
    battery: int | None      # Battery level if available
    icon: str                # Nerd font icon based on type
```

**Icon Mapping**:
| Type       | Icon |
|------------|------|
| headphones | 󰋋    |
| keyboard   | 󰌌    |
| mouse      | 󰍽    |
| speaker    | 󰓃    |
| other      | 󰂯    |

---

### BatteryState

Battery status (laptop only).

```python
@dataclass
class BatteryState:
    """Battery status."""

    percentage: int          # 0-100
    state: str               # "charging" | "discharging" | "full" | "empty"
    time_remaining: str | None  # e.g., "2h 30m" or None
    icon: str                # Nerd font icon based on level/state
    level: str               # "critical" | "low" | "normal" | "full"

    # Health info (for monitoring panel)
    health: int | None       # Battery health percentage
    cycles: int | None       # Charge cycles
    power_draw: float | None # Current power draw in watts
```

**Icon Mapping**:
| State      | Level    | Icon |
|------------|----------|------|
| charging   | any      | 󰂄    |
| discharging| 0-10     | 󰂎    |
| discharging| 11-20    | 󰁺    |
| discharging| 21-30    | 󰁻    |
| discharging| 31-40    | 󰁼    |
| discharging| 41-50    | 󰁽    |
| discharging| 51-60    | 󰁾    |
| discharging| 61-70    | 󰁿    |
| discharging| 71-80    | 󰂀    |
| discharging| 81-90    | 󰂁    |
| discharging| 91-100   | 󰂂    |
| full       | 100      | 󰁹    |

---

### PowerProfileState

Power profile / TLP status (laptop only).

```python
@dataclass
class PowerProfileState:
    """Power profile status."""

    current: str             # "performance" | "balanced" | "power-saver"
    on_ac: bool              # True if plugged in
    available: list[str]     # Available profiles
    icon: str                # Nerd font icon
```

**Icon Mapping**:
| Profile     | Icon |
|-------------|------|
| performance | 󱐋    |
| balanced    | 󰾅    |
| power-saver | 󰾆    |

---

### ThermalState

CPU temperature and fan status.

```python
@dataclass
class ThermalState:
    """Thermal monitoring state."""

    cpu_temp: int            # CPU temperature in Celsius
    cpu_temp_max: int        # Max safe temperature
    level: str               # "cool" | "warm" | "hot" | "critical"
    icon: str                # Nerd font icon

    # Fan info (optional)
    fan_speed: int | None    # RPM if available
    fan_speed_max: int | None

@dataclass
class ThermalZone:
    """Individual thermal zone (for monitoring panel)."""

    name: str                # e.g., "CPU", "GPU", "SSD"
    temp: int                # Temperature in Celsius
    max_temp: int            # Threshold temperature
```

**Level Thresholds**:
| Temperature | Level    |
|------------|----------|
| < 50°C     | cool     |
| 50-70°C    | warm     |
| 70-85°C    | hot      |
| > 85°C     | critical |

---

### NetworkState

WiFi and VPN connection status.

```python
@dataclass
class NetworkState:
    """Network connection state."""

    # WiFi
    wifi_enabled: bool       # WiFi radio state
    wifi_connected: bool     # Connected to a network
    wifi_ssid: str | None    # Current SSID
    wifi_signal: int | None  # Signal strength 0-100
    wifi_icon: str           # Icon based on signal

    # VPN
    tailscale_connected: bool
    tailscale_ip: str | None
```

**WiFi Icon Mapping**:
| Signal    | Icon |
|-----------|------|
| 0         | 󰤯    |
| 1-25      | 󰤟    |
| 26-50     | 󰤢    |
| 51-75     | 󰤥    |
| 76-100    | 󰤨    |
| Disabled  | 󰤭    |

---

### HardwareCapabilities

Detected hardware features per machine.

```python
@dataclass
class HardwareCapabilities:
    """Hardware detection flags."""

    has_battery: bool        # Battery present
    has_brightness: bool     # Display brightness controllable
    has_keyboard_backlight: bool  # Keyboard backlight present
    has_bluetooth: bool      # Bluetooth adapter present
    has_wifi: bool           # WiFi adapter present
    has_thermal_sensors: bool # lm_sensors available
    has_fan_control: bool    # Fan speed readable
    has_power_profiles: bool # TLP or power-profiles-daemon

    # Machine identification
    hostname: str            # "thinkpad" | "ryzen" | etc.
    is_laptop: bool          # Derived from has_battery
```

**Detection Paths**:
| Capability       | Detection Path |
|-----------------|----------------|
| battery         | `/sys/class/power_supply/BAT*` |
| brightness      | `/sys/class/backlight/*` |
| keyboard_backlight | `/sys/class/leds/*kbd*` |
| bluetooth       | `/sys/class/bluetooth/*` |
| wifi            | `/sys/class/net/wl*` |
| thermal_sensors | `/sys/class/hwmon/*` |

---

## JSON Output Format

The backend script outputs a single JSON object for Eww consumption.

```json
{
  "volume": {
    "volume": 75,
    "muted": false,
    "icon": "󰕾",
    "current_device": "Built-in Speakers",
    "devices": [
      {"id": 41, "name": "Built-in Speakers", "type": "speaker", "active": true},
      {"id": 52, "name": "Bluetooth Headphones", "type": "bluetooth", "active": false}
    ]
  },
  "brightness": {
    "display": 80,
    "display_device": "intel_backlight",
    "keyboard": 50,
    "keyboard_device": "tpacpi::kbd_backlight"
  },
  "bluetooth": {
    "enabled": true,
    "scanning": false,
    "devices": [
      {"mac": "E1:4B:6C:22:56:F0", "name": "AirPods Pro", "type": "headphones", "connected": true, "battery": 85, "icon": "󰋋"}
    ]
  },
  "battery": {
    "percentage": 72,
    "state": "discharging",
    "time_remaining": "3h 45m",
    "icon": "󰁿",
    "level": "normal",
    "health": 92,
    "cycles": 245,
    "power_draw": 8.5
  },
  "power_profile": {
    "current": "balanced",
    "on_ac": false,
    "available": ["performance", "balanced", "power-saver"],
    "icon": "󰾅"
  },
  "thermal": {
    "cpu_temp": 58,
    "cpu_temp_max": 100,
    "level": "warm",
    "icon": "󰔐",
    "fan_speed": 2500,
    "fan_speed_max": 5000
  },
  "network": {
    "wifi_enabled": true,
    "wifi_connected": true,
    "wifi_ssid": "HomeNetwork",
    "wifi_signal": 85,
    "wifi_icon": "󰤨",
    "tailscale_connected": true,
    "tailscale_ip": "100.64.0.5"
  },
  "hardware": {
    "has_battery": true,
    "has_brightness": true,
    "has_keyboard_backlight": true,
    "has_bluetooth": true,
    "has_wifi": true,
    "has_thermal_sensors": true,
    "has_fan_control": true,
    "has_power_profiles": true,
    "hostname": "thinkpad",
    "is_laptop": true
  }
}
```

---

## State Transitions

### Volume
- `set_volume(value: int)` → Updates volume 0-100
- `toggle_mute()` → Toggles muted state
- `set_device(device_id: int)` → Switches output device

### Brightness
- `set_brightness(value: int, device: str)` → Updates brightness 0-100

### Bluetooth
- `toggle_power()` → Toggles adapter power
- `connect(mac: str)` → Connects to device
- `disconnect(mac: str)` → Disconnects device

### Power Profile
- `set_profile(profile: str)` → Switches power profile

---

## Validation Rules

1. **Volume**: Must be 0-100, integers only
2. **Brightness**: Must be 0-100, integers only
3. **MAC addresses**: Must match `XX:XX:XX:XX:XX:XX` format
4. **Power profiles**: Must be one of available profiles
5. **Hardware flags**: Read-only, determined at startup
