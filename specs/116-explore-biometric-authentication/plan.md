# Implementation Plan: Biometric Authentication for Ryzen Desktop

**Branch**: `116-explore-biometric-authentication` | **Date**: 2025-12-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/116-explore-biometric-authentication/spec.md`

## Summary

Enable biometric authentication on the AMD Ryzen desktop workstation using a USB fingerprint reader, providing the same password-free authentication experience currently available on the ThinkPad configuration. The implementation extends the existing `services.bare-metal.enableFingerprint` option to work with USB fingerprint hardware on desktop systems, integrating with PAM for sudo, swaylock, and polkit authentication, plus 1Password biometric unlock via PAM delegation.

## Technical Context

**Language/Version**: Nix (NixOS configuration language)
**Primary Dependencies**: fprintd, libfprint, PAM, polkit, 1Password desktop app
**Storage**: Fingerprint templates in `/var/lib/fprint/<username>/` (managed by fprintd)
**Testing**: Manual verification via `fprintd-enroll`, `fprintd-verify`, sudo commands
**Target Platform**: NixOS 25.11 on x86_64 AMD Ryzen desktop
**Project Type**: NixOS module configuration (infrastructure-as-code)
**Performance Goals**: <2s screen unlock, <3s sudo authorization
**Constraints**: USB fingerprint reader hardware required, libfprint compatibility required
**Scale/Scope**: Single user (vpittamp), single machine (ryzen)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Extends existing `bare-metal.nix` module, no code duplication |
| II. Reference Implementation Flexibility | PASS | ThinkPad serves as reference, adapting patterns to Ryzen |
| III. Test-Before-Apply | PASS | Will use `nixos-rebuild dry-build --flake .#ryzen` before applying |
| IV. Override Priority Discipline | PASS | Uses existing module option pattern |
| V. Platform Flexibility | PASS | Conditional via `enableFingerprint` option |
| VI. Declarative Configuration | PASS | All config in Nix expressions, manual enrollment only post-deploy |
| VII. Documentation as Code | PASS | quickstart.md will document setup |
| X. Python Development | N/A | No Python code in this feature |
| XI. i3 IPC Alignment | N/A | No i3 IPC interaction |
| XII. Forward-Only Development | PASS | No legacy compatibility concerns |
| XIII. Deno CLI Development | N/A | No CLI tools in this feature |
| XIV. Test-Driven Development | PASS | Acceptance scenarios defined in spec |
| XV. Sway Test Framework | N/A | No window manager testing needed |

**Gate Status**: PASS - All applicable principles satisfied.

## Project Structure

### Documentation (this feature)

```text
specs/116-explore-biometric-authentication/
├── plan.md              # This file
├── research.md          # Phase 0 output - hardware recommendations
├── data-model.md        # Phase 1 output - NixOS module structure
├── quickstart.md        # Phase 1 output - setup instructions
├── contracts/           # N/A - no API contracts for NixOS config
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# NixOS module configuration (single project)
configurations/
├── ryzen.nix            # Primary target - add fingerprint config here
├── thinkpad.nix         # Reference implementation

modules/services/
├── bare-metal.nix       # Existing module with enableFingerprint option

# No new files required - configuration added to existing ryzen.nix
```

**Structure Decision**: This feature modifies existing configuration files rather than creating new modules. The implementation follows the ThinkPad reference pattern: enabling `services.bare-metal.enableFingerprint = true` and adding PAM/polkit configuration specific to the Ryzen desktop.

## Complexity Tracking

> No Constitution Check violations requiring justification.

No additional complexity introduced. This feature reuses existing patterns from the ThinkPad configuration.
