# Research: Monitoring Panel Click-Through Fix and Docking Mode

**Feature**: 125-convert-sidebar-split-pane
**Date**: 2025-12-18

## Research Questions Addressed

1. How to fix click-through when panel is hidden
2. How to implement dynamic dock mode with exclusive zones
3. How to toggle between overlay and docked modes
4. What constraints exist on eww layer-shell properties

---

## 1. Click-Through Fix When Panel Hidden

### Problem Analysis

The current monitoring panel uses a revealer widget for visibility, but the layer-shell surface remains active even when the revealer is collapsed. This causes the invisible panel area to intercept mouse clicks.

**Current implementation** (eww-monitoring-panel.nix:3712-3727):
```lisp
(defwindow monitoring-panel
  :focusable "ondemand"
  :exclusive false
  :windowtype "dock"
  ...)
```

The revealer widget collapses content but the GTK window still exists, intercepting input.

### Solution: Use `eww open --toggle` Instead of Revealer-Only

**Decision**: Use `eww close`/`eww open` commands to actually destroy/recreate the window when hiding/showing.

**Rationale**:
- When window is closed, there is no layer-shell surface to intercept clicks
- Feature 114 already implemented this pattern successfully
- The existing `toggle-monitoring-panel` script uses `eww open --toggle`

**Alternatives Considered**:
1. `:focusable false` when hidden - Rejected: Still intercepts clicks even with focusable=false
2. Move window off-screen - Rejected: Wastes resources, not a clean solution
3. Zero-width geometry - Rejected: Layer-shell doesn't support dynamic geometry changes

**Implementation Pattern**:
```bash
# toggle-monitoring-panel script
toggle_panel() {
  $EWW --config "$CONFIG" open --toggle monitoring-panel || true
  sleep 0.1
  if $EWW --config "$CONFIG" active-windows 2>/dev/null | grep -q "monitoring-panel"; then
    $EWW --config "$CONFIG" update panel_visible=true
  else
    $EWW --config "$CONFIG" update panel_visible=false
  fi
}
```

---

## 2. Dynamic Dock Mode with Exclusive Zones

### Problem Analysis

Eww's layer-shell properties (`:exclusive`, `:reserve`) are set at window creation time and cannot be changed dynamically. We need to switch between:
- **Overlay mode**: `:exclusive false`, no space reservation, panel floats over windows
- **Docked mode**: `:exclusive true`, `:reserve (struts :side "right" :distance "Xpx")`, panel reserves space

### Solution: Two Window Definitions, Toggle Between Them

**Decision**: Define two separate `defwindow` blocks with different exclusive/reserve settings, and toggle between them.

**Rationale**:
- `:exclusive` cannot be changed at runtime (layer-shell protocol limitation)
- Two windows allows clean separation of modes
- Existing pattern: top-bar and workspace-bar use static `:exclusive true`

**Alternatives Considered**:
1. Single window with dynamic `:exclusive` - Rejected: Not supported by eww/layer-shell
2. Single window with manual geometry adjustment - Rejected: Doesn't actually reserve space
3. Sway IPC to force window positioning - Rejected: Would fight against layer-shell

**Implementation Pattern**:

```lisp
;; Overlay mode window (current behavior)
(defwindow monitoring-panel-overlay
  :monitor "${primaryOutput}"
  :geometry (geometry :anchor "right center" :width "550px" :height "90%")
  :focusable "ondemand"
  :exclusive false      ;; No space reservation
  :windowtype "dock"
  (monitoring-panel-content))

;; Docked mode window (new)
(defwindow monitoring-panel-docked
  :monitor "${primaryOutput}"
  :geometry (geometry :anchor "right center" :x "0px" :y "0px" :width "550px" :height "100%")
  :focusable "ondemand"
  :exclusive true       ;; Reserve space
  :reserve (struts :side "right" :distance "554px")
  :windowtype "dock"
  (monitoring-panel-content))
```

**Toggle Script**:
```bash
toggle_dock_mode() {
  current_mode=$(cat "$STATE_FILE" 2>/dev/null || echo "overlay")

  if [ "$current_mode" = "overlay" ]; then
    $EWW close monitoring-panel-overlay 2>/dev/null || true
    $EWW open monitoring-panel-docked
    echo "docked" > "$STATE_FILE"
    $EWW update panel_dock_mode=true
  else
    $EWW close monitoring-panel-docked 2>/dev/null || true
    $EWW open monitoring-panel-overlay
    echo "overlay" > "$STATE_FILE"
    $EWW update panel_dock_mode=false
  fi
}
```

---

## 3. Mode Toggle Keybinding (Mod+Shift+M)

### Problem Analysis

`Mod+Shift+M` currently activates "focus mode" (Sway mode "📊 Panel"). The spec requires repurposing this to toggle between overlay and docked modes.

### Solution: Repurpose Keybinding, Remove Focus Mode

**Decision**: Remove the focus mode functionality entirely and use `Mod+Shift+M` for dock mode cycling.

**Rationale**:
- Constitution Principle XII (Forward-Only Development): Replace, don't preserve legacy
- Focus mode was rarely used; dock mode provides more value
- Simplifies the mental model: Mod+M = visibility, Mod+Shift+M = mode

**Alternatives Considered**:
1. New keybinding (Mod+Ctrl+M) - Rejected: Adds cognitive load, spec explicitly says repurpose
2. Keep focus mode in addition to dock mode - Rejected: Violates Forward-Only Development
3. Focus mode as third state in cycle - Rejected: Overcomplicates mode management

**Implementation**:

1. Remove Sway mode "📊 Panel" from sway.nix
2. Remove `toggle-panel-focus` and `exit-monitor-mode` scripts
3. Update sway-keybindings.nix:
   ```nix
   "${modifier}+Shift+m" = "exec toggle-panel-dock-mode";
   ```
4. Create new `toggle-panel-dock-mode` script

---

## 4. Eww Layer-Shell Property Constraints

### Research Findings

| Property | Dynamic? | Notes |
|----------|----------|-------|
| `:exclusive` | NO | Set at window creation, requires close/open to change |
| `:reserve` | NO | Tied to `:exclusive`, requires close/open |
| `:focusable` | YES | Can be changed with `eww update` |
| `:geometry` | NO | Width/height/position are static |
| `:stacking` | PARTIAL | May require reopen for some changes |

### Implications for Implementation

1. **Two windows required**: Cannot dynamically switch exclusive zones on single window
2. **Close-then-open pattern**: Mode changes require window destruction/recreation
3. **Shared content widget**: Both windows can use same `monitoring-panel-content` widget
4. **State synchronization**: Variables (panel_visible, current_view_index, etc.) persist across window changes

---

## 5. Docked Mode When Panel Hidden (Clarification Implementation)

### Requirement

Per spec clarification: "Space remains reserved when hidden (windows stay in reduced area) for consistent layouts."

### Solution: Keep Docked Window Open But Hide Content

When in docked mode and user presses Mod+M to hide:
1. Keep `monitoring-panel-docked` window open (maintains space reservation)
2. Use revealer widget to hide content
3. Set `:focusable false` equivalent to prevent interaction

**Implementation**:
```bash
toggle_visibility() {
  current_dock_mode=$(cat "$STATE_FILE" 2>/dev/null || echo "overlay")

  if [ "$current_dock_mode" = "docked" ]; then
    # Docked mode: toggle revealer, keep window
    current_visible=$($EWW get panel_visible)
    $EWW update panel_visible=$(!$current_visible)
  else
    # Overlay mode: destroy/create window
    $EWW open --toggle monitoring-panel-overlay
  fi
}
```

---

## 6. CPU Optimization Preservation

### Critical Optimizations to Preserve

1. **deflisten over defpoll** (monitoring_data.py):
   - Event-driven updates, no Python startup per poll
   - Location: lines 3350-3360 in eww-monitoring-panel.nix

2. **Disabled tabs** (`:run-while false`):
   - Tabs 2-6 disabled to reduce widget tree complexity
   - Location: lines 3800-3900 in eww-monitoring-panel.nix

3. **30-second build health polling**:
   - Reduced from 10s to 30s
   - Location: defpoll build_health_data

4. **Debounce mechanism**:
   - 1-second lockfile prevents rapid toggle crashes
   - Location: toggle-monitoring-panel script

### Implementation Guarantee

All window definitions will share the same content widget, ensuring optimizations are preserved regardless of dock mode.

---

## 7. Visual Mode Indicator (FR-010)

### Requirement

"System MUST provide visual feedback indicating current mode (overlay vs docked)"

### Solution: Add Mode Indicator to Panel Header

**Implementation**:
```lisp
(defwidget panel-header []
  (box :class "panel-header"
    (box :class "mode-indicator ${panel_dock_mode ? 'docked' : 'overlay'}"
      (label :text {panel_dock_mode ? "📌" : "🔳"}))
    ;; ... rest of header
  ))
```

**SCSS**:
```scss
.mode-indicator {
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 12px;

  &.docked {
    background: rgba(0, 180, 120, 0.3);
  }

  &.overlay {
    background: rgba(100, 100, 100, 0.3);
  }
}
```

---

## Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Click-through fix | `eww open --toggle` | Window destruction ensures no input interception |
| Dock mode implementation | Two window definitions | `:exclusive` cannot change at runtime |
| Keybinding | Repurpose `Mod+Shift+M` | Forward-Only Development principle |
| Hidden docked behavior | Revealer hides content, window stays | Space reservation persists |
| State persistence | File-based (`~/.local/state/...`) | Simple, survives session restart |
| Mode indicator | Header emoji + class styling | Non-intrusive visual feedback |

---

## References

- eww documentation: `docs/elkowar-eww-a2557b8d5a9637c8.txt`
- Feature 114 spec: `specs/114-fix-window-focus-issue/`
- Feature 123 CPU optimizations: `specs/123-otel-tracing/`
- Top-bar exclusive zone: `home-modules/desktop/eww-top-bar/eww.yuck.nix:14-29`
- Workspace-bar exclusive zone: `home-modules/desktop/eww-workspace-bar.nix:162-172`
