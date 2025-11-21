# Research: Monitor Panel Focus Enhancement

**Feature**: 086-monitor-focus-enhancement
**Date**: 2025-11-21

## Problem Analysis

The monitoring panel currently has `:focusable true` and `:windowtype "normal"`, causing it to steal focus when shown. This breaks the original click-through overlay behavior.

### Current Configuration (from `eww-monitoring-panel.nix:175-188`)

```yuck
(defwindow monitoring-panel
  :monitor "${primaryOutput}"
  :stacking "overlay"
  :focusable true          ; <-- Problem: steals focus
  :exclusive false
  :windowtype "normal"     ; <-- Problem: treated as regular window
  ...)
```

## Research Findings

### 1. Eww Focusable Property (Wayland)

**Source**: Eww documentation (`docs/src/configuration.md:137`)

The `focusable` property on Wayland supports three values:

| Value | Behavior |
|-------|----------|
| `none` | Never focusable (full click-through) |
| `exclusive` | Always captures focus |
| `ondemand` | Focusable only when explicitly requested |

**Decision**: Use `"ondemand"` - allows explicit focus via keybinding while preventing auto-focus.

**Rationale**: `"none"` would prevent keyboard interaction entirely; `"ondemand"` enables the hybrid approach requested in the spec.

### 2. Sway Focus Control Rules

**Source**: sway(5) man page

| Rule | Effect |
|------|--------|
| `no_focus [criteria]` | Prevents auto-focus on window creation |
| `focus_on_window_activation smart` | Focus if visible, otherwise mark urgent |

**Decision**: Add `for_window [app_id="eww-monitoring-panel"] no_focus`

**Rationale**: Prevents focus on panel creation/updates while still allowing explicit focus commands.

### 3. Scratchpad Behavior Analysis

**Source**: sway(5) man page

The spec proposed using scratchpad for visibility management. However, research reveals issues:

1. **Scratchpad always focuses on show**: `scratchpad show` brings window to foreground AND focuses it
2. **No no_focus override for scratchpad show**: The `no_focus` rule only applies to window creation
3. **Position not preserved**: Scratchpad windows may not maintain exact position/size

**Decision**: Do NOT use scratchpad. Instead:
- Use `eww open/close` for visibility (already implemented)
- Use `no_focus` rule for creation-time focus prevention
- Use `focusable: "ondemand"` for explicit focus toggle

**Rationale**: The existing toggle script (`toggle-monitoring-panel`) already provides clean show/hide without scratchpad complexity. Adding scratchpad would introduce focus-stealing on every toggle.

### 4. Focus Toggle Implementation

**Research**: How to programmatically toggle focus

```bash
# Focus the panel (when explicitly requested)
swaymsg '[app_id="eww-monitoring-panel"] focus'

# Return focus to previous window
swaymsg 'focus prev'  # or 'focus tiling'
```

**Challenge**: "Previous window" tracking. Options:
1. `focus prev` - may not always return to expected window
2. Track focused window con_id before focusing panel, restore by ID
3. Use focus history via `focus prev` repeatedly

**Decision**: Use `focus prev` as primary mechanism; if unreliable, track con_id.

**Rationale**: Simplest solution first; can iterate if testing reveals issues.

## Technical Decisions Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Eww `focusable` | `"ondemand"` | Enables keyboard interaction only when explicitly requested |
| Eww `windowtype` | `"normal"` | Keep as-is; focus control via Sway rules |
| Sway rule | `no_focus` | Prevents auto-focus on creation/updates |
| Visibility toggle | `eww open/close` | Keep existing; don't use scratchpad |
| Focus toggle key | `Mod+Shift+M` | Explicit focus lock/unlock |
| Previous window restore | `swaymsg focus prev` | Returns focus after unlock |

## Alternatives Rejected

### Scratchpad-Based Management

**Rejected because**:
- Scratchpad show always steals focus
- Would require complex scripting to prevent focus
- Position/size not reliably preserved
- Adds complexity over existing eww open/close

### `windowtype: "dock"`

**Rejected because**:
- Would prevent ANY focus, even explicit
- Doesn't support the "focus lock" user story
- Incompatible with `focusable: "ondemand"`

## Implementation Notes

### Files to Modify

1. **`home-modules/desktop/eww-monitoring-panel.nix`**:
   - Change `:focusable true` to `:focusable "ondemand"`
   - Create focus toggle script

2. **`home-modules/desktop/sway-keybindings.nix`**:
   - Add `Mod+Shift+M` keybinding for focus toggle

3. **Sway config (via sway.nix or window-rules.json)**:
   - Add `for_window [app_id="eww-monitoring-panel"] no_focus`

### Testing Strategy

1. Verify panel shows without stealing focus (FR-001, FR-002)
2. Verify `Mod+Shift+M` toggles focus (FR-003)
3. Verify focus returns to previous window (FR-004)
4. Verify panel survives workspace switches (FR-006)
