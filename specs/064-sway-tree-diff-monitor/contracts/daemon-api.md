# Daemon API Contract: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Date**: 2025-11-07
**Protocol**: JSON-RPC 2.0 over Unix Socket

## Overview

The Sway tree diff monitor daemon runs as a systemd user service, maintaining the event buffer and computing tree diffs in the background. CLI clients communicate with the daemon via JSON-RPC 2.0 over a Unix socket.

**Socket Path**: `$XDG_RUNTIME_DIR/sway-tree-monitor.sock` (typically `/run/user/1000/sway-tree-monitor.sock`)

**Transport**: Unix domain socket (SOCK_STREAM)

**Message Format**: JSON-RPC 2.0 (newline-delimited JSON)

---

## Connection

### Socket Connection

```python
import socket
import json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/run/user/1000/sway-tree-monitor.sock")

# Send request
request = {
    "jsonrpc": "2.0",
    "method": "query_events",
    "params": {"last": 50},
    "id": 1
}
sock.sendall(json.dumps(request).encode() + b'\n')

# Receive response
response = json.loads(sock.recv(4096).decode())
print(response)
```

### JSON-RPC 2.0 Format

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { "param1": "value1" },
  "id": 1
}
```

**Success Response**:
```json
{
  "jsonrpc": "2.0",
  "result": { "data": "..." },
  "id": 1
}
```

**Error Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": "Additional error details"
  },
  "id": 1
}
```

**JSON-RPC Error Codes**:
- `-32700`: Parse error (invalid JSON)
- `-32600`: Invalid request (missing required fields)
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error
- `-1000` to `-1999`: Custom application errors (see below)

---

## Methods

### 1. `ping` - Health Check

Verify daemon is running and responsive.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "ping",
  "params": {},
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "status": "ok",
    "version": "1.0.0",
    "uptime_seconds": 3661,
    "buffer_size": 500,
    "event_count": 234
  },
  "id": 1
}
```

**Performance**: <1ms

---

### 2. `query_events` - Query Event Buffer

Retrieve events from circular buffer with optional filters.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "query_events",
  "params": {
    "last": 50,                       // Optional: last N events
    "since_ms": 1699368600000,        // Optional: since timestamp
    "until_ms": 1699369000000,        // Optional: until timestamp
    "event_types": ["window::new"],   // Optional: filter by type
    "min_significance": 0.5,          // Optional: min significance score
    "project_name": "nixos",          // Optional: filter by I3PM project
    "window_class": "Firefox",        // Optional: filter by window class
    "user_initiated_only": false      // Optional: only user-initiated events
  },
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "event_id": 1234,
        "timestamp_ms": 1699368645123,
        "event_type": "window::new",
        "sway_change": "new",
        "container_id": 12345,
        "summary": "Firefox window added to workspace 2",
        "significance_score": 1.0,
        "correlation": {
          "action": "Key: Mod4+Return",
          "confidence": 0.95,
          "time_delta_ms": 45,
          "cascade_level": 0
        },
        "change_count": 15
      }
    ],
    "total_matched": 1,
    "buffer_size": 500,
    "query_time_ms": 0.8
  },
  "id": 2
}
```

**Performance**: <1ms for typical queries (<50 events)

**Errors**:
- `-1001`: Invalid time range (until_ms < since_ms)
- `-1002`: Invalid significance score (not in [0.0, 1.0])

---

### 3. `get_event` - Get Single Event Details

Retrieve detailed information for a specific event, including full diff.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_event",
  "params": {
    "event_id": 1234,
    "include_snapshots": false,  // Optional: include full tree snapshots
    "include_diff": true          // Optional: include detailed diff (default: true)
  },
  "id": 3
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "event_id": 1234,
    "timestamp_ms": 1699368645123,
    "event_type": "window::new",
    "sway_change": "new",
    "container_id": 12345,

    "diff": {
      "diff_id": 1234,
      "before_snapshot_id": 1233,
      "after_snapshot_id": 1234,
      "computation_time_ms": 4.2,
      "total_changes": 15,
      "significance_score": 1.0,

      "node_changes": [
        {
          "node_id": "12345",
          "node_type": "con",
          "change_type": "added",
          "node_path": "outputs[0].workspaces[2].nodes[5]",
          "field_changes": [
            {
              "field_path": "window",
              "old_value": null,
              "new_value": 12345,
              "change_type": "added",
              "significance_score": 1.0
            },
            {
              "field_path": "name",
              "old_value": null,
              "new_value": "Mozilla Firefox",
              "change_type": "added",
              "significance_score": 1.0
            }
          ]
        }
      ]
    },

    "correlations": [
      {
        "correlation_id": 567,
        "user_action": {
          "action_id": 890,
          "timestamp_ms": 1699368645078,
          "action_type": "binding",
          "binding_symbol": "Mod4+Return",
          "binding_command": "exec firefox",
          "source": "sway"
        },
        "time_delta_ms": 45,
        "confidence_score": 0.95,
        "confidence_factors": {
          "temporal": 95.0,
          "semantic": 100.0,
          "exclusivity": 85.0,
          "cascade": 100.0
        },
        "cascade_level": 0
      }
    ],

    "enrichment": {
      "12345": {
        "window_id": 12345,
        "pid": 98765,
        "i3pm_app_id": "firefox-nixos-123-456",
        "i3pm_app_name": "firefox",
        "i3pm_project_name": "nixos",
        "i3pm_scope": "global",
        "project_marks": [],
        "app_marks": ["app:firefox"]
      }
    }
  },
  "id": 3
}
```

**Performance**: <2ms

**Errors**:
- `-1003`: Event not found (event_id not in buffer)

---

### 4. `subscribe` - Subscribe to Real-Time Events

Subscribe to real-time event stream (streaming JSON-RPC).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "subscribe",
  "params": {
    "event_types": ["window::new", "window::close"],  // Optional: filter
    "min_significance": 0.5                            // Optional: threshold
  },
  "id": 4
}
```

**Response** (initial acknowledgment):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "subscription_id": "sub-1234-5678",
    "status": "subscribed"
  },
  "id": 4
}
```

**Subsequent Notifications** (no `id` field):
```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "subscription_id": "sub-1234-5678",
    "event": {
      "event_id": 1235,
      "timestamp_ms": 1699368648234,
      "event_type": "window::new",
      "summary": "Code window added to workspace 3",
      "significance_score": 1.0
    }
  }
}
```

**Unsubscribe**:
```json
{
  "jsonrpc": "2.0",
  "method": "unsubscribe",
  "params": {
    "subscription_id": "sub-1234-5678"
  },
  "id": 5
}
```

**Performance**: Notification latency <100ms from Sway event

**Errors**:
- `-1004`: Subscription limit reached (max 10 concurrent subscriptions)
- `-1005`: Invalid subscription ID

---

### 5. `get_statistics` - Get Event Statistics

Retrieve statistical summary of event buffer.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_statistics",
  "params": {
    "since_ms": 1699368600000  // Optional: analyze events since timestamp
  },
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "event_type_distribution": {
      "window::focus": 225,
      "window::move": 100,
      "workspace::focus": 90,
      "window::new": 50,
      "window::close": 35
    },

    "performance": {
      "avg_diff_computation_ms": 5.2,
      "p50_diff_computation_ms": 5.0,
      "p95_diff_computation_ms": 8.1,
      "p99_diff_computation_ms": 12.3,
      "avg_display_latency_ms": 42,
      "max_diff_computation_ms": 15.6
    },

    "correlation": {
      "user_initiated_count": 412,
      "user_initiated_percent": 82.4,
      "high_confidence_count": 380,
      "medium_confidence_count": 32,
      "low_confidence_count": 18,
      "no_correlation_count": 88
    },

    "buffer": {
      "total_events": 500,
      "oldest_event_ms": 1699360500000,
      "newest_event_ms": 1699368648234,
      "time_span_seconds": 8148,
      "events_per_minute": 3.7
    },

    "memory": {
      "buffer_size_mb": 2.5,
      "hash_cache_kb": 12.3,
      "correlation_tracker_kb": 24.8,
      "total_mb": 2.54
    }
  },
  "id": 6
}
```

**Performance**: <5ms (requires scanning buffer)

---

### 6. `export_events` - Export Events to JSON

Export event buffer to JSON file on daemon's filesystem.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "export_events",
  "params": {
    "output_path": "/home/user/.local/share/sway-tree-monitor/export-20241107.json",
    "since_ms": 1699368600000,        // Optional: filter by time
    "event_types": ["window"],        // Optional: filter by type
    "include_snapshots": false,       // Optional: include full snapshots (large)
    "compress": false                 // Optional: gzip compression
  },
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "exported_count": 250,
    "file_path": "/home/user/.local/share/sway-tree-monitor/export-20241107.json",
    "file_size_bytes": 1258291,
    "time_range": {
      "oldest_ms": 1699368600000,
      "newest_ms": 1699376800000
    }
  },
  "id": 7
}
```

**Performance**: ~2ms per event write (500ms for 250 events)

**Errors**:
- `-1006`: File write error (permission denied, disk full)
- `-1007`: Invalid output path

---

### 7. `import_events` - Import Events from JSON

Import previously exported events into buffer (replaces current buffer).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "import_events",
  "params": {
    "input_path": "/home/user/.local/share/sway-tree-monitor/export-20241107.json",
    "replace_buffer": true  // Optional: replace current buffer (default: true)
  },
  "id": 8
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "imported_count": 250,
    "schema_version": "1.0.0",
    "time_range": {
      "oldest_ms": 1699368600000,
      "newest_ms": 1699376800000
    },
    "buffer_size_after": 250
  },
  "id": 8
}
```

**Performance**: ~0.5ms per event read (125ms for 250 events)

**Errors**:
- `-1008`: File read error (not found, permission denied)
- `-1009`: Invalid JSON format
- `-1010`: Incompatible schema version

---

### 8. `get_daemon_status` - Get Daemon Status

Retrieve comprehensive daemon status and configuration.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_daemon_status",
  "params": {},
  "id": 9
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "version": "1.0.0",
    "uptime_seconds": 3661,
    "started_at": "2024-11-07T14:30:00Z",

    "sway_connection": {
      "status": "connected",
      "socket_path": "/run/user/1000/sway-ipc.sock",
      "subscribed_events": ["window", "workspace", "binding"]
    },

    "buffer": {
      "max_size": 500,
      "current_size": 234,
      "oldest_event_ms": 1699364600000,
      "newest_event_ms": 1699368261000
    },

    "correlation": {
      "time_window_ms": 500,
      "pending_actions": 8,
      "total_correlations": 192
    },

    "performance": {
      "total_events_processed": 234,
      "avg_diff_computation_ms": 5.2,
      "max_diff_computation_ms": 15.6,
      "cpu_percent": 0.8,
      "memory_mb": 2.54
    },

    "persistence": {
      "enabled": true,
      "directory": "/home/user/.local/share/sway-tree-monitor",
      "auto_export": false,
      "last_export": "2024-11-07T16:45:00Z"
    },

    "config": {
      "min_significance": 0.1,
      "enrichment_enabled": true,
      "hash_cache_ttl_seconds": 60
    }
  },
  "id": 9
}
```

**Performance**: <2ms

---

## Batch Requests

JSON-RPC 2.0 supports batch requests for efficiency:

**Request**:
```json
[
  {
    "jsonrpc": "2.0",
    "method": "query_events",
    "params": {"last": 10},
    "id": 1
  },
  {
    "jsonrpc": "2.0",
    "method": "get_statistics",
    "params": {},
    "id": 2
  }
]
```

**Response**:
```json
[
  {
    "jsonrpc": "2.0",
    "result": { "events": [...] },
    "id": 1
  },
  {
    "jsonrpc": "2.0",
    "result": { "event_type_distribution": {...} },
    "id": 2
  }
]
```

---

## Error Codes

### JSON-RPC Standard Errors

| Code | Message | Meaning |
|------|---------|---------|
| -32700 | Parse error | Invalid JSON was received |
| -32600 | Invalid Request | JSON is not a valid Request object |
| -32601 | Method not found | Method does not exist |
| -32602 | Invalid params | Invalid method parameter(s) |
| -32603 | Internal error | Internal JSON-RPC error |

### Application-Specific Errors

| Code | Message | Meaning |
|------|---------|---------|
| -1000 | Sway connection error | Cannot connect to Sway IPC |
| -1001 | Invalid time range | until_ms < since_ms |
| -1002 | Invalid significance score | Score not in [0.0, 1.0] |
| -1003 | Event not found | event_id not in buffer |
| -1004 | Subscription limit reached | Max 10 concurrent subscriptions |
| -1005 | Invalid subscription ID | Subscription ID not found |
| -1006 | File write error | Cannot write export file |
| -1007 | Invalid output path | Output path invalid or inaccessible |
| -1008 | File read error | Cannot read import file |
| -1009 | Invalid JSON format | Import file JSON parse error |
| -1010 | Incompatible schema version | Import file schema version mismatch |

---

## Systemd Service Integration

### Service Unit

```ini
[Unit]
Description=Sway Tree Diff Monitor Daemon
Documentation=file:///etc/nixos/specs/052-sway-tree-diff-monitor/
After=sway-session.target
PartOf=graphical-session.target

[Service]
Type=notify
ExecStart=/nix/store/...-sway-tree-monitor/bin/sway-tree-monitor-daemon
Restart=on-failure
RestartSec=5s

# Resource limits
MemoryMax=50M
CPUQuota=5%

[Install]
WantedBy=sway-session.target
```

### Control Commands

```bash
# Start daemon
systemctl --user start sway-tree-monitor

# Stop daemon
systemctl --user stop sway-tree-monitor

# Status
systemctl --user status sway-tree-monitor

# Enable auto-start
systemctl --user enable sway-tree-monitor

# Logs
journalctl --user -u sway-tree-monitor -f
```

---

## Socket Activation

The daemon supports systemd socket activation for on-demand startup:

**Socket unit** (`sway-tree-monitor.socket`):
```ini
[Unit]
Description=Sway Tree Monitor Socket

[Socket]
ListenStream=%t/sway-tree-monitor.sock
Accept=false

[Install]
WantedBy=sockets.target
```

---

## Performance Guarantees

| Operation | Target Latency | Achieved |
|-----------|----------------|----------|
| `ping` | <1ms | ~0.5ms |
| `query_events` (50 events) | <2ms | ~0.8ms |
| `get_event` (with diff) | <5ms | ~2ms |
| `subscribe` notification | <100ms | ~42ms avg |
| `get_statistics` | <10ms | ~5ms |
| `export_events` (500 events) | <1s | ~1s |

---

## Security Considerations

### Socket Permissions

The daemon socket is created with restrictive permissions:
- Owner: Current user
- Permissions: 0600 (owner read/write only)
- No world access

### Resource Limits

Systemd service enforces:
- Memory limit: 50 MB (buffer + overhead)
- CPU quota: 5% (prevent runaway CPU usage)
- File descriptor limit: 64 (buffer + subscriptions + Sway IPC)

### Input Validation

All JSON-RPC parameters are validated:
- Type checking (int, float, str, list, dict)
- Range checking (timestamps, significance scores)
- Path sanitization (no directory traversal)

---

## Versioning

### API Version

Current API version: **1.0.0**

Version returned in `ping` and `get_daemon_status` responses.

### Schema Evolution

Breaking changes require major version bump:
- New fields: Minor version bump
- Removed fields: Major version bump
- Changed field types: Major version bump

### Backward Compatibility

Version 1.x clients can communicate with 1.y daemon (y >= x).

---

## See Also

- `cli.md` - CLI command reference
- `data-model.md` - Event, snapshot, and diff data models
- `research.md` - Performance benchmarks and algorithm choices
