# Research: Eww Monitoring Widget Improvements

**Feature Branch**: `119-fix-window-close-actions`
**Date**: 2025-12-15

## Research Questions

### Q1: Dynamic Panel Width Resize at Runtime

**Question**: Can eww panels/windows be dynamically resized at runtime while preserving state across toggle operations?

**Findings**:

1. **Native Support**: Eww does NOT natively support dynamic window geometry changes at runtime. This is a [documented feature request (Issue #1101)](https://github.com/elkowar/eww/issues/1101) that remains OPEN and unimplemented as of December 2025.

2. **Known Bug**: When using a variable width via `deflisten`, the window will only INCREASE but not DECREASE its width ([Issue #696](https://github.com/elkowar/eww/issues/696)). This makes drag-to-resize fundamentally unreliable.

3. **Workarounds Evaluated**:
   - **Box widget width**: Use `:width` on a box widget inside the window instead of geometry - doesn't affect actual window boundaries, only content sizing
   - **Transparent background with padding**: Have window take full width with transparent background and dynamic padding - adds complexity without benefit
   - **Multiple hardcoded windows**: Pre-define windows at different widths and switch between them - fragile and increases complexity

**Decision**: Dynamic resize via drag is NOT FEASIBLE with eww in a stable way. The feature will be deferred.

**Implementation**:
- Reduce default panel width by ~33% (460px → 307px for non-ThinkPad, 320px → 213px for ThinkPad)
- Width changes require configuration change and rebuild
- Session persistence is NOT APPLICABLE since width cannot be changed at runtime

### Q2: Window Close Action Reliability

**Question**: Why are window close actions unreliable at project/worktree and individual window levels?

**Findings**:

1. **Current Implementation Analysis**:
   - **Project/Worktree close**: Uses `swaymsg -t get_tree | jq` to find windows by mark pattern, then iterates with `swaymsg "[con_id=$WID] kill"`
   - **Individual window close**: Inline `swaymsg [con_id=${window.id}] kill` in yuck onclick
   - Both have lock file debouncing (project/worktree level only)

2. **Identified Issues**:
   - **Race condition**: Individual window close has no debouncing - rapid clicks can cause multiple kill attempts on same window
   - **State desync**: Panel state update (`context_menu_window_id=0`) happens after kill command, but kill may be async
   - **No error handling**: `swaymsg kill` failures are silently ignored (redirected to `/dev/null`)
   - **Mark-based filtering fragility**: The jq filter `select(.marks | map(test("^scoped:" + $proj + ":")) | any)` may fail on windows with no marks array

3. **Lock file debounce issues**:
   - Lock file is created but only checked at start - no cleanup guarantee on script crash
   - 1-second debounce may be too aggressive for legitimate rapid operations

**Decision**: Implement robust window close handling with:
- Async-aware close operations using Sway IPC events for confirmation
- Proper error handling with user feedback
- Rate limiting instead of hard debounce
- State validation after close operations

### Q3: Debug Mode Toggle Implementation

**Question**: What state variables and UI elements need to be gated behind debug mode?

**Findings**:

1. **Debug Features to Hide**:
   - JSON inspection expand icon (󰅂/󰅀) on window rows
   - JSON panel revealer (`window-json-tooltip`)
   - Environment variable trigger icon (󰀫)
   - Environment variable panel revealer
   - Copy JSON button functionality

2. **State Variables**:
   - `hover_window_id` - triggers JSON panel
   - `env_window_id` - triggers env vars panel
   - `env_loading`, `env_error`, `env_filter`, `env_i3pm_vars`, `env_other_vars`

3. **Implementation Approach**:
   - Add new eww variable: `(defvar debug_mode false)`
   - Gate visibility of debug UI elements with `:visible {debug_mode && ...}`
   - Toggle via eww update command: `eww update debug_mode=true/false`
   - No keybinding needed - can use header button or CLI toggle

**Decision**: Implement debug mode as eww variable with UI toggle button in panel header.

### Q4: UI Elements to Remove

**Question**: What specific UI elements should be removed (workspace badges, PRJ/WS/WIN labels)?

**Findings**:

1. **Workspace Badge** (lines 3925-3926):
   ```yuck
   (label
     :class "badge badge-workspace"
     :text "WS${window.workspace_number}")
   ```
   - Remove entirely from window row badges

2. **Header Count Labels** (lines 3643-3652):
   ```yuck
   :text "${...} PRJ"
   :text "${...} WS"
   :text "${...} WIN"
   ```
   - Keep the counts, remove the text suffixes
   - Change to just show numbers with icons instead

3. **CSS Classes to Remove**:
   - `.badge-workspace` - no longer needed

**Decision**: Remove workspace badge from window rows. Replace text labels with icons or remove entirely, showing just counts.

## Technical Decisions Summary

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Dynamic width resize | DEFER - Not feasible | Eww doesn't support runtime geometry changes reliably |
| Default width reduction | IMPLEMENT - 33% reduction | Static config change, straightforward |
| Width session persistence | NOT APPLICABLE | Width cannot change at runtime |
| Debug mode toggle | IMPLEMENT - eww variable | Simple, reliable, no external deps |
| Window close fixes | IMPLEMENT - robust handling | Critical for reliability |
| Remove workspace badges | IMPLEMENT - remove from yuck | Cosmetic, low risk |
| Remove text labels | IMPLEMENT - icons only | Cleaner UI, saves space |
| Return-to-window fix | IMPLEMENT - rewrite callback | Mirror working focusWindowScript logic |

### Q5: Return-to-Window Notification Callback Failure

**Question**: Why does the "Return to Window" notification action fail to focus the correct Claude Code terminal window?

**Findings**:

1. **Working Implementation** (focusWindowScript in eww-monitoring-panel.nix):
   - Reads current project from `~/.config/i3/active-worktree.json` (single source of truth)
   - Compares notification's project with current project
   - Only switches project if different
   - Focuses window immediately after project switch (no sleep)
   - Uses full nix store paths for all binaries

2. **Broken Implementation** (swaync-action-callback.sh):
   - Uses arbitrary `sleep 1` after `i3pm worktree switch` (unreliable timing)
   - Doesn't check if already in correct project (unnecessary switches)
   - Different logic path than the eww panel (which works correctly)
   - May receive stale/incorrect PROJECT_NAME from environment

3. **Key Differences**:

   | Aspect | focusWindowScript (works) | swaync-action-callback.sh (broken) |
   |--------|---------------------------|-----------------------------------|
   | Current project check | Yes (active-worktree.json) | No |
   | Project switch timing | Synchronous (immediate) | Async (1s sleep) |
   | Conditional switch | Only if different | Always if PROJECT_NAME set |
   | Binary paths | Full nix store paths | Relies on PATH |

**Decision**: Rewrite swaync-action-callback.sh to mirror the working focusWindowScript logic exactly.

## Dependencies

- Existing eww-monitoring-panel.nix infrastructure
- Sway IPC for window operations
- Claude Code hooks infrastructure
- active-worktree.json for current project state
- No new external dependencies required

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Window close race conditions | Medium | Implement rate limiting and state validation |
| Debug toggle breaks existing workflows | Low | Default to OFF, preserves current behavior |
| Width reduction makes content unreadable | Medium | Test on both thinkpad and non-thinkpad configs |
| CSS class removal breaks styling | Low | Remove both yuck and CSS together |
| Return-to-window callback rewrite regression | Medium | Mirror working focusWindowScript exactly, comprehensive testing |
| PROJECT_NAME capture inaccurate | Low | Verify environment variable capture at notification time |
