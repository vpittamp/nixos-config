# Quickstart: Project-Scoped Workspace Management

**Feature**: 011-project-scoped-application
**Date**: 2025-10-19

## Overview

This quickstart guide provides a user-facing reference for managing projects and launching project-scoped applications in i3wm.

## Core Concepts

### Project-Scoped vs Global Applications

**Project-Scoped** (isolated per project):
- **Ghostty** (Workspace 1): Terminal with sesh session manager
- **VS Code** (Workspace 2): Code editor opening project directory
- **Yazi** (Workspace 5): File manager starting in project directory
- **Lazygit** (Workspace 7): Git TUI connected to project repository

**Global** (accessible across all projects):
- **Firefox** (Workspace 3): Web browser
- **YouTube PWA** (Workspace 4): Video player
- **K9s** (Workspace 6): Kubernetes manager
- **Google AI PWA** (Workspace 8): AI assistant

### How It Works

1. **Activate a project** (e.g., "NixOS Configuration")
2. **Launch applications** using keybindings (they open in project context)
3. **Switch to another project** (e.g., "Stacks Platform")
4. Previous project's applications are automatically hidden
5. New project's applications become visible
6. Global applications remain accessible throughout

## Key Bindings

### Project Management

| Keybinding | Action | Description |
|------------|--------|-------------|
| `Win+P` | Project Switcher | Open rofi menu to select active project |
| `Win+Shift+P` | Clear Project | Return to global mode (no project active) |

### Project-Aware Launchers

| Keybinding | Application | Behavior with Active Project |
|------------|-------------|------------------------------|
| `Win+Return` | Ghostty Terminal | Opens with sesh connected to project session |
| `Win+C` | VS Code | Opens project directory |
| `Win+Y` | Yazi | Starts in project directory |
| `Win+G` | Lazygit | Connects to project repository |

### Global Launchers (unchanged)

| Keybinding | Application | Workspace |
|------------|-------------|-----------|
| `Win+B` | Firefox | 3 |
| `Win+K` | K9s | 6 |
| `Win+A` | Google AI (Gemini) | 8 |

### Monitor Management

| Keybinding | Action | Description |
|------------|--------|-------------|
| `Win+Shift+M` | Detect Monitors | Manually trigger monitor detection and workspace reassignment |

## Workflows

### Workflow 1: Start Working on a Project

```
1. Press Win+P
2. Select "NixOS Configuration" from rofi menu
3. Polybar shows " NixOS Configuration"
4. Press Win+C to launch VS Code → opens /etc/nixos
5. Press Win+Return to launch terminal → sesh connects to nixos session
6. Press Win+G to launch lazygit → opens /etc/nixos repository
```

**Result**: All applications open in NixOS project context on designated workspaces.

### Workflow 2: Switch Between Projects

```
Current State: Working on NixOS project with VS Code and Ghostty open

1. Press Win+P
2. Select "Stacks Platform" from rofi menu
3. NixOS VS Code and Ghostty disappear (moved to scratchpad)
4. If Stacks applications were previously open, they reappear
5. Polybar shows " Stacks Platform"
6. Press Win+C to launch VS Code → opens /home/vpittamp/stacks
```

**Result**: Context switches seamlessly, previous project's windows hidden.

### Workflow 3: Access Global Tools While in Project

```
Current State: Working on NixOS project

1. Press Win+B to launch Firefox
2. Firefox opens on workspace 3
3. Press Win+3 to switch to Firefox workspace
4. Firefox remains accessible
5. Press Win+2 to return to VS Code (still in NixOS project)
```

**Result**: Global applications accessible regardless of active project.

### Workflow 4: Return to Global Mode

```
Current State: Working on Stacks project

1. Press Win+Shift+P to clear project
2. Polybar shows "No Project"
3. All hidden windows become visible again
4. Subsequent application launches use global workspace assignments
```

**Result**: All project windows visible, no project context active.

### Workflow 5: Working with Multiple Monitors

```
Setup: Connected 2 monitors (DP-1 primary, DP-2 secondary)

Automatic behavior:
- Workspaces 1-2 (Ghostty, VS Code) → Primary monitor (DP-1)
- Workspaces 3-9 (Firefox, etc.) → Secondary monitor (DP-2)

If monitors change (hotplug):
1. Press Win+Shift+M to manually trigger reassignment
2. Workspaces redistribute based on new monitor count
```

**Result**: Workspaces intelligently distributed across available monitors.

## Project Configuration

### Viewing Available Projects

Projects are defined in `~/.config/i3/projects.json`. Current projects:

- ** NixOS Configuration** (`nixos`): /etc/nixos
- ** Stacks Platform** (`stacks`): /home/vpittamp/stacks
- ** Personal Projects** (`personal`): /home/vpittamp/projects

### Checking Active Project

**Via Polybar**: Look at the project indicator module (shows icon + name)

**Via Command Line**:
```bash
~/.config/i3/scripts/project-current.sh | jq -r '.name'
# Output: "NixOS Configuration" or "No Project" if none active
```

### Adding a New Project

Edit `~/.config/i3/projects.json`:

```json
{
  "myproject": {
    "name": "My New Project",
    "directory": "/home/vpittamp/myproject",
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

After editing, project appears in switcher menu (no i3 reload needed).

## Troubleshooting

### Problem: Application doesn't open in project context

**Symptoms**: VS Code or terminal opens in wrong directory

**Solution**:
1. Check active project: `~/.config/i3/scripts/project-current.sh`
2. Verify project directory exists: `ls -la <directory>`
3. Try clearing and reactivating project: `Win+Shift+P` then `Win+P`

### Problem: Windows from old project still visible

**Symptoms**: After switching projects, old windows remain on workspaces

**Solution**:
1. Verify project switch completed: Check polybar shows new project
2. Manually move windows to scratchpad: `Win+Shift+Minus`
3. Re-run project switch: `Win+P` and select project again

### Problem: Monitor detection doesn't work

**Symptoms**: Workspaces appear on wrong monitors

**Solution**:
1. Manually trigger detection: `Win+Shift+M`
2. Check monitor connection: `xrandr --query | grep connected`
3. Verify i3 config: `cat ~/.config/i3/config | grep workspace.*output`

### Problem: Project switcher shows no projects

**Symptoms**: Rofi menu is empty or shows error

**Solution**:
1. Check projects.json exists: `cat ~/.config/i3/projects.json`
2. Validate JSON syntax: `jq . ~/.config/i3/projects.json`
3. Check script permissions: `ls -l ~/.config/i3/scripts/project-switcher.sh`

### Problem: Scratchpad windows lost on i3 restart

**Symptoms**: Hidden windows disappear after i3 restart

**Expected Behavior**: This is a known limitation. Windows in scratchpad should be manually restored or relaunched after i3 restart. Future enhancement may add persistent window state tracking.

## Tips & Best Practices

### Tip 1: Use sesh for persistent sessions

Sesh (tmux session manager) preserves your terminal state across disconnections:
- Sessions persist even after closing terminal window
- Reconnect to same session when launching terminal in project
- Sessions named after projects for easy identification

**Access sesh directly**:
```bash
# List sessions
sesh list

# Connect to specific session
sesh connect nixos

# Kill session
sesh kill nixos
```

### Tip 2: Keep global applications on separate workspaces

To avoid accidental hiding when switching projects:
- Firefox → Workspace 3 (always global)
- YouTube → Workspace 4 (always global)
- K9s → Workspace 6 (can be project-scoped if needed)

### Tip 3: Use Win+Number for quick workspace access

Even with projects active, direct workspace access works:
- `Win+1`: Jump to terminal workspace (current project's terminal)
- `Win+2`: Jump to code workspace (current project's VS Code)
- `Win+3`: Jump to Firefox (global)

### Tip 4: Clear project before system maintenance

If planning to restart i3 or reboot:
1. `Win+Shift+P` to clear project
2. All windows become visible
3. Close applications normally
4. Restart/reboot

This prevents windows from being lost in scratchpad.

### Tip 5: Monitor detection after docking/undocking

If using a laptop with docking station:
1. Dock/undock the laptop
2. Press `Win+Shift+M` to trigger monitor reassignment
3. Workspaces redistribute automatically

## Command Reference

### Project Management Scripts

```bash
# Get current project
~/.config/i3/scripts/project-current.sh

# Set project manually
~/.config/i3/scripts/project-set.sh nixos [--switch]

# Clear project
~/.config/i3/scripts/project-clear.sh

# Interactive project switcher
~/.config/i3/scripts/project-switcher.sh
```

### Launcher Scripts

```bash
# Launch VS Code in project context
~/.config/i3/scripts/launch-code.sh

# Launch Ghostty with sesh in project context
~/.config/i3/scripts/launch-ghostty.sh

# Launch lazygit in project repository
~/.config/i3/scripts/launch-lazygit.sh

# Launch yazi in project directory
~/.config/i3/scripts/launch-yazi.sh
```

### Monitor Scripts

```bash
# Detect monitors and assign workspaces
~/.config/i3/scripts/detect-monitors.sh

# Manually assign workspace to monitor
~/.config/i3/scripts/assign-workspace-monitor.sh <workspace> <output>
```

## Integration with Existing Workflows

### Integration with tmux/sesh

Project-scoped terminals use sesh sessions named after project IDs:
- `nixos` session → NixOS project
- `stacks` session → Stacks project

This means:
- Opening terminal in NixOS project connects to `nixos` tmux session
- Session state persists (open files, panes, layouts)
- Can manually connect: `sesh connect nixos`

### Integration with VS Code workspaces

VS Code opens project directory directly. To use VS Code workspaces:
1. Create `.code-workspace` file in project directory
2. Open it manually: `code /etc/nixos/nixos.code-workspace`
3. VS Code remembers last opened workspace

### Integration with Git workflows

Lazygit automatically connects to project repository:
- Detects `.git` directory in project root
- Shows status for project's repository
- Can be launched manually: `lazygit -p /etc/nixos`

### Integration with file managers

Yazi starts in project directory:
- Navigate filesystem from project root
- Respects `.gitignore` for cleaner views
- Can be launched manually: `yazi /etc/nixos`

## Further Reading

- [Full Architecture Documentation](../docs/PROJECT_WORKSPACE_MANAGEMENT.md)
- [Data Model Reference](./data-model.md)
- [i3 IPC API Contract](./contracts/i3-ipc-api.md)
- [Implementation Plan](./plan.md)

## Feedback & Support

For issues or feature requests:
1. Check [troubleshooting section](#troubleshooting) above
2. Review logs: `journalctl --user -u i3` (if i3 runs as systemd service)
3. Test individual scripts manually (see Command Reference)
4. Report issues with full error messages and steps to reproduce
