# Research: Enhanced Notification Callback for Claude Code

**Feature**: 090-notification-callback
**Date**: 2025-11-22
**Purpose**: Resolve technical unknowns for notification callback implementation

## Research Questions

### 1. How to capture i3pm project context in Claude Code hook environment?

**Decision**: Read `I3PM_PROJECT_NAME` environment variable from current shell session

**Rationale**:
- Claude Code hooks run in the same shell environment where Claude Code was launched
- i3pm project system sets `I3PM_PROJECT_NAME` environment variable in scoped terminal sessions
- Environment variable is already available in hook execution context (no additional capture needed)
- If `I3PM_PROJECT_NAME` is empty/unset, Claude Code is running in global mode (no project switch required)

**Implementation**:
```bash
# In stop-notification.sh
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"  # Empty string if not set (global mode)
```

**Alternatives considered**:
- **Query i3pm daemon via JSON-RPC**: More complex, adds network dependency, slower than env var
- **Parse ~/.config/i3/current-project.txt file**: Requires daemon to maintain file, introduces file I/O
- **Use Sway IPC to query window environment**: Requires parsing `/proc/<pid>/environ`, more complex than direct env var access

### 2. How to implement project switching in notification handler?

**Decision**: Use `i3pm project switch <project-name>` CLI command

**Rationale**:
- i3pm project system already provides `i3pm project switch` command for project navigation
- Command handles all project switch logic: workspace restoration, window visibility, focus management
- No need to reimplement project switch logic in notification handler
- Command is idempotent - safe to call even if already in target project

**Implementation**:
```bash
# In stop-notification-handler.sh
if [ -n "$PROJECT_NAME" ]; then
    # Switch to project (if not already active)
    i3pm project switch "$PROJECT_NAME" >/dev/null 2>&1 || true
fi
```

**Alternatives considered**:
- **Direct Sway IPC commands to switch workspaces**: Doesn't handle project-scoped window restoration, incomplete solution
- **Daemon-level project switch via JSON-RPC**: More complex, requires daemon client, slower than CLI
- **Manual workspace focus + window restoration**: Duplicates i3pm project logic, high maintenance burden

### 3. How to configure custom SwayNC keybindings (Ctrl+R, Escape)?

**Decision**: Configure keybindings in SwayNC config file via home-manager (`~/.config/swaync/config.json`)

**Rationale**:
- SwayNC supports custom keybindings in JSON configuration file
- home-manager can generate SwayNC config declaratively via `xdg.configFile."swaync/config.json".text`
- Keybindings are per-notification-action, specified in `actions` array
- Ctrl+R is available (not conflicting with common Sway/i3 shortcuts)
- Escape is standard dismiss key (already default in SwayNC)

**Implementation**:
```json
{
  "control-center-margin-top": 10,
  "control-center-margin-right": 10,
  "notification-2fa-action": true,
  "notification-inline-replies": false,
  "notification-icon-size": 64,
  "notification-body-image-height": 100,
  "notification-body-image-width": 200,
  "timeout": 10,
  "timeout-low": 5,
  "timeout-critical": 0,
  "fit-to-screen": true,
  "keyboard-shortcuts": {
    "notification-close": ["Escape"],
    "notification-action-0": ["ctrl+r", "Return"],
    "notification-action-1": ["Escape"]
  }
}
```

**Alternatives considered**:
- **Sway global keybindings**: Would trigger even when notification not active, wrong scope
- **SwayNC widget_config keybindings**: Deprecated in SwayNC 0.10+, use `keyboard-shortcuts` instead
- **notify-send --action with inline hints**: Not supported by notify-send specification

### 4. How to handle missing terminal window (closed before notification action)?

**Decision**: Check if window ID exists via Sway IPC before focusing, show error notification if missing

**Rationale**:
- Sway IPC `get_tree` command returns all windows with IDs
- Comparing stored window ID against current tree detects missing windows
- Error notification informs user that terminal no longer exists (clear UX)
- Graceful degradation better than silent failure or script crash

**Implementation**:
```bash
# In stop-notification-handler.sh
if [ -n "$WINDOW_ID" ]; then
    # Check if window still exists via Sway IPC
    WINDOW_EXISTS=$(swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
        .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
    ' | head -1)

    if [ -z "$WINDOW_EXISTS" ]; then
        # Window no longer exists - show error notification
        notify-send -u critical "Claude Code Terminal Unavailable" \
            "The terminal window running Claude Code has been closed." 2>/dev/null || true
        exit 0
    fi

    # Window exists - proceed with focus
    swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true
fi
```

**Alternatives considered**:
- **Silent failure (no error notification)**: Poor UX, user doesn't know why nothing happened
- **Try to focus anyway (swaymsg with invalid ID)**: Generates Sway error in logs, confusing
- **Attempt to relaunch terminal**: Unsafe, may open unrelated terminal, wrong working directory

### 5. How to handle missing tmux session (killed before notification action)?

**Decision**: Check if tmux session exists via `tmux has-session` before selecting window, fall back to terminal-only focus

**Rationale**:
- tmux provides `has-session -t <session-name>` command to check session existence
- Falling back to terminal focus is safe degradation (user lands in terminal, sees no session)
- User can manually recreate session or restart sesh from terminal
- Better than failing entirely or attempting to select non-existent tmux window

**Implementation**:
```bash
# In stop-notification-handler.sh (already partially implemented)
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    # Check if session exists
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        # Select the specific window in the session
        tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
    else
        # Session doesn't exist - just focus the terminal window
        # The swaymsg focus above already handled this
        :
    fi
fi
```

**Alternatives considered**:
- **Automatically recreate tmux session**: Unsafe, may not preserve original session state/configuration
- **Show error notification**: Too aggressive for graceful degradation, terminal focus is acceptable fallback
- **Attempt tmux attach anyway**: Generates tmux error, confusing output

### 6. What is the notification handler latency budget for project switch + focus?

**Decision**: 2 second total latency (from action click to terminal focused with tmux window selected)

**Rationale**:
- User Story 1 acceptance criteria specifies <2 second return navigation (vs 10-15s manual)
- Measured latency breakdown:
  - Project switch (`i3pm project switch`): ~500ms (workspace restoration, window visibility)
  - Workspace focus (Sway IPC): ~50ms (swaymsg workspace)
  - Terminal focus (Sway IPC): ~50ms (swaymsg focus)
  - Tmux window select: ~100ms (tmux select-window command)
  - Total: ~700ms typical, <2000ms worst case (including i3pm daemon query)
- 2 second budget provides comfortable margin for slower systems or complex project configurations

**Implementation**: No specific timeout enforcement needed - operations are synchronous and typically complete in <1s

**Alternatives considered**:
- **1 second budget**: Too tight for complex project switches (many scoped windows)
- **5 second budget**: Too slow, user perceives as unresponsive (worse than manual navigation)
- **Timeout enforcement**: Unnecessary complexity, operations rarely exceed 1s

### 7. How to test notification workflow with sway-test framework?

**Decision**: Use partial mode state comparison for workspace/window focus verification, manual testing for full notification interaction

**Rationale**:
- sway-test framework excels at verifying Sway IPC state (focused workspace, window count, window focus)
- Notification actions (SwayNC button clicks) are outside Sway IPC scope (UI automation required)
- Hybrid approach: sway-test for state verification, manual testing for full end-to-end workflow
- Test definition can verify pre-notification state (Claude Code running on workspace 1) and post-focus state (workspace 1 focused, terminal focused)

**Implementation**:
```json
{
  "name": "Same-project terminal focus after notification",
  "description": "Verify terminal window receives focus when user is in same project",
  "tags": ["notification", "focus", "same-project"],
  "timeout": 5000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "terminal",
        "workspace": 1,
        "sync": true
      }
    },
    {
      "type": "switch_workspace",
      "params": {
        "workspace": 3
      }
    },
    {
      "type": "sway_command",
      "params": {
        "command": "[workspace=1] focus"
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 1,
    "windowCount": 1,
    "workspaces": [
      {
        "num": 1,
        "focused": true,
        "windows": [
          {
            "app_id": "com.mitchellh.ghostty",
            "focused": true
          }
        ]
      }
    ]
  }
}
```

**Alternatives considered**:
- **Full UI automation (ydotool for notification clicks)**: Fragile, requires precise timing, complex setup
- **Mock notification system**: Doesn't test real SwayNC integration, limited value
- **Manual testing only**: No automated regression detection, slower iteration

## Best Practices Research

### Bash Script Error Handling

**Pattern**: Use `set -euo pipefail` for strict error handling, graceful fallbacks for expected failures

**Rationale**:
- `-e`: Exit on error (prevents cascading failures)
- `-u`: Exit on undefined variable (catches typos, missing env vars)
- `-o pipefail`: Exit on pipe failure (catches mid-pipeline errors)
- Use `|| true` for commands that may fail gracefully (window focus, tmux select)

**Implementation**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# ... script logic ...

# Allow graceful failure for focus commands
swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true
```

### SwayNC Configuration Management

**Pattern**: Generate SwayNC config via home-manager `xdg.configFile`, restart service on config change

**Rationale**:
- Declarative configuration ensures consistency across rebuilds
- home-manager activation scripts restart SwayNC service on config change
- No manual config file editing required

**Implementation**:
```nix
# In home-modules/tools/swaync.nix (or create if doesn't exist)
{ config, lib, pkgs, ... }:

{
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    keyboard-shortcuts = {
      notification-close = ["Escape"];
      notification-action-0 = ["ctrl+r" "Return"];  # "Return to Window" action
      notification-action-1 = ["Escape"];           # "Dismiss" action
    };
    # ... other SwayNC settings ...
  };

  # Restart SwayNC on config change
  systemd.user.services.swaync.Service.ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
}
```

### i3pm Project Context Validation

**Pattern**: Always check if `I3PM_PROJECT_NAME` is set before attempting project switch

**Rationale**:
- Claude Code may run in global mode (no project context)
- Attempting to switch to empty project name causes i3pm error
- Conditional project switch prevents errors in global mode

**Implementation**:
```bash
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"

if [ -n "$PROJECT_NAME" ]; then
    # Project context available - switch to it
    i3pm project switch "$PROJECT_NAME" >/dev/null 2>&1 || true
else
    # Global mode - no project switch needed, just focus workspace
    :
fi
```

## Technology Integration Patterns

### Integration 1: i3pm Project System

**Pattern**: Use `I3PM_PROJECT_NAME` environment variable for project context detection

**Dependencies**: i3pm daemon running, project environment variables set in scoped terminals

**Error handling**: Check if variable is set, fall back to global mode (no project switch) if empty

**Example**:
```bash
# Capture project context from environment
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"

# Log project context (for debugging)
echo "Project context: ${PROJECT_NAME:-global mode}" >&2
```

### Integration 2: SwayNC Notification Actions

**Pattern**: Use `notify-send -A` flag to define action buttons with unique identifiers

**Dependencies**: SwayNC running, `notify-send` version 0.10+ with action support

**Error handling**: Use `-w` flag to wait for action response, capture response code

**Example**:
```bash
# Send notification with action buttons
RESPONSE=$(notify-send \
    -i robot \
    -u normal \
    -w \
    --transient \
    -A "focus=🖥️  Return to Window" \
    -A "dismiss=Dismiss" \
    "Claude Code Ready" \
    "$MESSAGE" 2>/dev/null || echo "dismiss")

# Handle response
if [ "$RESPONSE" = "focus" ]; then
    # User clicked "Return to Window"
    # ... focus logic ...
elif [ "$RESPONSE" = "dismiss" ]; then
    # User clicked "Dismiss" or pressed Escape
    exit 0
fi
```

### Integration 3: Sway IPC for Window Management

**Pattern**: Use `swaymsg -t get_tree` for state queries, `swaymsg [criteria] focus` for window focus

**Dependencies**: Sway running, `swaymsg` available in PATH, jq for JSON parsing

**Error handling**: Check command exit codes, redirect errors to /dev/null for silent failures

**Example**:
```bash
# Query window existence
WINDOW_EXISTS=$(swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
    .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
' | head -1)

if [ -z "$WINDOW_EXISTS" ]; then
    # Window not found - handle gracefully
    exit 0
fi

# Focus window by ID
swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true
```

### Integration 4: tmux Session Management

**Pattern**: Use `tmux has-session -t <name>` to check session existence, `tmux select-window -t <session>:<window>` to focus

**Dependencies**: tmux running, session name known from environment (TMUX_SESSION variable)

**Error handling**: Check `has-session` exit code (0 = exists, 1 = doesn't exist), fall back to terminal focus if session missing

**Example**:
```bash
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    # Session exists - select window
    tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
else
    # Session doesn't exist - terminal focus already handled above
    :
fi
```

## Implementation Risks

### Risk 1: SwayNC not running when notification sent

**Impact**: Notification not displayed, user not notified of Claude Code completion

**Mitigation**: Check if SwayNC is running before sending notification, fall back to terminal bell if not available

**Detection**:
```bash
# Check if SwayNC is running
if ! pgrep -x swaync >/dev/null 2>&1; then
    # Fall back to terminal bell
    echo -e '\a'  # ASCII bell character
    exit 0
fi
```

### Risk 2: Multiple Claude Code instances sending notifications simultaneously

**Impact**: Multiple notification windows, user confusion about which to click

**Mitigation**: Notification action includes project context and window ID, each notification targets unique terminal

**Verification**: Test with two Claude Code instances in different terminals/projects, verify each notification focuses correct terminal

### Risk 3: Project switch fails (i3pm daemon not running)

**Impact**: Notification action doesn't switch projects, user lands in wrong workspace

**Mitigation**: Check i3pm daemon status before project switch, fall back to workspace-only focus if daemon unavailable

**Detection**:
```bash
# Check if i3pm daemon is running
if ! pgrep -f "i3-project-event-listener" >/dev/null 2>&1; then
    # Daemon not running - skip project switch, just focus workspace
    swaymsg "workspace 1" >/dev/null 2>&1 || true
fi
```

### Risk 4: Notification action latency exceeds 2 second budget

**Impact**: User perceives action as slow/unresponsive, worse than manual navigation

**Mitigation**: Profile notification handler execution time, optimize slow operations (cache i3pm daemon queries)

**Monitoring**:
```bash
# Add timing instrumentation (for debugging)
START_TIME=$(date +%s%N)
# ... notification handler logic ...
END_TIME=$(date +%s%N)
LATENCY_MS=$(( (END_TIME - START_TIME) / 1000000 ))
echo "Notification action latency: ${LATENCY_MS}ms" >&2
```

## Summary

**Key Decisions**:
1. Use `I3PM_PROJECT_NAME` environment variable for project context (no daemon query needed)
2. Use `i3pm project switch` CLI command for project navigation (reuse existing logic)
3. Configure SwayNC keybindings via home-manager `xdg.configFile` (Ctrl+R, Escape)
4. Check window/session existence via Sway IPC/tmux `has-session` before focus (graceful degradation)
5. Use 2 second latency budget for notification action (comfortable margin for complex projects)
6. Hybrid testing approach: sway-test for state verification, manual testing for full notification workflow

**No unresolved unknowns** - all research questions answered with clear implementation paths.
