# Implementation Plan: Lightweight X11 Desktop Environment for Hetzner Cloud

**Branch**: `005-research-a-more` | **Date**: 2025-10-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-research-a-more/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace the failed MangoWC Wayland compositor with a stable X11-based lightweight desktop environment for headless Hetzner Cloud QEMU/KVM servers. The solution uses i3wm window manager with existing XRDP infrastructure to provide remote desktop access with <50MB memory footprint (vs 500MB+ for KDE Plasma), 4+ workspaces, keyboard-driven workflow, and proven stability in production environments. This maintains all existing services (1Password, Tailscale, development tools) while delivering reliable remote GUI access via software rendering.

## Technical Context

**Language/Version**: Nix/NixOS 24.11+ (declarative system configuration)
**Primary Dependencies**:
- i3wm 4.23+ (window manager)
- XRDP with xorgxrdp backend (remote desktop)
- Xorg with llvmpipe (software rendering)
- PulseAudio with pulseaudio-module-xrdp (audio)
- dmenu/rofi (application launcher)
- i3status/i3blocks (status bar)

**Storage**: NixOS configuration files in `/etc/nixos/modules/desktop/` and `/etc/nixos/configurations/`
**Testing**: NixOS VM testing (`nixos-rebuild build-vm`), manual validation on Hetzner Cloud
**Target Platform**: Hetzner Cloud QEMU/KVM (headless virtual machine, no GPU)
**Project Type**: System configuration (NixOS modules)
**Performance Goals**:
- Window manager memory: <50MB baseline
- Remote desktop input latency: <100ms local network
- Workspace switching: <200ms
- 7-day continuous uptime without crashes

**Constraints**:
- Must use X11 (not Wayland) for headless compatibility
- Software rendering only (Mesa llvmpipe, no GPU acceleration)
- Must work with existing XRDP infrastructure
- Must integrate with existing 1Password, Tailscale, development tools
- Declarative NixOS configuration only (no imperative setup)

**Scale/Scope**:
- Single user desktop environment
- 4-9 workspaces
- 5-10 concurrent GUI applications
- ~15 NixOS configuration options to expose
- 2-3 new NixOS modules to create

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: ✅ PASSED - All constitutional principles followed

### Modular Composition ✅
- **Compliance**: Creating dedicated `modules/desktop/i3wm.nix` module
- **Reusability**: Existing `modules/desktop/xrdp.nix` will be refactored for reuse
- **Override Pattern**: Uses `lib.mkDefault` for user-overridable defaults, `lib.mkForce` only where mandatory

### Hetzner as Reference Implementation ✅
- **Compliance**: Configuration builds upon existing `configurations/hetzner.nix`
- **Pattern**: Follows exact structure of existing desktop modules (KDE Plasma pattern)
- **Migration**: Replaces KDE module while preserving all other Hetzner services

### Test-Before-Apply (NON-NEGOTIABLE) ✅
- **Plan**: All changes will be tested with `nixos-rebuild dry-build --flake .#hetzner`
- **VM Testing**: Will use `nixos-rebuild build-vm` for safe validation
- **Incremental**: Phase 1 deploys i3wm alongside KDE for safe migration

### Override Priority Discipline ✅
- **Module Design**: All i3wm options use `lib.mkDefault` for defaults
- **Mandatory Settings**: Only X11 enablement uses `lib.mkForce` (required for functionality)
- **User Control**: Configuration exposes all key options for user customization

### Platform Flexibility Through Conditional Features ✅
- **Target-Specific**: i3wm module only enabled on Hetzner configuration
- **Conditional**: Desktop features conditional on `config.services.xserver.enable`
- **Portable**: Other targets (WSL, M1) unaffected

### Declarative Configuration Over Imperative ✅
- **Full Declarative**: i3 config file generated from NixOS options
- **No Manual Steps**: All configuration in `.nix` files
- **Reproducible**: `nixos-rebuild switch` fully rebuilds system state

### Documentation as Code ✅
- **Implementation**: All phases documented in `specs/005-research-a-more/`
- **Code Comments**: Module options include descriptions
- **User Guide**: Quickstart.md provides configuration examples

### Complexity Tracking (No Violations)
- **New Modules**: 2 modules (i3wm.nix, refactored xrdp.nix) - within reasonable limits
- **Dependencies**: All dependencies available in nixpkgs stable
- **Alternatives**: Simpler options (IceWM, JWM) rejected for stability/UX reasons documented in research.md

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
/etc/nixos/
├── modules/
│   └── desktop/
│       ├── i3wm.nix              # NEW: i3 window manager module
│       ├── xrdp.nix               # REFACTORED: XRDP configuration module
│       ├── kde-plasma.nix         # EXISTING: Will be replaced by i3wm
│       └── remote-access.nix      # EXISTING: May be deprecated by xrdp.nix
│
├── configurations/
│   ├── hetzner.nix                # MODIFIED: Replace kde-plasma with i3wm
│   ├── hetzner-i3.nix             # NEW: i3wm variant (Phase 1 testing)
│   └── base.nix                   # UNMODIFIED: Shared base config
│
├── hardware/
│   └── hetzner.nix                # UNMODIFIED: Hardware config
│
└── flake.nix                      # MODIFIED: Add hetzner-i3 configuration
```

**Structure Decision**: System configuration project (NixOS modules). All implementation is NixOS module code in `modules/desktop/` with configuration composition in `configurations/`. No application source code - this is declarative system configuration only.

**Key Changes**:
1. **New Module**: `modules/desktop/i3wm.nix` - Complete i3 window manager configuration
2. **Refactored Module**: `modules/desktop/xrdp.nix` - Extracted from remote-access.nix
3. **New Configuration**: `configurations/hetzner-i3.nix` - Testing variant for Phase 1
4. **Updated Configuration**: `configurations/hetzner.nix` - Final i3 integration (Phase 3)

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**Status**: No constitutional violations - table not required.

All complexity justified in research.md:
- Simpler window managers (JWM, IceWM) rejected for stability/documentation reasons
- i3wm chosen despite learning curve for production-proven reliability
- XRDP kept over simpler VNC for better performance and existing validation
