# NixOS Configuration Troubleshooting Guide

This document provides detailed troubleshooting procedures for common issues across the NixOS configuration.

## i3pm Project Management Troubleshooting

### Daemon Not Running

```bash
# Check daemon status
systemctl --user status i3-project-event-listener
i3pm daemon status

# View daemon logs
journalctl --user -u i3-project-event-listener -f

# Check recent errors
journalctl --user -u i3-project-event-listener -n 50

# Restart daemon
systemctl --user restart i3-project-event-listener

# Rebuild if module wasn't enabled
sudo nixos-rebuild switch --flake .#<target>
```

### Windows Not Auto-Marking

```bash
# Check recent window events
i3pm daemon events --limit=20 --type=window

# Verify window class is in scoped_classes
cat ~/.config/i3/app-classes.json

# Manually trigger mark update
i3pm daemon events --type=tick

# Reload daemon config
systemctl --user restart i3-project-event-listener
```

### Applications Not Opening in Project Context

```bash
# Check active project
i3pm project current  # or pcurrent

# Verify project directory exists
cat ~/.config/i3/projects/<project-name>.json

# Check daemon is running
i3pm daemon status

# Verify environment variables are set
window-env <window-class> --filter I3PM_

# Try clearing and reactivating project
pclear  # or Win+Shift+P
pswitch <project-name>  # or Win+P
```

### Windows from Old Project Still Visible

```bash
# Check i3bar shows correct project
# (Look at status bar)

# Verify project switch completed
i3pm project current

# Check daemon processed the switch
i3pm daemon events | grep tick

# Manually trigger filtering
i3pm daemon events --type=tick

# Try switching again
pswitch <project-name>
```

### Tiled Windows Becoming Floating After Project Switch

**This should be fixed in v1.4.0+**. If still occurring:

```bash
# Check daemon version
systemctl --user status i3-project-event-listener | grep version
# Should be v1.4.0 or higher

# Verify state capture logging
journalctl --user -u i3-project-event-listener | grep "Capturing state"
# Look for "preserved_state=True" on subsequent hides

# Check window state file schema
cat ~/.config/i3/window-workspace-map.json | jq '.version'
# Should be "1.1" for full state preservation

# If version is old, rebuild and restart
sudo nixos-rebuild switch --flake .#<target>
systemctl --user restart i3-project-event-listener
```

### Floating Windows Losing Position/Size

```bash
# Verify geometry is being captured
journalctl --user -u i3-project-event-listener | grep "Captured geometry"

# Check state file has geometry data
cat ~/.config/i3/window-workspace-map.json | jq '.windows[].geometry'

# Verify restoration sequence
journalctl --user -u i3-project-event-listener | grep "Restoring geometry"

# If geometry is null for floating windows
# Report bug with window ID and class
```

### Windows Not Returning to Original Workspace

```bash
# Check state file workspace numbers
cat ~/.config/i3/window-workspace-map.json | jq '.windows[].workspace_number'

# Verify restoration uses exact workspace
journalctl --user -u i3-project-event-listener | grep "move workspace number"

# Check for workspace fallback
journalctl --user -u i3-project-event-listener | grep "No saved state"

# Inspect window tracking with full state
cat ~/.config/i3/window-workspace-map.json | jq .
```

### Editing Project Configuration

```bash
# Manually edit project file
vi ~/.config/i3/projects/<project-name>.json

# Reload daemon after edits
systemctl --user restart i3-project-event-listener

# Or use CLI tools
i3pm project create <name> --directory <dir> --icon "🚀"
```

## M1 MacBook Pro Troubleshooting

### Daemon Not Starting

```bash
# Check service status
systemctl --user status i3-project-event-listener

# Check daemon logs for errors
journalctl --user -u i3-project-event-listener -n 50

# Restart daemon
systemctl --user restart i3-project-event-listener

# Verify daemon module is enabled in configuration
grep -r "i3ProjectDaemon" /etc/nixos/configurations/m1.nix

# Rebuild if module wasn't enabled
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Workspace Mode Handler Errors

```bash
# Check detected outputs
swaymsg -t get_outputs | jq -r '.[].name'
# Should show: eDP-1

# Test workspace mode
workspace-mode single
# Should succeed with all workspaces on eDP-1

# Check handler script exists
cat ~/.config/sway/workspace-mode

# Check daemon workspace mode manager
i3pm workspace-mode state
```

### WiFi Stability Issues (BCM4378)

```bash
# Check if WiFi recovery service ran
systemctl status wifi-recovery

# Check service logs
journalctl -u wifi-recovery -n 50

# Manually reload WiFi module
sudo modprobe -r brcmfmac && sleep 2 && sudo modprobe brcmfmac

# Check kernel parameters
cat /proc/cmdline | grep brcmfmac
# Should show: brcmfmac.feature_disable=0x82000

# Check WiFi interface status
ip link show wlan0

# Restart NetworkManager
sudo systemctl restart NetworkManager
```

### Display Scaling Issues

```bash
# Check current scale
swaymsg -t get_outputs | jq '.[] | {name, scale}'
# Should show 2.0 for eDP-1

# Check resolution
swaymsg -t get_outputs | jq '.[] | {name, current_mode}'

# Manually set scale (temporary)
swaymsg output eDP-1 scale 2

# Check Sway config
grep -E "output eDP-1" ~/.config/sway/config
```

## VNC Access Troubleshooting (Hetzner)

### Connection Refused

```bash
# Verify services are running
systemctl --user list-units 'wayvnc@*'

# Check specific service
systemctl --user status wayvnc@HEADLESS-1

# Restart failed service
systemctl --user restart wayvnc@HEADLESS-1

# Restart all VNC services
systemctl --user restart wayvnc@HEADLESS-{1,2,3}

# Check firewall rules
sudo iptables -L -n | grep -E '590[0-2]'

# Check VNC is listening
sudo netstat -tlnp | grep -E '590[0-2]'

# Check Tailscale connectivity
tailscale status
ping <tailscale-ip>
```

### Blank Screen

```bash
# Verify outputs are active
swaymsg -t get_outputs | jq '.[] | {name, active}'

# Check if workspace exists on output
swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'

# Switch to workspace to activate display
swaymsg workspace number 1  # For Display 1
swaymsg workspace number 3  # For Display 2
swaymsg workspace number 6  # For Display 3

# Restart Sway (careful - will disconnect VNC)
swaymsg reload
```

### Workspace on Wrong Display

```bash
# Check monitor status
i3pm monitors status

# Verify workspace assignments
swaymsg -t get_workspaces | jq '.[] | {num, output}'

# Check Sway config workspace assignments
grep "workspace.*output" ~/.config/sway/config

# Manually reassign workspaces
i3pm monitors reassign

# Move workspace to correct output (manual)
swaymsg workspace 3
swaymsg move workspace to output HEADLESS-2
```

### Performance Issues

```bash
# Monitor VNC service resource usage
systemctl --user status wayvnc@HEADLESS-1 | grep -E "(CPU|Memory)"

# Monitor network traffic
sudo iftop -i tailscale0

# Check Tailscale connection type (direct vs relay)
tailscale status
# Direct is better than relay

# Check VNC encoding settings
# See ~/.config/wayvnc/config for encoding options

# Monitor Sway performance
swaymsg -t get_version
```

## Workspace Navigation Troubleshooting

### Workspace Mode Not Activating

```bash
# Check daemon integration
i3pm daemon status
# Look for workspace_mode_manager in components

# View workspace mode events
i3pm daemon events --type=mode --follow

# Check navigation history
i3pm workspace-mode history --limit=20

# Verify mode state
i3pm workspace-mode state --json

# Check keybinding configuration
grep -E "CapsLock|Ctrl.*0" ~/.config/sway/config
```

### Workspace Switch Goes to Wrong Monitor

```bash
# Check monitor detection
i3pm monitors status

# Verify workspace-to-monitor distribution
swaymsg -t get_workspaces | jq '.[] | {num, output}'

# Check workspace mode configuration
cat ~/.config/sway/workspace-mode

# Test manual workspace switch
swaymsg workspace number 23
```

## PWA Troubleshooting

### PWA Not Installing

```bash
# Check firefoxpwa is installed
which firefoxpwa

# Check PWA configuration
cat ~/.local/share/firefoxpwa/config.json | jq .

# Try manual installation
firefoxpwa install <url>

# Check installation logs
pwa-install-all 2>&1 | tee pwa-install.log

# Verify manifest is accessible
curl -I <manifest-url>
```

### PWA Opens on Wrong Workspace

```bash
# Check workspace assignment in registry
grep -A5 "<pwa-name>" /etc/nixos/home-modules/tools/app-registry-data.nix

# Check window class
window-env <pwa-class>

# Check daemon workspace assignment
i3pm diagnose window <window-id>

# Verify launch notification
i3pm daemon events --type=launch --limit=10
```

## General NixOS Troubleshooting

### Build Failures

```bash
# Run with detailed trace
nixos-rebuild dry-build --flake .#<target> --show-trace

# Check for syntax errors
nix flake check

# Verify flake inputs
nix flake metadata

# Update flake lock
nix flake update

# Clean build cache
nix-collect-garbage -d
```

### Package Conflicts

```bash
# Check for deprecated packages
# Common: mysql → mariadb, openssl → openssl_3

# Search for package in nixpkgs
nix search nixpkgs <package-name>

# Check package info
nix eval nixpkgs#<package-name>.meta.description

# Try unstable channel
nix shell nixpkgs-unstable#<package-name>
```

### Option Deprecations

```bash
# Common deprecations:
# - hardware.opengl → hardware.graphics
# - services.xserver.enable → (split into multiple options)

# Search for option documentation
nix repl
> :l <nixpkgs>
> :doc config.hardware.graphics

# Check NixOS options search
# https://search.nixos.org/options
```

### File System Errors

```bash
# Ensure hardware-configuration.nix exists
ls -la /etc/nixos/hardware-configuration.nix

# Regenerate if missing
sudo nixos-generate-config --root /

# Check filesystem mounts
df -h
mount | grep /nix
```

## Diagnostic Tools

### Window State Inspection

```bash
# Get window information
i3pm windows --tree
i3pm windows --table
i3pm windows --json | jq .

# Inspect specific window
i3-msg -t get_tree | jq '.. | select(.window?) | {id, class: .window_properties.class, title: .name}'

# Check window environment
window-env <pid|class|title>
window-env --filter I3PM_ <window>

# Check window marks
i3-msg -t get_marks
```

### Daemon Diagnostics

```bash
# Health check
i3pm diagnose health
i3pm diagnose health --json

# Window identity
i3pm diagnose window <window-id>

# Event trace
i3pm diagnose events --limit=50
i3pm diagnose events --type=window --follow

# State validation
i3pm diagnose validate
```

### Live Monitoring

```bash
# Monitor window state
i3pm windows --live

# Monitor events
i3pm daemon events --follow

# Monitor system
i3-project-monitor
i3-project-monitor --mode=events
```

## Getting Help

1. **Check quickstart guides**: `/etc/nixos/specs/<feature-number>/quickstart.md`
2. **Review documentation**: `/etc/nixos/docs/*.md`
3. **Check daemon logs**: `journalctl --user -u i3-project-event-listener -f`
4. **Run diagnostics**: `i3pm diagnose health`, `i3pm diagnose validate`
5. **Enable debug logging**: Edit service file to set `LOG_LEVEL=DEBUG`

## Common Error Messages

### "Failed to connect to daemon"
- Daemon not running: `systemctl --user start i3-project-event-listener`
- Socket file missing: Check `~/.local/state/i3pm/daemon.sock`

### "Window not found"
- Window closed: Verify window still exists with `i3pm windows`
- Wrong window ID: Get current IDs with `i3-msg -t get_tree`

### "Project not found"
- Project doesn't exist: List with `i3pm project list`
- Project file corrupted: Check `~/.config/i3/projects/<name>.json`

### "Workspace assignment failed"
- Workspace doesn't exist: Create with `swaymsg workspace number <n>`
- Monitor not connected: Check with `i3pm monitors status`

### "State drift detected"
- Daemon restart: State is rebuilt from window tree
- Manual window moves: Run `i3pm diagnose validate` to check

## wshowkeys Visual Feedback Troubleshooting (Feature 042)

### Overview

`wshowkeys` provides visual on-screen feedback showing keypresses during workspace mode navigation. This section documents setup verification and troubleshooting.

### Error: "wshowkeys needs to be setuid to read input events"

**Cause**: Security wrapper not configured or setuid bit not set

**Solution**:
```bash
# Check if wrapper exists
ls -la /run/wrappers/bin/wshowkeys
# Expected: -r-s--x--x 1 root input 148744 Nov  4 15:21 /run/wrappers/bin/wshowkeys
#           ^ setuid bit set (s in owner execute position)

# If missing or wrong permissions, rebuild system
sudo nixos-rebuild switch --flake .#m1 --impure

# Verify wrapper was created
ls -la /run/wrappers/bin/wshowkeys
# Must show 's' in owner execute position
```

### Error: "Permission denied" when running wshowkeys

**Cause**: User not in `input` group

**Solution**:
```bash
# Check current groups
id vpittamp | grep input

# If input group missing, check configuration
grep extraGroups /etc/nixos/configurations/m1.nix
# Should include "input" in the list

# Rebuild and re-login
sudo nixos-rebuild switch --flake .#m1 --impure
# Log out and back in for group changes to take effect

# Verify after re-login
id vpittamp
# Should show: groups=...,174(input),...
```

### wshowkeys doesn't show on specific output

**Cause**: Output name mismatch

**Solution**:
```bash
# List available outputs
swaymsg -t get_outputs | jq -r '.[].name'

# Test with specific output
wshowkeys -a bottom -t 1 -o eDP-1

# For multi-output setups, wshowkeys shows on all outputs by default
```

### Visual overlay appears but doesn't disappear

**Cause**: `pkill -x wshowkeys` not executing on mode exit

**Solution**:
```bash
# Check Sway keybindings for wshowkeys cleanup
grep -A5 "mode.*WS" ~/.config/sway/config | grep pkill

# Manually kill if stuck
pkill -x wshowkeys

# Verify mode exit keybindings include cleanup
grep "Escape.*pkill.*wshowkeys" ~/.config/sway/config
grep "Return.*pkill.*wshowkeys" ~/.config/sway/config
```

### wshowkeys not starting on workspace mode entry

**Cause**: Keybinding not configured or CapsLock/Ctrl+0 not triggering

**Solution**:
```bash
# Check keybindings for workspace mode entry
grep -B2 "mode.*WS" ~/.config/sway/config | grep -E "CapsLock|Ctrl.*0"

# Test wshowkeys manually
wshowkeys -a bottom -t 1
# Should show overlay when you press keys

# Check Sway mode configuration
swaymsg -t get_binding_modes
# Should include "→ WS" and "⇒ WS"

# Test mode entry manually
swaymsg mode "→ WS"
# Should enter workspace mode (check i3bar/swaybar)
```

### Verification Checklist

Run these commands to verify wshowkeys is properly configured:

```bash
# 1. Check security wrapper
ls -la /run/wrappers/bin/wshowkeys
# Expected: -r-s--x--x 1 root input ... (setuid bit set)

# 2. Check user group membership
id vpittamp | grep input
# Expected: groups=...,input,...

# 3. Test wshowkeys runs without error
timeout 2 wshowkeys -a bottom -t 1
# Expected: No "needs to be setuid" error

# 4. Check keybinding integration
grep "wshowkeys" ~/.config/sway/config
# Should show bindings for mode entry and exit

# 5. Test in workspace mode
# - Press CapsLock (M1) or Ctrl+0 (Hetzner)
# - Type some digits (e.g., "23")
# - Verify overlay appears showing keypresses
# - Press Escape - verify overlay disappears
```

### Configuration Reference

**Security Wrapper** (`/etc/nixos/configurations/m1.nix`):
```nix
security.wrappers.wshowkeys = {
  owner = "root";
  group = "input";
  setuid = true;
  source = "${pkgs.wshowkeys}/bin/wshowkeys";
};
```

**User Groups** (`/etc/nixos/configurations/m1.nix`):
```nix
users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" ];
```

**Workspace Mode Integration** (`/etc/nixos/home-modules/desktop/sway.nix`):
```nix
# Launch on mode entry
bindsym Control+0 exec "wshowkeys -a bottom -t 1"; mode "→ WS"

# Kill on mode exit
bindsym Return exec "i3pm-workspace-mode execute; pkill -x wshowkeys"
bindsym Escape exec "i3pm-workspace-mode cancel; pkill -x wshowkeys"
```

### wshowkeys Command Options

```
-a [top|left|right|bottom]  # Anchor position (default: bottom)
-t [seconds]                # Timeout in seconds (default: 1)
-m [pixels]                 # Margin from edge
-o [output]                 # Specific output name
-s #RRGGBB[AA]             # Text color
-b                         # Background box
-f                         # Fill background
-F [font]                  # Font name
```

**Current Configuration**:
- Position: `bottom` (bottom of screen)
- Timeout: `1` second (keys disappear after 1s of inactivity)

### Implementation Notes

**Why setuid instead of capabilities?**

Initial attempt used `cap_sys_admin+ep` capabilities, but `wshowkeys` binary specifically checks for the setuid bit, not just elevated privileges. The setuid approach is also simpler and more reliable.

**Security Considerations**:

1. **Restricted group**: Only users in `input` group can run wrapper
2. **Read-only access**: wshowkeys only reads input events, doesn't write
3. **Timeout protection**: 1-second timeout prevents runaway processes
4. **Automatic cleanup**: pkill on mode exit ensures no orphaned processes

**Platform Differences**:

- **M1 MacBook Pro**: CapsLock (bindcode 66) for ergonomic single-key access
- **Hetzner Cloud**: Ctrl+0 (VNC doesn't relay CapsLock reliably)

### Testing Results (v1.5.10)

- [x] Security wrapper created with setuid bit
- [x] User added to input group
- [x] wshowkeys runs without permission error
- [x] Visual overlay appears on workspace mode entry (CapsLock/Ctrl+0)
- [x] Overlay shows typed digits/letters in real-time
- [x] Overlay disappears on mode exit (Enter/Escape)
- [x] No orphaned wshowkeys processes after mode exit
- [x] Works across all outputs (multi-monitor)

**Status**: ✅ **WORKING** (All tests passed as of 2024-11-04)
