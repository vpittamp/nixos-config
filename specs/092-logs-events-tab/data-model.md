# Data Model: Real-Time Event Log and Activity Stream

**Feature**: 092-logs-events-tab
**Date**: 2025-11-23
**Phase**: 1 (Design & Contracts)

## Overview

This document defines the data structures for the event logging system, including raw Sway events, enriched events, event buffers, and filter state.

---

## Core Entities

### Event

Represents a single occurrence in the Sway window manager with optional i3pm daemon enrichment.

```python
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, Literal
from datetime import datetime

EventType = Literal[
    "window::new",
    "window::close",
    "window::focus",
    "window::move",
    "window::floating",
    "window::fullscreen_mode",
    "window::title",
    "window::mark",
    "window::urgent",
    "workspace::focus",
    "workspace::init",
    "workspace::empty",
    "workspace::move",
    "workspace::rename",
    "workspace::urgent",
    "workspace::reload",
    "output::unspecified",
    "binding::run",
    "mode::change",
    "shutdown::exit",
    "tick::manual",
]

class SwayEventPayload(BaseModel):
    """
    Raw Sway IPC event payload (varies by event type).

    Common fields:
    - container: Window/workspace/output container data
    - change: Type of change that occurred
    - current: Current state (for workspace/output focus events)
    - old: Previous state (for workspace/output focus events)
    """

    # Window events
    container: Optional[Dict[str, Any]] = None

    # Workspace events
    current: Optional[Dict[str, Any]] = None
    old: Optional[Dict[str, Any]] = None

    # Binding events
    binding: Optional[Dict[str, Any]] = None

    # Mode events
    change: Optional[str] = None
    pango_markup: Optional[bool] = None

    # Raw event data (catch-all)
    raw: Dict[str, Any] = Field(default_factory=dict)


class EventEnrichment(BaseModel):
    """
    i3pm daemon metadata enrichment for window-related events.

    Only populated for window::* events when i3pm daemon is available.
    """

    # Window identification
    window_id: Optional[int] = None
    pid: Optional[int] = None

    # App registry metadata
    app_name: Optional[str] = None  # From I3PM_APP_NAME or app registry
    app_id: Optional[str] = None    # Full app ID with instance suffix
    icon_path: Optional[str] = None  # Resolved icon file path

    # Project association
    project_name: Optional[str] = None  # i3pm project name
    scope: Optional[Literal["scoped", "global"]] = None

    # Workspace context
    workspace_number: Optional[int] = None
    workspace_name: Optional[str] = None
    output_name: Optional[str] = None

    # PWA detection
    is_pwa: bool = False  # True if workspace >= 50

    # Enrichment metadata
    daemon_available: bool = True  # False if i3pm daemon unreachable
    enrichment_latency_ms: Optional[float] = None  # Time to query daemon


class Event(BaseModel):
    """
    Complete event record with timestamp, type, payload, and enrichment.

    This is the primary data structure stored in the event buffer and
    sent to the Eww UI for display.
    """

    # Core event data
    timestamp: float  # Unix timestamp (seconds since epoch)
    timestamp_friendly: str  # Human-friendly relative time ("5s ago")
    event_type: EventType  # Sway event type (e.g., "window::new")
    change_type: Optional[str] = None  # Sub-type for some events (e.g., "new", "focus")

    # Event payload
    payload: SwayEventPayload

    # i3pm enrichment (optional)
    enrichment: Optional[EventEnrichment] = None

    # Display metadata
    icon: str  # Nerd Font icon for event type
    color: str  # Catppuccin Mocha color hex code

    # Categorization
    category: Literal["window", "workspace", "output", "binding", "mode", "system"]

    # Filtering support
    searchable_text: str  # Concatenated text for search (app_name, project, workspace, title)

    class Config:
        json_schema_extra = {
            "example": {
                "timestamp": 1700000000.123,
                "timestamp_friendly": "5 seconds ago",
                "event_type": "window::new",
                "change_type": "new",
                "payload": {
                    "container": {
                        "id": 12345,
                        "app_id": "terminal-nixos-123",
                        "title": "Terminal - ~/projects/nixos",
                    }
                },
                "enrichment": {
                    "window_id": 12345,
                    "pid": 67890,
                    "app_name": "terminal",
                    "project_name": "nixos",
                    "scope": "scoped",
                    "workspace_number": 1,
                    "is_pwa": False,
                    "daemon_available": True,
                    "enrichment_latency_ms": 15.3,
                },
                "icon": "󰖲",
                "color": "#89b4fa",
                "category": "window",
                "searchable_text": "terminal nixos 1 Terminal - ~/projects/nixos",
            }
        }
```

---

### EventFilter

Represents the current filter state applied to the event list.

```python
class EventFilter(BaseModel):
    """
    Filter criteria for event list display.

    Filters are applied in the frontend (Eww) via conditional visibility.
    Backend always sends all buffered events.
    """

    # Event type filter
    event_types: list[Literal["all", "window", "workspace", "output", "binding", "mode", "system"]] = ["all"]

    # Text search filter
    search_text: str = ""  # Case-insensitive substring match on searchable_text

    # Filter state
    active: bool = False  # Whether any filters are currently applied

    def matches(self, event: Event) -> bool:
        """
        Check if event passes filter criteria.

        Args:
            event: Event to check

        Returns:
            True if event should be displayed, False if filtered out
        """
        # Type filter
        if "all" not in self.event_types and event.category not in self.event_types:
            return False

        # Search filter
        if self.search_text and self.search_text.lower() not in event.searchable_text.lower():
            return False

        return True
```

---

### EventBuffer

Circular buffer for storing recent events with FIFO eviction.

```python
from collections import deque
from typing import List

class EventBuffer:
    """
    Circular buffer for event storage with automatic FIFO eviction.

    Uses Python deque with maxlen for O(1) append and automatic eviction.
    Thread-safe for single-writer scenarios (event loop).
    """

    def __init__(self, max_size: int = 500):
        """
        Initialize event buffer.

        Args:
            max_size: Maximum number of events to retain (default 500)
        """
        self._buffer: deque[Event] = deque(maxlen=max_size)
        self._max_size = max_size

    def append(self, event: Event) -> None:
        """
        Add event to buffer (automatically evicts oldest if full).

        Args:
            event: Event to append
        """
        self._buffer.append(event)

    def get_all(self) -> List[Event]:
        """
        Get all buffered events (oldest first, newest last).

        Returns:
            List of events in chronological order
        """
        return list(self._buffer)

    def get_filtered(self, filter_state: EventFilter) -> List[Event]:
        """
        Get filtered events matching criteria.

        Args:
            filter_state: Filter criteria to apply

        Returns:
            List of events matching filter (chronological order)
        """
        if not filter_state.active:
            return self.get_all()

        return [event for event in self._buffer if filter_state.matches(event)]

    def clear(self) -> None:
        """Clear all events from buffer."""
        self._buffer.clear()

    def size(self) -> int:
        """Get current buffer size."""
        return len(self._buffer)

    @property
    def max_size(self) -> int:
        """Get maximum buffer capacity."""
        return self._max_size
```

---

### EventsViewData

Response structure for `--mode events` backend query.

```python
class EventsViewData(BaseModel):
    """
    Complete response for events view mode.

    Sent from Python backend to Eww frontend via deflisten streaming.
    """

    # Response status
    status: Literal["ok", "error"]
    error: Optional[str] = None

    # Event data
    events: List[Event] = Field(default_factory=list)

    # Metadata
    event_count: int = 0  # Total events in buffer
    filtered_count: Optional[int] = None  # Count after filtering (if filter active)
    oldest_timestamp: Optional[float] = None  # Timestamp of oldest event
    newest_timestamp: Optional[float] = None  # Timestamp of newest event

    # System state
    daemon_available: bool = True  # i3pm daemon reachability
    ipc_connected: bool = True  # Sway IPC connection status

    # Timestamps
    timestamp: float  # Query execution time
    timestamp_friendly: str  # Human-friendly time

    class Config:
        json_schema_extra = {
            "example": {
                "status": "ok",
                "error": None,
                "events": [
                    # ... Event objects ...
                ],
                "event_count": 127,
                "filtered_count": None,
                "oldest_timestamp": 1699999000.0,
                "newest_timestamp": 1700000000.0,
                "daemon_available": True,
                "ipc_connected": True,
                "timestamp": 1700000000.5,
                "timestamp_friendly": "Just now",
            }
        }
```

---

## Eww Variable Schemas

### events_data

Eww variable storing the current events view data (updated via deflisten).

```yuck
; Type: EventsViewData (JSON)
(defvar events_data "{
  \"status\": \"ok\",
  \"events\": [],
  \"event_count\": 0,
  \"daemon_available\": true,
  \"ipc_connected\": true,
  \"timestamp\": 0,
  \"timestamp_friendly\": \"Loading...\"
}")
```

### event_filter_state

Eww variable tracking current filter state (managed by frontend).

```yuck
; Type: EventFilter (JSON)
(defvar event_filter_state "{
  \"event_types\": [\"all\"],
  \"search_text\": \"\",
  \"active\": false
}")
```

### scroll_at_bottom

Eww variable tracking scroll position for sticky scroll behavior.

```yuck
; Type: boolean
(defvar scroll_at_bottom true)
```

### events_paused

Eww variable indicating whether event stream is paused.

```yuck
; Type: boolean
(defvar events_paused false)
```

---

## Icon Mapping Reference

```python
EVENT_ICONS = {
    # Window events
    "window::new": {"icon": "󰖲", "color": "#89b4fa"},  # Blue
    "window::close": {"icon": "󰖶", "color": "#f38ba8"},  # Red
    "window::focus": {"icon": "󰋁", "color": "#74c7ec"},  # Sapphire
    "window::move": {"icon": "󰁔", "color": "#fab387"},  # Peach
    "window::floating": {"icon": "󰉈", "color": "#f9e2af"},  # Yellow
    "window::fullscreen_mode": {"icon": "󰊓", "color": "#cba6f7"},  # Mauve
    "window::title": {"icon": "󰓹", "color": "#a6adc8"},  # Subtext
    "window::mark": {"icon": "󰃀", "color": "#94e2d5"},  # Teal
    "window::urgent": {"icon": "󰀪", "color": "#f38ba8"},  # Red

    # Workspace events
    "workspace::focus": {"icon": "󱂬", "color": "#94e2d5"},  # Teal
    "workspace::init": {"icon": "󰐭", "color": "#a6e3a1"},  # Green
    "workspace::empty": {"icon": "󰭀", "color": "#6c7086"},  # Overlay
    "workspace::move": {"icon": "󰁔", "color": "#fab387"},  # Peach
    "workspace::rename": {"icon": "󰑕", "color": "#89dceb"},  # Sky
    "workspace::urgent": {"icon": "󰀪", "color": "#f38ba8"},  # Red
    "workspace::reload": {"icon": "󰑓", "color": "#a6e3a1"},  # Green

    # Output events
    "output::unspecified": {"icon": "󰍹", "color": "#cba6f7"},  # Mauve

    # Binding/mode events
    "binding::run": {"icon": "󰌌", "color": "#f9e2af"},  # Yellow
    "mode::change": {"icon": "󰘧", "color": "#89dceb"},  # Sky

    # System events
    "shutdown::exit": {"icon": "󰚌", "color": "#f38ba8"},  # Red
    "tick::manual": {"icon": "󰥔", "color": "#6c7086"},  # Overlay
}
```

---

## State Transitions

### Event Lifecycle

```
1. Sway generates event (window::new, workspace::focus, etc.)
   ↓
2. i3ipc.aio receives event via subscription
   ↓
3. Python event handler extracts event type and payload
   ↓
4. [IF window event] Query i3pm daemon for enrichment metadata
   ↓
5. Create Event object with timestamp, icon, color, searchable_text
   ↓
6. Append to EventBuffer (automatic FIFO eviction if len=500)
   ↓
7. Emit EventsViewData JSON to stdout (deflisten)
   ↓
8. Eww receives JSON update and re-renders UI
   ↓
9. Frontend applies EventFilter criteria (conditional visibility)
   ↓
10. User sees filtered event list with icons, timestamps, metadata
```

### Filter State Transitions

```
Initial State: event_filter_state = { event_types: ["all"], search_text: "", active: false }

User clicks "Window" filter:
  → event_filter_state = { event_types: ["window"], search_text: "", active: true }
  → UI re-renders with only window::* events visible

User types "firefox" in search box:
  → event_filter_state = { event_types: ["window"], search_text: "firefox", active: true }
  → UI re-renders with only window events containing "firefox"

User clears all filters:
  → event_filter_state = { event_types: ["all"], search_text: "", active: false }
  → UI shows all events
```

---

## Validation Rules

### Event Validation

1. **Timestamp**: Must be valid Unix timestamp (positive float)
2. **Event Type**: Must be one of predefined EventType literals
3. **Icon**: Must be non-empty Nerd Font character
4. **Color**: Must be valid hex color (#rrggbb)
5. **Searchable Text**: Must be non-empty for search functionality

### EventBuffer Validation

1. **Max Size**: Must be positive integer (default 500)
2. **Append**: Must accept any valid Event object
3. **FIFO**: Oldest events must be evicted when buffer full
4. **Thread Safety**: Single writer (event loop) guarantees consistency

### EventFilter Validation

1. **Event Types**: Must contain at least one valid category
2. **Search Text**: Can be empty (no filter) or non-empty string
3. **Active Flag**: Must reflect whether any filters are applied

---

## Performance Considerations

### Memory Usage

- **Event size**: ~500-1000 bytes per event (including enrichment)
- **Buffer capacity**: 500 events × 1KB = ~500KB maximum
- **Eww variable storage**: JSON serialization adds ~20% overhead
- **Total memory**: <1MB for event system (well under 50MB constraint)

### Latency Budget

- **Event enrichment**: <20ms per window event (daemon query)
- **Event batching**: 100ms debounce window (reduces UI updates)
- **Filter application**: <1ms per event (simple string matching)
- **UI rendering**: <10ms for 500 events (Eww GTK performance)
- **Total latency**: <100ms from event occurrence to UI display ✓

---

## Phase 1 Data Model Completion

**Status**: ✅ Complete

**Key Entities Defined**:
1. Event - Core event record with enrichment
2. EventFilter - Filter state and matching logic
3. EventBuffer - Circular buffer with FIFO eviction
4. EventsViewData - Backend response structure

**Next Phase**: Contract specification (API between Python backend and Eww frontend)
