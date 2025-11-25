# Contracts: Enhanced Notification Callback for Claude Code

**Feature**: 090-notification-callback
**Date**: 2025-11-22

## Overview

This feature uses **shell script interfaces** (command-line arguments and environment variables) rather than REST APIs or GraphQL endpoints. Therefore, traditional API contracts are not applicable.

Instead, this document defines the **shell script contracts** between components.

## Script Interfaces

### 1. stop-notification.sh → stop-notification-handler.sh

**Purpose**: Pass notification context from Claude Code hook to background notification handler

**Interface Type**: Command-line arguments (positional parameters)

**Contract**:

```bash
# Invocation
nohup stop-notification-handler.sh \
    "$WINDOW_ID" \           # $1: Sway window ID (string, numeric)
    "$NOTIFICATION_BODY" \   # $2: Notification message content (string, multi-line)
    "$TMUX_SESSION" \        # $3: tmux session name (string, optional)
    "$TMUX_WINDOW" \         # $4: tmux window index (string, optional)
    >/dev/null 2>&1 &
```

**Parameter Specifications**:

| Position | Name | Type | Required | Format | Example |
|----------|------|------|----------|--------|---------|
| $1 | WINDOW_ID | string | Yes | Numeric string | "12345" |
| $2 | NOTIFICATION_BODY | string | Yes | Multi-line text | "Task complete\n\n📊 Activity: 3 bash" |
| $3 | TMUX_SESSION | string | No | Alphanumeric + hyphens | "nixos-090" |
| $4 | TMUX_WINDOW | string | No | Numeric string | "0" |

**Validation Rules**:
- $1 (WINDOW_ID): Must be non-empty, must be valid Sway container ID
- $2 (NOTIFICATION_BODY): Must be non-empty, max ~500 characters recommended
- $3 (TMUX_SESSION): If present, $4 must also be present (paired values)
- $4 (TMUX_WINDOW): If present, $3 must also be present (paired values)

**Return Value**: None (background process, exit code not captured)

**Side Effects**:
- Displays SwayNC notification
- Waits for user action (blocking until click/dismiss/timeout)
- Focuses terminal window if "Return to Window" clicked

---

### 2. Environment Variables (Project Context)

**Purpose**: Capture i3pm project context from shell environment

**Interface Type**: Environment variables (inherited from parent shell)

**Contract**:

| Variable Name | Type | Required | Format | Example | Source |
|---------------|------|----------|--------|---------|--------|
| `I3PM_PROJECT_NAME` | string | No | Alphanumeric + hyphens | "nixos-090-notification-callback" | Set by i3pm when launching scoped terminal |
| `I3PM_APP_NAME` | string | No | String literal | "terminal" | Set by i3pm app launcher |
| `I3PM_SCOPE` | string | No | "scoped" or "global" | "scoped" | Set by i3pm app launcher |

**Usage in stop-notification.sh**:

```bash
# Capture project name from environment
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"  # Empty string if not set (global mode)

# Pass to handler (not yet implemented in current version)
# Future enhancement: Pass PROJECT_NAME as 5th argument
```

**Validation Rules**:
- `I3PM_PROJECT_NAME`: Optional (empty = global mode, no project switch needed)
- If `I3PM_PROJECT_NAME` is set, project must exist in `~/.config/i3/projects/`
- If `I3PM_SCOPE` is "scoped", `I3PM_PROJECT_NAME` should be set (but not enforced)

---

### 3. Environment Variables (tmux Context)

**Purpose**: Capture tmux session/window info from environment

**Interface Type**: Environment variables (TMUX variable) + tmux command output

**Contract**:

| Variable Name | Type | Required | Format | Example | Source |
|---------------|------|----------|--------|---------|--------|
| `TMUX` | string | No | `/tmp/tmux-<uid>/<session>,<pid>,<pane>` | "/tmp/tmux-1000/default,12345,0" | Set by tmux when shell starts |

**Extraction Commands**:

```bash
# Check if running inside tmux
if [ -n "${TMUX:-}" ]; then
    # Extract session name
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || true)

    # Extract window index
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || true)
fi
```

**Validation Rules**:
- `TMUX` variable presence indicates tmux environment
- `tmux display-message` commands may fail if tmux server dies (handle gracefully)
- Session name and window index must be extracted together (paired values)

---

### 4. Sway IPC Queries (Window Existence Check)

**Purpose**: Verify terminal window still exists before focusing

**Interface Type**: Sway IPC via `swaymsg` command

**Contract**:

```bash
# Query: Check if window with ID exists in Sway tree
swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
    .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
' | head -1

# Output:
# - "<window_id>" if window exists (e.g., "12345")
# - "" (empty string) if window doesn't exist
```

**Validation**:
- Empty output = window closed, show error notification
- Non-empty output = window exists, proceed with focus

**Error Handling**:
- If `swaymsg` fails (Sway not running): Exit gracefully, log error
- If `jq` fails (invalid JSON): Exit gracefully, log error

---

### 5. tmux Session Existence Check

**Purpose**: Verify tmux session still exists before selecting window

**Interface Type**: tmux command exit code

**Contract**:

```bash
# Query: Check if tmux session exists
tmux has-session -t "$TMUX_SESSION" 2>/dev/null

# Exit code:
# - 0: Session exists
# - 1: Session doesn't exist
```

**Usage**:

```bash
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    # Session exists - select window
    tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
else
    # Session doesn't exist - skip tmux window selection, terminal focus only
    :
fi
```

---

### 6. i3pm Project Switch Command

**Purpose**: Switch to project where Claude Code is running

**Interface Type**: CLI command (i3pm project switch)

**Contract**:

```bash
# Command: Switch to project by name
i3pm project switch <project_name>

# Exit code:
# - 0: Project switch successful
# - 1: Project switch failed (project not found, daemon error)
```

**Usage**:

```bash
if [ -n "$PROJECT_NAME" ]; then
    # Project context available - switch to it
    i3pm project switch "$PROJECT_NAME" >/dev/null 2>&1 || true
fi
```

**Validation**:
- `PROJECT_NAME` must be non-empty
- Project must exist in `~/.config/i3/projects/`
- i3pm daemon must be running

**Error Handling**:
- If project doesn't exist: Log error, skip project switch (terminal focus only)
- If i3pm daemon not running: Log error, skip project switch
- Use `|| true` to prevent script failure on project switch error

---

### 7. notify-send Action Response

**Purpose**: Capture user action selection from SwayNC notification

**Interface Type**: `notify-send` with `-w` wait flag and `-A` action buttons

**Contract**:

```bash
# Command: Send notification with actions, wait for response
RESPONSE=$(notify-send \
    -i robot \
    -u normal \
    -w \                              # Wait for user action
    --transient \                     # Auto-dismiss after action
    -A "focus=🖥️  Return to Window" \  # Action ID: "focus"
    -A "dismiss=Dismiss" \            # Action ID: "dismiss"
    "Claude Code Ready" \             # Title
    "$MESSAGE" \                      # Body
    2>/dev/null || echo "dismiss")

# Response values:
# - "focus": User clicked "Return to Window" or pressed Ctrl+R
# - "dismiss": User clicked "Dismiss" or pressed Escape
# - "" (empty): Notification timeout or SwayNC error (treat as dismiss)
```

**Validation**:
- Response must be "focus", "dismiss", or empty
- Empty response treated as "dismiss" (safe fallback)

**Action Handling**:

```bash
if [ "$RESPONSE" = "focus" ]; then
    # Execute focus logic (project switch, window focus, tmux select)
elif [ "$RESPONSE" = "dismiss" ]; then
    # Exit immediately (no focus change)
    exit 0
fi
```

## Data Flow Summary

```
┌─────────────────────────────────────┐
│ Environment Variables (Inherited)   │
│ - I3PM_PROJECT_NAME                 │
│ - I3PM_APP_NAME                     │
│ - I3PM_SCOPE                        │
│ - TMUX                              │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ stop-notification.sh                │
│ 1. Capture project name from env   │
│ 2. Extract tmux session/window      │
│ 3. Extract terminal window ID       │
│ 4. Build notification body          │
└──────────────┬──────────────────────┘
               │
               │ (Pass via command-line args)
               ▼
┌─────────────────────────────────────┐
│ stop-notification-handler.sh        │
│ Args: $1=WINDOW_ID                  │
│       $2=NOTIFICATION_BODY          │
│       $3=TMUX_SESSION               │
│       $4=TMUX_WINDOW                │
│       $5=PROJECT_NAME (future)      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ notify-send (SwayNC)                │
│ Returns: action_id ("focus"/"dismiss") │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Focus Logic                         │
│ 1. Sway IPC: Check window exists    │
│ 2. i3pm: Switch to project          │
│ 3. Sway IPC: Focus terminal         │
│ 4. tmux: Check session exists       │
│ 5. tmux: Select window              │
└─────────────────────────────────────┘
```

## Future Enhancements

### Enhancement 1: Pass PROJECT_NAME as 5th Argument

**Current**: Project name captured but not passed to handler (requires enhancement)

**Proposed**:

```bash
# In stop-notification.sh
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"

nohup stop-notification-handler.sh \
    "$WINDOW_ID" \
    "$NOTIFICATION_BODY" \
    "$TMUX_SESSION" \
    "$TMUX_WINDOW" \
    "$PROJECT_NAME" \        # NEW: 5th argument
    >/dev/null 2>&1 &

# In stop-notification-handler.sh
PROJECT_NAME="${5:-}"        # NEW: Capture 5th argument

if [ -n "$PROJECT_NAME" ]; then
    i3pm project switch "$PROJECT_NAME" >/dev/null 2>&1 || true
fi
```

**Benefit**: Handler has explicit project context, doesn't rely on daemon state

## No REST/GraphQL Contracts

This feature does not introduce:
- HTTP REST APIs
- GraphQL schemas
- JSON-RPC endpoints (beyond existing i3pm daemon)
- Protocol buffers
- gRPC services

All communication is via:
- Shell script positional arguments
- Environment variables
- Command exit codes
- Standard output/error streams
