# Implementation Notes: Feature 090 - Notification Callback

## Phase 2 Tasks (T004-T006) - Structural Requirements

**Context**: This feature branch is a git worktree. The SwayNC module and home-manager integration changes need to be applied when the branch is merged to main.

### T004: SwayNC Keyboard Shortcuts Configuration

**Status**: ✅ Module Created
**File**: `home-modules/tools/swaync.nix` (created in worktree)

**Keybindings configured**:
- `notification-action-0`: `["ctrl+r" "Return"]` - "Return to Window" action
- `notification-action-1`: `["Escape"]` - "Dismiss" action
- `notification-close`: `["Escape"]` - Close notification

**Action Required on Merge**:
This module needs to be committed to the main repository and placed in the correct home-modules structure.

### T005: Import SwayNC Module

**Status**: ⚠️ Deferred to Merge
**Action Required**:
When merging to main, add this import to the appropriate home-manager configuration file (likely `home-modules/ai-assistants/claude-code.nix` or a top-level home imports file):

```nix
imports = [
  #... existing imports
  ./tools/swaync.nix
];
```

### T006: Test SwayNC Keybinding Configuration

**Status**: ⚠️ Manual Testing Required After Merge
**Test Procedure**:
1. Merge feature branch to main
2. Rebuild home-manager configuration
3. Restart SwayNC: `systemctl --user restart swaync`
4. Send test notification: `notify-send -A "test=Test Action" "Test" "Press Ctrl+R"`
5. Verify Ctrl+R triggers the action
6. Verify Escape dismisses the notification

## Phase 4 Tasks (T014-T025) - Cross-Project Navigation

### T022-T023: Cross-Project Navigation Testing

**Status**: ⚠️ Manual Testing Required After Merge
**Implementation Complete**: ✅ Code implemented with i3pm project switching logic

**Test Scripts**:
- `specs/090-notification-callback/checklists/tests/090-notification-callback/manual-test-cross-project.sh` - Manual interactive test
- `specs/090-notification-callback/checklists/tests/090-notification-callback/test-cross-project-return.json` - Automated sway-test (partial validation)

**Test Procedure**:
1. Merge feature branch to main (required for i3pm daemon)
2. Rebuild NixOS/home-manager configuration
3. Ensure i3pm daemon is running: `systemctl --user start i3-project-event-listener`
4. Create two test projects (e.g., nixos-090, nixos-089)
5. Run manual test script: `./specs/090-notification-callback/checklists/tests/090-notification-callback/manual-test-cross-project.sh`
6. Follow interactive prompts and click notification "Return to Window" action
7. Verify:
   - Project switches back to original project
   - Terminal window is focused
   - tmux window is selected (if applicable)

**Code Validation**: ✅ Bash syntax validated, all error handling implemented

## Implementation Strategy

Since this is a feature branch, the actual notification hook enhancements (Phase 3-4) can proceed independently. The SwayNC configuration will be integrated when the branch is merged.

## Phase 8 Tasks (T046-T050) - Performance Validation

**Status**: ⚠️ Deferred to Post-Merge Testing
**Implementation Complete**: ✅ All code implemented, performance testing requires full environment

**Performance Budget (from spec.md SC-004):**
- Notification callback latency: <2 seconds worst case
- Hook execution time: <100ms (non-blocking)

**Test Procedure (Post-Merge):**
1. Merge feature branch to main
2. Rebuild and ensure all services running
3. Test simple project (1-3 windows):
   - Trigger notification
   - Click "Return to Window"
   - Measure time from click to focus complete
   - Expected: <1 second typical
4. Test complex project (10+ windows):
   - Same procedure as simple project
   - Expected: <2 seconds worst case
5. Test hook execution:
   - Add timing to stop-notification.sh
   - Verify hook returns in <100ms
   - Handler runs in background (non-blocking)

**Completed**:
- Phase 1 (Setup)
- Phase 2 (SwayNC keybindings)
- Phase 3 (User Story 2 - Same-project focus)
- Phase 4 (User Story 1 - Cross-project return)
- Phase 5 (User Story 3 - Notification dismissal)
- Phase 6 (User Story 4 - Notification content)
- Phase 7 (Edge case handling)
- Phase 8 (Performance validation) - Deferred to post-merge
