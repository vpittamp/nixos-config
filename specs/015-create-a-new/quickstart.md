# Quickstart: Event-Based i3 Project Synchronization

**Feature**: 015-create-a-new
**Last Updated**: 2025-10-20

## Overview

This feature replaces the polling-based i3 project management system with an event-driven architecture. A long-running daemon maintains a persistent IPC connection to i3 and processes window/workspace events in real-time, eliminating race conditions and polling delays.

---

## What's New

### Before (Polling-Based)

- Window detection: Poll every 0.5s for up to 10 seconds
- Project switch: Update file + signal i3blocks + sleep 0.1s
- Status bar: Poll file on SIGRTMIN+10 signal
- Race conditions: File writes vs. signal delivery timing issues

### After (Event-Driven)

- Window detection: Instant via `window::new` event (<100ms)
- Project switch: Tick event → daemon processes → windows show/hide (<200ms)
- Status bar: Query daemon state (no polling needed)
- No race conditions: Events fire after state changes complete

### Performance Improvements

| Metric | Before | After |
|--------|--------|-------|
| Window marking | 0.5-10s (polling) | <100ms (event-based) |
| Project switch | 200-500ms (file+signal) | <200ms (IPC) |
| Status bar update | Signal-based (delays) | Query daemon (instant) |
| CPU usage (idle) | 2-5% (constant polling) | <1% (event-driven) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  i3 Window Manager                                      │
│  - Sends events: window, workspace, tick, shutdown     │
└────────────────┬───────────────────────────────────────┘
                 │ IPC Connection
                 │ (UNIX socket)
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Event Listener Daemon (systemd user service)          │
│  - Maintains persistent i3 IPC connection               │
│  - Processes events in real-time                        │
│  - Maintains in-memory state (window→project mappings)  │
│  - Exposes IPC socket for CLI queries                   │
└────────────────┬───────────────────────────────────────┘
                 │ JSON-RPC IPC
                 │ (UNIX socket)
                 ▼
┌─────────────────────────────────────────────────────────┐
│  CLI Tools & Status Bars                                │
│  - i3-project-switch, i3-project-list, etc.             │
│  - i3blocks project indicator                           │
│  - Query daemon for state (no polling)                  │
└─────────────────────────────────────────────────────────┘
```

---

## Installation

### Prerequisites

- NixOS with i3 window manager v4.20+
- home-manager

### Enable the Feature

Add to your home-manager configuration:

```nix
# home.nix or appropriate configuration file
{
  imports = [
    ./home-modules/desktop/i3-project-daemon.nix
  ];

  services.i3ProjectEventListener = {
    enable = true;
    logLevel = "INFO";  # or "DEBUG" for troubleshooting
  };
}
```

### Rebuild Configuration

```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply configuration
sudo nixos-rebuild switch --flake .#hetzner
```

### Verify Installation

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Should show:
# Active: active (running)

# Check daemon connection to i3
i3-project-daemon-status

# Should show:
# Connection: Connected
# Status: connected
```

---

## Quick Start Guide

### 1. View Current Project

```bash
i3-project-current

# Output:
# Active project: nixos (NixOS)
# Directory: /etc/nixos
# Windows: 5
```

Short alias:
```bash
pcurrent
```

### 2. List All Projects

```bash
i3-project-list

# Output:
# Projects:
#   [*]  nixos     NixOS           /etc/nixos              5 windows
#   [ ]   stacks    Stacks          ~/projects/stacks       0 windows
```

Short alias:
```bash
plist
```

### 3. Switch Projects

Via rofi (Win+P):
- Press `Win+P`
- Select project from menu
- Instantly switches (no delays)

Via CLI:
```bash
i3-project-switch stacks

# Output:
# Switched to project: stacks
# Hidden 5 windows from project: nixos
# Shown 0 windows from project: stacks
```

Short alias:
```bash
pswitch stacks
```

Clear active project (global mode):
```bash
i3-project-switch --clear
# or
pswitch -c
```

### 4. Create New Project

```bash
i3-project-create \
  --name=myproject \
  --dir=/home/user/projects/myproject \
  --display-name="My Project" \
  --icon=""

# Output:
# Created project: myproject
#   Display name: My Project
#   Directory: /home/user/projects/myproject
#   Icon:
#   Config file: /home/user/.config/i3/projects/myproject.json
```

### 5. Launch Applications in Project Context

When a project is active, project-scoped applications are automatically associated:

```bash
# Switch to nixos project
i3-project-switch nixos

# Launch VS Code (Win+C or via CLI)
code /etc/nixos

# Window is automatically marked with "project:nixos"
# Stays visible only when nixos project is active
```

Scoped applications (auto-marked):
- **VS Code** (`Code`)
- **Ghostty terminal** (`org.kde.ghostty`)
- **Alacritty terminal** (`Alacritty`)
- **Yazi file manager** (`Yazi`)
- **Lazygit** (via terminal)

Global applications (always visible):
- **Firefox** (`firefox`)
- **YouTube Music PWA** (`youtube-music`)
- **K9s** (`k9s`)
- **Google AI Studio PWA** (`google-ai-studio`)

---

## Keybindings

Default i3 keybindings (configured via home-manager):

| Key | Action |
|-----|--------|
| `Win+P` | Open project switcher (rofi) |
| `Win+Shift+P` | Clear active project (global mode) |
| `Win+C` | Launch VS Code in project context |
| `Win+Return` | Launch Ghostty terminal with sesh session |
| `Win+G` | Launch lazygit in project repository |
| `Win+Y` | Launch yazi file manager in project directory |

---

## Common Tasks

### Check Daemon Status

```bash
i3-project-daemon-status

# Output:
# i3 Project Event Listener Daemon Status
#
# Connection:
#   Status: Connected
#   i3 socket: /run/user/1000/i3/ipc-socket.12345
#   Uptime: 1h 23m 45s
#
# Events:
#   Total processed: 1,234
#   Errors: 0
#   Subscriptions: window, workspace, tick, shutdown
#
# Active Project:
#   Name: nixos (NixOS)
#   Windows: 5 tracked
```

### View Recent Events (Diagnostics)

```bash
i3-project-daemon-events --limit=10

# Output:
# Recent Events (last 10):
#
# 2025-10-20 10:35:12  window::new       window_id=94557896564  class=Code       ✓
# 2025-10-20 10:35:11  window::mark      window_id=94557896564  mark=project:nixos  ✓
# 2025-10-20 10:35:05  workspace::focus  workspace=1            ✓
# 2025-10-20 10:34:58  tick              payload=project:nixos  ✓
```

### Reload Project Configurations

After manually editing project JSON files:

```bash
i3-project-daemon-reload

# Output:
# Reloading daemon configuration...
# Loaded 3 projects
#   ✓ nixos
#   ✓ stacks
#   ✓ personal
#
# Reload complete
```

### Edit Project Configuration

```bash
i3-project-edit nixos

# Opens ~/.config/i3/projects/nixos.json in $EDITOR
```

### Validate Project Configurations

```bash
i3-project-validate

# Output:
# Validating projects...
# ✓ nixos: Valid
# ✓ stacks: Valid
# ✓ personal: Valid
#
# All projects valid (3/3)
```

---

## Configuration Files

### Project Configuration

**Location**: `~/.config/i3/projects/{project_name}.json`

**Example** (`~/.config/i3/projects/nixos.json`):
```json
{
  "name": "nixos",
  "display_name": "NixOS",
  "icon": "",
  "directory": "/etc/nixos",
  "created": "2025-10-20T10:00:00Z",
  "last_active": "2025-10-20T10:35:12Z"
}
```

### Application Classification

**Location**: `~/.config/i3/app-classes.json`

**Purpose**: Define which window classes are project-scoped vs. global

**Example**:
```json
{
  "scoped_classes": [
    "Code",
    "Alacritty",
    "org.kde.ghostty",
    "Yazi",
    "org.gnome.Nautilus"
  ],
  "global_classes": [
    "firefox",
    "chromium-browser",
    "youtube-music",
    "k9s",
    "google-ai-studio"
  ]
}
```

### Active Project State

**Location**: `~/.config/i3/active-project.json`

**Purpose**: Persists active project across daemon restarts

**Example**:
```json
{
  "project_name": "nixos",
  "activated_at": "2025-10-20T10:30:00Z",
  "previous_project": "stacks"
}
```

**Note**: Daemon is source of truth during runtime. File is only read on startup.

---

## Troubleshooting

### Daemon Not Running

**Symptom**: `i3-project-current` returns "Error: Daemon not running"

**Solution**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# If inactive, start it
systemctl --user start i3-project-event-listener

# If failed, check logs
journalctl --user -u i3-project-event-listener -n 50
```

### Windows Not Auto-Marked

**Symptom**: New windows don't get project marks

**Diagnosis**:
```bash
# Check recent events
i3-project-daemon-events --limit=20 --type=window

# Should see window::new and window::mark events

# Check if window class is in scoped_classes
cat ~/.config/i3/app-classes.json | jq '.scoped_classes'
```

**Solution**:
1. Add window class to `app-classes.json` scoped_classes
2. Reload daemon: `i3-project-daemon-reload`
3. Test with new window

### Project Switch Delays

**Symptom**: Project switch takes >500ms

**Diagnosis**:
```bash
# Check daemon status for errors
i3-project-daemon-status

# Check event processing
i3-project-daemon-events --limit=50 | grep -E 'tick|✗'
```

**Common Causes**:
- i3 IPC connection issues (check daemon logs)
- Many windows (50+) to hide/show (expected <200ms for 50 windows)
- Daemon errors (check error_count in status)

### Status Bar Not Updating

**Symptom**: i3blocks project indicator shows wrong project

**Solution**:
1. i3blocks now queries daemon instead of file
2. Check i3blocks script: `cat /path/to/i3blocks/scripts/project.sh`
3. Verify it calls `i3-project-current --format=icon` or daemon IPC
4. Reload i3blocks: `pkill -SIGUSR1 i3blocks`

---

## Migration from Old System

### Compatibility

**Preserved**:
- CLI command names (i3-project-switch, i3-project-list, etc.)
- Keybindings (Win+P for project switcher)
- Project JSON file format (mostly compatible)

**Changed**:
- Window tracking: File-based → mark-based (automatic)
- Status bar updates: Signal-based → query-based (update i3blocks script)
- New window detection: Polling → event-based (transparent)

### Migration Steps

1. **Backup existing configs**:
   ```bash
   cp -r ~/.config/i3/projects ~/.config/i3/projects.backup
   ```

2. **Extract scoped applications** from project configs into centralized `app-classes.json`:
   ```bash
   # Manual step: Review all projects/*.json and consolidate scoped_applications
   # into ~/.config/i3/app-classes.json
   ```

3. **Enable new system** via home-manager:
   ```nix
   services.i3ProjectEventListener.enable = true;
   ```

4. **Rebuild and start daemon**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   systemctl --user start i3-project-event-listener
   ```

5. **Mark existing windows** (one-time):
   ```bash
   # Switch to each project to mark windows
   i3-project-switch nixos
   # Windows will be automatically marked on next creation

   # Or manually mark existing windows
   i3-msg '[class="Code"] mark --add project:nixos'
   ```

6. **Update i3blocks script** (if using i3blocks):
   ```bash
   # Replace file polling with daemon query
   # Edit: home-modules/desktop/i3blocks/scripts/project.sh
   # Change from: cat ~/.config/i3/active-project.json
   # To: i3-project-current --format=icon
   ```

7. **Test functionality**:
   ```bash
   i3-project-daemon-status
   i3-project-list
   i3-project-switch nixos
   # Launch new window and verify auto-marking
   ```

---

## Advanced Usage

### Custom Daemon Socket Path

For testing or custom deployments:

```bash
export I3_PROJECT_DAEMON_SOCKET=/tmp/test-daemon.sock
i3-project-current
```

### Query Daemon via IPC (Scripting)

```bash
# Direct IPC query
echo '{"jsonrpc":"2.0","id":1,"method":"get_status"}' | \
  nc -U "$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock" | \
  jq '.result'
```

### Monitor Events in Real-Time

```bash
# Watch last 10 events (refreshes every second)
watch -n 1 'i3-project-daemon-events --limit=10'
```

### Debug Mode Logging

```nix
services.i3ProjectEventListener.logLevel = "DEBUG";
```

Then rebuild and check logs:
```bash
journalctl --user -u i3-project-event-listener -f
```

---

## Performance Metrics

Expected performance on modern hardware (tested on Hetzner CPX21):

| Operation | Latency | Notes |
|-----------|---------|-------|
| Window creation → marked | <100ms | 95th percentile |
| Project switch | <200ms | For 50 windows |
| Event processing | <10ms | Most events |
| Daemon memory usage | 10-15MB | Idle state |
| Daemon CPU usage | <1% | Idle state |

---

## FAQ

### Q: Do I need to restart i3 after enabling the daemon?

A: No, but you need to reload the home-manager configuration and start the daemon service:
```bash
home-manager switch
systemctl --user start i3-project-event-listener
```

### Q: What happens if the daemon crashes?

A: Systemd automatically restarts it (configured with `Restart=on-failure`). Your project configuration is preserved. Windows may lose marks, but they'll be re-marked when you switch projects or create new windows.

### Q: Can I use both the old and new systems?

A: No, they conflict. The new system replaces the old polling-based approach. Disable the old system before enabling the daemon.

### Q: How do I add a new window class to project-scoped applications?

A: Edit `~/.config/i3/app-classes.json`, add the class to `scoped_classes`, then run:
```bash
i3-project-daemon-reload
```

### Q: Do window marks persist across i3 restarts?

A: Yes, marks are stored in i3's layout state and survive restarts. The daemon rebuilds its in-memory state from marks on reconnection.

### Q: Can I manually mark windows with projects?

A: Yes, the daemon detects manual mark changes:
```bash
i3-msg '[class="Code"] mark --add project:nixos'
```

The daemon's `window::mark` event handler will update its internal tracking.

---

## Support & Feedback

### View Logs

```bash
# Real-time logs
journalctl --user -u i3-project-event-listener -f

# Last 100 lines
journalctl --user -u i3-project-event-listener -n 100

# Errors only
journalctl --user -u i3-project-event-listener -p err
```

### Restart Daemon

```bash
systemctl --user restart i3-project-event-listener
```

### Disable Daemon

```nix
services.i3ProjectEventListener.enable = false;
```

Then rebuild:
```bash
home-manager switch
```

---

## Next Steps

- Read the [data model documentation](./data-model.md) for architecture details
- Review [daemon IPC contract](./contracts/daemon-ipc.md) for programmatic access
- Check [CLI interface contract](./contracts/cli-interface.md) for all commands
- Explore [i3 events contract](./contracts/i3-events.md) for event handling details

---

**Feature Version**: 1.0.0
**Last Updated**: 2025-10-20
