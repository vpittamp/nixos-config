# Implementation Plan: MangoWC Desktop Environment for Hetzner Cloud

**Branch**: `003-create-a-new` | **Date**: 2025-10-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-create-a-new/spec.md`

## Summary

Create a new NixOS configuration target (`hetzner-mangowc`) that replaces KDE Plasma with MangoWC, a lightweight Wayland compositor based on dwl. The configuration must support headless operation on Hetzner Cloud with remote desktop access via Wayland-compatible protocols. Key features include 9 configurable workspaces, multiple window layouts (tile, scroller, monocle), session persistence, concurrent connection support, and 1Password authentication integration.

## Technical Context

**Language/Version**: Nix 2.19+, MangoWC (dwl-based Wayland compositor), wlroots 0.19.1
**Primary Dependencies**:
- MangoWC compositor (github:DreamMaoMao/mangowc flake)
- wlroots 0.19.1
- scenefx (window effects library)
- wayvnc or RustDesk (Wayland remote desktop server)
- foot (terminal), wmenu/rofi (launcher), swaybg (wallpaper)
- 1Password CLI/SSH agent (authentication)

**Storage**:
- MangoWC configuration: `~/.config/mango/config.conf`, `~/.config/mango/autostart.sh`
- Session state managed by compositor
- User data in standard XDG directories

**Testing**:
- `nixos-rebuild dry-build --flake .#hetzner-mangowc` (build validation)
- `nixos-rebuild switch --flake .#hetzner-mangowc` (deployment test)
- Manual remote desktop connection testing (wayvnc/RustDesk client)
- Workspace switching and window management verification

**Target Platform**: NixOS 24.11+ on Hetzner Cloud (x86_64-linux, QEMU/KVM virtualization, headless operation)

**Project Type**: NixOS system configuration (modular composition of .nix files)

**Performance Goals**:
- Remote desktop input latency <100ms
- Workspace switching <200ms
- MangoWC memory footprint <200MB
- Remote connection establishment <30 seconds

**Constraints**:
- Headless operation (no physical display)
- Software rendering only (llvmpipe, no GPU)
- Must support session persistence across disconnects
- Must support concurrent remote connections
- Must integrate with existing 1Password infrastructure
- Must maintain QEMU guest optimizations from base Hetzner config

**Scale/Scope**:
- Single user system (vpittamp)
- 9 workspaces/tags
- ~10 concurrent applications typical workload
- Remote desktop audio redirection required
- Compatible with existing Hetzner networking (Tailscale, firewall rules)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: ✅ PASSED (Pre-Phase 0) | ✅ PASSED (Post-Phase 1)

### ✅ I. Modular Composition
**Status**: PASS

**Plan**: Create modular structure following existing patterns:
- `configurations/hetzner-mangowc.nix` - new target configuration
- `modules/desktop/mangowc.nix` - MangoWC compositor module
- `modules/desktop/wayland-remote-access.nix` - Wayland RDP/VNC module
- Reuse existing modules: `modules/services/development.nix`, `modules/services/networking.nix`, `modules/services/onepassword.nix`

**Rationale**: Follows established Hetzner configuration pattern. MangoWC-specific logic isolated in dedicated desktop module. No code duplication - shared services reused from existing modules.

### ✅ II. Hetzner as Reference Implementation
**Status**: PASS with EXTENSION

**Plan**: Create `hetzner-mangowc` as variant of `hetzner` configuration:
- Base: `configurations/base.nix` (unchanged)
- Hardware: `hardware/hetzner.nix` (unchanged)
- Services: Same development/networking/onepassword modules
- Desktop: NEW `modules/desktop/mangowc.nix` replaces `modules/desktop/kde-plasma.nix`
- Remote Access: NEW `modules/desktop/wayland-remote-access.nix` replaces `modules/desktop/remote-access.nix` (X11-based)

**Rationale**: Extends Hetzner reference with alternative desktop environment. Validates modular architecture by swapping desktop module while reusing all service layers. Hetzner remains canonical reference for KDE Plasma; hetzner-mangowc demonstrates desktop modularity.

### ✅ III. Test-Before-Apply (NON-NEGOTIABLE)
**Status**: PASS

**Plan**: Development workflow:
1. Build: `sudo nixos-rebuild dry-build --flake .#hetzner-mangowc`
2. Test: `sudo nixos-rebuild test --flake .#hetzner-mangowc` (temporary activation)
3. Apply: `sudo nixos-rebuild switch --flake .#hetzner-mangowc` (permanent)
4. Rollback: `sudo nixos-rebuild switch --rollback` (if issues)

**Rationale**: Standard NixOS test-before-apply protocol. MangoWC being new compositor requires extra caution. Test mode allows validation without boot commitment.

### ✅ IV. Override Priority Discipline
**Status**: PASS

**Plan**: Priority usage:
- `lib.mkDefault` for MangoWC compositor binary selection (allow override)
- `lib.mkDefault` for default keybindings (allow user customization)
- `lib.mkForce false` for X11 services (mandatory disable for Wayland)
- Normal assignment for MangoWC module options
- Document all `mkForce` usage with comments

**Rationale**: Follows constitution guidelines. X11 disablement requires `mkForce` to prevent conflicts. Keybindings/compositor use `mkDefault` for user overrides.

### ✅ V. Platform Flexibility Through Conditional Features
**Status**: PASS

**Plan**: MangoWC module will conditionally enable features:
```nix
let
  hasAudio = config.hardware.pulseaudio.enable || config.services.pipewire.enable;
  has1Password = config.services.onepassword-automation.enable or false;
in {
  # Audio redirection only if audio system enabled
  services.wayvnc.audio = lib.mkIf hasAudio { ... };

  # 1Password auth integration only if service available
  environment.systemPackages = lib.optionals has1Password [ ... ];
}
```

**Rationale**: MangoWC module adapts to system capabilities. Works with or without audio. Integrates with 1Password if available but doesn't require it.

### ✅ VI. Declarative Configuration Over Imperative
**Status**: PASS

**Plan**: Fully declarative:
- MangoWC configuration generated via `environment.etc."mango/config.conf"`
- Autostart script generated via `environment.etc."mango/autostart.sh"`
- Remote desktop service configured via NixOS systemd options
- Home-manager for user-level MangoWC config (if needed)
- No post-install scripts

**Rationale**: All configuration in Nix expressions. Reproducible across rebuilds. Follows constitution requirement for declarative configuration.

### ✅ VII. Documentation as Code
**Status**: PASS

**Plan**: Documentation deliverables:
- `docs/MANGOWC_SETUP.md` - Setup and connection guide
- `docs/MANGOWC_KEYBINDINGS.md` - Default keybindings reference
- Update `CLAUDE.md` with MangoWC build commands
- Update `README.md` with hetzner-mangowc target
- Inline module comments explaining MangoWC-specific logic

**Rationale**: Comprehensive documentation for new desktop environment. LLM navigation guide updated. Module comments explain Wayland-specific considerations.

### ✅ Multi-Platform Compatibility
**Status**: PASS (Hetzner-specific initially)

**Plan**: Initial implementation for Hetzner only. Architecture allows future extension to M1 (Wayland native on Asahi Linux) or WSL (if WSLg Wayland support added).

**Rationale**: Spec targets Hetzner. Modular design enables future platform ports. M1 already uses Wayland (good candidate for MangoWC). WSL uses WSLg (potential future support).

### ✅ 1Password Integration
**Status**: PASS

**Plan**: Reuse existing 1Password infrastructure:
- Authentication via `services.onepassword-password-management` (existing module)
- User password: `op://CLI/NixOS User Password/password` (existing reference)
- Service account: `op://Employee/kzfqt6yulhj6glup3w22eupegu/credential` (existing)
- No new 1Password configuration required

**Rationale**: Leverages existing 1Password setup from Hetzner config. Remote desktop auth uses system authentication (pam), which pulls from 1Password. No additional secrets needed.

### ⚠️ Package Management Standards
**Status**: NEEDS CLARIFICATION (package profile assignment)

**Question**: Which package profile should MangoWC use?
- MangoWC compositor itself is small (~10MB)
- Required companion tools (foot, wmenu, swaybg) are ~20MB combined
- Remote desktop server (wayvnc/RustDesk) ~5-15MB

**Proposed**: Add MangoWC packages to "development" profile (already used by hetzner.nix). MangoWC is a desktop environment, not a minimal tool.

**Rationale**: Hetzner uses "development" or "full" profiles. MangoWC as a desktop environment fits development profile. Container/minimal profiles wouldn't use MangoWC.

## Project Structure

### Documentation (this feature)

```
specs/003-create-a-new/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0: Technology research and decisions
├── data-model.md        # Phase 1: Configuration data model
├── quickstart.md        # Phase 1: Quick start guide for users
├── contracts/           # Phase 1: Configuration interfaces
│   └── mangowc-module-options.md  # NixOS module options contract
├── checklists/
│   └── requirements.md  # Requirements validation checklist (completed)
└── tasks.md             # Phase 2: Implementation tasks (NOT created by /speckit.plan)
```

### Source Code (repository root)

```
/etc/nixos/
├── flake.nix                               # Add hetzner-mangowc output
├── configurations/
│   ├── base.nix                            # Unchanged - reused
│   ├── hetzner.nix                         # Unchanged - reference
│   └── hetzner-mangowc.nix                 # NEW - MangoWC variant
│
├── hardware/
│   └── hetzner.nix                         # Unchanged - reused
│
├── modules/
│   ├── desktop/
│   │   ├── kde-plasma.nix                  # Unchanged - for hetzner
│   │   ├── mangowc.nix                     # NEW - MangoWC compositor
│   │   ├── wayland-remote-access.nix       # NEW - wayvnc/RustDesk config
│   │   └── firefox-virtual-optimization.nix # Reused if Firefox needed
│   │
│   └── services/
│       ├── development.nix                 # Unchanged - reused
│       ├── networking.nix                  # Unchanged - reused
│       ├── onepassword.nix                 # Unchanged - reused
│       └── onepassword-automation.nix      # Unchanged - reused
│
├── home-modules/
│   ├── tools/
│   │   └── mangowc-config.nix              # NEW - User-level MangoWC config
│   │
│   └── [other home modules]                # Unchanged - reused
│
└── docs/
    ├── MANGOWC_SETUP.md                    # NEW - Setup guide
    ├── MANGOWC_KEYBINDINGS.md              # NEW - Keybindings reference
    └── [existing docs]                     # Updated as needed
```

**Structure Decision**:

This follows the established NixOS modular configuration pattern:

1. **New target configuration**: `configurations/hetzner-mangowc.nix` composes MangoWC modules instead of KDE Plasma
2. **New desktop module**: `modules/desktop/mangowc.nix` encapsulates MangoWC compositor configuration
3. **New remote access module**: `modules/desktop/wayland-remote-access.nix` replaces X11-based XRDP with Wayland-native remote desktop
4. **Reused service modules**: All existing development/networking/onepassword modules work unchanged
5. **Optional home-manager module**: `home-modules/tools/mangowc-config.nix` for user-level customization

The modular structure enables:
- Side-by-side existence with Hetzner KDE Plasma config (no conflicts)
- Easy switching between desktop environments (rebuild with different target)
- Shared service configuration (no duplication)
- Future platform ports (M1, WSL could use same MangoWC module)

## Complexity Tracking

*This section intentionally left empty - no constitutional violations require justification.*

**Assessment**: The implementation adheres to all constitutional principles:
- Uses modular composition (no new complexity)
- Extends Hetzner reference (validates modularity)
- Follows test-before-apply (standard workflow)
- Uses appropriate override priorities (documented `mkForce`)
- Implements conditional features (audio, 1Password)
- Fully declarative (no imperative scripts)
- Includes comprehensive documentation

**No complexity violations detected.**
