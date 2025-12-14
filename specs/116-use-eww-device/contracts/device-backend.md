# Contract: Device Backend Scripts

**Feature**: 116-use-eww-device
**Date**: 2025-12-13

## Overview

This document defines the interface contracts for backend scripts that provide device state and control operations to Eww widgets.

---

## 1. device-backend.py

Main unified backend script for device state queries.

### Interface

```
Usage: device-backend.py [--mode MODE] [--listen]

Options:
  --mode MODE    Query mode: full | volume | brightness | bluetooth | battery | thermal | network
                 Default: full (all devices)
  --listen       Stream updates continuously (for deflisten)

Output: JSON to stdout
```

### Modes

| Mode       | Output | Use Case |
|------------|--------|----------|
| full       | Complete DeviceState | Initial load, monitoring panel |
| volume     | VolumeState only | Top bar volume widget |
| brightness | BrightnessState only | Top bar brightness widget |
| bluetooth  | BluetoothState only | Top bar bluetooth widget |
| battery    | BatteryState only | Top bar battery widget |
| thermal    | ThermalState only | Monitoring panel |
| network    | NetworkState only | Top bar network widget |

### Examples

```bash
# Full state query
./device-backend.py
# Returns: {"volume": {...}, "brightness": {...}, ...}

# Volume only
./device-backend.py --mode volume
# Returns: {"volume": 75, "muted": false, "icon": "󰕾", ...}

# Streaming mode for deflisten
./device-backend.py --mode volume --listen
# Outputs JSON on each volume change
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Invalid arguments |
| 2    | Hardware detection failed |
| 3    | Permission denied |

---

## 2. volume-control.sh

Volume adjustment wrapper for onclick handlers.

### Interface

```
Usage: volume-control.sh ACTION [VALUE]

Actions:
  get           Get current volume (JSON)
  set VALUE     Set volume to VALUE (0-100)
  up [STEP]     Increase volume by STEP (default: 5)
  down [STEP]   Decrease volume by STEP (default: 5)
  mute          Toggle mute
  device ID     Switch to device ID

Output: JSON status or empty
Exit: 0 on success, 1 on error
```

### Examples

```bash
# Get current volume
./volume-control.sh get
# Returns: {"volume": 75, "muted": false}

# Set volume to 50%
./volume-control.sh set 50

# Increase by 5%
./volume-control.sh up

# Toggle mute
./volume-control.sh mute

# Switch output device
./volume-control.sh device 52
```

---

## 3. brightness-control.sh

Brightness adjustment wrapper.

### Interface

```
Usage: brightness-control.sh ACTION [VALUE] [--device DEVICE]

Actions:
  get           Get current brightness (JSON)
  set VALUE     Set brightness to VALUE (0-100)
  up [STEP]     Increase by STEP (default: 5)
  down [STEP]   Decrease by STEP (default: 5)

Options:
  --device DEVICE  Target device (display|keyboard)
                   Default: display

Output: JSON status or empty
Exit: 0 on success, 1 on error, 2 if device unavailable
```

### Examples

```bash
# Get display brightness
./brightness-control.sh get

# Set display to 75%
./brightness-control.sh set 75

# Decrease keyboard backlight
./brightness-control.sh down --device keyboard
```

---

## 4. bluetooth-control.sh

Bluetooth control wrapper.

### Interface

```
Usage: bluetooth-control.sh ACTION [TARGET]

Actions:
  get           Get bluetooth state (JSON)
  power [on|off|toggle]  Control adapter power
  connect MAC   Connect to device
  disconnect MAC  Disconnect device
  scan [on|off] Control scanning

Output: JSON status or empty
Exit: 0 on success, 1 on error, 2 if bluetooth unavailable
```

### Examples

```bash
# Get bluetooth state
./bluetooth-control.sh get

# Toggle power
./bluetooth-control.sh power toggle

# Connect to device
./bluetooth-control.sh connect E1:4B:6C:22:56:F0

# Start scanning
./bluetooth-control.sh scan on
```

---

## 5. power-profile-control.sh

Power profile control wrapper.

### Interface

```
Usage: power-profile-control.sh ACTION [PROFILE]

Actions:
  get           Get current profile (JSON)
  set PROFILE   Set profile (performance|balanced|power-saver)
  cycle         Cycle to next profile

Output: JSON status or empty
Exit: 0 on success, 1 on error, 2 if profiles unavailable
```

### Examples

```bash
# Get current profile
./power-profile-control.sh get
# Returns: {"current": "balanced", "on_ac": true}

# Set to performance
./power-profile-control.sh set performance

# Cycle profiles
./power-profile-control.sh cycle
```

---

## Eww Integration Patterns

### defpoll (Polling)

```yuck
(defpoll device_state :interval "2s"
  :run-while {current_view_index == 6}
  `device-backend.py`)

(defpoll volume_state :interval "1s"
  `device-backend.py --mode volume`)
```

### deflisten (Event-Driven)

```yuck
(deflisten volume_stream
  `device-backend.py --mode volume --listen`)
```

### onclick Handlers

```yuck
(button
  :onclick "volume-control.sh mute"
  :onscroll "echo {} | sed -e 's/up/up/g' -e 's/down/down/g' | xargs volume-control.sh"
  ...)
```

---

## Error Handling

All scripts follow consistent error patterns:

1. **stderr**: Human-readable error messages
2. **stdout**: Empty or error JSON on failure
3. **Exit code**: Non-zero on error

### Error JSON Format

```json
{
  "error": true,
  "message": "Bluetooth adapter not found",
  "code": "BT_UNAVAILABLE"
}
```

### Error Codes

| Code | Meaning |
|------|---------|
| `BT_UNAVAILABLE` | Bluetooth adapter not found |
| `BRIGHTNESS_UNAVAILABLE` | No brightness device |
| `BATTERY_UNAVAILABLE` | No battery present |
| `PERMISSION_DENIED` | Insufficient permissions |
| `INVALID_VALUE` | Value out of range |
| `DEVICE_NOT_FOUND` | Specified device not found |
