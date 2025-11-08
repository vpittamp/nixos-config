# Quickstart Guide: Sway Test Framework Enhancement

**Feature**: 067-sway-test-app-launch-fix
**Date**: 2025-11-08

## Overview

This guide demonstrates how to use the enhanced sway-test framework to test application launches via app-launcher-wrapper, wait for Sway events, and validate I3PM environment variables.

---

## Prerequisites

- NixOS with Sway window manager running
- sway-test framework installed (`/etc/nixos/home-modules/tools/sway-test`)
- app-launcher-wrapper.sh at `~/.local/bin/app-launcher-wrapper.sh`
- Application registry at `~/.config/i3/application-registry.json`
- (Optional) sway-tree-monitor daemon running for RPC features

---

## Quick Start: Production App Launch Testing

### Test 1: Launch Firefox and Verify Workspace

**File**: `tests/sway-tests/basic/test_firefox_workspace.json`

```json
{
  "name": "Firefox launches on workspace 3",
  "description": "Test that Firefox launches via app-launcher-wrapper and appears on workspace 3",
  "tags": ["app-launch", "workspace", "i3pm"],
  "timeout": 15000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "firefox"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 8000,
        "criteria": {
          "change": "new",
          "app_id": "firefox"
        }
      }
    }
  ],
  "expectedState": {
    "windows": [
      {
        "app_id": "firefox",
        "workspace": 3
      }
    ]
  }
}
```

**Note**: ALL apps must be defined in `~/.config/i3/application-registry.json`. Direct command execution is not supported.

**Run**:
```bash
cd /etc/nixos/home-modules/tools/sway-test
./sway-test run tests/sway-tests/basic/test_firefox_workspace.json
```

**Expected Output**:
```
✓ Firefox launches on workspace 3
  ✓ launch_app: firefox via wrapper
  ✓ wait_event: window::new (matched in 1.2s)
  ✓ State comparison: 1 window on workspace 3

1 passing (3.5s)
```

---

## Test 2: VS Code with Project Context

**File**: `tests/sway-tests/integration/test_vscode_scoped.json`

```json
{
  "name": "VS Code launches with project context",
  "description": "Test scoped app launch with I3PM_PROJECT_NAME set",
  "tags": ["app-launch", "scoped", "project"],
  "timeout": 20000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "vscode",
        "args": ["--folder-uri", "/etc/nixos"],
        "project": "nixos"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 12000,
        "criteria": {
          "change": "new",
          "app_id": "Code"
        }
      }
    }
  ],
  "expectedState": {
    "windows": [
      {
        "app_id": "Code",
        "workspace": 2
      }
    ]
  }
}
```

**What's Tested**:
- App launches via wrapper
- Project context passed as `I3PM_PROJECT_NAME=nixos`
- VS Code appears on workspace 2 (scoped app workspace)
- Window event captured within 12 seconds

**Run**:
```bash
./sway-test run tests/sway-tests/integration/test_vscode_scoped.json
```

---

## Test 3: Environment Variable Validation

**File**: `tests/sway-tests/integration/test_env_validation.json`

```json
{
  "name": "Wrapper injects I3PM environment variables",
  "description": "Test that launched app has correct I3PM_* environment variables",
  "tags": ["env-vars", "wrapper"],
  "timeout": 15000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "firefox"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 8000,
        "criteria": {
          "change": "new",
          "app_id": "firefox"
        }
      }
    },
    {
      "type": "validate_environment",
      "params": {
        "expected_vars": {
          "I3PM_APP_NAME": "firefox",
          "I3PM_TARGET_WORKSPACE": "3"
        }
      }
    }
  ],
  "expectedState": {
    "windows": [
      {
        "app_id": "firefox"
      }
    ]
  }
}
```

**Note**: `validate_environment` action will:
1. Extract PID from most recent Firefox window
2. Read `/proc/<pid>/environ`
3. Verify `I3PM_APP_NAME=firefox` and `I3PM_TARGET_WORKSPACE=3`

**Run**:
```bash
./sway-test run tests/sway-tests/integration/test_env_validation.json
```

---

## Test 4: Multiple Apps with Workspace Assignment

**File**: `tests/sway-tests/integration/test_multi_app_workspaces.json`

```json
{
  "name": "Multiple apps launch on correct workspaces",
  "description": "Test that 3 apps launch and appear on their configured workspaces",
  "tags": ["app-launch", "workspace", "multi-app"],
  "timeout": 30000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "firefox"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 8000,
        "criteria": {
          "change": "new",
          "app_id": "firefox"
        }
      }
    },
    {
      "type": "launch_app",
      "params": {
        "app_name": "vscode",
        "project": "nixos"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 12000,
        "criteria": {
          "change": "new",
          "app_id": "Code"
        }
      }
    },
    {
      "type": "launch_app",
      "params": {
        "app_name": "thunar"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 8000,
        "criteria": {
          "change": "new",
          "app_id": "thunar"
        }
      }
    }
  ],
  "expectedState": {
    "windows": [
      {
        "app_id": "firefox",
        "workspace": 3
      },
      {
        "app_id": "Code",
        "workspace": 2
      },
      {
        "app_id": "thunar",
        "workspace": 6
      }
    ]
  }
}
```

**What's Tested**:
- Sequential app launches via wrapper
- Each app gets correct workspace assignment (3, 2, 6)
- Event-driven waiting (no fixed delays)
- Final state validates all 3 windows on correct workspaces

**Run**:
```bash
./sway-test run tests/sway-tests/integration/test_multi_app_workspaces.json
```

---

## Test 5: PWA Launch and Workspace Assignment

**File**: `tests/sway-tests/integration/test_pwa_workspace.json`

```json
{
  "name": "Claude PWA launches on workspace 52",
  "description": "Test PWA (Progressive Web App) launch via wrapper",
  "tags": ["pwa", "workspace", "wrapper"],
  "timeout": 15000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "claude"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window",
        "timeout": 10000,
        "criteria": {
          "change": "new",
          "app_id": "FFPWA-01JCYF8Z2"
        }
      }
    }
  ],
  "expectedState": {
    "windows": [
      {
        "app_id": "FFPWA-01JCYF8Z2",
        "workspace": 52
      }
    ]
  }
}
```

**What's Tested**:
- PWA launch (Firefox PWA with custom app_id)
- Workspace assignment for PWAs (workspace 52)
- Event matching by exact PWA app_id

**Run**:
```bash
./sway-test run tests/sway-tests/integration/test_pwa_workspace.json
```

---

## Understanding Test Output

### Successful Test
```
✓ Firefox launches on workspace 3
  ✓ launch_app: firefox via wrapper (completed in 0.5s)
  ✓ wait_event: window::new for firefox (matched in 1.2s)
  ✓ State comparison: passed
    - Expected: 1 window (firefox) on workspace 3
    - Actual: 1 window (firefox) on workspace 3

1 passing (3.5s)
```

### Failed Test (Timeout)
```
✗ Firefox launches on workspace 3
  ✓ launch_app: firefox via wrapper (completed in 0.5s)
  ✗ wait_event: window::new for firefox (timeout after 8.0s)
    Error: WaitEventTimeoutError: No matching event after 8000ms
    Last tree state:
      Workspace 1: [Alacritty (pid 12345)]
      Workspace 3: []

Diagnostic: No Firefox window appeared. Check if:
  - Firefox is installed: which firefox
  - Wrapper script exists: ls -l ~/.local/bin/app-launcher-wrapper.sh
  - Registry contains Firefox: cat ~/.config/i3/application-registry.json | jq '.firefox'

0 passing, 1 failing (8.8s)
```

### Failed Test (Wrong Workspace)
```
✗ Firefox launches on workspace 3
  ✓ launch_app: firefox via wrapper (completed in 0.5s)
  ✓ wait_event: window::new for firefox (matched in 1.2s)
  ✗ State comparison: failed
    - Expected: window on workspace 3
    - Actual: window on workspace 1

Diff:
  - workspace: 3 (expected)
  + workspace: 1 (actual)

Diagnostic: Workspace assignment failed. Check if:
  - Daemon is running: systemctl --user status i3-project-event-listener
  - Registry has preferred_workspace: cat ~/.config/i3/application-registry.json | jq '.firefox.preferred_workspace'
  - Daemon logs: journalctl --user -u i3-project-event-listener -n 50

0 passing, 1 failing (3.8s)
```

---

## Common Use Cases

### Testing Workspace Assignment Regression

**Problem**: Feature 053 broke workspace assignment, need to catch regressions

**Solution**: Test that validates each app appears on its configured workspace

```json
{
  "name": "Workspace assignment regression test",
  "actions": [
    {"type": "launch_app", "params": {"app_name": "firefox"}},
    {"type": "wait_event", "params": {"event_type": "window", "timeout": 8000}},
    {"type": "validate_workspace_assignment", "params": {"app_name": "firefox", "expected_workspace": 3}}
  ]
}
```

### Testing I3PM Environment Variables

**Problem**: Wrapper fails to inject environment variables

**Solution**: Test that reads `/proc/<pid>/environ` and validates I3PM_* variables

```json
{
  "name": "Environment variable injection test",
  "actions": [
    {"type": "launch_app", "params": {"app_name": "firefox"}},
    {"type": "wait_event", "params": {"event_type": "window", "timeout": 8000}},
    {"type": "validate_environment", "params": {
      "expected_vars": {
        "I3PM_APP_NAME": "firefox",
        "I3PM_APP_ID": "firefox-global-*",
        "I3PM_TARGET_WORKSPACE": "3"
      }
    }}
  ]
}
```

**Note**: Use `*` wildcard for values that vary (e.g., timestamps in I3PM_APP_ID)

### Testing Without Daemon

**Problem**: Tests fail when daemon not running

**Solution**: Framework automatically degrades gracefully

```bash
# Stop daemon
systemctl --user stop i3-project-event-listener

# Run test - will use timeout-based fallback
./sway-test run tests/sway-tests/basic/test_firefox_workspace.json

# Expected output:
# Warning: Auto-sync unavailable (daemon not running), using timeout-based synchronization
# ✓ Firefox launches on workspace 3 (completed in 5.2s)
```

---

## Troubleshooting

### Test times out waiting for window event

**Symptoms**:
```
✗ wait_event: window::new for firefox (timeout after 8.0s)
```

**Possible Causes**:
1. App failed to launch (check wrapper script stderr)
2. App launched but window not created yet (increase timeout)
3. Event criteria doesn't match (check app_id vs expected_class)

**Debug**:
```bash
# Check app launches manually
~/.local/bin/app-launcher-wrapper.sh firefox

# Check Sway events in real-time
swaymsg -t subscribe -m '["window"]' | jq

# Check daemon logs
journalctl --user -u i3-project-event-listener -f
```

### App launches on wrong workspace

**Symptoms**:
```
✗ State comparison: failed
  - Expected: window on workspace 3
  + Actual: window on workspace 1
```

**Possible Causes**:
1. Daemon not running (workspace assignment disabled)
2. Registry missing preferred_workspace
3. Event-driven assignment failed (check daemon logs)

**Debug**:
```bash
# Check registry configuration
cat ~/.config/i3/application-registry.json | jq '.firefox'

# Check daemon status
systemctl --user status i3-project-event-listener

# Check daemon assignment logic
i3pm diagnose window <window-id>
```

### Environment variables missing

**Symptoms**:
```
✗ validate_environment: Missing I3PM_APP_NAME
```

**Possible Causes**:
1. App not launched via wrapper (check action uses via_wrapper: true)
2. Wrapper script failed to inject variables
3. Reading wrong process (parent vs child)

**Debug**:
```bash
# Check process environment manually
window-env firefox

# Check wrapper script execution
bash -x ~/.local/bin/app-launcher-wrapper.sh firefox 2>&1 | grep I3PM_
```

---

## Advanced: Custom Event Criteria

### Match by Window Title

```json
{
  "type": "wait_event",
  "params": {
    "event_type": "window",
    "timeout": 8000,
    "criteria": {
      "change": "title",
      "name": "*Mozilla Firefox"
    }
  }
}
```

### Match by Workspace Focus

```json
{
  "type": "wait_event",
  "params": {
    "event_type": "workspace",
    "timeout": 5000,
    "criteria": {
      "change": "focus",
      "workspace": 3
    }
  }
}
```

### Match Any Window Event

```json
{
  "type": "wait_event",
  "params": {
    "event_type": "window",
    "timeout": 10000
  }
}
```

**Note**: No criteria = match any window event (new, close, focus, etc.)

---

## Best Practices

### 1. All Apps Must Be in Registry

❌ **Bad**: App not in registry (will fail)
```json
{
  "type": "launch_app",
  "params": {
    "app_name": "my-custom-script"  // Not in application-registry.json
  }
}
```

✅ **Good**: App defined in registry
```json
// First: Add to ~/.config/i3/application-registry.json via app-registry-data.nix
// Then: Use in test
{
  "type": "launch_app",
  "params": {
    "app_name": "firefox"  // Exists in registry
  }
}
```

### 2. Use Specific Event Criteria

❌ **Bad**: Wait for any window
```json
{
  "type": "wait_event",
  "params": {
    "event_type": "window"
  }
}
```

✅ **Good**: Wait for specific app
```json
{
  "type": "wait_event",
  "params": {
    "event_type": "window",
    "criteria": {
      "change": "new",
      "app_id": "firefox"
    }
  }
}
```

### 3. Set Appropriate Timeouts

- **Fast apps** (terminal, thunar): 5-8 seconds
- **Medium apps** (Firefox, Chrome): 8-12 seconds
- **Slow apps** (VS Code, IDE): 12-20 seconds

### 4. Clean Up Between Tests

Use test fixtures to ensure clean state:

```json
{
  "name": "Firefox test",
  "setup": [
    {"type": "send_ipc", "params": {"command": "[app_id=firefox] kill"}}
  ],
  "actions": [
    // ... test actions
  ],
  "teardown": [
    {"type": "send_ipc", "params": {"command": "[app_id=firefox] kill"}}
  ]
}
```

---

## Next Steps

1. **Read**: [API Functions Contract](./contracts/api-functions.md) for detailed function signatures
2. **Read**: [Data Model](./data-model.md) for entity relationships and validation rules
3. **Read**: [Test Actions Schema](./contracts/test-actions.json) for complete action definitions
4. **Explore**: Existing tests in `tests/sway-tests/` for more examples
5. **Write**: Your own tests for app launch workflows!

---

## Getting Help

- **Framework Docs**: `/etc/nixos/home-modules/tools/sway-test/docs/`
- **Sway IPC Docs**: `man 7 sway-ipc`
- **App Registry**: `cat ~/.config/i3/application-registry.json | jq`
- **Daemon Status**: `systemctl --user status i3-project-event-listener`
- **Test Debugging**: Run with `--verbose` flag for detailed output
