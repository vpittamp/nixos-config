# Quickstart Guide: i3 Project Workspace Management

**Feature**: i3-Native Dynamic Project Workspace Management
**Date**: 2025-10-19

## Overview

This guide provides step-by-step instructions for using the i3-native project workspace management system. Create, switch, and manage projects without rebuilding your NixOS configuration.

## Prerequisites

- i3 window manager >= 4.15 installed and running
- jq (JSON parser) installed
- rofi (application launcher) installed
- Bash shell >= 5.0

Verify prerequisites:
```bash
i3 --version  # Should show 4.15 or later
jq --version  # Should show 1.6 or later
rofi -version # Should show any version
```

## Basic Workflow

### 1. Create Your First Project

Create a project for your NixOS configuration work:

```bash
i3-project-create \
  --name nixos \
  --dir /etc/nixos \
  --icon  \
  --display-name "NixOS Configuration"
```

**Output**:
```
Created project 'nixos' at ~/.config/i3/projects/nixos.json
```

The project JSON file has been created with minimal configuration. You can edit it later to add workspace layouts and launch commands.

### 2. Activate the Project

Switch to your new project using the keyboard shortcut:

**Press**: `Win+P` (or `Mod+P` depending on your i3 config)

**Or use the command line**:
```bash
i3-project-switch nixos
```

**What happens**:
- Active project indicator appears in polybar: " NixOS"
- Project context is now active
- Applications launched via project wrappers will be marked with `project:nixos`

### 3. Launch Applications in Project Context

**Open VS Code** in project directory:
```bash
# Press Win+C, or run:
i3-project-launch-code
```

VS Code opens at `/etc/nixos` and receives the mark `project:nixos`.

**Open Terminal** with sesh session:
```bash
# Press Win+Return, or run:
i3-project-launch-terminal
```

Terminal opens in `/etc/nixos` with project mark.

**Open lazygit**:
```bash
# Press Win+G, or run:
i3-project-launch-lazygit
```

**Open yazi file manager**:
```bash
# Press Win+Y, or run:
i3-project-launch-yazi
```

### 4. Switch to Another Project

Create a second project:
```bash
i3-project-create \
  --name stacks \
  --dir ~/code/stacks \
  --icon  \
  --display-name "Stacks Project"
```

Switch to the new project:
```bash
# Press Win+P and select "Stacks Project"
# Or use command line:
i3-project-switch stacks
```

**What happens**:
- Windows marked with `project:nixos` move to scratchpad (hidden)
- Windows marked with `project:stacks` show from scratchpad (if any exist)
- Polybar updates to " Stacks"
- New applications launch in stacks context

### 5. Return to Global Mode

Clear the active project to work without project context:

```bash
# Press Win+Shift+P, or run:
i3-project-clear
```

**What happens**:
- All project-scoped windows show from scratchpad
- Polybar shows "No Project"
- New applications launch without project marks (global mode)

## Advanced Usage

### Customize Project Workspace Layout

Edit the project JSON to define workspace layouts:

```bash
i3-project-edit nixos
```

Add workspace configuration:
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
    "1": {
      "launchCommands": [
        "ghostty --working-directory /etc/nixos -e sesh connect nixos"
      ]
    },
    "2": {
      "layout": {
        "layout": "splith",
        "nodes": [
          {
            "swallows": [{"class": "^Code$"}],
            "marks": ["project:nixos"]
          }
        ]
      },
      "launchCommands": [
        "code /etc/nixos"
      ]
    }
  }
}
```

Save and reactivate the project:
```bash
i3-project-switch nixos
```

i3 will restore the workspace layout and launch the specified applications.

### Assign Workspaces to Monitors

For multi-monitor setups, specify which monitor each workspace should use:

```bash
i3-project-edit nixos
```

Add workspace output assignments:
```json
{
  "workspaceOutputs": {
    "1": "eDP-1",
    "2": "HDMI-1"
  }
}
```

**Find your output names**:
```bash
i3-msg -t get_outputs | jq -r '.[] | select(.active) | .name'
```

### Configure Application Classifications

Customize which applications are project-scoped vs global:

```bash
vi ~/.config/i3/app-classes.json
```

Example configuration:
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
      "class": "Obsidian",
      "scoped": true,
      "workspace": 3,
      "description": "Obsidian notes"
    },
    {
      "class": "Firefox",
      "scoped": false,
      "description": "Firefox browser (always global)"
    }
  ]
}
```

Changes take effect immediately on next application launch (no rebuild required).

### Manually Mark a Window

If you launched an application without the project wrapper, mark it manually:

**Focus the window**, then:
```bash
i3-project-mark-window
```

Or specify window ID:
```bash
# Get window ID with xdotool or i3-msg -t get_tree
i3-project-mark-window 0x1a00003
```

### Export Current Workspace Layout

Save your current workspace 2 layout as a starting point:

```bash
i3-save-tree --workspace 2 > /tmp/workspace-2.json
```

Simplify the JSON (remove transient properties), then copy to project JSON:
```bash
vi /tmp/workspace-2.json  # Remove unnecessary fields
jq '.workspaces."2".layout = input' \
  ~/.config/i3/projects/nixos.json \
  /tmp/workspace-2.json > /tmp/updated.json
mv /tmp/updated.json ~/.config/i3/projects/nixos.json
```

## Common Workflows

### Workflow: Web Development Project

Create project for web app development:
```bash
i3-project-create \
  --name webapp \
  --dir ~/code/my-webapp \
  --icon  \
  --display-name "Web Application"
```

Edit configuration to launch dev server and tools:
```json
{
  "project": {
    "name": "webapp",
    "directory": "~/code/my-webapp"
  },
  "workspaces": {
    "1": {
      "launchCommands": [
        "ghostty -e 'npm run dev'"
      ]
    },
    "2": {
      "launchCommands": [
        "code ~/code/my-webapp"
      ]
    },
    "3": {
      "launchCommands": [
        "firefox http://localhost:3000"
      ]
    }
  },
  "appClasses": ["Code", "Ghostty"]
}
```

Note: Firefox is NOT in appClasses, so it remains global (accessible from all projects).

### Workflow: Multiple Related Projects

Create parent and child projects that share context:

```bash
i3-project-create --name infra --dir ~/code/infrastructure
i3-project-create --name backend --dir ~/code/backend
i3-project-create --name frontend --dir ~/code/frontend
```

Switch between them as needed. Each maintains separate workspace state.

### Workflow: Temporary Project for Debugging

Create a temporary project for investigating an issue:

```bash
i3-project-create \
  --name debug-issue-123 \
  --dir /tmp/debug-workspace
```

Work on the issue with full project context, then delete when done:

```bash
i3-project-delete debug-issue-123 --force
```

## Troubleshooting

### Projects Don't Appear in Switcher

**Check project directory exists**:
```bash
ls ~/.config/i3/projects/
```

**Validate project JSON**:
```bash
i3-project-validate nixos
```

**List projects via CLI**:
```bash
i3-project-list
```

### Windows Not Getting Marked

**Check active project**:
```bash
i3-project-current
```

**Verify window class**:
```bash
xprop WM_CLASS  # Click on window
```

**Check if class is marked as scoped**:
```bash
jq '.classes[] | select(.class == "Code")' ~/.config/i3/app-classes.json
```

**Manually mark the window**:
```bash
i3-project-mark-window
```

### Polybar Not Updating

**Verify polybar module is running**:
```bash
ps aux | grep polybar
```

**Check i3 tick events are sent**:
```bash
# Subscribe to tick events
i3-msg -t subscribe -m '["tick"]'
# In another terminal, switch project
i3-project-switch nixos
# Should see tick event with "project:nixos"
```

**Restart polybar**:
```bash
killall polybar
polybar &
```

### Layout Not Restoring

**Validate layout JSON**:
```bash
jq '.workspaces."2".layout' ~/.config/i3/projects/nixos.json
```

**Test layout manually**:
```bash
i3-msg 'workspace 2; append_layout ~/.config/i3/projects/nixos.json'
```

**Check i3 logs**:
```bash
journalctl --user -u i3.service -f
```

### Project Switch is Slow

**Too many windows**:
- Reduce number of project-scoped windows
- Consider making some applications global

**Large layout JSON**:
- Simplify layout (remove unnecessary nesting)
- Use minimal swallows criteria

**Enable debug logging**:
```bash
export I3_PROJECT_DEBUG=1
i3-project-switch nixos
tail -f ~/.config/i3/project-manager.log
```

## Keybinding Reference

Default i3 keybindings for project management:

| Key | Action |
|-----|--------|
| `Win+P` | Open project switcher (rofi) |
| `Win+Shift+P` | Clear active project |
| `Win+C` | Launch VS Code in project context |
| `Win+Return` | Launch terminal with sesh session |
| `Win+G` | Launch lazygit |
| `Win+Y` | Launch yazi file manager |
| `Win+Shift+M` | Manually reassign workspaces to monitors |

## Command Reference

### Project Management
```bash
i3-project-create --name NAME --dir DIR [--icon ICON]
i3-project-delete NAME [--force]
i3-project-list [--format json|text]
i3-project-switch NAME
i3-project-clear
i3-project-current [--format json|text]
i3-project-edit NAME
i3-project-validate NAME
```

### Application Launchers
```bash
i3-project-launch-code [DIRECTORY]
i3-project-launch-terminal [COMMAND]
i3-project-launch-lazygit
i3-project-launch-yazi
```

### Window Management
```bash
i3-project-mark-window [WINDOW_ID]
```

### Migration
```bash
i3-project-migrate [--source FILE] [--dry-run]
```

## File Locations

```
~/.config/i3/
├── projects/               # Project JSON files
│   ├── nixos.json
│   ├── stacks.json
│   └── webapp.json
├── active-project          # Current active project name
├── app-classes.json        # Application classification config
├── launchers/              # Application wrapper scripts
│   ├── code
│   ├── ghostty
│   ├── lazygit
│   └── yazi
├── scripts/                # Project management scripts
│   ├── project-create.sh
│   ├── project-switch.sh
│   ├── project-clear.sh
│   └── rofi-switcher.sh
└── project-manager.log     # Debug/error log
```

## Next Steps

1. **Create your primary projects**: Use `i3-project-create` for your most common workspaces
2. **Customize workspace layouts**: Edit project JSON files to define window placement
3. **Configure application classifications**: Adjust `app-classes.json` to match your workflow
4. **Set up multi-monitor workspace distribution**: Add `workspaceOutputs` to project JSON
5. **Integrate with existing tools**: Use project launchers in your scripts and keybindings

## Getting Help

**View logs**:
```bash
tail -f ~/.config/i3/project-manager.log
```

**Enable debug mode**:
```bash
export I3_PROJECT_DEBUG=1
```

**Check project configuration**:
```bash
i3-project-validate PROJECT_NAME
```

**Verify i3 IPC is working**:
```bash
i3-msg -t get_version
```

**Report issues**: Include output from:
```bash
i3 --version
i3-project-list --format json
cat ~/.config/i3/project-manager.log
```

## Examples Repository

See `/etc/nixos/specs/012-review-project-scoped/examples/` for:
- Sample project JSON files
- Custom application launcher scripts
- Polybar module configurations
- Advanced workspace layouts
- Multi-monitor setups

## Migration from Static Configuration

If you have existing static project definitions in NixOS configuration:

```bash
# Review what will be migrated
i3-project-migrate --dry-run

# Perform migration
i3-project-migrate

# Verify migrated projects
i3-project-list
```

After successful migration, you can remove static project definitions from your NixOS configuration and rebuild.

---

**Last Updated**: 2025-10-19
**Version**: 1.0
**Feedback**: Report issues to `/etc/nixos` project maintainers
