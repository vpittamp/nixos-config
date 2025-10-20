# CLI Interface Contract

**Feature**: Event-Based i3 Project Synchronization
**Contract Type**: Command-Line Interface
**Version**: 1.0.0

## Overview

This contract defines the command-line interface for interacting with the i3 project management system. All commands communicate with the event listener daemon via IPC.

---

## Commands

### 1. `i3-project-switch <project_name>`

Switch to a specific project or global mode.

**Syntax**:
```bash
i3-project-switch <project_name>
i3-project-switch --clear     # Switch to global mode
```

**Aliases**: `pswitch`

**Arguments**:
- `project_name`: Project to activate (must exist in `~/.config/i3/projects/`)
- `--clear`, `-c`: Clear active project (global mode)

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `2`: Daemon not running
- `3`: IPC communication error

**Output** (stdout):
```
Switched to project: nixos
Hidden 3 windows from project: stacks
Shown 5 windows from project: nixos
```

**Output** (stderr on error):
```
Error: Project 'invalid' not found
Available projects: nixos, stacks, personal
```

**Examples**:
```bash
# Switch to nixos project
i3-project-switch nixos

# Switch to stacks project
pswitch stacks

# Clear active project (global mode)
i3-project-switch --clear
pswitch -c
```

---

### 2. `i3-project-current`

Show currently active project.

**Syntax**:
```bash
i3-project-current [--format=<format>]
```

**Aliases**: `pcurrent`

**Options**:
- `--format=text`: Human-readable text (default)
- `--format=json`: JSON output
- `--format=icon`: Only show project icon (for status bars)

**Exit Codes**:
- `0`: Success (project active or global mode)
- `2`: Daemon not running

**Output** (text format):
```
Active project: nixos (NixOS)
Directory: /etc/nixos
Windows: 5
```

**Output** (global mode):
```
No active project (global mode)
```

**Output** (JSON format):
```json
{
  "project_name": "nixos",
  "display_name": "NixOS",
  "icon": "",
  "directory": "/etc/nixos",
  "window_count": 5,
  "activated_at": "2025-10-20T10:30:00Z"
}
```

**Output** (icon format):
```

```

**Examples**:
```bash
# Show current project (text)
i3-project-current

# Get JSON output
i3-project-current --format=json | jq -r '.project_name'

# Get icon for status bar
i3-project-current --format=icon
```

---

### 3. `i3-project-list`

List all configured projects.

**Syntax**:
```bash
i3-project-list [--format=<format>]
```

**Aliases**: `plist`

**Options**:
- `--format=text`: Human-readable table (default)
- `--format=json`: JSON output
- `--format=simple`: Simple list (names only)

**Exit Codes**:
- `0`: Success
- `2`: Daemon not running

**Output** (text format):
```
Projects:
  [*]  nixos     NixOS           /etc/nixos              5 windows
  [ ]   stacks    Stacks          ~/projects/stacks       0 windows
  [ ]   personal  Personal        ~/personal              2 windows

Legend: [*] = active project
```

**Output** (JSON format):
```json
{
  "projects": [
    {
      "name": "nixos",
      "display_name": "NixOS",
      "icon": "",
      "directory": "/etc/nixos",
      "window_count": 5,
      "is_active": true
    },
    {
      "name": "stacks",
      "display_name": "Stacks",
      "icon": "",
      "directory": "/home/user/projects/stacks",
      "window_count": 0,
      "is_active": false
    }
  ]
}
```

**Output** (simple format):
```
nixos
stacks
personal
```

**Examples**:
```bash
# Show all projects
i3-project-list

# Get JSON for scripting
plist --format=json

# Get names for completion
plist --format=simple
```

---

### 4. `i3-project-create`

Create a new project.

**Syntax**:
```bash
i3-project-create --name=<name> --dir=<directory> [options]
```

**Options**:
- `--name=<name>`: Project name (required, alphanumeric + dashes/underscores)
- `--dir=<directory>`: Project directory (required, absolute path)
- `--display-name=<name>`: Human-readable name (optional, defaults to name)
- `--icon=<char>`: Project icon (optional, single Unicode character)

**Exit Codes**:
- `0`: Success
- `1`: Invalid arguments (missing required, invalid format)
- `4`: Project already exists
- `5`: Directory doesn't exist

**Output** (stdout):
```
Created project: nixos
  Display name: NixOS
  Directory: /etc/nixos
  Icon:
  Config file: /home/user/.config/i3/projects/nixos.json
```

**Examples**:
```bash
# Create new project
i3-project-create --name=nixos --dir=/etc/nixos --display-name="NixOS" --icon=""

# Create minimal project
i3-project-create --name=test --dir=/tmp/test
```

---

### 5. `i3-project-edit <project_name>`

Edit project configuration.

**Syntax**:
```bash
i3-project-edit <project_name>
```

**Behavior**: Opens project JSON file in `$EDITOR` (defaults to `vi`).

**Exit Codes**:
- `0`: Success (editor exited normally)
- `1`: Project not found
- `6`: Editor failed

**Output**: None (interactive)

**Examples**:
```bash
# Edit nixos project
i3-project-edit nixos

# Use specific editor
EDITOR=nano i3-project-edit stacks
```

---

### 6. `i3-project-delete <project_name>`

Delete a project.

**Syntax**:
```bash
i3-project-delete <project_name> [--force]
```

**Options**:
- `--force`, `-f`: Skip confirmation prompt

**Exit Codes**:
- `0`: Success
- `1`: Project not found
- `7`: Deletion cancelled by user
- `8`: Active project cannot be deleted

**Output** (stdout):
```
Delete project 'nixos'?
  This will remove the configuration file.
  Project directory (/etc/nixos) will NOT be deleted.

Confirm deletion [y/N]: y
Deleted project: nixos
```

**Output** (force mode):
```
Deleted project: nixos
```

**Examples**:
```bash
# Delete with confirmation
i3-project-delete old-project

# Delete without confirmation
i3-project-delete old-project --force
```

---

### 7. `i3-project-validate [project_name]`

Validate project configuration.

**Syntax**:
```bash
i3-project-validate [project_name]
```

**Arguments**:
- `project_name`: Specific project to validate (optional, validates all if omitted)

**Exit Codes**:
- `0`: All projects valid
- `9`: Validation errors found

**Output** (success):
```
Validating projects...
✓ nixos: Valid
✓ stacks: Valid
✓ personal: Valid

All projects valid (3/3)
```

**Output** (errors):
```
Validating projects...
✓ nixos: Valid
✗ stacks: Directory does not exist: /home/user/projects/invalid
✗ broken: Invalid JSON: Unexpected token at line 5

Validation failed (1/3 valid, 2 errors)
```

**Examples**:
```bash
# Validate all projects
i3-project-validate

# Validate specific project
i3-project-validate nixos
```

---

### 8. `i3-project-daemon-status`

Show daemon status and diagnostics.

**Syntax**:
```bash
i3-project-daemon-status [--format=<format>]
```

**Options**:
- `--format=text`: Human-readable (default)
- `--format=json`: JSON output

**Exit Codes**:
- `0`: Daemon running
- `2`: Daemon not running

**Output** (text format):
```
i3 Project Event Listener Daemon Status

Connection:
  Status: Connected
  i3 socket: /run/user/1000/i3/ipc-socket.12345
  Uptime: 1h 23m 45s

Events:
  Total processed: 1,234
  Errors: 0
  Subscriptions: window, workspace, tick, shutdown

Active Project:
  Name: nixos (NixOS)
  Windows: 5 tracked

Performance:
  Memory usage: 12.3 MB
  Event rate: 2.5 events/sec (avg)
```

**Output** (JSON format):
```json
{
  "status": "connected",
  "connection": {
    "is_connected": true,
    "socket_path": "/run/user/1000/i3/ipc-socket.12345",
    "uptime_seconds": 4985
  },
  "events": {
    "total": 1234,
    "errors": 0,
    "subscriptions": ["window", "workspace", "tick", "shutdown"]
  },
  "active_project": {
    "name": "nixos",
    "window_count": 5
  },
  "performance": {
    "memory_mb": 12.3,
    "event_rate": 2.5
  }
}
```

**Examples**:
```bash
# Show daemon status
i3-project-daemon-status

# Get JSON for monitoring
i3-project-daemon-status --format=json
```

---

### 9. `i3-project-daemon-events [--limit=N]`

Show recent daemon events (diagnostic tool).

**Syntax**:
```bash
i3-project-daemon-events [--limit=N] [--type=<type>]
```

**Options**:
- `--limit=N`: Number of events to show (default: 50, max: 1000)
- `--type=<type>`: Filter by event type (window, workspace, tick, shutdown)

**Exit Codes**:
- `0`: Success
- `2`: Daemon not running

**Output**:
```
Recent Events (last 50):

2025-10-20 10:35:12  window::new       window_id=94557896564  class=Code       ✓
2025-10-20 10:35:11  window::mark      window_id=94557896564  mark=project:nixos  ✓
2025-10-20 10:35:05  workspace::focus  workspace=1            ✓
2025-10-20 10:34:58  tick              payload=project:nixos  ✓
2025-10-20 10:34:55  window::close     window_id=94557895120  ✓

Legend: ✓ = success, ✗ = error
Total: 50 events, 0 errors
```

**Examples**:
```bash
# Show last 50 events
i3-project-daemon-events

# Show last 100 window events
i3-project-daemon-events --limit=100 --type=window

# Monitor events in real-time (with watch)
watch -n 1 'i3-project-daemon-events --limit=10'
```

---

### 10. `i3-project-daemon-reload`

Reload daemon configuration.

**Syntax**:
```bash
i3-project-daemon-reload
```

**Behavior**: Tells daemon to reload project configurations from `~/.config/i3/projects/` without restarting.

**Exit Codes**:
- `0`: Success
- `2`: Daemon not running
- `10`: Reload failed (check daemon logs)

**Output**:
```
Reloading daemon configuration...
Loaded 3 projects
  ✓ nixos
  ✓ stacks
  ✓ personal

Reload complete
```

**Examples**:
```bash
# Reload after editing project configs
i3-project-daemon-reload
```

---

## Shell Integration

### Bash Aliases

Add to `~/.bashrc`:
```bash
alias pswitch='i3-project-switch'
alias pcurrent='i3-project-current'
alias plist='i3-project-list'
```

### Bash Completion

```bash
# /etc/bash_completion.d/i3-project-completion.sh
_i3_project_switch() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local projects=$(i3-project-list --format=simple 2>/dev/null)
    COMPREPLY=($(compgen -W "$projects --clear" -- "$cur"))
}

_i3_project_edit() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local projects=$(i3-project-list --format=simple 2>/dev/null)
    COMPREPLY=($(compgen -W "$projects" -- "$cur"))
}

complete -F _i3_project_switch i3-project-switch pswitch
complete -F _i3_project_edit i3-project-edit i3-project-delete i3-project-validate
```

### Fish Completion

```fish
# ~/.config/fish/completions/i3-project-switch.fish
complete -c i3-project-switch -f -a "(i3-project-list --format=simple 2>/dev/null)"
complete -c i3-project-switch -l clear -d "Clear active project"

complete -c pswitch -f -a "(i3-project-list --format=simple 2>/dev/null)"
complete -c pswitch -l clear -d "Clear active project"
```

---

## Rofi Integration

### Project Switcher (Win+P)

```bash
#!/usr/bin/env bash
# i3-project-rofi-switcher.sh

# Get projects with icons
projects=$(i3-project-current --format=json | jq -r '.project_name // "none"')
all_projects=$(i3-project-list --format=json | jq -r '.projects[] | "\(.icon)  \(.display_name)|\(.name)"')

# Show rofi menu
selected=$(echo "$all_projects" | rofi -dmenu -i -p "Switch Project" -format "s" -selected-row 0)

if [ -n "$selected" ]; then
    project_name=$(echo "$selected" | cut -d'|' -f2)
    i3-project-switch "$project_name"
fi
```

i3 keybinding:
```
bindsym $mod+p exec --no-startup-id /path/to/i3-project-rofi-switcher.sh
```

---

## Environment Variables

### `I3_PROJECT_DAEMON_SOCKET`

Override daemon socket path (for testing or custom deployments).

**Default**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

**Example**:
```bash
I3_PROJECT_DAEMON_SOCKET=/tmp/test-daemon.sock i3-project-current
```

### `I3_PROJECT_CONFIG_DIR`

Override project configuration directory.

**Default**: `~/.config/i3/projects`

**Example**:
```bash
I3_PROJECT_CONFIG_DIR=/etc/i3/projects i3-project-list
```

---

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Daemon not running` | Event listener daemon not started | Start daemon: `systemctl --user start i3-project-event-listener` |
| `Project not found` | Project name doesn't exist | List projects: `i3-project-list` |
| `IPC communication error` | Socket connection failed | Check socket exists: `ls $XDG_RUNTIME_DIR/i3-project-daemon/` |
| `Directory does not exist` | Project directory removed | Update project config or delete project |
| `Active project cannot be deleted` | Trying to delete current project | Switch to another project first |

### Debugging

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# View daemon logs
journalctl --user -u i3-project-event-listener -f

# Test IPC connection
echo '{"jsonrpc":"2.0","id":1,"method":"get_status"}' | nc -U "$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock"

# Check recent events
i3-project-daemon-events --limit=10
```

---

## Implementation Notes

### CLI Tool Structure

All CLI commands are thin wrappers around daemon IPC calls:

```bash
#!/usr/bin/env bash
# i3-project-current

SOCKET="${I3_PROJECT_DAEMON_SOCKET:-$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock}"

if [ ! -S "$SOCKET" ]; then
    echo "Error: Daemon not running" >&2
    exit 2
fi

request='{"jsonrpc":"2.0","id":1,"method":"get_active_project"}'
response=$(echo "$request" | nc -U "$SOCKET" -W 1)

if [ $? -ne 0 ]; then
    echo "Error: IPC communication failed" >&2
    exit 3
fi

project=$(echo "$response" | jq -r '.result.project_name // "none"')

if [ "$project" = "none" ]; then
    echo "No active project (global mode)"
else
    echo "Active project: $project"
fi
```

### NixOS Deployment

```nix
# home-modules/desktop/i3-project-manager.nix
{ pkgs, ... }:

let
  i3-project-cli = pkgs.writeShellScriptBin "i3-project-switch" ''
    # CLI implementation
  '';
in
{
  home.packages = [ i3-project-cli ];

  # Shell aliases
  programs.bash.shellAliases = {
    pswitch = "i3-project-switch";
    pcurrent = "i3-project-current";
    plist = "i3-project-list";
  };
}
```

---

## Testing

### Manual Testing

```bash
# Test project switching
i3-project-switch nixos
i3-project-current
i3-project-list

# Test project creation
i3-project-create --name=test --dir=/tmp/test
i3-project-validate test
i3-project-delete test --force

# Test daemon status
i3-project-daemon-status
i3-project-daemon-events --limit=10
```

### Automated Testing

```bash
#!/usr/bin/env bash
# test-cli.sh

set -e

echo "Testing CLI interface..."

# Test current project
output=$(i3-project-current --format=json)
echo "✓ i3-project-current"

# Test project list
output=$(i3-project-list --format=json)
project_count=$(echo "$output" | jq '.projects | length')
echo "✓ i3-project-list ($project_count projects)"

# Test project switch
i3-project-switch nixos
active=$(i3-project-current --format=json | jq -r '.project_name')
[ "$active" = "nixos" ] || { echo "✗ Project switch failed"; exit 1; }
echo "✓ i3-project-switch"

# Test daemon status
i3-project-daemon-status --format=json >/dev/null
echo "✓ i3-project-daemon-status"

echo "All tests passed!"
```

---

## Versioning

**Current Version**: 1.0.0

**Compatibility**: CLI commands are stable. Exit codes and output formats (JSON) are guaranteed backward compatible within major versions.

**Breaking Changes**: Will increment major version (2.0.0) if:
- Exit code meanings change
- JSON output structure changes (fields removed or renamed)
- Required arguments added to existing commands
