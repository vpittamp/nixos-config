# Sway Tree Diff Monitor - Troubleshooting Guide

## Event Emission Failure (2025-11-07)

### Symptoms
- Daemon starts successfully without errors
- No events appear in daemon logs despite window creation
- Direct `swaymsg -t subscribe` receives no events
- Affects ALL IPC subscribers system-wide (not daemon-specific)

### Root Cause
Sway compositor's IPC event subsystem stopped broadcasting events after extended uptime. This appears to be a rare Sway bug where the event emission mechanism becomes broken, requiring a full compositor restart.

### Investigation Process
1. ✅ Verified daemon package contains all bug fixes
2. ✅ Confirmed EventCorrelation constructor fix is deployed
3. ✅ Created minimal i3ipc.aio test script - no events received
4. ✅ Tested direct `swaymsg -t subscribe` - no events received
5. ✅ Killed zombie `swaymsg subscribe` processes
6. ❌ Attempted `swaymsg reload` - didn't fix event emission
7. ✅ Identified need for full Sway restart

### Resolution
**Full Sway compositor restart required:**

```bash
# Exit Sway cleanly (will disconnect VNC)
swaymsg exit

# System should auto-restart Sway via login manager
# All systemd user services restart automatically via sway-session.target
```

**Post-Restart Verification:**
```bash
# Test 1: Direct subscription
swaymsg -t subscribe '["window"]' &
sub_pid=$!
sleep 1
swaymsg exec "alacritty -e echo test"
sleep 2
kill $sub_pid

# Test 2: Daemon event capture
sway-tree-monitor history --last 5
```

### Key Learnings
- `swaymsg reload` does NOT fix IPC event emission issues
- Full compositor restart is required (not just daemon restart)
- On headless Sway: use `swaymsg exit` (NOT `systemctl restart sway`)
- Sway is managed via `sway-session.target`, not a direct systemd service

### Prevention
- Monitor for extended Sway uptime (>24h)
- Consider periodic Sway restarts for headless servers
- Watch for zombie `swaymsg subscribe` processes

### Related Files
- `/etc/nixos/home-modules/desktop/sway.nix` - Sway session configuration
- `/etc/nixos/home-modules/tools/sway-tree-monitor/daemon.py` - Event subscription
- `/etc/nixos/home-modules/tools/sway-tree-monitor/correlation/tracker.py` - EventCorrelation fix

### Timeline
- 2025-11-06: Fixed all 6 critical bugs, rebuilt system
- 2025-11-06: Daemon starts successfully, no events captured
- 2025-11-07: Diagnosed IPC event emission failure, identified restart requirement
