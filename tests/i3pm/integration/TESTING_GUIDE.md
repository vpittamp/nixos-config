# i3pm Integration Testing Guide

## Problem: Terminal Disconnect

Integration tests launch real applications (Xvfb, i3, xterm) which can take 30+ seconds. If your SSH/terminal session disconnects, the tests abort. This guide solves that problem.

## Solution: systemd User Service

We run tests via a systemd user service that:
✅ Survives terminal disconnection
✅ Runs completely in background
✅ Logs to journalctl (persistent logs)
✅ Automatic cleanup on completion
✅ Resource limits to prevent runaway tests

## Quick Start

### Option 1: Run Standalone (Fastest)

Run tests directly with all dependencies included (no systemd setup needed):

```bash
cd /etc/nixos/tests/i3pm/integration

# Quick validation test (~5s)
./run_quick_test_standalone.sh

# Comprehensive user workflow tests (~60-120s)
./run_comprehensive_tests.sh
```

**Best for**: Quick testing, development, viewing tests live with VNC

### Option 2: Run via systemd (Background)

Run tests in background, survives terminal disconnect:

#### 1. Install the Test Service

```bash
cd /etc/nixos/tests/i3pm/integration
./test-runner install
```

#### 2. Start Tests

```bash
./test-runner start
```

**You can now disconnect your terminal safely!**

**Best for**: Long-running tests, SSH sessions, CI/CD

### 3. Monitor Progress

```bash
# Follow logs in real-time
./test-runner logs -f

# Check status
./test-runner status

# View all logs
./test-runner logs | less
```

### 4. View Results

```bash
# After tests complete:
./test-runner logs | grep -E "(PASSED|FAILED|ERROR)"
```

## Complete Command Reference

### `test-runner start`
Start integration tests in background via systemd.

```bash
./test-runner start
```

Output:
```
✅ Tests started via systemd service

Monitor progress:
  test-runner logs -f

You can now safely disconnect your terminal.
```

### `test-runner status`
Check if tests are running and view recent logs.

```bash
./test-runner status
```

### `test-runner logs [-f]`
View test logs from journalctl.

```bash
# View all logs
./test-runner logs

# Follow logs (like tail -f)
./test-runner logs -f

# Pipe to other commands
./test-runner logs | grep "test_"
./test-runner logs | less
```

### `test-runner stop`
Stop running tests and cleanup processes.

```bash
./test-runner stop
```

### `test-runner install`
Install systemd user service (automatic on first `start`).

```bash
./test-runner install
```

### `test-runner uninstall`
Remove systemd user service.

```bash
./test-runner uninstall
```

## How It Works

### Architecture

```
Your Terminal
    ↓
test-runner (CLI tool)
    ↓
systemd --user (process manager)
    ↓
nix-shell (environment)
    ↓
pytest (test runner)
    ↓
IntegrationTestFramework
    ↓
Xvfb + i3 + xterm
```

### Key Benefits

1. **Terminal Independence**: Tests run via systemd, not your shell
2. **Automatic Cleanup**: systemd handles process lifecycle
3. **Persistent Logs**: journalctl stores all output
4. **Resource Limits**: CPU and memory caps prevent runaway tests
5. **Standard Service**: Use all systemd tools (`systemctl`, `journalctl`)

## Test Isolation

### xterm as Test Terminal

The integration tests use **xterm** exclusively for testing. To ensure xterm doesn't interfere with your normal project management:

**xterm is NOT in scoped_classes or global_classes**

When the i3pm daemon marks windows, it will ignore xterm windows. This means:
- ✅ Test xterm windows won't be marked with `project:*`
- ✅ Test windows won't appear in project window counts
- ✅ Tests won't affect your normal workflow
- ✅ You can run tests while using other projects

### Excluded from Project Management

In your `~/.config/i3/app-classes.json`:
```json
{
  "scoped_classes": ["Ghostty", "Code", "neovide"],
  "global_classes": ["firefox", "pwa-youtube", "k9s"]
}
```

Notice **xterm is not listed**. This is intentional for test isolation.

## Workflow Examples

### Example 1: Run Tests and Disconnect

```bash
# SSH into machine
ssh user@server

# Start tests
cd /etc/nixos/tests/i3pm/integration
./test-runner start

# Disconnect terminal (Ctrl+D or close window)
# Tests continue running!

# Later, reconnect and check results
ssh user@server
cd /etc/nixos/tests/i3pm/integration
./test-runner status
./test-runner logs | grep -E "passed|failed"
```

### Example 2: Monitor Tests Remotely

```bash
# Terminal 1: Start tests
./test-runner start

# Terminal 2: Follow logs
./test-runner logs -f

# Disconnect both terminals
# Tests still running!

# Later: View results
./test-runner logs > test-results.txt
```

### Example 3: Run in tmux/screen (Alternative)

If you prefer tmux/screen over systemd:

```bash
# Start tmux
tmux new -s tests

# Run tests directly
./run_integration_tests.sh

# Detach: Ctrl+B, D
# Tests continue running

# Reattach later
tmux attach -t tests
```

## Troubleshooting

### Tests Won't Start

```bash
# Check if service is installed
systemctl --user list-unit-files | grep i3pm

# View service errors
systemctl --user status i3pm-integration-tests

# Reinstall service
./test-runner uninstall
./test-runner install
```

### Tests Stuck/Hanging

```bash
# Check what's running
ps aux | grep -E "Xvfb|i3.*:99|pytest"

# View live logs
./test-runner logs -f

# Force stop
./test-runner stop
```

### Clean Slate

```bash
# Complete cleanup
./test-runner stop
pkill -f "Xvfb :99"
pkill -f "i3.*DISPLAY=:99"
pkill -f "xterm.*DISPLAY=:99"
rm -rf /tmp/i3pm_integration_tests/*

# Restart
./test-runner start
```

### View Detailed Logs

```bash
# All logs with timestamps
./test-runner logs --no-pager

# Last 100 lines
./test-runner logs -n 100

# Logs from specific time
./test-runner logs --since "10 minutes ago"

# Export logs
./test-runner logs > integration-test-$(date +%Y%m%d).log
```

## Advanced Usage

### Run Specific Test

Modify the service to run a specific test:

```bash
# Edit service file
nano ~/.config/systemd/user/i3pm-integration-tests.service

# Change ExecStart line to:
ExecStart=/run/current-system/sw/bin/nix-shell ... \
    --run "pytest tests/i3pm/integration/test_quick_validation.py -v"

# Reload and restart
systemctl --user daemon-reload
./test-runner start
```

### Increase Timeout

For slow machines, increase the timeout:

```bash
# Edit service file
nano ~/.config/systemd/user/i3pm-integration-tests.service

# Change:
TimeoutStartSec=600  # 10 minutes instead of 5

# Reload
systemctl --user daemon-reload
```

### Enable Auto-Start on Login

```bash
# Enable service to start on login
systemctl --user enable i3pm-integration-tests

# Disable
systemctl --user disable i3pm-integration-tests
```

## Integration with CI/CD

The systemd approach works great for CI/CD:

```yaml
# .github/workflows/integration-tests.yml
name: Integration Tests

on: [push, pull_request]

jobs:
  integration:
    runs-on: nixos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Integration Tests
        run: |
          cd tests/i3pm/integration
          ./test-runner start

          # Wait for completion (systemd oneshot service)
          timeout 600 bash -c 'while systemctl --user is-active i3pm-integration-tests; do sleep 5; done'

          # Check results
          ./test-runner logs

          # Exit with test result
          systemctl --user show i3pm-integration-tests -p ExecMainStatus --value
```

## Test Suites

### Quick Validation Tests (`test_quick_validation.py`)
**Runtime**: ~5 seconds
**Purpose**: Fast validation of integration framework

Tests:
- Xvfb and i3 startup
- Basic IPC verification
- Environment setup/teardown

**Run**:
```bash
python -m pytest tests/i3pm/integration/test_quick_validation.py -v
```

### Real Application Tests (`test_real_apps.py`)
**Runtime**: ~30-60 seconds
**Purpose**: Test with actual application launching

Tests:
- Launching terminals (xterm, alacritty)
- Keyboard input with xdotool
- Workspace switching
- Multiple windows and cleanup
- Project/layout file creation

**Run**:
```bash
python -m pytest tests/i3pm/integration/test_real_apps.py -v -m integration
```

### User Workflow Tests (`test_user_workflows.py`) ⭐ NEW
**Runtime**: ~60-120 seconds
**Purpose**: Comprehensive end-to-end user workflows

Tests:
- ✅ Creating projects via CLI commands
- ✅ Switching between projects
- ✅ Opening applications in project context
- ✅ Saving and restoring workspace layouts
- ✅ Multi-project workflows
- ✅ Full user session simulation

**Run**:
```bash
# Run all user workflow tests
python -m pytest tests/i3pm/integration/test_user_workflows.py -v -m integration

# Run specific workflow test
python -m pytest tests/i3pm/integration/test_user_workflows.py::test_full_user_session_workflow -v -s

# Run via script
./run_comprehensive_tests.sh
```

**Test Coverage**:
1. `test_create_project_via_cli` - Project creation workflow
2. `test_project_switching_workflow` - Switching between multiple projects
3. `test_open_application_in_project_context` - App launching with project env
4. `test_save_and_restore_layout` - Layout save/restore cycle
5. `test_multiple_projects_workflow` - Managing 3+ projects
6. `test_list_and_manage_projects` - Project listing and management
7. `test_full_user_session_workflow` - Complete end-to-end user session

## Files

- `test-runner` - CLI tool for managing tests (systemd-based)
- `i3pm-integration-tests.service` - systemd unit file
- `run_simple_test.sh` - Quick validation test runner (requires systemd)
- `run_quick_test_standalone.sh` - ⭐ Standalone quick test (includes all deps)
- `run_comprehensive_tests.sh` - ⭐ Comprehensive user workflow runner (includes all deps)
- `test_quick_validation.py` - Fast validation tests (~5s)
- `test_real_apps.py` - Full integration tests (~30-60s)
- `test_user_workflows.py` - ⭐ User workflow tests (~60-120s)
- `test_tui_interactions.py` - ⭐ TUI interaction tests
- `test_daemon_integration.py` - ⭐ Daemon integration tests

## Summary

**Before**: Tests abort when terminal disconnects
**After**: Tests run reliably via systemd, survive any disconnection

**Quick Test**: `./test-runner start` (runs quick validation)
**Comprehensive Test**: `./run_comprehensive_tests.sh` via systemd
**Result**: Disconnect safely, check results anytime with `./test-runner logs`

🎯 **Perfect for**: SSH sessions, long-running tests, CI/CD pipelines

✅ **Coverage**: Framework setup, app launching, project management, full user workflows
