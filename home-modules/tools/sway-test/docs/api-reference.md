# Sway Test Framework - API Reference

## Table of Contents

- [Test Case Format](#test-case-format)
- [Actions](#actions)
- [Expected State](#expected-state)
- [Fixtures](#fixtures)
- [CLI Commands](#cli-commands)
- [Output Formats](#output-formats)
- [Python Daemon API](#python-daemon-api)

## Test Case Format

### TestCase Schema

```typescript
interface TestCase {
  name: string;                // Human-readable test name (required)
  description?: string;        // Detailed test description
  tags?: string[];             // Tags for filtering (e.g., ["workspace", "multi-monitor"])
  fixtures?: string[];         // Fixture names to apply before test
  actions: Action[];           // Actions to perform (required)
  expectedState: ExpectedState; // Expected Sway state after actions (required)
  expectations?: {             // Advanced assertions
    treeMonitorEvents?: TreeMonitorExpectations;
  };
}
```

### Minimal Example

```json
{
  "name": "Workspace switch to 1",
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}}
  ],
  "expectedState": {
    "focusedWorkspace": 1
  }
}
```

### Full Example

```json
{
  "name": "Multi-window workspace management",
  "description": "Verifies workspace switching with multiple windows preserves focus",
  "tags": ["workspace", "window-management", "focus"],
  "fixtures": ["threeMonitorLayout"],
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}},
    {"type": "send_ipc", "params": {"ipc_command": "exec alacritty"}},
    {"type": "wait_for_window", "params": {"app_id": "Alacritty", "timeout_ms": 2000}},
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 2"}},
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}}
  ],
  "expectedState": {
    "focusedWorkspace": 1,
    "hasWindows": [
      {"app_id": "Alacritty", "focused": true}
    ],
    "workspaces": [
      {"num": 1, "focused": true, "visible": true},
      {"num": 2, "focused": false, "visible": false}
    ]
  },
  "expectations": {
    "treeMonitorEvents": {
      "hasEvent": {
        "type": "workspace",
        "change": "focus",
        "current": {"num": 1}
      }
    }
  }
}
```

## Actions

Actions are executed sequentially to set up test conditions.

### send_ipc

Send an IPC command to Sway.

**Parameters:**
- `ipc_command` (string, required): Sway IPC command

**Examples:**

```json
{"type": "send_ipc", "params": {"ipc_command": "workspace number 5"}}
{"type": "send_ipc", "params": {"ipc_command": "exec firefox"}}
{"type": "send_ipc", "params": {"ipc_command": "focus left"}}
{"type": "send_ipc", "params": {"ipc_command": "split h"}}
{"type": "send_ipc", "params": {"ipc_command": "layout tabbed"}}
```

### wait_for_window

Wait for a window matching criteria to appear.

**Parameters:**
- `app_id` (string, optional): Window app_id to match
- `title` (string, optional): Window title to match (regex supported)
- `class` (string, optional): Window class to match
- `timeout_ms` (number, optional): Timeout in milliseconds (default: 5000)

**Examples:**

```json
// Wait for Alacritty by app_id
{"type": "wait_for_window", "params": {"app_id": "Alacritty"}}

// Wait for window with specific title
{"type": "wait_for_window", "params": {"title": "My Document.*", "timeout_ms": 3000}}

// Wait for any Firefox window
{"type": "wait_for_window", "params": {"class": "firefox"}}
```

### delay

Pause execution for specified milliseconds.

**Parameters:**
- `ms` (number, required): Milliseconds to wait

**Example:**

```json
{"type": "delay", "params": {"ms": 500}}
```

**Use Cases:**
- Allow window animations to complete
- Wait for async operations
- Debugging timing issues

### capture_state

Explicitly capture Sway state at this point (for debugging).

**Parameters:** None

**Example:**

```json
{"type": "capture_state"}
```

**Output:** State captured in verbose mode or debug REPL.

## Expected State

The `expectedState` object defines assertions about Sway's state after all actions complete.

### Workspace Assertions

```typescript
interface ExpectedState {
  // Current focused workspace number
  focusedWorkspace?: number;

  // Workspace list with detailed assertions
  workspaces?: Array<{
    num?: number;             // Workspace number
    name?: string;            // Workspace name
    focused?: boolean;        // Is focused
    visible?: boolean;        // Is visible on any output
    urgent?: boolean;         // Has urgent flag
    output?: string;          // Output name (e.g., "HEADLESS-1")
  }>;

  // Quick check: workspace numbers that should exist
  hasWorkspaces?: number[];
}
```

**Examples:**

```json
// Simple: verify focused workspace
{"focusedWorkspace": 3}

// Detailed: verify workspace properties
{
  "workspaces": [
    {"num": 1, "focused": true, "visible": true, "output": "HEADLESS-1"},
    {"num": 2, "focused": false, "visible": false}
  ]
}

// Quick check: these workspaces exist
{"hasWorkspaces": [1, 2, 3]}
```

### Window Assertions

```typescript
interface ExpectedState {
  // Window list with detailed assertions
  hasWindows?: Array<{
    app_id?: string;          // Window app_id
    title?: string;           // Window title (regex supported)
    class?: string;           // Window class
    focused?: boolean;        // Is focused
    floating?: boolean;       // Is floating
    fullscreen?: boolean;     // Is fullscreen
    workspace?: number;       // Workspace number
  }>;

  // Quick check: window count
  windowCount?: number;

  // No windows should exist
  noWindows?: boolean;
}
```

**Examples:**

```json
// Verify specific window exists and is focused
{
  "hasWindows": [
    {"app_id": "Alacritty", "focused": true, "floating": false}
  ]
}

// Verify window on specific workspace
{
  "hasWindows": [
    {"app_id": "firefox", "workspace": 2}
  ]
}

// Verify total window count
{"windowCount": 3}

// Verify no windows exist
{"noWindows": true}
```

### Output (Monitor) Assertions

```typescript
interface ExpectedState {
  outputs?: Array<{
    name?: string;            // Output name (e.g., "HEADLESS-1")
    active?: boolean;         // Is active
    current_workspace?: string; // Current workspace name
    focused?: boolean;        // Is focused
    scale?: number;           // Output scale
  }>;

  // Current focused output name
  focusedOutput?: string;
}
```

**Examples:**

```json
// Verify outputs exist
{
  "outputs": [
    {"name": "HEADLESS-1", "active": true},
    {"name": "HEADLESS-2", "active": true}
  ]
}

// Verify workspace on specific output
{
  "outputs": [
    {"name": "HEADLESS-1", "current_workspace": "1"}
  ]
}

// Verify focused output
{"focusedOutput": "HEADLESS-2"}
```

### Container Tree Assertions

```typescript
interface ExpectedState {
  // Deep tree structure assertion (advanced)
  tree?: {
    type?: string;            // Container type
    layout?: string;          // Layout mode
    nodes?: TreeNode[];       // Child nodes
  };
}
```

**Example:**

```json
{
  "tree": {
    "type": "workspace",
    "layout": "splith",
    "nodes": [
      {"type": "con", "app_id": "Alacritty"},
      {"type": "con", "app_id": "firefox"}
    ]
  }
}
```

### Tree Monitor Event Assertions

```typescript
interface ExpectedState {
  expectations?: {
    treeMonitorEvents?: {
      hasEvent?: {
        type?: string;        // Event type (e.g., "workspace", "window")
        change?: string;      // Change type (e.g., "focus", "new", "close")
        current?: object;     // Current state assertions
      };
      eventCount?: number;    // Total event count
    };
  };
}
```

**Example:**

```json
{
  "expectations": {
    "treeMonitorEvents": {
      "hasEvent": {
        "type": "workspace",
        "change": "focus",
        "current": {"num": 5}
      }
    }
  }
}
```

## Fixtures

Fixtures provide pre-configured Sway states for testing.

### Built-in Fixtures

#### threeMonitorLayout

Creates three virtual headless outputs with workspace distribution.

**Outputs:**
- `HEADLESS-1`: 1920x1080, workspaces 1-2
- `HEADLESS-2`: 1920x1080, workspaces 3-5
- `HEADLESS-3`: 1920x1080, workspaces 6+

**Usage:**

```json
{
  "name": "Test with multi-monitor",
  "fixtures": ["threeMonitorLayout"],
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 3"}},
    {"type": "send_ipc", "params": {"ipc_command": "focus output HEADLESS-2"}}
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "focusedOutput": "HEADLESS-2"
  }
}
```

### Custom Fixtures

Define custom fixtures in `src/fixtures/custom-fixtures.ts`:

```typescript
import type { Fixture } from "../models/fixture.ts";
import type { SwayClient } from "../services/sway-client.ts";

export const myFixture: Fixture = {
  name: "myFixture",
  description: "Custom window layout",
  setup: async (client: SwayClient) => {
    await client.command("workspace number 1");
    await client.command("exec alacritty");
    await client.command("exec firefox");
    // Wait for windows to appear
    await new Promise(resolve => setTimeout(resolve, 1000));
  },
  teardown: async (client: SwayClient) => {
    await client.command("[app_id=\"Alacritty\"] kill");
    await client.command("[class=\"firefox\"] kill");
  }
};
```

Register in `src/fixtures/index.ts`:

```typescript
import { myFixture } from "./custom-fixtures.ts";

export const allFixtures: Fixture[] = [
  threeMonitorLayout,
  myFixture
];
```

## CLI Commands

### sway-test run

Run tests matching criteria.

**Syntax:**

```bash
sway-test run [test-files...] [options]
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--directory, -d` | string | `tests/sway-tests` | Test directory path |
| `--tags, -t` | string | none | Comma-separated tags to filter |
| `--verbose, -v` | boolean | false | Verbose output |
| `--debug` | boolean | false | Interactive debugging (REPL) |
| `--no-color` | boolean | false | Disable colored output |
| `--fail-fast, -f` | boolean | false | Stop on first failure |
| `--timeout` | number | 30 | Test timeout in seconds |
| `--format` | string | `human` | Output format: `human`, `tap`, `junit` |
| `--ci` | boolean | false | CI mode (enables TAP, no-color, progress) |

**Examples:**

```bash
# Run all tests
sway-test run

# Run specific test file
sway-test run tests/sway-tests/workspace-switching.json

# Run tests with tags
sway-test run --tags workspace,multi-monitor

# Verbose output
sway-test run --verbose

# Interactive debugging
sway-test run --debug --fail-fast

# CI mode with JUnit output
sway-test run --ci --format=junit > results.xml

# Custom timeout
sway-test run --timeout 60
```

### sway-test --version

Display version information.

```bash
sway-test --version
```

### sway-test --help

Display help information.

```bash
sway-test --help
```

## Output Formats

### Human (Default)

Colored, human-readable output with test results and diffs.

**Example:**

```
Running 3 tests from tests/sway-tests/

✓ Basic workspace switching (45ms)
✓ Multi-workspace navigation (67ms)
✗ Window focus test (123ms)

  Expected:
    $.focusedWorkspace: 1

  Actual:
    $.focusedWorkspace: 2

  Differences:
    focusedWorkspace: expected 1 but got 2

=================================
Test Suite Summary
=================================
Tests:    3
Passed:   2 (66.67%)
Failed:   1 (33.33%)
Duration: 235ms
Average:  78ms per test
```

### TAP (Test Anything Protocol)

Machine-readable TAP v13 format for CI/CD.

**Command:**

```bash
sway-test run --format=tap
```

**Example Output:**

```
TAP version 13
1..3
ok 1 - Basic workspace switching # duration_ms 45
ok 2 - Multi-workspace navigation # duration_ms 67
not ok 3 - Window focus test # duration_ms 123
  # Expected workspace 1 but got 2
  # Differences found:
  #   focusedWorkspace: expected 1 but got 2
# Summary: 2 passed, 1 failed, 3 total
```

### JUnit XML

XML format compatible with Jenkins, GitLab CI, GitHub Actions.

**Command:**

```bash
sway-test run --format=junit > test-results.xml
```

**Example Output:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Sway Test Suite" tests="3" failures="1" errors="0" skipped="0" time="0.235">
    <testcase classname="SwayTest" name="Basic workspace switching" time="0.045"/>
    <testcase classname="SwayTest" name="Multi-workspace navigation" time="0.067"/>
    <testcase classname="SwayTest" name="Window focus test" time="0.123">
      <failure message="Test failed">
        <![CDATA[Differences found:
  focusedWorkspace: expected 1 but got 2]]>
      </failure>
    </testcase>
  </testsuite>
</testsuites>
```

## Python Daemon API

The Python test support daemon provides state capture and event monitoring.

### Module: test_support.state_capture

**Function:** `capture_tree_state()`

Captures current Sway tree state.

```python
from test_support.state_capture import capture_tree_state

state = capture_tree_state()
print(state["focused_workspace"])  # Current workspace number
print(state["workspaces"])          # List of all workspaces
print(state["windows"])             # List of all windows
```

**Returns:**

```python
{
  "focused_workspace": int,
  "focused_output": str,
  "workspaces": [
    {"num": int, "name": str, "focused": bool, "visible": bool, "output": str}
  ],
  "windows": [
    {"app_id": str, "title": str, "focused": bool, "workspace": int}
  ],
  "outputs": [
    {"name": str, "active": bool, "current_workspace": str}
  ],
  "tree": {...}  // Full container tree
}
```

### Module: test_support.event_monitor

**Class:** `EventMonitor`

Monitors Sway IPC events for test correlation.

```python
from test_support.event_monitor import EventMonitor

monitor = EventMonitor()
monitor.start()

# ... perform test actions ...

events = monitor.get_events()
workspace_events = [e for e in events if e["type"] == "workspace"]

monitor.stop()
```

**Methods:**

- `start()`: Start monitoring events
- `stop()`: Stop monitoring
- `get_events()`: Retrieve captured events
- `clear_events()`: Clear event history

**Event Structure:**

```python
{
  "type": str,         # "workspace", "window", "output", etc.
  "change": str,       # "focus", "new", "close", "move", etc.
  "timestamp": float,  # Unix timestamp
  "current": {...}     // Current state
}
```

## JSONPath Expressions

Use JSONPath for deep state assertions.

**Syntax:** `$.path.to.field`

**Examples:**

```json
// Focus state
"$.focused": true

// Workspace number
"$.workspaces[0].num": 1

// Window app_id
"$.windows[?(@.focused == true)].app_id": "Alacritty"

// Output name
"$.outputs[0].name": "HEADLESS-1"
```

## Error Codes

| Code | Description |
|------|-------------|
| 0 | All tests passed |
| 1 | One or more tests failed |
| 2 | Configuration error |
| 3 | Sway connection error |
| 4 | Test file parsing error |
| 5 | Fixture setup error |

## Next Steps

- Read [Quick Start Guide](quickstart.md) for practical examples
- Explore `tests/sway-tests/` for example test cases
- See [Dockerfile](../Dockerfile) for CI setup
- Check [GitHub Actions workflow](/.github/workflows/sway-tests-ci.yml)
