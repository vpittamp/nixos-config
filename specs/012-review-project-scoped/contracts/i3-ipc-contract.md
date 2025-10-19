# i3 IPC Contract

**Feature**: i3-Native Dynamic Project Workspace Management
**Date**: 2025-10-19

## Overview

This document defines how the project management system interacts with i3 window manager via the IPC (Inter-Process Communication) protocol. All i3 interactions must use native i3-msg commands or i3ipc library bindings.

## i3 IPC Message Types Used

### COMMAND (0)

**Purpose**: Send commands to i3 (move windows, mark, workspace operations)

**Protocol**:
```bash
i3-msg [criteria] command [arguments]
```

**Commands Used by Project Manager**:

#### Mark Window
```bash
i3-msg "[id=$WINDOW_ID] mark project:nixos"
i3-msg "[id=$WINDOW_ID] mark --add project:nixos"  # Don't replace existing marks
```

**Expected Response**:
```json
[{"success": true}]
```

#### Move to Scratchpad
```bash
i3-msg '[con_mark="project:nixos"] move scratchpad'
```

**Expected Response**:
```json
[{"success": true}]
```

#### Show from Scratchpad
```bash
i3-msg '[con_mark="project:nixos"] scratchpad show'
```

**Expected Response**:
```json
[{"success": true}]
```

#### Move to Workspace
```bash
i3-msg '[con_mark="project:nixos"] move to workspace 2'
```

**Expected Response**:
```json
[{"success": true}]
```

#### Workspace Output Assignment
```bash
i3-msg 'workspace 2 output HDMI-1'
```

**Expected Response**:
```json
[{"success": true}]
```

#### Load Layout
```bash
i3-msg 'workspace 2; append_layout /home/user/.config/i3/projects/nixos-ws2.json'
```

**Expected Response**:
```json
[{"success": true}, {"success": true}]
```

**Error Handling**:
- Check response JSON for `"success": false`
- Parse `"error"` field for details
- Retry once on transient errors (i3 busy)
- Log persistent failures

---

### GET_TREE (4)

**Purpose**: Query window tree to find windows by marks

**Protocol**:
```bash
i3-msg -t get_tree
```

**Response Structure** (simplified):
```json
{
  "id": 123456,
  "name": "root",
  "type": "root",
  "nodes": [
    {
      "type": "output",
      "name": "eDP-1",
      "nodes": [
        {
          "type": "workspace",
          "name": "2",
          "nodes": [
            {
              "id": 94339063078016,
              "type": "con",
              "name": "~/etc/nixos - Visual Studio Code",
              "window": 31457283,
              "marks": ["project:nixos", "editor"],
              "window_properties": {
                "class": "Code",
                "instance": "code"
              }
            }
          ]
        }
      ]
    }
  ]
}
```

**Queries Used**:

#### Find All Windows with Specific Mark
```bash
i3-msg -t get_tree | jq -r '
  .. |
  select(.marks? and (.marks | contains(["project:nixos"]))) |
  .id
'
```

**Output**: List of window IDs
```
94339063078016
94339063078032
```

#### Count Windows per Project
```bash
i3-msg -t get_tree | jq '
  [.. | select(.marks? and (.marks | contains(["project:nixos"])))] |
  length
'
```

**Output**: Integer count
```
3
```

#### Find Window by ID
```bash
i3-msg -t get_tree | jq --arg id "$WINDOW_ID" '
  .. |
  select(.window? == ($id | tonumber))
'
```

---

### GET_WORKSPACES (1)

**Purpose**: Query workspace information (current workspace, outputs)

**Protocol**:
```bash
i3-msg -t get_workspaces
```

**Response**:
```json
[
  {
    "id": 94339063075424,
    "num": 1,
    "name": "1",
    "visible": false,
    "focused": false,
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    "output": "eDP-1"
  },
  {
    "id": 94339063076448,
    "num": 2,
    "name": "2",
    "visible": true,
    "focused": true,
    "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080},
    "output": "HDMI-1"
  }
]
```

**Queries Used**:

#### Get Current Workspace Number
```bash
i3-msg -t get_workspaces | jq -r '.[] | select(.focused) | .num'
```

#### Get Workspace Output Assignments
```bash
i3-msg -t get_workspaces | jq -r '.[] | "\(.num) \(.output)"'
```

**Output**:
```
1 eDP-1
2 HDMI-1
```

---

### GET_OUTPUTS (3)

**Purpose**: Query connected monitors

**Protocol**:
```bash
i3-msg -t get_outputs
```

**Response**:
```json
[
  {
    "name": "eDP-1",
    "active": true,
    "primary": true,
    "current_workspace": "1",
    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
  },
  {
    "name": "HDMI-1",
    "active": true,
    "primary": false,
    "current_workspace": "2",
    "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080}
  }
]
```

**Queries Used**:

#### List Active Outputs
```bash
i3-msg -t get_outputs | jq -r '.[] | select(.active) | .name'
```

**Output**:
```
eDP-1
HDMI-1
```

#### Validate Output Exists
```bash
i3-msg -t get_outputs | jq -e --arg output "HDMI-1" '
  .[] | select(.name == $output and .active)
'
```

**Exit Code**: 0 if exists, 1 if not found

---

### SEND_TICK (10)

**Purpose**: Broadcast custom events to IPC subscribers

**Protocol**:
```bash
i3-msg -t send_tick 'project:nixos'
```

**Payload Format**: Plain string (not JSON, max 1KB recommended)
**Note**: The payload is sent as-is without JSON encoding. i3 v4.15+ required for tick events.

**Use Cases**:
- `project:nixos` - Project activated
- `project:none` - Project cleared
- `project:stacks` - Project switched

**Subscribers** (Python example):
```python
import i3ipc

i3 = i3ipc.Connection()

def on_tick(i3, event):
    payload = event.payload
    if payload.startswith('project:'):
        project_name = payload.replace('project:', '')
        if project_name == 'none':
            print("No Project")
        else:
            print(f" {project_name}")

i3.on('tick', on_tick)
i3.main()  # Blocks, listens for events
```

**Alternative Bash Subscription** (using socat):
```bash
#!/bin/bash
# Subscribe to i3 events via IPC socket

I3_SOCK=$(i3 --get-socketpath)

# Subscribe to tick events
echo -n '["tick"]' | socat - UNIX-CONNECT:$I3_SOCK | while read -r event; do
    # Parse JSON event and extract payload
    payload=$(echo "$event" | jq -r '.change')
    echo "Received tick: $payload"
done
```

**Response**: No response (fire-and-forget)

---

## Window Criteria Syntax

i3 supports powerful criteria for selecting windows. Project manager uses these patterns:

### By Mark
```bash
[con_mark="project:nixos"]
[con_mark="^project:.*"]  # Regex: any project mark
```

### By Window Class
```bash
[class="Code"]
[class="^Code$"]  # Exact match
```

### By Window ID
```bash
[id=94339063078016]
[id="$WINDOW_ID"]
```

### Combining Criteria (AND logic)
```bash
[class="Code" con_mark="project:nixos"]
```

### Multiple Commands on Same Selection
```bash
i3-msg '[con_mark="project:nixos"] mark --add active, move to workspace 2'
```

---

## Layout JSON Schema

When using `append_layout`, the JSON must follow i3's schema:

### Minimal Layout
```json
{
  "layout": "splith",
  "type": "con",
  "nodes": []
}
```

### Layout with Swallows
```json
{
  "layout": "splith",
  "type": "con",
  "nodes": [
    {
      "swallows": [
        {
          "class": "^Code$",
          "instance": "^code$"
        }
      ]
    }
  ]
}
```

### Layout with Marks
```json
{
  "layout": "splith",
  "type": "con",
  "marks": ["project:nixos"],
  "nodes": [
    {
      "swallows": [{"class": "^Code$"}],
      "marks": ["project:nixos", "editor"]
    }
  ]
}
```

### Swallows Criteria Properties
- `class`: WM_CLASS (regex)
- `instance`: WM_CLASS instance (regex)
- `title`: Window title (regex)
- `window_role`: WM_WINDOW_ROLE (regex)
- `window_type`: _NET_WM_WINDOW_TYPE (regex)

**Important**: All swallows patterns are PCRE regex, not glob patterns.

---

## Error Responses

### Command Failed
```json
[
  {
    "success": false,
    "error": "No window matches the given criteria."
  }
]
```

**Handling**: Log error, continue with next operation (non-fatal)

### IPC Socket Unavailable
```
Error: Unable to connect to i3 IPC socket
```

**Handling**: Exit with code 4, suggest user verify i3 is running

### Invalid JSON in Layout
```
Error: Failed to append layout from file X: JSON parse error at line Y
```

**Handling**: Log error, skip layout restoration, continue with launch commands

---

## Performance Considerations

### GET_TREE Query Optimization
- GET_TREE returns full window tree (can be 100KB+ JSON)
- Use jq streaming parser for large trees: `jq -c '.. | select(.marks?)'`
- Cache tree queries within same script invocation (avoid multiple calls)

### Batch Commands
Combine multiple commands in single i3-msg call:
```bash
i3-msg 'workspace 2; append_layout layout.json; exec code /etc/nixos'
```

### Asynchronous Operations
- Scratchpad move/show operations can be slow with many windows
- Don't wait for scratchpad operations to complete before sending tick event
- Use fire-and-forget for non-critical operations

---

## Testing i3 IPC

### Verify i3 IPC Socket
```bash
i3 --get-socketpath
# Output: /run/user/1000/i3/ipc-socket.123
```

### Test Command Response
```bash
i3-msg 'workspace 2' && echo "Success" || echo "Failed"
```

### Monitor IPC Traffic (Debug)
```bash
strace -e trace=sendto,recvfrom i3-msg 'workspace 2'
```

### Validate Layout JSON
```bash
# Test that layout loads without error
i3-msg "workspace 2; append_layout /tmp/test.json"
```

---

## Dependencies

**Required**:
- i3 >= 4.15 (tick events support)
- jq >= 1.6 (JSON parsing)
- bash >= 5.0

**Optional**:
- python3-i3ipc (for event-driven scripts)
- socat (for raw IPC socket access)

---

## Contract Violations

The following are **forbidden** and violate the i3-native design:

❌ Custom window tracking database (use i3 marks instead)
❌ Polling i3 state repeatedly (use events and single queries)
❌ Parsing `i3-msg -t get_tree` output with regex (use jq)
❌ Storing window-to-project mapping externally (use marks)
❌ Custom IPC server for project management (use i3 IPC)
❌ Modifying i3 source code or config generation
❌ Forking i3-msg or i3 daemon

The following are **required** for compliance:

✅ All window operations via `i3-msg` or i3ipc library
✅ Use marks for window-to-project association
✅ Use tick events for state synchronization
✅ Use append_layout for workspace restoration
✅ Use native workspace output assignments
✅ Graceful handling of i3 IPC errors
