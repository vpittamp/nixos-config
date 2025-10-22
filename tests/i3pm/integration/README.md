# Integration Testing Guide

This directory contains real integration tests that launch actual applications with Xvfb and i3.

## Quick Start

### 1. Run Quick Validation (Recommended First)

Test that the integration framework works without launching apps (~5 seconds):

```bash
cd /etc/nixos/tests/i3pm/integration

# Direct run (synchronous, see output immediately)
nix-shell -p python3Packages.pytest python3Packages.pytest-asyncio \
          python3Packages.psutil xorg.xorgserver i3 xdotool xterm \
          --run "python -m pytest test_quick_validation.py -v -s"
```

### 2. Run Full Integration Tests

Test with real application launching (~30-60 seconds):

```bash
# Option A: Direct run (see output, but terminal must stay connected)
./run_integration_tests.sh

# Option B: Background run (survives terminal disconnect)
./run_background.sh

# Monitor background run
tail -f /tmp/i3pm_integration_tests/background_*.log
```

## Test Levels

### Quick Validation (`test_quick_validation.py`)
- **Duration**: ~5 seconds
- **What it tests**: Xvfb startup, i3 startup, cleanup
- **No apps launched**: Just validates framework
- **Use when**: First time setup, quick verification

### Real Apps (`test_real_apps.py`)
- **Duration**: ~30-60 seconds
- **What it tests**: Launching xterm, keyboard input, window management
- **Real apps**: xterm, possibly alacritty
- **Use when**: Full integration validation

## Troubleshooting

### Tests won't start

```bash
# Check if processes are stuck
ps aux | grep -E "Xvfb|i3.*:99"

# Force cleanup
pkill -f "Xvfb :99"
pkill -f "i3.*DISPLAY=:99"
rm -f /tmp/i3pm_integration_tests/*.pid
```

### Terminal disconnects

Use background runner:
```bash
./run_background.sh
# Disconnect terminal safely
# Reconnect and check:
tail -f /tmp/i3pm_integration_tests/background_*.log
```

### Tests timeout

Increase timeout in test:
```python
@pytest.mark.timeout(120)  # 2 minutes
```

### Display :99 already in use

Change display number:
```bash
# Edit scripts to use :100 instead
# Or kill existing Xvfb:
pkill -f "Xvfb :99"
```

## Architecture

```
IntegrationTestFramework
├── Xvfb (:99)           # Virtual X server
├── i3                    # Window manager
├── xdotool               # Keyboard simulation
└── Applications          # xterm, alacritty, etc.
```

### Test Flow

1. **Setup**:
   - Start Xvfb on :99
   - Start i3 with test config
   - Create temp config directories
   - Verify i3 responds

2. **Test**:
   - Launch applications
   - Send keyboard input
   - Verify window states
   - Check i3 tree

3. **Cleanup**:
   - Close all windows
   - Kill i3
   - Kill Xvfb
   - Remove temp directories

## Examples

### Launch Terminal and Type

```python
async with IntegrationTestFramework(display=":99") as framework:
    # Launch terminal
    await framework.launch_application("xterm", wait_for_window=True)

    # Send keyboard input
    await framework.type_text("echo 'hello'")
    await framework.send_keys("Return")

    # Verify window count
    count = await framework._get_window_count()
    assert count == 1
```

### Create Project Config

```python
async with IntegrationTestFramework(display=":99") as framework:
    config_dir = framework.env.config_dir

    # Create project
    project_data = {"name": "test", "directory": "/tmp/test"}
    project_file = config_dir / "projects" / "test.json"

    with open(project_file, "w") as f:
        json.dump(project_data, f)

    assert project_file.exists()
```

## Logs

All test runs are logged to:
```
/tmp/i3pm_integration_tests/
├── test_run_TIMESTAMP.log     # Direct runs
├── background_TIMESTAMP.log   # Background runs
└── *.pid                      # Process tracking
```

View recent runs:
```bash
ls -lth /tmp/i3pm_integration_tests/*.log | head -5
```

## Markers

Tests use pytest markers:

- `@pytest.mark.integration` - All integration tests
- `@pytest.mark.slow` - Tests that take >5 seconds

Run only quick tests:
```bash
pytest -m "integration and not slow"
```

Run all integration tests:
```bash
pytest -m integration
```
