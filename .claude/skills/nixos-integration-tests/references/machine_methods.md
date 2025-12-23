# NixOS Test Machine Methods API

Complete reference for machine object methods in NixOS integration tests.

Source: [NixOS Manual](https://nlewo.github.io/nixos-manual-sphinx/development/writing-nixos-tests.xml.html)

## Contents

- [VM Lifecycle](#vm-lifecycle)
- [Command Execution](#command-execution)
- [Waiting Operations](#waiting-operations)
- [Systemd Operations](#systemd-operations)
- [Network Operations](#network-operations)
- [File Operations](#file-operations)
- [Display and Input](#display-and-input)
- [QEMU Control](#qemu-control)

## VM Lifecycle

### `start()`
Launch the VM asynchronously without waiting for boot completion.

```python
machine.start()
# VM boots in background
```

### `shutdown()`
Gracefully power down the machine by sending an ACPI shutdown signal.

```python
machine.shutdown()
```

### `crash()`
Simulate an immediate power failure (hard reset).

```python
machine.crash()
# VM loses all volatile state
```

### `reboot()`
Gracefully reboot the machine.

```python
machine.reboot()
machine.wait_for_unit("multi-user.target")
```

## Command Execution

### `succeed(command, timeout=None)`
Execute a shell command, raising an exception if the exit status is not zero. Returns stdout.

```python
output = machine.succeed("echo hello")
assert output.strip() == "hello"

# With timeout (seconds)
machine.succeed("slow-command", timeout=60)
```

### `fail(command)`
Execute a shell command, raising an exception if the exit status IS zero. Use to verify expected failures.

```python
machine.fail("test -f /nonexistent")
```

### `execute(command)`
Execute a shell command and return a tuple of (exit_status, stdout).

```python
status, output = machine.execute("maybe-fails")
if status == 0:
    print(f"Success: {output}")
```

### `wait_until_succeeds(command, timeout=900)`
Repeat a shell command with 1-second intervals until it succeeds (or timeout).

```python
machine.wait_until_succeeds("curl -f http://localhost:8080")
```

### `wait_until_fails(command, timeout=900)`
Repeat a shell command until it fails.

```python
machine.wait_until_fails("pgrep my-process")
```

## Waiting Operations

### `wait_for_unit(unit, user=None, timeout=900)`
Wait until the specified systemd unit reaches "active" state.

```python
# System unit
machine.wait_for_unit("nginx.service")

# User unit (requires user parameter)
machine.wait_for_unit("eww.service", user="testuser")
```

### `wait_for_file(path, timeout=900)`
Wait until a file exists at the specified path.

```python
machine.wait_for_file("/tmp/ready.flag")
```

### `wait_for_open_port(port, timeout=900)`
Wait until a process is listening on the specified TCP port.

```python
machine.wait_for_open_port(80)
machine.wait_for_open_port(5432)  # PostgreSQL
```

### `wait_for_closed_port(port, timeout=900)`
Wait until nothing is listening on the specified port.

```python
machine.wait_for_closed_port(8080)
```

### `wait_for_x(timeout=900)`
Wait until the X11 server is accepting connections.

```python
machine.wait_for_x()
machine.succeed("xdotool --version")
```

### `wait_for_window(regex, timeout=900)`
Wait until an X11 window appears whose name matches the regex.

```python
machine.wait_for_window("Firefox")
machine.wait_for_window(".*Terminal.*")
```

### `wait_for_text(regex, timeout=900)`
Use OCR to wait until text matching regex appears on screen.

```python
machine.wait_for_text("Login successful")
```

### `sleep(seconds)`
Pause execution for the specified number of seconds.

```python
machine.sleep(5)  # Wait 5 seconds
```

## Systemd Operations

### `systemctl(command, user=None)`
Execute systemctl with the given command.

```python
machine.systemctl("restart nginx")
machine.systemctl("status sshd")

# For user services
machine.systemctl("restart eww", user="testuser")
```

### `get_unit_info(unit, user=None)`
Get information about a systemd unit.

```python
info = machine.get_unit_info("nginx.service")
print(info["ActiveState"])
```

### `start_job(unit, user=None)`
Start a systemd unit.

```python
machine.start_job("nginx.service")
```

### `stop_job(unit, user=None)`
Stop a systemd unit.

```python
machine.stop_job("nginx.service")
```

## Network Operations

### `block()`
Simulate unplugging the Ethernet cable (isolate from network).

```python
machine.block()
# Machine is now isolated
```

### `unblock()`
Restore network connectivity after `block()`.

```python
machine.unblock()
```

## File Operations

### `copy_file_from_host(source, target)`
Copy a file from the Nix build host into the VM.

Note: The source file must be accessible during nix-build (use `builtins.path` or store paths).

```python
machine.copy_file_from_host("${./testdata.json}", "/tmp/testdata.json")
```

### `copy_from_vm(source, target)` / `copy_to_vm(source, target)`
Copy files between the VM and the test result directory.

```python
machine.copy_from_vm("/var/log/app.log", "logs/app.log")
```

## Display and Input

### `screenshot(name)`
Capture the VM's display to a PNG file in the test results.

```python
machine.screenshot("after_login")
# Creates: result/after_login.png
```

### `get_screen_text()`
Use OCR to extract text from the current screen.

```python
text = machine.get_screen_text()
assert "Welcome" in text
```

### `send_keys(keys)`
Simulate pressing keyboard keys.

```python
machine.send_keys("ctrl-alt-delete")
machine.send_keys("alt-F2")
machine.send_keys("ret")  # Enter key
```

Key names: `ret`, `spc`, `tab`, `backspace`, `ctrl`, `alt`, `shift`, `meta`, `F1`-`F12`, etc.

### `send_chars(text)`
Type a sequence of characters.

```python
machine.send_chars("mypassword\n")  # \n = Enter
```

## QEMU Control

### `send_monitor_command(command)`
Send a command to the QEMU monitor. Rarely needed but powerful.

```python
# Attach a USB device
machine.send_monitor_command("device_add usb-storage,drive=mydrive")

# Take a QEMU screenshot (different from machine.screenshot)
machine.send_monitor_command("screendump /tmp/qemu-screen.ppm")
```

## Helper Function

### `start_all()`

Global function (not a method) to start all defined nodes in parallel.

```python
# In testScript:
start_all()

# Equivalent to calling machine.start() for each node
# but waits for all VMs to be ready
```

## Assertions

Access `unittest.TestCase` assertions via the `t` variable:

```python
output = machine.succeed("cat /etc/hostname")
t.assertEqual(output.strip(), "testvm")
t.assertIn("expected", output)
t.assertTrue(some_condition)
```

## Examples

### Service Test Pattern

```python
start_all()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("nginx.service")
machine.wait_for_open_port(80)

output = machine.succeed("curl -s localhost")
assert "<html>" in output

machine.screenshot("nginx_running")
```

### Multi-Machine Test Pattern

```python
start_all()

server.wait_for_unit("postgresql.service")
server.wait_for_open_port(5432)

client.succeed("psql -h server -U postgres -c 'SELECT 1'")
```

### Cleanup Pattern

```python
try:
    machine.succeed("risky-operation")
except Exception:
    machine.screenshot("failure_state")
    machine.succeed("journalctl -u my-service --no-pager > /tmp/logs")
    raise
```
