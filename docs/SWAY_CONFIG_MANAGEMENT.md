# Sway Configuration Management Guide

**Feature**: Dynamic Sway Configuration (Feature 047)
**Status**: ✅ MVP Complete
**System**: hetzner-sway (Sway on NixOS/Wayland)

---

## Overview

The Sway Configuration Management system provides **hot-reloadable configuration** for Sway window manager, eliminating the need to rebuild NixOS when changing keybindings, window rules, or workspace assignments.

**Key Achievement**: Configuration iteration time reduced from **120 seconds** (nixos-rebuild) to **<5 seconds** (hot-reload) - a **96% reduction**.

---

## Quick Reference

### Essential Commands

```bash
# Reload configuration
swayconfig reload

# Validate configuration
swayconfig validate

# View current configuration
swayconfig show

# View version history
swayconfig versions

# Rollback to previous version
swayconfig rollback HEAD~1

# Check daemon status
swayconfig ping
systemctl --user status sway-config-manager
```

### Configuration Files

| File | Purpose | Format |
|------|---------|--------|
| `~/.config/sway/keybindings.toml` | Keybinding definitions | TOML |
| `~/.config/sway/window-rules.json` | Window behavior rules | JSON |
| `~/.config/sway/workspace-assignments.json` | Workspace-to-output mapping | JSON |
| `~/.config/sway/projects/<name>.json` | Project-specific overrides | JSON |

---

## Setup

### Enable in Home-Manager

Add to your Sway-specific home-manager configuration:

```nix
# In configurations/hetzner-sway.nix or similar
programs.sway-config-manager.enable = true;
```

### Configuration Options

```nix
programs.sway-config-manager = {
  enable = true;

  # Configuration directory (default: ~/.config/sway)
  configDir = "${config.home.homeDirectory}/.config/sway";

  # Enable automatic reload on file changes (default: true)
  enableFileWatcher = true;

  # File watcher debounce delay in milliseconds (default: 500)
  debounceMs = 500;
};
```

### Rebuild and Verify

```bash
# Rebuild home-manager
home-manager switch --flake .#user@hetzner-sway

# Verify daemon is running
systemctl --user status sway-config-manager

# Test CLI
swayconfig ping
```

---

## Configuration Workflows

### Workflow 1: Add a Keybinding

```bash
# 1. Edit keybindings file
vi ~/.config/sway/keybindings.toml

# 2. Add new keybinding
[keybindings]
"Mod+t" = { command = "exec btop", description = "System monitor" }

# 3. Save file → Auto-reload happens!
# Or manual reload:
swayconfig reload

# 4. Test keybinding
# Press Win+T → btop opens
```

### Workflow 2: Make Calculator Float

```bash
# 1. Edit window rules
vi ~/.config/sway/window-rules.json

# 2. Add floating rule
{
  "version": "1.0",
  "rules": [
    {
      "id": "float-calculator",
      "criteria": {
        "app_id": "^org\\.gnome\\.Calculator$"
      },
      "actions": [
        "floating enable",
        "resize set 400 300",
        "move position center"
      ],
      "scope": "global",
      "priority": 100,
      "source": "runtime"
    }
  ]
}

# 3. Reload
swayconfig reload

# 4. Launch calculator → Opens floating and centered!
```

### Workflow 3: Assign Workspace to Monitor

```bash
# 1. Edit workspace assignments
vi ~/.config/sway/workspace-assignments.json

# 2. Assign workspace 3 to HDMI monitor
{
  "version": "1.0",
  "assignments": [
    {
      "workspace_number": 3,
      "primary_output": "HDMI-A-1",
      "fallback_outputs": ["eDP-1"],
      "auto_reassign": true,
      "source": "runtime"
    }
  ]
}

# 3. Reload
swayconfig reload

# 4. Switch to workspace 3 → Appears on HDMI monitor
```

### Workflow 4: Experimental Changes with Rollback

```bash
# 1. Check current version
swayconfig versions

# 2. Make experimental changes
vi ~/.config/sway/keybindings.toml
# (try a new keybinding layout)

# 3. Reload and test
swayconfig reload

# 4. If you don't like it, rollback
swayconfig versions
swayconfig rollback HEAD~1

# 5. Configuration instantly reverts!
```

---

## Configuration Precedence

### Three-Tier System

```
Project Overrides    ← Priority 3 (highest)
    ↓
Runtime Config       ← Priority 2 (medium)
    ↓
Nix Base Config      ← Priority 1 (lowest)
```

### Example Scenario

**Nix base config** (from sway.nix):
```nix
"Mod+Return" = "exec terminal";
```

**Runtime config** (from keybindings.toml):
```toml
"Mod+Return" = { command = "exec ghostty", description = "Terminal" }
```

**Project override** (from projects/nixos.json):
```json
{
  "keybinding_overrides": {
    "Mod+n": { "command": "exec nvim /etc/nixos/configuration.nix" }
  }
}
```

**Result**:
- `Mod+Return` uses Runtime config (ghostty), overriding Nix base
- When nixos project is active, `Mod+n` opens NixOS config
- When no project is active, `Mod+n` does nothing (no global binding)

### Conflict Detection

```bash
# Check for configuration conflicts
swayconfig conflicts

# Example output:
⚠️  CONFIGURATION CONFLICTS

Type: keybinding
Key: Control+1
Sources: nix vs runtime
Resolution: Using runtime
```

---

## File Format Reference

### Keybindings (TOML)

**Simple format** (string command):
```toml
[keybindings]
"Mod+Return" = "exec terminal"
```

**Extended format** (with description and mode):
```toml
[keybindings]
"Mod+Return" = { command = "exec ghostty", description = "Terminal", mode = "default" }
"Mod+r" = { command = "resize", description = "Enter resize mode", mode = "default" }

# Mode-specific keybindings
# Note: Modes must be defined in Sway config separately
```

**Syntax Rules**:
- Key combination format: `(Mod|Shift|Control|Alt)+<key>`
- Multiple modifiers: `Mod+Shift+T`
- Valid keys: alphanumeric, underscores, hyphens

### Window Rules (JSON)

```json
{
  "version": "1.0",
  "rules": [
    {
      "id": "unique-rule-id",
      "criteria": {
        "app_id": "regex pattern",       // Wayland app ID
        "window_class": "regex pattern", // X11 window class
        "title": "regex pattern",        // Window title
        "window_role": "regex pattern"   // X11 window role
      },
      "actions": [
        "floating enable",
        "resize set 800 600",
        "move position center",
        "workspace number 4"
      ],
      "scope": "global",  // or "project"
      "project_name": "nixos",  // required if scope="project"
      "priority": 100,  // 0-1000, higher = applies later
      "source": "runtime"  // or "nix" or "project"
    }
  ]
}
```

**Criteria Fields** (at least one required):
- `app_id` - Wayland application ID (use `swaymsg -t get_tree` to find)
- `window_class` - X11 window class (for Xwayland apps)
- `title` - Window title (regex pattern)
- `window_role` - X11 window role

**Action Examples**:
- `floating enable` / `floating disable` - Set floating state
- `resize set <width> <height>` - Set window size
- `move position center` - Center window
- `move position <x> <y>` - Move to specific position
- `workspace number <N>` - Move to workspace N
- `fullscreen enable` - Make fullscreen

### Workspace Assignments (JSON)

```json
{
  "version": "1.0",
  "assignments": [
    {
      "workspace_number": 3,
      "primary_output": "HDMI-A-1",
      "fallback_outputs": ["eDP-1", "DP-1"],
      "auto_reassign": true,
      "source": "runtime"
    }
  ]
}
```

**Fields**:
- `workspace_number` - Workspace number (1-70)
- `primary_output` - Primary monitor name
- `fallback_outputs` - Fallback monitors if primary unavailable
- `auto_reassign` - Auto-reassign when monitors change
- `source` - Configuration source

**Finding Output Names**:
```bash
swaymsg -t get_outputs | jq '.[] | {name, make, model}'
```

---

## Advanced Features

### Automatic File Watching

By default, the daemon watches configuration files and auto-reloads on changes:

```bash
# Edit any config file
vi ~/.config/sway/keybindings.toml

# Save → Auto-reload happens within 1 second!

# Disable file watcher (if needed)
programs.sway-config-manager.enableFileWatcher = false;
```

**Debouncing**: File watcher waits 500ms after last change before reloading, batching rapid edits.

### Git-Based Version Control

Every successful reload creates a git commit:

```bash
# View version history
swayconfig versions --limit 10

# Example output:
═══════════════════════════════════════════════
  CONFIGURATION VERSIONS
═══════════════════════════════════════════════
● a1b2c3d  2025-10-29 14:30:00
  Update keybindings for workflow

  f9e8d7c  2025-10-29 12:15:00
  Add floating rules for calculators

# Rollback to specific version
swayconfig rollback f9e8d7c

# Or rollback N versions
swayconfig rollback HEAD~2
```

**Git Commands** (advanced):
```bash
cd ~/.config/sway
git log  # View full history
git diff HEAD~1  # Compare with previous version
git show a1b2c3d  # View specific commit
```

### Two-Phase Reload

The reload process uses a two-phase commit pattern:

**Phase 1: Validation**
- Load configuration files
- Structural validation (JSON Schema)
- Semantic validation (regex patterns, workspace numbers)
- Conflict detection

**Phase 2: Apply** (only if Phase 1 passes)
- Start transaction (save current commit)
- Merge configurations (Nix → Runtime → Project)
- Apply to rule engines
- Reload Sway config via IPC
- Commit to git
- Update daemon state

**On Failure**: Automatic rollback to previous commit

```bash
# Validate without applying
swayconfig reload --validate-only

# Reload without git commit
swayconfig reload --skip-commit
```

### Project-Specific Overrides

*Note: Full project integration with i3pm is not yet implemented in MVP*

**Concept**: Different window rules and keybindings per project.

**Example** (`~/.config/sway/projects/nixos.json`):
```json
{
  "project_name": "nixos",
  "directory": "/etc/nixos",
  "icon": "🔧",
  "window_rule_overrides": [
    {
      "base_rule_id": "float-calculator",
      "override_properties": {
        "actions": ["floating enable", "resize set 800 600"]
      },
      "enabled": true
    }
  ],
  "keybinding_overrides": {
    "Mod+n": { "command": "exec nvim /etc/nixos/configuration.nix" }
  }
}
```

---

## Troubleshooting

### Daemon Not Starting

**Check service status**:
```bash
systemctl --user status sway-config-manager
journalctl --user -u sway-config-manager -n 50
```

**Common issues**:
- Sway not running (daemon requires Sway session)
- Configuration directory missing
- Python dependencies not installed

**Fix**:
```bash
# Restart daemon
systemctl --user restart sway-config-manager

# Recreate config directory
mkdir -p ~/.config/sway/{projects,schemas}

# Rebuild home-manager
home-manager switch --flake .#user@hetzner-sway
```

### Configuration Not Reloading

**Check file watcher**:
```bash
swayconfig ping

# Should output:
✅ Daemon is running
```

**Manual reload**:
```bash
swayconfig reload
```

**Check for validation errors**:
```bash
swayconfig validate
```

### Keybinding Not Working

**1. Check if binding is loaded**:
```bash
swayconfig show --category keybindings | grep "Mod+t"
```

**2. Check Sway config includes generated file**:
```bash
grep "include.*keybindings-generated.conf" ~/.config/sway/config

# Should have:
include ~/.config/sway/keybindings-generated.conf
```

**3. Manually reload Sway**:
```bash
swaymsg reload
```

**4. Check for conflicts**:
```bash
swayconfig conflicts
```

### Window Rule Not Applying

**1. Find window's app_id**:
```bash
swaymsg -t get_tree | jq '.. | select(.focused==true) | {app_id, window_class, name}'
```

**2. Verify rule syntax**:
```bash
swayconfig validate --files window-rules
```

**3. Check rule matches window**:
```bash
# Rules are regex patterns
# Use ^...$ for exact match
# Use .* for wildcards
```

**4. Test rule manually**:
```bash
swaymsg "[app_id=\"org.gnome.Calculator\"] floating enable"
```

### Rollback Not Working

**Check git repository**:
```bash
cd ~/.config/sway
git status
git log --oneline
```

**Manual rollback**:
```bash
git checkout HEAD~1 .
swayconfig reload
```

### Performance Issues

**Check daemon resource usage**:
```bash
systemctl --user status sway-config-manager
# Should show <15MB memory, <1% CPU
```

**Increase file watcher debounce**:
```nix
programs.sway-config-manager.debounceMs = 1000;  # 1 second
```

**Disable auto-reload**:
```nix
programs.sway-config-manager.enableFileWatcher = false;
```

---

## Integration with Existing Systems

### Sway Configuration

Add to your Sway config to include generated keybindings:

```sway
# Include dynamically generated keybindings
include ~/.config/sway/keybindings-generated.conf
```

### i3pm Integration

*Note: Full i3pm project integration is planned but not yet implemented in MVP*

**Future**: Project-aware window rules will integrate with i3pm project switching:
- Switch to "nixos" project → Apply nixos-specific window rules
- Switch to "stacks" project → Apply stacks-specific window rules
- Global mode → Apply only global rules

### Home-Manager

Recommended structure for multi-machine configurations:

```nix
# configurations/hetzner-sway.nix
{ config, pkgs, ... }:
{
  imports = [
    ../home-modules/desktop/sway.nix
    ../home-modules/desktop/sway-config-manager.nix
  ];

  # Enable Sway configuration management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;
    debounceMs = 500;
  };

  # Sway base configuration
  wayland.windowManager.sway = {
    enable = true;
    config = {
      # ... other Sway settings ...

      # Include generated keybindings
      extraConfig = ''
        include ~/.config/sway/keybindings-generated.conf
      '';
    };
  };
}
```

---

## CLI Reference

### swayconfig reload

Reload configuration with two-phase commit.

**Usage**:
```bash
swayconfig reload [OPTIONS]
```

**Options**:
- `--files FILE1,FILE2` - Reload specific files only
- `--validate-only` - Only validate, don't apply
- `--skip-commit` - Don't commit changes to git

**Examples**:
```bash
swayconfig reload                        # Reload all
swayconfig reload --files keybindings    # Reload keybindings only
swayconfig reload --validate-only        # Dry-run
```

### swayconfig validate

Validate configuration without applying.

**Usage**:
```bash
swayconfig validate [OPTIONS]
```

**Options**:
- `--files FILE1,FILE2` - Validate specific files
- `--strict` - Treat warnings as errors

**Examples**:
```bash
swayconfig validate                      # Validate all
swayconfig validate --strict             # Strict validation
```

### swayconfig show

Display current configuration.

**Usage**:
```bash
swayconfig show [OPTIONS]
```

**Options**:
- `--category CAT` - Show specific category (all, keybindings, window-rules, workspaces)
- `--sources` - Show source attribution
- `--project PROJ` - Show project-specific config
- `--json` - Output as JSON

**Examples**:
```bash
swayconfig show                              # Show all
swayconfig show --category keybindings       # Keybindings only
swayconfig show --sources                    # With source info
swayconfig show --json                       # JSON output
```

### swayconfig versions

List configuration version history.

**Usage**:
```bash
swayconfig versions [OPTIONS]
```

**Options**:
- `--limit N` - Show N most recent versions (default: 10)

### swayconfig rollback

Rollback to previous configuration version.

**Usage**:
```bash
swayconfig rollback COMMIT [OPTIONS]
```

**Options**:
- `--no-reload` - Don't reload after rollback

**Examples**:
```bash
swayconfig rollback a1b2c3d              # Rollback to specific commit
swayconfig rollback HEAD~1               # Rollback to previous version
swayconfig rollback --no-reload a1b2c3d  # Rollback without reload
```

### swayconfig conflicts

Show configuration conflicts and resolutions.

**Usage**:
```bash
swayconfig conflicts
```

### swayconfig ping

Check if daemon is running.

**Usage**:
```bash
swayconfig ping
```

---

## Architecture

### Components

```
┌─────────────────────────────────────────┐
│          User Edits Config File         │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  File Watcher (500ms debounce)          │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Daemon (daemon.py)                     │
│  ┌──────────────────────────────────┐   │
│  │ Reload Manager                   │   │
│  │ ├─ Phase 1: Validation           │   │
│  │ └─ Phase 2: Apply                │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ Rule Engines                     │   │
│  │ ├─ Keybinding Manager            │   │
│  │ ├─ Window Rule Engine            │   │
│  │ └─ Workspace Assignment Handler  │   │
│  └──────────────────────────────────┘   │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Sway Window Manager (via IPC)          │
└─────────────────────────────────────────┘
```

### File Structure

```
home-modules/desktop/
├── sway-config-manager.nix        # Home-manager module
└── sway-config-manager/
    ├── daemon.py                  # Main daemon
    ├── ipc_server.py              # JSON-RPC server
    ├── cli.py                     # CLI client
    ├── state.py                   # State tracking
    ├── models.py                  # Pydantic models
    ├── config/
    │   ├── loader.py              # TOML/JSON parsing
    │   ├── validator.py           # Validation
    │   ├── merger.py              # Configuration merging
    │   ├── reload_manager.py      # Two-phase commit
    │   ├── file_watcher.py        # File monitoring
    │   ├── rollback.py            # Git version control
    │   └── schema_generator.py    # JSON schema generation
    └── rules/
        ├── keybinding_manager.py  # Keybinding application
        ├── window_rule_engine.py  # Window rule application
        └── workspace_assignments.py  # Workspace-to-output mapping
```

---

## Performance Tuning

### Optimize Reload Speed

**Reduce debounce delay** (faster reload, more frequent):
```nix
programs.sway-config-manager.debounceMs = 250;  # 250ms
```

**Increase debounce delay** (batch more edits):
```nix
programs.sway-config-manager.debounceMs = 1000;  # 1 second
```

### Disable Auto-Reload

For manual control:
```nix
programs.sway-config-manager.enableFileWatcher = false;
```

Then use manual reload:
```bash
swayconfig reload
```

---

## Best Practices

1. **Always validate before reloading in production**:
   ```bash
   swayconfig validate && swayconfig reload
   ```

2. **Use meaningful git commit messages**:
   The daemon auto-commits, but you can add messages by manually committing first

3. **Test experimental changes with rollback safety**:
   ```bash
   # Make changes
   swayconfig reload
   # Test...
   # If broken:
   swayconfig rollback HEAD~1
   ```

4. **Keep window rules organized**:
   Use descriptive rule IDs and comments in JSON

5. **Document custom keybindings**:
   Use the `description` field in keybindings.toml

---

## See Also

- [Feature Specification](../specs/047-create-a-new/spec.md)
- [Implementation Summary](../specs/047-create-a-new/IMPLEMENTATION_SUMMARY.md)
- [Quickstart Guide](../specs/047-create-a-new/quickstart.md)
- [Data Model](../specs/047-create-a-new/data-model.md)

---

**For questions or issues, see**: `/etc/nixos/specs/047-create-a-new/README.md`
