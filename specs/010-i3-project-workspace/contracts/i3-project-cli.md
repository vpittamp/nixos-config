# CLI Contract: i3-project

**Version**: 1.0
**Date**: 2025-10-17

## Overview

`i3-project` is the main CLI tool for managing i3 project workspaces. It provides commands for activating, listing, closing, and managing project environments.

---

## Command: i3-project activate

Activate a project by launching all its applications in configured workspaces.

###  Syntax

```bash
i3-project activate <project-name> [OPTIONS]
i3-project a <project-name>  # Short alias
```

### Arguments

- `<project-name>` (required): Name of the project to activate (as defined in config)

### Options

- `--dir <path>`, `-d <path>`: Override working directory for all applications
- `--workspace <number>`, `-w <number>`: Override primary workspace number
- `--dry-run`: Show what would be done without executing
- `--verbose`, `-v`: Show detailed activation progress

### Behavior

1. Load project configuration from `~/.config/i3-projects/projects.json`
2. Validate project exists and is enabled
3. For each workspace in project:
   - Switch to workspace
   - Load layout if specified
   - Launch applications in order with configured delays
   - Track PIDs for project state
4. Focus primary workspace
5. Write project state to `/tmp/i3-projects/<project-name>.state`

### Exit Codes

- `0`: Success - project activated
- `1`: Project not found
- `2`: Project disabled
- `3`: Application launch failed
- `4`: i3 communication error

### Output Examples

**Success**:
```
Activating project 'api-backend'...
  Workspace 1: Launching 2 applications...
    ✓ alacritty (PID 12345)
    ✓ code (PID 12346)
  Workspace 2: Launching 1 application...
    ✓ firefox (PID 12347)
✓ Project 'api-backend' activated (3 applications across 2 workspaces)
```

**Error - Project Not Found**:
```
Error: Project 'unknown' not found
Available projects: api-backend, docs-site, ml-research
Run 'i3-project list' to see all projects
```

**Dry Run**:
```
[DRY RUN] Would activate project 'api-backend':
  Workspace 1:
    - Launch: /nix/store/.../bin/alacritty --directory=/home/user/projects/api-backend
    - Launch: /nix/store/.../bin/code /home/user/projects/api-backend
  Workspace 2:
    - Launch: /nix/store/.../bin/firefox --new-window http://localhost:3000
  Primary workspace: 1
```

---

## Command: i3-project list

List all configured projects with their status.

### Syntax

```bash
i3-project list [OPTIONS]
i3-project ls  # Short alias
```

### Options

- `--active`, `-a`: Show only currently active projects
- `--enabled`, `-e`: Show only enabled projects
- `--json`: Output in JSON format
- `--verbose`, `-v`: Show detailed project information

### Output Examples

**Default**:
```
Available Projects:
  ● api-backend          API Backend Development (active)
    └─ 2 workspaces, 3 applications
  ○ docs-site            Documentation Site
    └─ 1 workspace, 2 applications
  ○ ml-research          Machine Learning Research
    └─ 3 workspaces, 5 applications

Legend: ● = active, ○ = inactive
Run 'i3-project activate <name>' to activate a project
```

**Verbose**:
```
● api-backend - API Backend Development
  Status: Active (activated 2025-10-17 14:30:00)
  Primary Workspace: 1
  Working Directory: /home/user/projects/api-backend
  Workspaces:
    1 (DP-1): alacritty, code
    2 (DP-2): firefox
  Running Applications: 3 (PIDs: 12345, 12346, 12347)
```

**JSON**:
```json
{
  "projects": [
    {
      "name": "api-backend",
      "displayName": "API Backend Development",
      "enabled": true,
      "active": true,
      "activatedAt": "2025-10-17T14:30:00Z",
      "primaryWorkspace": "1",
      "workspaces": ["1", "2"],
      "applicationCount": 3,
      "runningPids": [12345, 12346, 12347]
    }
  ]
}
```

---

## Command: i3-project close

Close a project by terminating all its applications.

### Syntax

```bash
i3-project close <project-name> [OPTIONS]
i3-project c <project-name>  # Short alias
```

### Arguments

- `<project-name>` (required): Name of the project to close

### Options

- `--force`, `-f`: Force kill (SIGKILL) if graceful termination fails
- `--timeout <seconds>`: Wait time for graceful termination (default: 5)
- `--keep-workspaces`: Don't remove empty workspaces after closing

### Behavior

1. Load project state from `/tmp/i3-projects/<project-name>.state`
2. For each running application:
   - Send SIGTERM to PID
   - Wait up to timeout seconds
   - If still running and `--force`: send SIGKILL
3. Remove project state file
4. Optionally remove empty workspaces

### Exit Codes

- `0`: Success - all applications terminated
- `1`: Project not active
- `2`: Some applications failed to terminate
- `3`: Invalid timeout value

### Output Examples

**Success**:
```
Closing project 'api-backend'...
  ✓ Terminated alacritty (PID 12345)
  ✓ Terminated code (PID 12346)
  ✓ Terminated firefox (PID 12347)
✓ Project 'api-backend' closed (3 applications terminated)
```

**Force Kill Required**:
```
Closing project 'api-backend'...
  ✓ Terminated alacritty (PID 12345)
  ⚠ code (PID 12346) did not respond to SIGTERM
  ! Force killing code (PID 12346)
  ✓ Terminated firefox (PID 12347)
✓ Project 'api-backend' closed (3 applications terminated, 1 forced)
```

---

## Command: i3-project status

Show status of a specific project or all projects.

### Syntax

```bash
i3-project status [project-name]
i3-project st [project-name]  # Short alias
```

### Arguments

- `[project-name]` (optional): Specific project to check (default: all active)

### Options

- `--json`: Output in JSON format

### Output Examples

**Single Project**:
```
Project: api-backend
Status: Active
Activated: 2025-10-17 14:30:00 (15 minutes ago)
Primary Workspace: 1
Working Directory: /home/user/projects/api-backend

Workspaces:
  1 (DP-1, focused): 2 applications
    ● alacritty (PID 12345, 0.1% CPU, 12MB RAM)
    ● code (PID 12346, 5.2% CPU, 245MB RAM)
  2 (DP-2): 1 application
    ● firefox (PID 12347, 2.1% CPU, 512MB RAM)

Total: 3 applications, 769MB RAM
```

**All Active Projects**:
```
Active Projects: 2

api-backend (active 15m ago)
  └─ 3 applications across 2 workspaces

docs-site (active 3h ago)
  └─ 2 applications across 1 workspace
```

---

## Command: i3-project switch

Quickly switch focus between active projects.

### Syntax

```bash
i3-project switch <project-name>
i3-project sw <project-name>  # Short alias
```

### Arguments

- `<project-name>` (required): Project to switch to

### Options

- `--activate-if-needed`: Activate project if not already active

### Behavior

1. Check if project is active
2. If active: Focus primary workspace
3. If not active and `--activate-if-needed`: Activate project
4. If not active without flag: Error

### Exit Codes

- `0`: Success - switched to project
- `1`: Project not active
- `2`: Project not found

### Output Examples

```
Switched to project 'api-backend' (workspace 1)
```

---

## Command: i3-project reload

Reload project configurations from NixOS home-manager.

### Syntax

```bash
i3-project reload
```

### Behavior

1. Re-read `~/.config/i3-projects/projects.json`
2. Validate configurations
3. Update internal state

### Exit Codes

- `0`: Success - configuration reloaded
- `1`: Configuration file not found
- `2`: Invalid configuration

### Output Examples

```
Reloading project configurations...
✓ Loaded 3 projects
✓ Configuration reloaded successfully
```

---

## Command: i3-project help

Show help information.

### Syntax

```bash
i3-project help [command]
i3-project --help
i3-project -h
```

### Arguments

- `[command]` (optional): Show help for specific command

### Output Examples

**General Help**:
```
i3-project - i3 Project Workspace Management

Usage: i3-project <command> [options]

Commands:
  activate, a <name>   Activate a project
  list, ls             List all projects
  close, c <name>      Close a project
  status, st [name]    Show project status
  switch, sw <name>    Switch to a project
  reload               Reload configurations
  help [command]       Show help

Options:
  --help, -h           Show this help message
  --version, -v        Show version information

Examples:
  i3-project activate api-backend
  i3-project list --active
  i3-project close api-backend --force
  i3-project status

For more information: man i3-project
```

---

## Environment Variables

- `I3_PROJECTS_CONFIG`: Override config file location (default: `~/.config/i3-projects/projects.json`)
- `I3_PROJECTS_STATE_DIR`: Override state directory (default: `/tmp/i3-projects`)
- `I3_PROJECTS_VERBOSE`: Enable verbose output (default: `0`)

---

## Files

- `~/.config/i3-projects/projects.json`: Project configurations (generated by Nix)
- `/tmp/i3-projects/<name>.state`: Runtime state for active projects
- `~/.config/i3/projects.conf`: i3 configuration snippet (generated by Nix)

---

## Exit Code Summary

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Not found / Not active |
| 2 | Configuration error |
| 3 | Execution error |
| 4 | Communication error |

---

## Integration Notes

### With rofi

```bash
# Project launcher with rofi
i3-project list --json | jq -r '.projects[].name' | rofi -dmenu -p "Project" | xargs i3-project activate
```

### With i3 keybindings

```bash
# In i3 config
bindsym $mod+p exec --no-startup-id i3-project-menu  # Custom rofi launcher
bindsym $mod+Shift+p exec --no-startup-id i3-project list --active | rofi -dmenu
```

---

**CLI Contract Version**: 1.0
**Last Updated**: 2025-10-17
