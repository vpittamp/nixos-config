# Quickstart: Declarative Workspace-to-Monitor Mapping

**Feature**: 033-declarative-workspace-to
**Date**: 2025-10-23
**Target Users**: System administrators, power users managing multi-monitor setups

## Overview

This guide helps you quickly configure and use the declarative workspace-to-monitor mapping system for i3 window manager. You'll learn how to:

1. Understand the default configuration
2. Customize workspace distribution for your setup
3. Use CLI commands to manage monitors and workspaces
4. Troubleshoot common issues

---

## Quick Start (5 Minutes)

### 1. Check Current Configuration

View your current monitor setup:

```bash
i3pm monitors status
```

**Expected Output**:
```
Monitors (2 active)
┌────────┬────────┬─────────┬───────────┬────────────┬────────────┐
│ Output │ Active │ Primary │ Role      │ Resolution │ Workspaces │
├────────┼────────┼─────────┼───────────┼────────────┼────────────┤
│ rdp0   │   ✓    │    ✓    │ primary   │ 1920x1080  │ 1, 2       │
│ rdp1   │   ✓    │         │ secondary │ 1920x1080  │ 3-10       │
└────────┴────────┴─────────┴───────────┴────────────┴────────────┘
```

View workspace assignments:

```bash
i3pm monitors workspaces
```

**Expected Output**:
```
Workspaces (10 total)
┌───────────┬────────┬───────────┬─────────┬─────────┬─────────┐
│ Workspace │ Output │ Role      │ Windows │ Visible │ Source  │
├───────────┼────────┼───────────┼─────────┼─────────┼─────────┤
│ 1         │ rdp0   │ primary   │ 2       │   ✓     │ default │
│ 2         │ rdp0   │ primary   │ 0       │         │ default │
│ 3         │ rdp1   │ secondary │ 5       │   ✓     │ default │
│ 4         │ rdp1   │ secondary │ 1       │         │ default │
│ ...       │ ...    │ ...       │ ...     │ ...     │ ...     │
└───────────┴────────┴───────────┴─────────┴─────────┴─────────┘
```

### 2. View Configuration

Show the current configuration:

```bash
i3pm monitors config show
```

**Expected Output** (with syntax highlighting):
```json
{
  "version": "1.0",
  "distribution": {
    "1_monitor": {
      "primary": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    },
    "2_monitors": {
      "primary": [1, 2],
      "secondary": [3, 4, 5, 6, 7, 8, 9, 10]
    },
    "3_monitors": {
      "primary": [1, 2],
      "secondary": [3, 4, 5],
      "tertiary": [6, 7, 8, 9, 10]
    }
  },
  "workspace_preferences": {},
  "output_preferences": {},
  "debounce_ms": 1000,
  "enable_auto_reassign": true
}
```

**Config Location**: `~/.config/i3/workspace-monitor-mapping.json`

### 3. Make a Simple Change

Move workspace 5 to the primary monitor:

```bash
i3pm monitors move 5 --to primary
```

**Expected Output**:
```
✓ Moved workspace 5: rdp1 → rdp0 (primary)
```

---

## Understanding the Configuration

### Default Distribution Rules

The system uses different distribution rules based on the number of active monitors:

#### 1-Monitor Setup
All workspaces on the single monitor:
```
Primary: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

#### 2-Monitor Setup (Default)
```
Primary:   [1, 2]           # First 2 workspaces
Secondary: [3-10]           # Remaining workspaces
```

**Use Case**: Primary monitor for focused work (terminals, editor), secondary for reference (browser, documentation).

#### 3-Monitor Setup
```
Primary:   [1, 2]           # Focused work
Secondary: [3, 4, 5]        # Active tasks
Tertiary:  [6, 7, 8, 9, 10] # Background tasks
```

**Use Case**: Primary for code, secondary for testing/preview, tertiary for communication/monitoring.

### Configuration Structure

```json
{
  "version": "1.0",

  "distribution": {
    /* Default workspace assignments for different monitor counts */
    "1_monitor": { ... },
    "2_monitors": { ... },
    "3_monitors": { ... }
  },

  "workspace_preferences": {
    /* Explicit workspace-to-role assignments (overrides distribution) */
    /* Example: "18": "secondary" means workspace 18 always goes to secondary */
  },

  "output_preferences": {
    /* Preferred output names for each role (with fallbacks) */
    /* Example: "primary": ["rdp0", "DP-1", "eDP-1"] */
  },

  "debounce_ms": 1000,
  /* Wait time before reassigning workspaces after monitor changes */

  "enable_auto_reassign": true
  /* Automatically redistribute workspaces when monitors connect/disconnect */
}
```

---

## Common Customizations

### Scenario 1: Assign Specific Workspace to Specific Monitor

**Goal**: Always put workspace 18 (project workspace) on the secondary monitor.

**Edit Config**:
```bash
i3pm monitors config edit
```

**Add to `workspace_preferences`**:
```json
{
  "workspace_preferences": {
    "18": "secondary"
  }
}
```

**Apply Changes**:
```bash
i3pm monitors config reload
```

**Verify**:
```bash
i3pm monitors workspaces | grep "18"
```

### Scenario 2: Adjust 2-Monitor Distribution

**Goal**: Put workspaces 1-5 on primary, 6-10 on secondary (more balanced distribution).

**Edit Config**:
```bash
i3pm monitors config edit
```

**Modify `2_monitors` section**:
```json
{
  "distribution": {
    "2_monitors": {
      "primary": [1, 2, 3, 4, 5],
      "secondary": [6, 7, 8, 9, 10]
    }
  }
}
```

**Apply Changes**:
```bash
i3pm monitors config reload
i3pm monitors reassign  # Redistribute workspaces immediately
```

### Scenario 3: Prefer Specific Monitor Names

**Goal**: Ensure primary role always uses "DP-1" if available, fallback to "eDP-1" (laptop screen).

**Edit Config**:
```bash
i3pm monitors config edit
```

**Add to `output_preferences`**:
```json
{
  "output_preferences": {
    "primary": ["DP-1", "eDP-1"],
    "secondary": ["HDMI-1", "HDMI-2"]
  }
}
```

**Apply Changes**:
```bash
i3pm monitors config reload
```

**Behavior**: When DP-1 is connected, it becomes primary. When disconnected, eDP-1 becomes primary.

### Scenario 4: Faster Monitor Change Response

**Goal**: Reduce delay when connecting/disconnecting monitors from 1 second to 500ms.

**Edit Config**:
```bash
i3pm monitors config edit
```

**Change `debounce_ms`**:
```json
{
  "debounce_ms": 500
}
```

**Apply Changes**:
```bash
i3pm monitors config reload
```

**Note**: Lower values provide faster response but may cause multiple reassignments if monitors are unstable.

---

## CLI Commands Reference

### Status and Information

```bash
# Show monitor configuration
i3pm monitors status

# Show workspace assignments
i3pm monitors workspaces

# Show configuration file
i3pm monitors config show

# Live monitoring dashboard (auto-refresh every 2 seconds)
i3pm monitors watch
```

### Configuration Management

```bash
# Edit configuration in default editor
i3pm monitors config edit

# Generate default configuration (if missing)
i3pm monitors config init

# Validate configuration file
i3pm monitors config validate

# Reload configuration without restart
i3pm monitors config reload
```

### Workspace Operations

```bash
# Move workspace to role
i3pm monitors move <workspace> --to <role>
# Examples:
i3pm monitors move 5 --to primary
i3pm monitors move 18 --to secondary

# Move workspace to specific output
i3pm monitors move <workspace> --to <output>
# Example:
i3pm monitors move 3 --to rdp1

# Redistribute all workspaces according to config
i3pm monitors reassign

# Preview changes without applying
i3pm monitors reassign --dry-run
```

### Diagnostic Tools

```bash
# Show recent monitor events and workspace moves
i3pm monitors history

# Generate diagnostic report
i3pm monitors diagnose

# Verbose debug output
i3pm monitors debug
```

### Interactive TUI

```bash
# Full interactive TUI (keybindings: m=move, e=edit, r=reload, q=quit)
i3pm monitors tui
```

**TUI Keybindings**:
- `Tab`: Switch between tree/table view
- `m`: Move selected workspace
- `e`: Edit configuration
- `r`: Reload configuration
- `h`: Toggle hidden workspaces
- `q`: Quit

---

## Common Workflows

### Workflow 1: Setting Up a New Multi-Monitor Configuration

1. **Connect monitors** (e.g., laptop + 2 external displays)

2. **Check detected monitors**:
   ```bash
   i3pm monitors status
   ```

3. **If auto-reassign is disabled, manually redistribute**:
   ```bash
   i3pm monitors reassign
   ```

4. **Verify workspace distribution**:
   ```bash
   i3pm monitors workspaces
   ```

5. **Customize if needed**:
   ```bash
   i3pm monitors config edit
   # Make changes
   i3pm monitors config reload
   i3pm monitors reassign
   ```

### Workflow 2: Docking/Undocking Laptop

**Scenario**: Laptop user who docks daily at a workstation with 2 external monitors.

**Behavior with `enable_auto_reassign: true`** (default):

1. **Undocked** (1 monitor - laptop screen):
   - All workspaces automatically move to laptop screen
   - Distribution follows `1_monitor` rules

2. **Docked** (3 monitors - laptop + 2 external):
   - Workspaces automatically redistribute across 3 monitors
   - Distribution follows `3_monitors` rules
   - Primary goes to preferred external monitor (if configured)

3. **Monitor change detected within 1 second** (debounce_ms)

**Manual Control**:
If you prefer manual control, set `enable_auto_reassign: false` and use:
```bash
i3pm monitors reassign
```

### Workflow 3: Troubleshooting Lost Workspaces

**Problem**: After disconnecting a monitor, some windows seem "lost".

**Solution**:

1. **Check for orphaned workspaces**:
   ```bash
   i3pm monitors diagnose
   ```

   **Output**:
   ```
   Issues:
   - Workspace 7 has 3 windows but is on inactive output "HDMI-1"

   Suggested Fix:
     i3pm monitors move 7 --to secondary
   ```

2. **Move orphaned workspaces**:
   ```bash
   i3pm monitors move 7 --to secondary
   ```

3. **Or reassign all workspaces**:
   ```bash
   i3pm monitors reassign
   ```

### Workflow 4: Testing Configuration Changes

**Best Practice**: Always validate and preview changes before applying.

1. **Edit configuration**:
   ```bash
   i3pm monitors config edit
   ```

2. **Validate syntax**:
   ```bash
   i3pm monitors config validate
   ```

   **Expected Output**:
   ```
   ✓ Configuration is valid
   ```

3. **Preview changes**:
   ```bash
   i3pm monitors reassign --dry-run
   ```

   **Expected Output**:
   ```
   Planned Changes:
   - Workspace 3: rdp0 → rdp1 (role: secondary)
   - Workspace 5: rdp0 → rdp1 (role: secondary)
   - Workspace 18: rdp0 → rdp1 (role: secondary, explicit preference)

   Total: 3 workspaces would be reassigned
   ```

4. **Apply changes**:
   ```bash
   i3pm monitors config reload
   i3pm monitors reassign
   ```

---

## Troubleshooting

### Issue 1: Configuration Not Loading

**Symptoms**:
- `i3pm monitors config show` shows default config despite edits
- Changes don't take effect after `reload`

**Diagnosis**:
```bash
i3pm monitors config validate
```

**Common Causes**:
1. **Invalid JSON syntax**: Missing comma, bracket, or quote
   - **Fix**: Use `i3pm monitors config validate` to find syntax errors
2. **Wrong file location**: Editing a different file than daemon is reading
   - **Fix**: Check config path in `i3pm monitors config show`
3. **Permission issues**: Daemon can't read config file
   - **Fix**: `chmod 644 ~/.config/i3/workspace-monitor-mapping.json`

### Issue 2: Workspaces Not Reassigning Automatically

**Symptoms**:
- Connecting/disconnecting monitors doesn't trigger workspace redistribution

**Diagnosis**:
```bash
i3pm monitors config show | grep enable_auto_reassign
i3pm daemon status
```

**Common Causes**:
1. **Auto-reassign disabled**: `enable_auto_reassign: false`
   - **Fix**: Set to `true` in config and reload
2. **Daemon not running**: Event-driven reassignment requires daemon
   - **Fix**: `systemctl --user start i3-project-event-listener`
3. **Debounce too long**: Change not detected within timeout
   - **Fix**: Reduce `debounce_ms` or manually reassign

### Issue 3: Workspace on Wrong Monitor

**Symptoms**:
- Workspace appears on unexpected output after config change

**Diagnosis**:
```bash
i3pm monitors workspaces
i3pm monitors diagnose
```

**Common Causes**:
1. **Explicit preference overrides distribution**: Check `workspace_preferences`
   - **Fix**: Remove explicit preference or adjust distribution
2. **Output preference mismatch**: Preferred output not active
   - **Fix**: Update `output_preferences` or connect preferred output
3. **Config not reloaded**: Using old config
   - **Fix**: `i3pm monitors config reload && i3pm monitors reassign`

### Issue 4: Validation Errors

**Symptoms**:
```
✗ Configuration validation failed
  Error (distribution.2_monitors.primary): Duplicate workspace assignments: {5}
```

**Common Causes**:
1. **Duplicate workspace in distribution**: Same workspace in multiple roles
   - **Fix**: Remove duplicate from one role
2. **Negative workspace number**: Workspace numbers must be positive
   - **Fix**: Use positive integers only
3. **Invalid role**: Typo in `workspace_preferences` value
   - **Fix**: Use "primary", "secondary", or "tertiary" only

**Example Fix**:
```json
/* BEFORE (invalid) */
{
  "distribution": {
    "2_monitors": {
      "primary": [1, 2, 5],
      "secondary": [3, 4, 5, 6, 7, 8, 9, 10]  // 5 appears twice
    }
  }
}

/* AFTER (valid) */
{
  "distribution": {
    "2_monitors": {
      "primary": [1, 2],
      "secondary": [3, 4, 5, 6, 7, 8, 9, 10]
    }
  }
}
```

### Issue 5: Daemon Unavailable

**Symptoms**:
```
Error: Socket file not found

Socket path: /run/user/1000/i3-project-daemon/ipc.sock

The daemon socket does not exist. Ensure the daemon is running:
  systemctl --user start i3-project-event-listener
```

**Fix**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Start daemon if stopped
systemctl --user start i3-project-event-listener

# Enable auto-start on boot
systemctl --user enable i3-project-event-listener

# View logs if daemon fails to start
journalctl --user -u i3-project-event-listener -n 50
```

---

## Advanced Usage

### Unlimited Workspace Numbers

The system supports workspace numbers beyond 10 (up to 70+):

```json
{
  "workspace_preferences": {
    "18": "secondary",
    "42": "tertiary",
    "99": "primary"
  }
}
```

**Note**: Workspaces not explicitly configured follow distribution rules based on monitor count.

### Custom Distribution for 4+ Monitors

For setups with more than 3 monitors, use explicit `workspace_preferences`:

```json
{
  "workspace_preferences": {
    "1": "primary",
    "2": "primary",
    "3": "secondary",
    "4": "secondary",
    "5": "tertiary",
    "6": "tertiary",
    "7": "quaternary",  // Not supported - will use tertiary
    "8": "quaternary"   // Not supported - will use tertiary
  }
}
```

**Limitation**: Only 3 roles supported (primary, secondary, tertiary). For 4+ monitors, assign multiple workspaces to tertiary or extend the system.

### JSON Output for Scripting

All commands support `--json` flag for scripting:

```bash
i3pm monitors status --json | jq '.monitors[] | select(.primary == true) | .name'
```

**Output**:
```
"rdp0"
```

**Use Cases**:
- Automation scripts
- Custom i3bar/polybar modules
- CI/CD monitoring
- Integration with other tools

### Exporting Configuration

```bash
# Export current config
i3pm monitors config show > workspace-mapping-backup.json

# Import to another machine
cp workspace-mapping-backup.json ~/.config/i3/workspace-monitor-mapping.json
i3pm monitors config reload
```

---

## Best Practices

### 1. Version Control Your Configuration

Store your config in dotfiles repository:

```bash
# Link config to version-controlled location
ln -s ~/dotfiles/i3/workspace-monitor-mapping.json ~/.config/i3/workspace-monitor-mapping.json
```

### 2. Use Descriptive Workspace Numbers

Assign specific workspace numbers to specific purposes:

```json
{
  "workspace_preferences": {
    "1": "primary",    // Terminal/editor
    "2": "primary",    // Testing/REPL
    "10": "secondary", // Browser
    "18": "secondary", // Documentation
    "42": "tertiary"   // Communication (Slack, email)
  }
}
```

### 3. Test Before Committing Changes

Always use the validation and dry-run workflow:

```bash
i3pm monitors config validate
i3pm monitors reassign --dry-run
# Review changes
i3pm monitors reassign
```

### 4. Monitor Daemon Health

Add to your i3bar config or daily routine:

```bash
# Quick health check
i3pm daemon status
```

### 5. Document Custom Configuration

Add comments to your config file (comments not supported in JSON, use a separate README):

```bash
# ~/dotfiles/i3/workspace-mapping-README.md
# Workspace Distribution Strategy
# - Workspaces 1-2: Primary monitor (focused work)
# - Workspaces 3-9: Secondary monitor (reference, testing)
# - Workspace 10: Secondary (browser)
# - Workspace 18: Secondary (documentation)
# - Workspace 42: Tertiary (communication)
```

---

## Migration from Old System

### What Changed

**Removed**:
- `detect-monitors.sh` bash script (no longer needed)
- Hardcoded distribution in `workspace_manager.py`

**Added**:
- JSON configuration file
- Comprehensive CLI commands
- Interactive TUI
- Diagnostic tools

### Migration Steps

1. **Existing behavior is now default**: The new default config matches the old hardcoded rules.

2. **No action required** if you're happy with the current behavior.

3. **To customize** (previously required editing Python code):
   ```bash
   i3pm monitors config edit
   # Make changes
   i3pm monitors config reload
   ```

4. **To verify migration**:
   ```bash
   # Old way: cat ~/.config/i3/scripts/detect-monitors.sh
   # New way:
   i3pm monitors config show
   ```

---

## Next Steps

1. **Explore Interactive TUI**:
   ```bash
   i3pm monitors tui
   ```

2. **Customize Configuration** for your specific workflow

3. **Set Up Live Monitoring** (if using multiple monitors frequently):
   ```bash
   i3pm monitors watch
   ```

4. **Read Full Documentation**:
   - `spec.md` - Complete feature specification
   - `data-model.md` - Configuration schema details
   - `contracts/jsonrpc-api.md` - API reference for scripting

---

## Getting Help

```bash
# Built-in help
i3pm monitors --help
i3pm monitors status --help

# Daemon status
i3pm daemon status

# Recent events
i3pm daemon events --limit=20

# Diagnostic report
i3pm monitors diagnose
```

**Community Support**:
- GitHub Issues: [github.com/anthropics/nixos-config/issues](https://github.com)
- Documentation: `/etc/nixos/specs/033-declarative-workspace-to/`

---

**Last Updated**: 2025-10-23
