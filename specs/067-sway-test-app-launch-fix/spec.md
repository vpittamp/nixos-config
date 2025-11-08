# Feature Specification: Sway Test Framework - App Launch Integration & Sync Fixes

**Feature Branch**: `067-sway-test-app-launch-fix`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "Enhance sway-test framework to use app-launcher-wrapper for proper I3PM environment variable injection and workspace assignment. Fix auto-sync RPC errors and implement wait_event for window::new events."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Realistic App Launch Testing (Priority: P1)

As a developer testing window management features, I want test framework to launch applications using the same `app-launcher-wrapper.sh` mechanism that users experience, so tests accurately reflect production behavior with proper I3PM environment variables and workspace assignment.

**Why this priority**: Current tests launch apps directly (e.g., `firefox`) without I3PM integration, making tests unrealistic. Production apps go through `app-launcher-wrapper.sh` which injects critical environment variables (`I3PM_APP_NAME`, `I3PM_TARGET_WORKSPACE`) that enable window tracking and workspace assignment. Tests must use the same flow to catch regressions in this integration.

**Independent Test**: Can be fully tested by writing a test that launches Firefox via `app-launcher-wrapper.sh firefox`, verifying window appears on configured workspace 3 (not random), and checking daemon logs show I3PM environment variables were read from `/proc/<pid>/environ`. Delivers value by catching workspace assignment bugs.

**Acceptance Scenarios**:

1. **Given** a test launches Firefox using `app-launcher-wrapper.sh firefox`, **When** Firefox window appears, **Then** daemon reads `I3PM_TARGET_WORKSPACE=3` from environment and assigns window to workspace 3 (not current focused workspace).

2. **Given** a test launches VS Code with project context via wrapper, **When** test captures final state, **Then** window shows `I3PM_PROJECT_NAME=nixos` in process environment, enabling project-scoped filtering.

3. **Given** a test launches multiple apps sequentially via wrapper, **When** each app appears, **Then** daemon sends launch notification RPC call before app starts (Feature 041 tier 0 matching), ensuring deterministic window-to-launch correlation.

4. **Given** wrapper launches app with `swaymsg exec` (not direct subprocess), **When** app window appears, **Then** environment variables propagate correctly through Sway's execution context, and window has proper Wayland display server access.

---

### User Story 2 - Reliable Event Synchronization (Priority: P1)

As a developer writing window lifecycle tests, I want framework to wait for `window::new` events deterministically without arbitrary timeouts, so tests don't fail randomly when windows take slightly longer to appear.

**Why this priority**: Current `wait_event` implementation only waits 1 second max (not the requested 10 seconds) and doesn't actually subscribe to Sway events. This causes test flakiness when apps take 2-3 seconds to launch. Proper event subscription eliminates race conditions.

**Independent Test**: Can be tested by launching a slow-starting app (e.g., VS Code), using `wait_event(window::new, timeout=10000)`, and verifying test waits up to 10 seconds for window appearance instead of failing after 1 second. Delivers value by reducing false failures.

**Acceptance Scenarios**:

1. **Given** a test with `wait_event("window::new", timeout=8000)`, **When** window appears after 3 seconds, **Then** test proceeds immediately (not after 8 seconds), proving event-driven waiting instead of fixed delay.

2. **Given** a test waits for window event with 5-second timeout, **When** window never appears, **Then** test fails after exactly 5 seconds with timeout error message showing last captured tree state for debugging.

3. **Given** multiple tests running concurrently, **When** each uses `wait_event`, **Then** events are correctly attributed to originating test without cross-contamination, using test-scoped event filtering.

4. **Given** a test waits for `workspace::focus` event after sending workspace switch command, **When** event arrives, **Then** framework captures which workspace became focused as part of event payload, enabling assertions on event data.

---

### User Story 3 - Fix Auto-Sync RPC Errors (Priority: P1)

As a developer running tests, I want framework to handle daemon connectivity gracefully without failing tests with "Method not found" errors, so tests run reliably even when optional daemon features aren't available.

**Why this priority**: Current auto-sync feature calls `sendSyncMarker()` RPC method that doesn't exist in tree-monitor daemon, causing every test to print "Auto-sync failed: RPC error: Method not found". This creates noise and confusion. Framework should either implement the method or gracefully degrade.

**Independent Test**: Can be tested by running any test with tree-monitor daemon running, verifying no "Method not found" errors appear in output, and confirming test passes. If daemon down, test should warn but not fail. Delivers value by reducing test output noise.

**Acceptance Scenarios**:

1. **Given** tree-monitor daemon is running but lacks `sendSyncMarker` method, **When** test runs with auto-sync enabled, **Then** framework detects missing method via RPC introspection, disables auto-sync for session, and logs single warning (not per-test spam).

2. **Given** daemon is not running, **When** test framework starts, **Then** framework attempts connection, detects socket unavailable, disables auto-sync features gracefully, and continues with timeout-based synchronization fallback.

3. **Given** daemon restarts mid-test, **When** framework makes RPC call, **Then** framework detects connection loss, attempts reconnection once, and falls back to timeout-based sync if reconnection fails within 1 second.

4. **Given** daemon adds `sendSyncMarker` support in future, **When** framework connects, **Then** framework queries available methods via RPC reflection, detects new method, and automatically enables I3_SYNC-style synchronization without code changes.

---

### User Story 4 - Workspace Assignment Validation (Priority: P2)

As a developer testing workspace assignment logic, I want to verify that apps launched via wrapper appear on their configured `preferred_workspace`, so I can catch regressions in Feature 053's event-driven workspace assignment.

**Why this priority**: Workspace assignment is core to i3pm's value proposition. Tests must validate that `I3PM_TARGET_WORKSPACE` environment variable correctly assigns windows to intended workspaces. Without this, workspace assignment bugs could ship to production.

**Independent Test**: Can be tested by launching 3 apps with different preferred workspaces (firefox→WS3, vscode→WS2, thunar→WS6), verifying each window appears on correct workspace (not all on WS1), proving per-app assignment works. Delivers value by validating Feature 053.

**Acceptance Scenarios**:

1. **Given** Firefox has `preferred_workspace=3` in app registry, **When** test launches Firefox via wrapper and waits for window, **Then** final state shows Firefox window on workspace 3 with `workspace: 3` property.

2. **Given** terminal app has `scope=scoped` and active project, **When** test launches terminal, **Then** window shows `I3PM_PROJECT_NAME` in environment, and daemon associates window with project for filtering.

3. **Given** test switches to workspace 1 then launches app configured for workspace 5, **When** window appears, **Then** window is on workspace 5 (not workspace 1), proving daemon overrides focused workspace.

4. **Given** PWA app with `expected_class=FFPWA-01JCYF8Z2M`, **When** test launches PWA and window appears, **Then** window's `app_id` matches expected class, proving PWA window identification works.

---

### Edge Cases

- **What happens when app-launcher-wrapper.sh script doesn't exist?** Test framework detects missing script at `~/.local/bin/app-launcher-wrapper.sh`, provides error message with installation command (`sudo nixos-rebuild switch`), and marks test as environment error (not test failure).

- **What happens when app registry JSON is missing?** Wrapper script fails with clear error, test framework captures stderr showing "Registry file not found", and test fails with actionable message suggesting rebuild.

- **What happens when daemon socket is missing for tree-monitor queries?** Framework attempts connection, detects socket unavailable, disables event-driven features (auto-sync, event correlation), logs warning once per test run, and continues with timeout-based fallbacks.

- **What happens when wait_event times out?** Framework marks test as failed with timeout error, captures diagnostic tree state showing current windows/workspaces, includes last tree-monitor events if available, and suggests increasing timeout or checking app launch command.

- **What happens when I3PM environment variables are missing from launched process?** Test can validate by checking `/proc/<pid>/environ` via `window-env` utility, detecting missing variables, and failing with specific error (e.g., "Expected I3PM_APP_NAME in environment, found none - was app launched via wrapper?").

- **What happens when multiple windows appear during wait_event?** Framework returns on first matching event (e.g., first `window::new`), captures all windows in diagnostic output, and allows test to assert on specific window using partial matching (e.g., `app_id=firefox`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Test framework MUST support launching applications via `app-launcher-wrapper.sh <app-name>` instead of direct command execution, enabling realistic testing of production app launch flow.

- **FR-002**: Test framework MUST provide `launch_app_via_wrapper` action type (or enhance existing `launch_app`) that accepts app name from registry (e.g., "firefox") and invokes wrapper script with proper PATH resolution.

- **FR-003**: Test framework MUST support validating I3PM environment variables in launched processes by reading `/proc/<pid>/environ` or using `window-env` utility, enabling assertions on `I3PM_APP_NAME`, `I3PM_TARGET_WORKSPACE`, etc.

- **FR-004**: Test framework MUST implement `wait_event` action to subscribe to Sway IPC events using `swaymsg -t subscribe -m` and wait for specific event types (`window`, `workspace`, `binding`) with configurable timeout.

- **FR-005**: `wait_event` action MUST respect timeout parameter (in milliseconds) up to 60 seconds, returning immediately when matching event arrives or failing after timeout expires with diagnostic context.

- **FR-006**: Test framework MUST filter subscribed events by type (e.g., only `window::new` not `window::close`) to avoid false matches, using event payload inspection to match criteria.

- **FR-007**: Test framework MUST handle concurrent event subscriptions from multiple tests without cross-contamination by using test-scoped subscription handlers or sequential test execution.

- **FR-008**: Test framework MUST detect missing RPC methods in tree-monitor daemon via introspection (e.g., checking available methods before calling), disabling features gracefully when methods unavailable.

- **FR-009**: Test framework MUST fall back to timeout-based synchronization when daemon unavailable or lacks sync support, with clear log message indicating degraded mode (e.g., "Auto-sync unavailable, using 500ms delays").

- **FR-010**: Test framework MUST suppress repeated "Method not found" errors by checking method availability once per session, logging single warning, and memoizing result to avoid per-test RPC failures.

- **FR-011**: Test framework MUST provide helper action `validate_workspace_assignment(app_name, expected_workspace)` that checks window with `I3PM_APP_NAME=app_name` exists on specified workspace number.

- **FR-012**: Test framework MUST support extracting window PID from Sway tree and querying `/proc/<pid>/environ` to validate environment variables without requiring custom daemons.

- **FR-013**: Test framework MUST enhance `launch_app` action to support `via_wrapper: true` parameter that automatically uses `app-launcher-wrapper.sh` with app name lookup from registry.

- **FR-014**: Test framework MUST document recommended test patterns in `docs/WALKER_APP_LAUNCH_TESTING.md` showing how to test workspace assignment, PWA launches, and multi-instance apps.

- **FR-015**: Test framework MUST provide example tests demonstrating wrapper-based launches in `tests/sway-tests/integration/` covering Firefox (global), VS Code (scoped), and PWA apps.

- **FR-016**: Test framework MUST log diagnostic information when wrapper launch fails, including: wrapper script exit code, stderr output, registry lookup result, and daemon connectivity status.

- **FR-017**: Test framework MUST support asserting on partial window state (e.g., "workspace 3 has window with app_id=firefox") without requiring exact tree structure match, enabling flexible workspace tests.

- **FR-018**: Test framework MUST handle wrapper launching apps asynchronously via `swaymsg exec`, waiting for window appearance via event subscription instead of assuming synchronous completion.

- **FR-019**: Test framework MUST detect when tests are running in environments where wrapper script unavailable (e.g., CI without home-manager), providing clear skip/error messages.

- **FR-020**: Test framework MUST validate test syntax for wrapper-based launches, detecting invalid app names (not in registry) during test validation phase before execution begins.

### Key Entities

- **AppLauncherWrapper**: Integration point with production app launch system, represented as executable script at `~/.local/bin/app-launcher-wrapper.sh` that accepts app name argument, loads configuration from `~/.config/i3/application-registry.json`, queries daemon for project context, injects I3PM environment variables, sends launch notification, and executes app via `swaymsg exec`.

- **LaunchAction**: Enhanced test action for launching apps with `via_wrapper` boolean flag, `app_name` (registry lookup) or `command` (direct execution), optional `args` array, and optional `env` object. When `via_wrapper=true`, framework resolves app name to wrapper invocation.

- **WaitEventAction**: New test action for event-driven synchronization with `event_type` (e.g., "window::new", "workspace::focus"), `timeout_ms` (max wait time), optional `criteria` (event payload filters like window app_id), and `on_timeout` behavior (fail test or continue).

- **EventSubscription**: Sway IPC event stream connection using `swaymsg -t subscribe -m '["window","workspace"]'`, parsed as JSON lines, filtered by event type and criteria, with per-test isolation to prevent event cross-contamination.

- **RpcMethodCache**: Framework-level cache of available RPC methods from tree-monitor daemon, populated on first connection via introspection call (e.g., `system.listMethods`), used to detect `sendSyncMarker` availability before calling.

- **EnvironmentValidator**: Utility for extracting and validating I3PM environment variables from process environment via `/proc/<pid>/environ` file read, supporting assertions like `assertEnvVar("I3PM_APP_NAME", "firefox")`.

- **WorkspaceAssertion**: High-level test assertion checking window exists on specific workspace with matching properties (app_id, title, PID), using partial state matching without requiring exact tree structure.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Tests launching apps via wrapper correctly validate workspace assignment in 100% of cases, catching regressions where windows appear on wrong workspace.

- **SC-002**: `wait_event` action successfully waits for window appearance with 0% false timeouts over 100 test runs, proving event-driven synchronization works reliably.

- **SC-003**: Test output contains zero "Method not found" error messages when daemon lacks sync support, improving developer experience by eliminating noise.

- **SC-004**: Tests complete in under 5 seconds when apps launch quickly (1-2 seconds), proving event-driven waiting is faster than 10-second fixed delays.

- **SC-005**: Framework detects missing wrapper script or registry within 500ms of test start, failing fast with actionable error message before attempting app launch.

- **SC-006**: Tests validate I3PM environment variables exist in launched processes with 100% accuracy, catching cases where wrapper fails to inject variables.

- **SC-007**: Example tests demonstrate realistic workflows (launch 3 apps via walker, verify workspaces, check project associations) completing in under 10 seconds total.

- **SC-008**: Framework degrades gracefully when daemon unavailable, with 0 test failures due to missing daemon (only feature warnings), enabling local development without full i3pm stack.

- **SC-009**: Documentation enables developers to write wrapper-based tests in under 5 minutes by following examples in `WALKER_APP_LAUNCH_TESTING.md`.

- **SC-010**: Test framework catches workspace assignment bugs in 95% of scenarios where daemon fails to move window to target workspace, as validated by intentionally breaking assignment logic.

## Assumptions

1. **App registry exists and is populated**: Tests assume `~/.config/i3/application-registry.json` exists with standard app definitions (firefox, vscode, etc.) at time of test execution. If missing, tests fail with clear error suggesting `nixos-rebuild switch`.

2. **Wrapper script uses absolute path**: Framework assumes wrapper is at `~/.local/bin/app-launcher-wrapper.sh` (standard home-manager location). Alternative paths not supported in initial implementation.

3. **Daemon optional for basic tests**: Framework assumes tree-monitor daemon is optional dependency - tests can run without it by falling back to timeout-based synchronization (degraded but functional).

4. **Events are JSON formatted**: Framework assumes Sway IPC events follow documented JSON schema from `man 7 sway-ipc`, with stable `change` field and event-specific payloads.

5. **Process environments are readable**: Framework assumes `/proc/<pid>/environ` is readable for processes launched by user (requires Linux procfs), enabling environment variable validation.

6. **Sway exec propagates environment**: Framework assumes `swaymsg exec "export VAR=value; command"` correctly propagates environment variables to spawned process, matching production behavior.

7. **App launch time under 10 seconds**: Framework assumes apps launch and show windows within 10 seconds of wrapper invocation (configurable timeout), covering 99% of normal launches.

8. **RPC socket path is stable**: Framework assumes tree-monitor socket at `/run/user/<uid>/sway-tree-monitor.sock` or similar XDG_RUNTIME_DIR path, matching daemon's configuration.
