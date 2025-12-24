# Data Model: Multiple AI Indicators Per Terminal Window

**Feature**: 136-multiple-indicators
**Date**: 2025-12-24
**Status**: Complete

## Overview

This document defines the data model changes required to support multiple AI session indicators per terminal window. The primary change is transforming the single-badge-per-window model to a multiple-badges-per-window model.

## Entity Changes

### 1. SessionListItem (Extended)

**File**: `scripts/otel-ai-monitor/models.py`

**Current**:
```python
class SessionListItem(BaseModel):
    session_id: str
    tool: str              # "claude-code", "codex", "gemini"
    state: str             # "idle", "working", "completed", "attention"
    project: Optional[str]
    window_id: Optional[int]
```

**Proposed** (no changes needed):
The existing model already contains all required fields. No schema changes to `SessionListItem`.

---

### 2. SessionList (Extended with Window Grouping)

**File**: `scripts/otel-ai-monitor/models.py`

**Current**:
```python
class SessionList(BaseModel):
    type: str = "session_list"
    sessions: list[SessionListItem]  # Flat list, deduplicated by feature
    timestamp: int
    has_working: bool
```

**Proposed**:
```python
class SessionList(BaseModel):
    type: str = "session_list"
    sessions: list[SessionListItem]  # All sessions, NOT deduplicated
    sessions_by_window: dict[int, list[SessionListItem]]  # NEW: Grouped by window_id
    timestamp: int
    has_working: bool
```

**Changes**:
- Remove feature-based deduplication in broadcast logic
- Add `sessions_by_window` dict grouping all sessions by their `window_id`
- Null window_id sessions go to key `-1` (orphan sessions)

---

### 3. Window Badge Model (EWW Data)

**File**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`

**Current** (in `transform_window()`):
```python
"badge": {
    "otel_state": "working",      # Single state
    "otel_tool": "claude-code",   # Single tool
    # ... other badge fields
}
```

**Proposed**:
```python
"badge": {
    # Existing badge fields (notifications, etc.)
    "count": 1,
    "source": "ai",
    ...
},
"otel_badges": [  # NEW: Array of AI session badges
    {
        "session_id": "claude-session-1",
        "otel_state": "working",
        "otel_tool": "claude-code",
        "project": "nixos-config",
        "pending_tools": 2,
        "is_streaming": True,
    },
    {
        "session_id": "codex-session-1",
        "otel_state": "idle",
        "otel_tool": "codex",
        "project": "nixos-config",
        "pending_tools": 0,
        "is_streaming": False,
    },
]
```

**Changes**:
- Keep `badge` for non-OTEL badge data (notifications, counts)
- Add `otel_badges` array for all AI sessions in this window
- Array sorted by state priority (WORKING > ATTENTION > COMPLETED > IDLE), then by timestamp

---

### 4. otel_sessions_by_window Lookup (Monitoring Data Backend)

**Current** (`monitoring_data.py` line ~1584-1588):
```python
otel_sessions_by_window: Dict[int, Dict[str, Any]] = {}
for session in otel_sessions.get("sessions", []):
    window_id = session.get("window_id")
    if window_id is not None:
        otel_sessions_by_window[window_id] = session  # Overwrites!
```

**Proposed**:
```python
otel_sessions_by_window: Dict[int, List[Dict[str, Any]]] = {}
for session in otel_sessions.get("sessions", []):
    window_id = session.get("window_id")
    if window_id is not None:
        if window_id not in otel_sessions_by_window:
            otel_sessions_by_window[window_id] = []
        otel_sessions_by_window[window_id].append(session)

# Sort each window's sessions by state priority
STATE_PRIORITY = {"working": 3, "attention": 2, "completed": 1, "idle": 0}
for window_id, sessions in otel_sessions_by_window.items():
    sessions.sort(key=lambda s: STATE_PRIORITY.get(s.get("state", "idle"), 0), reverse=True)
```

---

## State Priority Ordering

Sessions within a window are sorted by state priority for display:

| Priority | State | Description |
|----------|-------|-------------|
| 3 (highest) | `working` | Actively processing |
| 2 | `attention` | Needs user action |
| 1 | `completed` | Recently finished |
| 0 (lowest) | `idle` | Waiting |

---

## Overflow Handling

Per FR-009, when more than 3 sessions are active in one window:

**Data Model** (no change needed - overflow is UI-only):
- `otel_badges` contains ALL sessions for the window
- EWW widget handles display logic:
  - Shows first 3 badges
  - Shows "+N more" count badge
  - Tooltip on count badge shows full list

---

## JSON Output Examples

### SessionList (emitted by otel-ai-monitor)

```json
{
  "type": "session_list",
  "sessions": [
    {"session_id": "claude-1", "tool": "claude-code", "state": "working", "window_id": 42, "project": "nixos"},
    {"session_id": "codex-1", "tool": "codex", "state": "idle", "window_id": 42, "project": "nixos"},
    {"session_id": "gemini-1", "tool": "gemini", "state": "working", "window_id": 43, "project": "other"}
  ],
  "sessions_by_window": {
    "42": [
      {"session_id": "claude-1", "tool": "claude-code", "state": "working", "project": "nixos"},
      {"session_id": "codex-1", "tool": "codex", "state": "idle", "project": "nixos"}
    ],
    "43": [
      {"session_id": "gemini-1", "tool": "gemini", "state": "working", "project": "other"}
    ]
  },
  "timestamp": 1735056000,
  "has_working": true
}
```

### Window Object (in monitoring_data output)

```json
{
  "id": 42,
  "title": "Ghostty - tmux",
  "app_id": "com.mitchellh.ghostty",
  "project": "nixos-config",
  "badge": {
    "count": 0,
    "source": null
  },
  "otel_badges": [
    {
      "session_id": "claude-1",
      "otel_state": "working",
      "otel_tool": "claude-code",
      "project": "nixos",
      "pending_tools": 2,
      "is_streaming": true
    },
    {
      "session_id": "codex-1",
      "otel_state": "idle",
      "otel_tool": "codex",
      "project": "nixos",
      "pending_tools": 0,
      "is_streaming": false
    }
  ]
}
```

---

## Migration Strategy

### Breaking Change

This is a **breaking change** to the EWW data model:
- Old: `window.badge.otel_state`, `window.badge.otel_tool`
- New: `window.otel_badges[].otel_state`, `window.otel_badges[].otel_tool`

### Migration Steps

1. Update `session_tracker.py`: Remove deduplication, add `sessions_by_window` grouping
2. Update `output.py`: Emit grouped session data in `SessionList`
3. Update `monitoring_data.py`:
   - Change `otel_sessions_by_window` to store arrays
   - Add sorting by state priority
   - Update `_merge_badge_with_otel` → `_build_otel_badges` (returns array)
   - Update `transform_window` to set `otel_badges` field
4. Update EWW widgets:
   - Change `window.badge.otel_state` → `(for badge in window.otel_badges ...)`
   - Add overflow handling (`arraylength(window.otel_badges) > 3`)
5. Update SCSS: Add styles for badge container and overflow count

---

## Validation Rules

1. **Session ID uniqueness**: Each session in `otel_badges` must have a unique `session_id`
2. **State values**: `otel_state` must be one of: `"idle"`, `"working"`, `"completed"`, `"attention"`
3. **Tool values**: `otel_tool` must be one of: `"claude-code"`, `"codex"`, `"gemini"`
4. **Array ordering**: `otel_badges` must be sorted by state priority (highest first)
5. **Max array size**: No hard limit, but EWW only displays first 3 with overflow handling

---

## Relationships

```
┌─────────────────┐      ┌─────────────────┐
│  otel-ai-monitor│      │ monitoring_data │
│  SessionList    │      │ Window          │
├─────────────────┤      ├─────────────────┤
│ sessions[]      │──1:N─│ otel_badges[]   │
│ sessions_by_    │      │                 │
│   window{}      │      │                 │
└─────────────────┘      └─────────────────┘
         │                        │
         │                        │
         ▼                        ▼
┌─────────────────┐      ┌─────────────────┐
│ SessionListItem │      │ OTELBadge       │
├─────────────────┤      ├─────────────────┤
│ session_id      │      │ session_id      │
│ tool            │      │ otel_state      │
│ state           │      │ otel_tool       │
│ window_id       │      │ project         │
│ project         │      │ pending_tools   │
│ pending_tools   │      │ is_streaming    │
│ is_streaming    │      └─────────────────┘
└─────────────────┘
```

---

## Backward Compatibility

**None** - per Constitution Principle XII (Forward-Only Development), there is no backward compatibility layer. The single-badge model is completely replaced by the multi-badge model.
