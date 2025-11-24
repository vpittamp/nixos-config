# Contract: switch-project-action.sh

**Script Name**: `switch-project-action`
**Type**: Bash wrapper script (pkgs.writeShellScriptBin)
**Purpose**: Switch to a different project context by name

## Interface

### Command Signature

```bash
switch-project-action PROJECT_NAME
```

### Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `PROJECT_NAME` | string | Yes | Target project name to switch to | `"nixos"` |

### Exit Codes

| Code | Meaning | Scenario |
|------|---------|----------|
| 0 | Success | Project switched successfully OR already in target project |
| 1 | Failure | Project not found, daemon error, or invalid input |

### Side Effects

**File System**:
- Creates lock file: `/tmp/eww-monitoring-project-${PROJECT_NAME}.lock`
- Removes lock file on exit (via trap)

**Sway IPC** (via i3pm):
- Executes: `i3pm project switch ${PROJECT_NAME}`
- Hides scoped windows from old project
- Restores scoped windows for new project

**Notifications** (SwayNC):
- Success: "Switched to project [name]"
- Already current: "Already in project [name]" (informational)
- Error: "Project Switch Failed" with reason

**Eww State**:
- Sets: `clicked_project="${PROJECT_NAME}"`
- Auto-resets after 2s: `clicked_project=""`

---

## Behavior

### Execution Flow

```
1. Validate input
   - If PROJECT_NAME empty → exit 1

2. Check lock file
   - If /tmp/eww-monitoring-project-${PROJECT_NAME}.lock exists:
     → notify-send "Previous action still in progress"
     → exit 1
   - Else: touch lock file, trap to remove on exit

3. Get current project
   - Execute: i3pm project current --json | jq -r '.project_name // "global"'
   - Store in CURRENT_PROJECT

4. Check if already in target project
   - If PROJECT_NAME == CURRENT_PROJECT:
     → notify-send -u low "Already in project $PROJECT_NAME"
     → eww update clicked_project="$PROJECT_NAME"
     → (sleep 2 && eww update clicked_project="") &
     → exit 0

5. Execute project switch
   - Execute: i3pm project switch "$PROJECT_NAME"
   - If exit code == 0:
     → notify-send -u normal "Switched to project $PROJECT_NAME"
     → eww update clicked_project="$PROJECT_NAME"
     → (sleep 2 && eww update clicked_project="") &
     → exit 0
   - Else:
     → notify-send -u critical "Project Switch Failed" "Invalid project: $PROJECT_NAME"
     → eww update clicked_project=""
     → exit 1
```

### Debouncing Logic

**Lock File Mechanism**:
- Lock file path: `/tmp/eww-monitoring-project-${PROJECT_NAME}.lock`
- Created before any action
- Removed via `trap "rm -f $LOCK_FILE" EXIT`
- Prevents duplicate clicks on same project within execution time (~200ms)

**Rapid Click Handling**:
- If lock exists: Show notification "Previous action still in progress"
- If different project: Different lock file, can proceed in parallel
- Auto-cleanup on script exit (success or failure)

---

## Error Handling

### Input Validation

```bash
if [[ -z "$PROJECT_NAME" ]]; then
    notify-send -u critical "Project Switch Failed" "No project name provided"
    exit 1
fi
```

### Lock File Check

```bash
LOCK_FILE="/tmp/eww-monitoring-project-${PROJECT_NAME}.lock"

if [[ -f "$LOCK_FILE" ]]; then
    notify-send -u low "Project Switch" "Previous action still in progress"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT
```

### Project Switch Failure

```bash
if i3pm project switch "$PROJECT_NAME"; then
    # Success path
    notify-send -u normal "Switched to project $PROJECT_NAME"
    eww --config ~/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
    (sleep 2 && eww --config ~/.config/eww-monitoring-panel update clicked_project="") &
    exit 0
else
    # Failure path
    EXIT_CODE=$?
    notify-send -u critical "Project Switch Failed" \
        "Failed to switch to $PROJECT_NAME (exit code: $EXIT_CODE)"
    eww --config ~/.config/eww-monitoring-panel update clicked_project=""
    exit 1
fi
```

### Already in Target Project

```bash
CURRENT_PROJECT=$(i3pm project current --json | jq -r '.project_name // "global"')

if [[ "$PROJECT_NAME" == "$CURRENT_PROJECT" ]]; then
    notify-send -u low "Already in project $PROJECT_NAME"
    eww --config ~/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
    (sleep 2 && eww --config ~/.config/eww-monitoring-panel update clicked_project="") &
    exit 0
fi
```

---

## Performance

### Timing Breakdown

| Operation | Duration | Notes |
|-----------|----------|-------|
| Input validation | <1ms | Simple string check |
| Lock file check | <5ms | File existence test |
| Current project query | 20-50ms | i3pm JSON-RPC call |
| Project switch | 200ms | Feature 091 optimization |
| Notification display | 50ms | Async, doesn't block |
| **Total (switch)** | **~300ms** | Project switch path |
| **Total (already current)** | **~100ms** | Skip switch path |

### Optimization Notes

- Lock file check prevents wasted cycles on duplicate clicks
- Current project check avoids unnecessary switch
- Background eww update doesn't block script exit
- Notifications are async (via notify-send)

---

## Integration Points

### Eww Widget Call

```yuck
(eventbox
  :cursor "pointer"
  :onclick "switch-project-action ''${project.name} &"
  (box :class "project-header"
    ; ... project header display content
  ))
```

**Note**: Background execution (`&`) prevents UI blocking.

### i3pm Daemon

**Dependency**: Requires i3-project-event-listener service running

**Command Used**: `i3pm project switch <name>`
- Validates project exists in `~/.config/i3/projects/*.json`
- Hides scoped windows from old project (moves to scratchpad)
- Restores scoped windows for new project (moves from scratchpad to tracked workspaces)
- Updates daemon's active project state
- Broadcasts `project_switched` event

**Failure Modes**:
- Daemon not running → exit code 1
- Invalid project name → exit code 1
- Project config file missing → exit code 1
- IPC socket not accessible → exit code 1

### SwayNC Notifications

**Urgency Levels**:
- `-u low`: Informational (already in project)
- `-u normal`: Success confirmation
- `-u critical`: Errors requiring attention

**Message Format**:
- Title: Action description ("Switched to project", "Project Switch Failed")
- Body: Project name or error details

---

## Examples

### Successful Project Switch

```bash
$ switch-project-action "webapp"
# (No output to stdout - notifications only)
# Exit code: 0
# Notification: "Switched to project webapp"
# Scoped windows for "webapp" now visible
```

### Already in Target Project

```bash
$ switch-project-action "nixos"
# (Currently in "nixos" project)
# Exit code: 0
# Notification: "Already in project nixos" (low urgency)
```

### Failure: Invalid Project Name

```bash
$ switch-project-action "nonexistent-project"
# (No output to stdout)
# Exit code: 1
# Notification: "Project Switch Failed - Invalid project: nonexistent-project"
```

### Failure: Daemon Not Running

```bash
$ switch-project-action "webapp"
# (i3-project-event-listener service stopped)
# Exit code: 1
# Notification: "Project Switch Failed - Failed to switch to webapp (exit code: 1)"
```

### Failure: Rapid Duplicate Click

```bash
$ switch-project-action "webapp" &
$ switch-project-action "webapp"
# First command running (lock exists)
# Second command:
# Exit code: 1
# Notification: "Project Switch - Previous action still in progress"
```

---

## Testing

### Manual Testing

```bash
# Test successful switch
switch-project-action "nixos"

# Test already-in-project behavior
switch-project-action "$(i3pm project current --json | jq -r '.project_name')"

# Test error handling (invalid project)
switch-project-action "this-project-does-not-exist"

# Test rapid clicks
switch-project-action "webapp" & switch-project-action "webapp"
```

### Automated Testing (sway-test)

See `tests/093-actions-window-widget/test_project_switch_*.json` for declarative test definitions.

---

## Security Considerations

- **Input Sanitization**: PROJECT_NAME is not directly interpolated into eval - passed as quoted argument
- **Lock File Race**: Possible race condition if two clicks happen simultaneously (within 1ms) - acceptable risk
- **Notification Injection**: Project name displayed in notification - no XSS risk (plaintext)
- **Project Validation**: i3pm daemon validates project name against existing configs

---

## Dependencies

**Required Tools**:
- `bash` 5.0+
- `i3pm` (project management CLI)
- `notify-send` (libnotify)
- `jq` (JSON parsing)
- `eww` (widget framework)

**Required Services**:
- `i3-project-event-listener` (i3pm daemon)
- `swaync` (notification daemon)

---

## Differences from focus-window-action

| Aspect | switch-project-action | focus-window-action |
|--------|----------------------|---------------------|
| **Parameters** | 1 (project name) | 2 (project name, window ID) |
| **Lock File** | Per-project | Per-window |
| **Sway IPC** | Via i3pm only | i3pm + swaymsg |
| **Performance** | ~300ms (switch only) | ~500ms (switch + focus) |
| **Idempotence** | Yes (already-in-project check) | No (always focuses window) |
| **Use Case** | Change project context | Focus specific window |

---

## Version History

- **v1.0.0** (2025-11-23): Initial implementation (Feature 093)
