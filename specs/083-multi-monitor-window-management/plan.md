# Implementation Plan: Multi-Monitor Window Management Enhancements

**Branch**: `083-multi-monitor-window-management` | **Date**: 2025-11-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/083-multi-monitor-window-management/spec.md`

## Summary

Enhance the multi-monitor window management system to use event-driven architecture for real-time top bar updates, atomic profile switching to prevent race conditions, and daemon-owned state management to eliminate duplicate logic. Primary goals: reduce top bar update latency from 2000ms to 100ms, prevent workspace reassignment duplicates, and consolidate state management in i3-project-event-daemon.

## Technical Context

**Language/Version**: Python 3.11+ (daemon), Bash (profile scripts), Yuck/GTK (Eww widgets)
**Primary Dependencies**: i3ipc.aio (Sway IPC), asyncio (event handling), Eww (top bar), systemd (service management)
**Storage**: JSON files (~/.config/sway/output-states.json, monitor-profile.current, monitor-profiles/*.json)
**Testing**: pytest-asyncio (daemon), sway-test framework (end-to-end)
**Target Platform**: NixOS on Hetzner Cloud with headless Wayland (HEADLESS-1/2/3)
**Project Type**: single (daemon extension + widget update)
**Performance Goals**: <100ms top bar update latency, <500ms profile switch completion
**Constraints**: Zero polling for monitor state, atomic state transitions, full revert on failure
**Scale/Scope**: 3 headless outputs, 70 workspaces, single user

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ Pass | Extends existing i3-project-event-daemon module |
| II. Reference Implementation | ✅ Pass | Enhances Hetzner Sway reference configuration |
| III. Test-Before-Apply | ✅ Pass | Will use dry-build before applying changes |
| X. Python Development Standards | ✅ Pass | Python 3.11+, async/await, pytest-asyncio |
| XI. i3 IPC Alignment | ✅ Pass | Sway IPC events as authoritative source |
| XII. Forward-Only Development | ✅ Pass | Replacing polling with events, no backwards compat |
| XIII. Deno CLI Standards | N/A | No new CLI tools in this feature |
| XIV. Test-Driven Development | ✅ Pass | Structured events enable test verification |
| XV. Sway Test Framework | ✅ Pass | Will use for profile switch validation |

**Gate Result**: PASS - No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/083-multi-monitor-window-management/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── daemon.py                    # Main daemon (extend with profile events)
├── monitor_profile_service.py   # NEW: Profile state management
├── output_event_handler.py      # MODIFY: Event-driven output state
└── eww_publisher.py             # NEW: Real-time Eww updates

home-modules/desktop/scripts/
├── set-monitor-profile.sh       # MODIFY: Remove state management, add daemon notification
├── active-monitors.sh           # Unchanged (Sway IPC only)
└── monitor-profile-menu.sh      # Unchanged

home-modules/desktop/eww-top-bar/
├── eww.yuck                     # MODIFY: Add profile name widget, event-driven updates
└── eww.scss                     # MODIFY: Profile name styling

tests/083-multi-monitor-window-management/
├── test_monitor_profile_service.py
├── test_output_event_handler.py
└── test_eww_publisher.py
```

**Structure Decision**: Extends existing i3-project-event-daemon with new services for monitor profile management. Eww widget updated for real-time updates via daemon publishing. Shell script simplified to remove state management logic.

## Complexity Tracking

> No violations requiring justification - design uses existing patterns and extends current architecture.
