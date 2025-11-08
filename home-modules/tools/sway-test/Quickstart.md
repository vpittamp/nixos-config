# Sway Test Framework - Quickstart Guide

## Overview

The Sway Test Framework is a test-driven development tool for testing Sway window manager system behavior. It enables you to write declarative JSON test definitions that execute actions and validate system state against expected outcomes.

**Key Features:**
- ✅ Declarative JSON test definitions
- ✅ Action execution (IPC commands, app launches, workspace switching)
- ✅ State capture and comparison with detailed diff output
- ✅ Tree-monitor integration for event correlation
- ✅ Test isolation with custom Sway configurations
- ✅ Timeout enforcement with diagnostic state capture
- ✅ Headless Sway support for CI/CD environments

## Installation

The framework is already integrated into your NixOS configuration. The CLI tool is available as `sway-test`.

**Location:** `/etc/nixos/home-modules/tools/sway-test/`

## Quick Start

### 1. Basic Usage

```bash
# Run a single test file
sway-test run tests/sway-tests/basic/test_window_launch.json

# Run multiple test files
sway-test run tests/sway-tests/**/*.json

# Run with verbose output
sway-test run --verbose tests/sway-tests/basic/test_window_launch.json

# Validate test definitions
sway-test validate tests/sway-tests/basic/test_window_launch.json
```

### 2. Writing Your First Test

Create a test file `tests/my_test.json`:

```json
{
  "name": "Basic workspace switching test",
  "description": "Verify workspace switching works correctly",
  "tags": ["basic", "workspace"],
  "timeout": 5000,
  "actions": [
    {
      "type": "send_ipc",
      "params": {
        "ipc_command": "workspace number 2"
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 2
  }
}
```

### 3. Running Your Test

```bash
sway-test run tests/my_test.json
```

**Expected Output:**
```
Running 1 test(s)...

✓ Basic workspace switching test
  Duration: 12ms

Test Suite: Test Suite
==================================================

Results:
  Total:   1
  ✓ Passed:  1

  Duration: 12ms

✓ All tests passed
==================================================
```

## Test Definition Structure

### Basic Structure

```json
{
  "name": "Test name (required)",
  "description": "What this test validates (required)",
  "tags": ["category", "type"],
  "timeout": 10000,
  "fixtures": ["fixtureName"],
  "actions": [...],
  "expectedState": {...}
}
```

### Available Actions

#### 1. send_ipc - Execute Sway IPC command
```json
{
  "type": "send_ipc",
  "params": {
    "ipc_command": "workspace number 3"
  }
}
```

#### 2. launch_app - Launch an application
```json
{
  "type": "launch_app",
  "params": {
    "app_name": "firefox",
    "command": "firefox",
    "args": ["--new-window"]
  }
}
```

#### 3. switch_workspace - Switch to a workspace
```json
{
  "type": "switch_workspace",
  "params": {
    "workspace": 2
  }
}
```

#### 4. focus_window - Focus a specific window
```json
{
  "type": "focus_window",
  "params": {
    "app_id": "firefox",
    "title": "Mozilla Firefox"
  }
}
```

#### 5. wait_event - Wait for a Sway event
```json
{
  "type": "wait_event",
  "params": {
    "event_type": "window::new",
    "timeout_ms": 5000
  }
}
```

#### 6. debug_pause - Pause execution for debugging
```json
{
  "type": "debug_pause",
  "params": {
    "message": "Inspect state before continuing"
  }
}
```

### Expected State Format

The `expectedState` field uses partial matching - you only need to specify the fields you want to validate:

```json
{
  "expectedState": {
    "focusedWorkspace": 1,
    "workspaces": [
      {
        "num": 1,
        "focused": true,
        "visible": true
      }
    ],
    "windows": [
      {
        "app_id": "firefox",
        "workspace": 1
      }
    ]
  }
}
```

## CLI Options

### run command

```bash
sway-test run [options] <test-files...>

Options:
  --verbose         Show detailed test output
  --no-color        Disable colored output
  --fail-fast       Stop on first test failure
  -c, --config <path>   Custom Sway config file for test isolation
```

### validate command

```bash
sway-test validate <test-files...>
```

Validates JSON schema and test definition structure without running the tests.

## Advanced Features

### 1. Test Isolation

Run tests with a custom Sway configuration:

```bash
sway-test run --config /path/to/custom-sway.conf tests/my_test.json
```

This launches a separate headless Sway instance with your custom configuration, ensuring tests don't interfere with your main desktop session.

### 2. Fixtures

Reuse common test setups across multiple tests:

```json
{
  "name": "Multi-monitor test",
  "fixtures": ["threeMonitorLayout"],
  "actions": [...]
}
```

See `tests/sway-tests/fixtures-demo/` for examples.

### 3. Tree-Monitor Integration

The framework automatically captures tree-monitor events during test execution and includes them in failure output:

```
📋 Tree Monitor Events (last 10):

  ▸ window::new [CRITICAL] @18:35:19
    Changes: 3 fields modified
  ▸ workspace::focus [MEDIUM] @18:35:20
    Changes: 2 fields modified
```

This provides valuable debugging context for understanding what happened during test execution.

### 4. Timeout Handling

Tests automatically capture diagnostic state on timeout:

```bash
⏱ Test timeout (T078)
  Duration: 30000ms
  Message: Test exceeded timeout of 30000ms

  Recovery Suggestions:
    • Increase timeout value in test definition
    • Check if action is blocking or waiting indefinitely
    • Review diagnostic state for stuck processes
```

## Example Tests

### Multi-Step Workflow

```json
{
  "name": "Project switch workflow",
  "description": "Switch workspace, launch app, verify state",
  "tags": ["workflow", "multi-step"],
  "timeout": 15000,
  "actions": [
    {
      "type": "switch_workspace",
      "params": {"workspace": 3}
    },
    {
      "type": "launch_app",
      "params": {
        "app_name": "code",
        "command": "code",
        "args": ["/etc/nixos"]
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 10000
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "windows": [
      {"app_id": "code", "workspace": 3}
    ]
  }
}
```

### Interactive Debugging

```json
{
  "name": "Debug workspace state",
  "description": "Pause and inspect workspace configuration",
  "actions": [
    {
      "type": "switch_workspace",
      "params": {"workspace": 1}
    },
    {
      "type": "debug_pause",
      "params": {
        "message": "Inspect workspace 1 state"
      }
    }
  ]
}
```

## CI/CD Integration

The framework works in headless environments for automated testing:

```bash
# In CI/CD pipeline
WLR_BACKENDS=headless sway-test run tests/**/*.json
```

Or use the built-in headless mode (automatically enabled):

```bash
sway-test run tests/**/*.json
```

## Troubleshooting

### Test Failures

When a test fails, the framework shows:
1. **Summary**: Number of differences found
2. **Detailed Diff**: Field-by-field comparison (Expected vs Actual)
3. **Tree Monitor Events**: Recent Sway events with timestamps
4. **Recovery Suggestions**: Actionable next steps

### Common Issues

**Issue:** Test times out
**Solution:** Increase timeout value or check if actions are blocking

**Issue:** State mismatch
**Solution:** Use `--verbose` to see actual state, adjust `expectedState` accordingly

**Issue:** Application not found
**Solution:** Ensure application is available in headless environment or use IPC commands instead

## Next Steps

1. **Explore Examples**: Check `tests/sway-tests/` for more test examples
2. **Read the Spec**: See `/etc/nixos/specs/001-test-driven-development/spec.md` for detailed feature documentation
3. **Write Tests**: Create test definitions for your Sway window management workflows
4. **Integrate with CI**: Add test execution to your CI/CD pipeline

## Technical Details

- **Runtime**: Deno (TypeScript)
- **Location**: `/etc/nixos/home-modules/tools/sway-test/`
- **Test Examples**: `/etc/nixos/home-modules/tools/sway-test/tests/sway-tests/`
- **Documentation**: `/etc/nixos/specs/001-test-driven-development/`

## Support

For issues, questions, or feature requests:
- Check the specification: `/etc/nixos/specs/001-test-driven-development/spec.md`
- Review research notes: `/etc/nixos/specs/001-test-driven-development/research.md`
- See implementation tasks: `/etc/nixos/specs/001-test-driven-development/tasks.md`

---

**Version**: 1.0.0
**Last Updated**: 2025-11-08
**Framework Status**: ✅ Production Ready
