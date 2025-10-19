# CLI Interface Contract

**Feature**: i3-Native Dynamic Project Workspace Management
**Date**: 2025-10-19

## Overview

This document defines the command-line interface contracts for all project management commands. Each command must conform to standard Unix conventions for exit codes, output format, and error handling.

## Commands

### i3-project-create

**Purpose**: Create a new project configuration file

**Syntax**:
```bash
i3-project-create --name NAME --dir DIRECTORY [--icon ICON] [--display-name DISPLAY_NAME]
```

**Arguments**:
- `--name NAME` (required): Project identifier (alphanumeric, dash, underscore only)
- `--dir DIRECTORY` (required): Absolute path to project directory
- `--icon ICON` (optional): Unicode icon/emoji for display
- `--display-name DISPLAY_NAME` (optional): Human-readable name (defaults to NAME)

**Output**:
```
Created project 'nixos' at ~/.config/i3/projects/nixos.json
```

**Exit Codes**:
- `0`: Success
- `1`: Invalid arguments (missing required, invalid characters in name)
- `2`: Project already exists
- `3`: Directory doesn't exist or not accessible
- `4`: Failed to write JSON file

**Errors**:
```
Error: Project 'nixos' already exists at ~/.config/i3/projects/nixos.json
Use --force to overwrite
```

**Example**:
```bash
i3-project-create --name nixos --dir /etc/nixos --icon  --display-name "NixOS Configuration"
```

---

### i3-project-delete

**Purpose**: Delete a project configuration file

**Syntax**:
```bash
i3-project-delete NAME [--force]
```

**Arguments**:
- `NAME` (required): Project name to delete
- `--force` (optional): Skip confirmation prompt

**Output**:
```
Deleted project 'nixos' from ~/.config/i3/projects/nixos.json
```

**Exit Codes**:
- `0`: Success
- `1`: Project doesn't exist
- `2`: User cancelled (without --force)
- `3`: Failed to delete file

**Errors**:
```
Error: Project 'nixos' not found
```

**Example**:
```bash
i3-project-delete nixos --force
```

---

### i3-project-list

**Purpose**: List all available projects

**Syntax**:
```bash
i3-project-list [--format json|text]
```

**Arguments**:
- `--format` (optional): Output format (default: text)

**Output (text)**:
```
nixos       /etc/nixos                  NixOS Configuration
stacks      ~/code/stacks              Stacks Project
api         ~/code/api-gateway         API Gateway
```

**Output (json)**:
```json
[
  {
    "name": "nixos",
    "directory": "/etc/nixos",
    "displayName": "NixOS Configuration",
    "icon": ""
  },
  {
    "name": "stacks",
    "directory": "~/code/stacks",
    "displayName": "Stacks Project",
    "icon": ""
  }
]
```

**Exit Codes**:
- `0`: Success (even if no projects found)
- `1`: Invalid format argument

**Example**:
```bash
i3-project-list --format json | jq '.[] | select(.name == "nixos")'
```

---

### i3-project-switch

**Purpose**: Activate a project (hide other project windows, show this project's windows)

**Syntax**:
```bash
i3-project-switch NAME [--no-restore]
```

**Arguments**:
- `NAME` (required): Project name to activate
- `--no-restore` (optional): Don't restore workspace layouts or launch commands

**Output**:
```
Switched to project 'nixos'
Restored workspace layouts: 1, 2
Launched 2 applications
```

**Exit Codes**:
- `0`: Success
- `1`: Project doesn't exist
- `2`: i3 IPC error
- `3`: Project JSON parse error

**Errors**:
```
Error: Project 'nixos' not found at ~/.config/i3/projects/nixos.json
```

**Example**:
```bash
i3-project-switch nixos
```

**Side Effects**:
- Writes project name to `~/.config/i3/active-project`
- Moves windows with other project marks to scratchpad
- Restores windows with this project's mark from scratchpad
- Sends i3 tick event `project:NAME`
- Applies workspace output assignments
- Loads workspace layouts if present
- Executes launch commands if present

---

### i3-project-clear

**Purpose**: Deactivate current project (return to global mode)

**Syntax**:
```bash
i3-project-clear
```

**Arguments**: None

**Output**:
```
Cleared active project
```

**Exit Codes**:
- `0`: Success (even if no project was active)
- `1`: i3 IPC error

**Example**:
```bash
i3-project-clear
```

**Side Effects**:
- Clears `~/.config/i3/active-project` file (makes it empty)
- Shows all windows from scratchpad
- Sends i3 tick event `project:none`

---

### i3-project-current

**Purpose**: Display currently active project

**Syntax**:
```bash
i3-project-current [--format json|text]
```

**Arguments**:
- `--format` (optional): Output format (default: text)

**Output (text)**:
```
nixos
```

or empty output if no project active

**Output (json)**:
```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "displayName": "NixOS Configuration",
  "icon": ""
}
```

or `{}` if no project active

**Exit Codes**:
- `0`: Success (even if no project active)
- `1`: Active project file references non-existent project

**Example**:
```bash
PROJECT=$(i3-project-current)
if [[ -n "$PROJECT" ]]; then
  echo "Current project: $PROJECT"
fi
```

---

### i3-project-mark-window

**Purpose**: Manually mark a window as belonging to current project

**Syntax**:
```bash
i3-project-mark-window [WINDOW_ID]
```

**Arguments**:
- `WINDOW_ID` (optional): X11 window ID (if omitted, uses focused window)

**Output**:
```
Marked window 0x1a00003 with project:nixos
```

**Exit Codes**:
- `0`: Success
- `1`: No active project
- `2`: Window ID invalid or not found
- `3`: i3 IPC error

**Errors**:
```
Error: No active project. Activate a project first with i3-project-switch
```

**Example**:
```bash
# Mark currently focused window
i3-project-mark-window

# Mark specific window
i3-project-mark-window 0x1a00003
```

---

### i3-project-edit

**Purpose**: Open project JSON file in $EDITOR

**Syntax**:
```bash
i3-project-edit NAME
```

**Arguments**:
- `NAME` (required): Project name to edit

**Output**: None (opens editor)

**Exit Codes**:
- `0`: Success (editor closed)
- `1`: Project doesn't exist
- `2`: $EDITOR not set

**Example**:
```bash
i3-project-edit nixos
```

---

### i3-project-validate

**Purpose**: Validate project JSON file against schema

**Syntax**:
```bash
i3-project-validate NAME
```

**Arguments**:
- `NAME` (required): Project name to validate

**Output**:
```
✓ Project 'nixos' is valid
```

or

```
✗ Project 'nixos' has errors:
  - project.directory is not an absolute path: 'relative/path'
  - workspaces.2.layout: invalid i3 layout JSON
  - workspaceOutputs.15: workspace number out of range (1-10)
```

**Exit Codes**:
- `0`: Valid
- `1`: Invalid (errors printed to stderr)
- `2`: Project doesn't exist

**Example**:
```bash
if i3-project-validate nixos; then
  i3-project-switch nixos
fi
```

---

### i3-project-migrate

**Purpose**: Migrate static NixOS project definitions to runtime JSON files

**Syntax**:
```bash
i3-project-migrate [--source FILE] [--dry-run]
```

**Arguments**:
- `--source FILE` (optional): Nix file containing project definitions (default: detect automatically)
- `--dry-run` (optional): Print what would be created without writing files

**Output**:
```
Migrating projects from home-modules/desktop/i3-projects.nix
Created nixos.json -> ~/.config/i3/projects/nixos.json
Created stacks.json -> ~/.config/i3/projects/stacks.json
Migrated 2 projects
```

**Exit Codes**:
- `0`: Success
- `1`: Source file not found or invalid
- `2`: Failed to parse Nix expressions

**Example**:
```bash
i3-project-migrate --dry-run
```

---

## Launcher Wrapper Scripts

### i3-project-launch-code

**Purpose**: Launch VS Code in project context

**Syntax**:
```bash
i3-project-launch-code [DIRECTORY]
```

**Arguments**:
- `DIRECTORY` (optional): Directory to open (default: active project directory)

**Behavior**:
1. Check active project from `~/.config/i3/active-project`
2. If project active and Code is scoped: mark window with `project:NAME`
3. Open directory (project directory or argument)
4. Move window to configured workspace (default: 2)

**Example**:
```bash
# Open current project directory in VS Code
i3-project-launch-code
```

---

### i3-project-launch-terminal

**Purpose**: Launch terminal in project context

**Syntax**:
```bash
i3-project-launch-terminal [COMMAND]
```

**Arguments**:
- `COMMAND` (optional): Command to execute in terminal

**Behavior**:
1. Check active project
2. If project active: mark window, set working directory to project dir
3. Launch ghostty with sesh session if available
4. Move to workspace 1

**Example**:
```bash
# Launch terminal with sesh session
i3-project-launch-terminal
```

---

### i3-project-launch-lazygit

**Purpose**: Launch lazygit in project directory

**Syntax**:
```bash
i3-project-launch-lazygit
```

**Behavior**:
1. Check active project
2. Launch lazygit in project directory
3. Mark window if scoped
4. Move to workspace 1

---

### i3-project-launch-yazi

**Purpose**: Launch yazi file manager in project directory

**Syntax**:
```bash
i3-project-launch-yazi
```

**Behavior**:
1. Check active project
2. Launch yazi in project directory
3. Mark window if scoped
4. Move to workspace 1

---

## Rofi Integration

### i3-project-rofi-switcher

**Purpose**: Display project switcher menu in rofi

**Syntax**:
```bash
i3-project-rofi-switcher
```

**Behavior**:
1. List all projects with icons and display names
2. Highlight currently active project
3. On selection: call `i3-project-switch NAME`
4. On escape: exit without action

**Rofi Menu Format**:
```
 NixOS Configuration
 Stacks Project
 API Gateway
 Personal Projects
```

---

## Exit Code Standards

All commands follow standard Unix exit code conventions:

- `0`: Success
- `1`: General error (invalid arguments, file not found, etc.)
- `2`: Misuse of command (wrong number of arguments, invalid format)
- `3`: File I/O error (permission denied, write failed)
- `4`: External dependency error (i3 IPC unavailable, jq not found)

## Output Format Standards

**Text Output**:
- Human-readable messages
- Use stdout for normal output
- Use stderr for errors and warnings
- Color codes allowed (use `tput` for portability)

**JSON Output**:
- Valid JSON always (even for errors)
- Use compact format (no pretty-printing unless --pretty flag)
- Errors in JSON format:
```json
{
  "error": "Project not found",
  "code": 1,
  "details": "No file at ~/.config/i3/projects/nixos.json"
}
```

## Error Handling Standards

1. **Validate inputs early**: Check arguments before side effects
2. **Atomic operations**: Use temp files + rename for file writes
3. **Graceful degradation**: Continue with reduced functionality when possible
4. **Clear error messages**: Include what went wrong and how to fix it
5. **Log to file**: Write errors to `~/.config/i3/project-manager.log`

## Logging

**Log Location**: `~/.config/i3/project-manager.log`

**Log Format**:
```
[2025-10-19 14:32:15] INFO: Switching to project 'nixos'
[2025-10-19 14:32:15] DEBUG: Loaded project JSON from ~/.config/i3/projects/nixos.json
[2025-10-19 14:32:15] INFO: Moved 3 windows to scratchpad with mark 'project:stacks'
[2025-10-19 14:32:15] INFO: Restored 2 windows from scratchpad with mark 'project:nixos'
[2025-10-19 14:32:16] ERROR: Failed to apply workspace layout: jq parse error
```

**Log Levels**:
- `DEBUG`: Verbose details (disabled by default)
- `INFO`: Normal operations
- `WARN`: Non-fatal issues
- `ERROR`: Operation failures

**Enable Debug Logging**:
```bash
export I3_PROJECT_DEBUG=1
i3-project-switch nixos
```

## Dependencies

All commands must check for required dependencies on first run:

- `i3-msg`: i3 IPC communication
- `jq`: JSON parsing
- `rofi`: Project switcher UI
- `xdotool`: Window ID retrieval (optional, for mark assignment)

**Missing Dependency Handling**:
```
Error: Required command 'jq' not found
Install with: nix-shell -p jq
```
