# Data Model: Enhanced Swaybar Status

**Branch**: `052-enhanced-swaybar-status` | **Date**: 2025-10-31
**Phase**: 1 - Design & Contracts

## Overview

This document defines the data structures and state management for the enhanced swaybar status feature. All entities follow Python dataclass patterns with type hints and validation.

## Core Entities

### 1. StatusBlock

Represents a single status indicator in the swaybar.

```python
from dataclasses import dataclass
from typing import Optional
from enum import Enum

@dataclass
class StatusBlock:
    """A single status block in the i3bar protocol format"""

    # Required fields
    full_text: str          # Full text to display (with markup)
    name: str               # Block identifier (volume, battery, network, bluetooth)

    # Optional fields
    short_text: Optional[str] = None      # Abbreviated text for small displays
    color: Optional[str] = None           # Hex color code (#RRGGBB)
    background: Optional[str] = None      # Background color
    border: Optional[str] = None          # Border color
    border_top: int = 0                   # Border width (pixels)
    border_right: int = 0
    border_bottom: int = 0
    border_left: int = 0
    min_width: Optional[int] = None       # Minimum width (pixels or string)
    align: str = "left"                   # Text alignment (left, center, right)
    urgent: bool = False                  # Urgent flag (highlights block)
    separator: bool = True                # Show separator after block
    separator_block_width: int = 15       # Separator width
    markup: str = "pango"                 # Markup type (none, pango)
    instance: Optional[str] = None        # Block instance identifier

    def to_json(self) -> dict:
        """Convert to i3bar protocol JSON format"""
        return {
            k: v for k, v in self.__dict__.items()
            if v is not None and (not isinstance(v, int) or v != 0)
        }
```

**Relationships**: StatusBlock is output by StatusGenerator and consumed by swaybar

**Validation Rules**:
- `full_text` must not be empty
- `color`, `background`, `border` must be valid hex colors if provided
- `align` must be one of: left, center, right
- `markup` must be one of: none, pango

**State Transitions**: Blocks are created fresh on each update cycle (immutable)

---

### 2. VolumeState

Represents the current audio volume state.

```python
@dataclass
class VolumeState:
    """Current audio volume state"""

    level: int              # Volume level (0-100)
    muted: bool             # Mute state
    sink_name: str          # Audio sink/device name

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state"""
        if self.muted:
            return "󰝟"  # nf-md-volume_mute
        elif self.level >= 70:
            return "󰕾"  # nf-md-volume_high
        elif self.level >= 30:
            return "󰖀"  # nf-md-volume_medium
        else:
            return "󰕿"  # nf-md-volume_low

    def get_color(self, theme: 'ColorTheme') -> str:
        """Get color based on state"""
        if self.muted:
            return theme.volume.muted
        return theme.volume.normal

    def to_status_block(self, config: 'Config') -> StatusBlock:
        """Convert to status block"""
        icon = self.get_icon()
        color = self.get_color(config.theme)
        full_text = f"<span font='{config.icon_font}'>{icon}</span> {self.level}%"
        short_text = f"{self.level}%"

        return StatusBlock(
            name="volume",
            full_text=full_text,
            short_text=short_text,
            color=color,
            markup="pango"
        )
```

**Relationships**: Queried from PulseAudio/PipeWire D-Bus interface

**Validation Rules**:
- `level` must be 0-100
- `sink_name` must not be empty

---

### 3. BatteryState

Represents the current battery state.

```python
class BatteryStatus(Enum):
    CHARGING = "charging"
    DISCHARGING = "discharging"
    FULL = "full"
    UNKNOWN = "unknown"

@dataclass
class BatteryState:
    """Current battery state"""

    percentage: int                      # Charge level (0-100)
    status: BatteryStatus                # Charging status
    time_to_empty: Optional[int] = None  # Seconds until empty (if discharging)
    time_to_full: Optional[int] = None   # Seconds until full (if charging)
    present: bool = True                 # Battery present flag

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state"""
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

    def get_color(self, theme: 'ColorTheme') -> str:
        """Get color based on state"""
        if self.status == BatteryStatus.CHARGING:
            return theme.battery.charging
        elif self.percentage >= 50:
            return theme.battery.high
        elif self.percentage >= 20:
            return theme.battery.medium
        else:
            return theme.battery.low

    def get_tooltip(self) -> str:
        """Get detailed tooltip text"""
        if self.time_to_empty is not None:
            hours, remainder = divmod(self.time_to_empty, 3600)
            minutes, _ = divmod(remainder, 60)
            return f"{self.percentage}% - {hours}h {minutes}m remaining"
        elif self.time_to_full is not None:
            hours, remainder = divmod(self.time_to_full, 3600)
            minutes, _ = divmod(remainder, 60)
            return f"{self.percentage}% - {hours}h {minutes}m until full"
        else:
            return f"{self.percentage}% - {self.status.value}"

    def to_status_block(self, config: 'Config') -> Optional[StatusBlock]:
        """Convert to status block (None if battery not present)"""
        if not self.present:
            return None

        icon = self.get_icon()
        color = self.get_color(config.theme)
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
```

**Relationships**: Queried from UPower D-Bus interface (`/org/freedesktop/UPower/devices/battery_BAT0`)

**Validation Rules**:
- `percentage` must be 0-100
- `time_to_empty` and `time_to_full` must be non-negative if provided
- Only one of `time_to_empty` or `time_to_full` should be set at a time

---

### 4. NetworkState

Represents the current WiFi network state.

```python
class ConnectionState(Enum):
    CONNECTED = "connected"
    CONNECTING = "connecting"
    DISCONNECTED = "disconnected"
    DISABLED = "disabled"

@dataclass
class NetworkState:
    """Current WiFi network state"""

    state: ConnectionState
    ssid: Optional[str] = None           # Connected network name
    signal_strength: Optional[int] = None # Signal strength (0-100)
    device_name: str = "wlan0"           # Network device name

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state"""
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

    def get_color(self, theme: 'ColorTheme') -> str:
        """Get color based on state"""
        if self.state == ConnectionState.DISCONNECTED:
            return theme.network.disconnected
        elif self.state == ConnectionState.DISABLED:
            return theme.network.disabled
        elif self.signal_strength is not None and self.signal_strength < 40:
            return theme.network.weak
        else:
            return theme.network.connected

    def get_tooltip(self) -> str:
        """Get detailed tooltip text"""
        if self.state == ConnectionState.CONNECTED and self.ssid:
            return f"Connected to {self.ssid} ({self.signal_strength}%)"
        elif self.state == ConnectionState.CONNECTING:
            return "Connecting..."
        elif self.state == ConnectionState.DISABLED:
            return "WiFi disabled"
        else:
            return "Disconnected"

    def to_status_block(self, config: 'Config') -> StatusBlock:
        """Convert to status block"""
        icon = self.get_icon()
        color = self.get_color(config.theme)

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
```

**Relationships**: Queried from NetworkManager D-Bus interface

**Validation Rules**:
- `signal_strength` must be 0-100 if provided
- `ssid` should only be set when `state` is CONNECTED

---

### 5. BluetoothState

Represents the current Bluetooth state.

```python
@dataclass
class BluetoothDevice:
    """A paired/connected Bluetooth device"""
    name: str
    address: str
    connected: bool

@dataclass
class BluetoothState:
    """Current Bluetooth state"""

    enabled: bool
    devices: list[BluetoothDevice]
    adapter_name: str = "hci0"

    @property
    def connected_count(self) -> int:
        """Number of connected devices"""
        return sum(1 for dev in self.devices if dev.connected)

    def get_icon(self) -> str:
        """Get Nerd Font icon based on state"""
        if not self.enabled:
            return "󰂲"  # nf-md-bluetooth_off
        elif self.connected_count > 0:
            return "󰂱"  # nf-md-bluetooth_connected
        else:
            return "󰂯"  # nf-md-bluetooth

    def get_color(self, theme: 'ColorTheme') -> str:
        """Get color based on state"""
        if not self.enabled:
            return theme.bluetooth.disabled
        elif self.connected_count > 0:
            return theme.bluetooth.connected
        else:
            return theme.bluetooth.enabled

    def get_tooltip(self) -> str:
        """Get detailed tooltip text"""
        if not self.enabled:
            return "Bluetooth disabled"
        elif self.connected_count > 0:
            device_names = [dev.name for dev in self.devices if dev.connected]
            return f"Connected: {', '.join(device_names)}"
        else:
            return "Bluetooth enabled (no devices)"

    def to_status_block(self, config: 'Config') -> Optional[StatusBlock]:
        """Convert to status block (None if adapter not present)"""
        icon = self.get_icon()
        color = self.get_color(config.theme)

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
```

**Relationships**: Queried from BlueZ D-Bus interface (`/org/bluez/hci0`)

**Validation Rules**:
- `devices` list must not contain duplicates (by address)
- Device addresses must be valid Bluetooth MAC addresses

---

### 6. ColorTheme

Represents the color theme for status blocks.

```python
@dataclass
class VolumeColors:
    normal: str = "#a6e3a1"   # Green (Catppuccin Mocha)
    muted: str = "#6c7086"    # Gray

@dataclass
class BatteryColors:
    charging: str = "#a6e3a1"  # Green
    high: str = "#a6e3a1"      # Green (>50%)
    medium: str = "#f9e2af"    # Yellow (20-50%)
    low: str = "#f38ba8"       # Red (<20%)

@dataclass
class NetworkColors:
    connected: str = "#a6e3a1"     # Green
    connecting: str = "#f9e2af"    # Yellow
    disconnected: str = "#6c7086"  # Gray
    disabled: str = "#6c7086"      # Gray
    weak: str = "#f9e2af"          # Yellow (<40% signal)

@dataclass
class BluetoothColors:
    connected: str = "#89b4fa"   # Blue
    enabled: str = "#a6e3a1"     # Green
    disabled: str = "#6c7086"    # Gray

@dataclass
class ColorTheme:
    """Complete color theme for status bar"""
    name: str
    volume: VolumeColors
    battery: BatteryColors
    network: NetworkColors
    bluetooth: BluetoothColors
```

**Relationships**: Used by all state entities to determine display colors

**Validation Rules**:
- All color values must be valid hex colors (#RRGGBB)

---

### 7. Config

Represents the complete status generator configuration.

```python
@dataclass
class UpdateIntervals:
    battery: int = 30      # Seconds
    volume: int = 1
    network: int = 5
    bluetooth: int = 10

@dataclass
class ClickHandlers:
    volume: str = "pavucontrol"
    network: str = "nm-connection-editor"
    bluetooth: str = "blueman-manager"
    battery: str = ""  # No default handler

@dataclass
class Config:
    """Complete status generator configuration"""

    enabled: bool = True
    icon_font: str = "NerdFont"
    theme: ColorTheme = None  # Default theme loaded at init
    intervals: UpdateIntervals = UpdateIntervals()
    click_handlers: ClickHandlers = ClickHandlers()

    # Hardware detection flags
    detect_battery: bool = True
    detect_bluetooth: bool = True

    def __post_init__(self):
        if self.theme is None:
            self.theme = ColorTheme(
                name="catppuccin-mocha",
                volume=VolumeColors(),
                battery=BatteryColors(),
                network=NetworkColors(),
                bluetooth=BluetoothColors()
            )
```

**Relationships**: Used by StatusGenerator to configure behavior and appearance

---

### 8. ClickEvent

Represents a click event from swaybar.

```python
class MouseButton(Enum):
    LEFT = 1
    MIDDLE = 2
    RIGHT = 3
    SCROLL_UP = 4
    SCROLL_DOWN = 5

@dataclass
class ClickEvent:
    """A click event from swaybar (i3bar protocol)"""

    name: str               # Block name (volume, battery, etc.)
    instance: Optional[str] # Block instance
    button: MouseButton     # Mouse button
    x: int                  # Click X coordinate
    y: int                  # Click Y coordinate

    @classmethod
    def from_json(cls, data: dict) -> 'ClickEvent':
        """Parse from i3bar protocol JSON"""
        return cls(
            name=data["name"],
            instance=data.get("instance"),
            button=MouseButton(data["button"]),
            x=data["x"],
            y=data["y"]
        )
```

**Relationships**: Received from swaybar stdin, processed by ClickHandler

---

## Entity Relationships

```
┌─────────────────┐
│  StatusGenerator │
└────────┬─────────┘
         │
         ├──> VolumeState ────────> StatusBlock
         │
         ├──> BatteryState ───────> StatusBlock (optional)
         │
         ├──> NetworkState ───────> StatusBlock
         │
         ├──> BluetoothState ─────> StatusBlock (optional)
         │
         └──> ColorTheme (used by all states)

┌─────────────────┐
│   ClickHandler   │
└────────┬─────────┘
         │
         └──> ClickEvent ──> Subprocess (launch handler)
```

## Data Flow

1. **Status Update Cycle**:
   - StatusGenerator queries system state via D-Bus
   - Each state entity (VolumeState, BatteryState, etc.) creates StatusBlock
   - StatusBlocks serialized to JSON array
   - JSON printed to stdout (consumed by swaybar)

2. **Click Event Cycle**:
   - User clicks status block in swaybar
   - swaybar sends ClickEvent JSON to stdin
   - ClickHandler parses event, looks up handler command from Config
   - Handler subprocess launched asynchronously

## Persistence

**No persistent storage required** - all state is ephemeral and queried from system services. Configuration is managed via NixOS/home-manager and loaded at startup.
