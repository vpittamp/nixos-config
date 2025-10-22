# Quick Start Guide: i3pm Deno CLI

**Feature**: Complete i3pm Deno CLI with Extensible Architecture
**Version**: 2.0.0
**Date**: 2025-10-22

---

## Prerequisites

- NixOS system with i3 window manager
- i3-project-event-daemon running (`systemctl --user status i3-project-event-listener`)
- i3pm binary installed via home-manager

---

## Installation

### 1. Compile Deno CLI to Binary

```bash
cd /etc/nixos/home-modules/tools/i3pm-deno

# Compile TypeScript to standalone executable
deno compile \
  --allow-net \
  --allow-read=/run/user,/home \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  --output=i3pm \
  main.ts
```

### 2. Integrate into NixOS Configuration

```nix
# home-modules/tools/i3pm-deno.nix
{ config, lib, pkgs, ... }:

{
  home.packages = [
    (pkgs.stdenv.mkDerivation {
      pname = "i3pm";
      version = "2.0.0";
      src = /etc/nixos/home-modules/tools/i3pm-deno;

      nativeBuildInputs = [ pkgs.deno ];

      buildPhase = ''
        deno compile \
          --allow-net \
          --allow-read=/run/user,/home \
          --allow-env=XDG_RUNTIME_DIR,HOME,USER \
          --output=i3pm \
          main.ts
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp i3pm $out/bin/
      '';

      meta = {
        description = "i3 project management CLI tool";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
      };
    })
  ];
}
```

### 3. Rebuild NixOS

```bash
sudo nixos-rebuild switch --flake .#hetzner
# Or for home-manager only:
home-manager switch --flake .#<user>@<host>
```

### 4. Verify Installation

```bash
i3pm --version
# Expected output: i3pm 2.0.0

i3pm --help
# Expected output: Usage information
```

---

## Quick Start

### Project Switching (User Story 1 - Priority P1)

```bash
# List all configured projects
i3pm project list
# Output:
#   Projects:
#   - nixos (NixOS) /etc/nixos
#   - stacks (Stacks) /home/user/projects/stacks
#   - personal (Personal) /home/user/personal

# Check current project
i3pm project current
# Output: nixos

# Switch to different project
i3pm project switch stacks
# Output: Switched to project: stacks
#         Hidden 5 windows, shown 3 windows

# Clear project (global mode)
i3pm project clear
# Output: Cleared project context (global mode)
#         Shown 5 windows
```

**Expected Behavior**:
- Project switch completes in <2 seconds
- Windows immediately hide/show based on project scope
- i3bar indicator updates to show active project name

---

### Window State Visualization (User Story 2 - Priority P2)

```bash
# Tree view (default)
i3pm windows
# Output:
#   📺 Virtual-1 (1920x1080, primary)
#     Workspace 1 (focused)
#       ● Ghostty - nvim [nixos] 🔸
#       Firefox - GitHub
#     Workspace 2
#       VS Code - /etc/nixos [nixos] 🔸

# Table view
i3pm windows --table
# Output:
#   ID              Class    Title             WS  Output      Project  Status
#   94608348372768  Ghostty  nvim              1   Virtual-1   nixos    ●🔸
#   94608348373000  firefox  GitHub            1   Virtual-1   -        ●
#   94608348373100  code     /etc/nixos        2   Virtual-1   nixos    🔸

# JSON output (for scripting)
i3pm windows --json | jq '.outputs[0].workspaces[0].windows[0].title'
# Output: "nvim"

# Live TUI (real-time updates)
i3pm windows --live
# Interactive TUI launches:
# - Tab: Switch between tree/table view
# - H: Toggle hidden windows
# - Q: Quit
# - Ctrl+C: Exit
```

**Expected Behavior**:
- Tree/table views render instantly (<300ms)
- Live TUI updates within 100ms of window events
- Keyboard shortcuts respond immediately

---

### Project Configuration (User Story 3 - Priority P3)

```bash
# Create new project
i3pm project create \
  --name myproject \
  --dir /home/user/projects/myproject \
  --icon "" \
  --display-name "My Project"
# Output: Created project: myproject

# Show project details
i3pm project show nixos
# Output:
#   Project: nixos
#   Display Name: NixOS
#   Icon:
#   Directory: /etc/nixos
#   Scoped Classes: Ghostty, code-url-handler
#   Created: 2024-10-22 10:00:00
#   Last Used: 2024-10-22 15:30:00

# List all projects
i3pm project list

# Validate all projects
i3pm project validate
# Output: All projects valid (3 projects checked)

# Delete project
i3pm project delete oldproject
# Output: Deleted project: oldproject
```

**Expected Behavior**:
- Project creation takes <1 second
- Validation checks directory existence and config format
- Deletion does not affect windows (only removes config)

---

### Daemon Status and Events (User Story 4 - Priority P4)

```bash
# Check daemon status
i3pm daemon status
# Output:
#   Daemon Status:
#     Status: running
#     Connected to i3: yes
#     Uptime: 3600 seconds (1 hour)
#     Active Project: nixos
#     Windows: 8
#     Workspaces: 9
#     Events Processed: 1523
#     Errors: 0
#     Version: 1.0.0
#     Socket: /run/user/1000/i3-project-daemon/ipc.sock

# Show recent events
i3pm daemon events
# Output:
#   Recent Events (last 20):
#   [1523] 2024-10-22 15:30:45 - window:focus - Ghostty (nvim)
#   [1522] 2024-10-22 15:30:44 - window:title - Firefox (GitHub)
#   [1521] 2024-10-22 15:30:40 - workspace:focus - Workspace 2
#   ...

# Filter events by type
i3pm daemon events --type=window --limit=50
# Output: 50 most recent window events

# Show events since specific ID
i3pm daemon events --since-id=1500
# Output: Events 1501-1523
```

**Expected Behavior**:
- Status query responds in <500ms
- Events are displayed in reverse chronological order (newest first)
- Daemon unavailable errors show actionable systemctl command

---

### Window Classification (User Story 5 - Priority P5)

```bash
# List all classification rules
i3pm rules list
# Output:
#   Window Classification Rules:
#   1. Ghostty → scoped (priority: 100)
#   2. firefox → global (priority: 50)
#   3. code-url-handler → scoped (priority: 100)

# Test window classification
i3pm rules classify --class Ghostty --instance ghostty
# Output:
#   Classification Result:
#     Class: Ghostty
#     Instance: ghostty
#     Scope: scoped
#     Matched Rule: Ghostty (priority 100)

# Validate rules
i3pm rules validate
# Output: All rules valid (3 rules checked)

# Test rule matching
i3pm rules test --class Firefox
# Output:
#   Matching Rules:
#   1. firefox → global (priority: 50)
#   Final Classification: global

# Show application classes
i3pm app-classes
# Output:
#   Scoped Applications:
#   -  Ghostty (Ghostty Terminal)
#   -  code-url-handler (VS Code)
#
#   Global Applications:
#   -  firefox (Firefox Browser)
#   -  YouTube (YouTube PWA)
```

**Expected Behavior**:
- Rule listing responds in <500ms
- Classification test shows matched rule and final scope
- Validation checks regex patterns and rule conflicts

---

### Interactive Monitor Dashboard (User Story 6 - Priority P6)

```bash
# Launch interactive monitoring dashboard
i3pm monitor
# Interactive TUI launches with multiple panes:
# +-------------------+-------------------+
# | Daemon Status     | Event Stream      |
# | (real-time)       | (scrolling)       |
# +-------------------+-------------------+
# | Window State      |                   |
# | (tree/table)      |                   |
# +--------------------------------------- +
#
# Keyboard shortcuts:
# - Q: Quit
# - Ctrl+C: Exit
# - Tab: Switch focus between panes
```

**Expected Behavior**:
- Dashboard launches in <1 second
- All panes update in real-time (<250ms refresh)
- Terminal state fully restored on exit

---

## Common Workflows

### Workflow 1: Start Working on a Project

```bash
# 1. List available projects
i3pm project list

# 2. Switch to project
i3pm project switch nixos

# 3. Verify active project
i3pm project current
# Output: nixos

# 4. Check visible windows
i3pm windows
# Shows only nixos-scoped windows and global windows
```

**Time to Complete**: <5 seconds

---

### Workflow 2: Debug Window Visibility Issue

```bash
# 1. Check current project
i3pm project current

# 2. Show all windows including hidden
i3pm windows --live
# Press 'H' to toggle hidden windows

# 3. Identify window classification
i3pm rules classify --class <window-class>

# 4. Check daemon events for recent changes
i3pm daemon events --type=window --limit=20

# 5. Verify daemon is running
i3pm daemon status
```

**Time to Complete**: <2 minutes

---

### Workflow 3: Create New Project

```bash
# 1. Create project configuration
i3pm project create \
  --name newproject \
  --dir /home/user/projects/newproject \
  --icon "" \
  --display-name "New Project"

# 2. Verify creation
i3pm project show newproject

# 3. Switch to new project
i3pm project switch newproject

# 4. Confirm windows are scoped correctly
i3pm windows
```

**Time to Complete**: <30 seconds

---

### Workflow 4: Monitor System in Real-Time

```bash
# Option 1: Live window monitoring
i3pm windows --live
# Watch window events as they happen

# Option 2: Event stream monitoring
i3pm daemon events --follow  # (if implemented)
# Watch daemon events in real-time

# Option 3: Full dashboard
i3pm monitor
# Multi-pane view of daemon status, events, windows
```

**Use Case**: Debugging window management issues, understanding event flow

---

## Troubleshooting

### Issue: Daemon Not Running

**Symptoms**:
```bash
i3pm daemon status
# Output: Error: Failed to connect to daemon at /run/user/1000/i3-project-daemon/ipc.sock
#         Ensure daemon is running: systemctl --user start i3-project-event-listener
```

**Solution**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Start daemon if stopped
systemctl --user start i3-project-event-listener

# Enable daemon to start on login
systemctl --user enable i3-project-event-listener

# Retry CLI command
i3pm daemon status
```

---

### Issue: Windows Not Hiding on Project Switch

**Symptoms**:
- Switch to project but all windows remain visible

**Diagnosis**:
```bash
# 1. Verify project switch occurred
i3pm project current

# 2. Check window marks
i3pm windows --json | jq '.outputs[0].workspaces[0].windows[0].marks'

# 3. Verify daemon processed switch
i3pm daemon events --type=tick --limit=5

# 4. Check window classification
i3pm rules classify --class <window-class>
```

**Solutions**:
- Daemon may not have processed tick event - restart daemon
- Window class may not be in scoped_classes - verify with `i3pm rules classify`
- Window may be global - check with `i3pm app-classes`

---

### Issue: Terminal UI Not Restoring Properly

**Symptoms**:
- Cursor remains hidden after exiting live TUI
- Terminal still in raw mode

**Solution**:
```bash
# Restore cursor visibility
echo -e "\x1b[?25h"

# Restore terminal mode
reset

# If terminal is completely broken
tput reset
```

---

### Issue: Command Hangs or Times Out

**Symptoms**:
- CLI command hangs for >5 seconds
- Error: "Request timeout"

**Diagnosis**:
```bash
# Check daemon is responsive
systemctl --user status i3-project-event-listener

# Check daemon logs
journalctl --user -u i3-project-event-listener -n 50

# Test socket manually
echo '{"jsonrpc":"2.0","method":"get_status","id":1}' | \
  nc -U /run/user/$(id -u)/i3-project-daemon/ipc.sock
```

**Solutions**:
- Daemon may be deadlocked - restart with `systemctl --user restart i3-project-event-listener`
- Socket permissions may be wrong - check with `ls -l $XDG_RUNTIME_DIR/i3-project-daemon/`
- Multiple clients may be overwhelming daemon - disconnect other clients

---

## Performance Expectations

| Operation | Expected Time | Requirement |
|-----------|---------------|-------------|
| CLI Startup | <300ms | SC-003 |
| Project Switch | <2 seconds | SC-001 |
| Window State Query | <500ms | - |
| Live TUI Update | <100ms | FR-030, SC-004 |
| Event Processing | <100ms | - |
| Binary Size | <20MB | SC-002 |
| Memory Usage (live) | <50MB | SC-005 |

---

## Shell Aliases (Optional)

Add to `~/.bashrc` or `~/.config/fish/config.fish`:

```bash
# Project management shortcuts
alias pswitch='i3pm project switch'
alias pclear='i3pm project clear'
alias plist='i3pm project list'
alias pcurrent='i3pm project current'

# Window visualization shortcuts
alias iwin='i3pm windows'
alias iwinlive='i3pm windows --live'
alias iwintable='i3pm windows --table'

# Daemon monitoring shortcuts
alias dstatus='i3pm daemon status'
alias devents='i3pm daemon events'
```

---

## Next Steps

1. **Explore Projects**: Use `i3pm project list` to see configured projects
2. **Try Project Switching**: Practice with `i3pm project switch <name>`
3. **Visualize Windows**: Experiment with different output formats (`--tree`, `--table`, `--live`)
4. **Monitor Real-Time**: Launch `i3pm windows --live` and open/close windows
5. **Create Custom Project**: Use `i3pm project create` for your workflow
6. **Set Up Aliases**: Add shell aliases for frequently used commands

---

## Additional Resources

- **Full Specification**: See `spec.md` for complete requirements
- **Data Model**: See `data-model.md` for TypeScript type definitions
- **API Contract**: See `contracts/json-rpc-api.md` for daemon protocol
- **Implementation Plan**: See `plan.md` for architecture details
- **Constitution**: See `.specify/memory/constitution.md` for development principles

---

## Feedback

Report issues or suggestions at: (GitHub issues link or contact info)

---

**Last Updated**: 2025-10-22
**Document Version**: 1.0.0
