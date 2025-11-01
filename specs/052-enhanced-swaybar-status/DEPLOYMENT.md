# Deployment Guide: Enhanced Swaybar Status

**Feature**: Feature 052 - Enhanced Swaybar Status
**Branch**: `052-enhanced-swaybar-status`
**Date**: 2025-10-31

---

## Overview

The enhanced swaybar status integrates with the **existing home-manager Sway configuration** in `home-modules/desktop/swaybar.nix`. It does NOT require manual editing of Sway config files.

### Architecture

```
home-modules/desktop/
├── swaybar.nix              # Main swaybar configuration (UPDATED)
├── swaybar-enhanced.nix     # Enhanced status module (NEW)
└── swaybar/
    ├── status-generator.py  # Python status generator (NEW)
    └── blocks/*.py          # Status block implementations (NEW)
```

**Integration Pattern**:
- **Top bar**: Enhanced system status (volume, battery, network, bluetooth)
- **Bottom bar**: Project context with workspace buttons (unchanged)
- **Automatic selection**: Uses enhanced status when `programs.swaybar-enhanced.enable = true`

---

## Step 1: Enable the Enhanced Status Module

Add to your home-manager configuration (e.g., `home-modules/hetzner-sway.nix` or `configurations/hetzner-sway.nix`):

```nix
{
  imports = [
    ./desktop/swaybar-enhanced.nix  # Add this import
    ./desktop/swaybar.nix           # Should already be imported
  ];

  # Enable enhanced status bar
  programs.swaybar-enhanced.enable = true;
}
```

**That's it!** The `swaybar.nix` module automatically detects the `swaybar-enhanced.enable` option and switches the top bar to use the enhanced status generator.

---

## Step 2: Build and Switch

### Option A: Full System Rebuild (Recommended)

```bash
# For hetzner-sway configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# For M1 MacBook Pro
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Option B: Home-Manager Only

```bash
home-manager switch --flake .#<user>@<host>

# Example:
home-manager switch --flake .#vpittamp@hetzner-sway
```

---

## Step 3: Reload Sway

After rebuilding, reload Sway to apply the new status bar:

```bash
swaymsg reload
```

Or use the keyboard shortcut: `Mod+Shift+C`

---

## Verification

After reloading, you should see the enhanced status bar with:

### Top Bar (Enhanced Status - Preserves ALL Original Features + New Enhancements)

**Preserved from Original**:
- **  Generation**: NixOS generation info with sync status (e.g., `  27b62bf ⚠`)
- **  LOAD**: System load average (e.g., `  LOAD 1.23`)
- **  Memory**: RAM usage (e.g., `  4.2/16.0GB (26%)`)
- **  Disk**: Disk usage (e.g., `  45G/100G (45%)`)
- **  Network Traffic**: RX/TX bytes (e.g., `  ↓125.3MB ↑45.2MB`)
- **  Temperature**: CPU temp if available (e.g., `  45°C`)
- **  Date/Time**: Current date and time (e.g., `  Thu Oct 31  14:23:45`)

**New Enhanced Features** (added by swaybar-enhanced):
- **󰕾 Volume**: Live volume with mute detection (e.g., `󰕾 75%`)
- **󰁹 Battery**: Battery percentage with charging status (e.g., `󰁹 85%`)
- **󰖩 Network WiFi**: WiFi SSID and signal strength (e.g., `󰖩 MyNetwork`)
- **󰂯 Bluetooth**: Connected device count (e.g., `󰂯 2`)

### Bottom Bar (Project Context - Unchanged)
- **Project indicator**: Current i3pm project
- **Workspace buttons**: Clickable workspace indicators
- **Binding mode**: Shows workspace mode (`→ WS`, `⇒ WS`)

---

## Configuration Options

### Custom Colors (Catppuccin Mocha by default)

```nix
programs.swaybar-enhanced = {
  enable = true;
  theme = {
    colors = {
      battery.low = "#f38ba8";      # Red for low battery
      battery.medium = "#f9e2af";   # Yellow for medium
      battery.high = "#a6e3a1";     # Green for high/charging
      volume.normal = "#a6e3a1";    # Green
      volume.muted = "#6c7086";     # Gray
      network.connected = "#a6e3a1"; # Green
      network.weak = "#f9e2af";      # Yellow for weak signal
      bluetooth.connected = "#89b4fa"; # Blue
    };
  };
};
```

### Custom Update Intervals

```nix
programs.swaybar-enhanced = {
  enable = true;
  intervals = {
    battery = 60;    # 60 seconds (slower, saves CPU)
    volume = 2;      # 2 seconds
    network = 10;    # 10 seconds
    bluetooth = 30;  # 30 seconds
  };
};
```

### Custom Click Handlers

```nix
programs.swaybar-enhanced = {
  enable = true;
  clickHandlers = {
    volume = "${pkgs.alacritty}/bin/alacritty -e alsamixer";
    network = "${pkgs.networkmanager}/bin/nmtui";
    bluetooth = "${pkgs.bluez5}/bin/bluetoothctl";
    battery = ""; # Disable battery click handler
  };
};
```

### Disable Hardware Detection

Useful for desktops without battery or Bluetooth:

```nix
programs.swaybar-enhanced = {
  enable = true;
  detectBattery = false;    # Hide battery indicator
  detectBluetooth = false;  # Hide Bluetooth indicator
};
```

---

## How It Works

### Automatic Integration

The `swaybar.nix` module includes this logic:

```nix
# Select status script based on swaybar-enhanced enablement
topBarStatusScript = if (config.programs.swaybar-enhanced.enable or false)
  then enhancedStatusScript   # Python-based D-Bus status generator
  else systemMonitorScript;   # Legacy shell script
```

When `programs.swaybar-enhanced.enable = true`, all top bars (on all monitors) automatically use the enhanced status generator.

### Dual-Bar Layout

The existing dual-bar layout is preserved:

1. **Top Bar**: System status (switches to enhanced when enabled)
   - Headless mode: 3 monitors (HEADLESS-1, HEADLESS-2, HEADLESS-3)
   - M1 mode: 2 outputs (eDP-1, HDMI-A-1)

2. **Bottom Bar**: Project context (unchanged)
   - i3pm project indicator
   - Workspace buttons
   - Binding mode indicator

---

## Troubleshooting

### Status Bar Not Showing

**Check if module is loaded**:
```bash
home-manager packages | grep swaybar-enhanced
```

**Check if scripts are installed**:
```bash
ls -la ~/.config/sway/swaybar/
```

Should show:
- `status-generator.py` (executable)
- `blocks/__init__.py`
- `blocks/models.py`
- `blocks/config.py`
- `blocks/click_handler.py`
- `blocks/volume.py`
- `blocks/battery.py`
- `blocks/network.py`
- `blocks/bluetooth.py`

### Icons Not Displaying

**Check Nerd Fonts are installed**:
```bash
fc-list | grep -i "nerd"
```

Should show FiraCode Nerd Font or Hack Nerd Font.

**If missing**:
```bash
# Rebuild to install Nerd Fonts
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### Status Bar Shows Errors

**Check status generator logs**:
```bash
tail -f /tmp/swaybar-status-generator.log
```

Look for errors related to:
- D-Bus connection failures
- Python import errors
- pactl/UPower/NetworkManager unavailable

### Click Handlers Not Working

**Verify click handler packages are installed**:
```bash
which pavucontrol     # Volume mixer
which nm-connection-editor  # Network manager
which blueman-manager # Bluetooth manager
```

**If missing, they should be auto-installed**. Check:
```bash
home-manager packages | grep -E "pavucontrol|networkmanagerapplet|blueman"
```

### Reverting to Legacy Status Bar

To temporarily disable enhanced status:

```nix
programs.swaybar-enhanced.enable = false;
```

Then rebuild and reload:
```bash
sudo nixos-rebuild switch --flake .#hetzner-sway
swaymsg reload
```

The top bar will revert to the legacy shell script system monitor.

---

## Testing on Different Platforms

### Hetzner Cloud (hetzner-sway)

```bash
# SSH into hetzner-sway
ssh vpittamp@hetzner

# Enable enhanced status
# Edit configuration to add: programs.swaybar-enhanced.enable = true

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway

# Reload Sway (via VNC)
swaymsg reload

# Verify via VNC on ports 5900, 5901, 5902
# Top bar should show: 󰕾 Volume, 󰖩 Network, 󰂯 Bluetooth (no battery)
```

### M1 MacBook Pro

```bash
# Enable enhanced status
# Edit configuration to add: programs.swaybar-enhanced.enable = true

# Rebuild
sudo nixos-rebuild switch --flake .#m1 --impure

# Reload Sway
swaymsg reload

# Verify on eDP-1 and HDMI-A-1
# Top bar should show: 󰕾 Volume, 󰁹 Battery, 󰖩 Network, 󰂯 Bluetooth
```

---

## Performance Monitoring

### Check Resource Usage

```bash
# Monitor status generator process
ps aux | grep status-generator
top -p $(pgrep -f status-generator)

# Expected:
# CPU: <2%
# Memory: <50MB
```

### Check Update Latency

Watch the status bar for delays:
- Volume changes should reflect within 1-2 seconds
- Network changes should reflect within 5-10 seconds
- Battery changes should reflect within 30-60 seconds

If updates are slow, check logs:
```bash
tail -f /tmp/swaybar-status-generator.log
```

---

## Next Steps

1. **Deploy to hetzner-sway**: Test on headless VNC setup
2. **Deploy to M1**: Test on physical hardware
3. **Optional optimizations**:
   - Implement D-Bus signal subscriptions (replace polling)
   - Add additional status blocks (CPU, memory, temperature)
   - Create alternative color themes

---

## Files Modified

- ✅ `home-modules/desktop/swaybar.nix` - Updated to support enhanced status
- ✅ `home-modules/desktop/swaybar-enhanced.nix` - New module
- ✅ `home-modules/desktop/swaybar/status-generator.py` - New status generator
- ✅ `home-modules/desktop/swaybar/blocks/*.py` - New status block implementations

---

## Summary

**Deployment is simple**:
1. Add import for `swaybar-enhanced.nix`
2. Set `programs.swaybar-enhanced.enable = true`
3. Rebuild with `sudo nixos-rebuild switch`
4. Reload Sway with `swaymsg reload`

**No manual config editing required** - everything is managed via home-manager! 🎉
