# Test Scenarios - i3 Project Management System

This document provides example test scenarios for the i3 project management system, demonstrating how to write automated tests, manual testing procedures, and debugging workflows.

## Automated Test Scenarios

### Scenario 1: Project Lifecycle

**Objective**: Verify complete project creation, switching, and deletion workflow

**Test File**: `home-modules/tools/i3-project-test/scenarios/project_lifecycle.py`

```python
from .base_scenario import BaseScenario
from ..models import TestResult, Assertion

class ProjectLifecycleScenario(BaseScenario):
    """Test basic project lifecycle operations."""

    scenario_id = "project_lifecycle_001"
    name = "Basic Project Lifecycle"

    async def setup(self):
        """Create test projects."""
        self.log_info("Creating test projects")

        # Create two test projects
        await self.create_project("test-proj-a", "/tmp/test-a")
        await self.create_project("test-proj-b", "/tmp/test-b")

    async def execute(self):
        """Execute test scenario."""
        self.log_info("Switching between projects")

        # Switch to project A
        await self.run_command("i3-project-switch test-proj-a")
        await self.wait(0.5)

        # Switch to project B
        await self.run_command("i3-project-switch test-proj-b")
        await self.wait(0.5)

    async def validate(self):
        """Validate project state."""
        self.log_info("Validating project state")

        # Get current project from daemon
        state = await self.get_daemon_state()

        # Assert current project is test-proj-b
        self.add_assertion(Assertion(
            name="Current project is test-proj-b",
            expected="test-proj-b",
            actual=state.get("active_project"),
            passed=state.get("active_project") == "test-proj-b"
        ))

        # Clear active project
        await self.run_command("i3-project-switch --clear")
        await self.wait(0.5)

        # Verify project cleared
        state = await self.get_daemon_state()
        self.add_assertion(Assertion(
            name="Active project cleared",
            expected=None,
            actual=state.get("active_project"),
            passed=state.get("active_project") is None
        ))

    async def cleanup(self):
        """Clean up test projects."""
        self.log_info("Cleaning up test projects")

        await self.delete_project("test-proj-a")
        await self.delete_project("test-proj-b")
```

**Expected Output**:
```json
{
  "scenario_id": "project_lifecycle_001",
  "name": "Basic Project Lifecycle",
  "status": "passed",
  "assertions": {
    "total": 2,
    "passed": 2,
    "failed": 0
  }
}
```

### Scenario 2: Window Management

**Objective**: Verify windows are correctly marked and tracked by project

**Test File**: `home-modules/tools/i3-project-test/scenarios/window_management.py`

```python
from .base_scenario import BaseScenario
from ..models import Assertion

class WindowManagementScenario(BaseScenario):
    """Test window marking and project association."""

    scenario_id = "window_management_001"
    name = "Window Marking and Tracking"

    async def setup(self):
        """Set up test project."""
        await self.create_project("test-windows", "/tmp/test")
        await self.run_command("i3-project-switch test-windows")
        await self.wait(0.5)

    async def execute(self):
        """Open windows and verify marking."""
        self.log_info("Opening test windows")

        # Open terminal (should be marked with project)
        window_id = await self.open_window("alacritty")
        await self.wait(1.0)

        self.window_ids.append(window_id)

    async def validate(self):
        """Validate window is marked correctly."""
        self.log_info("Validating window marks")

        # Query i3 for window marks
        marks = await self.get_window_marks(self.window_ids[0])

        expected_mark = "project:test-windows"
        self.add_assertion(Assertion(
            name="Window has project mark",
            expected=expected_mark,
            actual=marks,
            passed=expected_mark in marks
        ))

        # Verify daemon tracks the window
        tracked_windows = await self.get_tracked_windows()
        window_tracked = any(
            w["window_id"] == self.window_ids[0]
            for w in tracked_windows
        )

        self.add_assertion(Assertion(
            name="Daemon tracks window",
            expected=True,
            actual=window_tracked,
            passed=window_tracked
        ))

    async def cleanup(self):
        """Clean up windows and project."""
        for window_id in self.window_ids:
            await self.close_window(window_id)

        await self.run_command("i3-project-switch --clear")
        await self.delete_project("test-windows")
```

### Scenario 3: Monitor Configuration Validation

**Objective**: Verify workspace-to-output assignments match expected configuration

**Test File**: `home-modules/tools/i3-project-test/scenarios/monitor_configuration.py`

```python
from .base_scenario import BaseScenario
from ..models import Assertion
import i3ipc.aio

class MonitorConfigurationScenario(BaseScenario):
    """Test monitor/output configuration validation."""

    scenario_id = "monitor_config_001"
    name = "Workspace-to-Output Assignment Validation"

    async def execute(self):
        """Query i3 for current monitor configuration."""
        self.log_info("Querying i3 output configuration")

        async with i3ipc.aio.Connection() as i3:
            # Get current outputs
            outputs = await i3.get_outputs()
            self.outputs = [o for o in outputs if o.active]

            # Get workspace assignments
            workspaces = await i3.get_workspaces()
            self.workspace_assignments = {
                ws.num: ws.output for ws in workspaces
            }

    async def validate(self):
        """Validate workspace assignments."""
        self.log_info("Validating workspace assignments")

        # Expected assignments (example - adjust for your setup)
        expected_assignments = {
            1: "HDMI-1",
            2: "HDMI-1",
            3: "DP-1"
        }

        for ws_num, expected_output in expected_assignments.items():
            actual_output = self.workspace_assignments.get(ws_num)

            self.add_assertion(Assertion(
                name=f"Workspace {ws_num} on {expected_output}",
                expected=expected_output,
                actual=actual_output,
                passed=actual_output == expected_output
            ))

        # Verify daemon state matches i3 state
        daemon_state = await self.get_monitor_state()

        for ws_num, expected_output in self.workspace_assignments.items():
            daemon_output = daemon_state.get("workspaces", {}).get(ws_num, {}).get("output")

            self.add_assertion(Assertion(
                name=f"Daemon knows WS{ws_num} assignment",
                expected=expected_output,
                actual=daemon_output,
                passed=daemon_output == expected_output
            ))
```

### Scenario 4: Event Stream Validation

**Objective**: Verify events are captured and contain correct data

```python
from .base_scenario import BaseScenario
from ..models import Assertion

class EventStreamScenario(BaseScenario):
    """Test event stream capture and validation."""

    scenario_id = "event_stream_001"
    name = "Event Stream Capture and Validation"

    async def setup(self):
        """Start event capture."""
        await self.create_project("test-events", "/tmp/test")
        self.event_buffer = []

        # Subscribe to daemon events
        await self.subscribe_to_events(self.event_buffer)

    async def execute(self):
        """Trigger events."""
        self.log_info("Triggering test events")

        # Clear buffer
        self.event_buffer.clear()

        # Trigger project switch (generates tick event)
        await self.run_command("i3-project-switch test-events")
        await self.wait(0.5)

        # Open window (generates window::new event)
        window_id = await self.open_window("alacritty")
        await self.wait(1.0)

        self.window_ids.append(window_id)

    async def validate(self):
        """Validate captured events."""
        self.log_info(f"Captured {len(self.event_buffer)} events")

        # Should have at least: tick, window::new, window::mark
        expected_event_types = {"tick", "window::new", "window::mark"}
        actual_event_types = {e["event_type"] for e in self.event_buffer}

        for expected_type in expected_event_types:
            self.add_assertion(Assertion(
                name=f"Event {expected_type} captured",
                expected=True,
                actual=expected_type in actual_event_types,
                passed=expected_type in actual_event_types
            ))

        # Validate tick event payload
        tick_events = [e for e in self.event_buffer if e["event_type"] == "tick"]
        if tick_events:
            tick_payload = tick_events[0].get("payload", {})

            self.add_assertion(Assertion(
                name="Tick event has project name",
                expected="test-events",
                actual=tick_payload.get("project"),
                passed=tick_payload.get("project") == "test-events"
            ))

    async def cleanup(self):
        """Clean up."""
        await self.unsubscribe_from_events()

        for window_id in self.window_ids:
            await self.close_window(window_id)

        await self.run_command("i3-project-switch --clear")
        await self.delete_project("test-events")
```

## Manual Testing Procedures

### Manual Test 1: Multi-Pane Monitoring

**Objective**: Visually observe state changes in real-time

**Procedure**:

1. Open tmux and split into two panes:
   ```bash
   tmux new-session \; split-window -h
   ```

2. In left pane, run the live monitor:
   ```bash
   i3-project-monitor --mode=live
   ```

3. In right pane, execute project commands:
   ```bash
   # Create project
   i3-project-create --name manual-test --dir /tmp/manual-test

   # Switch to project
   i3-project-switch manual-test

   # Open windows
   alacritty &
   code /tmp/manual-test &

   # Observe left pane updating in real-time
   ```

4. Verify in left pane:
   - Active project shows "manual-test"
   - Window table shows both windows
   - Windows have "project:manual-test" mark

5. Clean up:
   ```bash
   i3-project-switch --clear
   i3-project-delete manual-test
   ```

### Manual Test 2: Event Stream Debugging

**Objective**: Debug event handling by watching event stream

**Procedure**:

1. Open event stream monitor:
   ```bash
   i3-project-monitor --mode=events
   ```

2. In another terminal, perform actions:
   ```bash
   # Switch projects
   i3-project-switch nixos

   # Open window
   alacritty &

   # Close window
   # (close the terminal)

   # Switch back
   i3-project-switch --clear
   ```

3. Observe event stream for:
   - `tick` events when switching projects
   - `window::new` when window opens
   - `window::mark` when window is marked
   - `window::close` when window closes

4. Verify event timestamps are reasonable (<100ms latency)

### Manual Test 3: State Validation

**Objective**: Verify daemon state matches i3 IPC state

**Procedure**:

1. Capture diagnostic report:
   ```bash
   i3-project-monitor --mode=diagnose --output=/tmp/diagnostic.json
   ```

2. Review the report:
   ```bash
   cat /tmp/diagnostic.json | jq .
   ```

3. Verify sections present:
   - `daemon_state` - current active project, uptime
   - `tracked_windows` - all windows with marks
   - `outputs` - monitor configuration from i3 GET_OUTPUTS
   - `workspaces` - workspace assignments from i3 GET_WORKSPACES
   - `event_history` - recent 500 events

4. Compare `daemon_state.active_project` to i3 window marks:
   ```bash
   i3-msg -t get_marks | jq .
   ```

5. Verify workspace assignments match:
   ```bash
   i3-msg -t get_workspaces | jq '.[] | {num, output}'
   ```

## Debugging Workflows

### Debug Workflow 1: Window Not Being Marked

**Symptoms**: Window opens but doesn't get project mark

**Debugging Steps**:

1. Check daemon status:
   ```bash
   i3-project-daemon-status
   ```

2. Check recent events:
   ```bash
   i3-project-daemon-events --limit=20 --type=window
   ```

3. Start event monitor in one pane:
   ```bash
   tmux split-window -h 'i3-project-monitor --mode=events'
   ```

4. Open window and watch for events:
   - Should see `window::new` event
   - Should see `window::mark` event within 100ms

5. If `window::mark` is missing:
   - Check window class is in scoped_classes:
     ```bash
     cat ~/.config/i3/app-classes.json | jq .scoped_classes
     ```
   - Check daemon logs:
     ```bash
     journalctl --user -u i3-project-event-listener -n 50
     ```

### Debug Workflow 2: Workspace Assignment Issues

**Symptoms**: Workspaces appear on wrong monitors

**Debugging Steps**:

1. Query i3's authoritative state:
   ```bash
   i3-msg -t get_workspaces | jq '.[] | {num, name, output}'
   ```

2. Capture diagnostic report:
   ```bash
   i3-project-monitor --mode=diagnose --output=/tmp/ws-debug.json
   ```

3. Compare daemon understanding to i3 state:
   ```bash
   # i3 state
   i3-msg -t get_workspaces | jq '.[] | {num, output}'

   # Daemon state
   cat /tmp/ws-debug.json | jq '.workspaces'
   ```

4. If discrepancy found:
   - i3 state is authoritative
   - Check if daemon subscribed to `output` events:
     ```bash
     journalctl --user -u i3-project-event-listener | grep -i "subscribed"
     ```
   - Restart daemon to resync:
     ```bash
     systemctl --user restart i3-project-event-listener
     ```

### Debug Workflow 3: Event Processing Latency

**Symptoms**: Slow response to project switches or window marking

**Debugging Steps**:

1. Monitor event stream with timestamps:
   ```bash
   i3-project-monitor --mode=events
   ```

2. Trigger action and observe timestamp gap

3. If latency > 100ms:
   - Check daemon CPU usage:
     ```bash
     top -p $(pgrep -f i3-project-event)
     ```
   - Check event buffer size:
     ```bash
     i3-project-daemon-status | grep -i events
     ```
   - Check i3 IPC socket permissions:
     ```bash
     ls -la /run/user/$(id -u)/i3/
     ```

4. Review daemon performance:
   ```bash
   journalctl --user -u i3-project-event-listener -n 100 | grep -i "processed in"
   ```

## CI/CD Integration Examples

### GitHub Actions Workflow

```yaml
name: i3 Project Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y i3 xvfb python3-pip
          pip3 install pytest pytest-asyncio i3ipc rich

      - name: Start Xvfb and i3
        run: |
          Xvfb :99 -screen 0 1920x1080x24 &
          export DISPLAY=:99
          i3 &
          sleep 2

      - name: Run test suite
        run: |
          export DISPLAY=:99
          i3-project-test suite --ci --output=test-results.json

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test-results.json
```

### GitLab CI Configuration

```yaml
test:
  image: nixos/nix:latest
  script:
    - nix-shell -p i3 xvfb-run python311Packages.pytest python311Packages.pytest-asyncio python311Packages.i3ipc python311Packages.rich --run "
        xvfb-run -a i3 &
        sleep 2 &&
        i3-project-test suite --ci --output=test-results.json
      "
  artifacts:
    reports:
      junit: test-results.json
    when: always
```

## Best Practices

1. **Use tmux for manual testing**: Split panes enable simultaneous monitoring and command execution

2. **Check i3 IPC first**: When debugging state issues, always query i3's authoritative state first

3. **Use diagnostic capture**: Save diagnostic reports before making changes for comparison

4. **Test event subscriptions**: Verify daemon is subscribed to necessary i3 events (window, workspace, output)

5. **Validate with automated tests**: After manual debugging, write automated test to prevent regression

6. **Monitor event latency**: Event processing should complete in <100ms - higher latency indicates issues

7. **Keep event buffer small**: 500 events is sufficient for debugging without memory issues

8. **Use structured logging**: Enable verbose mode (`--verbose`) to see detailed processing logs

## See Also

- [Python Development Standards](./PYTHON_DEVELOPMENT.md) - Testing patterns and pytest examples
- [i3 IPC Patterns](./I3_IPC_PATTERNS.md) - State validation and event subscription patterns
- [Feature 018 Quickstart](../specs/018-create-a-new/quickstart.md) - Testing framework usage guide
