---
name: creating-nixos-integration-tests
description: Creates NixOS VM-based integration tests using testers.runNixOSTest with OpenTelemetry observability. Use when writing isolated system tests for Sway, daemons, multi-machine networking, or any NixOS feature requiring QEMU VM testing with full telemetry to Grafana.
---

# Creating NixOS Integration Tests

This skill provides guidance for creating NixOS VM-based integration tests with OpenTelemetry observability.

## Quick Start

Create a minimal test using `pkgs.testers.nixosTest`:

```nix
# tests/my-feature/default.nix
{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.nixosTest {
  name = "my-feature-test";

  nodes.machine = { config, pkgs, ... }: {
    # NixOS configuration for the test VM
    environment.systemPackages = [ pkgs.hello ];
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("hello --version")
    print("Test passed!")
  '';
}
```

**Build and run:**
```bash
nix-build tests/my-feature -A default
```

**Interactive debugging:**
```bash
$(nix-build tests/my-feature -A default.driverInteractive)/bin/nixos-test-driver
# Then in Python REPL: start_all(), machine.succeed("cmd"), etc.
```

## Test Structure

A NixOS test consists of three main components:

### 1. Test Definition

```nix
pkgs.testers.nixosTest {
  name = "test-name";           # Identifies the test
  nodes = { ... };              # VM configurations
  testScript = ''...'';         # Python test code
}
```

### 2. Nodes Configuration

Each node defines a NixOS VM:

```nix
nodes.machine = { config, pkgs, ... }: {
  # Standard NixOS module configuration
  services.nginx.enable = true;

  # VM-specific settings
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 8192;
};
```

For multi-machine tests:

```nix
nodes = {
  server = { ... }: { services.nginx.enable = true; };
  client = { ... }: { environment.systemPackages = [ pkgs.curl ]; };
};
```

### 3. Test Script

Python code that orchestrates the test:

```nix
testScript = ''
  start_all()                                    # Boot all VMs in parallel
  server.wait_for_unit("nginx.service")          # Wait for service
  client.succeed("curl -f http://server:80")     # Test connectivity
  server.screenshot("nginx_running")             # Capture state
'';
```

## Machine Methods

Essential methods available on machine objects. See [references/machine_methods.md](references/machine_methods.md) for the complete API.

| Method | Purpose |
|--------|---------|
| `start()` | Launch VM asynchronously |
| `shutdown()` | Graceful power down |
| `succeed(cmd)` | Run command, assert exit 0 |
| `fail(cmd)` | Run command, assert non-zero exit |
| `wait_for_unit(unit)` | Wait for systemd unit to be active |
| `wait_for_file(path)` | Wait for file to exist |
| `wait_for_open_port(port)` | Wait for TCP listener |
| `screenshot(name)` | Capture VM display |
| `copy_file_from_host(src, dst)` | Transfer file to VM |

**Helper functions in testScript:**
```python
start_all()     # Start all nodes in parallel

# Access unittest assertions via 't':
t.assertIn("expected", output)
```

## OpenTelemetry Integration

Emit test telemetry to Grafana for observability. See [references/otel_integration.md](references/otel_integration.md) for details.

### Quick Setup

Include Grafana Alloy in your test VM:

```nix
nodes.machine = { config, pkgs, ... }: {
  services.grafana-alloy.enable = true;

  environment.sessionVariables = {
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
  };
};
```

### Emit Test Spans

Use the provided script to emit test result traces:

```bash
scripts/emit_test_span.sh "my-test" "passed" 1500
```

Or within testScript:

```python
machine.succeed("emit_test_span.sh 'service-check' 'passed' 500")
```

## Templates

Choose a template based on your test requirements:

| Template | Use Case |
|----------|----------|
| [minimal.nix](templates/minimal.nix) | Basic single-machine tests |
| [multi_machine.nix](templates/multi_machine.nix) | Network/distributed testing |
| [graphical.nix](templates/graphical.nix) | GUI/Sway testing with VNC |
| [otel_traced.nix](templates/otel_traced.nix) | Full observability integration |

Copy and customize:
```bash
python scripts/init_test.py my-feature --type minimal
```

## Creating a New Test

Follow this workflow when creating tests:

```
Test Creation Checklist:
- [ ] Step 1: Choose appropriate template
- [ ] Step 2: Define nodes with required NixOS configuration
- [ ] Step 3: Write testScript with assertions
- [ ] Step 4: Build and run interactively to debug
- [ ] Step 5: Add OTEL instrumentation (optional)
- [ ] Step 6: Verify in CI/headless mode
```

### Step 1: Initialize Test File

```bash
python scripts/init_test.py my-feature --type minimal
```

### Step 2: Configure VM

Add required NixOS modules and packages:

```nix
nodes.machine = { config, pkgs, ... }: {
  imports = [ ./my-module.nix ];
  services.my-service.enable = true;
  environment.systemPackages = [ pkgs.my-tool ];
};
```

### Step 3: Write Test Logic

Use machine methods to verify behavior:

```python
machine.wait_for_unit("my-service.service")
output = machine.succeed("my-tool --status")
assert "running" in output, f"Expected 'running' in: {output}"
```

### Step 4: Debug Interactively

```bash
$(nix-build -A default.driverInteractive)/bin/nixos-test-driver
```

In the Python REPL:
```python
>>> start_all()
>>> machine.succeed("systemctl status my-service")
>>> machine.screenshot("debug")
```

### Step 5: Add Observability

See [references/otel_integration.md](references/otel_integration.md) for detailed patterns.

## Common Patterns

### Testing Services

```python
# Wait for service to be ready
machine.wait_for_unit("nginx.service")
machine.wait_for_open_port(80)

# Verify service responds correctly
output = machine.succeed("curl -s http://localhost:80")
assert "<html>" in output
```

### Multi-Machine Communication

```python
# Server/client test pattern
server.wait_for_unit("nginx.service")
client.succeed("ping -c 1 server")
client.succeed("curl -f http://server:80")
```

### Testing with Wayland/Sway

See [references/graphical_testing.md](references/graphical_testing.md) for VNC and GUI patterns.

```python
machine.wait_for_unit("greetd.service")
machine.wait_for_file("/tmp/sway-ipc.sock")
machine.succeed("swaymsg -t get_version")
```

### Testing Application Launches

See [references/app_testing.md](references/app_testing.md) for app-launcher patterns.

```python
# Launch app via unified wrapper
machine.succeed("app-launcher-wrapper.sh terminal")

# Verify window appeared
def wait_for_window(app_id, timeout=10):
    import time
    start = time.time()
    while time.time() - start < timeout:
        try:
            machine.succeed(f"swaymsg -t get_tree | jq '.. | .app_id?' | grep -q {app_id}")
            return True
        except:
            machine.sleep(1)
    return False

assert wait_for_window("com.mitchellh.ghostty")
```

## Configuration Options

### Virtualization Settings

```nix
virtualisation = {
  memorySize = 2048;           # RAM in MB
  diskSize = 8192;             # Disk in MB
  cores = 2;                   # CPU cores
  graphics = false;            # Disable for CI
  qemu.options = [             # Custom QEMU flags
    "-vga none"
    "-device virtio-gpu-pci"
  ];
};
```

### Headless Wayland (for Sway tests)

```nix
environment.sessionVariables = {
  WLR_BACKENDS = "headless";
  WLR_HEADLESS_OUTPUTS = "3";
  WLR_RENDERER = "pixman";
  WLR_NO_HARDWARE_CURSORS = "1";
};
```

### Multi-Machine Networking

```nix
# Machines on same VLAN can communicate via hostname
nodes = {
  server = { virtualisation.vlans = [ 1 ]; };
  client = { virtualisation.vlans = [ 1 ]; };
};

testScript = ''
  client.succeed("ping -c 1 server")
'';
```

## Debugging Tips

1. **Use interactive mode** for rapid iteration:
   ```bash
   $(nix-build -A driverInteractive)/bin/nixos-test-driver
   ```

2. **Take screenshots** at failure points:
   ```python
   machine.screenshot("before_failure")
   ```

3. **Check logs** when services fail:
   ```python
   machine.succeed("journalctl -u my-service --no-pager")
   ```

4. **Clear VM state** if corrupted:
   ```bash
   rm -rf /tmp/vm-state-machine
   ```

5. **Use VNC** for graphical debugging (see [references/graphical_testing.md](references/graphical_testing.md))

## Resources

- [references/machine_methods.md](references/machine_methods.md) - Complete Python API
- [references/otel_integration.md](references/otel_integration.md) - Telemetry patterns
- [references/graphical_testing.md](references/graphical_testing.md) - VNC/GUI testing
- [references/app_testing.md](references/app_testing.md) - Application launcher testing

### Official Documentation

- [nix.dev Integration Testing Tutorial](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html)
- [NixOS Manual - Writing Tests](https://nlewo.github.io/nixos-manual-sphinx/development/writing-nixos-tests.xml.html)
- [Nixcademy - Integration Tests Part 1](https://nixcademy.com/posts/nixos-integration-tests/)
- [Nixcademy - Integration Tests Part 2](https://nixcademy.com/posts/nixos-integration-tests-part-2/)
