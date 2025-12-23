# Application Launching Reference

Complete reference for the unified application launching system.

## Contents

- [Overview](#overview)
- [App Launcher Wrapper](#app-launcher-wrapper)
- [Application Registry](#application-registry)
- [PWA Configuration](#pwa-configuration)
- [Environment Variables](#environment-variables)
- [Daemon Integration](#daemon-integration)
- [Testing and Debugging](#testing-and-debugging)

## Overview

All applications launch through `app-launcher-wrapper.sh` which provides:
1. Registry-based configuration lookup
2. I3PM_* environment variable injection
3. Pre-launch daemon notification
4. Sway exec for proper lifecycle
5. Project context propagation

### Launch Flow

```
app-launcher-wrapper.sh <app-name>
        │
        ▼
┌───────────────────────┐
│ Read application-     │
│ registry.json         │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Read active-worktree  │
│ .json (if exists)     │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Substitute variables  │
│ in parameters         │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Notify daemon         │
│ (launch notification) │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Execute via           │
│ swaymsg exec          │
└───────────────────────┘
```

## App Launcher Wrapper

### Location
Script: `scripts/app-launcher-wrapper.sh`
Installed at: `~/.config/i3/app-launcher-wrapper.sh` (symlinked to PATH)

### Usage

```bash
# Basic launch
app-launcher-wrapper.sh <app-name>

# Examples
app-launcher-wrapper.sh terminal
app-launcher-wrapper.sh code
app-launcher-wrapper.sh firefox
app-launcher-wrapper.sh claude-pwa

# Dry run (show resolved command)
DRY_RUN=1 app-launcher-wrapper.sh terminal

# Debug mode (verbose logging)
DEBUG=1 app-launcher-wrapper.sh terminal
```

### Configuration Files

| File | Purpose |
|------|---------|
| `~/.config/i3/application-registry.json` | App definitions |
| `~/.config/i3/active-worktree.json` | Current project context |

### Log File
Location: `~/.local/state/app-launcher.log`
Rotation: 1000 lines max

## Application Registry

### Location
Source: `home-modules/desktop/app-registry-data.nix`
Generated: `~/.config/i3/application-registry.json`

### Application Definition

```nix
(mkApp {
  name = "terminal";              # Unique identifier (kebab-case)
  display_name = "Terminal";      # Human-readable name
  command = "ghostty";            # Executable
  parameters = "-e sesh connect $PROJECT_DIR";  # Arguments with variables
  scope = "scoped";               # "scoped" or "global"
  expected_class = "com.mitchellh.ghostty";     # Window class for validation
  preferred_workspace = 1;        # Target workspace (1-50 regular, 50+ PWAs)
  preferred_monitor_role = "primary";  # "primary", "secondary", "tertiary"
  icon = iconPath "tmux-original.svg";  # Icon path or GTK name
  nix_package = "pkgs.ghostty";   # Nix package reference
  multi_instance = true;          # Allow multiple instances
  fallback_behavior = "use_home"; # "skip", "use_home", "error"
  terminal = true;                # Is terminal app (auto-detected)
  description = "Terminal with sesh session management";
})
```

### Scope Types

| Scope | Behavior |
|-------|----------|
| `scoped` | Uses project directory, hidden on project switch |
| `global` | Always visible, uses HOME for working directory |

### Fallback Behaviors

| Value | When no project active |
|-------|----------------------|
| `skip` | Remove project variables from parameters |
| `use_home` | Substitute HOME for PROJECT_DIR |
| `error` | Fail with error message |

### Parameter Variables

| Variable | Substituted With |
|----------|-----------------|
| `$PROJECT_DIR` | Active worktree directory |
| `$PROJECT_NAME` | Qualified project name |
| `$SESSION_NAME` | Tmux session name |
| `$HOME` | User home directory |
| `$WORKSPACE` | Preferred workspace number |
| `$PROJECT_DISPLAY_NAME` | Human-readable project name |
| `$PROJECT_ICON` | Project icon |

### JSON Format

```json
{
  "applications": [
    {
      "name": "terminal",
      "display_name": "Terminal",
      "command": "ghostty",
      "parameters": ["-e", "sesh", "connect", "$PROJECT_DIR"],
      "scope": "scoped",
      "expected_class": "com.mitchellh.ghostty",
      "preferred_workspace": 1,
      "preferred_monitor_role": "primary",
      "icon": "/nix/store/.../icons/tmux-original.svg",
      "nix_package": "pkgs.ghostty",
      "multi_instance": true,
      "fallback_behavior": "use_home",
      "terminal": true,
      "description": "Terminal with sesh session management",
      "floating": false,
      "floating_size": null,
      "scratchpad": false
    }
  ]
}
```

## PWA Configuration

### Location
Source: `shared/pwa-sites.nix`

### PWA Definition

```nix
{
  name = "Claude";                    # Display name
  url = "https://claude.ai/code";     # Launch URL
  domain = "claude.ai";               # Primary domain
  icon = iconPath "claude.svg";       # Icon path
  description = "Claude AI Assistant by Anthropic";
  categories = "Network;Development;";
  keywords = "ai;claude;anthropic;assistant;";
  scope = "https://claude.ai/";       # PWA scope URL
  ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Deterministic FFPWA ID

  # App registry metadata
  app_scope = "scoped";               # "scoped" or "global"
  preferred_workspace = 52;           # Workspace number (50+ for PWAs)
  preferred_monitor_role = "secondary";

  # URL routing (Feature 113)
  routing_domains = [ "claude.ai" "www.claude.ai" ];

  # Path-based routing (Feature 118)
  routing_paths = [ "/ai" ];          # For path-specific PWAs

  # Auth domains (Feature 118)
  auth_domains = [ "accounts.google.com" ];  # SSO/OAuth domains
}
```

### ULID (Unique Lexicographically Sortable Identifier)

Each PWA has a deterministic ULID that:
- Becomes the FFPWA profile ID
- Determines window class: `FFPWA-{ULID}`
- Enables cross-machine portability

### PWA App Names
PWAs are launched with `-pwa` suffix:
```bash
app-launcher-wrapper.sh claude-pwa
app-launcher-wrapper.sh youtube-pwa
app-launcher-wrapper.sh github-pwa
```

### Window Class Pattern
```
FFPWA-{ULID}
Example: FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5
```

## Environment Variables

### I3PM Variables Injected

| Variable | Description | Example |
|----------|-------------|---------|
| `I3PM_APP_ID` | Unique instance ID | `terminal-nixos-12345-1703344800` |
| `I3PM_APP_NAME` | Registry app name | `terminal` |
| `I3PM_PROJECT_NAME` | Active project | `vpittamp/nixos-config/134-feature` |
| `I3PM_PROJECT_DIR` | Project directory | `/home/user/repos/...` |
| `I3PM_PROJECT_DISPLAY_NAME` | Display name | `134-feature` |
| `I3PM_PROJECT_ICON` | Project icon | `` |
| `I3PM_SCOPE` | App scope | `scoped` or `global` |
| `I3PM_ACTIVE` | Project active | `true` or `false` |
| `I3PM_LAUNCH_TIME` | Unix timestamp | `1703344800` |
| `I3PM_LAUNCHER_PID` | Launcher process ID | `12345` |
| `I3PM_TARGET_WORKSPACE` | Assigned workspace | `1` |
| `I3PM_EXPECTED_CLASS` | Expected window class | `com.mitchellh.ghostty` |

### Worktree Variables

| Variable | Description |
|----------|-------------|
| `I3PM_IS_WORKTREE` | Is git worktree | `true` |
| `I3PM_WORKTREE_BRANCH` | Branch name | `134-feature` |
| `I3PM_WORKTREE_ACCOUNT` | Git account | `vpittamp` |
| `I3PM_WORKTREE_REPO` | Repository name | `nixos-config` |
| `I3PM_FULL_BRANCH_NAME` | Full branch | `134-feature` |

### Git Metadata Variables

| Variable | Description |
|----------|-------------|
| `I3PM_GIT_BRANCH` | Current branch | `134-feature` |
| `I3PM_GIT_COMMIT` | Commit hash | `abc123...` |
| `I3PM_GIT_IS_CLEAN` | Clean working tree | `true` or `false` |
| `I3PM_GIT_AHEAD` | Commits ahead | `3` |
| `I3PM_GIT_BEHIND` | Commits behind | `0` |

### Layout Restore Variables

| Variable | Description |
|----------|-------------|
| `I3PM_RESTORE_MARK` | Mark for layout correlation | `project:app:id` |
| `I3PM_APP_ID_OVERRIDE` | Override app ID | `terminal-project-1` |

## Daemon Integration

### Launch Notification

Before executing, the wrapper sends a notification to the daemon:

```json
{
  "jsonrpc": "2.0",
  "method": "notify_launch",
  "params": {
    "app_name": "terminal",
    "project_name": "nixos-config",
    "project_directory": "/home/user/repos/...",
    "launcher_pid": 12345,
    "workspace_number": 1,
    "timestamp": 1703344800.123,
    "expected_class": "com.mitchellh.ghostty"
  },
  "id": 1
}
```

### Socket Communication

Socket: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

```bash
# The wrapper uses socat for IPC
timeout 1s bash -c "echo '$request' | socat - UNIX-CONNECT:$socket"
```

### Window Correlation

After launch notification:
1. Daemon stores pending launch in registry
2. Window appears (Sway event)
3. Daemon correlates using:
   - App class match
   - Time delta
   - Workspace match
4. Window marked with project context

## Testing and Debugging

### Dry Run Mode

```bash
DRY_RUN=1 app-launcher-wrapper.sh terminal
```

Output:
```
[DRY RUN] Would execute:
  Command: ghostty
  Arguments: -e sesh connect /home/user/repos/nixos-config
  Project: nixos-config (/home/user/repos/nixos-config)
  Full command: ghostty -e sesh connect /home/user/repos/nixos-config
```

### Debug Mode

```bash
DEBUG=1 app-launcher-wrapper.sh terminal
```

Shows verbose logging:
```
[DEBUG] Command: ghostty
[DEBUG] Parameters: -e sesh connect $PROJECT_DIR
[DEBUG] Scope: scoped
[DEBUG] Expected class: com.mitchellh.ghostty
[DEBUG] Project name: nixos-config
[DEBUG] Project directory: /home/user/repos/nixos-config
[DEBUG] Substituted $PROJECT_DIR -> /home/user/repos/nixos-config
[DEBUG] I3PM_APP_ID=terminal-nixos-12345-1703344800
...
```

### Log File

```bash
# View recent logs
tail -f ~/.local/state/app-launcher.log

# Search for errors
grep ERROR ~/.local/state/app-launcher.log
```

### Check Environment Variables

```bash
# Check process environment
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM

# Launch and capture env
app-launcher-wrapper.sh terminal &
sleep 2
pgrep ghostty | head -1 | xargs -I{} cat /proc/{}/environ | tr '\0' '\n' | grep I3PM
```

### Verify Window Class

```bash
# Get all window app_ids
swaymsg -t get_tree | jq -r '.. | .app_id? // empty' | sort -u

# Find specific window
swaymsg -t get_tree | jq '.. | select(.app_id == "com.mitchellh.ghostty")'
```

### Test Daemon Notification

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Watch daemon logs during launch
journalctl --user -u i3-project-event-listener -f &
app-launcher-wrapper.sh terminal
```

### Common Issues

**App not found in registry**:
```bash
# List available apps
jq '.applications[].name' ~/.config/i3/application-registry.json
```

**Command not found**:
```bash
# Check if command is in PATH
which <command>

# Verify Nix package is installed
nix-store -q --references /run/current-system/sw | grep <package>
```

**Project directory issues**:
```bash
# Check active worktree
cat ~/.config/i3/active-worktree.json | jq

# Clear project context
rm ~/.config/i3/active-worktree.json
```

**Daemon not responding**:
```bash
# Restart daemon
systemctl --user restart i3-project-event-listener

# Check socket
ls -la $XDG_RUNTIME_DIR/i3-project-daemon/
```

### Adding New Applications

1. Edit `home-modules/desktop/app-registry-data.nix`:
```nix
(mkApp {
  name = "my-new-app";
  display_name = "My New App";
  command = "my-app";
  parameters = "";
  scope = "global";
  expected_class = "MyApp";
  preferred_workspace = 8;
})
```

2. Rebuild NixOS:
```bash
sudo nixos-rebuild switch --flake .#<target>
```

3. Test:
```bash
app-launcher-wrapper.sh my-new-app
```

### Adding New PWAs

1. Edit `shared/pwa-sites.nix`:
```nix
{
  name = "My Service";
  url = "https://myservice.com";
  domain = "myservice.com";
  icon = iconPath "myservice.svg";
  description = "My Service description";
  categories = "Network;";
  keywords = "myservice;";
  scope = "https://myservice.com/";
  ulid = "01XXXXXXXXXXXXXXXXXXXXX";  # Generate with ulid tool
  app_scope = "global";
  preferred_workspace = 70;
  routing_domains = [ "myservice.com" "www.myservice.com" ];
}
```

2. Add icon to `assets/icons/myservice.svg`

3. Rebuild and install PWAs:
```bash
sudo nixos-rebuild switch --flake .#<target>
pwa-install-all
```

4. Test:
```bash
app-launcher-wrapper.sh my-service-pwa
```
