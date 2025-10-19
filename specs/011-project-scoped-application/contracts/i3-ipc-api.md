# i3 IPC API Contract

**Feature**: 011-project-scoped-application
**Date**: 2025-10-19

## Overview

This document defines the i3 IPC (Inter-Process Communication) interface used for project-scoped workspace management. All window queries and workspace manipulations use i3-msg commands communicating via Unix socket.

## Core Operations

### 1. Query Window Tree

**Purpose**: Get all windows with their properties for project matching.

**Command**:
```bash
i3-msg -t get_tree
```

**Output Format**: JSON tree structure

**Key Properties** (filtered):
```json
{
  "id": 94576115891776,
  "type": "con",
  "name": "[PROJECT:nixos] /etc/nixos - Visual Studio Code",
  "window": 65011713,
  "workspace": "2",
  "window_properties": {
    "class": "Code",
    "instance": "code",
    "title": "/etc/nixos - Visual Studio Code",
    "transient_for": null
  }
}
```

**Filtering Logic**:
```bash
i3-msg -t get_tree | jq '
  .. |
  objects |
  select(.window != null) |
  {
    id,
    name,
    window,
    workspace,
    window_properties: {
      class: .window_properties.class,
      instance: .window_properties.instance
    }
  }
'
```

**Returns**: Array of window objects with container IDs, titles, and properties.

**Performance**: O(n) where n = total i3 containers (windows + containers). Typically 50-200ms for 50 windows.

### 2. Move Window to Workspace

**Purpose**: Move a specific window to a designated workspace.

**Command**:
```bash
i3-msg "[con_id=<container_id>] move to workspace <number>"
```

**Example**:
```bash
i3-msg "[con_id=94576115891776] move to workspace 2"
```

**Parameters**:
- `container_id`: i3 container ID from get_tree query
- `number`: Workspace number (1-9)

**Response**:
```json
[
  {
    "success": true
  }
]
```

**Error Cases**:
- Invalid container ID → `{"success": false, "error": "No container matched"}`
- Invalid workspace number → Window moved to workspace with that name (creates if needed)

**Side Effects**:
- Window immediately appears on target workspace
- If window was focused, focus moves to target workspace
- Workspace becomes visible if not already focused

### 3. Move Window to Scratchpad

**Purpose**: Hide a window from all workspaces.

**Command**:
```bash
i3-msg "[con_id=<container_id>] move scratchpad"
```

**Example**:
```bash
i3-msg "[con_id=94576115891776] move scratchpad"
```

**Parameters**:
- `container_id`: i3 container ID from get_tree query

**Response**:
```json
[
  {
    "success": true
  }
]
```

**Side Effects**:
- Window removed from all workspaces
- Window state preserved (geometry, content, focus history)
- Window retrievable via "scratchpad show" command

**Scratchpad Characteristics**:
- Per-display, not per-workspace
- No limit on number of windows
- Windows remain in scratchpad until explicitly moved out
- Survives i3 restart (windows reload into scratchpad)

### 4. Show Scratchpad Window

**Purpose**: Retrieve a window from scratchpad to current workspace.

**Command**:
```bash
i3-msg "[con_id=<container_id>] scratchpad show"
```

**Alternative** (move to specific workspace):
```bash
i3-msg "[con_id=<container_id>] move to workspace <number>; [con_id=<container_id>] focus"
```

**Example**:
```bash
# Move from scratchpad to workspace 2
i3-msg "[con_id=94576115891776] move to workspace 2"
```

**Response**:
```json
[
  {
    "success": true
  }
]
```

### 5. Assign Workspace to Monitor

**Purpose**: Move a workspace to a specific monitor output.

**Command**:
```bash
i3-msg "workspace <number>; move workspace to output <output_name>"
```

**Example**:
```bash
i3-msg "workspace 1; move workspace to output DP-1"
```

**Parameters**:
- `number`: Workspace number (1-9)
- `output_name`: Monitor output name from xrandr (e.g., "DP-1", "HDMI-1")

**Response**:
```json
[
  {
    "success": true
  },
  {
    "success": true
  }
]
```

**Side Effects**:
- Workspace and all its windows move to target monitor
- If workspace was focused, it remains focused on new monitor
- Workspace-to-output binding persists until next assignment or i3 restart

**Error Cases**:
- Invalid output name → Workspace moves to first available output
- Disconnected output → Workspace moves to primary output

### 6. Query Workspaces

**Purpose**: List all workspaces with their current outputs and visible status.

**Command**:
```bash
i3-msg -t get_workspaces
```

**Output Format**:
```json
[
  {
    "num": 1,
    "name": "1: terminal ",
    "visible": true,
    "focused": true,
    "urgent": false,
    "rect": {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    },
    "output": "DP-1"
  },
  {
    "num": 2,
    "name": "2: code ",
    "visible": false,
    "focused": false,
    "urgent": false,
    "rect": {
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080
    },
    "output": "DP-1"
  }
]
```

**Use Cases**:
- Determine which workspaces are visible
- Find which output a workspace is currently on
- Check if workspace exists

## Script Integration Patterns

### Pattern 1: Find Project Windows

```bash
#!/usr/bin/env bash

# Query all windows and filter by project ID
PROJECT_ID="nixos"

i3-msg -t get_tree | jq -r "
  .. |
  objects |
  select(.window != null) |
  select(.name | test(\"\\[PROJECT:${PROJECT_ID}\\]\")) |
  {id, name, workspace, class: .window_properties.class} |
  @json
"
```

**Output**:
```json
{"id":94576115891776,"name":"[PROJECT:nixos] /etc/nixos - VS Code","workspace":"2","class":"Code"}
{"id":94576116023424,"name":"[PROJECT:nixos] ghostty","workspace":"1","class":"ghostty"}
```

### Pattern 2: Move Multiple Windows

```bash
#!/usr/bin/env bash

# Move all windows from project A to scratchpad
WINDOWS=$(i3-msg -t get_tree | jq -r '
  .. |
  objects |
  select(.window != null) |
  select(.name | test("\\[PROJECT:stacks\\]")) |
  .id
')

for window_id in $WINDOWS; do
  i3-msg "[con_id=${window_id}] move scratchpad"
done
```

### Pattern 3: Workspace-Monitor Assignment

```bash
#!/usr/bin/env bash

# Detect monitors
PRIMARY=$(xrandr --query | grep ' connected primary' | awk '{print $1}')
MONITORS=($(xrandr --query | grep ' connected' | awk '{print $1}'))
COUNT=${#MONITORS[@]}

# Assign workspaces based on count
if [ $COUNT -eq 1 ]; then
  for i in {1..9}; do
    i3-msg "workspace $i; move workspace to output ${MONITORS[0]}"
  done
elif [ $COUNT -eq 2 ]; then
  i3-msg "workspace 1; move workspace to output $PRIMARY"
  i3-msg "workspace 2; move workspace to output $PRIMARY"
  for i in {3..9}; do
    i3-msg "workspace $i; move workspace to output ${MONITORS[1]}"
  done
fi
```

## Window Selection Criteria

i3 supports various window selection criteria in square brackets:

### By Container ID (Recommended)
```bash
i3-msg "[con_id=94576115891776] <command>"
```
**Most precise**: Directly references specific window by unique ID.

### By Window ID
```bash
i3-msg "[id=65011713] <command>"
```
**Alternative**: Uses X11 window ID instead of i3 container ID.

### By Window Class
```bash
i3-msg "[class=\"Code\"] <command>"
```
**Broad match**: Affects all windows with matching WM_CLASS.

### By Window Title
```bash
i3-msg "[title=\".*nixos.*\"] <command>"
```
**Pattern match**: Regex matching on window title (name).

### Combined Criteria
```bash
i3-msg "[class=\"Code\" title=\".*nixos.*\"] <command>"
```
**Intersection**: Window must match all criteria.

## Error Handling

### Common Error Responses

**No matching window**:
```json
[
  {
    "success": false,
    "error": "No container matched the given criteria."
  }
]
```

**Invalid command syntax**:
```json
[
  {
    "success": false,
    "error": "Expected one of these tokens: <token>, <token>, ..."
  }
]
```

**IPC socket unavailable**:
```
Error: Unable to connect to i3
```

### Error Mitigation Strategies

1. **Stale Container IDs**: Always re-query window tree before operations
2. **Race Conditions**: Add small delays (100ms) between rapid commands
3. **Socket Errors**: Check `$I3SOCK` environment variable and i3 process
4. **Parsing Errors**: Use `jq -e` for validation before processing JSON

## Performance Characteristics

### Operation Latencies (Typical)

| Operation | Latency | Scale Factor |
|-----------|---------|--------------|
| get_tree | 10-50ms | O(n) windows |
| move to workspace | 5-20ms | O(1) |
| move scratchpad | 5-20ms | O(1) |
| workspace to output | 10-30ms | O(1) |
| get_workspaces | 1-5ms | O(w) workspaces |

**Batch Operations**:
- Moving 10 windows sequentially: ~100-200ms
- Querying + moving 10 windows: ~110-250ms
- Monitor assignment (9 workspaces): ~100-300ms

**Optimization Tips**:
1. Cache window tree results when possible
2. Batch operations in single script instead of multiple i3-msg calls
3. Use `&` for parallel operations (move multiple windows concurrently)
4. Avoid querying window tree on every keystroke

## Integration with xrandr

### Monitor Detection

**Query connected monitors**:
```bash
xrandr --query | grep ' connected' | awk '{print $1}'
```

**Output**:
```
DP-1
DP-2
```

**Query primary monitor**:
```bash
xrandr --query | grep ' connected primary' | awk '{print $1}'
```

**Output**:
```
DP-1
```

### Monitor Properties

**Full monitor info**:
```bash
xrandr --query
```

**Output**:
```
Screen 0: minimum 320 x 200, current 3840 x 1080, maximum 16384 x 16384
DP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 527mm x 296mm
   1920x1080     60.00*+  59.94    50.00
DP-2 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 527mm x 296mm
   1920x1080     60.00*+  59.94    50.00
HDMI-1 disconnected (normal left inverted right x axis y axis)
```

**Parsing**:
```bash
# Extract output name, resolution, position
xrandr --query | grep ' connected' | awk '{
  print "Output:", $1;
  print "Primary:", ($3 == "primary" ? "yes" : "no");
  print "Resolution:", ($3 == "primary" ? $4 : $3);
}'
```

### RandR Events

**Monitor hotplug detection**: i3 automatically receives RandR events, but workspace assignments must be manually reapplied.

**Manual trigger binding**:
```
bindsym $mod+Shift+m exec ~/.config/i3/scripts/detect-monitors.sh
```

## Security Considerations

### IPC Socket Permissions

- Socket location: `$I3SOCK` or `/run/user/<uid>/i3/ipc-socket.<pid>`
- Permissions: User-only (chmod 600)
- Authentication: None (local socket, process ownership)

**Implication**: Any process running as the user can control i3. This is acceptable for single-user systems but limits multi-user scenarios.

### Command Injection

**Risk**: Unsanitized input in i3-msg commands

**Example**:
```bash
# UNSAFE
TITLE="$USER_INPUT"
i3-msg "[title=\"$TITLE\"] move scratchpad"

# User input: "; rm -rf ~"
# Executed: i3-msg "[title=""; rm -rf ~""] move scratchpad"
```

**Mitigation**:
```bash
# SAFE - Use jq for JSON escaping
TITLE_ESCAPED=$(echo "$USER_INPUT" | jq -R .)
i3-msg "[title=$TITLE_ESCAPED] move scratchpad"
```

## Testing & Validation

### Unit Test Pattern

```bash
#!/usr/bin/env bash

# Test: Move window to workspace
test_move_window() {
  local window_id=94576115891776
  local target_ws=2

  # Execute command
  result=$(i3-msg "[con_id=$window_id] move to workspace $target_ws")

  # Validate success
  success=$(echo "$result" | jq '.[0].success')

  if [ "$success" = "true" ]; then
    # Verify window on correct workspace
    actual_ws=$(i3-msg -t get_tree | jq -r "
      .. |
      objects |
      select(.id == $window_id) |
      .workspace
    ")

    if [ "$actual_ws" = "$target_ws" ]; then
      echo "PASS: Window moved to workspace $target_ws"
      return 0
    fi
  fi

  echo "FAIL: Window not on expected workspace"
  return 1
}
```

### Integration Test Pattern

```bash
#!/usr/bin/env bash

# Test: Full project switch workflow
test_project_switch() {
  # Setup: Launch apps for project A
  launch-code.sh &  # Sets PROJECT:nixos
  sleep 1

  # Action: Switch to project B
  project-set.sh stacks
  sleep 0.5

  # Verify: Project A windows in scratchpad
  nixos_windows=$(i3-msg -t get_tree | jq '[
    .. |
    objects |
    select(.window != null) |
    select(.name | test("\\[PROJECT:nixos\\]"))
  ] | length')

  if [ "$nixos_windows" -eq 0 ]; then
    echo "PASS: NixOS windows hidden"
    return 0
  fi

  echo "FAIL: Found $nixos_windows NixOS windows still visible"
  return 1
}
```

## Summary

The i3 IPC API provides:
- **Window Querying**: Full window tree with properties
- **Window Management**: Move to workspace/scratchpad with precision
- **Workspace Control**: Assign to monitors, query state
- **Performance**: Sub-50ms operations for typical use cases
- **Integration**: Works with xrandr for monitor detection

All operations are synchronous and return JSON responses indicating success/failure. The API is stable (i3 IPC version 1) and compatible across i3 versions 4.x+.
