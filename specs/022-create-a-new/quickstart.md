# Quickstart Guide: Enhanced i3pm TUI

**Feature**: Enhanced i3pm TUI with Comprehensive Management & Automated Testing
**Branch**: `022-create-a-new`
**Date**: 2025-10-21

## Overview

This guide provides a quick introduction to the enhanced i3pm TUI features for end users. For implementation details, see [plan.md](./plan.md) and [data-model.md](./data-model.md).

## Table of Contents

1. [Layout Management](#layout-management)
2. [Workspace Configuration](#workspace-configuration)
3. [Window Classification](#window-classification)
4. [Auto-Launch Configuration](#auto-launch-configuration)
5. [Monitor Management](#monitor-management)
6. [Navigation Tips](#navigation-tips)
7. [Testing & Validation](#testing--validation)

---

## Layout Management

### Saving a Layout

Save your current window arrangement for later restoration:

1. Press `l` to open Layout Manager
2. Arrange your windows as desired across workspaces
3. Press `s` to save layout
4. Enter a descriptive name (e.g., "coding-layout", "debugging-setup")
5. Press Enter to confirm

**What Gets Saved**:
- Window positions and sizes
- Workspace assignments
- Application launch commands
- Environment variables
- Working directories

**File Location**: `~/.config/i3/layouts/{project-name}/{layout-name}.json`

### Restoring a Layout

Restore a previously saved layout:

1. Press `l` to open Layout Manager
2. Use arrow keys to select the layout
3. Press `r` to restore

**What Happens**:
- Missing applications are automatically launched
- Existing windows are repositioned
- Workspace assignments are applied
- Should complete within 2 seconds

**Tip**: If applications fail to launch, check the layout JSON file for correct launch commands.

### Restore All

Launch all project applications at once:

1. In Project Browser or Layout Manager
2. Press `Shift+R` for Restore All

This launches all applications from your project's auto-launch list and positions them according to the default layout.

### Close All

Close all project-scoped windows:

1. In Project Browser
2. Press `c` to close all project windows

Only closes windows marked with your project context. Global applications (Firefox, etc.) remain open.

### Deleting Layouts

Remove a saved layout:

1. Press `l` to open Layout Manager
2. Select the layout to delete
3. Press `d` for delete
4. Confirm when prompted

### Exporting Layouts

Export a layout to share or backup:

1. Press `l` to open Layout Manager
2. Select the layout
3. Press `e` to export
4. Choose destination path
5. Press Enter to confirm

Exported layouts are standard JSON files that can be imported on other systems.

---

## Workspace Configuration

### Assigning Workspaces to Monitors

Configure which workspaces appear on which monitors:

1. Open a project (select and press Enter)
2. Press `w` to open Workspace Configuration
3. For each workspace:
   - Select workspace number (1-10)
   - Choose monitor role: primary, secondary, or tertiary
   - Press Enter to save

**Monitor Roles**:
- **Primary**: Main display (laptop screen or left monitor)
- **Secondary**: Second display (usually right monitor)
- **Tertiary**: Third display (if available)

**Default Distribution** (if not configured):
- 1 monitor: All workspaces on primary
- 2 monitors: WS 1-2 on primary, WS 3-9 on secondary
- 3+ monitors: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

### Validation Warnings

The system validates your assignments against current monitor count:

- ✅ Valid: WS 1-2 → primary, WS 3-4 → secondary (with 2 monitors)
- ⚠️ Warning: WS 6 → tertiary (only 2 monitors available)

Warnings indicate the configuration will only work with more monitors connected.

---

## Window Classification

### Classification Wizard

Classify discovered applications as project-scoped or global:

1. From main menu, press `Shift+C` to open Classification Wizard
2. View table of all open windows with:
   - Application class
   - Window title
   - Current workspace
   - Classification status (scoped/global/unclassified)
3. Select a window
4. Press `s` for scoped or `g` for global
5. Classification is applied immediately

**Scoped Applications** (hidden when switching projects):
- Code editors (VS Code, Neovim)
- Terminals (Ghostty, Alacritty)
- Project-specific tools

**Global Applications** (always visible):
- Web browsers (Firefox, Chrome)
- Media players
- System monitors

### Pattern-Based Matching

Create pattern rules for automatic classification:

1. Press `p` in Classification Wizard for Pattern Configuration
2. Press `a` to add new pattern
3. Enter regex pattern (e.g., `^Code.*` matches "Code", "Code - Insiders")
4. Choose scope: scoped or global
5. Set priority (lower number = higher priority)
6. Press `t` to test pattern against current windows
7. Press Enter to save

**Example Patterns**:
- `^pwa-.*` → global (all PWAs are global)
- `terminal` → scoped (any terminal emulator)
- `^Code|^neovide$` → scoped (editors)

**Testing Patterns**: The test view shows which windows match your pattern in real-time.

---

## Auto-Launch Configuration

### Managing Auto-Launch Entries

Configure applications to launch automatically when switching to a project:

1. Open a project
2. Press `a` to open Auto-Launch Configuration
3. View table of current auto-launch entries with:
   - Application command
   - Target workspace
   - Environment variables
   - Launch status (enabled/disabled)

### Adding Auto-Launch Entry

1. Press `n` to add new entry
2. Fill in the form:
   - **Command**: `ghostty` or full path
   - **Workspace**: 1-10 (leave blank for current workspace)
   - **Environment Variables**: KEY=value (one per line)
   - **Working Directory**: `/path/to/project/dir` (uses PROJECT_DIR if blank)
   - **Wait Timeout**: Seconds to wait for window (default: 5.0)
3. Press Enter to save

### Editing Auto-Launch Entry

1. Select entry in table
2. Press `e` to edit
3. Modify fields
4. Press Enter to save

### Reordering Entries

Launch order matters for dependencies:

1. Select entry
2. Press `Up Arrow` or `Down Arrow` to reorder
3. Changes save automatically

**Example Order**:
1. Terminal (launches fast, provides shell access)
2. Editor (may need shell to be ready)
3. Browser (slowest to launch)

### Disabling Entries

Temporarily disable an entry without deleting:

1. Select entry
2. Press `t` to toggle enabled/disabled
3. Disabled entries won't launch but remain configured

---

## Monitor Management

### Viewing Monitor Configuration

See current monitor setup:

1. Press `m` to open Monitor Dashboard
2. View table showing:
   - Monitor name (DP-1, HDMI-1, etc.)
   - Resolution (1920x1080)
   - Role (primary/secondary/tertiary)
   - Assigned workspaces
   - Position (x,y coordinates)

### Manual Workspace Redistribution

Trigger workspace redistribution manually:

1. In Monitor Dashboard, press `r` to redistribute
2. Choose:
   - **Use project preferences**: Apply active project's workspace configuration
   - **Use default distribution**: Apply default based on monitor count
3. Confirm when prompted

**When to Use**:
- After connecting/disconnecting monitors
- When workspaces appear on wrong monitors
- After docking/undocking laptop

**Automatic Detection**: The system usually detects monitor changes automatically, but manual redistribution can force an update.

### Monitor Change Workflow

When you connect a new monitor:

1. Monitor Dashboard updates within 1 second
2. Notification appears: "Monitor configuration changed"
3. System shows redistribution preview
4. Choose to apply or ignore

---

## Navigation Tips

### Keyboard Shortcuts

**Global**:
- `Win+P`: Switch projects (rofi launcher)
- `Win+Shift+P`: Clear active project (global mode)
- `/`: Focus search box
- `Escape`: Clear search / return to previous screen
- `q`: Quit TUI

**Project Browser**:
- `Enter`: Switch to selected project
- `e`: Edit project
- `l`: Layout Manager
- `m`: Monitor Dashboard
- `n`: New project wizard
- `d`: Delete project
- `c`: Clear active project (global mode)
- `s`: Toggle sort mode
- `r`: Reverse sort order

**Layout Manager**:
- `s`: Save layout
- `r`: Restore layout
- `d`: Delete layout
- `e`: Export layout
- `Shift+R`: Restore All
- `Shift+C`: Close All

**General Navigation**:
- `h/j/k/l` or Arrow Keys: Navigate
- `Tab`: Next field
- `Shift+Tab`: Previous field
- `Enter`: Confirm / Activate
- `Escape`: Cancel / Go back

### Breadcrumb Navigation

The breadcrumb at the top shows your location:

- `Projects` - Project Browser (home)
- `Projects > NixOS > Edit` - Editing NixOS project
- `Projects > NixOS > Layouts` - Layout Manager for NixOS
- `Tools > Window Classification` - Classification Wizard

Click breadcrumb segments to jump directly (mouse support).

### Status Bar

Bottom status bar shows:
- Active project name
- Total project count
- Daemon connection status
- Contextual keybindings for current screen

---

## Testing & Validation

### Running Automated Tests

For developers: Run the test suite to validate TUI functionality:

```bash
# Run full test suite
pytest tests/i3pm/

# Run specific scenario
pytest tests/i3pm/scenarios/test_layout_workflow.py

# Run with verbose output
pytest tests/i3pm/ -v

# Run with coverage report
pytest tests/i3pm/ --cov=home-modules/tools/i3_project_manager --cov-report=html
```

### Test Scenarios

The test suite includes scenarios for:
- Layout save/restore workflow
- Window classification workflow
- Workspace configuration updates
- Monitor detection and redistribution
- Project lifecycle (create/edit/delete)

### Performance Validation

Test framework validates performance constraints:
- Layout restore completes within 2 seconds
- TUI operations complete within 2 seconds
- Pattern rule testing shows results within 500ms
- Monitor updates within 1 second of physical changes

### State Dumps

When tests fail, state dumps are automatically captured showing:
- Active screen and widget states
- Current project configuration
- Recent daemon events
- File system state

Useful for debugging issues.

---

## Troubleshooting

### Layout Restore Fails

**Problem**: Layout restore fails with "Failed to launch: ghostty"

**Solutions**:
1. Check launch command in layout JSON: `~/.config/i3/layouts/{project}/{layout}.json`
2. Verify command works in terminal: `ghostty`
3. Check PATH includes application: `echo $PATH`
4. Edit layout JSON to fix command
5. Try restoring again

### Windows Not Auto-Marking

**Problem**: Windows don't get marked with project context after switching

**Solutions**:
1. Check daemon status: `i3-project-daemon-status`
2. Verify window class is in scoped classes: Run Classification Wizard
3. Check recent events: `i3-project-daemon-events --limit=20 --type=window`
4. Restart daemon: `systemctl --user restart i3-project-event-listener`

### Workspace Appears on Wrong Monitor

**Problem**: After connecting monitor, workspaces are on wrong outputs

**Solutions**:
1. Open Monitor Dashboard (`m`)
2. Press `r` to redistribute workspaces
3. Choose "Use project preferences" if configured
4. If problem persists, check workspace configuration (`w`)

### TUI Operation Slow

**Problem**: Layout restore or other operations take longer than 2 seconds

**Check**:
1. Daemon connection: Should show "Connected" in status bar
2. i3 responsiveness: Try `i3-msg workspace 1` - should be instant
3. Application launch times: Some apps (VS Code) naturally take 1-2s to appear
4. Number of windows: 100 windows is the maximum supported

**Report**: If operations consistently exceed 2 seconds with <20 windows, this is a bug. Please report with:
- Project configuration
- Number of windows
- Daemon logs: `journalctl --user -u i3-project-event-listener -n 100`

---

## Advanced Usage

### Custom Launch Commands

Auto-launch entries support complex commands:

```bash
# Terminal in project directory with sesh
cd $PROJECT_DIR && ghostty --hold sesh connect $PROJECT_NAME

# VS Code with specific extensions
code $PROJECT_DIR --install-extension ms-python.python

# Browser with specific profile
firefox -P "$PROJECT_NAME" --new-window $PROJECT_URL

# Docker compose up
cd $PROJECT_DIR && docker-compose up -d
```

### Environment Variable Expansion

Available variables in launch commands and environments:
- `$PROJECT_DIR`: Project directory path
- `$PROJECT_NAME`: Project name
- `$I3_PROJECT`: Project name (alias)
- `$HOME`: User home directory
- Any custom environment variables from auto-launch entry

### Conditional Launch Commands

Use shell conditionals for complex launch logic:

```bash
# Launch terminal only if not already running
if ! pgrep -x "ghostty" > /dev/null; then ghostty; fi

# Launch VS Code or fallback to neovim
code $PROJECT_DIR || neovide $PROJECT_DIR
```

---

## Quick Reference Card

| Action | Keyboard | Mouse |
|--------|----------|-------|
| **Projects** |||
| Switch project | Enter | Double-click row |
| Edit project | e | - |
| New project | n | - |
| Delete project | d | - |
| Clear active | c | - |
| **Layouts** |||
| Open Layout Manager | l | - |
| Save layout | l, then s | - |
| Restore layout | l, select, r | - |
| Restore All | Shift+R | - |
| Close All | Shift+C | - |
| Delete layout | l, select, d | - |
| Export layout | l, select, e | - |
| **Configuration** |||
| Workspace config | w | - |
| Auto-launch config | a | - |
| Window classification | Shift+C | - |
| Pattern config | p | - |
| Monitor dashboard | m | - |
| **Navigation** |||
| Search | / | - |
| Clear search | Escape | - |
| Navigate | Arrow keys / hjkl | Click |
| Go back | Escape | Breadcrumb |
| Quit | q | - |

---

## Next Steps

### For Users

1. **Start Simple**: Create your first project and save a basic layout
2. **Classify Applications**: Run Classification Wizard to mark your common apps
3. **Configure Auto-Launch**: Add 2-3 essential applications
4. **Test Layout Restore**: Switch away and restore your layout

### For Developers

1. **Read Implementation Plan**: [plan.md](./plan.md) for architecture
2. **Review Contracts**: [contracts/](./contracts/) for API definitions
3. **Study Data Models**: [data-model.md](./data-model.md) for entities
4. **Write Tests**: Use test framework to validate new features

### For System Administrators

1. **Deploy Configuration**: Include i3pm TUI in NixOS configuration
2. **Set Defaults**: Configure default scoped/global application classes
3. **Monitor Performance**: Check layout restore times stay under 2 seconds
4. **Review Logs**: Monitor daemon logs for user issues

---

## Getting Help

### Documentation

- **Feature Specification**: [spec.md](./spec.md) - User requirements and acceptance criteria
- **Implementation Plan**: [plan.md](./plan.md) - Technical details and architecture
- **Data Model**: [data-model.md](./data-model.md) - Entity definitions
- **Research Findings**: [research.md](./research.md) - Design decisions and patterns
- **API Contracts**: [contracts/](./contracts/) - Interface definitions

### Commands

```bash
# Check daemon status
i3-project-daemon-status

# View recent events
i3-project-daemon-events --limit=50

# List projects
i3-project-list

# Show current project
i3-project-current

# Switch project
i3-project-switch nixos

# Launch TUI
i3pm-tui
```

### Logs

```bash
# Daemon logs
journalctl --user -u i3-project-event-listener -f

# TUI logs (if logging enabled)
tail -f ~/.cache/i3pm/tui.log
```

### Bug Reports

When reporting bugs, please include:
1. Description of the problem
2. Steps to reproduce
3. Expected vs actual behavior
4. Project configuration JSON
5. Daemon logs
6. TUI state dump (if available)

---

**Last Updated**: 2025-10-21
**Version**: 1.0 (Initial release)
**Status**: Ready for implementation
