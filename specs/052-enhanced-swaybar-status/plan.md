# Implementation Plan: Enhanced Swaybar Status

**Branch**: `052-enhanced-swaybar-status` | **Date**: 2025-10-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/052-enhanced-swaybar-status/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the Sway window manager's status bar with rich system status indicators (volume, battery, WiFi, Bluetooth) featuring icons, hover tooltips, and click interactions while preserving all native Sway functionality. The implementation will follow the i3bar protocol to integrate status blocks that query system state via D-Bus and Linux system interfaces, supporting both visual feedback and interactive controls.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon runtime for D-Bus integration)
**Primary Dependencies**: i3bar protocol (JSON format), pydbus (D-Bus queries), Nerd Fonts (icon rendering)
**Storage**: Configuration files only (swaybar config, status generator config) - no persistent data storage
**Testing**: pytest with pytest-asyncio for async D-Bus operations
**Target Platform**: Linux (NixOS) with Sway/Wayland compositor, i3bar protocol compatibility
**Project Type**: Single project - system utility with status generator script/daemon
**Performance Goals**: <16ms render time per update, <2 second status refresh for all indicators, <100ms click response latency
**Constraints**: <2% CPU usage, <50MB memory, must fit within 20-30px status bar height, i3bar protocol compliance
**Scale/Scope**: Single-user system utility, 4 primary status indicators (volume, battery, WiFi, Bluetooth), ~500-1000 LOC for status generator

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle Alignment

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Composition** | ✅ PASS | Status bar enhancement will be implemented as a NixOS module in `home-modules/desktop/swaybar-enhanced.nix` with clear separation from existing Sway configuration |
| **II. Reference Implementation** | ✅ PASS | Hetzner Sway configuration is the reference platform - this feature directly enhances the existing Sway/Wayland setup |
| **III. Test-Before-Apply** | ✅ PASS | Will use `nixos-rebuild dry-build` before applying changes; status generator can be tested independently before NixOS integration |
| **IV. Override Priority** | ✅ PASS | Module will use `lib.mkDefault` for overrideable options (icon sets, colors, update intervals) |
| **V. Platform Flexibility** | ✅ PASS | Will use conditional logic to detect hardware (battery presence, bluetooth adapter) and adapt status blocks accordingly |
| **VI. Declarative Configuration** | ✅ PASS | All configuration will be declared in NixOS modules; swaybar config generated via `xdg.configFile` in home-manager |
| **VII. Documentation as Code** | ✅ PASS | Includes quickstart.md, module header comments, and integration with existing CLAUDE.md |
| **VIII. Remote Desktop Standards** | ⚠️ N/A | Feature is specific to Sway/Wayland on hetzner-sway; does not affect xrdp/X11 configurations |
| **IX. Tiling WM Standards** | ✅ PASS | Enhances Sway (tiling WM) with keyboard-accessible status controls; preserves all native Sway features |
| **X. Python Development Standards** | ⚠️ CONDITIONAL | If Python chosen: will follow async patterns, pytest testing, type hints, Rich UI for diagnostic tools |
| **XI. i3 IPC Alignment** | ⚠️ N/A | Uses i3bar protocol (not i3 IPC) for status bar communication; queries system state via D-Bus instead |
| **XII. Forward-Only Development** | ✅ PASS | No legacy compatibility needed - new feature addition to existing Sway setup |
| **XIII. Deno CLI Standards** | ⚠️ CONDITIONAL | If Deno chosen: will use @std/cli, TypeScript, compile to standalone executable |

### Gate Evaluation (Initial - Pre-Research)

**GATE DECISION**: ✅ **PASSED - PROCEEDED TO PHASE 0**

**Clarifications Required** (resolved in research.md):
1. ✅ Language choice → **Python 3.11+** (D-Bus integration, consistency)
2. ✅ Icon rendering strategy → **Nerd Fonts** (already deployed, zero overhead)

### Gate Re-Evaluation (Post-Design)

**GATE DECISION**: ✅ **PROCEED TO IMPLEMENTATION**

**Final Alignment**:
- **Python Development Standards (X)**: ✅ Using Python 3.11+, async/await, pytest, type hints, pydbus for D-Bus
- **Modular Composition (I)**: ✅ home-modules/desktop/swaybar-enhanced.nix with modular status blocks
- **Declarative Configuration (VI)**: ✅ All config via NixOS/home-manager, generated via xdg.configFile
- **Forward-Only Development (XII)**: ✅ New feature, no legacy compatibility needed

**No violations detected**. Ready for implementation phase.

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
home-modules/desktop/
├── swaybar-enhanced.nix         # Main NixOS module for enhanced swaybar
└── swaybar/                     # Status bar components (if modularized)
    ├── status-generator.py      # OR status-generator.ts (Python or Deno)
    ├── config/
    │   ├── icons.nix           # Icon configuration
    │   └── themes.nix          # Color themes
    └── blocks/
        ├── volume.py/ts         # Volume status block
        ├── battery.py/ts        # Battery status block
        ├── network.py/ts        # WiFi status block
        └── bluetooth.py/ts      # Bluetooth status block

tests/swaybar/                   # Test suite
├── unit/
│   ├── test_volume_block.py
│   ├── test_battery_block.py
│   ├── test_network_block.py
│   └── test_bluetooth_block.py
├── integration/
│   └── test_status_generator.py
└── fixtures/
    └── mock_dbus_responses.py

assets/
└── icons/                       # Icon files if using custom SVGs
    ├── volume/
    ├── battery/
    ├── network/
    └── bluetooth/
```

**Structure Decision**: Single project structure following NixOS home-manager module patterns. Status generator will be a standalone script (Python or Deno) that outputs i3bar protocol JSON. Individual status blocks will be modular components that query system state and format output. Testing follows existing pytest patterns (if Python) or Deno.test (if TypeScript). Icons will use either Nerd Fonts (simplest), Font Awesome (via pango markup), or custom SVGs (more flexibility) - decision in Phase 0 research.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
