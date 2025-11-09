# Feature Specification: Synchronization-Based Test Framework

**Feature Branch**: `069-sync-test-framework`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "create a comprehensive spec/plan that enhances our test framework with our learnings from the native i3wm test-suite, including your recommendations above."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reliable Window Manager State Synchronization (Priority: P1) 🎯 MVP

Test developers can reliably verify window manager state changes without race conditions or arbitrary timeouts. When a test launches an application or changes window state, the test framework guarantees that all state changes are complete before assertions execute.

**Why this priority**: This solves the critical race condition causing test failures. i3 testsuite reduced runtime from 50s to 25s (50% faster) by implementing this synchronization protocol. Without this, tests are unreliable and slow.

**Independent Test**: Can be fully tested by launching Firefox and immediately checking workspace assignment (no timeout waits) - succeeds 100% of the time vs current ~90% success rate with 10s timeout.

**Acceptance Scenarios**:

1. **Given** test launches Firefox on workspace 3, **When** test immediately checks workspace assignment, **Then** Firefox is reliably on workspace 3 (no race condition)
2. **Given** test sends "focus left" command, **When** test immediately queries focused window, **Then** focus has moved to the correct window (not stale state)
3. **Given** test creates 5 windows sequentially, **When** each window creation is followed by state check, **Then** all 5 windows exist in correct workspaces without timeouts
4. **Given** test moves window between workspaces, **When** test checks window location, **Then** window is on target workspace (X11 processing complete)

---

### User Story 2 - Fast and Deterministic Test Actions (Priority: P1)

Test developers can use high-level test actions that automatically synchronize state, eliminating the need for manual timeout waits. Tests run 5-10x faster because they no longer wait arbitrary durations for state changes to complete.

**Why this priority**: Current tests waste 10+ seconds per test waiting for state changes. This makes the test suite slow (50s total) and frustrating to run during development. Fast tests = more frequent testing = higher code quality.

**Independent Test**: Create a test with 5 app launches using `launch_app_sync` - completes in <5 seconds vs current ~50 seconds with timeout waits.

**Acceptance Scenarios**:

1. **Given** test uses `launch_app_sync` action, **When** action completes, **Then** test can immediately verify state (no manual wait needed)
2. **Given** test uses `send_ipc_sync` action, **When** action completes, **Then** window manager state reflects the command execution
3. **Given** test uses explicit `sync` action, **When** action completes, **Then** all prior commands have finished X11 processing
4. **Given** test runs with new sync actions, **When** comparing runtime to old timeout-based tests, **Then** new tests are 5-10x faster

---

### User Story 3 - Reusable Test Helper Patterns (Priority: P2)

Test developers can use pre-built helper functions for common testing patterns (focus verification, workspace checking, window counting). This reduces test boilerplate from 30+ lines to 3-5 lines per test.

**Why this priority**: DRY principle - common patterns should have helper functions. i3 testsuite uses helpers like `focus_after()` and `focused_workspace_after()` extensively. Makes tests easier to write and maintain.

**Independent Test**: Write a focus test using `focusAfter()` helper - test is 5 lines vs 20 lines without helper, and reads like plain English.

**Acceptance Scenarios**:

1. **Given** test needs to verify focus after command, **When** test uses `focusAfter(command)` helper, **Then** helper returns focused window ID after synchronization
2. **Given** test needs to check workspace after switching, **When** test uses `focusedWorkspaceAfter(command)` helper, **Then** helper returns workspace number after sync
3. **Given** test needs to count windows, **When** test uses `windowCountAfter(command)` helper, **Then** helper returns accurate count
4. **Given** test uses helpers, **When** comparing to manual implementation, **Then** test has 70% less code

---

### User Story 4 - Test Coverage Visibility (Priority: P3)

Test developers can generate HTML coverage reports showing which sway-test framework code is tested. This helps identify untested code paths and validates that new features have adequate test coverage.

**Why this priority**: Nice-to-have for quality assurance. Helps identify gaps in test coverage but doesn't block immediate testing needs. i3 testsuite uses lcov for coverage reporting.

**Independent Test**: Run `deno test --coverage` and generate HTML report - shows percentage coverage and untested lines highlighted.

**Acceptance Scenarios**:

1. **Given** test suite runs with coverage enabled, **When** coverage report is generated, **Then** report shows line/branch coverage percentages
2. **Given** developer adds new action type, **When** developer writes tests for it, **Then** coverage report shows >90% coverage for new code
3. **Given** developer views HTML coverage report, **When** clicking on file names, **Then** report highlights tested (green) and untested (red) lines
4. **Given** CI/CD pipeline runs tests, **When** coverage falls below threshold, **Then** pipeline fails with coverage report

---

### User Story 5 - Organized Test Structure by Category (Priority: P3)

Test developers can organize tests into logical categories (basic, integration, regression) mirroring i3 testsuite structure. This makes finding and running specific test types easy.

**Why this priority**: Quality of life improvement. Makes test suite more maintainable but doesn't affect core testing functionality.

**Independent Test**: Organize existing tests into subdirectories - `basic/`, `integration/`, `regression/` - and run specific categories with `deno test tests/integration/`.

**Acceptance Scenarios**:

1. **Given** tests are organized by category, **When** developer runs `deno test tests/basic/`, **Then** only basic functionality tests execute
2. **Given** tests are organized by category, **When** new regression test is needed, **Then** developer knows to place it in `tests/regression/`
3. **Given** tests follow numbering convention, **When** viewing test directory, **Then** tests are sorted by feature area (01-workspace, 02-window-focus, etc.)
4. **Given** tests are categorized, **When** CI runs tests, **Then** test results are grouped by category in output

---

### Edge Cases

- What happens when synchronization timeout is exceeded (Sway unresponsive)?
  - Test should fail gracefully with clear error message, not hang indefinitely
  - Default sync timeout: 5 seconds (reasonable for normal operation)

- How does system handle sync during rapid sequential commands?
  - Each sync waits for ALL prior commands to complete via X11
  - No need for additional delays between syncs

- What if test launches app but app crashes immediately?
  - Sync completes successfully (command was sent)
  - Subsequent state verification catches missing window

- How does sync interact with asynchronous window manager events?
  - Sync only guarantees Sway→X11 command processing is complete
  - Does not control timing of external events (user input simulation, etc.)

- What happens when running tests in parallel?
  - Each test uses isolated X11 markers (unique IDs)
  - Syncs don't interfere with each other

## Requirements *(mandatory)*

### Functional Requirements

**Core Synchronization Mechanism**:

- **FR-001**: SwayClient MUST provide `sync()` method that guarantees all prior Sway IPC commands have been fully processed by X11 server
- **FR-002**: Sync mechanism MUST use unique markers per synchronization call to avoid conflicts when running parallel tests
- **FR-003**: Sync MUST complete within 5 seconds or fail with timeout error (prevents hanging tests)
- **FR-004**: Sync MUST use Sway's mark/unmark IPC commands as synchronization primitives (similar to i3's I3_SYNC protocol)

**Enhanced Test Actions**:

- **FR-005**: Test framework MUST support `sync` action type for explicit synchronization in test JSON
- **FR-006**: Test framework MUST support `launch_app_sync` action that launches app and automatically synchronizes before continuing
- **FR-007**: Test framework MUST support `send_ipc_sync` action that sends IPC command and automatically synchronizes
- **FR-008**: Sync actions MUST be backward compatible (existing tests without sync continue working)

**Convenience Methods**:

- **FR-009**: SwayClient MUST provide `getTreeSynced()` method that syncs before capturing tree state
- **FR-010**: SwayClient MUST provide `sendCommandSync()` method that sends command and syncs automatically

**Test Helper Functions**:

- **FR-011**: Framework MUST provide `focusAfter(command)` helper that returns focused window ID after command executes
- **FR-012**: Framework MUST provide `focusedWorkspaceAfter(command)` helper that returns workspace number after command executes
- **FR-013**: Framework MUST provide `windowCountAfter(command)` helper that returns window count after command executes
- **FR-014**: Helpers MUST use synchronization internally (developers don't need to manually sync)

**Test Organization**:

- **FR-015**: Test directory structure MUST support categorization: `tests/basic/`, `tests/integration/`, `tests/regression/`
- **FR-016**: Test files SHOULD follow naming convention: `NN-feature-name.json` where NN is two-digit number (e.g., `01-workspace-switch.json`)

**Coverage Reporting**:

- **FR-017**: Framework MUST support running tests with coverage tracking via `deno test --coverage`
- **FR-018**: Coverage reports MUST be generatable in HTML format showing line/branch coverage
- **FR-019**: Coverage MUST exclude test files themselves (only measure framework code coverage)

**Documentation and Examples**:

- **FR-020**: Framework MUST provide example tests demonstrating sync patterns
- **FR-021**: Framework MUST document migration path from timeout-based to sync-based tests
- **FR-022**: Quickstart guide MUST show before/after examples of sync vs timeout approaches

**Performance Targets**:

- **FR-023**: Sync operation MUST complete in <10ms under normal conditions (fast X11 server)
- **FR-024**: Test suite MUST achieve 50% reduction in total runtime when migrated to sync-based approach
- **FR-025**: Individual test with sync MUST be 5-10x faster than equivalent test with 10-second timeout

### Key Entities

- **SyncMarker**: Unique identifier for each synchronization operation (timestamp + random string)
  - Ensures parallel tests don't interfere
  - Used in mark/unmark IPC commands

- **TestAction**: Existing test action with three new types
  - `sync`: Explicit synchronization point
  - `launch_app_sync`: App launch with auto-sync
  - `send_ipc_sync`: IPC command with auto-sync

- **TestHelper**: Reusable function that encapsulates common test patterns
  - Takes command string as input
  - Returns specific state value (window ID, workspace number, count)
  - Internally handles synchronization

- **CoverageReport**: HTML/text report showing code coverage metrics
  - Line coverage percentage
  - Branch coverage percentage
  - Untested code highlighted

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Test developers can run Firefox workspace assignment test without race conditions - 100% success rate vs current ~90%
- **SC-002**: Test suite total runtime reduces from ~50 seconds to ~25 seconds (50% improvement)
- **SC-003**: Individual tests complete 5-10x faster than timeout-based equivalents (measured via benchmark)
- **SC-004**: Sync operation completes in <10ms for 95% of operations (measured via performance logging)
- **SC-005**: Test code using helpers is 70% shorter than manual implementation (line count comparison)
- **SC-006**: Developers can generate coverage reports showing >85% framework code coverage
- **SC-007**: Zero tests hang indefinitely (all syncs timeout within 5 seconds if Sway is unresponsive)
- **SC-008**: Test flakiness rate reduces from 5-10% to <1% (measured over 100 test runs)
- **SC-009**: Developer productivity improves - tests run frequently enough to catch bugs within same work session (subjective but observable)
- **SC-010**: New tests written after sync implementation use sync actions >90% of the time (indicates adoption)

## Assumptions

- **A-001**: Sway IPC mark/unmark commands are reliable and fast (<5ms typical latency)
- **A-002**: X11 server processes requests in order (FIFO) for same client connection
- **A-003**: Sway responds to IPC commands even under moderate load (doesn't drop requests)
- **A-004**: Test environment has single X11 server instance (not multiple nested X servers)
- **A-005**: Deno's test coverage tool (`deno test --coverage`) is sufficient for coverage reporting
- **A-006**: Existing tests can run unchanged during migration (backward compatibility maintained)
- **A-007**: Test developers are familiar with JSON test format (no need to learn new syntax)
- **A-008**: Sync timeout of 5 seconds is sufficient for slowest reasonable test environment
- **A-009**: Test execution is sequential within single test file (parallel test files are isolated)
- **A-010**: Framework maintainers will update existing tests gradually (not big-bang migration)

## Dependencies

- **D-001**: Sway window manager with IPC support (already present)
- **D-002**: Deno runtime 1.40+ for test execution and coverage (already present)
- **D-003**: Existing sway-test framework architecture (SwayClient, test action system)
- **D-004**: Feature 068 state comparison enhancements (recently completed)
- **D-005**: Access to i3 testsuite documentation for reference patterns

## Out of Scope

- **OS-001**: Modifying Sway IPC protocol itself (we use existing mark/unmark commands)
- **OS-002**: Testing window managers other than Sway (framework is Sway-specific)
- **OS-003**: Automated migration of all existing tests (manual migration with tooling support)
- **OS-004**: Real-time test execution monitoring UI (command-line output is sufficient)
- **OS-005**: Test parallelization within single test file (tests run sequentially per file)
- **OS-006**: Socket activation for test isolation (i3-specific pattern, not needed for Sway tests)
- **OS-007**: Perl-based test implementation (we use TypeScript/Deno, not Perl)
- **OS-008**: X11 ClientMessage protocol (we use Sway IPC, not raw X11 messages)

## Constraints

- **C-001**: Backward compatibility - existing tests without sync must continue working
- **C-002**: Performance - sync overhead must be <10ms (negligible compared to 10s timeout savings)
- **C-003**: Reliability - sync must not introduce new failure modes (robust timeout handling)
- **C-004**: Simplicity - test developers should not need to understand X11 internals
- **C-005**: Maintainability - sync implementation should be <100 lines of code
- **C-006**: Documentation - all sync patterns must have clear examples in quickstart guide
- **C-007**: Testing - sync mechanism itself must have unit tests (test the tests)
- **C-008**: Standards - follow i3 testsuite synchronization patterns where applicable
