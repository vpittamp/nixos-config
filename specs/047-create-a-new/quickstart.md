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

### 7. Rollback Configuration

If a change breaks something, instantly rollback:

```bash
# List recent versions
i3pm config list-versions --limit 5

# Rollback to previous version
i3pm config rollback <commit-hash>

# Example
i3pm config rollback f9e8d7c
```

**Output**:
```
🔄 Rolling back configuration...

Previous Version: a1b2c3d (Add custom keybindings)
Restored Version: f9e8d7c (Initial config)

Files Restored:
  • keybindings.toml

✅ Rollback complete (2.1 seconds)
✅ Configuration reloaded automatically
```

---

## Common Workflows

### Workflow 1: Experiment with Keybindings

```bash
# 1. Edit keybindings
i3pm config edit keybindings

# 2. Add experimental binding (e.g., Mod+Shift+t for terminal)

# 3. Save and test immediately (auto-reloads)

# 4. If you don't like it, rollback
i3pm config rollback HEAD~1
```

**Time saved**: ~2 minutes (vs NixOS rebuild)

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

Understanding which configuration takes priority:

```
Project Overrides  (highest priority)
    ↓
Runtime Config     (medium priority)
    ↓
Nix Base Config    (lowest priority, system defaults)
```

**Example**:
- Nix defines `Control+1 = workspace 1`
- Runtime config redefines `Control+1 = workspace 1` (same, no conflict)
- Project "nixos" overrides `Control+1 = exec nvim /etc/nixos/configuration.nix`
- **Result when nixos active**: `Control+1` opens NixOS config
- **Result when no project active**: `Control+1` switches to workspace 1

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
