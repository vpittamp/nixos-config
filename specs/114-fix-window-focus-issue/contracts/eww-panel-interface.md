# Contract: Eww Panel Focus Mode Interface

**Feature**: 114-fix-window-focus-issue
**Date**: 2025-12-13
**Type**: Shell/Eww Command Interface

## Overview

Defines the interface for controlling the monitoring panel's focus mode, enabling click-through behavior by default while preserving interactivity when explicitly requested.

## Commands

### Set Panel Focus Mode

**Command**: `eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=<value>`

**Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| value | boolean | Yes | true = interactive, false = click-through |

**Examples**:
```bash
# Enable interactive mode (panel receives clicks)
eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=true

# Disable interactive mode (clicks pass through)
eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false
```

### Query Panel Focus Mode

**Command**: `eww --config $HOME/.config/eww-monitoring-panel get panel_focus_mode`

**Response**: `true` or `false`

**Example**:
```bash
$ eww --config $HOME/.config/eww-monitoring-panel get panel_focus_mode
false
```

### Toggle Panel with Focus Mode

**Command**: `toggle-monitoring-panel` (updated script)

**Behavior**:
1. If panel hidden: Show panel AND set `panel_focus_mode=true`
2. If panel visible with `panel_focus_mode=true`: Set `panel_focus_mode=false` (keep visible)
3. If panel visible with `panel_focus_mode=false`: Hide panel

**Alternative Behavior** (simpler):
1. If panel hidden: Show panel AND set `panel_focus_mode=true`
2. If panel visible: Hide panel AND set `panel_focus_mode=false`

## Keybindings

### Mod+M - Toggle Panel Focus

**Current Behavior**: Toggles panel visibility
**New Behavior**: Toggles panel AND sets appropriate focus mode

```nix
# In sway keybindings
"${mod}+m" = "exec toggle-monitoring-panel --focus-mode";
```

### Escape - Exit Focus Mode (when panel focused)

**Behavior**: If panel has keyboard focus, set `panel_focus_mode=false`

This can be implemented in Eww via:
```lisp
(eventbox
  :onkeypress {matches(key, "Escape") ?
    `eww --config ... update panel_focus_mode=false` : ""}
  ...)
```

## Eww Variable Definition

**Location**: `home-modules/desktop/eww-monitoring-panel.nix`

```lisp
; Add to defvar section
(defvar panel_focus_mode false)

; Update defwindow
(defwindow monitoring-panel
  :monitor 0
  :geometry (geometry ...)
  :stacking "fg"
  :focusable {panel_focus_mode ? "ondemand" : false}  ; DYNAMIC
  :exclusive false
  :windowtype "dock"
)
```

## State Diagram

```
                    ┌──────────────┐
                    │   Hidden     │
                    │ visible=F    │
                    │ focus=F      │
                    └──────┬───────┘
                           │
                           │ Mod+M
                           ▼
                    ┌──────────────┐
                    │  Interactive │
                    │ visible=T    │◄──────────┐
                    │ focus=T      │           │
                    └──────┬───────┘           │
                           │                   │
              ┌────────────┼────────────┐      │
              │            │            │      │
              │ Escape     │ Mod+M      │ Mod+M│
              │            │ (toggle)   │ (from hidden)
              ▼            ▼            │      │
       ┌──────────────┐ ┌──────────────┐│      │
       │ Click-Through│ │   Hidden     ││      │
       │ visible=T    │ │ visible=F    │┘      │
       │ focus=F      │ │ focus=F      │───────┘
       └──────────────┘ └──────────────┘
```

## Integration Points

### 1. Sway Keybinding

File: `home-modules/desktop/sway.nix` or `sway-keybindings.nix`

```nix
"${mod}+m" = "exec ${toggle-monitoring-panel}/bin/toggle-monitoring-panel --focus-mode";
```

### 2. Toggle Script

File: Part of `home-modules/desktop/eww-monitoring-panel.nix`

```bash
#!/usr/bin/env bash
# toggle-monitoring-panel

CONFIG_DIR="$HOME/.config/eww-monitoring-panel"
FOCUS_MODE="${1:-false}"

VISIBLE=$(eww --config "$CONFIG_DIR" get panel_visible)

if [ "$VISIBLE" = "true" ]; then
  # Hide panel and disable focus mode
  eww --config "$CONFIG_DIR" update panel_visible=false panel_focus_mode=false
else
  # Show panel and enable focus mode if requested
  if [ "$1" = "--focus-mode" ]; then
    eww --config "$CONFIG_DIR" update panel_visible=true panel_focus_mode=true
  else
    eww --config "$CONFIG_DIR" update panel_visible=true panel_focus_mode=false
  fi
fi
```

### 3. Systemd Service

File: `home-modules/desktop/eww-monitoring-panel.nix` (ExecStartPost)

```nix
ExecStartPost = "${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel open monitoring-panel";
# Note: panel_focus_mode defaults to false, so panel starts in click-through mode
```

## Backward Compatibility

- No changes to external interfaces
- Existing keybindings continue to work
- Panel appearance unchanged
- Default behavior changes from "interactive always" to "click-through by default"
