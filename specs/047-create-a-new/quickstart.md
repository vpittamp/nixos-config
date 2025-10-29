# Quickstart Guide: Dynamic Sway Configuration Management

**Feature**: 047-create-a-new
**Audience**: End users and system administrators
**Prerequisites**: NixOS with hetzner-sway or M1 Sway configuration, i3pm daemon running

## Overview

This guide shows you how to use dynamic configuration management to customize your Sway window manager without rebuilding NixOS. You'll learn how to:

- Modify keybindings and reload them instantly (<5 seconds)
- Create project-specific window rules
- Validate configuration before applying changes
- Rollback to previous versions if something breaks

## Quick Start

### 1. Check System Status

Verify the daemon is running and file watcher is active:

```bash
# Check daemon status
i3pm daemon status

# Check configuration system
i3pm config watch status
```

**Expected output**:
```
✅ Daemon running (v2.1.0, uptime: 3h 25m)
✅ File watcher active (watching 3 files, debounce: 500ms)
```

---

### 2. Add a Custom Keybinding

Edit the keybindings configuration file:

```bash
# Open keybindings in your editor
i3pm config edit keybindings

# Or manually edit
nvim ~/.config/sway/keybindings.toml
```

Add a new keybinding at the end:

```toml
[keybindings]
# ... existing keybindings ...

"Mod+t" = { command = "exec btop", description = "Open system monitor" }
```

Save the file. If file watcher is enabled (default), configuration reloads automatically. Otherwise, trigger reload manually:

```bash
i3pm config reload
```

**Result**: Press `Win+T` to open btop - works immediately without rebuild!

---

### 3. Create a Floating Window Rule

Edit window rules to make Calculator always float:

```bash
# Edit window rules
i3pm config edit window-rules

# Or manually
nvim ~/.config/sway/window-rules.json
```

Add a new rule to the `rules` array:

```json
{
  "version": "1.0",
  "rules": [
    {
      "id": "rule-calculator",
      "criteria": {
        "app_id": "^org\\.gnome\\.Calculator$"
      },
      "actions": ["floating enable", "resize set 400 300", "move position center"],
      "scope": "global",
      "priority": 100,
      "source": "runtime"
    }
  ]
}
```

Save and reload:

```bash
i3pm config reload --files window-rules
```

**Result**: Open Calculator (`gnome-calculator`) - it appears floating and centered!

---

### 4. Add Project-Specific Window Rules

Create custom window behavior for the "nixos" project:

```bash
# Edit project configuration
nvim ~/.config/sway/projects/nixos.json
```

Add window rule overrides:

```json
{
  "project_name": "nixos",
  "directory": "/etc/nixos",
  "icon": "🔧",
  "window_rule_overrides": [
    {
      "base_rule_id": "rule-calculator",
      "override_properties": {
        "actions": ["floating enable", "resize set 800 600"]
      },
      "enabled": true
    }
  ],
  "keybinding_overrides": {
    "Mod+n": { "command": "exec nvim /etc/nixos/configuration.nix", "description": "Edit NixOS config" }
  }
}
```

Switch to the nixos project:

```bash
pswitch nixos
```

**Result**: When nixos project is active, Calculator opens larger (800x600 instead of 400x300), and `Win+N` opens NixOS config in editor!

---

### 5. Validate Configuration

Before reloading, validate your changes:

```bash
# Validate all configuration files
i3pm config validate

# Validate specific file
i3pm config validate --files keybindings

# Strict mode (warnings treated as errors)
i3pm config validate --strict
```

**Example output**:
```
✅ Configuration valid

Validation Time: 85ms
Files Validated:
  • keybindings.toml
  • window-rules.json
  • workspace-assignments.json

Summary:
  ✅ 0 syntax errors
  ✅ 0 semantic errors
  ⚠️  1 warning

Warnings:
  keybindings.toml:15
    Keybinding Control+2 conflicts with Nix base config
    → Using runtime config (higher precedence)
```

Fix any errors, then reload:

```bash
i3pm config reload
```

---

### 6. View Current Configuration

See all active keybindings, window rules, and their sources:

```bash
# Show all configuration
i3pm config show

# Show only keybindings
i3pm config show --category keybindings

# Include source attribution
i3pm config show --sources
```

**Example output**:
```
═══════════════════════════════════════════════════════════════
                    KEYBINDINGS
═══════════════════════════════════════════════════════════════
Key Combo     Command                Source    File
───────────────────────────────────────────────────────────────
Mod+Return    exec terminal          nix       sway.nix:22
Control+1     workspace number 1     runtime   keybindings.toml:5
Mod+t         exec btop              runtime   keybindings.toml:18
───────────────────────────────────────────────────────────────

Active Project: nixos
Config Version: a1b2c3d (2025-10-29 14:30:00)
```

---

### 7. Rollback Configuration (Feature 047 US4)

If a change breaks something, instantly rollback to a previous working version.

#### List Version History

View your configuration history with detailed commit information:

```bash
# List recent versions (default: 10)
i3pm config list-versions

# Show more versions
i3pm config list-versions --limit 20

# Show versions since a specific date
i3pm config list-versions --since "2025-10-01"

# JSON output for scripting
i3pm config list-versions --json
```

**Example Output**:
```
┌─ Configuration Version History ─────────────────────────────────────┐
│
│  f9e8d7c  2025-10-29 14:30:12 ← ACTIVE
│  Configuration reload: 2025-10-29 14:30:12
│
│  Files: keybindings.toml
│  Status: Success
│  Author: sway-config-daemon, Files: 1
│
│  a1b2c3d  2025-10-29 12:15:45
│  Configuration reload: 2025-10-29 12:15:45
│
│  Files: window-rules.json
│  Status: Success
│  Author: sway-config-daemon, Files: 1
│
│  e4f3b2a  2025-10-28 18:22:33
│  Initial configuration setup
│  Author: sway-config-daemon, Files: 3
│
└─ Total: 3 versions ────────────────────────────────────────────────┘

To rollback to a version:
  i3pm config rollback f9e8d7c

Options:
  --limit <n>     Limit number of versions (default: 10)
  --since <date>  Show versions since date (e.g., '2025-01-01')
  --json          Output in JSON format
```

#### Rollback to Previous Version

Restore configuration to a specific commit:

```bash
# Rollback to a specific version (by commit hash)
i3pm config rollback f9e8d7c

# Rollback without reloading configuration (manual reload later)
i3pm config rollback f9e8d7c --no-reload
```

**Example Output**:
```
Rolling back configuration to f9e8d7c...
✓ Configuration rolled back successfully
  Duration: 1847ms
  Files changed: keybindings.toml
```

#### Automatic Rollback on Failure

If a configuration change fails to apply (e.g., invalid Sway syntax), the system automatically rolls back to the previous working version:

```bash
# Make a breaking change
echo "invalid syntax" >> ~/.config/sway/keybindings.toml

# Try to reload (will fail and auto-rollback)
i3pm config reload
```

**Example Output**:
```
Phase 1: Validating configuration
✓ Structural validation passed
✓ Semantic validation passed

Phase 2: Applying configuration
✗ Sway config reload failed - configuration will be rolled back to previous version

Rolling back configuration:
  From: a1b2c3d
  To:   f9e8d7c
✓ Rollback successful (duration: 1204ms)
✓ Configuration restored to previous working state
  Files restored: keybindings.toml
```

**Key Features**:
- **Fast rollback**: <3 seconds to restore any previous version
- **Automatic commits**: Every successful reload creates a version
- **Detailed logging**: See exactly what changed (files, duration, status)
- **Safety net**: Automatic rollback on any apply failure
- **Git-based**: Use standard git commands if needed (`~/.config/sway/`)

#### Version Control Best Practices

1. **Commit meaningful changes**: Each reload auto-commits with timestamp and files changed
2. **Check history regularly**: Use `list-versions` to see your configuration evolution
3. **Test changes incrementally**: Make small changes and verify before continuing
4. **Keep backups**: The version history provides a complete audit trail
5. **Manual git operations**: You can use git commands directly in `~/.config/sway/` if needed

**Example git workflow**:
```bash
cd ~/.config/sway

# View full git history
git log --oneline

# See changes in a specific commit
git show f9e8d7c

# Create a branch for experiments
git checkout -b experiment

# Return to main
git checkout main
```

---

## Common Workflows

### Workflow 1: Experiment with Keybindings

```bash
# 1. Check current version (before changes)
i3pm config list-versions --limit 1

# 2. Edit keybindings
i3pm config edit keybindings

# 3. Add experimental binding (e.g., Mod+Shift+t for terminal)
# Save and test immediately (auto-reloads)

# 4. Test the new keybinding
# Press Mod+Shift+t to verify it works

# 5. If you don't like it, rollback to previous version
i3pm config list-versions --limit 2   # Find previous commit hash
i3pm config rollback <previous-hash>  # e.g., i3pm config rollback f9e8d7c
```

**Time saved**: ~2 minutes per iteration (vs NixOS rebuild)
**Safety**: Automatic rollback if configuration is invalid

---

### Workflow 2: Create Project-Specific Workspace Layout

```bash
# 1. Switch to project
pswitch data-science

# 2. Edit project config
nvim ~/.config/sway/projects/data-science.json

# 3. Add workspace assignments for data apps
{
  "workspace_assignments_override": [
    {
      "app_id": "jupyter-lab",
      "workspace_number": 4
    }
  ]
}

# 4. Reload
i3pm config reload

# 5. Launch Jupyter Lab - opens on workspace 4 automatically
```

---

### Workflow 3: Batch Configuration Changes

```bash
# 1. Edit multiple files
nvim ~/.config/sway/keybindings.toml
nvim ~/.config/sway/window-rules.json

# 2. Validate all changes
i3pm config validate --strict

# 3. If valid, reload atomically
i3pm config reload

# 4. Commit to git for version control
cd /etc/nixos
git add user-config/sway/
git commit -m "Update Sway config: new keybindings and window rules"
```

---

## Configuration File Locations

| File | Purpose | Format |
|------|---------|--------|
| `~/.config/sway/keybindings.toml` | User-defined keybindings | TOML |
| `~/.config/sway/window-rules.json` | Window behavior rules | JSON |
| `~/.config/sway/workspace-assignments.json` | Workspace-to-output mapping | JSON |
| `~/.config/sway/projects/<name>.json` | Project-specific overrides | JSON |
| `~/.config/sway/.config-version` | Active configuration version | JSON |

**Version Control**: All files are symlinked from `/etc/nixos/user-config/sway/` and tracked in git.

---

## Configuration Precedence

Understanding which configuration takes priority is crucial for managing settings across different contexts.

### Precedence Hierarchy

```
Project Overrides  (Level 3 - highest priority)
    ↓
Runtime Config     (Level 2 - medium priority)
    ↓
Nix Base Config    (Level 1 - lowest priority, system defaults)
```

### How It Works

1. **Nix Base Config (Level 1)**: System-wide defaults managed by NixOS configuration
   - Location: `home-modules/desktop/sway.nix` and related Nix files
   - Applied during: NixOS rebuild (`sudo nixos-rebuild switch`)
   - Purpose: Stable system defaults, package installation, service configuration

2. **Runtime Config (Level 2)**: User-editable configuration files
   - Location: `~/.config/sway/keybindings.toml`, `window-rules.json`, etc.
   - Applied during: Hot-reload (`i3pm config reload`)
   - Purpose: Personal customizations without rebuilding NixOS

3. **Project Overrides (Level 3)**: Project-specific behavior
   - Location: `~/.config/sway/projects/<name>.json`
   - Applied during: Project switch (`pswitch <project>`)
   - Purpose: Context-aware behavior for different workflows

### Precedence Examples

#### Example 1: Keybinding Override Chain

**Nix Config** (Level 1):
```nix
# home-modules/desktop/sway.nix
bindings = {
  "Mod+Return" = "exec ${terminal}";
  "Control+1" = "workspace number 1";
}
```

**Runtime Config** (Level 2):
```toml
# ~/.config/sway/keybindings.toml
[keybindings]
"Control+1" = { command = "workspace number 1", description = "Workspace 1" }
"Mod+t" = { command = "exec btop", description = "System monitor" }
```

**Project Override** (Level 3):
```json
// ~/.config/sway/projects/nixos.json
{
  "keybinding_overrides": {
    "Control+1": { "command": "exec nvim /etc/nixos/configuration.nix", "description": "Edit NixOS config" }
  }
}
```

**Results**:
- `Mod+Return`: Always opens terminal (from Nix, no override)
- `Mod+t`: Opens btop (from runtime config)
- `Control+1`:
  - When nixos project active → Opens NixOS config editor (project override)
  - When no project active → Switches to workspace 1 (runtime config)

#### Example 2: Window Rule Precedence

**Nix Config** (Level 1):
```nix
# Base floating rule for all calculators
windowRules = [
  { criteria = { app_id = "Calculator"; }; actions = [ "floating enable" ]; }
];
```

**Runtime Config** (Level 2):
```json
// ~/.config/sway/window-rules.json
{
  "rules": [
    {
      "id": "rule-calculator",
      "criteria": { "app_id": "^org\\.gnome\\.Calculator$" },
      "actions": ["floating enable", "resize set 400 300", "move position center"],
      "scope": "global"
    }
  ]
}
```

**Project Override** (Level 3):
```json
// ~/.config/sway/projects/data-science.json
{
  "window_rule_overrides": [
    {
      "base_rule_id": "rule-calculator",
      "override_properties": {
        "actions": ["floating enable", "resize set 800 600", "move workspace 4"]
      }
    }
  ]
}
```

**Results**:
- When data-science project active:
  - Calculator: Floating, 800x600, workspace 4 (project override)
- When no project active:
  - Calculator: Floating, 400x300, centered (runtime config)
- Nix rule is overridden by runtime config (more specific)

### Checking Configuration Precedence

Use these commands to understand which configuration is active:

```bash
# Show all configuration with source attribution
i3pm config show --sources

# Show conflicts between precedence levels
i3pm config conflicts

# Show configuration for specific project context
i3pm config show --project nixos
```

**Example Output**:
```
═══════════════════════════════════════════════════════════════
                    KEYBINDINGS
═══════════════════════════════════════════════════════════════
Key Combo     Command                    Source    File
───────────────────────────────────────────────────────────────
Mod+Return    exec terminal              nix       sway.nix:22
Control+1     workspace number 1         runtime   keybindings.toml:5
Mod+t         exec btop                  runtime   keybindings.toml:12
───────────────────────────────────────────────────────────────

Active Project: none
Config Version: a1b2c3d
```

### Configuration Conflict Detection

The system automatically detects conflicts when the same setting is defined at multiple precedence levels:

```bash
i3pm config conflicts
```

**Example Output**:
```
═══════════════════════════════════════════════════════════════
                 CONFIGURATION CONFLICTS
═══════════════════════════════════════════════════════════════

⚠️  Keybinding: Control+1

  Source      Value                    File                Active
  ────────────────────────────────────────────────────────────
  nix         workspace number 1       sway.nix:45         ✗
  runtime     workspace number 1       keybindings.toml:5  ✓

  Resolution: Runtime config takes precedence (higher priority)
  Severity: Warning

───────────────────────────────────────────────────────────────

Total Conflicts: 1
```

### Decision Tree: Where Should This Setting Go?

Use this flowchart to decide where to place a configuration setting:

```
Is this setting system-wide and stable?
  YES → Use Nix Config (Level 1)
    Examples: Package installation, service startup, display managers

  NO ↓

Does this setting change frequently during development?
  YES → Use Runtime Config (Level 2)
    Examples: Keybindings, window rules, color schemes

  NO ↓

Does this setting only apply when working on a specific project?
  YES → Use Project Override (Level 3)
    Examples: Project-specific keybindings, workspace layouts

  NO → Use Runtime Config (Level 2) as default
```

### Best Practices

1. **Nix for System Stability**
   - Use for packages, services, and system-level settings
   - Avoid frequently changing settings in Nix (requires rebuild)

2. **Runtime for Personal Customization**
   - Use for keybindings, window rules, and personal preferences
   - Changes take effect immediately without rebuild

3. **Projects for Context-Aware Behavior**
   - Use for project-specific workflows
   - Automatically apply/remove when switching projects

4. **Avoid Conflicts**
   - Don't duplicate settings across levels unless intentional
   - Use `i3pm config conflicts` to detect and resolve conflicts
   - Document overrides with comments explaining why

---

## Troubleshooting

### Configuration Doesn't Reload

**Check daemon status**:
```bash
i3pm daemon status
```

**Check file watcher**:
```bash
i3pm config watch status
```

**Manually trigger reload**:
```bash
i3pm config reload
```

**Check daemon logs**:
```bash
journalctl --user -u i3-project-event-listener -n 50
```

---

### Validation Errors

**Common syntax errors**:

❌ **Invalid keybinding syntax**:
```toml
"Mod++Return" = { command = "exec terminal" }  # Double +
```

✅ **Correct syntax**:
```toml
"Mod+Return" = { command = "exec terminal" }   # Single +
```

❌ **Invalid window criteria regex**:
```json
{
  "criteria": {
    "app_id": "^calc["  // Unclosed bracket
  }
}
```

✅ **Valid regex**:
```json
{
  "criteria": {
    "app_id": "^calc.*"
  }
}
```

---

### Keybinding Doesn't Work

1. **Check binding is loaded**:
   ```bash
   i3pm config show --category keybindings | grep "Mod+t"
   ```

2. **Check for conflicts**:
   ```bash
   i3pm config conflicts
   ```

3. **Test Sway directly**:
   ```bash
   swaymsg bindsym Mod+t exec btop
   ```

4. **Reload Sway config**:
   ```bash
   i3pm config reload --files keybindings
   ```

---

### Configuration Conflict Resolution

When you see conflicts in `i3pm config conflicts`, here's how to resolve them:

**Scenario 1: Same Keybinding, Different Commands**
```
⚠️  Keybinding: Mod+n

  Source      Value                    File                Active
  ────────────────────────────────────────────────────────────
  nix         exec nautilus            sway.nix:50         ✗
  runtime     exec nvim                keybindings.toml:8  ✓
```

**Resolution Options**:
1. **Keep runtime config** (default): Runtime takes precedence, nvim will execute
2. **Remove from runtime**: Delete line from `keybindings.toml` to use Nix version
3. **Remove from Nix**: Update `sway.nix` to remove the binding (requires rebuild)

**Scenario 2: Project Override Not Working**
```bash
# Check active project
i3pm project current

# Verify project override syntax
cat ~/.config/sway/projects/nixos.json

# Reload configuration
i3pm config reload

# Test in project context
i3pm config show --project nixos
```

**Scenario 3: Conflicting Window Rules**
```
⚠️  Window Rule: Calculator (app_id: org.gnome.Calculator)

  Multiple rules match the same window:
  - rule-calculator-global (priority: 100)
  - rule-calculator-nixos (priority: 150, project: nixos)
```

**Resolution**: Higher priority wins. Project-specific rules have higher precedence when that project is active.

---

### Window Rule Not Applying

1. **Verify window's app_id**:
   ```bash
   swaymsg -t get_tree | jq '.. | select(.app_id?) | {app_id, title}'
   ```

2. **Check rule syntax**:
   ```bash
   i3pm config validate --files window-rules
   ```

3. **Test rule manually**:
   ```bash
   swaymsg "[app_id=\"org.gnome.Calculator\"] floating enable"
   ```

4. **Check project context** (if rule is project-scoped):
   ```bash
   i3pm project current
   ```

---

## Project-Specific Configuration Overrides

**Feature 047 User Story 3**: Define project-specific window rules and keybindings that automatically apply when you switch to a project.

### Overview

Projects can override global configuration with project-specific behavior:
- **Window rule overrides**: Modify or add window rules for specific projects
- **Keybinding overrides**: Change keybindings per-project (e.g., `Mod+t` opens terminal in project directory)

### Example: Project Configuration with Overrides

Edit your project configuration:

```bash
# Edit project file
nvim ~/.config/i3/projects/nixos.json
```

Add window rule and keybinding overrides:

```json
{
  "name": "nixos",
  "display_name": "NixOS Configuration",
  "directory": "/etc/nixos",
  "icon": "❄️",
  "created_at": "2025-10-29T00:00:00Z",
  "updated_at": "2025-10-29T12:00:00Z",

  "window_rule_overrides": [
    {
      "base_rule_id": "calculator-float",
      "override_properties": {
        "actions": ["floating enable", "resize set 400 600", "move position center"],
        "priority": 50
      },
      "enabled": true
    },
    {
      "base_rule_id": null,
      "override_properties": {
        "criteria": {
          "app_id": "org.gnome.Nautilus"
        },
        "actions": ["floating enable", "move workspace 8"],
        "priority": 60
      },
      "enabled": true
    }
  ],

  "keybinding_overrides": {
    "Mod+t": {
      "key_combo": "Mod+t",
      "command": "exec ghostty --working-directory=/etc/nixos",
      "description": "Open terminal in NixOS directory",
      "enabled": true
    },
    "Mod+e": {
      "key_combo": "Mod+e",
      "command": "exec code /etc/nixos",
      "description": "Open VS Code in NixOS directory",
      "enabled": true
    }
  }
}
```

### Window Rule Override Types

1. **Override existing global rule** (modify behavior):
   ```json
   {
     "base_rule_id": "calculator-float",
     "override_properties": {
       "actions": ["floating enable", "resize set 800 600"],
       "priority": 50
     },
     "enabled": true
   }
   ```

2. **Create new project-specific rule** (no base_rule_id):
   ```json
   {
     "base_rule_id": null,
     "override_properties": {
       "criteria": {"app_id": "myapp"},
       "actions": ["move workspace 5"],
       "priority": 60
     },
     "enabled": true
   }
   ```

### Keybinding Override Format

```json
{
  "key_combo": "Mod+t",
  "command": "exec ghostty --working-directory=$PROJECT_DIR",
  "description": "Terminal in project directory",
  "enabled": true
}
```

**To disable a keybinding**: Set `"enabled": false` or `"command": null`

### Testing Project Overrides

1. **Switch to project**:
   ```bash
   pswitch nixos
   ```

2. **Launch application** (e.g., calculator):
   - Window rules from project overrides apply automatically

3. **Use overridden keybinding**:
   - `Mod+t` opens terminal in `/etc/nixos`

4. **View active configuration**:
   ```bash
   i3pm config show --project=nixos
   ```

### Precedence Rules

Configuration precedence (highest to lowest):

1. **Project overrides** (Level 3) - `~/.config/i3/projects/<name>.json`
2. **Runtime config** (Level 2) - `~/.config/sway/*.{toml,json}`
3. **Nix base config** (Level 1) - `home-modules/desktop/sway.nix`

**Example**:
- Global rule: Calculator floats at 400x400
- Project override: Calculator floats at 800x600
- **Result**: When project active, calculator is 800x600

### Validation

Project overrides are validated on reload:

```bash
# Validate project configuration
i3pm config validate --files projects

# Show validation errors
i3pm config show --project=nixos --json | jq '.errors'
```

**Common validation errors**:
- `base_rule_id` references non-existent global rule
- Invalid key combo syntax in keybinding override
- Missing required fields in override_properties

### Troubleshooting

**Override not applying**:
```bash
# 1. Check project is active
i3pm project current

# 2. Reload configuration
i3pm config reload

# 3. Check for validation errors
i3pm config validate

# 4. View active rules for project
i3pm config show --project=nixos
```

**Rule conflicts**:
```bash
# Check for conflicting rules
i3pm config conflicts
```

---

## Periodic Configuration Validation

**Feature 047 Phase 8 T059**: Automatic daily validation to detect configuration drift.

The system includes a systemd timer that runs configuration validation daily (by default) to catch errors before you manually reload.

### Check Timer Status

```bash
# Check if timer is active
systemctl --user status sway-config-validation.timer

# View timer schedule
systemctl --user list-timers sway-config-validation

# Check last validation result
systemctl --user status sway-config-validation.service
```

### Manual Validation

Trigger validation manually anytime:

```bash
# Run validation service manually
systemctl --user start sway-config-validation.service

# Check result
systemctl --user status sway-config-validation.service
```

### Configuration

Periodic validation is configured in your NixOS configuration:

```nix
programs.sway-config-manager = {
  enable = true;

  # Enable periodic validation (default: true)
  enablePeriodicValidation = true;

  # Validation interval (default: "daily")
  # Can be any systemd.time calendar format
  validationInterval = "daily";  # Or: "weekly", "Mon *-*-* 09:00:00", etc.
};
```

**Benefits**:
- Catch syntax errors early (before manual reload)
- Desktop notification if validation fails
- Zero performance impact (runs only once per day)
- Helps maintain configuration health

---

## Performance Tips

- **File watcher debounce**: Adjust if you're making rapid edits
  ```bash
  i3pm config watch start --debounce 1000  # 1 second delay
  ```

- **Validate before saving**: Use editor integration
  ```vim
  autocmd BufWritePre keybindings.toml !i3pm config validate --files keybindings
  ```

- **Batch changes**: Edit multiple files, then reload once
  ```bash
  i3pm config reload --files keybindings,window-rules
  ```

- **Monitor reload performance**: Check daemon logs for timing
  ```bash
  journalctl --user -u sway-config-manager -n 20 | grep "reload time"
  ```

- **Reduce validation overhead**: Disable Sway IPC validation if not needed
  ```bash
  # Validate structure only (faster)
  i3pm config validate --skip-sway-ipc
  ```

---

## Advanced Usage

### Auto-Reload on Git Pull

```bash
# In /etc/nixos/.git/hooks/post-merge
#!/bin/bash
if git diff --name-only HEAD@{1} HEAD | grep -q "user-config/sway/"; then
  echo "Sway config changed, reloading..."
  i3pm config reload
fi
```

### Configuration Backup Script

```bash
#!/bin/bash
# backup-sway-config.sh

BACKUP_DIR="$HOME/config-backups/sway"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
tar -czf "$BACKUP_DIR/sway-config-$TIMESTAMP.tar.gz" \
  ~/.config/sway/keybindings.toml \
  ~/.config/sway/window-rules.json \
  ~/.config/sway/workspace-assignments.json \
  ~/.config/sway/projects/

echo "Backup saved: $BACKUP_DIR/sway-config-$TIMESTAMP.tar.gz"
```

### Configuration Migration

```bash
# Migrate from Nix-only config to dynamic config

# 1. Extract current keybindings from Nix
grep "bindsym" ~/.config/sway/config > keybindings-extracted.txt

# 2. Convert to TOML format (manual or script)

# 3. Add to runtime config
cat keybindings-converted.toml >> ~/.config/sway/keybindings.toml

# 4. Validate and reload
i3pm config validate && i3pm config reload

# 5. Remove from Nix if desired (keep base only)
```

---

## Next Steps

- **Read full documentation**: `/etc/nixos/specs/047-create-a-new/plan.md`
- **Explore data models**: `/etc/nixos/specs/047-create-a-new/data-model.md`
- **API contracts**: `/etc/nixos/specs/047-create-a-new/contracts/`
- **Configure projects**: `i3pm project create --help`

---

## Success Metrics

Track your configuration management efficiency:

- **Configuration iteration time**: Target <10 seconds (vs 120 seconds for rebuild)
- **Validation accuracy**: 100% syntax error detection, 80%+ semantic error detection
- **Rollback speed**: <3 seconds to restore previous version
- **User confidence**: Experiment freely with instant rollback safety net

**Feedback**: Report issues or suggest improvements at `https://github.com/yourusername/nixos-config/issues`
