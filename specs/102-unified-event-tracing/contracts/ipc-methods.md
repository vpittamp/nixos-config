# IPC Methods: Unified Event Tracing System

**Feature**: 102-unified-event-tracing
**Date**: 2025-11-30
**Status**: Complete

## Overview

This document defines the IPC methods exposed by the i3pm daemon for Feature 102. All methods use JSON-RPC 2.0 over Unix socket at `~/.local/share/i3pm/daemon.sock`.

## New Methods

### 1. events.query

Query events from the event buffer with filtering.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "events.query",
  "params": {
    "since_id": 0,           // Optional: Return events after this ID
    "limit": 100,            // Optional: Max events to return (default 100, max 500)
    "event_types": ["window::focus", "project::switch"],  // Optional: Filter by types
    "sources": ["sway", "i3pm"],  // Optional: Filter by source
    "correlation_id": "uuid",     // Optional: Filter by correlation
    "window_id": 12345           // Optional: Filter by window
  },
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "events": [
      {
        "event_id": 501,
        "event_type": "project::switch",
        "timestamp": "2025-11-30T10:15:30.123456",
        "source": "i3pm",
        "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
        "causality_depth": 0,
        "trace_id": null,
        "old_project": "nixos",
        "new_project": "dotfiles",
        "windows_affected": 5
      }
    ],
    "total_count": 1,
    "buffer_size": 500,
    "oldest_id": 1,
    "newest_id": 501
  },
  "id": 1
}
```

### 2. events.get_causality_chain

Get all events in a causality chain by correlation_id.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "events.get_causality_chain",
  "params": {
    "correlation_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
    "root_event_id": 501,
    "event_count": 7,
    "duration_ms": 185.3,
    "depth": 2,
    "summary": "project::switch → 7 events, 185.3ms",
    "events": [
      {
        "event_id": 501,
        "event_type": "project::switch",
        "causality_depth": 0
      },
      {
        "event_id": 502,
        "event_type": "visibility::hidden",
        "causality_depth": 1
      }
    ]
  },
  "id": 2
}
```

### 3. traces.list_templates

List available trace templates.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "traces.list_templates",
  "params": {},
  "id": 3
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "templates": [
      {
        "template_id": "debug-app-launch",
        "name": "Debug App Launch",
        "description": "Pre-launch trace with lifecycle events enabled, 60s timeout",
        "match_focused": false,
        "match_all_scoped": false,
        "pre_launch": true,
        "timeout_seconds": 60,
        "enabled_categories": ["window", "launch", "visibility"]
      },
      {
        "template_id": "debug-project-switch",
        "name": "Debug Project Switch",
        "description": "Trace all scoped windows with visibility and command events",
        "match_focused": false,
        "match_all_scoped": true,
        "pre_launch": false,
        "timeout_seconds": 30,
        "enabled_categories": ["project", "visibility", "command"]
      },
      {
        "template_id": "debug-focus-chain",
        "name": "Debug Focus Chain",
        "description": "Capture focus/blur events only for focused window",
        "match_focused": true,
        "match_all_scoped": false,
        "pre_launch": false,
        "timeout_seconds": 60,
        "enabled_types": ["window::focus", "window::blur"]
      }
    ]
  },
  "id": 3
}
```

### 4. traces.start_from_template

Start a trace using a template.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "traces.start_from_template",
  "params": {
    "template_id": "debug-app-launch",
    "app_id": "firefox"    // Optional: Override template matcher
  },
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "trace_id": "trace-1701346530-firefox",
    "window_id": null,      // null for pre-launch traces
    "matcher": {
      "template_id": "debug-app-launch",
      "app_id": "firefox"
    },
    "started_at": "2025-11-30T10:15:30.123456",
    "timeout_at": "2025-11-30T10:16:30.123456",
    "enabled_categories": ["window", "launch", "visibility"]
  },
  "id": 4
}
```

### 5. traces.get_cross_reference

Get trace reference for a specific log event.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "traces.get_cross_reference",
  "params": {
    "event_id": 505
  },
  "id": 5
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "has_trace": true,
    "trace_id": "trace-1701346530-firefox",
    "trace_event_index": 3,    // Index of corresponding event in trace
    "trace_active": true,
    "window_id": 12345
  },
  "id": 5
}
```

### 6. events.get_by_trace

Get log events covered by a specific trace.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "events.get_by_trace",
  "params": {
    "trace_id": "trace-1701346530-firefox",
    "limit": 50
  },
  "id": 6
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "trace_id": "trace-1701346530-firefox",
    "events": [
      {
        "event_id": 505,
        "event_type": "window::new",
        "timestamp": "2025-11-30T10:15:31.456789",
        "window_id": 12345,
        "trace_event_index": 0
      }
    ],
    "total_count": 12
  },
  "id": 6
}
```

### 7. outputs.get_state

Get current output state (for debugging output events).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "outputs.get_state",
  "params": {},
  "id": 7
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "outputs": [
      {
        "name": "eDP-1",
        "active": true,
        "dpms": true,
        "current_mode": "2560x1600",
        "scale": 2.0
      },
      {
        "name": "HEADLESS-1",
        "active": true,
        "dpms": true,
        "current_mode": "1920x1080",
        "scale": 1.0
      }
    ],
    "profile": "local+1vnc"
  },
  "id": 7
}
```

## Modified Methods

### traces.query_window_traces (Enhanced)

Added `include_log_refs` parameter to include log event references.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "traces.query_window_traces",
  "params": {
    "active_only": false,
    "include_log_refs": true   // NEW: Include log event references
  },
  "id": 8
}
```

**Response** (enhanced):
```json
{
  "jsonrpc": "2.0",
  "result": {
    "traces": [
      {
        "trace_id": "trace-1701346530-firefox",
        "window_id": 12345,
        "active": true,
        "events": [
          {
            "event_type": "window::new",
            "timestamp": "2025-11-30T10:15:31.456789",
            "log_event_id": 505    // NEW: Reference to log event
          }
        ]
      }
    ]
  },
  "id": 8
}
```

## Error Codes

| Code | Message | Description |
|------|---------|-------------|
| -32001 | Event not found | Event ID does not exist in buffer |
| -32002 | Trace not found | Trace ID does not exist |
| -32003 | Template not found | Template ID does not exist |
| -32004 | Buffer overflow | Event burst exceeded buffer capacity |
| -32005 | Correlation not found | No events with given correlation_id |

## Streaming Events

For real-time event streaming, use the existing `monitoring_data.py --mode events --listen` command. This now includes i3pm events alongside Sway events.

**Output format** (newline-delimited JSON):
```json
{"events":[{"event_id":501,"event_type":"project::switch","source":"i3pm",...}],"heartbeat":false}
{"events":[],"heartbeat":true}
{"events":[{"event_id":502,"event_type":"visibility::hidden","source":"i3pm",...}],"heartbeat":false}
```

### Burst Handling

When event rate exceeds 100/second, events are batched:

```json
{"batch":true,"batch_count":15,"events":[...],"heartbeat":false}
```

The UI should display a "15 events collapsed" indicator for batched responses.
