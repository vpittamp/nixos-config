# Quickstart: Session Management

**Feature**: 074-session-management
**Status**: Implementation Planned
**For**: Users and developers of i3pm project management system

## Overview

Session management extends i3pm with workspace focus restoration, terminal working directory tracking, and automatic layout save/restore capabilities.

## Key Features

✅ **Workspace Focus Restoration** - Return to the exact workspace you were using when switching back to a project
✅ **Terminal Working Directory** - Terminals reopen in their original directories (not `$HOME`)
✅ **Focused Window Restoration** - Each workspace focuses the same window you were using
✅ **Auto-Save on Switch** - Automatically save layout when leaving a project
✅ **Auto-Restore on Activate** - Optionally restore layout when activating a project
✅ **Sway Compatible** - Works on Sway/Wayland (replaces broken i3 swallow mechanism)

## Basic Usage

### Workspace Focus (Automatic)

When you switch projects, i3pm automatically tracks which workspace you were focused on:

```bash
# Working on Project A, focused on workspace 3
current: Project A, Workspace 3

# Switch to Project B
i3pm project switch dotfiles
→ Workspace 1 (default for new project)

# Switch back to Project A
i3pm project switch nixos
→ Workspace 3 (automatically restored!)
```

**No configuration needed** - workspace focus tracking is always active.

### Layout Save & Restore

Save your current workspace layout:

```bash
# Save current layout with a name
i3pm layout save main

# List saved layouts
i3pm layout list

# Restore a layout
i3pm layout restore main

# Delete a layout
i3pm layout delete old-layout
```

### Auto-Save Configuration

Enable auto-save to automatically capture layouts when switching projects:

```nix
# File: home-modules/desktop/app-registry-data.nix
projects = [
  {
    name = "nixos";
    directory = "/etc/nixos";
    auto_save = true;         # Auto-save on project switch
    max_auto_saves = 10;      # Keep 10 most recent auto-saves
  }
];
```

After enabling auto-save:

```bash
# Switch away from project (auto-saves layout as "auto-20250114-103000")
i3pm project switch other-project

# Switch back (auto-saved layout is available)
i3pm layout list
→ auto-20250114-103000 (auto-saved)
→ main (manually saved)
```

### Auto-Restore Configuration

Enable auto-restore to automatically restore layout when activating a project:

```nix
projects = [
  {
    name = "nixos";
    directory = "/etc/nixos";
    auto_save = true;
    auto_restore = true;      # Auto-restore on project activate
    default_layout = "main";  # Which layout to restore
    max_auto_saves = 10;
  }
];
```

After enabling auto-restore:

```bash
# Switch to project (automatically restores "main" layout)
i3pm project switch nixos
→ Layout "main" restored automatically
→ All windows launched in correct workspaces
→ Workspace 3 focused (from last session)
→ Terminals open in their original directories
```

## Configuration

### Per-Project Settings

```nix
# File: home-modules/desktop/app-registry-data.nix
{
  name = "my-project";
  directory = "/home/user/projects/my-project";

  # Session Management Settings
  auto_save = true;                # Auto-save on project switch (default: false)
  auto_restore = false;            # Auto-restore on project activate (default: false)
  default_layout = "main";         # Layout name for auto-restore (default: null)
  max_auto_saves = 10;             # Max auto-saves to keep (default: 10, range: 1-100)
}
```

### Runtime Configuration (Temporary)

Change settings without rebuilding NixOS:

```bash
# View current config
i3pm config get

# Enable auto-save (runtime only)
i3pm config set --auto-save true

# Set max auto-saves
i3pm config set --max-auto-saves 15

# Enable auto-restore with default layout
i3pm config set --auto-restore true --default-layout main
```

**Note**: Runtime config changes are lost on daemon restart. To persist, edit `app-registry-data.nix` and rebuild.

## Workflow Examples

### Scenario 1: Daily Development Workflow

```bash
# Morning: Start project, auto-restore yesterday's layout
i3pm project switch nixos
→ Workspace 3 focused (where you left off yesterday)
→ Layout "main" restored (if auto_restore=true)
→ Terminals open in /etc/nixos, /etc/nixos/modules, etc.

# Work normally, switch workspaces as needed
# (focus tracking happens automatically)

# Afternoon: Quick context switch to check docs
i3pm project switch documentation
→ Workspace 5 focused (last workspace for docs project)

# Back to work
i3pm project switch nixos
→ Workspace 3 focused (exactly where you left off)

# Evening: Project auto-saved when you switch away
i3pm project switch personal
→ nixos project auto-saved as "auto-20250114-170000"
```

### Scenario 2: Manual Layout Management

```bash
# Set up ideal workspace layout for feature development
# - Workspace 1: Editor (VS Code)
# - Workspace 2: Terminal (running dev server)
# - Workspace 3: Browser (testing)

# Save this layout
i3pm layout save feature-dev

# Continue working, make changes

# Restore ideal layout
i3pm layout restore feature-dev
→ All 3 workspaces restored with correct windows
→ Terminals open in correct directories
→ Focus restored to workspace 3 (browser for testing)
```

### Scenario 3: Multiple Saved Layouts

```bash
# Save different layouts for different tasks
i3pm layout save frontend-dev
i3pm layout save backend-dev
i3pm layout save debugging

# List saved layouts
i3pm layout list
→ frontend-dev (created: 2025-01-14 10:00)
→ backend-dev (created: 2025-01-14 11:00)
→ debugging (created: 2025-01-14 12:00)

# Switch between layouts
i3pm layout restore backend-dev
# ... work on backend
i3pm layout restore frontend-dev
# ... work on frontend
```

## Technical Details

### Terminal Working Directory Detection

Terminal applications are detected by window class:
- `ghostty` (primary terminal per CLAUDE.md)
- `Alacritty`
- `kitty`
- `foot`
- `WezTerm`

Working directory is read from `/proc/{pid}/cwd` during layout capture.

**Fallback behavior** if original directory doesn't exist:
1. Try project root directory (from project config)
2. If project root doesn't exist, use `$HOME`

### Window Correlation (Sway Compatibility)

Sway doesn't support i3's swallow mechanism. This feature uses **mark-based correlation**:

1. Generate unique restoration mark: `i3pm-restore-{8-char-hex}`
2. Inject mark into environment before launching window
3. Poll Sway tree for window with matching mark (30s timeout)
4. Apply saved geometry, floating state, and project marks
5. Remove temporary restoration mark

**Success rate**: >95% for windows with unique class/instance combinations

**Timeout behavior**: After 30 seconds, window is marked as failed, restoration continues with remaining windows

### Storage Locations

| Data | Path |
|------|------|
| Project focus state | `~/.config/i3/project-focus-state.json` |
| Workspace focus state | `~/.config/i3/workspace-focus-state.json` |
| Layout snapshots | `~/.local/share/i3pm/layouts/{project}/{layout-name}.json` |

### Performance

| Operation | Latency |
|-----------|---------|
| Workspace focus switch | <100ms |
| Auto-save capture | <200ms |
| Window correlation (typical) | <500ms |
| 10-window layout restore | <15s total |

## Troubleshooting

### Workspace focus not restoring

**Check daemon status**:
```bash
i3pm daemon status
```

**Verify focus state**:
```bash
i3pm project focused-workspace
```

**Check logs**:
```bash
journalctl --user -u i3-project-event-listener -f
```

### Layout restore failing

**Verify layout exists**:
```bash
i3pm layout list
```

**Check layout file**:
```bash
cat ~/.local/share/i3pm/layouts/{project}/{layout-name}.json
```

**Try with verbose output**:
```bash
i3pm layout restore main --verbose
```

### Window correlation timeout

**Check application launch time**:
- Some applications (large IDEs) may take >30s to launch on first run
- Subsequent launches are usually faster

**Increase timeout** (if needed):
```bash
i3pm layout restore main --timeout 60
```

### Terminal not opening in correct directory

**Verify terminal class is detected**:
```bash
swaymsg -t get_tree | jq '.. | select(.window_class?) | .window_class' | grep -i terminal
```

**Check saved layout**:
```bash
cat ~/.local/share/i3pm/layouts/{project}/{layout}.json | jq '.workspace_layouts[].windows[] | select(.window_class == "ghostty") | .cwd'
```

**Verify directory exists**:
```bash
ls -la /path/from/layout
```

## Advanced Usage

### Manual Focus Override

Override tracked workspace focus:

```bash
# Set workspace 5 as focused for current project
i3pm project set-focused-workspace 5
```

### Pruning Auto-Saves

Auto-saves are automatically pruned based on `max_auto_saves` config. To manually prune:

```bash
# List all auto-saves
i3pm layout list | grep auto-

# Delete specific auto-save
i3pm layout delete auto-20250114-100000
```

### Viewing Daemon State

See complete daemon state including focus tracking:

```bash
i3pm daemon state
```

Output:
```json
{
  "active_project": "nixos",
  "uptime_seconds": 3600.5,
  "project_focused_workspaces": {
    "nixos": 3,
    "dotfiles": 5
  },
  "workspace_focused_windows": {
    "1": 12345,
    "2": 67890
  }
}
```

## Migration from Older Versions

### Backward Compatibility

Existing layouts without focus tracking data:
- Load successfully (optional fields default to `None`)
- Focus state falls back to workspace 1
- First save after upgrade will include new fields

**No manual migration needed** - layouts are forward-compatible.

## Next Steps

- **Enable auto-save**: Edit `app-registry-data.nix` and set `auto_save = true` for projects
- **Test layout save/restore**: Save current layout and try restoring it
- **Read full specification**: See [spec.md](./spec.md) for complete feature documentation
- **Review implementation plan**: See [plan.md](./plan.md) for technical details

## Support

**Issues**: Report bugs and feature requests via project issue tracker
**Logs**: `journalctl --user -u i3-project-event-listener -f`
**Diagnostics**: `i3pm diagnose health`
**State**: `i3pm daemon state`
