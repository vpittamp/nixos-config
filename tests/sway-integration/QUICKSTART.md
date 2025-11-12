# Sway Integration Tests - Quick Start Guide

Get started with NixOS VM-based integration testing for Sway in 5 minutes.

## TL;DR

```bash
cd /home/user/nixos-config/tests/sway-integration

# Run a simple test
./run-tests.sh basic

# Run all tests
./run-tests.sh all

# Debug interactively
./run-tests.sh interactive
```

## What Are These Tests?

These tests run your entire Sway window manager setup (compositor, i3pm daemon, sway-tree-monitor, apps) in an isolated QEMU virtual machine. Each test starts with a fresh VM, runs test actions, and verifies the result.

**Key Benefits:**
- ✅ **Reproducible**: Same environment every time
- ✅ **Isolated**: No risk to your running system
- ✅ **Complete**: Tests full stack (Sway + daemons + apps)
- ✅ **Automated**: Perfect for CI/CD pipelines

## 5-Minute Tutorial

### Step 1: Run Your First Test

```bash
cd /home/user/nixos-config/tests/sway-integration
./run-tests.sh basic
```

This test verifies:
- ✓ VM boots with NixOS
- ✓ Sway compositor starts in headless mode
- ✓ 3 virtual displays are created
- ✓ Basic workspace switching works

**Expected output:**
```
Building test: basic
✓ basic PASSED
```

### Step 2: Test Window Management

```bash
./run-tests.sh windowLaunch
```

This launches Alacritty terminal and verifies the window appears in the Sway tree.

### Step 3: Run All Tests

```bash
./run-tests.sh all
```

Runs the complete test suite:
1. Basic functionality
2. Window launch
3. Workspace navigation
4. i3pm daemon integration
5. Multi-monitor setup
6. Sway-test framework integration

**Takes ~2-3 minutes** (includes VM boot time)

### Step 4: Interactive Debugging

When a test fails or you want to explore the VM:

```bash
./run-tests.sh interactive
```

This gives you a Python REPL where you can:

```python
# Launch interactive shell in the VM
>>> machine.shell_interact()

# Execute commands as the test user
>>> machine.succeed("su - testuser -c 'swaymsg -t get_tree'")

# Take a screenshot
>>> machine.screenshot("my-debug-screenshot")

# Check daemon status
>>> machine.succeed("systemctl --user -M testuser@ status i3-project-event-listener")
```

Screenshots are saved to `./result/*.png`

## Common Use Cases

### Debugging a Failed Test

```bash
# Run the test that's failing
./run-tests.sh workspaceNavigation

# If it fails, run interactively
./run-tests.sh interactive

# In the REPL, reproduce the failure
>>> machine.succeed("su - testuser -c 'swaymsg workspace number 1'")
>>> machine.screenshot("before")
>>> machine.succeed("su - testuser -c 'alacritty &'")
>>> machine.sleep(2)
>>> machine.screenshot("after")

# Inspect Sway state
>>> output = machine.succeed("su - testuser -c 'swaymsg -t get_tree | jq'")
>>> print(output)
```

### Testing Your Own JSON Test Cases

Create a test file:

```json
// my-test.json
{
  "name": "My Custom Test",
  "actions": [
    {
      "type": "launch_app_sync",
      "params": {"app_name": "alacritty"}
    }
  ],
  "expectedState": {
    "windowCount": 1
  }
}
```

Run it in the VM:

```bash
./run-tests.sh interactive

# In REPL:
>>> machine.copy_from_host("${./my-test.json}", "/tmp/my-test.json")
>>> machine.succeed("su - testuser -c 'sway-test run /tmp/my-test.json'")
```

### Testing Feature Development

When developing a new feature (e.g., workspace mode enhancements):

1. **Write test first** (TDD):
   - Add test to `default.nix`
   - Define expected behavior

2. **Implement feature** in your main config

3. **Run test** to verify:
   ```bash
   ./run-tests.sh myFeature
   ```

4. **Iterate** until test passes

5. **Commit** both feature and test

### CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/test.yml
- name: Run Sway Integration Tests
  run: |
    cd tests/sway-integration
    ./run-tests.sh all
```

## Test Execution Flow

```
┌─────────────────────────────────────────┐
│ 1. Build NixOS VM Image                 │
│    (hetzner-sway config + test user)    │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 2. Start QEMU VM                         │
│    (headless Wayland, 3 displays)       │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 3. Wait for Services                     │
│    - Sway compositor                     │
│    - i3pm daemon                         │
│    - sway-tree-monitor                   │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 4. Execute Test Script                   │
│    - Launch apps                         │
│    - Switch workspaces                   │
│    - Verify state                        │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 5. Collect Results                       │
│    - Screenshots                         │
│    - Logs                                │
│    - Pass/Fail status                    │
└─────────────────────────────────────────┘
```

## Performance Tips

### Fast Iteration

For rapid development, use the regular sway-test framework on your live system:

```bash
# Fast (no VM overhead)
sway-test run my-test.json
```

Use NixOS integration tests for:
- Final verification before commit
- CI/CD pipelines
- Regression testing
- Multi-configuration testing

### Parallel Testing

Run multiple tests in parallel (if you have CPU cores to spare):

```bash
nix-build -A basic &
nix-build -A windowLaunch &
nix-build -A workspaceNavigation &
wait
```

### Caching

Nix automatically caches VM builds. Subsequent test runs are much faster:
- **First run**: ~60 seconds (build VM)
- **Subsequent runs**: ~20 seconds (cached VM)

## Troubleshooting

### "Error: nix command not found"

Install Nix or ensure it's in your PATH:
```bash
which nix
# or
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
```

### Test Hangs at "Waiting for Sway"

The VM might not have enough resources:

Edit `default.nix` and increase:
```nix
virtualisation = {
  memorySize = 4096;  # Increase from 2048
  cores = 4;          # Add more CPU cores
};
```

### Sway Crashes in VM

Check the logs in interactive mode:
```python
>>> machine.succeed("journalctl -u greetd -n 100")
>>> machine.succeed("journalctl --user -M testuser@ -u sway -n 100")
```

Common causes:
- Missing Wayland environment variables
- Incorrect renderer (should be pixman for headless)
- GPU device issues (should use virtio-gpu)

### Screenshots Are Black

This is normal for headless Wayland - Sway is running but there's no visual output to VNC. The window tree state is what matters for tests.

If you need visual verification:
- Use `machine.get_screen_text()` for OCR
- Rely on `swaymsg -t get_tree` output
- Check window properties instead of visual appearance

## Next Steps

- **Read full docs**: `README.md` in this directory
- **Review test cases**: `test-cases/` directory for examples
- **Write custom tests**: See "Writing New Tests" in README.md
- **Explore codebase**: `default.nix` for test definitions

## Quick Reference

| Command | Purpose |
|---------|---------|
| `./run-tests.sh list` | List all available tests |
| `./run-tests.sh basic` | Run basic functionality test |
| `./run-tests.sh all` | Run complete test suite |
| `./run-tests.sh interactive` | Launch Python REPL debugger |
| `machine.shell_interact()` | Interactive shell in VM (from REPL) |
| `machine.screenshot("name")` | Save screenshot |
| `machine.succeed("cmd")` | Run command, assert success |

## Resources

- **NixOS Test Driver Docs**: https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines
- **Sway Test Framework**: `/etc/nixos/specs/069-sync-test-framework/quickstart.md`
- **i3pm Documentation**: `CLAUDE.md` in repo root

## Questions?

Check the full `README.md` or open an issue in the repo.
