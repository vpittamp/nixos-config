# Implementation Plan: M1 Hybrid Multi-Monitor Management

**Branch**: `084-monitor-management-solution` | **Date**: 2025-11-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/084-monitor-management-solution/spec.md`

## Summary

Enable M1 MacBook Pro users to extend their workspace via dynamically created VNC displays alongside the physical Retina display. The system uses `swaymsg create_output` to create virtual HEADLESS outputs at runtime (not startup), with WayVNC providing remote access on ports 5900-5901. Profile switching via `Mod+Shift+M` allows users to toggle between local-only, local+1vnc, and local+2vnc configurations. Workspace distribution and window migration are handled by the existing i3pm daemon infrastructure from Feature 083.

## Technical Context

**Language/Version**: Python 3.11+ (daemon extensions), Nix (system/home-manager config), Bash (profile scripts)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic (data models), WayVNC (VNC server), asyncio (event handling), Eww (top bar)
**Storage**: JSON files (`~/.config/sway/monitor-profiles/*.json`, `output-states.json`, `monitor-profile.current`)
**Testing**: sway-test framework (declarative JSON tests), pytest (daemon unit tests)
**Target Platform**: NixOS on Apple Silicon M1 (Asahi Linux), requires `--impure` flag
**Project Type**: NixOS configuration extension (system + home-manager modules)
**Performance Goals**: Profile switch <2s, VNC connection <5s, top bar update <100ms
**Constraints**: GPU must remain available for physical display, Tailscale-only VNC access
**Scale/Scope**: 3 monitor profiles, 2 VNC displays max, workspaces 1-100+

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Gate Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Extends existing sway.nix, daemon modules - no duplication |
| II. Reference Implementation | ✅ PASS | Adapts Hetzner patterns for M1 hybrid mode |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build --flake .#m1 --impure` |
| V. Platform Flexibility | ✅ PASS | Conditional logic for M1 vs Hetzner (isHeadless detection) |
| VI. Declarative Config | ✅ PASS | All config via Nix modules, no imperative scripts |
| VIII. Remote Desktop | ✅ PASS | WayVNC + Tailscale provides secure remote access |
| X. Python Standards | ✅ PASS | Async/await, Pydantic models, existing daemon patterns |
| XI. i3 IPC Alignment | ✅ PASS | Sway IPC as authority for output/workspace state |
| XII. Forward-Only | ✅ PASS | No legacy compatibility needed, clean M1 implementation |
| XIV. Test-Driven | ✅ PASS | sway-test framework for profile switching validation |
| XV. Sway Test Framework | ✅ PASS | Declarative JSON tests for profile/workspace verification |

### Key Compliance Notes

1. **Modular Reuse**: Feature 083's MonitorProfileService, EwwPublisher, and profile switching logic will be extended, not duplicated
2. **Hybrid Mode**: New `isHybridMode` flag distinguishes M1 (physical + virtual) from Hetzner (pure headless)
3. **Dynamic Output Creation**: Uses `swaymsg create_output` instead of `WLR_HEADLESS_OUTPUTS` env var

## Project Structure

### Documentation (this feature)

```text
specs/084-monitor-management-solution/
├── plan.md              # This file
├── research.md          # Phase 0: Dynamic output creation patterns
├── data-model.md        # Phase 1: Profile, output, workspace models
├── quickstart.md        # Phase 1: User guide for M1 VNC setup
├── contracts/           # Phase 1: IPC message schemas
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
# NixOS configuration structure for Feature 084

configurations/
└── m1.nix                          # Enable wayvnc, firewall rules, hybrid mode flag

home-modules/
├── m1.nix                          # Home-manager imports for M1-specific services
└── desktop/
    ├── sway.nix                    # Extended with hybrid mode output/profile logic
    ├── sway-keybindings.nix        # Add Mod+Shift+M profile cycling keybinding
    ├── eww-top-bar.nix             # Update indicators for L/V1/V2 (vs H1/H2/H3)
    ├── scripts/
    │   ├── set-monitor-profile.sh  # Extend for hybrid mode (create_output)
    │   └── active-monitors.sh      # Extend for dynamic output management
    └── i3-project-event-daemon/
        ├── daemon.py               # Initialize hybrid mode services
        ├── monitor_profile_service.py  # Handle create_output for M1
        ├── eww_publisher.py        # Publish L/V1/V2 indicators
        └── models/
            └── monitor_profile.py  # HybridOutputState model

modules/
└── desktop/
    └── wayvnc.nix                  # Already exists, ensure M1 compatibility

tests/
└── 084-monitor-management/
    ├── test_profile_switch.json    # sway-test: Profile switching
    ├── test_vnc_activation.json    # sway-test: VNC output creation
    └── test_workspace_distribution.json  # sway-test: Workspace assignment
```

**Structure Decision**: Extends existing NixOS configuration modules following the established patterns from Features 048 and 083. No new directories created except test cases. All changes integrate into the existing modular architecture.

## Complexity Tracking

No complexity violations identified. The implementation:
- Reuses existing Profile/EwwPublisher infrastructure (Principle I)
- Extends rather than duplicates module logic (Principle XII)
- Follows established patterns from Feature 083 reference implementation
