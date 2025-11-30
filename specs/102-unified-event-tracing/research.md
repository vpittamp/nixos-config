# Research: Unified Event Tracing System

**Feature**: 102-unified-event-tracing
**Date**: 2025-11-30
**Status**: Complete

## Research Questions Addressed

### 1. How should i3pm events be published to the Log tab?

**Decision**: Extend existing `log_event_entry()` function in `handlers.py` to publish i3pm internal events to the EventBuffer alongside Sway IPC events.

**Rationale**:
- EventBuffer already supports multiple sources ("i3", "ipc", "daemon", "systemd", "proc")
- Adding source="i3pm" for internal events maintains consistency
- `log_event_entry()` is the single point for event publishing, minimizing code changes

**Alternatives Considered**:
1. Separate event buffer for i3pm events - Rejected: Would require duplicate UI logic and prevent unified filtering
2. Publish to trace only - Rejected: Current gap is visibility without starting a trace

**Implementation**:
- Add calls to `log_event_entry()` in handlers for project::switch, visibility::*, command::*, launch::* events
- Set `source="i3pm"` to distinguish from raw Sway events
- EventEntry already has fields for project_name, old_project, new_project, windows_affected

### 2. How should correlation_id be generated and propagated?

**Decision**: Use Python `contextvars.ContextVar` for async context propagation with UUID generation at root events.

**Rationale**:
- Standard Python mechanism (3.7+), well-documented
- Auto-propagates through `await` and `asyncio.create_task()`
- No manual threading through function parameters
- Same pattern used by OpenTelemetry and other tracing libraries

**Alternatives Considered**:
1. Pass correlation_id as function parameter - Rejected: Requires modifying all handler signatures
2. Store in thread-local - Rejected: Not async-safe, breaks with asyncio
3. Use OpenTelemetry library - Rejected: Over-engineering for this use case

**Implementation**:
```python
import contextvars
import uuid

trace_correlation_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    'trace_correlation_id', default=None
)

# At root event (e.g., project::switch)
async def handle_project_switch(old: str, new: str):
    correlation_id = str(uuid.uuid4())
    trace_correlation_id.set(correlation_id)
    # All child handlers automatically inherit this context
    await hide_scoped_windows()  # Gets same correlation_id
    await restore_project_windows()  # Gets same correlation_id
```

### 3. How should output event types be distinguished?

**Decision**: Implement state diffing by caching `swaymsg -t get_outputs` results and comparing before/after on output events.

**Rationale**:
- Sway IPC `output` event provides minimal information (just change indicator)
- State diffing is the only way to determine connected/disconnected/profile_changed
- Same pattern used for workspace state tracking in existing code

**Alternatives Considered**:
1. Parse Sway source code for detailed event types - Rejected: Fragile, version-dependent
2. Use udev events for output detection - Rejected: Sway may not reflect immediately
3. Only log generic output events - Rejected: Defeats purpose of Feature 102 enhancement

**Implementation**:
```python
# Cache output state
cached_outputs: Dict[str, OutputState] = {}

async def handle_output_event(event):
    current_outputs = await sway.get_outputs()
    event_type = detect_output_change(cached_outputs, current_outputs)
    # event_type: "connected", "disconnected", "profile_changed"
    cached_outputs = {o.name: o for o in current_outputs}
```

### 4. How should copy-on-evict work for the event buffer?

**Decision**: Before evicting an event from the circular buffer, check if any active trace covers that window_id and copy to trace storage.

**Rationale**:
- Prevents losing trace context during burst operations
- Minimal overhead (only checks on eviction, not every add)
- Trace storage is separate and not constrained by main buffer

**Alternatives Considered**:
1. Increase buffer size - Rejected: Memory constraints, doesn't solve fundamental problem
2. Never evict traced events - Rejected: Could cause memory growth for long traces
3. Persist all events to disk - Rejected: Over-engineering, I/O overhead

**Implementation**:
```python
def add_event(self, event: EventEntry) -> int:
    if len(self.events) >= self.max_size:
        evicted = self.events[0]
        # Check if any active trace needs this event
        if self.tracer and self.tracer.has_active_trace_for_window(evicted.window_id):
            self.tracer.preserve_evicted_event(evicted)
        self.events.pop(0)
    # ... rest of add logic
```

### 5. How should cross-referencing between Log and Trace views work?

**Decision**: Add `trace_id` field to EventEntry, display trace indicator icon in Log view, enable bidirectional click-to-navigate.

**Rationale**:
- Log events can reference traces by ID (not duplicating trace data)
- UI can check if trace is active and show indicator
- Navigation uses existing Eww tab switching + scroll-to-element

**Alternatives Considered**:
1. Embed trace data in event entries - Rejected: Duplicates data, increases memory
2. Always show trace button - Rejected: Clutters UI when no trace active
3. Only navigate from Trace to Log - Rejected: Users want bidirectional flow

**Implementation**:
- EventEntry gets `trace_id: Optional[str]` field
- Log event card shows trace icon if `trace_id is not None`
- Click icon: Switch to Traces tab, highlight matching trace, expand event
- Trace event click: Switch to Log tab, scroll to matching event

### 6. How should causality chains be visualized in the Log tab?

**Decision**: Group events by correlation_id with visual indentation based on causality_depth, highlight chain on hover.

**Rationale**:
- Consistent with existing trace timeline visualization
- Indentation shows hierarchy clearly
- Hover highlight reveals full chain scope

**Alternatives Considered**:
1. Flat list with badges - Rejected: Doesn't convey hierarchy
2. Separate causality view - Rejected: Fragments information
3. Tree expansion UI - Rejected: Too complex for event stream

**Implementation**:
- Log view groups consecutive events with same correlation_id
- Each event rendered with margin-left based on causality_depth (16px per level)
- Hover over any event in chain: Apply highlight class to all events in chain
- Chain summary at end of group showing total duration

### 7. How should trace templates be implemented?

**Decision**: Store template definitions in daemon, expose via IPC, render dropdown in Traces tab header.

**Rationale**:
- Daemon already manages traces, templates are natural extension
- IPC query allows templates to be user-extensible later
- Dropdown is familiar UI pattern for selection

**Alternatives Considered**:
1. Hardcode templates in Eww widget - Rejected: Not extensible
2. JSON config file - Rejected: Adds complexity for 3 templates
3. CLI commands only - Rejected: GUI users want clickable interface

**Templates Defined**:
1. **Debug App Launch**: Pre-launch trace, lifecycle events, 60s timeout
2. **Debug Project Switch**: Trace all scoped windows, visibility+command events
3. **Debug Focus Chain**: Focus/blur events only for focused window

### 8. How should burst event handling work?

**Decision**: Batch UI updates when event rate exceeds 100/second, show "N events collapsed" indicator.

**Rationale**:
- Prevents UI from lagging during rapid operations
- Users can still see all events after rate normalizes
- Indicator provides awareness of collapsed count

**Alternatives Considered**:
1. Drop events during burst - Rejected: Loses debugging information
2. Always batch - Rejected: Adds latency during normal operation
3. Queue to disk - Rejected: I/O overhead, complex recovery

**Implementation**:
```python
# In event streaming
event_rate = calculate_rate(last_second_events)
if event_rate > 100:
    batch_events = collect_for(100ms)
    yield {"batch": len(batch_events), "events": batch_events}
else:
    yield {"events": [event]}
```

## Technology Decisions Summary

| Area | Decision | Key Library/Pattern |
|------|----------|---------------------|
| Correlation propagation | contextvars.ContextVar | Python stdlib |
| Output event detection | State diffing | swaymsg -t get_outputs |
| Cross-referencing | trace_id in EventEntry | Existing model extension |
| Causality visualization | Indentation + hover highlight | CSS margin-left + class |
| Event bursts | 100/sec threshold batching | Rate calculation |
| Templates | Daemon-managed, IPC query | Existing daemon pattern |
| Copy-on-evict | Check active traces on eviction | Tracer service integration |

## Files to Modify/Create

### Modified Files
- `event_buffer.py` - Add copy-on-evict, tracer reference
- `handlers.py` - Publish i3pm events with correlation_id
- `models/legacy.py` - Add correlation_id, trace_id to EventEntry
- `services/window_tracer.py` - Add template support, cross-ref APIs
- `monitoring_data.py` - Include i3pm events in stream
- `eww-monitoring-panel.nix` - i3pm filters, cross-ref UI, templates, causality viz

### New Files
- `models/events.py` - Unified event type enum (30+ types)
- `services/correlation_service.py` - ContextVar management
- `services/output_event_service.py` - Output state diffing

## Dependencies

No new external dependencies required. All functionality uses:
- Python stdlib: contextvars, uuid, asyncio
- Existing: i3ipc.aio, Pydantic, Eww

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Burst handling causes lag | Medium | Medium | Throttle at 100 events/sec, test with synthetic bursts |
| Copy-on-evict memory growth | Low | Low | Traces limited to 1000 events max |
| State diff race conditions | Low | Medium | Use single async context for output state |
| Cross-ref navigation complexity | Medium | Low | Implement incrementally, test each direction |
