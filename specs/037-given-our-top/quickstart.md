# Quickstart: Unified Project-Scoped Window Management

**Feature**: 037-given-our-top | **Date**: 2025-10-25 | **Status**: Implementation Ready

## What This Feature Does

Automatically hides windows when you switch projects, showing only windows relevant to your active project and global applications. Windows restore to their exact workspaces when you return to a project.

**Key Benefits**:
- 🎯 **Focus**: See only windows for your active project
- 🚀 **Context switching**: Switch projects without window clutter
- 💾 **Workspace memory**: Windows return to where you left them
- 🌍 **Global apps**: Firefox, K9s stay visible across all projects

---

## Quick Examples

### Basic Project Switching (Automatic Filtering)

```bash
# Switch to nixos project (automatically hides other project windows)
i3pm project switch nixos

# Or use keybinding: Win+P → select "nixos"
```

**What Happens**:
1. All scoped windows from previous project hide (move to scratchpad)
2. Windows for "nixos" project restore to their workspaces
3. Global apps (Firefox, etc.) stay visible

---

### View Hidden Windows

```bash
# Show all hidden windows grouped by project
i3pm windows hidden

# Example output:
# [NixOS] (5 windows)
#   vscode       i3-project.nix - Visual Studio Code         → WS 2
#   terminal     vpittamp@hetzner: /etc/nixos                → WS 1
#   lazygit      /etc/nixos                                  → WS 7
#
# [Stacks] (3 windows)
#   vscode       backend/main.go - Visual Studio Code        → WS 2
#   terminal     ~/projects/stacks                           → WS 1
```

---

### Filter Hidden Windows

```bash
# Show hidden windows for specific project only
i3pm windows hidden --project=nixos

# Show hidden windows from workspace 2 only
i3pm windows hidden --workspace=2

# Show only VS Code windows that are hidden
i3pm windows hidden --app=vscode

# Get JSON output for scripting
i3pm windows hidden --format=json | jq '.total_hidden'
```

---

### Manual Window Restoration

```bash
# Restore all windows for a project
i3pm windows restore stacks

# Preview what would be restored (dry-run)
i3pm windows restore stacks --dry-run

# Restore specific window by ID
i3pm windows restore stacks --window-id=123456

# Restore all windows to workspace 5 (override tracked workspace)
i3pm windows restore stacks --workspace=5
```

---

### Inspect Window State

```bash
# Get detailed info about a window
i3pm windows inspect 123456

# Example output:
# Window 123456 State
#
# Basic Info:
#   Class: Code
#   Title: i3-project.nix - Visual Studio Code
#   PID: 12345
#
# Visibility:
#   Status: Hidden (in scratchpad)
#   Tracked Workspace: 2
#
# Project Association:
#   Project: nixos (NixOS)
#   Scope: scoped
```

---

### View All Windows Including Hidden

```bash
# Show tree view with hidden windows
i3pm windows --show-hidden

# Example output:
#  eDP-1 (Primary)
# ├── Workspace 1
# │   └── Ghostty (12345) [nixos] ●
# ├── Workspace 2
# │   └── Code (54321) [nixos]
# ├── Workspace 3
# │   └── Firefox (11111) [Global]
# └── Scratchpad
#     ├── Code (23456) [stacks] 🔒
#     └── Ghostty (34567) [stacks] 🔒
```

---

## Typical Workflows

### Multi-Project Development

**Scenario**: Working on NixOS config, need to switch to Stacks project

```bash
# 1. Currently in nixos project with 5 windows open (VS Code, terminals, lazygit)
i3pm project current
# Output: nixos

# 2. Switch to stacks project
i3pm project switch stacks
# Auto-hides: 5 nixos windows → scratchpad
# Auto-restores: 3 stacks windows → their workspaces

# 3. Work on stacks...

# 4. Return to nixos
i3pm project switch nixos
# Auto-hides: 3 stacks windows → scratchpad
# Auto-restores: 5 nixos windows → exact same workspaces as before
```

**Result**: Seamless context switching with zero manual window management

---

### Debugging Hidden Windows

**Scenario**: Windows unexpectedly hidden, need to find them

```bash
# 1. Check what's hidden
i3pm windows hidden

# 2. See which project they belong to
# Output shows project grouping

# 3. Check specific window details
i3pm windows inspect <window-id>

# 4. Manually restore if needed
i3pm windows restore <project-name>
```

---

### Custom Workspace Organization

**Scenario**: Want to move project windows to different workspaces

```bash
# 1. Switch to project
i3pm project switch nixos

# 2. Manually move windows with i3 (Win+Shift+<number>)
# Move VS Code to workspace 5 instead of default 2

# 3. System automatically tracks new location
# Next time you switch away and back, VS Code returns to WS 5

# 4. Verify tracking
i3pm windows hidden --project=nixos
# Shows: vscode → WS 5 (updated tracking)
```

---

### Global Mode (No Project Active)

**Scenario**: Working on ad-hoc tasks, no specific project context

```bash
# 1. Clear active project
i3pm project clear

# 2. All scoped windows hide
# Only global apps remain visible (Firefox, K9s, etc.)

# 3. Launch new applications
# Without active project, they're treated as global

# 4. Return to project
i3pm project switch nixos
# All nixos windows restore, ad-hoc global apps remain
```

---

## Keybindings (Default)

Add to `~/.config/i3/config`:

```
# Project switching (automatically filters windows)
bindsym $mod+p exec --no-startup-id i3pm project switch
bindsym $mod+Shift+p exec --no-startup-id i3pm project clear

# Show hidden windows
bindsym $mod+h exec --no-startup-id "alacritty -e bash -c 'i3pm windows hidden; read -p \"Press enter to close...\"'"

# Manual scratchpad toggle (for any window)
bindsym $mod+Shift+minus move scratchpad
bindsym $mod+minus scratchpad show
```

---

## Shell Aliases (Suggested)

Add to `~/.bashrc`:

```bash
# Window visibility
alias phidden='i3pm windows hidden'
alias prestore='i3pm windows restore'
alias pwinspect='i3pm windows inspect'

# Project management (already exists from Feature 015)
alias pswitch='i3pm project switch'
alias pcurrent='i3pm project current'
alias plist='i3pm project list'
alias pclear='i3pm project clear'
```

---

## Understanding Scope

### Scoped Applications (Hide When Project Inactive)

Applications launched via Walker/Elephant that are project-specific:

- **VS Code** (`vscode`) - Opens project directory
- **Terminal** (`terminal`) - Uses sesh session per project
- **Lazygit** (`lazygit`) - Opens project repository
- **Yazi** (`yazi`) - Opens project directory

**Behavior**: Hidden when you switch away from their project

---

### Global Applications (Always Visible)

Applications that aren't tied to a specific project:

- **Firefox** - Web browsing across all contexts
- **K9s** - Kubernetes monitoring
- **PWAs** (YouTube, Google AI, etc.)
- **System monitors**

**Behavior**: Remain visible across all project switches

---

### How Scope is Determined

Scope comes from the application registry (`app-registry.nix`):

```nix
{
  name = "vscode";
  scope = "scoped";      # Hides when project inactive
  # ...
}

{
  name = "firefox";
  scope = "global";      # Always visible
  # ...
}
```

**Environment Variables** (automatic):
- `I3PM_SCOPE=scoped` → Window hides with project
- `I3PM_SCOPE=global` → Window always visible

---

## Workspace Tracking

### How Tracking Works

1. **Initial Launch**: Application opens on `preferred_workspace` from registry
2. **Manual Move**: You drag window to different workspace (Win+Shift+<number>)
3. **Automatic Tracking**: System saves new workspace to `window-workspace-map.json`
4. **Restoration**: Window returns to last-known workspace when project reactivates

**File**: `~/.config/i3/window-workspace-map.json`

Example:
```json
{
  "windows": {
    "123456": {
      "workspace_number": 5,
      "project_name": "nixos",
      "app_name": "vscode",
      "last_seen": 1730000000.123
    }
  }
}
```

---

### Workspace Validation

When restoring windows, the system validates workspaces:

- ✅ **Valid workspace**: Window restores to tracked workspace
- ⚠️ **Invalid workspace**: Falls back to workspace 1 with warning
- 📺 **Monitor disconnected**: Falls back to primary monitor

**Example** (monitor disconnected):
```bash
i3pm windows restore nixos

# Output:
# ✓ vscode (123456) → Workspace 2
# ⚠ terminal (789012) → Workspace 1 (fallback from WS 5, monitor disconnected)
```

---

## Troubleshooting

### Windows Not Hiding

**Symptom**: Windows stay visible after project switch

**Check**:
```bash
# 1. Verify window has project association
i3pm windows inspect <window-id>

# Look for:
# Project Association:
#   Project: nixos (should match expected project)
#   Scope: scoped (should be "scoped" not "global")

# 2. Check daemon is running
systemctl --user status i3-project-event-listener

# 3. Check daemon logs
journalctl --user -u i3-project-event-listener -n 50
```

**Solutions**:
- If `scope=global`: Application is global by design, won't hide
- If `Project: <empty>`: Application launched without project context (pre-Feature-035)
- If daemon stopped: Restart with `systemctl --user restart i3-project-event-listener`

---

### Windows Not Restoring to Correct Workspace

**Symptom**: Windows restore to workspace 1 instead of tracked workspace

**Check**:
```bash
# 1. Check tracking file
cat ~/.config/i3/window-workspace-map.json | jq '.windows'

# 2. Verify workspace exists
i3pm monitors workspaces

# 3. Check for monitor disconnection
i3pm monitors status
```

**Solutions**:
- If workspace not tracked: Window hasn't been moved since tracking was enabled
- If monitor disconnected: System falls back to primary monitor (expected behavior)
- If tracking file corrupted: Delete file, daemon will reinitialize

---

### Hidden Windows Lost

**Symptom**: Windows disappeared after project switch

**Check**:
```bash
# 1. List all hidden windows
i3pm windows hidden

# 2. Check scratchpad directly
i3pm windows --show-hidden | grep Scratchpad

# 3. Query specific project
i3pm windows hidden --project=<name>
```

**Solutions**:
- Windows are in scratchpad, not lost: Use `i3pm windows restore <project>`
- Window closed unexpectedly: Check daemon logs for errors
- Process died: Window cleaned up automatically (expected behavior)

---

### Rapid Project Switching Issues

**Symptom**: Inconsistent window visibility after quick switches

**Explanation**: Daemon queues switch requests, processes sequentially

**Solution**: Wait for previous switch to complete (~300ms) before next switch

**Check queue status**:
```bash
i3pm daemon status | grep -A5 "Switch Queue"
```

---

### Manual Scratchpad Conflicts

**Symptom**: Manually scratchpadded windows interfere with project filtering

**Understanding**:
- Daemon manages project-scoped windows in scratchpad
- User-initiated scratchpad moves (Win+Shift+minus) are independent
- Daemon tracks daemon-managed windows separately

**Behavior**:
- Project switch won't affect manually scratchpadded windows
- Manual scratchpad show (Win+minus) cycles through ALL scratchpad windows

**Check window source**:
```bash
i3pm windows inspect <window-id>

# Look for:
# Visibility:
#   Status: Hidden (in scratchpad)
#   Managed By: daemon / user
```

---

## Advanced Usage

### Scripting with JSON Output

```bash
# Count hidden windows per project
i3pm windows hidden --format=json | jq '.projects[] | "\(.project_name): \(.hidden_count)"'

# Get all hidden VS Code windows
i3pm windows hidden --app=vscode --format=json | jq '.projects[].windows[] | .window_id'

# Check if specific project has hidden windows
if [ $(i3pm windows hidden --project=nixos --format=json | jq '.projects[0].hidden_count') -gt 0 ]; then
  echo "nixos has hidden windows"
fi
```

---

### Custom Rofi Integration

Show hidden windows in rofi menu with restore action:

```bash
#!/bin/bash
# rofi-hidden-windows.sh

selected=$(i3pm windows hidden --format=json | jq -r '
  .projects[].windows[] |
  "\(.project_name)|\(.window_id)|\(.app_name)|\(.window_title)"
' | rofi -dmenu -p "Restore Window" -format "s")

if [ -n "$selected" ]; then
  project=$(echo "$selected" | cut -d'|' -f1)
  window_id=$(echo "$selected" | cut -d'|' -f2)
  i3pm windows restore "$project" --window-id="$window_id"
fi
```

Add to i3 config:
```
bindsym $mod+r exec --no-startup-id ~/scripts/rofi-hidden-windows.sh
```

---

### Monitoring Window Events

Watch window filtering in real-time:

```bash
# Terminal 1: Monitor daemon events
i3pm daemon events --follow --type=window

# Terminal 2: Switch projects
i3pm project switch nixos

# Terminal 1 shows:
# [14:23:45] window.hidden | project=stacks | count=3
# [14:23:45] window.restored | project=nixos | count=5
```

---

### Batch Operations

Hide/restore multiple projects:

```bash
# Hide all windows from multiple projects
for project in nixos stacks personal; do
  i3pm windows restore "$project" --dry-run | grep "Would restore"
done

# Restore specific windows by ID
for window_id in 123456 789012 345678; do
  i3pm windows restore nixos --window-id="$window_id"
done
```

---

## Performance Notes

### Expected Latency

| Operation | Target | Typical |
|-----------|--------|---------|
| Project switch (30 windows) | <2s | ~350ms |
| Window hide (10 windows) | <500ms | ~150ms |
| Window restore (10 windows) | <500ms | ~120ms |
| List hidden windows | <200ms | ~50ms |
| Inspect single window | <100ms | ~20ms |

### Optimization Tips

- **Batch operations**: Use project-level commands instead of per-window
- **Limit window count**: Keep <30 windows per project for best performance
- **Monitor count**: 3+ monitors add ~50ms for workspace validation
- **Concurrent switches**: Daemon queues switches, avoid rapid successive switches

---

## Integration with Other Features

### Feature 035: Registry-Centric Architecture

Window filtering relies on I3PM_* environment variables:

```bash
# Check if application has proper environment
i3pm windows inspect <window-id> | grep "I3PM_"

# Expected output:
# I3PM_PROJECT_NAME: nixos
# I3PM_APP_NAME: vscode
# I3PM_SCOPE: scoped
```

---

### Feature 033: Workspace-Monitor Configuration

Workspace restoration respects monitor configuration:

```bash
# View workspace assignments
i3pm monitors workspaces

# Update configuration if needed
i3pm monitors config edit
i3pm monitors config reload
```

---

### Feature 025: Visual Window State

Visualize hidden windows in tree view:

```bash
# Show complete window state including hidden
i3pm windows --show-hidden --tree

# Live monitor with hidden windows
i3pm windows --live
# Press 'H' to toggle hidden window visibility
```

---

## Configuration Files

### Runtime State Files

```
~/.config/i3/
├── window-workspace-map.json      # NEW: Workspace tracking
├── active-project.json             # Current active project (Feature 015)
├── application-registry.json       # App definitions (Feature 035)
└── projects/*.json                 # Project definitions (Feature 015)
```

### Daemon Configuration

```
~/.config/systemd/user/i3-project-event-listener.service  # Daemon service
~/.local/state/i3pm-daemon.sock                           # IPC socket
~/.local/state/i3pm-daemon.log                            # Daemon logs (optional)
```

---

## FAQ

### Q: Do I need to restart the daemon after installing this feature?

**A**: Yes, after NixOS rebuild:
```bash
systemctl --user restart i3-project-event-listener
```

---

### Q: What happens to windows launched before Feature 035?

**A**: Legacy windows (without I3PM_* variables) are treated as **global scope** (always visible). They won't hide during project switches.

---

### Q: Can I manually move windows between projects?

**A**: Not directly. Project association is determined by I3PM_PROJECT_NAME from launch environment. To reassign:
1. Close window in old project
2. Switch to new project
3. Relaunch application (inherits new project context)

---

### Q: What if I want a scoped app to behave like global?

**A**: Change scope in `app-registry.nix`:
```nix
{
  name = "vscode";
  scope = "global";  # Change from "scoped"
  # ...
}
```
Rebuild and restart daemon.

---

### Q: Does this work with multiple instances of the same app?

**A**: Yes! Each instance gets unique `I3PM_APP_ID`:
```
vscode-nixos-12345-1730000000  → nixos project, PID 12345
vscode-stacks-67890-1730000010 → stacks project, PID 67890
```
Each instance hides/restores independently.

---

### Q: Performance impact on daemon?

**A**: Minimal:
- CPU: <3% during switches, <1% idle
- Memory: ~8MB overhead for tracking state
- Latency: ~300ms for 30-window project switch

---

### Q: Can I disable window filtering for specific projects?

**A**: Not currently supported. All projects follow same filtering rules. Workaround: Mark all project apps as `scope=global` in registry (not recommended).

---

## See Also

- **Feature 015 Quickstart**: Event-driven daemon architecture
- **Feature 035 Quickstart**: Registry-centric project management and I3PM_* variables
- **Feature 033 Quickstart**: Workspace-monitor configuration
- **Feature 025 Quickstart**: Visual window state monitoring
- **data-model.md**: Entity definitions and relationships
- **contracts/daemon-ipc.md**: JSON-RPC API specification
- **contracts/cli-commands.md**: CLI command reference

---

**Status**: ✅ Complete - Ready for implementation (/speckit.tasks)
**Next Steps**: Run `/speckit.tasks` to generate implementation tasks
