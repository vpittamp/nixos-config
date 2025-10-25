# Quick Start Guide: Registry-Centric Project Management

**Feature**: 035-now-that-we | **Date**: 2025-10-25
**For**: End users and developers

## Overview

This guide shows how to use the registry-centric project and workspace management system to organize your development workflows. The system uses `app-registry.nix` as the single source of truth for applications, projects reference apps by tag, and layouts save/restore your window arrangements.

---

## Prerequisites

- NixOS with i3 window manager configured (Hetzner reference platform)
- Feature 034 (Walker/Elephant registry integration) deployed
- `i3pm` Deno CLI installed and compiled
- i3 project management daemon running (`systemctl --user status i3-project-manager`)

---

## Core Concepts

### Application Registry

The **registry** is a Nix configuration file (`home-modules/desktop/app-registry.nix`) that defines all launchable applications with metadata:

- **Command** and **parameters** (with variable substitution like `$PROJECT_DIR`)
- **Window matching** (`expected_class` for workspace assignment)
- **Scope**: `scoped` (project-aware) or `global` (always available)
- **Tags**: Labels for grouping (e.g., `development`, `terminal`, `browser`)
- **Preferred workspace**: Where windows should appear (1-9)

### Projects

A **project** is a named workspace context with:

- **Root directory**: Project path (e.g., `/etc/nixos`)
- **Application tags**: Filter registry apps by tag (e.g., show only `development` + `editor`)
- **Optional layout**: Saved window arrangement

### Layouts

A **layout** is a snapshot of window positions, sizes, and workspace assignments. Layouts reference registry applications (not raw commands), so they always launch via the correct protocol.

---

## Quick Start: 5-Minute Workflow

### 1. Check the Registry

View all available applications:

```bash
i3pm apps list
```

Output:
```
NAME          DISPLAY NAME        WORKSPACE  SCOPE    TAGS
vscode        Visual Studio Code  1          scoped   development, editor
firefox       Firefox             2          global   browser, web
ghostty       Ghostty Terminal    -          scoped   terminal, development
lazygit       Lazygit TUI         -          scoped   git, development
```

Filter by tag:
```bash
i3pm apps list --tags development
```

### 2. Create a Project

Create a project for your work:

```bash
i3pm project create nixos \
  --display-name "NixOS Configuration" \
  --directory /etc/nixos \
  --tags development,editor,terminal,git
```

Output:
```
✓ Project 'nixos' created successfully
  Location: ~/.config/i3/projects/nixos.json

To switch to this project:
  i3pm project switch nixos
```

### 3. Switch to the Project

Activate your project:

```bash
i3pm project switch nixos
```

Output:
```
✓ Switched to project 'nixos'
  Directory: /etc/nixos
  Filtered Apps: 8 applications available
```

**What happens:**
- Active project set to "nixos"
- Walker launcher shows only apps with matching tags
- Scoped apps launched with `$PROJECT_DIR` = `/etc/nixos`
- i3bar shows "Project: nixos"

### 4. Launch Applications

Use Walker (Win+D) or command-line:

```bash
# Launch VS Code with project directory
walker  # Press Win+D, type "vscode"

# Or via command:
walker-launch vscode  # Automatically uses /etc/nixos
```

VS Code opens on workspace 1 with `/etc/nixos` loaded.

### 5. Arrange Your Workspace

Manually arrange windows across workspaces:

- Workspace 1: VS Code (full screen)
- Workspace 2: Firefox (documentation)
- Workspace 3: Two Ghostty terminals (split screen)

### 6. Save the Layout

Capture your arrangement:

```bash
i3pm layout save nixos
```

Output:
```
Capturing layout for project 'nixos'...

Windows captured:
  ✓ vscode on workspace 1 (1920x1080)
  ✓ ghostty on workspace 3 (1920x540) [1/2]
  ✓ ghostty on workspace 3 (1920x540) [2/2]
  ✓ firefox on workspace 2 (1920x1080)

✓ Layout 'nixos' saved successfully
  Windows: 4 (3 applications)
```

### 7. Restore the Layout Later

Close all windows, then restore:

```bash
i3pm layout restore nixos
```

Output:
```
Restoring layout 'nixos' for project 'nixos'...

Launching applications:
  [1/4] ✓ vscode launched (workspace 1)
  [2/4] ✓ ghostty launched (workspace 3) [instance 1]
  [3/4] ✓ ghostty launched (workspace 3) [instance 2]
  [4/4] ✓ firefox launched (workspace 2)

✓ Layout restored successfully
  4 windows launched, 4 positioned, 1 focused
```

All your windows reappear in their original positions!

---

## Common Workflows

### Switching Between Projects

```bash
# Switch to NixOS configuration work
i3pm project switch nixos

# Switch to Stacks development
i3pm project switch stacks

# Return to global mode (no project)
i3pm project clear
```

### Managing Projects

```bash
# List all projects
i3pm project list

# Show current project
i3pm project current

# Show specific project details
i3pm project show nixos

# Update project tags
i3pm project update nixos --tags development,editor,terminal,git,devops

# Delete project
i3pm project delete nixos
```

### Working with Layouts

```bash
# Save layout with custom name
i3pm layout save nixos nixos-debugging

# Preview what would be restored (dry-run)
i3pm layout restore nixos --dry-run

# Delete layout
i3pm layout delete nixos
```

### Monitoring Windows

```bash
# View current window state (tree view)
i3pm windows

# View as table
i3pm windows --table

# Live monitoring (interactive TUI)
i3pm windows --live

# JSON output for scripting
i3pm windows --json | jq '.outputs[0].workspaces'
```

---

## Daemon Interaction

The i3 project management daemon runs in the background and handles:

- Window auto-marking (assign scoped windows to workspaces)
- Project switch events (show/hide windows based on project tags)
- i3bar status updates (display active project)

### Check Daemon Status

```bash
i3pm daemon status
```

Output:
```
Daemon Status: RUNNING
  PID: 12345
  Uptime: 2h 15m 30s
  Active Project: nixos (since 2h 15m ago)
  Events Processed: 1,247
  Tracked Windows: 8
```

### View Daemon Events (Debugging)

```bash
# Show recent events
i3pm daemon events --limit 20

# Follow events in real-time
i3pm daemon events --follow

# Filter by event type
i3pm daemon events --type window
```

### Restart Daemon

```bash
systemctl --user restart i3-project-manager
```

---

## Keyboard Shortcuts

These are standard i3 bindings (from i3 config):

| Key | Action |
|-----|--------|
| `Win+D` | Walker launcher (shows filtered apps based on project) |
| `Win+P` | Project switcher (rofi menu with projects) |
| `Win+Shift+P` | Clear active project (global mode) |
| `Win+Return` | Launch terminal (Ghostty with project context) |
| `Win+C` | Launch VS Code with project directory |
| `Win+G` | Launch lazygit in project repository |
| `Win+Y` | Launch yazi file manager in project directory |

---

## Troubleshooting

### Applications Not Launching with Project Context

**Symptom**: VS Code opens in wrong directory, terminal doesn't use project path

**Check**:
1. Verify active project: `i3pm project current`
2. Check daemon is running: `i3pm daemon status`
3. Verify app is scoped in registry: `i3pm apps show vscode`
4. Check daemon logs: `journalctl --user -u i3-project-manager -n 50`

**Fix**:
```bash
# Restart daemon
systemctl --user restart i3-project-manager

# Re-switch to project
i3pm project switch nixos
```

### Windows Not Appearing on Correct Workspace

**Symptom**: Firefox opens on workspace 1 instead of workspace 2

**Check**:
1. Verify registry workspace assignment: `i3pm apps show firefox`
2. Check for conflicting i3 window rules: `cat ~/.config/i3/config | grep for_window`
3. Check daemon window matching: `i3pm daemon events --type window --limit 10`

**Fix**:
```bash
# Rebuild NixOS config (regenerates window rules)
sudo nixos-rebuild switch --flake .#hetzner

# Restart i3 to reload config
i3-msg restart
```

### Layout Restore Fails

**Symptom**: Some applications don't launch, or windows appear in wrong positions

**Check**:
1. Verify all apps exist in registry: `i3pm layout restore nixos --dry-run`
2. Check registry for missing apps: `i3pm apps list`
3. View layout contents: `cat ~/.config/i3/layouts/nixos.json | jq '.windows'`

**Fix**:
```bash
# Recapture layout with current applications
i3pm layout save nixos --overwrite

# Or delete and recreate layout
i3pm layout delete nixos
# Arrange windows manually
i3pm layout save nixos
```

### Project Tags Not Filtering Applications

**Symptom**: Walker shows all applications instead of project-filtered apps

**Check**:
1. Verify project tags: `i3pm project show nixos`
2. Verify application tags: `i3pm apps list --json | jq '.[] | {name, tags}'`
3. Check daemon processed project switch: `i3pm daemon events --type tick --limit 5`

**Fix**:
```bash
# Update project tags to match registry
i3pm project update nixos --tags development,editor,terminal

# Re-switch to project
i3pm project clear
i3pm project switch nixos
```

---

## Advanced Usage

### JSON Output for Scripting

All commands support `--json` for automation:

```bash
# Get list of all development apps as JSON
i3pm apps list --tags development --json > dev-apps.json

# Check if project exists
if i3pm project show nixos --json 2>/dev/null | jq -e '.status == "success"' > /dev/null; then
  echo "Project exists"
fi

# Get current project name
current=$(i3pm project current --json | jq -r '.data.project_name // "none"')
echo "Active project: $current"
```

### Multi-Instance Applications

Terminal applications allow multiple windows:

```bash
# Launch multiple terminals in same project
walker-launch ghostty  # Instance 1
walker-launch ghostty  # Instance 2

# Both terminals open with project context
# Workspace assignment is dynamic (not fixed)
```

### Custom Fallback Behavior

Scoped applications have fallback behavior when no project is active:

- `skip`: Don't launch (show error message)
- `use_home`: Launch with `$HOME` instead of `$PROJECT_DIR`
- `error`: Show error dialog

Check app fallback:
```bash
i3pm apps show vscode --json | jq '.fallback_behavior'
```

---

## Configuration Files

### User Configuration Locations

```
~/.config/i3/
├── application-registry.json     # Compiled registry (read-only symlink to /nix/store)
├── active-project.json           # Current active project state
├── projects/                     # Project configurations
│   ├── nixos.json
│   ├── stacks.json
│   └── personal.json
└── layouts/                      # Saved layouts
    ├── nixos.json
    ├── stacks-fullstack.json
    └── personal-productivity.json
```

### System Configuration (Nix)

```
/etc/nixos/
├── home-modules/desktop/
│   ├── app-registry.nix          # Source of truth for applications
│   └── i3-window-rules.nix       # Auto-generated window rules
├── home-modules/tools/i3pm/      # Deno CLI source code
└── configurations/hetzner-i3.nix # Reference platform config
```

### Daemon Configuration

```
~/.config/systemd/user/i3-project-manager.service  # Systemd service
/run/user/1000/i3-project-manager.sock             # JSON-RPC socket
```

---

## Next Steps

1. **Extend the registry**: Add more applications to `app-registry.nix` and rebuild
2. **Create additional projects**: Different projects for different work contexts
3. **Experiment with layouts**: Save different arrangements for different tasks
4. **Customize tags**: Group applications in ways that match your workflow
5. **Bind keyboard shortcuts**: Add i3 keybindings for quick project switching

---

## Getting Help

```bash
# Command help
i3pm --help
i3pm project --help
i3pm layout --help

# Check daemon logs
journalctl --user -u i3-project-manager -f

# View system state
i3pm windows --live  # Real-time monitoring
i3pm daemon status   # Daemon diagnostics

# Debug layout issues
i3pm layout restore <project> --dry-run  # Preview without launching
```

For issues or feature requests, consult the feature specification at `/etc/nixos/specs/035-now-that-we/spec.md`.
