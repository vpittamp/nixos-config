# Quickstart Guide: Event-Driven Workspace Mode Navigation

**Feature**: Event-Driven Workspace Mode Navigation
**Branch**: 042-event-driven-workspace-mode
**Status**: Planning Complete, Implementation Pending

## Overview

Fast workspace navigation via keyboard-driven digit input. Navigate to any workspace (1-70) by entering mode, typing digits, and pressing Enter. Replaces slow bash scripts with event-driven Python daemon for <20ms latency.

## Quick Reference

### Essential Keybindings

| Action | M1 MacBook Pro | Hetzner Cloud | Fallback (All Platforms) |
|--------|----------------|---------------|--------------------------|
| **Navigate to workspace** | `CapsLock` | `Ctrl+0` | `Mod+;` |
| **Move window to workspace** | `Shift+CapsLock` | `Ctrl+Shift+0` | `Mod+Shift+;` |
| **Cancel mode** | `Escape` | `Escape` | `Ctrl+C` or `Ctrl+G` |

### Common Workflows

**Navigate to workspace 23**:
```
1. Press CapsLock (M1) or Ctrl+0 (Hetzner)
2. Type: 2 3
3. Press Enter
→ Focus switches to workspace 23 on correct monitor
```

**Move window to workspace 5**:
```
1. Focus window you want to move
2. Press Shift+CapsLock (M1) or Ctrl+Shift+0 (Hetzner)
3. Type: 5
4. Press Enter
→ Window moves to workspace 5, you follow it there
```

**Cancel without action**:
```
1. Enter workspace mode (CapsLock)
2. Type some digits (optional)
3. Press Escape
→ Mode exits, no workspace change
```

---

## How It Works

### Visual Feedback

**Status Bar Display** (i3bar block):
- Mode inactive: ` ` (empty)
- Mode active, no digits: `WS: _`
- Mode active, digits typed: `WS: 23`

**Native Mode Indicator** (Swaybar binding_mode):
- Goto mode: `→ WS` (green)
- Move mode: `⇒ WS` (blue)

### Digit Accumulation Logic

- Leading zeros ignored: `0` + `5` = `5` (not `05`)
- Empty execution: Pressing Enter without digits exits mode (no-op)
- Multi-digit workspaces: Type all digits sequentially (`2` `3` for workspace 23)

### Multi-Monitor Output Focusing

Workspaces automatically focus the correct monitor based on workspace number:

| Workspace | Monitor (M1) | Monitor (Hetzner 3-display) |
|-----------|--------------|---------------------------|
| 1-2 | eDP-1 (built-in) | HEADLESS-1 (PRIMARY) |
| 3-5 | eDP-1 (built-in) | HEADLESS-2 (SECONDARY) |
| 6+ | eDP-1 (built-in) | HEADLESS-3 (TERTIARY) |

**Adaptive Behavior**:
- 1 monitor: All workspaces on same display (no errors)
- 2 monitors: WS 1-2 on primary, WS 3+ on secondary
- 3+ monitors: Distribution as shown above

---

## CLI Commands

### Workspace Mode State

```bash
# Query current mode state
i3pm workspace-mode state

# Output (mode active):
Active: true
Mode: goto
Digits: 23
Entered: 2025-10-31 12:34:56

# Output (mode inactive):
Active: false
```

**JSON output**:
```bash
i3pm workspace-mode state --json
```
```json
{
  "active": true,
  "mode_type": "goto",
  "accumulated_digits": "23",
  "entered_at": 1698768000.0,
  "output_cache": {
    "PRIMARY": "eDP-1",
    "SECONDARY": "eDP-1",
    "TERTIARY": "eDP-1"
  }
}
```

### Navigation History

```bash
# View last 10 workspace switches
i3pm workspace-mode history --limit 10

# Output:
WS   Output          Time                Mode
23   HEADLESS-2      2025-10-31 12:35:10 goto
5    HEADLESS-1      2025-10-31 12:34:45 move
12   HEADLESS-2      2025-10-31 12:33:20 goto
```

**JSON output**:
```bash
i3pm workspace-mode history --json
```
```json
{
  "history": [
    {
      "workspace": 23,
      "output": "HEADLESS-2",
      "timestamp": 1698768910.123,
      "mode_type": "goto"
    },
    {
      "workspace": 5,
      "output": "HEADLESS-1",
      "timestamp": 1698768885.456,
      "mode_type": "move"
    }
  ],
  "total": 42
}
```

### Manual IPC Commands

**For debugging or scripting**:

```bash
# Add digit (requires mode active)
i3pm workspace-mode digit 2

# Execute workspace switch
i3pm workspace-mode execute

# Cancel mode
i3pm workspace-mode cancel
```

---

## Daemon Management

### Check Daemon Status

```bash
# Verify daemon is running
systemctl --user status i3-project-event-listener

# Check if workspace mode handler is loaded
i3pm daemon status | grep -i workspace
```

### View Daemon Logs

```bash
# Real-time logs
journalctl --user -u i3-project-event-listener -f

# Filter for workspace mode events
journalctl --user -u i3-project-event-listener | grep workspace_mode
```

### Restart Daemon

```bash
# Restart daemon (clears workspace mode state and history)
systemctl --user restart i3-project-event-listener

# Verify restart successful
i3pm daemon status
```

---

## Troubleshooting

### Mode doesn't activate when pressing CapsLock (M1)

**Symptoms**: Pressing CapsLock does nothing, no mode indicator appears

**Diagnosis**:
```bash
# Check if keyd is running (required for CapsLock remap)
systemctl status keyd

# Verify CapsLock is remapped to F13
sudo keyd -m  # Press CapsLock, should show "f13"
```

**Solution**:
```bash
# Restart keyd service
sudo systemctl restart keyd

# Verify Sway config has F13 binding
grep "bindcode 191" ~/.config/sway/config.d/workspace-modes.conf
```

---

### Mode activates but digits don't accumulate

**Symptoms**: Mode indicator appears, but status bar doesn't show digits

**Diagnosis**:
```bash
# Check daemon received digit command
journalctl --user -u i3-project-event-listener -n 50 | grep "workspace_mode.digit"

# Manually test IPC
echo '{"jsonrpc":"2.0","method":"workspace_mode.digit","params":{"digit":"2"},"id":1}' | \
  socat - UNIX-CONNECT:$HOME/.local/state/i3-project-daemon.sock
```

**Solution**:
```bash
# Restart daemon
systemctl --user restart i3-project-event-listener

# Verify Sway bindings call correct CLI command
swaymsg -t get_binding_state
```

---

### Workspace switch goes to wrong monitor

**Symptoms**: Workspace appears but on wrong output

**Diagnosis**:
```bash
# Check output cache
i3pm workspace-mode state --json | jq '.output_cache'

# Verify actual outputs
swaymsg -t get_outputs | jq '.[] | {name, active}'
```

**Solution**:
```bash
# Refresh output cache by entering mode again
# CapsLock (enter mode) → Escape (exit mode)

# Or manually reassign monitors
i3pm monitors reassign
```

---

### Status bar doesn't update

**Symptoms**: Mode activates but status bar block stays empty

**Diagnosis**:
```bash
# Check if status bar script is subscribed to daemon events
ps aux | grep workspace_mode_block.py

# Check daemon event broadcasting
i3pm daemon events --follow --type=workspace_mode
```

**Solution**:
```bash
# Restart i3bar (reload Sway config)
swaymsg reload

# Or restart daemon to clear subscriptions
systemctl --user restart i3-project-event-listener
```

---

### Leading zero accepted instead of ignored

**Symptoms**: Typing `0` `5` results in workspace "05" instead of "5"

**Diagnosis**:
```bash
# Check daemon logs for digit accumulation
journalctl --user -u i3-project-event-listener | grep "add_digit.*0"

# Verify accumulated digits
i3pm workspace-mode state
```

**Solution**: Bug in digit accumulation logic - report issue. Expected behavior: leading `0` should be ignored.

---

### History is empty after many switches

**Symptoms**: `i3pm workspace-mode history` shows no entries despite recent switches

**Diagnosis**:
```bash
# Check if daemon restarted recently (clears in-memory history)
systemctl --user status i3-project-event-listener | grep "Active:"

# Check if switches are being recorded
journalctl --user -u i3-project-event-listener | grep "Recorded workspace switch"
```

**Solution**: History is in-memory only, cleared on daemon restart. This is expected behavior.

---

## Performance Monitoring

### Measure Latency

**Digit accumulation latency**:
```bash
# Time from keypress to status bar update
# Target: <10ms

# Manual test: Enter mode, type digit, observe status bar lag
# Use phone stopwatch video recording at 240fps to measure precisely
```

**Workspace switch latency**:
```bash
# Time from Enter keypress to focus change
# Target: <20ms

# Manual test: Enter mode, type digits, press Enter, observe focus change
# Should feel instant (no perceptible lag)
```

**End-to-end navigation latency**:
```bash
# Time from mode entry to final focus
# Target: <100ms total

# Includes:
# - Mode entry: ~5ms
# - Digit accumulation (2 digits): ~20ms (2 x 10ms)
# - Execute: ~20ms
# - Mode exit: ~5ms
# Total: ~50ms (well under 100ms target)
```

### Stress Testing

**Rapid workspace switches**:
```bash
# Perform 50 switches in 1 minute
# Expected: No lag, no state corruption, no missed events

# Automated stress test (if implemented):
i3pm workspace-mode stress-test --count 50 --duration 60
```

---

## Advanced Usage

### Scripting with IPC

**Custom launcher integration**:
```python
#!/usr/bin/env python3
"""Custom workspace launcher with fuzzy search."""
import asyncio
import json
from pathlib import Path

async def goto_workspace(workspace_num):
    """Navigate to workspace via daemon IPC."""
    socket_path = Path.home() / ".local" / "state" / "i3-project-daemon.sock"

    reader, writer = await asyncio.open_unix_connection(str(socket_path))

    # Simulate mode entry
    request = {
        "jsonrpc": "2.0",
        "method": "workspace_mode.digit",
        "params": {"digit": str(workspace_num)[0]},
        "id": 1
    }
    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    # Add remaining digits
    for digit in str(workspace_num)[1:]:
        request["id"] += 1
        request["params"]["digit"] = digit
        writer.write(json.dumps(request).encode() + b"\n")
        await writer.drain()

    # Execute switch
    request = {
        "jsonrpc": "2.0",
        "method": "workspace_mode.execute",
        "params": {},
        "id": 100
    }
    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    writer.close()
    await writer.wait_closed()

# Usage
asyncio.run(goto_workspace(23))
```

### Analytics with History

**Find most-used workspaces**:
```bash
# Query history and aggregate
i3pm workspace-mode history --json | \
  jq '.history | group_by(.workspace) | map({workspace: .[0].workspace, count: length}) | sort_by(.count) | reverse'
```

**Output**:
```json
[
  {"workspace": 1, "count": 45},
  {"workspace": 5, "count": 32},
  {"workspace": 23, "count": 18},
  {"workspace": 3, "count": 12}
]
```

### Custom Mode Indicator Styling

**Edit Sway bar config** (home-modules/desktop/sway/):
```nix
xdg.configFile."sway/config.d/bar-mode-indicator.conf".text = ''
  bar {
    colors {
      binding_mode {
        background #1e1e2e  # Darker background
        border #f9e2af      # Yellow border for visibility
        text #cdd6f4        # Light text
      }
    }
  }
'';
```

---

## Future Enhancements

### Potential Features (Not in Current Scope)

1. **Recent workspace shortcuts**:
   - `Alt+Tab` equivalent for workspaces
   - Jump to 3 most recent workspaces

2. **Workspace name search**:
   - Fuzzy search workspace names instead of numbers
   - Integration with walker launcher

3. **Backspace support**:
   - Remove last digit during accumulation
   - Requires additional IPC method: `workspace_mode.backspace`

4. **Persistent history**:
   - Save workspace switch history to file
   - Analyze patterns across daemon restarts

5. **Smart workspace suggestions**:
   - ML-based predictions from navigation patterns
   - Time-based workspace recommendations

6. **Relative navigation**:
   - `hjkl` keys for previous/next workspace
   - Circular workspace rotation

---

## Architecture Notes

### Event Flow

```
User Input (Keyboard)
  ↓
Sway (Window Manager)
  ↓ mode event / exec i3pm command
i3pm CLI Tool
  ↓ JSON-RPC over UNIX socket
i3pm Daemon (WorkspaceModeManager)
  ↓ i3 IPC commands
Sway (Workspace Switch)
  ↓ event broadcast
Status Bar Scripts (i3bar)
```

### Data Flow

```
WorkspaceModeState (in-memory singleton)
  ├─ active: bool
  ├─ mode_type: "goto" | "move"
  ├─ accumulated_digits: str
  ├─ entered_at: timestamp
  └─ output_cache: PRIMARY/SECONDARY/TERTIARY → output names

WorkspaceHistory (circular buffer, max 100)
  └─ List[WorkspaceSwitch]
       ├─ workspace: int
       ├─ output: str
       ├─ timestamp: float
       └─ mode_type: str

WorkspaceModeEvent (broadcast payload)
  ├─ mode_active: bool
  ├─ mode_type: "goto" | "move" | null
  ├─ accumulated_digits: str
  └─ timestamp: float
```

---

## Summary

Workspace mode navigation provides:

✅ **Fast**: <20ms workspace switch (down from 70ms with bash)
✅ **Flexible**: Any workspace 1-70, not limited to 1-10
✅ **Visual**: Real-time feedback in status bar and mode indicator
✅ **Smart**: Automatic output focusing based on workspace number
✅ **Reliable**: Event-driven daemon with in-memory state

**Key Takeaway**: Press CapsLock/Ctrl+0, type digits, press Enter. Fast workspace navigation with zero configuration.
