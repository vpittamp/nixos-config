# Quick Start: i3 Project System Testing & Debugging Framework

**Feature**: 018-create-a-new
**Date**: 2025-10-20
**Prerequisites**: Feature 015 (daemon), Feature 017 (monitor tool), i3wm, tmux

## Overview

This guide provides quick start instructions for using the i3 project testing and debugging framework. The framework extends the i3-project-monitor tool with automated testing capabilities, diagnostic modes, and monitor/workspace validation.

## Installation

The testing framework will be installed via home-manager module:

```bash
# After implementation, rebuild home-manager configuration
home-manager switch --flake .#hetzner

# Verify installation
i3-project-test --version
i3-project-monitor diagnose --help
```

## Basic Usage

### 1. Manual Interactive Testing (P1 - MVP)

Use tmux split-pane monitoring to observe system state changes in real-time.

```bash
# Open tmux session
tmux new-session -s test-session

# Split horizontally (creates two panes)
Ctrl+B "

# In right pane: Start live monitor
i3-project-monitor live

# In left pane: Execute commands and observe state changes
i3-project-switch nixos
i3-project-switch stacks

# Monitor pane updates in real-time:
# - Active project changes
# - Window list filtered by project
# - Monitor/workspace assignments
# - Event stream
```

**What to observe**:
- Active project indicator updates within 1 second
- Window table shows only project-scoped windows
- Monitor panel displays GET_OUTPUTS data
- Workspace assignments show GET_WORKSPACES data

### 2. Automated State Validation

Run automated tests that simulate workflows and validate correctness.

```bash
# Run single test scenario
i3-project-test run project_lifecycle_001

# Run all tests in category
i3-project-test run --category project_management

# Run full test suite
i3-project-test run --all

# Run with verbose output
i3-project-test run --all --verbose

# Run headless for CI/CD
i3-project-test run --all --no-ui --format=json > results.json
```

**Example output**:
```
i3 Project Test Runner v1.0.0
================================

Running test scenarios...

✓ project_lifecycle_001: Basic Project Switch (5.2s)
✓ project_lifecycle_002: Create and Delete Project (3.8s)
✓ window_management_001: Window Marking Validation (4.1s)
✓ monitor_config_001: Workspace Assignment Validation (2.5s)
✗ event_stream_001: Event Order Validation (6.3s)
  Expected event sequence: [window::new, window::mark, window::focus]
  Actual sequence: [window::new, window::focus, window::mark]

================================
Results: 4 passed, 1 failed, 0 skipped
Total time: 21.9s
```

### 3. Diagnostic Capture

Capture comprehensive system state snapshot for debugging.

```bash
# Capture diagnostic snapshot to file
i3-project-monitor diagnose --output=diagnostic.json

# Capture with specific components
i3-project-monitor diagnose \
  --include-events=500 \
  --include-tree \
  --include-monitors \
  --output=diagnostic-detailed.json

# View diagnostic summary
i3-project-monitor diagnose --summary

# Compare two diagnostic snapshots
i3-project-monitor diagnose \
  --compare diagnostic-before.json diagnostic-after.json
```

**Diagnostic snapshot includes**:
- Daemon status and statistics
- All projects and window assignments
- Last 500 events from event buffer
- Complete i3 tree structure with marks
- Output configuration (GET_OUTPUTS)
- Workspace assignments (GET_WORKSPACES)
- Environment metadata

### 4. Monitor/Workspace Validation

Validate monitor configuration and workspace assignments.

```bash
# Run monitor configuration tests
i3-project-test run --category monitor_configuration

# Test with simulated display changes
i3-project-test run monitor_disconnect_001

# Validate current workspace assignments
i3-project-monitor validate-workspaces
```

**What's validated**:
- All workspaces assigned to active outputs
- Visible workspaces on correct outputs
- Output configuration matches expected state
- Daemon state matches i3 IPC state

## Common Test Scenarios

### Scenario 1: Validate Project Switch

```bash
# Test basic project switching
i3-project-test run project_switch_basic

# What it tests:
# 1. Create two test projects
# 2. Switch between them
# 3. Validate active project changes
# 4. Validate events recorded correctly
# 5. Cleanup test projects
```

### Scenario 2: Validate Window Marking

```bash
# Test window marking and visibility
i3-project-test run window_marking_validation

# What it tests:
# 1. Create test project
# 2. Open windows in project context
# 3. Validate windows have correct project mark
# 4. Switch away and verify windows hidden
# 5. Switch back and verify windows visible
```

### Scenario 3: Validate Multi-Monitor Setup

```bash
# Test workspace-to-output assignments
i3-project-test run workspace_assignment_validation

# What it tests:
# 1. Query current outputs via GET_OUTPUTS
# 2. Query workspace assignments via GET_WORKSPACES
# 3. Validate all visible workspaces on active outputs
# 4. Validate monitor tool displays match i3 state
```

### Scenario 4: Validate Event Stream

```bash
# Test event recording and ordering
i3-project-test run event_stream_validation

# What it tests:
# 1. Subscribe to event stream
# 2. Perform actions (open window, switch project)
# 3. Validate expected events recorded
# 4. Validate event ordering correct
# 5. Validate event payloads accurate
```

## Tmux Testing Workflow

For manual testing with visual monitoring:

```bash
# Create test session layout
tmux new-session -s i3-test \; \
  split-window -h \; \
  split-window -v

# Pane 0 (top-left): Commands
# Pane 1 (top-right): Live monitor
# Pane 2 (bottom-right): Event stream

# In pane 0: Run test commands
tmux select-pane -t 0
# Execute: i3-project-switch nixos

# In pane 1: Monitor live state
tmux select-pane -t 1
i3-project-monitor live

# In pane 2: Monitor events
tmux select-pane -t 2
i3-project-monitor events
```

## Troubleshooting

### Daemon Not Running

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Check daemon connection
i3-project-daemon-status

# Restart daemon
systemctl --user restart i3-project-event-listener

# View daemon logs
journalctl --user -u i3-project-event-listener -f
```

### Test Failures

```bash
# Run single test with verbose output
i3-project-test run test_name --verbose --show-logs

# Capture diagnostic on failure
i3-project-test run test_name --capture-on-failure

# View test logs
less ~/.local/share/i3-project-test/logs/test_name.log
```

### Monitor Tool Issues

```bash
# Test monitor connection
i3-project-monitor --test-connection

# Check socket exists
ls -la $XDG_RUNTIME_DIR/i3-project-daemon/

# View monitor tool logs
i3-project-monitor live --debug
```

### Workspace Assignment Issues

```bash
# Validate current assignments
i3-project-monitor validate-workspaces

# Capture diagnostic with full tree
i3-project-monitor diagnose --include-tree --output=debug.json

# Compare against expected state
i3-project-monitor diagnose --compare expected.json debug.json
```

## CI/CD Integration

For automated testing in CI pipelines:

```bash
# Run tests headless with JSON output
i3-project-test run --all \
  --no-ui \
  --format=json \
  --output=test-results.json \
  --capture-on-failure \
  --diagnostics-dir=./diagnostics/

# Check exit code
echo $?  # 0 = all passed, non-zero = failures or errors

# Parse JSON results
jq '.summary' test-results.json
```

**GitHub Actions Example**:
```yaml
- name: Run i3 Project Tests
  run: |
    i3-project-test run --all --no-ui --format=json --output=results.json

- name: Upload Test Results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: |
      results.json
      diagnostics/

- name: Check Test Results
  run: |
    jq -e '.summary.passed == .summary.total' results.json
```

## Advanced Usage

### Custom Test Scenarios

Create custom test scenarios in Python:

```python
# ~/.config/i3-project-test/custom_scenarios/my_test.py
from i3_project_test.scenarios import BaseScenario
from i3_project_test.assertions import *

class MyCustomTest(BaseScenario):
    scenario_id = "custom_001"
    name = "My Custom Test"
    description = "Test custom workflow"

    async def run(self):
        # Setup
        await self.create_project("test-custom")

        # Test actions
        await self.switch_project("test-custom")
        await self.open_window("ghostty")

        # Assertions
        await self.assert_active_project("test-custom")
        await self.assert_window_count(1)

        # Cleanup
        await self.delete_project("test-custom")
```

Run custom scenario:
```bash
i3-project-test run --scenario-file ~/.config/i3-project-test/custom_scenarios/my_test.py
```

### Diagnostic Comparison

Compare system state before and after changes:

```bash
# Capture before state
i3-project-monitor diagnose --output=before.json

# Make changes (switch projects, open windows, etc.)
i3-project-switch nixos

# Capture after state
i3-project-monitor diagnose --output=after.json

# Compare and show differences
i3-project-monitor diagnose --compare before.json after.json

# Output shows:
# - Daemon state changes
# - Window additions/removals
# - Event history
# - Workspace assignment changes
```

### Monitor Configuration Testing

Test display configuration changes:

```bash
# Capture baseline state
xrandr  # Note current configuration
i3-project-monitor diagnose --output=baseline.json

# Disable output (simulated disconnect)
xrandr --output HDMI-2 --off

# Validate i3 detected change
i3-project-test run monitor_disconnect_validation

# Re-enable output
xrandr --output HDMI-2 --auto

# Validate workspaces reassigned
i3-project-test run monitor_reconnect_validation
```

## Configuration

Test framework configuration:

```bash
# ~/.config/i3-project-test/config.json
{
  "test_timeout_seconds": 30,
  "cleanup_on_failure": true,
  "capture_diagnostics_on_failure": true,
  "diagnostics_dir": "~/.local/share/i3-project-test/diagnostics",
  "log_level": "INFO",
  "tmux_session_prefix": "i3-project-test-",
  "test_project_prefix": "test-"
}
```

## Best Practices

1. **Always use test-* prefix** for test projects to avoid interfering with real projects
2. **Run diagnostic capture before making changes** to have baseline for comparison
3. **Use tmux isolation** for manual testing to prevent interference with active i3 session
4. **Check daemon status first** before running tests - most failures are daemon connectivity issues
5. **Review event stream** when debugging state issues - events show exact sequence of operations
6. **Compare diagnostic snapshots** when investigating regressions
7. **Run tests locally** before pushing to CI - CI environments have limited debugging capabilities

## Quick Reference

### Common Commands

```bash
# Test framework
i3-project-test run --all                    # Run all tests
i3-project-test run test_name                # Run specific test
i3-project-test list                         # List available tests
i3-project-test run --help                   # Show all options

# Monitor tool (enhanced)
i3-project-monitor live                      # Live dashboard
i3-project-monitor events                    # Event stream
i3-project-monitor history --limit=50        # Event history
i3-project-monitor diagnose                  # Diagnostic capture
i3-project-monitor validate-workspaces       # Validate workspace assignments
i3-project-monitor tree --marks project:     # Show project-marked windows

# Daemon
i3-project-daemon-status                     # Daemon status
i3-project-daemon-events --limit=20          # Recent events
systemctl --user status i3-project-event-listener  # Systemd status
```

### Key Files and Paths

- Test framework: `~/.local/share/i3-project-test/`
- Test logs: `~/.local/share/i3-project-test/logs/`
- Diagnostics: `~/.local/share/i3-project-test/diagnostics/`
- Configuration: `~/.config/i3-project-test/config.json`
- Custom scenarios: `~/.config/i3-project-test/custom_scenarios/`
- Daemon socket: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

## Next Steps

1. **Explore test scenarios**: Run `i3-project-test list` to see available tests
2. **Try manual testing**: Set up tmux layout and observe live monitoring
3. **Run full test suite**: `i3-project-test run --all` to validate installation
4. **Capture diagnostics**: Create baseline diagnostic snapshot for your setup
5. **Read contracts**: Review `/specs/018-create-a-new/contracts/jsonrpc-api.md` for API details

## Support

For issues and questions:
- Check daemon logs: `journalctl --user -u i3-project-event-listener -n 100`
- Review test logs: `~/.local/share/i3-project-test/logs/`
- Capture diagnostic: `i3-project-monitor diagnose --output=support.json`
- See Feature 015 docs: `/specs/015-create-a-new/quickstart.md`
- See Feature 017 docs: `/specs/017-now-lets-create/quickstart.md`
