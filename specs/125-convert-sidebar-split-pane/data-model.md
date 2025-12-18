# Data Model: Monitoring Panel Click-Through Fix and Docking Mode

**Feature**: 125-convert-sidebar-split-pane
**Date**: 2025-12-18

## Entities

### 1. Panel Mode State

**Description**: Persistent state tracking whether the panel is in overlay or docked mode.

**Storage**: File-based at `$XDG_STATE_HOME/eww-monitoring-panel/dock-mode`

**Schema**:
```
Type: Plain text file
Values: "overlay" | "docked"
Default: "overlay"
```

**Lifecycle**:
- Created on first mode toggle
- Read on session startup to restore previous mode
- Updated on each mode toggle

---

### 2. Eww Variables

**Description**: Runtime state variables managed by eww for widget rendering.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `panel_visible` | boolean | `true` | Whether panel content is visible (revealer state) |
| `panel_dock_mode` | boolean | `false` | Whether panel is in docked mode |
| `panel_focus_mode` | boolean | `false` | **DEPRECATED** - removed in this feature |
| `current_view_index` | integer | `0` | Active tab index (0-6) |

**State Transitions**:

```
Initial State (session start):
  panel_visible = true
  panel_dock_mode = (read from state file, default false)

Mod+M (toggle visibility):
  If overlay mode:
    panel_visible = !panel_visible (via window open/close)
  If docked mode:
    panel_visible = !panel_visible (revealer only, window stays)

Mod+Shift+M (toggle dock mode):
  panel_dock_mode = !panel_dock_mode
  Write state to file
  Close current window, open other window
```

---

### 3. Window Definitions

**Description**: Two eww window definitions for different modes.

#### monitoring-panel-overlay

```yaml
name: monitoring-panel-overlay
monitor: ${primaryOutput}
geometry:
  anchor: "right center"
  x: "0px"
  y: "0px"
  width: "${panelWidth}px"
  height: "90%"
properties:
  focusable: "ondemand"
  exclusive: false
  windowtype: "dock"
  stacking: "fg"
  namespace: "eww-monitoring-panel"
content: monitoring-panel-content
```

#### monitoring-panel-docked

```yaml
name: monitoring-panel-docked
monitor: ${primaryOutput}
geometry:
  anchor: "right center"
  x: "0px"
  y: "0px"
  width: "${panelWidth}px"
  height: "100%"  # Full height when docked
properties:
  focusable: "ondemand"
  exclusive: true
  reserve:
    side: "right"
    distance: "${panelWidth + 4}px"  # Panel width + margin
  windowtype: "dock"
  stacking: "fg"
  namespace: "eww-monitoring-panel"
content: monitoring-panel-content
```

---

### 4. Keybinding Mappings

**Description**: Sway keybindings for panel control.

| Keybinding | Action | Target Script |
|------------|--------|---------------|
| `Mod+M` | Toggle visibility | `toggle-monitoring-panel` |
| `Mod+Shift+M` | Toggle dock mode | `toggle-panel-dock-mode` |
| `Alt+1-6` | Switch tabs | `monitor-panel-tab <index>` (unchanged) |

---

## State Diagram

```
                    ┌─────────────────────────────────────────┐
                    │                                         │
                    ▼                                         │
        ┌───────────────────┐     Mod+Shift+M     ┌──────────┴────────┐
        │  Overlay Mode     │◄───────────────────►│   Docked Mode     │
        │  (exclusive=false)│                     │  (exclusive=true) │
        └─────────┬─────────┘                     └─────────┬─────────┘
                  │                                         │
                  │ Mod+M                                   │ Mod+M
                  │                                         │
                  ▼                                         ▼
        ┌───────────────────┐                     ┌───────────────────┐
        │  Overlay Hidden   │                     │  Docked Hidden    │
        │  (window closed)  │                     │  (revealer=false) │
        │  Click-through ✓  │                     │  Space reserved ✓ │
        └───────────────────┘                     └───────────────────┘
```

---

## File Structure

```
$XDG_STATE_HOME/eww-monitoring-panel/
└── dock-mode              # "overlay" or "docked"

$XDG_CONFIG_HOME/eww-monitoring-panel/
├── eww.yuck               # Widget definitions (both windows)
└── eww.scss               # Styles (mode indicator classes)

$XDG_RUNTIME_DIR/
└── eww-monitoring-panel-toggle.lock  # Debounce lockfile (existing)
```

---

## Validation Rules

1. **dock-mode file**: Must contain exactly "overlay" or "docked" (no whitespace)
2. **panel_visible**: Must be boolean (`true` or `false`)
3. **panel_dock_mode**: Must be boolean, synchronized with dock-mode file
4. **panelWidth**: Must be positive integer, minimum 200px, maximum 800px
5. **Exclusive zone distance**: Must be panelWidth + 4px (margin for clean edge)

---

## Relationships

```
┌─────────────────────┐
│   Sway Keybindings  │
│  (sway-keybindings  │
│       .nix)         │
└─────────┬───────────┘
          │ exec
          ▼
┌─────────────────────┐        ┌─────────────────────┐
│   Toggle Scripts    │───────►│   State Files       │
│  toggle-monitoring  │  read/ │  dock-mode          │
│  toggle-panel-dock  │  write │  toggle.lock        │
└─────────┬───────────┘        └─────────────────────┘
          │ eww update
          ▼
┌─────────────────────┐
│   Eww Variables     │
│  panel_visible      │
│  panel_dock_mode    │
│  current_view_index │
└─────────┬───────────┘
          │ render
          ▼
┌─────────────────────┐
│   Eww Windows       │
│  monitoring-panel-  │
│    overlay/docked   │
└─────────────────────┘
```
