# Research: Fix Window Focus/Click Issue

**Feature**: 114-fix-window-focus-issue
**Date**: 2025-12-13
**Purpose**: Resolve NEEDS CLARIFICATION items and establish root cause

## Root Cause Analysis - CONFIRMED

### Primary Root Cause: Eww Monitoring Panel Layer-Shell Configuration

**Confidence**: HIGH - Based on code analysis, git history, and symptom correlation

**Evidence**:

1. **Panel Configuration** (eww-monitoring-panel.nix:3432-3445):
   ```lisp
   (defwindow monitoring-panel
     :monitor 0
     :geometry (geometry ...)
     :stacking "fg"           ; Foreground - highest z-order
     :focusable "ondemand"    ; PROBLEM: Receives pointer input
     :exclusive false         ; Doesn't reserve space but still intercepts clicks
     :windowtype "dock"
   )
   ```

2. **Panel Auto-Start** (eww-monitoring-panel.nix:11757-11787):
   - Panel opens on every login via `ExecStartPost ... eww ... open monitoring-panel`
   - `panel_visible` defaults to `true` (line 3156-3168)
   - The 460px-wide overlay intercepts all clicks in that region

3. **Affected Configurations**:
   - ThinkPad: `home-modules/thinkpad.nix:5-70` imports monitoring panel
   - M1: `home-modules/m1.nix` imports monitoring panel
   - Hetzner/Ryzen: Similar imports
   - All configurations affected simultaneously

4. **Regression Timeline**:
   - Introduced: 2025-11-21 (focus-mode work)
   - Previous config: `focusable false`, `stacking "overlay"` - click-through behavior
   - Current config: `focusable "ondemand"`, `stacking "fg"` - intercepts clicks
   - Git evidence: `git log -L3432,3445:home-modules/desktop/eww-monitoring-panel.nix`

**Why Maximizing Works**:
- When a window is maximized/fullscreen, Sway moves it to a higher layer
- The maximized window is rendered above the layer-shell panel
- Clicks reach the window because it's now the topmost surface in that region

**Decision**: Fix the Eww monitoring panel configuration to restore click-through behavior while preserving keyboard interactions.

---

## Research Tasks (Additional Context)

### 1. Layer-Shell Input Behavior

**Task**: Understand how to configure layer-shell surfaces to be visible but click-through.

**Findings**:

Layer-shell surfaces have three relevant properties:
- `:stacking` - z-order layer (bg, bottom, top, overlay, fg)
- `:focusable` - whether surface can receive keyboard/pointer focus (true, false, ondemand)
- `:exclusive` - whether surface reserves screen space

**Click-Through Behavior**:
- `focusable: false` - surface never receives focus, clicks pass through
- `focusable: ondemand` - surface receives focus when clicked, consumes click
- Input region can also be set to empty to allow click-through

**Decision**: Change `:focusable "ondemand"` back to `:focusable false` for default state. Implement explicit focus request via keybinding when interaction is needed.

**Rationale**: The panel's primary use is visual monitoring. Keyboard interaction (via Mod+M) should explicitly focus the panel, rather than having it intercept all pointer events in its region.

---

### 2. Preserving Panel Interactivity

**Task**: Ensure panel can still be interacted with when explicitly focused.

**Options**:

| Option | Pros | Cons |
|--------|------|------|
| A: `focusable false` always | Simple, click-through works | No mouse interaction possible |
| B: Dynamic focusable via eww variable | Can toggle when needed | Complex, may have timing issues |
| C: Smaller input region | Partial interaction | Doesn't fully solve the problem |
| D: `stacking "overlay"` with `focusable ondemand` | May work | Depends on Sway layer ordering |

**Decision**: Option B - Use eww variable to control focusability
```lisp
:focusable {panel_focus_mode ? "ondemand" : false}
```

When user presses Mod+M:
1. Set `panel_focus_mode` to true
2. Panel becomes focusable
3. User can interact with panel
4. On panel close or Escape, reset `panel_focus_mode` to false

**Rationale**: This preserves all existing interactivity while restoring click-through behavior by default.

**Alternative Considered**: Always `focusable false` with keyboard-only interaction - rejected because some panel features (like clicking window entries to focus) require pointer input.

---

### 3. Verification Testing

**Task**: Define tests to verify the fix works correctly.

**Test Cases**:

1. **Click-through when panel visible but inactive**:
   - Panel visible, `panel_focus_mode = false`
   - Click on window beneath panel
   - EXPECTED: Click reaches window

2. **Panel interaction when explicitly focused**:
   - Press Mod+M to focus panel
   - `panel_focus_mode = true`
   - Click on panel controls
   - EXPECTED: Panel receives click

3. **Return to click-through after panel use**:
   - Focus panel (Mod+M)
   - Press Escape or click elsewhere
   - `panel_focus_mode = false`
   - Click on window beneath panel
   - EXPECTED: Click reaches window

4. **No regression in maximized/fullscreen**:
   - Window maximized
   - EXPECTED: All interactions work (unchanged)

---

## Summary of Root Cause and Fix

### Root Cause
The Eww monitoring panel was changed from click-through (`focusable false`, `stacking "overlay"`) to interactive (`focusable "ondemand"`, `stacking "fg"`) on 2025-11-21 for focus-mode work. This caused the 460px-wide panel to intercept all pointer input in its region, blocking clicks on tiled windows beneath it.

### Fix Strategy
1. Change default panel state to click-through (`focusable false`)
2. Add `panel_focus_mode` eww variable to toggle focusability
3. Update Mod+M keybinding to set `panel_focus_mode = true` before showing panel
4. Add escape/close handler to reset `panel_focus_mode = false`
5. Test on all three configurations (ThinkPad, M1, Hetzner-Sway)

### Files to Modify
1. `home-modules/desktop/eww-monitoring-panel.nix`:
   - Lines 3432-3445: Change `:focusable` configuration
   - Add `panel_focus_mode` variable
   - Update toggle-monitoring-panel script

2. `home-modules/desktop/sway.nix` or `sway-keybindings.nix`:
   - Update Mod+M keybinding to set focus mode

### Verification
- Manual testing on ThinkPad (current system)
- Build and test on M1 and Hetzner-Sway
- sway-test framework tests for automated verification

---

## Previous Research (Reference)

The following potential causes were investigated but are NOT the root cause for this specific issue:

| Potential Cause | Status | Notes |
|-----------------|--------|-------|
| Window geometry mismatch | Not primary | May contribute but panel is main issue |
| smart_borders config | Not primary | Configuration unchanged during regression |
| Multi-monitor scaling | Not primary | Issue affects single-monitor too |
| XWayland vs Wayland | Not primary | Affects both client types |

These may be relevant for other input issues but the current symptom (click blocked in 460px region, fixed by maximize) is definitively caused by the Eww panel configuration.
