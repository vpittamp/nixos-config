# Data Model: Workspace Mode Visual Feedback

**Feature**: 058-workspace-mode-feedback
**Date**: 2025-11-11
**Status**: Design Phase

## Overview

This feature extends the existing workspace mode system (Feature 042) with visual feedback entities. The data model focuses on **pending workspace state** - the workspace number that will be navigated to when the user presses Enter, derived from accumulated digit input.

## Entity Relationships

```
WorkspaceModeManager (Feature 042)
    ├─> WorkspaceModeEvent (NEW - emitted on state changes)
    │   └─> PendingWorkspaceState (NEW - pending navigation target)
    │
    └─> WorkspaceModeState (EXISTING - internal daemon state)
        └─> accumulated_digits (str) → derives PendingWorkspaceState

sway-workspace-panel
    ├─> consumes WorkspaceModeEvent via IPC subscription
    └─> emits WorkspaceButtonYuck (NEW - extended with pending field)
        └─> includes urgent field (EXISTING - from Sway workspace state)

Eww workspace bar
    └─> renders workspace-button widget with overlay structure:
        ├─> base button with CSS class "pending" (pending highlight)
        └─> NotificationBadge overlay (NEW - urgent indicator)
            └─> visible when urgent=true, 8px red circle
```

## Core Entities

### 1. PendingWorkspaceState

**Purpose**: Represents the workspace that will be focused when the user presses Enter in workspace mode.

**Fields**:

| Field | Type | Validation | Description |
|-------|------|------------|-------------|
| `workspace_number` | `int` | `1 <= n <= 70` | Target workspace number derived from accumulated digits |
| `accumulated_digits` | `str` | `/^[0-9]{1,2}$/` | Raw digit string (e.g., "23", "5") |
| `mode_type` | `Literal["goto", "move"]` | Enum | Navigation mode: "goto" (focus workspace) or "move" (move window + follow) |
| `target_output` | `str \| None` | Valid output name | Monitor where workspace will appear (e.g., "eDP-1", "HEADLESS-2") |

**Validation Rules**:
- `workspace_number` must be in range 1-70 (Sway workspace limit)
- `accumulated_digits` cannot be empty when `workspace_number` is set
- `target_output` determined by Feature 001 workspace-to-monitor rules:
  - WS 1-2 → primary monitor
  - WS 3-5 → secondary monitor
  - WS 6+ → tertiary monitor
- Leading zeros are ignored during accumulation (e.g., "05" → "5")

**Derivation Logic**:

```python
def derive_pending_workspace(accumulated_digits: str, mode_type: str) -> PendingWorkspaceState | None:
    """Derive pending workspace state from accumulated digits."""
    if not accumulated_digits:
        return None

    workspace_number = int(accumulated_digits)

    # Validate range
    if workspace_number < 1 or workspace_number > 70:
        return None

    # Determine target output based on workspace number (Feature 001 rules)
    if workspace_number <= 2:
        role = "primary"
    elif workspace_number <= 5:
        role = "secondary"
    else:
        role = "tertiary"

    target_output = get_output_for_role(role)  # Query from monitor state

    return PendingWorkspaceState(
        workspace_number=workspace_number,
        accumulated_digits=accumulated_digits,
        mode_type=mode_type,
        target_output=target_output
    )
```

**State Transitions**: None (stateless DTO - derived on-demand from WorkspaceModeState)

**Example Values**:

```python
# User types "2" in goto mode
PendingWorkspaceState(
    workspace_number=2,
    accumulated_digits="2",
    mode_type="goto",
    target_output="eDP-1"  # Primary monitor on M1 Mac
)

# User types "2" then "3" in move mode
PendingWorkspaceState(
    workspace_number=23,
    accumulated_digits="23",
    mode_type="move",
    target_output="HEADLESS-2"  # Secondary monitor on Hetzner
)

# User types "9" then "9" (invalid - exceeds WS 70 limit)
None  # No pending state returned
```

---

### 2. WorkspaceModeEvent

**Purpose**: IPC event published by i3pm daemon to notify workspace panel of workspace mode state changes.

**Fields**:

| Field | Type | Validation | Description |
|-------|------|------------|-------------|
| `event_type` | `Literal["enter", "digit", "cancel", "execute"]` | Enum | Type of workspace mode event |
| `pending_workspace` | `PendingWorkspaceState \| None` | Valid PendingWorkspaceState | Current pending workspace (None when mode inactive or invalid input) |
| `timestamp` | `float` | `> 0` | Unix timestamp when event was emitted (seconds since epoch) |

**Event Type Semantics**:

- **`enter`**: Workspace mode activated (CapsLock pressed)
  - `pending_workspace` is `None` (no digits accumulated yet)

- **`digit`**: Digit added to accumulated state
  - `pending_workspace` contains derived workspace state
  - Emitted after each digit keypress (e.g., "2", then "23")

- **`cancel`**: Workspace mode canceled (Escape pressed)
  - `pending_workspace` is `None`
  - Visual feedback should clear pending highlights

- **`execute`**: Navigation executed (Enter pressed)
  - `pending_workspace` contains final target workspace
  - Workspace bar should transition pending → focused state

**Validation Rules**:
- `event_type` must be one of the 4 valid types
- `timestamp` must be > 0 (Unix epoch time)
- `pending_workspace` must be `None` for "enter" and "cancel" events
- `pending_workspace` must be valid `PendingWorkspaceState` for "digit" and "execute" events (unless invalid workspace number)

**State Transitions**:

```
[mode inactive]
    ↓ enter event (pending_workspace=None)
[mode active, no input]
    ↓ digit event (pending_workspace=PendingWorkspaceState(workspace_number=2, ...))
[mode active, WS 2 pending]
    ↓ digit event (pending_workspace=PendingWorkspaceState(workspace_number=23, ...))
[mode active, WS 23 pending]
    ↓ execute event (pending_workspace=PendingWorkspaceState(workspace_number=23, ...))
[mode inactive] (focus changed to WS 23)
```

**Example Events**:

```json
// Event 1: User enters workspace mode (CapsLock)
{
  "event_type": "enter",
  "pending_workspace": null,
  "timestamp": 1699727480.1234
}

// Event 2: User types "2"
{
  "event_type": "digit",
  "pending_workspace": {
    "workspace_number": 2,
    "accumulated_digits": "2",
    "mode_type": "goto",
    "target_output": "eDP-1"
  },
  "timestamp": 1699727480.5432
}

// Event 3: User types "3" (accumulated "23")
{
  "event_type": "digit",
  "pending_workspace": {
    "workspace_number": 23,
    "accumulated_digits": "23",
    "mode_type": "goto",
    "target_output": "HEADLESS-2"
  },
  "timestamp": 1699727480.8765
}

// Event 4: User presses Enter (execute navigation)
{
  "event_type": "execute",
  "pending_workspace": {
    "workspace_number": 23,
    "accumulated_digits": "23",
    "mode_type": "goto",
    "target_output": "HEADLESS-2"
  },
  "timestamp": 1699727481.2345
}
```

**IPC Transport**: Broadcast via Sway `tick` event with JSON payload in `first` field

```python
# i3pm daemon broadcast
await i3_connection.command(f'exec swaymsg -t send_tick workspace_mode:{json.dumps(event_dict)}')
```

**Subscription Filter**: `payload.startswith("workspace_mode:")`

---

### 3. WorkspaceButtonYuck (Eww Widget State)

**Purpose**: Yuck markup data for a single workspace button in the Eww workspace bar, extended with pending highlight state.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `number_label` | `str` | Workspace number displayed on button (e.g., "23") |
| `workspace_name` | `str` | Full workspace name from Sway (e.g., "23") |
| `app_name` | `str` | Primary application name on workspace (e.g., "Firefox") or "" if empty |
| `icon_path` | `str` | Absolute path to workspace icon SVG/PNG or "" if no icon |
| `icon_fallback` | `str` | Fallback icon name for icon theme lookup |
| `workspace_id` | `str` | Workspace ID for Sway IPC commands (e.g., "23") |
| `focused` | `bool` | **EXISTING** - Workspace is currently focused |
| `visible` | `bool` | **EXISTING** - Workspace is visible on another monitor |
| `urgent` | `bool` | **EXISTING** - Workspace has urgent window |
| `pending` | `bool` | **NEW** - Workspace is pending navigation target |
| `empty` | `bool` | **EXISTING** - Workspace has no windows |

**Validation Rules**:
- **Mutual exclusion**: `focused` and `pending` should not both be `True` (pending takes visual priority)
- If `pending=True`, button gets CSS class `.workspace-button.pending`
- `pending` overrides all other visual states in CSS hierarchy

**State Transitions**:

```
[normal state: focused=false, pending=false]
    ↓ workspace mode "digit" event for this workspace
[pending state: focused=false, pending=true]
    ↓ workspace mode "execute" event (navigation completes)
[focused state: focused=true, pending=false]
```

**Example Yuck Markup**:

```lisp
(workspace-button
  :number_label "23"
  :workspace_name "23"
  :app_name "Firefox"
  :icon_path "/etc/nixos/assets/pwa-icons/firefox.svg"
  :icon_fallback "firefox"
  :workspace_id "23"
  :focused false
  :visible false
  :urgent false
  :pending true    ; NEW FIELD - highlights this button in yellow/peach
  :empty false)
```

**CSS Class Mapping**:

```scss
// Normal state
.workspace-button {
  background: rgba(30, 30, 46, 0.3);
}

// Focused state (blue)
.workspace-button.focused {
  background: rgba(137, 180, 250, 0.3);
}

// Pending state (yellow/peach) - HIGHEST PRIORITY
.workspace-button.pending {
  background: rgba(249, 226, 175, 0.25);  /* Catppuccin Mocha Yellow */
  border: 1px solid rgba(249, 226, 175, 0.7);
  transition: all 0.2s;
}

// Pending overrides focused (if both true, pending wins)
.workspace-button.pending.focused {
  background: rgba(249, 226, 175, 0.25);  /* Pending takes priority */
}
```

---

### 4. NotificationBadge (Eww Overlay Widget)

**Purpose**: Apple-style circular notification badge overlaid on workspace buttons to indicate urgent windows, using Eww's native overlay widget for clean layering.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `visible` | `bool` | Badge visibility tied to workspace `urgent` state |
| `workspace_number` | `int` | Workspace this badge is associated with (1-70) |

**Validation Rules**:
- `visible` is `True` when workspace has at least one urgent window
- Badge renders on top of workspace button via Eww `overlay` widget
- Badge coexists with pending highlight (both can be visible simultaneously)
- No count indicator in MVP (single dot regardless of number of urgent windows)

**Visual Specifications**:

| Property | Value | Rationale |
|----------|-------|-----------|
| Diameter | 8px | Small enough to not obscure button content, large enough to be visible |
| Background | `#f38ba8` (Catppuccin Mocha Red) | Matches urgent state color, high visibility |
| Border | 2px solid white | Contrast against button background |
| Border Radius | 50% | Perfect circle |
| Position | Top-right corner | Standard notification badge position (Apple, Android) |
| Fade-out | 200ms opacity transition | Smooth disappearance when urgent clears |

**State Transitions**:

```
[hidden: urgent=false, badge visible=false]
    ↓ urgent window appears on workspace
[visible: urgent=true, badge visible=true]
    ↓ urgent window closes or urgent state clears
[fading: urgent=false, badge opacity 1.0 → 0.0 over 200ms]
    ↓ animation complete
[hidden: urgent=false, badge visible=false]
```

**Eww Yuck Structure**:

```lisp
(defwidget workspace-button [number_label workspace_name app_name icon_path workspace_id focused visible urgent pending empty]
  (overlay
    ; Base button (first child determines overlay size)
    (button
      :class "workspace-button..."
      :onclick "swaymsg workspace..."
      (box :class "workspace-pill" ...))

    ; Notification badge (overlaid on top-right corner)
    (box
      :class "notification-badge-container"
      :valign "start"
      :halign "end"
      :visible urgent  ; Badge visibility tied to urgent state
      (label :class "notification-badge" :text ""))))  ; Styled as circular dot
```

**CSS Implementation**:

```scss
.notification-badge-container {
  margin: 2px 2px 0 0;  /* Position in top-right corner with slight offset */
}

.notification-badge {
  min-width: 8px;
  min-height: 8px;
  background: #f38ba8;  /* Catppuccin Mocha Red */
  border: 2px solid white;
  border-radius: 50%;  /* Perfect circle */
  opacity: 1;
  transition: opacity 0.2s;  /* Smooth fade-out when urgent clears */
}
```

**Layering with Pending Highlight**:

- Badge renders **on top** of button background (via overlay widget)
- Pending highlight affects **button background** (yellow background + border)
- Both indicators can be visible simultaneously:
  - Example: Workspace 5 has urgent window + user types "5" in workspace mode
  - Result: Yellow pending highlight + red badge dot in top-right corner

**Example Scenarios**:

```python
# Scenario 1: Normal urgent workspace (no pending)
WorkspaceButtonYuck(
    workspace_number=5,
    urgent=True,    # Badge visible
    pending=False,  # No pending highlight
    # ... other fields
)
# Visual: Normal button background + red badge in top-right

# Scenario 2: Urgent workspace that is also pending navigation target
WorkspaceButtonYuck(
    workspace_number=5,
    urgent=True,    # Badge visible
    pending=True,   # Pending highlight active
    # ... other fields
)
# Visual: Yellow pending background + red badge in top-right (both visible)

# Scenario 3: Badge disappears when urgent clears
WorkspaceButtonYuck(
    workspace_number=5,
    urgent=False,   # Badge fades out over 200ms
    pending=False,
    # ... other fields
)
# Visual: Normal button background, badge fades out smoothly
```

---

## Integration Flow

```
User types "2" in workspace mode
    ↓
WorkspaceModeManager.add_digit("2")
    ├─> accumulated_digits = "2"
    ├─> derive PendingWorkspaceState(workspace_number=2, ...)
    └─> emit WorkspaceModeEvent(event_type="digit", pending_workspace=...)
        ↓
sway-workspace-panel receives tick event
    ├─> parse JSON payload
    ├─> update pending_workspace state
    └─> regenerate Yuck markup for all workspaces
        └─> workspace 2 gets pending=true
            ↓
Eww deflisten variable updates
    ├─> Yuck literal content refreshes
    └─> GTK renders .workspace-button.pending CSS
        └─> Button 2 highlights in yellow/peach (visual feedback complete)
```

**Total Latency**: <50ms from keystroke to visual update (measured end-to-end)

---

## Performance Characteristics

### Memory Footprint

- **PendingWorkspaceState**: ~120 bytes per instance (5 fields, Python object overhead)
- **WorkspaceModeEvent**: ~200 bytes per event (includes embedded PendingWorkspaceState)
- **WorkspaceButtonYuck**: ~300 bytes per workspace × 70 workspaces = ~21 KB total

**Total additional memory**: <25 KB (negligible impact)

### Latency Budget

| Operation | Target | Measured |
|-----------|--------|----------|
| Derive PendingWorkspaceState | <1ms | ~0.1ms (integer conversion + range check) |
| Serialize WorkspaceModeEvent | <1ms | ~0.5ms (Python json.dumps with 200-byte payload) |
| Broadcast IPC event | <5ms | ~3ms (Sway tick event emission) |
| Parse event in workspace panel | <2ms | ~1ms (json.loads) |
| Regenerate Yuck markup | <10ms | ~5ms (70 workspaces, string template) |
| Eww widget refresh | <20ms | ~10ms (GTK re-render with deflisten) |
| **Total end-to-end** | **<50ms** | **~20ms** (well within budget) |

---

## Validation Examples

### Valid Pending Workspace States

```python
# Single digit
PendingWorkspaceState(workspace_number=5, accumulated_digits="5", mode_type="goto", target_output="eDP-1")

# Multi-digit
PendingWorkspaceState(workspace_number=23, accumulated_digits="23", mode_type="move", target_output="HEADLESS-2")

# Maximum workspace
PendingWorkspaceState(workspace_number=70, accumulated_digits="70", mode_type="goto", target_output="HEADLESS-3")
```

### Invalid Cases (return None)

```python
# Workspace 0 (below minimum)
derive_pending_workspace("0", "goto") → None

# Workspace 99 (exceeds maximum)
derive_pending_workspace("99", "goto") → None

# Empty accumulated digits
derive_pending_workspace("", "goto") → None

# Leading zero only
derive_pending_workspace("0", "goto") → None  # Filtered during accumulation
```

---

## Future Extensions (Out of Scope for MVP)

### Preview Card State (User Story 2 - P2)

```python
@dataclass
class WorkspacePreviewState:
    """Preview card showing target workspace details."""
    workspace_number: int
    workspace_name: str
    app_name: str  # Primary application on workspace
    app_icon_path: str
    window_count: int
    is_empty: bool
```

**Not implemented in MVP** - Focus on workspace button highlighting only (P1)

