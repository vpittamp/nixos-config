# Quickstart: Multi-Monitor Headless Sway/Wayland Setup

**Feature**: 048-multi-monitor-headless
**Target**: Hetzner Cloud VM (hetzner-sway configuration)

## Overview

This guide explains how to connect to your Hetzner Cloud VM's three virtual displays via VNC over Tailscale. Each display shows different workspaces, allowing a multi-monitor development workflow from any location.

## Display Layout

```
┌──────────────┬──────────────┬──────────────┐
│ HEADLESS-1   │ HEADLESS-2   │ HEADLESS-3   │
│ (Primary)    │ (Secondary)  │ (Tertiary)   │
│              │              │              │
│ Workspaces   │ Workspaces   │ Workspaces   │
│   1-2        │   3-5        │   6-9        │
│              │              │              │
│ Port 5900    │ Port 5901    │ Port 5902    │
└──────────────┴──────────────┴──────────────┘
```

**Resolution**: 1920x1080@60Hz (all displays)
**Layout**: Horizontal (left to right)

## Prerequisites

1. **Tailscale installed** on your local machine
2. **VNC client installed** (see recommendations below)
3. **Tailscale IP** of your Hetzner VM (find with: `tailscale status`)

## Quick Connect

### Step 1: Get Your VM's Tailscale IP

```bash
# On your local machine
tailscale status | grep hetzner

# Example output:
# 100.64.1.234   hetzner-sway         vpittamp@    linux   -
```

Your Tailscale IP is `100.64.1.234` (example - yours will differ).

### Step 2: Connect VNC Clients

Open **three VNC client windows**, one for each display:

**Display 1 (Workspaces 1-2)**:
```
vnc://100.64.1.234:5900
```

**Display 2 (Workspaces 3-5)**:
```
vnc://100.64.1.234:5901
```

**Display 3 (Workspaces 6-9)**:
```
vnc://100.64.1.234:5902
```

### Step 3: Arrange Windows

Position the three VNC client windows on your local screen to mimic a multi-monitor setup:

- **Left third**: Display 1 (port 5900)
- **Center third**: Display 2 (port 5901)
- **Right third**: Display 3 (port 5902)

## Recommended VNC Clients

### macOS
- **RealVNC Viewer**: https://www.realvnc.com/en/connect/download/viewer/
  - Best quality and performance
  - Connect via: `100.64.1.234:5900` (no `vnc://` prefix needed)

### Linux
- **TigerVNC Viewer**: `sudo apt install tigervnc-viewer` or `brew install tiger-vnc`
  - Command line: `vncviewer 100.64.1.234:5900`

### Windows
- **TightVNC Viewer**: https://www.tightvnc.com/download.php
  - Lightweight and fast

### Cross-Platform
- **Remmina** (Linux): Full-featured remote desktop client
- **Vinagre** (GNOME): Simple VNC viewer

## Workspace Navigation

Use keyboard shortcuts to switch workspaces within each display:

| Shortcut | Action |
|----------|--------|
| `Ctrl+1` | Switch to workspace 1 (Display 1) |
| `Ctrl+2` | Switch to workspace 2 (Display 1) |
| `Ctrl+3` | Switch to workspace 3 (Display 2) |
| `Ctrl+4` | Switch to workspace 4 (Display 2) |
| `Ctrl+5` | Switch to workspace 5 (Display 2) |
| `Ctrl+6` | Switch to workspace 6 (Display 3) |
| `Ctrl+7` | Switch to workspace 7 (Display 3) |
| `Ctrl+8` | Switch to workspace 8 (Display 3) |
| `Ctrl+9` | Switch to workspace 9 (Display 3) |

**Note**: The VNC client window must have focus for keyboard shortcuts to work.

## Common Tasks

### Open a Terminal

- Press `Win+Return` (on any display)
- Terminal opens on the currently active workspace
- Use `Win+Shift+N` to move terminal to workspace N

### Launch Applications

- Press `Win+D` to open application launcher (walker)
- Type application name and press Enter
- Application opens on current workspace

### Move Windows Between Workspaces

- Focus the window to move
- Press `Win+Shift+N` (where N is workspace number 1-9)
- Window moves to workspace N and appears on the corresponding display

### Switch Projects (i3pm)

- Press `Win+P` to open project switcher
- Select project with arrow keys
- Press Enter to switch
- Project-scoped windows distribute across all three displays

## Troubleshooting

### VNC Connection Refused

**Problem**: `Connection refused` when connecting to port 5900/5901/5902

**Solution**:
1. Check WayVNC services are running:
   ```bash
   ssh vpittamp@<tailscale-ip>
   systemctl --user status wayvnc@HEADLESS-1
   systemctl --user status wayvnc@HEADLESS-2
   systemctl --user status wayvnc@HEADLESS-3
   ```

2. Restart failed services:
   ```bash
   systemctl --user restart wayvnc@HEADLESS-1
   systemctl --user restart wayvnc@HEADLESS-2
   systemctl --user restart wayvnc@HEADLESS-3
   ```

3. Check Sway session is active:
   ```bash
   systemctl --user status sway-session.target
   ```

### Display Shows Blank Screen

**Problem**: VNC connects but displays a blank/black screen

**Solution**:
1. Verify outputs exist:
   ```bash
   swaymsg -t get_outputs | jq '.[] | {name, active, current_mode}'
   ```
   Should show three outputs: HEADLESS-1, HEADLESS-2, HEADLESS-3

2. Check workspace assignments:
   ```bash
   swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'
   ```

3. Switch to a workspace to activate the display:
   - Press `Ctrl+1` (for Display 1)
   - Press `Ctrl+3` (for Display 2)
   - Press `Ctrl+6` (for Display 3)

### Workspace Appears on Wrong Display

**Problem**: Workspace 5 shows on Display 1 instead of Display 2

**Solution**:
1. Verify workspace assignments:
   ```bash
   i3pm monitors status
   ```

2. Manually reassign workspaces:
   ```bash
   i3pm monitors reassign
   ```

3. Check configuration is correct:
   ```bash
   swaymsg -t get_workspaces | jq '.[] | {num, output}'
   ```

### VNC Client Connection Drops Frequently

**Problem**: VNC disconnects and reconnects frequently

**Possible Causes**:
1. **Network instability**: Check Tailscale connection quality
2. **VM resource exhaustion**: Check CPU/memory usage with `htop`
3. **WayVNC crash**: Check service logs:
   ```bash
   journalctl --user -u wayvnc@HEADLESS-1 -n 50
   ```

**Solution**:
- Systemd auto-restart should recover from crashes
- If persistent, check for errors in logs and report issue

### Can't Connect from Public WiFi

**Problem**: VNC connection times out on public networks

**Cause**: Some networks block VNC ports (5900-5902)

**Solution**:
- Tailscale should handle NAT traversal automatically
- If Tailscale can't establish direct connection, check:
  ```bash
  tailscale status
  ```
  Look for "direct" connection type (not "relay")

- Enable Tailscale's DERP relay if direct connection fails

### Keyboard Shortcuts Don't Work

**Problem**: `Ctrl+1` doesn't switch workspaces

**Cause**: VNC client may be intercepting keyboard shortcuts

**Solution**:
1. **macOS RealVNC**: Enable "Send special keys" in viewer preferences
2. **TigerVNC**: Use `--FullScreen` mode for proper key capture
3. **Alternative**: Use `swaymsg` via SSH:
   ```bash
   ssh vpittamp@<tailscale-ip> "swaymsg workspace number 3"
   ```

## Advanced Usage

### Changing Display Resolution

Each virtual display can have independent resolution settings. This is useful for:
- **Higher resolution** (2560x1440, 3840x2160) for clarity with high-bandwidth connections
- **Lower resolution** (1280x720) for reduced bandwidth on slower networks
- **Mixed resolutions** for different use cases per display

#### Procedure

1. **Edit** `/etc/nixos/home-modules/desktop/sway.nix` and locate the output configuration:
   ```nix
   output = if isHeadless then {
     "HEADLESS-1" = {
       resolution = "1920x1200@60Hz";  # Current default
       position = "0,0";
       scale = "1.0";
     };
     "HEADLESS-2" = {
       resolution = "2560x1440@60Hz";  # Example: Higher resolution
       position = "1920,0";
       scale = "1.0";
     };
     "HEADLESS-3" = {
       resolution = "1920x1200@60Hz";  # Keep default
       position = "4480,0";  # Adjust position for new width (1920 + 2560)
       scale = "1.0";
     };
   };
   ```

2. **Rebuild configuration**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner-sway
   ```

3. **Restart Sway** (choose one method):
   ```bash
   # Method 1: Reload Sway (faster, may not apply all changes)
   swaymsg reload

   # Method 2: Restart Sway session (recommended for resolution changes)
   systemctl --user restart sway-session.target

   # Method 3: Log out and back in (most reliable)
   ```

4. **Reconnect VNC clients** to see new resolution

#### Supported Resolution Formats

**Standard 16:10 (Recommended - matches TigerVNC defaults)**:
- `1920x1200@60Hz` - Default, good balance
- `2560x1600@60Hz` - High resolution
- `1280x800@60Hz` - Low bandwidth

**Standard 16:9 (May show letterboxing in some VNC clients)**:
- `1920x1080@60Hz` - Full HD
- `2560x1440@60Hz` - 2K/QHD
- `3840x2160@60Hz` - 4K/UHD
- `1280x720@60Hz` - HD

**Standard 4:3 (Legacy)**:
- `1600x1200@60Hz`
- `1024x768@60Hz`

**Custom Resolutions**:
- Format: `WIDTHxHEIGHT@REFRESHHz`
- Example: `1680x1050@60Hz`, `2048x1536@60Hz`
- Refresh rate typically 60Hz for VNC use

**Important Notes**:
- All displays can use different resolutions simultaneously
- Update `position` values when changing widths to avoid overlaps
- Higher resolutions increase network bandwidth requirements
- Some VNC clients auto-scale; others show native resolution
- Refresh rate (60Hz) is nominal for virtual displays

### Changing Workspace Distribution

To modify which workspaces appear on which display:

1. Edit `home-modules/desktop/sway.nix`:
   ```nix
   workspaceOutputAssign = [
     { workspace = "1"; output = "HEADLESS-1"; }
     # ... modify assignments ...
   ];
   ```

2. Rebuild and apply:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner-sway
   i3pm monitors reassign  # Apply changes without reboot
   ```

### Using Clipboard Across Displays

Clipboard content is shared across all displays and VNC clients:

1. Copy text in Display 1 (Ctrl+C or select + middle-click)
2. Paste in Display 2 or 3 (Ctrl+V or middle-click)
3. Clipboard syncs automatically via Wayland

### Monitoring VNC Performance

Check VNC stream latency and bandwidth:

```bash
# Monitor service CPU/memory usage
systemctl --user status wayvnc@HEADLESS-1 | grep -E "(CPU|Memory)"

# Monitor network traffic
sudo iftop -i tailscale0

# View VNC server logs for errors
journalctl --user -u wayvnc@HEADLESS-1 -f
```

## Service Management

### Start/Stop Individual Displays

```bash
# Stop Display 2 (workspaces 3-5)
systemctl --user stop wayvnc@HEADLESS-2

# Start Display 2
systemctl --user start wayvnc@HEADLESS-2

# Restart all displays
systemctl --user restart wayvnc@HEADLESS-{1,2,3}
```

### Disable Displays Permanently

```bash
# Disable Display 3 (won't start on boot)
systemctl --user disable wayvnc@HEADLESS-3

# Re-enable
systemctl --user enable wayvnc@HEADLESS-3
```

### View Service Logs

```bash
# Follow live logs for Display 1
journalctl --user -u wayvnc@HEADLESS-1 -f

# View last 50 log lines
journalctl --user -u wayvnc@HEADLESS-1 -n 50

# View logs for all displays
journalctl --user -u 'wayvnc@*' -f
```

## Persistence Guarantees

The three-display configuration is **fully persistent** and survives both VM reboots and Sway restarts. All configuration is declarative and managed by NixOS.

### What Persists Across Reboots

✅ **Automatic Startup**:
- All three WayVNC services start automatically when the system boots
- Services are enabled via systemd `WantedBy=sway-session.target`
- Startup occurs within 10 seconds of Sway initialization

✅ **Display Configuration**:
- Three virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3) are created automatically
- Resolution settings persist (1920x1200@60Hz by default, or custom resolutions if configured)
- Horizontal positioning (0,0; 1920,0; 3840,0) remains consistent

✅ **Workspace Assignments**:
- Workspaces 1-2 → HEADLESS-1 (Primary)
- Workspaces 3-5 → HEADLESS-2 (Secondary)
- Workspaces 6-9 → HEADLESS-3 (Tertiary)

✅ **VNC Access**:
- Port assignments remain stable (5900, 5901, 5902)
- Firewall rules automatically applied on Tailscale interface
- VNC connections work immediately after reboot

### What Persists Across Sway Restarts

When you reload Sway (`swaymsg reload` or `Ctrl+Shift+C`), the following persist:

✅ **Display Configuration**: All outputs remain active with correct resolutions
✅ **Workspace Assignments**: Workspace-to-output mappings remain intact
✅ **VNC Services**: WayVNC instances continue running without interruption
✅ **Active Connections**: Existing VNC client connections remain connected

**Note**: Window positions and focus state are managed by Sway and will be restored based on your workspace state.

### How It Works

The multi-display setup uses **declarative configuration** in NixOS:

1. **Environment Variables** (`/etc/nixos/configurations/hetzner-sway.nix`):
   ```nix
   WLR_HEADLESS_OUTPUTS = "3";  # Creates 3 virtual displays at startup
   ```

2. **Sway Output Configuration** (`/etc/nixos/home-modules/desktop/sway.nix`):
   ```nix
   output = {
     "HEADLESS-1" = { resolution = "1920x1200@60Hz"; position = "0,0"; };
     "HEADLESS-2" = { resolution = "1920x1200@60Hz"; position = "1920,0"; };
     "HEADLESS-3" = { resolution = "1920x1200@60Hz"; position = "3840,0"; };
   };
   ```

3. **Systemd Services** (managed by home-manager):
   ```nix
   systemd.user.services."wayvnc@HEADLESS-N" = {
     Install.WantedBy = [ "sway-session.target" ];  # Auto-start
   };
   ```

All configuration is stored in `/etc/nixos/` and tracked in Git, ensuring reproducibility across rebuilds.

### Verifying Persistence

After a reboot or Sway restart, verify everything is working:

```bash
# Check all services are active
systemctl --user list-units 'wayvnc@*'

# Verify outputs exist
swaymsg -t get_outputs | jq -r '.[] | "\(.name): \(.current_mode.width)x\(.current_mode.height)"'

# Verify workspace assignments
swaymsg -t get_workspaces | jq -r '.[] | "WS \(.num): \(.output)"'

# Test VNC connectivity
nc -zv <tailscale-ip> 5900 5901 5902
```

### Troubleshooting Persistence Issues

**Services don't start after reboot:**
1. Check if services are enabled: `systemctl --user list-unit-files 'wayvnc@*'`
2. View service logs: `journalctl --user -u wayvnc@HEADLESS-1 -b 0`
3. Verify sway-session.target is active: `systemctl --user status sway-session.target`

**Wrong resolution after reboot:**
1. Check Sway configuration: `grep -A 5 "output.*HEADLESS" ~/.config/sway/config`
2. Rebuild configuration: `sudo nixos-rebuild switch --flake .#hetzner-sway`
3. Restart Sway session or reboot

**Workspace assignments reset:**
1. Check workspace assignments: `swaymsg -t get_workspaces | jq -r '.[] | "WS \(.num): \(.output)"'`
2. Manually reassign: `i3pm monitors reassign`
3. If persistent issue, verify Sway config has `workspace N output HEADLESS-X` directives

## Integration with i3pm

The multi-monitor setup integrates seamlessly with i3pm project management:

### Project Switching

```bash
# Switch to NixOS project
pswitch nixos

# Windows distribute across all three displays:
# - VS Code → Workspace 2 (Display 1)
# - Terminal → Workspace 1 (Display 1)
# - Firefox → Workspace 3 (Display 2)
# - etc.
```

### Monitor Status

```bash
# Check VNC monitor connections and status
i3pm-monitors status

# Expected output shows all three displays with VNC connection status:
# ✅ HEADLESS-1 (Port: 5900, Clients: N, Workspaces: 1)
# ✅ HEADLESS-2 (Port: 5901, Clients: N, Workspaces: 3)
# ✅ HEADLESS-3 (Port: 5902, Clients: N, Workspaces: 6)

# View window state across all displays
i3pm windows --tree

# Check daemon status (confirms integration with Sway)
i3pm daemon status
```

### Workspace Distribution

Workspaces are **statically assigned** to displays in the Sway configuration:
- **Workspaces 1-2** → HEADLESS-1 (Primary)
- **Workspaces 3-5** → HEADLESS-2 (Secondary)
- **Workspaces 6-9** → HEADLESS-3 (Tertiary)

This follows the i3pm 3-monitor distribution pattern and requires no runtime configuration. The assignments are declared in `/etc/nixos/home-modules/desktop/sway.nix` and persist across reboots.

```bash
# Verify workspace assignments
swaymsg -t get_workspaces | jq -r '.[] | "WS \(.num): \(.output)"'

# Check Sway config workspace assignments
grep "workspace.*output" ~/.config/sway/config
```

## Performance Tips

### Reduce VNC Bandwidth

1. **Lower resolution**: Use 1280x720 instead of 1920x1080
2. **Reduce color depth**: Configure VNC client for 8-bit color (if supported)
3. **Disable desktop effects**: Sway is minimal by default, no changes needed
4. **Close unused displays**: Stop VNC services for displays not in use

### Improve Responsiveness

1. **Use wired connection**: Ethernet > WiFi for VNC streaming
2. **Minimize VNC client windows**: Reduce rendering overhead
3. **Use keyboard shortcuts**: Avoid VNC pointer lag
4. **Enable Tailscale direct connections**: Avoid relay latency

## Security Notes

- **VNC ports (5900-5902)** are only accessible via Tailscale network
- **No authentication** is configured (Tailscale provides network-level security)
- **Unencrypted VNC traffic** over Tailscale encrypted tunnel
- **To verify**: Public IP should NOT accept VNC connections

### Test Security

```bash
# From outside Tailscale network (should timeout):
nc -zv <public-ip> 5900

# From Tailscale network (should connect):
nc -zv <tailscale-ip> 5900
```

## Rollback and Recovery

If you encounter issues with the multi-monitor setup and need to revert to the previous single-display configuration, follow these procedures.

### Quick Rollback (Temporary)

Disable the multi-monitor VNC services temporarily without changing configuration:

```bash
# Stop all VNC services
systemctl --user stop wayvnc@HEADLESS-{1,2,3}

# Disable automatic startup
systemctl --user disable wayvnc@HEADLESS-{1,2,3}

# Restart Sway to use single display (HEADLESS-1)
swaymsg reload
```

This keeps the multi-monitor configuration but disables VNC access. You'll still have three virtual displays, but no VNC services.

### Full Rollback (Restore Single Display)

To completely revert to the single-display configuration:

1. **Restore configuration backups** (created during Phase 1):
   ```bash
   cd /etc/nixos

   # Restore hetzner-sway.nix
   cp configurations/hetzner-sway.nix.backup configurations/hetzner-sway.nix

   # Restore sway.nix home-manager configuration
   cp home-modules/desktop/sway.nix.backup home-modules/desktop/sway.nix
   ```

2. **Test configuration**:
   ```bash
   sudo nixos-rebuild dry-build --flake .#hetzner-sway
   ```

3. **Apply rollback**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner-sway
   ```

4. **Restart Sway session**:
   ```bash
   # Log out and log back in, or:
   systemctl --user restart sway-session.target
   ```

5. **Verify single display**:
   ```bash
   swaymsg -t get_outputs | jq '.[] | {name, active}'
   # Should show only HEADLESS-1

   systemctl --user list-units 'wayvnc@*'
   # Should show only wayvnc@HEADLESS-1 (port 5900)
   ```

### NixOS Generation Rollback

NixOS keeps previous system generations. You can rollback to any previous generation:

```bash
# List available generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or switch to specific generation (e.g., generation 42)
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 42
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

**Note**: This rolls back ALL system changes, not just the multi-monitor setup.

### Emergency Recovery (Broken Sway)

If Sway fails to start due to configuration issues:

1. **SSH into the VM**:
   ```bash
   ssh vpittamp@<tailscale-ip>
   ```

2. **Check Sway logs**:
   ```bash
   journalctl --user -u sway-session.target -b 0 -n 50
   ```

3. **Restore from backup or rollback**:
   ```bash
   # Option 1: Restore backups (see "Full Rollback" above)

   # Option 2: Rollback to previous generation
   sudo nixos-rebuild switch --rollback
   ```

4. **Restart greetd** (login manager):
   ```bash
   sudo systemctl restart greetd
   ```

### Verifying Rollback Success

After rollback, verify the system is working:

```bash
# Check single display exists
swaymsg -t get_outputs | jq -r '.[] | .name'
# Expected: HEADLESS-1

# Check single VNC service
systemctl --user status wayvnc@HEADLESS-1
# Expected: active (running)

# Test VNC connectivity
nc -zv <tailscale-ip> 5900
# Expected: Connection succeeded

# Verify workspace assignments reset
swaymsg -t get_workspaces | jq -r '.[] | "WS \(.num): \(.output)"'
# Expected: All workspaces on HEADLESS-1
```

### Re-applying Multi-Monitor Setup

To re-enable the multi-monitor setup after rollback:

```bash
# Restore multi-monitor configuration (if backups were used)
git checkout configurations/hetzner-sway.nix home-modules/desktop/sway.nix

# Or manually re-apply changes following Phase 2-4 tasks

# Test and apply
sudo nixos-rebuild dry-build --flake .#hetzner-sway
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### Getting Help

If rollback doesn't resolve the issue:

1. **Check system status**:
   ```bash
   systemctl --failed --user
   journalctl --user -b 0 -p err
   ```

2. **Review configuration errors**:
   ```bash
   sudo nixos-rebuild dry-build --flake .#hetzner-sway --show-trace
   ```

3. **Consult documentation**:
   - `/etc/nixos/CLAUDE.md` - System overview and troubleshooting
   - `/etc/nixos/specs/048-multi-monitor-headless/plan.md` - Implementation details
   - GitHub Issues: https://github.com/your-repo/issues

## Further Reading

- **WayVNC Documentation**: https://github.com/any1/wayvnc
- **Sway User Guide**: https://github.com/swaywm/sway/wiki
- **Tailscale VPN**: https://tailscale.com/kb/
- **i3pm Project Management**: See `/etc/nixos/CLAUDE.md` section "Project Management Workflow"
- **Feature 047 (Sway Config Manager)**: `/etc/nixos/specs/047-create-a-new/quickstart.md`

---

**Created**: 2025-10-29
**Feature**: 048-multi-monitor-headless
**Configuration**: hetzner-sway
