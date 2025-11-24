# Backend-Frontend API Contract

**Feature**: 092-logs-events-tab
**Protocol**: JSON streaming via stdout (deflisten)
**Date**: 2025-11-23

## Overview

This contract defines the API between the Python backend (`monitoring_data.py --mode events`) and the Eww frontend (GTK widget). The backend streams JSON updates to stdout, which Eww consumes via the `deflisten` command.

---

## Backend Command Interface

### One-Shot Mode

Query current event buffer state (no streaming).

```bash
# Command
python3 -m i3_project_manager.cli.monitoring_data --mode events

# Output (stdout, single line JSON)
{
  "status": "ok",
  "events": [...],
  "event_count": 127,
  "filtered_count": null,
  "oldest_timestamp": 1699999000.0,
  "newest_timestamp": 1700000000.0,
  "daemon_available": true,
  "ipc_connected": true,
  "timestamp": 1700000000.5,
  "timestamp_friendly": "Just now"
}

# Exit code
0 = success (status: "ok")
1 = error (status: "error")
```

### Stream Mode

Continuous JSON stream with real-time event updates (deflisten).

```bash
# Command
python3 -m i3_project_manager.cli.monitoring_data --mode events --listen

# Output (stdout, one JSON object per event update)
{"status":"ok","events":[...],"event_count":1,"timestamp":1700000000.1,"timestamp_friendly":"Just now"}
{"status":"ok","events":[...],"event_count":2,"timestamp":1700000000.2,"timestamp_friendly":"Just now"}
{"status":"ok","events":[...],"event_count":3,"timestamp":1700000000.3,"timestamp_friendly":"Just now"}
... (continues until SIGTERM/SIGINT)

# Heartbeat (every 5s if no events)
{"status":"ok","events":[...],"event_count":127,"timestamp":1700000005.0,"timestamp_friendly":"Just now"}

# Error state (if Sway IPC disconnected)
{"status":"error","error":"Sway IPC disconnected","events":[],"event_count":0,"ipc_connected":false,"timestamp":1700000010.0,"timestamp_friendly":"10 seconds ago"}

# Exit code (when terminated)
0 = graceful shutdown (SIGTERM/SIGINT)
1 = fatal error (cannot recover)
```

---

## Response Schema

### Success Response

```json
{
  "status": "ok",
  "error": null,
  "events": [
    {
      "timestamp": 1700000000.123,
      "timestamp_friendly": "5 seconds ago",
      "event_type": "window::new",
      "change_type": "new",
      "payload": {
        "container": {
          "id": 12345,
          "app_id": "terminal-nixos-123",
          "title": "Terminal - ~/projects/nixos",
          "pid": 67890,
          "focused": true,
          "floating": false
        }
      },
      "enrichment": {
        "window_id": 12345,
        "pid": 67890,
        "app_name": "terminal",
        "app_id": "terminal-nixos-123",
        "icon_path": "/usr/share/icons/hicolor/256x256/apps/terminal.png",
        "project_name": "nixos",
        "scope": "scoped",
        "workspace_number": 1,
        "workspace_name": "1",
        "output_name": "HEADLESS-1",
        "is_pwa": false,
        "daemon_available": true,
        "enrichment_latency_ms": 15.3
      },
      "icon": "󰖲",
      "color": "#89b4fa",
      "category": "window",
      "searchable_text": "terminal nixos 1 Terminal - ~/projects/nixos"
    }
  ],
  "event_count": 127,
  "filtered_count": null,
  "oldest_timestamp": 1699999000.0,
  "newest_timestamp": 1700000000.123,
  "daemon_available": true,
  "ipc_connected": true,
  "timestamp": 1700000000.5,
  "timestamp_friendly": "Just now"
}
```

### Error Response

```json
{
  "status": "error",
  "error": "Sway IPC connection failed: [Errno 111] Connection refused",
  "events": [],
  "event_count": 0,
  "filtered_count": null,
  "oldest_timestamp": null,
  "newest_timestamp": null,
  "daemon_available": false,
  "ipc_connected": false,
  "timestamp": 1700000000.5,
  "timestamp_friendly": "Just now"
}
```

---

## Event Types & Payloads

### Window Events

#### window::new

Triggered when a new window is created.

```json
{
  "event_type": "window::new",
  "change_type": "new",
  "payload": {
    "container": {
      "id": 12345,
      "app_id": "firefox",
      "title": "Mozilla Firefox",
      "pid": 67890,
      "focused": true,
      "floating": false,
      "workspace": { "num": 3 },
      "output": "HEADLESS-1"
    }
  },
  "enrichment": {
    "window_id": 12345,
    "app_name": "firefox",
    "project_name": null,
    "scope": "global",
    "workspace_number": 3,
    "is_pwa": false
  },
  "icon": "󰖲",
  "color": "#89b4fa",
  "category": "window"
}
```

#### window::close

Triggered when a window is closed.

```json
{
  "event_type": "window::close",
  "change_type": "close",
  "payload": {
    "container": {
      "id": 12345,
      "app_id": "firefox"
    }
  },
  "enrichment": null,
  "icon": "󰖶",
  "color": "#f38ba8",
  "category": "window"
}
```

#### window::focus

Triggered when focus changes between windows.

```json
{
  "event_type": "window::focus",
  "change_type": "focus",
  "payload": {
    "container": {
      "id": 12346,
      "app_id": "code",
      "focused": true
    }
  },
  "enrichment": {
    "window_id": 12346,
    "app_name": "code",
    "project_name": "nixos",
    "scope": "scoped"
  },
  "icon": "󰋁",
  "color": "#74c7ec",
  "category": "window"
}
```

### Workspace Events

#### workspace::focus

Triggered when workspace focus changes.

```json
{
  "event_type": "workspace::focus",
  "change_type": "focus",
  "payload": {
    "current": {
      "num": 3,
      "name": "3",
      "focused": true,
      "visible": true,
      "output": "HEADLESS-1"
    },
    "old": {
      "num": 1,
      "name": "1",
      "focused": false,
      "visible": false
    }
  },
  "enrichment": null,
  "icon": "󱂬",
  "color": "#94e2d5",
  "category": "workspace"
}
```

#### workspace::init

Triggered when a new workspace is created.

```json
{
  "event_type": "workspace::init",
  "change_type": "init",
  "payload": {
    "current": {
      "num": 5,
      "name": "5",
      "output": "HEADLESS-2"
    }
  },
  "icon": "󰐭",
  "color": "#a6e3a1",
  "category": "workspace"
}
```

### Output Events

#### output::unspecified

Triggered when monitor configuration changes.

```json
{
  "event_type": "output::unspecified",
  "change_type": "unspecified",
  "payload": {
    "container": {
      "name": "HEADLESS-1",
      "active": true,
      "primary": false,
      "make": "Unknown",
      "model": "Unknown"
    }
  },
  "icon": "󰍹",
  "color": "#cba6f7",
  "category": "output"
}
```

---

## Eww Integration

### deflisten Command

Eww configuration for consuming the event stream.

```yuck
; Variable: events_data (streamed from backend)
(deflisten events_data :initial "{\"status\":\"ok\",\"events\":[]}"
  "python3 -m i3_project_manager.cli.monitoring_data --mode events --listen")

; Widget: Event list with filtering
(defwidget logs-view []
  (box :orientation "v"
    (scroll :vscroll true :hscroll false :vexpand true
      (box :orientation "v"
        (for event in {events_data.events}
          (box
            :visible {event_filter_matches(event)}
            (event-card :event event)))))))

; Helper function: Check if event matches filter
(defun event_filter_matches [event]
  (and
    (or (== event_filter_type "all")
        (== event.category event_filter_type))
    (or (== event_filter_search "")
        (str-contains event.searchable_text event_filter_search))))
```

### Filter State Management

User-controlled filter state (not sent to backend).

```yuck
; Filter variables (frontend-only)
(defvar event_filter_type "all")
(defvar event_filter_search "")

; UI controls
(defwidget filter-controls []
  (box :orientation "h" :space-evenly false
    ; Event type dropdown
    (box :class "filter-type"
      (button :onclick "eww update event_filter_type='all'" "All")
      (button :onclick "eww update event_filter_type='window'" "Window")
      (button :onclick "eww update event_filter_type='workspace'" "Workspace")
      (button :onclick "eww update event_filter_type='output'" "Output"))

    ; Search box
    (input
      :value event_filter_search
      :onchange "eww update event_filter_search={}"
      :placeholder "Search events...")))
```

---

## Error Handling

### Backend Errors

| Error Condition | Response | Exit Code |
|----------------|----------|-----------|
| Sway IPC connection failed | `{"status":"error","error":"Sway IPC connection failed","ipc_connected":false}` | 0 (stream mode), 1 (one-shot mode) |
| i3pm daemon unavailable | `{"status":"ok","daemon_available":false}` (degraded, no enrichment) | 0 |
| Invalid event payload | Log warning to stderr, skip event, continue streaming | 0 |
| Python exception | `{"status":"error","error":"<exception message>"}` | 1 |

### Frontend Handling

```yuck
; Error display
(defwidget error-state []
  (box
    :visible {events_data.status == "error"}
    :class "error-box"
    (label :text "⚠ ${events_data.error}")))

; Degraded state (daemon unavailable)
(defwidget degraded-warning []
  (box
    :visible {!events_data.daemon_available}
    :class "warning-box"
    (label :text "⚠ i3pm daemon unavailable - showing raw events without enrichment")))

; Connection lost indicator
(defwidget connection-status []
  (box
    :visible {!events_data.ipc_connected}
    :class "connection-lost"
    (label :text "󰌙 Reconnecting to Sway IPC...")))
```

---

## Performance Characteristics

### Latency Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Event to stdout | <50ms | Event occurrence → JSON output |
| Enrichment query | <20ms | i3pm daemon round-trip |
| Event batching window | 100ms | Debounce for UI updates |
| Total event latency | <100ms | Event → UI display (SC-001) |

### Throughput

| Scenario | Events/Sec | Handling |
|----------|-----------|----------|
| Normal usage | 1-5 | Stream individual events |
| Project switch | 10-20 | Batch within 100ms window |
| Automation/testing | 50+ | Batch and debounce (SC-003) |

### Resource Usage

| Resource | Limit | Validation |
|----------|-------|------------|
| Memory (buffer) | <1MB | 500 events × 1KB |
| Memory (total) | <50MB | Monitor via pytest |
| CPU (streaming) | <5% | Single core usage |
| Network (daemon) | <1KB/event | JSON payload size |

---

## Backward Compatibility

### Existing Modes

The `--mode events` addition is backward compatible with existing modes:

```bash
# Existing modes (unchanged)
monitoring_data.py                    # Default: windows mode
monitoring_data.py --mode windows --listen
monitoring_data.py --mode projects
monitoring_data.py --mode apps
monitoring_data.py --mode health

# New mode
monitoring_data.py --mode events --listen
```

No breaking changes to existing API contracts.

---

## Testing Contract Compliance

### Backend Tests

```python
# tests/092-logs-events-tab/integration/test_events_api.py

async def test_events_mode_one_shot():
    """Test --mode events returns valid EventsViewData."""
    result = subprocess.run(
        ["python3", "-m", "i3_project_manager.cli.monitoring_data", "--mode", "events"],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0
    data = json.loads(result.stdout)

    assert data["status"] == "ok"
    assert "events" in data
    assert "event_count" in data
    assert data["ipc_connected"] is True


async def test_events_mode_stream():
    """Test --mode events --listen produces continuous JSON stream."""
    proc = await asyncio.create_subprocess_exec(
        "python3", "-m", "i3_project_manager.cli.monitoring_data", "--mode", "events", "--listen",
        stdout=asyncio.subprocess.PIPE
    )

    # Read first two events
    line1 = await proc.stdout.readline()
    line2 = await proc.stdout.readline()

    data1 = json.loads(line1.decode())
    data2 = json.loads(line2.decode())

    assert data1["status"] == "ok"
    assert data2["status"] == "ok"

    # Cleanup
    proc.terminate()
    await proc.wait()
```

### Frontend Tests

Manual verification (Eww GTK widget tests not automated):

1. Open monitoring panel (`Mod+M`)
2. Switch to Logs tab (`Alt+5` or click "Logs")
3. Verify events appear in real-time (create window, switch workspace)
4. Apply filter (click "Window" button)
5. Verify only window events displayed
6. Enter search text ("firefox")
7. Verify only matching events displayed

---

## Contract Completion

**Status**: ✅ Complete

**Key Contracts Defined**:
1. Backend command interface (one-shot and stream modes)
2. Response schema (success and error states)
3. Event type payloads (window, workspace, output)
4. Eww integration (deflisten, filter controls)
5. Error handling and degraded states
6. Performance characteristics and limits

**Next**: quickstart.md and agent context update
