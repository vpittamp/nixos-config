# IPC Protocol Extensions

**Feature**: 029-linux-system-log
**Protocol**: JSON-RPC 2.0 over Unix domain socket
**Socket**: `~/.config/i3/i3-project-daemon.sock`

## Overview

This document defines new JSON-RPC methods added to the i3-project-event-daemon IPC server to support systemd journal integration and /proc filesystem monitoring.

**Base Protocol**: Extends existing i3-project daemon IPC protocol (unchanged methods not listed here)

## Existing IPC Methods (For Reference)

```
query_status() → DaemonStatus
query_events(limit, event_type, source) → EventEntry[]
query_projects() → Project[]
// ... other existing methods
```

## New IPC Methods

### 1. query_systemd_events

Query systemd journal for application launch events.

**Method**: `query_systemd_events`

**Parameters**:
```json
{
  "since": "string (optional)",    // Time expression: "1 hour ago", "today", ISO timestamp
  "until": "string (optional)",    // Time expression (default: "now")
  "unit_pattern": "string (optional)",  // Filter by unit name pattern (e.g., "app-*")
  "limit": "integer (optional)"    // Maximum events to return (default: 100)
}
```

**Returns**: `EventEntry[]`

**Example Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "query_systemd_events",
  "params": {
    "since": "1 hour ago",
    "unit_pattern": "app-*",
    "limit": 50
  }
}
```

**Example Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    {
      "event_id": 1001,
      "event_type": "systemd::service::start",
      "timestamp": "2025-10-23T07:28:46.500000",
      "source": "systemd",
      "systemd_unit": "app-firefox-12345.service",
      "systemd_message": "Started Firefox Web Browser",
      "systemd_pid": 54321,
      "journal_cursor": "s=abc123...",
      "processing_duration_ms": 0.5
    }
  ]
}
```

**Errors**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "journalctl not available"
  }
}

{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32002,
    "message": "Invalid time expression: 'xyz'"
  }
}
```

**Error Codes**:
- `-32001`: journalctl command not found or failed
- `-32002`: Invalid time expression in since/until parameters
- `-32003`: Journal query timeout (>5 seconds)

---

### 2. start_proc_monitoring

Start /proc filesystem monitoring for process detection.

**Method**: `start_proc_monitoring`

**Parameters**:
```json
{
  "poll_interval_ms": "number (optional)",  // Polling interval (default: 500ms)
  "allowlist": "string[] (optional)"        // Process names to monitor (default: all interesting processes)
}
```

**Returns**:
```json
{
  "status": "string",       // "started" | "already_running"
  "monitor_pid": "integer", // PID of monitoring task
  "poll_interval_ms": "number",
  "allowlist": "string[]"
}
```

**Example Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "start_proc_monitoring",
  "params": {
    "poll_interval_ms": 500,
    "allowlist": ["rust-analyzer", "node", "python", "docker"]
  }
}
```

**Example Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "status": "started",
    "monitor_pid": 12345,
    "poll_interval_ms": 500,
    "allowlist": ["rust-analyzer", "node", "python", "docker"]
  }
}
```

**Errors**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "error": {
    "code": -32004,
    "message": "/proc filesystem not accessible"
  }
}
```

**Error Codes**:
- `-32004`: /proc filesystem not accessible or not mounted
- `-32005`: Invalid poll_interval_ms (must be 100-5000ms)

---

### 3. stop_proc_monitoring

Stop /proc filesystem monitoring.

**Method**: `stop_proc_monitoring`

**Parameters**: None

**Returns**:
```json
{
  "status": "string",  // "stopped" | "not_running"
  "events_captured": "integer"  // Total process events captured
}
```

**Example Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "stop_proc_monitoring",
  "params": {}
}
```

**Example Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "status": "stopped",
    "events_captured": 127
  }
}
```

---

### 4. get_correlation

Retrieve event correlation for a specific event.

**Method**: `get_correlation`

**Parameters**:
```json
{
  "event_id": "integer",     // Event ID to get correlation for
  "min_confidence": "number (optional)"  // Minimum confidence score (default: 0.5)
}
```

**Returns**: `EventCorrelation | null`

**Example Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "get_correlation",
  "params": {
    "event_id": 1000,
    "min_confidence": 0.7
  }
}
```

**Example Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "correlation_id": 501,
    "created_at": "2025-10-23T07:28:50.000000",
    "confidence_score": 0.85,
    "parent_event_id": 1000,
    "child_event_ids": [1002, 1003],
    "correlation_type": "window_to_process",
    "time_delta_ms": 1200.0,
    "detection_window_ms": 5000.0,
    "timing_factor": 0.92,
    "hierarchy_factor": 1.0,
    "name_similarity": 0.65,
    "workspace_match": true
  }
}
```

**If no correlation found**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": null
}
```

**Errors**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "error": {
    "code": -32006,
    "message": "Event not found: 9999"
  }
}
```

**Error Codes**:
- `-32006`: Event ID not found in event log

---

### 5. query_correlations

Query all correlations matching criteria.

**Method**: `query_correlations`

**Parameters**:
```json
{
  "correlation_type": "string (optional)",  // "window_to_process" | "process_to_subprocess"
  "min_confidence": "number (optional)",    // Minimum confidence score (default: 0.5)
  "limit": "integer (optional)"             // Maximum correlations to return (default: 50)
}
```

**Returns**: `EventCorrelation[]`

**Example Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "query_correlations",
  "params": {
    "correlation_type": "window_to_process",
    "min_confidence": 0.8,
    "limit": 10
  }
}
```

**Example Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": [
    {
      "correlation_id": 501,
      "created_at": "2025-10-23T07:28:50.000000",
      "confidence_score": 0.85,
      "parent_event_id": 1000,
      "child_event_ids": [1002, 1003],
      "correlation_type": "window_to_process",
      "time_delta_ms": 1200.0,
      "detection_window_ms": 5000.0,
      "timing_factor": 0.92,
      "hierarchy_factor": 1.0,
      "name_similarity": 0.65,
      "workspace_match": true
    }
  ]
}
```

---

## Updated query_events Method

**Existing method** `query_events` is extended to support new event sources.

**Method**: `query_events`

**Parameters** (extended):
```json
{
  "limit": "integer (optional)",       // Maximum events (default: 100)
  "event_type": "string (optional)",   // Filter by event type pattern
  "source": "string (optional)",       // NEW: "i3" | "ipc" | "daemon" | "systemd" | "proc" | "all"
  "since": "string (optional)",        // NEW: Time expression for filtering
  "until": "string (optional)"         // NEW: Time expression for filtering
}
```

**Example - Query all sources**:
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "query_events",
  "params": {
    "source": "all",
    "limit": 50,
    "since": "1 hour ago"
  }
}
```

**Response**: Mixed event stream from all sources sorted by timestamp

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": [
    {
      "event_id": 1001,
      "event_type": "systemd::service::start",
      "source": "systemd",
      "timestamp": "2025-10-23T07:28:46.500000",
      "systemd_unit": "app-firefox-12345.service",
      "systemd_message": "Started Firefox Web Browser",
      "systemd_pid": 54321
    },
    {
      "event_id": 1000,
      "event_type": "window::new",
      "source": "i3",
      "timestamp": "2025-10-23T07:28:47.123456",
      "window_id": 94392938473,
      "window_class": "Code",
      "workspace_name": "1:term"
    },
    {
      "event_id": 1002,
      "event_type": "process::start",
      "source": "proc",
      "timestamp": "2025-10-23T07:28:48.200000",
      "process_pid": 54322,
      "process_name": "rust-analyzer",
      "process_cmdline": "/usr/bin/rust-analyzer"
    }
  ]
}
```

---

## Error Code Reference

| Code | Description |
|------|-------------|
| `-32001` | journalctl not available or failed |
| `-32002` | Invalid time expression in query parameters |
| `-32003` | Journal query timeout (>5 seconds) |
| `-32004` | /proc filesystem not accessible |
| `-32005` | Invalid poll_interval_ms (must be 100-5000ms) |
| `-32006` | Event ID not found |

**Standard JSON-RPC 2.0 errors** (unchanged):
- `-32700`: Parse error
- `-32600`: Invalid Request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

---

## Implementation Notes

### IPC Server Changes (ipc_server.py)

**New method registrations**:
```python
# In IPCServer.__init__()
self.methods = {
    # Existing methods
    "query_status": self.handle_query_status,
    "query_events": self.handle_query_events,
    "query_projects": self.handle_query_projects,

    # New methods
    "query_systemd_events": self.handle_query_systemd_events,
    "start_proc_monitoring": self.handle_start_proc_monitoring,
    "stop_proc_monitoring": self.handle_stop_proc_monitoring,
    "get_correlation": self.handle_get_correlation,
    "query_correlations": self.handle_query_correlations,
}
```

### Deno CLI Changes (daemon.ts)

**New CLI flags**:
```bash
# Query systemd events
i3pm daemon events --source=systemd --since="1 hour ago"

# Query process events
i3pm daemon events --source=proc --limit=20

# Query all sources (unified stream)
i3pm daemon events --source=all

# View correlations
i3pm daemon events --correlate --min-confidence=0.8
```

**Client implementation**:
```typescript
async function queryEvents(options: QueryOptions): Promise<EventNotification[]> {
  const params: any = {
    limit: options.limit,
  };

  if (options.source) {
    params.source = options.source;
  }
  if (options.since) {
    params.since = options.since;
  }
  if (options.eventType) {
    params.event_type = options.eventType;
  }

  return await client.call("query_events", params);
}
```

---

## Backward Compatibility

**All existing IPC methods remain unchanged.**

New methods are additions only - existing clients continue to work without modification. The `query_events` method extension is backward compatible (new parameters are optional).

**Versioning**: IPC protocol version remains `1.0` (additive changes only).
