# Data Model: i3 Project Management System

**Feature**: 014 - Consolidate and Validate i3 Project Management System
**Date**: 2025-10-19
**Phase**: Phase 1 - Design

## Overview

This data model defines all entities in the i3 project management system, their fields, relationships, validation rules, and state transitions. The system follows a **hybrid approach**: runtime window and workspace state is managed entirely by i3's native mechanisms (marks, IPC queries), while project metadata and configuration are stored in minimal external JSON files.

**Design Principle**: Minimize external state. Prefer i3 native features (marks, workspace names, IPC queries) over custom data structures.

---

## Entity Catalog

| Entity | Storage | Source of Truth | Mutable |
|--------|---------|----------------|---------|
| i3 Tree State | i3 IPC | i3 window manager | Yes (by i3) |
| i3 Workspace State | i3 IPC | i3 window manager | Yes (by i3) |
| i3 Window Mark | i3 container | i3 window manager | Yes (via i3-msg) |
| Project Configuration | JSON file | User creation | Rarely |
| Active Project Metadata | JSON file | Project switch | Frequently |
| Application Classification | JSON file | NixOS config | Rarely |
| Project System Log | Text file | All operations | Append-only |

---

## 1. i3 Tree State (Native)

**Definition**: The complete hierarchical representation of all containers, windows, workspaces, and outputs in i3.

### Fields

| Field | Type | Source | Description | Validation |
|-------|------|--------|-------------|-----------|
| `id` | integer | i3 | Internal C pointer (unique identifier) | Read-only |
| `type` | enum | i3 | Container type: `root`, `output`, `con`, `floating_con`, `workspace`, `dockarea` | Read-only |
| `name` | string | i3/window | Human-readable name (_NET_WM_NAME for windows) | Read-only |
| `window` | integer | i3 | X11 window ID (null for containers) | Read-only |
| `window_properties` | object | i3 | X11 properties: `class`, `instance`, `window_role`, `title` | Read-only |
| `marks` | array[string] | i3 | Marks assigned to this container | Writable via i3-msg |
| `rect` | object | i3 | Absolute coordinates: `{x, y, width, height}` | Read-only |
| `layout` | enum | i3 | Layout mode: `splith`, `splitv`, `stacked`, `tabbed`, `dockarea`, `output` | Writable via i3-msg |
| `nodes` | array[container] | i3 | Child containers (tiling) | Read-only |
| `floating_nodes` | array[container] | i3 | Child containers (floating) | Read-only |
| `focused` | boolean | i3 | Whether this container has focus | Read-only |
| `urgent` | boolean | i3 | Urgency hint set | Read-only |
| `fullscreen_mode` | integer | i3 | 0 (none), 1 (output), 2 (global) | Writable via i3-msg |
| `swallows` | array[criteria] | i3 | Window matching criteria for append_layout | Writable via append_layout |

### Access Pattern

```bash
# Query entire tree
i3-msg -t get_tree

# Query specific windows by mark (project management use case)
i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'
```

### Relationships

- Parent: Single parent container (except root)
- Children: 0+ child containers in `nodes` or `floating_nodes`
- Marks: 0+ string marks associated with container

### Validation Rules

- System MUST NOT cache i3 tree state (query dynamically via IPC)
- System MUST NOT transform i3 tree structure (consume as-is)
- Window marks MUST follow format: `project:PROJECT_NAME` or `project:PROJECT_NAME:SUFFIX`

### Notes

This is the **primary source of truth** for all window-project associations. The `marks` array is the only custom data the project management system stores in i3's native state.

---

## 2. i3 Workspace State (Native)

**Definition**: Current state of all workspaces in i3.

### Fields

| Field | Type | Source | Description | Validation |
|-------|------|--------|-------------|-----------|
| `id` | integer | i3 | Unique workspace ID | Read-only |
| `num` | integer | i3 | Numeric workspace number (-1 for named workspaces) | Read-only |
| `name` | string | i3 | Display name (may include icons) | Read-only |
| `visible` | boolean | i3 | Currently visible on some output | Read-only |
| `focused` | boolean | i3 | Has focus (only one workspace true at a time) | Read-only |
| `urgent` | boolean | i3 | Contains urgent window | Read-only |
| `rect` | object | i3 | Coordinates: `{x, y, width, height}` | Read-only |
| `output` | string | i3 | Monitor/output name (e.g., HDMI-1, eDP-1, rdp0) | Read-only |

### Access Pattern

```bash
# Query all workspaces
i3-msg -t get_workspaces

# Query focused workspace
i3-msg -t get_workspaces | jq '.[] | select(.focused == true)'
```

### Relationships

- Output: 1 output (monitor) per workspace
- Windows: 0+ windows (via tree state, not workspace query)

### Validation Rules

- System MUST query workspace state dynamically (no caching)
- System MUST NOT assume workspace numbering (gaps allowed)
- System MUST handle named workspaces (num == -1)

### Notes

Used primarily for multi-monitor workspace assignment. The project management system does not modify workspace properties directly (i3 handles this automatically).

---

## 3. i3 Window Mark (Native)

**Definition**: A string label attached to an i3 container to identify project membership.

### Format

```
project:PROJECT_NAME[:SUFFIX]
```

**Examples**:
- `project:nixos` - Window belongs to "nixos" project
- `project:stacks:term0` - Terminal 0 in "stacks" project
- `project:personal:term1` - Terminal 1 in "personal" project

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|-----------|
| prefix | literal | Always "project" | Required |
| project_name | string | Project identifier | Required, alphanumeric+dash, 1-50 chars |
| suffix | string | Optional instance identifier | Optional, alphanumeric+dash, 1-20 chars |

### Operations

```bash
# Add mark to window
i3-msg "[id=$WINDOW_ID] mark --add \"project:nixos\""

# Remove mark from window
i3-msg "[id=$WINDOW_ID] unmark \"project:nixos\""

# Query windows by mark
i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'

# Move all windows with mark
i3-msg "[con_mark=\"project:nixos\"] move scratchpad"
```

### Validation Rules

- Mark MUST start with "project:" prefix
- Project name MUST match existing project in `~/.config/i3/projects/`
- Mark MUST be unique per window (window can have multiple marks)
- Suffix is OPTIONAL and user-defined (used for terminal instance numbering)

### State Transitions

```
[Window Created] → [Unmarked]
    ↓
[Launch in Project Context] → [Marked: project:NAME]
    ↓
[Project Switch Away] → [Window moved to scratchpad, mark retained]
    ↓
[Project Switch Back] → [Window restored from scratchpad, mark retained]
    ↓
[Window Closed] → [Mark deleted by i3 automatically]
```

### Notes

Marks are **persistent across i3 restarts** via i3's native state persistence. Marks are the **only custom data** the system stores in i3's runtime state.

---

## 4. Project Configuration

**Definition**: Static metadata defining a project's identity, directory, and optional workspace layout.

### Storage

- **Path**: `~/.config/i3/projects/PROJECT_NAME.json`
- **Format**: JSON
- **Generator**: `project-create.sh` script
- **Managed by**: NixOS (deployed by home-manager module)

### Schema

```json
{
  "version": "1.0",
  "project": {
    "name": "nixos",
    "displayName": "NixOS Configuration",
    "icon": "",
    "directory": "/etc/nixos"
  },
  "workspaces": {
    "2": {
      "layout_file": "/path/to/layout.json"
    }
  },
  "workspaceOutputs": {
    "2": "HDMI-1",
    "3": "eDP-1"
  },
  "appClasses": []
}
```

### Field Definitions

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|-----------|
| `version` | string | Yes | Schema version (for future migrations) | Semver format |
| `project.name` | string | Yes | Unique project identifier | Alphanumeric+dash, 1-50 chars, matches filename |
| `project.displayName` | string | Yes | Human-readable project name | 1-100 chars, any UTF-8 |
| `project.icon` | string | Yes | Unicode emoji or Nerd Font icon | 0-10 chars, UTF-8 emoji |
| `project.directory` | string | Yes | Absolute path to project root | Valid absolute path, directory must exist |
| `workspaces` | object | No | Optional workspace layouts | Keys are workspace numbers (string) |
| `workspaces.N.layout_file` | string | No | Path to i3 append_layout JSON file | Valid path to i3-compatible layout file |
| `workspaceOutputs` | object | No | Workspace-to-monitor assignments | Keys are workspace numbers, values are output names |
| `appClasses` | array | No | Reserved for future use (currently unused) | Empty array or omitted |

### Validation Rules

- Project name MUST be unique across all projects
- Project directory MUST be an absolute path
- Project directory SHOULD exist at creation time (warning if missing)
- Workspace layout files (if specified) MUST be valid i3 append_layout format
- Workspace output assignments reference outputs that MAY not exist (i3 handles missing outputs)

### Relationships

- Created by: `project-create.sh` (user-initiated)
- Read by: `project-switch.sh`, `project-list.sh`, rofi project switcher
- Modified by: `project-edit.sh` (future enhancement)
- Deleted by: `project-delete.sh`

### Lifecycle

```
[project-create] → [File created in ~/.config/i3/projects/]
    ↓
[Project active/inactive] → [File remains unchanged]
    ↓
[project-delete] → [File deleted, active-project cleared if this was active]
```

### Notes

This is **static configuration**, not runtime state. It does not track which windows are currently associated with the project (that's done via i3 marks).

---

## 5. Active Project Metadata

**Definition**: Minimal runtime state tracking which project is currently active.

### Storage

- **Path**: `~/.config/i3/active-project`
- **Format**: JSON
- **Generator**: `project-switch.sh` (on switch), `project-clear.sh` (on clear)
- **Consumer**: i3blocks `project.sh` status bar script

### Schema

```json
{
  "name": "nixos",
  "display_name": "NixOS Configuration",
  "icon": ""
}
```

### Field Definitions

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|-----------|
| `name` | string | Yes | Project identifier | Must match existing project config |
| `display_name` | string | Yes | Human-readable name for display | 1-100 chars |
| `icon` | string | Yes | Icon for status bar | UTF-8 emoji or Nerd Font icon |

### Special States

**No Active Project**:
```json
{}
```
or file does not exist

Status bar should display: "∅ No Project"

### Validation Rules

- File MUST contain valid JSON (malformed JSON treated as no active project)
- If `name` field exists, corresponding project config MUST exist in `~/.config/i3/projects/`
- Fields are duplicated from project config for fast status bar reads (no join required)

### Relationships

- Written by: `project-switch.sh`, `project-clear.sh`
- Read by: `project.sh` (i3blocks), `project-current.sh`
- Updated: On every project switch or clear

### State Transitions

```
[System Start] → [File missing or empty] → "No Project"
    ↓
[project-switch nixos] → [File written with project metadata] → " NixOS Configuration"
    ↓
[project-switch stacks] → [File overwritten] → " Stacks Development"
    ↓
[project-clear] → [File cleared to {}] → "∅ No Project"
```

### Synchronization

**File Write → Status Bar Update Flow**:
1. Script writes JSON to temp file
2. Script renames temp → active-project (atomic)
3. Script sends SIGRTMIN+10 to i3blocks
4. i3blocks re-runs project.sh
5. project.sh reads active-project
6. i3bar displays updated text

**Timing**: <1 second end-to-end (measured)

### Notes

This file is **redundant with i3 mark state** (active project can be inferred from window marks) but maintained for **fast status bar queries** without parsing full i3 tree.

---

## 6. Application Classification

**Definition**: Global configuration defining which application window classes should receive project marks.

### Storage

- **Path**: `~/.config/i3/app-classes.json`
- **Format**: JSON
- **Generator**: NixOS configuration (via i3-projects.nix module)
- **Managed by**: Declarative configuration

### Schema

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
      "class": "firefox",
      "scoped": false,
      "workspace": 3,
      "description": "Firefox browser (global)"
    }
  ]
}
```

### Field Definitions

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|-----------|
| `version` | string | Yes | Schema version | Semver format |
| `classes` | array | Yes | Application classifications | 0+ entries |
| `classes[].class` | string | Yes | X11 WM_CLASS value | Exact match, case-sensitive |
| `classes[].scoped` | boolean | Yes | Whether app should receive project mark | true = scoped, false = global |
| `classes[].workspace` | integer | No | Preferred workspace number | 1-20 |
| `classes[].description` | string | Yes | Human-readable description | For documentation |

### Validation Rules

- WM_CLASS values MUST match actual X11 window classes
- `scoped: true` applications receive `project:NAME` mark when launched
- `scoped: false` applications never receive project marks (remain visible across switches)
- Workspace preference is advisory (i3 may override based on current focus)

### Relationships

- Defined by: NixOS home-manager module `i3-projects.nix`
- Read by: Application launcher scripts (`launch-code.sh`, `launch-ghostty.sh`, etc.)
- Updated by: NixOS rebuild (declarative)

### Example Classification

**Scoped Applications** (hidden when switching projects):
- `Code` - VS Code
- `Alacritty` - Alacritty terminal
- `ghostty` - Ghostty terminal
- Custom application launchers

**Global Applications** (always visible):
- `firefox` - Firefox browser
- `k9s` - Kubernetes TUI
- PWAs (YouTube Music, Google AI)

### Notes

This is **global configuration** shared across all projects. Individual projects do not override application classifications.

---

## 7. Project System Log

**Definition**: Structured append-only log of all project management operations, i3 events, and errors.

### Storage

- **Path**: `~/.config/i3/project-system.log`
- **Format**: Text (structured lines)
- **Rotation**: 10MB max size, keep 5 historical files
- **Generator**: All project management scripts via `log()` function

### Format

```
[TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
```

**Example**:
```
[2025-10-19 14:32:15] [INFO] [project-switch] Switching to project: nixos
[2025-10-19 14:32:15] [DEBUG] [project-switch] Reading project config: /home/user/.config/i3/projects/nixos.json
[2025-10-19 14:32:15] [DEBUG] [i3-ipc] i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:stacks"]))'
[2025-10-19 14:32:15] [INFO] [project-switch] Hiding 8 windows from project: stacks
[2025-10-19 14:32:15] [DEBUG] [i3-cmd] i3-msg '[con_mark="project:stacks"] move scratchpad'
[2025-10-19 14:32:15] [INFO] [project-switch] Showing 5 windows from project: nixos
[2025-10-19 14:32:16] [INFO] [project-switch] Updated active project file
[2025-10-19 14:32:16] [DEBUG] [signal] pkill -RTMIN+10 i3blocks
[2025-10-19 14:32:16] [INFO] [project-switch] Project switch completed in 0.8s
[2025-10-19 14:32:17] [ERROR] [launch-code] Failed to launch VS Code: code command not found
```

### Field Definitions

| Field | Format | Description | Validation |
|-------|--------|-------------|-----------|
| TIMESTAMP | ISO 8601 | `YYYY-MM-DD HH:MM:SS` | Local time |
| LEVEL | enum | `DEBUG`, `INFO`, `WARN`, `ERROR` | Uppercase |
| COMPONENT | string | Script or module name | Alphanumeric+dash, 1-30 chars |
| MESSAGE | string | Log message with context | Free-form, 1-500 chars |

### Log Levels

- **DEBUG**: Detailed information for troubleshooting (i3-msg commands, JSON parsing, timing)
- **INFO**: Normal operation events (project switched, window marked, config loaded)
- **WARN**: Recoverable errors (missing project directory, i3blocks not running, slow operations)
- **ERROR**: Failures that prevent operation (invalid JSON, command failed, missing dependencies)

### Validation Rules

- Timestamps MUST be in local time (not UTC)
- Log lines MUST be single-line (newlines in messages escaped)
- Rotation MUST preserve at least last 5 files
- Log writes MUST be atomic (append with >>)

### Rotation Strategy

```bash
# When log exceeds 10MB:
mv project-system.log project-system.log.1
mv project-system.log.1 project-system.log.2
mv project-system.log.2 project-system.log.3
mv project-system.log.3 project-system.log.4
mv project-system.log.4 project-system.log.5
rm project-system.log.5  # Delete oldest
touch project-system.log  # Create new
```

### Access Pattern

```bash
# Tail live logs
tail -f ~/.config/i3/project-system.log

# Filter by level
grep '\[ERROR\]' ~/.config/i3/project-system.log

# Filter by component
grep '\[project-switch\]' ~/.config/i3/project-system.log

# View last 50 lines
project-logs --tail 50

# Filter by time range (future enhancement)
project-logs --since "2025-10-19 14:00:00" --until "2025-10-19 15:00:00"
```

### Relationships

- Written by: All project scripts via shared `log()` function
- Read by: `project-logs` viewer, manual debugging
- Rotated by: Log rotation script (future enhancement)

### Notes

Logging is **best-effort** - log write failures do not prevent script execution. Debug mode increases verbosity (logs full i3 IPC responses, timing for every operation).

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         i3 Window Manager                            │
│  ┌───────────────────┐           ┌──────────────────────┐          │
│  │  i3 Tree State    │◄─────────►│ i3 Workspace State   │          │
│  │  (get_tree)       │           │ (get_workspaces)     │          │
│  │                   │           │                      │          │
│  │  - containers     │           │  - num, name         │          │
│  │  - windows        │           │  - output            │          │
│  │  - marks ◄────────┼───────┐   │  - visible, focused  │          │
│  └───────────────────┘       │   └──────────────────────┘          │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
                               │ Window Mark
                               │ "project:NAME"
                               │
       ┌───────────────────────┴────────────────────────┐
       │                                                 │
       ▼                                                 ▼
┌─────────────────────┐                      ┌────────────────────────┐
│ Project             │                      │ Active Project         │
│ Configuration       │                      │ Metadata               │
│                     │                      │                        │
│ ~/.config/i3/       │◄─────reads──────────┤│ ~/.config/i3/          │
│ projects/NAME.json  │                      │ active-project         │
│                     │                      │                        │
│ - name              │                      │ - name (denormalized)  │
│ - displayName       │                      │ - display_name         │
│ - icon              │                      │ - icon                 │
│ - directory         │                      │                        │
│ - workspaces        │                      └────────────────────────┘
│ - workspaceOutputs  │                                 │
└─────────────────────┘                                 │
       │                                                │
       │                                                ▼
       │                                      ┌────────────────────────┐
       │                                      │ i3blocks Status Bar    │
       │                                      │ (project.sh)           │
       │                                      │                        │
       │                                      │ Displays:              │
       │                                      │ " NixOS Configuration" │
       │                                      └────────────────────────┘
       │
       ▼
┌─────────────────────┐
│ Application         │
│ Classification      │
│                     │
│ ~/.config/i3/       │
│ app-classes.json    │
│                     │
│ - class (WM_CLASS)  │
│ - scoped (bool)     │
│ - workspace (int)   │
└─────────────────────┘
       │
       │ read by
       ▼
┌─────────────────────┐
│ Launcher Scripts    │
│                     │
│ - launch-code.sh    │
│ - launch-ghostty.sh │
│ - launch-lazygit.sh │
│                     │
│ Determine if app    │
│ should receive mark │
└─────────────────────┘
       │
       │ all operations logged to
       ▼
┌─────────────────────┐
│ Project System Log  │
│                     │
│ ~/.config/i3/       │
│ project-system.log  │
│                     │
│ [TIMESTAMP] [LEVEL] │
│ [COMPONENT] MESSAGE │
└─────────────────────┘
```

---

## Data Flow Scenarios

### Scenario 1: Create New Project

```
1. User: project-create --name "api-gateway" --dir ~/code/api --icon ""
2. Script validates inputs (name unique, directory exists)
3. Script generates JSON:
   {
     "version": "1.0",
     "project": {
       "name": "api-gateway",
       "displayName": "API Gateway",
       "icon": "",
       "directory": "/home/user/code/api"
     },
     "workspaces": {},
     "workspaceOutputs": {},
     "appClasses": []
   }
4. Script writes to ~/.config/i3/projects/api-gateway.json
5. Script logs: [INFO] [project-create] Created project: api-gateway
6. Project appears in rofi switcher (project-list reads all *.json files)
```

### Scenario 2: Switch Project

```
1. User: project-switch nixos (or Win+P → select "NixOS")
2. Script reads ~/.config/i3/projects/nixos.json
3. Script queries i3 for current active project windows:
   i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:stacks"]))'
4. Script hides old project windows:
   i3-msg '[con_mark="project:stacks"] move scratchpad'
5. Script shows new project windows:
   i3-msg '[con_mark="project:nixos"] scratchpad show'
6. Script writes active-project file:
   { "name": "nixos", "display_name": "NixOS", "icon": "" }
7. Script sends signal:
   pkill -RTMIN+10 i3blocks
8. i3blocks re-runs project.sh
9. project.sh reads active-project, outputs " NixOS"
10. i3bar displays updated indicator
11. Script logs: [INFO] [project-switch] Switched to project: nixos (0.8s)
```

### Scenario 3: Launch Application in Project Context

```
1. Active project: nixos (from active-project file)
2. User: launch-code.sh (or Win+C keybinding)
3. Script reads ~/.config/i3/app-classes.json
4. Script finds: { "class": "Code", "scoped": true, "workspace": 2 }
5. Script launches: code /etc/nixos &
6. Script waits for window to appear:
   xdotool search --classname "code" (poll up to 5 seconds)
7. Script marks window:
   i3-msg "[id=$WINDOW_ID] mark --add \"project:nixos\""
8. Script logs: [INFO] [launch-code] Launched VS Code in project: nixos
9. Window now visible only when nixos project is active
10. i3 tree state includes: { "window": 12345, "marks": ["project:nixos"] }
```

### Scenario 4: Query Current Project

```
1. User: project-current
2. Script reads ~/.config/i3/active-project
3. If file exists and valid: Output project name and icon
4. If file missing/invalid: Output "No active project"
5. Alternative implementation (slower but more authoritative):
   - Query i3 tree for all marks starting with "project:"
   - Find most common project in marks → infer active project
   - Handles edge case where active-project file is stale
```

### Scenario 5: i3 Restart

```
1. i3 is restarted (Win+Shift+R)
2. i3 restores all window positions and marks from saved state
3. active-project file remains unchanged on disk
4. Project system continues working without intervention:
   - Window marks still present (project:nixos on VS Code)
   - project-switch still hides/shows correct windows
   - Status bar still displays correct project
5. No migration or recovery needed
```

---

## Validation & Integrity

### Project Configuration Validation

**Script**: `project-validate.sh PROJECT_NAME`

**Checks**:
1. JSON is well-formed (jq parse succeeds)
2. Required fields present: `version`, `project.name`, `project.displayName`, `project.icon`, `project.directory`
3. Project name matches filename (nixos.json → name: "nixos")
4. Directory is absolute path
5. Directory exists (warning if missing)
6. Workspace layout files exist (if specified)
7. Workspace numbers are valid (1-20)

### Active Project Consistency

**Check**: Does active-project reference existing project config?

```bash
active_name=$(jq -r '.name' ~/.config/i3/active-project)
if [ ! -f "~/.config/i3/projects/$active_name.json" ]; then
  echo "WARNING: Active project '$active_name' config not found"
fi
```

### Window Mark Consistency

**Check**: Do marked windows reference valid projects?

```bash
# Get all project marks from i3
i3-msg -t get_tree | jq -r '.. | .marks? | .[]? | select(startswith("project:"))'

# For each mark, verify project config exists
# Warn about orphaned marks (project deleted but windows still marked)
```

### Application Classification

**Check**: Do WM_CLASS values match actual applications?

```bash
# Get all running application classes
i3-msg -t get_tree | jq -r '.. | .window_properties?.class?' | sort -u

# Compare with app-classes.json
# Warn about classifications for non-existent apps
```

---

## Migration & Compatibility

### Version 1.0 (Current)

- Project config schema: 1.0
- Active project schema: implicit (no version field)
- Log format: unversioned text format

### Future Version 2.0 (Hypothetical)

**Potential Changes**:
- Add `tags` array to project config (for categorization)
- Add `color` field to project config (for status bar customization)
- Add `startup_apps` array (launch apps automatically on project switch)
- Change log format to JSON for better parsing

**Migration Strategy**:
1. Scripts detect `version` field in config files
2. Version 1.0 files migrated automatically on first read
3. Backup created before migration: `nixos.json.v1.backup`
4. Migration logged: [INFO] [migration] Upgraded nixos.json: 1.0 → 2.0

---

## Performance Characteristics

### Query Performance

| Operation | Time | Method |
|-----------|------|--------|
| Get active project | <10ms | Read active-project JSON (1KB) |
| List all projects | <50ms | Read all files in projects/ (typ. 5-20 files) |
| Query windows by mark | <100ms | i3-msg -t get_tree + jq filter |
| Switch project (10 windows) | <1s | Hide old + show new + signal i3blocks |
| Launch app with mark | <500ms | Launch + poll for window + mark |

### Storage Size

| Entity | Typical Size | Max Size |
|--------|-------------|----------|
| Project config | 500 bytes | 5 KB (with large layout files) |
| Active project | 150 bytes | 500 bytes |
| App classes | 2 KB | 20 KB |
| Log file (before rotation) | 1-5 MB | 10 MB (rotation threshold) |

### Scalability Limits

- **Projects**: 20 projects per user (reasonable limit for interactive switcher)
- **Windows per project**: 50+ windows (tested, no performance issues)
- **Concurrent i3 sessions**: 3-5 users on same server (Hetzner use case)
- **Log file growth**: ~100 KB/day with moderate use, ~1 MB/day with debug mode

---

## Security & Privacy

### Sensitive Data

**Project directory paths** may reveal:
- User home directory structure
- Presence of specific codebases
- Client/project names

**Mitigation**: Project configs have 600 permissions (user-readable only)

### Log Data

**Logs may contain**:
- Project names (potentially client-confidential)
- Directory paths
- Timing information (activity patterns)

**Mitigation**: Logs have 600 permissions, rotation prevents unbounded growth

### X11 Window Properties

**window_properties expose**:
- Application names (which tools user runs)
- Window titles (may contain file names, URLs)

**Mitigation**: i3 tree queries are local-only (not exposed over network)

---

## Conclusion

This data model defines a **minimal external state** approach where i3's native mechanisms (marks, IPC queries) are the source of truth for runtime window management, supplemented only by small JSON files for project metadata and status bar performance optimization. The design prioritizes i3 native integration, declarative configuration, and operational simplicity.
