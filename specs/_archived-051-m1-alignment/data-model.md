# Data Model: M1 Configuration Alignment

**Feature**: M1 Configuration Alignment with Hetzner-Sway
**Branch**: `051-the-hetzner-sway`
**Date**: 2025-10-30

## Overview

This document defines the configuration entities and their relationships for aligning the M1 MacBook Pro NixOS configuration with the hetzner-sway reference implementation. The data model focuses on module composition, import structures, and service configurations rather than runtime state.

## Core Entities

### 1. Platform Configuration

**Entity**: `PlatformConfiguration`

Represents a complete NixOS system configuration for a specific deployment target.

**Fields**:
- `name`: String - Configuration identifier (e.g., "hetzner-sway", "m1")
- `hostname`: String - System hostname
- `architecture`: Enum - "x86_64-linux" | "aarch64-linux"
- `deploymentContext`: Enum - "cloud-headless" | "laptop-physical"
- `baseImports`: List<ModulePath> - Core modules shared across platforms
- `serviceImports`: List<ModulePath> - Service modules for this platform
- `desktopImports`: List<ModulePath> - Desktop environment modules
- `hardwareImports`: List<ModulePath> - Hardware-specific modules
- `platformSpecificSettings`: Map<String, Any> - Override configurations

**Relationships**:
- Has many: ServiceModule
- Has many: DesktopModule
- Has one: HardwareConfiguration
- Has one: HomeManagerConfiguration

**Validation Rules**:
- Must import base.nix
- architecture must match nixpkgs.hostPlatform
- serviceImports must not include hardware-specific modules
- desktopImports must not conflict (e.g., KDE + Sway)

**State Transitions**: N/A (static configuration)

**Example**:
```nix
{
  name = "m1";
  hostname = "nixos-m1";
  architecture = "aarch64-linux";
  deploymentContext = "laptop-physical";
  baseImports = [ ./base.nix ];
  serviceImports = [
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix  # ADDED in this feature
    ../modules/services/onepassword-automation.nix  # ADDED in this feature
  ];
  desktopImports = [
    ../modules/desktop/sway.nix
  ];
  hardwareImports = [
    ../hardware/m1.nix
    inputs.nixos-apple-silicon.nixosModules.default
  ];
}
```

---

### 2. Service Module

**Entity**: `ServiceModule`

Represents a reusable system service configuration module.

**Fields**:
- `path`: String - Absolute path to .nix file
- `name`: String - Module identifier (e.g., "i3-project-daemon", "onepassword")
- `architectureIndependent`: Boolean - Works on all architectures
- `requiresGui`: Boolean - Needs X11/Wayland environment
- `requiresHardware`: Enum - "none" | "physical-display" | "physical-audio" | "physical-input"
- `dependencies`: List<String> - Other required modules
- `conflicts`: List<String> - Incompatible modules
- `serviceConfiguration`: Map<String, Any> - systemd service settings
- `packageRequirements`: List<String> - Required nixpkgs packages

**Relationships**:
- Belongs to many: PlatformConfiguration
- May have: SystemdService

**Validation Rules**:
- architectureIndependent=false modules must specify supported architectures
- requiresGui=true modules must check for X11/Wayland availability
- dependencies must not create circular references
- conflicts must be mutual (if A conflicts with B, B must conflict with A)

**State Transitions**:
- `disabled` → `enabled` (added to platform imports)
- `enabled` → `disabled` (removed from platform imports)

**Examples**:
```nix
# i3-project-daemon.nix
{
  path = "/etc/nixos/modules/services/i3-project-daemon.nix";
  name = "i3-project-daemon";
  architectureIndependent = true;  # Python daemon, works on ARM64 and x86_64
  requiresGui = false;  # Uses i3/Sway IPC, not GUI-dependent
  requiresHardware = "none";  # Works headless and physical
  dependencies = [];  # No other module dependencies
  conflicts = [];
  serviceConfiguration = {
    enable = true;
    user = "vpittamp";
    logLevel = "INFO";
  };
  packageRequirements = [ "python311" "python311Packages.i3ipc" ];
}

# wayvnc.nix
{
  path = "/etc/nixos/modules/desktop/wayvnc.nix";
  name = "wayvnc";
  architectureIndependent = true;
  requiresGui = true;  # Needs Wayland compositor
  requiresHardware = "none";  # Works headless (virtual outputs)
  dependencies = [ "sway" ];  # Requires Sway or wlroots compositor
  conflicts = [ "xrdp" ];  # VNC vs RDP - choose one
  serviceConfiguration = {
    enable = true;
    outputs = [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ];
    ports = [ 5900 5901 5902 ];
  };
}
```

---

### 3. Home Manager Configuration

**Entity**: `HomeManagerConfiguration`

Represents user-level environment configuration via home-manager.

**Fields**:
- `username`: String - System username
- `platform`: String - Platform identifier (links to PlatformConfiguration)
- `moduleImports`: List<ModulePath> - home-modules/ imports
- `shellConfig`: ShellConfiguration - Bash, Zsh, Fish settings
- `editorConfig`: EditorConfiguration - Neovim, Emacs settings
- `desktopApps`: List<DesktopAppConfiguration> - User desktop applications
- `xdgConfigFiles`: Map<String, FileContent> - ~/.config/ file generation
- `homeFiles`: Map<String, FileContent> - ~/ dotfile generation
- `userServices`: List<SystemdUserService> - systemd --user services

**Relationships**:
- Belongs to one: PlatformConfiguration
- Has many: HomeModule
- Has many: SystemdUserService

**Validation Rules**:
- moduleImports must not include system-level service modules
- xdgConfigFiles paths must not conflict
- userServices must not require root privileges
- desktopApps must check for Wayland/X11 availability

**State Transitions**: N/A (static configuration)

**Example**:
```nix
{
  username = "vpittamp";
  platform = "m1";
  moduleImports = [
    ../home-modules/shell/bash.nix
    ../home-modules/editors/neovim.nix
    ../home-modules/terminal/tmux.nix
    ../home-modules/desktop/sway.nix
    ../home-modules/desktop/walker.nix
    ../home-modules/desktop/sway-config-manager.nix
    ../home-modules/desktop/declarative-cleanup.nix  # ADDED in this feature
    ../home-modules/tools/i3pm
  ];
  shellConfig = {
    shell = "bash";
    enableStarship = true;
    historySize = 10000;
  };
  desktopApps = [
    { name = "walker"; wayland = true; }
    { name = "firefox"; wayland = true; }
  ];
}
```

---

### 4. Sway Configuration

**Entity**: `SwayConfiguration`

Represents Sway compositor configuration with platform-specific adaptations.

**Fields**:
- `platform`: String - Platform identifier
- `outputs`: List<OutputConfiguration> - Display output definitions
- `inputs`: List<InputConfiguration> - Input device settings
- `keybindingsFile`: String - Path to keybindings.toml
- `appearanceFile`: String - Path to appearance.json
- `windowRulesFile`: String - Path to window-rules.json
- `workspaceAssignmentsFile`: String - Path to workspace-assignments.json
- `environmentVariables`: Map<String, String> - Wayland/WLR environment
- `sessionCommand`: String - Command to start Sway session
- `dynamicConfigEnabled`: Boolean - Feature 047 hot-reload support

**Relationships**:
- Belongs to one: PlatformConfiguration
- Has many: OutputConfiguration
- Has many: InputConfiguration
- Has one: SwayConfigManagerDaemon (if dynamicConfigEnabled)

**Validation Rules**:
- outputs must have unique names
- environmentVariables must not conflict with system-wide settings
- keybindingsFile must use TOML format (Feature 047 schema)
- dynamicConfigEnabled requires sway-config-manager daemon

**State Transitions**:
- `initial` → `active` (Sway session started)
- `active` → `reloading` (swaymsg reload triggered)
- `reloading` → `active` (reload completed)

**Example**:
```nix
# Hetzner-Sway
{
  platform = "hetzner-sway";
  outputs = [
    { name = "HEADLESS-1"; resolution = "1920x1080"; position = "0,0"; }
    { name = "HEADLESS-2"; resolution = "1920x1080"; position = "1920,0"; }
    { name = "HEADLESS-3"; resolution = "1920x1080"; position = "3840,0"; }
  ];
  inputs = [];  # Disabled for headless
  keybindingsFile = "~/.config/sway/keybindings.toml";
  environmentVariables = {
    WLR_BACKENDS = "headless";
    WLR_HEADLESS_OUTPUTS = "3";
    WLR_LIBINPUT_NO_DEVICES = "1";
    WLR_RENDERER = "pixman";
  };
  dynamicConfigEnabled = true;
}

# M1
{
  platform = "m1";
  outputs = [
    { name = "eDP-1"; resolution = "3024x1890"; scale = 2.0; position = "0,0"; }
    { name = "HDMI-A-1"; resolution = "1920x1080"; position = "1512,0"; }  # Optional external
  ];
  inputs = [
    { type = "touchpad"; naturalScrolling = true; tapToClick = true; }
  ];
  keybindingsFile = "~/.config/sway/keybindings.toml";  # SAME as hetzner
  environmentVariables = {
    # Standard Wayland, no headless backend
  };
  dynamicConfigEnabled = true;
}
```

---

### 5. Output Configuration

**Entity**: `OutputConfiguration`

Represents a display output (physical or virtual) in Sway.

**Fields**:
- `name`: String - Output identifier (e.g., "eDP-1", "HEADLESS-1")
- `type`: Enum - "physical" | "virtual"
- `resolution`: String - WIDTHxHEIGHT (e.g., "1920x1080")
- `scale`: Float - HiDPI scaling factor (1.0, 2.0, etc.)
- `position`: String - X,Y coordinates (e.g., "0,0", "1920,0")
- `transform`: Enum - "normal" | "90" | "180" | "270" | "flipped"
- `adaptive_sync`: Boolean - Enable VRR/FreeSync
- `workspaceAssignments`: List<Int> - Workspace numbers assigned to this output

**Relationships**:
- Belongs to one: SwayConfiguration
- Has many: Workspace (via workspaceAssignments)

**Validation Rules**:
- name must be unique within SwayConfiguration
- resolution must be valid WIDTHxHEIGHT format
- scale must be positive (typical: 1.0, 1.5, 2.0)
- workspaceAssignments must not overlap with other outputs
- type=virtual only valid with WLR_BACKENDS=headless

**State Transitions**:
- `connected` → `active` (output enabled)
- `active` → `disconnected` (physical display unplugged)
- `disconnected` → `connected` (physical display reconnected)

**Example**:
```nix
# M1 Retina Display
{
  name = "eDP-1";
  type = "physical";
  resolution = "3024x1890";
  scale = 2.0;  # Retina requires 2x scaling
  position = "0,0";
  adaptive_sync = false;  # Not needed for built-in display
  workspaceAssignments = [ 1 2 ];  # Primary workspaces
}

# Hetzner Virtual Display
{
  name = "HEADLESS-1";
  type = "virtual";
  resolution = "1920x1080";
  scale = 1.0;
  position = "0,0";
  workspaceAssignments = [ 1 2 ];  # Primary workspaces
}
```

---

### 6. Module Import Diff

**Entity**: `ModuleImportDiff`

Represents the difference between two platform configurations' module imports.

**Fields**:
- `sourcePlatform`: String - Reference platform (hetzner-sway)
- `targetPlatform`: String - Platform to align (m1)
- `missingInTarget`: List<ModulePath> - Modules in source but not target
- `extraInTarget`: List<ModulePath> - Modules in target but not source
- `intentionalDifferences`: List<ModulePath> - Documented architectural differences
- `alignmentRequired`: List<ModulePath> - Must be added to target
- `removalRequired`: List<ModulePath> - Should be removed from target

**Relationships**:
- References two: PlatformConfiguration (source and target)
- Has many: ServiceModule (via alignmentRequired/removalRequired)

**Validation Rules**:
- missingInTarget ∪ extraInTarget = all differences
- intentionalDifferences ⊆ (missingInTarget ∪ extraInTarget)
- alignmentRequired = missingInTarget - intentionalDifferences (where appropriate)
- All differences must be justified (alignment or architectural)

**State Transitions**:
- `analysis` → `reviewed` (manual review of differences)
- `reviewed` → `approved` (architectural differences documented)
- `approved` → `implemented` (changes applied to target)

**Example**:
```nix
{
  sourcePlatform = "hetzner-sway";
  targetPlatform = "m1";
  missingInTarget = [
    ../modules/services/i3-project-daemon.nix      # ALIGNMENT REQUIRED
    ../modules/services/onepassword-automation.nix # ALIGNMENT REQUIRED
    ../modules/services/keyd.nix                   # OPTIONAL (consider)
    ../modules/desktop/wayvnc.nix                  # INTENTIONAL (headless-specific)
    ../modules/services/tailscale-audio.nix        # INTENTIONAL (remote audio)
  ];
  extraInTarget = [
    ../modules/desktop/firefox-1password.nix       # INTENTIONAL (desktop GUI)
    ../modules/desktop/firefox-pwa-1password.nix   # INTENTIONAL (PWA support)
  ];
  intentionalDifferences = [
    ../modules/desktop/wayvnc.nix                  # Headless VNC server
    ../modules/services/tailscale-audio.nix        # Audio streaming
    ../modules/desktop/firefox-1password.nix       # M1 browser integration
    ../modules/desktop/firefox-pwa-1password.nix   # M1 PWA support
  ];
  alignmentRequired = [
    ../modules/services/i3-project-daemon.nix      # Critical for i3pm features
    ../modules/services/onepassword-automation.nix # Service account automation
  ];
  removalRequired = [];  # No incorrect modules on M1
}
```

---

## Entity Relationships Diagram

```
PlatformConfiguration (hetzner-sway, m1)
  │
  ├──> ServiceModule (i3-project-daemon, onepassword, networking, etc.)
  │      │
  │      └──> SystemdService (system-level services)
  │
  ├──> DesktopModule (sway, wayvnc, walker, etc.)
  │
  ├──> HardwareConfiguration (m1.nix, hardware-configuration.nix)
  │
  └──> HomeManagerConfiguration
         │
         ├──> HomeModule (bash, neovim, tmux, sway-user-config, etc.)
         │
         ├──> SwayConfiguration
         │      │
         │      ├──> OutputConfiguration (eDP-1, HEADLESS-1, etc.)
         │      │      │
         │      │      └──> Workspace (1-70)
         │      │
         │      └──> InputConfiguration (touchpad, keyboard, etc.)
         │
         └──> SystemdUserService (walker, i3pm-daemon-client, etc.)

ModuleImportDiff
  ├──> PlatformConfiguration (source: hetzner-sway)
  └──> PlatformConfiguration (target: m1)
```

## Key Constraints

### Cross-Platform Consistency Rules

1. **Service Daemon Behavior**: i3pm, walker, sway-config-manager MUST behave identically
2. **Keybinding Parity**: keybindings.toml MUST be identical (except hardware-specific keys)
3. **Application Registry**: app-registry.nix MUST be shared (no platform-specific apps)
4. **Dynamic Configuration**: sway-config-manager templates MUST be shared

### Platform-Specific Isolation Rules

1. **Display Configuration**: Output definitions MUST be platform-specific
2. **Input Devices**: Input configuration MUST be platform-specific
3. **Environment Variables**: WLR_* variables MUST be isolated to headless platform
4. **Remote Access**: VNC (hetzner) and RustDesk (m1) MUST NOT coexist

### Validation Invariants

1. **Module Import Closure**: All imported modules must exist and be accessible
2. **No Circular Dependencies**: Module dependency graph must be acyclic
3. **Architecture Compatibility**: All packages must have builds for target architecture
4. **Service Conflicts**: No two conflicting services can be enabled simultaneously

## Data Flow

### Configuration Build Process

```
1. Flake Evaluation
   ├─> Load PlatformConfiguration (m1.nix)
   ├─> Resolve all imports (base, services, desktop, hardware, home-manager)
   ├─> Merge module options with priority handling (mkDefault, mkForce)
   └─> Generate final system configuration

2. Home Manager Evaluation (parallel to system)
   ├─> Load HomeManagerConfiguration (base-home.nix)
   ├─> Resolve home-modules/ imports
   ├─> Generate XDG config files (~/.config/sway/*, ~/.config/walker/*, etc.)
   └─> Link home files to /nix/store

3. Build Phase
   ├─> Compile system configuration to /nix/store derivation
   ├─> Build all packages for target architecture
   ├─> Create systemd unit files
   └─> Generate activation scripts

4. Activation Phase
   ├─> Switch system generation
   ├─> Restart changed systemd services
   ├─> Run activation scripts (user lingering, etc.)
   └─> Apply home-manager changes (user services, XDG files)
```

### Dynamic Configuration Reload (Feature 047)

```
1. User Edit
   ├─> Modify ~/.config/sway/keybindings.toml
   └─> Save file

2. File Watcher (inotifywait, 500ms debounce)
   ├─> Detect file change
   ├─> Trigger validation
   └─> Wait for 500ms of inactivity

3. Validation (sway-config-manager)
   ├─> Parse TOML/JSON schema
   ├─> Validate syntax
   ├─> Check semantic correctness (valid commands, key combinations)
   └─> Generate Sway config from template

4. Apply & Commit
   ├─> Run `swaymsg reload` (<100ms latency)
   ├─> Git commit if successful
   └─> Log errors if failed (no commit, no reload)
```

## Migration Path

### Phase 1: Add Missing Modules (This Feature)

```
Before:
  m1.nix:
    imports = [
      development.nix
      networking.nix
      onepassword.nix
      sway.nix
    ]

After:
  m1.nix:
    imports = [
      development.nix
      networking.nix
      onepassword.nix
      i3-project-daemon.nix        # ADDED
      onepassword-automation.nix   # ADDED
      keyd.nix                     # ADDED (optional)
      sway.nix
    ]
```

### Phase 2: Fix Sway Configuration Issues

```
Before:
  workspace-mode-handler.sh:
    swaymsg output HEADLESS-1 ...  # Hardcoded

After:
  workspace-mode-handler.sh:
    OUTPUTS=$(swaymsg -t get_outputs | jq -r '.[].name')
    for output in $OUTPUTS; do
      swaymsg output $output ...  # Dynamic
    done
```

### Phase 3: Simplify Home Manager Imports

```
Before (M1):
  base-home.nix:
    imports = [ 45+ modules via nested structure ]

After (M1):
  home-vpittamp.nix:
    imports = [ 10 explicit desktop modules ]  # Match hetzner-sway
```

## Summary

This data model defines configuration entities (PlatformConfiguration, ServiceModule, SwayConfiguration, etc.) that represent the alignment between hetzner-sway and M1 configurations. The model emphasizes:

1. **Module Composition**: Reusable service and desktop modules composed into platform configurations
2. **Platform Differentiation**: Clear separation of shared vs platform-specific settings
3. **Validation Rules**: Constraints ensuring configuration correctness and compatibility
4. **Migration Path**: Incremental steps to achieve alignment without breaking existing functionality

The next phase (contracts/) will define the specific Nix expressions to implement these changes.
