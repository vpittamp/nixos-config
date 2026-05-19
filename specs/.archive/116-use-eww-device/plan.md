# Implementation Plan: Unified Eww Device Control Panel

**Branch**: `116-use-eww-device` | **Date**: 2025-12-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/116-use-eww-device/spec.md`

## Summary

Create a unified Eww-based device control system for bare metal NixOS machines (ThinkPad, Ryzen). The feature provides tiered device controls: quick controls via expandable top bar panels (volume, brightness, Bluetooth, battery) and a comprehensive Devices tab in the monitoring panel for detailed hardware status and configuration. Hardware-adaptive detection ensures only applicable controls are shown per machine. Deprecates the existing eww-quick-panel module to consolidate device controls.

## Technical Context

**Language/Version**: Nix (flakes), Python 3.11+ (backend scripts), Yuck/SCSS (Eww widgets)
**Primary Dependencies**: Eww 0.4+ (GTK3 widgets), PipeWire/WirePlumber (audio), BlueZ (Bluetooth), UPower (battery), brightnessctl (brightness), TLP (power profiles), lm_sensors (thermals)
**Storage**: N/A (stateless - queries system state in real-time)
**Testing**: Manual verification on ThinkPad and Ryzen, sway-test framework for widget visibility
**Target Platform**: NixOS on bare metal (ThinkPad laptop, Ryzen desktop)
**Project Type**: Single - NixOS home-manager module with Eww widgets
**Performance Goals**: <100ms latency for device state updates, <2 seconds for user to complete device adjustment
**Constraints**: <50MB additional memory overhead, hardware-adaptive (no false controls), click-outside-to-close UX
**Scale/Scope**: 2 target machines (ThinkPad, Ryzen), ~10 device controls total

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | New module `eww-device-controls.nix` follows single responsibility, composes with existing eww-top-bar and eww-monitoring-panel |
| II. Reference Implementation Flexibility | ✅ PASS | ThinkPad as reference for laptop features, Ryzen as reference for desktop-only features |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build` before applying changes |
| IV. Override Priority Discipline | ✅ PASS | Use `mkDefault` for device detection flags, normal assignment for widget config |
| V. Platform Flexibility | ✅ PASS | Hardware detection via conditional logic (battery exists? brightness device present?) |
| VI. Declarative Configuration | ✅ PASS | All widget config in Nix, no imperative scripts except device query backends |
| VII. Documentation as Code | ✅ PASS | Will create quickstart.md, update CLAUDE.md with device control keybindings |
| X. Python Development Standards | ✅ PASS | Backend scripts use Python 3.11+, async patterns for D-Bus monitoring |
| XII. Forward-Only Development | ✅ PASS | Deprecates eww-quick-panel entirely, no backwards compatibility needed |
| XIV. Test-Driven Development | ⚠️ PARTIAL | Widget visibility tests via sway-test, device operations require manual verification |
| XV. Sway Test Framework | ✅ PASS | Will create JSON test cases for Devices tab visibility and keyboard navigation |

**Gate Status**: ✅ PASS - All critical principles satisfied. Partial TDD is acceptable given hardware interaction requirements.

## Project Structure

### Documentation (this feature)

```text
specs/116-use-eww-device/
├── plan.md              # This file
├── research.md          # Phase 0: Tool research and best practices
├── data-model.md        # Phase 1: Device state models
├── quickstart.md        # Phase 1: User guide for device controls
├── contracts/           # Phase 1: Backend script interfaces
│   └── device-backend.md
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-device-controls.nix          # NEW: Main device controls module
├── eww-device-controls/
│   ├── eww.yuck.nix                 # Widget definitions (expandable panels, sliders)
│   ├── eww.scss.nix                 # Catppuccin Mocha styling
│   └── scripts/
│       ├── device-backend.py        # Unified device state backend
│       ├── volume-control.sh        # Volume adjustment wrapper
│       ├── brightness-control.sh    # Brightness adjustment wrapper
│       └── bluetooth-control.sh     # Bluetooth toggle/connect wrapper
├── eww-top-bar/
│   └── [existing - will integrate device indicators with expandable panels]
├── eww-monitoring-panel.nix
│   └── [existing - will add Devices tab at index 6]
└── eww-quick-panel.nix              # DEPRECATED: Disable by default

tests/116-use-eww-device/
├── test_devices_tab_visible.json    # Sway-test: Devices tab appears on Alt+7
├── test_keyboard_navigation.json    # Sway-test: j/k/Enter works in focus mode
└── test_hardware_detection.json     # Sway-test: Only applicable controls shown
```

**Structure Decision**: Follows existing Eww module pattern (eww-top-bar, eww-monitoring-panel). Device controls module is standalone but integrates with both existing widgets. Scripts follow the existing Python backend pattern (volume-monitor.py, bluetooth-monitor.py).

## Complexity Tracking

No constitution violations requiring justification. The design follows existing patterns and consolidates rather than adds complexity.
