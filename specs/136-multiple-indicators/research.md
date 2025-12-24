# Phase 0 Research: Multiple AI Indicators Per Terminal Window

**Feature**: 136-multiple-indicators
**Date**: 2025-12-24
**Status**: Complete

## Research Areas

### 1. Current Session Tracking Architecture

**Decision**: Session tracking already supports multiple concurrent sessions - no changes needed.

**Rationale**: The `SessionTracker` in `scripts/otel-ai-monitor/session_tracker.py` maintains independent state for each session via:
- `_sessions: dict[session_id → Session]` - unique session ID per AI CLI instance
- Independent state machines per session (`IDLE → WORKING → COMPLETED → ATTENTION`)
- Per-session timers in `_quiet_timers` and `_completed_timers`

The limitation is only in the **aggregation layer**, not tracking.

**Alternatives considered**:
- Merge sessions by window: Rejected - would lose per-session state granularity
- Create composite session IDs: Rejected - adds complexity without benefit

---

### 2. Window-to-Session Correlation for Tmux

**Decision**: Existing PID-based correlation via daemon IPC works correctly for tmux panes.

**Rationale**: The `find_window_for_session()` function in `sway_helper.py` uses:
1. Read `I3PM_*` environment variables from process via `/proc/{pid}/environ`
2. Extract `I3PM_APP_ID` (format: `"app-project-pid-timestamp"`)
3. Query daemon IPC: `get_window_by_launch_id(app_name, timestamp)`
4. For tmux: validates via `find_window_via_tmux_client()` to trace through tmux server

Each AI CLI process has a unique PID and gets correlated to the same `window_id` (the terminal window), but the session tracking maintains distinct `session_id` values.

**Alternatives considered**:
- Tmux pane detection via PTY: Deferred - adds complexity, spatial hints optional per P2
- Direct pane index injection: Deferred - requires app launcher changes

---

### 3. Deduplication Logic Removal

**Decision**: Remove feature-based deduplication in broadcast logic, replace with window grouping.

**Rationale**: Current code in `session_tracker.py` lines 1100-1108:
```python
# CURRENT: Keeps only "best" session per feature number
best_by_feature: dict[str, Session] = {}
for session in active_sessions:
    feature = extract_feature_number(session.project)
    if state_priority(session.state) > state_priority(existing.state):
        best_by_feature[key] = session
```

This **hides** lower-priority sessions. The new approach:
```python
# NEW: Group all sessions by window_id
sessions_by_window: dict[int, list[Session]] = defaultdict(list)
for session in active_sessions:
    if session.window_id:
        sessions_by_window[session.window_id].append(session)
```

**Alternatives considered**:
- Keep deduplication as optional mode: Rejected per Constitution Principle XII (Forward-Only)
- Deduplicate only identical tools: Rejected - distinct sessions should be visible

---

### 4. EWW Data Model for Multiple Badges

**Decision**: Change `window.badge` (object) to `window.badges` (array) with overflow handling.

**Rationale**: EWW widget currently expects:
```nix
window.badge = { otel_state: "working", otel_tool: "claude-code" }
```

New model:
```nix
window.badges = [
  { session_id: "...", otel_state: "working", otel_tool: "claude-code" },
  { session_id: "...", otel_state: "idle", otel_tool: "codex" }
]
```

EWW supports `(for badge in window.badges ...)` iteration.

**Alternatives considered**:
- Keep single badge with count: Rejected - loses tool type visibility
- Separate widget per session: Rejected - requires major restructure

---

### 5. Overflow Handling Strategy

**Decision**: Display first 3 badges + "+N more" count badge with tooltip on hover.

**Rationale**: Per FR-009, when more than 3 sessions are active:
1. Show first 3 indicators (sorted by state priority: WORKING > ATTENTION > COMPLETED > IDLE)
2. Show count badge: `+2 more`
3. Tooltip reveals full list with tool types and states

Implementation:
```yuck
(box
  :class "badge-container"
  :orientation "h"
  :space-evenly false
  (for badge in {(window.badges ?: []) | take(3)}
    (image :class "ai-badge" :path {badge.tool_icon} ...))
  (label
    :visible {(window.badges | length) > 3}
    :text {"+${(window.badges | length) - 3} more"}
    :tooltip {window.badges | map(...) | join("\n")}))
```

**Alternatives considered**:
- Scrollable badge area: Rejected - adds interaction complexity
- Stacked/layered badges: Rejected - harder to distinguish tools

---

### 6. Session Priority Ordering

**Decision**: Sort badges by state priority (WORKING > ATTENTION > COMPLETED > IDLE), then by timestamp.

**Rationale**: When displaying limited badges, users should see most "active" sessions first:
1. WORKING - actively processing
2. ATTENTION - needs user action
3. COMPLETED - recently finished
4. IDLE - waiting

Within same state, sort by `last_activity` descending (most recent first).

**Alternatives considered**:
- Alphabetical by tool: Rejected - not meaningful for monitoring
- Random order: Rejected - confusing when list changes

---

### 7. Spatial Position Hints (P2 Requirement)

**Decision**: Defer to future enhancement. Not blocking for P1 (multiple indicators visible).

**Rationale**: Per spec clarification: "Use spatial position hints (left pane, right pane, or quadrant position)" for disambiguating identical tool types. This requires:
1. Tmux pane layout detection
2. Mapping pane PTY to spatial position
3. Passing position through telemetry pipeline

Current scope focuses on displaying multiple badges. Spatial hints can be added via:
- `I3PM_PANE_INDEX` environment variable (future daemon enhancement)
- Tmux pane position query: `tmux list-panes -F "#{pane_index} #{pane_tty}"`

**Alternatives considered**:
- Include in initial scope: Rejected - increases complexity, P1 is valuable alone
- Pane ID as fallback: Possible future enhancement

---

### 8. Performance Considerations

**Decision**: No performance concerns for typical usage (2-5 sessions per window).

**Rationale**:
- Session state changes are already event-driven, not polling
- Badge rendering is client-side in EWW (no server round-trips)
- Array iteration over 5-10 items is negligible
- Overflow handling prevents UI degradation at scale

Testing plan:
- Verify update latency remains under 2 seconds (FR-008)
- Test with 10+ concurrent sessions to verify UI stability

**Alternatives considered**:
- Virtualized badge list: Rejected - overkill for 5-10 items
- Debounced updates: Already implemented for state transitions

---

## Summary of Decisions

| Area | Decision | Impact |
|------|----------|--------|
| Session Tracking | No changes needed | ✅ Tracks multiple sessions correctly |
| Window Correlation | No changes needed | ✅ PID-based correlation works for tmux |
| Deduplication | Remove feature-based dedup | ⚠️ Breaking change to data model |
| EWW Data Model | `badge` → `badges` array | ⚠️ Breaking change to widget |
| Overflow | 3 visible + count badge | ✅ Per FR-009 requirements |
| Sort Order | State priority, then timestamp | ✅ Most relevant badges first |
| Spatial Hints | Deferred to future | ⏸️ P2 can be added later |
| Performance | No concerns | ✅ Event-driven, small arrays |

---

## Unresolved Questions

None - all NEEDS CLARIFICATION items resolved.

---

## Next Steps

1. Proceed to Phase 1: Design data models (`SessionListItem` extension, `WindowBadgeSet`)
2. Define API contracts for session list emission
3. Create quickstart.md with testing steps
