# Data Model: NixOS Configuration Entities

**Feature**: 009-let-s-create
**Date**: 2025-10-17
**Status**: Phase 1 Design

## Overview

This document defines the configuration entities and their relationships for the NixOS KDE Plasma to i3wm migration. Unlike traditional applications with databases, this is a declarative system configuration model where "entities" represent configuration structures, modules, and their composition relationships.

## Entity Definitions

### 1. Platform Configuration

A **Platform Configuration** represents a complete NixOS system configuration for a specific deployment target (hardware + software stack).

**Attributes**:
- `name`: string (e.g., "hetzner-i3", "m1", "container")
- `hostname`: string (e.g., "nixos-hetzner", "nixos-m1")
- `system`: enum { "x86_64-linux", "aarch64-linux" }
- `imports`: list of module paths
- `overrides`: map of NixOS options to values
- `isPrimary`: boolean (true for hetzner-i3.nix)
- `parentConfig`: optional reference to another Platform Configuration

**Relationships**:
- **Imports** multiple **Desktop Modules**, **Service Modules**, **Hardware Modules**
- **Extends** zero or one parent **Platform Configuration** (inheritance)
- **Defined in** flake.nix as nixosConfigurations entry

**Lifecycle**:
- Created during initial setup or configuration addition
- Modified when platform requirements change
- Removed when platform is deprecated

**Validation Rules**:
- Must have unique `name` within flake.nix
- Must import at least base.nix or a parent configuration
- System architecture must match hardware platform
- If `parentConfig` is set, imports list must include parent config file

---

### 2. Desktop Module

A **Desktop Module** encapsulates desktop environment functionality (window manager, display server, peripheral services).

**Attributes**:
- `modulePath`: string (e.g., "modules/desktop/i3wm.nix")
- `enable`: boolean option (exposed via NixOS module system)
- `displayServer`: enum { "X11", "Wayland", "None" }
- `windowManager`: enum { "i3", "KDE Plasma", "sway", "None" }
- `packages`: list of Nix packages
- `configFiles`: map of file paths to content
- `services`: list of systemd service definitions
- `conditionalFeatures`: map of conditions to feature sets

**Relationships**:
- **Imported by** one or more **Platform Configurations**
- **Depends on** zero or more **Service Modules** (e.g., xrdp for remote access)
- **Generates** configuration files in /etc
- **Provides** packages to environment.systemPackages
- **Integrates with** **Home Manager Modules** for user-specific configuration

**State Transitions**:
```
Created → Enabled → Configured → Active → Deprecated → Removed
```

**Validation Rules**:
- If `displayServer` is "X11", must enable services.xserver
- If `displayServer` is "Wayland", must not enable services.xserver
- `packages` list must not be empty if `enable` is true
- `configFiles` must generate syntactically valid configuration

**Current Instances**:
- `modules/desktop/i3wm.nix` (✅ Active)
- `modules/desktop/kde-plasma.nix` (🗑️ To Remove)
- `modules/desktop/kde-plasma-vm.nix` (🗑️ To Remove)
- `modules/desktop/mangowc.nix` (🗑️ To Remove)
- `modules/desktop/wayland-remote-access.nix` (🗑️ To Remove)

---

### 3. Service Module

A **Service Module** provides system-level functionality (networking, development tools, authentication).

**Attributes**:
- `modulePath`: string (e.g., "modules/services/onepassword.nix")
- `enable`: boolean option
- `hasGuiComponent`: boolean
- `hasCliComponent`: boolean
- `packages`: list of Nix packages (may differ by GUI/CLI mode)
- `systemdServices`: list of systemd service definitions
- `conditionalLogic`: map of system capabilities to feature sets

**Relationships**:
- **Imported by** one or more **Platform Configurations**
- **May depend on** **Desktop Modules** (for GUI components)
- **Provides** system-level services
- **May integrate with** **Home Manager Modules** for user-specific configuration

**Conditional Feature Pattern**:
```nix
let
  hasGui = config.services.xserver.enable or false;
in {
  environment.systemPackages = with pkgs; [
    package-cli  # Always installed
  ] ++ lib.optionals hasGui [
    package-gui  # Only with GUI
  ];
}
```

**Validation Rules**:
- If `hasGuiComponent` and `hasCliComponent` are both false, module is invalid
- If `hasGuiComponent` is true, must check for GUI availability before enabling GUI features
- `packages` list must include at least CLI or GUI variant

**Current Instances**:
- `modules/services/onepassword.nix` (✅ Active, supports both GUI and CLI)
- `modules/services/development.nix` (✅ Active, CLI-focused)
- `modules/services/networking.nix` (✅ Active, system services)

---

### 4. Home Manager Module

A **Home Manager Module** defines user-specific configuration (dotfiles, user services, desktop customization).

**Attributes**:
- `modulePath`: string (e.g., "home-modules/desktop/i3.nix")
- `category`: enum { "desktop", "tools", "shell", "terminal", "editors" }
- `configFiles`: map of paths to generated content
- `packages`: list of user-level packages
- `services`: list of systemd user services
- `environmentVariables`: map of environment variables

**Relationships**:
- **Associated with** **Platform Configuration** via home-manager.users.<username>
- **May depend on** **Desktop Modules** for system-level desktop environment
- **Generates** files in user home directory (~/.config, ~/.local, etc.)
- **Starts** systemd user services

**Lifecycle**:
- Created during initial user environment setup
- Modified when user preferences change
- Removed when feature is deprecated

**Validation Rules**:
- `configFiles` must not conflict with system-generated files in /etc
- User services must not conflict with system services
- Must declare inputs: `{ config, lib, pkgs, ... }`

**Current Instances (Desktop Category)**:
- `home-modules/desktop/i3.nix` (✅ Active)
- `home-modules/desktop/i3wsr.nix` (✅ Active)
- `home-modules/desktop/plasma-config.nix` (🗑️ To Remove)
- `home-modules/desktop/plasma-sync.nix` (🗑️ To Remove)
- `home-modules/desktop/touchpad-gestures.nix` (🗑️ To Remove, Wayland-specific)

---

### 5. Configuration File

A **Configuration File** represents a generated system or user configuration file.

**Attributes**:
- `filePath`: string (e.g., "/etc/i3/config", "~/.config/alacritty/alacritty.yml")
- `generationMethod`: enum { "environment.etc", "home.file", "xdg.configFile" }
- `content`: string (Nix expression evaluating to file content)
- `permissions`: octal mode (e.g., "0644", "0755")
- `owner`: optional string (for environment.etc files)

**Relationships**:
- **Generated by** **Desktop Module**, **Service Module**, or **Home Manager Module**
- **Read by** system services or user applications
- **May include** other configuration files (e.g., i3 config includes web-apps.conf)

**Validation Rules**:
- `filePath` must be absolute (for system) or relative to HOME (for user)
- `content` must evaluate to valid string
- `permissions` must be valid octal mode
- Files in /etc must use `environment.etc`, files in ~/ must use `home.file` or `xdg.configFile`

**State Transitions**:
```
Defined → Generated (during build) → Deployed (on system) → Updated → Removed
```

**Key Instances**:
- `/etc/i3/config` (Generated by modules/desktop/i3wm.nix)
- `/etc/i3status.conf` (Generated by modules/desktop/i3wm.nix)
- `~/.config/i3/config` (Generated by home-modules/desktop/i3.nix)
- `~/.config/i3wsr/config.toml` (Generated by home-modules/desktop/i3wsr.nix)

---

### 6. Documentation File

A **Documentation File** provides technical guidance for configuration, setup, and usage.

**Attributes**:
- `filePath`: string (e.g., "docs/ARCHITECTURE.md", "CLAUDE.md")
- `category`: enum { "Architecture", "Setup", "Feature", "Migration", "Reference" }
- `relevance`: enum { "Active", "Obsolete", "Historical" }
- `referencedConfigurations`: list of configuration names
- `lastUpdated`: date

**Relationships**:
- **Documents** one or more **Platform Configurations**, **Modules**, or **Features**
- **May reference** other **Documentation Files**
- **Updated with** related code changes

**Lifecycle**:
```
Created → Active → Updated → Obsolete → Removed (or marked Historical)
```

**Validation Rules**:
- `relevance` must be "Obsolete" if `referencedConfigurations` contains only removed configurations
- Files with `relevance` = "Obsolete" should be removed unless historical value justifies retention

**Classification for Migration**:

**To Remove** (Obsolete, no historical value):
- `docs/PLASMA_CONFIG_STRATEGY.md` - KDE Plasma-specific
- `docs/PLASMA_MANAGER.md` - plasma-manager usage
- `docs/IPHONE_KDECONNECT_GUIDE.md` - KDE Connect integration

**To Update** (Active, needs i3wm context):
- `CLAUDE.md` - LLM navigation guide
- `docs/ARCHITECTURE.md` - System architecture
- `docs/M1_SETUP.md` - M1 platform setup
- `docs/PWA_SYSTEM.md` - PWA management system
- `docs/PWA_COMPARISON.md` - PWA implementation comparison
- `docs/PWA_PARAMETERIZATION.md` - PWA configuration patterns

**To Create**:
- `docs/MIGRATION.md` - KDE Plasma → i3wm migration guide
- `docs/I3WM_SETUP.md` - i3wm configuration guide (optional, post-migration)

---

## Entity Relationships Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     flake.nix                                │
│  Defines nixosConfigurations and homeConfigurations          │
└───────────┬────────────────────────────────────┬────────────┘
            │                                    │
            ▼                                    ▼
┌───────────────────────────┐      ┌────────────────────────────┐
│ Platform Configuration    │      │ Home Configuration         │
│  (e.g., hetzner-i3.nix)  │      │  (home-vpittamp.nix)       │
│                           │      │                            │
│  - name                   │      │  - username                │
│  - hostname               │      │  - imports                 │
│  - system (arch)          │      │  - packages                │
│  - imports ───────────────┼──┐   │  - dotfiles                │
│  - overrides              │  │   └────┬──────────────────────┬┘
└───────────────────────────┘  │        │                      │
                               │        │ imports              │
                               │        ▼                      ▼
                               │  ┌──────────────────┐ ┌───────────────────┐
                               │  │ Home Module      │ │ Home Module       │
                               │  │  i3.nix          │ │  i3wsr.nix        │
                               │  ├──────────────────┤ ├───────────────────┤
                               │  │ - configFiles    │ │ - configFiles     │
                               │  │ - packages       │ │ - packages        │
                               │  │ - services       │ │ - services        │
                               │  └──────────────────┘ └───────────────────┘
                               │
                               │ imports
                               ▼
┌────────────────────────────────────────────────────────────┐
│                    Desktop Module                          │
│                     i3wm.nix                               │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ options.services.i3wm                                 │ │
│  │  - enable: boolean                                    │ │
│  │  - package: package                                   │ │
│  │  - extraPackages: [package]                           │ │
│  └──────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ config (when enabled)                                 │ │
│  │  - services.xserver.enable = true                     │ │
│  │  - services.xserver.windowManager.i3.enable = true    │ │
│  │  - environment.systemPackages = [i3, rofi, alacritty]│ │
│  │  - environment.etc."i3/config".text = "..."          │ │
│  │  - environment.etc."i3status.conf".text = "..."      │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
                               │
                               │ generates
                               ▼
┌────────────────────────────────────────────────────────────┐
│             Configuration Files (System-level)             │
│                                                            │
│  /etc/i3/config          - i3 window manager config        │
│  /etc/i3status.conf      - i3status bar config             │
│  /etc/i3/scripts/*.sh    - Helper scripts                  │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│             Configuration Files (User-level)               │
│                                                            │
│  ~/.config/i3/config         - User-specific i3 config     │
│  ~/.config/i3wsr/config.toml - Workspace renaming config   │
│  ~/.config/i3/web-apps.conf  - PWA window rules            │
└────────────────────────────────────────────────────────────┘
```

---

## Configuration Inheritance Hierarchy

```
┌──────────────────────────────────────────────────────────────┐
│                    base.nix (Shared Base)                    │
│  - Core packages                                             │
│  - User account (vpittamp)                                   │
│  - Common system settings                                    │
│  - Nix configuration                                         │
└───────────────────────┬──────────────────────────────────────┘
                        │ imported by
                        │
        ┌───────────────┴───────────────┬─────────────────────┐
        │                               │                     │
        ▼                               ▼                     ▼
┌──────────────────┐       ┌─────────────────────┐   ┌─────────────────┐
│  hetzner-i3.nix  │       │  m1.nix             │   │  container.nix  │
│  (PRIMARY REF)   │       │  (EXTENDS PRIMARY)  │   │  (EXTENDS)      │
├──────────────────┤       ├─────────────────────┤   ├─────────────────┤
│ + i3wm.nix       │◄──────│ imports PRIMARY     │   │ imports PRIMARY │
│ + xrdp.nix       │       │ + m1 hardware       │   │ - GUI disabled  │
│ + development    │       │ + X11 DPI=180       │   │ - minimal pkgs  │
│ + networking     │       │ - xrdp (no remote)  │   │                 │
│ + onepassword    │       │ + Apple firmware    │   │                 │
└──────────────────┘       └─────────────────────┘   └─────────────────┘

Inheritance Rules:
- Child configs IMPORT parent
- Use lib.mkDefault in parent for overrideable values
- Use lib.mkForce in child for mandatory overrides
- Document every lib.mkForce with rationale comment
```

---

## State Transitions for Platform Configurations

```
┌─────────────┐
│   Planned   │ New platform identified, not yet implemented
└──────┬──────┘
       │ create configuration file
       ▼
┌─────────────┐
│   Defined   │ Configuration file exists in repo
└──────┬──────┘
       │ nixos-rebuild dry-build succeeds
       ▼
┌─────────────┐
│  Buildable  │ Configuration builds without errors
└──────┬──────┘
       │ nixos-rebuild switch succeeds
       ▼
┌─────────────┐
│   Active    │ System running this configuration
└──────┬──────┘
       │ requirements change or platform deprecated
       ▼
┌─────────────┐
│ Deprecated  │ Configuration no longer recommended
└──────┬──────┘
       │ remove from flake.nix and delete file
       ▼
┌─────────────┐
│   Removed   │ Configuration deleted, preserved in git history
└─────────────┘
```

**Migration State for 009 Feature**:
- hetzner-i3.nix: **Active** (already working)
- m1.nix: **Active** → **Refactoring** (needs to import hetzner-i3.nix)
- container.nix: **Active** → **Refactoring** (needs to import hetzner-i3.nix)
- hetzner.nix: **Active** → **Deprecated** → **Removed**
- hetzner-mangowc.nix: **Active** → **Deprecated** → **Removed**
- wsl.nix: **Deprecated** → **Removed**

---

## Configuration Composition Model

```
Flake Entry (nixosConfigurations.hetzner)
  │
  ├─> mkSystem helper function
  │     │
  │     ├─> base system modules (nixpkgs.lib.nixosSystem)
  │     ├─> specialArgs (inputs, pkgs-unstable)
  │     └─> modules list
  │           │
  │           ├─> configurations/hetzner-i3.nix
  │           │     │
  │           │     ├─> imports
  │           │     │     ├─> base.nix
  │           │     │     ├─> disko module
  │           │     │     ├─> modules/desktop/i3wm.nix
  │           │     │     ├─> modules/desktop/xrdp.nix
  │           │     │     ├─> modules/services/development.nix
  │           │     │     ├─> modules/services/networking.nix
  │           │     │     └─> modules/services/onepassword.nix
  │           │     │
  │           │     └─> config overrides
  │           │           ├─> networking.hostName
  │           │           ├─> boot.loader settings
  │           │           └─> platform-specific packages
  │           │
  │           └─> home-manager integration
  │                 │
  │                 └─> home-vpittamp.nix
  │                       │
  │                       ├─> home-modules/desktop/i3.nix
  │                       ├─> home-modules/desktop/i3wsr.nix
  │                       ├─> home-modules/tools/*.nix
  │                       └─> home-modules/terminal/*.nix
  │
  └─> Resulting NixOS system
        ├─> System packages (i3, rofi, alacritty, firefox, 1Password)
        ├─> System services (xserver, i3wm, xrdp, tailscale)
        ├─> Configuration files (/etc/i3/config, /etc/i3status.conf)
        └─> User environment (via home-manager)
              ├─> User packages
              ├─> Dotfiles (~/.config/i3/config, ~/.config/i3wsr/config.toml)
              └─> User services (i3wsr systemd service)
```

---

## Summary

This data model defines the key configuration entities for the NixOS migration:

1. **Platform Configurations**: System-level configs (hetzner-i3, m1, container) with inheritance relationships
2. **Desktop Modules**: Desktop environment functionality (i3wm) with conditional features
3. **Service Modules**: System services (onepassword, development, networking)
4. **Home Manager Modules**: User-specific configuration (i3 user config, i3wsr, tools)
5. **Configuration Files**: Generated system and user configuration files
6. **Documentation Files**: Technical guides with lifecycle management

The model emphasizes:
- **Modular Composition**: Entities compose to form complete system configurations
- **Inheritance**: Configurations extend a primary reference (hetzner-i3.nix)
- **Conditional Features**: Modules adapt based on system capabilities (GUI vs headless)
- **Clear Lifecycle**: State transitions from Defined → Buildable → Active → Deprecated → Removed
- **Validation Rules**: Each entity type has explicit validation requirements

**Next Step**: Create contracts/ directory with module interface contracts and migration checklist.
