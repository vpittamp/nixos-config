# Quickstart Guide: Linux System Log Integration

**Feature**: 029-linux-system-log
**Branch**: `029-linux-system-log`

## Overview

This feature extends i3pm event tracking to include:
- **systemd journal events** - Application service starts/stops from systemd
- **/proc monitoring** - Background process detection and tracking
- **Event correlation** - Relationships between GUI windows and spawned processes

All events appear in a unified stream with existing i3 window manager events.

## Prerequisites

- i3pm daemon running (`systemctl --user status i3-project-event-listener`)
- systemd journal available (`journalctl --version`)
- /proc filesystem mounted (standard on Linux)

**Check daemon status**:
```bash
i3pm daemon status
```

## Quick Start

### 1. Query systemd Application Launches

View applications started by systemd in the last hour:

```bash
i3pm daemon events --source=systemd --since="1 hour ago"
```

**Output**:
```
Recent Events (showing systemd):
────────────────────────────────────────────────────────────────────────────────
5m ago    [systemd] Started Firefox Web Browser
3m ago    [systemd] Started Code - OSS
1m ago    [systemd] Started Ghostty terminal
```

**Common time expressions**:
- `"1 hour ago"` - Last hour
- `"today"` - Since midnight
- `"2025-10-23 07:00:00"` - Specific ISO timestamp

### 2. Enable Process Monitoring

Start monitoring background processes:

```bash
# Process monitoring starts automatically with daemon
# Check if running:
i3pm daemon status
```

**View process events**:
```bash
i3pm daemon events --source=proc --limit=20
```

**Output**:
```
Recent Process Events:
────────────────────────────────────────────────────────────────────────────────
2m ago    [proc] Process started: rust-analyzer (PID 54322)
2m ago    [proc] Process started: typescript-language-server (PID 54323)
1m ago    [proc] Process started: docker-compose (PID 54400)
```

### 3. View Unified Event Stream

See events from all sources (i3, systemd, proc) in chronological order:

```bash
i3pm daemon events --source=all --limit=30
```

**Output**:
```
Recent Events (all sources):
────────────────────────────────────────────────────────────────────────────────
5m ago    [systemd] Started Firefox Web Browser
4m 58s ago [i3] New window opened: firefox [project: personal] 7.2ms
3m ago    [systemd] Started Code - OSS
2m 59s ago [i3] New window opened: Code [project: nixos] 6.8ms
2m 58s ago [proc] Process started: rust-analyzer (PID 54322)
2m ago    [proc] Process started: typescript-language-server (PID 54323)
1m ago    [i3] Focused window: Code [project: nixos] 0.1ms
```

### 4. Correlate GUI Apps with Backend Processes

View relationships between windows and spawned processes:

```bash
i3pm daemon events --correlate --limit=10
```

**Output**:
```
Event Correlation (confidence ≥ 0.5):
────────────────────────────────────────────────────────────────────────────────
2m 59s ago [i3] New window opened: Code [project: nixos] 6.8ms
  ├─ 2m 58s ago [proc] Process started: rust-analyzer (PID 54322) [1.2s later, conf: 0.85]
  └─ 2m 57s ago [proc] Process started: typescript-language-server (PID 54323) [2.3s later, conf: 0.82]

5m ago [i3] New window opened: firefox [project: personal] 7.2ms
  └─ 4m 59s ago [proc] Process started: firefox-bin (PID 54100) [1.0s later, conf: 0.92]
```

**Confidence scores**:
- `0.9-1.0`: Very confident (timing + hierarchy + name match)
- `0.7-0.9`: Confident (timing + hierarchy OR strong name match)
- `0.5-0.7`: Likely (timing proximity with moderate evidence)
- `<0.5`: Not shown (low confidence)

### 5. Filter by Process Name

Find all events related to a specific process:

```bash
i3pm daemon events --source=proc | grep rust-analyzer
```

**Output**:
```
2m 58s ago [proc] Process started: rust-analyzer (PID 54322)
1m 45s ago [proc] Process started: rust-analyzer (PID 54500)
```

### 6. Export to JSON

Export event data for analysis:

```bash
i3pm daemon events --source=all --json --limit=100 > events.json
```

**Analyze with jq**:
```bash
# Count events by source
jq '.[] | .source' events.json | sort | uniq -c

# Find all VS Code spawned processes
jq '.[] | select(.event_type == "process::start" and .process_name == "rust-analyzer")' events.json
```

## Common Use Cases

### Debugging Application Startup

Track the complete lifecycle from systemd service start to process spawns:

```bash
# 1. See when service started
i3pm daemon events --source=systemd | grep firefox

# 2. See when window appeared
i3pm daemon events --source=i3 --type=window | grep firefox

# 3. See timing difference
i3pm daemon events --source=all | grep firefox
```

### Monitor Development Environment

Watch all processes spawned by your IDE:

```bash
# Live monitor with correlation
i3pm daemon events --follow --correlate
```

Press `Ctrl+C` to stop live monitoring.

### Application Usage Analytics

Count launches by application:

```bash
# All Firefox launches today
i3pm daemon events --source=all --since=today | grep -i firefox | wc -l

# All VS Code window creations this week
i3pm daemon events --source=i3 --since="1 week ago" | grep "Code" | wc -l
```

### Performance Analysis

Measure time between service start and window appearance:

```bash
# Export events
i3pm daemon events --source=all --json --since="1 hour ago" > perf.json

# Analyze with jq
jq -r '.[] | select(.systemd_unit == "app-firefox-12345.service" or .window_class == "firefox") | [.timestamp, .event_type, .source] | @csv' perf.json
```

## Configuration

### Process Monitoring Allowlist

Edit daemon configuration to customize which processes are monitored:

```python
# In proc_monitor.py
INTERESTING_PROCESSES = [
    "rust-analyzer",
    "typescript-language-server",
    "node",
    "python",
    "docker",
    "docker-compose",
    "kubectl",
]
```

After editing, restart daemon:
```bash
systemctl --user restart i3-project-event-listener
```

### Polling Interval

Adjust /proc monitoring frequency (default: 500ms):

```python
# In daemon.py
proc_monitor = ProcessMonitor(
    event_buffer=event_buffer,
    poll_interval_ms=500  # Adjust this value
)
```

**Trade-offs**:
- Lower interval (100ms): Faster detection, higher CPU usage
- Higher interval (1000ms): Lower CPU usage, slower detection

## Command Reference

### Event Query Flags

```bash
i3pm daemon events [OPTIONS]
```

**Options**:
```
--source=<source>        Filter by event source
                         Values: i3, ipc, daemon, systemd, proc, all
                         Default: all

--since=<time>           Show events after this time
                         Examples: "1 hour ago", "today", "2025-10-23 07:00:00"

--until=<time>           Show events before this time
                         Default: now

--limit=<n>              Maximum events to show
                         Default: 100

--type=<pattern>         Filter by event type pattern
                         Examples: window, systemd::service, process

--follow, -f             Live stream events (like tail -f)

--json                   Output JSON format

--correlate              Show event correlations (parent-child relationships)

--min-confidence=<n>     Minimum correlation confidence (0.0-1.0)
                         Default: 0.5
```

### Examples

```bash
# Show last 50 systemd events
i3pm daemon events --source=systemd --limit=50

# Live monitor all sources
i3pm daemon events --source=all --follow

# High-confidence correlations only
i3pm daemon events --correlate --min-confidence=0.8

# Process events from last 30 minutes
i3pm daemon events --source=proc --since="30 minutes ago"

# Export i3 window events to JSON
i3pm daemon events --source=i3 --type=window --json > windows.json
```

## Troubleshooting

### "No systemd events found"

**Cause**: journalctl not available or no matching events

**Solution**:
```bash
# Check journalctl works
journalctl --user --since="1 hour ago" --output=json

# Check for application units
journalctl --user --unit="app-*" --since=today
```

### "Process monitoring not active"

**Cause**: Process monitoring failed to start or crashed

**Solution**:
```bash
# Check daemon logs
journalctl --user -u i3-project-event-listener -n 50

# Restart daemon
systemctl --user restart i3-project-event-listener

# Verify status
i3pm daemon status
```

### High CPU usage

**Cause**: /proc monitoring polling too frequently

**Solution**: Increase polling interval in configuration (see Configuration section)

### Sensitive data visible in command lines

**Cause**: Sanitization pattern didn't match sensitive data format

**Solution**: Report the pattern to add to sanitization list

## Performance

### Resource Usage

**Expected overhead**:
- systemd queries: <1s per query (on-demand only)
- /proc monitoring: <2% CPU (500ms polling)
- Event storage: ~1KB per event (SQLite)

### Event Volume

**Typical event rates**:
- i3 window events: 10-50 per hour
- systemd service events: 5-20 per hour
- Process spawns: 50-200 per hour (depends on development activity)

**Storage**:
- 500-event circular buffer (in-memory)
- Full history in SQLite (~10MB per week of active development)

## Next Steps

- [Data Model](./data-model.md) - EventEntry extensions and correlation algorithm
- [IPC Extensions](./contracts/ipc-extensions.md) - JSON-RPC API documentation
- [Research](./research.md) - Technology decisions and patterns
- [Implementation Tasks](./tasks.md) - Task breakdown (run `/speckit.tasks`)

## Support

**Issues**: Report bugs or feature requests on GitHub

**Daemon logs**:
```bash
journalctl --user -u i3-project-event-listener -f
```

**Debug mode**:
```bash
# Enable verbose logging
export I3PM_LOG_LEVEL=DEBUG
systemctl --user restart i3-project-event-listener
```
