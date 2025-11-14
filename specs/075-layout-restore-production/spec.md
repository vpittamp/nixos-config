# Feature Specification: Production-Ready Layout Restoration

**Feature Branch**: `075-layout-restore-production`
**Created**: 2025-11-14
**Status**: Draft
**Input**: User description: "Production-ready layout restoration with comprehensive testing and wrapper integration fixes"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Successful Window Restoration with Mark-Based Correlation (Priority: P1)

As a user restoring a saved layout, when I run the restore command, I want all windows to launch, match correctly, and appear in their saved positions within 10 seconds so I can immediately resume work without waiting or manual intervention.

**Why this priority**: This is the core capability that defines layout restoration. Current implementation shows 0% match rate (0 matched out of 5 windows), making the feature completely non-functional. This must work before any other improvements can deliver value.

**Independent Test**: Can be fully tested by: (1) Save layout with 3 windows (terminal, editor, browser), (2) Close all windows, (3) Run restore command, (4) Verify all 3 windows appear with correct app_id and geometry within 10 seconds, (5) Check that correlation matched windows (not timed out). Delivers core session restoration capability.

**Acceptance Scenarios**:

1. **Given** user has saved layout with 3 windows (terminal on ws1, editor on ws2, browser on ws3), **When** user runs restore command, **Then** all 3 windows launch, correlation matches each to correct placeholder within 5 seconds, and windows appear with saved geometry
2. **Given** user restores layout with 5 windows of different types (terminals, PWAs, native apps), **When** correlation completes, **Then** match rate is ≥95% (at most 1 window may timeout due to slow startup)
3. **Given** restoration marks are properly set in process environment, **When** window::new event fires for launched window, **Then** daemon reads I3PM_RESTORE_MARK from /proc/<pid>/environ and applies it as Sway mark within 100ms

---

### User Story 2 - Automated Integration Testing for Layout Restoration (Priority: P1)

As a developer maintaining layout restoration, when I make changes to the restoration code, I want automated tests that validate the complete restore flow (save → close → restore → verify) so I can catch regressions before they reach production.

**Why this priority**: Current debugging shows windows launch but correlation fails (100% timeout rate). Without automated tests, every fix requires manual testing with multiple windows, which is slow and error-prone. This directly blocks achieving a working P1 implementation.

**Independent Test**: Can be fully tested by: (1) Write test case using sway-test framework, (2) Run test that saves layout, closes windows, restores layout, (3) Verify test passes when restoration works correctly, (4) Verify test fails when restoration has bugs. Delivers continuous validation of core functionality.

**Acceptance Scenarios**:

1. **Given** developer has test suite using sway-test framework, **When** tests run against working restore implementation, **Then** all tests pass and report window match success rates
2. **Given** developer introduces regression that breaks mark application, **When** tests run, **Then** tests fail with clear error showing "0 windows matched" and specific correlation failures
3. **Given** test framework validates wrapper integration, **When** test launches windows during restore, **Then** test verifies I3PM_RESTORE_MARK exists in launched process environment before checking correlation

---

### User Story 3 - Home-Manager Wrapper Script Rebuilds (Priority: P1)

As a user applying wrapper script fixes, when I run nixos-rebuild, I want home-manager to actually rebuild the wrapper script (not use cached version) so my fixes are deployed and functional.

**Why this priority**: Current session shows wrapper source has fixes (I3PM_RESTORE_MARK export in ENV_EXPORTS) but installed wrapper still points to old nix store from before the fix. This prevents validation of the complete solution and blocks production deployment.

**Independent Test**: Can be fully tested by: (1) Modify wrapper script source, (2) Run nixos-rebuild, (3) Check installed wrapper symlink target and grep for new content, (4) Verify new content exists in installed wrapper. Delivers deployment reliability.

**Acceptance Scenarios**:

1. **Given** wrapper script source contains new code (ENV_EXPORTS with I3PM_RESTORE_MARK), **When** user runs nixos-rebuild switch, **Then** home-manager rebuilds wrapper and ~/.local/bin/app-launcher-wrapper.sh symlink points to new nix store path containing updated code
2. **Given** wrapper script is cached in nix store, **When** user modifies wrapper and rebuilds with --option eval-cache false, **Then** nix forces re-evaluation and creates new store derivation
3. **Given** home-manager has wrapper configuration, **When** developer adds comment to force rebuild, **Then** nix detects content change and regenerates wrapper derivation

---

### User Story 4 - Diagnostic Logging and Troubleshooting (Priority: P2)

As a user debugging failed restoration, when correlation times out, I want detailed logs showing exactly which step failed (launch, mark setting, correlation) and what values were involved so I can identify the root cause quickly.

**Why this priority**: Improves debuggability but doesn't fix core functionality. Priority 1 issues (correlation working) are more critical, but good logging accelerates debugging of remaining edge cases.

**Independent Test**: Can be fully tested by: (1) Trigger restoration failure (e.g., remove I3PM_RESTORE_MARK from wrapper), (2) Check daemon logs for "restoration mark" related messages, (3) Verify logs show mark generation, mark value, and timeout reason. Delivers diagnostic capability.

**Acceptance Scenarios**:

1. **Given** window launches without I3PM_RESTORE_MARK in environment, **When** daemon processes window::new event, **Then** logs show "No restoration mark found for window <id> (PID <pid>)" with specific values
2. **Given** correlation waits for window with mark i3pm-restore-abc123, **When** timeout occurs, **Then** logs show "Timeout waiting for window with mark: i3pm-restore-abc123 (waited 30.0s)" and list which marks were actually seen
3. **Given** user enables verbose logging, **When** restoration runs, **Then** logs show complete flow: mark generation → wrapper launch → mark in process env → window::new → mark application → correlation success/failure

---

### Edge Cases

- What happens when wrapper script fails to export I3PM_RESTORE_MARK to process environment (ENV_EXPORTS array doesn't include it)?
  - **Expected**: Window launches without mark, correlation times out after 30s, logs show "No restoration mark found"
  - **Current behavior**: This is the active bug - ENV_EXPORTS missing I3PM_RESTORE_MARK

- What happens when window launches faster than 100ms (before daemon reads environment)?
  - **Expected**: Daemon still reads environment via /proc/<pid>/environ even if window appeared before handler fully ran
  - **Mitigation**: Environment reading should be synchronous in window::new handler

- What happens when two windows launch simultaneously with different restoration marks?
  - **Expected**: Each window gets its unique mark from wrapper, daemon correlates each independently
  - **Risk**: If marks aren't properly isolated, correlation could match wrong window

- What happens when saved layout references app that's no longer installed?
  - **Expected**: AppLauncher fails to launch (app not in registry), restore logs failure, continues with remaining windows
  - **User impact**: Partial restoration - user sees which apps failed

- What happens when nix store has multiple wrapper versions cached?
  - **Expected**: home-manager symlink points to latest version based on generation
  - **Current issue**: Symlink stuck on old version despite rebuilds - cache invalidation problem

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Wrapper script MUST include I3PM_RESTORE_MARK in ENV_EXPORTS array when mark is present in wrapper's environment
- **FR-002**: Home-manager MUST regenerate wrapper-script derivation when source file (/etc/nixos/scripts/app-launcher-wrapper.sh) content changes
- **FR-003**: AppLauncher MUST pass I3PM_RESTORE_MARK environment variable to app-launcher-wrapper.sh when launching windows during restore
- **FR-004**: Daemon window::new handler MUST read I3PM_RESTORE_MARK from /proc/<pid>/environ and apply it as Sway mark to window
- **FR-005**: Correlation system MUST use the mark set by restore.py (not generate new mark) when correlating launched windows
- **FR-006**: System MUST achieve ≥95% window match rate when restoring layouts with 3-5 windows of different types
- **FR-007**: Automated tests MUST validate complete restore flow: save → close → restore → verify match rate
- **FR-008**: Test framework MUST support both sway-test (declarative JSON) and nixos-integration-driver (imperative Python) testing modes
- **FR-009**: Daemon logs MUST include restoration mark values, correlation status (matched/timeout/failed), and timing information for troubleshooting
- **FR-010**: System MUST complete restoration within 10 seconds for typical layouts (3-5 windows) on standard hardware

### Key Entities

- **Restoration Mark**: Unique identifier (format: `i3pm-restore-XXXXXXXX`) passed through wrapper environment to launched process, applied as Sway mark for correlation
  - Attributes: 8-character hex suffix, lifecycle (generated → env var → process env → Sway mark → matched → removed)
  - Relationships: One mark per window placeholder during restore

- **Wrapper Environment**: Set of I3PM_* environment variables exported by app-launcher-wrapper.sh and passed to launched applications
  - Attributes: APP_ID, APP_NAME, PROJECT_NAME, PROJECT_DIR, TARGET_WORKSPACE, EXPECTED_CLASS, RESTORE_MARK (during restore)
  - Relationships: Inherited from wrapper process → exported via ENV_EXPORTS → passed to swaymsg exec → visible in /proc/<pid>/environ

- **Home-Manager Derivation**: Nix store artifact containing app-launcher-wrapper.sh with content hash determining store path
  - Attributes: Source file content, nix store path, symlink target (~/.local/bin/app-launcher-wrapper.sh)
  - Relationships: home-manager-files → wrapper derivation → user symlink

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Window match rate during restoration ≥95% (at most 1 timeout per 20 windows due to slow startup)
- **SC-002**: Restoration completes within 10 seconds for layouts with 3-5 windows (measured from command start to last window matched)
- **SC-003**: Automated test suite passes 100% of test cases after fixes are applied (0 failures)
- **SC-004**: Wrapper script changes deploy successfully on first nixos-rebuild attempt (no manual cache clearing required)
- **SC-005**: Restoration mark appears in launched process environment for 100% of windows launched via AppLauncher during restore
- **SC-006**: Daemon logs provide sufficient diagnostic information to identify root cause of correlation failures within 2 minutes of reviewing logs
- **SC-007**: Test execution time for complete restore test (save → close → restore → verify) completes in under 30 seconds

## Assumptions *(optional)*

- System is running Sway (Wayland compositor) - i3 (X11) compatibility is out of scope
- home-manager is properly configured and functional for user account
- app-launcher-wrapper.sh is the source of truth for wrapper script (managed via Nix)
- Nix store integrity is maintained (no manual modifications to /nix/store)
- Test environments have access to Sway IPC and can launch graphical applications
- Restoration timeout of 30 seconds is sufficient for slow-starting applications
- Mark-based correlation is the only supported method (swallow mechanism not available on Sway)

## Dependencies *(optional)*

### Internal Dependencies
- Feature 074 (Session Management) - provides base restoration infrastructure (correlation, AppLauncher, mark generation)
- Feature 056 (Unified Launch Architecture) - app-launcher-wrapper.sh must work correctly for mark propagation
- Feature 041 (IPC Launch Context) - launch notifications required for correlation

### External Dependencies
- Sway compositor (tested on Sway 1.11+)
- home-manager Nix module (for wrapper script deployment)
- sway-test framework (for declarative testing)
- nixos-integration-driver (for imperative Python-based testing)
- Python 3.11+ with i3ipc.aio library (for daemon IPC)

## Out of Scope *(optional)*

- i3/X11 compatibility (Feature 074 already removed X11 support)
- Backward compatibility with Feature 074 pre-wrapper-integration layouts (users must re-save layouts)
- Auto-save/auto-restore functionality (Feature 074 User Stories 5-6) - separate feature
- Focused window restoration per workspace (Feature 074 User Story 4) - separate feature
- Performance optimization beyond 10-second target for typical layouts
- GUI for restore progress/status - CLI output is sufficient
- Cross-compositor restoration (Sway → i3, i3 → Sway)
- Layout version migration tools (users re-save layouts manually)

## Technical Notes *(optional)*

### Root Cause Analysis

Based on debugging session (2025-11-14):

1. **Duplicate Mark Generation Bug** (FIXED):
   - restore.py generated mark at line 540
   - correlation.py generated NEW mark at line 182, overwriting original
   - Fix: Check for existing mark before generating new one

2. **Missing I3PM_RESTORE_MARK in ENV_EXPORTS** (ACTIVE BUG):
   - wrapper script exports I3PM_RESTORE_MARK at line 276 (PRESENT)
   - ENV_EXPORTS array at line 398-411 doesn't include I3PM_RESTORE_MARK (MISSING)
   - ENV_EXPORTS is used to build ENV_STRING for swaymsg exec (line 418)
   - Without I3PM_RESTORE_MARK in ENV_EXPORTS, mark never reaches process environment
   - Fix applied: Added conditional export at line 414-416

3. **Home-Manager Cache Issue** (ACTIVE BUG):
   - Source file /etc/nixos/scripts/app-launcher-wrapper.sh has fix (modified 13:11)
   - Installed wrapper ~/.local/bin/app-launcher-wrapper.sh points to old nix store (created 13:08)
   - Nix isn't detecting content change and rebuilding derivation
   - Multiple rebuilds with --option eval-cache false don't help
   - Likely issue: Content-addressed store path collision or home-manager not re-evaluating

### Implementation Status

- ✅ AppLauncher integration with wrapper (commit ad7b69e2)
- ✅ Correlation duplicate mark fix (commit ad7b69e2)
- ✅ Sway window detection in capture.py (commit ad7b69e2)
- ✅ CLI parameter name fixes (commit ad7b69e2)
- ✅ Restoration mark handler in window::new (commit ad7b69e2)
- ⏳ Wrapper ENV_EXPORTS fix (committed but not deployed - cache issue)
- ❌ Automated test suite (not started)
- ❌ Home-manager cache invalidation solution (investigating)

### Testing Strategy

**Phase 1: Unit Tests** (sway-test framework)
- Test mark generation produces valid format (i3pm-restore-[0-9a-f]{8})
- Test wrapper exports I3PM_RESTORE_MARK when present in environment
- Test daemon reads restoration mark from /proc/<pid>/environ
- Test correlation uses existing mark (doesn't generate duplicate)

**Phase 2: Integration Tests** (sway-test + nixos-driver)
- Test single-window restore with mark correlation
- Test multi-window restore with different app types
- Test concurrent window launches
- Test timeout behavior for missing marks
- Test wrapper deployment after source changes

**Phase 3: End-to-End Tests** (manual validation)
- Full user workflow: save → modify workspace → close → restore → verify
- Performance test: measure restoration time for 5-window layout
- Stress test: restore layout with 10+ windows
- Regression test: verify fixes don't break existing functionality

### Success Metrics Tracking

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Match rate | 0% (0/5) | ≥95% | ❌ Failing |
| Restore time | 152s | <10s | ❌ Failing |
| Test coverage | 0% | 100% | ❌ None |
| Wrapper deployment | Cached | Fresh | ❌ Failing |
| Mark in env | 0% | 100% | ❌ Failing |
| Diagnostic logs | Partial | Complete | ⚠️ Partial |
