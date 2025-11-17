# Research: Preview Pane User Experience

**Feature Branch**: `079-preview-pane-user-experience`
**Date**: 2025-11-16
**Status**: Complete

## Executive Summary

This research identifies the root causes of current UX limitations and documents the technical approaches for implementing enhanced navigation, visual hierarchy, and cross-component integration.

## Research Areas

### 1. Arrow Key Navigation in Project Selection Mode

**Question**: Why don't arrow keys work when project list is displayed?

**Root Cause Found**: `NavigationHandler.handle_arrow_key_event()` explicitly blocks non-`all_windows` modes.

**File**: `home-modules/tools/sway-workspace-panel/workspace-preview-daemon` (lines 283-285)

```python
def handle_arrow_key_event(self, direction: str, mode: str) -> None:
    if mode != "all_windows":
        return  # <<< BLOCKS PROJECT MODE
```

**Solution**: Add conditional routing based on mode:
- `all_windows` → Use existing `SelectionManager.navigate_down()`
- `project_list` → Use existing `FilterState.navigate_down()` (already implemented but never called)

**Decision**: Modify `NavigationHandler` to route events based on preview mode
**Rationale**: FilterState already has `navigate_up()`/`navigate_down()` with circular wrapping (models/project_filter.py:160-172)
**Alternatives Rejected**:
- Creating new navigation handler (violates DRY)
- Polling-based navigation (violates Constitution Principle XI - event-driven architecture)

---

### 2. Backspace Exit Behavior

**Question**: How should backspace exit project selection mode?

**Current Implementation**: `workspace_mode.py` `backspace()` method (lines 177-218) already handles character deletion.

**Gap Found**: When ":" is deleted, system doesn't exit project mode. The `_handle_project_mode_char()` method (line 292) should transition back to workspace mode when accumulated_chars becomes empty.

**Solution**: Check if accumulated_chars is empty after backspace removes ":". If so, call `exit_project_mode()` and restore workspace preview.

**Decision**: Add conditional in `backspace()` to detect empty filter and exit mode
**Rationale**: Follows standard UI pattern (backspace through modal indicator exits mode)
**Alternatives Rejected**:
- Explicit Escape key only (non-intuitive, requires two different keys to exit)
- Keeping mode but showing empty state (confusing UX)

---

### 3. Numeric Prefix Filtering

**Question**: How to enable deterministic filtering by branch number (e.g., ":79" → "079-*")?

**Current Fuzzy Matching**: `project_filter_service.py` uses priority scoring:
- Exact match: 1000 points
- Prefix match: 500 points
- Substring: 100 points

**Enhancement Needed**: Add branch number extraction and prioritize numeric prefix matches.

**Pattern**: Branch names follow `NNN-descriptive-name` (e.g., `079-preview-pane-user-experience`)

**Solution**:
1. Extract leading numeric prefix from branch name via regex `^(\d+)-`
2. When filter contains only digits, match against extracted prefix with highest priority (1000 points)
3. Display branch number in project list entry (e.g., "079 - Preview Pane UX")

**Decision**: Add `branch_number` field to `ProjectListItem` model, prioritize in `_compute_match_score()`
**Rationale**: Deterministic selection (100% accuracy vs fuzzy matching ambiguity)
**Alternatives Rejected**:
- Using full branch name only (long strings, harder to remember)
- Sequential numbering (doesn't match actual branch identifiers)

---

### 4. Worktree Hierarchy Display

**Question**: How to visually represent parent-child relationships in project list?

**Current Data**: Project JSON files contain:
- `worktree.is_worktree` (boolean)
- `worktree.parent_repo` (string, e.g., "nixos")
- `worktree.branch` (string, e.g., "079-preview-pane-user-experience")

**Solution**:
1. Group projects by parent_project_name
2. Root projects displayed at top level with folder icon
3. Worktrees indented under parent with branch icon
4. Sort worktrees by branch number within parent group

**Visual Layout**:
```
nixos                      [folder icon]
  ├─ 078 - Eww Preview     [branch icon]
  └─ 079 - Preview Pane UX [branch icon]
dotfiles                   [folder icon]
```

**Decision**: Hierarchical grouping with visual indentation and icons
**Rationale**: Clear parent-child relationship, reduces cognitive load
**Alternatives Rejected**:
- Flat list (no relationship visible)
- Tree view with collapsible nodes (adds interaction complexity)

---

### 5. Worktree List Command Implementation

**Question**: What should `i3pm worktree list` output?

**Current State**: Stub returns "not yet implemented" (worktree.ts:77-80)

**Available Service**: `worktree-metadata.ts` provides:
- `extractGitMetadata(projectPath)`: branch, commit, dirty, ahead/behind
- `parseWorktreeData(json)`: Extracts worktree info from project JSON

**Solution**: Implement list command that:
1. Reads all project JSON files from `~/.config/i3/projects/`
2. Filters for `worktree.is_worktree === true`
3. Extracts git metadata via `extractGitMetadata()`
4. Outputs JSON array with: branch, path, status, parent

**Output Format**:
```json
[
  {
    "branch": "079-preview-pane-user-experience",
    "path": "/home/vpittamp/nixos-079-preview-pane-user-experience",
    "parent_repo": "nixos",
    "git_status": {
      "dirty": false,
      "ahead": 2,
      "behind": 0
    }
  }
]
```

**Decision**: JSON output via Deno CLI, leveraging existing metadata service
**Rationale**: Composable output for scripting, consistent with other i3pm commands
**Alternatives Rejected**:
- Plain text (harder to parse programmatically)
- Table format only (less scriptable)

---

### 6. Top Bar Project Label Enhancement

**Question**: How to make active project label more visually prominent?

**Current Implementation**: `eww.yuck.nix` displays plain text `{active_project.project}` (line 191)

**Enhancement Plan**:
1. Add project/worktree icon (folder for root, branch for worktree)
2. Apply accent color background (Catppuccin Mocha peach `#fab387`)
3. Display branch number prefix if present (e.g., "079 - Preview Pane UX")
4. Add padding and border-radius for button-like appearance

**CSS Styling**:
```scss
.project-label {
  background-color: #fab387;  // Catppuccin peach
  color: #1e1e2e;             // Base dark
  padding: 4px 12px;
  border-radius: 6px;
  font-weight: bold;
}
```

**Decision**: GTK-styled button widget with icon + formatted name
**Rationale**: Consistent with unified bar theming (Feature 057)
**Alternatives Rejected**:
- Different colors per project (inconsistent theming)
- Plain text without background (not visually prominent)

---

### 7. Worktree Environment Variables

**Question**: What additional environment variables should be injected?

**Current Variables** (injected by `window_environment_bridge.py`):
- `I3PM_APP_ID`
- `I3PM_APP_NAME`
- `I3PM_SCOPE`
- `I3PM_PROJECT_NAME`
- `I3PM_PROJECT_DIR`
- `I3PM_TARGET_WORKSPACE`

**New Variables Needed**:
- `I3PM_IS_WORKTREE` (boolean string: "true"/"false")
- `I3PM_PARENT_PROJECT` (parent repo name or empty)
- `I3PM_BRANCH_TYPE` (classification: "feature"/"main"/"hotfix"/"release")

**Branch Type Classification**:
- Pattern `^\d+-` → "feature"
- Pattern `^hotfix-` → "hotfix"
- Pattern `^release-` → "release"
- Default (main, master) → "main"

**Decision**: Add 3 new environment variables with clear naming convention
**Rationale**: Enables future worktree-aware behavior in applications
**Alternatives Rejected**:
- Single JSON variable (harder to parse in shell scripts)
- No additional variables (loses worktree context)

---

### 8. Notification Click Navigation

**Question**: How to click notification and navigate to source tmux window?

**Current Implementation**: `stop-notification-handler.sh` already supports actions via `notify-send -w -A` flags.

**Missing Pieces**:
1. Tmux session:window identifier extraction
2. Action callback to focus window

**Tmux Window Extraction**:
```bash
if [ -n "${TMUX:-}" ]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}")
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}")
    WINDOW_ID="${TMUX_SESSION}:${TMUX_WINDOW}"
fi
```

**Navigation Command**:
```bash
if [ "$RESPONSE" = "focus" ]; then
    # Focus terminal in Sway
    swaymsg "[con_id=$WINDOW_ID] focus" 2>/dev/null || true

    # Select tmux window
    tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}"
fi
```

**Decision**: Enhance stop-notification.sh to capture tmux context, pass to handler
**Rationale**: Builds on existing notification infrastructure, minimal new code
**Alternatives Rejected**:
- Window class matching (unreliable for multiple terminals)
- Process ID tracking (complex, state management overhead)

---

## Technical Decisions Summary

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Arrow Navigation | Extend NavigationHandler | Reuses existing event routing |
| Backspace Exit | workspace_mode.py | Follows mode transition patterns |
| Numeric Filtering | Pydantic model extension | Type-safe, validates at boundaries |
| Hierarchy Display | Eww widget update | Declarative Nix generation |
| Worktree List | Deno CLI command | Matches existing i3pm patterns |
| Top Bar Label | GTK CSS styling | Catppuccin theme consistency |
| Env Variables | window_environment_bridge.py | Central injection point |
| Notification Click | bash script enhancement | Existing SwayNC action support |

## Dependencies Identified

1. **No new external dependencies** - All functionality uses existing libraries
2. **Internal dependencies**:
   - Pydantic 2.x (already installed)
   - i3ipc 2.x (already installed)
   - SwayNC 0.10+ (already configured)
   - Eww 0.4+ (already configured)

## Performance Considerations

- Arrow key navigation: <50ms (currently <10ms for workspace mode)
- Numeric prefix matching: O(n) where n = number of projects (max ~50)
- Project list rendering: <100ms (Eww widget update)
- Notification action callback: <500ms (bash script execution)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Arrow key event routing conflicts | Medium | Preserve all_windows behavior, add mode check |
| Backspace double-exit | Low | Check for empty filter before mode transition |
| Slow hierarchy rendering | Low | Pre-sort projects during filter phase |
| Notification action timeout | Low | Use -w flag with reasonable timeout |

## Conclusion

All research areas resolved with clear technical approaches. No blockers identified. Implementation can proceed following Constitution principles with test-driven development.
