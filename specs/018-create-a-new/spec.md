# Feature Specification: i3 Project System Testing & Debugging Framework

**Feature Branch**: `018-create-a-new`
**Created**: 2025-10-20
**Status**: Draft
**Input**: User description: "create a new feature. given the i3-project-monitor tool is working so well, i want to enhance its functionality to serve as a debugging/testing mechanism for our i3 project related python functionality we created that manages projects via monitors/workspaces, etc. this feature's objective will be to further analyze the functionality of our project management workflow and it's integration with i3wm, and then enhance/refine our monitor tool to test/debug if our functionality is working. we may even create automated tests that simulate the user experience of creating/deleting project, and then navigating/switching projects, etc. and confirming that our logic is producing the correct behavior and tracking state effectively. use the monitoring tool in separate tmux sessions in order to execute commands separately, and then review the tools output relative to our monitoring tools to determine if its working. also include enhanced functionality around tracking monitors/displays and making sure workspaces are showing correctly relative to what monitors they show on. consider using arandr/xrandr applications as needed to help. also, its worth stressing again that our implementation should align as closely as possible with i3wm, and its api's."

**Key Design Principle**: This feature MUST align with i3wm's native IPC API. All state queries, workspace assignments, and monitor tracking should use i3's native message types (GET_WORKSPACES, GET_OUTPUTS, GET_TREE, GET_MARKS) to ensure consistency with i3's actual state.

## User Scenarios & Testing

### User Story 1 - Manual Interactive Testing with Live Monitoring (Priority: P1) 🎯 MVP

As a developer maintaining the i3 project management system, I need to run project commands while simultaneously observing system state in real-time, so I can verify that state transitions occur correctly and debug issues as they happen.

**Why this priority**: This is the foundation for all debugging - the ability to see what's happening in real-time. Without this, developers cannot diagnose issues or verify fixes. This story enables immediate value by providing visual feedback for manual testing.

**Independent Test**: Run the monitor in one tmux pane, execute `i3-project-switch nixos` in another pane, and visually confirm that:
- The live monitor shows "Active Project: nixos" within 1 second
- Event stream displays the tick event with project change payload
- Window table updates to show only nixos-scoped windows
- Monitor panel shows correct workspace-to-output assignments using i3's GET_OUTPUTS and GET_WORKSPACES data

**Acceptance Scenarios**:

1. **AS1.1**: **Given** no monitor is running, **When** developer launches monitor in tmux pane with `tmux split-window -h 'i3-project-monitor live'`, **Then** live dashboard displays current daemon state and updates every 250ms, including real-time monitor/output information from i3's GET_OUTPUTS IPC call
2. **AS1.2**: **Given** live monitor is running in one pane and shell is in another pane, **When** developer executes `i3-project-switch stacks`, **Then** monitor shows project change within 1 second and displays updated window list filtered by project
3. **AS1.3**: **Given** event stream monitor is running (`i3-project-monitor events`), **When** developer creates a new terminal window, **Then** event stream displays window::new, window::mark, and window::focus events with timestamps and processing duration
4. **AS1.4**: **Given** both live and event monitors are running in split panes, **When** developer switches between projects, **Then** both monitors reflect state changes synchronously and show no lag or missing events
5. **AS1.5**: **Given** live monitor displays workspace assignments, **When** developer runs `xrandr` to change monitor configuration or connects/disconnects a display, **Then** monitor detects output change event via i3 IPC and updates workspace-to-monitor mappings within 1 second to reflect actual i3 state

---

### User Story 2 - Automated State Validation Testing (Priority: P2)

As a developer making changes to the project management code, I need to run automated tests that simulate user workflows and verify state correctness, so I can catch regressions before deploying changes.

**Why this priority**: Manual testing is time-consuming and error-prone. Automated tests provide confidence that changes don't break existing functionality and can be run in CI/CD pipelines.

**Independent Test**: Run `i3-project-test verify-state` which creates a test project, switches to it, opens windows, and validates that:
- Daemon reports correct active project
- Windows are marked with correct project tags
- Monitor tool shows expected state
- Workspace-to-output assignments match i3's GET_OUTPUTS and GET_WORKSPACES data
Test passes if all assertions succeed, fails with detailed diff if state doesn't match expectations.

**Acceptance Scenarios**:

1. **AS2.1**: **Given** a test script that simulates project workflow, **When** script runs test scenario "create and switch project", **Then** test validates daemon state matches expected values and reports pass/fail with details
2. **AS2.2**: **Given** a project exists with 3 windows, **When** automated test switches away and back to the project, **Then** test verifies all 3 windows remain correctly marked and visible
3. **AS2.3**: **Given** automated test suite with 10 test scenarios, **When** developer runs full test suite, **Then** each scenario runs independently and reports results in machine-readable format (exit code, JSON output)
4. **AS2.4**: **Given** a test that expects 5 events, **When** test captures daemon event stream for 2 seconds, **Then** test validates correct event types, order, and payloads match expectations
5. **AS2.5**: **Given** a multi-monitor setup with known configuration, **When** automated test queries workspace assignments via i3's GET_WORKSPACES IPC, **Then** test verifies each workspace is assigned to correct output and matches monitor tool's display
6. **AS2.6**: **Given** a test scenario that simulates monitor disconnect, **When** test runs xrandr command to disable output, **Then** test validates i3's GET_OUTPUTS data reflects change and workspace reassignments occur correctly

---

### User Story 3 - Diagnostic Reporting and State Inspection (Priority: P3)

As a developer debugging a production issue, I need to capture a complete snapshot of current system state and recent history, so I can analyze what went wrong without needing to reproduce the issue.

**Why this priority**: When issues occur in production or during complex workflows, having a comprehensive diagnostic dump helps identify root causes. This is less critical than real-time monitoring but valuable for post-mortem analysis.

**Independent Test**: Run `i3-project-monitor diagnose --output=report.json` which captures:
- Current daemon status and configuration
- All active projects and their window assignments
- Last 500 events from event buffer
- i3 tree structure with project marks
- Complete output configuration from i3's GET_OUTPUTS IPC
- Workspace-to-output assignments from i3's GET_WORKSPACES IPC
Test succeeds if report contains all expected sections and is valid JSON.

**Acceptance Scenarios**:

1. **AS3.1**: **Given** system is in a known state with 3 projects, **When** developer runs diagnostic capture, **Then** output includes complete current state (projects, windows, marks) and last 500 events, plus complete monitor/output configuration
2. **AS3.2**: **Given** a diagnostic report file, **When** developer opens it, **Then** report is human-readable JSON with timestamps, event details, and state snapshots organized by section
3. **AS3.3**: **Given** a suspected state corruption, **When** developer captures diagnostic report, **Then** report includes i3 tree structure showing actual marks and daemon state showing expected marks for comparison
4. **AS3.4**: **Given** multiple diagnostic reports from different times, **When** developer compares them, **Then** reports use consistent schema and can be diffed to identify state changes over time
5. **AS3.5**: **Given** a suspected workspace assignment issue, **When** developer captures diagnostic report, **Then** report includes complete i3 output state (active, dimensions, workspaces) and workspace assignments, enabling comparison of expected vs actual monitor configurations

---

### User Story 4 - Automated Integration Test Suite (Priority: P4)

As a CI/CD pipeline maintainer, I need a comprehensive test suite that validates end-to-end project management workflows, so I can automatically verify changes before merging.

**Why this priority**: This enables continuous integration and prevents regressions, but requires the foundation of manual testing (P1), automated validation (P2), and diagnostic tooling (P3) to be in place first.

**Independent Test**: Run `i3-project-test suite --ci` in CI environment which:
- Sets up test i3 environment (if in CI)
- Runs all test scenarios from library
- Validates results against expectations
- Outputs test report and returns exit code 0 for success, non-zero for failure
Can be integrated into GitHub Actions or GitLab CI.

**Acceptance Scenarios**:

1. **AS4.1**: **Given** clean test environment, **When** CI runs test suite, **Then** all test scenarios execute without manual intervention and produce pass/fail results
2. **AS4.2**: **Given** a PR that changes project marking logic, **When** CI test suite runs, **Then** relevant test scenarios catch the regression and fail the build with clear error messages
3. **AS4.3**: **Given** test suite completes, **When** developer reviews CI output, **Then** test results are formatted for easy reading with summary showing passed/failed/skipped counts
4. **AS4.4**: **Given** test suite with 20 scenarios, **When** one scenario fails, **Then** remaining scenarios still execute and final report shows which scenarios passed and which failed

---

### Edge Cases

- **EC-001**: What happens when monitor tool tries to connect to daemon but daemon is not running? System should display clear error message with troubleshooting steps, not hang or crash.
- **EC-002**: What happens when automated test switches projects but window marking fails? Test should detect missing marks and fail with diagnostic info showing expected vs actual state.
- **EC-003**: How does system handle test running while another user is actively using i3? Tests should operate in isolated project namespace (test-* prefix) to avoid interfering with user's actual projects.
- **EC-004**: What happens when event stream monitor loses connection during test? Test should detect connection loss, log warning, and either retry connection or fail test with clear error.
- **EC-005**: How does diagnostic capture handle large event buffers (500 events)? Output should be efficiently formatted (compressed JSON) and not exceed reasonable file size limits.
- **EC-006**: What happens when tests run on system without i3wm? Tests should detect environment and either skip i3-specific tests with clear messaging or provide simulation mode.
- **EC-007**: What happens when monitor is disconnected during test execution? System should detect output change event via i3 IPC, log the change, and validate that workspaces reassign correctly according to i3's GET_OUTPUTS response.
- **EC-008**: How does system handle workspace assignment validation when i3 auto-moves workspaces after monitor disconnect? Test should query i3's GET_WORKSPACES to get authoritative state and compare daemon's understanding to i3's actual workspace-to-output mappings.
- **EC-009**: What happens when xrandr reports different resolution than i3's GET_OUTPUTS? System should prioritize i3's IPC data as source of truth and log discrepancy for investigation.

## Requirements

### Functional Requirements

#### Monitor Tool Enhancements

- **FR-001**: Monitor tool MUST support diagnostic capture mode that outputs current system state as structured JSON
- **FR-002**: Monitor tool MUST provide comparison mode that diffs two state snapshots and highlights changes
- **FR-003**: Monitor tool MUST support headless operation (no terminal UI) for automated testing scenarios
- **FR-004**: Monitor tool MUST return machine-readable exit codes indicating success (0) or failure (non-zero) when used in testing mode
- **FR-005**: Monitor tool MUST query i3's GET_OUTPUTS IPC message type to retrieve current output/monitor configuration and display this information in live dashboard
- **FR-006**: Monitor tool MUST query i3's GET_WORKSPACES IPC message type to retrieve workspace-to-output assignments and validate assignments match expected configuration

#### Test Framework

- **FR-007**: System MUST provide test command that executes predefined test scenarios simulating user workflows
- **FR-008**: Test scenarios MUST include: create project, delete project, switch project, open project window, close project window, clear project
- **FR-009**: Test execution MUST use tmux for session management to isolate monitor from test commands
- **FR-010**: Test framework MUST validate state by querying daemon via monitor tool and comparing to expected values
- **FR-011**: Test framework MUST capture event stream during test execution and validate event sequence matches expectations
- **FR-012**: Test framework MUST support xrandr-based display configuration changes and validate system responds correctly to output changes

#### State Validation

- **FR-013**: Tests MUST verify daemon reports correct active project after project switch
- **FR-014**: Tests MUST verify windows are marked with correct project tags after window creation
- **FR-015**: Tests MUST verify window visibility changes when switching between projects
- **FR-016**: Tests MUST verify event buffer contains expected events in correct chronological order
- **FR-017**: Tests MUST validate event payloads contain correct data (window IDs, project names, timestamps)
- **FR-018**: Tests MUST verify workspace-to-output assignments by querying i3's GET_WORKSPACES IPC and comparing output field against GET_OUTPUTS data
- **FR-019**: Tests MUST validate that monitor tool's display state matches i3's authoritative GET_OUTPUTS and GET_WORKSPACES responses

#### Tmux Integration

- **FR-020**: Test framework MUST create tmux session with split panes for monitor and command execution
- **FR-021**: Test framework MUST capture output from both monitor pane and command pane
- **FR-022**: Test framework MUST support cleanup of tmux sessions after test completion
- **FR-023**: Test framework MUST detect if already running in tmux and handle gracefully

#### Reporting

- **FR-024**: Test results MUST be output in both human-readable format (terminal) and machine-readable format (JSON/TAP)
- **FR-025**: Failed tests MUST report expected vs actual values with clear diff showing what didn't match
- **FR-026**: Test reports MUST include timestamps, execution duration, and environment details
- **FR-027**: Diagnostic captures MUST include daemon logs, event history, i3 tree state, complete i3 GET_OUTPUTS response, and complete i3 GET_WORKSPACES response

### Key Entities

- **Test Scenario**: Represents a single test case with setup steps, actions to execute, and expected outcomes to validate
- **State Snapshot**: Point-in-time capture of system state including active project, window marks, daemon status, recent events, output configuration, and workspace assignments
- **Test Assertion**: Expected condition to validate (e.g., "active project equals 'nixos'", "window has mark 'project:test'", "workspace 1 assigned to output HDMI-1")
- **Test Report**: Results of test execution including passed/failed scenarios, execution time, and diagnostic information
- **Tmux Test Session**: Isolated tmux session containing monitor pane and command pane for test execution
- **Output State**: i3 output/monitor configuration retrieved via GET_OUTPUTS IPC, including name, active status, current mode, dimensions, and assigned workspaces
- **Workspace Assignment**: Mapping between workspace number/name and output name as reported by i3's GET_WORKSPACES IPC response

## Success Criteria

### Measurable Outcomes

- **SC-001**: Developers can visually observe system state changes in real-time while executing commands in separate terminal pane
- **SC-002**: Automated tests detect state corruption within 2 seconds of occurrence and report specific discrepancy
- **SC-003**: Test suite executes complete workflow (create, switch, delete project) in under 10 seconds
- **SC-004**: Diagnostic capture generates comprehensive state report in under 3 seconds
- **SC-005**: 95% of manual testing scenarios can be automated using test framework
- **SC-006**: Failed tests provide sufficient diagnostic information to identify root cause without needing manual reproduction
- **SC-007**: Test suite can run unattended in CI environment and produces reliable pass/fail results
- **SC-008**: Monitor tool state validation reduces time to diagnose issues by 50% compared to manual log inspection
- **SC-009**: Monitor/output configuration changes detected within 1 second and workspace assignment validation completes within 2 seconds using i3's native IPC

## Scope

### In Scope

- Enhancements to i3-project-monitor tool for diagnostic and testing modes
- Python-based test framework for automated workflow simulation
- Tmux integration for multi-pane monitoring during tests
- State validation utilities that query daemon and compare to expectations
- Test scenario library covering common project management workflows
- Diagnostic capture and reporting capabilities
- CI/CD integration support
- Monitor/output tracking via i3's GET_OUTPUTS IPC message type
- Workspace-to-output assignment validation via i3's GET_WORKSPACES IPC message type
- Integration with xrandr for testing display configuration changes
- Validation that monitor tool's state matches i3's authoritative IPC responses

### Out of Scope

- Testing or validation of i3wm itself (only testing project management layer)
- Performance benchmarking or load testing (focus is functional correctness)
- UI testing for graphical applications opened within projects
- Network-based testing or distributed system scenarios
- Testing of other i3 features not related to project management
- Automated fixing of detected issues (diagnostic only, not remediation)

## Assumptions

- Existing i3-project-monitor tool (Feature 017) is stable and provides reliable real-time monitoring
- i3 project management daemon and CLI tools are already implemented and functional
- Tests will run on same system where i3wm is running (not remote testing)
- Tmux is available and can be used for session management
- Python 3.11+ is available for test framework implementation
- Developer has access to terminal and can observe split-pane output during manual testing
- Test framework will use existing JSON-RPC API exposed by daemon (no new API needed)
- False positives from timing issues are acceptable if tests include retry logic

## Dependencies

- **Feature 017**: i3-project-monitor tool must be implemented and working
- **Feature 015**: i3 project event daemon must be running and functional
- **i3wm IPC**: All state queries MUST use i3's native IPC (GET_WORKSPACES, GET_OUTPUTS, GET_TREE, GET_MARKS, SUBSCRIBE) to ensure alignment with i3's authoritative state
- **Tmux**: Required for multi-pane monitoring setup
- **i3-msg**: Required for simulating i3 commands in tests
- **xrandr**: Required for testing display configuration changes and monitor connect/disconnect scenarios
- **Python asyncio**: Required for async test execution and daemon communication
- **i3ipc-python / i3ipc.aio**: Python library for i3 IPC communication (already used in Feature 015 daemon)

## Open Source Considerations

This feature enhances existing open source i3 project management tooling:

- Test framework can serve as examples for other developers building similar systems
- Diagnostic tooling demonstrates best practices for debugging event-driven systems
- Tmux integration patterns are reusable for other multi-component testing scenarios
- State validation approach is applicable to any system with expected vs actual state comparison needs
- Test scenario format could become a standard for documenting expected system behavior
- Monitor/output tracking patterns demonstrate proper use of i3's GET_OUTPUTS and GET_WORKSPACES IPC for multi-monitor validation
- Approach to validating workspace-to-output assignments can help other i3 extension developers ensure consistency with i3's native state
