# Apple Silicon (M1/M2) NixOS Setup Guide

## Overview

This guide documents the setup, configuration, and troubleshooting of NixOS on Apple Silicon Macs (M1/M2), including all issues encountered and their resolutions.

## Prerequisites

- Apple Silicon Mac (M1, M1 Pro, M1 Max, M1 Ultra, M2, etc.)
- Asahi Linux installed as the base system
- Basic familiarity with NixOS

## Installation

### 1. Initial Setup with Asahi Linux

First, install Asahi Linux on your Mac following their official guide. This provides the necessary bootloader and firmware support for Apple Silicon.

### 2. Building NixOS Configuration

```bash
# Clone the configuration
git clone https://github.com/vpittamp/nixos-config /etc/nixos
cd /etc/nixos

# Build with --impure flag (REQUIRED for firmware access)
sudo nixos-rebuild switch --flake .#m1 --impure
```

> **Important**: The `--impure` flag is mandatory for M1 builds as it allows access to the Asahi Linux firmware located in `/boot/asahi`.

## Known Issues and Resolutions

### 1. WiFi/Wireless Connectivity Issues

**Problem**: WiFi doesn't work after initial NixOS installation.

**Root Cause**: Missing Apple Silicon wireless firmware.

**Resolution**:
```nix
# In hardware/m1.nix
hardware.firmware = [
  (pkgs.stdenvNoCC.mkDerivation {
    name = "asahi-firmware";
    src = /boot/asahi;
    installPhase = ''
      mkdir -p $out/lib/firmware
      cp -r $src/* $out/lib/firmware/
    '';
  })
];
```

The firmware is extracted from `/boot/asahi` which contains the necessary wireless drivers from the Asahi Linux installation.

### 2. Display Scaling on Retina Display

**Problem**: Interface elements appear too small or inconsistently sized on the high-DPI Retina display.

**Attempted Solutions**:
1. Initial: 192 DPI (2x scaling) - Too large for some applications
2. Intermediate: Various Qt scaling factors (0.85, 0.6, 0.35) - Inconsistent results

**Final Resolution**:
```nix
# In configurations/m1.nix
services.xserver = {
  dpi = 180;  # Optimal DPI for Retina displays
  displayManager.sessionCommands = ''
    export QT_AUTO_SCREEN_SCALE_FACTOR=0  # Disable Qt auto-scaling
    export QT_ENABLE_HIGHDPI_SCALING=0    # Disable Qt HiDPI
    export PLASMA_USE_QT_SCALING=1        # Let Plasma handle scaling
  '';
};
```

**Key Insights**:
- 180 DPI provides better balance than 192 DPI
- Disabling Qt's auto-scaling prevents double-scaling issues
- Letting KDE Plasma handle Qt scaling provides consistency

### 3. 1Password Display Scaling Issues

**Problem**: 1Password desktop application shows disproportionate UI elements (header normal, content too large).

**Attempted Solutions**:
1. Qt scaling wrapper with QT_SCALE_FACTOR - Caused crashes
2. Various scale factors (0.85, 0.6, 0.35) - Temporary fixes that reverted

**Final Resolution**:
Removed Qt wrapper entirely and relied on system-wide display scaling configuration. The issue was resolved by:
- Setting proper system DPI (180)
- Disabling Qt auto-scaling globally
- Using declarative configuration without wrapper scripts

### 4. Memory Shortage Issues

**Problem**: System runs out of memory, causing terminal crashes with "memory shortage avoided" errors.

**Resolution**:
```nix
# In configurations/m1.nix
# 8GB swap file for memory pressure relief
swapDevices = [{
  device = "/var/lib/swapfile";
  size = 8192; # 8GB
}];

# Memory management optimizations
boot.kernel.sysctl = {
  "vm.swappiness" = 10;              # Reduce swap usage
  "vm.vfs_cache_pressure" = 50;      # Balance cache pressure
  "vm.dirty_background_ratio" = 5;   # Write dirty pages earlier
  "vm.dirty_ratio" = 10;             # Force sync I/O earlier
};
```

### 5. KDE Plasma Session Type Conflicts

**Problem**: Wayland session conflicts with certain applications, causing black screen on logout.

**Resolution**:
```nix
# Force X11 session for compatibility
services.displayManager.defaultSession = "plasmax11";
services.xserver.displayManager.defaultSession = lib.mkForce "plasmax11";
```

### 6. Touch ID / Biometric Authentication

**Status**: Not supported on Linux/NixOS for Apple Silicon.

**Workaround**: Use 1Password with system authentication (PAM) instead:
- 1Password prompts for system password
- Integrates with polkit for elevated privileges
- SSH keys stored in 1Password vault

## Performance Optimizations

### 1. Asahi Linux Kernel

The configuration uses the Asahi Linux kernel which includes Apple Silicon optimizations:
```nix
boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
```

### 2. Filesystem Optimizations

Using appropriate mount options for SSDs:
```nix
fileSystems."/".options = [ "noatime" "nodiratime" ];
```

### 3. Power Management

Asahi Linux includes Apple Silicon power management:
- CPU frequency scaling
- Thermal management
- Battery optimization (for MacBooks)

## Hardware Support Status

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | ✅ Full | All cores working with frequency scaling |
| GPU | ⚠️ Partial | Basic acceleration, no 3D yet |
| WiFi | ✅ Full | Requires Asahi firmware |
| Bluetooth | ✅ Full | Works with firmware |
| Audio | ✅ Full | Speakers and headphone jack work |
| Touch ID | ❌ No | Not supported on Linux |
| Thunderbolt | ⚠️ Partial | USB works, video output limited |
| Internal Storage | ✅ Full | NVMe SSD fully supported |
| External Displays | ⚠️ Partial | HDMI works, DisplayPort varies |

### Keyboard Backlight Controls

- Fn+F5/F6 now trigger the `XF86KbdBrightness*` bindings in Sway, which call `brightnessctl -d kbd_backlight` to raise or lower the LEDs in 10 % steps.
- `services.udev.packages = [ pkgs.brightnessctl ]` ships the required udev rules so members of the `input` group (the default `vpittamp` user) can write `/sys/class/leds/kbd_backlight/brightness` without sudo.
- Brightness state survives reboots and suspend/resume cycles via `systemd-backlight@leds:kbd_backlight.service`.
- Display brightness is handled with the same tool (`brightnessctl set ±5%`), so the Fn+F1/F2 keys use a consistent backend whether you’re on the M1 laptop or a VNC session.
- Prefer GUI? Press `Mod+i` to open the dedicated **Eww quick panel**:
  - Two brightness cards display the live `%` values from `brightnessctl` and give ± buttons for the internal panel and keyboard backlight.
  - Action tiles (Network Manager, Bluetooth, Volume mixer, Tailscale status, Firefox, Ghostty, VS Code, Files, screenshot, lock, suspend) reuse the Arin/Dashboard icon packs pulled straight from [adi1090x/widgets](https://github.com/adi1090x/widgets/tree/main/eww/dashboard).
- `Mod+Shift+i` still opens the native SwayNC notification center and `Mod+Ctrl+Shift+i` toggles Do Not Disturb.

## Troubleshooting

### Build Failures

**Issue**: `error: access to path '/boot/asahi' is forbidden in restricted mode`

**Solution**: Always use `--impure` flag:
```bash
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Black Screen After Logout

**Issue**: Screen goes black after logging out of KDE session.

**Solution**: Force X11 session instead of Wayland (see Session Type Conflicts above).

### Application Scaling Issues

**Issue**: Applications have inconsistent scaling.

**Solution**: Check application-specific scaling settings:
- Firefox: Set `layout.css.devPixelsPerPx` to 1.75 in about:config
- Electron apps: May need `--force-device-scale-factor=1.75`
- Qt apps: Controlled by system-wide PLASMA_USE_QT_SCALING

### WiFi Not Working

**Issue**: WiFi interface not showing up.

**Solution**: Verify firmware is loaded:
```bash
# Check if firmware is present
ls /run/current-system/firmware/lib/firmware/

# Check kernel messages for firmware loading
dmesg | grep firmware

# Rebuild with --impure if firmware missing
sudo nixos-rebuild switch --flake .#m1 --impure
```

## Tips and Best Practices

1. **Always use --impure flag** for rebuilds to ensure firmware access
2. **Regular updates**: Keep both NixOS and Asahi components updated
3. **Monitor thermals**: Use `sensors` to check temperatures
4. **Battery life**: Reduce screen brightness and disable unused services
5. **External storage**: Use ext4 or btrfs for best compatibility

## Future Improvements

### Expected from Asahi Linux
- Full GPU acceleration (Metal → Vulkan translation)
- Better Thunderbolt/DisplayPort support
- ProMotion display support
- Touch ID support (long-term goal)

### Possible NixOS Improvements
- Native flake support for Asahi firmware
- Automated display scaling detection
- Better Rosetta 2 integration for x86 binaries

## References

- [Asahi Linux Documentation](https://asahilinux.org/docs/)
- [NixOS on Apple Silicon Wiki](https://nixos.wiki/wiki/Apple_Silicon)
- [nixos-apple-silicon GitHub](https://github.com/tpwrules/nixos-apple-silicon)
- [Asahi Linux Feature Support Matrix](https://github.com/AsahiLinux/docs/wiki/Feature-Support)

## Support

For issues specific to this configuration:
- Open an issue on [GitHub](https://github.com/vpittamp/nixos-config/issues)
- Check the [Asahi Linux forums](https://forums.asahilinux.org/)
- Join the NixOS Discord/Matrix for community help

---

**Last Updated**: September 2025  
**Tested On**: MacBook Pro M1 (2020)
