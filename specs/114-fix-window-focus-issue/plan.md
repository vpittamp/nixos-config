# Implementation Plan: Fix Window Focus/Click Issue

**Branch**: `114-fix-window-focus-issue` | **Date**: 2025-12-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/114-fix-window-focus-issue/spec.md`

## Summary

Fix a bug where certain windows cannot receive click/input events when tiled but work correctly when maximized. The issue affects all three configurations (ThinkPad, M1, Hetzner-Sway) and is likely caused by window geometry vs input region mismatches, smart_borders configuration, Eww layer-shell interference, or coordinate handling with scaling.

The approach is:
1. Diagnose the exact root cause using Sway IPC state inspection
2. Implement targeted fix based on findings
3. Create diagnostic tooling for future troubleshooting

## Technical Context

**Language/Version**: Nix (NixOS modules), Python 3.11+ (diagnostics), Bash (scripts)
**Primary Dependencies**: Sway 1.9+, wlroots 0.17+, Eww (GTK3), i3ipc-python
**Storage**: N/A (configuration-based fix)
**Testing**: sway-test framework (Deno/TypeScript), manual verification
**Target Platform**: NixOS with Sway Wayland compositor (ThinkPad, M1, Hetzner-Sway)
**Project Type**: Configuration fix with diagnostic tooling
**Performance Goals**: Zero perceptible delay in click registration
**Constraints**: Must not break existing functionality (floating, fullscreen, panels)
**Scale/Scope**: Fix applies to all Sway-based configurations in this repo

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Fix will be in existing sway.nix or sway-config-manager modules |
| II. Reference Implementation | PASS | Hetzner-Sway is reference; ThinkPad also affected |
| III. Test-Before-Apply | PASS | Will use `nixos-rebuild dry-build` before switch |
| VI. Declarative Configuration | PASS | All changes in Nix modules |
| XI. i3 IPC Alignment | PASS | Will use Sway IPC (GET_TREE) for diagnostics |
| XII. Forward-Only Development | PASS | Will replace faulty config, not add workarounds |
| XIV. Test-Driven Development | PASS | Will create sway-test cases for verification |
| XV. Sway Test Framework | PASS | Will use declarative JSON tests |

**Gate Status**: PASS - No violations requiring justification

## Project Structure

### Documentation (this feature)

```text
specs/114-fix-window-focus-issue/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output - root cause investigation
├── data-model.md        # Phase 1 output - diagnostic data structures
├── quickstart.md        # Phase 1 output - testing/verification guide
├── contracts/           # Phase 1 output - diagnostic command interfaces
├── checklists/          # Validation checklists
│   └── requirements.md  # Spec quality checklist (complete)
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# Bug fix touches existing modules (no new directories)
home-modules/desktop/
├── sway.nix                    # Main Sway configuration
├── sway-config-manager.nix     # Dynamic config management
├── sway-default-appearance.json # Appearance settings (gaps, borders)
└── eww-monitoring-panel.nix    # Eww panel configuration

# Diagnostic tooling (may extend existing)
home-modules/tools/
├── i3pm/                       # Existing project manager CLI
│   └── src/commands/           # May add diagnose-input command
└── sway-test/                  # Test framework
    └── tests/sway-tests/       # Test cases for this fix
```

**Structure Decision**: This is a bug fix in existing modules, not a new feature. Changes will be made to existing sway.nix, sway-config-manager.nix, and potentially appearance.json. Diagnostic tooling may extend existing i3pm CLI or create a focused diagnostic script.

## Complexity Tracking

> No violations - table not required
