# Quickstart Guide: Unified Application Launcher

**Feature**: 034-create-a-feature
**Version**: 1.0.0
**Date**: 2025-10-24
**Estimated Reading Time**: 10 minutes

## Overview

This guide will help you start using the unified application launcher system within 10 minutes. You'll learn how to launch applications, add new ones to the registry, and understand project-aware launching.

## Prerequisites

- NixOS system with i3 window manager
- home-manager configured
- i3pm daemon running (Feature 015)
- Active feature branch: `034-create-a-feature`

**Verify Prerequisites**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check current branch
git branch --show-current  # Should show: 034-create-a-feature

# Verify i3pm CLI installed
which i3pm
```

## Quick Start (5 Minutes)

### 1. Launch Applications from rofi

**Default Keybinding**: `Win+D`

```bash
# Press Win+D to open launcher
# Type application name (e.g., "VS Code")
# Press Enter to launch
```

**What Happens**:
1. rofi shows all applications from `~/.local/share/applications/`
2. You select an application
3. Desktop file invokes `app-launcher-wrapper.sh <app-name>`
4. Wrapper queries i3pm daemon for active project
5. Wrapper substitutes `$PROJECT_DIR` and other variables
6. Application launches in project context

### 2. Launch from Command Line

```bash
# List available applications
i3pm apps list

# Launch VS Code in active project
i3pm apps launch vscode

# Launch with dry-run (show command without executing)
i3pm apps launch vscode --dry-run
```

### 3. Check Application Info

```bash
# Show application details
i3pm apps info vscode

# Show with resolved variables for current context
i3pm apps info vscode --resolve
```

**Example Output**:
```
Application: VS Code
Name: vscode
Command: code
Parameters: $PROJECT_DIR
Scope: scoped
Expected Class: Code
Preferred Workspace: 1

Current Context:
  Active Project: nixos
  Project Directory: /etc/nixos
  Resolved Command: code /etc/nixos
```

## Core Concepts

### Project-Aware Launching

**Scoped Applications** (project-aware):
- VS Code → Opens in active project directory
- Ghostty Terminal → Opens with project sesh session
- Lazygit → Opens with project repository

**Global Applications** (always visible):
- Firefox → No project context
- PWAs (YouTube, Claude) → Always available
- System tools → Independent of projects

### Variable Substitution

Applications can use variables in their launch parameters:

| Variable | Example Value | Description |
|----------|---------------|-------------|
| `$PROJECT_DIR` | `/etc/nixos` | Active project directory |
| `$PROJECT_NAME` | `nixos` | Active project name |
| `$SESSION_NAME` | `nixos` | Sesh/tmux session name |
| `$WORKSPACE` | `1` | Target workspace number |

**Example**:
```json
{
  "name": "vscode",
  "command": "code",
  "parameters": "$PROJECT_DIR"
}
```

When launching with `nixos` project active:
```bash
# Resolves to:
code /etc/nixos
```

## Common Workflows

### Workflow 1: Start Working on a Project

```bash
# 1. Switch to project
pswitch nixos  # Or: Win+P → select "nixos"

# 2. Launch applications
Win+D → "VS Code" → Enter
Win+Return  # Ghostty terminal with sesh session

# 3. Check project context
pcurrent  # Shows: nixos (/etc/nixos)
```

**Result**:
- VS Code opens to `/etc/nixos`
- Terminal opens with sesh session `nixos` in `/etc/nixos`
- All scoped applications show on screen
- Global applications (Firefox) remain visible

### Workflow 2: Add a New Application

**Interactive**:
```bash
i3pm apps add
```

**Follow prompts**:
```
Application name: yazi
Display name: Yazi File Manager
Executable command: yazi
Parameters: $PROJECT_DIR
Scope: scoped
Expected WM_CLASS: yazi
Preferred workspace: 4
Icon: folder
Package: pkgs.yazi
Multi-instance: y
Fallback: skip

Add this application? [Y/n]: y
```

**Rebuild System**:
```bash
sudo nixos-rebuild switch --flake .#hetzner
```

**Launch New Application**:
```bash
Win+D → "Yazi File Manager" → Enter
# Or: i3pm apps launch yazi
```

### Workflow 3: Debug a Failed Launch

**Problem**: Application doesn't launch or opens in wrong directory

**Steps**:

1. **Check launch log**:
   ```bash
   tail -f ~/.local/state/app-launcher.log
   ```

2. **Dry-run launch**:
   ```bash
   i3pm apps launch vscode --dry-run
   ```

3. **Check project context**:
   ```bash
   pcurrent  # Shows active project
   i3pm project current --json  # Full details
   ```

4. **Check daemon**:
   ```bash
   i3pm daemon status
   systemctl --user status i3-project-event-listener
   ```

5. **Check application definition**:
   ```bash
   i3pm apps info vscode
   ```

6. **Validate registry**:
   ```bash
   i3pm apps validate --check-paths --check-icons
   ```

## Registry Management

### View Current Registry

```bash
# List all applications
i3pm apps list

# Show specific application
i3pm apps info vscode

# List scoped applications only
i3pm apps list --scope=scoped

# List applications on workspace 1
i3pm apps list --workspace=1
```

### Edit Registry

**Method 1: Interactive CLI**:
```bash
i3pm apps add         # Add new application
i3pm apps remove vscode --force  # Remove application
```

**Method 2: Direct Edit**:
```bash
i3pm apps edit  # Opens in $EDITOR

# After saving:
sudo nixos-rebuild switch --flake .#hetzner
```

**Method 3: Nix Configuration** (recommended):
```nix
# In home-modules/desktop/app-registry.nix
{
  applications = [
    {
      name = "vscode";
      display_name = "VS Code";
      command = "code";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Code";
      preferred_workspace = 1;
      icon = "vscode";
      nix_package = "pkgs.vscode";
    }
    # ... more applications
  ];
}
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#hetzner
```

### Validate Registry

```bash
# Basic validation
i3pm apps validate

# Full validation (check paths and icons)
i3pm apps validate --check-paths --check-icons

# Auto-fix common issues
i3pm apps validate --fix
```

## Keybindings

### Default i3 Keybindings

| Keybinding | Action | Details |
|------------|--------|---------|
| `Win+D` | Open launcher | Shows all applications in rofi |
| `Win+C` | Launch VS Code | Opens in active project |
| `Win+Return` | Launch Terminal | Ghostty with sesh session |
| `Win+G` | Launch Lazygit | Opens in project repository |
| `Win+Y` | Launch Yazi | File manager in project directory |
| `Win+P` | Switch Project | Opens project switcher |
| `Win+Shift+P` | Clear Project | Return to global mode |

### Custom Keybindings

Add to i3 config:
```bash
# Launch application by name
bindsym $mod+Shift+c exec app-launcher-wrapper.sh <app-name>

# Or via CLI
bindsym $mod+Shift+c exec i3pm apps launch <app-name>
```

## Troubleshooting

### Application Not Found in Launcher

**Symptoms**: Application doesn't appear in rofi

**Causes & Solutions**:

1. **Desktop file not generated**:
   ```bash
   # Check if desktop file exists
   ls ~/.local/share/applications/vscode.desktop

   # If missing, rebuild
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. **Application not in registry**:
   ```bash
   i3pm apps list  # Check if application listed
   i3pm apps add   # Add if missing
   ```

3. **rofi cache issue**:
   ```bash
   # Clear rofi cache
   rm -rf ~/.cache/rofi
   ```

### Application Opens in Wrong Directory

**Symptoms**: Application launches but not in project directory

**Causes & Solutions**:

1. **No active project**:
   ```bash
   pcurrent  # Check active project
   pswitch nixos  # Activate project
   ```

2. **Wrong variable in parameters**:
   ```bash
   i3pm apps info vscode
   # Check Parameters field shows $PROJECT_DIR
   ```

3. **Invalid project directory**:
   ```bash
   cat ~/.config/i3/projects/nixos.json
   # Verify "directory" field is correct
   ```

4. **Daemon not running**:
   ```bash
   systemctl --user restart i3-project-event-listener
   ```

### Command Not Found Error

**Symptoms**: "Command not found: code"

**Causes & Solutions**:

1. **Package not installed**:
   ```bash
   # Check if command in PATH
   which code

   # Install package
   nix-shell -p vscode --run "which code"
   ```

2. **Package reference wrong**:
   ```bash
   i3pm apps info vscode
   # Check nix_package field
   # Should be: pkgs.vscode
   ```

3. **PATH not updated**:
   ```bash
   # Logout/login to refresh PATH
   # Or source profile:
   source ~/.profile
   ```

### Variable Not Substituting

**Symptoms**: Literal `$PROJECT_DIR` in command instead of path

**Causes & Solutions**:

1. **Check wrapper script exists**:
   ```bash
   ls -la ~/.local/bin/app-launcher-wrapper.sh
   # Should be executable (755)
   ```

2. **Check parameters format**:
   ```bash
   i3pm apps info vscode
   # Parameters should be: $PROJECT_DIR
   # NOT: ${PROJECT_DIR} or \$PROJECT_DIR
   ```

3. **Check launch log**:
   ```bash
   tail ~/.local/state/app-launcher.log
   # Look for substitution details
   ```

## Advanced Usage

### Custom Fallback Behavior

When no project is active, control what happens:

```json
{
  "name": "vscode",
  "fallback_behavior": "skip"  // Options: skip, use_home, error
}
```

**Options**:
- `skip`: Launch without parameter (VS Code opens last workspace)
- `use_home`: Substitute `$HOME` for `$PROJECT_DIR` (opens home directory)
- `error`: Show error and abort launch (for critical project-dependent tools)

### Multiple Variable Substitution

```json
{
  "name": "custom-tool",
  "command": "my-tool",
  "parameters": "--dir=$PROJECT_DIR --name=$PROJECT_NAME --session=$SESSION_NAME"
}
```

**Resolves to** (with `nixos` project active):
```bash
my-tool --dir=/etc/nixos --name=nixos --session=nixos
```

### Window Rules Integration

Applications in the registry automatically generate window rules:

```bash
# Generated rule for VS Code:
{
  "pattern_rule": {
    "pattern": "Code",
    "scope": "scoped",
    "priority": 240,
    "description": "VS Code - WS1"
  },
  "workspace": 1
}
```

**Effect**:
- Windows with WM_CLASS="Code" are classified as scoped
- New VS Code windows auto-move to workspace 1
- VS Code windows hide when switching away from their project

**Override** (manual rule with higher priority):
```bash
# Edit manual rules
vi ~/.config/i3/window-rules-manual.json

# Add:
{
  "pattern_rule": {
    "pattern": "Code",
    "priority": 250,  # Higher than generated (240)
    "scope": "global"  # Override to global
  },
  "workspace": 2  # Different workspace
}
```

## Next Steps

### Migrate Existing Launch Scripts

**Before**: Custom scripts in i3 config
```bash
# Old approach
bindsym $mod+c exec ~/.local/bin/launch-code.sh
```

**After**: Registry-based launching
```bash
# Add to registry
i3pm apps add --non-interactive \
  --name=vscode \
  --display-name="VS Code" \
  --command=code \
  --parameters='$PROJECT_DIR' \
  --scope=scoped \
  --workspace=1

# Update i3 config
bindsym $mod+c exec i3pm apps launch vscode

# Remove old script
rm ~/.local/bin/launch-code.sh

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner
```

### Explore Registry Examples

```bash
# See example applications
cat ~/.config/i3/application-registry.json | jq '.applications[]'

# See scoped applications
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.scope == "scoped")'

# See applications on workspace 1
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.preferred_workspace == 1)'
```

### Configure More Applications

**Recommendations**:
- **Scoped**: Editors (VS Code, Neovim), terminals, file managers, git UIs
- **Global**: Browsers, communication apps, media players, system monitors

**Examples to Add**:
```bash
# Neovim in terminal
i3pm apps add --name=nvim --display-name="Neovim" \
  --command=ghostty --parameters="-e nvim $PROJECT_DIR" \
  --scope=scoped --workspace=1

# File manager
i3pm apps add --name=thunar --display-name="Thunar" \
  --command=thunar --parameters='$PROJECT_DIR' \
  --scope=scoped --workspace=4

# Browser (global)
i3pm apps add --name=firefox --display-name="Firefox" \
  --command=firefox --scope=global --workspace=2
```

## Getting Help

**Documentation**:
- Full specification: `/etc/nixos/specs/034-create-a-feature/spec.md`
- Implementation plan: `/etc/nixos/specs/034-create-a-feature/plan.md`
- Data model: `/etc/nixos/specs/034-create-a-feature/data-model.md`
- Research findings: `/etc/nixos/specs/034-create-a-feature/research.md`

**Contracts**:
- Registry schema: `/etc/nixos/specs/034-create-a-feature/contracts/registry-schema.json`
- CLI API: `/etc/nixos/specs/034-create-a-feature/contracts/cli-api.md`
- Launcher protocol: `/etc/nixos/specs/034-create-a-feature/contracts/launcher-protocol.md`

**Logs & Diagnostics**:
```bash
# Application launches
tail -f ~/.local/state/app-launcher.log

# Daemon events
i3pm daemon events --follow

# Window state
i3pm windows --live

# System logs
journalctl --user -u i3-project-event-listener -f
```

**Commands**:
```bash
# Show help
i3pm apps --help
i3pm apps list --help
i3pm apps launch --help

# Validate everything
i3pm apps validate --check-paths --check-icons
i3pm daemon status
i3pm project current
```

## Summary

**You've learned**:
- ✅ How to launch applications from rofi and CLI
- ✅ How project-aware launching works
- ✅ How to add new applications to the registry
- ✅ How to troubleshoot launch issues
- ✅ How variable substitution works
- ✅ How to migrate from custom launch scripts

**Key Commands**:
```bash
i3pm apps list              # List applications
i3pm apps launch <name>     # Launch application
i3pm apps info <name>       # Show application details
i3pm apps add               # Add new application
i3pm apps validate          # Validate registry
pcurrent                    # Show active project
pswitch <project>           # Switch project
```

**Next**: Customize your registry with project-aware applications!

---

**Quickstart Status**: ✅ COMPLETE
**Estimated Setup Time**: 10 minutes from rebuild to first project-aware launch
