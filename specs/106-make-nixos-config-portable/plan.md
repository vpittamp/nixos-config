# Implementation Plan: Make NixOS Config Portable

**Branch**: `106-make-nixos-config-portable` | **Date**: 2025-12-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/106-make-nixos-config-portable/spec.md`

## Summary

Make NixOS configuration portable so it can be built from any directory (git worktrees) with identical results to building from `/etc/nixos`. The solution involves:
1. Converting hardcoded `/etc/nixos` paths in Nix files to use Nix store paths for runtime assets
2. Updating shell/Python scripts to use dynamic path discovery via git or environment variables
3. Making environment variables configurable rather than hardcoded

## Technical Context

**Language/Version**: Nix (flakes), Bash 5.0+, Python 3.11+ (existing daemon standard per Constitution Principle X)
**Primary Dependencies**: NixOS/nixpkgs, home-manager, flake-parts
**Storage**: N/A (configuration management, not data storage)
**Testing**: Manual dry-build verification, runtime testing after switch
**Target Platform**: Linux (NixOS) - WSL, Hetzner x86_64, M1 ARM64
**Project Type**: Single (NixOS configuration repository)
**Performance Goals**: Build parity - identical derivation hashes regardless of source directory
**Constraints**: Must not break existing functionality; runtime script execution <100ms
**Scale/Scope**: ~131 files with 2,734 `/etc/nixos` references (57 critical runtime paths)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Solution uses existing module structure |
| II. Reference Implementation | ✅ PASS | Changes apply to all targets (hetzner-sway, m1, wsl) |
| III. Test-Before-Apply | ✅ PASS | Dry-build required before switch (spec SC-001) |
| IV. Override Priority | ✅ PASS | No priority changes needed |
| V. Platform Flexibility | ✅ PASS | Solution works across all platforms |
| VI. Declarative Config | ✅ PASS | Paths will be declarative via Nix store |
| VII. Documentation as Code | ✅ PASS | CLAUDE.md already updated with build commands |
| X. Python Standards | ✅ PASS | Python scripts will use dynamic discovery |
| XI. i3 IPC Alignment | N/A | Not modifying i3/Sway IPC behavior |
| XII. Forward-Only | ✅ PASS | Complete replacement of hardcoded paths, no dual support |
| XIII. Deno CLI Standards | N/A | No Deno changes required |
| XIV. Test-Driven | ✅ PASS | Acceptance criteria are testable (dry-build, runtime) |

**Gate Status**: ✅ PASS - No violations requiring justification

## Project Structure

### Documentation (this feature)

```text
specs/106-make-nixos-config-portable/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (path categorization)
├── quickstart.md        # Phase 1 output (usage guide)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Files requiring modification (by category)

## Nix Configuration Files (runtime asset paths → Nix store)
home-modules/desktop/app-registry-data.nix    # 14 icon references
shared/pwa-sites.nix                          # 29 icon references
home-modules/desktop/sway.nix                 # Script exec paths
home-modules/desktop/i3.nix                   # Script exec paths
modules/services/i3-project-daemon.nix        # Documentation URLs

## Shell Scripts (hardcoded paths → dynamic discovery)
scripts/emergency-recovery.sh                 # cd /etc/nixos
scripts/setup-test-session.sh                 # Multiple hardcoded paths
scripts/fzf-launcher.sh                       # FLAKE_PATH default
scripts/test-feature-035.sh                   # SPEC_DIR hardcoded
scripts/nixos-build-wrapper                   # Default path
scripts/deploy-nixos-ssh.sh                   # Remote paths
scripts/claude-hooks/stop-notification.sh     # Callback paths
tests/i3pm/integration/run_*.sh               # Test script paths

## Python Scripts (constants → dynamic discovery)
scripts/code-cleanup-check.py                 # DAEMON_DIR constant
scripts/analyze-conflicts.py                  # target_dir constant
scripts/audit-duplicates.py                   # target_dir constant
home-modules/tools/sway-workspace-panel/models.py  # project_directory

## Environment Variables
home-modules/tools/nix.nix                    # NH_FLAKE, NH_OS_FLAKE
```

**Structure Decision**: No new directories needed. Modifications apply to existing files across the repository.

## Complexity Tracking

No violations requiring justification. Solution follows Forward-Only Development (Principle XII) by completely replacing hardcoded paths.
