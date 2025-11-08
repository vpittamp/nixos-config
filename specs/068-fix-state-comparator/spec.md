# Feature Specification: Fix State Comparator Bug in Sway Test Framework

**Feature Branch**: `068-fix-state-comparator`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "Fix state comparison bug in sway-test framework that causes all tests to fail after successful action execution"

## User Scenarios & Testing

### User Story 1 - Test Execution Completes Successfully (Priority: P1)

As a test framework user, I want my tests to pass when all actions execute successfully and the actual state matches the expected state, so that I can confidently validate my Sway window manager configuration.

**Why this priority**: This is the core functionality of the test framework. Without accurate state comparison, the framework cannot reliably validate system behavior, making it unusable for its primary purpose.

**Independent Test**: Run any existing test in the framework (e.g., `test_window_launch.json`). When all actions complete successfully and the actual window state matches expectations, the test should pass with a success status, not fail with "state comparison failed" error.

**Acceptance Scenarios**:

1. **Given** a test with valid actions and matching expected state, **When** the test executes, **Then** the test passes and shows success status (no "state comparison failed" error)
2. **Given** a test that launches a window on workspace 1, **When** the window appears on workspace 1 as expected, **Then** the state comparator reports a match and the test passes
3. **Given** a test that switches to workspace 3, **When** workspace 3 becomes focused, **Then** the state comparator validates the focused workspace correctly

---

### User Story 2 - Accurate Failure Detection (Priority: P1)

As a test framework user, I want tests to fail only when there is an actual mismatch between expected and actual state, so that I can identify real issues in my window manager configuration.

**Why this priority**: Accurate failure detection is equally critical as success detection - false negatives are as problematic as false positives. Users need to trust that failures indicate real problems.

**Independent Test**: Run a test with intentionally mismatched expected state (e.g., expect window on workspace 1 but it appears on workspace 2). The test should fail with a clear diff showing the actual mismatch, not a generic "state comparison failed" error.

**Acceptance Scenarios**:

1. **Given** a test expecting a window on workspace 1, **When** the window actually appears on workspace 2, **Then** the test fails with a clear diff showing workspace mismatch
2. **Given** a test expecting 2 windows, **When** only 1 window exists, **Then** the test fails showing the window count difference
3. **Given** a test expecting a focused window, **When** no window is focused, **Then** the test fails indicating the focus mismatch

---

### User Story 3 - Clear Error Messages for Debugging (Priority: P2)

As a test framework user, I want clear error messages when state comparison fails, so that I can quickly understand what went wrong and fix my tests or configuration.

**Why this priority**: While working state comparison is P1, enhanced error messages improve developer experience but aren't blocking for basic functionality.

**Independent Test**: Introduce a deliberate mismatch in a test's expected state. The error message should clearly indicate what was expected, what was found, and where in the state tree the difference occurred.

**Acceptance Scenarios**:

1. **Given** a state mismatch in workspace number, **When** comparison fails, **Then** error shows "Expected workspace: 1, Actual workspace: 3"
2. **Given** a mismatch in window count, **When** comparison fails, **Then** error shows "Expected 2 windows, Found 1 window"
3. **Given** a missing window property, **When** comparison fails, **Then** error indicates which property is missing and from which window

---

### Edge Cases

- What happens when the expected state is empty (`{}`) but actual state has windows?
- How does the comparator handle partial state matching (only validating workspace number, ignoring window details)?
- What happens when the expected state contains properties that don't exist in the actual Sway tree structure?
- How does the system handle undefined vs null vs missing properties in state comparison?
- What happens when comparing arrays of different lengths (e.g., expected 2 workspaces, actual has 5)?

## Requirements

### Functional Requirements

- **FR-001**: State comparator MUST correctly identify when actual state matches expected state
- **FR-002**: State comparator MUST pass tests when all actions execute successfully and states match
- **FR-003**: State comparator MUST fail tests only when actual state differs from expected state
- **FR-004**: State comparator MUST support partial state matching (validating subset of properties)
- **FR-005**: State comparator MUST handle empty expected states (`{}` or omitted properties)
- **FR-006**: State comparator MUST provide clear diff output showing differences between expected and actual states
- **FR-007**: State comparator MUST support nested object comparison (workspaces, windows, properties)
- **FR-008**: State comparator MUST handle array comparisons (workspace lists, window lists)
- **FR-009**: State comparator MUST distinguish between undefined, null, and missing properties
- **FR-010**: State comparator MUST work with all existing test action types (launch_app, wait_event, send_ipc, etc.)

### Key Entities

- **ExpectedState**: The target state definition in a test case, containing optional properties for workspace count, focused workspace, window properties, and custom assertions
- **ActualState**: The captured Sway window tree state from `swaymsg -t get_tree`, containing full hierarchy of workspaces, containers, and windows
- **StateDiff**: The comparison result showing matches, mismatches, and missing/extra properties between expected and actual states
- **ComparisonMode**: The matching strategy (exact match, partial match, assertion-based) used for validation

## Success Criteria

### Measurable Outcomes

- **SC-001**: All existing framework tests that currently fail with "state comparison failed" error pass successfully when actions execute correctly
- **SC-002**: Tests complete with accurate pass/fail status in 100% of test runs (no false positives or false negatives)
- **SC-003**: State comparison errors include specific property paths and value differences in at least 90% of failure cases
- **SC-004**: State comparator handles empty/partial expected states without throwing errors in 100% of cases
- **SC-005**: Test execution time increases by no more than 5% due to improved comparison logic

## Assumptions

- The test framework is already functional and can execute actions successfully (this was confirmed in Feature 067)
- The Sway IPC `get_tree` command returns consistent, valid JSON structure
- The existing test JSON format for `expectedState` will remain unchanged (backward compatibility required)
- State comparison occurs after all test actions complete, not during action execution
- The bug is isolated to the state comparison logic, not the action execution or state capture mechanisms

## Dependencies

- Requires Feature 001 (sway-test framework foundation)
- Requires Feature 067 (app launch integration) to test realistic scenarios
- No external service dependencies
- No new daemon or process requirements

## Out of Scope

- Adding new state validation features beyond fixing the existing comparison bug
- Implementing new test action types
- Performance optimization beyond ensuring no regression
- Adding visual diff tools or GUI comparison viewers
- Modifying the test case JSON schema or format
