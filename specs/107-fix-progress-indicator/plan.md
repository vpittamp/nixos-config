# Implementation Plan: Fix Progress Indicator Focus State and Event Efficiency

**Branch**: `107-fix-progress-indicator` | **Date**: 2025-12-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/107-fix-progress-indicator/spec.md`

## Summary

Enhance the Claude Code progress indicator badge in the monitoring panel to:
1. Display visual distinction based on window focus state (focused vs. unfocused)
2. Replace file-based polling with event-driven IPC signaling for lower latency and CPU usage
3. Optimize spinner animation updates to avoid full data refresh overhead

**Technical Approach**: Migrate from file-based badge state (`$XDG_RUNTIME_DIR/i3pm-badges/*.json`) to daemon IPC-based state management, leverage existing Sway IPC focus events for focus state tracking, and decouple spinner frame updates from full monitoring data refresh.

## Technical Context

**Language/Version**: Python 3.11+ (daemon/backend), Bash 5.0+ (hook scripts)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), asyncio, Pydantic (data models), Eww 0.4+ (UI)
**Storage**: In-memory daemon state (BadgeState in badge_service.py), file-based fallback
**Testing**: pytest with pytest-asyncio for daemon tests, manual sway-test for UI validation
**Target Platform**: NixOS with Sway Wayland compositor
**Project Type**: Single - extending existing i3pm daemon and monitoring panel
**Performance Goals**: <100ms badge appearance latency, <2% CPU during animation
**Constraints**: 3-second hook timeout, maintain backward compatibility with file-based fallback
**Scale/Scope**: Single-user desktop, <20 concurrent badged windows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| X. Python Development Standards | ✅ PASS | Uses Python 3.11+, async/await, Pydantic models |
| XI. i3 IPC Alignment & State Authority | ✅ PASS | Focus state from Sway IPC events, not custom tracking |
| XII. Forward-Only Development | ✅ PASS | Replaces polling with IPC; file fallback for reliability |
| XIV. Test-Driven Development | ✅ PASS | Will add tests for badge IPC and focus state |

**No violations requiring justification.**

## Project Structure

### Documentation (this feature)

```text
specs/107-fix-progress-indicator/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
home-modules/
├── ai-assistants/
│   └── claude-code.nix                    # Claude Code hooks configuration
├── desktop/
│   ├── i3-project-event-daemon/
│   │   ├── badge_service.py               # Badge state manager (existing, to extend)
│   │   ├── models/
│   │   │   └── badge.py                   # Badge Pydantic models (new)
│   │   └── services/
│   │       └── badge_ipc_handler.py       # Badge IPC command handler (new)
│   └── eww-monitoring-panel.nix           # Eww widget configuration (modify)
├── tools/
│   └── i3_project_manager/
│       └── cli/
│           └── monitoring_data.py         # Badge reading logic (modify)
scripts/
└── claude-hooks/
    ├── prompt-submit-notification.sh      # Hook script (modify for IPC)
    └── stop-notification.sh               # Hook script (modify for IPC)

tests/107-fix-progress-indicator/
├── unit/
│   └── test_badge_focus.py               # Focus state tests
└── integration/
    └── test_badge_ipc.py                 # IPC integration tests
```

**Structure Decision**: Single project extending existing daemon infrastructure. No new directories needed beyond test structure.

## Complexity Tracking

> **No violations to justify - implementation follows existing patterns.**

---

## Phase 0 Research Items

### R1: Event-Driven Badge Signaling via Unix Socket IPC

**Question**: How should hook scripts communicate with the daemon for badge creation?

**Research Focus**:
- Existing daemon IPC patterns (Unix socket JSON-RPC)
- Hook script execution context (environment, PATH, socket availability)
- Timeout constraints (3-second hook timeout)

### R2: Focus State Integration with Badge Display

**Question**: How to propagate window focus state to badge rendering in Eww?

**Research Focus**:
- Current `monitoring_data.py` window data structure
- Eww widget access to window focus state
- Badge CSS class differentiation patterns

### R3: Spinner Animation Decoupling

**Question**: How to update spinner frame without full data refresh?

**Research Focus**:
- Eww `defvar` vs `deflisten` for spinner updates
- Separate spinner variable approach
- Animation performance implications

---

## Phase 1 Deliverables

After research.md is complete:
- **data-model.md**: Badge IPC commands, focus state in WindowBadge
- **contracts/**: Badge IPC command schema (JSON-RPC style)
- **quickstart.md**: Testing and verification instructions
