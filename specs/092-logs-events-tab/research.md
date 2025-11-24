# Research: Real-Time Event Log and Activity Stream

**Feature**: 092-logs-events-tab
**Date**: 2025-11-23
**Phase**: 0 (Outline & Research)

## Research Questions & Decisions

### Q1: Event Subscription Strategy

**Question**: Should we create a dedicated event listener service or extend the existing monitoring_data.py script with event mode?

**Decision**: **Extend monitoring_data.py with `--mode events` flag**

**Rationale**:
- Feature 085 already implements deflisten architecture with i3ipc.aio event subscriptions
- monitoring_data.py has `--mode windows|projects|apps|health` pattern - adding `events` mode is consistent
- Avoids duplication of connection management, reconnection logic, signal handling
- Single backend script simplifies systemd service management (one eww-monitoring-panel service)
- Event enrichment can reuse existing DaemonClient connection patterns

**Alternatives Considered**:
1. **New dedicated service** (`eww-event-stream.service`) - Rejected: adds complexity, duplicates reconnection/error handling, requires additional systemd service management
2. **Reuse sway-tree-monitor** (Feature 064) - Rejected: that service focuses on tree diffs, not raw events; different use case

**Implementation Notes**:
- Add `query_events_data()` and `stream_events()` functions to monitoring_data.py
- Event mode uses same deflisten pattern as windows mode (i3ipc.aio subscriptions)
- Circular buffer implemented in Python (collections.deque with maxlen=500)

---

### Q2: Event Enrichment Architecture

**Question**: How do we enrich raw Sway IPC events with i3pm daemon metadata (project associations, scope, app registry)?

**Decision**: **Query i3pm daemon on-demand per event via DaemonClient**

**Rationale**:
- i3pm daemon is authoritative source for project associations (Constitution Principle XI)
- DaemonClient already exists in monitoring_data.py for windows/projects modes
- Enrichment adds <20ms latency per event (within SC-008 budget)
- Daemon query provides fresh data (no stale cache issues)

**Alternatives Considered**:
1. **Cache window metadata** - Rejected: cache invalidation complexity, stale data risk, daemon state changes asynchronously
2. **Parse /proc/<pid>/environ directly** - Rejected: requires PID lookup, less reliable than daemon query, duplicates daemon logic
3. **No enrichment (raw events only)** - Rejected: loses critical context (project names, scope classification), defeats debugging value proposition

**Implementation Notes**:
- For each window-related event (window::new, window::focus, window::close):
  1. Extract window ID from Sway event payload
  2. Call `daemon.get_window_tree()` to get window metadata
  3. Match window ID to find project, scope, app_name
  4. Merge enrichment into event payload
- For workspace/output events: minimal enrichment (workspace number, output name)
- Graceful degradation: if daemon unavailable, show raw event without enrichment (user warning in UI)

---

### Q3: Event Buffer Implementation

**Question**: What data structure and eviction strategy should we use for the 500-event circular buffer?

**Decision**: **Python collections.deque with maxlen=500 (FIFO automatic eviction)**

**Rationale**:
- `deque` provides O(1) append and popleft operations
- `maxlen` parameter automatically evicts oldest when buffer full (FIFO)
- Thread-safe for single-writer scenarios (our event loop)
- Memory-efficient (no manual resize logic required)
- Standard library (no external dependencies)

**Alternatives Considered**:
1. **List with manual slicing** - Rejected: O(n) eviction, manual index management, error-prone
2. **Ring buffer with explicit index** - Rejected: unnecessary complexity, deque handles this natively
3. **SQLite in-memory database** - Rejected: overkill for simple FIFO buffer, adds query overhead

**Implementation Notes**:
```python
from collections import deque

event_buffer = deque(maxlen=500)  # Automatic FIFO eviction

# Append new event (automatically evicts oldest if len=500)
event_buffer.append({
    "timestamp": time.time(),
    "type": "window::new",
    "payload": {...},
    "enrichment": {...}
})

# Convert to list for JSON serialization
events_list = list(event_buffer)  # Newest at end, oldest at start
```

---

### Q4: Event Filtering Strategy

**Question**: Should filtering happen backend (Python) or frontend (Eww/Yuck)?

**Decision**: **Hybrid approach - backend provides all events, frontend filters in Eww Yuck expressions**

**Rationale**:
- Eww `for` loops support conditional rendering via `(box :visible {condition})`
- Frontend filtering enables instant response (<200ms per SC-002) without backend round-trip
- Backend sends all buffered events - frontend decides what to display
- Simpler backend logic (no filter state management)
- Filter state persists in Eww variables (eww update event_filter="window")

**Alternatives Considered**:
1. **Backend filtering with query parameters** - Rejected: requires backend state management, slower filter updates (IPC round-trip), complicates streaming deflisten
2. **Pure frontend with client-side buffer** - Rejected: Eww variables not suited for large buffers, limited string manipulation capabilities

**Implementation Notes**:
- Backend sends all 500 events in JSON response
- Eww variables track filter state:
  ```yuck
  (defvar event_filter_type "all")         ; "all" | "window" | "workspace" | "output"
  (defvar event_filter_search "")          ; Text search string
  ```
- Eww widgets use conditional visibility:
  ```yuck
  (for event in {events_data.events}
    (box
      :visible {(event_filter_type == "all" || event.type matches event_filter_type)
                && (event_filter_search == "" || event.payload matches event_filter_search)}
      (event-card :event event)))
  ```

---

### Q5: Scroll Behavior Implementation

**Question**: How do we implement "sticky scroll" (auto-scroll to bottom only when user is at bottom)?

**Decision**: **Eww scroll widget with auto-scroll tracking via Yuck expressions**

**Rationale**:
- Eww `scroll` widget supports :vscroll property and scroll callbacks
- Can detect if user scrolled up (not at bottom) vs at bottom
- Use Eww variable to track scroll state: `scroll_at_bottom` (boolean)
- Only auto-scroll when `scroll_at_bottom == true`

**Alternatives Considered**:
1. **Always auto-scroll** - Rejected: disrupts user reading historical events (FR-019 violation)
2. **Never auto-scroll** - Rejected: loses real-time streaming value
3. **Manual scroll-to-bottom button** - Rejected: extra UI complexity, user must remember to click

**Implementation Notes**:
```yuck
(defvar scroll_at_bottom true)  ; Track scroll position

(scroll
  :vscroll true
  :hscroll false
  :vexpand true
  :onscroll "eww update scroll_at_bottom={scrolled_to_bottom}"  ; Callback to update state
  (box :orientation "v"
    (for event in {events_data.events}
      (event-card :event event))
    ; Auto-scroll trigger (conditional on scroll_at_bottom)
    (label :text "" :visible {scroll_at_bottom})))  ; Forces scroll update
```

Note: Exact Eww scroll API may require testing - if callbacks insufficient, fallback to periodic polling.

---

### Q6: Event Type Icons

**Question**: What icon set should we use for event type indicators?

**Decision**: **Nerd Fonts icons (already available in system)**

**Rationale**:
- Nerd Fonts already installed on system (used in other UI elements)
- Comprehensive icon coverage for all event types
- No additional dependencies
- Catppuccin Mocha color coding for visual distinction

**Icon Mapping**:
| Event Type | Icon | Color (Catppuccin Mocha) |
|------------|------|--------------------------|
| window::new | 󰖲 | Blue (#89b4fa) |
| window::close | 󰖶 | Red (#f38ba8) |
| window::focus | 󰋁 | Sapphire (#74c7ec) |
| window::move | 󰁔 | Peach (#fab387) |
| workspace::focus | 󱂬 | Teal (#94e2d5) |
| workspace::init | 󰐭 | Green (#a6e3a1) |
| workspace::empty | 󰭀 | Overlay (#6c7086) |
| output::unspecified | 󰍹 | Mauve (#cba6f7) |
| binding::run | 󰌌 | Yellow (#f9e2af) |
| mode::change | 󰘧 | Sky (#89dceb) |

**Alternatives Considered**:
1. **Unicode emoji** - Rejected: inconsistent rendering across terminals, limited selection
2. **SVG icons** - Rejected: Eww GTK widget complexity, file management overhead
3. **ASCII symbols** - Rejected: poor visual distinction, unprofessional appearance

---

### Q7: Performance Optimization for High Event Volume

**Question**: How do we maintain 30fps UI rendering at 50+ events/second (SC-003)?

**Decision**: **Event batching with 100ms debounce window**

**Rationale**:
- Sway generates bursts of events (e.g., project switch: 5-10 events in 50ms)
- UI rendering is expensive (GTK reflow on each update)
- Batching events reduces UI updates from 50/sec to 10/sec
- 100ms debounce imperceptible to humans (within <100ms latency budget from SC-001)

**Implementation Pattern**:
```python
event_batch = []
last_emit_time = 0
BATCH_WINDOW_MS = 100

async def on_sway_event(event):
    global event_batch, last_emit_time

    # Add to batch
    enriched = await enrich_event(event)
    event_batch.append(enriched)

    # Emit batch if window expired
    now = time.time() * 1000  # milliseconds
    if now - last_emit_time >= BATCH_WINDOW_MS:
        emit_events_to_ui(event_batch)
        event_batch = []
        last_emit_time = now
```

**Alternatives Considered**:
1. **No batching (emit every event)** - Rejected: 50+ UI updates/sec causes frame drops, high CPU
2. **Larger batch window (500ms)** - Rejected: violates <100ms latency goal (SC-001)
3. **Adaptive batching** - Rejected: unnecessary complexity for MVP

---

## Technology Stack Summary

### Backend (Python)

| Component | Technology | Version | Justification |
|-----------|-----------|---------|---------------|
| Language | Python | 3.11+ | Constitution Principle X mandate |
| Event Subscriptions | i3ipc.aio | Latest | Async Sway IPC client |
| Event Loop | asyncio | stdlib | Async/await pattern |
| Data Validation | Pydantic | Latest | Event schema validation |
| Circular Buffer | collections.deque | stdlib | O(1) FIFO eviction |
| Daemon Client | DaemonClient | (existing) | Reuse from monitoring_data.py |

### Frontend (Eww)

| Component | Technology | Version | Justification |
|-----------|-----------|---------|---------------|
| UI Framework | Eww (Yuck/GTK) | 0.4+ | Existing monitoring panel |
| Icons | Nerd Fonts | (system) | Already available |
| Theme | Catppuccin Mocha | (existing) | Unified bar system (Feature 057) |
| Data Streaming | deflisten | (Eww builtin) | Real-time JSON stream |

### Testing (pytest)

| Component | Technology | Version | Justification |
|-----------|-----------|---------|---------------|
| Test Framework | pytest | Latest | Constitution Principle X |
| Async Testing | pytest-asyncio | Latest | Test async event handlers |
| Mocking | pytest-mock | Latest | Mock i3ipc connections |
| Coverage | pytest-cov | Latest | Ensure >80% test coverage |

---

## Best Practices Reference

### From Feature 085 (Monitoring Panel)

- **deflisten architecture**: Backend script with `--listen` flag, Eww `deflisten` command
- **Reconnection pattern**: Exponential backoff (1s, 2s, 4s, max 10s)
- **Signal handling**: SIGTERM, SIGINT for graceful shutdown; SIGPIPE for broken pipe
- **Error states**: Return JSON with `status: "error"` and `error` field
- **Timestamp formatting**: Unix timestamp + friendly relative time ("5s ago")

### From Feature 088 (Health Tab)

- **Categorized data**: Group items by category for UI organization
- **Conditional rendering**: Use Eww `:visible` for show/hide logic
- **Action handlers**: Bash scripts for button clicks (pause/resume/clear)
- **Icon indicators**: Visual status (✓/⚠/✗) with color coding

### From Feature 064 (Sway Tree Monitor)

- **Event buffering**: Circular buffer with size limit
- **Event metadata**: Include timestamp, event type, change type
- **Historical queries**: Support lookback queries ("last 50 events")
- **Diagnostic output**: JSON format for programmatic analysis

---

## Open Questions for Implementation

1. **Eww scroll callback API**: Need to verify exact Yuck syntax for scroll position detection (may require Eww docs review)
2. **Filter performance**: Will frontend filtering of 500 events cause UI lag? (fallback: backend pagination if needed)
3. **Event deduplication**: Should we deduplicate rapid duplicate events (e.g., 3x window::focus in 10ms)? (MVP: no deduplication, assess in testing)
4. **Enrichment timeout**: What timeout for i3pm daemon queries? (use existing DaemonClient timeout: 2.0s)

---

## Phase 0 Completion

**Status**: ✅ All research questions resolved

**Key Decisions**:
1. Extend monitoring_data.py with `--mode events` (reuse existing architecture)
2. On-demand event enrichment via i3pm daemon (fresh data, <20ms latency)
3. Python deque for circular buffer (stdlib, O(1) FIFO)
4. Hybrid filtering (backend sends all, frontend filters)
5. Sticky scroll with Eww scroll state tracking
6. Nerd Fonts icons with Catppuccin color coding
7. 100ms event batching for performance

**Ready for Phase 1**: Data model definition and contract specification
