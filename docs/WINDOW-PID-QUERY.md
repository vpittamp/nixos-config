# Window PID Query Feature

**Status**: Complete
**Date**: 2025-11-03
**Files Modified**: 5 files
**Files Created**: 2 files

## Overview

Added PID (Process ID) support to all i3pm window-related commands and created a user-friendly `window-env` helper tool to query window PIDs and environment variables.

## Changes Made

### 1. Daemon Window Data Extraction
**File**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/ipc_server.py`

Added PID field to window data returned by the daemon's `_extract_windows_from_container` method:
```python
"pid": node.pid if hasattr(node, 'pid') else None
```

### 2. CLI Formatters
**File**: `/etc/nixos/home-modules/tools/i3_project_manager/cli/formatters.py`

**Table View**:
- Added PID column (width: 8, right-justified, dim style)
- Shows PID or "-" if not available
- Updated title column width from 35 to 30 to accommodate PID

**Tree View**:
- Added PID display in node labels: `(PID: 12345)`
- Only shown if PID is available

### 3. TUI Widgets
**Files**:
- `/etc/nixos/home-modules/tools/i3_project_manager/visualization/table_view.py`
- `/etc/nixos/home-modules/tools/i3_project_manager/visualization/tree_view.py`

**Table View Widget**:
- Added PID column to COLUMNS definition
- Updated add_row to include PID value
- Added PID to numeric sorting logic (id, pid, workspace)

**Tree View Widget**:
- Added PID display in window labels: `(PID: 12345)`

### 4. Helper Script
**File**: `/etc/nixos/home-modules/tools/window-env.nix` (new)

Created a user-friendly command-line tool to query window PIDs and environment variables:
- Uses `pkgs.writeShellScriptBin` for proper Nix integration
- Fuzzy pattern matching on window class names
- Colored output with I3PM_* variables highlighted
- Multiple output modes: full env vars, PID only, JSON, filtered
- Handles multiple matching windows

### 5. Configuration Integration
**File**: `/etc/nixos/home-modules/profiles/base-home.nix`

Added window-env module to home-manager imports at line 50.

### 6. Documentation
**File**: `/etc/nixos/CLAUDE.md`

Added comprehensive documentation section: "🔍 Window Environment Query Tool" with:
- Quick examples
- Feature list
- Common use cases
- Output format examples
- Integration notes with i3pm windows

## Usage

### View PIDs in i3pm commands

```bash
# Table view with PID column
i3pm windows --table

# Tree view with PID in labels
i3pm windows --tree

# JSON with PID field
i3pm windows --json | jq '.outputs[].workspaces[].windows[] | {class, pid}'

# Live TUI with PID column
i3pm windows --live
```

### Query window environment variables

```bash
# Show all environment variables for a window
window-env YouTube

# Get just the PID
window-env --pid YouTube

# Show only I3PM_* variables
window-env --filter I3PM_ YouTube

# Show all matching windows (not just first)
window-env --all Code

# Get raw JSON data
window-env --json Firefox | jq .
```

### Practical workflows

```bash
# Debug PWA workspace assignment
window-env --filter I3PM_ YouTube
# Output shows: I3PM_PROJECT_NAME, I3PM_APP_NAME, I3PM_TARGET_WORKSPACE, etc.

# Find PID and manually inspect /proc
PID=$(window-env --pid YouTube)
cat /proc/$PID/environ | tr '\0' '\n'

# Verify project context for an application
window-env --filter I3PM_PROJECT vscode

# One-liner to get specific env var
window-env --json YouTube | jq -r '.[0].pid' | xargs -I{} sh -c 'cat /proc/{}/environ | tr "\0" "\n" | grep I3PM_PROJECT_NAME'
```

## Implementation Details

### PID Availability
- PIDs are available from i3/Sway IPC via the `pid` property on container nodes
- The daemon checks for PID availability with `hasattr(node, 'pid')`
- If PID is not available (rare cases), it's represented as `None` in JSON or "-" in formatted output

### Performance Impact
- Minimal: PID is already available in i3 IPC data, no additional queries needed
- All PID queries are synchronous reads from `/proc/<pid>/environ`
- No daemon overhead beyond initial window tree query

### Error Handling
The `window-env` tool includes comprehensive error handling:
- **No matching windows**: Lists available window classes
- **PID not available**: Shows warning message
- **Process no longer exists**: Checks `/proc/<pid>` existence
- **Permission denied**: Suggests running with sudo if needed
- **Daemon not running**: Provides helpful diagnostic message

## Testing

After rebuilding the system, verify:

1. **PID appears in i3pm windows commands**:
   ```bash
   i3pm windows --table | head -5
   # Should show PID column
   ```

2. **window-env command is available**:
   ```bash
   which window-env
   window-env --help
   ```

3. **Query a known window**:
   ```bash
   # Replace "Firefox" with an actual window class on your system
   window-env --filter I3PM_ Firefox
   ```

4. **JSON output includes PID**:
   ```bash
   i3pm windows --json | jq '.outputs[0].workspaces[0].windows[0] | has("pid")'
   # Should output: true
   ```

## Future Enhancements

Possible improvements:
- Add `window-env --watch` for real-time environment monitoring
- Support filtering by workspace or output
- Add completion scripts for window class names
- Integration with `i3pm diagnose` for automated debugging
- Environment variable diffing between windows

## Related Features

This enhancement complements:
- **Feature 025**: Window State Visualization - provides PID in all visualization modes
- **Feature 035**: Registry-Centric Architecture - environment variables show project context
- **Feature 039**: Diagnostic Tooling - PID enables deeper process inspection
- **Feature 041**: IPC Launch Context - PID correlation for multi-instance tracking

## Migration Notes

No breaking changes:
- All existing `i3pm windows` commands continue to work
- PID field is additive (new column/field)
- JSON output is backward compatible (new optional field)
- No configuration changes required

## References

- i3 IPC specification: https://i3wm.org/docs/ipc.html
- Sway IPC: https://github.com/swaywm/sway/blob/master/sway/sway-ipc.7.scd
- /proc filesystem: https://man7.org/linux/man-pages/man5/proc.5.html
