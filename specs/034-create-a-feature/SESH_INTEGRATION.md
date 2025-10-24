# Sesh Integration with Application Launcher

**Feature**: 034-create-a-feature
**Enhancement**: Terminal sesh session integration
**Date**: 2025-10-24

## Overview

Integrated sesh session manager with the unified application launcher, enabling automatic connection to project-specific tmux sessions when launching terminals.

**Key Feature**: Uses directory paths directly with `sesh connect $PROJECT_DIR` - no predefined sessions needed! Sesh automatically creates and manages sessions for any directory.

## Changes Made

### 1. Application Registry Updates

**Added/Updated Entries:**

#### Ghostty Terminal (Scoped)
```nix
name = "ghostty"
command = "ghostty -e sesh connect $PROJECT_DIR"
scope = "scoped"
fallback_behavior = "error"
description = "Terminal with automatic sesh session for project directory"
```

**Behavior:**
- **With project active**: Launches Ghostty and automatically connects to sesh session for project directory (e.g., `sesh connect /etc/nixos`)
- **Without project**: Shows error message requiring project context (use "terminal" entry instead)
- **Session naming**: Sesh automatically creates sessions named after the directory path
- **No configuration needed**: Works with any project directory automatically

#### Terminal Selector (Global)
```nix
name = "terminal"
command = "ghostty -e sesh"
scope = "global"
fallback_behavior = "skip"
description = "Terminal with sesh session selector"
```

**Behavior:**
- **Always available**: No project context required
- **Interactive selector**: Shows all available sessions (tmux, config, tmuxinator, zoxide)
- **Use case**: Start new session, choose different session, work without project

#### Neovim (Updated)
```nix
name = "neovim"
command = "ghostty -e bash -c 'cd $PROJECT_DIR && nvim'"
scope = "scoped"
fallback_behavior = "use_home"
```

**Behavior:**
- Opens in project directory
- Falls back to $HOME if no project active

### 2. i3 Keybinding Updates

Updated all project-aware keybindings to use the unified launcher:

```i3
# Project-aware (requires active project)
bindsym $mod+Return exec ~/.local/bin/app-launcher-wrapper.sh ghostty
bindsym $mod+c      exec ~/.local/bin/app-launcher-wrapper.sh vscode
bindsym $mod+g      exec ~/.local/bin/app-launcher-wrapper.sh lazygit
bindsym $mod+y      exec ~/.local/bin/app-launcher-wrapper.sh yazi
bindsym $mod+b      exec ~/.local/bin/app-launcher-wrapper.sh btop

# Global terminal selector (no project required)
bindsym $mod+Shift+Return exec ~/.local/bin/app-launcher-wrapper.sh terminal
```

### 3. Bug Fixes

- Fixed `pkgs.alacritty` → `pkgs.ghostty` in nix_package field
- Added `${pkgs.gawk}/bin` to firefox-pwas-declarative.nix PATH

## Usage Guide

### Launching Terminals with Sesh

#### Option 1: With Active Project (Win+Return)

```bash
# 1. Switch to a project
pswitch nixos

# 2. Press Win+Return (or: i3pm apps launch ghostty)
# Result: Ghostty opens with "sesh connect /etc/nixos"
# - Connects to existing tmux session for /etc/nixos
# - Or creates new session if doesn't exist
# - Session automatically named based on directory (typically "nixos" or "etc-nixos")
# - Automatically starts in /etc/nixos directory
```

#### Option 2: Interactive Selector (Win+Shift+Return)

```bash
# Press Win+Shift+Return (or: i3pm apps launch terminal)
# Result: Ghostty opens with sesh's interactive selector
# - Shows all available sessions
# - Can choose any session (not limited to current project)
# - Can create new session
# - Can browse zoxide directories
```

#### Option 3: From rofi Launcher (Win+D)

```bash
# Press Win+D
# Type "ghost" or "term"
# See two options:
#   - "Ghostty Terminal [WS3 - ...]" (requires project)
#   - "Terminal (Sesh Selector) [WS3 - ...]" (always available)
```

#### Option 4: From CLI

```bash
# With project context
pswitch nixos
i3pm apps launch ghostty

# Without project (interactive selector)
i3pm apps launch terminal

# Dry run to see command
i3pm apps launch ghostty --dry-run
```

## Sesh Session Configuration

Configured in `home-modules/terminal/sesh.nix`:

### Automatic Directory-Based Sessions

**No predefined sessions needed!** Sesh automatically creates sessions based on directory paths.

When you run `sesh connect /path/to/directory`, sesh will:
1. Create or connect to a tmux session for that directory
2. Session name is derived from the directory path
3. Automatically changes to that directory
4. Session persists even after closing terminal

### Adding New Projects

To use sesh with a new project:

1. **Create i3pm project** (for window management):
```bash
i3pm project create --name myproject --dir /path/to/myproject
```

2. **That's it!** No sesh configuration needed.

3. **Use it:**
```bash
pswitch myproject
# Press Win+Return
# Ghostty automatically runs: sesh connect /path/to/myproject
# Session created automatically if it doesn't exist
```

### Optional: Customize Default Behavior

You can customize default behavior in `sesh.nix`:

```nix
default_session = {
  startup_command = "";  # Command to run in new sessions
  preview_command = "eza --all --git --icons --color=always --group-directories-first --long {}";
};
```

This applies to **all** sessions created by sesh, not just specific projects.

## Workflow Examples

### Example 1: Start Working on NixOS Project

```bash
# 1. Switch project
pswitch nixos

# 2. Launch terminal (Win+Return or i3pm apps launch ghostty)
# Automatically connects to sesh session for /etc/nixos

# 3. Session starts in /etc/nixos directory
# 4. Multiple terminals to same project = same tmux session (shared state)
# 5. Session persists - close terminal, reopen later, session is still there
```

### Example 2: Quick Terminal Without Project

```bash
# Press Win+Shift+Return (or i3pm apps launch terminal)
# Sesh selector appears
# Choose from:
#   - Existing tmux sessions (including all your project sessions)
#   - Zoxide directories (recent directories)
# Pick one or create new
```

### Example 3: Multiple Windows, Same Session

```bash
pswitch nixos
# Press Win+Return → First terminal (creates/connects to /etc/nixos session)
# Press Win+Return → Second terminal (connects to same /etc/nixos session)
# Both terminals share tmux session state
# Can split panes, create windows, detach/reattach, etc.
```

### Example 4: Working on Multiple Projects

```bash
# Work on NixOS
pswitch nixos
# Press Win+Return → Terminal for /etc/nixos

# Switch to another project
pswitch myapp
# Press Win+Return → Terminal for /path/to/myapp

# Both sessions persist independently
# Can switch back and forth, both sessions remain active

# View all sessions
# Press Win+Shift+Return → See both sessions in selector
```

## Error Handling

### No Project Active (Ghostty Entry)

```bash
# No project context
i3pm apps launch ghostty

# Result:
Error: No project active and fallback behavior is 'error'
  This application requires a project context.
  Use 'i3pm project switch <name>' to activate a project.
```

**Solution**: Use `i3pm apps launch terminal` instead, or switch to a project first

### Session Doesn't Exist

Sesh automatically creates sessions if they don't exist. When connecting to a directory:
1. Creates new tmux session named after the directory
2. Automatically changes to that directory
3. Session is ready to use immediately
4. Session persists until explicitly killed

## Benefits

1. **Automatic Context**: Terminal always opens in correct project directory with proper session
2. **Session Persistence**: Close terminal, session stays alive. Reopen, reconnect instantly
3. **Shared State**: Multiple terminals = same tmux session (shared history, panes, windows)
4. **Quick Access**: One keypress (Win+Return) to project terminal
5. **Fallback Options**: Interactive selector available when needed
6. **Consistent UX**: Same launcher system for all applications

## Technical Details

### Variable Substitution Flow

1. User presses Win+Return with "nixos" project active
2. Wrapper script loads registry: `ghostty -e sesh connect $PROJECT_DIR`
3. Queries daemon: `i3pm project current --json` → returns `{"directory": "/etc/nixos", ...}`
4. Substitutes: `$PROJECT_DIR` → `/etc/nixos`
5. Executes: `ghostty -e sesh connect /etc/nixos`
6. Ghostty launches with sesh connecting to session for /etc/nixos
7. Sesh creates/connects to tmux session named after the directory (e.g., "nixos" or "etc-nixos")

### Sesh Command Reference

```bash
sesh                    # Interactive selector (all sessions)
sesh connect <name>     # Connect to specific session
sesh list              # List all available sessions
sesh kill <name>       # Kill a session
```

## Registry Statistics

**Total Applications**: 17 (was 16, added "terminal" entry)

**Terminal Applications**:
- ghostty (scoped, requires project)
- terminal (global, sesh selector)
- alacritty (scoped, working directory)

**All accessible via**:
- i3 keybindings (Win+Return, Win+Shift+Return)
- rofi launcher (Win+D)
- CLI commands (i3pm apps launch)

---

**Status**: ✅ Sesh integration complete and ready for use

After rebuild, all terminals will automatically connect to project sesh sessions!
