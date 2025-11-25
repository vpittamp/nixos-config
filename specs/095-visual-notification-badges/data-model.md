# Data Model: Visual Notification Badges

**Date**: 2025-11-24 | **Feature**: 095-visual-notification-badges

## Overview

Badge state is stored in-memory within the i3pm daemon as a Python dictionary mapping Sway window IDs to badge metadata. The data model uses Pydantic for validation and serialization, following Constitution Principle X (Python Development & Testing Standards).

## Core Entities

### WindowBadge

Represents the notification badge state for a single window.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `window_id` | `int` | Required, positive | Sway window container ID (authoritative key) |
| `count` | `int` | Required, ≥1, ≤9999 | Number of pending notifications (display as "9+" if >9) |
| `timestamp` | `float` | Required, Unix timestamp | When badge was created (for cleanup/sorting) |
| `source` | `str` | Required, default="generic" | Notification source identifier ("claude-code", "build", "test", etc.) |

**Operations**:
- `increment()` → `None`: Increment count (capped at 9999)
- `display_count()` → `str`: Get display string ("1", "2", ..., "9+")

**Validation Rules**:
- `window_id` must match existing Sway window (validated on creation via GET_TREE query)
- `count` cannot be zero (badge must be deleted if count reaches 0)
- `timestamp` must be valid Unix timestamp (seconds since epoch, float)
- `source` must be non-empty string (defaults to "generic" for undefined sources)

**Lifecycle**:
1. **Creation**: New badge created when `create_badge` IPC called with window ID
2. **Increment**: Existing badge count incremented when `create_badge` called again for same window
3. **Clearing**: Badge deleted when window receives focus (any duration) or window closes
4. **Cleanup**: Orphaned badges (window no longer exists) cleaned up on daemon restart or manual validation

**Example**:
```python
badge = WindowBadge(
    window_id=12345,
    count=2,
    timestamp=1732450000.5,
    source="claude-code"
)

badge.increment()  # count now 3
assert badge.display_count() == "3"

# After 8 more increments
for _ in range(8):
    badge.increment()
assert badge.display_count() == "9+"  # Visual overflow protection
```

---

### BadgeState

Daemon-level badge state manager, stored as instance variable on i3pm daemon.

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `badges` | `Dict[int, WindowBadge]` | Key = window ID, value = WindowBadge | In-memory badge storage, O(1) lookup |

**Operations**:
- `create_badge(window_id: int, source: str = "generic")` → `WindowBadge`: Create new badge or increment existing
- `clear_badge(window_id: int)` → `int`: Remove badge and return cleared count (0 if no badge)
- `has_badge(window_id: int)` → `bool`: Check if window has badge
- `get_badge(window_id: int)` → `Optional[WindowBadge]`: Get badge by window ID
- `get_all_badges()` → `List[WindowBadge]`: Get all badges (for UI rendering)
- `get_project_badge_count(project_name: str)` → `int`: Aggregate badge count for project (P3 feature)
- `cleanup_orphaned()` → `int`: Remove badges for windows that no longer exist
- `to_eww_format()` → `Dict[str, dict]`: Serialize for Eww monitoring panel

**Validation Rules**:
- Badge dictionary keys (window IDs) must be unique (enforced by dict type)
- No duplicate badges for same window (dict ensures uniqueness)
- Orphaned badges detected by querying Sway tree (window ID not in GET_TREE response)

**State Transitions**:

```
[No Badge] --create_badge(window_id)--> [Badge Exists (count=1)]
[Badge Exists (count=N)] --create_badge(same window_id)--> [Badge Exists (count=N+1)]
[Badge Exists] --window receives focus--> [No Badge] (cleared)
[Badge Exists] --window closes--> [No Badge] (cleaned up)
[Badge Exists] --daemon restart--> [No Badge] (in-memory state lost)
```

**Memory Footprint**:
- Each `WindowBadge`: ~200 bytes (int + int + float + str + Pydantic overhead)
- 50 concurrent badges: ~10KB total
- Dict overhead: ~2KB for 50 entries
- **Total**: ~12KB for typical usage (50 windows with badges)

**Concurrency**:
- Badge state accessed from async event handlers (window::focus, IPC requests)
- No locking needed (Python GIL ensures atomicity for dict operations)
- Badge create/clear operations are synchronous (<1ms each)

**Example Usage**:
```python
# Daemon initialization
badge_state = BadgeState()

# External notification (Claude Code hook)
badge = badge_state.create_badge(window_id=12345, source="claude-code")
# Badge created: count=1, timestamp=now, source="claude-code"

# Second notification on same window
badge = badge_state.create_badge(window_id=12345, source="claude-code")
# Badge updated: count=2 (incremented)

# User focuses window
cleared_count = badge_state.clear_badge(window_id=12345)
# Badge removed, cleared_count=2

# Window no longer exists
badge_state.create_badge(window_id=99999, source="test")
orphaned_count = badge_state.cleanup_orphaned()  # Queries Sway tree, removes badge
# orphaned_count=1 (badge for window 99999 removed)
```

---

## Data Flow

### Badge Creation Flow

```
[Claude Code Hook] --IPC call--> [Daemon IPC Server]
                                         ↓
                              create_badge(window_id, source)
                                         ↓
                              [BadgeState.create_badge()]
                                         ↓
                     ┌─────────────────┴──────────────────┐
                     ↓                                     ↓
            [New Badge Created]              [Existing Badge Incremented]
                     ↓                                     ↓
         WindowBadge(count=1, ...)            badge.increment()
                     ↓                                     ↓
                     └─────────────────┬──────────────────┘
                                       ↓
                        [publish_monitoring_state()]
                                       ↓
                     eww update panel_state=<json with badges>
                                       ↓
                        [Eww Monitoring Panel]
                                       ↓
                   Badge appears on window item (🔔 2)
```

### Badge Clearing Flow

```
[User focuses window] --Sway IPC--> [window::focus event]
                                            ↓
                                [Daemon Event Handler]
                                            ↓
                             on_window_focus(event.container.id)
                                            ↓
                         badge_state.clear_badge(window_id)
                                            ↓
                            badges.pop(window_id)
                                            ↓
                         [publish_monitoring_state()]
                                            ↓
                      eww update panel_state=<json without badge>
                                            ↓
                         [Eww Monitoring Panel]
                                            ↓
                     Badge disappears from window item
```

### Badge Cleanup Flow (Orphaned Badges)

```
[Window closes] --Sway IPC--> [window::close event]
                                      ↓
                          [Daemon Event Handler]
                                      ↓
                      on_window_close(event.container.id)
                                      ↓
                    badge_state.clear_badge(window_id)
                                      ↓
                     Badge removed from state
                                      ↓
              [publish_monitoring_state()]
                                      ↓
                  Eww panel updated (badge gone)
```

---

## Serialization Formats

### Eww Panel State Format

Badge state is embedded in the existing `panel_state` JSON pushed to Eww monitoring panel.

**Schema**:
```json
{
  "status": "ok",
  "monitors": [ /* existing monitor/workspace/window tree */ ],
  "window_count": 42,
  "badges": {
    "12345": {
      "count": "2",
      "timestamp": 1732450000.5,
      "source": "claude-code"
    },
    "67890": {
      "count": "1",
      "timestamp": 1732450100.0,
      "source": "build"
    }
  }
}
```

**Notes**:
- Badge keys are stringified window IDs (Eww/JSON requirement)
- `count` is display string ("9+" for overflow)
- `timestamp` is float (Unix seconds)
- `source` is string identifier for notification origin

### IPC Response Format (JSON-RPC)

**create_badge response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "badge": {
      "window_id": 12345,
      "count": 2,
      "timestamp": 1732450000.5,
      "source": "claude-code"
    }
  },
  "id": 1
}
```

**clear_badge response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "cleared_count": 2
  },
  "id": 2
}
```

**get_badge_state response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "badges": {
      "12345": {"count": 2, "timestamp": 1732450000.5, "source": "claude-code"},
      "67890": {"count": 1, "timestamp": 1732450100.0, "source": "build"}
    }
  },
  "id": 3
}
```

---

## Validation & Constraints

### Window ID Validation

Badge creation validates window ID exists in Sway tree:

```python
async def validate_window_exists(window_id: int, conn) -> bool:
    """Query Sway tree to confirm window ID exists."""
    tree = await conn.get_tree()
    windows = tree.find_by_id(window_id)
    return windows is not None
```

**Behavior**:
- Invalid window ID → IPC error response (badge not created)
- Window closes after badge created → Badge orphaned, cleaned up on next validation cycle
- Edge case: Badge created for window that closes 1ms later → Badge persists until cleanup (acceptable)

### Count Overflow Protection

Badge count display uses "9+" for values > 9:

```python
def display_count(self) -> str:
    """Return display string with overflow protection."""
    return "9+" if self.count > 9 else str(self.count)
```

**Rationale**:
- Prevents UI clutter from excessive counts (e.g., "143" takes more space than "9+")
- Actual count preserved in internal state (for diagnostics/logging)
- Spec requirement (FR-005, User Story 4 Acceptance Scenario 3)

### Source Validation

Badge source is free-form string (no enum constraint):

**Predefined Sources**:
- `"claude-code"`: Claude Code stop notification hooks
- `"build"`: Build system notifications (future)
- `"test"`: Test suite failures (future)
- `"generic"`: Default for undefined sources

**Extensibility**: New sources can be added without code changes (just use different string in IPC call).

---

## Relationships

### Badge → Window (One-to-One)

Each window has at most one badge. Multiple notifications on the same window increment the badge count.

```
Window 12345 ---has_badge---> WindowBadge(count=3, source="claude-code")
Window 67890 ---has_badge---> WindowBadge(count=1, source="build")
Window 11111 ---no badge----> None
```

### Badge → Project (Many-to-One, Future)

User Story 3 (P3) requires project-level badge aggregation:

```
Project "nixos-095" ---contains---> [Window 12345 (badge count=2), Window 67890 (badge count=1)]
                    ---aggregate---> Total badge count = 3
```

**Implementation** (deferred to P3):
```python
def get_project_badge_count(self, project_name: str) -> int:
    """Aggregate badge count for all windows in project."""
    # Query i3pm daemon for project's window IDs
    project_windows = await get_project_windows(project_name)

    # Sum badge counts
    return sum(
        self.badges[window_id].count
        for window_id in project_windows
        if window_id in self.badges
    )
```

---

## Testing Considerations

### Unit Tests (test_badge_models.py)

- WindowBadge creation with valid/invalid data
- Badge count increment and overflow behavior
- Display count formatting ("1", "9+")
- BadgeState dict operations (create, clear, has, get)
- Eww format serialization

### Integration Tests (test_badge_ipc.py)

- IPC create_badge with valid window ID
- IPC create_badge with invalid window ID (error response)
- IPC clear_badge for existing/non-existing badge
- IPC get_badge_state returns correct format

### State Tests (test_badge_focus_clearing.py)

- Badge clears on window::focus event
- Badge clears when window closes (window::close event)
- Orphaned badge cleanup after window no longer exists

---

## Summary

- **Primary Entity**: `WindowBadge` (window_id, count, timestamp, source)
- **Manager Entity**: `BadgeState` (dict[int, WindowBadge])
- **Storage**: In-memory Python dict (~12KB for 50 badges)
- **Serialization**: Pydantic → Eww JSON, JSON-RPC responses
- **Validation**: Window ID existence, count overflow protection
- **Lifecycle**: Create → Increment → Clear (on focus or close)
- **Performance**: O(1) operations, <1ms badge create/clear, <100ms UI update
