# Application Testing Patterns

Testing application launches via app-launcher-wrapper and verifying window management.

## Contents

- [App Launcher Overview](#app-launcher-overview)
- [Testing App Launches](#testing-app-launches)
- [PWA Testing](#pwa-testing)
- [Project Context Testing](#project-context-testing)
- [Window Verification](#window-verification)
- [I3PM Integration](#i3pm-integration)

## App Launcher Overview

The unified app launcher (`app-launcher-wrapper.sh`) provides:

1. **I3PM_* environment injection** - Project context for all apps
2. **Launch notification** - Pre-launch daemon notification
3. **Workspace assignment** - Automatic workspace placement
4. **Process isolation** - Sway exec for proper lifecycle

### Environment Variables Set

| Variable | Purpose |
|----------|---------|
| `I3PM_APP_ID` | Unique instance identifier |
| `I3PM_APP_NAME` | Application name from registry |
| `I3PM_PROJECT_NAME` | Active project name |
| `I3PM_PROJECT_DIR` | Project directory path |
| `I3PM_SCOPE` | "scoped" or "global" |
| `I3PM_TARGET_WORKSPACE` | Assigned workspace number |
| `I3PM_EXPECTED_CLASS` | Expected window class |

## Testing App Launches

### Basic App Launch Test

```python
# Ensure app-launcher-wrapper is available
machine.succeed("which app-launcher-wrapper.sh")

# Launch terminal app
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")

# Wait for window
def wait_for_window(app_id, timeout=20):
    import time
    start = time.time()
    while time.time() - start < timeout:
        try:
            result = machine.succeed(
                f"su - testuser -c 'swaymsg -t get_tree | "
                f"jq -r \".. | .app_id? // empty\" | grep -q \"{app_id}\"'"
            )
            return True
        except:
            machine.sleep(1)
    return False

assert wait_for_window("com.mitchellh.ghostty"), "Terminal window not found"
```

### Test with Dry Run

```python
# Dry run shows what would execute
output = machine.succeed(
    "su - testuser -c 'DRY_RUN=1 app-launcher-wrapper.sh terminal'"
)
assert "ghostty" in output
assert "PROJECT_DIR" in output or "HOME" in output
```

### Verify Environment Variables

```python
# Launch app that prints its environment
machine.succeed("""
su - testuser -c '
    app-launcher-wrapper.sh terminal &
    sleep 2
    # Check the launched process has I3PM vars
    ps aux | grep ghostty | head -1
'
""")

# Or read from /proc if we know the PID
output = machine.succeed("""
su - testuser -c '
    swaymsg exec "ghostty -e printenv > /tmp/app-env.txt && sleep 1"
    sleep 3
    cat /tmp/app-env.txt | grep I3PM || true
'
""")
print(f"App environment:\n{output}")
```

## PWA Testing

PWAs use Firefox with FFPWA extension. Window class follows pattern: `FFPWA-{ULID}`

### Launch PWA

```python
# PWAs are launched via app-launcher with -pwa suffix
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh claude-pwa'")

# Wait for PWA window
# PWA ULID from pwa-sites.nix: 01JCYF8Z2M7R4N6QW9XKPHVTB5
expected_class = "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5"

def wait_for_pwa(window_class, timeout=30):
    import time
    start = time.time()
    while time.time() - start < timeout:
        try:
            machine.succeed(
                f"su - testuser -c 'swaymsg -t get_tree | "
                f"jq -r \".. | .app_id? // empty\" | grep -q \"{window_class}\"'"
            )
            return True
        except:
            machine.sleep(1)
    return False

assert wait_for_pwa(expected_class), f"PWA window {expected_class} not found"
```

### Verify PWA Workspace Assignment

```python
# PWAs should be on workspace 50+
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh youtube-pwa'")
machine.sleep(5)

# Check workspace assignment (YouTube is WS 50)
ws = machine.succeed("""
su - testuser -c '
    swaymsg -t get_tree | jq -r "
        .. | objects | select(.app_id? == \"FFPWA-01K666N2V6BQMDSBMX3AY74TY7\") |
        .workspace_name // empty
    " | head -1
'
""")
print(f"YouTube PWA on workspace: {ws}")
```

## Project Context Testing

### Set Up Project Context

```python
# Create test project configuration
machine.succeed("""
su - testuser -c '
mkdir -p ~/.config/i3
cat > ~/.config/i3/active-worktree.json << EOF
{
    "qualified_name": "test-project",
    "directory": "/home/testuser/projects/test-project",
    "branch": "main",
    "account": "testuser",
    "repo_name": "test-project"
}
EOF
mkdir -p ~/projects/test-project
'
""")

# Launch scoped app
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")

# Verify working directory
output = machine.succeed("""
su - testuser -c '
    swaymsg exec "ghostty -e pwd > /tmp/pwd.txt && sleep 1"
    sleep 3
    cat /tmp/pwd.txt
'
""")
assert "/home/testuser/projects/test-project" in output
```

### Test Global vs Scoped Apps

```python
# Firefox is global - should work without project
machine.succeed("""
su - testuser -c '
    rm -f ~/.config/i3/active-worktree.json
    app-launcher-wrapper.sh firefox
'
""")

# Terminal with fallback_behavior=use_home
machine.succeed("""
su - testuser -c '
    rm -f ~/.config/i3/active-worktree.json
    app-launcher-wrapper.sh terminal
'
""")
# Should fall back to HOME directory
```

## Window Verification

### Get All Windows

```python
def get_windows():
    """Get list of all windows from Sway tree."""
    output = machine.succeed(
        "su - testuser -c 'swaymsg -t get_tree | "
        "jq -r \"[.. | objects | select(.app_id != null) | "
        "{app_id, name, focused, workspace: .workspace_name}]\"'"
    )
    import json
    return json.loads(output)

windows = get_windows()
for w in windows:
    print(f"  {w['app_id']}: {w.get('name', 'unnamed')}")
```

### Verify Window on Correct Workspace

```python
def verify_window_workspace(app_id, expected_ws):
    """Verify a window is on the expected workspace."""
    output = machine.succeed(f"""
        su - testuser -c 'swaymsg -t get_tree | jq -r "
            [.. | objects | select(.app_id == \\"{app_id}\\")] |
            first | .workspace_name // empty
        "'
    """)
    actual_ws = output.strip()
    assert actual_ws == str(expected_ws), \
        f"Window {app_id} on WS {actual_ws}, expected WS {expected_ws}"

# Terminal should be on WS 1
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")
machine.sleep(3)
verify_window_workspace("com.mitchellh.ghostty", 1)

# VS Code should be on WS 2
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh code'")
machine.sleep(5)
verify_window_workspace("Code", 2)
```

### Check Window Focus

```python
def get_focused_window():
    """Get the currently focused window's app_id."""
    output = machine.succeed(
        "su - testuser -c 'swaymsg -t get_tree | "
        "jq -r \".. | objects | select(.focused == true) | .app_id\"'"
    )
    return output.strip()

# After launching, verify focus
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")
machine.sleep(2)
assert get_focused_window() == "com.mitchellh.ghostty"
```

## I3PM Integration

### Test Daemon Launch Notification

```python
# Ensure daemon is running
machine.wait_for_unit("i3-project-event-listener.service", "testuser")

# Check daemon socket exists
machine.succeed("test -S /run/user/1000/i3-project-daemon/ipc.sock")

# Launch app (triggers notification)
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")

# Check daemon logs for launch notification
logs = machine.succeed(
    "journalctl --user -u i3-project-event-listener -n 10 --no-pager"
)
assert "launch" in logs.lower() or "terminal" in logs.lower()
```

### Test Window-to-Project Association

```python
# Set project context
machine.succeed("""
su - testuser -c '
cat > ~/.config/i3/active-worktree.json << EOF
{"qualified_name": "my-project", "directory": "/tmp/my-project", "branch": "main"}
EOF
mkdir -p /tmp/my-project
'
""")

# Launch scoped app
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh terminal'")
machine.sleep(3)

# Query daemon for window info
status = machine.succeed("su - testuser -c 'i3pm daemon status' || true")
print(f"Daemon status:\n{status}")

# The window should be associated with my-project
windows = machine.succeed("su - testuser -c 'i3pm diagnose window' || true")
print(f"Window diagnose:\n{windows}")
```

### Test Scratchpad Terminal

```python
# Scratchpad terminal is special - workspace 0
machine.succeed("su - testuser -c 'app-launcher-wrapper.sh scratchpad-terminal'")
machine.sleep(2)

# Verify it's floating and on scratchpad
output = machine.succeed("""
su - testuser -c 'swaymsg -t get_tree | jq "
    [.. | objects | select(.app_id == \"com.mitchellh.ghostty\")] |
    map({app_id, floating: .type, scratchpad: .scratchpad_state})
"'
""")
print(f"Scratchpad windows: {output}")
```
