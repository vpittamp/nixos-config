# Feature Specification: Sway Test Framework Usability Improvements

**Feature Branch**: `070-sway-test-improvements`
**Created**: 2025-11-10
**Status**: In Progress
**Input**: User description: "Complete the spec definition from the following work we started: Feature 070 - Sway Test Framework Usability Improvements"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clear Error Diagnostics (Priority: P1)

Developers running sway-test need immediate, actionable feedback when tests fail. Currently, test failures often show cryptic error messages that require diving into framework source code to understand what went wrong. This story focuses on providing clear, structured error messages that pinpoint exactly what failed and why.

**Why this priority**: P1 - Without clear error diagnostics, developers waste significant time debugging test failures instead of fixing actual bugs. This is a fundamental usability requirement that blocks effective test-driven development.

**Independent Test**: Can be fully tested by intentionally creating failing tests (missing app, invalid PWA ULID, malformed test JSON) and verifying that error messages clearly explain the problem and suggest remediation steps.

**Acceptance Scenarios**:

1. **Given** a test references a non-existent app name, **When** the test executes, **Then** the system displays an error message listing all available apps from the registry
2. **Given** a test uses an invalid PWA ULID format, **When** the test validates, **Then** the system explains the ULID format requirements (26-char base32) and shows the actual value that failed
3. **Given** a test JSON file has malformed structure, **When** the test loader parses it, **Then** the system shows the specific JSON location (line/field) and expected structure with examples
4. **Given** a launch action fails due to missing dependencies, **When** the test executes, **Then** the error message includes the command that failed, the exit code, and relevant log output
5. **Given** a test times out waiting for a window, **When** the timeout expires, **Then** the error shows what windows are currently open and what criteria failed to match

---

### User Story 2 - Graceful Cleanup Commands (Priority: P1)

Test runners need a reliable way to clean up test state between runs without manually killing processes or closing windows. Failed tests often leave orphaned windows and processes that interfere with subsequent test runs, requiring manual cleanup or system restarts.

**Why this priority**: P1 - Test isolation is critical for reliable CI/CD pipelines. Without automatic cleanup, flaky tests multiply and developers lose trust in the test suite.

**Independent Test**: Can be tested by running a test that launches multiple apps, forcibly stopping the test mid-execution, then verifying cleanup commands successfully restore the system to a clean state without manual intervention.

**Acceptance Scenarios**:

1. **Given** a test has launched applications, **When** the test completes or fails, **Then** all test-spawned processes are automatically terminated
2. **Given** orphaned windows exist from previous test runs, **When** cleanup command executes, **Then** all windows matching test markers are closed gracefully
3. **Given** a test left workspaces in non-default states, **When** cleanup runs, **Then** workspace focus and layout are restored to initial state
4. **Given** multiple tests run concurrently, **When** each completes, **Then** cleanup operations don't interfere with other running tests
5. **Given** a process fails to terminate gracefully, **When** cleanup times out, **Then** the system force-kills the process and logs the action

---

### User Story 3 - PWA Application Support (Priority: P2)

Test authors need to launch and validate Progressive Web Apps (PWAs) in tests just as easily as native applications. Currently, PWA testing requires manual ULID lookup and boilerplate command construction, making PWA tests brittle and hard to maintain.

**Why this priority**: P2 - PWAs are increasingly important to the system architecture (workspace assignments, project scope), but lack of first-class test support creates a testing gap. While critical, it can be built after core diagnostics and cleanup are working.

**Independent Test**: Can be tested by creating a test that launches a PWA by name (e.g., "youtube"), verifies it appears on the correct workspace, and validates window properties, all without manual ULID management.

**Acceptance Scenarios**:

1. **Given** a PWA is defined in the registry, **When** a test uses launch_pwa_sync action with PWA name, **Then** the system launches the PWA and waits for the window to appear
2. **Given** a test specifies a PWA by ULID, **When** launch_pwa_sync executes, **Then** the system resolves the ULID to the correct PWA and launches it
3. **Given** a PWA launch fails (ULID not found, firefoxpwa not installed), **When** the test runs, **Then** the error clearly explains whether the issue is missing PWA, missing tool, or configuration problem
4. **Given** a PWA test validates workspace assignment, **When** the PWA appears, **Then** the test can query the PWA's workspace and monitor role from the registry
5. **Given** allow_failure flag is set on PWA launch, **When** the PWA fails to launch, **Then** the test continues execution instead of failing

---

### User Story 4 - App Registry Integration (Priority: P2)

Test authors need to reference applications by name and have the test framework automatically resolve app metadata (commands, workspaces, expected classes) from the central application registry. Currently, tests hardcode launch commands and window criteria, creating maintenance burden when app configurations change.

**Why this priority**: P2 - Reduces test brittleness and maintenance overhead by centralizing app configuration. Tests become more readable ("launch firefox" vs hardcoded command strings) and resilient to config changes.

**Independent Test**: Can be tested by writing a test that launches an app by registry name only, then changing the app's command in the registry, and verifying the test still works without modification.

**Acceptance Scenarios**:

1. **Given** an app is defined in the registry, **When** a test uses launch_app_sync with app name, **Then** the system resolves the app's command, parameters, and expected_class automatically
2. **Given** an app has workspace preferences in the registry, **When** the test launches the app, **Then** the test framework can validate the app appears on the expected workspace
3. **Given** the registry contains 50+ apps, **When** a test references an invalid app name, **Then** the error shows a helpful filtered list of similar app names (fuzzy matching)
4. **Given** an app has floating window configuration, **When** the test launches it, **Then** the test framework can validate floating state and size preset
5. **Given** an app definition changes in the registry, **When** existing tests run, **Then** tests automatically pick up the new configuration without test file modifications

---

### User Story 5 - Convenient CLI Access (Priority: P3)

Test framework users need quick discovery commands to explore available apps and PWAs without reading Nix configuration files. Developers waste time searching through app-registry-data.nix and pwa-sites.nix to find correct app names and ULIDs for test authoring.

**Why this priority**: P3 - Improves developer experience but doesn't block core testing functionality. Nice-to-have for test authoring workflow efficiency.

**Independent Test**: Can be tested by running CLI commands (sway-test list-apps, sway-test list-pwas) and verifying they display formatted tables with all registry information without requiring filesystem navigation.

**Acceptance Scenarios**:

1. **Given** multiple apps exist in the registry, **When** user runs list-apps command, **Then** the system displays a table with app names, commands, workspaces, and monitor roles
2. **Given** PWAs are configured, **When** user runs list-pwas command, **Then** the system shows PWA names, URLs, ULIDs, and workspace assignments
3. **Given** list-apps is invoked with --json flag, **When** output is generated, **Then** machine-readable JSON is produced for scripting use cases
4. **Given** user provides a filter argument, **When** list-apps runs, **Then** only apps matching the filter pattern are displayed
5. **Given** registry files are missing or malformed, **When** list commands execute, **Then** clear error messages explain the registry issue and expected file locations

---

### Edge Cases

- What happens when PWA registry file doesn't exist at expected location? **System shows clear error with expected path and setup instructions**
- How does system handle duplicate PWA names in registry? **Validation catches duplicates at registry load time with clear error identifying conflicting entries**
- What if firefoxpwa binary is not installed when PWA test runs? **Test fails immediately with actionable error about missing firefoxpwa-cli package**
- How are ULID format errors detected? **Regex validation checks for exact 26-char base32 alphabet before attempting PWA lookup**
- What happens when app registry and PWA registry are out of sync? **Each registry loads independently; mismatches are only errors if test references non-existent entries**
- How does cleanup handle windows that can't be closed? **Cleanup attempts graceful close first (500ms timeout), then force-kills processes and logs the action**
- What if test spawns background processes that outlive the test? **Cleanup tracks all child processes via process tree and terminates entire subtree**

## Requirements *(mandatory)*

### Functional Requirements

**Error Diagnostics (US1)**

- **FR-001**: System MUST provide structured error messages that include error type, failing component, root cause, and remediation suggestions
- **FR-002**: System MUST list all available registry entries when test references non-existent app or PWA
- **FR-003**: System MUST show actual vs expected values for all validation failures
- **FR-004**: System MUST include relevant context (current workspace, open windows, process states) in timeout errors
- **FR-005**: System MUST validate JSON test files and show precise error locations (line, field) with examples of correct structure

**Cleanup Commands (US2)**

- **FR-006**: System MUST automatically terminate all test-spawned processes when test completes or fails
- **FR-007**: System MUST provide manual cleanup command that removes all test markers and closes test windows
- **FR-008**: System MUST attempt graceful process termination before force-killing
- **FR-009**: System MUST restore workspace focus to initial state after cleanup
- **FR-010**: System MUST log all cleanup actions (windows closed, processes terminated) for debugging

**PWA Support (US3)**

- **FR-011**: System MUST support launch_pwa_sync action type that accepts either pwa_name or pwa_ulid
- **FR-012**: System MUST load PWA registry from ~/.config/i3/pwa-registry.json at test startup
- **FR-013**: System MUST validate ULID format (26-char base32) before attempting PWA lookup
- **FR-014**: System MUST provide allow_failure parameter to continue test execution when PWA launch fails
- **FR-015**: System MUST resolve PWA workspace and monitor role preferences from registry for test assertions

**App Registry Integration (US4)**

- **FR-016**: System MUST load application registry from ~/.config/i3/application-registry.json at test startup
- **FR-017**: System MUST resolve app command, parameters, and expected_class from registry when launching by name
- **FR-018**: System MUST support app workspace and monitor role validation using registry metadata
- **FR-019**: System MUST validate app floating configuration (state and size preset) from registry
- **FR-020**: System MUST cache registry data per test session to avoid repeated file reads

**CLI Access (US5)**

- **FR-021**: System MUST provide list-apps command that displays app registry in table format
- **FR-022**: System MUST provide list-pwas command that displays PWA registry in table format
- **FR-023**: System MUST support --json flag for machine-readable output on list commands
- **FR-024**: System MUST support --filter argument to search apps/PWAs by name pattern
- **FR-025**: System MUST show clear errors when registry files are missing or malformed

### Key Entities *(include if feature involves data)*

- **PWADefinition**: Represents a Progressive Web App with name (lowercase normalized), URL, ULID identifier (26-char base32), optional workspace preference, and optional monitor role
- **AppDefinition**: Represents a launchable application with name (kebab-case), display name, command with optional parameters, expected window class, workspace/monitor preferences, scope (global/scoped), and optional floating configuration
- **PWARegistry**: Collection of PWADefinition entries loaded from JSON, indexed by both name and ULID for fast lookups
- **AppRegistry**: Collection of AppDefinition entries loaded from JSON, indexed by name for fast lookups
- **TestAction**: Test step with action type (launch_pwa_sync, launch_app_sync, etc.) and parameters specific to that action
- **ErrorContext**: Structured error information including error type, component, message, suggested fixes, and relevant system state

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Test failure messages include actionable remediation steps in 100% of error scenarios
- **SC-002**: Developers can identify and fix test configuration errors without consulting framework documentation in 90% of cases
- **SC-003**: Cleanup commands successfully restore clean state in under 2 seconds for tests with up to 10 spawned processes
- **SC-004**: Zero orphaned processes remain after cleanup completes (verified by process tree inspection)
- **SC-005**: PWA tests can be authored using friendly names without manual ULID lookup
- **SC-006**: Test authoring time for PWA scenarios reduces by 60% compared to manual ULID management
- **SC-007**: Registry-based app launches eliminate hardcoded commands in 100% of test files
- **SC-008**: Test maintenance burden reduces by 40% when app configurations change
- **SC-009**: List commands execute in under 200ms and display formatted output without errors
- **SC-010**: Developers can discover all available apps/PWAs without reading Nix configuration files

## Assumptions

- Existing test framework infrastructure (Feature 069 sync protocol) is fully functional and provides the foundation for these improvements
- The application-registry.json and pwa-registry.json files are generated by Nix home-manager during system configuration
- Test framework runs on NixOS with Sway compositor and has access to i3 IPC socket
- The firefoxpwa package is available for PWA launches (test will error clearly if missing)
- Tests run in environments where process termination signals (SIGTERM, SIGKILL) are respected
- Registry files are UTF-8 JSON and follow the defined schema (Zod validation ensures this)
- Test framework has permission to send IPC commands to close windows and terminate processes
- TypeScript/Deno runtime is available (matching existing sway-test framework)
- Work-in-progress implementation already completed foundational infrastructure (Phase 1 & 2):
  - PWADefinition and AppDefinition TypeScript models with Zod schemas (T001-T002)
  - PWA registry JSON generation from pwa-sites.nix (T004)
  - PWA registry reader with lookupPWA() and lookupPWAByULID() functions (T005)
  - launch_pwa_sync action type in test-case.ts (T006)

## Out of Scope

- Real-time registry reloading during test execution (tests load registry at startup only)
- PWA installation or management (assumes PWAs are already installed via firefoxpwa)
- GUI for test authoring or app discovery (CLI-only for this feature)
- Integration with external test runners (focuses on sway-test framework only)
- Automatic test generation from app registry
- Cross-compositor support (Sway/i3 only)
- Registry migration tools for breaking changes
- Performance optimization for registries >1000 apps
- Network-based registry sync or remote registries
