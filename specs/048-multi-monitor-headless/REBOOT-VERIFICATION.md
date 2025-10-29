# Reboot and Verification Procedure
**Feature 048: Multi-Monitor Headless Sway/Wayland Setup**
**Date**: 2025-10-29

## Pre-Reboot Checklist

✅ Configuration validated with `nixos-rebuild dry-build`
✅ Backups created:
- `/etc/nixos/configurations/hetzner-sway.nix.backup-*`
- `/etc/nixos/home-modules/desktop/sway.nix.backup-*`

✅ Changes applied with `nixos-rebuild switch`
✅ Audio configuration reviewed - no conflicts

## Step 1: Reboot the System

```bash
sudo reboot
```

**Expected downtime**: ~30-60 seconds

## Step 2: Verify Three Outputs Were Created

After system comes back online, SSH in and check:

```bash
# Find the current Sway socket
SWAYSOCK=$(find /run/user/1000 -name "sway-ipc.*.sock" | head -1)

# Export it for subsequent commands
export SWAYSOCK

# Verify three outputs exist
swaymsg -t get_outputs | jq '.[] | {name, active, current_mode}'
```

**Expected output**:
```json
{
  "name": "HEADLESS-1",
  "active": true,
  "current_mode": {
    "width": 1920,
    "height": 1080,
    "refresh": 60000
  }
}
{
  "name": "HEADLESS-2",
  "active": true,
  "current_mode": {
    "width": 1920,
    "height": 1080,
    "refresh": 60000
  }
}
{
  "name": "HEADLESS-3",
  "active": true,
  "current_mode": {
    "width": 1920,
    "height": 1080,
    "refresh": 60000
  }
}
```

## Step 3: Verify WayVNC Services Started

```bash
systemctl --user list-units 'wayvnc@*' --no-pager
```

**Expected output**:
```
UNIT                       LOAD   ACTIVE SUB     DESCRIPTION
wayvnc@HEADLESS-1.service  loaded active running wayvnc VNC server for HEADLESS-1
wayvnc@HEADLESS-2.service  loaded active running wayvnc VNC server for HEADLESS-2
wayvnc@HEADLESS-3.service  loaded active running wayvnc VNC server for HEADLESS-3
```

All three should show **active (running)**.

### If services are failed, check logs:

```bash
journalctl --user -u wayvnc@HEADLESS-1 -n 20 --no-pager
journalctl --user -u wayvnc@HEADLESS-2 -n 20 --no-pager
journalctl --user -u wayvnc@HEADLESS-3 -n 20 --no-pager
```

## Step 4: Verify Workspace Assignments

```bash
swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'
```

**Expected output**:
```json
{"num": 1, "output": "HEADLESS-1", "visible": true}
{"num": 2, "output": "HEADLESS-1", "visible": false}
{"num": 3, "output": "HEADLESS-2", "visible": false}
{"num": 4, "output": "HEADLESS-2", "visible": false}
{"num": 5, "output": "HEADLESS-2", "visible": false}
{"num": 6, "output": "HEADLESS-3", "visible": false}
{"num": 7, "output": "HEADLESS-3", "visible": false}
{"num": 8, "output": "HEADLESS-3", "visible": false}
{"num": 9, "output": "HEADLESS-3", "visible": false}
```

Distribution:
- **HEADLESS-1**: Workspaces 1-2
- **HEADLESS-2**: Workspaces 3-5
- **HEADLESS-3**: Workspaces 6-9

## Step 5: Verify VNC Ports Are Listening

```bash
ss -tlnp | grep -E '5900|5901|5902'
```

**Expected output** (similar to):
```
LISTEN 0  128  0.0.0.0:5900  0.0.0.0:*  users:(("wayvnc",pid=XXXX,fd=X))
LISTEN 0  128  0.0.0.0:5901  0.0.0.0:*  users:(("wayvnc",pid=XXXX,fd=X))
LISTEN 0  128  0.0.0.0:5902  0.0.0.0:*  users:(("wayvnc",pid=XXXX,fd=X))
```

## Step 6: Test VNC Connectivity from Local Machine

### Get Tailscale IP

On your local machine:
```bash
tailscale status | grep hetzner
```

Example output: `100.64.1.234   hetzner-sway   ...`

### Connect VNC Clients

Open three VNC client windows:

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

### Expected Result

✅ All three connections succeed
✅ Each display shows a different view
✅ Display 1 shows workspace 1 by default
✅ Displays 2 and 3 show empty workspaces initially

## Step 7: Test Workspace Switching

### From VNC Display 1 (port 5900):

Press `Ctrl+3` (or `Super+3`) to switch to workspace 3.

**Expected**: Display 1 should now be empty (workspace 3 is on HEADLESS-2).

### From VNC Display 2 (port 5901):

You should now see workspace 3 become active on Display 2.

### Test moving a window:

1. From Display 1, press `Super+Return` to open a terminal
2. The terminal should appear on workspace 1 (visible on Display 1)
3. Press `Super+Shift+5` to move window to workspace 5
4. Look at Display 2 - the terminal should now appear there (workspace 5 is on HEADLESS-2)

## Step 8: Verify i3pm Integration

```bash
i3pm monitors status
```

**Expected output**:
```
Monitor 1: HEADLESS-1 (active)
Monitor 2: HEADLESS-2 (active)
Monitor 3: HEADLESS-3 (active)
Workspace distribution: 1-2, 3-5, 6-9
```

## Troubleshooting

### If outputs are not created:

```bash
# Check WLR environment variables
systemctl status greetd | grep WLR_HEADLESS_OUTPUTS

# Should show: export WLR_HEADLESS_OUTPUTS=3
```

### If only HEADLESS-1 exists:

This means the environment variable didn't apply. Check:
```bash
cat /proc/$(pgrep sway | head -1)/environ | tr '\0' '\n' | grep WLR_HEADLESS_OUTPUTS
```

Should output: `WLR_HEADLESS_OUTPUTS=3`

### If WayVNC services fail with "Failed to listen on socket":

```bash
# Check if ports are already in use
ss -tlnp | grep -E '5900|5901|5902'

# Check service logs for specific error
journalctl --user -u wayvnc@HEADLESS-1 -n 50 --no-pager
```

### If workspace assignments are wrong:

```bash
# Manually reassign workspaces
i3pm monitors reassign

# Or reload Sway config
swaymsg reload
```

## Success Criteria (from spec.md)

✅ **SC-001**: Three independent VNC clients can connect simultaneously
✅ **SC-002**: Each VNC stream updates in real-time (<200ms latency)
✅ **SC-003**: Workspace switching activates correct displays
✅ **SC-004**: WayVNC services start automatically within 10 seconds
✅ **SC-005**: VNC ports NOT accessible from public internet (only Tailscale)
✅ **SC-006**: i3pm reports 3 outputs and correct workspace distribution

## Next Steps After Verification

Once all checks pass:

1. **Mark tasks T017-T025 as complete** in tasks.md
2. **Test audio separately** (audio issue is independent of VNC)
3. **Proceed to Phase 4** (User Story 2: Dynamic Resolution) if desired
4. **Or stop at MVP** and use the three-display setup

## Rollback Procedure (if needed)

If something goes wrong:

```bash
# Restore backups
sudo cp /etc/nixos/configurations/hetzner-sway.nix.backup-* /etc/nixos/configurations/hetzner-sway.nix
sudo cp /etc/nixos/home-modules/desktop/sway.nix.backup-* /etc/nixos/home-modules/desktop/sway.nix

# Rebuild with old configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# Or boot into previous NixOS generation
sudo nixos-rebuild --list-generations
sudo nixos-rebuild switch --rollback
```

---

**Created**: 2025-10-29
**Feature**: 048-multi-monitor-headless
**Phase**: User Story 1 - MVP Verification
