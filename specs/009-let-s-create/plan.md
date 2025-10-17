# Implementation Plan: NixOS KDE Plasma to i3wm Migration

**Branch**: `009-let-s-create` | **Date**: 2025-10-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/009-let-s-create/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Complete migration from KDE Plasma desktop environment to i3wm tiling window manager across all NixOS configurations. Establish hetzner-i3.nix as the primary reference configuration and consolidate all platform-specific configurations (M1, container) to derive from it. Remove obsolete configurations (WSL, VM, kubevirt, hetzner-mangowc) and KDE-specific documentation. Migrate M1 from Wayland to X11 for consistency with the reference configuration. Achieve at least 30% reduction in configuration files and 15% reduction in documentation while maintaining all critical integrations (1Password, Firefox PWAs, tmux, clipcat).

## Technical Context

**Language/Version**: Nix 2.18+, NixOS 24.11 (nixos-unstable channel)
**Primary Dependencies**:
- nixpkgs (github:NixOS/nixpkgs/nixos-unstable)
- home-manager (github:nix-community/home-manager/master)
- nixos-apple-silicon (github:tpwrules/nixos-apple-silicon) - for M1 support
- i3wm, rofi, alacritty, clipcat - window manager stack
- xrdp, PulseAudio - remote desktop with audio
- 1Password (desktop + CLI), Firefox with PWA support

**Storage**: Git repository for configuration, /nix/store for packages, no database
**Testing**: `nixos-rebuild dry-build` for validation, git branches for rollback
**Target Platform**:
- x86_64-linux (Hetzner Cloud server - primary reference)
- aarch64-linux (M1 MacBook Pro via Asahi Linux)
- Container targets (Docker/Kubernetes)

**Project Type**: Infrastructure as Code - NixOS system configuration
**Performance Goals**:
- Boot time <30 seconds to usable desktop (SC-004)
- Memory reduction of 200MB+ vs KDE Plasma (SC-005)
- Configuration rebuild <5 minutes (SC-003)

**Constraints**:
- Must preserve all existing tool integrations (1Password, PWAs, tmux, clipcat)
- Must maintain xrdp multi-session functionality on Hetzner
- M1 must use X11 (not Wayland) for consistency with reference config
- Configuration must be fully declarative (no imperative scripts)

**Scale/Scope**:
- Current: ~17 configuration files, ~45 documentation files
- Target: ≤12 configuration files (30% reduction), ≤38 docs (15% reduction)
- Current: ~3,486 lines already reduced from 46 files in previous consolidation
- Code reuse target: ≥80% shared code via hetzner-i3.nix inheritance (SC-009)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principle Compliance

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Composition** | ✅ PASS | Migration enhances modularity by consolidating configs to inherit from hetzner-i3.nix. Removes duplicate KDE modules. Uses proper NixOS option patterns (mkEnableOption, mkOption). |
| **II. Reference Implementation** | ✅ PASS | Explicitly establishes hetzner-i3.nix as new reference (from KDE Plasma on Hetzner). Aligns with constitution's flexibility for architectural transitions. Documented technical rationale: i3wm+xrdp+X11 for multi-session RDP. |
| **III. Test-Before-Apply** | ✅ PASS | Plan requires `nixos-rebuild dry-build` before all configuration changes (FR-033). Rollback via NixOS generations. |
| **IV. Override Priority Discipline** | ✅ PASS | Existing modules already use lib.mkDefault and lib.mkForce appropriately. Migration preserves these patterns. |
| **V. Platform Flexibility** | ✅ PASS | Migration maintains conditional features for GUI vs headless. Container config will derive from hetzner-i3 with GUI disabled via lib.mkIf. |
| **VI. Declarative Configuration** | ✅ PASS | All changes are declarative Nix modules. No imperative scripts. i3 config generated via environment.etc. |
| **VII. Documentation as Code** | ✅ PASS | Plan includes comprehensive documentation updates (FR-024 through FR-032). MIGRATION.md will document transition. |
| **VIII. Remote Desktop Multi-Session** | ✅ PASS | Preserves xrdp multi-session functionality. Maintains X11 for mature RDP compatibility. Clipcat clipboard manager integration. |
| **IX. Tiling WM & Productivity** | ✅ PASS | Migration to i3wm directly implements this principle. Keyboard-driven workflows, workspace management, rofi/clipcat/i3wsr integration. |

### Platform Support Standards

| Standard | Status | Notes |
|----------|--------|-------|
| **Multi-Platform Compatibility** | ✅ PASS | Maintains Hetzner (x86_64), M1 (aarch64), container support. Removes WSL (no longer in use per user clarification). |
| **Testing Requirements** | ✅ PASS | Hetzner: i3+xrdp+X11 architecture. M1: X11 migration with HiDPI scaling. Container: headless i3 (GUI components disabled). |
| **Desktop Environment Transitions** | ✅ PASS | Follows constitution's transition guidance: Research target (i3wm), evaluate X11 vs Wayland (X11 chosen for RDP), test on reference platform first, validate integrations, create MIGRATION.md. |

### Security & Authentication

| Standard | Status | Notes |
|----------|--------|-------|
| **1Password Integration** | ✅ PASS | Preserves all 1Password functionality (FR-036). Desktop app + CLI. Works with i3wm (no KDE dependency). |
| **SSH Hardening** | ✅ PASS | No changes to SSH configuration. Tailscale VPN preserved. |

### Package Management

| Standard | Status | Notes |
|----------|--------|-------|
| **Package Profiles** | ✅ PASS | Container continues to use minimal/essential profiles. No changes to profile system. |
| **Package Organization** | ✅ PASS | i3wm module properly scopes packages (modules/desktop/i3wm.nix). Follows best practices for module package scoping. |

### Complexity Justification

| Potential Violation | Assessment | Justification |
|---------------------|------------|---------------|
| **Removing configurations** | ✅ NOT A VIOLATION | Constitution principle II allows reference implementation changes. Aggressive cleanup philosophy (documented in spec Notes section) aligns with git history preservation. |
| **Breaking changes** | ✅ NOT A VIOLATION | Constitution requires documentation of breaking changes in MIGRATION.md (FR-032). No backward compatibility needed per constitution. |
| **Architectural transition** | ✅ NOT A VIOLATION | Constitution explicitly supports reference implementation flexibility when "architectural requirements demand it." Multi-session RDP + keyboard-driven productivity justify transition. |

### Gate Status: **✅ PASS**

All constitutional principles are satisfied. No violations requiring justification. Migration enhances rather than compromises modular architecture, maintains all security standards, and follows documented transition procedures. Reference implementation change (KDE Plasma → i3wm) is constitutionally supported with clear technical rationale (RDP multi-session + tiling WM productivity).

## Project Structure

### Documentation (this feature)

```
specs/009-let-s-create/
├── spec.md              # Feature specification (user stories, requirements, success criteria)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output: Technology decisions, migration patterns
├── data-model.md        # Phase 1 output: Configuration entities, module relationships
├── quickstart.md        # Phase 1 output: Migration execution guide
├── contracts/           # Phase 1 output: Validation schemas, configuration contracts
│   ├── hetzner-i3-contract.nix     # Reference configuration validation
│   ├── m1-x11-contract.nix         # M1 X11 migration validation
│   └── removal-checklist.md        # File removal verification
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### NixOS Configuration Structure (repository root)

```
/etc/nixos/
├── flake.nix                          # [MODIFY] Update nixosConfigurations, remove obsolete targets
├── configurations/
│   ├── hetzner-i3.nix                # [PRIMARY REFERENCE] Already exists, becomes base for all
│   ├── base.nix                      # [MODIFY] Update to reflect i3wm patterns (not KDE)
│   ├── m1.nix                        # [MODIFY] Import hetzner-i3.nix, add M1 overrides, migrate to X11
│   ├── container.nix                 # [MODIFY] Derive from hetzner-i3, disable GUI components
│   ├── hetzner.nix                   # [REMOVE] Old KDE-based Hetzner config
│   ├── hetzner-mangowc.nix           # [REMOVE] Wayland experimental compositor
│   ├── hetzner-minimal.nix           # [EVALUATE] May keep for nixos-anywhere deployment
│   ├── hetzner-example.nix           # [EVALUATE] May keep for deployment examples
│   ├── wsl.nix                       # [REMOVE] No longer in use
│   ├── vm-hetzner.nix                # [ARCHIVE] Move to git branch
│   ├── vm-minimal.nix                # [ARCHIVE] Move to git branch
│   ├── kubevirt-*.nix                # [ARCHIVE] Move kubevirt-* to git branch
├── modules/
│   ├── desktop/
│   │   ├── i3wm.nix                  # [KEEP] Primary window manager module
│   │   ├── xrdp.nix                  # [KEEP] Remote desktop for i3
│   │   ├── kde-plasma.nix            # [REMOVE] KDE Plasma desktop environment
│   │   ├── kde-plasma-vm.nix         # [REMOVE] KDE for VMs
│   │   ├── mangowc.nix               # [REMOVE] Wayland compositor
│   │   ├── wayland-remote-access.nix # [REMOVE] Wayland RDP (not needed with X11)
│   │   └── [other desktop modules]   # [EVALUATE] Keep if i3-compatible
│   ├── services/
│   │   ├── development.nix           # [KEEP] Dev tools
│   │   ├── networking.nix            # [KEEP] SSH, Tailscale
│   │   ├── onepassword.nix           # [KEEP] 1Password integration
│   │   └── [other services]          # [KEEP] No changes needed
├── home-modules/                      # [KEEP] User environment via home-manager
│   ├── desktop/
│   │   └── i3.nix                    # [MAY EXIST] User-specific i3 config
│   ├── tools/
│   │   ├── firefox-pwas-declarative.nix  # [KEEP] PWA support (desktop-agnostic)
│   │   ├── vscode.nix                # [KEEP] Editor config
│   │   └── [other tools]             # [KEEP] No changes
├── docs/
│   ├── ARCHITECTURE.md               # [MODIFY] Update reference implementation section
│   ├── CLAUDE.md                     # [MODIFY] Replace KDE references with i3wm
│   ├── M1_SETUP.md                   # [MODIFY] Document X11 instead of Wayland
│   ├── MIGRATION.md                  # [MODIFY] Add KDE→i3wm migration section
│   ├── PWA_SYSTEM.md                 # [MODIFY] Update for i3wm context
│   ├── PWA_COMPARISON.md             # [MODIFY] Remove KDE-specific context
│   ├── PWA_PARAMETERIZATION.md       # [MODIFY] Focus on i3wm workspace integration
│   ├── PLASMA_CONFIG_STRATEGY.md     # [REMOVE] KDE-specific
│   ├── PLASMA_MANAGER.md             # [REMOVE] KDE-specific
│   ├── IPHONE_KDECONNECT_GUIDE.md    # [REMOVE] KDE Connect not applicable
│   └── [other docs]                  # [KEEP] Unless KDE-specific
```

**Structure Decision**: This is an Infrastructure-as-Code project with NixOS configuration files organized in a modular hierarchy. The migration involves:
1. **Establishing hetzner-i3.nix as the single source of truth** for full-featured installations
2. **Platform-specific configurations inherit and override** only platform-specific settings
3. **File removal strategy**: Aggressive cleanup of obsolete configs (30% reduction target)
4. **Documentation consolidation**: Remove KDE-specific docs, update remaining to reflect i3wm
5. **Module cleanup**: Remove KDE and Wayland modules, keep i3wm and X11 modules

This structure aligns with NixOS's modular composition principle and the constitution's reference implementation flexibility.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations detected.** Constitution Check passed all gates. See Constitution Check section above for detailed compliance analysis.
