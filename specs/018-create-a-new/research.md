# Research: i3 Project System Testing & Debugging Framework

**Feature**: 018-create-a-new
**Date**: 2025-10-20
**Status**: Complete

## Overview

This document captures research findings and design decisions for implementing a comprehensive testing and debugging framework for the i3 project management system. The framework enhances the existing i3-project-monitor tool (Feature 017) with automated testing capabilities, diagnostic modes, and monitor/display tracking.

## Research Areas

### 1. i3 IPC API for Monitor/Workspace Tracking

**Decision**: Use i3's native GET_OUTPUTS and GET_WORKSPACES IPC message types as the authoritative source of truth for all monitor and workspace state validation.

**Rationale**:
- i3 IPC provides authoritative state directly from the window manager
- GET_OUTPUTS returns complete monitor configuration: name, active status, current_workspace, rect (dimensions)
- GET_WORKSPACES returns workspace-to-output assignments via "output" field
- Already using i3ipc.aio library in Feature 015 daemon - no new dependency
- Aligns with spec requirement: "implementation should align as closely as possible with i3wm, and its api's"

**Alternatives Considered**:
- ❌ xrandr parsing: Less reliable, requires separate subprocess calls, may differ from i3's view
- ❌ Daemon-maintained state: Could drift from i3's actual state, violates "i3 as source of truth" principle
- ✅ Direct i3 IPC queries: Authoritative, real-time, already integrated

**Implementation Notes**:
```python
# GET_OUTPUTS returns list of output objects:
{
  "name": "HDMI-1",
  "active": true,
  "current_workspace": "1",
  "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}
}

# GET_WORKSPACES returns workspace objects with output field:
{
  "num": 1,
  "name": "1",
  "output": "HDMI-1",
  "visible": true,
  "focused": true
}
```

### 2. Test Framework Architecture

**Decision**: Implement pytest-style test framework with declarative scenario definitions and pluggable assertion system.

**Rationale**:
- Pytest provides familiar pattern for Python developers
- Scenarios defined as Python classes inheriting from BaseScenario
- Assertions organized by domain (state, i3, output) for clarity
- Reporters separated from test logic for flexibility (terminal vs JSON/TAP)
- Follows single responsibility principle

**Alternatives Considered**:
- ❌ JSON test definitions: Less flexible than Python, harder to implement complex logic
- ❌ Bash scripts: Less maintainable, poor error handling, no type safety
- ✅ Python class-based scenarios: Type hints, async support, composable

**Architecture Pattern**:
```
Test Runner
  ├─ Load scenarios from scenarios/ directory
  ├─ Execute each scenario.run()
  ├─ Collect assertions (pass/fail)
  └─ Report via reporters/ (terminal/JSON)

Scenario
  ├─ setup(): Prepare test environment
  ├─ execute(): Run test actions
  ├─ validate(): Run assertions
  └─ cleanup(): Restore state
```

### 3. Tmux Integration for Test Isolation

**Decision**: Use Python subprocess module to manage tmux sessions programmatically with explicit session IDs and pane targeting.

**Rationale**:
- Tmux provides robust multi-pane terminal management
- Session isolation prevents interference with user's active i3 session
- Can capture output from monitor pane for validation
- Already required for Feature 017 manual testing workflows
- Python subprocess provides clean async interface

**Alternatives Considered**:
- ❌ Screen: Less flexible pane management, tmux is standard
- ❌ Terminal emulator tabs: Can't programmatically control or capture output
- ✅ Tmux: Industry standard, scriptable, reliable

**Implementation Pattern**:
```python
class TmuxManager:
    async def create_test_session(self, session_id: str):
        """Create tmux session with monitor and command panes"""
        # tmux new-session -d -s {session_id}
        # tmux split-window -h -t {session_id}

    async def run_in_pane(self, session_id: str, pane: int, command: str):
        """Execute command in specific pane"""
        # tmux send-keys -t {session_id}:{pane} "{command}" Enter

    async def capture_pane_output(self, session_id: str, pane: int) -> str:
        """Capture current pane output"""
        # tmux capture-pane -p -t {session_id}:{pane}

    async def cleanup_session(self, session_id: str):
        """Kill test session"""
        # tmux kill-session -t {session_id}
```

### 4. Diagnostic Capture Format

**Decision**: Use structured JSON format with versioned schema for diagnostic captures.

**Rationale**:
- JSON enables machine parsing and programmatic diff
- Versioned schema allows evolution without breaking tooling
- Human-readable with proper indentation (json.dumps with indent=2)
- Can include nested structures (i3 tree, event lists, output configs)
- Supports future compression if needed

**Alternatives Considered**:
- ❌ Plain text: Hard to parse programmatically, no structure
- ❌ YAML: More ambiguous parsing, less universal tooling than JSON
- ✅ JSON: Universal support, structured, validated

**Schema Design**:
```json
{
  "schema_version": "1.0.0",
  "timestamp": "2025-10-20T10:30:00Z",
  "daemon_state": {
    "status": "running",
    "active_project": "nixos",
    "window_count": 5,
    "uptime_seconds": 3600.5
  },
  "i3_state": {
    "outputs": [
      {"name": "HDMI-1", "active": true, "current_workspace": "1", ...}
    ],
    "workspaces": [
      {"num": 1, "name": "1", "output": "HDMI-1", "visible": true, ...}
    ],
    "tree": { /* i3 tree dump */ },
    "marks": ["project:nixos", "project:stacks", ...]
  },
  "event_buffer": [
    {"event_id": 1, "event_type": "window::new", "timestamp": "...", ...}
  ],
  "metadata": {
    "i3_version": "4.22",
    "python_version": "3.11.5",
    "capture_duration_ms": 250
  }
}
```

### 5. State Validation Strategy

**Decision**: Implement dual-source validation comparing daemon state against i3 IPC queries.

**Rationale**:
- Daemon maintains project management state (active project, window marks)
- i3 maintains window manager state (workspaces, outputs, actual window tree)
- Tests must validate both sources agree
- Detects desynchronization issues early
- Validates daemon correctly interprets i3 events

**Validation Layers**:
1. **Daemon State Validation**: Query daemon via JSON-RPC, validate internal consistency
2. **i3 IPC Validation**: Query i3 directly, validate i3's state is as expected
3. **Cross-Validation**: Compare daemon's understanding to i3's actual state

**Example Validation**:
```python
# Daemon says active project is "nixos"
daemon_project = await daemon_client.get_active_project()

# i3 should have windows marked with "project:nixos"
i3_tree = await i3_conn.get_tree()
marked_windows = find_windows_with_mark(i3_tree, "project:nixos")

# Daemon should track same windows i3 shows
daemon_windows = await daemon_client.get_windows(project="nixos")

assert len(marked_windows) == len(daemon_windows)
assert all(w.window_id in [d['window_id'] for d in daemon_windows]
           for w in marked_windows)
```

### 6. Monitor Configuration Testing with xrandr

**Decision**: Use xrandr subprocess calls for display configuration simulation, then validate i3's response via GET_OUTPUTS.

**Rationale**:
- xrandr is the standard X11 display configuration tool
- Can programmatically enable/disable outputs
- Can change resolutions and positions
- i3 automatically detects xrandr changes and updates internal state
- Tests validate i3 correctly processes xrandr events

**Alternatives Considered**:
- ❌ arandr (GUI): Can't script, defeats automation purpose
- ❌ Mock i3 events: Doesn't test real xrandr integration
- ✅ xrandr CLI: Standard tool, scriptable, real integration test

**Testing Pattern**:
```python
async def test_monitor_disconnect():
    # Get initial state
    initial_outputs = await i3_conn.get_outputs()

    # Simulate monitor disconnect
    subprocess.run(["xrandr", "--output", "HDMI-2", "--off"])

    # Wait for i3 to process change
    await asyncio.sleep(0.5)

    # Validate i3 updated its state
    updated_outputs = await i3_conn.get_outputs()
    hdmi2_output = find_output(updated_outputs, "HDMI-2")

    assert hdmi2_output["active"] == False

    # Validate workspaces reassigned
    workspaces = await i3_conn.get_workspaces()
    hdmi2_workspaces = [ws for ws in workspaces if ws["output"] == "HDMI-2"]
    assert len(hdmi2_workspaces) == 0  # All moved to other outputs
```

### 7. Test Isolation Strategy

**Decision**: Use "test-*" project namespace prefix for all test-created projects to avoid interfering with user's actual projects.

**Rationale**:
- Clear separation between real and test projects
- Easy to identify and cleanup test artifacts
- Prevents accidental deletion of user projects
- Allows tests to run on active development system
- Follows convention-based isolation pattern

**Implementation**:
```python
TEST_PROJECT_PREFIX = "test-"

def create_test_project(name: str) -> str:
    """Create test project with safety prefix"""
    test_project_name = f"{TEST_PROJECT_PREFIX}{name}-{uuid.uuid4().hex[:8]}"
    # Create project with unique ID
    return test_project_name

def cleanup_test_projects():
    """Remove all test projects"""
    projects = get_all_projects()
    test_projects = [p for p in projects if p.startswith(TEST_PROJECT_PREFIX)]
    for project in test_projects:
        delete_project(project)
```

### 8. CI/CD Integration Approach

**Decision**: Provide headless mode (--no-ui flag) with machine-readable output (JSON/TAP) and exit codes.

**Rationale**:
- CI environments often lack terminal UI capabilities
- JSON/TAP output can be parsed by CI tools
- Exit code 0 for success, non-zero for failures
- Supports both local development (rich UI) and CI (headless)
- Follows standard CLI tool conventions

**Output Formats**:
- **Terminal** (default): Rich library colored output, live progress, human-readable
- **JSON** (--format=json): Structured test results, parseable by tools
- **TAP** (--format=tap): Test Anything Protocol, standard CI format

**Exit Codes**:
- 0: All tests passed
- 1: One or more tests failed
- 2: Test execution error (setup failure, missing dependencies)
- 3: Invalid configuration

## Best Practices Integration

### Python Async Patterns

- Use `asyncio.gather()` for parallel i3 IPC queries
- Use `async with` for resource management (connections, sessions)
- Use `asyncio.create_task()` for background monitoring
- Proper exception handling with try/except/finally in async context

### Type Hints and Validation

- Use dataclasses for structured data (TestResult, OutputState, WorkspaceAssignment)
- Type hints on all public functions
- Pydantic models for JSON validation (diagnostic captures, test configs)
- mypy static type checking in development

### Error Handling

- Clear error messages with troubleshooting hints
- Structured exceptions (TestSetupError, ValidationError, StateCorruptionError)
- Graceful degradation (skip xrandr tests if X11 unavailable)
- Detailed assertion failure messages with expected vs actual diff

### Performance Optimization

- Cache i3 connection for multiple queries
- Batch IPC requests where possible
- Async operations to avoid blocking
- Timeout guards on all subprocess calls (tmux, xrandr)

## Integration with Existing Features

### Feature 015: i3 Project Event Daemon

**Enhancements Required**:
- Add JSON-RPC methods for test framework queries (if needed beyond existing API)
- Potentially add "test mode" flag for enhanced logging
- No breaking changes to existing API

**Already Available**:
- `get_status()`: Daemon health and statistics
- `get_active_project()`: Current active project
- `get_projects()`: All projects with window counts
- `get_windows(project)`: Windows filtered by project
- `get_events(limit, event_type)`: Event buffer history

### Feature 017: i3-project-monitor Tool

**Enhancements Required**:
- `live.py`: Add monitor panel showing GET_OUTPUTS data
- `live.py`: Add workspace assignment table from GET_WORKSPACES
- New `diagnose.py`: Diagnostic capture mode
- New `validators/`: Validation utilities

**Integration Points**:
- Test framework uses daemon_client.py to query daemon
- Validators use same models.py data structures
- Shared logging configuration

## Summary

All research questions resolved. Key decisions:

1. **i3 IPC as source of truth**: Use GET_OUTPUTS and GET_WORKSPACES directly
2. **Python class-based test scenarios**: Flexible, type-safe, composable
3. **Tmux for isolation**: Programmatic control via subprocess module
4. **JSON diagnostic format**: Versioned schema, machine-readable, diff-friendly
5. **Dual-source validation**: Compare daemon state against i3 IPC state
6. **xrandr for display testing**: Real integration tests via standard tool
7. **test-* namespace isolation**: Prevent interference with user projects
8. **Headless CI mode**: JSON/TAP output, exit codes, --no-ui flag

No blockers identified. Ready to proceed to Phase 1 (design).
