# Script Contracts: Monitoring Panel Click-Through Fix and Docking Mode

**Feature**: 125-convert-sidebar-split-pane
**Date**: 2025-12-18

## Script Interface Contracts

### 1. toggle-monitoring-panel

**Purpose**: Toggle panel visibility (Mod+M)

**Invocation**:
```bash
toggle-monitoring-panel
```

**Behavior**:
- **Overlay mode**: Closes or opens `monitoring-panel-overlay` window
- **Docked mode**: Toggles `panel_visible` variable (revealer), keeps window open

**Exit Codes**:
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Eww not running |
| 2 | Lockfile held (debounce) |

**Side Effects**:
- Updates `panel_visible` eww variable
- Creates/removes lockfile for debounce

**Debounce**: 1 second (existing behavior)

---

### 2. toggle-panel-dock-mode (NEW)

**Purpose**: Cycle between overlay and docked modes (Mod+Shift+M)

**Invocation**:
```bash
toggle-panel-dock-mode
```

**Behavior**:
1. Read current mode from state file
2. Close current window
3. Open other mode's window
4. Update state file
5. Update `panel_dock_mode` eww variable

**Exit Codes**:
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Eww not running |
| 3 | Screen too narrow for dock mode |

**Side Effects**:
- Writes to `$XDG_STATE_HOME/eww-monitoring-panel/dock-mode`
- Updates `panel_dock_mode` eww variable
- Triggers window close/open

**Constraints**:
- Refuses to dock if (monitor_width - panel_width) < 400px
- Displays notification via swaync if dock refused

---

### 3. monitor-panel-tab (UNCHANGED)

**Purpose**: Switch active tab (Alt+1-6)

**Invocation**:
```bash
monitor-panel-tab <index>
```

**Arguments**:
| Arg | Type | Valid Values | Description |
|-----|------|--------------|-------------|
| index | integer | 0-6 | Tab index to switch to |

**Exit Codes**:
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid index |

---

## State File Contract

### dock-mode

**Path**: `$XDG_STATE_HOME/eww-monitoring-panel/dock-mode`

**Format**:
```
overlay
```
or
```
docked
```

**Constraints**:
- Single line, no trailing newline
- Case-sensitive exact match required
- Default to "overlay" if file missing or invalid

---

## Eww Variable Contract

### Variables Updated by Scripts

| Variable | Type | Script | Trigger |
|----------|------|--------|---------|
| `panel_visible` | boolean | toggle-monitoring-panel | Mod+M |
| `panel_dock_mode` | boolean | toggle-panel-dock-mode | Mod+Shift+M |
| `current_view_index` | integer | monitor-panel-tab | Alt+1-6 |

### eww update Commands

```bash
# Toggle visibility
eww --config $CONFIG update panel_visible=true
eww --config $CONFIG update panel_visible=false

# Toggle dock mode
eww --config $CONFIG update panel_dock_mode=true
eww --config $CONFIG update panel_dock_mode=false
```

---

## Removed Scripts (Forward-Only Development)

The following scripts are **removed** in this feature:

| Script | Reason |
|--------|--------|
| `toggle-panel-focus` | Focus mode replaced by dock mode |
| `exit-monitor-mode` | No longer needed without focus mode |

The Sway mode "📊 Panel" is also removed.
