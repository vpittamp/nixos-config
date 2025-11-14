# Test Scenarios Contract

**Feature**: 075-layout-restore-production

## Overview

This contract defines comprehensive test scenarios for production-ready layout restoration, organized by test level (unit, integration, E2E) and user story from spec.md.

## Test Pyramid Structure

```
           ┌───────────────┐
           │  E2E Tests    │  10% - Full restore workflow in VM
           │   (~3 tests)  │
           ├───────────────┤
           │ Integration   │  20% - Daemon + wrapper + Sway
           │  (~6 tests)   │
           ├───────────────┤
           │  Unit Tests   │  70% - Individual components
           │  (~20 tests)  │
           └───────────────┘
```

---

## Unit Tests (70%)

### Category: Mark Generation

**UT-001: Valid mark format**
```python
def test_mark_format():
    """Verify mark matches regex pattern."""
    mark = generate_restoration_mark()
    assert re.match(r'^i3pm-restore-[0-9a-f]{8}$', mark)
    assert len(mark) == 21
```

**UT-002: Mark uniqueness**
```python
def test_mark_uniqueness():
    """Verify no duplicate marks in batch."""
    marks = [generate_restoration_mark() for _ in range(100)]
    assert len(marks) == len(set(marks))
```

**UT-003: Mark generation performance**
```python
def test_mark_generation_performance():
    """Verify mark generation is fast (<1ms per mark)."""
    import time
    start = time.time()
    marks = [generate_restoration_mark() for _ in range(1000)]
    elapsed = time.time() - start
    assert elapsed < 1.0  # 1000 marks in <1s = <1ms per mark
```

---

### Category: Wrapper Script Logic

**UT-004: ENV_EXPORTS includes restoration mark**
```bash
#!/usr/bin/env bats

@test "wrapper adds I3PM_RESTORE_MARK to ENV_EXPORTS when set" {
    export I3PM_RESTORE_MARK="i3pm-restore-test123"
    source app-launcher-wrapper.sh
    [[ "${ENV_EXPORTS[@]}" =~ "I3PM_RESTORE_MARK" ]]
}

@test "wrapper skips I3PM_RESTORE_MARK when not set" {
    unset I3PM_RESTORE_MARK
    source app-launcher-wrapper.sh
    ! [[ "${ENV_EXPORTS[@]}" =~ "I3PM_RESTORE_MARK" ]]
}
```

**UT-005: ENV_STRING construction**
```python
def test_env_string_contains_mark():
    """Verify ENV_STRING includes restoration mark."""
    env = {"I3PM_RESTORE_MARK": "i3pm-restore-abc123"}
    result = subprocess.run(
        ["bash", "app-launcher-wrapper.sh", "alacritty"],
        env=env,
        capture_output=True,
        text=True,
    )
    # Check wrapper log shows ENV_STRING with mark
    assert "I3PM_RESTORE_MARK" in result.stderr
```

---

### Category: Environment Variable Reading

**UT-006: Read mark from /proc/environ**
```python
def test_read_environ_with_mark():
    """Verify daemon can read I3PM_RESTORE_MARK from process environ."""
    env = os.environ.copy()
    env["I3PM_RESTORE_MARK"] = "i3pm-restore-unit789"
    proc = subprocess.Popen(["sleep", "5"], env=env)

    env_dict = read_process_environ(proc.pid)
    assert "I3PM_RESTORE_MARK" in env_dict
    assert env_dict["I3PM_RESTORE_MARK"] == "i3pm-restore-unit789"

    proc.terminate()
```

**UT-007: Handle missing environ file**
```python
def test_read_environ_missing_pid():
    """Verify graceful handling of invalid PID."""
    env_dict = read_process_environ(999999)  # Invalid PID
    assert env_dict == {}
    # Should not raise exception
```

---

### Category: Correlation Logic

**UT-008: Match window by mark**
```python
def test_correlation_match_by_mark():
    """Verify correlation finds placeholder by mark."""
    correlation = CorrelationState()
    placeholder = WindowPlaceholder(app_name="alacritty", workspace=1)
    mark = "i3pm-restore-test456"
    correlation.pending_marks[mark] = placeholder

    correlation.window_marked(window_id=123, restore_mark=mark)

    assert mark not in correlation.pending_marks
    assert 123 in correlation.matched_windows
    assert correlation.matched_windows[123] == mark
```

**UT-009: Unknown mark handling**
```python
def test_correlation_unknown_mark():
    """Verify warning for unknown marks."""
    correlation = CorrelationState()

    with pytest.warns(UserWarning, match="Unknown restoration mark"):
        correlation.window_marked(window_id=123, restore_mark="unknown-mark")

    assert 123 not in correlation.matched_windows
```

---

## Integration Tests (20%)

### Category: Wrapper + Process Environment

**IT-001: End-to-end environment propagation**
```python
@pytest.mark.asyncio
async def test_wrapper_propagates_mark_to_process():
    """Verify mark passes from wrapper to launched process environment."""
    # Launch app via wrapper with mark
    env = os.environ.copy()
    env["I3PM_RESTORE_MARK"] = "i3pm-restore-int001"

    proc = await asyncio.create_subprocess_exec(
        "app-launcher-wrapper.sh",
        "alacritty",
        env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    # Wait for app to start
    await asyncio.sleep(2)

    # Find launched alacritty PID (via swaymsg)
    result = await asyncio.create_subprocess_exec(
        "swaymsg", "-t", "get_tree",
        stdout=asyncio.subprocess.PIPE,
    )
    tree_json = await result.stdout.read()
    tree = json.loads(tree_json)

    alacritty_windows = find_windows_by_app_id(tree, "Alacritty")
    assert len(alacritty_windows) > 0

    window_pid = alacritty_windows[0]["pid"]

    # Read mark from process environ
    env_dict = read_process_environ(window_pid)
    assert env_dict["I3PM_RESTORE_MARK"] == "i3pm-restore-int001"

    # Cleanup
    await asyncio.create_subprocess_exec("swaymsg", f"[pid={window_pid}]", "kill")
```

---

### Category: Daemon + Sway IPC

**IT-002: Daemon applies mark to window**
```python
@pytest.mark.asyncio
async def test_daemon_applies_mark_on_window_new():
    """Verify daemon reads environ and applies Sway mark on window::new."""
    # Launch app with mark via wrapper
    env = os.environ.copy()
    env["I3PM_RESTORE_MARK"] = "i3pm-restore-int002"

    proc = await asyncio.create_subprocess_exec(
        "app-launcher-wrapper.sh",
        "alacritty",
        env=env,
    )

    # Wait for daemon to process window::new event
    await asyncio.sleep(3)

    # Query Sway for mark
    result = await asyncio.create_subprocess_exec(
        "swaymsg", "-t", "get_marks",
        stdout=asyncio.subprocess.PIPE,
    )
    marks_json = await result.stdout.read()
    marks = json.loads(marks_json)

    assert "i3pm-restore-int002" in marks

    # Cleanup
    await asyncio.create_subprocess_exec("swaymsg", "[app_id=Alacritty]", "kill")
```

**IT-003: Correlation matches window by mark**
```python
@pytest.mark.asyncio
async def test_correlation_matches_window():
    """Verify correlation service matches window to placeholder."""
    # Setup: Create correlation state with pending mark
    correlation = CorrelationState()
    placeholder = WindowPlaceholder(app_name="alacritty", workspace=1)
    mark = "i3pm-restore-int003"
    correlation.pending_marks[mark] = placeholder

    # Launch app with mark
    env = os.environ.copy()
    env["I3PM_RESTORE_MARK"] = mark

    await asyncio.create_subprocess_exec(
        "app-launcher-wrapper.sh",
        "alacritty",
        env=env,
    )

    # Wait for daemon to process and notify correlation
    await asyncio.sleep(3)

    # Verify mark was matched (removed from pending)
    assert mark not in correlation.pending_marks
    assert len(correlation.matched_windows) == 1
```

---

### Category: Home-Manager Deployment

**IT-004: Wrapper script updates after source change**
```python
def test_wrapper_deployment_after_source_change():
    """Verify home-manager rebuilds wrapper when source changes."""
    wrapper_source = "/etc/nixos/scripts/app-launcher-wrapper.sh"
    wrapper_installed = os.path.expanduser("~/.local/bin/app-launcher-wrapper.sh")

    # Get current wrapper store path
    before_link = os.readlink(wrapper_installed)

    # Modify source file (add version comment)
    with open(wrapper_source, "r") as f:
        content = f.read()

    new_content = content.replace(
        "# Version:",
        f"# Version: test-{int(time.time())}"
    )

    with open(wrapper_source, "w") as f:
        f.write(new_content)

    # Rebuild
    subprocess.run(["nixos-rebuild", "switch"], check=True)

    # Verify symlink changed
    after_link = os.readlink(wrapper_installed)
    assert after_link != before_link

    # Verify new wrapper has updated content
    with open(wrapper_installed, "r") as f:
        installed_content = f.read()
    assert f"test-{int(time.time())}" in installed_content
```

---

## E2E Tests (10%) - NixOS Integration Driver

### Category: Full Restore Workflow

**E2E-001: Single window restore (User Story 1)**
```python
# tests/sway-integration/test-cases/layout-restore/single-window-restore.json
{
  "name": "Single Window Restore",
  "description": "Save layout with 1 terminal, close it, restore, verify match",
  "actions": [
    {"type": "launch_app_sync", "params": {"app_name": "alacritty"}},
    {"type": "wait_sync", "params": {"seconds": 2}},
    {"type": "ipc_command_sync", "params": {"command": "i3pm layout save single-test"}},
    {"type": "ipc_command_sync", "params": {"command": "[workspace=1] kill"}},
    {"type": "wait_sync", "params": {"seconds": 1}},
    {"type": "ipc_command_sync", "params": {"command": "i3pm layout restore nixos single-test"}},
    {"type": "wait_sync", "params": {"seconds": 10}}
  ],
  "expectedState": {
    "windowCount": 1,
    "workspaces": [
      {
        "num": 1,
        "windows": [
          {"app_id": "Alacritty"}
        ]
      }
    ]
  }
}
```

**E2E-002: Multi-window restore (User Story 1)**
```python
# tests/sway-integration/test-cases/layout-restore/multi-window-restore.json
{
  "name": "Multi-Window Restore (3 windows)",
  "description": "Save layout with terminal, firefox, vscode. Restore and verify all matched.",
  "actions": [
    {"type": "launch_app_sync", "params": {"app_name": "alacritty"}},
    {"type": "launch_app_sync", "params": {"app_name": "firefox"}},
    {"type": "launch_app_sync", "params": {"app_name": "vscode"}},
    {"type": "wait_sync", "params": {"seconds": 5}},
    {"type": "ipc_command_sync", "params": {"command": "i3pm layout save multi-test"}},
    {"type": "ipc_command_sync", "params": {"command": "[workspace=1] kill"}},
    {"type": "wait_sync", "params": {"seconds": 2}},
    {"type": "ipc_command_sync", "params": {"command": "i3pm layout restore nixos multi-test"}},
    {"type": "wait_sync", "params": {"seconds": 15}}
  ],
  "expectedState": {
    "windowCount": 3,
    "focusedWorkspace": 1
  }
}
```

**E2E-003: Concurrent window launch (edge case)**
```python
# Test that simultaneous launches don't cause mark collisions
def test_concurrent_launch_restore(machine):
    """Verify correlation handles concurrent window launches correctly."""
    # Save layout with 5 windows
    machine.succeed("su - testuser -c 'i3pm layout save concurrent-test'")

    # Close all windows
    machine.succeed("su - testuser -c 'swaymsg [workspace=1] kill'")

    # Restore (launches all 5 apps nearly simultaneously)
    machine.succeed("su - testuser -c 'i3pm layout restore nixos concurrent-test'")

    # Wait for correlation (should be <10s for 5 windows)
    machine.sleep(10)

    # Verify all windows matched
    output = machine.succeed("su - testuser -c 'swaymsg -t get_tree | jq \".. | select(.app_id? != null) | .app_id\"'")
    window_count = len([line for line in output.split("\n") if line.strip()])
    assert window_count == 5, f"Expected 5 windows, got {window_count}"

    # Check daemon logs for match confirmation
    logs = machine.succeed("journalctl --user -M testuser@ -u i3-project-event-listener -n 50")
    match_count = logs.count("window matched")
    assert match_count >= 5
```

---

## Test Execution Matrix

| Test ID | Level | Framework | Environment | Duration |
|---------|-------|-----------|-------------|----------|
| UT-001 to UT-009 | Unit | pytest | Local Python | <1s total |
| IT-001 to IT-004 | Integration | pytest + Sway | Live Sway session | ~30s total |
| E2E-001 to E2E-003 | E2E | NixOS Test Driver | QEMU VM | ~60s per test |

---

## Success Criteria Validation

Map tests to Feature 075 success criteria:

| Success Criteria | Test Coverage |
|------------------|---------------|
| **SC-001**: ≥95% match rate | E2E-001, E2E-002, E2E-003 |
| **SC-002**: <10s restoration time | E2E-002 (measure elapsed time) |
| **SC-003**: 100% test pass rate | All tests must pass |
| **SC-004**: Wrapper deploys on first rebuild | IT-004 |
| **SC-005**: 100% mark in process env | IT-001, UT-006 |
| **SC-006**: Diagnostic logs sufficient | IT-002, E2E-003 (check logs) |
| **SC-007**: Test execution <30s | Measured in CI |

---

## Test Environment Requirements

### Local Development
- Python 3.11+, pytest, pytest-asyncio
- Sway compositor running
- i3pm daemon active
- app-launcher-wrapper.sh in PATH

### CI/CD (NixOS Integration Driver)
- QEMU VM with hetzner-sway configuration
- Headless Sway (pixman rendering)
- 3 virtual displays (HEADLESS-1,2,3)
- Auto-login test user
- Full i3pm stack installed

---

## Test Execution Commands

```bash
# Unit tests
pytest tests/unit/ -v

# Integration tests (requires live Sway)
pytest tests/integration/ -v --asyncio-mode=auto

# E2E tests (NixOS VMs)
cd tests/sway-integration
nix-build -A layoutRestore

# All tests in CI
nix-build tests/sway-integration -A all
```
