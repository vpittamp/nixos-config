# Data Model: Eww Monitoring Widget Improvements

**Feature Branch**: `119-fix-window-close-actions`
**Date**: 2025-12-15

## Eww State Variables

### New Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `debug_mode` | boolean | `false` | Controls visibility of JSON and environment variable debugging features |

### Existing Variables (Modified Usage)

| Variable | Type | Current Usage | Changes |
|----------|------|---------------|---------|
| `env_window_id` | integer | Shows env panel for window | Gate behind `debug_mode` |
| `hover_window_id` | integer | Shows JSON panel for window | Gate behind `debug_mode` |
| `context_menu_window_id` | integer | Shows action bar for window | No change |
| `context_menu_project` | string | Shows project context menu | No change |

## Configuration Options

### Modified Options

| Option | Current Default | New Default | Description |
|--------|-----------------|-------------|-------------|
| `panelWidth` (non-ThinkPad) | 460 | 307 | Panel width in pixels (~33% reduction) |
| `panelWidth` (ThinkPad) | 320 | 213 | Panel width in pixels (~33% reduction) |

## UI Element Removals

### Window Row Badges

**Removed**:
```yuck
;; BEFORE: Workspace badge shown on every window
(label
  :class "badge badge-workspace"
  :text "WS${window.workspace_number}")
```

**After**: Element removed entirely

### Header Count Badges

**Before**:
```yuck
(label :class "count-badge" :text "${...} PRJ")
(label :class "count-badge" :text "${...} WS")
(label :class "count-badge" :text "${...} WIN")
```

**After**:
```yuck
;; Just numbers, no text labels
(label :class "count-badge" :text "${...}")
```

## CSS Classes

### Removed Classes

| Class | Reason |
|-------|--------|
| `.badge-workspace` | Workspace badge removed |

### Modified Classes

| Class | Change |
|-------|--------|
| `.count-badge` | Styling may adjust for icon-only display |

## Script Changes

### closeWorktreeScript

**Current Flow**:
1. Check lock file (exit if exists)
2. Create lock file
3. Query sway tree for windows with project marks
4. Kill each window
5. Send notification

**Improved Flow**:
1. Check rate limiter (skip if too recent)
2. Query sway tree for windows with project marks
3. For each window:
   - Send kill command
   - Log any errors
4. Re-query tree to verify close
5. Update eww state
6. Send notification with actual close count

### closeAllWindowsScript

**Changes**: Same improvements as closeWorktreeScript

### Individual Window Close (inline yuck)

**Current**:
```yuck
:onclick "swaymsg [con_id=${window.id}] kill && eww update context_menu_window_id=0"
```

**Improved**:
```yuck
:onclick "${closeWindowScript}/bin/close-window ${window.id}"
```

With new closeWindowScript handling rate limiting and error handling.

## Notification Callback Data Flow

### Stop Notification → Callback Data

The stop-notification.sh script captures context at notification time and passes it to the callback:

| Field | Source | Usage |
|-------|--------|-------|
| `WINDOW_ID` | `get_terminal_window_id()` (tmux PID → process tree → Sway) | Focus target |
| `PROJECT_NAME` | `$I3PM_PROJECT_NAME` environment variable | Project switch |
| `TMUX_SESSION` | `tmux display-message -p "#{session_name}"` | Tmux navigation |
| `TMUX_WINDOW` | `tmux display-message -p "#{window_index}"` | Tmux navigation |

### Current Active Project Source

Single source of truth for current project: `~/.config/i3/active-worktree.json`

```json
{
  "qualified_name": "project-name",
  "display_name": "Project Name",
  "directory": "/path/to/project",
  ...
}
```

Read via: `jq -r '.qualified_name // "global"' ~/.config/i3/active-worktree.json`

## State Transitions

### Debug Mode Toggle

```
User clicks debug toggle
  → debug_mode = !debug_mode
  → UI elements with :visible {debug_mode} update
  → If debug_mode changed to false:
      → env_window_id = 0 (collapse any open env panel)
      → hover_window_id = 0 (collapse any open JSON panel)
```

### Window Close Operation

```
User clicks close button
  → Rate limit check (skip if <200ms since last close)
  → swaymsg [con_id=X] kill
  → Wait for window::close event OR timeout (500ms)
  → Update panel state (monitoring_data refresh)
  → Clear context_menu_window_id if was the closed window
```

### Project Close Operation

```
User clicks project close
  → Rate limit check (skip if <1s since last project close)
  → Query sway tree for project windows
  → For each window: swaymsg kill
  → Wait for all window::close events OR timeout
  → Re-query to get actual close count
  → Send notification
  → Clear context_menu_project
```

### Return-to-Window Notification Callback (NEW)

```
User clicks "Return to Window" on Claude Code notification
  → Receive WINDOW_ID, PROJECT_NAME, TMUX_SESSION, TMUX_WINDOW from environment
  → Verify window still exists (swaymsg -t get_tree | jq)
  → If window doesn't exist:
      → Show error notification
      → Exit
  → Read current project from active-worktree.json
  → If PROJECT_NAME != CURRENT_PROJECT:
      → i3pm worktree switch "$PROJECT_NAME"
      → If switch fails: show warning, continue to focus
  → Focus window: swaymsg "[con_id=$WINDOW_ID] focus"
  → Clear badge file: rm "$XDG_RUNTIME_DIR/i3pm-badges/$WINDOW_ID.json"
  → If TMUX_SESSION and TMUX_WINDOW set:
      → tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}"
```

**Key Difference from Current Implementation**:
- **Current**: Uses arbitrary `sleep 1` after project switch
- **New**: Project switch is synchronous; focus immediately after completion
- **Current**: Doesn't check if already in correct project
- **New**: Reads active-worktree.json and skips switch if already in correct project
