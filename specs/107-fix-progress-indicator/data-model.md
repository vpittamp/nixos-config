# Data Model: Fix Progress Indicator Focus State and Event Efficiency

**Feature**: 107-fix-progress-indicator | **Date**: 2025-12-01

## Overview

This feature extends the existing Feature 095 badge system without changing the core data model. The primary changes are:

1. **Badge display logic** - Add focus-aware styling (CSS, no data changes)
2. **Hook communication** - IPC primary path, file fallback (same data format)
3. **Spinner animation** - Separate Eww variable (no daemon data changes)

## Existing Entities (From Feature 095)

### WindowBadge (Unchanged)

```python
class WindowBadge(BaseModel):
    """Represents a single window's notification badge state."""
    window_id: int = Field(..., description="Sway window container ID", gt=0)
    count: int = Field(1, description="Number of pending notifications", ge=1, le=9999)
    timestamp: float = Field(..., description="Unix timestamp when badge was created")
    source: str = Field("generic", description="Notification source identifier", min_length=1)
    state: BadgeStateType = Field("stopped", description="Badge state: working or stopped")
```

### BadgeState (Unchanged)

```python
class BadgeState(BaseModel):
    """Daemon-level badge state manager."""
    badges: Dict[int, WindowBadge] = Field(default_factory=dict)

    def create_badge(self, window_id: int, source: str, state: BadgeStateType) -> WindowBadge
    def set_badge_state(self, window_id: int, state: BadgeStateType) -> Optional[WindowBadge]
    def clear_badge(self, window_id: int, min_age_seconds: float = 0.0) -> int
    def has_badge(self, window_id: int) -> bool
    def get_badge(self, window_id: int) -> Optional[WindowBadge]
    def to_eww_format(self) -> Dict[str, dict]
```

## Existing Window Data (From Feature 085)

Window data already includes focus state:

```python
# From monitoring_data.py:transform_window()
{
    "id": 12345,
    "pid": 67890,
    "title": "Claude Code - nixos",
    "app_id": "ghostty",
    "focused": True,  # ← Already exists, used by Feature 107
    "floating": False,
    "hidden": False,
    "badge": {  # From badge_state.to_eww_format()
        "count": "1",
        "state": "working",
        "source": "claude-code",
        "timestamp": 1732450000.5
    }
}
```

## New Eww Variables (Feature 107)

### spinner_frame Variable

Separate variable for spinner animation, decoupled from monitoring data:

```lisp
;; Type: string
;; Values: One of ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
;; Update frequency: 120ms (only when working badge exists)
(defvar spinner_frame "⠋")
```

## Badge File Format (Unchanged)

File-based fallback uses same format as before:

```json
// Location: $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "count": "1",
  "timestamp": 1732450000
}
```

## IPC Commands (From Feature 095 - Unchanged)

The IPC contract from Feature 095 remains unchanged:

- `create_badge(window_id, source, state)` - Create or update badge
- `clear_badge(window_id)` - Remove badge
- `get_badge_state()` - Query all badges

See `specs/095-visual-notification-badges/contracts/badge-ipc.json` for full schema.

## CSS Class Extensions (Feature 107)

New CSS class added for focus-aware badge styling:

| Class | Condition | Visual Effect |
|-------|-----------|---------------|
| `.badge-notification` | Base class | Standard badge styling |
| `.badge-working` | `badge.state == "working"` | Teal glow, spinner icon |
| `.badge-stopped` | `badge.state == "stopped"` | Peach glow, bell icon |
| `.badge-focused-window` | `window.focused == true` | Dimmed, no glow (NEW) |

## State Transitions

```
┌─────────────────────────────────────────────────────────────────┐
│                        Badge Lifecycle                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [No Badge]                                                     │
│      │                                                          │
│      │ UserPromptSubmit hook                                    │
│      ▼                                                          │
│  [Working Badge]  ──────────────────────────────────────────┐   │
│      │            state: "working"                          │   │
│      │            spinner animation (120ms)                 │   │
│      │                                                      │   │
│      │ Stop hook                                            │   │
│      ▼                                                      │   │
│  [Stopped Badge]  ←─────────────────────────────────────────┘   │
│      │            state: "stopped"                              │
│      │            bell icon + count                             │
│      │                                                          │
│      │ Window focus event                                       │
│      ▼                                                          │
│  [No Badge]       (badge cleared)                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Focus State Overlay (Independent):

┌─────────────────────────────────────────────────────────────────┐
│                     Badge Display Logic                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  badge.state + window.focused → CSS class                       │
│                                                                 │
│  ┌─────────────┬───────────────┬────────────────────────────┐  │
│  │ badge.state │ window.focused │ CSS Classes                │  │
│  ├─────────────┼───────────────┼────────────────────────────┤  │
│  │ working     │ false         │ badge-working              │  │
│  │ working     │ true          │ badge-working              │  │
│  │             │               │ badge-focused-window       │  │
│  │ stopped     │ false         │ badge-stopped              │  │
│  │ stopped     │ true          │ badge-stopped              │  │
│  │             │               │ badge-focused-window       │  │
│  └─────────────┴───────────────┴────────────────────────────┘  │
│                                                                 │
│  Note: Working badge on focused window is edge case             │
│  (user submitted prompt but didn't switch away yet)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Changes

### Current (Feature 095):

```
Hook Script → File Write → Daemon Poll (500ms) → Full Data Refresh → Eww Update
```

### Proposed (Feature 107):

```
Hook Script → IPC Call → Daemon In-Memory Update → Eww Update
      │                         (Primary Path)
      │
      └─→ File Write (Fallback only if IPC fails)
```

### Spinner Animation:

```
Current:  Daemon Poll (50ms) → Full Data Refresh → Eww Update (including spinner_frame)
Proposed: Eww Timer (120ms) → defvar Update (spinner_frame only) → Badge Rerender
```

## Validation Rules

No changes to validation rules from Feature 095:

| Field | Validation |
|-------|------------|
| `window_id` | Integer > 0, must exist in Sway tree |
| `count` | Integer 1-9999, display as "9+" if > 9 |
| `timestamp` | Unix timestamp (float) |
| `source` | Non-empty string, max 50 chars |
| `state` | Literal["working", "stopped"] |
