# Implementation Plan: Improve Notification Progress Indicators

**Branch**: `117-improve-notification-progress-indicators` | **Date**: 2025-12-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/117-improve-notification-progress-indicators/spec.md`

## Summary

Consolidate and simplify the Claude Code notification system by replacing dual notification channels with a single unified flow, implementing focus-aware badge dismissal, and cleaning up stale badges. Per the spec's clean-slate approach, legacy code paths (file+IPC dual updates, fallback window detection, polling+inotify hybrid) will be completely replaced with optimal implementations.

## Technical Context

**Language/Version**: Bash (hooks), Python 3.11+ (daemon/backend), Nix (configuration)
**Primary Dependencies**: i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools
**Storage**: File-based badges at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
**Testing**: pytest (Python), sway-test framework (Deno/TypeScript)
**Target Platform**: NixOS with Sway/Wayland compositor
**Project Type**: Single project (NixOS configuration with embedded services)
**Performance Goals**: Badge state changes visible within 600ms, focus dismissal within 500ms
**Constraints**: Must work in tmux/ghostty terminal hierarchy, multi-session support
**Scale/Scope**: Single user, 1-5 concurrent Claude Code sessions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| XII. Forward-Only Development | ✅ PASS | Spec explicitly states no backwards compatibility, replace legacy |
| X. Python Development Standards | ✅ PASS | Using Python 3.11+, Pydantic, async patterns |
| XI. i3/Sway IPC Alignment | ✅ PASS | Sway IPC is source of truth for window state |
| XIV. Test-Driven Development | ✅ PASS | Will create sway-test cases for badge lifecycle |
| XV. Sway Test Framework | ✅ PASS | Declarative JSON tests for window/badge validation |
| VI. Declarative Configuration | ✅ PASS | Config via Nix modules, not imperative scripts |

**Constitution violations requiring justification**: None

## Project Structure

### Documentation (this feature)

```text
specs/117-improve-notification-progress-indicators/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── badge-state.md   # Badge state contract
├── checklists/
│   └── requirements.md  # Spec validation checklist
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
# Affected files in this feature:

scripts/claude-hooks/
├── prompt-submit-notification.sh    # MODIFY: Simplify to single badge mechanism
├── stop-notification.sh             # MODIFY: Simplify notification, integrate with badge
├── swaync-action-callback.sh        # MODIFY: Focus-aware cleanup
└── badge-ipc-client.sh              # REMOVE: Consolidating to file-only approach

home-modules/
├── ai-assistants/
│   └── claude-code.nix              # MODIFY: Update hook references
├── desktop/
│   ├── eww-monitoring-panel.nix     # MODIFY: Add focus-aware badge dismissal
│   └── i3-project-event-daemon/
│       ├── badge_service.py         # MODIFY: Add TTL cleanup, focus tracking
│       ├── handlers.py              # MODIFY: Window focus event handling
│       └── monitoring_data.py       # MODIFY: Integrate badge cleanup

tests/
└── 117-notification-indicators/     # NEW: Test suite for this feature
    ├── test_badge_lifecycle.json    # sway-test: badge create/update/cleanup
    └── test_focus_dismissal.json    # sway-test: focus-aware dismissal
```

**Structure Decision**: This feature modifies existing NixOS configuration modules and scripts. No new directories needed except for test suite.

## Complexity Tracking

No constitution violations requiring justification.

## Design Decisions

### D1: Single Badge Storage Mechanism

**Decision**: Use file-based badges only, remove IPC dual-write

**Rationale**:
- Current system writes to both files AND sends IPC - redundant
- Files are already source of truth (monitoring_data.py reads files)
- IPC adds latency and complexity without benefit
- Per Constitution XII: remove redundant code paths

**What gets removed**:
- IPC calls in `prompt-submit-notification.sh`
- IPC calls in `stop-notification.sh`
- `badge-ipc-client.sh` script entirely
- IPC badge handlers in daemon

### D2: Single Window ID Detection Method

**Decision**: Use tmux client PID → process tree → sway query (remove fallback to focused window)

**Rationale**:
- Current code has fallback to "focused window" which is unreliable
- The tmux → process tree method is correct and reliable
- Fallback masks bugs - better to fail clearly than silently use wrong window
- Per Constitution XII: single optimal path

**What gets removed**:
- Fallback to `focused==true` in window detection
- Error silencing that masks detection failures

### D3: Focus-Aware Badge Dismissal

**Decision**: Implement focus event handling in daemon to clear badges

**Rationale**:
- Currently badges only clear via notification action click
- Users expect badge to clear when they focus the window
- Daemon already receives window focus events
- Need minimum age check to prevent immediate dismissal on badge creation

**Implementation**:
- Add window focus handler in `handlers.py`
- Check if focused window has badge with age > 1 second
- Delete badge file on focus
- EWW picks up change via inotify

### D4: Simplified Notification Content

**Decision**: Notification shows only "Ready" + project name

**Rationale**:
- Current notification is verbose (tmux session:window info)
- Users need to identify which project, not terminal details
- Project name is sufficient context for switching

**New format**:
```
Title: "Claude Code Ready"
Body: "📁 feature-123" (or "Awaiting input" if no project)
Action: "Return to Window"
```

### D5: Stale Badge Cleanup

**Decision**: Validate badges against Sway window tree on each monitoring refresh

**Rationale**:
- Current system has no cleanup for orphaned badges
- Windows can close without triggering cleanup hooks
- monitoring_data.py already queries Sway tree
- Add window existence check and remove orphaned badges

**Implementation**:
- In monitoring_data.py refresh cycle
- Get set of valid window IDs from Sway tree
- Remove badge files for non-existent windows
- Add 5-minute TTL as backup cleanup
