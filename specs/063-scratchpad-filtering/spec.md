# Feature Specification: Scratchpad Terminal Filtering Reliability

**Feature Branch**: `051-scratchpad-filtering`
**Created**: 2025-11-07
**Status**: Draft
**Input**: User description: "Fix scratchpad terminal filtering reliability with TDD approach, environment variable validation, and one-terminal-per-project constraint"

## Context & Problem Statement

### Current Situation

The scratchpad terminal feature (Feature 062) allows project-scoped floating terminals that toggle show/hide. However, the filtering system that should hide scratchpad terminals when switching away from their project has reliability issues:

**What Worked**:
- Manual `swaymsg "[con_id=N] move scratchpad"` commands successfully hide terminals
- Scratchpad mark format `scratchpad:{project}` is correctly applied
- Environment variables (`I3PM_SCRATCHPAD=true`, `I3PM_PROJECT_NAME`, etc.) are set on terminal launch
- Recent fix (commit e48603bc) added scratchpad mark checking to `ipc_server.py`

**Challenges Identified**:
1. **Duplicate Code Paths**: Project switching uses `ipc_server.py` filtering, but other code paths use `window_filter.py` - both need scratchpad support
2. **Inconsistent Behavior**: Scratchpad terminals sometimes stay visible when switching projects
3. **No Duplicate Prevention**: Multiple scratchpad terminals can be created for the same project
4. **Launch Process**: Unclear if environment variables are consistently injected via the app launcher mechanism
5. **Limited Testing**: No systematic test protocol to verify filtering behavior

### Root Cause

The filtering system has multiple code paths that weren't all updated when scratchpad support was added. The lack of a constraint preventing duplicate terminals and inconsistent environment variable injection makes debugging difficult.

### Design Principle

**No Backwards Compatibility Constraints**: This spec aims for the optimal solution. Legacy code and approaches should be discarded in favor of a clean, reliable design.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean Project Switching (Priority: P1)

Users switch between projects and expect their scratchpad terminals to hide/show automatically, maintaining exactly one terminal per project.

**Why this priority**: This is the core value proposition - seamless context switching without window clutter.

**Independent Test**: Can be fully tested by opening a scratchpad terminal, switching projects, and verifying the terminal is hidden. Delivers immediate value by reducing visual clutter during project switches.

**Acceptance Scenarios**:

1. **Given** user is on project A with scratchpad terminal open
   **When** user switches to project B
   **Then** project A's scratchpad terminal becomes hidden (not visible)

2. **Given** user is on project B (no scratchpad yet)
   **When** user switches back to project A
   **Then** project A's existing scratchpad terminal becomes visible again

3. **Given** user has scratchpad terminals for multiple projects
   **When** user switches between projects
   **Then** only the current project's scratchpad is visible, all others are hidden

4. **Given** user toggles a scratchpad terminal to hide it manually
   **When** user switches away and back to that project
   **Then** the terminal remains hidden (respects user's explicit hide action)

---

### User Story 2 - Single Terminal Per Project (Priority: P1)

Users always have exactly one scratchpad terminal per project, preventing confusion and resource waste.

**Why this priority**: Critical for system reliability and user experience - duplicates cause confusion about which terminal is "real".

**Independent Test**: Can be tested by attempting to create multiple scratchpad terminals for the same project and verifying only one exists. Delivers value by preventing confusing duplicate terminals.

**Acceptance Scenarios**:

1. **Given** user is on project A with no scratchpad terminal
   **When** user opens a scratchpad terminal
   **Then** exactly one scratchpad terminal is created for project A

2. **Given** user is on project A with an existing scratchpad terminal
   **When** user attempts to open another scratchpad terminal
   **Then** the existing terminal is shown/focused instead of creating a new one

3. **Given** user is on project A with a hidden scratchpad terminal
   **When** user runs the scratchpad launch command
   **Then** the existing hidden terminal is shown, no new terminal is created

4. **Given** a scratchpad terminal exists but its process has died
   **When** user opens a scratchpad terminal
   **Then** the dead terminal is cleaned up and a new one is created

---

### User Story 3 - Reliable Environment Variables (Priority: P2)

Scratchpad terminals are correctly identified through consistent environment variables, enabling reliable filtering regardless of window manager state.

**Why this priority**: Essential for robust filtering logic - without reliable identification, terminals may not be correctly hidden/shown.

**Independent Test**: Can be tested by inspecting terminal process environment variables and verifying all required variables are present with correct values. Delivers value by ensuring filtering logic has reliable data to work with.

**Acceptance Scenarios**:

1. **Given** user launches a scratchpad terminal
   **When** examining the terminal process environment
   **Then** environment contains `I3PM_SCRATCHPAD=true`, `I3PM_PROJECT_NAME={project}`, `I3PM_APP_NAME=scratchpad-terminal`, `I3PM_SCOPE=scoped`

2. **Given** scratchpad terminal is launched via app launcher mechanism
   **When** examining the terminal process environment
   **Then** all I3PM_* variables are present and match the registry configuration

3. **Given** multiple scratchpad terminals exist (from before deduplication)
   **When** filtering logic examines terminals
   **Then** all terminals are correctly identified as scratchpad terminals via environment variables

---

### User Story 4 - Test-Driven Development Protocol (Priority: P2)

Developers can systematically test scratchpad filtering behavior using a standardized test protocol that eliminates variables.

**Why this priority**: Critical for development and debugging - without a reliable test protocol, it's difficult to verify fixes or catch regressions.

**Independent Test**: Can be tested by following the test protocol and verifying it produces consistent, repeatable results. Delivers value by making the feature debuggable and maintainable.

**Acceptance Scenarios**:

1. **Given** developer needs to test scratchpad filtering
   **When** following the test protocol (kill all scratchpads, use commands)
   **Then** tests produce consistent results across runs

2. **Given** a test reveals a filtering bug
   **When** developer fixes the bug and re-runs the test protocol
   **Then** the test can verify the fix without manual inspection

3. **Given** developer makes changes to filtering code
   **When** running the test protocol
   **Then** any regression in behavior is immediately detected

---

### Edge Cases

- What happens when a scratchpad terminal is launched but its mark isn't set yet (race condition)?
- How does the system handle a scratchpad terminal whose process exists but window is destroyed?
- What happens when switching to a project that has a scratchpad terminal on a non-existent workspace?
- How does filtering behave when multiple projects are switched rapidly (< 1 second between switches)?
- What happens when a scratchpad terminal is manually moved to a different workspace by the user?
- How does the system handle scratchpad terminals after a Sway restart/reload?
- What happens when attempting to create a scratchpad while the previous one is still launching?

## Requirements *(mandatory)*

### Functional Requirements

#### Core Filtering

- **FR-001**: System MUST hide a project's scratchpad terminal when user switches away from that project
- **FR-002**: System MUST show a project's scratchpad terminal when user switches to that project (if terminal was previously visible)
- **FR-003**: System MUST maintain scratchpad terminal visibility state (hidden by user action vs. hidden by project switch)
- **FR-004**: Filtering MUST work consistently across all code paths (ipc_server.py, window_filter.py, handlers.py TICK events)

#### Duplicate Prevention

- **FR-005**: System MUST prevent creation of multiple scratchpad terminals for the same project
- **FR-006**: When scratchpad launch is requested for a project that already has a terminal, system MUST show/focus the existing terminal
- **FR-007**: System MUST detect and clean up dead scratchpad terminals (process no longer exists) before creating new ones
- **FR-008**: System MUST maintain an authoritative registry of which projects have scratchpad terminals
- **FR-009**: Launch command MUST check registry and process state before creating new terminals

#### Environment Variable Injection

- **FR-010**: System MUST launch scratchpad terminals through the app launcher mechanism to ensure proper environment variable injection
- **FR-011**: Every scratchpad terminal MUST have these environment variables: `I3PM_SCRATCHPAD=true`, `I3PM_PROJECT_NAME={project}`, `I3PM_APP_NAME=scratchpad-terminal`, `I3PM_SCOPE=scoped`, `I3PM_APP_ID=scratchpad-{project}-{timestamp}`
- **FR-012**: System MUST validate environment variables are present before considering a terminal as a valid scratchpad terminal
- **FR-013**: Filtering logic MUST use environment variables as the primary identification mechanism (with window marks as secondary validation)

#### Testing & Development

- **FR-014**: System MUST provide a test protocol that: kills all existing scratchpad terminals, creates clean state, uses commands to open/close terminals and switch projects
- **FR-015**: Test protocol MUST be automatable (scriptable) for regression testing
- **FR-016**: Filtering behavior MUST be verifiable through observable window state (visible/hidden) without inspecting internal daemon state

### Key Entities

- **Scratchpad Terminal**: A project-scoped floating terminal window with specific environment variables, exactly one per project, managed by the scratchpad manager
  - Identified by: Sway mark `scratchpad:{project}`, environment variable `I3PM_SCRATCHPAD=true`
  - State: PID, window ID, working directory, created timestamp, last shown timestamp, visibility state

- **Project**: A workspace context with associated windows and exactly zero or one scratchpad terminal
  - Attributes: name, directory, active/inactive state, list of associated windows

- **Filtering Code Path**: A location in the codebase where window visibility decisions are made
  - Locations: ipc_server.py (_hide_windows, _restore_windows), window_filter.py (filter_windows_by_project), handlers.py (TICK event)
  - Each must implement consistent scratchpad filtering logic

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch between projects 20 times in succession and scratchpad terminals are correctly hidden/shown 100% of the time (measured by visible/hidden state)

- **SC-002**: Users attempting to create a second scratchpad terminal for a project see the existing terminal instead 100% of the time

- **SC-003**: Filtering behavior is consistent regardless of which code path handles the project switch (ipc_server vs. TICK event)

- **SC-004**: Test protocol produces identical results across 10 consecutive runs (0% variance in pass/fail outcomes)

- **SC-005**: Every launched scratchpad terminal has all required environment variables present (100% compliance rate)

- **SC-006**: Time to hide/show scratchpad terminals during project switch is under 200ms (median) from user action to visual result

- **SC-007**: Zero scratchpad-related errors appear in daemon logs during normal usage (20 project switches with scratchpad operations)

## Test Protocol *(development guidance)*

### Standard Test Sequence

**Setup Phase**:
1. Kill all existing scratchpad terminals: `pkill -f "ghostty.*I3PM_SCRATCHPAD"`
2. Clean up daemon state: `pkill -9 -f i3_project_daemon && sleep 4`
3. Verify clean state: `i3pm scratchpad status --all` shows no terminals
4. Verify daemon running: `i3pm daemon status | head -3`

**Test Phase**:
1. Switch to project A: `i3pm project switch projectA`
2. Open scratchpad: `i3pm scratchpad toggle`
3. Wait for launch: `sleep 2`
4. Verify visible: `swaymsg -t get_tree | jq '.. | select(.marks? and (.marks[] | contains("scratchpad:projectA"))) | {id, visible}'`
5. Switch to project B: `i3pm project switch projectB`
6. Wait for filtering: `sleep 2`
7. Verify hidden: Check `visible: false`
8. Switch back to project A: `i3pm project switch projectA`
9. Wait for restore: `sleep 2`
10. Verify visible again: Check `visible: true`

**Duplicate Prevention Test**:
1. While on project A with scratchpad visible
2. Run toggle again: `i3pm scratchpad toggle`
3. Verify window count: `i3pm scratchpad status --all` shows exactly 1 terminal
4. Verify same window ID (no new terminal created)

**Environment Variable Validation**:
1. Get scratchpad PID: `swaymsg -t get_tree | jq -r '.. | select(.marks[] | contains("scratchpad:projectA")) | .pid'`
2. Inspect environment: `cat /proc/{pid}/environ | tr '\0' '\n' | grep I3PM_`
3. Verify all required variables present
4. Verify mark format: `swaymsg -t get_tree | jq '.. | select(.marks[] | contains("scratchpad:projectA")) | .marks'`

**Cleanup Phase**:
1. Close all scratchpad terminals: `i3pm scratchpad close projectA; i3pm scratchpad close projectB`
2. Verify clean state: `i3pm scratchpad status --all` shows no terminals

### Automated Test Script Structure

```bash
#!/bin/bash
# Test: Scratchpad filtering during project switches

set -e  # Exit on any error

# Helper functions
cleanup_scratchpads() {
    pkill -f "ghostty.*I3PM_SCRATCHPAD" || true
    sleep 1
}

restart_daemon() {
    pkill -9 -f i3_project_daemon || true
    sleep 4
}

verify_clean_state() {
    local count=$(i3pm scratchpad status --all 2>&1 | grep -c "PID:" || echo "0")
    if [ "$count" != "0" ]; then
        echo "ERROR: Clean state verification failed, found $count terminals"
        return 1
    fi
    echo "✓ Clean state verified"
}

assert_visible() {
    local project=$1
    local msg=$2
    local visible=$(swaymsg -t get_tree | jq -r ".. | select(.marks[] | contains(\"scratchpad:$project\")) | .visible")
    if [ "$visible" != "true" ]; then
        echo "FAIL: $msg (expected visible=true, got visible=$visible)"
        exit 1
    fi
    echo "✓ $msg"
}

assert_hidden() {
    local project=$1
    local msg=$2
    local visible=$(swaymsg -t get_tree | jq -r ".. | select(.marks[] | contains(\"scratchpad:$project\")) | .visible")
    if [ "$visible" != "false" ]; then
        echo "FAIL: $msg (expected visible=false, got visible=$visible)"
        exit 1
    fi
    echo "✓ $msg"
}

assert_count_equals() {
    local project=$1
    local expected=$2
    local msg=$3
    local count=$(i3pm scratchpad status --all 2>&1 | grep -c "$project" || echo "0")
    if [ "$count" != "$expected" ]; then
        echo "FAIL: $msg (expected count=$expected, got count=$count)"
        exit 1
    fi
    echo "✓ $msg"
}

assert_env_var() {
    local pid=$1
    local var_name=$2
    local expected_value=$3
    local actual_value=$(cat /proc/$pid/environ | tr '\0' '\n' | grep "^$var_name=" | cut -d= -f2)
    if [ "$actual_value" != "$expected_value" ]; then
        echo "FAIL: Environment variable $var_name (expected=$expected_value, got=$actual_value)"
        exit 1
    fi
    echo "✓ Environment variable $var_name = $expected_value"
}

get_scratchpad_pid() {
    local project=$1
    swaymsg -t get_tree | jq -r ".. | select(.marks[] | contains(\"scratchpad:$project\")) | .pid"
}

# Setup
echo "=== Setup Phase ==="
cleanup_scratchpads
restart_daemon
verify_clean_state || exit 1

# Test Case 1: Basic hide/show
echo ""
echo "=== Test Case 1: Basic Hide/Show ==="
i3pm project switch nixos
i3pm scratchpad toggle
sleep 2
assert_visible "nixos" "nixos scratchpad should be visible"

i3pm project switch stacks
sleep 2
assert_hidden "nixos" "nixos scratchpad should be hidden"

i3pm project switch nixos
sleep 2
assert_visible "nixos" "nixos scratchpad should be visible again"

# Test Case 2: Duplicate prevention
echo ""
echo "=== Test Case 2: Duplicate Prevention ==="
i3pm scratchpad toggle  # Try to create another
sleep 1
assert_count_equals "nixos" 1 "Should still have exactly 1 nixos scratchpad"

# Test Case 3: Environment variables
echo ""
echo "=== Test Case 3: Environment Variables ==="
pid=$(get_scratchpad_pid "nixos")
echo "Scratchpad PID: $pid"
assert_env_var $pid "I3PM_SCRATCHPAD" "true"
assert_env_var $pid "I3PM_PROJECT_NAME" "nixos"
assert_env_var $pid "I3PM_APP_NAME" "scratchpad-terminal"
assert_env_var $pid "I3PM_SCOPE" "scoped"

# Test Case 4: Multiple projects
echo ""
echo "=== Test Case 4: Multiple Projects ==="
i3pm project switch stacks
i3pm scratchpad toggle
sleep 2
assert_visible "stacks" "stacks scratchpad should be visible"
assert_hidden "nixos" "nixos scratchpad should still be hidden"

i3pm project switch nixos
sleep 2
assert_visible "nixos" "nixos scratchpad should be visible"
assert_hidden "stacks" "stacks scratchpad should be hidden"

# Cleanup
echo ""
echo "=== Cleanup Phase ==="
i3pm scratchpad close nixos
i3pm scratchpad close stacks
sleep 1
verify_clean_state || exit 1

echo ""
echo "✓✓✓ All tests passed ✓✓✓"
```

## Implementation Constraints

- **IC-001**: All scratchpad terminals MUST be launched through the existing app launcher mechanism (no direct `swaymsg exec` calls)
- **IC-002**: Filtering logic MUST be added to ALL code paths that handle window visibility, not just one
- **IC-003**: Registry of scratchpad terminals MUST be maintained in daemon memory and kept in sync with actual window state
- **IC-004**: Environment variable validation MUST happen before any filtering decision
- **IC-005**: Legacy code and approaches should be replaced with optimal solutions (no backwards compatibility required)

## Assumptions

1. **App Launcher Mechanism**: We assume the existing app launcher infrastructure properly injects I3PM_* environment variables when configured correctly
2. **Mark Reliability**: We assume Sway window marks persist across window hide/show operations (they do according to testing)
3. **PID Availability**: We assume window PIDs are available for environment variable inspection (they are in Sway)
4. **Single Daemon Instance**: We assume exactly one i3pm daemon is running at a time
5. **Ghostty Terminal**: We assume Ghostty is the terminal emulator used for scratchpad terminals

## Dependencies

- Sway window manager with mark support
- Existing i3pm daemon infrastructure
- Existing app launcher mechanism
- Scratchpad terminal feature (Feature 062) as baseline
- Access to `/proc/{pid}/environ` for environment variable inspection
- Ghostty terminal emulator

## Out of Scope

- Performance optimization beyond the 200ms visibility change requirement
- Support for non-Sway window managers
- Scratchpad terminal features beyond filtering (sizing, positioning, etc.)
- Multi-daemon or distributed scratchpad management
- User-configurable scratchpad behavior (number of terminals per project, etc.)
- Backwards compatibility with previous scratchpad implementations
