# Implementation Plan: Enhanced Notification Callback for Claude Code

**Branch**: `090-notification-callback` | **Date**: 2025-11-22 | **Spec**: [spec.md](./spec.md)

## Summary

This feature enhances the Claude Code notification system to provide actionable callbacks that automatically return users to the originating terminal/tmux pane when Claude Code completes a long-running task. The solution adds cross-project navigation support, allowing users to switch projects while Claude Code works, then return instantly via notification action (keyboard shortcut Ctrl+R or click). The implementation extends existing notification hooks (`stop-notification.sh`, `stop-notification-handler.sh`) to capture i3pm project context, integrate with the i3pm project switching system, and handle edge cases (missing windows, killed sessions, multiple Claude Code instances).

**Primary requirement**: User receives desktop notification when Claude Code stops, clicks "Return to Window" action (or presses Ctrl+R), and is automatically returned to the exact terminal window and tmux pane where Claude Code is waiting for input, regardless of current project or workspace context.

**Technical approach** (from research): Enhance Bash notification hooks to capture i3pm project name from environment, pass project context to notification handler, implement project switching logic via `i3pm project switch` command, add error handling for missing windows/sessions, configure custom SwayNC keybindings (Ctrl+R, Escape).

## Technical Context

**Language/Version**: Bash 5.0+ (notification hooks), Python 3.11+ (optional i3pm daemon enhancements for project context tracking)
**Primary Dependencies**: SwayNC 0.10+ (notification daemon with action buttons), Sway 1.8+ (window manager IPC), i3pm (project management system), tmux/sesh (session manager), jq (JSON parsing), Ghostty (terminal emulator)
**Storage**: JSON project files in `~/.config/i3/projects/*.json` (i3pm project definitions), notification handler passes project context via command-line arguments (ephemeral)
**Testing**: Sway test framework (declarative JSON tests for notification workflow), manual testing (trigger Claude Code stop event, verify focus behavior), pytest (if Python daemon extensions needed)
**Target Platform**: Linux with Sway window manager, SwayNC notification daemon, i3pm project system
**Project Type**: Single project (shell scripts for hooks, optional Python daemon extensions)
**Performance Goals**: Notification hook completes in <100ms (non-blocking), focus action completes in <2 seconds (project switch + workspace focus + terminal focus + tmux select)
**Constraints**: Must not block Claude Code execution, must preserve backward compatibility with existing notification hooks, must handle edge cases gracefully (missing windows, killed sessions, multiple instances)
**Scale/Scope**: ~500 lines of Bash script enhancements, ~200 lines of SwayNC configuration, ~300 lines of sway-test framework tests, potential ~200 lines of Python daemon extensions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Assessment

**✅ Principle I - Modular Composition**:
- Notification hook enhancements are modular extensions to existing `scripts/claude-hooks/` scripts
- SwayNC configuration added to home-manager module (`home-modules/ai-assistants/claude-code.nix`)
- No duplication - extends existing hook infrastructure, doesn't replace it

**✅ Principle VI - Declarative Configuration Over Imperative**:
- SwayNC keybindings declared in home-manager configuration
- Notification hooks remain in `scripts/` (standard location for runtime hooks)
- Project context configuration via i3pm JSON project files

**✅ Principle VII - Documentation as Code**:
- Feature spec, plan, and quickstart guide in `specs/090-notification-callback/`
- Inline comments in notification hook scripts explaining project capture logic
- CLAUDE.md updated with notification callback usage instructions

**✅ Principle X - Python Development & Testing Standards**:
- If Python daemon extensions needed, use Python 3.11+ with i3ipc.aio
- pytest for daemon integration tests
- Pydantic models for project context data (if daemon extensions required)

**✅ Principle XII - Forward-Only Development & Legacy Elimination**:
- Enhances existing notification hooks without preserving deprecated patterns
- Replaces any legacy notification mechanisms completely (no dual support)
- Clean implementation without backward compatibility shims

**✅ Principle XIV - Test-Driven Development & Autonomous Testing**:
- sway-test framework tests for notification workflow (launch Claude Code, switch project, trigger stop event, verify focus)
- Manual testing for user experience validation
- Autonomous test execution via `sway-test run tests/090-notification-callback/*.json`

**✅ Principle XV - Sway Test Framework Standards**:
- Declarative JSON test definitions for notification callback workflow
- Partial mode state comparison (focusedWorkspace, windowCount, project context)
- Sway IPC as authoritative source of truth for window/workspace state

**GATE STATUS**: ✅ PASSED - No principle violations. Feature aligns with modular composition, declarative configuration, test-driven development, and forward-only development principles.

### Post-Design Re-check (after Phase 1)

**Design artifacts completed**:
- ✅ research.md - All technical unknowns resolved (project context via environment variables, i3pm project switch command, SwayNC keybindings, error handling strategies)
- ✅ data-model.md - Data structures defined (notification context, action response, environment variables, SwayNC config)
- ✅ quickstart.md - User documentation complete (keyboard shortcuts, use cases, troubleshooting)
- ✅ contracts/README.md - Shell script interfaces documented (command-line args, environment variables, Sway IPC queries, tmux commands)

**Constitution compliance re-check**:

✅ **Principle I - Modular Composition**: Design extends existing hook scripts in `scripts/claude-hooks/`, adds SwayNC configuration to home-manager module. No duplication introduced.

✅ **Principle VI - Declarative Configuration**: SwayNC keybindings declared in home-manager `xdg.configFile`, notification hooks remain in `scripts/` per standard pattern.

✅ **Principle VII - Documentation as Code**: Complete documentation generated (spec, plan, research, data model, quickstart, contracts). Inline script comments planned for project capture logic.

✅ **Principle X - Python Development Standards**: Optional Python daemon extensions (if needed) will follow Python 3.11+, i3ipc.aio, Pydantic patterns per existing i3pm daemon structure.

✅ **Principle XII - Forward-Only Development**: Solution enhances existing notification hooks without legacy compatibility shims. Clean implementation of new project switching capability.

✅ **Principle XIV - Test-Driven Development**: sway-test framework tests planned for same-project focus, notification dismissal. Manual testing documented for cross-project workflow (notification UI automation limitations).

✅ **Principle XV - Sway Test Framework**: Declarative JSON test definitions using partial mode state comparison (focusedWorkspace, windowCount, workspaces). Sway IPC as authoritative state source.

**GATE STATUS**: ✅ PASSED - Design adheres to all relevant constitution principles. No complexity violations. Ready for implementation phase.

## Project Structure

### Documentation (this feature)

```text
specs/090-notification-callback/
├── plan.md              # This file (/speckit.plan command output)
├── spec.md              # Feature specification (completed)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── (none - no API contracts for shell scripts)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Option 1: Single project - SELECTED for this feature

scripts/claude-hooks/
├── stop-notification.sh              # Enhanced: Capture i3pm project name from environment
├── stop-notification-handler.sh      # Enhanced: Project switch logic, improved focus handling
└── bash-history.sh                   # Existing - no changes

home-modules/ai-assistants/
└── claude-code.nix                   # Enhanced: SwayNC keybinding configuration

home-modules/tools/swaync/
└── config.json                       # Enhanced: Custom keybindings (Ctrl+R, Escape)

tests/090-notification-callback/
├── test-same-project-focus.json      # User Story 2: Same-project terminal focus
├── test-cross-project-return.json    # User Story 1: Cross-project return (manual verification needed)
└── test-notification-dismiss.json    # User Story 3: Notification dismissal

# Optional Python daemon extensions (only if needed for project context tracking)
home-modules/desktop/i3-project-event-daemon/
├── notification_context.py           # Project context capture service
└── models/
    └── notification_context.py       # Pydantic model for project metadata
```

**Structure Decision**: Single project structure selected because this feature enhances existing notification hooks (Bash scripts in `scripts/claude-hooks/`) and SwayNC configuration (home-manager module in `home-modules/ai-assistants/claude-code.nix`). No separate frontend/backend or mobile components. Optional Python daemon extensions follow existing i3pm daemon module structure if project context tracking requires daemon-level integration.

## Complexity Tracking

> **No complexity violations** - this feature extends existing notification hook infrastructure following established patterns. No new abstraction layers, no additional platform targets, no deep inheritance hierarchies introduced.
