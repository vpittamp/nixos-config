# CLI Commands Contract: Window Visibility Management

**Feature**: 037-given-our-top | **Date**: 2025-10-25 | **Tool**: i3pm

## Overview

This contract defines new CLI commands for managing window visibility and inspecting hidden windows during project switches.

**Binary**: `i3pm` (existing tool, extended functionality)

---

## New Commands

### i3pm windows hidden

Display all hidden windows grouped by project.

**Synopsis**:
```bash
i3pm windows hidden [OPTIONS]
```

**Options**:
```
--project=<name>     Filter to specific project only
--format=<format>    Output format: table, tree, json (default: table)
--workspace=<num>    Filter to windows from specific workspace
--app=<name>         Filter to specific application
```

**Output** (table format - default):
```
Hidden Windows (8 total)

[NixOS] (5 windows)
  vscode       i3-project.nix - Visual Studio Code         → WS 2
  terminal     vpittamp@hetzner: /etc/nixos                → WS 1
  terminal     i3pm daemon logs                            → WS 1
  lazygit      /etc/nixos                                  → WS 7
  yazi         /etc/nixos/home-modules                     → WS 4

[Stacks] (3 windows)
  vscode       backend/main.go - Visual Studio Code        → WS 2
  terminal     vpittamp@hetzner: ~/projects/stacks         → WS 1
  firefox      Stacks Documentation                        → WS 3
```

**Output** (tree format):
```
Hidden Windows (8 total)
├── [NixOS] (5 windows)
│   ├── vscode → WS 2: i3-project.nix - Visual Studio Code
│   ├── terminal → WS 1: vpittamp@hetzner: /etc/nixos
│   ├── terminal → WS 1: i3pm daemon logs
│   ├── lazygit → WS 7: /etc/nixos
│   └── yazi → WS 4: /etc/nixos/home-modules
└── [Stacks] (3 windows)
    ├── vscode → WS 2: backend/main.go - Visual Studio Code
    ├── terminal → WS 1: vpittamp@hetzner: ~/projects/stacks
    └── firefox → WS 3: Stacks Documentation
```

**Output** (json format):
```json
{
  "total_hidden": 8,
  "projects": [
    {
      "project_name": "nixos",
      "display_name": "NixOS",
      "icon": "",
      "hidden_count": 5,
      "windows": [
        {
          "window_id": 123456,
          "app_name": "vscode",
          "window_class": "Code",
          "window_title": "i3-project.nix - Visual Studio Code",
          "tracked_workspace": 2,
          "floating": false,
          "last_seen": 1730000000.123
        }
      ]
    }
  ]
}
```

**Behavior**:
- Call daemon JSON-RPC method: `windows.getHidden`
- Apply filters if specified (project, workspace, app)
- Format output according to `--format` option
- Use Rich library for table rendering with colors
- Sort windows by tracked workspace number within each project

**Exit Codes**:
- **0**: Success, hidden windows displayed
- **1**: Daemon not running or unreachable
- **2**: Invalid filter parameters
- **3**: No hidden windows found

**Examples**:
```bash
# Show all hidden windows
i3pm windows hidden

# Show only nixos project hidden windows
i3pm windows hidden --project=nixos

# Show hidden windows that were on workspace 2
i3pm windows hidden --workspace=2

# Get JSON output for scripting
i3pm windows hidden --format=json | jq '.total_hidden'

# Show only VS Code windows
i3pm windows hidden --app=vscode
```

---

### i3pm windows restore

Manually restore hidden windows for a specific project.

**Synopsis**:
```bash
i3pm windows restore <project-name> [OPTIONS]
```

**Arguments**:
- `<project-name>`: Project whose windows should be restored

**Options**:
```
--dry-run            Show what would be restored without actually restoring
--window-id=<id>     Restore specific window only (not entire project)
--workspace=<num>    Override tracked workspace, restore to specific workspace
--json               Output result as JSON
```

**Output** (default):
```
Restoring windows for project: nixos

✓ vscode (123456) → Workspace 2
✓ terminal (789012) → Workspace 1
✓ terminal (345678) → Workspace 1
✓ lazygit (901234) → Workspace 7
✓ yazi (567890) → Workspace 4

Restored 5 windows in 147ms
```

**Output** (with fallback):
```
Restoring windows for project: nixos

✓ vscode (123456) → Workspace 2
⚠ terminal (789012) → Workspace 1 (fallback from WS 5, monitor disconnected)
✓ lazygit (901234) → Workspace 7

Restored 3 windows in 112ms (1 with fallback)
```

**Output** (dry-run):
```
Would restore 5 windows for project: nixos

→ vscode (123456) to Workspace 2
→ terminal (789012) to Workspace 1
→ terminal (345678) to Workspace 1
→ lazygit (901234) to Workspace 7
→ yazi (567890) to Workspace 4

Use without --dry-run to execute
```

**Behavior**:
- Call daemon JSON-RPC method: `project.restoreWindows`
- If `--dry-run`, query `windows.getHidden` and simulate
- If `--window-id`, restore only that specific window
- If `--workspace`, override tracked workspace with specified number
- Display progress with checkmarks (✓) or warnings (⚠)
- Report total time taken

**Exit Codes**:
- **0**: Success, all windows restored
- **1**: Daemon not running
- **2**: Invalid project name or window ID
- **3**: No hidden windows found for project
- **4**: Partial failure (some windows failed to restore)

**Examples**:
```bash
# Restore all nixos project windows
i3pm windows restore nixos

# Preview what would be restored
i3pm windows restore nixos --dry-run

# Restore specific window by ID
i3pm windows restore nixos --window-id=123456

# Restore all windows to workspace 5 (override tracking)
i3pm windows restore nixos --workspace=5

# Get JSON output
i3pm windows restore nixos --json
```

---

### i3pm windows inspect

Inspect detailed state for a specific window.

**Synopsis**:
```bash
i3pm windows inspect <window-id>
```

**Arguments**:
- `<window-id>`: i3 container ID to inspect

**Output**:
```
Window 123456 State

Basic Info:
  Class: Code
  Title: i3-project.nix - Visual Studio Code
  PID: 12345

Visibility:
  Status: Hidden (in scratchpad)
  Current Workspace: None
  Tracked Workspace: 2
  Floating: No

Project Association:
  Project: nixos (NixOS)
  App Name: vscode
  Scope: scoped
  App ID: vscode-nixos-12345-1730000000

Environment Variables:
  I3PM_PROJECT_NAME: nixos
  I3PM_APP_NAME: vscode
  I3PM_SCOPE: scoped
  I3PM_PROJECT_DIR: /etc/nixos
  I3PM_ACTIVE: true

Tracking:
  Last Seen: 2025-10-25 14:23:20 (5 minutes ago)
  In Workspace Map: Yes
```

**Behavior**:
- Call daemon JSON-RPC method: `windows.getState`
- Display comprehensive window state
- Show I3PM_* environment variables if present
- Format timestamps in human-readable format
- Highlight visibility status (visible, hidden, unknown)

**Exit Codes**:
- **0**: Success, window state displayed
- **1**: Daemon not running
- **2**: Invalid window ID
- **3**: Window not found in i3 tree

**Examples**:
```bash
# Inspect window by ID
i3pm windows inspect 123456

# Find window ID first, then inspect
i3pm windows --json | jq '.outputs[].workspaces[].windows[0].id' | head -1 | xargs i3pm windows inspect
```

---

## Modified Commands

### i3pm windows

Extend existing windows command to show hidden state.

**New Option**:
```
--show-hidden        Include hidden windows in tree/table view
```

**Output** (tree with --show-hidden):
```
 eDP-1 (Primary)
├── Workspace 1
│   ├── Ghostty (12345) [nixos] ●
│   └── Ghostty (67890) [nixos]
├── Workspace 2
│   └── Code (54321) [nixos] ●
├── Workspace 3
│   └── Firefox (11111) [Global]
└── Scratchpad
    ├── Code (23456) [stacks] 🔒
    ├── Ghostty (34567) [stacks] 🔒
    └── Lazygit (45678) [stacks] 🔒
```

**Legend**:
- `●` = Focused
- `🔒` = Hidden (in scratchpad)
- `[Project]` = Project association
- `[Global]` = Global scope (always visible)

**Behavior**:
- Query i3 tree including scratchpad containers
- Mark scratchpad windows with 🔒 icon
- Show project association for all windows
- Filter hidden windows by default unless `--show-hidden` specified

---

### i3pm project switch

Existing command now automatically handles window filtering.

**Synopsis** (unchanged):
```bash
i3pm project switch <project-name>
```

**New Behavior**:
- Switch triggers daemon's `project.switchWithFiltering` internally
- Daemon automatically hides old project windows
- Daemon automatically restores new project windows
- User sees seamless project switch with filtered windows

**Output**:
```
Switching to project: stacks

Hidden 5 windows from nixos
Restored 3 windows for stacks

Switch completed in 342ms
```

**No Breaking Changes**: Existing `i3pm project switch` usage unchanged

---

## Shell Aliases (Suggested)

Add to `~/.bashrc` or `~/.config/bash/aliases`:

```bash
# Window visibility aliases
alias phidden='i3pm windows hidden'                  # Show hidden windows
alias prestore='i3pm windows restore'                # Restore project windows
alias pwinspect='i3pm windows inspect'               # Inspect window state

# Project switching (already exists)
alias pswitch='i3pm project switch'
alias pcurrent='i3pm project current'
alias plist='i3pm project list'
```

---

## Keybindings (Suggested i3 Config)

Add to `~/.config/i3/config`:

```
# Show hidden windows via rofi
bindsym $mod+h exec --no-startup-id i3pm windows hidden --format=tree | rofi -dmenu -p "Hidden Windows"

# Toggle current window to scratchpad (manual hide)
bindsym $mod+Shift+minus move scratchpad

# Show scratchpad (cycle through hidden windows)
bindsym $mod+minus scratchpad show
```

---

## Output Format Standards

### Colors (Rich Library)

| Element | Color | Style |
|---------|-------|-------|
| Project name | Cyan | Bold |
| Hidden count | Yellow | Normal |
| Window title | White | Normal |
| App name | Green | Normal |
| Workspace | Magenta | Normal |
| Error message | Red | Bold |
| Success checkmark | Green | Bold |
| Warning icon | Yellow | Bold |

### Table Columns (hidden command)

| Column | Width | Align | Description |
|--------|-------|-------|-------------|
| App | 12 | Left | Application name |
| Title | 50 | Left | Window title (truncated) |
| Workspace | 8 | Right | Tracked workspace (e.g., "→ WS 2") |

### Tree Symbols

- `├──` - Branch
- `└──` - Last branch
- `│` - Vertical line
- `→` - Points to workspace
- `✓` - Success
- `⚠` - Warning
- `✗` - Error
- `🔒` - Hidden/locked

---

## Error Messages

### Daemon Not Running
```
Error: i3pm daemon is not running

Try:
  systemctl --user status i3-project-event-listener
  systemctl --user start i3-project-event-listener
```

### Invalid Project Name
```
Error: Project 'invalid-name' does not exist

Available projects:
  nixos
  stacks
  personal

Use: i3pm project list --all
```

### No Hidden Windows
```
No hidden windows found

All scoped windows are currently visible.
```

### Partial Restore Failure
```
Warning: 1 of 5 windows failed to restore

✓ vscode (123456) → Workspace 2
✓ terminal (789012) → Workspace 1
✗ lazygit (901234) → Failed: Window no longer exists
✓ yazi (567890) → Workspace 4

4 windows restored successfully, 1 failed
```

---

## Help Text

### i3pm windows hidden --help

```
Usage: i3pm windows hidden [OPTIONS]

Display all hidden windows grouped by project

Options:
  --project=<name>    Filter to specific project only
  --format=<format>   Output format: table, tree, json (default: table)
  --workspace=<num>   Filter to windows from specific workspace
  --app=<name>        Filter to specific application
  -h, --help          Show this help message

Examples:
  i3pm windows hidden
  i3pm windows hidden --project=nixos
  i3pm windows hidden --workspace=2
  i3pm windows hidden --format=json | jq '.total_hidden'

See also:
  i3pm windows restore - Restore hidden windows
  i3pm windows inspect - Inspect window state
  i3pm windows --show-hidden - Show hidden in tree view
```

---

## Performance Requirements

| Command | Target Latency | Notes |
|---------|---------------|-------|
| `i3pm windows hidden` | <200ms | Includes daemon query + formatting |
| `i3pm windows restore <project>` | <500ms | For up to 30 windows |
| `i3pm windows inspect <id>` | <100ms | Single window query |

---

## Testing Contract

### Unit Tests
- ✅ Argument parsing for all commands
- ✅ Filter logic (project, workspace, app)
- ✅ Output formatting (table, tree, json)
- ✅ Error message generation

### Integration Tests
- ✅ End-to-end CLI execution
- ✅ Daemon communication
- ✅ Output validation

### Scenario Tests
- ✅ Display hidden windows after project switch
- ✅ Restore windows to correct workspaces
- ✅ Inspect window with all states (visible, hidden, global)

---

**Status**: ✅ Complete - CLI commands contract defined with examples and help text
**Related**: `daemon-ipc.md` for underlying JSON-RPC API
