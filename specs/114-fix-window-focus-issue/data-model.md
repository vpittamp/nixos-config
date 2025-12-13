# Data Model: Fix Window Focus/Click Issue

**Feature**: 114-fix-window-focus-issue
**Date**: 2025-12-13

## Overview

This bug fix primarily involves configuration changes, not new data structures. However, we document the relevant state entities that are modified and queried.

## Entities

### 1. Eww Panel State

**Description**: Runtime state of the monitoring panel controlled by Eww variables.

**Fields**:

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `panel_visible` | boolean | Whether panel is rendered | eww variable |
| `panel_focus_mode` | boolean | Whether panel can receive focus/input | eww variable (NEW) |
| `panel_opacity` | integer (0-100) | Panel background transparency | eww variable |

**State Transitions**:

```
Initial State: panel_visible=true, panel_focus_mode=false
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Default: Click-through mode                             │
│ panel_focus_mode = false                                │
│ Clicks pass through to windows beneath                  │
└─────────────────────────────────────────────────────────┘
                     │
                     │ User presses Mod+M
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Focus Mode: Interactive mode                            │
│ panel_focus_mode = true                                 │
│ Panel receives clicks, can interact with controls       │
└─────────────────────────────────────────────────────────┘
                     │
                     │ User presses Escape / clicks outside / Mod+M again
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Return to Default: Click-through mode                   │
│ panel_focus_mode = false                                │
└─────────────────────────────────────────────────────────┘
```

### 2. Layer-Shell Window Properties

**Description**: Eww window definition properties that control layer-shell behavior.

**Fields**:

| Field | Type | Description | Values |
|-------|------|-------------|--------|
| `stacking` | string | Z-order layer | bg, bottom, top, overlay, fg |
| `focusable` | string/boolean | Input focus behavior | true, false, "ondemand" |
| `exclusive` | boolean | Reserve screen space | true, false |
| `windowtype` | string | Window type hint | dock, dialog, normal, etc. |

**Current vs Fixed Configuration**:

| Property | Current (Broken) | Fixed |
|----------|------------------|-------|
| `stacking` | "fg" | "fg" (unchanged) |
| `focusable` | "ondemand" | `{panel_focus_mode ? "ondemand" : false}` |
| `exclusive` | false | false (unchanged) |

### 3. Sway Window Geometry (Reference)

**Description**: Geometry data from Sway IPC used for diagnostics.

**Fields** (from `swaymsg -t get_tree`):

| Field | Type | Description |
|-------|------|-------------|
| `rect` | {x, y, width, height} | Container position/size |
| `window_rect` | {x, y, width, height} | Window content area |
| `deco_rect` | {x, y, width, height} | Decoration area |
| `geometry` | {x, y, width, height} | Client-reported geometry |

**Usage**: These fields are queried for diagnostics to compare tiled vs maximized states.

## Validation Rules

### Panel Focus Mode

1. `panel_focus_mode` MUST default to `false` on session start
2. `panel_focus_mode` MUST be set to `true` only via explicit user action (Mod+M)
3. `panel_focus_mode` MUST return to `false` on:
   - Panel close/hide
   - Escape key press
   - Mod+M toggle (if already true)
   - Focus change to another window (optional, TBD)

### Panel Visibility

1. `panel_visible` controls rendering, independent of `panel_focus_mode`
2. When `panel_visible=false`, `panel_focus_mode` SHOULD also be `false`
3. Panel can be visible but not focusable (default state)

## Related Existing Entities

These entities exist in the codebase and interact with the panel:

### Window Workspace Map (i3pm daemon)

- Tracks window-to-workspace assignments
- Not directly modified by this fix
- May be queried by panel for window list

### Sway Config Manager State

- Manages appearance.json, window-rules.json
- Not directly modified by this fix
- Panel configuration is separate from config manager

## No New Persistent Storage

This fix does not introduce any new persistent storage. All state changes are:
- Runtime eww variables (reset on session restart)
- Nix configuration changes (persistent via NixOS rebuild)
