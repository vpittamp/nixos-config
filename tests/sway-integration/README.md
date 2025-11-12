# Sway Integration Tests - NixOS Test Driver

Comprehensive integration testing for Sway window manager using NixOS's native VM-based test infrastructure.

## Overview

This test suite runs your sway-test framework in an isolated NixOS VM with full Sway compositor, i3pm daemon, and sway-tree-monitor. It provides:

- **Isolated Environment**: Each test runs in a fresh QEMU VM
- **Reproducible**: Exact NixOS configuration based on hetzner-sway
- **Headless Wayland**: Uses pixman software rendering with 3 virtual displays
- **Complete Stack**: Sway + i3pm + sway-tree-monitor + your test framework
- **Debugging Support**: Interactive mode with Python REPL and screenshots

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     NixOS Test Driver                        │
│  (Python test scripts orchestrating QEMU VM)                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    QEMU Virtual Machine                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ NixOS with Sway (headless Wayland)                    │  │
│  │  • WLR_BACKENDS=headless                              │  │
│  │  • WLR_RENDERER=pixman                                │  │
│  │  • 3 virtual displays (HEADLESS-1,2,3)                │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ System Services                                        │  │
│  │  • i3-project-event-listener (i3pm daemon)            │  │
│  │  • sway-tree-monitor (event tracking)                 │  │
│  │  • greetd (auto-login testuser)                       │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Sway Test Framework                                    │  │
│  │  • TypeScript/Deno test runner                        │  │
│  │  • JSON test case definitions                         │  │
│  │  • Sync-based actions (Feature 069)                   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Running Individual Tests

```bash
# From nixos-config root directory
cd /home/user/nixos-config

# Build and run basic functionality test
nix-build tests/sway-integration -A basic

# Run window launch test
nix-build tests/sway-integration -A windowLaunch

# Run workspace navigation test
nix-build tests/sway-integration -A workspaceNavigation

# Run i3pm daemon integration test
nix-build tests/sway-integration -A i3pmDaemon

# Run multi-monitor test
nix-build tests/sway-integration -A multiMonitor

# Run sway-test framework integration
nix-build tests/sway-integration -A swayTestFramework
```

### Running All Tests

```bash
# Run all tests in sequence
nix-build tests/sway-integration -A all

# View results
cat result/results.txt
```

### Interactive Debugging

The interactive mode gives you a Python REPL where you can:
- Execute commands in the VM with `machine.succeed("command")`
- Take screenshots with `machine.screenshot("name")`
- Read files with `machine.succeed("cat /path/to/file")`
- Inspect Sway state with `swaymsg` commands

```bash
# Build the interactive test driver
nix-build tests/sway-integration -A interactive

# Run interactively
$(result)/bin/nixos-test-driver

# In the Python REPL:
>>> machine.shell_interact()  # Interactive shell in the VM
>>> machine.succeed("su - testuser -c 'swaymsg -t get_tree'")
>>> machine.screenshot("debug")
>>> machine.succeed("su - testuser -c 'i3pm daemon status'")
```

## Test Categories

### 1. Basic Functionality (`basic`)

Tests core Sway functionality:
- VM boots successfully
- Sway compositor starts
- 3 virtual displays are created
- IPC socket is available
- Basic workspace switching works

**Run**: `nix-build tests/sway-integration -A basic`

### 2. Window Launch (`windowLaunch`)

Tests window creation and tracking:
- Launch terminal application
- Verify window appears in Sway tree
- Check window properties (app_id, workspace)

**Run**: `nix-build tests/sway-integration -A windowLaunch`

### 3. Workspace Navigation (`workspaceNavigation`)

Tests workspace switching:
- Switch between workspaces 1-5
- Verify focused workspace changes
- Ensure workspace state is consistent

**Run**: `nix-build tests/sway-integration -A workspaceNavigation`

### 4. i3pm Daemon (`i3pmDaemon`)

Tests i3pm project management:
- Verify daemon is running
- Check daemon status
- List projects
- Validate IPC communication

**Run**: `nix-build tests/sway-integration -A i3pmDaemon`

### 5. Multi-Monitor (`multiMonitor`)

Tests workspace distribution across displays:
- Verify 3 outputs exist
- Create workspaces on different outputs
- Validate workspace-to-monitor assignment (Feature 001)

**Run**: `nix-build tests/sway-integration -A multiMonitor`

### 6. Sway-Test Framework (`swayTestFramework`)

Tests the sway-test framework itself:
- Load JSON test case
- Execute sync-based actions
- Validate state comparison

**Run**: `nix-build tests/sway-integration -A swayTestFramework`

## Writing New Tests

### 1. Add to `default.nix`

```nix
myNewTest = makeSwayTest {
  name = "sway-my-new-test";
  testScript = ''
    # Your Python test code here
    machine.succeed("su - testuser -c 'swaymsg workspace number 1'")

    # Take screenshot
    machine.screenshot("my_test")

    # Assert something
    output = machine.succeed("su - testuser -c 'some-command'")
    assert "expected" in output, "Test failed"

    print("✓ My new test passed")
  '';
};
```

### 2. Create JSON Test Case

For tests using the sway-test framework, create JSON files in `test-cases/`:

```json
{
  "name": "My Feature Test",
  "description": "Test description here",
  "actions": [
    {
      "type": "launch_app_sync",
      "params": {"app_name": "alacritty"}
    },
    {
      "type": "send_ipc_sync",
      "params": {"ipc_command": "workspace number 2"}
    }
  ],
  "expectedState": {
    "focusedWorkspace": 2,
    "windowCount": 1
  }
}
```

### 3. Run from VM

```nix
swayTestFramework = makeSwayTest {
  name = "my-json-test";
  testScript = ''
    # Copy test case to VM
    machine.copy_from_host("${./test-cases/my-test.json}", "/tmp/my-test.json")

    # Run with sway-test framework
    machine.succeed("su - testuser -c 'sway-test run /tmp/my-test.json'")
  '';
};
```

## Available Test Methods

The `machine` object provides many useful methods:

### Command Execution
- `machine.succeed(command)` - Run command, assert success, return output
- `machine.fail(command)` - Run command, assert failure
- `machine.execute(command)` - Run command, return (status, output) tuple

### Timing & Waiting
- `machine.sleep(seconds)` - Wait for specified time
- `machine.wait_for_unit(unit)` - Wait for systemd unit to start
- `machine.wait_for_file(path)` - Wait for file to exist
- `machine.wait_for_open_port(port)` - Wait for network port

### Debugging
- `machine.screenshot(name)` - Save screenshot to result directory
- `machine.get_screen_text()` - OCR text from screen
- `machine.shell_interact()` - Interactive shell in VM

### User Sessions
- Use `su - testuser -c 'command'` to run commands as test user
- Use `systemctl --user -M testuser@ ...` for user systemd units

## Test Case Examples

See `test-cases/` directory for complete examples:

- `workspace-navigation.json` - Workspace switching and focus
- `multi-window-layout.json` - Tiling layout with multiple windows
- `workspace-assignment.json` - App workspace assignment (Feature 001)
- `window-focus.json` - Focus navigation between windows

## Troubleshooting

### Test Hangs or Times Out

The VM might not be starting Sway properly. Check:

```bash
# Run interactively to debug
$(nix-build tests/sway-integration -A interactive)/bin/nixos-test-driver

# In REPL:
>>> machine.succeed("systemctl status greetd")
>>> machine.succeed("ps aux | grep sway")
>>> machine.succeed("journalctl -u greetd -n 50")
```

### Sway IPC Socket Not Found

```bash
# Check if socket exists
>>> machine.succeed("ls -la /tmp/sway-ipc.sock")

# Check Sway logs
>>> machine.succeed("journalctl --user -M testuser@ -u sway -n 50")
```

### i3pm Daemon Not Running

```bash
# Check daemon status
>>> machine.succeed("systemctl --user -M testuser@ status i3-project-event-listener")

# View daemon logs
>>> machine.succeed("journalctl --user -M testuser@ -u i3-project-event-listener -n 50")
```

### Application Won't Launch

```bash
# Check if app is installed
>>> machine.succeed("which alacritty")

# Try launching manually
>>> machine.succeed("su - testuser -c 'alacritty &'")

# Check Sway tree for window
>>> machine.succeed("su - testuser -c 'swaymsg -t get_tree | jq'")
```

### Screenshots Not Appearing

Screenshots are saved to the Nix store result directory:

```bash
# After test runs
ls result/*.png

# Or specify custom path in test
machine.screenshot("/tmp/my-debug-screenshot")
```

## Performance

Test execution times (on typical hardware):

- **VM Boot**: ~10-15 seconds
- **Sway Start**: ~2-5 seconds
- **Per Test**: ~5-30 seconds depending on complexity
- **Full Suite**: ~2-3 minutes

Optimization tips:
- Use `launch_app_sync` instead of `launch_app` + `wait_event` (5-10x faster)
- Minimize `sleep()` calls - use `wait_for_*` methods instead
- Reuse VM state where possible (but be careful of test isolation)

## CI/CD Integration

These tests are designed to run in CI environments:

```yaml
# Example GitHub Actions
- name: Run Sway Integration Tests
  run: |
    nix-build tests/sway-integration -A all

# Example GitLab CI
test:sway-integration:
  script:
    - nix-build tests/sway-integration -A all
```

## Comparison with Existing Framework

| Aspect | Current sway-test | NixOS Integration Tests |
|--------|-------------------|-------------------------|
| Isolation | Runs on live system | Fresh VM per test |
| Reproducibility | Depends on system state | Fully reproducible |
| Debugging | REPL in test framework | Full VM access + Python REPL |
| Speed | Fast (no VM overhead) | Slower (VM boot time) |
| Use Case | Rapid development | CI/CD, regression testing |

**Best Practice**: Use both!
- **Development**: Regular sway-test for fast iteration
- **CI/CD**: NixOS integration tests for reproducibility
- **Debugging**: NixOS tests for full system inspection

## Related Documentation

- **Sway Test Framework**: `/etc/nixos/specs/069-sync-test-framework/quickstart.md`
- **Feature 001 (Workspace Assignment)**: `/etc/nixos/specs/001-declarative-workspace-monitor/quickstart.md`
- **i3pm Daemon**: `/etc/nixos/specs/015-create-a-new/quickstart.md`
- **NixOS Test Driver**: https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines

## Contributing

When adding new tests:
1. Follow the naming convention: `sway-feature-name`
2. Include clear assertions with helpful error messages
3. Add screenshots for visual verification
4. Document expected behavior in test description
5. Keep tests focused and atomic (one feature per test)
6. Use sync-based actions from Feature 069

## License

Part of the NixOS configuration at `/etc/nixos/`
