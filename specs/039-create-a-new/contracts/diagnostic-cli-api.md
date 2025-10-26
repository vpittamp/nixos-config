# Diagnostic CLI API Contract

**Feature**: 039-create-a-new
**Command**: `i3pm diagnose`
**Language**: Python 3.13 with click + Rich

## Overview

Diagnostic CLI commands for troubleshooting i3 window management issues. All commands communicate with the daemon via JSON-RPC IPC.

---

## Command Structure

```
i3pm diagnose <subcommand> [options]
```

Subcommands follow kubectl/systemctl diagnostic patterns:
- `health` - Daemon health check
- `window` - Window property inspection
- `events` - Event trace viewer
- `validate` - State consistency validation

---

## Global Options

All commands support these flags:

| Flag | Description | Default |
|------|-------------|---------|
| `--json` | Output JSON instead of formatted tables | false |
| `--help` | Show command help | - |

---

## Commands

### 1. i3pm diagnose health

Check daemon health and event subscriptions.

**Usage**:
```bash
i3pm diagnose health [--json]
```

**Output (Human-Readable)**:
```
Daemon Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check                      Status
──────────────────────────────────────────────────────
Daemon Version             1.4.0
Uptime                     1h 0m 0s
IPC Connection             ✓ Connected
JSON-RPC Server            ✓ Running

Event Subscriptions
──────────────────────────────────────────────────────
Type           Active    Count    Last Event
window         ✓         1,234    2s ago (new)
workspace      ✓         89       5s ago (focus)
output         ✓         5        30m ago (change)
tick           ✓         12       10s ago

Window Tracking
──────────────────────────────────────────────────────
Total Windows              23
Tracked Windows            23

Overall Status: ✓ HEALTHY
```

**Output (JSON)**:
```json
{
  "daemon_version": "1.4.0",
  "uptime_seconds": 3600.5,
  "i3_ipc_connected": true,
  "json_rpc_server_running": true,
  "event_subscriptions": [...],
  "total_events_processed": 1350,
  "total_windows": 23,
  "overall_status": "healthy",
  "health_issues": []
}
```

**Exit Codes**:
- `0` - Healthy
- `1` - Warning (state drift, subscription issues)
- `2` - Critical (daemon not running, i3 IPC disconnected)

---

### 2. i3pm diagnose window

Inspect window properties and matching information.

**Usage**:
```bash
i3pm diagnose window <window_id> [--json]
```

**Arguments**:
- `window_id` (required): i3 container ID (get from `i3pm windows` or `xwininfo`)

**Output (Human-Readable)**:
```
Window Diagnostic: 14680068
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

X11 Properties
──────────────────────────────────────────────────────
Window Class               com.mitchellh.ghostty
Window Instance            ghostty
Normalized Class           ghostty
Window Title               vpittamp@hetzner: ~
Process ID                 823199

Workspace Context
──────────────────────────────────────────────────────
Current Workspace          5
Workspace Name             5
Output                     HDMI-1

Window State
──────────────────────────────────────────────────────
Floating                   No
Focused                    Yes
Hidden (Scratchpad)        No

I3PM Environment
──────────────────────────────────────────────────────
App ID                     terminal-stacks-823199-1730000000
App Name                   terminal
Project Name               stacks
Project Directory          /home/vpittamp/projects/stacks
Scope                      scoped

Window Matching
──────────────────────────────────────────────────────
Matched Application        terminal
Match Type                 instance ✓
Expected Workspace         3
Actual Workspace           5 ⚠️ MISMATCH

Marks
──────────────────────────────────────────────────────
project:stacks
app:terminal

⚠️ Workspace Assignment Issue
──────────────────────────────────────────────────────
Window should be on workspace 3 but is on workspace 5.

Possible Causes:
  • Window was manually moved after assignment
  • Workspace assignment failed during creation
  • Daemon restarted after window creation

Recommendation:
  Run `i3pm diagnose events --limit 100 | grep 14680068` to see
  window creation event and assignment attempt.
```

**Output (JSON)**:
```json
{
  "window_id": 14680068,
  "window_class": "com.mitchellh.ghostty",
  "window_class_normalized": "ghostty",
  "window_instance": "ghostty",
  "matched_app": "terminal",
  "match_type": "instance",
  "workspace_number": 5,
  "expected_workspace": 3,
  "workspace_mismatch": true,
  ...
}
```

**Exit Codes**:
- `0` - Window found and inspected
- `1` - Window not found
- `2` - Window not tracked by daemon

---

### 3. i3pm diagnose events

View recent event processing log.

**Usage**:
```bash
i3pm diagnose events [OPTIONS]
```

**Options**:
| Flag | Description | Default |
|------|-------------|---------|
| `--limit N` | Show last N events | 50 |
| `--type TYPE` | Filter by event type (window, workspace, output, tick) | all |
| `--follow` | Stream events in real-time | false |
| `--json` | Output JSON | false |

**Output (Human-Readable)**:
```
Event Processing Log (Last 50 Events)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Time                Type        Change    Window ID    Duration    Result
───────────────────────────────────────────────────────────────────────────
12:34:56.789        window      new       14680068     45.2ms      ✓ WS3
12:34:55.123        window      focus     14680064     2.1ms       ✓
12:34:50.456        workspace   focus     -            0.5ms       ✓
12:34:45.789        window      close     14680060     1.2ms       ✓
...

Summary
───────────────────────────────────────────────────────────────────────────
Total Events                   50
window::new                    12
window::focus                  28
window::close                  8
workspace::focus               2

Performance
───────────────────────────────────────────────────────────────────────────
Avg Handler Duration           15.3ms
Max Handler Duration           45.2ms (window::new at 12:34:56)
Events >100ms                  0 ✓
```

**Output (JSON)**:
```json
[
  {
    "event_type": "window",
    "event_change": "new",
    "timestamp": "2025-10-26T12:34:56.789",
    "window_id": 14680068,
    "handler_duration_ms": 45.2,
    "workspace_assigned": 3,
    "error": null
  }
]
```

**Follow Mode** (Live Streaming):
```bash
# Terminal updates in real-time as events occur
i3pm diagnose events --follow

# Output updates live:
[12:35:01] window::new     14680070    48.1ms    ✓ WS2
[12:35:05] window::focus   14680070     2.3ms    ✓
[12:35:10] workspace::focus -           0.8ms    ✓
^C  # Ctrl+C to stop
```

**Exit Codes**:
- `0` - Events retrieved successfully
- `2` - Daemon not running

---

### 4. i3pm diagnose validate

Validate daemon state consistency against i3 IPC.

**Usage**:
```bash
i3pm diagnose validate [--json]
```

**Output (Human-Readable)**:
```
State Consistency Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Validation Summary
──────────────────────────────────────────────────────
Total Windows Checked          23
Consistent                     21
Inconsistent                   2
Consistency                    91.3%

State Mismatches
──────────────────────────────────────────────────────
Window ID    Property     Daemon Value    i3 Value    Severity
14680068     workspace    3               5           warning
14680070     marks        [...]           [...]       info

Details: Window 14680068 (workspace mismatch)
──────────────────────────────────────────────────────
Daemon believes window is on workspace 3
i3 IPC reports window is on workspace 5
Severity: warning

Recommendation:
  Window may have been manually moved. Run:
    i3pm diagnose window 14680068
  to inspect full window state.

Overall Status: ⚠️ WARNING (State drift detected)

To fix:
  Restart daemon to resynchronize state:
    systemctl --user restart i3-project-event-listener
```

**Output (JSON)**:
```json
{
  "validated_at": "2025-10-26T12:34:56",
  "total_windows_checked": 23,
  "windows_consistent": 21,
  "windows_inconsistent": 2,
  "mismatches": [...],
  "is_consistent": false,
  "consistency_percentage": 91.3
}
```

**Exit Codes**:
- `0` - All state consistent (100%)
- `1` - State drift detected (<100% consistency)
- `2` - Critical issues (i3 IPC unavailable)

---

## Common Workflows

### Debugging Workspace Assignment Failure

```bash
# 1. Get window ID (using xwininfo or i3pm windows)
xwininfo | grep "Window id"  # Click window

# 2. Inspect window properties
i3pm diagnose window <window_id>
# Shows: expected workspace vs actual, match type, environment

# 3. Check event log for creation event
i3pm diagnose events --limit 200 | grep <window_id>
# Shows: whether window::new event fired, assignment attempt, errors

# 4. Validate overall system state
i3pm diagnose validate
# Shows: any systemic state drift
```

### Monitoring Event Processing

```bash
# Watch events in real-time
i3pm diagnose events --follow

# Then in another terminal, launch applications
# Observe: window::new events, workspace assignments, handler latency
```

### Checking Daemon Health After Changes

```bash
# After daemon restart or configuration change
i3pm diagnose health

# Check:
# - All 4 event subscriptions active
# - No errors in subscription status
# - Event counts incrementing (launch a window to test)
```

---

## Error Handling

All commands handle these error scenarios:

**Daemon Not Running**:
```
Error: Unable to connect to i3-project-daemon

The daemon is not running or the socket is unavailable.

To start the daemon:
  systemctl --user start i3-project-event-listener

To check daemon status:
  systemctl --user status i3-project-event-listener
```

**i3 IPC Connection Failed**:
```
Error: i3 IPC connection failed

The daemon cannot communicate with i3 window manager.

Possible causes:
  • i3 is not running
  • i3 IPC socket permission denied
  • i3 crashed or restarted

To check i3 status:
  pgrep -a i3
  ls -l /run/user/$(id -u)/i3/ipc-socket.*
```

**Window Not Found**:
```
Error: Window 14680068 not found

Window does not exist in i3 tree.

Possible causes:
  • Window was closed
  • Incorrect window ID
  • Window is on different i3 instance

To find window ID:
  i3pm windows
  xwininfo  # then click window
```

---

## Rich UI Components

All human-readable output uses Rich library:

**Tables**: Window properties, event logs, validation results
**Colors**: Status indicators (✓ green, ⚠️ yellow, ✗ red)
**Syntax Highlighting**: JSON output, environment variables
**Progress**: Validation progress for large window counts
**Live Displays**: Event streaming (--follow mode)

---

## Implementation Pattern

```python
import click
from rich.console import Console
from rich.table import Table
import json

@click.group()
def diagnose():
    """Diagnostic commands for i3 window management."""
    pass

@diagnose.command()
@click.option('--json', 'output_json', is_flag=True, help='Output JSON')
def health(output_json):
    """Check daemon health."""
    from client import DaemonClient

    client = DaemonClient()
    health_data = client.health_check()

    if output_json:
        print(json.dumps(health_data, indent=2))
        return

    # Rich table output
    console = Console()
    table = Table(title="Daemon Health Check")
    table.add_column("Check")
    table.add_column("Status")

    table.add_row("Daemon Version", health_data["daemon_version"])
    # ... more rows

    console.print(table)

    # Exit code based on status
    if health_data["overall_status"] == "healthy":
        exit(0)
    elif health_data["overall_status"] == "warning":
        exit(1)
    else:
        exit(2)
```

---

## Testing

Each command must have:

1. **Unit Tests**: Argument parsing, JSON formatting
2. **Integration Tests**: Mock daemon responses
3. **Manual Tests**: Real daemon interaction

Example test:
```python
def test_health_command_json_output():
    """Test health command JSON output."""
    result = runner.invoke(diagnose, ['health', '--json'])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert "daemon_version" in data
    assert "overall_status" in data
```

---

## Documentation

Each command provides `--help`:

```bash
$ i3pm diagnose health --help

Usage: i3pm diagnose health [OPTIONS]

  Check daemon health and event subscriptions.

  Shows connection status, event subscription health, and system metrics.
  Exits with code 0 (healthy), 1 (warning), or 2 (critical).

Options:
  --json  Output JSON instead of formatted table
  --help  Show this message and exit.

Examples:
  i3pm diagnose health
  i3pm diagnose health --json | jq '.overall_status'
```
