# Sway Configuration Reference

Complete reference for Sway window manager configuration in this NixOS setup.

## Contents

- [Configuration Architecture](#configuration-architecture)
- [Core Configuration](#core-configuration)
- [Keybindings](#keybindings)
- [Window Rules](#window-rules)
- [Workspace Management](#workspace-management)
- [Monitor Configuration](#monitor-configuration)
- [Workspace Mode](#workspace-mode)
- [Dynamic Configuration](#dynamic-configuration)

## Configuration Architecture

### File Locations

| File | Purpose | Hot-reload |
|------|---------|------------|
| `home-modules/desktop/sway.nix` | Core Sway config | No (rebuild) |
| `home-modules/desktop/sway-keybindings.nix` | Static keybindings | No (rebuild) |
| `~/.config/sway/window-rules.json` | Dynamic window rules | Yes |
| `~/.config/sway/workspace-assignments.json` | Workspace-monitor map | Yes |
| `~/.config/sway/appearance.json` | Theme settings | Yes |
| `~/.config/sway/monitor-profile.current` | Active monitor profile | Yes |

### What Goes Where

**In Nix (rebuild required)**:
- Package installation
- Service configuration
- Output/display setup
- Input device settings
- Core keybindings (stable)
- Essential window rules

**In Runtime Config (hot-reload)**:
- Custom keybindings
- Floating window rules
- Workspace assignments
- Theme preferences
- Project-specific overrides

## Core Configuration

### Output Configuration

#### Hetzner (Headless)
```nix
output = {
  "HEADLESS-1" = {
    resolution = "1920x1200";
    position = "1920,0";  # Center
  };
  "HEADLESS-2" = {
    resolution = "1920x1200";
    position = "0,0";     # Left
  };
  "HEADLESS-3" = {
    resolution = "1920x1200";
    position = "3840,0";  # Right
  };
};
```

#### Ryzen (4-Monitor)
```nix
output = {
  "HDMI-A-1" = { resolution = "1920x1080"; position = "0,0"; };      # Left
  "DP-1" = { resolution = "1920x1200"; position = "1920,0"; };       # Center
  "DP-2" = { resolution = "1920x1200"; position = "3840,0"; };       # Right
  "DP-3" = { resolution = "1920x1080"; position = "1920,1200"; };    # Bottom
};
```

#### Laptop
```nix
output = {
  "eDP-1" = {
    scale = "1.25";  # HiDPI scaling
  };
  "HDMI-A-1" = {
    resolution = "1920x1080";
    position = "1920,0";
    scale = "1";
  };
};
```

### Input Configuration

#### Touchpad
```nix
input = {
  "type:touchpad" = {
    dwt = "enabled";           # Disable while typing
    tap = "enabled";           # Tap to click
    natural_scroll = "enabled";
    middle_emulation = "enabled";
    scroll_method = "two_finger";
  };
};
```

#### Keyboard
```nix
input = {
  "type:keyboard" = {
    xkb_layout = "us";
    xkb_options = "caps:none";  # Disable CapsLock (used for workspace mode)
    repeat_delay = "300";
    repeat_rate = "30";
  };
};
```

### Gaps and Borders

```nix
gaps = {
  inner = 4;
  outer = 2;
};

window = {
  border = 2;
  titlebar = false;
  hideEdgeBorders = "smart";
};

colors = {
  focused = {
    border = "#89b4fa";
    background = "#1e1e2e";
    text = "#cdd6f4";
    indicator = "#89b4fa";
    childBorder = "#89b4fa";
  };
  unfocused = {
    border = "#313244";
    background = "#1e1e2e";
    text = "#6c7086";
    indicator = "#313244";
    childBorder = "#313244";
  };
};
```

## Keybindings

### Modifier Key
- Default: `Mod4` (Super/Windows key)
- Set via: `wayland.windowManager.sway.config.modifier = "Mod4"`

### Navigation

| Keys | Action |
|------|--------|
| `Mod+h/j/k/l` | Focus left/down/up/right |
| `Mod+Left/Down/Up/Right` | Focus direction |
| `Mod+a` | Focus parent container |
| `Mod+Space` | Toggle focus mode (tiling/floating) |
| `Mod+/` | Easyfocus (show window hints) |

### Window Movement

| Keys | Action |
|------|--------|
| `Mod+Shift+h/j/k/l` | Move window left/down/up/right |
| `Mod+Shift+arrows` | Move window direction |
| `Mod+Shift+Space` | Toggle floating |
| `Mod+Shift+/` | Easyfocus swap |

### Layout

| Keys | Action |
|------|--------|
| `Mod+v` | Split vertical |
| `Mod+b` | Split horizontal |
| `Mod+s` | Stacking layout |
| `Mod+w` | Tabbed layout |
| `Mod+e` | Toggle split |
| `F11` | Fullscreen |

### Workspace Navigation

| Keys | Action |
|------|--------|
| `Ctrl+0` / `F9` | Enter workspace mode |
| `Ctrl+Shift+0` / `Shift+F9` | Move window to workspace mode |
| `CapsLock` | Enter workspace mode (M1 only) |
| `Mod+Tab` | Last workspace |
| `Mod+n` | Next workspace |
| `Mod+Shift+n` | Previous workspace |

### Application Launchers

| Keys | Action |
|------|--------|
| `Mod+d` | Walker launcher |
| `Alt+Space` | Walker launcher (alternative) |
| `Mod+Return` | Scratchpad terminal |
| `Mod+Shift+Return` | New Ghostty terminal |
| `Mod+Shift+f` | FZF file search |
| `Mod+y` | Yazi file manager |

### Project Management

| Keys | Action |
|------|--------|
| `Mod+p` | Project switcher |
| `Mod+Shift+p` | Clear project (global mode) |

### Monitoring Panel

| Keys | Action |
|------|--------|
| `Mod+m` | Toggle monitoring panel |
| `Mod+Shift+m` | Toggle dock/overlay mode |
| `F10` | Toggle dock mode (VNC) |
| `Alt+1-6` | Switch panel tabs |

### Notifications

| Keys | Action |
|------|--------|
| `Mod+i` | Toggle quick settings |
| `Mod+Shift+i` | Toggle notification center |

### Screenshots

| Keys | Action |
|------|--------|
| `Print` | Screenshot focused output |
| `Shift+Print` | Screenshot selection |
| `Ctrl+Print` | Screenshot to file |

### System

| Keys | Action |
|------|--------|
| `Mod+Shift+c` | Reload Sway config |
| `Mod+Shift+e` | Exit Sway |
| `Mod+x` | Kill focused window |
| `Mod+Shift+r` | Enter resize mode |

## Window Rules

### Rule Syntax (JSON)

```json
{
  "rules": [
    {
      "criteria": {
        "app_id": "firefox",
        "title": ".*Private.*"
      },
      "actions": [
        "floating enable",
        "resize set 1200 800",
        "move position center"
      ]
    }
  ]
}
```

### Criteria Options

| Field | Description | Example |
|-------|-------------|---------|
| `app_id` | Wayland app ID (regex) | `"firefox"` |
| `class` | X11 window class | `"Code"` |
| `title` | Window title (regex) | `".*Private.*"` |
| `instance` | Window instance | `"Navigator"` |
| `shell` | Window shell | `"xwayland"` |
| `floating` | Is floating | `true` |
| `workspace` | Current workspace | `"3"` |

### Common Actions

```sway
# Floating
floating enable
floating disable
floating toggle

# Sizing
resize set 1200 800
resize set 50 ppt 50 ppt

# Positioning
move position center
move position 100 100

# Workspace
move to workspace 5
move to workspace number 5

# Focus
focus
no_focus

# Borders
border none
border pixel 2
border normal

# Sticky (visible on all workspaces)
sticky enable

# Fullscreen
fullscreen enable

# Mark
mark --add my_mark

# Opacity
opacity 0.9
```

### Built-in Window Rules

```nix
# System UI
for_window [app_id="Walker"] floating enable, border none
for_window [app_id="com.mitchellh.ghostty" title="FZF File Search"] floating enable, resize set 1800 1000
for_window [app_id="pavucontrol"] floating enable
for_window [app_id="blueman-manager"] floating enable
for_window [app_id="nm-connection-editor"] floating enable

# Monitoring panel (no focus steal)
for_window [app_id="eww-monitoring-panel"] no_focus
```

## Workspace Management

### Workspace Assignments

File: `~/.config/sway/workspace-assignments.json`

```json
{
  "version": "1.0",
  "output_preferences": {
    "primary": ["HEADLESS-1", "DP-1", "eDP-1"],
    "secondary": ["HEADLESS-2", "HDMI-A-1"],
    "tertiary": ["HEADLESS-3", "DP-2"]
  },
  "assignments": [
    {
      "workspace_number": 1,
      "app_name": "terminal",
      "monitor_role": "primary",
      "primary_output": "HEADLESS-1",
      "fallback_outputs": ["HEADLESS-2", "HEADLESS-3"],
      "auto_reassign": true,
      "source": "nix"
    }
  ]
}
```

### Workspace Ranges

| Range | Purpose |
|-------|---------|
| 1-12 | Regular applications |
| 50-99 | PWAs |
| 0 | Scratchpad marker |

### Monitor Roles

| Role | Default Workspaces | Purpose |
|------|-------------------|---------|
| primary | 1-2, 11-12 | Main work (terminal, AI tools) |
| secondary | 3-5 | Code editors, email |
| tertiary | 6-10 | Browsers, tools |

### Dynamic Assignment

When monitor connects/disconnects:
1. Daemon detects output event
2. Checks current profile
3. Reassigns workspaces to available outputs
4. Updates EWW panels

## Monitor Configuration

### Profile System

Location: `~/.config/sway/monitor-profiles/`

#### Available Profiles

**Hetzner**:
- `single`: HEADLESS-1 only
- `dual`: HEADLESS-1 + HEADLESS-2
- `triple`: All three outputs

**M1**:
- `local-only`: eDP-1 only
- `local+1vnc`: eDP-1 + HEADLESS-1
- `local+2vnc`: eDP-1 + HEADLESS-1 + HEADLESS-2

### Profile Format

```json
{
  "name": "triple",
  "description": "Full triple-head workflow",
  "outputs": ["HEADLESS-1", "HEADLESS-2", "HEADLESS-3"],
  "workspace_roles": {
    "primary": [1, 2],
    "secondary": [3, 4, 5],
    "tertiary": [6, 7, 8, 9]
  }
}
```

### Profile Commands

```bash
# Switch profile
set-monitor-profile triple

# List profiles
set-monitor-profile --list

# Show current
cat ~/.config/sway/monitor-profile.current

# Cycle profiles
cycle-monitor-profile
```

### WayVNC (Headless)

Each HEADLESS output has corresponding VNC:
- HEADLESS-1 → port 5900
- HEADLESS-2 → port 5901
- HEADLESS-3 → port 5902

```bash
# Connect via VNC
vnc://<tailscale-ip>:5900
vnc://<tailscale-ip>:5901
vnc://<tailscale-ip>:5902
```

## Workspace Mode

### Entry

| Platform | Keys |
|----------|------|
| Hetzner/VNC | `Ctrl+0` or `F9` |
| M1 Physical | `CapsLock` |
| Universal | `F9` |

### Navigation

In workspace mode:
- Type digits (0-9) to build workspace number
- Press `Enter` to switch
- Press `Escape` to cancel
- Type `:` for project fuzzy search

### Move Mode

Enter with `Shift` variant:
- `Ctrl+Shift+0` or `Shift+F9`
- Same digit input
- Moves focused window to target workspace

### Visual Feedback

- Workspace bar shows typed digits
- Mode indicator in bar
- Cancel shows "×"

## Dynamic Configuration

### Reload Sway Config

```bash
# Via keybinding
Mod+Shift+c

# Via command
swaymsg reload
```

### Validate Config

```bash
sway --validate
swayconfig validate
```

### Update Runtime Config

```bash
# Update EWW variable
eww update variable=value

# Run Sway command
swaymsg 'command'

# Examples
swaymsg 'workspace 1'
swaymsg 'move workspace to output HEADLESS-2'
swaymsg 'output HEADLESS-3 disable'
```

### Query Sway State

```bash
# Get outputs
swaymsg -t get_outputs | jq

# Get workspaces
swaymsg -t get_workspaces | jq

# Get window tree
swaymsg -t get_tree | jq

# Get focused window
swaymsg -t get_tree | jq '.. | select(.focused? == true)'

# Get all windows
swaymsg -t get_tree | jq '.. | select(.app_id?) | {app_id, name, workspace: .workspace}'

# Get inputs
swaymsg -t get_inputs | jq
```

### Common Debugging

```bash
# Check if Sway is running
pgrep -x sway

# View Sway logs
journalctl --user -u sway -f

# Check socket
echo $SWAYSOCK
ls -la $SWAYSOCK

# Test command
swaymsg -t get_version
```
