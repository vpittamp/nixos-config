# CLI Commands API Contract

**Feature**: 035-now-that-we | **Date**: 2025-10-25
**Status**: Design Phase | **Input**: data-model.md, research.md

## Overview

This document defines the complete command-line interface for the `i3pm` Deno CLI tool. All commands follow standard CLI conventions with `--help` and `--version` flags, support `--json` output for scripting, and provide clear error messages.

**Implementation**: Deno 1.40+ with `@std/cli/parse-args` for argument parsing, TypeScript with strict types, compiled to standalone executable.

---

## Command Structure

```
i3pm <command> <subcommand> [arguments] [flags]
```

**Global Flags**:
- `--help`, `-h`: Show command help
- `--version`, `-v`: Show i3pm version
- `--json`: Output in JSON format (where applicable)
- `--verbose`: Enable verbose logging

---

## Command Group: `apps`

**Purpose**: Query and display application registry information.

### `i3pm apps list`

**Description**: List all applications from the registry with their metadata.

**Usage**:
```bash
i3pm apps list [--tags TAG1,TAG2] [--scope scoped|global] [--workspace N] [--json]
```

**Arguments**: None

**Flags**:
- `--tags <tags>`: Filter by comma-separated tags (OR logic)
- `--scope <scope>`: Filter by scope (`scoped` or `global`)
- `--workspace <n>`: Filter by preferred workspace number (1-9)
- `--json`: Output as JSON array
- `--format <format>`: Output format (`table`, `simple`, `json`), default: `table`

**Output (Table Format)**:
```
NAME          DISPLAY NAME        WORKSPACE  SCOPE    TAGS
vscode        Visual Studio Code  1          scoped   development, editor
firefox       Firefox             2          global   browser, web
ghostty       Ghostty Terminal    -          scoped   terminal, development (multi-instance)
youtube-pwa   YouTube             7          global   media, video, pwa
```

**Output (JSON Format)**:
```json
[
  {
    "name": "vscode",
    "display_name": "Visual Studio Code",
    "command": "/nix/store/.../bin/code",
    "parameters": ["$PROJECT_DIR"],
    "expected_class": "Code",
    "preferred_workspace": 1,
    "scope": "scoped",
    "fallback_behavior": "skip",
    "multi_instance": false,
    "tags": ["development", "editor"]
  },
  ...
]
```

**Exit Codes**:
- `0`: Success
- `1`: Registry file not found
- `2`: Registry JSON parse error
- `3`: Invalid filter arguments

**Example Usage**:
```bash
# List all applications
i3pm apps list

# List all development tools
i3pm apps list --tags development

# List all scoped applications
i3pm apps list --scope scoped

# List applications on workspace 1
i3pm apps list --workspace 1

# Output as JSON for scripting
i3pm apps list --json | jq '.[] | select(.scope == "scoped") | .name'
```

---

### `i3pm apps show <name>`

**Description**: Show detailed information about a specific application.

**Usage**:
```bash
i3pm apps show <name> [--json]
```

**Arguments**:
- `<name>`: Application name (from registry)

**Flags**:
- `--json`: Output as JSON object

**Output (Human-Readable)**:
```
Application: vscode
Display Name: Visual Studio Code
Command: /nix/store/.../bin/code
Parameters: $PROJECT_DIR
Expected Class: Code
Preferred Workspace: 1
Scope: scoped
Fallback Behavior: skip
Multi-Instance: false
Tags: development, editor
```

**Output (JSON)**:
```json
{
  "name": "vscode",
  "display_name": "Visual Studio Code",
  "command": "/nix/store/.../bin/code",
  "parameters": ["$PROJECT_DIR"],
  "expected_class": "Code",
  "preferred_workspace": 1,
  "scope": "scoped",
  "fallback_behavior": "skip",
  "multi_instance": false,
  "tags": ["development", "editor"]
}
```

**Exit Codes**:
- `0`: Success
- `1`: Application not found in registry
- `2`: Registry file error

---

## Command Group: `project`

**Purpose**: Manage project configurations (create, read, update, delete, switch).

### `i3pm project list`

**Description**: List all configured projects.

**Usage**:
```bash
i3pm project list [--json]
```

**Output (Table)**:
```
NAME     DISPLAY NAME           DIRECTORY        TAGS                        LAYOUT
nixos    NixOS Configuration    /etc/nixos       development, editor, ...    nixos-coding
stacks   Stacks Development     ~/projects/...   development, browser, ...   stacks-fullstack
personal Personal Tasks         ~/documents      productivity, ...           (none)
```

**Output (JSON)**:
```json
[
  {
    "name": "nixos",
    "display_name": "NixOS Configuration",
    "directory": "/etc/nixos",
    "application_tags": ["development", "editor", "terminal", "git"],
    "saved_layout": "nixos-coding",
    "created_at": "2025-10-25T14:30:00-04:00",
    "updated_at": "2025-10-25T16:45:00-04:00"
  },
  ...
]
```

**Exit Codes**:
- `0`: Success
- `1`: Projects directory not found or unreadable

---

### `i3pm project show [name]`

**Description**: Show detailed information about a project. If no name provided, shows current active project.

**Usage**:
```bash
i3pm project show [name] [--json]
```

**Arguments**:
- `[name]`: Project name (optional, defaults to active project)

**Flags**:
- `--json`: Output as JSON object

**Output (Human-Readable)**:
```
Project: nixos
Display Name: NixOS Configuration
Directory: /etc/nixos
Application Tags: development, editor, terminal, git
Saved Layout: nixos-coding
Status: ACTIVE (switched 2h 15m ago)
Created: 2025-10-25 14:30:00
Updated: 2025-10-25 16:45:00

Available Applications (filtered by tags):
- vscode (Visual Studio Code)
- neovim (Neovim Editor)
- ghostty (Ghostty Terminal)
- lazygit (Lazygit TUI)
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: No active project (when name not provided)
- `3`: Project file parse error

---

### `i3pm project current`

**Description**: Show currently active project (alias for `i3pm project show` with no arguments).

**Usage**:
```bash
i3pm project current [--json]
```

**Output**:
```
Active Project: nixos
Activated: 2025-10-25 14:30:00 (2h 15m ago)
Directory: /etc/nixos
```

**Exit Codes**:
- `0`: Success (project active)
- `1`: No active project

---

### `i3pm project create <name>`

**Description**: Create a new project configuration interactively or with flags.

**Usage**:
```bash
i3pm project create <name> [--display-name NAME] [--directory DIR] [--tags TAG1,TAG2] [--icon ICON] [--non-interactive]
```

**Arguments**:
- `<name>`: Project name (kebab-case, unique)

**Flags**:
- `--display-name <name>`: Human-readable name (required in non-interactive mode)
- `--directory <dir>`: Absolute path to project root (required in non-interactive mode)
- `--tags <tags>`: Comma-separated application tags (required in non-interactive mode)
- `--icon <icon>`: Optional icon identifier
- `--non-interactive`: Skip interactive prompts, use only flags

**Interactive Prompts** (if flags not provided):
```
Creating project: nixos

Display name: NixOS Configuration
Project directory: /etc/nixos
Application tags (comma-separated): development,editor,terminal,git
Icon (optional): nix-snowflake

Summary:
  Name: nixos
  Display Name: NixOS Configuration
  Directory: /etc/nixos
  Tags: development, editor, terminal, git
  Icon: nix-snowflake

Create project? [Y/n]: y
```

**Validation**:
- Project name must be unique (no existing project with same name)
- Directory must exist and be absolute path
- All tags must exist in at least one registry application
- Name must be kebab-case, 3-64 characters

**Output**:
```
✓ Project 'nixos' created successfully
  Location: ~/.config/i3/projects/nixos.json

To switch to this project:
  i3pm project switch nixos
```

**Exit Codes**:
- `0`: Success
- `1`: Project name already exists
- `2`: Directory does not exist or is not absolute
- `3`: Invalid tags (not found in registry)
- `4`: Validation error (invalid name format)

---

### `i3pm project update <name>`

**Description**: Update an existing project configuration.

**Usage**:
```bash
i3pm project update <name> [--display-name NAME] [--directory DIR] [--tags TAG1,TAG2] [--icon ICON]
```

**Arguments**:
- `<name>`: Project name

**Flags**:
- `--display-name <name>`: New display name
- `--directory <dir>`: New project directory
- `--tags <tags>`: New application tags (replaces existing)
- `--icon <icon>`: New icon identifier

**Note**: Only provided flags are updated; other fields remain unchanged.

**Output**:
```
✓ Project 'nixos' updated successfully
  Updated: display_name, application_tags
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: Validation error
- `3`: Directory does not exist (if --directory provided)

---

### `i3pm project delete <name>`

**Description**: Delete a project configuration (with confirmation prompt).

**Usage**:
```bash
i3pm project delete <name> [--force]
```

**Arguments**:
- `<name>`: Project name

**Flags**:
- `--force`: Skip confirmation prompt

**Interactive Prompt**:
```
Delete project 'nixos'?
  Location: ~/.config/i3/projects/nixos.json
  Saved Layout: nixos-coding (will also be deleted)

This action cannot be undone. Continue? [y/N]: y
```

**Output**:
```
✓ Project 'nixos' deleted
✓ Layout 'nixos-coding' deleted
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: User cancelled deletion (non-force mode)

---

### `i3pm project switch <name>`

**Description**: Switch to a project (make it the active project).

**Usage**:
```bash
i3pm project switch <name>
```

**Arguments**:
- `<name>`: Project name

**Behavior**:
1. Validate project exists
2. Update `~/.config/i3/active-project.json`
3. Send tick event to daemon (if running) to trigger window visibility updates
4. Update i3bar status (via daemon event subscription)

**Output**:
```
✓ Switched to project 'nixos'
  Directory: /etc/nixos
  Filtered Apps: 12 applications available (tags: development, editor, terminal, git)

To launch applications:
  - Press Win+D for Walker launcher (filtered by project tags)
  - Or use: i3pm apps list --tags development
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: Daemon not running (warning, but still updates active-project.json)

---

### `i3pm project clear`

**Description**: Clear active project (return to global mode with no project context).

**Usage**:
```bash
i3pm project clear
```

**Behavior**:
1. Set `active-project.json` to `{"project_name": null, "activated_at": null}`
2. Send tick event to daemon
3. All scoped application windows become hidden (via daemon marks)

**Output**:
```
✓ Cleared active project
  All applications now available (global mode)
```

**Exit Codes**:
- `0`: Success
- `1`: Daemon not running (warning)

---

## Command Group: `layout`

**Purpose**: Save and restore window layouts for projects.

### `i3pm layout save <project-name> [layout-name]`

**Description**: Capture current window layout and save it for a project.

**Usage**:
```bash
i3pm layout save <project-name> [layout-name] [--overwrite]
```

**Arguments**:
- `<project-name>`: Project to save layout for
- `[layout-name]`: Optional layout name (defaults to project name)

**Flags**:
- `--overwrite`: Overwrite existing layout without confirmation

**Behavior**:
1. Query i3 IPC for all windows (via JSON-RPC to daemon or `i3-msg -t get_tree`)
2. Match windows to registry applications by `expected_class`
3. Capture window geometry (workspace, x, y, width, height, floating, focused)
4. Validate all windows match registry applications (warn if unmatched windows found)
5. Save to `~/.config/i3/layouts/<layout-name>.json`
6. Update project's `saved_layout` field

**Output**:
```
Capturing layout for project 'nixos'...

Windows captured:
  ✓ vscode on workspace 1 (1920x1080)
  ✓ ghostty on workspace 3 (1920x540) [1/2]
  ✓ ghostty on workspace 3 (1920x540) [2/2]
  ✓ firefox on workspace 2 (1920x1080)

⚠ Unmatched windows (will not be restored):
  - Unknown window 'rofi' (class: Rofi) on workspace 5

✓ Layout 'nixos-coding' saved successfully
  Location: ~/.config/i3/layouts/nixos-coding.json
  Windows: 4 (3 applications)

To restore this layout:
  i3pm layout restore nixos
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: No windows to capture
- `3`: Layout already exists (without --overwrite)
- `4`: i3 IPC query failed

---

### `i3pm layout restore <project-name>`

**Description**: Restore saved layout for a project (closes existing project windows first).

**Usage**:
```bash
i3pm layout restore <project-name> [--dry-run]
```

**Arguments**:
- `<project-name>`: Project whose layout to restore

**Flags**:
- `--dry-run`: Show what would be restored without actually launching applications

**Behavior**:
1. Load project and layout configurations
2. Validate all layout applications exist in current registry
3. **Close existing project-scoped windows** (FR-012)
4. Switch to project (set as active)
5. Launch each application via registry protocol with project context
6. Wait for window to appear (timeout: 5 seconds per app)
7. Move window to saved workspace and apply geometry
8. Focus the window marked as focused in layout

**Output (Normal Mode)**:
```
Restoring layout 'nixos-coding' for project 'nixos'...

⚠ Closing existing project windows: 2 windows closed

Launching applications:
  [1/4] ✓ vscode launched (workspace 1)
  [2/4] ✓ ghostty launched (workspace 3) [instance 1]
  [3/4] ✓ ghostty launched (workspace 3) [instance 2]
  [4/4] ✓ firefox launched (workspace 2)

⚠ Some windows may take a moment to reach their final positions...

✓ Layout restored successfully
  4 windows launched, 4 positioned, 1 focused
```

**Output (Dry-Run Mode)**:
```
Would restore layout 'nixos-coding' for project 'nixos':

Applications to launch:
  1. vscode → workspace 1 (1920x1080, tiled, FOCUSED)
  2. ghostty → workspace 3 (1920x540, tiled)
  3. ghostty → workspace 3 (1920x540, tiled)
  4. firefox → workspace 2 (1920x1080, tiled)

Total: 4 windows (3 applications)

Run without --dry-run to restore layout.
```

**Error Handling**:
- If app not in registry: Skip with warning, continue with others
- If app fails to launch: Log error, continue with others
- If window never appears: Timeout after 5 seconds, continue
- If positioning fails: Log warning, window remains where launched

**Exit Codes**:
- `0`: Success (all windows restored)
- `1`: Partial success (some windows failed, warnings logged)
- `2`: Project not found
- `3`: Project has no saved layout
- `4`: Layout file not found or invalid

---

### `i3pm layout delete <project-name>`

**Description**: Delete a saved layout for a project.

**Usage**:
```bash
i3pm layout delete <project-name> [--force]
```

**Arguments**:
- `<project-name>`: Project whose layout to delete

**Flags**:
- `--force`: Skip confirmation prompt

**Output**:
```
✓ Layout 'nixos-coding' deleted
  Project 'nixos' no longer has a saved layout
```

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: Project has no saved layout
- `3`: User cancelled (non-force mode)

---

## Command Group: `windows`

**Purpose**: Query and monitor current window state (extends existing functionality).

### `i3pm windows [--tree|--table|--live|--json]`

**Description**: Display current window state with multiple visualization modes (from Feature 025).

**Usage**:
```bash
i3pm windows [--tree] [--table] [--live] [--json] [--show-hidden]
```

**Flags**:
- `--tree`: Tree view (default)
- `--table`: Table view
- `--live`: Interactive TUI with real-time updates
- `--json`: JSON output
- `--show-hidden`: Show hidden project-scoped windows

**Note**: This command already exists from Feature 025 and may need extension to show registry app names and project tags.

---

## Command: `i3pm daemon`

**Purpose**: Interact with the i3 project management daemon.

### `i3pm daemon status`

**Description**: Show daemon status and connectivity (from Feature 015).

**Usage**:
```bash
i3pm daemon status [--json]
```

**Output**:
```
Daemon Status: RUNNING
  PID: 12345
  Uptime: 2h 15m 30s
  Socket: /run/user/1000/i3-project-manager.sock
  Active Project: nixos (since 2h 15m ago)
  Events Processed: 1,247
  Tracked Windows: 8
```

**Exit Codes**:
- `0`: Daemon running
- `1`: Daemon not running

---

### `i3pm daemon events [--follow] [--limit N] [--type TYPE]`

**Description**: Show recent daemon events for debugging (from Feature 015).

**Usage**:
```bash
i3pm daemon events [--follow] [--limit N] [--type TYPE]
```

**Flags**:
- `--follow`: Stream events in real-time (like `tail -f`)
- `--limit <n>`: Show last N events (default: 20)
- `--type <type>`: Filter by event type (window, workspace, tick, etc.)

---

## Error Handling

All commands follow consistent error handling patterns:

### Standard Error Messages

```
Error: Project 'invalid-name' not found
  Available projects: nixos, stacks, personal
  Run 'i3pm project list' to see all projects

Error: Application 'invalid-app' not found in registry
  Run 'i3pm apps list' to see all applications

Error: Invalid tag 'nonexistent-tag'
  This tag is not used by any application in the registry
  Run 'i3pm apps list' to see available tags

Error: Daemon not running
  The i3 project management daemon is required for this operation
  Start with: systemctl --user start i3-project-manager

Error: Directory '/invalid/path' does not exist
  Project directory must be an absolute path to an existing directory
```

### Exit Code Summary

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Resource not found (project, app, file) |
| `2` | Invalid input (validation error, bad format) |
| `3` | Operation failed (i3 IPC error, file write error) |
| `4` | User cancelled operation (non-force delete) |
| `5` | Daemon not running (where required) |

---

## JSON Output Format

All commands with `--json` flag output structured JSON for scripting:

```json
{
  "status": "success" | "error" | "warning",
  "data": { ... },              // Command-specific payload
  "errors": [ ... ],             // Array of error messages (if status=error)
  "warnings": [ ... ],           // Array of warnings (optional)
  "metadata": {
    "command": "i3pm project show nixos",
    "timestamp": "2025-10-25T16:45:00-04:00",
    "version": "1.0.0"
  }
}
```

**Example - Success**:
```json
{
  "status": "success",
  "data": {
    "project": {
      "name": "nixos",
      "display_name": "NixOS Configuration",
      "directory": "/etc/nixos",
      "application_tags": ["development", "editor"],
      "saved_layout": "nixos-coding"
    }
  },
  "metadata": {
    "command": "i3pm project show nixos",
    "timestamp": "2025-10-25T16:45:00-04:00",
    "version": "1.0.0"
  }
}
```

**Example - Error**:
```json
{
  "status": "error",
  "errors": [
    "Project 'invalid-name' not found"
  ],
  "metadata": {
    "command": "i3pm project show invalid-name",
    "timestamp": "2025-10-25T16:45:00-04:00",
    "version": "1.0.0"
  }
}
```

---

## Implementation Notes

1. **Argument Parsing**: Use `@std/cli/parse-args` from Deno standard library (Principle XIII)
2. **Validation**: Validate all inputs before executing operations, provide clear error messages
3. **Idempotency**: Commands like `create`, `update`, `switch` should be idempotent where possible
4. **Atomic Operations**: File writes should be atomic (write to temp file, then rename)
5. **Error Recovery**: Graceful degradation when daemon not running (warn, but continue if possible)
6. **Help Text**: All commands and subcommands must provide `--help` output with examples

---

## Testing Strategy

- **Unit Tests**: Command parsing, validation logic, JSON output formatting
- **Integration Tests**: File I/O, daemon communication (mocked), i3-msg shell-out (mocked)
- **Scenario Tests**: End-to-end workflows (create project → switch → save layout → restore)
- **Error Tests**: Invalid inputs, missing files, daemon down, registry errors
