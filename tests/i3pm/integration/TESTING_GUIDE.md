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

### 1. Install the Test Service

```bash
cd /etc/nixos/tests/i3pm/integration
./test-runner install
```

### 2. Start Tests

```bash
./test-runner start
```

**You can now disconnect your terminal safely!**

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

## Files

- `test-runner` - CLI tool for managing tests
- `i3pm-integration-tests.service` - systemd unit file
- `run_integration_tests.sh` - Actual test execution script
- `test_quick_validation.py` - Fast validation tests (~5s)
- `test_real_apps.py` - Full integration tests (~30-60s)

## Summary

**Before**: Tests abort when terminal disconnects
**After**: Tests run reliably via systemd, survive any disconnection

**Command**: `./test-runner start`
**Result**: Disconnect safely, check results anytime with `./test-runner logs`

🎯 **Perfect for**: SSH sessions, long-running tests, CI/CD pipelines
