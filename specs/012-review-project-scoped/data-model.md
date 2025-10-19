# Data Model: i3-Native Dynamic Project Workspace Management

**Date**: 2025-10-19
**Feature**: 012-review-project-scoped

## Overview

This document defines the data structures, entities, and relationships for the i3-native project workspace management system. All entities are stored as JSON files or plain text files in `~/.config/i3/` directory.

## Core Entities

### 1. Project Configuration

**File Location**: `~/.config/i3/projects/{project_name}.json`

**Purpose**: Defines a project's workspace layout, application assignments, and metadata

**Schema**:
```json
{
  "$schema": "http://i3wm.org/schemas/project-config.json",
  "version": "1.0",
  "project": {
    "name": "string (required, matches filename without .json)",
    "displayName": "string (optional, human-readable name)",
    "icon": "string (optional, unicode icon/emoji)",
    "directory": "string (required, absolute path)"
  },
  "workspaces": {
    "1": {
      "layout": "object (optional, i3 layout JSON)",
      "launchCommands": [
        "string (shell command to execute)"
      ]
    },
    "2": {
      "layout": "object (optional)",
      "launchCommands": []
    }
  },
  "workspaceOutputs": {
    "1": "string (optional, output name like 'eDP-1')",
    "2": "string (optional)"
  },
  "appClasses": [
    "string (WM_CLASS values for project-scoped apps)"
  ]
}
```

**Validation Rules**:
- `project.name` must match filename (e.g., `nixos.json` → name: "nixos")
- `project.name` must be filesystem-safe (alphanumeric, dash, underscore only)
- `project.directory` must be absolute path
- Workspace numbers must be integers 1-10
- `layout` must be valid i3 layout JSON if present
- `launchCommands` array may be empty

**Example**:
```json
{
  "$schema": "http://i3wm.org/schemas/project-config.json",
  "version": "1.0",
  "project": {
    "name": "nixos",
    "displayName": "NixOS Configuration",
    "icon": "",
    "directory": "/etc/nixos"
  },
  "workspaces": {
    "1": {
      "launchCommands": [
        "ghostty --working-directory /etc/nixos -e sesh connect nixos"
      ]
    },
    "2": {
      "layout": {
        "border": "pixel",
        "layout": "splith",
        "marks": ["project:nixos"],
        "nodes": [
          {
            "swallows": [{"class": "^Code$"}],
            "marks": ["project:nixos", "editor"]
          }
        ]
      },
      "launchCommands": [
        "code /etc/nixos"
      ]
    }
  },
  "workspaceOutputs": {
    "1": "eDP-1",
    "2": "HDMI-1"
  },
  "appClasses": [
    "Code",
    "Ghostty",
    "lazygit",
    "yazi"
  ]
}
```

**Relationships**:
- References Active Project State (one-to-zero-or-one: only one project active)
- References Application Classes (many-to-many: multiple classes can be in multiple projects)
- Creates i3 Window Marks when project is activated

### 2. Active Project State

**File Location**: `~/.config/i3/active-project`

**Purpose**: Tracks which project is currently active (if any)

**Format**: Plain text file containing project name

**Content**:
```
nixos
```

or empty file if no project is active

**Validation Rules**:
- Content must match existing project JSON filename (without .json extension)
- File must exist even when empty (empty = no active project)
- File permissions: 0644 (readable by user and group)

**State Transitions**:
- Empty → "project_name" : User activates project via switcher
- "project_name" → Empty : User clears project (Win+Shift+P)
- "project_A" → "project_B" : User switches between projects
- Preserved across i3 restart/reload

**Relationships**:
- Referenced by Project Configuration (inverse: which project is active)
- Used by Application Launchers to determine window marking
- Monitored by Polybar module for display

### 3. Application Class Configuration

**File Location**: `~/.config/i3/app-classes.json`

**Purpose**: Defines which WM_CLASS values are project-scoped vs global

**Schema**:
```json
{
  "version": "1.0",
  "classes": [
    {
      "class": "string (required, WM_CLASS value)",
      "instance": "string (optional, WM_CLASS instance)",
      "scoped": "boolean (required, true = project-scoped)",
      "workspace": "integer (optional, default workspace 1-10)",
      "description": "string (optional, human-readable)"
    }
  ]
}
```

**Example**:
```json
{
  "version": "1.0",
  "classes": [
    {
      "class": "Code",
      "scoped": true,
      "workspace": 2,
      "description": "VS Code editor"
    },
    {
      "class": "Ghostty",
      "scoped": true,
      "workspace": 1,
      "description": "Ghostty terminal"
    },
    {
      "class": "Firefox",
      "scoped": false,
      "description": "Firefox browser (global)"
    }
  ]
}
```

**Validation Rules**:
- `class` field is required
- `scoped` field is required (boolean)
- `workspace` must be integer 1-10 if present
- Duplicate class entries: last one wins (array order matters)

**Default Behavior** (if file missing or class not found):
- Pattern matching on class name:
  - Contains "term", "terminal", "konsole": scoped = true, workspace = 1
  - Contains "code", "vim", "emacs", "idea": scoped = true, workspace = 2
  - Contains "git", "lazygit", "gitg": scoped = true, workspace = 1
  - All others: scoped = false (global)

**Relationships**:
- Referenced by Application Launchers to determine marking behavior
- Referenced by Project Configurations (appClasses array)

### 4. i3 Window Mark

**Storage**: Managed by i3 window manager (not a file)

**Purpose**: Associates windows with projects using i3's native marking system

**Format**: String mark in format `project:{project_name}`

**Examples**:
- `project:nixos`
- `project:stacks`
- `project:api-gateway`

**Properties**:
- Multiple marks can exist on same window
- Marks persist across i3 restart
- Marks are removed when window closes
- Marks can be queried via i3 IPC GET_TREE

**Lifecycle**:
1. Window launches → Application Launcher checks active-project file
2. If project active AND class is scoped → Apply mark `project:{name}`
3. If project switches → Move marked windows to/from scratchpad
4. If window closes → i3 automatically removes mark
5. If project deleted → Marks become orphaned (harmless, can be cleaned up)

**Querying Marks**:
```bash
# Get all windows with specific mark
i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'

# Select windows by mark for operations
i3-msg '[con_mark="project:nixos"] move scratchpad'
```

**Relationships**:
- Created by Application Launchers based on Active Project State
- Referenced by Project Switch scripts for visibility management
- Linked to Project Configuration (project name embedded in mark)

### 5. i3 Layout Definition

**Storage**: Embedded in Project Configuration JSON (workspaces.*.layout field)

**Purpose**: Defines window placement, split directions, and swallows criteria

**Format**: Standard i3 layout JSON (see i3 layout-saving documentation)

**Key Fields**:
```json
{
  "border": "normal|pixel|none",
  "floating": "auto_on|auto_off|user_on|user_off",
  "layout": "splith|splitv|stacked|tabbed",
  "percent": "float (0.0-1.0, percentage of parent container)",
  "type": "con|floating_con|workspace",
  "marks": ["string", "..."],
  "nodes": [
    {
      "swallows": [
        {
          "class": "^RegexPattern$",
          "instance": "^RegexPattern$",
          "title": "^RegexPattern$",
          "window_role": "^RegexPattern$"
        }
      ]
    }
  ]
}
```

**Swallows Criteria** (how i3 matches windows to placeholders):
- Uses regex matching on window properties
- Common patterns:
  - `{"class": "^Code$"}` - exact match VS Code
  - `{"class": "^Ghostty$", "instance": "^ghostty$"}` - terminal with instance
  - `{"title": ".*nixos.*"}` - any window with "nixos" in title

**Lifecycle**:
1. Project activated → `i3-msg 'workspace 2; append_layout layout.json'`
2. Placeholders created on workspace
3. Applications launched via launchCommands
4. i3 automatically assigns windows to placeholders based on swallows
5. Placeholder consumed, window appears in correct position

**Validation**:
- Must be valid JSON
- Must follow i3 layout schema (validate with i3-msg)
- Swallows regex must be valid PCRE

**Relationships**:
- Embedded in Project Configuration (workspaces.*.layout)
- References Window Marks via marks array
- Consumed by i3 during project activation

### 6. i3 Tick Event

**Storage**: Ephemeral (event-based, not persisted)

**Purpose**: Notify subscribers (polybar, custom scripts) of project state changes

**Format**: String payload in format `project:{project_name}` or `project:none`

**Examples**:
- `project:nixos` - NixOS project activated
- `project:stacks` - Stacks project activated
- `project:none` - No project active (cleared)

**Delivery**:
```bash
# Send tick event
i3-msg -t send_tick -m 'project:nixos'

# Subscribe to tick events (in Python script)
import i3ipc
i3 = i3ipc.Connection()
def on_tick(i3, event):
    print(f"Received: {event.payload}")
i3.on('tick', on_tick)
i3.main()
```

**Lifecycle**:
1. Project state changes (activation, switch, clear)
2. Project script sends tick event via i3-msg
3. i3 broadcasts event to all IPC subscribers
4. Subscribers update their state (polybar text, logging, etc.)
5. Event discarded (not persisted)

**Relationships**:
- Triggered by changes to Active Project State
- Consumed by Polybar Module for display updates
- Referenced in Project Configuration (project name in payload)

## Entity Relationship Diagram

```
┌─────────────────────────┐
│ Project Configuration   │
│ (JSON files)            │
│ ~/.config/i3/projects/  │
└───────────┬─────────────┘
            │
            │ references (via name)
            ▼
┌─────────────────────────┐         ┌──────────────────────┐
│ Active Project State    │────────▶│ i3 Tick Event        │
│ (text file)             │ triggers│ (ephemeral)          │
│ ~/.config/i3/active-... │         └──────────────────────┘
└───────────┬─────────────┘
            │
            │ determines marking
            ▼
┌─────────────────────────┐         ┌──────────────────────┐
│ Application Launchers   │────────▶│ i3 Window Mark       │
│ (shell scripts)         │ creates │ (i3 internal state)  │
│ ~/.config/i3/launchers/ │         └──────────────────────┘
└───────────┬─────────────┘
            │
            │ consults
            ▼
┌─────────────────────────┐
│ Application Classes     │
│ (JSON file)             │
│ ~/.config/i3/app-cla... │
└─────────────────────────┘

┌─────────────────────────┐
│ i3 Layout Definition    │
│ (embedded in project)   │
└───────────┬─────────────┘
            │
            │ consumed by
            ▼
       [i3-msg append_layout]
```

## Data Validation Strategy

### On Project Creation
1. Validate project name is filesystem-safe
2. Check project directory exists and is accessible
3. Ensure project.json doesn't already exist (or prompt to overwrite)
4. Validate JSON schema if layout provided
5. Write project.json atomically (temp file + rename)

### On Project Activation
1. Verify project.json exists and is readable
2. Parse JSON with jq, exit on parse error
3. Validate project.directory is accessible
4. Test i3 IPC connectivity before sending commands
5. Log errors to ~/.config/i3/project-manager.log

### On Application Launch
1. Check active-project file exists and is readable
2. Verify project referenced in active-project exists
3. Validate app-classes.json if present (use defaults if invalid)
4. Timeout on window ID retrieval (2 seconds max)
5. Graceful degradation: launch app even if marking fails

## File Permissions

All configuration files must be user-writable:

```
~/.config/i3/projects/           755 (drwxr-xr-x)
~/.config/i3/projects/*.json     644 (-rw-r--r--)
~/.config/i3/active-project      644 (-rw-r--r--)
~/.config/i3/app-classes.json    644 (-rw-r--r--)
~/.config/i3/launchers/          755 (drwxr-xr-x)
~/.config/i3/launchers/*         755 (-rwxr-xr-x)
```

## Backwards Compatibility

**Migration from Static NixOS Configuration**:
- Existing projects defined in `home-modules/desktop/i3-projects.nix` (hypothetical)
- Migration tool reads Nix expressions, generates JSON files
- NixOS can continue to provide default projects declaratively via environment.etc
- User-created projects coexist with NixOS-managed defaults

**Schema Versioning**:
- All JSON files include `"version": "1.0"` field
- Future schema changes increment version
- Scripts check version field and apply appropriate parsing logic
- Unknown versions log warning but attempt best-effort parsing

## Performance Considerations

**File I/O**:
- Project JSON files: <10KB typical, <100KB maximum
- Parse time with jq: <50ms on typical hardware
- Active project file: <100 bytes, read time negligible
- Total project switch time: <500ms (including i3 IPC round-trips)

**i3 IPC**:
- GET_TREE queries: <100ms for typical window count (50 windows)
- COMMAND messages (move, mark): <10ms per window
- SEND_TICK: <5ms (broadcast to subscribers)
- Subscribe connections: low overhead, persistent socket

**Scalability**:
- 20 projects: No performance impact (only active project is loaded)
- 50 windows per project: Acceptable (scratchpad operations parallelized by i3)
- 5 concurrent i3 IPC subscribers: No measurable overhead

## Error Handling

**Project JSON Parse Errors**:
- Log error with jq error message
- Display rofi notification with error details
- Fall back to simple workspace assignment (no layout)
- Active project state remains unchanged

**i3 IPC Errors**:
- Detect with i3-msg exit code check
- Retry once with 100ms delay
- Log to project-manager.log
- Display user notification via rofi or notify-send

**Missing Project Directory**:
- Warn user via notification
- Allow project activation (directory may be on unmounted drive)
- Applications fail gracefully with "directory not found"

**Window ID Retrieval Timeout**:
- Log timeout event
- Launch application without mark (behaves as global)
- Suggest user manually mark window with i3-project-mark-window command

## Testing Data

**Minimal Valid Project**:
```json
{
  "version": "1.0",
  "project": {
    "name": "test",
    "directory": "/tmp/test"
  },
  "workspaces": {},
  "workspaceOutputs": {},
  "appClasses": []
}
```

**Full-Featured Project** (for integration testing):
```json
{
  "version": "1.0",
  "project": {
    "name": "integration-test",
    "displayName": "Integration Test Project",
    "icon": "",
    "directory": "/tmp/integration-test"
  },
  "workspaces": {
    "1": {
      "launchCommands": [
        "echo 'workspace 1' > /tmp/test-ws1.txt"
      ]
    },
    "2": {
      "layout": {
        "layout": "splith",
        "nodes": [
          {"swallows": [{"class": "^XTerm$"}]}
        ]
      },
      "launchCommands": [
        "xterm -e 'echo test; sleep 10'"
      ]
    }
  },
  "workspaceOutputs": {
    "1": "eDP-1"
  },
  "appClasses": ["XTerm"]
}
```
