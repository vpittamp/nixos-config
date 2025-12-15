# Implementation Plan: Improve Notification Progress Indicators

**Branch**: `117-improve-notification-progress-indicators` | **Date**: 2025-12-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/117-improve-notification-progress-indicators/spec.md`

## Summary

Replace Claude Code hook-based detection with universal tmux-based process monitoring that detects any configured AI assistant (Claude Code, Codex CLI) running as foreground process in tmux panes. The system maintains the existing badge file storage, EWW monitoring panel integration, and desktop notification workflow while eliminating application-specific hooks.

## Technical Context

**Language/Version**: Bash (hooks/monitor), Python 3.11+ (daemon/backend), Nix (configuration)
**Primary Dependencies**: tmux, i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools
**Storage**: File-based badges at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
**Testing**: pytest (Python), manual testing, sway-test framework
**Target Platform**: NixOS with Sway compositor, Ghostty terminal, tmux
**Project Type**: Single (NixOS configuration)
**Performance Goals**: <500ms latency from process state change to UI update
**Constraints**: 300ms polling interval (configurable), one badge per Sway window
**Scale/Scope**: Single user, 1-10 concurrent AI assistant sessions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ Pass | New monitor service as separate module |
| III. Test-Before-Apply | ✅ Pass | dry-build required before switch |
| X. Python Development Standards | ✅ Pass | Python 3.11+, pytest, Pydantic |
| XI. i3/Sway IPC Alignment | ✅ Pass | Sway IPC for window ID resolution |
| XII. Forward-Only Development | ✅ Pass | Legacy hooks suppressed, not maintained |
| XIV. Test-Driven Development | ✅ Pass | Tests defined in spec acceptance criteria |

**All gates pass. Proceeding with Phase 0.**

## Project Structure

### Documentation (this feature)

```text
specs/117-improve-notification-progress-indicators/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── badge-state.md   # Badge file contract (existing)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
# Monitor service (NEW)
home-modules/services/
└── tmux-ai-monitor.nix         # Systemd service for tmux process monitoring

# Monitor script (NEW)
scripts/tmux-ai-monitor/
├── monitor.sh                   # Main polling loop
└── notify.sh                    # Notification sender

# Modified files
home-modules/ai-assistants/
├── claude-code.nix              # Suppress UserPromptSubmit/Stop hooks
└── codex.nix                    # Add notify hook (completion only)

home-modules/desktop/i3-project-event-daemon/
├── badge_service.py             # Badge state management (existing)
└── handlers.py                  # Focus-aware dismissal (existing)

home-modules/tools/monitoring-panel/
└── monitoring_data.py           # Badge reading via inotify (existing)

# Configuration
home-modules/services/
└── tmux-ai-monitor-config.nix   # Configurable process list, polling interval

# Tests
tests/117-notification-indicators/
├── test_tmux_monitor.sh         # Monitor detection tests
├── test_badge_lifecycle.json    # sway-test badge lifecycle
└── test_hooks.sh                # Hook suppression verification
```

**Structure Decision**: Single project structure. New tmux monitor is a standalone systemd service that polls tmux and writes badge files. Existing badge infrastructure (badge_service.py, handlers.py, monitoring_data.py) is reused unchanged.

## Complexity Tracking

> No violations - design follows constitution principles.

## Architecture Overview

```
┌─────────────────┐      ┌────────────────────┐      ┌──────────────────┐
│   tmux panes    │      │  tmux-ai-monitor   │      │   Badge Files    │
│  ┌───────────┐  │      │    (systemd)       │      │  (runtime dir)   │
│  │ claude    │  │──────│                    │──────│                  │
│  └───────────┘  │ poll │  - Poll 300ms      │write │ <window_id>.json │
│  ┌───────────┐  │      │  - Detect process  │      │  {state, source} │
│  │ codex     │  │      │  - Map to window   │      │                  │
│  └───────────┘  │      │  - Write badge     │      └────────┬─────────┘
└─────────────────┘      │  - Send notify     │               │
                         └────────────────────┘               │ inotify
                                                              │
┌─────────────────┐      ┌────────────────────┐      ┌────────▼─────────┐
│   Sway Focus    │      │  i3-project-daemon │      │   EWW Panel      │
│    Events       │──────│                    │      │  (monitoring)    │
│                 │      │  - Focus handler   │      │                  │
│                 │      │  - Badge dismiss   │      │  - Read badges   │
│                 │      │  - Orphan cleanup  │      │  - Show spinner  │
└─────────────────┘      └────────────────────┘      └──────────────────┘
```

## Key Design Decisions

1. **Polling vs Event-Driven**: tmux doesn't expose foreground process change events, so polling is necessary. 300ms provides good responsiveness without excessive CPU.

2. **Window ID Resolution**: tmux client PID → process tree → Ghostty PID → Sway window ID (reuse existing logic from prompt-submit-notification.sh).

3. **Badge Granularity**: One badge per Sway window. Multiple panes in one window share a badge (working if ANY active, stopped when ALL exit).

4. **Hook Suppression**: Remove hooks from claude-code.nix via config option, not code deletion. Allows easy rollback.

5. **Codex notify hook**: Codex only has completion event, no start event. Use tmux monitor for start detection, Codex's native `notify` hook for completion (optional optimization).
