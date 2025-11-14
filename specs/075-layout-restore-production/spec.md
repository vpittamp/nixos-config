# Feature Specification: Idempotent Layout Restoration

**Feature Branch**: `075-layout-restore-production`
**Created**: 2025-11-14
**Revised**: 2025-11-14
**Status**: Draft - MVP Scope Revised
**Input**: User description: "Revise spec to use app-registry-based restoration as MVP, with geometry/positioning as future enhancement"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Idempotent App Restoration (Priority: P1) 🎯 MVP

As a user restoring a saved layout, when I run the restore command, I want all missing applications to launch (skipping already-running apps) so I can resume my workspace quickly without creating duplicate windows.

**Why this priority**: Current implementation has 0% match rate due to PWA process reuse breaking mark-based correlation. This simpler approach eliminates correlation entirely by checking what's already running and only launching missing apps. This is the foundational capability that must work before any positioning/geometry features can add value.

**Independent Test**: Can be fully tested by: (1) Launch terminal and browser manually, (2) Save layout with terminal, browser, and editor, (3) Close editor only, (4) Run restore command, (5) Verify editor launches but terminal/browser are skipped (no duplicates), (6) Run restore again, (7) Verify all apps skipped (idempotent). Delivers core session restoration without timeouts or correlation failures.

**Acceptance Scenarios**:

1. **Given** user has saved layout with 3 apps (terminal, editor, browser), **When** user closes all windows and runs restore, **Then** all 3 apps launch successfully within 10 seconds (no correlation, no timeouts)
2. **Given** user has terminal and browser already running, **When** user restores layout with terminal, browser, and editor, **Then** only editor launches (terminal and browser skipped to avoid duplicates)
3. **Given** user runs restore command twice in succession, **When** second restore executes, **Then** all apps are already running and no new windows launch (idempotent behavior)
4. **Given** saved layout includes PWA apps (Claude, ChatGPT) that reuse Firefox processes, **When** user restores layout, **Then** PWAs launch successfully without correlation failures (no dependency on process environment variables)

---

### User Story 2 - Current Window Detection (Priority: P1) 🎯 MVP

As the restoration system, before launching apps, I need to check which apps are already running by reading I3PM_APP_NAME from window environments so I can skip launching duplicates.

**Why this priority**: This is the critical detection mechanism that makes restoration idempotent. Without it, every restore would create duplicate windows. This must work reliably for all app types (native, PWAs, terminals).

**Independent Test**: Can be fully tested by: (1) Launch apps with unique I3PM_APP_NAME values, (2) Call detection function, (3) Verify it returns correct set of running app names, (4) Test with PWAs sharing Firefox process, (5) Verify PWA detection works despite process reuse. Delivers duplicate prevention.

**Acceptance Scenarios**:

1. **Given** user has terminal, editor, and browser running, **When** detection reads window environments, **Then** returns set containing {"terminal", "code", "firefox"}
2. **Given** user has 2 PWAs running (Claude, ChatGPT) sharing same Firefox process, **When** detection reads environments, **Then** returns {"claude-pwa", "chatgpt-pwa"} (both detected despite shared process)
3. **Given** window has no I3PM_APP_NAME in environment, **When** detection encounters it, **Then** window is ignored (not counted as managed app)
4. **Given** process has crashed but window still exists, **When** detection reads /proc/<pid>/environ, **Then** handles error gracefully and skips that window

---

### User Story 3 - Automated Integration Testing (Priority: P1) 🎯 MVP

As a developer maintaining layout restoration, when I make changes to the restoration code, I want automated tests that validate the app-launching flow (save → close → restore → verify running) so I can catch regressions before they reach production.

**Why this priority**: Current debugging shows complex correlation issues that could have been caught by tests. With simpler app-based restoration, tests become straightforward: verify apps launch and duplicates are prevented. This validates the complete MVP flow.

**Independent Test**: Can be fully tested by: (1) Write test using sway-test framework, (2) Test saves layout, closes windows, restores, (3) Verify correct apps running with no duplicates, (4) Introduce bug (e.g., break detection), (5) Verify test catches failure. Delivers continuous validation.

**Acceptance Scenarios**:

1. **Given** developer has test suite using sway-test framework, **When** test restores layout with 3 apps, **Then** test verifies all 3 apps launched and no duplicates exist
2. **Given** test runs restore twice in succession, **When** second restore completes, **Then** test verifies idempotent behavior (same apps running, no new launches)
3. **Given** developer breaks app detection logic, **When** tests run, **Then** tests fail with clear error showing duplicate windows created

---

### User Story 4 - Diagnostic Logging (Priority: P2)

As a user debugging restoration issues, when restore runs, I want clear logs showing which apps were already running, which were launched, and any launch failures so I can quickly identify problems.

**Why this priority**: Improves debuggability but doesn't affect core functionality. The simpler MVP approach has fewer failure modes than mark-based correlation, making this less critical initially.

**Independent Test**: Can be fully tested by: (1) Run restore with mixed state (some apps running, some missing), (2) Check logs for "already running" and "launching" messages, (3) Trigger launch failure (invalid app name), (4) Verify error logged clearly. Delivers diagnostic capability.

**Acceptance Scenarios**:

1. **Given** terminal and browser are already running, **When** user restores layout with 3 apps, **Then** logs show "✓ terminal already running - skip", "✓ firefox already running - skip", "→ Launching code"
2. **Given** saved layout references app not in registry, **When** restore attempts to launch it, **Then** logs show "✗ Failed to launch 'unknown-app': not found in registry" and continues with remaining apps
3. **Given** user enables debug logging, **When** restore runs, **Then** logs show current window detection results and launch decisions for each app

---

### Edge Cases

- What happens when saved layout includes app that's no longer in registry?
  - **Expected**: Restore logs failure for that app, continues with remaining apps
  - **User impact**: Partial restoration - user sees which apps failed in logs

- What happens when multiple windows exist for same app (multi-instance)?
  - **Expected**: Detection finds app running once, skips launch
  - **Limitation**: Won't restore multiple instances of same app (future enhancement)

- What happens when window crashes between detection and launch check?
  - **Expected**: Detection runs once at start, uses snapshot of running apps
  - **Safe**: At worst, duplicate launch if window dies during restore

- What happens when user runs restore while previous restore is still launching apps?
  - **Expected**: Second restore detects apps being launched, may skip or duplicate depending on timing
  - **Mitigation**: Add restore lock file (future enhancement)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Restore system MUST read all current window environments to extract I3PM_APP_NAME values before launching any apps
  - **Test**: Launch 3 apps with known I3PM_APP_NAME, run detection, verify all 3 names returned
  - **Scope**: Works for all app types including PWAs sharing processes

- **FR-002**: Restore system MUST skip launching apps whose I3PM_APP_NAME already exists in current windows
  - **Test**: Launch terminal, restore layout with terminal + editor, verify only editor launches
  - **Scope**: Prevents duplicate windows for already-running apps

- **FR-003**: Restore system MUST launch apps via AppLauncher.launch_app() with project context
  - **Test**: Restore layout with project="nixos", verify launched apps have correct I3PM_PROJECT_NAME
  - **Scope**: Ensures apps integrate with existing launcher system

- **FR-004**: Restore system MUST launch apps with saved working directory (for terminal apps)
  - **Test**: Save layout with terminal in /etc/nixos, restore, verify terminal opens in /etc/nixos
  - **Scope**: Preserves terminal CWD from save time

- **FR-005**: Restore system MUST be idempotent (running restore N times produces same state as running once)
  - **Test**: Restore layout, verify apps running, restore again, verify no new apps launched
  - **Scope**: Safe to run restore repeatedly without side effects

- **FR-006**: Restore system MUST log clear status for each app (already running, launching, failed)
  - **Test**: Restore layout, check logs contain status line for each app in layout
  - **Scope**: Enables debugging and user understanding of restore actions

- **FR-007**: Restore system MUST continue with remaining apps if one app fails to launch
  - **Test**: Create layout with 3 apps including invalid one, restore, verify 2 valid apps launch
  - **Scope**: Partial restoration better than complete failure

- **FR-008**: Restore system MUST complete within 15 seconds for typical layout (5 apps)
  - **Test**: Measure time from restore command to all apps launched
  - **Scope**: No timeouts, no correlation delays - just sequential launches

### Non-Functional Requirements

- **NFR-001**: App detection MUST handle PWAs sharing Firefox processes correctly
  - **Test**: Launch 2 PWAs, run detection, verify both detected despite same parent process
  - **Importance**: Critical for real-world usage with PWAs

- **NFR-002**: Restore system MUST handle missing /proc/<pid>/environ gracefully (process died)
  - **Test**: Simulate dead process by pointing to non-existent PID, verify no crash
  - **Importance**: Robustness for edge cases

- **NFR-003**: Launch order SHOULD be deterministic (same order each time for same layout)
  - **Test**: Restore layout 3 times, verify apps launch in same order
  - **Importance**: Predictability for users

## Success Criteria *(mandatory)*

- **SC-001**: App detection identifies 100% of running managed apps (no false negatives)
  - **Measurement**: Launch 10 apps of various types, run detection, verify all 10 found
  - **Target**: 100% detection rate

- **SC-002**: Idempotent restore produces no duplicate windows (0 duplicates after 3 consecutive restores)
  - **Measurement**: Restore layout with 5 apps, run restore 3 times, count total windows
  - **Target**: Exactly 5 windows after 3 restores (same as after 1 restore)

- **SC-003**: Restore completes within 15 seconds for typical layout (5 apps, none running)
  - **Measurement**: Time from restore command start to completion with all apps launched
  - **Target**: <15 seconds (no 30s correlation timeouts)

- **SC-004**: Partial restore succeeds when some apps already running
  - **Measurement**: Launch 2 of 5 apps, restore layout, verify only 3 new apps launch
  - **Target**: Correct selective launching

- **SC-005**: Automated test suite validates complete restore flow
  - **Measurement**: Run test suite, verify tests cover save/close/restore/verify cycle
  - **Target**: 100% test pass rate for working implementation

- **SC-006**: Restore logs provide clear diagnostic information
  - **Measurement**: Run restore, count log entries showing app status
  - **Target**: At least 1 status log per app (already running / launching / failed)

## Out of Scope *(optional)*

**Explicitly excluded from MVP**:

- **Window geometry restoration**: Apps launch in default positions/sizes (not saved positions)
  - **Reason**: Requires mark-based correlation or alternative matching mechanism
  - **Future**: Add as Phase 2 after MVP proven stable

- **Window focus restoration**: Last-focused window not restored
  - **Reason**: Requires tracking window IDs which don't persist across launches
  - **Future**: Track by app name + workspace combination

- **Multi-instance restoration**: Only first instance of each app type restored
  - **Reason**: Ambiguous which terminal window goes where without geometry matching
  - **Future**: Combine with geometry restoration to support multiple terminals

- **Mark-based correlation**: No restoration marks, no /proc environment matching to windows
  - **Reason**: Breaks for PWAs due to process reuse, adds 120s+ timeout delays
  - **Future**: May revisit for geometry restoration with different approach

- **Layout migration**: Old layouts with different format remain incompatible
  - **Reason**: Breaking change already documented, users must re-save layouts
  - **Future**: Could add migration tool if requested

## Key Entities *(optional)*

### RunningApp

Represents currently running application detected in workspace.

**Properties**:
- app_name (string): Value from I3PM_APP_NAME environment variable
- window_id (integer): Sway container ID
- pid (integer): Process ID for environment reading
- workspace (integer): Current workspace number

**Purpose**: Tracks what's already running to prevent duplicates

### SavedWindow

Represents window configuration from saved layout.

**Properties**:
- app_registry_name (string): Key from application registry (e.g., "terminal", "claude-pwa")
- workspace (integer): Target workspace number
- cwd (path, optional): Working directory for terminal apps
- focused (boolean): Whether this window was focused when saved

**Purpose**: Defines what should be running after restore

### RestoreResult

Represents outcome of restore operation.

**Properties**:
- apps_already_running (list<string>): Apps skipped (already present)
- apps_launched (list<string>): Apps successfully launched
- apps_failed (list<string>): Apps that failed to launch
- elapsed_seconds (float): Total restore duration

**Purpose**: Provides diagnostic information and success metrics

## Dependencies *(mandatory)*

### Internal Dependencies

- **Feature 057**: Environment Variable-Based Window Matching
  - **Dependency**: Requires I3PM_APP_NAME to be set in all launched process environments
  - **Impact**: Without this, cannot detect which apps are currently running
  - **Status**: Already implemented and stable

- **Feature 074**: Session Management (AppLauncher, layout save/load)
  - **Dependency**: Uses AppLauncher.launch_app() and existing layout persistence
  - **Impact**: Without this, no mechanism to launch apps or load saved layouts
  - **Status**: Base implementation complete, being simplified for MVP

### External Dependencies

None - feature operates entirely within existing i3pm daemon and launcher system.

## Assumptions *(mandatory)*

1. **Registry uniqueness**: Each app has unique name in app-registry-data.nix
   - **Validation**: Nix build enforces uniqueness at line 389-390
   - **Impact**: Enables reliable app detection by name

2. **Environment variable availability**: I3PM_APP_NAME is set for all managed apps
   - **Validation**: Feature 057 implementation sets this for all wrapper-launched apps
   - **Impact**: Detection works for 100% of managed apps

3. **First launches work**: AppLauncher.launch_app() successfully launches apps
   - **Validation**: Feature 074 implementation tested and working
   - **Impact**: Restore can rely on existing launcher

4. **Process environments readable**: /proc/<pid>/environ is readable for window processes
   - **Validation**: Linux standard, no special permissions needed for same-user processes
   - **Impact**: Detection can read all managed app environments

5. **Layout format compatibility**: Feature 074 layouts have app_registry_name field
   - **Validation**: Breaking change already documented, users re-save layouts
   - **Impact**: Old layouts incompatible (expected, documented)

6. **PWA detection works**: Multiple PWA windows can coexist with same parent process
   - **Validation**: Each PWA window has its own I3PM_APP_NAME despite shared Firefox
   - **Impact**: PWA restoration reliable without correlation

## Technical Constraints *(optional)*

- **No window ID persistence**: Sway container IDs change between launches
  - **Impact**: Cannot correlate new windows to saved windows by ID
  - **Workaround**: Use app_registry_name only (no geometry restoration in MVP)

- **Process reuse**: Some apps (Firefox PWAs, VS Code) reuse existing processes
  - **Impact**: Cannot rely on process environment of newly launched window
  - **Workaround**: Avoid mark-based correlation entirely, check current state

- **Launch timing**: Apps launch at different speeds (terminal <1s, PWA 3-5s)
  - **Impact**: Cannot assume all apps ready immediately
  - **Mitigation**: Sequential launches acceptable for MVP (<15s total)

## Metrics and Observability *(optional)*

### Key Metrics

- **Detection accuracy**: Percentage of running apps correctly identified
  - **Target**: 100%
  - **Measurement**: Launch known set of apps, run detection, count matches

- **Duplicate prevention rate**: Percentage of restores producing no duplicates
  - **Target**: 100% (for apps already running)
  - **Measurement**: Run idempotent restore 10 times, count duplicate windows

- **Restore success rate**: Percentage of apps successfully launched from layout
  - **Target**: 100% (for valid apps in registry)
  - **Measurement**: Restore 100 layouts, count successful launches vs failures

- **Restore duration**: Time from command start to all apps launched
  - **Target**: <15 seconds for 5-app layout
  - **Measurement**: Timer in restore code, logged in RestoreResult

### Logging Requirements

- **Detection phase**: Log count of currently running apps with names
  - Example: "Detected 3 running apps: terminal, firefox, claude-pwa"

- **Per-app decision**: Log action for each app in layout
  - Example: "✓ terminal already running - skip" or "→ Launching code"

- **Launch failures**: Log specific error for failed launches
  - Example: "✗ Failed to launch 'unknown-app': not found in registry"

- **Summary**: Log final statistics
  - Example: "Restore complete: 2 skipped, 3 launched, 0 failed (4.2s)"

## Future Enhancements *(optional)*

**Phase 2: Geometry and Positioning**

After MVP is stable, add window geometry restoration:

- Use alternative to mark-based correlation (e.g., workspace + app_id matching)
- Restore window positions, sizes, floating state
- Handle multi-instance apps (multiple terminals with different geometries)
- Focus restoration to last-focused window

**Phase 3: Advanced Features**

- **Workspace layout validation**: Warn if saved layout conflicts with current state
- **Restore locking**: Prevent concurrent restore operations
- **Layout diff preview**: Show what will change before applying restore
- **Partial restore**: Restore only specific workspaces or apps
- **Multi-instance support**: Restore multiple instances of same app type

**Phase 4: Performance Optimization**

- **Parallel launches**: Launch independent apps concurrently (reduce 15s → 5s)
- **Lazy launching**: Launch apps only when switching to their workspace
- **Preemptive detection**: Cache running apps list, invalidate on window events
