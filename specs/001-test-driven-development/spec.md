# Feature Specification: Test-Driven Development Framework for Sway Window Manager

**Feature Branch**: `001-test-driven-development`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "Design a test-driven development framework for Sway window manager system testing. Enable comparison of expected vs actual system state from `swaymsg tree` output, using Deno runtime for CLI tooling and Python backend for daemon APIs. Incorporate I3_SYNC protocol patterns, socket activation, and test isolation. Build on existing `i3pm tree-monitor live` feature to enable testing of project management, workspace assignment, and application launching with environment injection."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic State Comparison Testing (Priority: P1)

As a developer, I want to write simple test cases that compare expected vs actual Sway window tree state, so I can verify that my window management features work correctly.

**Why this priority**: This is the foundation of the entire test framework. Without the ability to compare expected vs actual state, no other testing capability is possible. This delivers immediate value by enabling developers to catch regressions in window management behavior.

**Independent Test**: Can be fully tested by running a single test case that launches a window, captures the state, and compares it against a predefined expected state. Delivers value by catching window positioning bugs.

**Acceptance Scenarios**:

1. **Given** a test case with an expected window tree state (JSON), **When** I execute the test case, **Then** the framework captures the actual state from `swaymsg -t get_tree`, compares it to expected state, and reports differences with clear error messages showing what changed.

2. **Given** a test case where expected and actual states match, **When** I run the test, **Then** the test passes with a success message indicating all assertions passed.

3. **Given** multiple test cases in a test suite, **When** I run the suite, **Then** each test executes independently with isolated state, and I receive a summary showing passed/failed/skipped counts.

---

### User Story 2 - Action Sequence Execution (Priority: P2)

As a developer, I want to define sequences of user actions (keybindings, IPC commands) that the test framework executes before capturing state, so I can test interactive workflows like project switching and workspace navigation.

**Why this priority**: Most real-world bugs occur during state transitions (e.g., switching projects, moving windows between workspaces). This enables testing of complex user journeys that represent actual usage patterns.

**Independent Test**: Can be tested by defining a multi-step test (launch app → switch workspace → verify window moved) and confirming each action executes in sequence with proper timing.

**Acceptance Scenarios**:

1. **Given** a test case with action sequence `[launch_app("firefox"), switch_workspace(2), focus_window("firefox")]`, **When** test executes, **Then** each action runs sequentially with configurable delays, and final state shows Firefox focused on workspace 2.

2. **Given** an action sequence that includes IPC commands (`i3pm project switch nixos`), **When** test executes, **Then** the framework waits for daemon acknowledgment before proceeding to next action, ensuring deterministic execution.

3. **Given** an action fails mid-sequence (e.g., app doesn't launch within timeout), **When** test runs, **Then** framework reports which action failed, captures diagnostic state (logs, tree snapshot), and marks test as failed with actionable error message.

---

### User Story 3 - Live Debugging and Interactive Development (Priority: P2)

As a developer, I want to pause test execution at any point, inspect the current state interactively, and modify the test on the fly, so I can rapidly iterate on test development without full rebuild cycles.

**Why this priority**: Developer experience is critical for adoption. Fast iteration cycles dramatically reduce time to write and debug tests. This addresses the "test-driven" part of TDD by making tests easy to evolve.

**Independent Test**: Can be tested by running a test with a breakpoint, verifying the interactive prompt appears with state inspection commands available, and confirming changes to test definition take effect immediately.

**Acceptance Scenarios**:

1. **Given** a test with a `debug_pause()` action in sequence, **When** test executes and reaches pause point, **Then** framework drops into interactive REPL showing current tree state, available commands, and allows manual IPC commands for exploration.

2. **Given** a paused test in debug mode, **When** I modify the test definition file and save it, **Then** framework detects change, reloads test definition, and offers to continue with updated steps or restart from beginning.

3. **Given** I'm in debug mode inspecting state, **When** I run command `show_diff()`, **Then** framework displays visual diff between current actual state and expected state from test definition, highlighting mismatches.

---

### User Story 4 - I3_SYNC-Style Synchronization Protocol (Priority: P3)

As a developer, I want the test framework to synchronize with Sway's event loop deterministically (similar to i3 test suite's I3_SYNC), so tests avoid race conditions when waiting for window events to complete.

**Why this priority**: While important for reliability, basic timeout-based waiting can work for initial MVP. This is optimization for flaky test elimination.

**Independent Test**: Can be tested by running rapid-fire window operations (create 10 windows in 100ms) and verifying framework correctly waits for all events to settle before capturing state, with 0% flakiness over 100 runs.

**Acceptance Scenarios**:

1. **Given** a test that launches multiple windows in quick succession, **When** test uses `await_sync()` after launches, **Then** framework sends sync marker through Sway IPC, waits for marker event to return, ensuring all prior events have processed.

2. **Given** a test performing workspace switch, **When** action includes `sync: true` flag, **Then** framework automatically waits for sync before proceeding, without manual delays or timeouts.

3. **Given** daemon is processing background events (e.g., tree-monitor correlation), **When** test requests sync, **Then** framework waits for both Sway event queue AND daemon processing queue to be empty before continuing.

---

### User Story 5 - Test Case Organization and Reusability (Priority: P3)

As a developer, I want to organize tests into logical suites, define reusable fixtures (common setup/teardown), and share helper functions across test files, so I can maintain a clean and scalable test codebase.

**Why this priority**: Important for long-term maintainability but not required for initial testing capability. Can start with simple standalone test files.

**Independent Test**: Can be tested by defining a fixture (e.g., "3-monitor layout preset"), referencing it from multiple test files, and verifying setup runs once before tests and cleanup runs after, with shared state accessible.

**Acceptance Scenarios**:

1. **Given** multiple test files importing a shared fixture `@fixture workspace_with_firefox`, **When** tests run, **Then** fixture setup executes before each test, teardown after, and tests receive initialized state object.

2. **Given** test files organized in directory structure (`tests/project-management/`, `tests/workspace-assignment/`), **When** I run `sway-test tests/project-management/`, **Then** only tests in that directory execute, preserving hierarchy in output.

3. **Given** reusable assertion helpers (`assertWindowFloating()`, `assertWorkspaceEmpty()`), **When** test imports and calls them, **Then** helpers provide clear failure messages with context (e.g., "Expected window 'firefox' to be floating, but found tiled on workspace 3").

---

### User Story 6 - Integration with Existing tree-monitor Tools (Priority: P1)

As a developer, I want test framework to leverage existing `i3pm tree-monitor` infrastructure for event capture and state snapshots, so I benefit from proven correlation algorithms and diff computation without duplication.

**Why this priority**: Reusing battle-tested code reduces implementation time and inherits existing stability. Tree-monitor already captures events, computes diffs, and correlates user actions - all valuable for test diagnostics.

**Independent Test**: Can be tested by running a test that triggers window change, verifying framework captures event via tree-monitor RPC, and includes correlation data (user action + binding) in test failure output.

**Acceptance Scenarios**:

1. **Given** tree-monitor daemon is running, **When** test framework initializes, **Then** framework connects to daemon's Unix socket, verifies connectivity via ping, and subscribes to event stream for duration of test run.

2. **Given** a test that moves a window between workspaces, **When** test completes, **Then** framework includes tree-monitor event log in test output showing exactly what changed (field-level diffs), correlated with test actions.

3. **Given** a test failure where actual state doesn't match expected, **When** test reports failure, **Then** output includes latest tree-monitor event with significance score, helping developer understand what unexpected change occurred.

---

### User Story 7 - CI/CD Integration (Priority: P3)

As a developer, I want test framework to run in headless CI environments (GitHub Actions, GitLab CI), producing machine-readable output (TAP, JUnit XML) and exiting with appropriate status codes, so tests gate deployments and pull requests.

**Why this priority**: Essential for production readiness but not needed for local development workflow. Can be added after core testing works locally.

**Independent Test**: Can be tested by running test suite in Docker container with no X11/Wayland access, verifying it starts Sway in headless mode (WLR_BACKENDS=headless), runs tests, and produces JUnit XML report with correct pass/fail counts.

**Acceptance Scenarios**:

1. **Given** test suite running in CI with `--ci` flag, **When** any test fails, **Then** framework exits with non-zero status code and produces parseable output in requested format (--format=tap or --format=junit).

2. **Given** CI environment with no display server, **When** test framework starts, **Then** it automatically launches Sway in headless mode using virtual outputs, runs tests against headless instance, and cleans up on exit.

3. **Given** test suite with 100 tests taking 5+ minutes, **When** running in CI, **Then** framework outputs progress indicators (e.g., "42/100 passed") every 10 seconds so CI doesn't timeout, and provides test timing statistics for performance regression detection.

---

### Edge Cases

- **What happens when daemon is not running?** Framework detects missing socket connection, provides helpful error message with daemon start command (`systemctl --user start sway-tree-monitor`), and exits gracefully.

- **What happens when test hangs waiting for window event?** Framework enforces configurable global timeout (default 30s per test), captures diagnostic snapshot (tree state, daemon logs, pending IPC operations), and marks test as timeout failure with diagnostic context.

- **What happens when Sway crashes during test?** Framework detects Sway socket disconnection, marks test as environment failure (not test failure), captures crash logs from journalctl, and provides recovery options (restart Sway, skip remaining tests, abort suite).

- **What happens when expected state file is malformed?** Framework validates expected state JSON against schema on test load, reports parse errors with line/column numbers, and refuses to run test until fixed (fail-fast principle).

- **What happens when multiple tests modify same global state (e.g., workspace layout)?** Framework provides test isolation options: (1) automatic cleanup between tests (restore to empty state), (2) explicit fixtures declaring state requirements, (3) parallel execution with separate Sway instances for fully independent tests.

- **What happens when test involves timing-sensitive operations (e.g., animation durations)?** Framework provides `await_stable()` helper that polls tree state until no changes detected for configurable duration (default 100ms), ensuring animations/transitions complete before capture.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Test framework MUST capture actual Sway window tree state via `swaymsg -t get_tree` and parse output as structured data for comparison.

- **FR-002**: Test framework MUST accept expected state definitions in JSON format matching `swaymsg -t get_tree` structure, with support for partial matching (e.g., "workspace 3 has at least one Firefox window" without specifying exact geometry).

- **FR-003**: Test framework MUST execute action sequences defined in test cases, including: launching applications with environment variables, sending IPC commands, simulating keybindings, and waiting for conditions.

- **FR-004**: Test framework MUST integrate with `i3pm tree-monitor` daemon via JSON-RPC over Unix socket, enabling access to event history, field-level diffs, and user action correlation during test execution.

- **FR-005**: Test framework MUST provide clear diff output when expected and actual states diverge, highlighting specific fields that changed with values shown (e.g., "Expected workspace[3].focused = true, got false").

- **FR-006**: Test framework MUST support synchronization primitives to avoid race conditions, including: waiting for specific events, polling state until stable, and I3_SYNC-style deterministic synchronization with Sway event loop.

- **FR-007**: Test framework MUST provide interactive debugging mode allowing developers to pause execution, inspect current state, manually execute IPC commands, and modify test definitions without restarting test run.

- **FR-008**: Test framework MUST use Deno runtime and Deno standard library for all user-facing CLI tooling (test runner, state comparison, reporting), ensuring TypeScript support and modern JavaScript features.

- **FR-009**: Test framework MUST enhance Python backend APIs as needed to support test execution (e.g., adding RPC methods for sync markers, state snapshots, test-scoped event filtering).

- **FR-010**: Test framework MUST support test isolation by allowing tests to run with separate Sway configuration files, preventing cross-test interference from window rules or workspace assignments.

- **FR-011**: Test framework MUST provide fixtures system for reusable setup/teardown logic (e.g., "launch 3-monitor layout", "create project with 5 workspaces", "populate workspace with specific apps").

- **FR-012**: Test framework MUST output test results in multiple formats: human-readable terminal output with colors/formatting, machine-readable TAP protocol, and JUnit XML for CI integration.

- **FR-013**: Test framework MUST handle daemon unavailability gracefully, providing actionable error messages and recovery suggestions (e.g., "daemon not running - start with systemctl --user start sway-tree-monitor").

- **FR-014**: Test framework MUST enforce per-test timeout (default 30s, configurable), capturing diagnostic state on timeout and marking test as failed with timeout context.

- **FR-015**: Test framework MUST support running in headless CI environments by automatically detecting absence of display server and launching Sway with WLR_BACKENDS=headless.

- **FR-016**: Test framework MUST validate test definitions on load, checking for syntax errors, missing required fields, and malformed expected state schemas, failing fast with clear error messages.

- **FR-017**: Test framework MUST provide helper utilities for common assertions (window count, workspace existence, focus state, floating/tiling status, window geometry ranges) with descriptive failure messages.

- **FR-018**: Test framework MUST log all IPC communications, action executions, and state captures to structured log file (JSON Lines format) for post-test debugging and performance analysis.

- **FR-019**: Test framework MUST support selective test execution via filters (by name pattern, by tag, by suite directory, by priority level) to enable rapid iteration on specific functionality.

- **FR-020**: Test framework MUST measure and report test execution time per test and per suite, enabling performance regression detection and identification of slow tests.

### Key Entities

- **TestCase**: Represents a single test with unique name, description, optional tags, setup actions, test actions, expected state definition, and assertions to run. Includes metadata like priority, timeout override, and fixture dependencies.

- **ActionSequence**: Ordered list of actions to execute during test, where each action has type (launch_app, send_ipc, simulate_key, wait_event, debug_pause), parameters (app_id, command, timeout), and sync requirements (whether to wait for completion).

- **StateSnapshot**: Captured Sway window tree at a point in time, parsed from `swaymsg -t get_tree` JSON output. Includes root node, all workspaces, containers, windows with full properties (id, name, type, geometry, focused state, etc.).

- **ExpectedState**: Test author's definition of what state should look like, supporting exact matching (full tree structure) or partial matching (assertions about specific properties, e.g., "workspace 3 contains window with app_id='firefox'").

- **StateDiff**: Computed difference between expected and actual state, showing added/removed/modified nodes with field-level changes (old value → new value) similar to tree-monitor diff format.

- **TestFixture**: Reusable setup/teardown logic with unique name, setup function (runs before test), teardown function (runs after test), and shared state object accessible to tests. Examples: monitor layouts, project definitions, pre-populated workspaces.

- **TestSuite**: Collection of related test cases, organized by directory or explicit grouping, with suite-level fixtures and configuration (timeout defaults, isolation mode, output format).

- **SyncMarker**: Mechanism for deterministic synchronization with Sway, using unique ID sent through IPC, awaiting corresponding event callback to ensure event queue drained.

- **TestExecutionContext**: Runtime state during test execution, including: current Sway connection, tree-monitor RPC client, event log buffer, debug mode flag, timeout handler, and isolation configuration (config file path, headless mode).

- **TestResult**: Outcome of single test execution with status (passed/failed/skipped/timeout/error), execution time, captured state snapshots, event logs from tree-monitor, diff output if failed, and diagnostic context (stderr, Sway logs).

- **TreeMonitorEvent**: Event captured by tree-monitor daemon during test execution, including event ID, timestamp, type, field-level changes (diff), user action correlation, and significance score. Used for test diagnostics and debugging.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can write and execute a basic state comparison test (launch app, verify window exists on workspace) in under 5 minutes using test framework CLI.

- **SC-002**: Test framework correctly identifies state mismatches with 100% accuracy across 50+ test cases covering window management, workspace operations, and multi-monitor scenarios.

- **SC-003**: Test execution latency is under 2 seconds per test for simple cases (launch app + verify), and under 10 seconds for complex multi-step scenarios (project switch + multiple apps).

- **SC-004**: Test framework eliminates race conditions with I3_SYNC-style synchronization, achieving 0% flaky test rate over 1000 consecutive test runs.

- **SC-005**: Interactive debugging mode enables developers to identify test failures in under 3 minutes by inspecting state at pause points and reviewing tree-monitor event correlation.

- **SC-006**: Test framework runs successfully in headless CI environment (GitHub Actions) with 100% pass rate for passing tests and 0 false failures due to environment issues.

- **SC-007**: Integration with existing tree-monitor reduces duplicate code by at least 80% compared to building separate event capture and diff computation.

- **SC-008**: Test framework produces clear, actionable failure messages that include: what expected, what got, field-level diff, correlated user actions from tree-monitor, and suggested fixes - as validated by 90% of developers finding error messages helpful in user testing.

- **SC-009**: Test suite execution time scales linearly with number of tests, with overhead of less than 100ms per test for framework initialization and cleanup.

- **SC-010**: Test framework supports organizing 100+ test cases across multiple suites/directories without performance degradation, with selective execution (run 10 tests from suite of 100) completing in under 20 seconds.
