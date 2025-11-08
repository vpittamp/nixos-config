# Data Model: i3pm Tree Monitor Integration

**Feature**: 065-i3pm-tree-monitor
**Date**: 2025-11-08
**Purpose**: Define TypeScript interfaces and data structures for CLI client

---

## Overview

The CLI client is a stateless TypeScript/Deno application that communicates with the Python daemon via JSON-RPC 2.0. All data models represent the contract between daemon (Python) and client (TypeScript).

**Source**: Daemon returns Python dataclasses serialized to JSON. Client deserializes to TypeScript interfaces.

---

## Core Entities

### Event

Represents a window or workspace state change captured by the daemon.

```typescript
interface Event {
  /** Unique event ID (UUID) */
  id: string;

  /** Unix timestamp (milliseconds) when event was captured */
  timestamp: number;

  /** Event type (e.g., "window::new", "workspace::focus") */
  type: string;

  /** Number of field-level changes in this event */
  change_count: number;

  /** Significance score (0.0-1.0): minimal, low, moderate, high, critical */
  significance: number;

  /** User action correlation (if any) */
  correlation?: Correlation;

  /** Field-level diff (only in detailed view via get_event) */
  diff?: Diff[];

  /** Enriched I3PM context (only if window-related event) */
  enrichment?: Enrichment;
}
```

**Derived Properties**:
```typescript
function getSignificanceLabel(score: number): string {
  if (score >= 0.8) return "critical";
  if (score >= 0.6) return "high";
  if (score >= 0.4) return "moderate";
  if (score >= 0.2) return "low";
  return "minimal";
}
```

**Event Types** (from Sway IPC subscriptions):
- `window::new` - New window created
- `window::close` - Window closed
- `window::focus` - Focus changed to different window
- `window::title` - Window title changed
- `window::move` - Window moved to different workspace/output
- `workspace::focus` - Workspace focus changed
- `workspace::init` - New workspace created
- `workspace::empty` - Workspace became empty

---

### Correlation

Links an event to a user action (keyboard binding, mouse click, etc.)

```typescript
interface Correlation {
  /** Type of user action that triggered this event */
  action_type: string;  // e.g., "binding", "mouse_click", "external_command"

  /** Sway binding command that was executed */
  binding_command?: string;  // e.g., "exec alacritty", "workspace 2"

  /** Time delta (milliseconds) between user action and event */
  time_delta_ms: number;

  /** Confidence score (0.0-1.0) */
  confidence: number;

  /** Human-readable reasoning for correlation */
  reasoning: string;  // e.g., "Window appeared 150ms after 'exec' binding"
}
```

**Confidence Levels** (from FR-012):
- `>= 0.90` - Very Likely (🟢)
- `>= 0.70` - Likely (🟡)
- `>= 0.50` - Possible (🟠)
- `>= 0.30` - Unlikely (🔴)
- `< 0.30` - Very Unlikely (⚫)

**Derived Function**:
```typescript
function getConfidenceIndicator(confidence: number): string {
  if (confidence >= 0.90) return "🟢";
  if (confidence >= 0.70) return "🟡";
  if (confidence >= 0.50) return "🟠";
  if (confidence >= 0.30) return "🔴";
  return "⚫";
}
```

---

### Diff

Field-level change within an event (tree node property modification).

```typescript
interface Diff {
  /** JSON path to changed field (e.g., "focused", "geometry.width") */
  path: string;

  /** Type of change */
  change_type: "modified" | "added" | "removed";

  /** Old value (null for "added") */
  old_value: any;

  /** New value (null for "removed") */
  new_value: any;

  /** Significance score for this specific change (0.0-1.0) */
  significance: number;
}
```

**Example**:
```json
{
  "path": "geometry.width",
  "change_type": "modified",
  "old_value": 800,
  "new_value": 1200,
  "significance": 0.6
}
```

---

### Enrichment

I3PM-specific context for window events (read from process environment `/proc/<pid>/environ`).

```typescript
interface Enrichment {
  /** Process ID of window */
  pid: number;

  /** I3PM environment variables (if present) */
  i3pm_vars?: {
    APP_ID?: string;       // e.g., "vscode-nixos-123-456"
    APP_NAME?: string;     // e.g., "vscode"
    PROJECT_NAME?: string; // e.g., "nixos"
    SCOPE?: string;        // "scoped" | "global"
    LAUNCH_CONTEXT?: string; // "daemon" | "manual"
  };

  /** Sway window marks (e.g., ["project:nixos", "app:vscode"]) */
  marks?: string[];

  /** Launch context metadata */
  launch_context?: {
    method: string;       // "launcher" | "binding" | "scratchpad"
    timestamp: number;    // Unix timestamp (ms)
  };
}
```

---

### Stats

Daemon performance and health metrics.

```typescript
interface Stats {
  /** Memory usage (MB) */
  memory_mb: number;

  /** CPU usage percentage */
  cpu_percent: number;

  /** Event buffer utilization */
  buffer: {
    current_size: number;   // Number of events currently stored
    max_size: number;       // Maximum capacity (500)
    utilization: number;    // Percentage (0.0-1.0)
  };

  /** Event distribution by type */
  event_distribution: Record<string, number>;  // { "window::new": 45, "workspace::focus": 12, ... }

  /** Diff computation performance */
  diff_stats: {
    avg_compute_time_ms: number;
    max_compute_time_ms: number;
    total_diffs_computed: number;
  };

  /** Daemon uptime (seconds) */
  uptime_seconds: number;

  /** Timestamp when stats were collected */
  timestamp: number;
}
```

---

## RPC Protocol Models

### JSON-RPC 2.0 Request

```typescript
interface RPCRequest {
  jsonrpc: "2.0";
  method: string;
  params?: Record<string, any>;
  id: string | number;
}
```

**Example**:
```json
{
  "jsonrpc": "2.0",
  "method": "query_events",
  "params": {"last": 10, "filter": "window::new"},
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

### JSON-RPC 2.0 Response

```typescript
type RPCResponse = RPCSuccessResponse | RPCErrorResponse;

interface RPCSuccessResponse {
  jsonrpc: "2.0";
  result: any;
  id: string | number;
}

interface RPCErrorResponse {
  jsonrpc: "2.0";
  error: RPCError;
  id: string | number | null;
}

interface RPCError {
  code: number;
  message: string;
  data?: any;
}
```

**Standard Error Codes**:
- `-32700` - Parse error (invalid JSON)
- `-32600` - Invalid Request (malformed RPC)
- `-32601` - Method not found
- `-32602` - Invalid params
- `-32603` - Internal error
- `-32000 to -32099` - Server-defined errors

---

## Query Parameters

### QueryEventsParams

```typescript
interface QueryEventsParams {
  /** Return last N events */
  last?: number;

  /** Return events since timestamp (ISO 8601 or human format "5m") */
  since?: string;

  /** Return events until timestamp (ISO 8601) */
  until?: string;

  /** Filter by event type (exact match or prefix, e.g., "window::" matches all window events) */
  filter?: string;
}
```

**Examples**:
```typescript
// Last 50 events
{ last: 50 }

// Events from last 5 minutes
{ since: "5m" }

// Only window creation events
{ filter: "window::new" }

// All window events from last hour
{ since: "1h", filter: "window::" }
```

---

### GetEventParams

```typescript
interface GetEventParams {
  /** Event ID (UUID) */
  event_id: string;
}
```

---

## CLI Output Models

### HistoryTableRow

Data structure for tabular history view.

```typescript
interface HistoryTableRow {
  id: string;
  timestamp: string;      // Formatted: "HH:MM:SS.mmm"
  type: string;
  changes: string;        // e.g., "3 changes (critical)"
  triggered_by: string;   // Correlation summary or "(no correlation)"
  confidence: string;     // Emoji indicator
}
```

---

### LiveEventDisplay

Real-time event stream display format.

```typescript
interface LiveEventDisplay {
  id: string;
  timestamp: string;      // Relative: "2s ago" or absolute: "HH:MM:SS"
  type: string;
  change_count: number;
  significance_label: string;
  correlation_summary?: string;
}
```

---

### DetailedEventView

Full event inspection view.

```typescript
interface DetailedEventView {
  /** Event metadata */
  metadata: {
    id: string;
    timestamp: string;
    type: string;
    significance: string;
  };

  /** Correlation section (if present) */
  correlation?: {
    action: string;
    command: string;
    time_delta: string;    // e.g., "150ms"
    confidence: string;    // Emoji + percentage
    reasoning: string;
  };

  /** Field-level diff */
  diff: Array<{
    path: string;
    change: string;        // e.g., "800 → 1200"
    significance: string;
  }>;

  /** Enrichment (if window event) */
  enrichment?: {
    pid: number;
    i3pm_vars: Record<string, string>;
    marks: string[];
  };
}
```

---

## Validation Rules

### Event Validation

```typescript
function validateEvent(event: any): event is Event {
  return (
    typeof event.id === "string" &&
    typeof event.timestamp === "number" &&
    typeof event.type === "string" &&
    typeof event.change_count === "number" &&
    typeof event.significance === "number" &&
    event.significance >= 0.0 &&
    event.significance <= 1.0
  );
}
```

### Time Filter Validation

```typescript
function validateTimeFilter(input: string): boolean {
  return /^\d+[smhd]$/.test(input);
}
```

### Event Type Filter Validation

```typescript
function validateEventTypeFilter(input: string): boolean {
  const validPrefixes = ["window::", "workspace::"];
  const validExact = [
    "window::new", "window::close", "window::focus", "window::title", "window::move",
    "workspace::focus", "workspace::init", "workspace::empty"
  ];

  return validExact.includes(input) || validPrefixes.some(p => input.startsWith(p));
}
```

---

## State Management

**Principle**: CLI is stateless. All state resides in daemon.

**No Client-Side State**:
- ❌ Event caching
- ❌ Filter history
- ❌ Connection pooling

**Client Responsibilities**:
- ✅ Parse user input
- ✅ Format daemon responses
- ✅ Render terminal UI
- ✅ Handle keyboard input

**Daemon Responsibilities** (existing Python backend):
- ✅ Event capture and storage (circular buffer)
- ✅ Diff computation
- ✅ Correlation analysis
- ✅ RPC server

---

## Relationships

```
Event (1) ──── (0..1) Correlation
  │
  ├─── (0..*) Diff
  │
  └─── (0..1) Enrichment

Stats ──── Event Distribution (aggregated)
```

**Key**:
- Event has optional correlation (1:0..1)
- Event has zero or more diffs (1:0..*)
- Event has optional enrichment if window-related (1:0..1)
- Stats aggregates event counts by type

---

## JSON Examples

### Event (Minimal)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1699564800000,
  "type": "workspace::focus",
  "change_count": 2,
  "significance": 0.85
}
```

### Event (Full with Correlation)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "timestamp": 1699564801500,
  "type": "window::new",
  "change_count": 5,
  "significance": 0.92,
  "correlation": {
    "action_type": "binding",
    "binding_command": "exec alacritty",
    "time_delta_ms": 150,
    "confidence": 0.95,
    "reasoning": "Window appeared 150ms after 'exec' binding"
  },
  "diff": [
    {
      "path": "app_id",
      "change_type": "added",
      "old_value": null,
      "new_value": "Alacritty",
      "significance": 0.9
    }
  ],
  "enrichment": {
    "pid": 12345,
    "i3pm_vars": {
      "APP_NAME": "alacritty",
      "APP_ID": "alacritty-nixos-123-456",
      "PROJECT_NAME": "nixos",
      "SCOPE": "scoped"
    },
    "marks": ["project:nixos", "app:alacritty"]
  }
}
```

### Stats

```json
{
  "memory_mb": 12.5,
  "cpu_percent": 0.8,
  "buffer": {
    "current_size": 342,
    "max_size": 500,
    "utilization": 0.684
  },
  "event_distribution": {
    "window::new": 45,
    "window::focus": 120,
    "workspace::focus": 23,
    "window::close": 38
  },
  "diff_stats": {
    "avg_compute_time_ms": 1.2,
    "max_compute_time_ms": 4.5,
    "total_diffs_computed": 342
  },
  "uptime_seconds": 3600,
  "timestamp": 1699564800000
}
```

---

## Summary

**Total Entities**: 5 core (Event, Correlation, Diff, Enrichment, Stats) + 3 RPC (Request, Response, Error)
**Relationships**: Event is the root entity with optional nested structures
**Validation**: Type guards for runtime validation of daemon responses
**State**: Stateless client, all data sourced from daemon RPC calls

**Next**: Generate JSON schemas for RPC methods in `/contracts/`
