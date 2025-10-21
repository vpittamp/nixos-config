# CLI Interface Contract: i3pm

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 1 Design
**Data Model**: [../data-model.md](../data-model.md)

## Overview

This document defines the complete command-line interface for `i3pm` (i3 Project Manager), including all subcommands, arguments, output formats, and error handling patterns.

## Entry Point

```bash
i3pm [SUBCOMMAND] [OPTIONS] [ARGS]
i3pm                           # No args → Launch TUI
i3pm --help                    # Show help
i3pm --version                 # Show version
```

**Mode Detection**:
- **TUI Mode**: No subcommand (launches interactive Textual interface)
- **CLI Mode**: Subcommand specified (executes and exits)

---

## Command Categories

### 1. Project Management (CRUD)
- `create` - Create new project
- `edit` - Edit project configuration
- `delete` - Delete project
- `list` - List all projects
- `show` - Show project details
- `validate` - Validate project configuration

### 2. Project Switching
- `switch` - Switch to project
- `current` - Show current active project
- `clear` - Clear active project (return to global mode)

### 3. Layout Management
- `save-layout` - Save current window layout
- `restore-layout` - Restore saved layout
- `list-layouts` - List saved layouts
- `delete-layout` - Delete saved layout
- `export-layout` - Export layout to portable format
- `import-layout` - Import layout from file

### 4. Monitoring
- `monitor` - Launch TUI monitor dashboard
- `status` - Show daemon status
- `events` - Show recent daemon events
- `windows` - List tracked windows

### 5. Configuration
- `config` - Show configuration paths
- `app-classes` - Manage global app classifications
- `completions` - Generate shell completions

---

## Detailed Command Specifications

### Project Management Commands

#### `i3pm create`

**Purpose**: Create a new project interactively or from arguments.

**Syntax**:
```bash
i3pm create [OPTIONS]
```

**Options**:
```
--name NAME               Project name (required)
--directory DIR           Project directory (required)
--display-name NAME       Display name (defaults to name)
--icon EMOJI              Icon emoji (optional)
--scoped-classes CLASS... Application classes to scope (space-separated)
--interactive, -i         Interactive wizard mode
--from-template TEMPLATE  Create from template
--json                    Output JSON
```

**Examples**:
```bash
# Interactive mode (wizard)
i3pm create --interactive

# From arguments
i3pm create --name nixos --directory /etc/nixos --scoped-classes Ghostty Code

# From template
i3pm create --name myapp --from-template python-dev

# JSON output
i3pm create --name test --directory /tmp/test --json
```

**Output (Human-Readable)**:
```
✓ Created project: nixos
  Directory: /etc/nixos
  Scoped Apps: Ghostty, Code
  Config: ~/.config/i3/projects/nixos.json
```

**Output (JSON)**:
```json
{
  "success": true,
  "project": {
    "name": "nixos",
    "directory": "/etc/nixos",
    "display_name": "nixos",
    "scoped_classes": ["Ghostty", "Code"],
    "created_at": "2025-10-20T14:30:00Z"
  },
  "config_file": "/home/user/.config/i3/projects/nixos.json"
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project already exists
- `2` - Invalid arguments (directory doesn't exist, etc.)
- `3` - Configuration error

---

#### `i3pm edit`

**Purpose**: Edit an existing project configuration.

**Syntax**:
```bash
i3pm edit PROJECT [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name to edit
```

**Options**:
```
--directory DIR           Update directory
--display-name NAME       Update display name
--icon EMOJI              Update icon
--add-class CLASS         Add scoped class
--remove-class CLASS      Remove scoped class
--set-classes CLASS...    Replace scoped classes
--interactive, -i         Interactive TUI editor
--json                    Output JSON
```

**Examples**:
```bash
# Interactive TUI editor
i3pm edit nixos --interactive

# Add scoped class
i3pm edit nixos --add-class firefox

# Update multiple fields
i3pm edit nixos --display-name "NixOS Config" --icon ❄️

# JSON output
i3pm edit nixos --add-class Code --json
```

**Output (Human-Readable)**:
```
✓ Updated project: nixos
  Added scoped class: firefox
  Config: ~/.config/i3/projects/nixos.json
```

**Output (JSON)**:
```json
{
  "success": true,
  "project": {
    "name": "nixos",
    "scoped_classes": ["Ghostty", "Code", "firefox"],
    "modified_at": "2025-10-20T14:35:00Z"
  }
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project not found
- `2` - Invalid arguments

---

#### `i3pm delete`

**Purpose**: Delete a project and optionally its layouts.

**Syntax**:
```bash
i3pm delete PROJECT [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name to delete
```

**Options**:
```
--force, -f               Skip confirmation
--keep-layouts            Keep saved layouts
--json                    Output JSON
```

**Examples**:
```bash
# With confirmation
i3pm delete test

# Force delete
i3pm delete test --force

# Delete project but keep layouts
i3pm delete test --force --keep-layouts
```

**Output (Human-Readable)**:
```
⚠ Delete project 'test'? This will also delete 2 saved layouts. [y/N]: y
✓ Deleted project: test
  Deleted layouts: default, debugging
```

**Output (JSON)**:
```json
{
  "success": true,
  "deleted_project": "test",
  "deleted_layouts": ["default", "debugging"]
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project not found
- `2` - User cancelled

---

#### `i3pm list`

**Purpose**: List all projects with optional filtering and sorting.

**Syntax**:
```bash
i3pm list [OPTIONS]
```

**Options**:
```
--sort FIELD              Sort by: name, modified, directory (default: modified)
--reverse                 Reverse sort order
--filter TEXT             Filter by name/directory
--long, -l                Long format (more details)
--json                    Output JSON
```

**Examples**:
```bash
# Default (sort by modified, descending)
i3pm list

# Sort by name
i3pm list --sort name

# Filter by name
i3pm list --filter nix

# Long format
i3pm list --long

# JSON output
i3pm list --json
```

**Output (Default)**:
```
NAME      DIRECTORY        APPS  LAYOUTS  MODIFIED
nixos     /etc/nixos       2     3        2h ago
stacks    ~/code/stacks    3     1        1d ago
personal  ~/personal       1     0        5d ago
```

**Output (Long)**:
```
Project: nixos
  Directory: /etc/nixos
  Display Name: NixOS Configuration
  Icon: ❄️
  Scoped Apps: Ghostty, Code
  Saved Layouts: default, debugging, testing
  Created: 2025-10-15 10:00:00
  Modified: 2025-10-20 14:30:00

Project: stacks
  ...
```

**Output (JSON)**:
```json
{
  "projects": [
    {
      "name": "nixos",
      "directory": "/etc/nixos",
      "display_name": "NixOS Configuration",
      "icon": "❄️",
      "scoped_classes": ["Ghostty", "Code"],
      "saved_layouts": ["default", "debugging", "testing"],
      "created_at": "2025-10-15T10:00:00Z",
      "modified_at": "2025-10-20T14:30:00Z"
    }
  ],
  "total": 3
}
```

**Exit Codes**:
- `0` - Success (even if no projects found)

---

#### `i3pm show`

**Purpose**: Show detailed information about a specific project.

**Syntax**:
```bash
i3pm show PROJECT [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
```

**Options**:
```
--json                    Output JSON
--config                  Show raw JSON config file
```

**Examples**:
```bash
# Human-readable
i3pm show nixos

# JSON
i3pm show nixos --json

# Raw config file
i3pm show nixos --config
```

**Output (Human-Readable)**:
```
Project: nixos
  Directory: /etc/nixos
  Display Name: NixOS Configuration
  Icon: ❄️

Scoped Applications:
  • Ghostty
  • Code

Workspace Preferences:
  WS 1 → primary
  WS 2 → secondary

Auto-Launch:
  1. ghostty (workspace 1)
  2. code /etc/nixos (workspace 2)

Saved Layouts:
  • default (2025-10-20, 5 windows)
  • debugging (2025-10-18, 8 windows)

Metadata:
  Created: 2025-10-15 10:00:00
  Modified: 2025-10-20 14:30:00
  Config: ~/.config/i3/projects/nixos.json
```

**Output (JSON)**: (same as data-model.md Project.to_json())

**Exit Codes**:
- `0` - Success
- `1` - Project not found

---

#### `i3pm validate`

**Purpose**: Validate project configuration against schema.

**Syntax**:
```bash
i3pm validate [PROJECT] [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name (if omitted, validate all)
```

**Options**:
```
--fix                     Attempt to fix validation errors
--json                    Output JSON
```

**Examples**:
```bash
# Validate single project
i3pm validate nixos

# Validate all projects
i3pm validate

# Fix validation errors
i3pm validate nixos --fix
```

**Output (Human-Readable)**:
```
✓ nixos: Valid
⚠ stacks: 2 warnings
  - Directory /home/user/code/stacks does not exist
  - Scoped class 'ObsoleteApp' not found in app-classes.json
✗ personal: 1 error
  - Invalid workspace number: 11 (must be 1-10)

Summary: 1 valid, 1 warnings, 1 errors
```

**Output (JSON)**:
```json
{
  "valid": ["nixos"],
  "warnings": {
    "stacks": [
      "Directory /home/user/code/stacks does not exist",
      "Scoped class 'ObsoleteApp' not found"
    ]
  },
  "errors": {
    "personal": [
      "Invalid workspace number: 11 (must be 1-10)"
    ]
  }
}
```

**Exit Codes**:
- `0` - All valid
- `1` - Warnings found
- `2` - Errors found

---

### Project Switching Commands

#### `i3pm switch`

**Purpose**: Switch to a project (activates window scoping).

**Syntax**:
```bash
i3pm switch PROJECT [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
```

**Options**:
```
--no-launch               Don't run auto-launch apps
--workspace WS            Switch to specific workspace after switch
--json                    Output JSON
```

**Examples**:
```bash
# Switch to project
i3pm switch nixos

# Switch without auto-launch
i3pm switch nixos --no-launch

# Switch and go to workspace 2
i3pm switch nixos --workspace 2
```

**Output (Human-Readable)**:
```
✓ Switched to project: nixos
  Directory: /etc/nixos
  Launched: ghostty, code
  Workspace: 1
```

**Output (JSON)**:
```json
{
  "success": true,
  "project": "nixos",
  "launched_apps": ["ghostty", "code"],
  "current_workspace": 1
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project not found
- `2` - Daemon not running

---

#### `i3pm current`

**Purpose**: Show currently active project.

**Syntax**:
```bash
i3pm current [OPTIONS]
```

**Options**:
```
--json                    Output JSON
--quiet, -q               Output project name only (for scripting)
```

**Examples**:
```bash
# Human-readable
i3pm current

# Quiet (for scripts)
i3pm current --quiet

# JSON
i3pm current --json
```

**Output (Human-Readable)**:
```
Active Project: nixos
  Directory: /etc/nixos
  Tracked Windows: 5
```

**Output (Quiet)**:
```
nixos
```

**Output (JSON)**:
```json
{
  "active_project": "nixos",
  "directory": "/etc/nixos",
  "tracked_windows": 5
}
```

**Exit Codes**:
- `0` - Project active
- `1` - No active project (global mode)
- `2` - Daemon not running

---

#### `i3pm clear`

**Purpose**: Clear active project (return to global mode).

**Syntax**:
```bash
i3pm clear [OPTIONS]
```

**Options**:
```
--json                    Output JSON
```

**Examples**:
```bash
# Clear active project
i3pm clear
```

**Output (Human-Readable)**:
```
✓ Cleared active project (was: nixos)
  Mode: Global
```

**Output (JSON)**:
```json
{
  "success": true,
  "previous_project": "nixos",
  "mode": "global"
}
```

**Exit Codes**:
- `0` - Success
- `1` - No project was active

---

### Layout Management Commands

#### `i3pm save-layout`

**Purpose**: Save current window layout for a project.

**Syntax**:
```bash
i3pm save-layout PROJECT LAYOUT_NAME [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
LAYOUT_NAME               Name for the layout
```

**Options**:
```
--overwrite               Overwrite existing layout
--workspaces WS...        Only save specific workspaces (default: all)
--json                    Output JSON
```

**Examples**:
```bash
# Save all workspaces
i3pm save-layout nixos default

# Save specific workspaces
i3pm save-layout nixos debugging --workspaces 1 2

# Overwrite existing
i3pm save-layout nixos default --overwrite
```

**Output (Human-Readable)**:
```
✓ Saved layout: nixos/default
  Workspaces: 1, 2
  Windows: 5
  Config: ~/.config/i3/layouts/nixos/default.json
```

**Output (JSON)**:
```json
{
  "success": true,
  "project": "nixos",
  "layout_name": "default",
  "workspaces": [1, 2],
  "total_windows": 5,
  "layout_file": "/home/user/.config/i3/layouts/nixos/default.json"
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project not found
- `2` - Layout already exists (use --overwrite)
- `3` - No windows to save

---

#### `i3pm restore-layout`

**Purpose**: Restore a saved layout.

**Syntax**:
```bash
i3pm restore-layout PROJECT LAYOUT_NAME [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
LAYOUT_NAME               Layout name
```

**Options**:
```
--close-existing          Close existing project windows before restore
--timeout SECONDS         Launch timeout (default: 5.0)
--json                    Output JSON
```

**Examples**:
```bash
# Restore layout
i3pm restore-layout nixos default

# Close existing windows first
i3pm restore-layout nixos debugging --close-existing

# Custom timeout
i3pm restore-layout nixos default --timeout 10
```

**Output (Human-Readable)**:
```
✓ Restoring layout: nixos/default
  Launching 5 windows...
  ✓ ghostty (workspace 1)
  ✓ code (workspace 2)
  ✓ firefox (workspace 2)
✓ Layout restored (3/5 windows launched)
  Failed: 2 (timeout)
```

**Output (JSON)**:
```json
{
  "success": true,
  "project": "nixos",
  "layout_name": "default",
  "launched": 3,
  "failed": 2,
  "errors": ["Window 'ObsoleteApp' timed out after 5.0s"]
}
```

**Exit Codes**:
- `0` - Success (all windows launched)
- `1` - Partial success (some windows failed)
- `2` - Layout not found
- `3` - Daemon not running

---

#### `i3pm list-layouts`

**Purpose**: List saved layouts for a project.

**Syntax**:
```bash
i3pm list-layouts PROJECT [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
```

**Options**:
```
--long, -l                Show layout details
--json                    Output JSON
```

**Examples**:
```bash
# List layouts
i3pm list-layouts nixos

# Long format
i3pm list-layouts nixos --long
```

**Output (Default)**:
```
LAYOUT      WINDOWS  WORKSPACES  SAVED
default     5        1, 2        2025-10-20 14:30
debugging   8        1, 2, 3     2025-10-18 10:15
```

**Output (Long)**:
```
Layout: default
  Windows: 5
  Workspaces: 1 (2 windows), 2 (3 windows)
  Monitor Config: dual
  Saved: 2025-10-20 14:30:00
  File: ~/.config/i3/layouts/nixos/default.json

Layout: debugging
  ...
```

**Output (JSON)**:
```json
{
  "project": "nixos",
  "layouts": [
    {
      "name": "default",
      "total_windows": 5,
      "workspaces": [1, 2],
      "monitor_config": "dual",
      "saved_at": "2025-10-20T14:30:00Z"
    }
  ]
}
```

**Exit Codes**:
- `0` - Success
- `1` - Project not found

---

#### `i3pm delete-layout`

**Purpose**: Delete a saved layout.

**Syntax**:
```bash
i3pm delete-layout PROJECT LAYOUT_NAME [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
LAYOUT_NAME               Layout name
```

**Options**:
```
--force, -f               Skip confirmation
--json                    Output JSON
```

**Examples**:
```bash
# With confirmation
i3pm delete-layout nixos old-layout

# Force delete
i3pm delete-layout nixos old-layout --force
```

**Output (Human-Readable)**:
```
⚠ Delete layout 'nixos/old-layout'? [y/N]: y
✓ Deleted layout: nixos/old-layout
```

**Exit Codes**:
- `0` - Success
- `1` - Layout not found
- `2` - User cancelled

---

#### `i3pm export-layout`

**Purpose**: Export layout to portable JSON format.

**Syntax**:
```bash
i3pm export-layout PROJECT LAYOUT_NAME [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
LAYOUT_NAME               Layout name
```

**Options**:
```
--output FILE             Output file (default: stdout)
--format FORMAT           Format: json, yaml (default: json)
```

**Examples**:
```bash
# Export to stdout
i3pm export-layout nixos default

# Export to file
i3pm export-layout nixos default --output ~/layouts/nixos-default.json

# Export as YAML
i3pm export-layout nixos default --format yaml --output layout.yaml
```

**Output**: (writes to file or stdout)

**Exit Codes**:
- `0` - Success
- `1` - Layout not found
- `2` - Write error

---

#### `i3pm import-layout`

**Purpose**: Import layout from portable JSON/YAML format.

**Syntax**:
```bash
i3pm import-layout PROJECT LAYOUT_NAME FILE [OPTIONS]
```

**Arguments**:
```
PROJECT                   Project name
LAYOUT_NAME               Name for imported layout
FILE                      Input file (or '-' for stdin)
```

**Options**:
```
--overwrite               Overwrite existing layout
--validate-only           Only validate, don't import
--json                    Output JSON
```

**Examples**:
```bash
# Import from file
i3pm import-layout nixos imported ~/layout.json

# Import from stdin
cat layout.json | i3pm import-layout nixos imported -

# Validate only
i3pm import-layout nixos test layout.json --validate-only
```

**Output (Human-Readable)**:
```
✓ Imported layout: nixos/imported
  Windows: 5
  Workspaces: 1, 2
  Config: ~/.config/i3/layouts/nixos/imported.json
```

**Exit Codes**:
- `0` - Success
- `1` - Invalid layout format
- `2` - Project not found

---

### Monitoring Commands

#### `i3pm monitor`

**Purpose**: Launch TUI monitoring dashboard.

**Syntax**:
```bash
i3pm monitor [MODE] [OPTIONS]
```

**Arguments**:
```
MODE                      Display mode: live, events, history, tree (default: live)
```

**Options**:
```
--refresh SECONDS         Refresh interval (default: 1.0)
```

**Examples**:
```bash
# Default (live mode)
i3pm monitor

# Event stream
i3pm monitor events

# History view
i3pm monitor history

# i3 tree inspector
i3pm monitor tree
```

**Output**: (launches TUI, see tui-screens.md)

**Exit Codes**:
- `0` - Normal exit
- `1` - Daemon not running

---

#### `i3pm status`

**Purpose**: Show daemon status and diagnostics.

**Syntax**:
```bash
i3pm status [OPTIONS]
```

**Options**:
```
--json                    Output JSON
```

**Examples**:
```bash
# Human-readable
i3pm status

# JSON
i3pm status --json
```

**Output (Human-Readable)**:
```
Daemon Status: Running
  Uptime: 2h 34m
  PID: 12345
  Socket: ~/.cache/i3-project/daemon.sock

Active Project: nixos
  Directory: /etc/nixos
  Tracked Windows: 5

Statistics:
  Total Windows: 12
  Total Events: 1,234
  Event Rate: 2.3/s
```

**Output (JSON)**:
```json
{
  "daemon": {
    "status": "running",
    "uptime_seconds": 9240,
    "pid": 12345,
    "socket": "/home/user/.cache/i3-project/daemon.sock"
  },
  "active_project": {
    "name": "nixos",
    "directory": "/etc/nixos",
    "tracked_windows": 5
  },
  "statistics": {
    "total_windows": 12,
    "total_events": 1234,
    "event_rate_per_second": 2.3
  }
}
```

**Exit Codes**:
- `0` - Daemon running
- `1` - Daemon not running

---

#### `i3pm events`

**Purpose**: Show recent daemon events.

**Syntax**:
```bash
i3pm events [OPTIONS]
```

**Options**:
```
--limit N                 Show last N events (default: 20)
--type TYPE               Filter by event type: window, workspace, tick, output
--follow, -f              Follow events (like tail -f)
--json                    Output JSON
```

**Examples**:
```bash
# Last 20 events
i3pm events

# Last 50 events
i3pm events --limit 50

# Filter by type
i3pm events --type window

# Follow (live stream)
i3pm events --follow
```

**Output (Human-Readable)**:
```
2025-10-20 14:30:15  window::new      Ghostty (#12345) marked: project:nixos
2025-10-20 14:30:10  workspace::focus WS 1 focused
2025-10-20 14:30:05  tick             Project switch: nixos
2025-10-20 14:29:58  window::close    Code (#12344)
```

**Output (JSON)**:
```json
{
  "events": [
    {
      "timestamp": "2025-10-20T14:30:15Z",
      "type": "window::new",
      "details": {
        "window_id": 12345,
        "window_class": "Ghostty",
        "mark": "project:nixos"
      }
    }
  ],
  "total": 4
}
```

**Exit Codes**:
- `0` - Success
- `1` - Daemon not running

---

#### `i3pm windows`

**Purpose**: List tracked windows.

**Syntax**:
```bash
i3pm windows [OPTIONS]
```

**Options**:
```
--project PROJECT         Filter by project
--workspace WS            Filter by workspace
--long, -l                Show detailed info
--json                    Output JSON
```

**Examples**:
```bash
# All tracked windows
i3pm windows

# Filter by project
i3pm windows --project nixos

# Long format
i3pm windows --long
```

**Output (Default)**:
```
ID      CLASS     WORKSPACE  PROJECT  TITLE
12345   Ghostty   1          nixos    nvim flake.nix
12346   Code      2          nixos    /etc/nixos - VSCode
12347   firefox   3          (global) Firefox
```

**Output (Long)**:
```
Window: 12345
  Class: Ghostty
  Title: nvim flake.nix
  Workspace: 1
  Project: nixos
  Marks: project:nixos
  Geometry: 1920x1080+0+0
```

**Output (JSON)**:
```json
{
  "windows": [
    {
      "id": 12345,
      "class": "Ghostty",
      "title": "nvim flake.nix",
      "workspace": 1,
      "project": "nixos",
      "marks": ["project:nixos"],
      "geometry": {"width": 1920, "height": 1080, "x": 0, "y": 0}
    }
  ],
  "total": 3
}
```

**Exit Codes**:
- `0` - Success
- `1` - Daemon not running

---

### Configuration Commands

#### `i3pm config`

**Purpose**: Show configuration paths and information.

**Syntax**:
```bash
i3pm config [OPTIONS]
```

**Options**:
```
--json                    Output JSON
```

**Examples**:
```bash
i3pm config
```

**Output (Human-Readable)**:
```
Configuration Paths:
  Projects: ~/.config/i3/projects/
  Layouts: ~/.config/i3/layouts/
  App Classes: ~/.config/i3/app-classes.json
  Daemon Socket: ~/.cache/i3-project/daemon.sock

Statistics:
  Total Projects: 3
  Total Layouts: 7
  Config Version: 1.0
```

**Output (JSON)**:
```json
{
  "paths": {
    "projects": "/home/user/.config/i3/projects",
    "layouts": "/home/user/.config/i3/layouts",
    "app_classes": "/home/user/.config/i3/app-classes.json",
    "daemon_socket": "/home/user/.cache/i3-project/daemon.sock"
  },
  "statistics": {
    "total_projects": 3,
    "total_layouts": 7,
    "config_version": "1.0"
  }
}
```

**Exit Codes**:
- `0` - Success

---

#### `i3pm app-classes`

**Purpose**: Manage global application classifications.

**Syntax**:
```bash
i3pm app-classes [SUBCOMMAND] [OPTIONS]
```

**Subcommands**:
```
list                      List all classifications
add-scoped CLASS          Add to scoped classes
add-global CLASS          Add to global classes
remove CLASS              Remove from classifications
show CLASS                Show classification for a class
```

**Examples**:
```bash
# List all
i3pm app-classes list

# Add scoped class
i3pm app-classes add-scoped neovide

# Add global class
i3pm app-classes add-global vlc

# Show classification
i3pm app-classes show Ghostty
```

**Output (list)**:
```
Scoped Classes:
  • Ghostty
  • Code
  • neovide

Global Classes:
  • firefox
  • Google-chrome
  • mpv
  • vlc

Class Patterns:
  • pwa-* → global
  • *terminal → scoped
  • *editor → scoped
```

**Exit Codes**:
- `0` - Success
- `1` - Class not found

---

#### `i3pm completions`

**Purpose**: Generate shell completions.

**Syntax**:
```bash
i3pm completions SHELL [OPTIONS]
```

**Arguments**:
```
SHELL                     Shell: bash, zsh, fish
```

**Options**:
```
--output FILE             Output file (default: stdout)
```

**Examples**:
```bash
# Generate bash completions
i3pm completions bash

# Install to completion directory
i3pm completions bash --output ~/.bash_completion.d/i3pm

# Generate zsh completions
i3pm completions zsh --output ~/.zsh/completions/_i3pm
```

**Output**: (completion script written to stdout or file)

**Exit Codes**:
- `0` - Success
- `1` - Unsupported shell

---

## Global Options

**All commands support**:
```
--help, -h                Show help for command
--version, -v             Show version
--verbose                 Verbose output
--quiet, -q               Suppress non-essential output
--json                    Output JSON (where applicable)
```

---

## Error Handling

### Exit Code Conventions

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error (not found, validation failed, etc.) |
| `2` | Invalid arguments |
| `3` | Configuration error |
| `4` | Daemon not running |
| `10` | User cancelled (interactive prompts) |

### Error Output Format

**Human-Readable** (stderr):
```
Error: Project 'invalid' not found
Available projects: nixos, stacks, personal

Run 'i3pm create --help' to create a new project.
```

**JSON** (stdout):
```json
{
  "success": false,
  "error": {
    "code": 1,
    "message": "Project 'invalid' not found",
    "suggestions": ["nixos", "stacks", "personal"]
  }
}
```

---

## Shell Integration

### Aliases (suggested)

```bash
alias pswitch='i3pm switch'
alias pcurrent='i3pm current'
alias pclear='i3pm clear'
alias plist='i3pm list'
alias pedit='i3pm edit'
```

### Completion Integration

```bash
# Bash (~/.bashrc)
eval "$(register-python-argcomplete i3pm)"

# Zsh (~/.zshrc)
autoload -U bashcompinit
bashcompinit
eval "$(register-python-argcomplete i3pm)"

# Fish (~/.config/fish/config.fish)
register-python-argcomplete --shell fish i3pm | source
```

---

## Summary

**Total Commands**: 30+ subcommands across 5 categories
**Output Formats**: Human-readable (Rich formatted), JSON, quiet (script-friendly)
**Shell Completion**: argcomplete with dynamic project/layout name completion
**Error Handling**: Consistent exit codes, helpful error messages, JSON error format

**Next Steps**:
1. Create TUI screens contract
2. Create daemon IPC contract
3. Implement CLI commands in `cli/commands.py`
