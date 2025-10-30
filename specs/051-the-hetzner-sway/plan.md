# Implementation Plan: M1 Configuration Alignment with Hetzner-Sway

**Branch**: `051-the-hetzner-sway` | **Date**: 2025-10-30 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/051-the-hetzner-sway/spec.md`

## Summary

Align the M1 MacBook Pro NixOS configuration with the hetzner-sway reference implementation to achieve 95%+ configuration parity while preserving architectural differences for hardware-specific features. The alignment focuses on three key areas: (1) adding missing system service modules (i3-project-daemon, onepassword-automation, keyd), (2) unifying home-manager module imports to match hetzner-sway's clean structure, and (3) fixing Sway configuration issues (workspace-mode-handler hardcoded outputs). This ensures consistent development environments, portable workflows, and reduced maintenance burden across both platforms.

## Technical Context

**Language/Version**: Nix 2.18+, NixOS 24.11, Python 3.11 (for system daemons), TypeScript/Deno 1.40+ (for CLI tools)
**Primary Dependencies**: nixpkgs 24.11, home-manager 24.11, nixos-apple-silicon flake (M1-specific), Sway compositor, i3ipc-python, Deno standard library
**Storage**: Git version control for configuration, JSON files for dynamic Sway configuration, systemd state for service management
**Testing**: `nixos-rebuild dry-build` for static validation, manual workflow testing on both platforms, systemd service status verification
**Target Platform**: NixOS 24.11 on aarch64-linux (Apple Silicon M1) and x86_64-linux (Hetzner Cloud VM with headless Wayland)
**Project Type**: System configuration (NixOS modules, home-manager modules, systemd services)
**Performance Goals**: <5 second system rebuild evaluation, <100ms service daemon latency, zero user-visible behavioral differences
**Constraints**: Must preserve hetzner-sway headless functionality, must not break existing M1 hardware features, changes must be declarative and reversible
**Scale/Scope**: ~25 NixOS module files, ~76 home-manager module files, 3 service daemons, 2 deployment targets

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ I. Modular Composition
- Configuration is built from composable modules (modules/services/, modules/desktop/, home-modules/)
- Changes will be module additions/adjustments, not code duplication
- Clear responsibility: system services in configuration.nix, user apps in home-manager
- **PASS**: Alignment preserves modular structure

### ✅ II. Reference Implementation Flexibility
- Hetzner-sway is confirmed as reference implementation (Sway/Wayland, headless VNC, Feature 047)
- M1 adapts to match reference while preserving hardware-specific settings
- No breaking changes to reference configuration
- **PASS**: M1 correctly adapts to reference

### ✅ III. Test-Before-Apply (NON-NEGOTIABLE)
- All changes will be tested with `nixos-rebuild dry-build --flake .#m1 --impure`
- Hetzner-sway will also be tested to ensure no regressions
- Rollback procedures documented in quickstart.md
- **PASS**: Testing workflow established

### ✅ IV. Override Priority Discipline
- No new `lib.mkForce` usage required
- Existing overrides in M1 are justified (e.g., videoDrivers for ARM64)
- Module additions use standard imports
- **PASS**: No priority conflicts

### ✅ V. Platform Flexibility Through Conditional Features
- Sway module already uses conditional logic for headless vs physical display
- New modules (i3-project-daemon) work identically on both platforms
- Platform-specific services correctly gated (WayVNC, RustDesk)
- **PASS**: Conditionals work correctly

### ✅ VI. Declarative Configuration Over Imperative
- All changes are declarative module imports and service configurations
- No post-install scripts required
- Dynamic Sway configuration uses template-based generation (Feature 047)
- **PASS**: Fully declarative

### ✅ VII. Documentation as Code
- research.md documents all decisions and alternatives considered
- quickstart.md will provide step-by-step implementation guide
- CLAUDE.md will be updated with M1-specific sections
- Architectural differences documented in spec.md
- **PASS**: Comprehensive documentation

### ✅ VIII. Remote Desktop & Multi-Session Standards
- Not applicable - this feature aligns existing configurations, doesn't change remote access strategy
- M1 uses RustDesk (peer-to-peer), hetzner uses WayVNC (headless VNC)
- **PASS**: No impact on remote desktop standards

### ✅ IX. Tiling Window Manager & Productivity Standards
- Both platforms use Sway tiling compositor
- i3pm project management will work identically after alignment
- Keyboard-driven workflows preserved
- **PASS**: Productivity standards maintained

### ✅ X. Python Development & Testing Standards
- i3-project-daemon uses Python 3.11 with asyncio patterns (existing, well-tested)
- No new Python development required for alignment
- Service daemons follow established patterns
- **PASS**: Standards followed

### ✅ XI. i3 IPC Alignment & State Authority
- i3pm daemon uses i3 IPC as authoritative source (existing implementation)
- Sway compositor uses same IPC protocol as i3
- No changes to IPC integration required
- **PASS**: IPC alignment maintained

### ✅ XII. Forward-Only Development & Legacy Elimination
- Alignment removes technical debt (missing modules on M1)
- No backwards compatibility layers added
- workspace-mode-handler fix replaces hardcoded implementation
- **PASS**: Forward-only approach

### ✅ XIII. Deno CLI Development Standards
- Not applicable - no new CLI tools required for alignment
- Existing i3pm CLI tools already use Deno (Feature 026)
- **PASS**: No impact on Deno standards

## Overall Assessment: ✅ PASS

All constitutional principles are satisfied. This feature aligns configurations without introducing complexity, maintains modular composition, and follows test-before-apply discipline. No violations require justification.

## Project Structure

### Documentation (this feature)

```
specs/051-the-hetzner-sway/
├── spec.md              # Feature specification (user scenarios, requirements)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (completed)
├── data-model.md        # Phase 1 output (next)
├── quickstart.md        # Phase 1 output (next)
├── contracts/           # Phase 1 output (next)
│   ├── m1-module-imports.nix      # Required module additions for M1
│   ├── home-manager-alignment.nix # Home-manager structure changes
│   └── sway-fixes.patch           # workspace-mode-handler fixes
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (NixOS configuration repository root)

```
/etc/nixos/
├── configurations/
│   ├── base.nix                # Shared base (no changes)
│   ├── hetzner-sway.nix        # Reference implementation (no changes)
│   └── m1.nix                  # TARGET: Add missing module imports
│
├── modules/
│   ├── services/
│   │   ├── i3-project-daemon.nix      # Existing (already works on M1)
│   │   ├── onepassword-automation.nix # Existing (already works on M1)
│   │   └── keyd.nix                   # Existing (optional for M1)
│   └── desktop/
│       └── sway.nix            # Existing (already unified with conditionals)
│
├── home-modules/
│   ├── desktop/
│   │   ├── sway.nix                        # Existing (unified)
│   │   ├── sway-config-manager.nix         # TARGET: Fix workspace-mode-handler
│   │   ├── walker.nix                      # Existing (unified)
│   │   └── declarative-cleanup.nix         # TARGET: Add to M1 home-manager
│   ├── shell/
│   │   └── bash.nix                        # Existing (unified)
│   ├── editors/
│   │   └── neovim.nix                      # Existing (unified)
│   ├── terminal/
│   │   └── tmux.nix                        # Existing (unified)
│   └── tools/
│       └── i3pm/                           # Existing (unified)
│
├── home-manager/
│   ├── home-vpittamp.nix        # Hetzner home-manager (reference structure)
│   └── base-home.nix            # M1 home-manager (TARGET: simplify to match hetzner)
│
└── docs/
    ├── CLAUDE.md                # TARGET: Update with M1-specific sections
    └── SWAY_CONFIG_MANAGEMENT.md # Existing documentation
```

**Structure Decision**: NixOS configuration repository structure. Changes are localized to:
1. **configurations/m1.nix**: Add 3 module imports (i3-project-daemon, onepassword-automation, keyd)
2. **home-modules/desktop/sway-config-manager.nix**: Fix hardcoded output names in workspace-mode-handler
3. **home-manager/base-home.nix**: Simplify imports to match hetzner-sway's clean structure
4. **docs/CLAUDE.md**: Add M1-specific quick reference sections

No new files created, only modifications to existing configuration files.

## Complexity Tracking

*No constitutional violations identified - this section is empty.*

All changes follow existing patterns and reduce complexity by eliminating configuration drift between platforms.
