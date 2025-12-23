---
name: nixos-sway-wm
description: This skill should be used when working with NixOS/Sway window management, i3pm project/worktree management, EWW widgets (monitoring panel, top bar, workspace bar), application launching, or UI configuration. Use for creating/modifying EWW widgets, configuring Sway keybindings/window rules, managing projects via i3pm CLI, or launching applications through the unified app-launcher-wrapper system.
---

# NixOS Sway Window Manager Skill

This skill provides comprehensive guidance for the NixOS-based Sway window manager configuration with i3pm project management, EWW widgets, and unified application launching.

## Overview

The system comprises:
- **Sway WM**: Wayland compositor with declarative Nix configuration
- **i3pm Daemon/CLI**: Project and worktree management with window correlation
- **EWW Widgets**: Top bar, monitoring panel, workspace bar, device controls
- **App Launcher**: Unified application launching with environment injection

## Quick Reference

### Key Keybindings

| Keys | Action |
|------|--------|
| `Mod+M` | Toggle monitoring panel |
| `Mod+Shift+M` | Toggle dock/overlay mode |
| `Mod+Tab` | Workspace overview |
| `Mod+P` | Project switcher |
| `Mod+Return` | Scratchpad terminal |
| `Mod+D` | Walker launcher |
| `Ctrl+0` / `CapsLock` | Workspace mode |

### Essential Commands

```bash
# Project management
i3pm worktree list                    # List worktrees
i3pm worktree switch <name>           # Switch project
i3pm daemon status                    # Daemon health

# EWW operations
eww --config ~/.config/eww-monitoring-panel open monitoring-panel-overlay
eww --config ~/.config/eww-top-bar update ai_sessions_data='{"sessions":[]}'
systemctl --user restart eww-top-bar

# Sway configuration
swaymsg reload                        # Reload config
swaymsg -t get_tree | jq              # Window tree
```

## EWW Widget Development

EWW uses Yuck (S-expression language) for widget definitions and SCSS for styling.

### Widget Architecture

```
~/.config/eww-{bar-name}/
├── eww.yuck          # Widget definitions
├── eww.scss          # Styling
└── scripts/          # Backend scripts (Python/Bash)
```

### Core Widget Types

#### Variables

```yuck
;; Static variable (update via `eww update`)
(defvar show_popup false)

;; Polling variable (periodic refresh)
(defpoll system_metrics
  :interval "2s"
  :initial '{"cpu":0}'
  `python3 scripts/metrics.py`)

;; Listening variable (event-driven, continuous)
(deflisten notifications
  :initial '{"count":0}'
  `python3 scripts/notification-monitor.py`)
```

#### Window Definition

```yuck
(defwindow my-window
  :monitor "HEADLESS-1"
  :geometry (geometry
    :x "0px"
    :y "0px"
    :width "300px"
    :height "100%"
    :anchor "right center")
  :stacking "fg"           ;; fg, bg, overlay, bottom
  :exclusive true          ;; Reserve screen space
  :focusable false
  :namespace "eww-my-window"
  :reserve (struts :distance "300px" :side "right")
  (my-widget))
```

#### Widget Definition

```yuck
(defwidget my-widget []
  (box
    :class "container"
    :orientation "vertical"
    :space-evenly false
    (label :text "Hello")
    (children)))

;; With parameters
(defwidget metric-pill [label value color]
  (box :class "metric ${color}"
    (label :text "${label}: ${value}")))
```

### Common EWW Patterns

```yuck
;; Conditional rendering
(box :visible {condition}
  (label :text "Shown when true"))

;; Button with click handler
(button :onclick "swaymsg workspace 1"
  (label :text "WS1"))

;; JSON data access
(label :text {system_metrics.cpu_load})

;; Progress bar
(progress :value {battery.percentage} :orientation "h")

;; Circular progress
(circular-progress :value {volume.level} :thickness 3)

;; Event handling
(eventbox
  :onhover "eww update hover=true"
  :onhoverlost "eww update hover=false"
  (label :text "Hover me"))
```

### Styling (SCSS)

```scss
// Catppuccin Mocha theme colors
$base: #1e1e2e;
$text: #cdd6f4;
$blue: #89b4fa;
$red: #f38ba8;

.metric-container {
  background-color: rgba($base, 0.8);
  border-radius: 12px;
  padding: 4px 8px;

  .label {
    color: $text;
    font-size: 12px;
  }
}
```

See [references/eww_widgets.md](references/eww_widgets.md) for complete widget reference.

## i3pm Daemon and CLI

### Daemon Architecture

The i3pm daemon (Python 3.11+) manages:
- Window-to-project correlation via environment variables
- Git worktree discovery and management
- Layout save/restore with marks
- Real-time Sway event handling

### CLI Commands

```bash
# Worktree management
i3pm worktree list                    # List all worktrees
i3pm worktree create <repo> <branch>  # Create new worktree
i3pm worktree switch <name>           # Switch active project
i3pm worktree remove <name>           # Remove worktree

# Daemon operations
i3pm daemon status                    # Health check
i3pm daemon events                    # Live event stream
i3pm daemon ping                      # Connectivity test

# Layout management
i3pm layout save <name>               # Save current layout
i3pm layout restore <name>            # Restore saved layout
i3pm layout list                      # List saved layouts

# Diagnostics
i3pm diagnose health                  # Full health check
i3pm diagnose window <id>             # Window details
i3pm diagnose socket-health           # IPC socket status
```

### Environment Variables

Applications launched via app-launcher receive these variables:

| Variable | Description |
|----------|-------------|
| `I3PM_APP_ID` | Unique instance ID |
| `I3PM_APP_NAME` | Registry app name |
| `I3PM_PROJECT_NAME` | Active project |
| `I3PM_PROJECT_DIR` | Project directory |
| `I3PM_SCOPE` | "scoped" or "global" |
| `I3PM_TARGET_WORKSPACE` | Assigned workspace |
| `I3PM_WORKTREE_BRANCH` | Git branch name |

See [references/i3pm_daemon.md](references/i3pm_daemon.md) for daemon internals.

## Application Launching

All applications launch through `app-launcher-wrapper.sh` which:
1. Reads app config from `~/.config/i3/application-registry.json`
2. Injects I3PM_* environment variables
3. Notifies daemon of pending launch
4. Executes via `swaymsg exec`

### Launching Apps

```bash
# Direct launch
app-launcher-wrapper.sh terminal
app-launcher-wrapper.sh code
app-launcher-wrapper.sh firefox

# Dry run (show resolved command)
DRY_RUN=1 app-launcher-wrapper.sh terminal

# Debug mode
DEBUG=1 app-launcher-wrapper.sh terminal
```

### Application Registry

Apps are defined in `home-modules/desktop/app-registry-data.nix`:

```nix
(mkApp {
  name = "terminal";
  display_name = "Terminal";
  command = "ghostty";
  parameters = "-e sesh connect $PROJECT_DIR";
  scope = "scoped";                # "scoped" or "global"
  expected_class = "com.mitchellh.ghostty";
  preferred_workspace = 1;
  preferred_monitor_role = "primary";  # "primary", "secondary", "tertiary"
  fallback_behavior = "use_home";      # "skip", "use_home", "error"
})
```

### PWA Configuration

PWAs are defined in `shared/pwa-sites.nix`:

```nix
{
  name = "Claude";
  url = "https://claude.ai/code";
  domain = "claude.ai";
  ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Deterministic FFPWA ID
  app_scope = "scoped";
  preferred_workspace = 52;
  routing_domains = [ "claude.ai" "www.claude.ai" ];
}
```

See [references/app_launching.md](references/app_launching.md) for complete details.

## Sway Configuration

### Configuration Files

| Location | Purpose | Hot-reload |
|----------|---------|------------|
| `home-modules/desktop/sway.nix` | Core Sway config | No (rebuild) |
| `home-modules/desktop/sway-keybindings.nix` | Static keybindings | No (rebuild) |
| `~/.config/sway/window-rules.json` | Dynamic window rules | Yes |
| `~/.config/sway/workspace-assignments.json` | Workspace-monitor map | Yes |

### Window Rules

```json
{
  "rules": [
    {
      "criteria": { "app_id": "firefox" },
      "actions": ["floating enable", "resize set 1200 800"]
    }
  ]
}
```

### Workspace Mode

Enter with `Ctrl+0` or `CapsLock`, then:
- Type digits (0-9) to build workspace number
- Press `Enter` to switch
- Press `Escape` to cancel
- Hold `Shift` to move window instead

### Monitor Profiles

```bash
set-monitor-profile single           # HEADLESS-1 only
set-monitor-profile dual             # HEADLESS-1 + HEADLESS-2
set-monitor-profile triple           # All three outputs
```

See [references/sway_config.md](references/sway_config.md) for complete reference.

## Common Workflows

### Creating a New EWW Widget

1. **Define the widget** in `.yuck.nix`:
```yuck
(defwidget my-status []
  (box :class "my-status"
    (label :text {my_data.value})))
```

2. **Add data source**:
```yuck
(deflisten my_data
  :initial '{"value":"loading..."}'
  `python3 scripts/my-backend.py`)
```

3. **Create backend script** (`scripts/my-backend.py`):
```python
#!/usr/bin/env python3
import json
import sys

while True:
    data = {"value": "current status"}
    print(json.dumps(data), flush=True)
    time.sleep(1)
```

4. **Style the widget** in `.scss.nix`:
```scss
.my-status {
  background: rgba(30, 30, 46, 0.8);
  padding: 4px 8px;
}
```

### Adding a New Application

1. **Edit** `home-modules/desktop/app-registry-data.nix`:
```nix
(mkApp {
  name = "my-app";
  display_name = "My Application";
  command = "my-app-binary";
  scope = "global";
  expected_class = "MyApp";
  preferred_workspace = 8;
})
```

2. **Rebuild NixOS**:
```bash
sudo nixos-rebuild switch --flake .#<target>
```

3. **Launch**:
```bash
app-launcher-wrapper.sh my-app
```

### Debugging Window Issues

```bash
# Check daemon status
i3pm daemon status

# View window tree
swaymsg -t get_tree | jq '.. | .app_id? // empty' | sort -u

# Check window environment
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM

# View daemon events
i3pm daemon events

# Check app launcher logs
tail -f ~/.local/state/app-launcher.log
```

## Testing

### Test App Launching

```bash
# Dry run to verify configuration
DRY_RUN=1 app-launcher-wrapper.sh terminal

# Debug mode shows all steps
DEBUG=1 app-launcher-wrapper.sh code
```

### Test EWW Widgets

```bash
# Open specific window
eww --config ~/.config/eww-monitoring-panel open monitoring-panel-overlay

# Update variable
eww --config ~/.config/eww-top-bar update show_popup=true

# Check active windows
eww --config ~/.config/eww-top-bar active-windows
```

### Verify Sway State

```bash
# Check workspaces
swaymsg -t get_workspaces | jq

# Check outputs
swaymsg -t get_outputs | jq

# Check focused window
swaymsg -t get_tree | jq '.. | select(.focused? == true)'
```

## Resources

- [references/eww_widgets.md](references/eww_widgets.md) - Complete EWW widget reference
- [references/i3pm_daemon.md](references/i3pm_daemon.md) - Daemon architecture and IPC
- [references/sway_config.md](references/sway_config.md) - Sway configuration details
- [references/app_launching.md](references/app_launching.md) - Application launching system

### External Documentation

- [EWW Documentation](https://elkowar.github.io/eww/)
- [Sway Wiki](https://github.com/swaywm/sway/wiki)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
