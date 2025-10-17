# Implementation Plan: i3 Project Workspace Management System

**Branch**: `010-i3-project-workspace` | **Date**: 2025-10-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-i3-project-workspace/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

A declarative i3 window manager workspace management system for NixOS that enables developers to define, activate, and switch between complete project environments with pre-configured applications, window layouts, and workspace assignments. The system integrates with NixOS/home-manager for reproducible, version-controlled project configurations, supports multi-monitor setups with graceful single-monitor fallback, and provides both declarative configuration and ad-hoc workspace composition.

## Technical Context

**Language/Version**: Bash 5.x (for scripting) + Nix 2.x (for configuration)
**Primary Dependencies**:
  - i3wm 4.8+ (window manager with IPC)
  - i3ipc or i3-msg (i3 IPC communication)
  - xdotool (X11 window automation)
  - xprop (window class detection)
  - jq (JSON processing for i3 layouts)
  - xrandr (monitor configuration)

**Storage**:
  - Project definitions: Nix attribute sets in NixOS/home-manager configuration
  - Captured layouts: JSON files (i3's native layout format) in user config directory
  - Runtime state: i3's workspace tree (via IPC)

**Testing**:
  - Integration testing via bash test framework or bats (Bash Automated Testing System)
  - Manual testing with i3 dry-build and real workspace activation
  - Contract testing for i3 IPC command outputs

**Target Platform**: NixOS with i3wm on X11 (Hetzner primary, M1 Mac with Asahi Linux secondary)

**Project Type**: System utilities / Window manager integration (NixOS module + CLI tools)

**Performance Goals**:
  - Project activation: Complete within 10 seconds for up to 10 applications
  - Layout capture: Complete workspace scan within 2 seconds
  - Project switching: Focus change within 500ms
  - Memory overhead: <50MB for project management daemon (if needed)

**Constraints**:
  - Must integrate with existing i3wm configuration (modules/desktop/i3wm.nix)
  - Must not override existing i3 keybindings without explicit configuration
  - Must work with i3wsr workspace renaming system
  - Must support asynchronous application launching (apps start at different speeds)
  - Applications must have consistent WM_CLASS values for reliable matching
  - Cannot persist application internal state (only window positions)

**Scale/Scope**:
  - Support 10-20 project definitions per user
  - Handle 3-5 workspaces per project
  - Manage 5-15 applications per project
  - Support 1-3 concurrent active projects
  - Configuration complexity: ~100-200 lines per project definition

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

**I. Modular Composition** ✅ PASS
- Feature will be implemented as a new NixOS module in `modules/desktop/i3-project-workspace.nix`
- Home-manager module will handle user-level project definitions in `home-modules/desktop/i3-projects.nix`
- Clear separation: system-level CLI tools vs user-level project configurations
- No duplication with existing i3wm module; extends it through composition

**II. Reference Implementation Flexibility** ✅ PASS
- Feature targets Hetzner configuration (current reference with i3wm)
- Will be tested on reference platform first before considering M1 deployment
- Hetzner's i3wm + X11 + xrdp setup is ideal for validating multi-session workspace isolation

**III. Test-Before-Apply** ✅ PASS
- All configuration changes will use `nixos-rebuild dry-build --flake .#hetzner` before applying
- Project definitions are declarative Nix; can be dry-built without risk
- Provides natural rollback via NixOS generations if issues arise

**IV. Override Priority Discipline** ✅ PASS
- Will use `lib.mkDefault` for default project configurations that users can override
- No `lib.mkForce` needed; this feature adds capabilities without overriding existing i3 options
- Users control project activation; system provides tools without forcing behavior

**V. Platform Flexibility Through Conditional Features** ✅ PASS
- Module will detect i3wm presence: `config.services.xserver.enable && config.services.i3wm.enable`
- CLI tools will be available system-wide but functionality requires i3wm
- Project definitions gracefully skip if referenced applications aren't installed

**VI. Declarative Configuration Over Imperative** ✅ PASS
- Project definitions: Pure Nix attribute sets in home-manager configuration
- CLI tools: Installed via NixOS module, generated from Nix expressions
- Configuration files: Generated via `environment.etc` or `home.file`
- NO imperative post-install scripts; all configuration is declarative
- Layout capture generates declarative Nix code (similar to existing PWA capture scripts)

**VII. Documentation as Code** ✅ PASS
- Module header comments will explain purpose, options, and integration points
- Will create `docs/I3_PROJECT_WORKSPACE.md` with usage guide and examples
- `CLAUDE.md` will be updated with project workspace commands in "Common Tasks" section
- All module options will include `description` fields

**VIII. Remote Desktop & Multi-Session Standards** ✅ PASS
- Projects will work correctly in RDP sessions (X11 environment, DISPLAY variable propagation)
- Each RDP session gets independent i3 workspace tree; projects won't conflict across sessions
- Session isolation ensures project workspaces are user-session specific
- Clipboard integration via existing clipcat setup

**IX. Tiling Window Manager & Productivity Standards** ✅ PASS
- **Core alignment**: This feature directly implements the tiling WM productivity principle
- Extends i3wm's native workspace management with project-level abstractions
- Fully keyboard-driven workflow; no GUI required
- Integrates with existing i3wsr for workspace naming (project names in workspace labels)
- Leverages existing rofi for project selection menus (optional enhancement)
- Enhances keyboard-first philosophy with rapid project switching

### Platform Support Standards ✅ PASS
- Primary target: Hetzner (i3wm + X11 + xrdp) - aligns with current reference implementation
- Secondary consideration: M1 Mac (Asahi + i3wm or Wayland/Sway variant)
- Not applicable: WSL (typically GUI-less), Containers (no desktop environment)
- Feature aligns with desktop environment transition guidance in constitution

### Security & Authentication Standards ✅ PASS
- No security implications; feature manages window positions, not credentials
- Projects may reference paths containing 1Password configurations; users should review before sharing
- No new authentication mechanisms introduced

### Package Management Standards ✅ PASS
- New dependencies (xdotool, i3-msg, jq) will be scoped to the i3-project-workspace module
- No system-wide package additions unless module is enabled
- Profile impact: ~5-10MB additional packages (already minimal tools)

### Home-Manager Standards ✅ PASS
- User project definitions in `home-modules/desktop/i3-projects.nix`
- Module structure: `{ config, lib, pkgs, ... }:` with proper option declarations
- Configuration via `xdg.configFile` for generated project scripts
- Conditional activation via `lib.mkIf config.services.i3wm.enable`

### Gate Decision: ✅ PROCEED TO PHASE 0

All constitution principles are satisfied. No violations requiring justification. Feature naturally aligns with existing modular architecture and tiling window manager productivity standards.

---

### Post-Design Re-Evaluation ✅ PASS

**Date**: 2025-10-17
**Phase**: After Phase 1 (Design & Contracts)

**Review of Design Artifacts**:
- research.md: Technology choices documented
- data-model.md: Nix-native data structures defined
- contracts/: CLI specifications complete
- quickstart.md: User workflows documented

**Constitution Compliance Verification**:

✅ **Modular Composition**: Confirmed
- System module (`modules/desktop/i3-project-workspace.nix`) for CLI tools
- Home-manager module (`home-modules/desktop/i3-projects.nix`) for user configs
- Clear separation of concerns maintained

✅ **Declarative Configuration**: Confirmed
- All project definitions as Nix attribute sets
- Scripts generated via `pkgs.writeShellScriptBin`
- No imperative post-install steps
- Layout capture generates declarative Nix code

✅ **Platform Flexibility**: Confirmed
- Conditional activation via i3wm presence detection
- Optional features based on available packages
- Graceful degradation (multi-monitor → single monitor)

✅ **Package Management**: Confirmed
- Dependencies scoped to module (`xdotool`, `jq`, `i3-msg`)
- Uses `lib.optionals` for conditional packages
- No system-wide pollution

✅ **Tiling WM Standards**: Confirmed
- Fully keyboard-driven workflow
- Integrates with i3wsr for workspace naming
- Supports rofi for interactive selection
- Extends i3wm capabilities without conflicts

**No New Issues Identified**

The design phase has confirmed all initial constitution compliance assumptions. No additional principles violated, no complexity justifications needed.

**Final Gate Decision**: ✅ APPROVED FOR IMPLEMENTATION

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
modules/desktop/
└── i3-project-workspace.nix      # System-level NixOS module
                                   # - Enables i3-project-workspace feature
                                   # - Installs CLI tools (i3-project, i3-project-capture)
                                   # - Provides system-level options

home-modules/desktop/
└── i3-projects.nix                # User-level home-manager module
                                   # - Project definitions (attribute sets)
                                   # - User-specific workspace configurations
                                   # - Integration with i3wsr for workspace naming

scripts/                           # Generated CLI tools (embedded in modules)
├── i3-project                     # Main CLI: activate, list, close projects
├── i3-project-capture             # Layout capture tool
└── i3-project-lib.sh              # Shared functions (i3 IPC, window management)

docs/
└── I3_PROJECT_WORKSPACE.md        # User guide and reference

tests/                             # Test suite (future)
└── i3-project-integration.bats    # Bash integration tests
```

**Structure Decision**: NixOS system integration pattern - no separate source tree needed. All code is embedded within Nix modules as generated scripts. This aligns with existing patterns like PWA management (firefox-pwas-declarative.nix) where functionality is distributed across:
- System module for tool installation and system-level config
- Home-manager module for user-specific configurations
- Generated scripts for runtime functionality

This pattern maximizes NixOS integration, declarative configuration, and reproducibility while minimizing external dependencies.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
