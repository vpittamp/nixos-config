# Implementation Plan: Monitoring Panel Click-Through Fix and Docking Mode

**Branch**: `125-convert-sidebar-split-pane` | **Date**: 2025-12-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/125-convert-sidebar-split-pane/spec.md`

## Summary

Enhance the eww monitoring panel with two key capabilities: (1) Fix click-through behavior when hidden so mouse clicks pass through to underlying windows, and (2) Add a docked mode that reserves screen space via Sway's exclusive zone, causing tiled windows to automatically resize. The `Mod+Shift+M` keybinding will cycle between overlay and docked modes, replacing the current focus mode functionality.

## Technical Context

**Language/Version**: Nix (flakes), Yuck (eww widget DSL), SCSS, Bash (scripts), Python 3.11+ (backend)
**Primary Dependencies**: eww 0.4+, Sway IPC (layer-shell protocol), GTK3, i3ipc.aio
**Storage**: File-based state persistence (`$XDG_STATE_HOME/eww-monitoring-panel/dock-mode`)
**Testing**: grim (screenshots), sway-test framework, manual verification
**Target Platform**: NixOS with Sway Wayland compositor (Hetzner headless VNC, M1 Mac)
**Project Type**: Single NixOS home-manager module with integrated widgets
**Performance Goals**: <7% CPU contribution, <100ms click-through latency after hide, <500ms mode transition
**Constraints**: Must preserve existing CPU optimizations (deflisten, disabled tabs, 30s polling)
**Scale/Scope**: Single-user desktop environment, 1-4 monitors

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ Pass | Changes confined to eww-monitoring-panel.nix module |
| II. Reference Implementation | ✅ Pass | Hetzner-sway is reference; changes will be tested there first |
| III. Test-Before-Apply | ✅ Pass | Will use `nixos-rebuild dry-build` before switch |
| VI. Declarative Configuration | ✅ Pass | All changes via Nix expressions, no imperative scripts |
| XI. i3 IPC Alignment | ✅ Pass | Sway IPC used for workspace/window state queries |
| XII. Forward-Only Development | ✅ Pass | Replacing focus mode with dock mode (no legacy support) |
| XIV. Test-Driven Development | ✅ Pass | Will use grim screenshots and sway-test for validation |
| XV. Sway Test Framework | ✅ Pass | Will create declarative JSON tests for mode transitions |

## Project Structure

### Documentation (this feature)

```text
specs/125-convert-sidebar-split-pane/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/          # Quality checklists
│   └── requirements.md  # Spec validation checklist
├── screenshots/         # Before/after UI screenshots
│   └── before-monitoring-panel.png
└── tasks.md             # Phase 2 output (from /speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix    # Main module (defwindow, scripts, styles)
├── sway-keybindings.nix        # Keybinding definitions
└── sway.nix                    # Sway modes configuration

~/.config/eww-monitoring-panel/  # Generated at runtime
├── eww.yuck                     # Widget definitions
└── eww.scss                     # Styles

~/.local/state/eww-monitoring-panel/  # Persistent state
└── dock-mode                    # Boolean: "docked" or "overlay"
```

**Structure Decision**: This is a modification to existing modules, not new directory creation. The eww-monitoring-panel.nix file contains inline yuck and scss generation.

## Complexity Tracking

No constitution violations requiring justification.
