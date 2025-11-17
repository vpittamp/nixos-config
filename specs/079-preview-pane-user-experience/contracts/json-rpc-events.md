# JSON-RPC Event Contracts: Preview Pane User Experience

**Feature Branch**: `079-preview-pane-user-experience`
**Date**: 2025-11-16

## Overview

This document defines the JSON-RPC event contracts for daemon-to-widget communication and CLI commands.

---

## 1. Project Mode Navigation Events

### Event: `project_mode.nav`

Emitted when user presses arrow keys in project selection mode.

**Direction**: Daemon → workspace-preview-daemon

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "project_mode",
    "payload": {
      "event_type": "nav",
      "direction": "down",
      "accumulated_chars": ":79",
      "selected_index": 1,
      "projects": [
        {
          "name": "nixos-079-preview-pane",
          "display_name": "Preview Pane UX",
          "branch_number": "079",
          "branch_type": "feature",
          "icon": "",
          "is_worktree": true,
          "parent_project_name": "nixos",
          "git_status": {
            "dirty": false,
            "ahead": 2,
            "behind": 0
          },
          "relative_time": "2h ago"
        }
      ],
      "total_count": 3,
      "timestamp": "2025-11-16T14:30:00.000Z"
    }
  }
}
```

**Required Fields**:
- `event_type`: Must be "nav"
- `direction`: "up" or "down"
- `selected_index`: New selection index after navigation
- `projects`: Full filtered project list

**Response**: None (event broadcast)

---

### Event: `project_mode.backspace`

Emitted when user presses backspace in project selection mode.

**Direction**: Daemon → workspace-preview-daemon

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "project_mode",
    "payload": {
      "event_type": "backspace",
      "accumulated_chars": ":",
      "selected_index": 0,
      "projects": [...],
      "exit_mode": false,
      "timestamp": "2025-11-16T14:30:00.000Z"
    }
  }
}
```

**Special Case - Mode Exit**:

When backspace removes ":", accumulated_chars becomes empty and `exit_mode` is true:

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "project_mode",
    "payload": {
      "event_type": "backspace",
      "accumulated_chars": "",
      "exit_mode": true,
      "timestamp": "2025-11-16T14:30:00.000Z"
    }
  }
}
```

**Consumer Action**: When `exit_mode` is true, hide project list preview and restore workspace preview.

---

### Event: `project_mode.char`

Emitted when user types character for filtering.

**Direction**: Daemon → workspace-preview-daemon

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "project_mode",
    "payload": {
      "event_type": "char",
      "char": "7",
      "accumulated_chars": ":79",
      "selected_index": 0,
      "projects": [...],
      "total_count": 3,
      "timestamp": "2025-11-16T14:30:00.000Z"
    }
  }
}
```

**Numeric Prefix Behavior**:
- When `accumulated_chars` contains only ":" + digits, match against `branch_number`
- Score exact prefix matches highest (1000 points)
- Automatically select first match (index 0)

---

## 2. Eww Widget Data Contracts

### Variable: `workspace_preview_data`

Updated by workspace-preview-daemon to render project list.

**Schema**:

```json
{
  "visible": true,
  "type": "project_list",
  "accumulated_chars": ":79",
  "selected_index": 0,
  "total_count": 10,
  "grouped": true,
  "projects": [
    {
      "name": "nixos-079-preview-pane",
      "display_name": "Preview Pane UX",
      "branch_number": "079",
      "branch_type": "feature",
      "full_branch_name": "079-preview-pane-user-experience",
      "icon": "",
      "is_worktree": true,
      "parent_project_name": "nixos",
      "selected": true,
      "indentation_level": 1,
      "git_status": {
        "dirty": false,
        "ahead": 2,
        "behind": 0
      },
      "relative_time": "2h ago",
      "path": "/home/vpittamp/nixos-079-preview-pane-user-experience"
    }
  ],
  "hierarchy": [
    {
      "type": "root",
      "project": {...},
      "children": [...]
    }
  ],
  "empty": false
}
```

**New Fields for Feature 079**:
- `branch_number`: Extracted numeric prefix (e.g., "079")
- `branch_type`: Classification ("feature", "main", "hotfix", "release")
- `indentation_level`: 0 for root, 1 for worktree child
- `hierarchy`: Grouped structure for tree rendering (optional)

**Rendering Rules**:
1. If `grouped` is true, render using `hierarchy` structure
2. Each project with `selected: true` gets highlight styling
3. Display `branch_number` prominently in list entry
4. Show indentation for worktrees (children)

---

### Variable: `active_project`

Top bar project label data.

**Schema**:

```json
{
  "project": "nixos-079-preview-pane",
  "active": true,
  "branch_number": "079",
  "display_name": "Preview Pane UX",
  "icon": "",
  "is_worktree": true,
  "git_status": {
    "dirty": false,
    "ahead": 2,
    "behind": 0
  }
}
```

**New Fields for Feature 079**:
- `branch_number`: For formatted display
- `display_name`: Human-readable name
- `icon`: Project type icon
- `is_worktree`: Boolean for icon selection
- `git_status`: Repository state (optional, for status indicators)

**Display Format**:
- If `branch_number` present: `"{icon} {branch_number} - {display_name}"`
- Else: `"{icon} {project}"`
- If not `active`: Show "Global"

---

## 3. CLI Commands

### Command: `i3pm worktree list`

**Usage**:
```bash
i3pm worktree list [--format json|table] [--filter <pattern>]
```

**Output Schema (JSON)**:

```json
[
  {
    "branch": "079-preview-pane-user-experience",
    "path": "/home/vpittamp/nixos-079-preview-pane-user-experience",
    "parent_repo": "nixos",
    "git_status": {
      "dirty": false,
      "ahead": 2,
      "behind": 0,
      "branch": "079-preview-pane-user-experience"
    },
    "created_at": "2025-11-16T10:30:00Z"
  }
]
```

**Table Output**:
```
BRANCH                          PATH                                    PARENT   STATUS
079-preview-pane-user-experience /home/vpittamp/nixos-079-preview-...  nixos    +2 ↑
078-eww-preview-improvement      /home/vpittamp/nixos-078-eww-...       nixos    clean
```

**Exit Codes**:
- 0: Success
- 1: No worktrees found
- 2: Invalid arguments
- 3: File system error

---

## 4. Environment Variable Injection

### Contract: App Launch Environment

When `i3pm app launch <app>` is called, inject these variables:

**Existing Variables**:
```bash
I3PM_APP_ID="vscode-nixos-079-1234567890"
I3PM_APP_NAME="vscode"
I3PM_SCOPE="scoped"
I3PM_PROJECT_NAME="nixos-079-preview-pane"
I3PM_PROJECT_DIR="/home/vpittamp/nixos-079-preview-pane-user-experience"
I3PM_TARGET_WORKSPACE="2"
```

**New Variables (Feature 079)**:
```bash
I3PM_IS_WORKTREE="true"
I3PM_PARENT_PROJECT="nixos"
I3PM_BRANCH_TYPE="feature"
```

**Injection Point**: `window_environment_bridge.py` in `_prepare_launch_environment()` method.

**Type Coercion**:
- Boolean → "true" or "false" (string)
- Integer → string representation
- Optional → empty string if None

---

## 5. Notification Action Contract

### Command: `notify-send` with Actions

**Syntax**:
```bash
notify-send \
  -w \
  -i "dialog-information" \
  -u "normal" \
  -A "focus=Return to Window" \
  -A "dismiss=Dismiss" \
  "Claude Code Complete" \
  "Task finished\n\nSource: nixos:0"
```

**Action Response**:
- User clicks "Return to Window": stdout = "focus"
- User clicks "Dismiss": stdout = "dismiss"
- Timeout/close: stdout = ""

**Handler Script Contract**:

```bash
#!/bin/bash
# stop-notification-handler.sh

TITLE="$1"
BODY="$2"
TMUX_SESSION="$3"
TMUX_WINDOW="$4"
SWAY_WINDOW_ID="$5"

RESPONSE=$(notify-send -w -A "focus=Return" -A "dismiss=Dismiss" "$TITLE" "$BODY")

if [ "$RESPONSE" = "focus" ]; then
    # Focus Sway window
    if [ -n "$SWAY_WINDOW_ID" ]; then
        swaymsg "[con_id=$SWAY_WINDOW_ID] focus" 2>/dev/null || true
    fi

    # Select tmux window
    if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
        tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
    fi
fi
```

**Required Arguments**:
1. `TITLE`: Notification title
2. `BODY`: Notification body
3. `TMUX_SESSION`: Source tmux session name (optional)
4. `TMUX_WINDOW`: Source tmux window index (optional)
5. `SWAY_WINDOW_ID`: Sway container ID (optional)

---

## 6. IPC Command Contract

### Command: `workspace_mode.backspace`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.backspace",
  "id": 123
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "accumulated_chars": ":",
    "exit_mode": false
  },
  "id": 123
}
```

**Exit Mode Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "accumulated_chars": "",
    "exit_mode": true,
    "restored_mode": "workspace_preview"
  },
  "id": 123
}
```

---

### Command: `workspace_mode.nav`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "workspace_mode.nav",
  "params": {
    "direction": "down"
  },
  "id": 124
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "new_index": 1,
    "current_mode": "project_list"
  },
  "id": 124
}
```

---

## Error Contracts

### Validation Errors

**Invalid Direction**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid direction parameter",
    "data": {
      "received": "left",
      "expected": ["up", "down"]
    }
  },
  "id": 124
}
```

**No Projects Available**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32603,
    "message": "No projects available for navigation",
    "data": {
      "project_count": 0
    }
  },
  "id": 125
}
```

**Mode Mismatch**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32000,
    "message": "Navigation not available in current mode",
    "data": {
      "current_mode": "workspace_preview",
      "expected_mode": "project_list"
    }
  },
  "id": 126
}
```

---

## Performance SLAs

| Contract | Max Latency | Measurement Point |
|----------|-------------|-------------------|
| Arrow key event → widget update | <50ms | Event emit to Eww variable update |
| Backspace event processing | <20ms | Command receipt to response |
| Project list filtering | <100ms | Filter input to sorted results |
| Notification action callback | <500ms | Click to window focus |
| Top bar label update | <500ms | Project switch to display change |

These contracts ensure consistent communication between all components of the preview pane system.
