# Implementation Plan: Unified Notification System with Eww Integration

**Branch**: `110-improve-notifications-system` | **Date**: 2025-12-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/110-improve-notifications-system/spec.md`

## Summary

This feature bridges SwayNC (notification daemon) with the Eww top bar widget system to provide real-time unread notification badge display. Following the established pattern where backend systems provide data and Eww renders the display layer (proven in Feature 085), a Python streaming backend will subscribe to SwayNC events and emit JSON to Eww via deflisten. The top bar will display a notification count badge with Catppuccin Mocha theming, pulsing glow animation for unread notifications, and visual state indicators for DND and control center visibility.

## Technical Context

**Language/Version**: Python 3.11+ (streaming backend, matching Constitution Principle X), Yuck/GTK CSS (Eww widgets)
**Primary Dependencies**: SwayNC (swaync-client --subscribe), Eww 0.4+ (deflisten), Python subprocess for event streaming
**Storage**: N/A (stateless - SwayNC is the source of truth)
**Testing**: Manual verification via notify-send, visual inspection; automated tests via sway-test framework (Constitution Principle XV)
**Target Platform**: NixOS with Sway Wayland compositor (Hetzner and M1)
**Project Type**: Single project (Eww widget + Python streaming script)
**Performance Goals**: <100ms update latency (event-driven via deflisten)
**Constraints**: Event-driven (no polling), graceful degradation on daemon failure
**Scale/Scope**: Single user desktop environment, typical notification volume 0-50/session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Widget extends existing eww-top-bar module |
| II. Reference Implementation | PASS | Hetzner Sway is reference, M1 also supported |
| III. Test-Before-Apply | PASS | dry-build required before switch |
| VI. Declarative Configuration | PASS | All config via Nix, no imperative scripts |
| X. Python Development Standards | PASS | Python 3.11+, streaming pattern matches Feature 085 |
| XI. Sway IPC Alignment | N/A | Uses SwayNC IPC, not Sway IPC directly |
| XII. Forward-Only Development | PASS | No legacy compatibility concerns |
| XIV. Test-Driven Development | PASS | Tests via notify-send + visual verification |
| XV. Sway Test Framework | PARTIAL | Can use sway-test for panel visibility tests |

**Gate Status**: PASS - No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/110-improve-notifications-system/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (IPC event schema)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/
├── desktop/
│   ├── eww-top-bar/
│   │   ├── eww.yuck.nix          # Add notification widget + deflisten
│   │   ├── eww.scss.nix          # Add notification badge CSS
│   │   └── scripts/
│   │       └── notification-monitor.py  # NEW: Streaming backend
│   └── swaync.nix                # Already configured (no changes expected)

tests/110-improve-notifications-system/
├── test_notification_badge.json   # Sway-test: badge visibility
├── test_notification_toggle.json  # Sway-test: panel toggle
└── test_notification_states.json  # Sway-test: visual states
```

**Structure Decision**: Extends existing `eww-top-bar` module with new notification widget and streaming script. Follows established pattern from Feature 085 (monitoring panel deflisten).

## Complexity Tracking

No violations requiring justification - implementation follows established patterns.
