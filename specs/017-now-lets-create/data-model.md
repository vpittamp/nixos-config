# Data Model: i3 Project System Monitor

**Branch**: `017-now-lets-create` | **Date**: 2025-10-20

## Overview

This document defines all data structures used by the i3 project system monitor tool. Models are organized by display mode and data source (daemon queries vs. i3 tree inspection).

## Core Display Models

### MonitorState

Represents the overall system state displayed in live mode.

```python
@dataclass
class MonitorState:
    """Top-level monitor state for live display mode."""

    # Connection
    daemon_connected: bool
    daemon_uptime_seconds: float
    connection_attempts: int = 0
    last_connection_error: Optional[str] = None

    # Active project
    active_project: Optional[str]
    is_global_mode: bool

    # Statistics
    total_windows: int
    tracked_windows: int  # Windows with project marks
    total_events_processed: int
    error_count: int

    # System info
    detected_monitors: List['MonitorEntry']
    active_workspaces: List[str]

    # Timestamps
    state_updated_at: datetime
```

**Source**: Constructed from daemon `get_status` JSON-RPC call combined with `list_monitors` call.

**Validation Rules**:
- `daemon_uptime_seconds` must be >= 0
- If `daemon_connected` is False, all other fields may be stale/cached
- `tracked_windows` <= `total_windows`

### WindowEntry

Represents a single window for display in windows list.

```python
@dataclass
class WindowEntry:
    """Window information for display."""

    # Identifiers
    window_id: int
    con_id: int

    # Window properties
    window_class: str
    window_title: str
    window_instance: str

    # Project tracking
    project: Optional[str]
    marks: List[str]

    # Location
    workspace: str
    output: str  # Monitor name
    floating: bool

    # State
    focused: bool
    visible: bool  # Not in scratchpad

    # Timestamps
    created: datetime
    last_focus: Optional[datetime]
```

**Source**: Daemon `get_windows` JSON-RPC call returns list of windows.

**Display Format**:
```
ID       Class       Title                     Project    WS   Output
─────────────────────────────────────────────────────────────────────
94558... Ghostty     ~/code/nixos             nixos      1    eDP-1
94562... code        NixOS Configuration      nixos      2    eDP-1
94578... firefox     Documentation            (none)     3    eDP-1
```

**Sorting**: By workspace number, then by focus timestamp (most recent first).

**Filtering**: Support filtering by project name in CLI (--project=nixos).

### MonitorEntry

Represents a physical display/output with workspace assignments.

```python
@dataclass
class MonitorEntry:
    """Monitor/output information for display."""

    # Identifiers
    name: str  # e.g., "eDP-1", "HDMI-1"

    # Properties
    width: int
    height: int
    refresh_rate: float  # Hz
    primary: bool

    # Workspace assignments
    assigned_workspaces: List[int]  # e.g., [1, 2] for primary monitor
    active_workspace: Optional[int]  # Currently visible workspace

    # State
    connected: bool
    enabled: bool
```

**Source**: New daemon JSON-RPC method `list_monitors` (to be implemented).

**Display Format**:
```
Monitor  Resolution    Workspaces    Primary    Active
──────────────────────────────────────────────────────
eDP-1    1920x1080@60  1, 2          ✓         WS 1
HDMI-1   2560x1440@60  3, 4, 5                 WS 3
```

### EventEntry

Represents a single event in the event stream or history.

```python
@dataclass
class EventEntry:
    """Event log entry for event stream display."""

    # Event metadata
    event_id: int  # Incremental ID for event ordering
    event_type: str  # "window::new", "window::close", "tick", "workspace::init"
    timestamp: datetime

    # Event payload (varies by type)
    window_id: Optional[int]
    window_class: Optional[str]
    workspace_name: Optional[str]
    project_name: Optional[str]
    tick_payload: Optional[str]

    # Processing info
    processing_duration_ms: float  # Time daemon took to handle event
    error: Optional[str]  # If event processing failed
```

**Source**: Daemon `get_events` JSON-RPC call with `{"limit": N, "event_type": "window"}` params.

**Storage**: Daemon maintains circular buffer of last 500 events in memory (FIFO).

**Display Format** (Live Event Stream):
```
TIME      TYPE             WINDOW     PROJECT    DETAILS
─────────────────────────────────────────────────────────────
14:23:45  window::new      94558      nixos      Ghostty
14:23:46  window::mark     94558      nixos      Applied project:nixos
14:23:50  window::close    94520      stacks     VS Code
14:23:51  tick             -          -          project:nixos
```

**Display Format** (History Mode):
```
[2025-10-20 14:23:45.123] window::new | window_id=94558 project=nixos class=Ghostty
[2025-10-20 14:23:46.456] window::mark | window_id=94558 marks=['project:nixos']
[2025-10-20 14:23:50.789] window::close | window_id=94520 project=stacks
```

### EventSubscription

Represents an active event subscription for streaming mode.

```python
@dataclass
class EventSubscription:
    """Active event subscription state."""

    # Subscription filter
    event_types: List[str]  # Empty list = all types

    # Buffer configuration
    buffer_size: int = 100  # Local buffer for smooth display updates

    # State
    subscribed_at: datetime
    events_received: int
    last_event_at: Optional[datetime]

    # Connection
    connection_active: bool
    reconnect_attempts: int = 0
```

**Source**: Local monitor tool state, not stored in daemon.

**Lifecycle**: Created when `subscribe_events` JSON-RPC call succeeds, maintained until connection lost.

## Tree Inspection Models

### TreeNode

Represents a node in the i3 window tree hierarchy.

```python
@dataclass
class TreeNode:
    """i3 window tree node for tree inspection mode."""

    # Node identity
    id: int
    type: str  # "root", "output", "workspace", "con", "floating_con"

    # Hierarchy
    parent_id: Optional[int]
    child_ids: List[int]

    # Properties
    name: str
    marks: List[str]
    focused: bool
    visible: bool

    # Container-specific (if type == "con")
    window_id: Optional[int]
    window_class: Optional[str]
    window_title: Optional[str]
    window_role: Optional[str]

    # Workspace-specific (if type == "workspace")
    workspace_num: Optional[int]
    workspace_output: Optional[str]

    # Layout
    layout: str  # "splith", "splitv", "tabbed", "stacked"
    border: str  # "normal", "pixel", "none"
    floating: str  # "auto_off", "auto_on", "user_off", "user_on"

    # Geometry
    rect: Dict[str, int]  # {"x": 0, "y": 0, "width": 1920, "height": 1080}
```

**Source**: i3 IPC `get_tree()` call via `i3ipc.aio.Connection`, not daemon mediated.

**Display Format** (Tree View):
```
TYPE           ID        MARKS              NAME/TITLE
──────────────────────────────────────────────────────────────
root           1         -                  root
├─ output      2         -                  eDP-1
│  ├─ workspace 4        -                  1
│  │  ├─ con   94558     project:nixos      Ghostty: ~/code/nixos
│  │  └─ con   94562     project:nixos      code: NixOS Configuration
│  └─ workspace 5        -                  2
│     └─ con   94578     -                  firefox: Documentation
└─ output      3         -                  __i3
   └─ workspace 6        -                  __i3_scratch
      └─ floating 94520  project:stacks     VS Code: Stacks
```

**Filtering**: Support expanding/collapsing subtrees, filtering by marks.

## Daemon State Extension

The daemon will need to track additional state to support the monitor tool.

### EventBuffer

Internal daemon structure for event storage (not exposed directly).

```python
class EventBuffer:
    """Circular buffer for event storage in daemon."""

    def __init__(self, max_size: int = 500):
        self.events: deque[EventEntry] = deque(maxlen=max_size)
        self.event_counter: int = 0

    def add_event(self, event: EventEntry) -> None:
        """Add event to buffer (FIFO, oldest evicted)."""
        self.events.append(event)
        self.event_counter += 1

    def get_events(
        self,
        limit: int = 100,
        event_type: Optional[str] = None
    ) -> List[EventEntry]:
        """Retrieve events with optional filtering."""
        filtered = self.events
        if event_type:
            filtered = [e for e in self.events if e.event_type.startswith(event_type)]
        return list(filtered)[-limit:]  # Most recent N events
```

**Integration**: Event handlers in `handlers.py` will call `event_buffer.add_event()` after processing each i3 event.

### SubscribedClients

Track clients subscribed to event notifications.

```python
@dataclass
class SubscribedClient:
    """Track subscribed client for event notifications."""

    writer: asyncio.StreamWriter
    event_types: List[str]  # Empty = all types
    subscribed_at: datetime
```

**Integration**: `IPCServer._handle_request()` will maintain `self.subscribed_clients: set[SubscribedClient]`.

## Data Flow Diagrams

### Live Mode Data Flow

```
┌──────────────┐
│ Monitor Tool │
│  (Live Mode) │
└──────┬───────┘
       │ 1. get_status
       ├──────────────────────┐
       │                      │
       │ 2. list_monitors     │
       ├──────────────────────┤
       │                      │
       │ 3. get_windows       │
       ├──────────────────────┤
       │                      ▼
       │              ┌───────────────┐
       │              │    Daemon     │
       │              │  IPC Server   │
       │              └───────┬───────┘
       │                      │
       │                      ├─ StateManager.get_stats()
       │                      ├─ StateManager.get_active_project()
       │                      ├─ StateManager.get_windows()
       │                      └─ i3.get_outputs()
       │                      │
       │ ◄────────────────────┤
       │    JSON responses    │
       ▼                      │
┌─────────────┐               │
│ Rich Live   │               │
│ Display     │◄──refresh@4Hz─┘
└─────────────┘
```

### Event Streaming Data Flow

```
┌──────────────┐
│ Monitor Tool │
│ (Event Mode) │
└──────┬───────┘
       │ 1. subscribe_events
       ├──────────────────────┐
       │                      ▼
       │              ┌───────────────┐
       │              │    Daemon     │
       │              │  IPC Server   │
       │              └───────┬───────┘
       │                      │
       │                      ├─ subscribed_clients.add(client)
       │                      │
       │                      ▼
       │              ┌───────────────┐
       │              │ Event Handlers│◄──i3 IPC events
       │              └───────┬───────┘
       │                      │
       │                      ├─ event_buffer.add_event()
       │                      ├─ broadcast_notification()
       │                      │
       │ ◄────────────────────┤
       │  JSON-RPC notification
       ▼                      │
┌─────────────┐               │
│ Event       │               │
│ Display     │◄──stream──────┘
└─────────────┘
```

## Validation and Constraints

### Window Entry Validation

- `window_id` must be unique within daemon state
- `workspace` must exist in i3 workspace list
- `project` must be None or match a known project name
- `marks` containing `project:X` must have `project` field set to `X`

### Event Entry Constraints

- `event_id` must be monotonically increasing
- `timestamp` must not be in the future
- `event_type` must match i3 event naming: `window::*`, `workspace::*`, `tick`, `shutdown`
- `processing_duration_ms` must be >= 0

### Monitor Entry Constraints

- `name` must be unique across all monitors
- `assigned_workspaces` must not overlap between monitors
- `active_workspace` must be in `assigned_workspaces` if not None
- `primary` must be true for exactly one monitor

## State Transitions

### Connection State Transitions

```
┌─────────────┐
│ Disconnected│
└──────┬──────┘
       │ connect_with_retry()
       ▼
┌─────────────┐
│ Connecting  │
└──────┬──────┘
       │ success
       ├──────────────┐
       │              │ failure, retries < 5
       │              ├──────────────┐
       │              │              │
       │              ▼              │
       │      ┌──────────────┐       │
       │      │   Retrying   │───────┘
       │      └──────────────┘
       │
       │ failure, retries >= 5
       ├──────────────┐
       │              │
       ▼              ▼
┌─────────────┐  ┌──────────┐
│  Connected  │  │  Failed  │
└──────┬──────┘  └──────────┘
       │
       │ connection lost
       └──────────────────────► Retrying
```

### Event Subscription State

```
┌────────────────┐
│  Unsubscribed  │
└────────┬───────┘
         │ subscribe_events()
         ▼
┌────────────────┐
│   Subscribed   │◄──────┐
└────────┬───────┘       │
         │               │
         │ events─────────┘
         │
         │ connection lost
         ▼
┌────────────────┐
│  Reconnecting  │
└────────┬───────┘
         │ success → re-subscribe
         └────────────────────► Subscribed
```

## Performance Considerations

### Memory Usage

- **EventBuffer**: 500 events × ~200 bytes/event = ~100KB
- **WindowEntry** list: 50 windows × ~300 bytes/window = ~15KB
- **TreeNode** cache: ~500 nodes × ~400 bytes/node = ~200KB
- **Total monitor tool memory**: < 5MB expected

### Update Frequency

- **Live mode**: Poll daemon every 250ms (4 Hz), acceptable latency
- **Event stream**: Push notifications as events occur (<100ms latency)
- **Tree inspection**: Single query on load, refresh on user request only

### Circular Buffer Performance

- `deque` with `maxlen` provides O(1) append and O(1) eviction
- Linear scan for filtering acceptable for 500 events (<1ms)

---

**Data Model Status**: ✅ Complete - All entities, validation rules, and data flows defined
