# Quickstart: M1 Sway Migration

**Feature**: 045-migrate-m1-macbook
**Date**: 2025-10-27
**Audience**: Developers deploying Sway on M1 MacBook Pro

## Overview

This guide covers building, deploying, and validating the M1 Sway configuration remotely from a development machine.

---

## Prerequisites

- M1 MacBook Pro running NixOS with Asahi Linux kernel
- SSH access to M1 from development machine
- Git repository cloned at `/etc/nixos` on both machines
- Feature branch `045-migrate-m1-macbook` checked out

---

## Build & Deploy

### Remote Build from Development Machine

```bash
# From development machine (Codespace/Hetzner)
cd /etc/nixos

# Test build configuration (dry-build)
nixos-rebuild dry-build --flake .#m1 --impure \
  --target-host vpittamp@m1-macbook --use-remote-sudo

# If dry-build succeeds, deploy
nixos-rebuild switch --flake .#m1 --impure \
  --target-host vpittamp@m1-macbook --use-remote-sudo
```

**Notes**:
- `--impure` flag required for Asahi firmware access (`/boot/asahi`)
- `--target-host` enables remote build and deployment
- `--use-remote-sudo` for privilege elevation on M1
- Build artifacts cached on M1 (no local Nix store transfer needed)

### Local Build on M1 (Alternative)

```bash
# SSH into M1
ssh vpittamp@m1-macbook

# Navigate to repo
cd /etc/nixos

# Test build
sudo nixos-rebuild dry-build --flake .#m1 --impure

# Apply
sudo nixos-rebuild switch --flake .#m1 --impure
```

---

## Post-Deployment Validation

### 1. Verify Sway Session Starts

```bash
# Reboot M1
ssh vpittamp@m1-macbook sudo reboot

# Wait ~30 seconds, then SSH back in
ssh vpittamp@m1-macbook

# Check if Sway is running
pgrep -a sway
# Expected: Process ID and command line

# Check display server
echo $WAYLAND_DISPLAY
# Expected: wayland-1

# Verify no X11 session
echo $DISPLAY
# Expected: (empty)
```

### 2. Validate i3pm Daemon Connection

```bash
# Check daemon status
i3pm daemon status

# Expected output:
# Daemon Status: RUNNING
# Connection: Sway IPC (socket: /run/user/1000/sway-ipc.*.sock)
# Uptime: 5s
# Event Subscriptions: window, workspace, output, tick, shutdown
```

### 3. Test Window Management

```bash
# Open terminal (Meta+Return from Sway session)
# Should open Ghostty/Alacritty with i3pm project context

# From SSH session, check windows
i3pm windows --tree

# Expected output:
# 📺 eDP-1 (2560x1600, scale 2.0)
#   └─ Workspace 1
#       └─ [code] VS Code ● [nixos]
```

### 4. Test Walker Launcher

From Sway session (Meta+D):
1. Press Meta+D → Walker should appear centered
2. Type "code" → VS Code should appear in results
3. Press "=" → Calculator mode
4. Type "=2+2" → Should show "4"
5. Type ":" → Clipboard history (if wl-clipboard installed)

### 5. Validate Display Scaling

```bash
# Check Sway output configuration
swaymsg -t get_outputs | jq '.[] | {name, scale, rect}'

# Expected for eDP-1 (Retina):
# {
#   "name": "eDP-1",
#   "scale": 2.0,
#   "rect": {"x": 0, "y": 0, "width": 1280, "height": 800}
# }
```

### 6. Test Project Switching

```bash
# From Sway session:
# Press Meta+P → Project switcher
# Select "nixos" project
# Verify windows appear with project marks

# From SSH:
i3pm project current
# Expected: nixos

# Check window marks
i3pm windows --json | jq '.outputs[].workspaces[].windows[].marks'
# Expected: ["project:nixos:12345"]
```

### 7. Test Multi-Monitor (Optional)

```bash
# Connect external monitor
# Wait 1-2 seconds for hotplug detection

# Check monitor distribution
i3pm monitors status

# Expected:
# Output      | Active | Current WS | Role      | Assigned WS
# eDP-1       | Yes    | 1          | primary   | 1, 2
# HDMI-A-1    | Yes    | 3          | secondary | 3-9, 70

# Test workspace redistribution
i3pm monitors reassign --dry-run
# Should show no changes (already correct)
```

---

## Troubleshooting

### Sway Fails to Start

**Symptom**: Login loops back to display manager or black screen.

**Debug Steps**:
```bash
# SSH into M1
ssh vpittamp@m1-macbook

# Check Sway logs
journalctl --user -u sway -n 50

# Check if Wayland socket exists
ls -la /run/user/$(id -u)/wayland-*

# Try manual Sway start
sway --debug 2>&1 | tee /tmp/sway-debug.log
```

**Common Issues**:
- Missing Asahi firmware → Rebuild with `--impure` flag
- Display scaling error → Check output names match config
- GPU driver issue → Verify `hardware.asahi` settings

### i3pm Daemon Not Connecting

**Symptom**: `i3pm daemon status` shows disconnected.

**Debug Steps**:
```bash
# Check daemon logs
journalctl --user -u i3-project-event-listener -n 50

# Verify Sway IPC socket
ls -la /run/user/$(id -u)/sway-ipc.*

# Restart daemon
systemctl --user restart i3-project-event-listener

# Check connection
i3pm daemon status
```

**Common Issues**:
- Socket path wrong → Check `SWAYSOCK` environment variable
- Python i3ipc not installed → Verify home-manager packages
- Daemon crash loop → Check for Python errors in logs

### Walker Not Launching

**Symptom**: Meta+D does nothing or Walker crashes.

**Debug Steps**:
```bash
# Try manual launch
walker

# Check for errors
journalctl --user -u elephant -n 50

# Verify Elephant service
systemctl --user status elephant

# Check Wayland display
echo $WAYLAND_DISPLAY
# Should be wayland-1
```

**Common Issues**:
- GDK_BACKEND still set to x11 → Remove from config
- Elephant not running → Restart service
- Missing wl-clipboard → Install via home-manager

### Display Scaling Issues

**Symptom**: Blurry text or incorrect resolution.

**Debug Steps**:
```bash
# Check output scaling
swaymsg -t get_outputs | jq '.[] | {name, scale, current_mode}'

# Manually set scaling
swaymsg output eDP-1 scale 2.0

# Test with different scales
swaymsg output eDP-1 scale 1.5  # Fractional (may blur XWayland)
swaymsg output eDP-1 scale 2.0  # Integer (crisp)
```

**Fix**: Update `sway.nix` with correct scale value, rebuild.

### External Monitor Not Detected

**Symptom**: `i3pm monitors status` shows only eDP-1.

**Debug Steps**:
```bash
# Check Sway outputs
swaymsg -t get_outputs

# Check kernel DRM
ls /sys/class/drm/

# Check hotplug events
journalctl -f -u i3-project-event-listener
# Connect monitor, watch for output::added event
```

**Common Issues**:
- USB-C adapter not compatible → Try different adapter
- Output event not subscribed → Verify daemon config
- Workspace mapping config has wrong output names → Update JSON

---

## Rollback Procedure

If migration fails, revert to previous NixOS generation:

```bash
# SSH into M1
ssh vpittamp@m1-macbook

# List generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or specific generation
sudo nixos-rebuild switch --switch-generation 42

# Reboot
sudo reboot
```

---

## Common Sway Commands

| Action | i3 Command | Sway Command | Notes |
|--------|------------|--------------|-------|
| Reload config | `i3-msg reload` | `swaymsg reload` | Same functionality |
| List outputs | `xrandr` | `swaymsg -t get_outputs` | JSON format |
| Set output scale | `xrandr --scale` | `swaymsg output eDP-1 scale 2.0` | Per-output |
| Workspace to output | `i3-msg "workspace 1 output eDP-1"` | `swaymsg "workspace 1 output eDP-1"` | Identical |
| Mark window | `i3-msg mark foo` | `swaymsg mark foo` | Identical |
| Get tree | `i3-msg -t get_tree` | `swaymsg -t get_tree` | Identical |

---

## Performance Baselines

After successful deployment, capture performance baselines:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Sway startup | <5s | `systemd-analyze blame` |
| Daemon connection | <2s | `i3pm daemon status` (check uptime) |
| Window event latency | <100ms | `i3pm daemon events --follow` (watch timestamps) |
| Project switch | <500ms | Time `i3pm project switch` command |
| Walker launch | <200ms | Time from Meta+D to window visible |

---

## Next Steps

After validation passes:

1. **Test multi-monitor setup** (if external display available)
2. **Configure wayvnc** for remote access (optional)
3. **Customize Sway** appearance (theme, gaps, borders)
4. **Update CLAUDE.md** with M1 Sway build instructions
5. **Document differences** from Hetzner i3 in migration guide

---

## References

- [Sway Configuration Documentation](https://github.com/swaywm/sway/wiki)
- [i3pm Daemon Quickstart](../015-create-a-new/quickstart.md)
- [Feature 033 Multi-Monitor](../033-declarative-workspace-to/quickstart.md)
- [Feature 043 Walker/Elephant](../043-get-full-functionality/quickstart.md)
