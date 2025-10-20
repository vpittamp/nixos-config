# Quickstart: i3 Project System Monitor

**Branch**: `017-now-lets-create` | **Date**: 2025-10-20

## Overview

The i3 project system monitor is a terminal-based debugging tool that provides real-time visibility into the i3 project management system. It helps developers understand system state, track events, and diagnose issues without manually parsing logs.

## Prerequisites

- **NixOS**: System running NixOS with i3 window manager
- **i3 Project Daemon**: The `i3-project-event-listener` systemd service must be running
- **Terminal**: Any terminal emulator (Ghostty, Alacritty, or similar)

Check daemon status:
```bash
systemctl --user status i3-project-event-listener
# Or use the status command:
i3-project-daemon-status
```

If not running, start it:
```bash
systemctl --user start i3-project-event-listener
```

## Installation

The monitor tool is installed automatically via home-manager when the i3 project daemon module is enabled.

### Verify Installation

```bash
which i3-project-monitor
# Expected: /home/user/.nix-profile/bin/i3-project-monitor

i3-project-monitor --help
```

### Manual Installation (Development)

If working from source before the package is integrated:

```bash
# Add rich library to Python environment
nix-shell -p python3Packages.rich python3Packages.i3ipc

# Run directly from source
cd /path/to/monitor/source
python3 -m i3_project_monitor --mode=live
```

## Display Modes

The monitor tool supports four display modes, each optimized for specific debugging tasks.

### 1. Live State Display (Default)

**Purpose**: View current system state at a glance

**Command**:
```bash
i3-project-monitor --mode=live
# Or simply:
i3-project-monitor
```

**Display**:
```
═══════════════════════════════════════════════════════════
i3 Project System Monitor - Live State
═══════════════════════════════════════════════════════════

Connection Status
─────────────────────────────────────────────────────────
Daemon:           ● Connected
Uptime:           1h 23m 45s
Events Processed: 1523
Errors:           0

Active Project
─────────────────────────────────────────────────────────
Project:          NixOS
Tracked Windows:  8 / 12 total

Tracked Windows
─────────────────────────────────────────────────────────
ID       Class       Title                  Project   WS
94558    Ghostty     ~/code/nixos          nixos     1
94562    code        NixOS Configuration   nixos     2
94578    firefox     Documentation         (none)    3
94580    Ghostty     ~/code/stacks         stacks    4

Monitors
─────────────────────────────────────────────────────────
Monitor   Resolution      Workspaces   Primary   Active
eDP-1     1920x1080@60    1, 2         ✓        WS 1
HDMI-1    2560x1440@60    3, 4, 5               WS 3

Refreshing every 250ms... Press Ctrl+C to exit
```

**Use Cases**:
- Quick system health check
- Verify project switch succeeded
- Check which windows are tracked
- Confirm monitor workspace assignments

**Refresh Rate**: 250ms (4 Hz)

### 2. Event Stream Monitor

**Purpose**: Watch events in real-time as they occur

**Command**:
```bash
i3-project-monitor --mode=events

# Filter by event type:
i3-project-monitor --mode=events --filter=window
i3-project-monitor --mode=events --filter=workspace
i3-project-monitor --mode=events --filter=tick
```

**Display**:
```
═══════════════════════════════════════════════════════════
i3 Project System Monitor - Event Stream
═══════════════════════════════════════════════════════════

Subscribed to event stream (all types)
Press Ctrl+C to stop

TIME      TYPE              WINDOW    PROJECT    DETAILS
─────────────────────────────────────────────────────────────
14:23:45  window::new       94558     nixos      Ghostty
14:23:46  window::mark      94558     nixos      project:nixos
14:23:50  window::close     94520     stacks     -
14:23:51  tick              -         -          project:nixos
14:24:00  workspace::init   -         -          workspace 6
14:24:05  window::focus     94562     nixos      -

Events: 6 | Errors: 0 | Duration: 00:00:20
```

**Use Cases**:
- Verify events fire when expected (e.g., window opens trigger marks)
- Debug event ordering and timing
- Monitor event processing latency
- Identify missing or duplicate events

**Event Types**:
- `window::new` - New window created
- `window::close` - Window closed
- `window::mark` - Window mark changed
- `window::focus` - Window gained focus
- `workspace::init` - New workspace created
- `workspace::empty` - Workspace became empty
- `tick` - Project switch notification

### 3. Historical Event Log

**Purpose**: Review past events to diagnose issues

**Command**:
```bash
i3-project-monitor --mode=history

# Show last 50 events:
i3-project-monitor --mode=history --limit=50

# Filter by type:
i3-project-monitor --mode=history --filter=window --limit=20
```

**Display**:
```
═══════════════════════════════════════════════════════════
i3 Project System Monitor - Event History
═══════════════════════════════════════════════════════════

Showing last 20 events (window events only)
Total events in buffer: 500

[2025-10-20 14:20:30.123] window::new
  Window ID:    94550
  Class:        firefox
  Workspace:    3
  Project:      (none)
  Duration:     1.2ms

[2025-10-20 14:21:45.456] window::mark
  Window ID:    94558
  Class:        Ghostty
  Marks:        ['project:nixos']
  Project:      nixos
  Duration:     0.5ms

[2025-10-20 14:22:15.789] window::close
  Window ID:    94520
  Class:        code
  Project:      stacks
  Duration:     0.8ms

Press q to quit, / to search, n/p for next/previous page
```

**Use Cases**:
- Post-mortem debugging ("what happened 5 minutes ago?")
- Identify event patterns (e.g., duplicate marks)
- Find specific window by ID or class
- Review error events

**Buffer Size**: Last 500 events (circular buffer, oldest evicted)

### 4. i3 Tree Inspector

**Purpose**: Inspect full i3 window tree hierarchy

**Command**:
```bash
i3-project-monitor --mode=tree

# Expand specific subtree:
i3-project-monitor --mode=tree --expand=workspace:1

# Filter by marks:
i3-project-monitor --mode=tree --marks=project:nixos
```

**Display**:
```
═══════════════════════════════════════════════════════════
i3 Project System Monitor - Tree Inspector
═══════════════════════════════════════════════════════════

TYPE           ID      MARKS              NAME/TITLE
──────────────────────────────────────────────────────────────
root           1       -                  root
├─ output      2       -                  eDP-1
│  ├─ workspace 4      -                  1
│  │  ├─ con   94558   project:nixos      Ghostty: ~/code/nixos
│  │  └─ con   94562   project:nixos      code: NixOS Config
│  └─ workspace 5      -                  2
│     └─ con   94578   -                  firefox: Docs
└─ output      3       -                  __i3
   └─ workspace 6      -                  __i3_scratch
      └─ floating 94520 project:stacks    VS Code: Stacks

Press SPACE to expand/collapse, / to search, q to quit
```

**Use Cases**:
- Verify window marks applied correctly
- Understand window hierarchy (containers, splits)
- Debug scratchpad window behavior
- Inspect window properties (class, instance, role)

**Data Source**: Queries i3 directly (not daemon-mediated)

## Command Reference

### Global Options

```bash
i3-project-monitor [OPTIONS]

OPTIONS:
  --mode=MODE       Display mode: live|events|history|tree (default: live)
  --filter=TYPE     Filter events by type prefix (events/history mode)
  --limit=N         Limit events displayed (history mode, default: 20)
  --format=FORMAT   Output format: rich|plain|json (default: rich)
  --help, -h        Show help message
  --version, -v     Show version information
```

### Examples

**Quick system status check**:
```bash
i3-project-monitor
```

**Monitor window events only**:
```bash
i3-project-monitor --mode=events --filter=window
```

**Review last 100 events**:
```bash
i3-project-monitor --mode=history --limit=100
```

**Export event history as JSON**:
```bash
i3-project-monitor --mode=history --format=json > events.json
```

**Inspect tree with project marks**:
```bash
i3-project-monitor --mode=tree --marks=project:
```

## Troubleshooting

### Monitor tool shows "Daemon not running"

**Cause**: The i3-project-event-listener service is not active

**Solution**:
```bash
# Check service status
systemctl --user status i3-project-event-listener

# Start service
systemctl --user start i3-project-event-listener

# Enable service to auto-start
systemctl --user enable i3-project-event-listener
```

### Monitor tool shows "Connection lost, retrying..."

**Cause**: Daemon stopped or crashed during monitoring

**Solution**:
```bash
# Check daemon logs for errors
journalctl --user -u i3-project-event-listener -n 50

# Restart daemon
systemctl --user restart i3-project-event-listener

# Monitor will auto-reconnect with exponential backoff
# Wait up to 30 seconds, or restart monitor tool after daemon is up
```

### Event stream shows no events despite window activity

**Possible Causes**:
1. Event filtering is too restrictive
2. Daemon is not subscribed to i3 events
3. i3 IPC connection lost

**Solutions**:
```bash
# Check daemon status
i3-project-daemon-status

# Verify daemon is connected to i3
journalctl --user -u i3-project-event-listener | grep "Connected to i3"

# Try without filter
i3-project-monitor --mode=events
```

### Monitor tool performance degrades over time

**Cause**: Terminal buffer filling with thousands of events

**Solution**:
- Use `--limit` to cap historical display
- Clear terminal periodically: `clear` or `Ctrl+L`
- Restart monitor tool to reset buffer
- Use event filtering: `--filter=window`

### Tree view shows incomplete hierarchy

**Cause**: i3 tree query timing (windows in transition)

**Solution**:
- Refresh tree view (restart monitor tool)
- Check if windows are in scratchpad: look for `__i3_scratch` workspace
- Verify i3 IPC socket: `echo $I3SOCK`

### "No module named 'rich'" error

**Cause**: Rich library not installed in Python environment

**Solution**:
```bash
# Check installation
nix-shell -p python3Packages.rich --run "python3 -c 'import rich; print(rich.__version__)'"

# If using home-manager, rebuild:
home-manager switch

# If using standalone Python:
pip install rich
```

## Integration with Existing Tools

### Use with tmux

Split terminal for multi-mode monitoring:

```bash
# Create tmux session
tmux new-session -s monitor

# Split horizontally for event stream
tmux split-window -h
tmux send-keys "i3-project-monitor --mode=events" C-m

# Split vertically for status
tmux split-window -v
tmux send-keys "i3-project-monitor --mode=live" C-m

# Attach to session
tmux attach -t monitor
```

### Use with watch for polling

Alternative to live mode using watch:

```bash
# Poll status every second
watch -n 1 'i3-project-monitor --mode=live --format=plain'
```

### Pipe to jq for JSON processing

Extract specific fields:

```bash
# Get only window IDs from history
i3-project-monitor --mode=history --format=json | jq '.events[].window_id'

# Count events by type
i3-project-monitor --mode=history --format=json | jq '.events | group_by(.event_type) | map({type: .[0].event_type, count: length})'
```

## Performance Characteristics

- **Memory Usage**: ~5MB typical (10MB with full event buffer)
- **CPU Usage**: <1% idle, ~3% during heavy event streams
- **Network**: Local Unix socket (no network overhead)
- **Latency**: <100ms event display delay from occurrence

## Keyboard Shortcuts (Interactive Modes)

**Live Mode**:
- `Ctrl+C` - Exit
- `Ctrl+L` - Clear and refresh display

**Event Stream**:
- `Ctrl+C` - Stop stream and exit
- `Ctrl+L` - Clear event history display

**History Mode** (planned):
- `/` - Search events
- `n` - Next search result
- `p` - Previous search result
- `q` - Quit

**Tree Mode** (planned):
- `SPACE` - Expand/collapse node
- `/` - Search by window class or title
- `q` - Quit

## Related Documentation

- **Feature Specification**: `/etc/nixos/specs/017-now-lets-create/spec.md`
- **Daemon Documentation**: `/etc/nixos/specs/015-create-a-new/quickstart.md`
- **i3 Project Management Guide**: `/etc/nixos/CLAUDE.md` (Project Management Workflow section)
- **API Contract**: `/etc/nixos/specs/017-now-lets-create/contracts/jsonrpc-api.md`

## Support

**View daemon logs**:
```bash
journalctl --user -u i3-project-event-listener -f
```

**Get daemon status**:
```bash
i3-project-daemon-status
```

**View recent daemon events**:
```bash
i3-project-daemon-events --limit=20
```

**Report issues**: Create issue in NixOS configuration repository

---

**Quickstart Status**: ✅ Complete - Installation, usage, and troubleshooting documented
