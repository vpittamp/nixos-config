# Quickstart: Tree Monitor Inspect Command

**Feature**: 066-inspect-daemon-fix
**Date**: 2025-11-08
**Audience**: End users, system administrators, developers debugging window state changes

---

## Overview

The `i3pm tree-monitor inspect` command retrieves detailed information about a specific event from the daemon's circular buffer. It answers questions like:

- What changed when I pressed this key?
- Why did this window appear/disappear?
- What was my terminal's state at this moment?

This is a companion to `i3pm tree-monitor history` (browse multiple events) and `i3pm tree-monitor live` (watch events in real-time).

---

## Installation

The tree monitor daemon and CLI are included with Feature 065. Ensure they're enabled:

```bash
# Check daemon status
systemctl --user status sway-tree-monitor

# Start daemon if needed
systemctl --user start sway-tree-monitor

# Enable to auto-start on login
systemctl --user enable sway-tree-monitor
```

## Basic Usage

### Inspect a Single Event

```bash
# Get event #15 with default options
i3pm tree-monitor inspect 15

# Get event #42 with full snapshots
i3pm tree-monitor inspect 42 --snapshots

# Get event #99 as JSON
i3pm tree-monitor inspect 99 --json
```

### Command Syntax

```
i3pm tree-monitor inspect <event-id> [OPTIONS]

Arguments:
  event-id              Event ID to inspect (integer or string)

Options:
  --snapshots           Include full before/after tree snapshots (large payloads)
  --no-enrichment       Exclude I3PM enrichment data (PIDs, env vars, marks)
  --json                Output as JSON instead of formatted text
  --raw                 Raw RPC response (for debugging)
  --socket <path>       Custom socket path (default: $XDG_RUNTIME_DIR/sway-tree-monitor.sock)
  --help                Show this help message
```

---

## Example Outputs

### Formatted Output (Default)

```
============================================================
Event Metadata
============================================================
ID:           15
Timestamp:    2025-11-08 14:23:45 (2 seconds ago)
Type:         window::new
Changes:      3
Significance: high (0.85)

============================================================
User Action Correlation
============================================================
Action Type:     binding
Binding Command: exec --no-startup-id alacritty
Time Delta:      67 ms
Confidence:      Very Likely (95%)
Reasoning:       Temporal proximity (67ms) + semantic match (exec command triggers window::new)

============================================================
Field-Level Changes (Diff)
============================================================

Modified Fields (1):
  focused:
    false → true
    Significance: 0.80

Added Fields (2):
  rect:
    null → {x: 100, y: 200, width: 800, height: 600}
    Significance: 0.95
  name:
    null → "Alacritty"
    Significance: 1.00

============================================================
I3PM Enrichment
============================================================
Process ID: 12345

Environment Variables:
  I3PM_APP_ID:       alacritty
  I3PM_APP_NAME:     Terminal
  I3PM_PROJECT_NAME: nixos
  I3PM_SCOPE:        scoped
  I3PM_LAUNCH_CONTEXT: {"method": "keybinding", "timestamp": 1699441234400}

Window Marks: project:nixos, app:alacritty

Launch Context:
  Method:    keybinding
  Timestamp: 2025-11-08 14:23:45

============================================================
```

### JSON Output

```bash
$ i3pm tree-monitor inspect 15 --json
```

```json
{
  "event_id": 15,
  "timestamp_ms": 1699441234567,
  "event_type": "window::new",
  "sway_change": "new",
  "container_id": 6442450944,
  "diff": {
    "diff_id": 14,
    "before_snapshot_id": 13,
    "after_snapshot_id": 15,
    "total_changes": 3,
    "significance_score": 0.85,
    "significance_level": "high",
    "computation_time_ms": 2.34,
    "node_changes": [
      {
        "node_id": "6442450944",
        "node_type": "con",
        "node_path": "outputs[0].workspaces[1].nodes[2]",
        "change_type": "added",
        "field_changes": [
          {
            "field_path": "name",
            "old_value": null,
            "new_value": "Alacritty",
            "change_type": "added",
            "significance_score": 1.0
          },
          {
            "field_path": "rect",
            "old_value": null,
            "new_value": {"x": 100, "y": 200, "width": 800, "height": 600},
            "change_type": "added",
            "significance_score": 0.95
          }
        ]
      }
    ]
  },
  "correlations": [
    {
      "action": {
        "timestamp_ms": 1699441234500,
        "action_type": "binding",
        "binding_command": "exec --no-startup-id alacritty",
        "input_type": "keybinding"
      },
      "confidence": 0.95,
      "confidence_level": "VeryLikely",
      "time_delta_ms": 67,
      "reasoning": "Temporal proximity (67ms) + semantic match (exec command triggers window::new)"
    }
  ],
  "enrichment": {
    "6442450944": {
      "window_id": 6442450944,
      "pid": 12345,
      "i3pm_app_id": "alacritty",
      "i3pm_app_name": "Terminal",
      "i3pm_project_name": "nixos",
      "i3pm_scope": "scoped",
      "project_marks": ["project:nixos"],
      "app_marks": ["app:alacritty"],
      "launch_timestamp_ms": 1699441234400,
      "launch_action": "Key: Mod4+Return"
    }
  }
}
```

---

## Common Tasks

### Find Event IDs to Inspect

Use `history` command to find events:

```bash
# Show last 10 events with IDs
i3pm tree-monitor history --last 10

# Show events from last hour
i3pm tree-monitor history --since 1h

# Filter by event type
i3pm tree-monitor history --filter window::new

# Show high-significance events
i3pm tree-monitor history --significance high
```

### Inspect the Most Recent Event

```bash
# Get latest event ID from history
LATEST=$(i3pm tree-monitor history --last 1 --json | jq '.events[0].event_id')
i3pm tree-monitor inspect $LATEST
```

### Extract Window Information

```bash
# Get all windows that changed in event #25
i3pm tree-monitor inspect 25 --json | jq '.enrichment | keys'

# Get process IDs for all changed windows
i3pm tree-monitor inspect 25 --json | jq '.enrichment | to_entries[] | "\(.key): PID \(.value.pid)"'

# Find events for specific app
i3pm tree-monitor history --json | jq '.events[] | select(.container_id == 6442450944)'
```

### Debug Event Correlation

```bash
# See what action triggered an event
i3pm tree-monitor inspect 50 --json | jq '.correlations[0] | {action_type, confidence, time_delta_ms, reasoning}'

# Find events with high confidence correlation
i3pm tree-monitor history --json | jq '.events[] | select(.correlations[0].confidence > 0.9)'
```

### Monitor Buffer Health

```bash
# Check daemon status
i3pm tree-monitor stats

# Get buffer info
i3pm tree-monitor stats --json | jq '.buffer'

# See performance metrics
i3pm tree-monitor stats --json | jq '.performance'
```

---

## Understanding the Output

### Significance Score

Indicates how important the change is (0.0 = minimal, 1.0 = critical).

| Score | Level | Meaning | Examples |
|-------|-------|---------|----------|
| 1.0 | Critical | Major structural change | Window added/removed, workspace created |
| 0.75 | High | Important state change | Focus change, app switch |
| 0.5 | Medium | Noticeable change | Window move (>10px) |
| 0.25 | Low | Minor change | Small geometry adjustment (<10px) |
| 0.0 | Minimal | No user-visible change | Internal state update |

### Confidence Score

How confident the daemon is that a user action caused the tree change (0.0 = unlikely, 1.0 = very likely).

| Score | Label | Interpretation |
|-------|-------|-----------------|
| >0.90 | Very Likely (green) | Action definitely caused this change |
| 0.70-0.90 | Likely (yellow) | Action probably caused this change |
| 0.50-0.70 | Possible (orange) | Action might have caused this change |
| <0.50 | Unlikely (red) | Action probably didn't cause this change |

**Factors considered**:
- Time between action and change (temporal proximity)
- Type of action vs type of change (semantic matching)
- Competing actions in similar timeframe (exclusivity)
- Position in cascade of effects (cascade level)

### Field-Level Changes

Shows exactly what changed in the tree structure.

```
path:           JSONPath to the changed field
old_value:      Previous value (null for additions)
new_value:      New value (null for removals)
change_type:    added, removed, or modified
significance:   How important this field is
```

### Enrichment Data

Shows I3PM context extracted from process environment and window marks.

| Field | Meaning |
|-------|---------|
| `i3pm_app_id` | Application identifier from registry |
| `i3pm_app_name` | Human-readable app name |
| `i3pm_project_name` | Project this window is scoped to |
| `i3pm_scope` | "scoped" (project-specific) or "global" (all projects) |
| `project_marks` | Sway marks like `project:nixos` |
| `app_marks` | Sway marks like `app:firefox` |
| `launch_context` | How and when this window was created |

---

## Troubleshooting

### "Daemon not running" Error

```
Error: Socket not found at /run/user/1000/sway-tree-monitor.sock
```

**Solution**:
```bash
# Start the daemon
systemctl --user start sway-tree-monitor

# Check if it started
systemctl --user status sway-tree-monitor

# Enable auto-start
systemctl --user enable sway-tree-monitor
```

### "Event not found" Error

```
Error: Event ID 999 does not exist in buffer
```

**Solution**:
- Event IDs range from 0-499 in circular buffer
- When buffer is full, oldest events are overwritten
- Use `i3pm tree-monitor history --last 1` to find valid event IDs

```bash
# Find valid event range
i3pm tree-monitor history --last 50 --json | jq '.events | {min_id: min_by(.event_id).event_id, max_id: max_by(.event_id).event_id}'
```

### "Invalid event_id" Error

```
Error: Invalid event_id: must be an integer or numeric string, got "abc"
```

**Solution**:
- Event ID must be a number
- Valid: `i3pm tree-monitor inspect 15`
- Invalid: `i3pm tree-monitor inspect abc`

### Type Conversion Issues

The daemon accepts both string and integer event IDs:

```bash
# All these work the same
i3pm tree-monitor inspect 15
i3pm tree-monitor inspect "15"
curl -X POST /run/user/1000/sway-tree-monitor.sock -d '{"jsonrpc":"2.0","method":"get_event","params":{"event_id":"15"},"id":1}'
curl -X POST /run/user/1000/sway-tree-monitor.sock -d '{"jsonrpc":"2.0","method":"get_event","params":{"event_id":15},"id":1}'
```

The conversion happens server-side in Python:
```python
try:
    event_id = int(event_id)  # Converts "15" -> 15
except (ValueError, TypeError):
    raise ValueError(f"Invalid event_id: ...")
```

### Socket Permission Denied

```
Error: Permission denied opening socket /run/user/1000/sway-tree-monitor.sock
```

**Solution**:
- Socket should be owned by your user with mode 0600
- Restart daemon to fix permissions

```bash
systemctl --user restart sway-tree-monitor
ls -la /run/user/1000/sway-tree-monitor.sock  # Should show -rw-------
```

### Large Output Truncated

The `--snapshots` flag includes full tree JSON (5-10 KB), which can be large:

```bash
# Pipe to jq for filtering
i3pm tree-monitor inspect 15 --snapshots --json | jq '.snapshots.after'

# Save to file
i3pm tree-monitor inspect 15 --snapshots --json > event-15.json

# Pretty-print with pagination
i3pm tree-monitor inspect 15 --snapshots --json | jq . | less
```

---

## Advanced Usage

### RPC Protocol Interaction

For integration or debugging, you can communicate directly with the daemon:

```bash
# Using socat to connect to socket
socat - UNIX-CONNECT:/run/user/1000/sway-tree-monitor.sock

# Type JSON-RPC request (single line, then Enter):
{"jsonrpc":"2.0","method":"get_event","params":{"event_id":"15"},"id":1}

# Response appears immediately (newline-delimited JSON)
```

### Batch Processing

```bash
# Inspect multiple events
for id in {0..9}; do
  echo "=== Event $id ==="
  i3pm tree-monitor inspect $id --json | jq '.event_id, .event_type, .diff.significance_level'
done

# Find all window::new events with high confidence
i3pm tree-monitor history --json | jq '
  .events[] |
  select(.event_type == "window::new") |
  select(.correlations[0].confidence > 0.7) |
  {id: .event_id, timestamp: .timestamp_ms, confidence: .correlations[0].confidence}
'
```

### Integration with Scripts

```bash
#!/bin/bash
# Extract specific event data for analysis

EVENT_ID=$1
i3pm tree-monitor inspect "$EVENT_ID" --json | jq '{
  id: .event_id,
  time: .timestamp_ms,
  type: .event_type,
  changes: .diff.total_changes,
  significance: .diff.significance_level,
  correlated_action: .correlations[0].action.binding_command,
  confidence: (.correlations[0].confidence * 100 | round),
  windows: (.enrichment | keys)
}'
```

### Daemon Statistics

```bash
# View buffer stats
i3pm tree-monitor stats --json

# Monitor performance over time
watch 'i3pm tree-monitor stats --json | jq ".performance"'

# Find slowest diff computations
i3pm tree-monitor history --json | jq '
  .events[] |
  {id: .event_id, computation_ms: .diff.computation_time_ms} |
  sort_by(.computation_ms) |
  reverse |
  .[0:5]
'
```

---

## Performance Characteristics

### Response Times

Typical latencies for `inspect` command:

| Operation | Time |
|-----------|------|
| CLI startup | <10ms |
| Socket connect | <1ms |
| Buffer lookup | <1ms |
| Type conversion | <0.1ms |
| JSON serialization | 0.5-1ms |
| RPC transmission | 0.2-0.5ms |
| **Total (without snapshots)** | **2-3ms** |
| **Total (with snapshots)** | **3-5ms** |

### Memory Usage

- Event in buffer: ~5 KB
- RPC response: 1-2 KB (without snapshots), 10-15 KB (with snapshots)
- Daemon overhead: ~15 MB base

---

## Related Commands

```bash
# See tree monitor commands
i3pm tree-monitor --help

# Browse events interactively
i3pm tree-monitor history

# Watch events in real-time
i3pm tree-monitor live

# Get performance statistics
i3pm tree-monitor stats

# Monitor daemon health
systemctl --user status sway-tree-monitor

# View daemon logs
journalctl --user -u sway-tree-monitor -f
```

---

## Integration with Other Tools

### Using with jq (JSON Query)

```bash
# Extract correlation details
i3pm tree-monitor inspect 15 --json | jq '.correlations[]'

# Filter events by significance
i3pm tree-monitor history --json | jq '.events[] | select(.diff.significance_level == "high")'

# Build timeline of window changes
i3pm tree-monitor history --json | jq '.events[] | {id, time: .timestamp_ms, windows_changed: .diff.total_changes}'
```

### Using with ripgrep (for log analysis)

```bash
# Find events matching pattern in history
i3pm tree-monitor history --json | jq '.events[] | select(.event_type | test("window"))'

# Analyze event type distribution
i3pm tree-monitor history --json | jq '.events[] | .event_type' | sort | uniq -c
```

### Using with Sway IPC

Combine with `swaymsg` for cross-referencing:

```bash
# Get current window ID
CURRENT_WID=$(swaymsg -t get_tree | jq '..|objects|select(.focused==true).id')

# Find events for this window
i3pm tree-monitor history --json | jq --arg wid "$CURRENT_WID" '
  .events[] |
  select(.container_id == ($wid | tonumber))
'
```

---

## File Locations

| Component | Path |
|-----------|------|
| RPC Socket | `$XDG_RUNTIME_DIR/sway-tree-monitor.sock` |
| Daemon Binary | `/nix/store/.../sway-tree-monitor/daemon.py` |
| CLI Binary | `/nix/store/.../i3pm` |
| Systemd Service | `~/.config/systemd/user/sway-tree-monitor.service` |
| Daemon Logs | `journalctl --user -u sway-tree-monitor` |

---

## See Also

- **Feature 065**: Full tree monitor documentation - `specs/065-i3pm-tree-monitor/quickstart.md`
- **Data Model**: RPC schemas and types - `specs/066-inspect-daemon-fix/data-model.md`
- **RPC Protocol**: JSON-RPC 2.0 contract - `specs/066-inspect-daemon-fix/contracts/rpc-protocol.json`
- **Sway IPC**: `man sway-ipc` (window events, tree structure)
- **i3pm Documentation**: `i3pm --help`, `i3pm tree-monitor --help`
