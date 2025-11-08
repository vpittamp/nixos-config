# Walker Application Launch Testing Guide

## Overview

This guide explains how applications are launched via Walker and how to test this process using the sway-test framework.

## Application Launch Flow

### 1. Application Registry (`app-registry-data.nix`)

Applications are defined declaratively with metadata:

```nix
(mkApp {
  name = "firefox";
  display_name = "Firefox";
  command = "firefox";
  parameters = "";
  scope = "global";
  expected_class = "firefox";
  preferred_workspace = 3;
  icon = "firefox";
  nix_package = "pkgs.firefox";
  multi_instance = false;
  fallback_behavior = "skip";
  description = "Mozilla Firefox web browser";
})
```

**Key Fields**:
- `name`: Internal identifier used by launcher
- `command`: Executable to run
- `parameters`: Command-line arguments (supports `$PROJECT_DIR`, `$PROJECT_NAME` variables)
- `scope`: "scoped" (project-aware) or "global" (project-agnostic)
- `preferred_workspace`: Where window should appear (1-70)
- `expected_class`: Window class/app_id for validation
- `fallback_behavior`: What to do when no project is active ("skip", "use_home", "error")

### 2. Desktop File Generation (`app-registry.nix`)

Each app gets a `.desktop` file at `~/.local/share/i3pm-applications/applications/<app-name>.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Firefox [WS3]
Comment=Mozilla Firefox web browser
Exec=/home/vpittamp/.local/bin/app-launcher-wrapper.sh firefox
Icon=firefox
Terminal=false
NoDisplay=false
Categories=Application;Global;
StartupWMClass=firefox
X-Project-Scope=global
X-Preferred-Workspace=3
X-Multi-Instance=false
X-Fallback-Behavior=skip
X-Nix-Package=pkgs.firefox
```

**Key Points**:
- `Exec` points to `app-launcher-wrapper.sh <app-name>` (not direct command)
- `StartupWMClass` matches expected window class
- Custom `X-*` fields store i3pm metadata

### 3. Walker Configuration

Walker (Elephant) is configured to:
- Read desktop files from `~/.local/share/i3pm-applications/applications/`
- Provide fuzzy search interface
- Execute the `Exec` command when user selects an app

**User Experience**:
1. User presses `Meta+D` (opens Walker)
2. Types "fire" (fuzzy matches "Firefox [WS3]")
3. Presses Enter
4. Walker executes: `~/.local/bin/app-launcher-wrapper.sh firefox`

### 4. App Launcher Wrapper (`app-launcher-wrapper.sh`)

The wrapper script is the **core integration point** that:

#### 4.1. Loads App Configuration
```bash
APP_JSON=$(jq --arg name "$APP_NAME" \
    '.applications[] | select(.name == $name)' \
    "$HOME/.config/i3/application-registry.json")
```

#### 4.2. Queries Project Context
```bash
PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')
PROJECT_NAME=$(echo "$PROJECT_JSON" | jq -r '.name // ""')
PROJECT_DIR=$(echo "$PROJECT_JSON" | jq -r '.directory // ""')
```

#### 4.3. Injects I3PM Environment Variables
```bash
export I3PM_APP_ID="firefox-nixos-12345-1699876543"
export I3PM_APP_NAME="firefox"
export I3PM_PROJECT_NAME="nixos"
export I3PM_PROJECT_DIR="/etc/nixos"
export I3PM_SCOPE="global"
export I3PM_ACTIVE="true"
export I3PM_LAUNCH_TIME="1699876543"
export I3PM_LAUNCHER_PID="12345"
export I3PM_TARGET_WORKSPACE="3"
export I3PM_EXPECTED_CLASS="firefox"
```

**Why These Variables Matter**:
- `I3PM_APP_NAME`: Window identification (tier 1 matching via `/proc/<pid>/environ`)
- `I3PM_PROJECT_NAME`: Associates window with project
- `I3PM_TARGET_WORKSPACE`: Tells daemon where to assign window (Feature 053)
- `I3PM_EXPECTED_CLASS`: Validation (expected vs actual window class)

#### 4.4. Sends Launch Notification (Feature 041)
```bash
# Sends JSON-RPC to daemon BEFORE app launches
notify_launch "$APP_NAME" "$PROJECT_NAME" "$PROJECT_DIR" \
    "$PREFERRED_WORKSPACE" "$LAUNCH_TIMESTAMP" "$EXPECTED_CLASS"
```

**Purpose**:
- Daemon knows app is about to launch (tier 0 correlation)
- 500ms time window for matching window appearance to launch notification
- Enables 100% deterministic workspace assignment

#### 4.5. Launches App via Sway IPC
```bash
# Export environment variables and execute via Sway
FULL_CMD="export I3PM_APP_ID='...'; export I3PM_APP_NAME='...'; firefox"
swaymsg exec "bash -c \"$FULL_CMD\""
```

**Why Sway Exec**:
- Runs in compositor context (has `WAYLAND_DISPLAY`, etc.)
- Environment variables propagate to spawned process
- Window creation happens in proper display server context
- Independent of launcher process lifecycle

### 5. Daemon Window Processing

When Firefox window appears:

1. **Sway Event**: `window::new` event fired
2. **PID Extraction**: Daemon gets window PID from Sway tree
3. **Environment Read**: Daemon reads `/proc/<pid>/environ`
4. **Tier 1 Matching**: Matches `I3PM_APP_NAME=firefox` from environ
5. **Workspace Assignment**: Moves window to `I3PM_TARGET_WORKSPACE=3`
6. **Project Association**: Records window as part of `I3PM_PROJECT_NAME` project

## Testing Walker-Style Launch

### Approach 1: Direct Wrapper Call (Recommended)

**Test Definition**:
```json
{
  "name": "Walker-style Firefox launch",
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "command": "bash",
        "args": ["-c", "~/.local/bin/app-launcher-wrapper.sh firefox"]
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 10000
      }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 3,
        "windows": [{"app_id": "firefox"}]
      }
    ]
  }
}
```

**What This Tests**:
✅ App registry lookup
✅ Project context query
✅ I3PM environment variable injection
✅ Launch notification to daemon
✅ Sway IPC execution
✅ Workspace assignment
✅ Window appearance on correct workspace

### Approach 2: Sway Exec with Environment (Advanced)

**Test Definition**:
```json
{
  "name": "Manual environment injection",
  "actions": [
    {
      "type": "send_ipc",
      "params": {
        "ipc_command": "exec 'export I3PM_APP_NAME=firefox; export I3PM_TARGET_WORKSPACE=3; firefox'"
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 10000
      }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 3,
        "windows": [{"app_id": "firefox"}]
      }
    ]
  }
}
```

**What This Tests**:
✅ Raw Sway exec with environment variables
✅ Daemon environment reading
✅ Workspace assignment
❌ Does NOT test launch notification
❌ Does NOT test wrapper script logic
❌ Does NOT test project context integration

## Example Tests

### Test 1: Firefox on Workspace 3 (Global App)

```json
{
  "name": "Launch Firefox via walker wrapper",
  "description": "Test global app launches on preferred workspace",
  "tags": ["walker", "global", "workspace-3"],
  "timeout": 12000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "command": "bash",
        "args": ["-c", "~/.local/bin/app-launcher-wrapper.sh firefox"]
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 10000
      }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 3,
        "windows": [
          {
            "app_id": "firefox"
          }
        ]
      }
    ]
  }
}
```

### Test 2: VS Code with Project Context (Scoped App)

```json
{
  "name": "Launch VS Code in project context",
  "description": "Test scoped app with project directory",
  "tags": ["walker", "scoped", "vscode"],
  "timeout": 15000,
  "actions": [
    {
      "type": "send_ipc",
      "params": {
        "ipc_command": "exec 'i3pm project switch nixos'"
      }
    },
    {
      "type": "launch_app",
      "params": {
        "command": "bash",
        "args": ["-c", "~/.local/bin/app-launcher-wrapper.sh vscode"]
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 12000
      }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 2,
        "windows": [
          {
            "app_id": "Code"
          }
        ]
      }
    ]
  }
}
```

### Test 3: Multi-Instance Terminal with Project

```json
{
  "name": "Launch Ghostty terminal with project context",
  "description": "Test multi-instance terminal app with project directory",
  "tags": ["walker", "terminal", "multi-instance"],
  "timeout": 10000,
  "actions": [
    {
      "type": "send_ipc",
      "params": {
        "ipc_command": "exec 'i3pm project switch nixos'"
      }
    },
    {
      "type": "launch_app",
      "params": {
        "command": "bash",
        "args": ["-c", "~/.local/bin/app-launcher-wrapper.sh terminal"]
      }
    },
    {
      "type": "wait_event",
      "params": {
        "event_type": "window::new",
        "timeout_ms": 8000
      }
    }
  ],
  "expectedState": {
    "workspaces": [
      {
        "num": 1,
        "windows": [
          {
            "app_id": "com.mitchellh.ghostty"
          }
        ]
      }
    ]
  }
}
```

## Debugging Launch Issues

### Check Wrapper Logs
```bash
tail -f ~/.local/state/app-launcher.log
```

### Test Wrapper Directly
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh firefox
```

### Dry Run Mode
```bash
DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh firefox
```

### Check App Registry
```bash
jq '.applications[] | select(.name == "firefox")' \
    ~/.config/i3/application-registry.json
```

### Verify Desktop File
```bash
cat ~/.local/share/i3pm-applications/applications/firefox.desktop
```

### Check Walker Can See App
```bash
# List all desktop files Walker sees
ls -la ~/.local/share/i3pm-applications/applications/
```

## Key Differences: Direct Launch vs Walker Launch

| Aspect | Direct `firefox` | Walker Launch |
|--------|-----------------|---------------|
| **Environment** | User shell environment | Sway exec environment |
| **I3PM Variables** | ❌ Not set | ✅ Injected by wrapper |
| **Project Context** | ❌ None | ✅ Current project |
| **Workspace Assignment** | ❌ Random/focused | ✅ Preferred workspace |
| **Daemon Notification** | ❌ No | ✅ Launch notification sent |
| **Window Tracking** | ❌ Not tracked | ✅ Full i3pm tracking |

## Summary

To **simulate Walker app launch** in tests:
1. ✅ **Use `app-launcher-wrapper.sh <app-name>`** - This is the actual Walker Exec command
2. ✅ **Use `bash -c` wrapper** - Ensures proper shell evaluation
3. ✅ **Wait for window event** - Apps take time to start
4. ✅ **Check workspace assignment** - Verify window appears on `preferred_workspace`
5. ✅ **Validate window properties** - Check `app_id` matches `expected_class`

**Best Practice**: Always test via `app-launcher-wrapper.sh` to ensure full integration testing of the launch pipeline.
