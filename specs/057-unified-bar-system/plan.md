# Implementation Plan: Unified Bar System with Enhanced Workspace Mode

**Branch**: `057-unified-bar-system` | **Date**: 2025-11-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/057-unified-bar-system/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Unify bar modules across top bar (Swaybar), bottom bar (Eww), and notification center (SwayNC) with centralized Catppuccin Mocha theming, synchronized workspace mode indicators, enhanced workspace preview cards, keyboard-driven workspace move operations, and app-aware notification icons. Based on research into AGS, SwayNC, and Eww patterns, the solution leverages existing Python 3.11+ event-driven architecture with i3ipc.aio for real-time state synchronization, Eww overlays for visual feedback, and JSON-based configuration for hot-reloadable appearance settings.

## Technical Context

**Language/Version**: Python 3.11+ (existing workspace_panel.py daemon), Nix configuration language, GTK3 CSS for SwayNC theming
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Eww 0.4+ (ElKowar's Wacky Widgets with Yuck DSL), SwayNC 0.10+ (notification center), pyxdg (desktop entry resolution), orjson (fast JSON serialization)
**Storage**: JSON configuration files (~/.config/sway/appearance.json for unified theme, ~/.config/swaync/config.json for notification center layout, ~/.config/eww/workspace-mode-preview.json for preview card config)
**Testing**: sway-test framework (TypeScript/Deno-based declarative tests, Principle XV), pytest for Python daemon unit tests, manual UI validation for theme consistency
**Target Platform**: NixOS with Sway/Wayland compositor (Hetzner Cloud: 3 virtual displays HEADLESS-1/2/3, M1 Mac: single eDP-1 Retina display)
**Project Type**: System integration (desktop environment configuration)
**Performance Goals**: <50ms UI sync latency between bars (SC-003), <50ms workspace mode preview appearance (SC-002), <200ms workspace move execution (SC-004), <3s theme reload propagation (SC-001)
**Constraints**: Must preserve existing SwayNC setup (A001), maintain Feature 058 workspace mode backend, hot-reload appearance without Sway restart, support multi-monitor with per-output bars
**Scale/Scope**: 3 bar components (top/bottom/notification), 6 user stories (P1-P4 priority), 41 functional requirements across 7 categories, ~5-10 theme variables to centralize

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Status | Justification |
|-----------|-------------|---------|---------------|
| **I. Modular Composition** | Bar modules MUST be composable, not monolithic | ✅ PASS | Eww, Swaybar, and SwayNC are separate modules. Unified theming via shared JSON config (~/.config/sway/appearance.json). |
| **III. Test-Before-Apply** | Configuration changes MUST be tested with dry-build | ✅ PASS | All Nix changes will be tested with `nixos-rebuild dry-build --flake .#hetzner-sway` and `.#m1` |
| **VI. Declarative Configuration** | System config MUST be declared in Nix, not imperative | ✅ PASS | Bar configurations in home-modules/desktop/*.nix. Appearance JSON files generated via Nix. No manual file editing. |
| **VII. Documentation as Code** | Architectural decisions MUST be documented | ✅ PASS | This plan documents architecture. quickstart.md will be created in Phase 1. |
| **X. Python Development Standards** | Python 3.11+ with i3ipc.aio, pytest, Pydantic | ✅ PASS | Extends existing workspace_panel.py daemon (Python 3.11+, i3ipc.aio). Pydantic models for theme config. pytest for daemon tests. |
| **XI. i3 IPC Alignment** | Sway IPC MUST be authoritative for state | ✅ PASS | All workspace state queries via Sway IPC GET_WORKSPACES/GET_TREE. Event-driven via SUBSCRIBE. |
| **XII. Forward-Only Development** | No legacy compatibility, optimal solution only | ✅ PASS | Extends existing bars, no backwards compatibility with old theme systems. Complete replacement of ad-hoc theme variables. |
| **XIII. Deno CLI Standards** | New CLI tools MUST use Deno/TypeScript | ⚠️ N/A | No new CLI tools. Extends existing Python daemon and Nix config. |
| **XIV. Test-Driven Development** | Tests before implementation, autonomous execution | ✅ PASS | sway-test framework for workspace mode preview (JSON test definitions). pytest for daemon unit tests. Manual UI validation for theme consistency (visual inspection required). |
| **XV. Sway Test Framework** | Window manager tests via declarative JSON | ✅ PASS | Workspace mode preview and move operations tested via sway-test with partial state comparison (focusedWorkspace, window placement). |

**Overall Status**: ✅ **PASSED** - No gate violations. All principles align with feature design.

**Notes**:
- Principle XIII (Deno CLI) not applicable - extending existing Python daemon, not creating new CLI tools
- Manual UI validation required for theme consistency (visual inspection cannot be fully automated for color/appearance verification)

---

## Post-Phase 1 Constitution Re-Check

*Executed after data model, contracts, and quickstart generation*

| Principle | Re-Check Status | Phase 1 Impact |
|-----------|----------------|----------------|
| **I. Modular Composition** | ✅ PASS | Confirmed: 6 new Nix modules (unified-bar-theme.nix, swaync.nix, sway-workspace-preview.nix) + 3 modified modules. All composable with clear separation. |
| **VI. Declarative Configuration** | ✅ PASS | Confirmed: All JSON configs (appearance.json, workspace-preview-output.json, workspace-mode-ipc.json) generated by Nix. No imperative scripts. |
| **X. Python Development Standards** | ✅ PASS | Confirmed: 4 new Python modules (theme_manager.py, preview_renderer.py, notification_icon_resolver.py, workspace-preview-daemon) follow Python 3.11+, i3ipc.aio, Pydantic patterns. |
| **XI. i3 IPC Alignment** | ✅ PASS | Confirmed: All workspace queries via Sway IPC GET_WORKSPACES/GET_TREE. Event-driven via SUBSCRIBE. No custom state tracking without IPC validation. |
| **XIV. Test-Driven Development** | ✅ PASS | Confirmed: 4 sway-test JSON test suites planned (test_theme_propagation.json, test_workspace_preview.json, test_workspace_move.json, test_notification_icons.json) + pytest for Python modules. |
| **XV. Sway Test Framework** | ✅ PASS | Confirmed: Partial state comparison mode for focusedWorkspace, workspace structure, window placement. JSON test definitions follow schema. |

**Post-Design Status**: ✅ **ALL GATES PASSED** - No new violations introduced during design phase.

**Implementation Readiness**: ✅ Ready to proceed with `/speckit.tasks` command for task breakdown

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
# NixOS Configuration Modules
home-modules/desktop/
├── swaybar.nix                          # Top bar (Swaybar) config - MODIFY
├── swaybar-enhanced.nix                 # Python status generator - MODIFY
├── eww-workspace-bar.nix                # Bottom bar (Eww) config - MODIFY
├── swaync.nix                           # Notification center config - CREATE
├── unified-bar-theme.nix                # Centralized theme module - CREATE
└── sway-workspace-preview.nix           # Workspace preview overlay - CREATE

home-modules/tools/sway-workspace-panel/
├── workspace_panel.py                   # Main daemon - MODIFY
├── models.py                            # Feature 058 models - MODIFY
├── theme_manager.py                     # Theme loading/validation - CREATE
├── preview_renderer.py                  # Workspace preview card generation - CREATE
└── notification_icon_resolver.py        # App-aware notification icons - CREATE

# Configuration Files (generated by Nix, hot-reloadable)
~/.config/sway/
├── appearance.json                      # Unified theme variables - GENERATE
└── workspace-preview-config.json        # Preview card layout - GENERATE

~/.config/swaync/
├── config.json                          # Notification center layout - GENERATE
└── style.css                            # SwayNC theming (Catppuccin) - GENERATE

~/.config/eww/eww-workspace-bar/
├── eww.yuck                             # Eww widget definitions - MODIFY
├── eww.scss                             # Eww styling (Catppuccin) - MODIFY
└── workspace-mode-preview.yuck          # Preview card widget - CREATE

# Test Files
tests/sway-tests/
├── unified-bar/
│   ├── test_theme_propagation.json      # Theme reload validation
│   ├── test_workspace_preview.json      # Preview card appearance
│   ├── test_workspace_move.json         # Move operations
│   └── test_notification_icons.json     # Icon resolution
└── fixtures/
    └── theme-samples.json               # Test theme configurations
```

**Structure Decision**: System integration feature extending existing desktop modules. No new standalone applications - modifications to existing Swaybar, Eww, SwayNC configurations and workspace_panel.py daemon. Centralized theme management via new `unified-bar-theme.nix` module that generates JSON configs consumed by all bar components. Test coverage via sway-test framework for UI behaviors and pytest for daemon logic.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations identified. All design decisions align with Constitution principles.*
