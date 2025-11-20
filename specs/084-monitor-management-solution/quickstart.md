# Quickstart: M1 Hybrid Multi-Monitor Management

**Feature**: 084-monitor-management-solution
**Date**: 2025-11-19

## Overview

Extend your M1 MacBook Pro workspace with VNC-accessible virtual displays while keeping your physical Retina display active. Access virtual displays from an iPad, another computer, or any VNC client over Tailscale.

---

## Prerequisites

- NixOS on Apple Silicon M1 (Asahi Linux)
- Tailscale configured and connected
- VNC client on secondary device (iPad, other computer)

---

## Quick Commands

| Action | Command |
|--------|---------|
| Cycle profiles | `Mod+Shift+M` |
| Switch to specific profile | `set-monitor-profile local+1vnc` |
| Check current profile | `cat ~/.config/sway/monitor-profile.current` |
| View output states | `cat ~/.config/sway/output-states.json \| jq` |

---

## Monitor Profiles

### local-only (Default)

Physical Retina display only. All workspaces on eDP-1.

**Use when**: Working locally without need for extended screen space.

### local+1vnc

Physical display + one VNC virtual display.

**Workspaces**:
- eDP-1 (L): Workspaces 1-4
- HEADLESS-1 (V1): Workspaces 5-9, PWAs 50+

**VNC Access**: Connect to `<tailscale-ip>:5900`

**Use when**: Need one additional display for reference material, chat, or monitoring.

### local+2vnc

Physical display + two VNC virtual displays.

**Workspaces**:
- eDP-1 (L): Workspaces 1-3
- HEADLESS-1 (V1): Workspaces 4-6, PWAs 50-74
- HEADLESS-2 (V2): Workspaces 7-9, PWAs 75+

**VNC Access**:
- V1: `<tailscale-ip>:5900`
- V2: `<tailscale-ip>:5901`

**Use when**: Maximum workspace expansion for complex projects.

---

## Usage

### Activating VNC Displays

1. **Via Keyboard**: Press `Mod+Shift+M` to cycle through profiles
   - local-only → local+1vnc → local+2vnc → local-only

2. **Via Command**:
   ```bash
   set-monitor-profile local+1vnc
   ```

3. **Via Menu**: (if Walker launcher configured with profile actions)

### Connecting via VNC

1. Find your M1's Tailscale IP:
   ```bash
   tailscale status | grep nixos-m1
   ```

2. Connect from your VNC client:
   - **iPad**: Use Jump Desktop, Screens, or RealVNC
   - **macOS**: `vnc://<tailscale-ip>:5900`
   - **Windows**: TightVNC, RealVNC
   - **Linux**: Remmina, TigerVNC

3. You'll see the virtual display's workspaces immediately.

### Moving Windows Between Displays

Standard Sway workspace navigation works across all displays:

- `Mod+<number>`: Switch to workspace
- `Mod+Shift+<number>`: Move focused window to workspace

Windows on virtual displays are accessible from the local display via workspace switching.

---

## Top Bar Indicators

The Eww top bar shows current profile and active displays:

| Indicator | Meaning |
|-----------|---------|
| **L** | Physical display (eDP-1) active |
| **V1** | Virtual display 1 active |
| **V2** | Virtual display 2 active |

Profile name (local-only, local+1vnc, local+2vnc) displayed in teal pill.

---

## Troubleshooting

### VNC Connection Refused

1. Check profile is active:
   ```bash
   cat ~/.config/sway/monitor-profile.current
   ```

2. Verify WayVNC service running:
   ```bash
   systemctl --user status wayvnc@HEADLESS-1.service
   ```

3. Check Tailscale connectivity:
   ```bash
   tailscale ping <client-device>
   ```

4. Ensure firewall rules:
   ```bash
   # Should show ports 5900, 5901 on tailscale0
   sudo nft list ruleset | grep 5900
   ```

### Profile Switch Failed

1. Check daemon logs:
   ```bash
   journalctl --user -u i3-project-event-listener -f | grep "Feature 084"
   ```

2. Manually retry:
   ```bash
   set-monitor-profile local-only
   set-monitor-profile local+1vnc
   ```

3. If stuck, restart daemon:
   ```bash
   systemctl --user restart i3-project-event-listener
   ```

### Top Bar Not Updating

1. Check Eww service:
   ```bash
   systemctl --user status eww-top-bar
   ```

2. Restart if needed:
   ```bash
   systemctl --user restart eww-top-bar
   ```

### Windows Stuck on Disabled Display

Windows are automatically moved to eDP-1 when virtual displays are disabled. If this fails:

1. Check daemon health:
   ```bash
   i3pm diagnose health
   ```

2. Manually move workspace:
   ```bash
   swaymsg "[workspace=5] move workspace to output eDP-1"
   ```

---

## Configuration

### Profile Definitions

Located in `~/.config/sway/monitor-profiles/`:

```bash
ls ~/.config/sway/monitor-profiles/
# local-only.json
# local+1vnc.json
# local+2vnc.json
```

### Customizing Workspace Distribution

Edit profile JSON to change which workspaces go on which display:

```json
{
  "name": "local+1vnc",
  "workspace_assignments": [
    {"output": "eDP-1", "workspaces": [1, 2, 3, 4, 5]},
    {"output": "HEADLESS-1", "workspaces": [6, 7, 8, 9]}
  ]
}
```

Then reload:
```bash
swaymsg reload
```

### VNC Resolution

Virtual displays default to 1920x1080@60Hz. To customize, edit profile output configuration:

```json
{
  "outputs": [
    {
      "name": "HEADLESS-1",
      "position": {"width": 1920, "height": 1080}
    }
  ]
}
```

---

## Security

VNC access is restricted to Tailscale network only:
- Ports 5900-5901 are only open on tailscale0 interface
- Connection attempts from public internet are blocked
- All traffic encrypted via Tailscale's WireGuard

---

## Architecture

```
┌──────────────────────────────────────────────┐
│ M1 MacBook Pro                               │
│                                              │
│  ┌─────────┐   ┌─────────────┐               │
│  │  eDP-1  │   │  HEADLESS-1 │──→ VNC:5900   │
│  │ (Retina)│   │  (Virtual)  │               │
│  └─────────┘   └─────────────┘               │
│                ┌─────────────┐               │
│                │  HEADLESS-2 │──→ VNC:5901   │
│                │  (Virtual)  │               │
│                └─────────────┘               │
│                                              │
│  Profile: local+2vnc                         │
│  Top Bar: [L] [V1: 3] [V2: 3]               │
└──────────────────────────────────────────────┘
                    │ Tailscale
                    ▼
        ┌───────────────────┐
        │   VNC Client      │
        │   (iPad, etc)     │
        └───────────────────┘
```

---

## Related Features

- **Feature 083**: Multi-Monitor Window Management (Hetzner reference)
- **Feature 048**: Multi-Monitor Headless Setup
- **Feature 001**: Declarative Workspace-to-Monitor Assignment
- **Feature 049**: Auto Workspace Monitor Redistribution

---

## CLI Reference

### set-monitor-profile

```bash
set-monitor-profile <profile-name>

# Examples
set-monitor-profile local-only
set-monitor-profile local+1vnc
set-monitor-profile local+2vnc
```

### i3pm monitors

```bash
i3pm monitors status    # Show current assignments
i3pm monitors reassign  # Force workspace reassignment
i3pm monitors config    # Show profile configuration
```

### Systemd Services

```bash
# WayVNC services
systemctl --user {start|stop|status} wayvnc@HEADLESS-1.service
systemctl --user {start|stop|status} wayvnc@HEADLESS-2.service

# Daemon
systemctl --user {status|restart} i3-project-event-listener

# Top bar
systemctl --user {status|restart} eww-top-bar
```
