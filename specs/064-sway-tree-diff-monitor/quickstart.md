# Quick Start: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Status**: Planning Complete - Ready for Implementation

## What is This?

The Sway Tree Diff Monitor provides real-time visibility into window management state changes in your Sway Wayland compositor. It tracks every window open, close, move, and focus change, correlates them with user actions (keypresses), and displays detailed diffs showing exactly what changed in the window tree.

**Use cases**:
- **Debug window management issues**: See exactly what's happening when windows disappear or move unexpectedly
- **Understand i3pm behavior**: Track how project switching affects window visibility
- **Monitor workspace assignment**: Verify PWAs are going to the correct workspaces
- **Performance analysis**: Measure diff computation and display latency

---

## Installation

### 1. Add Python Dependencies

Edit `/etc/nixos/home-modules/desktop/python-environment.nix`:

```nix
sharedPythonEnv = pkgs.python3.withPackages (ps: with ps; [
  # Existing packages
  i3ipc
  pydantic
  rich

  # New for Feature 052
  xxhash        # Fast tree hashing
  orjson        # 6x faster JSON
  textual       # TUI framework
]);
```

### 2. Rebuild System

```bash
sudo nixos-rebuild switch --flake .#hetzner-sway  # or .#m1
```

### 3. Start Daemon (After Implementation)

```bash
systemctl --user start sway-tree-monitor
systemctl --user enable sway-tree-monitor  # Auto-start on login
```

---

## Quick Commands

### Live Monitoring

Watch tree changes in real-time:

```bash
# Basic live monitoring
sway-tree-monitor live

# Only show window events
sway-tree-monitor live --filter=window

# Hide minor changes (< 0.5 significance)
sway-tree-monitor live --min-significance=0.5

# Disable user action correlation (faster)
sway-tree-monitor live --no-correlation
```

**Example output**:
```
┌──────────────┬────────────────┬────────────────────────────────────┬──────────────────┐
│ Time         │ Event          │ Change Summary                     │ Triggered By     │
├──────────────┼────────────────┼────────────────────────────────────┼──────────────────┤
│ 15:30:45.123 │ window::new    │ Firefox window added (WS 2)        │ Key: Mod4+Return │
│ 15:30:46.890 │ window::focus  │ Focus: Firefox ← Code              │ Click: (520,340) │
│ 15:30:48.234 │ workspace::foc │ Switched to workspace 3            │ Key: Mod4+3      │
└──────────────┴────────────────┴────────────────────────────────────┴──────────────────┘

Press 'f' to filter | 'd' to drill down | 'q' to quit
```

---

### Historical Query

View past events:

```bash
# Last 50 events (default)
sway-tree-monitor history

# Last 100 events
sway-tree-monitor history --last=100

# Events in last 5 minutes
sway-tree-monitor history --since=5m

# Only workspace changes
sway-tree-monitor history --filter=workspace

# Only user-initiated events
sway-tree-monitor history --user-initiated

# Export to JSON
sway-tree-monitor history --since=1h --format=json > events.json
```

---

### Detailed Inspection

Inspect detailed diff for a specific event:

```bash
# Show detailed diff for event #1234
sway-tree-monitor diff 1234

# Include full tree snapshots (verbose)
sway-tree-monitor diff 1234 --show-tree

# JSON output for scripting
sway-tree-monitor diff 1234 --format=json
```

**Example output**:
```
Event #1234: window::new (2024-11-07 15:30:45.123)

Triggered by: Key: Mod4+Return (confidence: 95%, 45ms)

Changes:
  outputs[0].workspaces[2].nodes
    ├─ ADDED: con#12345 (Firefox)
    │  ├─ window: 12345
    │  ├─ name: "Mozilla Firefox"
    │  ├─ app_id: null
    │  ├─ class: "Firefox"
    │  ├─ rect: {x: 0, y: 0, width: 1920, height: 1080}
    │  ├─ focused: true
    │  └─ [enriched]
    │     ├─ I3PM_PROJECT_NAME: "nixos"
    │     ├─ I3PM_APP_NAME: "firefox"
    │     └─ pid: 98765
    │
    └─ MODIFIED: con#12340 (Code)
       └─ focused: true → false

Computation time: 4.2ms
```

---

### Statistics

View event statistics:

```bash
# Stats for all buffered events
sway-tree-monitor stats

# Stats for last hour
sway-tree-monitor stats --since=1h
```

**Example output**:
```
Event Statistics (last 500 events, 2h 15m)
──────────────────────────────────────────

Event Type Distribution:
  window::focus      45% (225 events)
  window::move       20% (100 events)
  workspace::focus   18% (90 events)
  window::new        10% (50 events)
  window::close       7% (35 events)

Performance:
  Avg diff computation:  5.2ms (p50), 8.1ms (p95), 12.3ms (p99)
  Avg display latency:   42ms
  Total events:          500
  Events/minute:         3.7

Correlation:
  User-initiated:        412 (82%)
  High confidence (>90%): 380 (76%)
  No correlation:         88 (18%)
```

---

## Common Workflows

### Debug: Why did my window disappear?

```bash
# Start live monitoring
sway-tree-monitor live

# Perform action that causes issue
# (window disappears)

# Review recent history
sway-tree-monitor history --last=20

# Inspect suspicious event
sway-tree-monitor diff <event_id>
```

---

### Debug: PWA workspace assignment

```bash
# Watch for window::new events
sway-tree-monitor live --filter=window::new

# Launch PWA from walker (Mod+D)
# Verify it appears on correct workspace

# Check event details
sway-tree-monitor history --last=1
sway-tree-monitor diff <event_id>

# Look for workspace number in diff output
```

---

### Debug: i3pm project switch

```bash
# Start monitoring
sway-tree-monitor live

# Switch to project
i3pm project switch nixos

# Observe window hide/show events
# Should see:
#   - window::hidden events for scoped windows
#   - window::visible events for restored windows
```

---

### Performance Analysis

```bash
# Monitor diff computation performance
sway-tree-monitor stats

# Check p95/p99 latencies
# Should be < 10ms for 95% of events

# If latencies high, check window count
sway-tree-monitor history --last=1
# Look for large tree sizes in diff output
```

---

### Export for Post-Mortem Analysis

```bash
# Experience a bug but monitor wasn't running?
# Enable persistence first (see Configuration)

# After bug occurs, export recent events
sway-tree-monitor export ~/bug-report-$(date +%Y%m%d).json --since=10m

# Share file with bug report
# Import later for analysis:
sway-tree-monitor import ~/bug-report-20241107.json
sway-tree-monitor history --last=50
```

---

## Configuration

Optional config at `~/.config/sway-tree-monitor/config.toml`:

```toml
[monitor]
buffer_size = 500               # Event buffer size
refresh_rate = 10               # UI refresh rate (Hz)
min_significance = 0.1          # Filter low-significance changes

[correlation]
time_window_ms = 500            # User action correlation window
high_confidence = 0.90          # Confidence thresholds
medium_confidence = 0.70

[persistence]
enabled = true                  # Auto-save events to disk
dir = "~/.local/share/sway-tree-monitor"
retention_days = 7              # Auto-delete old exports

[ui]
theme = "auto"                  # auto, dark, light, monochrome
syntax_highlighting = true      # Color JSON diffs
```

---

## Keyboard Shortcuts (Live Mode)

| Key | Action |
|-----|--------|
| `q` | Quit |
| `f` | Change filter |
| `d` | Drill down into selected event |
| `h` | Show help |
| `s` | Save current view to file |
| `r` | Reset filters |
| `↑`/`↓` | Navigate events |
| `Enter` | Inspect selected event |

---

## Performance Targets

The monitor is designed for minimal overhead:

| Metric | Target | Expected |
|--------|--------|----------|
| **Diff computation** | <10ms | 2-8ms (50-100 windows) |
| **Display latency** | <100ms | ~42ms avg |
| **Memory usage** | <25MB | ~2.5MB (500 events) |
| **CPU usage** | <2% | ~0.8% avg |

---

## Troubleshooting

### Daemon won't start

```bash
# Check status
systemctl --user status sway-tree-monitor

# View logs
journalctl --user -u sway-tree-monitor -f

# Common issues:
# - Sway IPC socket not found → Check Sway is running
# - Socket permission denied → Check $XDG_RUNTIME_DIR permissions
# - Python import error → Rebuild NixOS config with new packages
```

### High diff computation latency

```bash
# Check window count
sway-tree-monitor stats

# If >150 windows, performance may degrade
# Consider:
#   1. Increase min_significance to filter noise
#   2. Close unused windows
#   3. Monitor specific event types only
```

### No user action correlation

```bash
# Check if Sway binding events are enabled
swaymsg -t get_binding_state

# Ensure daemon is subscribing to binding events
sway-tree-monitor get_daemon_status | jq '.sway_connection.subscribed_events'

# Should include "binding" in list
```

### Events missing from history

```bash
# Check buffer size
sway-tree-monitor stats

# Buffer is circular (500 events default)
# Older events are automatically evicted

# To preserve events, enable persistence:
# Edit config.toml: persistence.enabled = true
```

---

## Integration with Existing Tools

### i3pm Diagnostics

The tree monitor integrates with i3pm:

```bash
# View tree changes for current project
i3pm diagnose tree-monitor

# Start monitoring with i3pm context
i3pm project tree-changes
```

### Sway IPC

The monitor uses native Sway IPC (no custom patches required):

```bash
# Verify Sway IPC is working
swaymsg -t get_tree | jq '.type'
# Should output "root"

# Check subscribed events
swaymsg -t subscribe -m '["window"]'
```

---

## Advanced Usage

### Custom Filters with JSON

```bash
# Use JSON filter for complex queries
cat > filter.json << EOF
{
  "event_types": ["window::new", "window::close"],
  "min_significance": 0.5,
  "project_name": "nixos",
  "since_ms": $(date -d '1 hour ago' +%s%3N)
}
EOF

sway-tree-monitor history --filter-json=filter.json
```

### Scripting with JSON Output

```bash
# Get event count by type
sway-tree-monitor history --format=json | \
  jq '.events | group_by(.event_type) | map({type: .[0].event_type, count: length})'

# Find all window additions for a specific app
sway-tree-monitor history --format=json | \
  jq '.events[] | select(.event_type == "window::new" and .enrichment[].i3pm_app_name == "firefox")'

# Export high-significance events only
sway-tree-monitor history --min-significance=0.8 --format=json > important-events.json
```

---

## Real-World Examples

### Example 1: Debug i3pm Window Filtering

**Problem**: Windows are being hidden unexpectedly when switching projects.

**Solution**:
```bash
# Start monitoring
sway-tree-monitor live --filter=window

# Switch to project
i3pm project switch other-project

# Observe window::hidden events
# Check which windows were hidden
# Inspect event details to see window properties

sway-tree-monitor history --last=10
sway-tree-monitor diff <event_id>

# Look for I3PM_SCOPE in enriched data
# Verify scoped windows are being hidden correctly
```

---

### Example 2: Measure Workspace Switch Latency

**Problem**: Workspace switching feels slow.

**Solution**:
```bash
# Start monitoring
sway-tree-monitor live

# Press Mod+3 (switch to workspace 3)

# Check time delta between events:
#   1. binding event (Mod+3)
#   2. workspace::focus event

# If >100ms, investigate:
sway-tree-monitor diff <workspace_focus_event_id>

# Look for:
#   - Many window geometry recalculations (slow layout)
#   - Large number of windows on source workspace
#   - Window hide/show operations (i3pm project switch overhead)
```

---

### Example 3: Verify PWA Launch Environment Variables

**Problem**: PWAs not associating with correct i3pm project.

**Solution**:
```bash
# Monitor PWA launch
sway-tree-monitor live --filter=window::new

# Launch PWA from walker
walker-cmd launch claude

# Inspect most recent event
EVENT_ID=$(sway-tree-monitor history --last=1 --format=json | jq '.events[0].event_id')
sway-tree-monitor diff $EVENT_ID

# Check enriched data:
#   I3PM_APP_NAME: "FFPWA-01JCYF8Z2"
#   I3PM_PROJECT_NAME: (should match current project or "global")
#   I3PM_SCOPE: "scoped" or "global"

# If incorrect, debug PWA launch mechanism
```

---

## Performance Benchmarks

Expected performance on reference hardware (Hetzner Cloud, 8 vCPUs):

| Windows | Tree Size | Diff Latency | Memory (500 events) |
|---------|-----------|--------------|---------------------|
| 50 | ~2.8 KB | 2-4ms | ~2.5 MB |
| 100 | ~5.5 KB | 4-8ms | ~4 MB |
| 200 | ~11 KB | 8-15ms | ~7 MB |

**Note**: Apple M1 performance is similar or better (faster CPU, but single-core Python).

---

## See Also

- `cli.md` - Complete CLI reference with all options
- `daemon-api.md` - JSON-RPC API for advanced integration
- `data-model.md` - Event, snapshot, and diff data structures
- `research.md` - Performance analysis and algorithm choices
- `/etc/nixos/specs/029-linux-system-log/` - Multi-source event monitoring (related pattern)
- `/etc/nixos/specs/025-visual-window-state/` - Window state visualization (i3pm windows)

---

## Next Steps

After implementation:

1. **Test with typical workload**: Open 50-100 windows, monitor performance
2. **Verify correlation accuracy**: Press keys, check "Triggered By" column
3. **Enable persistence**: Test export/import workflow
4. **Integrate with i3pm**: Add tree-monitor subcommand to i3pm CLI
5. **Add to CLAUDE.md**: Document in main navigation guide

---

**Implementation Status**: Planning complete. Proceed to `/speckit.tasks` to generate implementation tasks.
