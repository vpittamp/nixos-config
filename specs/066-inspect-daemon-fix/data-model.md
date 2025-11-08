# Data Model: Tree Monitor Inspect Command

**Feature**: 066-inspect-daemon-fix
**Date**: 2025-11-08
**Purpose**: Document RPC request/response schemas and type conversion flow for the daemon's `get_event` method

---

## Overview

This document defines the data structures exchanged between the TypeScript CLI client (`i3pm tree-monitor inspect`) and the Python daemon via JSON-RPC 2.0 over Unix domain sockets.

The core issue addressed: The CLI sends `event_id` as a string (from command-line arguments), but the daemon's event buffer lookup requires an integer. This document specifies the type conversion process and validates both request and response formats.

---

## RPC Protocol Foundation

**Protocol**: JSON-RPC 2.0
**Transport**: Unix domain socket (SOCK_STREAM)
**Message Format**: Newline-delimited JSON
**Socket Path**: `$XDG_RUNTIME_DIR/sway-tree-monitor.sock`
**Socket Permissions**: 0600 (owner read/write only)

### Request Format

All RPC requests follow JSON-RPC 2.0 specification:

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { ... },
  "id": "request-id"
}
```

### Response Format (Success)

```json
{
  "jsonrpc": "2.0",
  "result": { ... },
  "id": "request-id"
}
```

### Response Format (Error)

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": <error_code>,
    "message": "<error_message>",
    "data": "<optional_additional_data>"
  },
  "id": "request-id"
}
```

---

## GetEventRequest Schema

**RPC Method**: `get_event`

**Purpose**: Retrieve a single event from the circular buffer with optional detailed information (diff, enrichment, snapshots).

### Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event_id` | `string \| number` | Yes | Event ID to retrieve. Accepts both string (e.g., `"15"`) and integer (e.g., `15`) for flexibility. |
| `include_snapshots` | `boolean` | No | Include full tree snapshots (before/after states). Default: `false`. Large payloads (~5-10 KB per snapshot). |
| `include_enrichment` | `boolean` | No | Include I3PM enriched context (environment vars, project marks, PID). Default: `true`. |

### Type Conversion Flow

The daemon implements defensive type conversion in `rpc/server.py` lines 333-337:

```python
# Convert event_id to int (accept both string and int from RPC client)
try:
    event_id = int(event_id)
except (ValueError, TypeError):
    raise ValueError(f"Invalid event_id: must be an integer or numeric string, got {event_id!r}")
```

**Flow**:
1. CLI sends `event_id` as JSON string: `"15"`
2. Python `json.loads()` preserves type: `str("15")`
3. `int()` conversion succeeds: `int("15") → 15`
4. Buffer lookup uses integer: `buffer.get_event_by_id(15)`

**Error Cases**:
- `event_id = "abc"` → `ValueError: Invalid event_id: must be an integer or numeric string, got 'abc'`
- `event_id = 3.14` → `ValueError: Invalid event_id: must be an integer or numeric string, got 3.14`
- `event_id = null` → `ValueError: Missing required parameter: event_id`

### Request Examples

**Minimal Request** (event details only):
```json
{
  "jsonrpc": "2.0",
  "method": "get_event",
  "params": {
    "event_id": "15"
  },
  "id": 1
}
```

**With Snapshots** (for full tree state inspection):
```json
{
  "jsonrpc": "2.0",
  "method": "get_event",
  "params": {
    "event_id": 15,
    "include_snapshots": true,
    "include_enrichment": true
  },
  "id": 2
}
```

---

## GetEventResponse Schema

### Success Response Structure

```json
{
  "jsonrpc": "2.0",
  "result": {
    "event_id": 15,
    "timestamp_ms": 1699441234567,
    "event_type": "window::new",
    "sway_change": "new",
    "container_id": 6442450944,
    "diff": { ... },
    "correlations": [ ... ],
    "snapshots": { ... },
    "enrichment": { ... }
  },
  "id": 1
}
```

### Core Event Fields

| Field | Type | Description |
|-------|------|-------------|
| `event_id` | `int` | Unique monotonic ID (sequence number in buffer) |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds when event was captured |
| `event_type` | `string` | Sway event type (e.g., `"window::new"`, `"workspace::focus"`) |
| `sway_change` | `string` | Sway event 'change' field (e.g., `"new"`, `"focus"`, `"close"`) |
| `container_id` | `int \| null` | Sway container ID from event (window ID or workspace ID). May be `null` for certain events. |

### Diff Object

Contains field-level changes between snapshots:

```json
{
  "diff": {
    "diff_id": 14,
    "before_snapshot_id": 13,
    "after_snapshot_id": 15,
    "total_changes": 3,
    "significance_score": 0.85,
    "significance_level": "high",
    "computation_time_ms": 2.34,
    "node_changes": [
      {
        "node_id": "6442450944",
        "node_type": "con",
        "node_path": "outputs[0].workspaces[1].nodes[2]",
        "change_type": "added",
        "field_changes": [
          {
            "field_path": "rect.x",
            "old_value": null,
            "new_value": 100,
            "change_type": "added",
            "significance_score": 0.8
          },
          {
            "field_path": "name",
            "old_value": null,
            "new_value": "Alacritty",
            "change_type": "added",
            "significance_score": 1.0
          }
        ]
      }
    ]
  }
}
```

**Diff Fields**:
- `diff_id`: Unique ID for this diff computation
- `before_snapshot_id`: ID of previous snapshot
- `after_snapshot_id`: ID of current snapshot
- `total_changes`: Count of all field-level changes
- `significance_score`: Overall significance (0.0-1.0) based on change importance
- `significance_level`: Human-readable category: `"critical"`, `"high"`, `"medium"`, `"low"`, `"minimal"`
- `computation_time_ms`: Performance metric for diff algorithm
- `node_changes`: List of changed tree nodes with field-level details

**Significance Scoring**:
- **1.0 (Critical)**: Window added/removed, workspace created/deleted
- **0.75 (High)**: Focus change, major window movement
- **0.5 (Medium)**: Moderate geometry adjustment (>10px)
- **0.25 (Low)**: Minor geometry adjustment (<10px)
- **0.0 (Minimal)**: No user-visible change

### Correlations Array

User actions correlated with this tree change:

```json
{
  "correlations": [
    {
      "action": {
        "timestamp_ms": 1699441234500,
        "action_type": "binding",
        "binding_command": "workspace number 2",
        "input_type": "keybinding"
      },
      "confidence": 0.95,
      "confidence_level": "VeryLikely",
      "time_delta_ms": 67,
      "reasoning": "Temporal proximity (67ms) + semantic match (workspace command triggers focus event)"
    }
  ]
}
```

**Correlation Fields**:
- `action.timestamp_ms`: When the user action occurred
- `action.action_type`: Type of action (`"binding"`, `"ipc_command"`, `"keypress"`, `"mouse_click"`)
- `action.binding_command`: Sway command executed (for binding type)
- `confidence`: Confidence score (0.0-1.0)
- `confidence_level`: Human-readable confidence category
- `time_delta_ms`: Milliseconds between action and tree change
- `reasoning`: Explanation of how confidence was calculated

**Confidence Levels**:
- **>0.90**: "Caused by" - Very strong evidence of causation
- **0.70-0.90**: "Likely caused by" - High confidence
- **0.50-0.70**: "Possibly caused by" - Moderate confidence
- **<0.50**: "Unknown trigger" - Low confidence

### Snapshots Object (Optional)

Only included if `include_snapshots: true`:

```json
{
  "snapshots": {
    "before": null,
    "after": {
      "type": "root",
      "id": 0,
      "pid": null,
      "name": null,
      "rect": { "x": 0, "y": 0, "width": 1920, "height": 1080 },
      "focused": false,
      "focus": [1, 2, 3],
      "children": [ ... ],
      ...
    }
  }
}
```

**Note**: The daemon stores only the "after" snapshot (current state). The "before" snapshot is reconstructed from the previous event's "after" snapshot if needed.

### Enrichment Object (Optional)

Only included if `include_enrichment: true`:

```json
{
  "enrichment": {
    "6442450944": {
      "window_id": 6442450944,
      "pid": 12345,
      "i3pm_app_id": "alacritty",
      "i3pm_app_name": "Terminal",
      "i3pm_project_name": "nixos",
      "i3pm_scope": "scoped",
      "project_marks": ["project:nixos"],
      "app_marks": ["app:alacritty"],
      "launch_timestamp_ms": 1699441234400,
      "launch_action": "Key: Mod4+Return"
    },
    "6442450945": {
      "window_id": 6442450945,
      "pid": 12346,
      "i3pm_app_id": "firefox",
      "i3pm_app_name": "Firefox",
      "i3pm_project_name": null,
      "i3pm_scope": "global",
      "project_marks": [],
      "app_marks": ["app:firefox"],
      "launch_timestamp_ms": 1699441230000,
      "launch_action": null
    }
  }
}
```

**Enrichment Fields** (per window ID):
- `window_id`: Sway window ID
- `pid`: Process ID (from Sway tree)
- `i3pm_app_id`: Application identifier from environment
- `i3pm_app_name`: Human-readable app name
- `i3pm_project_name`: Associated project name (if scoped)
- `i3pm_scope`: Scope type (`"scoped"` or `"global"`)
- `project_marks`: Sway window marks starting with `project:`
- `app_marks`: Sway window marks starting with `app:`
- `launch_timestamp_ms`: When window was launched
- `launch_action`: User action that triggered launch

---

## Error Responses

### Missing event_id Parameter

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": "Missing required parameter: event_id"
  },
  "id": 1
}
```

### Invalid event_id Type

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": "Invalid event_id: must be an integer or numeric string, got 'abc'"
  },
  "id": 1
}
```

### Event Not Found

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32000,
    "message": "Event not found",
    "data": "Event ID 999 does not exist in buffer"
  },
  "id": 1
}
```

### RPC Protocol Errors

| Code | Message | Cause |
|------|---------|-------|
| `-32700` | Parse error | Invalid JSON sent by client |
| `-32600` | Invalid Request | Malformed RPC request |
| `-32601` | Method not found | Unknown method name |
| `-32603` | Internal error | Unexpected daemon error |
| `-32000` | Event not found | Event ID doesn't exist in buffer |

---

## Performance Characteristics

### Memory Usage Per Event

```
TreeEvent (complete):
  - event_id, timestamp_ms, event_type: 50 bytes
  - TreeDiff (for 3 field changes): 200 bytes
  - Correlations (1 action): 150 bytes
  - TreeSnapshot enrichment: 100-200 bytes per window (10-20 windows)
  ─────────────────────────────
  Total: ~5 KB per event
```

### Response Size Examples

```
Minimal response (no snapshots/enrichment):
  - Metadata + diff + correlations: 1-2 KB

With enrichment (10 windows):
  - Add 1-2 KB enrichment data: 2-4 KB total

With snapshots (2 full trees):
  - Add 5-10 KB snapshot data: 10-15 KB total
```

### Performance Targets

| Operation | Target | Typical |
|-----------|--------|---------|
| Buffer lookup by ID | <1ms | 0.1ms |
| Type conversion | <0.1ms | <0.01ms |
| JSON serialization | <1ms | 0.5ms |
| Unix socket write | <1ms | 0.2ms |
| **Total round-trip** | **<5ms** | **2-3ms** |

---

## Type System Summary

### TypeScript Client Types

```typescript
// Request
interface GetEventRequest {
  event_id: string | number;        // Flexible input
  include_snapshots?: boolean;
  include_enrichment?: boolean;
}

// Response
interface TreeEvent {
  event_id: number;
  timestamp_ms: number;
  event_type: string;
  sway_change: string;
  container_id: number | null;
  diff: TreeDiff;
  correlations: EventCorrelation[];
  snapshots?: SnapshotPair;
  enrichment?: Record<string, WindowContext>;
}

interface TreeDiff {
  diff_id: number;
  before_snapshot_id: number;
  after_snapshot_id: number;
  total_changes: number;
  significance_score: number;
  significance_level: "critical" | "high" | "medium" | "low" | "minimal";
  computation_time_ms: number;
  node_changes: NodeChange[];
}

interface NodeChange {
  node_id: string;
  node_type: string;
  node_path: string;
  change_type: "added" | "removed" | "modified";
  field_changes: FieldChange[];
}

interface FieldChange {
  field_path: string;
  old_value: any;
  new_value: any;
  change_type: "added" | "removed" | "modified";
  significance_score: number;
}

interface EventCorrelation {
  action: UserAction;
  confidence: number;
  confidence_level: string;
  time_delta_ms: number;
  reasoning: string;
}

interface UserAction {
  timestamp_ms: number;
  action_type: "binding" | "ipc_command" | "keypress" | "mouse_click";
  binding_command?: string;
  input_type: string;
}

interface WindowContext {
  window_id: number;
  pid: number | null;
  i3pm_app_id?: string;
  i3pm_app_name?: string;
  i3pm_project_name?: string | null;
  i3pm_scope?: string;
  project_marks: string[];
  app_marks: string[];
  launch_timestamp_ms?: number;
  launch_action?: string;
}
```

### Python Daemon Types

```python
# From models.py (Pydantic)
@dataclass
class TreeEvent:
    event_id: int                          # Must be int for buffer lookup
    timestamp_ms: int
    event_type: str
    sway_change: str
    container_id: Optional[int]
    snapshot: TreeSnapshot
    diff: TreeDiff
    correlations: List[EventCorrelation]

@dataclass
class TreeDiff:
    diff_id: int
    before_snapshot_id: int
    after_snapshot_id: int
    node_changes: List[NodeChange]
    computation_time_ms: float
    total_changes: int
    significance_score: float
    significance_level: str

@dataclass
class NodeChange:
    node_id: str
    node_type: str
    change_type: ChangeType
    field_changes: List[FieldChange]
    node_path: str

@dataclass
class FieldChange:
    field_path: str
    old_value: Any
    new_value: Any
    change_type: ChangeType
    significance_score: float

@dataclass
class WindowContext:
    window_id: int
    pid: Optional[int]
    i3pm_app_id: Optional[str]
    i3pm_app_name: Optional[str]
    i3pm_project_name: Optional[str]
    i3pm_scope: Optional[str]
    project_marks: List[str]
    app_marks: List[str]
    launch_timestamp_ms: Optional[int]
    launch_action: Optional[str]
```

---

## Integration Points

### CLI Integration

The TypeScript `tree-monitor inspect` command:
1. Accepts event ID from command line (string): `i3pm tree-monitor inspect 15`
2. Creates RPC request with `event_id: "15"`
3. Daemon converts to int and looks up event
4. CLI receives response and renders formatted output

### Buffer Integration

The daemon's `TreeEventBuffer`:
1. Stores events with integer IDs (0-499 in circular buffer)
2. Provides `get_event_by_id(event_id: int)` method
3. Returns `TreeEvent` if found, `None` if not found

### Serialization Flow

```
Python TreeEvent
    ↓
RPC Handler serialization (_serialize_node_changes, etc.)
    ↓
JSON dumps (event object)
    ↓
Unix socket write + newline
    ↓
TypeScript client reads + JSON parse
    ↓
TypeScript Event type
    ↓
UI Renderer (tree-monitor-detail.ts)
```

---

## Related Documents

- `/etc/nixos/specs/066-inspect-daemon-fix/contracts/rpc-protocol.json` - JSON-RPC 2.0 schema
- `/etc/nixos/specs/066-inspect-daemon-fix/quickstart.md` - User guide and examples
- `/etc/nixos/specs/065-i3pm-tree-monitor/data-model.md` - Full tree monitor data model
- `/etc/nixos/home-modules/tools/sway-tree-monitor/rpc/server.py` - Daemon RPC implementation
- `/etc/nixos/home-modules/tools/i3pm/src/ui/tree-monitor-detail.ts` - CLI response rendering
