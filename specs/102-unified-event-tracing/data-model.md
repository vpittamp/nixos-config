# Data Model: Unified Event Tracing System

**Feature**: 102-unified-event-tracing
**Date**: 2025-11-30
**Status**: Complete

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Event System Architecture                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────┐     ┌────────────────┐     ┌────────────────────────┐  │
│  │ EventBuffer    │────►│ EventEntry     │────►│ UnifiedEventType       │  │
│  │ (500 max)      │     │ (enhanced)     │     │ (enum, 35+ types)      │  │
│  └───────┬────────┘     └───────┬────────┘     └────────────────────────┘  │
│          │                      │                                           │
│          │ copy-on-evict        │ correlation_id                            │
│          ▼                      ▼                                           │
│  ┌────────────────┐     ┌────────────────┐     ┌────────────────────────┐  │
│  │ WindowTracer   │────►│ WindowTrace    │────►│ TraceEvent             │  │
│  │ (10 max)       │     │ (per window)   │     │ (1000 max per trace)   │  │
│  └────────────────┘     └───────┬────────┘     └────────────────────────┘  │
│                                 │                                           │
│                                 │ templates                                 │
│                                 ▼                                           │
│                         ┌────────────────┐                                  │
│                         │ TraceTemplate  │                                  │
│                         │ (3 built-in)   │                                  │
│                         └────────────────┘                                  │
│                                                                             │
│  ┌────────────────┐     ┌────────────────┐                                  │
│  │ Correlation    │────►│ CausalityChain │                                  │
│  │ Service        │     │ (visualization)│                                  │
│  └────────────────┘     └────────────────┘                                  │
│                                                                             │
│  ┌────────────────┐     ┌────────────────┐                                  │
│  │ OutputEvent    │────►│ OutputState    │                                  │
│  │ Service        │     │ (cached diff)  │                                  │
│  └────────────────┘     └────────────────┘                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Entity Definitions

### 1. UnifiedEventType (Enum)

**Purpose**: Single source of truth for all event types across Log and Trace views.

**Location**: `models/events.py`

```python
from enum import Enum

class EventSource(str, Enum):
    """Event origin classification."""
    SWAY = "sway"       # Raw Sway IPC events
    I3PM = "i3pm"       # i3pm daemon internal events

class EventCategory(str, Enum):
    """High-level event grouping for filters."""
    WINDOW = "window"
    WORKSPACE = "workspace"
    OUTPUT = "output"
    PROJECT = "project"
    VISIBILITY = "visibility"
    COMMAND = "command"
    LAUNCH = "launch"
    STATE = "state"
    TRACE = "trace"
    SYSTEM = "system"

class UnifiedEventType(str, Enum):
    """All event types unified across Log and Trace views."""

    # Window Events (Sway)
    WINDOW_NEW = "window::new"
    WINDOW_CLOSE = "window::close"
    WINDOW_FOCUS = "window::focus"
    WINDOW_BLUR = "window::blur"           # NEW: Logged to buffer
    WINDOW_MOVE = "window::move"
    WINDOW_FLOATING = "window::floating"
    WINDOW_FULLSCREEN = "window::fullscreen_mode"
    WINDOW_TITLE = "window::title"
    WINDOW_MARK = "window::mark"
    WINDOW_URGENT = "window::urgent"

    # Workspace Events (Sway)
    WORKSPACE_FOCUS = "workspace::focus"
    WORKSPACE_INIT = "workspace::init"
    WORKSPACE_EMPTY = "workspace::empty"
    WORKSPACE_MOVE = "workspace::move"
    WORKSPACE_RENAME = "workspace::rename"
    WORKSPACE_URGENT = "workspace::urgent"
    WORKSPACE_RELOAD = "workspace::reload"

    # Output Events (Enhanced)
    OUTPUT_CONNECTED = "output::connected"           # NEW
    OUTPUT_DISCONNECTED = "output::disconnected"     # NEW
    OUTPUT_PROFILE_CHANGED = "output::profile_changed"  # NEW
    OUTPUT_UNSPECIFIED = "output::unspecified"       # Fallback

    # Project Events (i3pm)
    PROJECT_SWITCH = "project::switch"
    PROJECT_CLEAR = "project::clear"

    # Visibility Events (i3pm)
    VISIBILITY_HIDDEN = "visibility::hidden"
    VISIBILITY_SHOWN = "visibility::shown"
    SCRATCHPAD_MOVE = "scratchpad::move"

    # Command Events (i3pm)
    COMMAND_QUEUED = "command::queued"
    COMMAND_EXECUTED = "command::executed"
    COMMAND_RESULT = "command::result"
    COMMAND_BATCH = "command::batch"

    # Launch Events (i3pm)
    LAUNCH_INTENT = "launch::intent"
    LAUNCH_NOTIFICATION = "launch::notification"
    LAUNCH_ENV_INJECTED = "launch::env_injected"
    LAUNCH_CORRELATED = "launch::correlated"

    # State Events (i3pm)
    STATE_SAVED = "state::saved"
    STATE_LOADED = "state::loaded"
    STATE_CONFLICT = "state::conflict"

    # Mark Events (i3pm)
    MARK_ADDED = "mark::added"
    MARK_REMOVED = "mark::removed"

    # Environment Events (i3pm)
    ENV_DETECTED = "env::detected"
    ENV_CHANGED = "env::changed"

    # Trace Events (i3pm)
    TRACE_START = "trace::start"
    TRACE_STOP = "trace::stop"
    TRACE_SNAPSHOT = "trace::snapshot"

    # System Events (Sway)
    BINDING_RUN = "binding::run"
    MODE_CHANGE = "mode::change"
    SHUTDOWN_EXIT = "shutdown::exit"
    TICK_MANUAL = "tick::manual"

    @classmethod
    def get_source(cls, event_type: "UnifiedEventType") -> EventSource:
        """Determine event source from type."""
        sway_types = {
            cls.WINDOW_NEW, cls.WINDOW_CLOSE, cls.WINDOW_FOCUS, cls.WINDOW_BLUR,
            cls.WINDOW_MOVE, cls.WINDOW_FLOATING, cls.WINDOW_FULLSCREEN,
            cls.WINDOW_TITLE, cls.WINDOW_MARK, cls.WINDOW_URGENT,
            cls.WORKSPACE_FOCUS, cls.WORKSPACE_INIT, cls.WORKSPACE_EMPTY,
            cls.WORKSPACE_MOVE, cls.WORKSPACE_RENAME, cls.WORKSPACE_URGENT,
            cls.WORKSPACE_RELOAD,
            cls.OUTPUT_CONNECTED, cls.OUTPUT_DISCONNECTED, cls.OUTPUT_PROFILE_CHANGED,
            cls.OUTPUT_UNSPECIFIED,
            cls.BINDING_RUN, cls.MODE_CHANGE, cls.SHUTDOWN_EXIT, cls.TICK_MANUAL,
        }
        return EventSource.SWAY if event_type in sway_types else EventSource.I3PM

    @classmethod
    def get_category(cls, event_type: "UnifiedEventType") -> EventCategory:
        """Determine event category from type."""
        categories = {
            EventCategory.WINDOW: {cls.WINDOW_NEW, cls.WINDOW_CLOSE, cls.WINDOW_FOCUS,
                                   cls.WINDOW_BLUR, cls.WINDOW_MOVE, cls.WINDOW_FLOATING,
                                   cls.WINDOW_FULLSCREEN, cls.WINDOW_TITLE, cls.WINDOW_MARK,
                                   cls.WINDOW_URGENT},
            EventCategory.WORKSPACE: {cls.WORKSPACE_FOCUS, cls.WORKSPACE_INIT,
                                      cls.WORKSPACE_EMPTY, cls.WORKSPACE_MOVE,
                                      cls.WORKSPACE_RENAME, cls.WORKSPACE_URGENT,
                                      cls.WORKSPACE_RELOAD},
            EventCategory.OUTPUT: {cls.OUTPUT_CONNECTED, cls.OUTPUT_DISCONNECTED,
                                   cls.OUTPUT_PROFILE_CHANGED, cls.OUTPUT_UNSPECIFIED},
            EventCategory.PROJECT: {cls.PROJECT_SWITCH, cls.PROJECT_CLEAR},
            EventCategory.VISIBILITY: {cls.VISIBILITY_HIDDEN, cls.VISIBILITY_SHOWN,
                                       cls.SCRATCHPAD_MOVE},
            EventCategory.COMMAND: {cls.COMMAND_QUEUED, cls.COMMAND_EXECUTED,
                                    cls.COMMAND_RESULT, cls.COMMAND_BATCH},
            EventCategory.LAUNCH: {cls.LAUNCH_INTENT, cls.LAUNCH_NOTIFICATION,
                                   cls.LAUNCH_ENV_INJECTED, cls.LAUNCH_CORRELATED},
            EventCategory.STATE: {cls.STATE_SAVED, cls.STATE_LOADED, cls.STATE_CONFLICT},
            EventCategory.TRACE: {cls.TRACE_START, cls.TRACE_STOP, cls.TRACE_SNAPSHOT,
                                  cls.MARK_ADDED, cls.MARK_REMOVED, cls.ENV_DETECTED,
                                  cls.ENV_CHANGED},
            EventCategory.SYSTEM: {cls.BINDING_RUN, cls.MODE_CHANGE, cls.SHUTDOWN_EXIT,
                                   cls.TICK_MANUAL},
        }
        for category, types in categories.items():
            if event_type in types:
                return category
        return EventCategory.SYSTEM
```

**Validation Rules**:
- Event type strings must match `category::subtype` format
- Source is derived from type, not stored separately
- Category is derived from type, not stored separately

### 2. EventEntry (Extended)

**Purpose**: Single event in the Log tab buffer with correlation and trace references.

**Location**: `models/legacy.py` (extended)

```python
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Dict, Any
from .events import UnifiedEventType, EventSource

@dataclass
class EventEntry:
    """Event entry in the circular buffer."""

    # Metadata (always present)
    event_id: int                                # Incremental ID
    event_type: str                              # UnifiedEventType value
    timestamp: datetime                          # When event occurred
    source: str                                  # EventSource value ("sway" or "i3pm")
    processing_duration_ms: float = 0.0          # Handler execution time
    error: Optional[str] = None                  # Error if processing failed

    # NEW: Correlation and tracing
    correlation_id: Optional[str] = None         # UUID linking related events
    causality_depth: int = 0                     # Nesting level (0 = root)
    trace_id: Optional[str] = None               # Reference to active trace (if any)

    # Source context
    client_pid: Optional[int] = None             # PID of triggering IPC client

    # Window events
    window_id: Optional[int] = None
    window_class: Optional[str] = None
    window_title: Optional[str] = None
    window_instance: Optional[str] = None
    workspace_name: Optional[str] = None

    # Project events
    project_name: Optional[str] = None
    project_directory: Optional[str] = None
    old_project: Optional[str] = None            # For project::switch
    new_project: Optional[str] = None            # For project::switch
    windows_affected: Optional[int] = None       # Count of affected windows

    # Command events (NEW)
    command_text: Optional[str] = None           # Sway command text
    command_success: Optional[bool] = None       # Execution result
    command_error: Optional[str] = None          # Error message if failed
    batch_count: Optional[int] = None            # For command::batch

    # Output events (ENHANCED)
    output_name: Optional[str] = None
    output_count: Optional[int] = None
    old_output_state: Optional[Dict[str, Any]] = None  # For diff
    new_output_state: Optional[Dict[str, Any]] = None  # For diff

    # Other existing fields...
    tick_payload: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Serialize for JSON output."""
        return {k: v for k, v in {
            "event_id": self.event_id,
            "event_type": self.event_type,
            "timestamp": self.timestamp.isoformat(),
            "source": self.source,
            "processing_duration_ms": self.processing_duration_ms,
            "error": self.error,
            "correlation_id": self.correlation_id,
            "causality_depth": self.causality_depth,
            "trace_id": self.trace_id,
            "window_id": self.window_id,
            "window_class": self.window_class,
            "window_title": self.window_title,
            "workspace_name": self.workspace_name,
            "project_name": self.project_name,
            "old_project": self.old_project,
            "new_project": self.new_project,
            "windows_affected": self.windows_affected,
            "command_text": self.command_text,
            "command_success": self.command_success,
            "command_error": self.command_error,
            "batch_count": self.batch_count,
            "output_name": self.output_name,
        }.items() if v is not None}
```

**Validation Rules**:
- `event_id` is auto-incremented by EventBuffer
- `event_type` must be a valid UnifiedEventType value
- `correlation_id` is UUID v4 format if present
- `causality_depth` >= 0, with 0 being root event
- `trace_id` references existing WindowTrace if present

### 3. TraceTemplate

**Purpose**: Pre-configured trace settings for common debugging scenarios.

**Location**: `services/window_tracer.py`

```python
from dataclasses import dataclass
from typing import List, Optional, Dict, Any
from .events import UnifiedEventType, EventCategory

@dataclass
class TraceTemplate:
    """Pre-configured trace template for common scenarios."""

    template_id: str                             # Unique identifier
    name: str                                    # Display name
    description: str                             # User-facing description

    # Matching criteria
    match_focused: bool = False                  # Trace currently focused window
    match_all_scoped: bool = False               # Trace all scoped windows
    match_app_id: Optional[str] = None           # Match by app_id
    match_class: Optional[str] = None            # Match by window class

    # Event filtering
    enabled_categories: List[EventCategory] = field(default_factory=list)
    enabled_types: List[UnifiedEventType] = field(default_factory=list)

    # Timing
    timeout_seconds: int = 60                    # Auto-stop timeout
    pre_launch: bool = False                     # Start before window exists

    def to_dict(self) -> Dict[str, Any]:
        return {
            "template_id": self.template_id,
            "name": self.name,
            "description": self.description,
            "match_focused": self.match_focused,
            "match_all_scoped": self.match_all_scoped,
            "match_app_id": self.match_app_id,
            "match_class": self.match_class,
            "enabled_categories": [c.value for c in self.enabled_categories],
            "enabled_types": [t.value for t in self.enabled_types],
            "timeout_seconds": self.timeout_seconds,
            "pre_launch": self.pre_launch,
        }

# Built-in templates
TRACE_TEMPLATES = [
    TraceTemplate(
        template_id="debug-app-launch",
        name="Debug App Launch",
        description="Pre-launch trace with lifecycle events enabled, 60s timeout",
        pre_launch=True,
        timeout_seconds=60,
        enabled_categories=[
            EventCategory.WINDOW,
            EventCategory.LAUNCH,
            EventCategory.VISIBILITY,
        ],
    ),
    TraceTemplate(
        template_id="debug-project-switch",
        name="Debug Project Switch",
        description="Trace all scoped windows with visibility and command events",
        match_all_scoped=True,
        timeout_seconds=30,
        enabled_categories=[
            EventCategory.PROJECT,
            EventCategory.VISIBILITY,
            EventCategory.COMMAND,
        ],
    ),
    TraceTemplate(
        template_id="debug-focus-chain",
        name="Debug Focus Chain",
        description="Capture focus/blur events only for focused window",
        match_focused=True,
        timeout_seconds=60,
        enabled_types=[
            UnifiedEventType.WINDOW_FOCUS,
            UnifiedEventType.WINDOW_BLUR,
        ],
    ),
]
```

### 4. CausalityChain

**Purpose**: Visual grouping of related events by correlation_id.

**Location**: `services/window_tracer.py`

```python
from dataclasses import dataclass, field
from typing import List
from datetime import datetime

@dataclass
class CausalityChain:
    """Group of events linked by correlation_id."""

    correlation_id: str                          # UUID linking events
    root_event_id: int                           # First event in chain
    events: List[EventEntry] = field(default_factory=list)

    @property
    def duration_ms(self) -> float:
        """Total duration from first to last event."""
        if len(self.events) < 2:
            return 0.0
        first = min(e.timestamp for e in self.events)
        last = max(e.timestamp for e in self.events)
        return (last - first).total_seconds() * 1000

    @property
    def depth(self) -> int:
        """Maximum nesting depth in chain."""
        return max(e.causality_depth for e in self.events) if self.events else 0

    @property
    def summary(self) -> str:
        """Human-readable chain summary."""
        if not self.events:
            return "Empty chain"
        root = self.events[0]
        return f"{root.event_type} → {len(self.events)} events, {self.duration_ms:.1f}ms"

    def to_dict(self) -> dict:
        return {
            "correlation_id": self.correlation_id,
            "root_event_id": self.root_event_id,
            "event_count": len(self.events),
            "duration_ms": self.duration_ms,
            "depth": self.depth,
            "summary": self.summary,
            "events": [e.to_dict() for e in self.events],
        }
```

### 5. OutputState

**Purpose**: Cached output configuration for state diffing.

**Location**: `services/output_event_service.py`

```python
from dataclasses import dataclass
from typing import Optional, Dict, Any

@dataclass
class OutputState:
    """Cached state of a Sway output for diffing."""

    name: str                                    # Output name (e.g., "eDP-1")
    active: bool                                 # Whether output is enabled
    dpms: bool                                   # DPMS state
    current_mode: Optional[str] = None           # Resolution mode
    transform: Optional[str] = None              # Rotation/transform
    scale: float = 1.0                           # Scale factor
    rect: Optional[Dict[str, int]] = None        # Position/size

    @classmethod
    def from_sway(cls, output: dict) -> "OutputState":
        """Create from swaymsg -t get_outputs response."""
        return cls(
            name=output.get("name", "unknown"),
            active=output.get("active", False),
            dpms=output.get("dpms", True),
            current_mode=output.get("current_mode", {}).get("width"),
            transform=output.get("transform"),
            scale=output.get("scale", 1.0),
            rect=output.get("rect"),
        )

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "active": self.active,
            "dpms": self.dpms,
            "current_mode": self.current_mode,
            "transform": self.transform,
            "scale": self.scale,
        }

@dataclass
class OutputDiff:
    """Detected change between two output states."""

    output_name: str
    change_type: str                             # "connected", "disconnected", "profile_changed"
    old_state: Optional[OutputState] = None
    new_state: Optional[OutputState] = None

    @property
    def event_type(self) -> str:
        """Map to UnifiedEventType."""
        mapping = {
            "connected": "output::connected",
            "disconnected": "output::disconnected",
            "profile_changed": "output::profile_changed",
        }
        return mapping.get(self.change_type, "output::unspecified")
```

### 6. CorrelationContext

**Purpose**: Manage correlation_id propagation through async context.

**Location**: `services/correlation_service.py`

```python
import contextvars
import uuid
from typing import Optional
from dataclasses import dataclass

# Context variable for correlation tracking
_correlation_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    'correlation_id', default=None
)
_causality_depth: contextvars.ContextVar[int] = contextvars.ContextVar(
    'causality_depth', default=0
)

@dataclass
class CorrelationContext:
    """Context for tracking event correlation."""

    correlation_id: str
    causality_depth: int

    @classmethod
    def current(cls) -> Optional["CorrelationContext"]:
        """Get current correlation context."""
        cid = _correlation_id.get()
        if cid is None:
            return None
        return cls(
            correlation_id=cid,
            causality_depth=_causality_depth.get(),
        )

    @classmethod
    def new_root(cls) -> "CorrelationContext":
        """Create new root correlation context."""
        cid = str(uuid.uuid4())
        _correlation_id.set(cid)
        _causality_depth.set(0)
        return cls(correlation_id=cid, causality_depth=0)

    @classmethod
    def enter_child(cls) -> Optional["CorrelationContext"]:
        """Enter child context (increment depth)."""
        cid = _correlation_id.get()
        if cid is None:
            return None
        depth = _causality_depth.get() + 1
        _causality_depth.set(depth)
        return cls(correlation_id=cid, causality_depth=depth)

    @classmethod
    def exit_child(cls) -> None:
        """Exit child context (decrement depth)."""
        depth = _causality_depth.get()
        if depth > 0:
            _causality_depth.set(depth - 1)

    @classmethod
    def clear(cls) -> None:
        """Clear correlation context."""
        _correlation_id.set(None)
        _causality_depth.set(0)
```

## State Transitions

### Event Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Created   │────►│   Buffered  │────►│   Streamed  │────►│   Evicted   │
│             │     │             │     │             │     │             │
└─────────────┘     └──────┬──────┘     └─────────────┘     └──────┬──────┘
                          │                                        │
                          │ if traced                              │ copy-on-evict
                          ▼                                        ▼
                   ┌─────────────┐                         ┌─────────────┐
                   │   Traced    │                         │  Preserved  │
                   │             │                         │  (in trace) │
                   └─────────────┘                         └─────────────┘
```

### Trace Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Created   │────►│   Active    │────►│   Stopped   │
│ (template)  │     │ (recording) │     │ (archived)  │
└─────────────┘     └──────┬──────┘     └─────────────┘
                          │
                          │ window closed
                          ▼
                   ┌─────────────┐
                   │ Auto-stopped│
                   │(w/ summary) │
                   └─────────────┘
```

## Relationships

```
EventBuffer (1) ─────contains─────► (N) EventEntry
EventEntry (N) ─────references─────► (1) WindowTrace (optional)
EventEntry (N) ─────shares─────► (1) correlation_id (CausalityChain)
WindowTracer (1) ─────manages─────► (N) WindowTrace (max 10)
WindowTrace (1) ─────contains─────► (N) TraceEvent (max 1000)
TraceTemplate (1) ─────creates─────► (1) WindowTrace
OutputEventService (1) ─────caches─────► (N) OutputState
CorrelationContext (1) ─────propagates─────► (N) EventEntry
```

## Filter Categories (UI)

```yaml
filters:
  window_events:
    - window::new
    - window::close
    - window::focus
    - window::blur      # NEW
    - window::move
    - window::floating
    - window::fullscreen_mode
    - window::title
    - window::mark
    - window::urgent

  workspace_events:
    - workspace::focus
    - workspace::init
    - workspace::empty
    - workspace::move
    - workspace::rename
    - workspace::urgent
    - workspace::reload

  output_events:        # ENHANCED
    - output::connected     # NEW
    - output::disconnected  # NEW
    - output::profile_changed  # NEW
    - output::unspecified

  i3pm_events:          # NEW CATEGORY
    - project::switch
    - project::clear
    - visibility::hidden
    - visibility::shown
    - scratchpad::move
    - command::queued
    - command::executed
    - command::result
    - command::batch
    - launch::intent
    - launch::notification
    - launch::env_injected
    - launch::correlated
    - state::saved
    - state::loaded
    - state::conflict
    - mark::added
    - mark::removed
    - env::detected
    - env::changed
    - trace::start
    - trace::stop
    - trace::snapshot

  system_events:
    - binding::run
    - mode::change
    - shutdown::exit
    - tick::manual
```
