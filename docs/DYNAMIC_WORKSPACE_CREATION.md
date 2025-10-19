# Dynamic Workspace Creation

## Overview

Create and configure i3 workspaces dynamically **without NixOS rebuilds** using `i3-msg`, `xdotool`, and bash scripts. This approach allows instant workspace setup while maintaining the benefits of declarative configuration when desired.

## Key Insight

i3 workspaces are **created on-demand** when you:
1. Switch to them: `i3-msg "workspace number N"`
2. Launch applications on them: `i3-msg "exec --no-startup-id app"`
3. Move windows to them: `i3-msg "move container to workspace number N"`

**No rebuild required** - these commands work immediately!

## Available Tools

### 1. Quick Demo Script

**Location:** `/etc/nixos/scripts/demo-workspace-setup.sh`

Opens VSCode on workspace 4 and Ghostty on workspace 2:

```bash
/etc/nixos/scripts/demo-workspace-setup.sh
```

**What it does:**
- Switches to workspace 2
- Launches Ghostty
- Switches to workspace 4
- Launches VSCode
- Returns to workspace 2
- Shows workspace status

### 2. Single-App Launcher

**Location:** `/etc/nixos/scripts/workspace-launcher.sh`

Launch any application on a specific workspace:

```bash
# Basic usage
workspace-launcher.sh <app> <workspace> [args...]

# Examples
workspace-launcher.sh ghostty 2
workspace-launcher.sh code 4
workspace-launcher.sh firefox 3 --new-window https://github.com
workspace-launcher.sh "ghostty --class=floating_terminal" 5
```

**Features:**
- Instant execution (no rebuild)
- Automatic workspace switching
- Application argument support
- Desktop notifications
- Error handling

### 3. Multi-App Project Launcher

**Location:** `/etc/nixos/scripts/workspace-project.sh`

Launch multiple apps across multiple workspaces from a JSON definition:

```bash
workspace-project.sh /etc/nixos/examples/example-project.json
```

**Features:**
- JSON-based project definitions
- Multi-workspace support
- Launch delays for timing
- Dry-run mode: `DRY_RUN=true workspace-project.sh project.json`

## Project Definition Format

Create a JSON file (anywhere on your system):

```json
{
  "name": "my-dev-environment",
  "description": "Full development setup",
  "workspaces": [
    {
      "number": 1,
      "apps": [
        {
          "command": "firefox",
          "args": ["--new-window", "http://localhost:3000"],
          "delay": 0
        }
      ]
    },
    {
      "number": 2,
      "apps": [
        {
          "command": "ghostty",
          "args": [],
          "delay": 0
        },
        {
          "command": "ghostty",
          "args": ["--class=floating_terminal"],
          "delay": 500
        }
      ]
    },
    {
      "number": 4,
      "apps": [
        {
          "command": "code",
          "args": ["/path/to/project"],
          "delay": 1000
        }
      ]
    }
  ]
}
```

**Field explanations:**
- `name`: Project identifier
- `description`: Human-readable description (optional)
- `workspaces[]`: Array of workspace configurations
  - `number`: Workspace number (1-10 typical)
  - `apps[]`: Applications to launch
    - `command`: Binary or command to execute
    - `args`: Array of command-line arguments (can be empty)
    - `delay`: Milliseconds to wait before launching (0 = immediate)

## Example Use Cases

### 1. Development Environment

```json
{
  "name": "nixos-dev",
  "workspaces": [
    {
      "number": 1,
      "apps": [
        {"command": "code", "args": ["/etc/nixos"], "delay": 0}
      ]
    },
    {
      "number": 2,
      "apps": [
        {"command": "ghostty", "args": [], "delay": 0}
      ]
    },
    {
      "number": 3,
      "apps": [
        {"command": "firefox", "args": ["--new-window", "https://nixos.org/manual"], "delay": 0}
      ]
    }
  ]
}
```

### 2. Video Conferencing Setup

```json
{
  "name": "meeting",
  "workspaces": [
    {
      "number": 1,
      "apps": [
        {"command": "slack", "args": [], "delay": 0}
      ]
    },
    {
      "number": 2,
      "apps": [
        {"command": "zoom", "args": [], "delay": 0}
      ]
    },
    {
      "number": 3,
      "apps": [
        {"command": "firefox", "args": ["--new-window", "https://meet.google.com"], "delay": 0}
      ]
    }
  ]
}
```

### 3. Monitoring Dashboard

```json
{
  "name": "monitoring",
  "workspaces": [
    {
      "number": 8,
      "apps": [
        {"command": "btop", "args": [], "delay": 0},
        {"command": "journalctl", "args": ["-f"], "delay": 500}
      ]
    }
  ]
}
```

## Command-Line i3 Workspace Operations

Direct i3-msg commands for manual workspace management:

### Basic Workspace Operations

```bash
# Switch to workspace
i3-msg "workspace number 4"

# Create and switch to workspace
i3-msg "workspace number 9"

# Move current window to workspace
i3-msg "move container to workspace number 5"

# Launch app on current workspace
i3-msg "exec --no-startup-id code"

# Combined: switch and launch
i3-msg "workspace number 4; exec --no-startup-id code"
```

### Query Workspace State

```bash
# List all workspaces (JSON)
i3-msg -t get_workspaces

# Pretty print workspace info
i3-msg -t get_workspaces | jq -r '.[] | "Workspace \(.num): \(.name) - focused: \(.focused)"'

# Get windows on workspace 4
i3-msg -t get_tree | jq '.. | select(.type? == "workspace" and .num? == 4) | .nodes[] | select(.window_properties?) | .window_properties.class'

# Count windows per workspace
for ws in {1..9}; do
  count=$(i3-msg -t get_tree | jq -r ".. | select(.type? == \"workspace\" and .num? == $ws) | .nodes[] | select(.window_properties?)" | jq -s 'length')
  echo "Workspace $ws: $count windows"
done
```

### Window Management

```bash
# Focus specific window by class
i3-msg '[class="Code"] focus'

# Move window to workspace
i3-msg '[class="Firefox"] move container to workspace number 3'

# Float specific window
i3-msg '[class="floating_terminal"] floating enable'

# Tile all floating windows
i3-msg '[floating] floating toggle'
```

## Integration with Existing System

### Add to i3 Keybindings

Edit `/etc/nixos/home-modules/desktop/i3.nix`:

```nix
# Launch demo setup
bindsym $mod+Shift+p exec /etc/nixos/scripts/demo-workspace-setup.sh

# Launch custom project
bindsym $mod+Shift+o exec /etc/nixos/scripts/workspace-project.sh ~/.config/i3-projects/my-project.json
```

Then rebuild: `sudo nixos-rebuild switch --flake .#hetzner`

### Create Shell Aliases

Add to `~/.bashrc` or `/etc/nixos/home-modules/shell/bash.nix`:

```bash
alias ws-setup='/etc/nixos/scripts/demo-workspace-setup.sh'
alias ws-launch='/etc/nixos/scripts/workspace-launcher.sh'
alias ws-project='/etc/nixos/scripts/workspace-project.sh'
```

### FZF Project Launcher

Combine with FZF for interactive project selection:

```bash
#!/usr/bin/env bash
# Pick and launch a project workspace

PROJECT_DIR="$HOME/.config/i3-projects"
PROJECT=$(find "$PROJECT_DIR" -name "*.json" -type f | \
  fzf --preview 'jq -C . {}' --preview-window=right:60%)

[[ -n "$PROJECT" ]] && /etc/nixos/scripts/workspace-project.sh "$PROJECT"
```

## Comparison: Dynamic vs Declarative

| Aspect | Dynamic (Scripts) | Declarative (NixOS) |
|--------|------------------|---------------------|
| **Setup Time** | Instant | Requires rebuild (~2-5 min) |
| **Flexibility** | Edit JSON, run script | Edit .nix, rebuild |
| **Persistence** | Manual each session | Automatic on startup |
| **Version Control** | Easy (JSON files) | Built-in (git) |
| **Testing** | Immediate | Test with dry-build first |
| **Best For** | Ad-hoc setups, experimentation | Permanent configurations |

## Best Practices

### When to Use Dynamic Scripts

1. **Experimenting** with workspace layouts
2. **One-off** project setups
3. **Quick demos** or presentations
4. **Testing** before committing to declarative config
5. **User-specific** setups not suitable for system config

### When to Use Declarative NixOS Config

1. **Permanent** workspace assignments
2. **System-wide** defaults
3. **Consistent** environment across machines
4. **Automated** setup on every login
5. **Version-controlled** team configurations

### Hybrid Approach (Recommended)

1. Use **declarative config** for core workspaces (1-4)
2. Use **dynamic scripts** for project-specific setups (5-9)
3. Keep **project definitions** in `~/.config/i3-projects/`
4. Version control both NixOS config and project JSON files

## Advanced Techniques

### Workspace Templates

Create reusable templates:

```bash
# Template function
create_dev_workspace() {
    local workspace=$1
    local project_path=$2

    i3-msg "workspace number $workspace"
    sleep 0.1
    i3-msg "exec --no-startup-id code $project_path"
    i3-msg "exec --no-startup-id ghostty"
}

# Use it
create_dev_workspace 5 "/home/user/myproject"
```

### Conditional Launches

Only launch if not already running:

```bash
# Check if app is running
if ! wmctrl -lx | grep -i "code"; then
    i3-msg "workspace number 4; exec --no-startup-id code"
fi
```

### Layout Restoration

Save and restore window layouts:

```bash
# Save layout
i3-save-tree --workspace 4 > ~/.config/i3/workspace-4-layout.json

# Load layout (requires window matching setup)
i3-msg "workspace 4; append_layout ~/.config/i3/workspace-4-layout.json"
```

## Troubleshooting

### Applications Not Launching

```bash
# Verify i3 connection
i3-msg -t get_version

# Check if command exists
which code ghostty firefox

# Test launch manually
i3-msg "exec --no-startup-id code" && echo "Success"
```

### Windows Appear on Wrong Workspace

```bash
# Application might have window assignment rules
grep -r "assign" ~/.config/i3/
grep -r "for_window" ~/.config/i3/

# Override with move command
i3-msg '[class="Code"] move container to workspace number 4'
```

### Timing Issues

Increase delays in project JSON or add sleeps:

```bash
i3-msg "workspace number 4"
sleep 0.2  # Give i3 time to switch
i3-msg "exec --no-startup-id code"
```

## Files Reference

| File | Purpose |
|------|---------|
| `/etc/nixos/scripts/demo-workspace-setup.sh` | Quick demo: VSCode + Ghostty |
| `/etc/nixos/scripts/workspace-launcher.sh` | Single-app launcher |
| `/etc/nixos/scripts/workspace-project.sh` | Multi-app project launcher |
| `/etc/nixos/examples/example-project.json` | Example project definition |
| `/etc/nixos/home-modules/desktop/i3-projects.nix` | Declarative project module |
| `/etc/nixos/modules/desktop/i3-project-workspace.nix` | System-level tools |

## Next Steps

1. **Try the demo:** `./scripts/demo-workspace-setup.sh`
2. **Create your first project:** Copy and edit `examples/example-project.json`
3. **Add keybindings:** Bind scripts to i3 shortcuts
4. **Automate:** Add to shell aliases or launcher scripts

---

_Last updated: 2025-10-18_
