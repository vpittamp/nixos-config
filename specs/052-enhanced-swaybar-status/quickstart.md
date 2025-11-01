# Quickstart: Enhanced Swaybar Status

**Feature**: Enhanced Swaybar Status
**Branch**: `052-enhanced-swaybar-status`
**Platform**: NixOS with Sway/Wayland (hetzner-sway reference)

## Overview

Enhanced swaybar adds rich system status indicators with icons, tooltips, and click interactions while preserving all native Sway functionality. Status blocks display volume, battery, WiFi, and Bluetooth state with visual feedback and quick controls.

## Quick Start

### Enable Enhanced Status Bar

1. **Add to your NixOS configuration** (for home-manager integration):

If using a standalone home-manager configuration:
```nix
# home.nix
{
  imports = [
    ./home-modules/desktop/swaybar-enhanced.nix
  ];

  programs.swaybar-enhanced.enable = true;
}
```

If using flake-based configuration, add the module to your home-manager imports.

2. **Update your Sway configuration** to use the enhanced status generator:

Add to `~/.config/sway/config`:
```
bar {
    position top
    status_command python ~/.config/sway/swaybar/status-generator.py
    font pango:FiraCode Nerd Font 10

    colors {
        statusline #cdd6f4
        background #1e1e2e
        focused_workspace #89b4fa #89b4fa #1e1e2e
    }
}
```

3. **Rebuild and switch**:

```bash
sudo nixos-rebuild switch --flake .#hetzner-sway
# or
home-manager switch --flake .#<user>@<host>
```

4. **Reload Sway**:

```bash
swaymsg reload
```

### Verify Status Bar

After rebuild, the enhanced status bar should appear in swaybar with:
- 󰕾 Volume indicator (percentage)
- 󰁹 Battery indicator (if present)
- 󰖩 WiFi indicator (connection status)
- 󰂯 Bluetooth indicator (device count)

## Status Indicators

### Volume 󰕾

**Display**: Icon + percentage (e.g., `󰕾 75%`)

**States**:
- 󰕾 High volume (≥70%)
- 󰖀 Medium volume (30-69%)
- 󰕿 Low volume (<30%)
- 󰝟 Muted

**Actions**:
- **Left click**: Open `pavucontrol` (volume mixer)
- **Scroll up**: Increase volume 5%
- **Scroll down**: Decrease volume 5%

**Tooltip**: "Volume: 75%" (on hover)

---

### Battery 󰁹

**Display**: Icon + percentage (e.g., `󰁹 85%`)

**States**:
- 󰂄 Charging
- 󰁹 High charge (≥90%)
- 󰂂 Good charge (70-89%)
- 󰂀 Medium charge (50-69%)
- 󰁾 Low charge (30-49%)
- 󰁼 Very low (10-29%)
- 󰂃 Critical (<10%) - **urgent** (highlighted)

**Actions**:
- **Left click**: Show detailed power statistics

**Tooltip**:
- Discharging: "85% - 3h 24m remaining"
- Charging: "85% - 1h 15m until full"

**Note**: Battery indicator hidden on desktop systems without battery.

---

### WiFi 󰖩

**Display**: Icon + SSID or state (e.g., `󰖩 MyNetwork`)

**States**:
- 󰤨 Excellent signal (≥80%)
- 󰤥 Good signal (60-79%)
- 󰤢 Fair signal (40-59%)
- 󰤟 Weak signal (<40%)
- 󰤭 Disconnected
- 󰖪 WiFi disabled

**Actions**:
- **Left click**: Open network manager (`nm-connection-editor`)

**Tooltip**:
- Connected: "Connected to MyNetwork (87%)"
- Disconnected: "Disconnected"
- Disabled: "WiFi disabled"

---

### Bluetooth 󰂯

**Display**: Icon + connected device count (e.g., `󰂯 2`)

**States**:
- 󰂱 Connected (one or more devices)
- 󰂯 Enabled (no devices)
- 󰂲 Disabled

**Actions**:
- **Left click**: Open Bluetooth manager (`blueman-manager`)

**Tooltip**:
- Connected: "Connected: Headphones, Keyboard"
- Enabled: "Bluetooth enabled (no devices)"
- Disabled: "Bluetooth disabled"

**Note**: Bluetooth indicator hidden if Bluetooth adapter not present.

---

## Configuration

### Custom Colors

Override default color theme:

```nix
programs.swaybar-enhanced = {
  enable = true;
  theme = {
    colors = {
      battery = {
        charging = "#a6e3a1";  # Green
        high = "#a6e3a1";
        medium = "#f9e2af";    # Yellow
        low = "#f38ba8";       # Red
      };
      volume.normal = "#89b4fa";  # Blue
      network.connected = "#a6e3a1";
      bluetooth.connected = "#89dceb";
    };
  };
};
```

### Custom Update Intervals

Change status refresh rates (seconds):

```nix
programs.swaybar-enhanced = {
  enable = true;
  intervals = {
    battery = 30;    # 30 seconds
    volume = 1;      # 1 second
    network = 5;     # 5 seconds
    bluetooth = 10;  # 10 seconds
  };
};
```

### Custom Click Handlers

Override default click actions:

```nix
programs.swaybar-enhanced = {
  enable = true;
  clickHandlers = {
    volume = "${pkgs.alacritty}/bin/alacritty -e alsamixer";
    network = "${pkgs.networkmanager}/bin/nmtui";
    bluetooth = "${pkgs.bluez5}/bin/bluetoothctl";
  };
};
```

### Disable Specific Indicators

Hide unwanted status blocks:

```nix
programs.swaybar-enhanced = {
  enable = true;
  detectBattery = false;     # Hide battery (desktop)
  detectBluetooth = false;   # Hide Bluetooth (if not used)
};
```

## Troubleshooting

### Status Bar Not Updating

**Check status generator is running**:
```bash
ps aux | grep status-generator
```

**Restart sway**:
```bash
swaymsg reload
```

**Check logs**:
```bash
journalctl --user -u sway -f
```

---

### Icons Not Displaying

**Verify Nerd Font installed**:
```bash
fc-list | grep -i nerd
```

**If missing, add to configuration**:
```nix
fonts.packages = with pkgs; [
  (nerdfonts.override { fonts = [ "FiraCode" "Hack" ]; })
];
```

---

### Volume Clicks Not Working

**Check pavucontrol installed**:
```bash
which pavucontrol
```

**If missing, add to packages**:
```nix
home.packages = with pkgs; [ pavucontrol ];
```

---

### Battery Indicator Missing

**Check if battery present**:
```bash
upower -d | grep -A 10 "battery"
```

**If desktop without battery**: This is expected - battery indicator auto-hides.

**If laptop with battery**: Check UPower service:
```bash
systemctl status upower
```

---

### Network Indicator Shows Wrong State

**Check NetworkManager status**:
```bash
nmcli general status
nmcli device wifi list
```

**Restart NetworkManager**:
```bash
sudo systemctl restart NetworkManager
```

---

### Bluetooth Indicator Not Showing Devices

**Check BlueZ service**:
```bash
systemctl status bluetooth
bluetoothctl devices
```

**Restart Bluetooth**:
```bash
sudo systemctl restart bluetooth
```

---

## Advanced Usage

### Manual Status Generator Testing

Run status generator standalone to debug output:

```bash
python ~/.config/sway/swaybar/status-generator.py
```

Output should be JSON arrays:
```json
{"version":1}
[
  {"full_text":"<span font='NerdFont'>󰕾</span> 75%","color":"#a6e3a1","markup":"pango","name":"volume"},
  ...
]
```

### Test Click Events

Send click event to status generator:

```bash
echo '{"name":"volume","button":1,"x":0,"y":0}' | python status-generator.py
```

Should launch `pavucontrol`.

### Monitor D-Bus Signals

Watch for system state changes:

```bash
# Battery changes
dbus-monitor --system "type='signal',sender='org.freedesktop.UPower'"

# Network changes
dbus-monitor --system "type='signal',sender='org.freedesktop.NetworkManager'"

# Bluetooth changes
dbus-monitor --system "type='signal',sender='org.bluez'"
```

### Custom Status Blocks

Add custom status blocks by extending the status generator:

```python
# Add to status-generator.py
def get_custom_block():
    return StatusBlock(
        name="custom",
        full_text="<span font='NerdFont'></span> Custom",
        color="#a6e3a1",
        markup="pango"
    )

# Add to status array
status_blocks.append(get_custom_block())
```

## Integration with Existing Sway Config

The enhanced status bar preserves all native Sway features:

- ✅ Workspace indicators
- ✅ Binding mode display
- ✅ System tray (`tray_output primary`)
- ✅ Custom bar colors
- ✅ Multiple monitor support

**Sway config** (`~/.config/sway/config`):
```
bar {
    position top
    status_command python ~/.config/sway/swaybar/status-generator.py
    font pango:FiraCode Nerd Font 10

    colors {
        statusline #cdd6f4
        background #1e1e2e
        focused_workspace #89b4fa #89b4fa #1e1e2e
    }
}
```

## Performance

**Resource Usage** (typical):
- CPU: <1% average, <2% peak
- Memory: ~25MB
- Update Latency: <50ms (D-Bus queries)
- Click Response: <100ms

**Benchmarking**:
```bash
# Monitor CPU usage
top -p $(pgrep -f status-generator)

# Monitor memory usage
ps aux | grep status-generator | awk '{print $6}'  # Memory in KB
```

## Related Documentation

- **Spec**: [spec.md](spec.md) - Feature requirements and user scenarios
- **Data Model**: [data-model.md](data-model.md) - Status block data structures
- **i3bar Protocol**: [contracts/i3bar-protocol.md](contracts/i3bar-protocol.md) - Protocol specification
- **D-Bus Interfaces**: [contracts/dbus-interfaces.md](contracts/dbus-interfaces.md) - System state queries
- **Research**: [research.md](research.md) - Technology decisions and alternatives

## Quick Reference

| Indicator | Click Action | Scroll Action | Update Interval |
|-----------|--------------|---------------|-----------------|
| Volume 󰕾 | Open mixer | ±5% volume | 1s |
| Battery 󰁹 | Show stats | - | 30s |
| WiFi 󰖩 | Open network manager | - | 5s |
| Bluetooth 󰂯 | Open BT manager | - | 10s |

**Default Colors** (Catppuccin Mocha):
- Green: `#a6e3a1` (good/high/connected)
- Yellow: `#f9e2af` (medium/warning)
- Red: `#f38ba8` (low/critical)
- Gray: `#6c7086` (disabled/muted)
- Blue: `#89b4fa` (active/special)
