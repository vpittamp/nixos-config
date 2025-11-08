# Sway Test Framework - Quick Start Guide

## Table of Contents

- [Installation](#installation)
- [Your First Test](#your-first-test)
- [Running Tests](#running-tests)
- [Common Patterns](#common-patterns)
- [Debugging](#debugging)
- [CI/CD Integration](#cicd-integration)

## Installation

### NixOS Installation

The Sway Test Framework is included in this NixOS configuration. Simply rebuild your system:

```bash
sudo nixos-rebuild switch --flake .#<target>
```

The `sway-test` command will be available in your PATH.

### Manual Installation

Requires:
- Deno 1.x or later
- Sway compositor (can run in headless mode for CI)
- Python 3.11+ with i3ipc, orjson, psutil (for tree-monitor integration)

```bash
# Clone the repository
git clone <repo-url>
cd home-modules/tools/sway-test

# Test installation
deno run --allow-all src/main.ts --version
```

### Docker Installation

```bash
# Build the Docker image
docker build -t sway-test:latest -f Dockerfile .

# Run tests in container
docker run --rm sway-test:latest deno run --allow-all src/main.ts run --ci
```

## Your First Test

### Create a Test File

Test cases are JSON files that describe:
1. **Initial setup** (fixtures, actions to reach desired state)
2. **Expected state** (what Sway should look like)
3. **Assertions** (deep comparisons using JSONPath)

Create `tests/sway-tests/my-first-test.json`:

```json
{
  "name": "Basic workspace switching",
  "description": "Verify switching to workspace 1 focuses that workspace",
  "actions": [
    {
      "type": "send_ipc",
      "params": {
        "ipc_command": "workspace number 1"
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 1,
    "workspaces": [
      {
        "num": 1,
        "focused": true
      }
    ]
  }
}
```

### Test File Structure

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Human-readable test name |
| `description` | No | Detailed explanation of test purpose |
| `tags` | No | Array of tags for filtering (e.g., `["workspace", "basic"]`) |
| `fixtures` | No | Array of fixture names to apply before test |
| `actions` | Yes | Array of actions to perform (see [Actions](#actions)) |
| `expectedState` | Yes | Expected Sway state after actions |

## Running Tests

### Basic Usage

```bash
# Run all tests
sway-test run

# Run specific test file
sway-test run tests/sway-tests/my-first-test.json

# Run tests matching tags
sway-test run --tags workspace,multi-monitor

# Run tests in specific directory
sway-test run --directory tests/sway-tests/workspaces/
```

### Output Formats

```bash
# Human-readable output (default)
sway-test run

# TAP format for CI/CD
sway-test run --format=tap

# JUnit XML for CI/CD
sway-test run --format=junit > test-results.xml

# CI mode (auto-enables TAP, no color, progress indicators)
sway-test run --ci
```

### Debugging Options

```bash
# Verbose output (shows all IPC calls and state captures)
sway-test run --verbose

# Interactive debugging (drops into REPL when test fails)
sway-test run --debug

# Fail fast (stop on first failure)
sway-test run --fail-fast

# Custom timeout
sway-test run --timeout 60
```

## Common Patterns

### Pattern 1: Workspace Management

```json
{
  "name": "Multi-workspace navigation",
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}},
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 2"}},
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}}
  ],
  "expectedState": {
    "focusedWorkspace": 1,
    "workspaces": [
      {"num": 1, "focused": true},
      {"num": 2, "focused": false}
    ]
  }
}
```

### Pattern 2: Window Management

```json
{
  "name": "Open and focus terminal",
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "exec alacritty"}},
    {"type": "wait_for_window", "params": {"app_id": "Alacritty", "timeout_ms": 2000}}
  ],
  "expectedState": {
    "hasWindows": [
      {"app_id": "Alacritty", "focused": true}
    ]
  }
}
```

### Pattern 3: Multi-Monitor Setups

```json
{
  "name": "Workspace distribution across monitors",
  "fixtures": ["threeMonitorLayout"],
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}},
    {"type": "send_ipc", "params": {"ipc_command": "focus output HEADLESS-2"}},
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 3"}}
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "outputs": [
      {"name": "HEADLESS-1", "current_workspace": "1"},
      {"name": "HEADLESS-2", "current_workspace": "3"}
    ]
  }
}
```

### Pattern 4: Using Fixtures

Fixtures provide pre-configured Sway states (e.g., multi-monitor setups, window layouts).

```json
{
  "name": "Test with multi-monitor fixture",
  "fixtures": ["threeMonitorLayout"],
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 1"}}
  ],
  "expectedState": {
    "outputs": [
      {"name": "HEADLESS-1"},
      {"name": "HEADLESS-2"},
      {"name": "HEADLESS-3"}
    ]
  }
}
```

### Pattern 5: Tree Monitor Integration

Track Sway events alongside test execution:

```json
{
  "name": "Workspace switch event correlation",
  "actions": [
    {"type": "send_ipc", "params": {"ipc_command": "workspace number 5"}}
  ],
  "expectedState": {
    "focusedWorkspace": 5
  },
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

## Debugging

### Interactive REPL

When a test fails with `--debug` flag, you enter an interactive REPL:

```bash
sway-test run --debug tests/sway-tests/failing-test.json
```

Available REPL commands:
- `state` - Show current Sway state
- `expected` - Show expected state
- `diff` - Show differences between current and expected
- `tree` - Show window tree
- `ipc <command>` - Send IPC command (e.g., `ipc workspace 2`)
- `retry` - Retry the test
- `continue` - Skip to next test
- `quit` - Exit test run

### Verbose Output

```bash
sway-test run --verbose
```

Shows:
- IPC commands sent
- State captures
- Comparison results
- Tree monitor events (if enabled)

### Understanding Diff Output

When a test fails, the framework shows a detailed diff:

```
✗ Basic workspace switching

Expected:
  $.focusedWorkspace: 1

Actual:
  $.focusedWorkspace: 2

Differences:
  focusedWorkspace: expected 1 but got 2
```

## CI/CD Integration

### GitHub Actions

Example workflow (see `.github/workflows/sway-tests-ci.yml`):

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: debian:bookworm-slim
    env:
      WLR_BACKENDS: headless
      WLR_LIBINPUT_NO_DEVICES: 1
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tests
        run: |
          sway-test run --ci --format=junit > test-results.xml
        timeout-minutes: 10

      - name: Publish results
        uses: EnricoMi/publish-unit-test-result-action@v2
        with:
          files: test-results.xml
```

### Docker

```bash
# Build container
docker build -t sway-test:latest -f home-modules/tools/sway-test/Dockerfile .

# Run tests
docker run --rm sway-test:latest
```

### TAP Output

```bash
sway-test run --format=tap
```

Produces:
```
TAP version 13
1..3
ok 1 - Basic workspace switching # duration_ms 45
ok 2 - Multi-workspace navigation # duration_ms 67
not ok 3 - Window focus test # duration_ms 123
  # Expected workspace 1 but got 2
```

### JUnit XML Output

```bash
sway-test run --format=junit > test-results.xml
```

Compatible with Jenkins, GitLab CI, GitHub Actions, and other CI systems.

## Advanced Topics

### Custom Fixtures

Create reusable Sway configurations in `src/fixtures/`:

```typescript
export const myCustomFixture: Fixture = {
  name: "myCustomFixture",
  description: "Custom multi-window layout",
  setup: async (client: SwayClient) => {
    await client.command("workspace number 1");
    await client.command("exec alacritty");
    // ... more setup
  },
  teardown: async (client: SwayClient) => {
    await client.command("[app_id=\"Alacritty\"] kill");
  }
};
```

### Performance Tips

- Use `--fail-fast` to stop on first failure
- Tag tests for selective execution
- Use fixtures to avoid repeating setup actions
- Run tests in parallel (future feature)

### Troubleshooting

**Sway not available:**
```bash
# Verify Sway is running
swaymsg -t get_version

# For CI, use headless mode (auto-detected)
export WLR_BACKENDS=headless
```

**Test timeouts:**
```bash
# Increase timeout (default 30s)
sway-test run --timeout 60
```

**State mismatches:**
- Use `--verbose` to see actual vs expected state
- Use `--debug` to enter interactive REPL
- Check fixture setup is complete before test actions

## Next Steps

- Read the [API Reference](api-reference.md) for detailed action and assertion syntax
- Explore example tests in `tests/sway-tests/`
- See [Dockerfile](../Dockerfile) for containerized testing setup
- Check [GitHub Actions workflow](/.github/workflows/sway-tests-ci.yml) for CI integration

## Support

- GitHub Issues: [Report bugs or request features]
- Documentation: [Full API reference](api-reference.md)
- Examples: `home-modules/tools/sway-test/tests/sway-tests/`
