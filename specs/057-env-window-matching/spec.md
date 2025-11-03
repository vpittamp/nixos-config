# Feature Specification: Environment Variable-Based Window Matching

**Feature Branch**: `057-env-window-matching`
**Created**: 2025-11-03
**Status**: Draft
**Input**: User description: "create a new feature to explore how we match windows in our python module that manages our sway windows/workspaces/projects etc;  we've updated our logic to inject environment variables when we launch applications that corresond to the current project, use a unique app id, etc.  we used to only do this for regular applications, but we've now succesfully implemented this for firefox pwa's.  given this is the case, i want to explore whether our window matching logic (and perhaps other operations) can be simplified to use environment variables to understand the nature of the application (application type, instance, etc.) instead of having multiple levels of logic that involve non-deterministic properties such as window class, title, etc.  we must test to be sure the environment variables result in a determistic method, and there are no gaps in our process of assigning the environment variables, etc;  we also need to make sure that querying for environment variables provides a reasonable performance in terms of latency.  if it does meet these requirements, then this might simplify our logic in several places, and could be foundational to our system of managing projects, restoring layouts, navigating, etc.  don't worry about backwards compatibility.  determine the optimal solution, and then implement it, discarding legacy approaches, code, files that are no longer part of the optimal solution."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deterministic Window Identification (Priority: P1)

When a user launches any application (regular application or Firefox PWA), the system must reliably identify that window using environment variables injected at launch time, without relying on non-deterministic properties like window class or title.

**Why this priority**: This is the foundational capability that all other features depend on. Without deterministic window identification, project management, workspace assignment, and layout restoration cannot work reliably.

**Independent Test**: Can be fully tested by launching multiple instances of the same application (e.g., 3 VS Code windows, 2 Firefox PWAs) and verifying each window can be uniquely identified by its I3PM_APP_ID environment variable. Delivers reliable window identification independent of window properties.

**Acceptance Scenarios**:

1. **Given** a user launches VS Code from project "nixos", **When** the window appears in Sway, **Then** the system reads I3PM_PROJECT_NAME="nixos", I3PM_APP_NAME="vscode", and I3PM_APP_ID from the window's process environment
2. **Given** a user launches two different Firefox PWAs (e.g., Claude and YouTube), **When** both windows appear, **Then** each window has distinct I3PM_APP_ID values and correct I3PM_APP_NAME values
3. **Given** a user launches the same application twice in the same project, **When** both windows appear, **Then** each window has the same I3PM_APP_NAME and I3PM_PROJECT_NAME but different I3PM_APP_ID values
4. **Given** a window from a native Wayland application (app_id available), **When** the system checks its identity, **Then** the system uses environment variables instead of app_id for identification
5. **Given** a window from an XWayland application (only window class available), **When** the system checks its identity, **Then** the system uses environment variables instead of window class for identification

---

### User Story 2 - Environment Variable Coverage Validation (Priority: P1)

The system must validate that all launched applications (100% coverage) receive the required I3PM_* environment variables, with no gaps in the injection process.

**Why this priority**: Any gap in environment variable injection breaks the deterministic identification model. This must be verified before relying on environment variables as the primary identification mechanism.

**Independent Test**: Can be tested by launching every registered application type (regular apps and PWAs) and verifying I3PM_* variables are present. Delivers confidence that environment injection is complete.

**Acceptance Scenarios**:

1. **Given** the system has N registered applications in the app registry, **When** each application is launched, **Then** 100% of windows have I3PM_APP_ID, I3PM_APP_NAME, and I3PM_SCOPE environment variables
2. **Given** a user launches a Firefox PWA, **When** the PWA window appears, **Then** the window's process has I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE, and I3PM_PROJECT_NAME (if launched from a project)
3. **Given** a user launches an application without an active project, **When** the window appears, **Then** I3PM_PROJECT_NAME and I3PM_PROJECT_DIR are empty strings (not missing)
4. **Given** a child process spawned by a launched application, **When** checking its environment, **Then** the child process inherits all I3PM_* variables from the parent or the system can traverse to the parent to find them
5. **Given** an application launched via command line instead of the launcher, **When** the window appears, **Then** the system detects missing I3PM_* variables and logs a warning

---

### User Story 3 - Performance Benchmark for Environment Variable Queries (Priority: P1)

The system must measure the latency of querying environment variables from /proc/<pid>/environ to ensure it meets performance requirements for real-time window management.

**Why this priority**: If environment variable queries are too slow, they will create lag in window management operations, degrading user experience. Performance validation is essential before replacing existing logic.

**Independent Test**: Can be tested by running a benchmark that queries environment variables for 100 windows and measures average latency. Delivers performance metrics to validate viability.

**Acceptance Scenarios**:

1. **Given** the system needs to identify a newly created window, **When** reading environment variables from /proc/<pid>/environ, **Then** the operation completes in under 10ms on average
2. **Given** the system needs to filter 50 windows based on project association, **When** reading environment variables for all windows, **Then** the total operation completes in under 100ms
3. **Given** a window's direct PID has no I3PM_* variables, **When** traversing up to 3 parent processes, **Then** the environment lookup completes in under 20ms
4. **Given** a process that has exited before environment query, **When** attempting to read /proc/<pid>/environ, **Then** the system handles FileNotFoundError gracefully without crashing and completes in under 5ms
5. **Given** high system load (100+ processes), **When** querying multiple window environments simultaneously, **Then** the system maintains sub-10ms average latency per query

---

### User Story 4 - Simplified Window Matching Logic (Priority: P2)

After validating deterministic identification and performance, the system should replace multi-level fallback logic (app_id → window class → title matching) with environment variable-based identification.

**Why this priority**: Simplification reduces code complexity and eliminates race conditions from non-deterministic properties. This is a high-value refactor but depends on P1 validation.

**Independent Test**: Can be tested by removing old matching logic (app_id, window class, title) and verifying all window identification operations work correctly using only environment variables. Delivers simplified codebase.

**Acceptance Scenarios**:

1. **Given** a window appears in Sway, **When** the system needs to identify its application type, **Then** it reads I3PM_APP_NAME instead of checking app_id or window class
2. **Given** a window with multiple instances, **When** the system needs to distinguish between instances, **Then** it uses I3PM_APP_ID instead of window title patterns
3. **Given** the old window matching code paths (app_id, class, title fallbacks), **When** refactoring is complete, **Then** these code paths are removed entirely
4. **Given** a Firefox PWA that previously required window class pattern matching, **When** identifying the window, **Then** the system uses I3PM_APP_NAME without class-based logic
5. **Given** workspace assignment rules, **When** determining where to place a new window, **Then** the system reads I3PM_TARGET_WORKSPACE instead of looking up workspace by window class

---

### User Story 5 - Project Association via Environment Variables (Priority: P2)

The system should determine window-to-project association by reading I3PM_PROJECT_NAME from the process environment, replacing mark-based or tag-based association.

**Why this priority**: Project association is a core capability for window filtering and project switching. Environment-based association is more reliable than marks but requires P1 validation first.

**Independent Test**: Can be tested by switching between projects and verifying window visibility is controlled by I3PM_PROJECT_NAME and I3PM_SCOPE. Delivers deterministic project filtering.

**Acceptance Scenarios**:

1. **Given** a window launched in project "nixos", **When** checking project association, **Then** I3PM_PROJECT_NAME="nixos" indicates the window belongs to that project
2. **Given** a global application (I3PM_SCOPE="global"), **When** switching projects, **Then** the window remains visible regardless of I3PM_PROJECT_NAME
3. **Given** a scoped application (I3PM_SCOPE="scoped"), **When** switching to a different project, **Then** the window hides because I3PM_PROJECT_NAME doesn't match the active project
4. **Given** the old mark-based filtering logic, **When** refactoring is complete, **Then** all project association uses environment variables and mark-based code is removed
5. **Given** a window with I3PM_PROJECT_NAME="personal", **When** the user switches to project "nixos", **Then** the window moves to scratchpad without checking window marks

---

### User Story 6 - Layout Restoration via Environment Variables (Priority: P3)

The system should use environment variables to restore window layouts, matching saved windows by I3PM_APP_ID and I3PM_APP_NAME instead of window class or title.

**Why this priority**: Layout restoration enhances user productivity but is not critical for basic functionality. This builds on the simplified matching logic from P2.

**Independent Test**: Can be tested by saving a layout with multiple windows, closing all windows, launching them again, and verifying they restore to saved positions using I3PM_APP_ID matching. Delivers layout persistence.

**Acceptance Scenarios**:

1. **Given** a saved layout with 5 windows identified by I3PM_APP_ID, **When** restoring the layout, **Then** the system launches applications and matches windows by I3PM_APP_ID to restore positions
2. **Given** a window that existed when the layout was saved, **When** the same window (same I3PM_APP_ID) is launched, **Then** it appears on the workspace and position from the saved layout
3. **Given** a layout saved with window classes/titles (old format), **When** attempting to restore, **Then** the system migrates to I3PM_APP_ID-based matching
4. **Given** multiple instances of the same application (same I3PM_APP_NAME, different I3PM_APP_ID), **When** restoring layout, **Then** each instance restores to its correct position based on I3PM_APP_ID
5. **Given** a window whose I3PM_APP_ID no longer exists, **When** restoring layout, **Then** the system reports missing window and continues with remaining windows

---

### Edge Cases

- What happens when a process exits before its environment variables can be read? (FileNotFoundError handling, graceful degradation to fallback identification if needed)
- How does the system handle child processes that don't inherit I3PM_* variables? (Parent PID traversal up to 3 levels)
- What happens when reading /proc/<pid>/environ fails due to permission denied? (Log warning, treat as unmanaged window)
- How does the system identify windows launched outside the launcher (e.g., from command line)? (Missing I3PM_* variables, fallback to unmanaged window classification)
- What happens if a Firefox PWA is launched manually without environment injection? (Detected as gap in coverage, validation test should catch this)
- How does the system handle race conditions where window appears before PID is available? (Delayed property re-check with 100ms retry, as implemented in Feature 053)
- What happens when /proc/<pid>/environ contains invalid UTF-8? (Skip invalid variables, continue with valid ones)
- How does the system perform when querying 100+ windows simultaneously? (Async I/O, parallel queries, target <1 second total for 100 windows)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST read I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_SCOPE from /proc/<pid>/environ for every window
- **FR-002**: System MUST validate that 100% of launched applications (regular apps and PWAs) have I3PM_APP_ID and I3PM_APP_NAME environment variables
- **FR-003**: System MUST query /proc/<pid>/environ with average latency under 10ms per window
- **FR-004**: System MUST handle FileNotFoundError (process exited) and PermissionError (access denied) gracefully without crashing
- **FR-005**: System MUST traverse up to 3 parent processes to find I3PM_* variables if child process doesn't have them
- **FR-006**: System MUST identify windows by I3PM_APP_NAME instead of app_id, window_class, or window_properties
- **FR-007**: System MUST distinguish between window instances using I3PM_APP_ID instead of window title
- **FR-008**: System MUST determine project association using I3PM_PROJECT_NAME instead of window marks
- **FR-009**: System MUST determine window scope (global vs scoped) using I3PM_SCOPE instead of registry lookups based on class
- **FR-010**: System MUST remove all code paths that use app_id, window_class, or title for primary window identification (these may remain for diagnostic logging only)
- **FR-011**: System MUST provide benchmark tool to measure environment variable query latency across N windows
- **FR-012**: System MUST log validation report showing coverage percentage (windows with I3PM_* variables / total windows launched)
- **FR-013**: System MUST report performance metrics (p50, p95, p99 latency) for environment variable queries
- **FR-014**: System MUST save window layouts using I3PM_APP_ID as the primary identifier
- **FR-015**: System MUST restore window layouts by matching I3PM_APP_ID between saved state and current windows
- **FR-016**: System MUST detect windows launched outside the launcher (missing I3PM_* variables) and classify them as unmanaged
- **FR-017**: System MUST handle invalid UTF-8 in /proc/<pid>/environ by skipping invalid variables and continuing

### Key Entities

- **Window Environment**: Parsed I3PM_* environment variables from a window's process (I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_SCOPE, I3PM_ACTIVE, I3PM_LAUNCH_TIME, I3PM_LAUNCHER_PID, I3PM_TARGET_WORKSPACE)
- **Window Identity**: Unique identifier for a window instance (I3PM_APP_ID) and application type (I3PM_APP_NAME)
- **Project Association**: Relationship between window and project based on I3PM_PROJECT_NAME and I3PM_SCOPE
- **Window Matching Rule**: Logic that determines which windows belong to a project, application type, or scope using environment variables
- **Performance Benchmark**: Measurement of latency for environment variable queries (average, p50, p95, p99, max)
- **Coverage Report**: Validation results showing percentage of windows with complete I3PM_* variables
- **Layout Snapshot**: Saved state of windows including I3PM_APP_ID, workspace, position, size for restoration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System achieves 100% environment variable coverage for all launched applications (0 gaps in injection)
- **SC-002**: Environment variable queries complete in under 10ms on average (95th percentile under 15ms)
- **SC-003**: Window identification operations complete in under 20ms end-to-end (including parent traversal if needed)
- **SC-004**: Window filtering for project switching completes in under 100ms for 50 windows
- **SC-005**: Codebase complexity reduces by at least 30% (measured by lines of code and cyclomatic complexity in window matching modules)
- **SC-006**: Zero regressions in window management functionality (all existing tests pass with new environment-based logic)
- **SC-007**: Layout restoration matches 100% of windows by I3PM_APP_ID (no mismatches or duplicate assignments)
- **SC-008**: System handles 100+ concurrent window environment queries in under 1 second total
- **SC-009**: Parent process traversal (up to 3 levels) completes in under 20ms for edge cases
- **SC-010**: Validation benchmark runs on every system start and reports coverage percentage to logs

## Assumptions

- All applications are launched through the centralized launcher that injects I3PM_* environment variables
- Child processes inherit environment variables from parent processes in most cases
- /proc filesystem is available and readable (standard Linux environment)
- Window PIDs are available via Sway IPC or xprop (already implemented in Feature 053)
- Performance benchmarks run on modern hardware (SSD for /proc access, multi-core CPU)
- Environment variables are set at process creation and remain constant for process lifetime
- Firefox PWAs are launched via firefoxpwa CLI with environment variable support (already implemented in Feature 056)
- System prioritizes correctness over backward compatibility (legacy matching logic can be removed)

## Out of Scope

- Backward compatibility with layouts saved using window class/title identifiers (migration to I3PM_APP_ID is acceptable)
- Support for applications not launched via the centralized launcher (these remain unmanaged)
- Real-time migration of existing window marks to environment variables (existing windows keep marks until next launch)
- Support for non-Linux operating systems (no /proc filesystem)
- Support for X11-only systems without Wayland (system is Sway-focused)
- Performance optimization beyond stated latency targets (10ms average is sufficient)
- Environment variable encryption or security (I3PM_* variables are not sensitive)
