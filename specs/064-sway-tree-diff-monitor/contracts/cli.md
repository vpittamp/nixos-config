# CLI Contract: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Date**: 2025-11-07

## Command Overview

```bash
sway-tree-monitor <mode> [options]
```

Primary entry point for monitoring Sway tree changes with multiple display modes.

---

## Modes

### 1. `live` - Real-Time Event Stream (Default, P1)

Display real-time tree changes as they occur.

```bash
sway-tree-monitor live [--filter=TYPE] [--min-significance=SCORE]
```

**Options**:
- `--filter=TYPE` - Filter by event type (e.g., `window`, `workspace`, `window::new`)
- `--min-significance=SCORE` - Minimum significance score (0.0-1.0, default: 0.1)
- `--show-correlation` - Display user action correlations (default: true)
- `--no-enrichment` - Skip environment variable enrichment (faster, less context)
- `--refresh-rate=HZ` - UI refresh rate (default: 10 Hz = 100ms)

**Behavior**:
- Connects to Sway IPC and subscribes to all events
- Displays events in real-time table with:
  - Timestamp
  - Event type
  - Primary change summary
  - User action correlation (if any)
- Auto-scrolls to show latest events
- Press `q` to quit, `f` to change filter, `d` to drill down into selected event

**Output Format** (Terminal Table):
```
┌──────────────┬────────────────┬────────────────────────────────────┬──────────────────┐
│ Time         │ Event          │ Change Summary                     │ Triggered By     │
├──────────────┼────────────────┼────────────────────────────────────┼──────────────────┤
│ 15:30:45.123 │ window::new    │ Firefox window added (WS 2)        │ Key: Mod4+Return │
│ 15:30:46.890 │ window::focus  │ Focus: Firefox ← Code              │ Click: (520,340) │
│ 15:30:48.234 │ workspace::foc │ Switched to workspace 3            │ Key: Mod4+3      │
└──────────────┴────────────────┴────────────────────────────────────┴──────────────────┘
```

**Exit Codes**:
- 0: Normal exit (user quit)
- 1: Connection error (Sway IPC unreachable)
- 2: Invalid arguments

---

### 2. `history` - Historical Event Query (P2)

Query and browse past events from circular buffer.

```bash
sway-tree-monitor history [--since=TIME] [--last=COUNT] [--filter=TYPE] [--format=FORMAT]
```

**Options**:
- `--since=TIME` - Show events since time (e.g., `30s`, `5m`, `2024-11-07T15:30:00`)
- `--last=COUNT` - Show last N events (default: 50, max: 500)
- `--filter=TYPE` - Filter by event type
- `--project=NAME` - Filter by I3PM project name
- `--window-class=CLASS` - Filter by window class (e.g., `Firefox`, `Code`)
- `--user-initiated` - Only show events with user action correlation
- `--format=FORMAT` - Output format: `table` (default), `json`, `json-pretty`

**Behavior**:
- Queries event buffer for matching events
- Displays in chronological order (oldest first)
- Supports pagination in interactive mode
- Shows detailed correlation info with `--verbose`

**Output Format** (JSON):
```json
{
  "query": {
    "since_ms": 1699368600000,
    "filters": ["window::new"],
    "count": 2
  },
  "events": [
    {
      "event_id": 1234,
      "timestamp_ms": 1699368645123,
      "event_type": "window::new",
      "summary": "Firefox window added to workspace 2",
      "correlation": {
        "action": "Key: Mod4+Return",
        "confidence": 0.95,
        "time_delta_ms": 45
      }
    },
    {
      "event_id": 1235,
      "timestamp_ms": 1699368648234,
      "event_type": "workspace::focus",
      "summary": "Switched to workspace 3",
      "correlation": {
        "action": "Key: Mod4+3",
        "confidence": 0.98,
        "time_delta_ms": 23
      }
    }
  ],
  "total_matched": 2,
  "buffer_size": 500
}
```

**Exit Codes**:
- 0: Success
- 1: Connection error
- 2: Invalid arguments
- 3: No events matched query

---

### 3. `diff` - Detailed Event Inspection (P2)

Inspect detailed tree diff for a specific event.

```bash
sway-tree-monitor diff <EVENT_ID> [--format=FORMAT]
```

**Arguments**:
- `EVENT_ID` - Event ID from history (required)

**Options**:
- `--format=FORMAT` - Output format: `tree` (default), `json`, `compact`
- `--show-tree` - Include full tree snapshots (before/after)
- `--no-color` - Disable syntax highlighting

**Behavior**:
- Retrieves event from buffer by ID
- Displays structured diff with before/after values
- Shows enriched context (env vars, project data)
- Highlights significant changes

**Output Format** (Tree):
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

**Exit Codes**:
- 0: Success
- 1: Connection error
- 2: Invalid event ID
- 3: Event not found in buffer

---

### 4. `stats` - Statistical Summary (P3)

Display statistical summary of event stream.

```bash
sway-tree-monitor stats [--since=TIME] [--format=FORMAT]
```

**Options**:
- `--since=TIME` - Analyze events since time (default: all buffered events)
- `--format=FORMAT` - Output format: `table` (default), `json`

**Behavior**:
- Analyzes event buffer for patterns
- Shows event type distribution
- Displays average latencies
- Reports correlation accuracy

**Output Format** (Table):
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
  Medium (70-90%):        32 (6%)
  Low (<70%):             18 (4%)
  No correlation:         88 (18%)
```

**Exit Codes**:
- 0: Success
- 1: Connection error
- 2: Invalid arguments

---

### 5. `export` - Export Event Data (P3)

Export event buffer to file for post-mortem analysis.

```bash
sway-tree-monitor export <OUTPUT_FILE> [--since=TIME] [--filter=TYPE]
```

**Arguments**:
- `OUTPUT_FILE` - Output file path (JSON format)

**Options**:
- `--since=TIME` - Export events since time
- `--filter=TYPE` - Filter by event type
- `--include-snapshots` - Include full tree snapshots (large files)
- `--compress` - Compress output with gzip

**Behavior**:
- Queries event buffer
- Serializes matched events to JSON
- Writes to file
- Reports export statistics

**Output**:
```
Exported 250 events to sway-events-2024-11-07.json
  Time range: 15:30:00 - 17:45:32 (2h 15m)
  File size: 1.2 MB (uncompressed)
  Event types: window::focus (45%), window::move (20%), ...
```

**Exit Codes**:
- 0: Success
- 1: Connection error
- 2: Invalid arguments
- 3: File write error

---

### 6. `import` - Import and Replay Events (P3)

Import previously exported event data for analysis.

```bash
sway-tree-monitor import <INPUT_FILE> [--replay]
```

**Arguments**:
- `INPUT_FILE` - Input file path (JSON from `export`)

**Options**:
- `--replay` - Replay events in live mode (simulate real-time)
- `--speed=FACTOR` - Playback speed multiplier (default: 1.0)

**Behavior**:
- Reads exported JSON file
- Loads events into buffer
- Optionally replays events with original timing
- Allows analysis with `history`, `diff`, `stats` commands

**Output**:
```
Imported 250 events from sway-events-2024-11-07.json
  Time range: 15:30:00 - 17:45:32 (2h 15m)
  Event types: 5 distinct types
  Buffer size: 250/500

Use 'sway-tree-monitor history' to query imported events
Use 'sway-tree-monitor import --replay <file>' to replay
```

**Exit Codes**:
- 0: Success
- 1: File read error
- 2: Invalid JSON format
- 3: Incompatible event schema version

---

## Global Options

Available for all modes:

```bash
--help, -h          Show help message
--version, -v       Show version information
--daemon-socket     Path to daemon socket (default: $XDG_RUNTIME_DIR/sway-tree-monitor.sock)
--no-daemon         Run in standalone mode (no daemon connection)
--debug             Enable debug logging
--log-file=PATH     Log to file instead of stderr
```

---

## Exit Codes Summary

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 0 | Success | Normal operation |
| 1 | Connection error | Sway IPC unreachable, daemon not running |
| 2 | Invalid arguments | Bad command-line options, missing required args |
| 3 | Data error | Event not found, file not found, no matches |
| 4 | Permission error | Cannot read/write file, cannot connect to socket |

---

## Examples

### Basic Live Monitoring
```bash
# Start live monitoring with defaults
sway-tree-monitor live

# Only show window events with high significance
sway-tree-monitor live --filter=window --min-significance=0.5
```

### Historical Query
```bash
# Show last 100 events
sway-tree-monitor history --last=100

# Show workspace changes in last 5 minutes
sway-tree-monitor history --since=5m --filter=workspace

# Export to JSON for external analysis
sway-tree-monitor history --since=1h --format=json > events.json
```

### Detailed Inspection
```bash
# Show detailed diff for event #1234
sway-tree-monitor diff 1234

# Show diff with full tree snapshots (verbose)
sway-tree-monitor diff 1234 --show-tree
```

### Statistics & Export
```bash
# Show stats for last hour
sway-tree-monitor stats --since=1h

# Export all events to file
sway-tree-monitor export sway-events-$(date +%Y%m%d).json

# Export with compression
sway-tree-monitor export events.json.gz --compress
```

### Import & Replay
```bash
# Import events from file
sway-tree-monitor import sway-events-20241107.json

# Replay events at 2x speed
sway-tree-monitor import events.json --replay --speed=2.0
```

---

## Integration with Existing Tools

### i3pm Integration

The tree diff monitor can be invoked from i3pm:

```bash
# Add to i3pm diagnostics
i3pm diagnose tree-monitor

# View tree changes for current project
i3pm project tree-changes
```

### Daemon Communication

The monitor communicates with a background daemon via Unix socket:

**Socket path**: `$XDG_RUNTIME_DIR/sway-tree-monitor.sock`
**Protocol**: JSON-RPC 2.0 over Unix socket
**Methods**: See `daemon-api.md` for details

---

## Configuration File

Optional configuration at `~/.config/sway-tree-monitor/config.toml`:

```toml
[monitor]
# Default event buffer size
buffer_size = 500

# Default refresh rate (Hz)
refresh_rate = 10

# Default significance threshold
min_significance = 0.1

[correlation]
# Correlation time window (ms)
time_window_ms = 500

# Confidence thresholds
high_confidence = 0.90
medium_confidence = 0.70

[persistence]
# Enable automatic persistence
enabled = true

# Persistence directory
dir = "~/.local/share/sway-tree-monitor"

# Retention period (days)
retention_days = 7

[ui]
# Color theme (auto, dark, light)
theme = "auto"

# Syntax highlighting for JSON diffs
syntax_highlighting = true
```

---

## Accessibility

### Color-Blind Modes
- `--theme=monochrome` - No color, use symbols only
- `--theme=high-contrast` - High-contrast colors

### Screen Reader Support
- `--format=plain` - Plain text output without tables/colors
- `--narrate` - Announce events to screen reader

---

## Performance Monitoring

All commands report performance metrics in debug mode:

```bash
sway-tree-monitor live --debug
```

**Metrics shown**:
- Diff computation time (ms)
- Display latency (ms)
- Memory usage (MB)
- Events/second

---

## Backward Compatibility

**Event schema versioning**: Exported JSON includes schema version for compatibility:

```json
{
  "schema_version": "1.0.0",
  "events": [...]
}
```

Import command checks schema version and migrates if needed.

---

## See Also

- `daemon-api.md` - Daemon JSON-RPC API specification
- `data-model.md` - Data models for events, snapshots, diffs
- `research.md` - Performance benchmarks and implementation decisions
