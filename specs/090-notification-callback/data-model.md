# Data Model: Enhanced Notification Callback for Claude Code

**Feature**: 090-notification-callback
**Date**: 2025-11-22
**Purpose**: Define data structures for notification context and handler communication

## Overview

This feature enhances notification hooks with project context and focus handling. The data model is minimal - primarily passing context via command-line arguments and environment variables. No persistent storage or complex data structures required.

## Entities

### 1. Notification Context

**Description**: Context information captured when Claude Code stop hook is triggered, passed to notification handler via command-line arguments.

**Fields**:
- `window_id` (string): Sway window ID (con_id) of terminal running Claude Code
  - Format: Numeric string (e.g., "12345")
  - Source: Extracted from Sway tree via `swaymsg -t get_tree` and terminal PID
  - Validation: Must be valid Sway container ID (checked via Sway IPC before focus)

- `notification_body` (string): Notification message content with context
  - Format: Multi-line string with sections (message preview, activity summary, modified files, working directory, source)
  - Max length: ~500 characters (80 char message + 300 char context)
  - Source: Constructed in `stop-notification.sh` from transcript parsing

- `tmux_session` (string, optional): tmux session name where Claude Code is running
  - Format: Alphanumeric string with hyphens (e.g., "nixos-090", "dotfiles")
  - Source: `tmux display-message -p "#{session_name}"`
  - Validation: Checked via `tmux has-session -t <name>` before window selection

- `tmux_window` (string, optional): tmux window index in session
  - Format: Numeric string (e.g., "0", "1", "2")
  - Source: `tmux display-message -p "#{window_index}"`
  - Validation: Implicitly validated by `tmux select-window` (fails gracefully if invalid)

- `project_name` (string, optional): i3pm project name where Claude Code was launched
  - Format: Alphanumeric string with hyphens (e.g., "nixos-090-notification-callback")
  - Source: `I3PM_PROJECT_NAME` environment variable
  - Validation: Checked for non-empty before project switch

**Relationships**:
- Links to Sway window via `window_id` (1:1 - one notification per terminal window)
- Links to tmux session via `tmux_session` (1:1 - one notification per session)
- Links to i3pm project via `project_name` (1:1 - one notification per project context)

**State Transitions**: None - notification context is ephemeral (created on stop event, consumed by handler, discarded after action)

**Validation Rules**:
- `window_id` must be non-empty if project switch required (cannot focus without window ID)
- `tmux_session` and `tmux_window` must both be present or both absent (paired values)
- `project_name` is optional (empty string = global mode, no project switch)

**Example**:
```bash
# Command-line arguments passed to stop-notification-handler.sh
WINDOW_ID="12345"
NOTIFICATION_BODY="Task complete - awaiting your input

📊 Activity: 3 bash, 2 edits, 1 write

📝 Modified:
  • scripts/claude-hooks/stop-notification.sh
  • home-modules/ai-assistants/claude-code.nix

📁 nixos-090-notification-callback

Source: nixos-090:0"
TMUX_SESSION="nixos-090"
TMUX_WINDOW="0"
PROJECT_NAME="nixos-090-notification-callback"  # NEW - added by this feature
```

### 2. Notification Action Response

**Description**: User action selection from SwayNC notification (which button clicked or key pressed).

**Fields**:
- `action_id` (string): Identifier of selected action
  - Format: String literal ("focus" or "dismiss")
  - Source: `notify-send -A` response captured via `-w` wait flag
  - Validation: Must be one of two values: "focus" (Return to Window) or "dismiss" (Dismiss)

**Relationships**:
- Triggers focus handler logic if `action_id == "focus"`
- Triggers no-op if `action_id == "dismiss"`

**State Transitions**:
```
Notification displayed
  ├─> User clicks "Return to Window" (or presses Ctrl+R) → action_id = "focus" → Execute focus handler
  └─> User clicks "Dismiss" (or presses Escape) → action_id = "dismiss" → Exit immediately
```

**Example**:
```bash
# Captured response from notify-send
RESPONSE=$(notify-send -w -A "focus=🖥️  Return to Window" -A "dismiss=Dismiss" "Claude Code Ready" "$MESSAGE")

# RESPONSE value examples:
# - "focus" (user clicked Return to Window)
# - "dismiss" (user clicked Dismiss or pressed Escape)
# - "" (notification timeout or SwayNC error - treat as dismiss)
```

### 3. Project Context Environment

**Description**: Environment variables set by i3pm project system, inherited by Claude Code hook.

**Fields**:
- `I3PM_PROJECT_NAME` (environment variable): Current project name
  - Format: String (e.g., "nixos-090-notification-callback", "dotfiles")
  - Source: Set by i3pm project system when launching scoped terminal
  - Validation: Check for non-empty before project switch

- `I3PM_APP_NAME` (environment variable): Application name (always "terminal" for Claude Code)
  - Format: String literal "terminal"
  - Source: Set by i3pm app launcher
  - Validation: Not used by notification callback (informational only)

- `I3PM_SCOPE` (environment variable): Application scope ("scoped" or "global")
  - Format: String literal ("scoped" or "global")
  - Source: Set by i3pm app launcher based on project context
  - Validation: Not used by notification callback (project name check is sufficient)

**Relationships**:
- `I3PM_PROJECT_NAME` determines whether project switch is needed (non-empty = switch required)
- Available in hook execution context via `${I3PM_PROJECT_NAME:-}` Bash syntax

**Example**:
```bash
# Environment variables available in stop-notification.sh
I3PM_PROJECT_NAME="nixos-090-notification-callback"  # Set by i3pm when terminal launched
I3PM_APP_NAME="terminal"
I3PM_SCOPE="scoped"

# Capture in hook
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"  # Empty string if not set (global mode)
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Claude Code Stop Event                                          │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ stop-notification.sh (Hook)                                     │
│                                                                  │
│ 1. Extract terminal window ID from Sway tree                   │
│ 2. Extract tmux session/window from environment                │
│ 3. Extract project name from I3PM_PROJECT_NAME env var (NEW)   │
│ 4. Parse transcript for notification content                    │
│ 5. Build notification body (message + context)                 │
│                                                                  │
│ Output: Notification Context                                    │
│   - window_id                                                   │
│   - notification_body                                           │
│   - tmux_session                                                │
│   - tmux_window                                                 │
│   - project_name (NEW)                                          │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   │ (Spawn background process)
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ stop-notification-handler.sh (Background Handler)               │
│                                                                  │
│ 1. Receive notification context via command-line args          │
│ 2. Send SwayNC notification with action buttons                │
│ 3. Wait for user action (-w flag)                              │
│ 4. Capture action response (focus/dismiss)                     │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   │ (User clicks button or presses key)
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ Notification Action Handler                                     │
│                                                                  │
│ If action_id == "focus":                                        │
│   1. Check if window_id exists via Sway IPC (NEW)              │
│   2. Switch to project_name if set (i3pm project switch) (NEW) │
│   3. Focus terminal window (swaymsg con_id focus)              │
│   4. Check if tmux_session exists (tmux has-session) (NEW)     │
│   5. Select tmux window if session exists                      │
│                                                                  │
│ If action_id == "dismiss":                                      │
│   1. Exit immediately (no focus change)                         │
└─────────────────────────────────────────────────────────────────┘
```

## No Persistent Storage

**Rationale**: Notification context is ephemeral - created on stop event, consumed by handler, discarded after action. No need for:
- Database tables
- JSON files
- In-memory caches
- State persistence across notifications

All context is passed via command-line arguments (strings) and validated at runtime.

## Validation Examples

### Valid Notification Context (Full Project Context)

```bash
WINDOW_ID="12345"
NOTIFICATION_BODY="Task complete"
TMUX_SESSION="nixos-090"
TMUX_WINDOW="0"
PROJECT_NAME="nixos-090-notification-callback"

# Validation passes:
# ✓ window_id non-empty
# ✓ tmux_session and tmux_window both present
# ✓ project_name non-empty (project switch required)
```

### Valid Notification Context (Global Mode)

```bash
WINDOW_ID="67890"
NOTIFICATION_BODY="Task complete"
TMUX_SESSION="main"
TMUX_WINDOW="1"
PROJECT_NAME=""  # Empty - global mode

# Validation passes:
# ✓ window_id non-empty
# ✓ tmux_session and tmux_window both present
# ✓ project_name empty (no project switch)
```

### Invalid Notification Context (Missing Window ID)

```bash
WINDOW_ID=""  # Missing
NOTIFICATION_BODY="Task complete"
TMUX_SESSION="nixos-090"
TMUX_WINDOW="0"
PROJECT_NAME="nixos-090-notification-callback"

# Validation fails:
# ✗ window_id empty (cannot focus without window ID)
# → Handler shows error notification: "Terminal window not found"
```

### Invalid Notification Context (Partial tmux Info)

```bash
WINDOW_ID="12345"
NOTIFICATION_BODY="Task complete"
TMUX_SESSION="nixos-090"
TMUX_WINDOW=""  # Missing window index
PROJECT_NAME="nixos-090-notification-callback"

# Validation fails:
# ✗ tmux_window empty but tmux_session present (inconsistent state)
# → Handler skips tmux window selection (terminal focus only)
```

## SwayNC Configuration Data

**Description**: SwayNC keyboard shortcut configuration for notification actions.

**Format**: JSON configuration file generated by home-manager

**Location**: `~/.config/swaync/config.json`

**Schema**:
```json
{
  "keyboard-shortcuts": {
    "notification-close": ["Escape"],
    "notification-action-0": ["ctrl+r", "Return"],  // "Return to Window" action
    "notification-action-1": ["Escape"]            // "Dismiss" action
  }
}
```

**Validation**:
- `notification-action-0` must include "ctrl+r" (Ctrl+R) per FR-011 requirement
- `notification-action-1` must include "Escape" per FR-011 requirement
- No conflicts with existing Sway/SwayNC keybindings

**Generation**: home-manager `xdg.configFile."swaync/config.json".text = builtins.toJSON { ... }`

## Summary

**Total Entities**: 4
1. Notification Context (command-line arguments)
2. Notification Action Response (SwayNC response string)
3. Project Context Environment (environment variables)
4. SwayNC Configuration Data (JSON config file)

**No persistent storage** - all data is ephemeral (created, consumed, discarded)

**Validation focus**: Runtime checks for window existence, session existence, project context availability
