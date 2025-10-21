# Quickstart Guide: i3pm (i3 Project Manager)

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## What is i3pm?

`i3pm` is a unified CLI/TUI tool for managing i3 window manager projects. It eliminates the need for manual JSON editing and provides an intuitive interface for:

- Creating and managing projects
- Associating applications and windows with projects
- Saving and restoring window layouts
- Switching between project contexts
- Monitoring project state in real-time

## Installation

### NixOS (Recommended)

Add to your NixOS configuration:

```nix
# flake.nix or configuration.nix
{
  imports = [
    ./home-modules/tools/i3-project-manager.nix
  ];

  home-manager.users.youruser = {
    programs.i3pm.enable = true;
  };
}
```

Rebuild:

```bash
sudo nixos-rebuild switch --flake .#<your-host>
```

### Manual Installation (Other Linux)

```bash
# Install dependencies
pip install textual rich i3ipc argcomplete

# Clone repository
git clone https://github.com/vpittamp/nixos.git
cd nixos

# Install package
pip install -e ./home-modules/tools/i3_project_manager

# Enable completions (bash)
eval "$(register-python-argcomplete i3pm)"
```

---

## First Run: Interactive TUI

Launch the TUI with no arguments:

```bash
i3pm
```

You'll see the **Project Browser** screen:

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ i3pm - Project Manager                              Active: None ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Search: _                                                        ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ No projects found. Press 'n' to create your first project.      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [n] New Project  [q] Quit                                        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Create Your First Project

Press `n` to open the **Project Wizard**:

#### Step 1: Basic Information

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 1 of 4: Basic Information                 ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                   ┃
┃ Project Name                                                     ┃
┃   [nixos__________]  ← Type: nixos                              ┃
┃                                                                   ┃
┃ Display Name (optional)                                          ┃
┃   [NixOS Config___]  ← Type: NixOS Config                       ┃
┃                                                                   ┃
┃ Icon (optional emoji)                                            ┃
┃   [❄️]              ← Type: ❄️                                    ┃
┃                                                                   ┃
┃ Project Directory                                                ┃
┃   [/etc/nixos_____] 📁  ← Type: /etc/nixos                      ┃
┃   ✓ Directory exists                                             ┃
┃                                                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Enter] Next Step  [Esc] Cancel                                  ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Fill in**:
- **Project Name**: `nixos` (filesystem-safe identifier)
- **Display Name**: `NixOS Config` (human-readable)
- **Icon**: `❄️` (optional emoji)
- **Directory**: `/etc/nixos` (must exist)

Press `Enter` to continue.

#### Step 2: Application Selection

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 2 of 4: Application Selection             ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                   ┃
┃ Select applications to scope to this project:                    ┃
┃                                                                   ┃
┃ Terminal Applications                                            ┃
┃   [x] Ghostty       ← Press Space to toggle                     ┃
┃   [ ] Alacritty                                                  ┃
┃                                                                   ┃
┃ Editors                                                          ┃
┃   [x] Code (Visual Studio Code)  ← Press Space to toggle        ┃
┃   [ ] neovide                                                    ┃
┃                                                                   ┃
┃ Browsers                                                         ┃
┃   [ ] firefox                                                    ┃
┃   [ ] Google-chrome                                              ┃
┃                                                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Space] Toggle  [↑↓] Navigate  [Enter] Next  [Esc] Back         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Select**:
- `[x]` Ghostty (terminal)
- `[x]` Code (editor)

These applications will be hidden when you switch away from this project.

Press `Enter` to continue.

#### Step 3: Auto-Launch (Optional)

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 3 of 4: Auto-Launch (Optional)            ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                   ┃
┃ Application 1                                                    ┃
┃   Command:   [ghostty________]  ← Type: ghostty                 ┃
┃   Workspace: [1_]                                                ┃
┃                                                                   ┃
┃ Application 2                                                    ┃
┃   Command:   [code /etc/nixos_]  ← Type: code /etc/nixos        ┃
┃   Workspace: [2_]                                                ┃
┃                                                                   ┃
┃ [Skip this step]                                                 ┃
┃                                                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [s] Skip  [Enter] Next  [Esc] Back                              ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Optional**: Configure applications to launch automatically:
- App 1: `ghostty` on workspace 1
- App 2: `code /etc/nixos` on workspace 2

Press `s` to skip, or `Enter` to continue.

#### Step 4: Review & Create

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 4 of 4: Review                            ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                   ┃
┃ Project: nixos                                                   ┃
┃   Display Name: NixOS Config                                     ┃
┃   Icon: ❄️                                                        ┃
┃   Directory: /etc/nixos                                          ┃
┃                                                                   ┃
┃ Scoped Applications (2):                                         ┃
┃   • Ghostty                                                      ┃
┃   • Code                                                         ┃
┃                                                                   ┃
┃ Auto-Launch (2):                                                 ┃
┃   1. ghostty (workspace 1)                                       ┃
┃   2. code /etc/nixos (workspace 2)                               ┃
┃                                                                   ┃
┃ Configuration will be saved to:                                  ┃
┃   ~/.config/i3/projects/nixos.json                               ┃
┃                                                                   ┃
┃   [Create Project] [Cancel]                                      ┃
┃                                                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Enter] Create  [Esc] Cancel                                     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

Review and press `Enter` to create the project.

**Success**! You'll return to the browser with your new project:

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ i3pm - Project Manager                              Active: None ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Search: _                                                        ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ NAME      DIRECTORY        APPS  LAYOUTS  MODIFIED            ┃
┃ ❄️ nixos   /etc/nixos       2     0        Just now          * ┃
┃                                                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Enter] Switch  [e] Edit  [l] Layouts  [m] Monitor  [q] Quit    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## Common Tasks

### Switch to a Project

**TUI**: Press `Enter` on selected project in browser

**CLI**:
```bash
i3pm switch nixos

# Output:
# ✓ Switched to project: nixos
#   Directory: /etc/nixos
#   Launched: ghostty, code
```

**Result**:
- All Ghostty and Code windows are now marked with `project:nixos`
- Windows are shown on workspaces 1-10
- Auto-launch apps start on designated workspaces

### List All Projects

**CLI**:
```bash
i3pm list

# Output:
# NAME      DIRECTORY        APPS  LAYOUTS  MODIFIED
# nixos     /etc/nixos       2     0        2h ago
# stacks    ~/code/stacks    3     1        1d ago
```

**With JSON output**:
```bash
i3pm list --json

# Output:
# {
#   "projects": [
#     {
#       "name": "nixos",
#       "directory": "/etc/nixos",
#       "scoped_classes": ["Ghostty", "Code"],
#       "saved_layouts": []
#     }
#   ],
#   "total": 1
# }
```

### Check Current Project

**CLI**:
```bash
i3pm current

# Output:
# Active Project: nixos
#   Directory: /etc/nixos
#   Tracked Windows: 5
```

**Quiet mode (for scripts)**:
```bash
PROJECT=$(i3pm current --quiet)
echo $PROJECT  # Output: nixos
```

### Edit a Project

**TUI**: Press `e` in browser (opens editor screen)

**CLI**:
```bash
# Add scoped class
i3pm edit nixos --add-class firefox

# Update display name
i3pm edit nixos --display-name "NixOS Configuration"

# Interactive editor (TUI)
i3pm edit nixos --interactive
```

### Save Current Layout

**CLI**:
```bash
i3pm save-layout nixos default

# Output:
# ✓ Saved layout: nixos/default
#   Workspaces: 1, 2
#   Windows: 5
```

**TUI**: Press `l` in browser → Press `s` in layout manager

### Restore a Layout

**CLI**:
```bash
i3pm restore-layout nixos default

# Output:
# ✓ Restoring layout: nixos/default
#   Launching 5 windows...
#   ✓ ghostty (workspace 1)
#   ✓ code (workspace 2)
# ✓ Layout restored (5/5 windows launched)
```

**TUI**: Press `l` in browser → Select layout → Press `r`

### Monitor Daemon Status

**CLI**:
```bash
i3pm status

# Output:
# Daemon Status: Running
#   Uptime: 2h 34m
#   Active Project: nixos
#   Tracked Windows: 5
```

**TUI**: Press `m` in browser (opens monitor dashboard)

### Clear Active Project

**CLI**:
```bash
i3pm clear

# Output:
# ✓ Cleared active project (was: nixos)
#   Mode: Global
```

**Keybinding** (from i3 config):
```bash
# ~/.config/i3/config
bindsym $mod+Shift+p exec --no-startup-id i3pm clear
```

---

## CLI Quick Reference

### Project Management

```bash
i3pm create --name NAME --directory DIR --scoped-classes CLASS...
i3pm edit PROJECT [--add-class CLASS] [--interactive]
i3pm delete PROJECT [--force]
i3pm list [--sort FIELD] [--json]
i3pm show PROJECT [--json]
i3pm validate [PROJECT]
```

### Project Switching

```bash
i3pm switch PROJECT [--no-launch]
i3pm current [--quiet]
i3pm clear
```

### Layout Management

```bash
i3pm save-layout PROJECT LAYOUT_NAME [--overwrite]
i3pm restore-layout PROJECT LAYOUT_NAME [--close-existing]
i3pm list-layouts PROJECT
i3pm delete-layout PROJECT LAYOUT_NAME [--force]
i3pm export-layout PROJECT LAYOUT_NAME [--output FILE]
i3pm import-layout PROJECT LAYOUT_NAME FILE
```

### Monitoring

```bash
i3pm monitor [MODE]            # Launch TUI monitor
i3pm status [--json]           # Daemon status
i3pm events [--limit N] [-f]   # Recent events
i3pm windows [--project NAME]  # Tracked windows
```

### Configuration

```bash
i3pm config                    # Show config paths
i3pm app-classes list          # List app classifications
i3pm completions bash          # Generate completions
```

---

## TUI Keyboard Shortcuts

### Project Browser

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate project list |
| `Enter` | Switch to selected project |
| `e` | Edit selected project |
| `l` | Open layout manager |
| `m` | Open monitor dashboard |
| `n` | Create new project (wizard) |
| `d` | Delete selected project |
| `/` | Focus search input |
| `s` | Toggle sort order |
| `q` | Quit |

### Project Editor

| Key | Action |
|-----|--------|
| `Tab` | Next field |
| `Shift+Tab` | Previous field |
| `Ctrl+S` | Save changes |
| `Esc` | Cancel (discard changes) |

### Layout Manager

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate layout list |
| `s` | Save current layout |
| `r` | Restore selected layout |
| `d` | Delete selected layout |
| `e` | Export selected layout |
| `Esc` | Return to browser |

### Monitor Dashboard

| Key | Action |
|-----|--------|
| `Tab` | Switch tab (Live/Events/History/Tree) |
| `r` | Force refresh |
| `Esc` | Return to browser |

---

## Troubleshooting

### Daemon Not Running

**Symptom**:
```
✗ Daemon not running: Connection refused
```

**Solution**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Start daemon
systemctl --user start i3-project-event-listener

# Enable auto-start
systemctl --user enable i3-project-event-listener

# Check daemon logs
journalctl --user -u i3-project-event-listener -f
```

### Project Not Found

**Symptom**:
```
✗ Error: Project 'nixos' not found
Available projects: stacks, personal
```

**Solution**:
```bash
# List all projects
i3pm list

# Check project files
ls ~/.config/i3/projects/

# Create missing project
i3pm create --name nixos --directory /etc/nixos --scoped-classes Ghostty Code
```

### Directory Does Not Exist

**Symptom** (during project creation):
```
✗ Error: Project directory does not exist: /etc/nixos
```

**Solution**:
```bash
# Verify directory exists
ls -la /etc/nixos

# Use absolute path
i3pm create --name nixos --directory $(realpath /etc/nixos) --scoped-classes Ghostty
```

### Windows Not Auto-Marking

**Symptom**: Windows don't get `project:name` marks

**Solution**:
```bash
# Check daemon is running
i3pm status

# Check daemon events
i3pm events --limit 20 --type window

# Verify window class is in scoped_classes
i3pm show nixos

# Check global app classification
cat ~/.config/i3/app-classes.json

# Reload daemon config
systemctl --user restart i3-project-event-listener
```

### Layout Restore Fails

**Symptom**:
```
✓ Restoring layout: nixos/default
  Launching 5 windows...
  ✓ ghostty (workspace 1)
  ✗ obsolete-app (timeout)
✗ Layout restored (1/2 windows launched)
  Failed: 1 (timeout)
```

**Solution**:
```bash
# Edit layout to remove obsolete apps
i3pm export-layout nixos default --output ~/layout.json
vim ~/layout.json  # Remove obsolete windows
i3pm import-layout nixos default ~/layout.json --overwrite

# Or save a fresh layout
i3pm save-layout nixos default --overwrite
```

### TUI Not Responding

**Symptom**: TUI freezes or doesn't update

**Solution**:
```bash
# Kill and restart
pkill -9 i3pm
i3pm

# Check for background processes
ps aux | grep i3pm

# Clear cache
rm -rf ~/.cache/i3pm/
```

---

## Configuration Files

### Project Configuration

**Location**: `~/.config/i3/projects/nixos.json`

**Example**:
```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS Config",
  "icon": "❄️",
  "scoped_classes": ["Ghostty", "Code"],
  "workspace_preferences": {
    "1": "primary",
    "2": "secondary"
  },
  "auto_launch": [
    {
      "command": "ghostty",
      "workspace": 1,
      "env": {"PROJECT_DIR": "/etc/nixos"},
      "wait_for_mark": "project:nixos"
    }
  ],
  "saved_layouts": ["default"],
  "created_at": "2025-10-20T10:00:00Z",
  "modified_at": "2025-10-20T14:30:00Z"
}
```

### Global App Classification

**Location**: `~/.config/i3/app-classes.json`

**Example**:
```json
{
  "scoped_classes": ["Ghostty", "Code", "neovide"],
  "global_classes": ["firefox", "Google-chrome", "mpv"],
  "class_patterns": {
    "pwa-": "global",
    "terminal": "scoped",
    "editor": "scoped"
  }
}
```

---

## Integration with i3

### Keybindings

Add to `~/.config/i3/config`:

```bash
# Project management
bindsym $mod+p exec --no-startup-id rofi-i3-project-switch
bindsym $mod+Shift+p exec --no-startup-id i3pm clear

# Launch i3pm TUI
bindsym $mod+Ctrl+p exec --no-startup-id i3-sensible-terminal -e i3pm

# Project-scoped applications
bindsym $mod+Return exec --no-startup-id i3-project-launch ghostty
bindsym $mod+c exec --no-startup-id i3-project-launch "code $(i3pm current --quiet | xargs -I {} i3pm show {} --json | jq -r .directory)"
```

### Status Bar (i3bar + i3blocks)

Add to `~/.config/i3blocks/config`:

```ini
[project]
command=~/.config/i3blocks/scripts/project-status.sh
interval=5
```

**Script** (`~/.config/i3blocks/scripts/project-status.sh`):

```bash
#!/usr/bin/env bash
PROJECT=$(i3pm current --quiet 2>/dev/null)

if [ -n "$PROJECT" ]; then
  ICON=$(i3pm show "$PROJECT" --json 2>/dev/null | jq -r '.icon // ""')
  echo "$ICON $PROJECT"
else
  echo "—"
fi
```

---

## Advanced Usage

### Shell Aliases

Add to `~/.bashrc`:

```bash
# Project management aliases
alias pswitch='i3pm switch'
alias pcurrent='i3pm current'
alias pclear='i3pm clear'
alias plist='i3pm list'
alias pedit='i3pm edit'

# Jump to project directory
pcd() {
  DIR=$(i3pm show "$1" --json 2>/dev/null | jq -r '.directory')
  [ -n "$DIR" ] && cd "$DIR" || echo "Project not found: $1"
}

# Example: pcd nixos → cd /etc/nixos
```

### Shell Completions

**Bash**:
```bash
# Add to ~/.bashrc
eval "$(register-python-argcomplete i3pm)"
```

**Zsh**:
```bash
# Add to ~/.zshrc
autoload -U bashcompinit
bashcompinit
eval "$(register-python-argcomplete i3pm)"
```

### Tmux Integration

Launch project in tmux session:

```bash
#!/usr/bin/env bash
# ~/bin/project-tmux

PROJECT="$1"
if [ -z "$PROJECT" ]; then
  echo "Usage: project-tmux <project-name>"
  exit 1
fi

# Get project directory
DIR=$(i3pm show "$PROJECT" --json | jq -r '.directory')

# Switch i3pm project
i3pm switch "$PROJECT"

# Launch tmux session
tmux new-session -s "$PROJECT" -c "$DIR"
```

---

## Next Steps

1. **Create more projects** - Organize your work by project context
2. **Save layouts** - Capture your workspace setups for quick restoration
3. **Configure auto-launch** - Automate application launches when switching projects
4. **Explore the monitor** - Use `i3pm monitor` to debug and understand project state
5. **Customize keybindings** - Add i3 keybindings for quick project switching

For more details, see:
- [spec.md](./spec.md) - Full feature specification
- [UNIFIED_UX_DESIGN.md](./UNIFIED_UX_DESIGN.md) - Detailed UX design
- [contracts/cli-interface.md](./contracts/cli-interface.md) - Complete CLI reference
- [contracts/tui-screens.md](./contracts/tui-screens.md) - TUI screen documentation

---

**Questions or Issues?**
- Check troubleshooting section above
- Review daemon logs: `journalctl --user -u i3-project-event-listener -f`
- Validate configuration: `i3pm validate`
- File issues on GitHub repository

**Happy project managing!** 🎯
