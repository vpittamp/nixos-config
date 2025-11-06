# Quickstart: i3run-Inspired Application Launch UX

**Feature**: 051-i3run-enhanced-launch
**Status**: Implementation Ready
**Version**: 1.0.0

## Overview

Intelligent application launching with i3run-inspired UX patterns: single-keybinding toggle for run/raise/hide, summon mode to bring windows to current workspace, and automatic scratchpad state preservation.

**Key Improvement**: Combines the best of i3run's UX patterns with our superior I3PM_* environment-based window matching.

## Quick Start

### Basic Usage

```bash
# Launch or focus Firefox (default: summon mode)
i3pm run firefox

# Toggle Firefox visibility (hide if visible, show if hidden)
i3pm run firefox --hide

# Show Firefox without ever hiding (idempotent)
i3pm run firefox --nohide

# Always launch new terminal instance
i3pm run alacritty --force
```

### Common Workflows

**Single-Key App Toggle** (recommended keybinding):
```bash
# In sway config: bind $mod+F to toggle Firefox
bindsym $mod+f exec i3pm run firefox --hide
```

**Behavior**:
- Not running → Launch Firefox
- On different workspace → Switch to Firefox's workspace
- On same workspace, unfocused → Focus Firefox
- On same workspace, focused → Hide to scratchpad
- Hidden in scratchpad → Show on current workspace

**Summon Window to Current Workspace**:
```bash
# Bring VS Code to current workspace instead of switching
i3pm run vscode --summon
```

**Multi-Instance Apps**:
```bash
# Always launch new terminal (don't reuse existing)
i3pm run alacritty --force

# First terminal
i3pm run alacritty  # Launches new instance

# Second terminal (without --force, would focus first)
i3pm run alacritty --force  # Launches another instance
```

## CLI Reference

### Command: `i3pm run <app-name> [OPTIONS]`

**Arguments**:
- `<app-name>`: Application name from registry (e.g., `firefox`, `vscode`, `alacritty`)

**Options**:
- `--summon`: Show window on current workspace (default behavior)
- `--hide`: Toggle visibility (hide if focused, show if hidden/unfocused)
- `--nohide`: Never hide, only show (idempotent show operation)
- `--force`: Always launch new instance (skip existing window check)
- `--json`: Output result as JSON (for scripting)
- `-h, --help`: Show help message

**Flags are mutually exclusive**: Only one of `--summon`, `--hide`, `--nohide` can be used per command.

### Exit Codes

- `0`: Success
- `1`: Error (app not found, daemon not running, Sway IPC failure)

### JSON Output

```bash
$ i3pm run firefox --json
{
  "action": "focused",
  "window_id": 123456,
  "focused": true,
  "message": "Focused Firefox on workspace 3"
}
```

**Action Values**:
- `"launched"`: New instance launched
- `"focused"`: Existing window focused
- `"moved"`: Window moved to current workspace (summon)
- `"hidden"`: Window hidden to scratchpad
- `"shown"`: Window shown from scratchpad
- `"none"`: No action taken (e.g., already visible with `--nohide`)

## Mode Behaviors

### Default Mode (--summon or no flag)

| Window State | Action |
|-------------|--------|
| Not running | Launch on current workspace |
| On different workspace | **Move** to current workspace + focus |
| On same workspace, unfocused | Focus |
| On same workspace, focused | Focus (no-op) |
| Hidden in scratchpad | Show on current workspace |

**Use case**: Bring window to me, don't make me go to it.

### Hide Mode (--hide)

| Window State | Action |
|-------------|--------|
| Not running | Launch on current workspace |
| On different workspace | Move to current workspace + focus |
| On same workspace, unfocused | Focus |
| On same workspace, focused | **Hide to scratchpad** |
| Hidden in scratchpad | Show on current workspace |

**Use case**: Single-key toggle for visibility (like i3run's default behavior).

**Recommended keybinding**:
```bash
# Sway config
bindsym $mod+f exec i3pm run firefox --hide
bindsym $mod+c exec i3pm run vscode --hide
bindsym $mod+t exec i3pm run alacritty --hide
```

### NoHide Mode (--nohide)

| Window State | Action |
|-------------|--------|
| Not running | Launch on current workspace |
| On different workspace | Move to current workspace + focus |
| On same workspace, unfocused | Focus |
| On same workspace, focused | **No-op** (already visible) |
| Hidden in scratchpad | Show on current workspace |

**Use case**: Idempotent "show window" command that never hides.

## Scratchpad State Preservation

When hiding windows to scratchpad, the following state is automatically preserved:

**For Floating Windows**:
- Window position (x, y)
- Window size (width, height)
- Floating state

**On Show**: Window appears in **exact same position and size** (within 10px accuracy).

**For Tiled Windows**:
- Only tiling state preserved
- Position/size determined by Sway's tiling layout

**Storage**: State persists across daemon restarts in `~/.config/i3/window-workspace-map.json`.

### Example

```bash
# Float and position Firefox (1600x900 at position 200,100)
i3pm run firefox
# User manually resizes/positions window to 1600x900 at (200,100)

# Hide to scratchpad
i3pm run firefox --hide

# Show from scratchpad
i3pm run firefox
# → Firefox appears at EXACTLY (200,100) with size 1600x900
```

## Integration with Existing Features

### Feature 041 (Launch Notification)

Launch notifications work automatically - no configuration needed.

```bash
i3pm run firefox
# → Daemon receives pre-launch notification
# → Window correlation happens automatically via I3PM_APP_NAME
```

### Feature 057 (Unified Launcher)

All launches go through `app-launcher-wrapper.sh`:

```bash
i3pm run vscode
# → app-launcher-wrapper.sh injects I3PM_* environment variables
# → Daemon tracks window via I3PM_APP_NAME
# → 100% deterministic window matching
```

### Feature 062 (Scratchpad Terminal)

Scratchpad terminal remains independent:

```bash
# Project scratchpad terminal (Feature 062)
Win+Return  # Toggle project terminal

# General app scratchpad (Feature 051)
i3pm run alacritty --hide  # Toggle any app
```

**Difference**:
- Feature 062: One terminal per project, hardcoded keybinding
- Feature 051: Any app, customizable keybindings, CLI command

## Performance

**Typical Latencies** (P95):
- Launch new app: <2s (limited by app startup time)
- Focus existing window: <100ms
- Move window (summon): <200ms
- Hide to scratchpad: <300ms (includes state save)
- Show from scratchpad: <500ms (includes geometry restore)

**State Query**: ~20-22ms (well under 500ms target)

## Troubleshooting

### Daemon Not Running

```bash
$ i3pm run firefox
Error: Daemon not responding

Check daemon status:
  systemctl --user status i3-project-event-listener
```

**Fix**: Restart daemon
```bash
systemctl --user restart i3-project-event-listener
```

### Application Not Found

```bash
$ i3pm run nonexistent-app
Error: Application 'nonexistent-app' not found in registry

Available applications:
  Run 'i3pm apps list' to see registered apps
```

**Fix**: Check application registry
```bash
i3pm apps list
# Add app to registry in home-modules/desktop/app-registry.nix
```

### Window Not Appearing in Expected Position

**Symptom**: Window appears in wrong position after showing from scratchpad

**Causes**:
1. Monitor configuration changed (different resolution)
2. Window was tiled when hidden (no geometry to restore)
3. State file corrupted

**Fix**: Clear scratchpad state
```bash
# Remove entry from state file
rm ~/.config/i3/window-workspace-map.json
# Restart daemon
systemctl --user restart i3-project-event-listener
```

### Geometry Not Preserved

**Check**: Window was floating when hidden?
```bash
# In Sway: Toggle floating
$mod+Shift+Space

# Then hide
i3pm run firefox --hide
```

Only floating windows preserve geometry. Tiled windows restore to tiling layout.

## Examples

### Use Case 1: Browser Toggle

**Goal**: Single key to toggle browser visibility

```bash
# Sway keybinding
bindsym $mod+b exec i3pm run firefox --hide

# First press: Launch Firefox (or focus if running)
# Second press: Hide to scratchpad
# Third press: Show from scratchpad
# Repeat: Hide/show toggle
```

### Use Case 2: Summon Terminal

**Goal**: Bring terminal to current workspace for quick command

```bash
# Launch terminal on workspace 1
i3pm run alacritty

# Switch to workspace 5, need terminal
i3pm run alacritty --summon  # Moves terminal from WS 1 to WS 5

# Back to workspace 1
i3pm run alacritty --summon  # Moves terminal from WS 5 to WS 1
```

### Use Case 3: Multi-Instance Development

**Goal**: Separate terminal instances for different projects

```bash
# Project A terminal
i3pm project switch project-a
i3pm run alacritty  # Launches terminal for project-a

# Project B terminal
i3pm project switch project-b
i3pm run alacritty --force  # Launches NEW terminal (doesn't reuse project-a terminal)
```

### Use Case 4: Scratchpad Note-Taking

**Goal**: Quick access to note-taking app without occupying workspace

```bash
# Setup: Bind $mod+n to toggle obsidian
bindsym $mod+n exec i3pm run obsidian --hide

# Working on workspace 1
$mod+n  # Show Obsidian (floating, 1200x800 centered)
# Take notes...
$mod+n  # Hide Obsidian to scratchpad

# Switch to workspace 5
$mod+n  # Show Obsidian on workspace 5 (same position/size)
# Continue notes...
$mod+n  # Hide again
```

## Advanced Usage

### Scripting with JSON Output

```bash
#!/bin/bash
# Launch Firefox and check if already running

result=$(i3pm run firefox --json)
action=$(echo "$result" | jq -r '.action')

if [ "$action" == "launched" ]; then
    echo "Firefox was not running, launched new instance"
elif [ "$action" == "focused" ]; then
    echo "Firefox was already running, focused existing window"
fi
```

### Combining with Project Switching

```bash
# Switch project and bring relevant windows
i3pm project switch nixos
i3pm run vscode --summon  # Bring VS Code to current workspace
i3pm run alacritty --summon  # Bring terminal to current workspace
```

### Custom Launcher Script

```bash
#!/bin/bash
# smart-launch.sh - Launch with auto-hide if already focused

app="$1"

# Get window state
state=$(i3pm run "$app" --json | jq -r '.action')

if [ "$state" == "none" ]; then
    # Already focused, hide it
    i3pm run "$app" --hide
else
    # Not focused, summon it
    i3pm run "$app" --summon
fi
```

## Configuration

### Application Registry

Applications must be registered in `home-modules/desktop/app-registry.nix`:

```nix
{
  applications = [
    {
      name = "firefox";
      command = "firefox";
      preferred_workspace = 3;
      scope = "global";
      expected_class = "firefox";
    }
    {
      name = "vscode";
      command = "code";
      parameters = [ "$PROJECT_DIR" ];
      scope = "scoped";
      preferred_workspace = 2;
      expected_class = "Code";
    }
  ];
}
```

### Keybindings (Recommended)

```bash
# Sway config (~/.config/sway/keybindings.toml or generated via Nix)

# Application toggles (hide mode)
bindsym $mod+f exec i3pm run firefox --hide
bindsym $mod+c exec i3pm run vscode --hide
bindsym $mod+t exec i3pm run alacritty --hide

# Summon mode (bring to current workspace)
bindsym $mod+Shift+f exec i3pm run firefox --summon
bindsym $mod+Shift+c exec i3pm run vscode --summon

# Force new instances
bindsym $mod+Ctrl+t exec i3pm run alacritty --force
```

## See Also

- [spec.md](spec.md) - Full feature specification
- [data-model.md](data-model.md) - Data models and entities
- [contracts/daemon-rpc.json](contracts/daemon-rpc.json) - RPC API contract
- Feature 038 (Window State Preservation) - Storage backend
- Feature 041 (Launch Notification) - Window correlation
- Feature 062 (Scratchpad Terminal) - Related scratchpad functionality

## Feedback

Found a bug or have a feature request? File an issue on the NixOS configuration repository.

---

**Version**: 1.0.0 | **Last Updated**: 2025-11-06 | **Status**: Ready for Implementation
