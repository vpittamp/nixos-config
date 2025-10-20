# Data Model: i3 Project System Testing & Debugging Framework

**Feature**: 018-create-a-new
**Date**: 2025-10-20
**Status**: Complete

## Overview

This document defines the data structures for the testing and debugging framework. Entities are organized by domain: test framework, state validation, monitor tracking, and diagnostic reporting.

## Core Entities

### 1. Test Scenario

Represents a single test case with setup, execution, and validation phases.

**Fields**:
- `scenario_id`: str - Unique identifier (e.g., "project_lifecycle_001")
- `name`: str - Human-readable test name
- `description`: str - Test purpose and expected outcome
- `priority`: int - Execution priority (1 = highest)
- `timeout_seconds`: float - Maximum execution time
- `requires_xrandr`: bool - Whether test needs X11/xrandr
- `requires_tmux`: bool - Whether test needs tmux isolation
- `setup_actions`: List[Action] - Setup steps (create projects, etc.)
- `test_actions`: List[Action] - Main test steps
- `assertions`: List[Assertion] - Validation conditions
- `cleanup_actions`: List[Action] - Cleanup steps

**Validation Rules**:
- `scenario_id` must be unique across test suite
- `timeout_seconds` must be > 0
- `priority` must be 1-5
- At least one assertion required

**State Transitions**:
```
pending → setup → executing → validating → completed
                                       ↓
                                   failed → cleanup
```

**Example**:
```json
{
  "scenario_id": "project_switch_basic",
  "name": "Basic Project Switch",
  "description": "Create two projects, switch between them, validate state changes",
  "priority": 1,
  "timeout_seconds": 10.0,
  "requires_xrandr": false,
  "requires_tmux": true,
  "setup_actions": [
    {"type": "create_project", "params": {"name": "test-proj-a"}},
    {"type": "create_project", "params": {"name": "test-proj-b"}}
  ],
  "test_actions": [
    {"type": "switch_project", "params": {"name": "test-proj-a"}},
    {"type": "wait_seconds", "params": {"duration": 0.5}},
    {"type": "switch_project", "params": {"name": "test-proj-b"}}
  ],
  "assertions": [
    {"type": "daemon_active_project_equals", "params": {"expected": "test-proj-b"}},
    {"type": "event_buffer_contains", "params": {"event_types": ["tick"]}}
  ],
  "cleanup_actions": [
    {"type": "delete_project", "params": {"name": "test-proj-a"}},
    {"type": "delete_project", "params": {"name": "test-proj-b"}}
  ]
}
```

### 2. Test Action

Represents a single action in a test scenario (setup, test, or cleanup).

**Fields**:
- `action_id`: str - Unique identifier (generated)
- `type`: ActionType - Action type enum
- `params`: Dict[str, Any] - Action-specific parameters
- `timeout_seconds`: float - Action-specific timeout (default: 5.0)
- `retry_on_failure`: bool - Whether to retry if action fails
- `max_retries`: int - Maximum retry attempts (default: 0)

**Action Types**:
- `create_project`: Create test project
- `delete_project`: Delete test project
- `switch_project`: Switch active project
- `clear_project`: Clear active project (global mode)
- `open_window`: Open application window
- `close_window`: Close window by ID
- `mark_window`: Manually mark window with tag
- `xrandr_enable_output`: Enable display output
- `xrandr_disable_output`: Disable display output
- `xrandr_change_resolution`: Change output resolution
- `wait_seconds`: Wait for specified duration
- `run_command`: Execute arbitrary shell command

**Validation Rules**:
- `type` must be valid ActionType
- `params` must match requirements for action type
- `timeout_seconds` must be > 0
- `max_retries` must be >= 0

### 3. Test Assertion

Represents an expected condition to validate after test execution.

**Fields**:
- `assertion_id`: str - Unique identifier (generated)
- `type`: AssertionType - Assertion type enum
- `params`: Dict[str, Any] - Assertion-specific parameters
- `failure_message`: str - Custom message if assertion fails
- `critical`: bool - Whether failure stops test execution

**Assertion Types**:

**Daemon State Assertions**:
- `daemon_active_project_equals`: Validate active project name
- `daemon_window_count_equals`: Validate tracked window count
- `daemon_project_exists`: Validate project exists
- `daemon_window_marked`: Validate window has expected mark

**i3 IPC Assertions**:
- `i3_workspace_visible`: Validate workspace is visible
- `i3_workspace_on_output`: Validate workspace assigned to output
- `i3_output_active`: Validate output is active
- `i3_output_exists`: Validate output exists
- `i3_window_exists`: Validate window exists in i3 tree
- `i3_mark_exists`: Validate mark exists in i3

**Event Buffer Assertions**:
- `event_buffer_contains`: Validate event type present
- `event_buffer_count_equals`: Validate event count
- `event_order_correct`: Validate event sequence

**Cross-Validation Assertions**:
- `daemon_i3_state_match`: Validate daemon and i3 agree on state
- `workspace_assignment_valid`: Validate all workspaces assigned to active outputs

**Validation Rules**:
- `type` must be valid AssertionType
- `params` must include all required fields for assertion type
- `critical` assertions stop test on failure

**Example**:
```json
{
  "assertion_id": "assert_001",
  "type": "daemon_active_project_equals",
  "params": {"expected": "test-nixos"},
  "failure_message": "Active project should be 'test-nixos' after switch",
  "critical": true
}
```

### 4. Test Result

Captures outcome of test scenario execution.

**Fields**:
- `scenario_id`: str - Reference to test scenario
- `status`: ResultStatus - Test outcome (passed, failed, skipped, error)
- `start_time`: datetime - Test start timestamp
- `end_time`: datetime - Test end timestamp
- `duration_seconds`: float - Execution duration
- `assertion_results`: List[AssertionResult] - Per-assertion outcomes
- `error_message`: str | None - Error message if test failed
- `logs`: List[LogEntry] - Test execution logs
- `artifacts`: Dict[str, str] - Captured artifacts (screenshots, logs, states)

**Result Status**:
- `passed`: All assertions passed
- `failed`: One or more assertions failed
- `skipped`: Test skipped (dependencies not met)
- `error`: Test execution error (setup failure, timeout)

**Validation Rules**:
- `end_time` must be >= `start_time`
- `duration_seconds` must match end_time - start_time
- `status` must be valid ResultStatus

**Example**:
```json
{
  "scenario_id": "project_switch_basic",
  "status": "passed",
  "start_time": "2025-10-20T10:30:00Z",
  "end_time": "2025-10-20T10:30:05Z",
  "duration_seconds": 5.2,
  "assertion_results": [
    {
      "assertion_id": "assert_001",
      "status": "passed",
      "expected": "test-proj-b",
      "actual": "test-proj-b"
    }
  ],
  "error_message": null,
  "logs": [...],
  "artifacts": {}
}
```

### 5. Output State

Represents i3 output/monitor configuration from GET_OUTPUTS IPC.

**Fields**:
- `name`: str - Output name (e.g., "HDMI-1", "eDP-1")
- `active`: bool - Whether output is active
- `primary`: bool - Whether output is primary display
- `current_workspace`: str | None - Currently visible workspace name
- `rect`: Rectangle - Output dimensions and position
- `workspaces`: List[str] - All workspaces assigned to this output

**Rectangle**:
- `x`: int - X position
- `y`: int - Y position
- `width`: int - Width in pixels
- `height`: int - Height in pixels

**Validation Rules**:
- `name` must be non-empty
- `rect.width` and `rect.height` must be > 0
- `current_workspace` must be in `workspaces` list if not None

**Relationships**:
- Multiple workspaces per output
- One workspace can only be on one output at a time

**Example**:
```json
{
  "name": "HDMI-1",
  "active": true,
  "primary": true,
  "current_workspace": "1",
  "rect": {
    "x": 0,
    "y": 0,
    "width": 1920,
    "height": 1080
  },
  "workspaces": ["1", "2", "3"]
}
```

### 6. Workspace Assignment

Represents workspace-to-output mapping from GET_WORKSPACES IPC.

**Fields**:
- `num`: int - Workspace number
- `name`: str - Workspace name (may include dynamic naming from i3wsr)
- `output`: str - Output name this workspace is assigned to
- `visible`: bool - Whether workspace is currently visible
- `focused`: bool - Whether workspace is focused
- `rect`: Rectangle - Workspace dimensions
- `urgent`: bool - Whether workspace has urgent window

**Validation Rules**:
- `num` must be > 0
- `name` must be non-empty
- `output` must reference existing output
- Only one workspace can be focused at a time

**Relationships**:
- Many workspaces to one output
- Workspace must be assigned to active output if visible

**Example**:
```json
{
  "num": 1,
  "name": "1:term",
  "output": "HDMI-1",
  "visible": true,
  "focused": true,
  "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
  "urgent": false
}
```

### 7. Diagnostic Snapshot

Complete system state capture for debugging.

**Fields**:
- `schema_version`: str - Snapshot format version (semver)
- `timestamp`: datetime - Capture time
- `capture_duration_ms`: float - Time taken to capture snapshot
- `daemon_state`: DaemonState - Daemon status and statistics
- `i3_state`: I3State - Complete i3 state
- `event_buffer`: List[EventEntry] - Recent events
- `metadata`: CaptureMetadata - Environment and version info

**DaemonState**:
- `status`: str - Daemon status (running, stopped, error)
- `connected`: bool - i3 IPC connection status
- `active_project`: str | None - Current active project
- `window_count`: int - Tracked windows
- `workspace_count`: int - Known workspaces
- `uptime_seconds`: float - Daemon uptime
- `event_count`: int - Total events processed
- `error_count`: int - Error count

**I3State**:
- `outputs`: List[OutputState] - All outputs from GET_OUTPUTS
- `workspaces`: List[WorkspaceAssignment] - All workspaces from GET_WORKSPACES
- `tree`: Dict - Complete i3 tree dump from GET_TREE
- `marks`: List[str] - All marks from GET_MARKS

**CaptureMetadata**:
- `i3_version`: str - i3wm version
- `python_version`: str - Python interpreter version
- `hostname`: str - System hostname
- `user`: str - Current user
- `display`: str - DISPLAY environment variable

**Validation Rules**:
- `schema_version` must follow semver
- `capture_duration_ms` must be > 0
- `timestamp` must be valid ISO 8601 datetime

**Example**:
```json
{
  "schema_version": "1.0.0",
  "timestamp": "2025-10-20T10:30:00Z",
  "capture_duration_ms": 245.8,
  "daemon_state": {
    "status": "running",
    "connected": true,
    "active_project": "nixos",
    "window_count": 5,
    "uptime_seconds": 3600.5
  },
  "i3_state": {
    "outputs": [...],
    "workspaces": [...],
    "tree": {...},
    "marks": ["project:nixos", "project:stacks"]
  },
  "event_buffer": [...],
  "metadata": {
    "i3_version": "4.22",
    "python_version": "3.11.5",
    "hostname": "hetzner",
    "user": "vpittamp",
    "display": ":0"
  }
}
```

### 8. Tmux Test Session

Represents a tmux session for test isolation.

**Fields**:
- `session_id`: str - Unique tmux session identifier
- `monitor_pane_id`: str - Pane running monitor tool
- `command_pane_id`: str - Pane for command execution
- `created_at`: datetime - Session creation time
- `status`: SessionStatus - Session status

**Session Status**:
- `initializing`: Session being created
- `ready`: Both panes ready for use
- `running`: Test executing
- `cleaning_up`: Cleanup in progress
- `closed`: Session terminated

**Validation Rules**:
- `session_id` must be unique and valid tmux identifier
- Pane IDs must reference existing tmux panes

**Operations**:
- `create()`: Initialize tmux session with split panes
- `run_monitor(mode)`: Start monitor tool in monitor pane
- `run_command(cmd)`: Execute command in command pane
- `capture_output(pane)`: Capture pane output
- `cleanup()`: Kill session and release resources

## Entity Relationships

```
TestScenario (1) ──> (N) TestAction
TestScenario (1) ──> (N) TestAssertion
TestScenario (1) ──> (1) TestResult
TestResult (1) ──> (N) AssertionResult

OutputState (1) ──> (N) WorkspaceAssignment
WorkspaceAssignment (N) ──> (1) OutputState

DiagnosticSnapshot (1) ──> (1) DaemonState
DiagnosticSnapshot (1) ──> (1) I3State
DiagnosticSnapshot (1) ──> (N) EventEntry

TmuxTestSession (1) ──> (N) TestScenario (executed in session)
```

## Data Flow

### Test Execution Flow

```
1. Load TestScenario from scenario library
2. Create TmuxTestSession for isolation
3. Execute setup_actions (create test projects)
4. Execute test_actions (switch projects, open windows)
5. Run assertions:
   - Query daemon via JSON-RPC (DaemonState)
   - Query i3 via IPC (I3State with OutputState, WorkspaceAssignment)
   - Compare states (cross-validation)
6. Collect TestResult with assertion outcomes
7. Execute cleanup_actions (delete test projects)
8. Cleanup TmuxTestSession
9. Report results via reporters
```

### Diagnostic Capture Flow

```
1. Trigger diagnostic capture (manual or on failure)
2. Query daemon state → DaemonState
3. Query i3 IPC:
   - GET_OUTPUTS → List[OutputState]
   - GET_WORKSPACES → List[WorkspaceAssignment]
   - GET_TREE → i3 tree structure
   - GET_MARKS → marks list
4. Query daemon event buffer → List[EventEntry]
5. Collect metadata → CaptureMetadata
6. Assemble DiagnosticSnapshot
7. Serialize to JSON file
8. Return file path
```

### State Validation Flow

```
1. Query daemon: active_project, windows
2. Query i3: tree, marks, workspaces, outputs
3. Validate daemon consistency:
   - active_project matches expected
   - windows have correct project marks
4. Validate i3 consistency:
   - workspaces assigned to active outputs
   - visible workspaces on correct outputs
   - marks exist in i3 tree
5. Cross-validate daemon vs i3:
   - daemon windows match i3 marked windows
   - daemon project state matches i3 marks
6. Return validation results
```

## Storage and Persistence

### Test Scenarios

- Stored as Python modules in `scenarios/` directory
- Can also be loaded from JSON configuration files
- No database required (scenarios are code)

### Test Results

- Temporarily stored in memory during test run
- Serialized to JSON for reporting
- Optionally persisted to test-results/ directory

### Diagnostic Snapshots

- Written to JSON files in diagnostics/ directory
- Filename format: `diagnostic-{timestamp}.json`
- Configurable retention policy (default: 30 days)

### Tmux Sessions

- Ephemeral (exist only during test execution)
- Session IDs use format: `i3-project-test-{uuid}`
- Automatically cleaned up after test completion

## Validation Summary

Key validation rules enforced:

1. Test scenarios must have unique IDs
2. Workspaces must be assigned to active outputs
3. Only one workspace can be focused at a time
4. Daemon and i3 state must agree on window marks
5. Event buffer events must be chronologically ordered
6. Diagnostic snapshots must follow versioned schema
7. Test results must have valid start/end times
8. Tmux sessions must have unique identifiers

## Extension Points

The data model supports future extensions:

1. **Custom Action Types**: Register new action types via plugin system
2. **Custom Assertion Types**: Add domain-specific assertions
3. **Alternative Storage**: Swap JSON file storage for database
4. **Additional Reporters**: New output formats (HTML, XML)
5. **Snapshot Versioning**: Schema evolution via version field
6. **Test Tags**: Group scenarios by feature/priority/type
