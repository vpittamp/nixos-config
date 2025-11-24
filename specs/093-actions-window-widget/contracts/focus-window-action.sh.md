# Contract: focus-window-action.sh

**Script Name**: `focus-window-action`
**Type**: Bash wrapper script (pkgs.writeShellScriptBin)
**Purpose**: Focus a window with automatic project switching if needed

## Interface

### Command Signature

```bash
focus-window-action PROJECT_NAME WINDOW_ID
```

### Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `PROJECT_NAME` | string | Yes | Target window's project name | `"nixos"` |
| `WINDOW_ID` | number | Yes | Sway container ID (con_id) | `94638583398848` |

### Exit Codes

| Code | Meaning | Scenario |
|------|---------|----------|
| 0 | Success | Window focused successfully |
| 1 | Failure | Window not found, IPC error, or invalid input |

### Side Effects

**File System**:
- Creates lock file: `/tmp/eww-monitoring-focus-${WINDOW_ID}.lock`
- Removes lock file on exit (via trap)

**Sway IPC**:
- May execute: `i3pm project switch ${PROJECT_NAME}` (if project differs)
- Always executes: `swaymsg [con_id=${WINDOW_ID}] focus`

**Notifications** (SwayNC):
- Success: "Window Focused" with project name
- Error: "Focus Failed" with specific reason

**Eww State**:
- Sets: `clicked_window_id=${WINDOW_ID}` (via eww update)
- Auto-resets after 2s: `clicked_window_id=0`

---

## Behavior

### Execution Flow

```
1. Validate inputs
   - If PROJECT_NAME empty → exit 1
   - If WINDOW_ID empty → exit 1

2. Check lock file
   - If /tmp/eww-monitoring-focus-${WINDOW_ID}.lock exists:
     → notify-send "Previous action still in progress"
     → exit 1
   - Else: touch lock file, trap to remove on exit

3. Get current project
   - Execute: i3pm project current --json | jq -r '.project_name // "global"'
   - Store in CURRENT_PROJECT

4. Conditional project switch
   - If PROJECT_NAME != CURRENT_PROJECT:
     → Execute: i3pm project switch "$PROJECT_NAME"
     → If exit code != 0:
       → notify-send -u critical "Project switch failed"
       → exit 1

5. Focus window
   - Execute: swaymsg "[con_id=${WINDOW_ID}] focus"
   - If exit code == 0:
     → notify-send -u normal "Window Focused" "Switched to project $PROJECT_NAME"
     → eww update clicked_window_id=${WINDOW_ID}
     → (sleep 2 && eww update clicked_window_id=0) &
     → exit 0
   - Else:
     → notify-send -u critical "Focus Failed" "Window no longer available"
     → eww update clicked_window_id=0
     → exit 1
```

### Debouncing Logic

**Lock File Mechanism**:
- Lock file path: `/tmp/eww-monitoring-focus-${WINDOW_ID}.lock`
- Created before any action
- Removed via `trap "rm -f $LOCK_FILE" EXIT`
- Prevents duplicate clicks on same window within execution time (~300-500ms)

**Rapid Click Handling**:
- If lock exists: Show notification "Previous action still in progress"
- If different window: Different lock file, can proceed in parallel
- Auto-cleanup on script exit (success or failure)

---

## Error Handling

### Input Validation

```bash
if [[ -z "$PROJECT_NAME" ]]; then
    notify-send -u critical "Focus Action Failed" "No project name provided"
    exit 1
fi

if [[ -z "$WINDOW_ID" ]]; then
    notify-send -u critical "Focus Action Failed" "No window ID provided"
    exit 1
fi
```

### Lock File Check

```bash
LOCK_FILE="/tmp/eww-monitoring-focus-${WINDOW_ID}.lock"

if [[ -f "$LOCK_FILE" ]]; then
    notify-send -u low "Focus Action" "Previous action still in progress"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT
```

### Project Switch Failure

```bash
if ! i3pm project switch "$PROJECT_NAME"; then
    EXIT_CODE=$?
    notify-send -u critical "Project Switch Failed" \
        "Failed to switch to project $PROJECT_NAME (exit code: $EXIT_CODE)"
    exit 1
fi
```

### Window Focus Failure

```bash
if swaymsg "[con_id=${WINDOW_ID}] focus"; then
    # Success path
    notify-send -u normal "Window Focused" "Switched to project $PROJECT_NAME"
    eww --config ~/.config/eww-monitoring-panel update clicked_window_id=${WINDOW_ID}
    (sleep 2 && eww --config ~/.config/eww-monitoring-panel update clicked_window_id=0) &
    exit 0
else
    # Failure path
    notify-send -u critical "Focus Failed" "Window no longer available"
    eww --config ~/.config/eww-monitoring-panel update clicked_window_id=0
    exit 1
fi
```

---

## Performance

### Timing Breakdown

| Operation | Duration | Notes |
|-----------|----------|-------|
| Input validation | <1ms | Simple string checks |
| Lock file check | <5ms | File existence test |
| Current project query | 20-50ms | i3pm JSON-RPC call |
| Project switch (if needed) | 200ms | Feature 091 optimization |
| Window focus | 100ms | Sway IPC command |
| Notification display | 50ms | Async, doesn't block |
| **Total (same project)** | **~300ms** | No project switch |
| **Total (cross-project)** | **~500ms** | With project switch |

### Optimization Notes

- Lock file check prevents wasted cycles on duplicate clicks
- Project comparison avoids unnecessary switch (skip if already in target project)
- Background eww update doesn't block script exit
- Notifications are async (via notify-send)

---

## Integration Points

### Eww Widget Call

```yuck
(eventbox
  :cursor "pointer"
  :onclick "focus-window-action ''${window.project_name} ''${window.id} &"
  (box :class "window-row"
    ; ... window display content
  ))
```

**Note**: Background execution (`&`) prevents UI blocking.

### i3pm Daemon

**Dependency**: Requires i3-project-event-listener service running

**Command Used**: `i3pm project switch <name>`
- Hides old project's scoped windows
- Restores new project's scoped windows
- Updates daemon state

**Failure Modes**:
- Daemon not running → exit code 1
- Invalid project name → exit code 1
- IPC socket not accessible → exit code 1

### Sway IPC

**Command Used**: `swaymsg [con_id=X] focus`
- Switches to window's workspace automatically
- Focuses window
- Restores from scratchpad if hidden

**Failure Modes**:
- Window closed → exit code 1
- Invalid con_id → exit code 1
- Sway IPC socket not accessible → exit code 1

### SwayNC Notifications

**Urgency Levels**:
- `-u low`: Informational (duplicate click warning)
- `-u normal`: Success confirmation
- `-u critical`: Errors requiring attention

**Message Format**:
- Title: Action description ("Window Focused", "Focus Failed")
- Body: Contextual details (project name, error reason)

---

## Examples

### Successful Same-Project Focus

```bash
$ focus-window-action "nixos" 94638583398848
# (No output to stdout - notifications only)
# Exit code: 0
# Notification: "Window Focused - Switched to project nixos"
# Window now has keyboard focus
```

### Successful Cross-Project Focus

```bash
$ focus-window-action "webapp" 94638583398900
# (No output to stdout)
# Exit code: 0
# Notification: "Window Focused - Switched to project webapp"
# Project switched (200ms), window focused (100ms)
```

### Failure: Window Closed

```bash
$ focus-window-action "nixos" 99999999999999
# (No output to stdout)
# Exit code: 1
# Notification: "Focus Failed - Window no longer available"
```

### Failure: Rapid Duplicate Click

```bash
$ focus-window-action "nixos" 94638583398848 &
$ focus-window-action "nixos" 94638583398848
# First command running (lock exists)
# Second command:
# Exit code: 1
# Notification: "Focus Action - Previous action still in progress"
```

---

## Testing

### Manual Testing

```bash
# Test successful focus
focus-window-action "nixos" $(swaymsg -t get_tree | jq '.. | select(.focused? == true) | .id')

# Test project switch
focus-window-action "different-project" $(swaymsg -t get_tree | jq '.. | select(.app_id == "firefox") | .id')

# Test error handling (invalid ID)
focus-window-action "nixos" 99999999999999

# Test rapid clicks
focus-window-action "nixos" 12345 & focus-window-action "nixos" 12345
```

### Automated Testing (sway-test)

See `tests/093-actions-window-widget/test_window_focus_*.json` for declarative test definitions.

---

## Security Considerations

- **Input Sanitization**: PROJECT_NAME and WINDOW_ID are not directly interpolated into eval - passed as quoted arguments
- **Lock File Race**: Possible race condition if two clicks happen simultaneously (within 1ms) - acceptable risk
- **Notification Injection**: Project name displayed in notification - no XSS risk (plaintext)

---

## Dependencies

**Required Tools**:
- `bash` 5.0+
- `i3pm` (project management CLI)
- `swaymsg` (Sway IPC client)
- `notify-send` (libnotify)
- `jq` (JSON parsing)
- `eww` (widget framework)

**Required Services**:
- `i3-project-event-listener` (i3pm daemon)
- `swaync` (notification daemon)
- `sway` (window manager)

---

## Version History

- **v1.0.0** (2025-11-23): Initial implementation (Feature 093)
