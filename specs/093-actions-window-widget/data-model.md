# Data Model: Interactive Monitoring Widget Actions

**Feature**: 093-actions-window-widget
**Date**: 2025-11-23
**Purpose**: Define data structures for click interaction state management

## Entities

### WindowMetadata

Represents a window displayed in the monitoring panel with click interaction metadata.

**Fields**:
- `id` (number): Sway window container ID (con_id), unique identifier for window focus commands
- `project_name` (string): Project this window belongs to ("global" for non-scoped windows)
- `workspace_number` (number): Workspace number (1-70) where window is currently located
- `display_name` (string): Human-readable window title (e.g., "Firefox - Mozilla", "VS Code - main.py")
- `is_focused` (boolean): True if this window currently has keyboard focus in Sway
- `is_hidden` (boolean): True if window is in scratchpad/hidden state
- `is_floating` (boolean): True if window is floating (not tiled)

**Relationships**:
- Window belongs to exactly one Project (via `project_name`)
- Window resides on exactly one Workspace (via `workspace_number`)
- Window may have zero or one ClickAction targeting it

**Validation Rules**:
- `id` must be positive integer matching active Sway container ID
- `workspace_number` must be 1-70 (per system constraints)
- `project_name` must match existing project name in i3pm system or be "global"
- `display_name` should not be empty (use app_id or class name as fallback)

**Example**:
```json
{
  "id": 94638583398848,
  "project_name": "nixos",
  "workspace_number": 2,
  "display_name": "VS Code - eww-monitoring-panel.nix",
  "is_focused": false,
  "is_hidden": false,
  "is_floating": false
}
```

---

### ClickAction

Represents a user click interaction with its execution state and outcome.

**Fields**:
- `action_type` (enum): Type of action - "focus_window" or "switch_project"
- `target_id` (string | number): Window ID (number) for focus_window, project name (string) for switch_project
- `requires_project_switch` (boolean): True if window focus requires changing project context first
- `timestamp` (number): Unix timestamp (milliseconds) when click occurred
- `success_state` (boolean): True if action completed successfully, false if error occurred

**Relationships**:
- ClickAction targets exactly one WindowMetadata (for focus_window) or Project (for switch_project)
- ClickAction may trigger zero or one notification (SwayNC)

**State Lifecycle**:
1. **Created**: User clicks on window/project row
2. **Executing**: Bash script wrapper running (lock file exists)
3. **Completed**: Success notification shown, lock file removed
4. **Failed**: Error notification shown, lock file removed

**Validation Rules**:
- `action_type` must be "focus_window" or "switch_project"
- `target_id` must be valid window ID or project name
- `timestamp` must be within reasonable range (not future, not too old)
- `success_state` only set after completion (not during execution)

**Example**:
```json
{
  "action_type": "focus_window",
  "target_id": 94638583398848,
  "requires_project_switch": true,
  "timestamp": 1732377600000,
  "success_state": true
}
```

---

### EwwClickState

Represents the ephemeral UI state for visual feedback in Eww monitoring panel.

**Fields**:
- `clicked_window_id` (number): Window ID of last clicked window (0 = none)
- `clicked_project` (string): Project name of last clicked project ("" = none)
- `click_in_progress` (boolean): True during action execution (prevents duplicate clicks)

**Lifecycle**:
- Set to target ID/name when user clicks
- Auto-reset to default after 2 seconds for visual feedback timeout
- Reset immediately on error or completion in some cases

**Validation Rules**:
- `clicked_window_id` must be 0 or match existing window ID
- `clicked_project` must be "" or match existing project name
- Only one field should be non-default at a time (either window OR project, not both)

**Example**:
```json
{
  "clicked_window_id": 94638583398848,
  "clicked_project": "",
  "click_in_progress": true
}
```

**CSS Binding**:
```yuck
:class "window-row''${clicked_window_id == window.id ? ' clicked' : ""}"
```
When `clicked_window_id` matches `window.id`, the `.clicked` CSS class is applied for visual feedback (blue highlight).

---

### FocusTarget (Implicit)

Represents the resolved target of a focus action - either a window or workspace.

**Fields**:
- `target_type` (enum): "window" or "workspace"
- `target_identifier` (number): Window con_id for "window", workspace number for "workspace"

**Resolution Logic**:
```
if window.is_hidden:
    target_type = "workspace"  # Focus workspace first to restore window
    target_identifier = window.workspace_number
else:
    target_type = "window"     # Focus window directly
    target_identifier = window.id
```

**Sway IPC Command Mapping**:
- Window: `swaymsg '[con_id=${target_identifier}] focus'`
- Workspace: `swaymsg 'workspace ${target_identifier}'`

**Decision Logic** (per spec.md clarification):
The system focuses **individual windows**, not workspaces. Sway automatically switches to the correct workspace when focusing a window. For hidden/scratchpad windows, the window focus command automatically restores them.

---

## Data Flow

### Window Focus Action Flow

```
User clicks window row
    ↓
Eww onclick handler triggered
    ↓
EwwClickState updated (clicked_window_id = target)
    ↓
focus-window-action.sh invoked with (project_name, window_id)
    ↓
ClickAction created (action_type="focus_window", timestamp=now)
    ↓
If project_name != current_project:
    Execute: i3pm project switch $project_name
    Set: requires_project_switch = true
    ↓
Execute: swaymsg [con_id=$window_id] focus
    ↓
If success:
    ClickAction.success_state = true
    Notification: "Window Focused" (SwayNC)
    EwwClickState resets after 2s
Else:
    ClickAction.success_state = false
    Notification: "Focus Failed - Window no longer exists" (SwayNC)
    EwwClickState resets immediately
```

### Project Switch Action Flow

```
User clicks project header
    ↓
Eww onclick handler triggered
    ↓
EwwClickState updated (clicked_project = target)
    ↓
switch-project-action.sh invoked with (project_name)
    ↓
ClickAction created (action_type="switch_project", timestamp=now)
    ↓
If project_name != current_project:
    Execute: i3pm project switch $project_name
    ↓
    If success:
        ClickAction.success_state = true
        Notification: "Switched to project $project_name" (SwayNC)
        EwwClickState resets after 2s
    Else:
        ClickAction.success_state = false
        Notification: "Project switch failed" (SwayNC)
        EwwClickState resets immediately
Else:
    No-op (already in target project)
    Notification: "Already in project $project_name" (SwayNC)
    EwwClickState resets immediately
```

---

## Storage

**EwwClickState**: In-memory Eww variables (not persisted)
- Variables declared in Eww config with `defvar`
- Updated via `eww update` commands
- Lost on panel restart (acceptable - ephemeral UI state)

**WindowMetadata**: Provided by monitoring_data.py script
- Queried from Sway IPC and i3pm daemon
- Streamed to Eww via deflisten mechanism
- No persistence needed (real-time data)

**ClickAction**: Ephemeral (not stored)
- Created during bash script execution
- State tracked via lock files in /tmp
- Only outcome persisted: notification history (SwayNC)

---

## Constraints

- **Window ID Stability**: Sway window IDs (con_id) remain stable during window lifecycle but change on window recreate
- **Project Name Validation**: Must match existing projects in `~/.config/i3/projects/*.json`
- **Workspace Range**: Limited to 1-70 per system design
- **Concurrency**: Lock files prevent duplicate actions on same target
- **Performance**: Click actions must complete <500ms (cross-project) or <300ms (same-project)

---

## Error States

| Error Condition | Detection | Handling |
|----------------|-----------|----------|
| Window closed before focus | swaymsg exit code != 0 | Error notification "Window no longer available" |
| Project switch failed | i3pm exit code != 0 | Error notification "Project switch failed" |
| Rapid duplicate clicks | Lock file exists | Reject with notification "Previous action in progress" |
| Invalid window ID | ID not in current tree | Error notification "Invalid window" |
| Daemon not running | i3pm command fails | Error notification "Project daemon not running" |

---

## Performance Characteristics

- **Window metadata query**: <50ms (from monitoring_data.py cache)
- **Click state update**: <10ms (Eww variable update)
- **Project switch**: 200ms (Feature 091 optimization)
- **Window focus**: 100ms (Sway IPC RTT)
- **Total (cross-project)**: ~500ms (switch + focus + overhead)
- **Total (same-project)**: ~300ms (focus + overhead)

---

## Future Extensions (Out of Scope)

- **Click history**: Store last N click actions for analytics
- **Undo/redo**: Revert focus actions
- **Multi-window selection**: Click + Shift for multiple targets
- **Custom actions**: Right-click context menu for additional operations
