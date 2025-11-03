# Implementation Plan: Declarative PWA Installation

**Branch**: `056-declarative-pwa-installation` | **Date**: 2025-11-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/056-declarative-pwa-installation/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement fully declarative Progressive Web App (PWA) installation using NixOS home-manager configuration. System will generate ULID identifiers, Web App Manifest files, and firefoxpwa configuration from app-registry-data.nix, enabling zero-touch PWA deployment across multiple machines without manual Firefox GUI interaction. Primary requirement is cross-machine portability with single source of truth for PWA metadata (name, URL, icon, workspace assignment).

## Technical Context

**Language/Version**: Nix expression language (nixpkgs-unstable), Bash scripts for helper utilities
**Primary Dependencies**: firefoxpwa package, home-manager with programs.firefoxpwa module, ulid CLI tool for ULID generation
**Storage**: JSON configuration files (~/.local/share/firefoxpwa/config.json), Web App Manifest JSON files (hosted via HTTP or file://), ULID mapping file for persistence
**Testing**: Manual testing via nixos-rebuild switch and pwa-install-all command, validation via firefoxpwa list
**Target Platform**: NixOS systems (WSL, Hetzner Cloud, M1 Mac) with Firefox and firefoxpwa installed
**Project Type**: System configuration (NixOS modules + home-manager)
**Performance Goals**: PWA installation during rebuild <2 minutes for 15 PWAs, manifest generation <5 seconds, ULID generation <100ms
**Constraints**: ULID spec compliance (26 chars, alphabet 0-9 A-Z excluding I/L/O/U), manifest files must be accessible during installation, idempotent installation required
**Scale/Scope**: ~15 PWAs initially, extensible to 50+ PWAs, cross-machine deployment to 3+ NixOS systems

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅ PASS
- **Compliance**: Feature uses existing home-manager module pattern (`programs.firefoxpwa`)
- **Approach**: Declarative configuration in home-modules/tools/firefox-pwas-declarative.nix
- **Rationale**: Leverages home-manager's module system, no monolithic files

### Principle II: Reference Implementation Flexibility ✅ PASS
- **Compliance**: Feature tested against hetzner-sway reference configuration first
- **Approach**: Sway/Wayland compatible (Firefox + firefoxpwa work on both X11 and Wayland)
- **Validation**: Will deploy to Hetzner, M1, and WSL configurations

### Principle III: Test-Before-Apply ✅ PASS
- **Compliance**: Will use `nixos-rebuild dry-build` before switch
- **Testing**: Manual validation via `firefoxpwa list` and PWA launch tests
- **Rollback**: NixOS generations enable safe rollback if installation fails

### Principle VI: Declarative Configuration Over Imperative ✅ PASS
- **Compliance**: Fully declarative via home-manager programs.firefoxpwa module
- **Approach**: No imperative post-install scripts, all config via Nix expressions
- **Exception**: Helper commands (pwa-install-all) are declaratively defined wrappers

### Principle VII: Documentation as Code ✅ PASS
- **Compliance**: Will create quickstart.md with usage examples and troubleshooting
- **Documentation**: Inline comments in Nix modules, update CLAUDE.md with PWA workflows
- **Migration**: Existing manual PWA workflow documented, migration path clear

### No Constitution Violations
This feature fully complies with NixOS modular configuration principles. No complexity justification required.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
/etc/nixos/
├── home-modules/tools/
│   ├── firefox-pwas-declarative.nix    # Main home-manager module for declarative PWAs
│   └── pwa-helpers.nix                 # Helper scripts (pwa-install-all, pwa-get-ids, etc.)
│
├── shared/
│   ├── app-registry-data.nix           # PWA metadata source of truth (existing)
│   └── pwa-sites.nix                   # ULID mapping and manifest metadata (NEW)
│
├── assets/
│   └── pwa-icons/                      # Custom PWA icons (existing)
│       ├── youtube.png
│       ├── google-ai.png
│       └── ...
│
└── configurations/
    ├── hetzner-sway.nix                # Reference config imports firefox-pwas-declarative
    ├── m1.nix                          # M1 Mac imports firefox-pwas-declarative
    └── wsl.nix                         # WSL imports firefox-pwas-declarative
```

**Structure Decision**: NixOS system configuration (modular composition pattern). Primary logic in home-manager module (`firefox-pwas-declarative.nix`) with data source in existing `app-registry-data.nix`. New `pwa-sites.nix` stores ULID mappings and manifest metadata. Helper scripts packaged as Nix derivations in `pwa-helpers.nix`. No separate src/tests directories - testing via NixOS rebuild and manual validation.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations** - Feature fully complies with all constitution principles.

---

## Post-Design Constitution Re-Evaluation

*Re-evaluation Date*: 2025-11-02 (Phase 1 Complete)

### Principle I: Modular Composition ✅ PASS (Confirmed)
- **Design Validation**: Custom home-manager module in `firefox-pwas-declarative.nix` with clear single responsibility
- **Module Reuse**: Leverages existing pwa-sites.nix, pwa-helpers.nix patterns
- **No Duplication**: Manifest generation and config management centralized in single module

### Principle II: Reference Implementation Flexibility ✅ PASS (Confirmed)
- **Testing Strategy**: Will test on hetzner-sway first, then deploy to M1 and WSL
- **Platform Compatibility**: firefoxpwa works identically on all NixOS targets (X11 and Wayland)
- **Cross-Platform Validation**: Static ULIDs ensure identical behavior across machines

### Principle III: Test-Before-Apply ✅ PASS (Confirmed)
- **Testing Workflow**: Documented in quickstart.md - always use `nixos-rebuild dry-build` first
- **Validation Commands**: pwa-validate ensures correctness before deployment
- **Rollback Safety**: NixOS generations enable safe rollback if installation fails

### Principle VI: Declarative Configuration Over Imperative ✅ PASS (Confirmed)
- **Fully Declarative**: All configuration via Nix expressions (pwa-sites.nix, home-manager module)
- **Activation Scripts**: Used only for idempotent installation, not configuration generation
- **No Manual Steps**: Zero-touch deployment achieved via home.activation

### Principle VII: Documentation as Code ✅ PASS (Confirmed)
- **Comprehensive Docs**: quickstart.md, data-model.md, contracts/ cover all workflows
- **Inline Comments**: Nix modules will include purpose, dependencies, options documentation
- **CLAUDE.md Update**: Agent context updated with new PWA installation workflows

### No New Violations Introduced

**Conclusion**: Design adheres to all relevant constitution principles. No complexity justification required. Feature ready for implementation (Phase 2).
