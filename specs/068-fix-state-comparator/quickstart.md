# Quickstart: State Comparison in Sway Test Framework

**Last Updated**: 2025-11-08 (Feature 068)
**Status**: Fixed - state comparison now works correctly for all test modes

## Overview

The sway-test framework validates that your Sway window manager behaves correctly by comparing expected vs actual window/workspace state after test actions execute. This guide covers the three comparison modes and how to write effective state assertions.

## Quick Reference

### Comparison Modes

| Mode | Trigger | Use Case | Example |
|------|---------|----------|---------|
| **Partial** (recommended) | `focusedWorkspace`, `windowCount`, `workspaces` | Simple assertions on specific properties | `{ "focusedWorkspace": 3 }` |
| **Exact** | `tree` | Full tree structure validation | `{ "tree": {...} }` |
| **Assertions** | `assertions` | Advanced JSONPath queries | `{ "assertions": [{...}] }` |

### Common Test Patterns

```json
// Pattern 1: Validate focused workspace
{
  "expectedState": {
    "focusedWorkspace": 3
  }
}

// Pattern 2: Count windows
{
  "expectedState": {
    "windowCount": 2
  }
}

// Pattern 3: Validate workspace structure
{
  "expectedState": {
    "workspaces": [
      {
        "num": 1,
        "focused": true,
        "windows": [
          { "app_id": "firefox" }
        ]
      }
    ]
  }
}

// Pattern 4: Combine multiple assertions
{
  "expectedState": {
    "focusedWorkspace": 3,
    "windowCount": 1,
    "workspaces": [
      { "num": 3, "focused": true }
    ]
  }
}
```

## Partial Mode (Recommended)

**Best for**: 90% of tests - simple assertions on workspace/window state

### Simple Assertions

```json
{
  "name": "Firefox launches on workspace 3",
  "actions": [
    { "type": "launch_app", "params": { "app_name": "firefox", "sync": true } }
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "windowCount": 1
  }
}
```

**What happens**:
1. Framework extracts `focusedWorkspace` and `windowCount` from actual Sway state
2. Compares extracted values against expected values
3. Ignores all other state properties (workspace names, window titles, etc.)

**✅ Test passes if**: Workspace 3 is focused AND exactly 1 window exists
**❌ Test fails if**: Different workspace focused OR different window count

### Workspace Structure Validation

```json
{
  "expectedState": {
    "workspaces": [
      {
        "num": 1,
        "focused": true,
        "windows": [
          {
            "app_id": "alacritty",
            "floating": false
          }
        ]
      },
      {
        "num": 3,
        "visible": true,
        "windows": [
          { "app_id": "firefox" }
        ]
      }
    ]
  }
}
```

**What happens**:
1. Framework extracts workspaces matching the specified structure
2. Compares only specified fields (num, focused, visible, windows)
3. Ignores unspecified fields (name, geometry, output)
4. Windows array is order-sensitive (first window matches first spec)

**Field semantics**:
- `undefined` (field not present) = don't check this field
- `null` = must be null
- Any value = must match exactly

### Undefined vs Null vs Missing

```json
// Example 1: Don't check workspace name (undefined)
{
  "workspaces": [
    { "num": 1, "focused": true }  // name is undefined → not checked
  ]
}

// Example 2: Workspace name must be null
{
  "workspaces": [
    { "num": 1, "name": null }  // name must be exactly null
  ]
}

// Example 3: Any workspace name is OK
{
  "workspaces": [
    { "num": 1 }  // name field missing → not checked
  ]
}
```

## Exact Mode

**Best for**: Full tree structure validation (rare - use only when partial mode insufficient)

```json
{
  "expectedState": {
    "tree": {
      "id": 1,
      "type": "root",
      "nodes": [
        {
          "type": "output",
          "name": "HEADLESS-1",
          "nodes": [
            {
              "type": "workspace",
              "num": 1,
              "focused": true,
              "nodes": [
                {
                  "type": "con",
                  "app_id": "firefox"
                }
              ]
            }
          ]
        }
      ]
    }
  }
}
```

**⚠️ Warning**: Exact mode compares the **entire** tree structure. Small differences (window IDs, timestamps, geometry) will cause test failures. Use partial mode instead.

## Assertion Mode

**Best for**: Advanced queries with operators

```json
{
  "expectedState": {
    "assertions": [
      {
        "path": "workspaces[0].num",
        "expected": 1,
        "operator": "equals"
      },
      {
        "path": "workspaces[*].windows[*].app_id",
        "expected": "firefox",
        "operator": "contains"
      },
      {
        "path": "workspaces.length",
        "expected": 3,
        "operator": "greaterThan"
      }
    ]
  }
}
```

**Supported operators**:
- `equals` (default): Exact match
- `contains`: Array/string contains value
- `matches`: Regex pattern match
- `greaterThan`: Numeric comparison
- `lessThan`: Numeric comparison

## Empty Expected State

```json
{
  "expectedState": {}
}
```

**Meaning**: Test passes if actions execute successfully (don't validate final state)

**Use case**: Testing action execution without caring about result state

## Debugging Failed Comparisons

When a test fails with "state comparison failed":

### 1. Check the diff output

```
✗ Firefox launches on workspace 3
  Message: State comparison failed
✗ States differ:
  Summary: ~1 modified
  Differences:
    ~ $.focusedWorkspace
      Expected: 3
      Actual:   1
```

**This tells you**: Expected workspace 3 to be focused, but workspace 1 is focused

### 2. Inspect actual state

Run test with verbose mode to see full actual state:

```bash
sway-test run path/to/test.json --verbose
```

### 3. Common mistakes

| Error Pattern | Cause | Fix |
|--------------|-------|-----|
| All fields show as "added" | Used exact mode with partial expected state | Switch to partial mode fields |
| Window not found | Wrong `app_id` or `class` | Check actual app_id with `swaymsg -t get_tree` |
| Workspace mismatch | App launched on wrong workspace | Fix app-registry.nix workspace assignment |
| Window count wrong | Windows from previous test still open | Add teardown actions or use isolated tests |

### 4. Inspect Sway state directly

```bash
# See full tree structure
swaymsg -t get_tree | jq

# See focused workspace
swaymsg -t get_tree | jq '.. | select(.focused? == true and .type? == "workspace") | .num'

# Count windows
swaymsg -t get_tree | jq '[.. | select(.app_id? or .window_properties?.class?) ] | length'
```

## Examples by Use Case

### Test: App launches on correct workspace

```json
{
  "name": "VS Code launches on workspace 2",
  "actions": [
    { "type": "launch_app", "params": { "app_name": "vscode", "sync": true } }
  ],
  "expectedState": {
    "focusedWorkspace": 2,
    "workspaces": [
      {
        "num": 2,
        "windows": [
          { "class": "Code" }
        ]
      }
    ]
  }
}
```

### Test: Multiple windows on multiple workspaces

```json
{
  "name": "Multi-window layout",
  "actions": [
    { "type": "launch_app", "params": { "app_name": "firefox" } },
    { "type": "send_ipc", "params": { "command": "workspace 2" } },
    { "type": "launch_app", "params": { "app_name": "vscode" } }
  ],
  "expectedState": {
    "windowCount": 2,
    "workspaces": [
      {
        "num": 3,
        "windows": [{ "app_id": "firefox" }]
      },
      {
        "num": 2,
        "focused": true,
        "windows": [{ "class": "Code" }]
      }
    ]
  }
}
```

### Test: Window focus behavior

```json
{
  "name": "Launched window receives focus",
  "actions": [
    { "type": "launch_app", "params": { "app_name": "alacritty", "sync": true } }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 1,
        "windows": [
          {
            "app_id": "Alacritty",
            "focused": true
          }
        ]
      }
    ]
  }
}
```

## Performance Tips

1. **Prefer partial mode**: 10ms comparison vs 50ms exact mode
2. **Minimize workspace specs**: Only specify workspaces you care about
3. **Use simple assertions**: `focusedWorkspace` faster than `workspaces` array
4. **Avoid exact mode**: Reserved for rare full-tree validation needs

## Migration from Old Tests

If you have tests written before Feature 068 fix:

### Before (broken):
```json
{
  "expectedState": {
    "state": { "focusedWorkspace": 3 }  // ❌ ".state" wrapper doesn't exist
  }
}
```

### After (fixed):
```json
{
  "expectedState": {
    "focusedWorkspace": 3  // ✅ Direct field
  }
}
```

## Running Tests

```bash
# Run single test
sway-test run path/to/test.json

# Run all tests in directory
sway-test run tests/integration/

# Run with verbose output (shows full diff)
sway-test run tests/ --verbose

# Run specific tags only
sway-test run tests/ --tags integration,workspace

# Fail fast (stop on first failure)
sway-test run tests/ --fail-fast
```

## Further Reading

- **Test File Format**: See `docs/TEST_FORMAT.md` for full JSON schema
- **Action Types**: See `src/models/test-case.ts` for all available actions
- **State Extraction**: See `src/services/state-extractor.ts` for implementation details
- **Comparison Logic**: See `src/services/state-comparator.ts` for comparison algorithms
