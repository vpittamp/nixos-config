# Quickstart: i3pm Tree Monitor

**Real-time window state monitoring integrated into i3pm CLI**

Monitor Sway window/workspace state changes with live streaming, historical queries, and detailed event inspection. All monitoring logic runs in the `sway-tree-monitor` daemon - the i3pm CLI is a fast, user-friendly client.

---

## Prerequisites

1. **Daemon running**: `systemctl --user status sway-tree-monitor`
   - If not running: `systemctl --user start sway-tree-monitor`
2. **Sway compositor**: Must be running (Wayland/i3-compatible)
3. **i3pm CLI**: Installed via NixOS configuration

---

## Quick Commands

### Live Event Streaming

Watch window state changes in real-time:

```bash
i3pm tree-monitor live
```

**Features**:
- Full-screen TUI with event table
- Updates within 100ms of window operations
- Color-coded event types and confidence indicators
- Keyboard shortcuts: `q` (quit), `↑`/`↓` (navigate), `Enter` (inspect), `r` (refresh)

**Example**:
```
┌─────────────────────────────────── Tree Monitor (Live) ───────────────────────────────────┐
│ ID    Timestamp       Type              Changes              Triggered By          Conf   │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│ 0     22:04:53.674    workspace::focus  2 changes (critical)  Binding: workspace 2  🟢    │
│ 1     22:05:08.951    window::new       3 changes (critical)  Binding: exec ghosh   🟢    │
│ 2     22:05:08.952    window::focus     0 changes (minimal)   (no correlation)      —     │
└────────────────────────────────────────────────────────────────────────────────────────────┘
Confidence: 🟢 Very Likely | 🟡 Likely | 🟠 Possible | 🔴 Unlikely | ⚫ Very Unlikely
```

---

### Historical Query

Query past events with flexible filters:

```bash
# Last 10 events
i3pm tree-monitor history --last 10

# Events from last 5 minutes
i3pm tree-monitor history --since 5m

# Only window creation events
i3pm tree-monitor history --filter window::new

# All window events from last hour (combined)
i3pm tree-monitor history --since 1h --filter window::

# Machine-readable JSON output
i3pm tree-monitor history --last 50 --json
```

**Time Formats**: `5m` (5 minutes), `1h` (1 hour), `30s` (30 seconds), `2d` (2 days)

**Event Type Filters**:
- Exact: `window::new`, `window::focus`, `workspace::focus`
- Prefix: `window::` (all window events), `workspace::` (all workspace events)

**Output**:
```
ID  Timestamp       Type              Changes               Triggered By          Conf
──  ──────────────  ────────────────  ────────────────────  ────────────────────  ────
0   22:04:53.674    workspace::focus  2 changes (critical)  Binding: workspace 2  🟢
1   22:05:08.951    window::new       3 changes (critical)  Binding: exec ghosh   🟢
2   22:05:08.952    window::focus     0 changes (minimal)   (no correlation)      —
```

---

### Detailed Event Inspection

Inspect individual events with field-level diff and I3PM enrichment:

```bash
i3pm tree-monitor inspect <event-id>
```

**Example**:
```
Event: 550e8400-e29b-41d4-a716-446655440001
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Metadata:
  ID:           550e8400-e29b-41d4-a716-446655440001
  Timestamp:    2025-11-08 22:05:08.951
  Type:         window::new
  Significance: critical (0.92)

Correlation:
  Action:      Binding
  Command:     exec alacritty
  Time Delta:  150ms
  Confidence:  🟢 95% (Very Likely)
  Reasoning:   Window appeared 150ms after 'exec' binding

Field-Level Changes:
  app_id:      (none) → Alacritty                    [critical]
  focused:     false → true                           [high]
  geometry:    (none) → {width: 800, height: 600}    [moderate]

I3PM Enrichment:
  PID:         12345
  APP_NAME:    alacritty
  APP_ID:      alacritty-nixos-123-456
  PROJECT:     nixos
  SCOPE:       scoped
  Marks:       project:nixos, app:alacritty

Press 'b' to return | 'q' to quit
```

---

### Daemon Statistics

Monitor daemon performance and health:

```bash
i3pm tree-monitor stats
```

**Output**:
```
Daemon Statistics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Performance:
  Memory:      12.5 MB
  CPU:         0.8%
  Uptime:      1h 30m

Event Buffer:
  Current:     342 events
  Capacity:    500 events
  Utilization: 68.4%

Event Distribution:
  window::new       45
  window::focus     120
  window::close     38
  workspace::focus  23

Diff Computation:
  Avg Time:    1.2ms
  Max Time:    4.5ms
  Total:       342 diffs

Last Updated: 2025-11-08 22:10:00
```

**Watch Mode** (refresh every 5 seconds):
```bash
i3pm tree-monitor stats --watch
```

---

## Common Workflows

### Debug Window Focus Issues

```bash
# Live view to see focus events in real-time
i3pm tree-monitor live

# Then perform window operations and observe events
# Press 'Enter' on suspicious event to inspect details
```

### Analyze Workspace Switching Patterns

```bash
# Query last hour of workspace events
i3pm tree-monitor history --since 1h --filter workspace::

# Export to JSON for analysis
i3pm tree-monitor history --since 1h --filter workspace:: --json > workspace-events.json
```

### Verify Project Switching

```bash
# Trigger project switch (in another terminal)
i3pm project switch nixos

# Check for window visibility changes (within 5 seconds)
i3pm tree-monitor history --since 5s
```

### Monitor Daemon Health

```bash
# Check if daemon is running and healthy
i3pm tree-monitor stats

# Watch resource usage over time
i3pm tree-monitor stats --watch
```

---

## Keyboard Shortcuts

### Live View
| Key | Action |
|-----|--------|
| `q` | Quit |
| `↑` / `↓` | Navigate events |
| `Enter` | Inspect event details |
| `r` | Refresh |
| `f` | Focus filter input |
| `/` | Search |

### History View
| Key | Action |
|-----|--------|
| `q` | Quit |
| `↑` / `↓` | Scroll events |
| `Enter` | Inspect event |
| `f` | Edit filter |
| `Esc` | Clear filter |

### Detail Inspection
| Key | Action |
|-----|--------|
| `q` | Quit |
| `b` | Back to previous view |

---

## Troubleshooting

### "Cannot connect to daemon"

**Cause**: Daemon not running or socket file missing

**Fix**:
```bash
# Check daemon status
systemctl --user status sway-tree-monitor

# Start daemon
systemctl --user start sway-tree-monitor

# Verify socket exists
ls -l $XDG_RUNTIME_DIR/sway-tree-monitor.sock
```

---

### "Request timeout after 5 seconds"

**Cause**: Daemon is running but not responding (hung/overloaded)

**Fix**:
```bash
# Restart daemon
systemctl --user restart sway-tree-monitor

# Check daemon logs for errors
journalctl --user -u sway-tree-monitor -f
```

---

### "No events found"

**Cause**: Buffer is empty or filters too restrictive

**Fix**:
```bash
# Check if any events exist
i3pm tree-monitor stats

# Remove filters
i3pm tree-monitor history --last 100

# Generate events by switching workspaces or opening windows
```

---

### "Permission denied" accessing socket

**Cause**: Socket permissions incorrect (should be 0600)

**Fix**:
```bash
# Check socket permissions
ls -l $XDG_RUNTIME_DIR/sway-tree-monitor.sock

# Should show: srw------- (owner read/write only)

# Restart daemon to recreate socket
systemctl --user restart sway-tree-monitor
```

---

## Performance Tips

### CLI Startup

- **Target**: <50ms (10x faster than Python TUI)
- **Measured**: Time from command to first output
- **Optimize**: Use compiled binary (`deno compile`), avoid unnecessary imports

### Live View Responsiveness

- **Target**: <100ms from Sway event to CLI display
- **Depends on**: Daemon event capture (<50ms) + RPC call (<2ms) + UI render (<50ms)
- **Smooth scrolling**: Throttled to 10 FPS (100ms) to prevent flicker

### Historical Queries

- **Target**: <500ms for 500 events
- **Depends on**: RPC call (<2ms) + deserialization (<10ms) + table formatting (<100ms)
- **Use filters**: Reduce result set for faster rendering

---

## Examples

### Monitor project-scoped window hiding

```bash
# Terminal 1: Live view
i3pm tree-monitor live

# Terminal 2: Switch projects
i3pm project switch myproject

# Observe in Terminal 1: scoped windows hide/show with marks
```

### Debug slow workspace switches

```bash
# Capture events during workspace switch
i3pm tree-monitor history --since 1s --after-workspace-switch

# Inspect each event to find delays
i3pm tree-monitor inspect <event-id>
```

### Export event data for analysis

```bash
# Get last 500 events as JSON
i3pm tree-monitor history --last 500 --json > events.json

# Analyze with jq
cat events.json | jq '.events[] | select(.type == "window::new") | .correlation'
```

---

## Advanced Usage

### Custom Socket Path

```bash
i3pm tree-monitor live --socket-path /custom/path/monitor.sock
```

### Combine Filters

```bash
# Window events from last 10 minutes
i3pm tree-monitor history --since 10m --filter window::
```

### Machine-Readable Output

```bash
# All commands support --json flag
i3pm tree-monitor history --last 10 --json
i3pm tree-monitor inspect <id> --json
i3pm tree-monitor stats --json
```

---

## Related Commands

- `i3pm windows --live` - Real-time window tree visualization
- `i3pm daemon events` - i3pm daemon event log
- `i3pm diagnose window <id>` - Window diagnostic info
- `journalctl --user -u sway-tree-monitor -f` - Daemon logs

---

## See Also

- Feature Spec: `/etc/nixos/specs/065-i3pm-tree-monitor/spec.md`
- Data Model: `/etc/nixos/specs/065-i3pm-tree-monitor/data-model.md`
- RPC Protocol: `/etc/nixos/specs/065-i3pm-tree-monitor/contracts/rpc-protocol.json`
- Research: `/etc/nixos/specs/065-i3pm-tree-monitor/research.md`

---

**Version**: 1.0.0 | **Date**: 2025-11-08 | **Status**: Implementation Pending
