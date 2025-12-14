# Quickstart: Eww Device Controls

**Feature**: 116-use-eww-device
**Date**: 2025-12-13

## Overview

Unified device control system for bare metal NixOS machines providing quick access via top bar and comprehensive monitoring via the Devices tab.

---

## Quick Access (Top Bar)

### Volume Control

| Action | Method |
|--------|--------|
| View volume | Look at 󰕾 icon in top bar |
| Adjust volume | Click icon, drag slider |
| Quick adjust | Scroll over icon |
| Mute toggle | Click 󰝟 icon in expanded panel |
| Switch output | Click device in dropdown |

### Brightness Control (Laptop Only)

| Action | Method |
|--------|--------|
| View brightness | Look at 󰃟 icon in top bar |
| Adjust display | Click icon, drag slider |
| Adjust keyboard | Click icon, use second slider |

### Bluetooth

| Action | Method |
|--------|--------|
| View status | Look at 󰂯 icon (blue = connected) |
| Toggle Bluetooth | Click icon, use toggle switch |
| Connect device | Click device in list |
| Disconnect device | Click connected device |

### Battery (Laptop Only)

| Action | Method |
|--------|--------|
| View percentage | Look at battery icon |
| View time remaining | Click to expand |
| View power profile | See profile pill in expanded panel |
| Change profile | Click profile to cycle |

---

## Comprehensive Dashboard (Monitoring Panel)

### Opening the Devices Tab

| Method | Keys |
|--------|------|
| Open panel | `Mod+M` |
| Switch to Devices | `Alt+7` (or click tab) |
| Enter focus mode | `Mod+Shift+M` |

### Keyboard Navigation (Focus Mode)

| Key | Action |
|-----|--------|
| `j` / `↓` | Navigate down |
| `k` / `↑` | Navigate up |
| `Enter` / `l` | Select/toggle item |
| `h` / `←` | Go back / collapse |
| `Escape` | Exit focus mode |

### Dashboard Sections

1. **Audio**
   - Current output device
   - Volume slider
   - Microphone status
   - Output device selector

2. **Display** (Laptop)
   - Display brightness slider
   - Keyboard backlight slider (if available)

3. **Bluetooth**
   - Adapter toggle
   - Paired devices list
   - Connection status per device
   - Device battery levels

4. **Power** (Laptop)
   - Battery percentage and health
   - Charging status
   - Time remaining
   - Power profile selector
   - Current power draw

5. **Thermal**
   - CPU temperature
   - Fan speed (if available)
   - Thermal zone readings

6. **Network**
   - WiFi status and SSID
   - Signal strength
   - Tailscale connection status

---

## Hardware Differences

### M1 MacBook Pro (Laptop)

Available controls:
- ✅ Volume (speaker, headphones)
- ✅ Display brightness (apple-panel-bl)
- ✅ Keyboard backlight (kbd_backlight)
- ✅ Bluetooth
- ✅ Battery status
- ✅ Power profiles (powerprofilesctl)
- ✅ Thermal monitoring
- ⚠️ Fan control (limited visibility)
- ✅ WiFi
- ✅ Tailscale

### ThinkPad (Laptop)

Available controls:
- ✅ Volume (speaker, headphones)
- ✅ Display brightness
- ✅ Keyboard backlight
- ✅ Bluetooth
- ✅ Battery status
- ✅ Power profiles (TLP)
- ✅ Thermal monitoring
- ✅ Fan control visibility
- ✅ WiFi
- ✅ Tailscale

### Ryzen (Desktop)

Available controls:
- ✅ Volume (speaker, headphones)
- ❌ Display brightness (external monitors)
- ❌ Keyboard backlight
- ✅ Bluetooth
- ❌ Battery status
- ❌ Power profiles
- ✅ Thermal monitoring
- ❌ Fan control (external controller)
- ❌ WiFi (ethernet only)
- ✅ Tailscale

---

## Troubleshooting

### Volume not responding

```bash
# Check PipeWire status
systemctl --user status pipewire

# Restart PipeWire
systemctl --user restart pipewire
```

### Brightness not working

```bash
# Check available devices
brightnessctl -l

# Verify permissions
ls -la /sys/class/backlight/*/brightness
```

### Bluetooth devices not showing

```bash
# Check Bluetooth service
systemctl status bluetooth

# Verify adapter power
bluetoothctl show | grep Powered
```

### Battery info missing

```bash
# Check UPower
upower -e
upower -i /org/freedesktop/UPower/devices/battery_BAT0
```

### Panel not updating

```bash
# Restart the Eww service
systemctl --user restart eww-top-bar

# Check logs
journalctl --user -u eww-top-bar -f
```

---

## CLI Commands

Scripts are installed to `~/.config/eww/eww-device-controls/scripts/`.

### Backend Direct Access

```bash
# Get full device state (JSON output)
~/.config/eww/eww-device-controls/scripts/device-backend.py

# Get specific state
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode volume
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode bluetooth
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode brightness
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode battery
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode thermal
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode network

# Stream updates (for deflisten)
~/.config/eww/eww-device-controls/scripts/device-backend.py --mode volume --listen
```

### Device Control

```bash
# Volume (uses wpctl for WirePlumber)
~/.config/eww/eww-device-controls/scripts/volume-control.sh get
~/.config/eww/eww-device-controls/scripts/volume-control.sh set 50
~/.config/eww/eww-device-controls/scripts/volume-control.sh up      # +5%
~/.config/eww/eww-device-controls/scripts/volume-control.sh down    # -5%
~/.config/eww/eww-device-controls/scripts/volume-control.sh mute    # toggle

# Brightness (uses brightnessctl)
~/.config/eww/eww-device-controls/scripts/brightness-control.sh get
~/.config/eww/eww-device-controls/scripts/brightness-control.sh set 75
~/.config/eww/eww-device-controls/scripts/brightness-control.sh up --device display
~/.config/eww/eww-device-controls/scripts/brightness-control.sh down --device keyboard

# Bluetooth (uses bluetoothctl)
~/.config/eww/eww-device-controls/scripts/bluetooth-control.sh get
~/.config/eww/eww-device-controls/scripts/bluetooth-control.sh power toggle
~/.config/eww/eww-device-controls/scripts/bluetooth-control.sh connect E1:4B:6C:22:56:F0
~/.config/eww/eww-device-controls/scripts/bluetooth-control.sh disconnect E1:4B:6C:22:56:F0
~/.config/eww/eww-device-controls/scripts/bluetooth-control.sh scan     # 10s scan

# Power profile (uses powerprofilesctl or TLP)
~/.config/eww/eww-device-controls/scripts/power-profile-control.sh get
~/.config/eww/eww-device-controls/scripts/power-profile-control.sh set balanced
~/.config/eww/eww-device-controls/scripts/power-profile-control.sh set performance
~/.config/eww/eww-device-controls/scripts/power-profile-control.sh set power-saver
~/.config/eww/eww-device-controls/scripts/power-profile-control.sh cycle   # next profile
```

---

## Configuration

The device controls are enabled via home-manager:

```nix
# In home-vpittamp.nix
programs.eww-device-controls = {
  enable = true;

  # Optional: override polling intervals
  volumeInterval = "1s";
  brightnessInterval = "2s";

  # Optional: disable specific controls
  showBluetooth = true;
  showNetwork = true;
};
```

---

## Related Features

- **Feature 060**: Eww Top Bar (where device indicators appear)
- **Feature 085**: Monitoring Panel (where Devices tab lives)
- **Feature 086**: Panel Focus Mode (keyboard navigation)
- **Deprecated**: eww-quick-panel (replaced by this feature)
