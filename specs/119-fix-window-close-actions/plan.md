# Implementation Plan: Eww Monitoring Widget Improvements

**Branch**: `119-fix-window-close-actions` | **Date**: 2025-12-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/119-fix-window-close-actions/spec.md`

## Summary

Improve the eww monitoring panel with: (1) reliable window close actions at project/worktree and individual levels, (2) debug mode toggle to hide/show JSON and environment variable features, (3) reduced default panel width by ~33%, (4) UI cleanup removing workspace badges and PRJ/WS/WIN text labels, and (5) fix the "Return to Window" notification callback to correctly focus Claude Code terminal windows with proper project switching. Dynamic resize feature is deferred due to eww limitations.

## Technical Context

**Language/Version**: Nix (configuration), Bash (scripts), Yuck (eww widgets), CSS (styling)
**Primary Dependencies**: eww 0.4+, swaymsg (Sway IPC), jq, bash
**Storage**: N/A (eww state is in-memory, config in ~/.config/eww-monitoring-panel)
**Testing**: Manual testing with sway-test framework for window close operations
**Target Platform**: NixOS with Sway compositor (Hetzner reference, ThinkPad variant)
**Project Type**: Single - eww widget configuration module
**Performance Goals**: Window close operations complete within 500ms, UI updates within 200ms
**Constraints**: eww does NOT support dynamic geometry changes at runtime (see research.md)
**Scale/Scope**: Single nix module (~9000 lines), affects monitoring panel only

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Changes confined to single eww-monitoring-panel.nix module |
| II. Reference Implementation | PASS | Hetzner-sway is reference, ThinkPad is variant |
| III. Test-Before-Apply | WILL COMPLY | dry-build before switch |
| VI. Declarative Configuration | PASS | All changes in Nix/eww configuration |
| VII. Documentation as Code | PASS | Plan and research docs included |
| XI. Sway IPC Alignment | PASS | Window operations use swaymsg IPC |
| XII. Forward-Only Development | PASS | No backwards compatibility concerns |
| XIV. Test-Driven Development | PARTIAL | Manual testing; sway-test for close actions |
| XV. Sway Test Framework | PARTIAL | Will add test cases for window close operations |

**Gate Result**: PASS - All applicable principles satisfied

## Project Structure

### Documentation (this feature)

```text
specs/119-fix-window-close-actions/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0: eww limitations research
├── data-model.md        # Phase 1: State model documentation
├── quickstart.md        # Phase 1: Testing guide
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (repository root)

```text
home-modules/desktop/
└── eww-monitoring-panel.nix    # Main eww widget file
    ├── closeWorktreeScript     # Project-level close (to be improved)
    ├── closeAllWindowsScript   # All windows close (to be improved)
    ├── focusWindowScript       # Window focus with project switch (reference)
    ├── toggleScript            # Panel toggle (width persistence)
    └── yuck/css definitions    # UI elements and styling

scripts/claude-hooks/
├── stop-notification.sh        # Stop notification sender (to be improved)
├── swaync-action-callback.sh   # Return-to-window callback (to be rewritten)
└── prompt-submit-notification.sh  # Start notification (unchanged)
```

**Structure Decision**: Modifications to eww-monitoring-panel.nix module and Claude Code hook scripts. The callback script will be rewritten to use the same focus logic as focusWindowScript.

## Implementation Phases

### Phase 1: Window Close Reliability (P1 - Critical)

**Goal**: Fix unreliable window close actions at all levels

**Changes**:
1. **Individual window close** (line ~4006):
   - Add rate limiting (prevent double-clicks)
   - Add state validation after close
   - Handle missing window gracefully

2. **Project/worktree close** (closeWorktreeScript):
   - Replace lock file with rate limiter
   - Add explicit error handling for swaymsg failures
   - Add confirmation via Sway tree re-query
   - Update panel state after confirmed close

3. **Close all windows** (closeAllWindowsScript):
   - Same improvements as worktree close
   - Add progress feedback for large batches

**Files Modified**: `home-modules/desktop/eww-monitoring-panel.nix`

### Phase 2: Debug Mode Toggle (P2)

**Goal**: Gate JSON and environment variable features behind debug toggle

**Changes**:
1. Add eww variable: `(defvar debug_mode false)`
2. Add toggle button in panel header
3. Gate visibility of debug UI elements:
   - JSON expand icon: `:visible {debug_mode && ...}`
   - JSON panel revealer: `:visible {debug_mode && ...}`
   - Environment variable trigger: `:visible {debug_mode && ...}`
   - Environment variable panel: `:visible {debug_mode && ...}`
4. Debug mode persists within session (eww state)

**Files Modified**: `home-modules/desktop/eww-monitoring-panel.nix`

### Phase 3: Panel Width Reduction (P2)

**Goal**: Reduce default panel width by ~33%

**Changes**:
1. Update `panelWidth` option defaults:
   - Non-ThinkPad: 460px → 307px
   - ThinkPad: 320px → 213px
2. Verify content still readable at new width
3. Adjust any fixed-width CSS that breaks at narrower width

**Note**: Dynamic resize is DEFERRED (see research.md). Session persistence of custom widths is NOT APPLICABLE since width cannot be changed at runtime.

**Files Modified**: `home-modules/desktop/eww-monitoring-panel.nix`

### Phase 4: UI Cleanup (P3)

**Goal**: Remove unused workspace badges and text labels

**Changes**:
1. Remove workspace badge from window rows (lines 3925-3926)
2. Remove "PRJ", "WS", "WIN" text from header count badges
3. Keep count numbers, use icons or just numbers
4. Remove `.badge-workspace` CSS class
5. Verify other badges (PWA, notification) still display correctly

**Files Modified**: `home-modules/desktop/eww-monitoring-panel.nix`

### Phase 5: Return-to-Window Notification Fix (P1 - Critical)

**Goal**: Fix the "Return to Window" notification callback to correctly focus the Claude Code terminal window with proper project switching

**Root Cause Analysis**:
The current `swaync-action-callback.sh` has several issues compared to the working `focusWindowScript`:
1. Uses arbitrary 1-second sleep after project switch instead of waiting for completion
2. Doesn't check current active project before switching (unnecessary switches)
3. May have stale or incorrect PROJECT_NAME from environment variable
4. Different logic path than the eww panel's window click (which works correctly)

**Changes**:

1. **Rewrite swaync-action-callback.sh** to mirror focusWindowScript logic:
   - Read current active project from `~/.config/i3/active-worktree.json`
   - Only switch projects if notification's project differs from current
   - Use `i3pm worktree switch` synchronously (no arbitrary sleep)
   - Focus window immediately after project switch completes
   - Handle errors gracefully with user notifications

2. **Improve stop-notification.sh** project name capture:
   - Verify I3PM_PROJECT_NAME is correctly captured from terminal environment
   - Store window ID and project name reliably for callback

3. **Add debouncing/rate limiting** to prevent rapid-fire callback issues

**Implementation Pattern** (from working focusWindowScript):
```bash
# Get current project from single source of truth
CURRENT_PROJECT=$(jq -r '.qualified_name // "global"' ~/.config/i3/active-worktree.json 2>/dev/null || echo "global")

# Only switch if different
if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
    if ! i3pm worktree switch "$PROJECT_NAME"; then
        notify-send -u critical "Project Switch Failed" "..."
        # Still try to focus window
    fi
fi

# Focus window immediately
swaymsg "[con_id=$WINDOW_ID] focus"

# Select tmux window if applicable
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
fi
```

**Files Modified**:
- `scripts/claude-hooks/swaync-action-callback.sh` (rewrite)
- `scripts/claude-hooks/stop-notification.sh` (minor improvements)

## Complexity Tracking

> No Constitution violations requiring justification.

## Testing Strategy

### Manual Testing Checklist

1. **Window Close**:
   - [ ] Close individual window via close button
   - [ ] Rapid-click close on multiple windows
   - [ ] Close all windows for a project
   - [ ] Close all scoped windows
   - [ ] Close window that's already closing
   - [ ] Verify panel state updates after closes

2. **Debug Mode**:
   - [ ] Toggle debug mode on/off
   - [ ] Verify JSON features hidden when off
   - [ ] Verify env features hidden when off
   - [ ] Verify features appear when on
   - [ ] Toggle while panel is open

3. **Panel Width**:
   - [ ] Panel opens at new reduced width
   - [ ] Content is readable
   - [ ] Scrolling works if needed
   - [ ] Test on both host configurations

4. **UI Cleanup**:
   - [ ] No workspace badges visible
   - [ ] No PRJ/WS/WIN text labels
   - [ ] Other badges (PWA, notification) still work

5. **Return-to-Window Notification**:
   - [ ] Run Claude Code in project terminal, wait for "Ready" notification
   - [ ] Click "Return to Window" - verify correct terminal focused
   - [ ] Test from different project - verify project switch occurs
   - [ ] Test from same project - verify no unnecessary switch
   - [ ] Test with tmux - verify correct tmux window selected
   - [ ] Test with closed terminal - verify error message shown
   - [ ] Test with i3pm daemon stopped - verify window still focuses

### Sway-Test Cases (Window Close)

```json
{
  "name": "Close individual window via monitoring panel",
  "actions": [
    {"type": "launch_app", "params": {"app_name": "firefox", "workspace": 1}},
    {"type": "wait", "params": {"ms": 500}},
    {"type": "exec", "params": {"command": "swaymsg [app_id=firefox] kill"}}
  ],
  "expectedState": {
    "windowCount": 0
  }
}
```

## Deferred Items

### Dynamic Panel Width Resize

**Reason**: Eww does not support dynamic window geometry changes at runtime. This is a known limitation documented in [eww Issue #1101](https://github.com/elkowar/eww/issues/1101).

**Workarounds Evaluated**:
1. Box widget width - doesn't change window boundaries
2. Transparent background with padding - complex, no benefit
3. Multiple hardcoded windows - fragile

**Future**: If eww adds native support for runtime geometry updates, this feature can be revisited.
