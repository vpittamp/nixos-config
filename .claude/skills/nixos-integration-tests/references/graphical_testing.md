# Graphical Testing with NixOS VMs

Testing GUI applications, Sway compositor, and interactive elements.

## Contents

- [VNC Setup](#vnc-setup)
- [Headless vs Graphical](#headless-vs-graphical)
- [Sway Testing Patterns](#sway-testing-patterns)
- [Screenshot and OCR](#screenshot-and-ocr)
- [Home-Manager Integration](#home-manager-integration)
- [Debugging Tips](#debugging-tips)

## VNC Setup

### Enable VNC in Test VM

```nix
nodes.machine = { config, pkgs, ... }: {
  virtualisation = {
    memorySize = 4096;
    cores = 4;
    resolution = { x = 1920; y = 1080; };
    qemu.options = [
      "-vga none"
      "-device virtio-gpu-pci"
      "-vnc :0"  # VNC on port 5900
    ];
  };

  hardware.graphics.enable = true;
};
```

### Connect to VNC

During interactive mode:
```bash
$(nix-build -A test.driverInteractive)/bin/nixos-test-driver

# In another terminal:
vncviewer localhost:5900
# or
vinagre vnc://localhost:5900
```

## Headless vs Graphical

### Headless Mode (Fast, CI-friendly)

```nix
environment.sessionVariables = {
  WLR_BACKENDS = "headless";
  WLR_HEADLESS_OUTPUTS = "3";  # Number of virtual monitors
  WLR_RENDERER = "pixman";     # Software rendering
  WLR_NO_HARDWARE_CURSORS = "1";
  WLR_LIBINPUT_NO_DEVICES = "1";
};
```

**Pros:** Fast, works in CI, no display needed
**Cons:** No visual debugging, limited screenshots

### Graphical Mode (VNC-accessible)

```nix
environment.sessionVariables = {
  WLR_RENDERER = "pixman";
  WLR_NO_HARDWARE_CURSORS = "1";
  # Note: NO WLR_BACKENDS=headless
};
```

**Pros:** Real rendering, VNC debugging, accurate GUI tests
**Cons:** Slower, requires more memory

## Sway Testing Patterns

### Wait for Sway Ready

```python
# Wait for display manager
machine.wait_for_unit("greetd.service")

# Wait for Sway IPC socket
machine.wait_for_file("/tmp/sway-ipc.sock")

# Wait a moment for Sway to initialize
machine.sleep(2)

# Verify Sway is responding
machine.succeed("su - testuser -c 'swaymsg -t get_version'")
```

### Sway IPC Commands

```python
# Get outputs (monitors)
output = machine.succeed("su - testuser -c 'swaymsg -t get_outputs'")
outputs = json.loads(output)
assert len(outputs) == 3

# Get workspaces
workspaces = machine.succeed("su - testuser -c 'swaymsg -t get_workspaces | jq'")

# Get window tree
tree = machine.succeed("su - testuser -c 'swaymsg -t get_tree | jq'")

# Execute Sway command
machine.succeed("su - testuser -c 'swaymsg workspace number 1'")
```

### Launch and Find Windows

```python
def wait_for_window(app_id, timeout=20):
    """Wait for a Sway window with given app_id."""
    import time
    start = time.time()
    while time.time() - start < timeout:
        try:
            output = machine.succeed(
                f"su - testuser -c 'swaymsg -t get_tree | "
                f"jq -r \".. | .app_id? // empty\" | grep -q {app_id} && echo found'"
            )
            if "found" in output:
                return True
        except:
            pass
        machine.sleep(1)
    return False

# Launch application via Sway exec
machine.succeed("su - testuser -c 'swaymsg exec foot'")

# Wait for window
assert wait_for_window("foot"), "Window not found"
```

### Workspace Navigation

```python
# Switch to workspace 1
machine.succeed("su - testuser -c 'swaymsg workspace number 1'")
machine.sleep(0.5)

# Verify focused workspace
ws = machine.succeed(
    "su - testuser -c 'swaymsg -t get_workspaces | "
    "jq -r \".[] | select(.focused == true) | .num\"'"
)
assert ws.strip() == "1"
```

## Screenshot and OCR

### Take Screenshots

```python
# Basic screenshot
machine.screenshot("before_login")

# Screenshot after action
machine.succeed("su - testuser -c 'swaymsg exec firefox'")
machine.sleep(3)
machine.screenshot("firefox_launched")
```

Screenshots are saved to the test result directory.

### OCR Text Recognition

Requires `enableOCR = true` in test config:

```nix
pkgs.testers.nixosTest {
  name = "ocr-test";
  enableOCR = true;  # Enable tesseract OCR

  nodes.machine = { ... };

  testScript = ''
    machine.wait_for_text("Login")
    text = machine.get_screen_text()
    assert "Welcome" in text
  '';
}
```

### Wait for Visual Elements

```python
# Wait for text to appear
machine.wait_for_text("Desktop ready")

# Get all screen text
text = machine.get_screen_text()
print(f"Screen content:\n{text}")

# Assert visual content
assert "Expected Text" in text, f"Text not found in: {text}"
```

## Home-Manager Integration

### Include Home-Manager in Test VM

```nix
{ pkgs, inputs, ... }:

let
  home-manager = inputs.home-manager;
in
pkgs.testers.nixosTest {
  name = "home-manager-test";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      home-manager.nixosModules.home-manager
    ];

    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.testuser = { config, pkgs, ... }: {
        # Your home-manager config
        programs.git.enable = true;

        home.stateVersion = "24.11";
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("home-manager-testuser.service", "testuser")
    machine.succeed("su - testuser -c 'git --version'")
  '';
}
```

### Test EWW Widgets

```python
# Wait for EWW daemon
machine.wait_for_unit("eww.service", "testuser")

# Open a window
machine.succeed("su - testuser -c 'eww open monitoring-panel'")
machine.sleep(1)

# Verify widget is running
output = machine.succeed("su - testuser -c 'eww windows'")
assert "monitoring-panel" in output
```

### Test i3pm Daemon

```python
# Wait for daemon
machine.wait_for_unit("i3-project-event-listener.service", "testuser")

# Check daemon status
status = machine.succeed("su - testuser -c 'i3pm daemon status'")
print(f"Daemon status: {status}")

# List projects
projects = machine.succeed("su - testuser -c 'i3pm project list' || true")
print(f"Projects: {projects}")
```

## Debugging Tips

### 1. Use VNC for Live Debugging

```bash
# Start interactive driver
$(nix-build -A test.driverInteractive)/bin/nixos-test-driver

# In Python REPL
>>> start_all()
>>> machine.shell_interact()  # Opens shell

# Connect VNC to see the desktop
vncviewer localhost:5900
```

### 2. Capture State on Failure

```python
try:
    machine.succeed("risky-gui-operation")
except Exception as e:
    machine.screenshot("failure_screenshot")
    machine.succeed("su - testuser -c 'swaymsg -t get_tree' > /tmp/sway-tree.json")
    logs = machine.succeed("journalctl --user -n 100 --no-pager 2>/dev/null || true")
    print(f"Logs:\n{logs}")
    raise
```

### 3. Check Sway Logs

```python
# Sway log location varies, check common places
machine.succeed("cat /tmp/sway.log 2>/dev/null || true")
machine.succeed("journalctl -u greetd --no-pager || true")
```

### 4. Verify Display Manager Session

```python
# Check greetd started Sway
machine.succeed("loginctl show-session -p Type | grep wayland")

# Check WAYLAND_DISPLAY is set
machine.succeed("su - testuser -c 'echo $WAYLAND_DISPLAY'")
```

### 5. GTK/Qt Rendering Issues

If GUI apps fail to render:

```nix
environment.sessionVariables = {
  GSK_RENDERER = "cairo";  # Force software rendering for GTK4
  GDK_BACKEND = "wayland";
  QT_QPA_PLATFORM = "wayland";
};
```

### 6. Memory Issues

Graphical tests need more memory:

```nix
virtualisation.memorySize = 4096;  # 4GB minimum for GUI testing
virtualisation.cores = 4;
```
