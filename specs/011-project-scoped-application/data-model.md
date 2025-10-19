# Data Model: Project-Scoped Application Workspace Management

**Feature**: 011-project-scoped-application
**Date**: 2025-10-19

## Overview

This document defines the data structures, state management, and entity relationships for the project-scoped workspace management system.

## Core Entities

### 1. Project Definition

**Location**: `~/.config/i3/projects.json`

**Purpose**: Declarative definition of all available projects with their applications, directories, and workspace assignments.

**Schema**:
```json
{
  "<project-id>": {
    "name": "string",              // Display name (e.g., "NixOS Configuration")
    "directory": "string",          // Absolute path to project directory
    "icon": "string",              // Font Awesome icon for display
    "applications": [              // NEW: Application configuration array
      {
        "name": "string",          // Application identifier (e.g., "code", "ghostty")
        "workspace": number,        // Target workspace (1-9)
        "projectScoped": boolean,   // Whether app is project-scoped or global
        "wmClass": "string",        // Expected WM_CLASS for matching
        "command": "string",        // Launch command template
        "monitor_priority": number  // NEW: Monitor assignment priority (1=highest)
      }
    ]
  }
}
```

**Example**:
```json
{
  "nixos": {
    "name": "NixOS Configuration",
    "directory": "/etc/nixos",
    "icon": "",
    "applications": [
      {
        "name": "ghostty",
        "workspace": 1,
        "projectScoped": true,
        "wmClass": "ghostty",
        "command": "~/.config/i3/scripts/launch-ghostty.sh",
        "monitor_priority": 1
      },
      {
        "name": "code",
        "workspace": 2,
        "projectScoped": true,
        "wmClass": "Code",
        "command": "~/.config/i3/scripts/launch-code.sh",
        "monitor_priority": 1
      },
      {
        "name": "yazi",
        "workspace": 5,
        "projectScoped": true,
        "wmClass": "ghostty",
        "command": "~/.config/i3/scripts/launch-yazi.sh",
        "monitor_priority": 2
      },
      {
        "name": "lazygit",
        "workspace": 7,
        "projectScoped": true,
        "wmClass": "ghostty",
        "command": "~/.config/i3/scripts/launch-lazygit.sh",
        "monitor_priority": 2
      }
    ]
  },
  "stacks": {
    "name": "Stacks Platform",
    "directory": "/home/vpittamp/stacks",
    "icon": "",
    "applications": [
      {
        "name": "ghostty",
        "workspace": 1,
        "projectScoped": true,
        "wmClass": "ghostty",
        "command": "~/.config/i3/scripts/launch-ghostty.sh",
        "monitor_priority": 1
      },
      {
        "name": "code",
        "workspace": 2,
        "projectScoped": true,
        "wmClass": "Code",
        "command": "~/.config/i3/scripts/launch-code.sh",
        "monitor_priority": 1
      }
    ]
  }
}
```

**Validation Rules**:
- `project-id` MUST be lowercase alphanumeric (no spaces or special characters)
- `directory` MUST be absolute path and exist on filesystem
- `workspace` MUST be 1-9
- `projectScoped` applications MUST have unique (name, wmClass) combinations
- `monitor_priority` MUST be positive integer (1=highest priority)

### 2. Active Project State

**Location**: `~/.config/i3/current-project`

**Purpose**: Tracks the currently active project context for the user session.

**Schema**:
```json
{
  "mode": "string",               // "manual" or "auto" (future)
  "override": boolean,            // User manually set this project
  "project_id": "string",         // References key in projects.json
  "name": "string",               // Cached display name
  "directory": "string",          // Cached project directory
  "icon": "string",               // Cached icon
  "activated_at": "string"        // ISO 8601 timestamp
}
```

**Example**:
```json
{
  "mode": "manual",
  "override": true,
  "project_id": "nixos",
  "name": "NixOS Configuration",
  "directory": "/etc/nixos",
  "icon": "",
  "activated_at": "2025-10-19T14:30:00-04:00"
}
```

**State Transitions**:
- **Empty/Missing** → User has no active project (global mode)
- **Project Set** → User activates project via `project-switcher.sh`
- **Project Cleared** → User clears project via `project-clear.sh`
- **Stale Check** → Projects older than 24 hours treated as inactive

**Lifecycle**:
- Created by `project-set.sh`
- Read by `project-current.sh`, `project-switch-hook.sh`, launcher scripts
- Deleted by `project-clear.sh`
- Persists across i3 restarts (file-based)
- Independent per RDP session (per-user ~/.config)

### 3. Window-Project Association

**Location**: Runtime (derived from i3 window tree query)

**Purpose**: Maps open windows to their associated projects by parsing window properties.

**Derived Structure** (not persisted):
```typescript
interface WindowAssociation {
  containerId: number;           // i3 container ID
  windowId: number;              // X11 window ID
  projectId: string | null;      // Extracted from window title
  wmClass: string;               // Window class
  workspace: number;             // Current workspace number
  title: string;                 // Full window title
}
```

**Example**:
```typescript
{
  containerId: 94576115891776,
  windowId: 65011713,
  projectId: "nixos",              // Extracted from "[PROJECT:nixos]" in title
  wmClass: "Code",
  workspace: 2,
  title: "[PROJECT:nixos] /etc/nixos - Visual Studio Code"
}
```

**Extraction Logic**:
```bash
# Extract project ID from window title
project_id=$(echo "$window_title" | grep -oP '\[PROJECT:\K[a-z]+(?=\])')

# Example matches:
# "[PROJECT:nixos] /etc/nixos - Visual Studio Code" → "nixos"
# "[PROJECT:stacks] ghostty" → "stacks"
# "Firefox" → null (no project association)
```

**Window Matching Algorithm**:
1. Query i3 window tree: `i3-msg -t get_tree`
2. Filter to windows with non-null `window` property
3. Extract `name` (title) and `window_properties.class`
4. Parse project ID from title using regex `\[PROJECT:([a-z]+)\]`
5. Build WindowAssociation objects for project-scoped windows

### 4. Monitor Configuration

**Location**: Runtime (detected via xrandr)

**Purpose**: Tracks connected monitors and their properties for workspace assignment.

**Derived Structure**:
```typescript
interface MonitorConfiguration {
  monitors: MonitorInfo[];
  primary: string;                // Output name of primary monitor
  count: number;                  // Total connected monitors
  detectedAt: string;             // ISO 8601 timestamp
}

interface MonitorInfo {
  output: string;                 // Output name (e.g., "DP-1")
  resolution: string;             // Resolution (e.g., "1920x1080")
  position: string;               // Position (e.g., "+0+0")
  isPrimary: boolean;
}
```

**Example**:
```typescript
{
  monitors: [
    {
      output: "DP-1",
      resolution: "1920x1080",
      position: "+0+0",
      isPrimary: true
    },
    {
      output: "DP-2",
      resolution: "1920x1080",
      position: "+1920+0",
      isPrimary: false
    }
  ],
  primary: "DP-1",
  count: 2,
  detectedAt: "2025-10-19T14:30:00-04:00"
}
```

**Detection Command**:
```bash
xrandr --query | grep ' connected'
# Output:
# DP-1 connected primary 1920x1080+0+0 (...)
# DP-2 connected 1920x1080+1920+0 (...)
```

### 5. Workspace-Monitor Assignment

**Location**: Runtime (applied via i3-msg)

**Purpose**: Maps workspaces to monitors based on priority and monitor count.

**Assignment Table**:

| Monitor Count | Workspace 1 | Workspace 2 | Workspace 3-5 | Workspace 6-9 |
|---------------|-------------|-------------|---------------|---------------|
| 1             | Primary     | Primary     | Primary       | Primary       |
| 2             | Primary     | Primary     | Secondary     | Secondary     |
| 3             | Primary     | Primary     | Secondary     | Tertiary      |

**Runtime Application**:
```bash
# Applied via i3-msg after monitor detection
i3-msg "workspace 1; move workspace to output DP-1"
i3-msg "workspace 2; move workspace to output DP-1"
i3-msg "workspace 3; move workspace to output DP-2"
# etc.
```

**Per-Workspace Priority** (from projects.json):
```json
{
  "applications": [
    {
      "workspace": 1,
      "monitor_priority": 1    // Highest priority → primary monitor
    },
    {
      "workspace": 5,
      "monitor_priority": 2    // Lower priority → secondary monitor
    }
  ]
}
```

Priority determines monitor assignment when multiple monitors available:
- Priority 1: Primary monitor (DP-1)
- Priority 2: Secondary monitor (DP-2 or primary if only 1 monitor)
- Priority 3: Tertiary monitor (DP-3 or fallback to secondary/primary)

## State Flow Diagrams

### Project Activation Flow

```
┌─────────────────────┐
│ User presses Mod+p  │
│ (project-switcher)  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────┐
│ Display rofi menu           │
│ (list projects from         │
│  projects.json)             │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│ User selects project        │
│ (e.g., "nixos")             │
└──────────┬──────────────────┘
           │
           ▼
┌────────────────────────────────────┐
│ project-set.sh                     │
│ 1. Validate project exists         │
│ 2. Write to current-project file   │
│ 3. Detect monitors (xrandr)        │
│ 4. Call project-switch-hook.sh     │
└────────────┬───────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ project-switch-hook.sh                  │
│ 1. Query window tree (i3-msg)          │
│ 2. Parse window titles for project IDs │
│ 3. Move active project windows to WS   │
│ 4. Move inactive project windows to    │
│    scratchpad                           │
│ 5. Apply workspace-monitor assignments │
└─────────────────────────────────────────┘
```

### Application Launch Flow

```
┌───────────────────────┐
│ User presses Mod+c    │
│ (launch VS Code)      │
└──────────┬────────────┘
           │
           ▼
┌────────────────────────────┐
│ launch-code.sh             │
│ 1. Read current-project    │
│ 2. Get project directory   │
└──────────┬─────────────────┘
           │
           ▼
     ┌────┴─────┐
     │ Project? │
     └────┬─────┘
          │
    ┌─────┴─────┐
    │           │
    NO          YES
    │           │
    ▼           ▼
┌─────────┐  ┌──────────────────────────────┐
│ Launch  │  │ Launch with project context: │
│ VS Code │  │ 1. Set window title with     │
│ default │  │    [PROJECT:nixos] prefix    │
│ args    │  │ 2. Open project directory    │
└─────────┘  │ 3. code /etc/nixos           │
             └──────────────────────────────┘
```

### Monitor Hotplug Flow

```
┌─────────────────────────┐
│ Monitor added/removed   │
│ (RandR event or manual) │
└──────────┬──────────────┘
           │
           ▼
┌────────────────────────────┐
│ User presses Mod+Shift+m   │
│ (manual trigger)           │
└──────────┬─────────────────┘
           │
           ▼
┌──────────────────────────────┐
│ detect-monitors.sh           │
│ 1. Query xrandr              │
│ 2. Count connected monitors  │
│ 3. Identify primary          │
└──────────┬───────────────────┘
           │
           ▼
┌────────────────────────────────────┐
│ assign-workspace-monitor.sh        │
│ 1. Read workspace priorities       │
│ 2. Apply assignment algorithm      │
│ 3. Move workspaces to outputs      │
│    via i3-msg                      │
└────────────────────────────────────┘
```

## Data Validation & Integrity

### Project Definition Validation

**Performed by**: `project-set.sh` before activating project

**Checks**:
1. Project ID exists in projects.json
2. Project directory exists and is readable
3. All application commands are executable
4. Workspace numbers are 1-9
5. Monitor priorities are positive integers

**Error Handling**:
- Invalid project ID → Display error via rofi, abort activation
- Missing directory → Display warning, allow activation (directory might be mounted later)
- Invalid workspace → Log warning, default to workspace 1

### Active Project State Validation

**Performed by**: `project-current.sh` on read

**Checks**:
1. File exists and is valid JSON
2. Timestamp is recent (<24 hours)
3. Referenced project still exists in projects.json

**Error Handling**:
- Invalid JSON → Return empty state `{}`
- Stale timestamp → Return empty state, delete file
- Missing project reference → Return empty state, delete file

### Window Association Validation

**Performed by**: `project-switch-hook.sh` during window matching

**Checks**:
1. Window container ID is valid
2. Project ID extracted from title exists in projects.json
3. Window class matches expected application

**Error Handling**:
- Invalid container ID → Skip window (may have been closed)
- Unknown project ID → Log warning, leave window on current workspace
- Class mismatch → Log warning, proceed with title-based match

## Performance Considerations

### Query Optimization

**i3 window tree query**: O(n) where n = total windows
- Typically <100 windows per user session
- Query time: ~10-50ms for typical setups
- Mitigate: Cache window list, only re-query on project switch

**Project definition lookup**: O(1) hash map lookup
- projects.json loaded into memory once
- Subsequent queries are instant

**Monitor detection**: O(m) where m = connected monitors
- Typically 1-3 monitors
- xrandr query time: ~5-20ms

### State File I/O

**Read operations**:
- `project-current.sh`: Called by launchers (~10 times per session)
- File size: <1KB
- Read time: <1ms

**Write operations**:
- `project-set.sh`: Called on project switch (~5 times per day)
- File size: <1KB
- Write time: <1ms

**Optimization**: Use atomic writes (write to temp file, then mv) to prevent corruption.

## Future Extensions

### Potential Enhancements

1. **Project Auto-Detection**:
   - Add `auto_detect_patterns` to project definitions
   - Detect project from current directory in focused terminal
   - Update active project automatically

2. **Window State Persistence**:
   - Save window IDs to state file
   - Restore scratchpad windows on i3 restart
   - Preserve workspace assignments across reboots

3. **Per-Project Workspace Layouts**:
   - Store i3 layout JSON per project
   - Restore window positions automatically
   - Support custom tiling arrangements

4. **Multi-User Project State**:
   - Share project definitions across users
   - Per-user active project state
   - Collaborative project switching

5. **Advanced Monitor Profiles**:
   - Save monitor arrangements as profiles
   - Switch between profiles (home/office/mobile)
   - Per-profile workspace assignments

## Summary

The data model provides:
- **Project Definitions**: Declarative configuration in projects.json
- **Active State**: File-based per-user state
- **Runtime Associations**: Derived from i3 window tree
- **Monitor Configuration**: Detected dynamically via xrandr
- **Workspace Assignments**: Applied programmatically via i3-msg

All state is either declaratively defined (projects.json) or ephemerally derived (window associations, monitor config), with a single mutable state file (current-project) for tracking user's active project context.
