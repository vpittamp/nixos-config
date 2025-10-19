# Quick Start Guide: i3 Project Management System

**Feature**: 014 - Consolidate and Validate i3 Project Management System
**Date**: 2025-10-19
**Audience**: End users of the i3 project management system

## Introduction

The i3 project management system provides seamless project-based workspace isolation in i3 window manager. You can create multiple projects, switch between them with keyboard shortcuts, and have project-specific applications automatically show/hide based on the active project. Global applications (browser, monitoring tools) remain visible across all projects.

**Key Benefits**:
- Fast project switching with keyboard shortcuts (Win+P)
- Automatic window visibility management
- Visual feedback in status bar
- No manual window arrangement needed

---

## Quick Reference

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Win+P` | Open project switcher (rofi) |
| `Win+Shift+P` | Clear active project (global mode) |
| `Win+C` | Launch VS Code in project directory |
| `Win+Return` | Launch Ghostty terminal in project directory |
| `Win+G` | Launch lazygit in project repository |
| `Win+Y` | Launch yazi file manager in project directory |

### Shell Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `project-create` | - | Create new project |
| `project-delete` | - | Delete existing project |
| `project-switch NAME` | `pswitch` | Switch to project |
| `project-clear` | `pclear` | Clear active project |
| `project-list` | `plist` | List all projects |
| `project-current` | `pcurrent` | Show current project |
| `project-logs` | - | View system logs |

---

## Getting Started

### 1. Create Your First Project

```bash
project-create --name "nixos" --dir /etc/nixos --icon "" --display-name "NixOS Configuration"
```

**Parameters**:
- `--name` : Unique identifier (alphanumeric + dash, used in commands)
- `--dir` : Absolute path to project root directory
- `--icon` : Unicode emoji or Nerd Font icon for status bar
- `--display-name` : Human-readable name for display

**Example output**:
```
[INFO] Created project: nixos
[INFO] Project config written to: /home/user/.config/i3/projects/nixos.json
```

### 2. List Available Projects

```bash
project-list
# or short alias:
plist
```

**Example output**:
```
nixos - NixOS Configuration (/etc/nixos)
stacks -  Stacks Platform (/home/user/code/stacks)
personal -  Personal Projects (/home/user/personal)
```

### 3. Switch to a Project

**Method 1: Keyboard Shortcut (Recommended)**
```
Press: Win+P
Type: nixos
Press: Enter
```

**Method 2: Command Line**
```bash
project-switch nixos
# or short alias:
pswitch nixos
```

**What happens**:
1. Windows from previous project move to scratchpad (hidden)
2. Windows from new project appear on workspaces
3. Status bar updates to show " NixOS Configuration"
4. New applications launched will be tagged with this project

**Timing**: <1 second for typical project (10 windows)

### 4. Launch Applications in Project Context

**VS Code** (Win+C):
```bash
# Launches VS Code in project directory
# Window automatically tagged with project:nixos
```

**Ghostty Terminal** (Win+Return):
```bash
# Launches terminal in project directory
# Window automatically tagged with project:nixos
```

**lazygit** (Win+G):
```bash
# Launches lazygit for project repository
# Window automatically tagged with project:nixos
```

**yazi File Manager** (Win+Y):
```bash
# Launches yazi in project directory
# Window automatically tagged with project:nixos
```

### 5. Check Current Project

```bash
project-current
# or short alias:
pcurrent
```

**Example output**:
```
 NixOS Configuration (nixos)
```

### 6. Clear Active Project (Global Mode)

**Method 1: Keyboard Shortcut**
```
Press: Win+Shift+P
```

**Method 2: Command Line**
```bash
project-clear
# or short alias:
pclear
```

**What happens**:
- All project windows remain visible
- Status bar shows "∅ No Project"
- New applications launched will NOT be tagged with project

---

## Common Workflows

### Workflow 1: Daily Development Routine

**Morning: Start work on NixOS configuration**
```bash
# Switch to nixos project
Win+P → type "nixos" → Enter

# Launch tools
Win+C           # VS Code opens /etc/nixos
Win+Return      # Terminal opens in /etc/nixos
Win+G           # lazygit for nixos repo
```

**Afternoon: Switch to Stacks development**
```bash
# Switch to stacks project
Win+P → type "stacks" → Enter

# NixOS windows hide automatically
# Stacks windows appear (if they exist)
# Launch new tools
Win+C           # VS Code opens /home/user/code/stacks
Win+Return      # Terminal opens in stacks directory
```

**Evening: Check personal projects**
```bash
# Switch to personal project
Win+P → type "personal" → Enter

# Or use command line
pswitch personal
```

**End of day: Return to global mode**
```bash
# Clear active project
Win+Shift+P

# Or use command line
pclear
```

### Workflow 2: Multi-Project Debugging

**Scenario**: You're working on an API and need to test with a frontend simultaneously.

```bash
# Create both projects
project-create --name "api" --dir ~/code/api-gateway --icon "" --display-name "API Gateway"
project-create --name "frontend" --dir ~/code/web-app --icon "" --display-name "Web App"

# Start with API
pswitch api
Win+C                    # VS Code for API
Win+Return               # Terminal: npm run dev

# Keep firefox global (it stays visible across switches)
# Frontend in separate project
pswitch frontend
Win+C                    # VS Code for frontend (API editor hides)
Win+Return               # Terminal: npm run dev

# Switch back to API to check logs
pswitch api              # API editor and terminal reappear
```

### Workflow 3: Clean Up Old Projects

```bash
# List all projects
plist

# Delete unused project
project-delete old-project

# Confirm deletion
# Windows with old-project marks remain but become unmarked
```

---

## Status Bar Indicator

The i3blocks status bar shows your current project context:

| Display | Meaning |
|---------|---------|
| ` NixOS Configuration` | Project "nixos" active |
| ` Stacks Platform` | Project "stacks" active |
| `∅ No Project` | No active project (global mode) |

**Colors** (Catppuccin Mocha theme):
- Active project: Highlighted color (#89b4fa blue)
- No project: Dimmed color (#6c7086 surface2)

**Update Timing**: <1 second after project switch

---

## Application Classification

### Project-Scoped Applications

These applications **hide when switching away** from their project:

- **VS Code** - Each project opens its own editor instance
- **Ghostty Terminal** - Terminal sessions tied to project directory
- **Alacritty Terminal** - Alternative terminal (if configured)
- **lazygit** - Git client for project repository
- **yazi** - File manager in project directory

### Global Applications

These applications **remain visible** across all projects:

- **Firefox** - Browser stays open regardless of project
- **PWAs** - YouTube Music, Google AI, etc.
- **k9s** - Kubernetes monitoring tool
- **System Tools** - Network monitors, system settings

**Configuration**: See `~/.config/i3/app-classes.json` for full list

---

## Troubleshooting

### Issue: Project switcher (Win+P) doesn't appear

**Diagnosis**:
```bash
# Check if rofi is installed
which rofi

# Check i3 keybinding
grep "bindsym.*rofi.*project" ~/.config/i3/config
```

**Solution**:
```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --flake .#hetzner
```

### Issue: Status bar doesn't update after project switch

**Diagnosis**:
```bash
# Check active project file exists
cat ~/.config/i3/active-project

# Check i3blocks is running
pgrep i3blocks

# Check project indicator script
~/.config/i3blocks/scripts/project.sh
```

**Solution**:
```bash
# Manually trigger status bar update
pkill -RTMIN+10 i3blocks

# Or restart i3
Win+Shift+R
```

### Issue: Applications launch but don't receive project mark

**Diagnosis**:
```bash
# Check current project
project-current

# Check if app is classified as scoped
jq '.classes[] | select(.class == "Code")' ~/.config/i3/app-classes.json

# Check window marks
i3-msg -t get_tree | jq '.. | select(.window_properties?.class == "Code") | .marks'
```

**Solution**:
```bash
# Ensure project is active before launching
project-current

# If "No active project", switch first
pswitch nixos

# Then launch application
Win+C
```

### Issue: Windows from old project still visible

**Diagnosis**:
```bash
# Check which windows have marks
i3-msg -t get_tree | jq '.. | select(.marks != null) | {class: .window_properties.class, marks: .marks}'

# Check if project switch completed
project-logs --tail 20 | grep project-switch
```

**Solution**:
```bash
# Try switching again
pswitch nixos

# Or manually move windows to scratchpad
i3-msg '[con_mark="project:old"] move scratchpad'

# Check logs for errors
project-logs --level ERROR
```

### Issue: Project directory doesn't exist

**Symptom**: Warning when switching projects or launching apps

**Diagnosis**:
```bash
# Check project configuration
jq '.project.directory' ~/.config/i3/projects/PROJECT_NAME.json

# Verify directory exists
ls -ld /path/to/project
```

**Solution**:
```bash
# Create missing directory
mkdir -p /path/to/project

# Or update project configuration
# Edit ~/.config/i3/projects/PROJECT_NAME.json
# Change "directory" field to existing path
```

### Issue: Can't find project-logs command

**Diagnosis**:
```bash
# Check if logs exist
ls -lh ~/.config/i3/project-system.log

# Check if command is in PATH
which project-logs
```

**Solution**:
```bash
# View logs manually
tail -f ~/.config/i3/project-system.log

# Filter by level
grep '\[ERROR\]' ~/.config/i3/project-system.log

# Filter by component
grep '\[project-switch\]' ~/.config/i3/project-system.log
```

---

## Advanced Usage

### Custom Workspace Layouts (Future Enhancement)

Projects can specify custom i3 workspace layouts using `append_layout`:

**Example layout file** (`~/.config/i3/layouts/coding.json`):
```json
{
  "border": "normal",
  "layout": "splith",
  "percent": 0.5,
  "type": "con",
  "marks": ["project:nixos"],
  "swallows": [
    {
      "class": "^Code$"
    }
  ]
}
```

**Add to project configuration**:
```json
{
  "version": "1.0",
  "project": { ... },
  "workspaces": {
    "2": {
      "layout_file": "/home/user/.config/i3/layouts/coding.json"
    }
  }
}
```

When switching to this project, workspace 2 will load the layout and place matching windows.

### Multi-Monitor Workspace Assignment

Assign workspaces to specific monitors:

**Edit project configuration**:
```json
{
  "version": "1.0",
  "project": { ... },
  "workspaceOutputs": {
    "2": "HDMI-1",
    "3": "eDP-1",
    "4": "DP-1"
  }
}
```

**Find output names**:
```bash
i3-msg -t get_workspaces | jq '.[].output' | sort -u
```

### Debugging with Logs

**Enable debug mode**:
```bash
export I3_PROJECT_DEBUG=1
project-switch nixos
```

**View detailed logs**:
```bash
project-logs --tail 100 --level DEBUG

# Or manually
tail -100 ~/.config/i3/project-system.log | grep DEBUG
```

**Common log patterns**:

| Pattern | Meaning |
|---------|---------|
| `[INFO] [project-switch] Switching to project: X` | Project switch started |
| `[DEBUG] [i3-ipc] i3-msg -t get_tree` | Querying window state |
| `[DEBUG] [i3-cmd] i3-msg '[con_mark="..."]'` | Moving windows |
| `[WARN] [signal] i3blocks not running` | Status bar update failed |
| `[ERROR] [launch-code] code command not found` | Missing dependency |

---

## Best Practices

### 1. Use Short, Memorable Project Names

**Good**:
- `nixos`, `stacks`, `api`, `frontend`, `personal`

**Bad**:
- `my-super-long-project-name-2024`, `project1`, `temp`

### 2. Use Descriptive Display Names

**Good**:
- "NixOS Configuration", "Stacks Platform", "API Gateway"

**Bad**:
- "nixos", "proj", "stuff"

### 3. Choose Meaningful Icons

**Good**:
- `` for NixOS, `` for Stacks, `` for API
- Icons help visual identification in status bar and switcher

**Bad**:
- Random emojis (🚀, 🎉, 💻) without semantic meaning

### 4. Organize Projects by Purpose

**By Technology**:
- `nixos` - System configuration
- `rust-learning` - Rust projects
- `python-tools` - Python utilities

**By Client**:
- `client-a-api` - Client A backend
- `client-a-web` - Client A frontend
- `client-b` - Client B project

**By Domain**:
- `work` - Work projects
- `personal` - Personal projects
- `learning` - Educational projects

### 5. Keep Global Applications Minimal

Only make applications global if you **always** need them visible:
- ✅ Web browser (for documentation, testing)
- ✅ System monitors (k9s, htop)
- ✅ Communication tools (Slack, email)

Don't make global:
- ❌ Code editors (project-specific)
- ❌ Terminals (project-specific)
- ❌ File managers (project-specific)

### 6. Use Keyboard Shortcuts Over Commands

**Faster**:
```
Win+P → type "nixos" → Enter    (2 seconds)
```

**Slower**:
```
Ctrl+Shift+T → type "pswitch nixos" → Enter    (5 seconds)
```

### 7. Leverage Shell Aliases

**Instead of**:
```bash
project-switch nixos
project-list
project-current
```

**Use short aliases**:
```bash
pswitch nixos
plist
pcurrent
```

---

## Tips & Tricks

### Tip 1: Quick Project Creation

Create a template script for new projects:

```bash
#!/usr/bin/env bash
# ~/bin/create-code-project
NAME="$1"
DIR="$HOME/code/$NAME"

mkdir -p "$DIR"
cd "$DIR"
git init

project-create --name "$NAME" --dir "$DIR" --icon "" --display-name "$NAME"
pswitch "$NAME"
```

Usage:
```bash
create-code-project my-new-api
# Creates directory, initializes git, creates project, switches to it
```

### Tip 2: Batch Project Operations

List projects and switch based on directory:

```bash
# Switch to project based on current directory
current_dir=$(pwd)
project=$(jq -r --arg dir "$current_dir" '.project | select(.directory == $dir) | .name' ~/.config/i3/projects/*.json)
if [ -n "$project" ]; then
  pswitch "$project"
fi
```

### Tip 3: Project-Specific Terminal Sessions (tmux/sesh)

Combine with tmux or sesh for persistent terminal sessions:

```bash
# In launch-ghostty.sh (enhanced):
if [ -n "$project_name" ]; then
  # Start tmux session named after project
  ghostty --title "ghostty" --class="ghostty" -- tmux new-session -A -s "$project_name" -c "$project_dir"
else
  ghostty
fi
```

Now each project has its own tmux session that persists across switches.

### Tip 4: Auto-Switch Based on Git Repository

Create a hook to auto-switch when entering a directory:

```bash
# In ~/.bashrc or ~/.zshrc
cd() {
  builtin cd "$@"
  local project=$(jq -r --arg dir "$(pwd)" '.project | select(.directory == $dir) | .name' ~/.config/i3/projects/*.json 2>/dev/null)
  if [ -n "$project" ]; then
    local current=$(project-current 2>/dev/null | awk '{print $NF}' | tr -d '()')
    if [ "$current" != "$project" ]; then
      echo "Switching to project: $project"
      pswitch "$project"
    fi
  fi
}
```

Now `cd /etc/nixos` automatically switches to the nixos project.

---

## FAQ

**Q: Can I have multiple projects active at once?**
A: No, only one project can be active at a time. This is by design to maintain focus. Global applications remain visible across all projects.

**Q: What happens to windows when I delete a project?**
A: Windows with marks from the deleted project remain open but lose their marks. They become "global" windows. To close them, manually close each window.

**Q: Can I rename a project?**
A: Not directly. You must create a new project with the new name, then delete the old project. Consider using `--display-name` instead if you just want to change the visible name.

**Q: How do I back up my projects?**
A: Project configurations are in `~/.config/i3/projects/`. Back up this directory:
```bash
tar -czf i3-projects-backup.tar.gz ~/.config/i3/projects/
```

**Q: Can I share projects across multiple machines?**
A: Yes, but directory paths must be consistent. Use a dotfiles manager or sync `~/.config/i3/projects/` via git.

**Q: Do projects work with Wayland/sway?**
A: No, this system is i3-specific and uses i3 IPC. For sway (Wayland), a similar system would need to be built using sway IPC.

**Q: How many projects can I create?**
A: Practically unlimited, but the rofi switcher is optimized for 5-20 projects. More than 20 makes selection cumbersome.

**Q: What happens during i3 restart?**
A: i3 saves window marks and positions. After restart, the project system continues working normally. The active project file persists across restarts.

**Q: Can I use this with tiling window managers other than i3?**
A: No, the system is designed specifically for i3 and uses i3's mark system and IPC protocol.

---

## Next Steps

1. **Create your first 3 projects** for your most common workflows
2. **Practice keyboard shortcuts** (Win+P, Win+C, Win+Return)
3. **Customize application classifications** in `~/.config/i3/app-classes.json`
4. **Explore logs** with `project-logs` when troubleshooting
5. **Experiment with multi-monitor** workspace assignments

**Documentation**:
- Full specification: `/etc/nixos/specs/014-create-a-new/spec.md`
- Data model: `/etc/nixos/specs/014-create-a-new/data-model.md`
- Implementation plan: `/etc/nixos/specs/014-create-a-new/plan.md`

**Support**:
- Check logs: `project-logs --level ERROR`
- Review system state: `i3-msg -t get_tree | jq '.. | .marks'`
- NixOS rebuild: `sudo nixos-rebuild switch --flake .#hetzner`

---

**Version**: 1.0
**Last Updated**: 2025-10-19
**Feedback**: Report issues or suggestions via project logs and documentation
