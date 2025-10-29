# Sway Configuration Architecture

## Configuration Responsibility Boundaries

This document defines the clear separation between Nix-managed static settings and Python-managed dynamic runtime behavior in the Sway configuration system.

### Decision Tree: Where Should This Setting Go?

```
Is it a system-level setting?
├─ YES → Nix (system packages, window manager binary, systemd services)
└─ NO → Continue...

Does it change frequently during development/work?
├─ YES → Runtime (TOML/JSON files managed by sway-config-manager)
└─ NO → Continue...

Does it need to be version-controlled and reproducible?
├─ YES → Nix (part of system configuration)
└─ NO → Continue...

Does it depend on the active project context?
├─ YES → Project overrides (JSON files in ~/.config/sway/projects/)
└─ NO → Continue...

Does it need instant reload without rebuild?
├─ YES → Runtime (TOML/JSON files)
└─ NO → Nix
```

## Configuration Categories

### 1. Nix-Managed Settings (Static, System-Level)

**Location**: `/etc/nixos/home-modules/desktop/`

**Characteristics**:
- System packages and binaries
- Systemd services configuration
- Home-manager modules
- Display manager settings
- Environment variables
- Default configuration templates

**Examples**:
```nix
# System packages
programs.sway.enable = true;
home.packages = [ pkgs.sway pkgs.swaylock ];

# Systemd services
systemd.user.services.sway-config-manager = { ... };

# Default templates (copied to ~/.config/sway/ on first run)
xdg.configFile."sway/keybindings.toml" = {
  source = ./sway-default-keybindings.toml;
  force = false;  # Don't overwrite user changes
};
```

**When to Use Nix**:
- Installing Sway and related packages
- Configuring systemd services
- Setting up default configuration templates
- Defining environment variables
- System-wide settings that require rebuild

**Rebuilding**: Required via `nixos-rebuild switch`

---

### 2. Runtime-Managed Settings (Dynamic, Hot-Reload)

**Location**: `~/.config/sway/`

**Characteristics**:
- User-editable TOML/JSON files
- Hot-reloadable without rebuild
- Instant changes (< 5 seconds)
- Git version-controlled for rollback

**Examples**:

#### Keybindings (`keybindings.toml`)
```toml
[keybindings]
"Mod+Return" = { command = "exec ghostty", description = "Launch terminal" }
"Mod+d" = { command = "exec walker", description = "Launch application finder" }
"Mod+1" = { command = "workspace number 1", description = "Focus workspace 1" }
```

#### Window Rules (`window-rules.json`)
```json
{
  "version": "1.0",
  "rules": [
    {
      "criteria": { "app_id": "org.gnome.Calculator" },
      "action": { "floating": true, "resize": { "width": 400, "height": 500 } }
    }
  ]
}
```

#### Workspace Assignments (`workspace-assignments.json`)
```json
{
  "version": "1.0",
  "assignments": [
    {
      "workspace": "1",
      "output": "DP-1"
    }
  ]
}
```

**When to Use Runtime Files**:
- Keybindings you change frequently
- Window rules for specific applications
- Workspace-to-monitor mappings
- Settings that need instant reload

**Reloading**: Via `swayconfig reload` (< 5 seconds)

---

### 3. Project-Specific Overrides (Context-Aware)

**Location**: `~/.config/sway/projects/<project-name>.json`

**Characteristics**:
- Override global settings per project
- Automatically applied when project is active
- Higher precedence than runtime settings

**Example** (`~/.config/sway/projects/nixos.json`):
```json
{
  "name": "nixos",
  "display_name": "NixOS Configuration",
  "directory": "/etc/nixos",
  "window_rule_overrides": [
    {
      "base_rule_id": "calculator-float",
      "override_properties": {
        "resize": { "width": 600, "height": 800 }
      }
    }
  ],
  "keybinding_overrides": {
    "Mod+g": {
      "command": "exec ghostty -e lazygit",
      "description": "Launch lazygit in project directory"
    }
  }
}
```

**When to Use Project Overrides**:
- Different keybindings for different projects
- Project-specific window behavior
- Context-aware automation

**Activation**: Automatic when project is active via `i3pm project switch`

---

## Precedence Rules

When the same setting is defined in multiple places:

```
Nix (Precedence 1 - Base)
  ↓ Overridden by
Runtime TOML/JSON (Precedence 2 - User Defaults)
  ↓ Overridden by
Project Overrides (Precedence 3 - Context)
```

**Example Scenario**:
- Nix defines default terminal: `ghostty`
- Runtime keybindings.toml overrides `Mod+Return` to: `exec wezterm`
- Project `nixos` overrides `Mod+Return` to: `exec ghostty -e tmux`

**Result when "nixos" project is active**: `Mod+Return` launches `ghostty -e tmux`
**Result when no project is active**: `Mod+Return` launches `wezterm`

---

## Configuration Flow

```
┌─────────────────────────────────────────────┐
│  Nix Configuration (Static Base)           │
│  • System packages                          │
│  • Systemd services                         │
│  • Default templates                        │
└─────────────────┬───────────────────────────┘
                  │
                  ↓ (Copy defaults on first run)
┌─────────────────────────────────────────────┐
│  Runtime Configuration (User Editable)      │
│  • ~/.config/sway/keybindings.toml          │
│  • ~/.config/sway/window-rules.json         │
│  • ~/.config/sway/workspace-assignments.json│
└─────────────────┬───────────────────────────┘
                  │
                  ↓ (Merge on config reload)
┌─────────────────────────────────────────────┐
│  Configuration Merger                       │
│  • Load Nix base + Runtime + Project        │
│  • Apply precedence rules                   │
│  • Detect conflicts                         │
└─────────────────┬───────────────────────────┘
                  │
                  ↓ (Validate before apply)
┌─────────────────────────────────────────────┐
│  Configuration Validator                    │
│  • Structural validation (JSON Schema)      │
│  • Semantic validation (Sway IPC queries)   │
│  • Keybinding syntax checks                 │
└─────────────────┬───────────────────────────┘
                  │
                  ↓ (Apply to Sway)
┌─────────────────────────────────────────────┐
│  Sway Window Manager (Live State)          │
│  • Keybindings active                       │
│  • Window rules applied                     │
│  • Workspaces assigned to outputs           │
└─────────────────────────────────────────────┘
```

---

## Common Scenarios

### Scenario 1: Changing a Keybinding

**Question**: I want to change `Mod+Return` to launch a different terminal.

**Answer**: Edit `~/.config/sway/keybindings.toml`:
```toml
"Mod+Return" = { command = "exec wezterm", description = "Launch Wezterm" }
```

Run: `swayconfig reload`

**Why not Nix?**: Keybindings change frequently during workflow tuning. Reloading via Nix would require a full system rebuild (minutes) instead of hot-reload (< 5 seconds).

---

### Scenario 2: Installing a New Application

**Question**: I want to use a new application (e.g., Alacritty).

**Answer**: Add to Nix configuration:
```nix
home.packages = [ pkgs.alacritty ];
```

Run: `nixos-rebuild switch`

Then configure keybinding in `keybindings.toml`:
```toml
"Mod+Shift+Return" = { command = "exec alacritty", description = "Launch Alacritty" }
```

Run: `swayconfig reload`

**Why Nix for package?**: Package installation requires system-level changes (adding to PATH, desktop files, etc.) which are managed by Nix.

**Why Runtime for keybinding?**: Keybinding is user preference that changes frequently.

---

### Scenario 3: Project-Specific Terminal Command

**Question**: When working on "nixos" project, I want `Mod+g` to launch lazygit in the project directory.

**Answer**: Edit `~/.config/sway/projects/nixos.json`:
```json
{
  "keybinding_overrides": {
    "Mod+g": {
      "command": "exec ghostty -e 'cd /etc/nixos && lazygit'",
      "description": "Launch lazygit in NixOS directory"
    }
  }
}
```

Switch to project: `i3pm project switch nixos`

**Why project override?**: Context-specific behavior that only applies to one project.

---

### Scenario 4: System-Wide Window Rule

**Question**: I want all calculator windows to float.

**Answer**: Edit `~/.config/sway/window-rules.json`:
```json
{
  "rules": [
    {
      "id": "calculator-float",
      "criteria": { "app_id": "org.gnome.Calculator" },
      "action": { "floating": true }
    }
  ]
}
```

Run: `swayconfig reload`

**Why not Nix?**: Window rules are user preferences that may change based on workflow.

---

## Troubleshooting

### Problem: Setting Not Taking Effect

**Diagnosis Steps**:
1. Check which layer defined the setting:
   ```bash
   swayconfig show --sources
   ```

2. Check for conflicts:
   ```bash
   swayconfig conflicts
   ```

3. Check precedence:
   - Nix base (precedence 1)
   - Runtime files (precedence 2)
   - Project overrides (precedence 3)

4. Verify file syntax:
   ```bash
   swayconfig validate
   ```

---

### Problem: Change Requires Rebuild When It Shouldn't

**Diagnosis**:
- Is the setting in Nix configuration?
- Move it to runtime files (`keybindings.toml`, `window-rules.json`)
- Reload via `swayconfig reload` instead of `nixos-rebuild switch`

---

### Problem: Project Override Not Applying

**Diagnosis**:
1. Check project is active:
   ```bash
   i3pm project current
   ```

2. Verify override syntax in project JSON file

3. Check daemon logs:
   ```bash
   journalctl --user -u sway-config-manager -f
   ```

---

## Best Practices

### 1. Use Nix For:
- ✅ System packages (`programs.sway.enable`)
- ✅ Systemd services (`systemd.user.services`)
- ✅ Default configuration templates (copied on first run)
- ✅ Environment variables (`home.sessionVariables`)

### 2. Use Runtime Files For:
- ✅ Keybindings that change frequently
- ✅ Window rules for specific applications
- ✅ Workspace-to-monitor assignments
- ✅ Settings that need instant reload

### 3. Use Project Overrides For:
- ✅ Context-specific keybindings
- ✅ Project-aware window behavior
- ✅ Workflow automation per project

### 4. Version Control:
- ✅ Nix configuration: Git repository (`/etc/nixos/`)
- ✅ Runtime files: Git repository (`~/.config/sway/`)
- ✅ Use `swayconfig rollback` for instant rollback

### 5. Testing Changes:
- ✅ Runtime changes: `swayconfig validate` → `swayconfig reload`
- ✅ Nix changes: `nixos-rebuild dry-build` → `nixos-rebuild switch`

---

## Reference

### Configuration Files

| File | Location | Purpose | Reload Method |
|------|----------|---------|---------------|
| `sway.nix` | `/etc/nixos/home-modules/desktop/` | Sway package and service | `nixos-rebuild switch` |
| `sway-config-manager.nix` | `/etc/nixos/home-modules/desktop/` | Config manager service | `nixos-rebuild switch` |
| `keybindings.toml` | `~/.config/sway/` | Keybinding definitions | `swayconfig reload` |
| `window-rules.json` | `~/.config/sway/` | Window behavior rules | `swayconfig reload` |
| `workspace-assignments.json` | `~/.config/sway/` | Workspace-to-output mappings | `swayconfig reload` |
| `projects/<name>.json` | `~/.config/sway/projects/` | Project-specific overrides | Automatic on project switch |

### CLI Commands

| Command | Purpose |
|---------|---------|
| `swayconfig reload` | Hot-reload configuration (< 5s) |
| `swayconfig validate` | Check configuration syntax |
| `swayconfig show --sources` | Display active config with sources |
| `swayconfig conflicts` | Show configuration conflicts |
| `swayconfig rollback <commit>` | Rollback to previous version |
| `swayconfig versions` | List configuration history |
| `i3pm project switch <name>` | Activate project (applies overrides) |

---

**Last Updated**: 2025-10-29
**Feature**: 047 - Dynamic Sway Configuration Management
**Author**: Claude Code
