# Implementation Plan: i3 Project System Testing & Debugging Framework

**Branch**: `018-create-a-new` | **Date**: 2025-10-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/018-create-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the existing i3-project-monitor tool (Feature 017) to serve as a comprehensive testing and debugging framework for the i3 project management system. The framework enables manual interactive testing with live monitoring, automated state validation, diagnostic reporting, and CI/CD integration. A critical requirement is adding monitor/display tracking to validate workspace-to-output assignments using i3's native IPC API (GET_OUTPUTS, GET_WORKSPACES). The system uses tmux for multi-pane monitoring during test execution and must align with i3wm's native IPC message types to ensure consistency with i3's authoritative state.

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon and monitor tool use Python 3.11)
**Primary Dependencies**:
- i3ipc.aio (async i3 IPC library - already used in Feature 015 daemon)
- rich (terminal UI library - already used in Feature 017 monitor)
- pytest (for test framework)
- tmux (session management)
- xrandr (display configuration testing)

**Storage**:
- N/A for test framework (reads daemon state via JSON-RPC IPC)
- Diagnostic reports output to JSON files
- Test scenarios defined as Python code or JSON configuration

**Testing**:
- pytest for test framework implementation (unit tests)
- Custom test runner for i3 project management workflow tests
- Test framework validates via i3 IPC queries (GET_OUTPUTS, GET_WORKSPACES, GET_TREE, GET_MARKS)

**Target Platform**:
- Linux with i3wm window manager
- Requires running i3 IPC socket
- Requires tmux for multi-pane monitoring
- Primary deployment: Hetzner i3 development workstation

**Project Type**: Single project (enhancement to existing i3-project-monitor tool)

**Performance Goals**:
- State validation within 2 seconds
- Monitor configuration change detection within 1 second
- Diagnostic capture in under 3 seconds
- Test suite execution under 10 seconds for full workflow

**Constraints**:
- MUST use i3's native IPC API (not custom daemon state) as source of truth
- MUST support headless operation for CI/CD
- MUST operate in tmux for test isolation
- MUST not interfere with active user i3 sessions (test-* project namespace)

**Scale/Scope**:
- ~10-20 test scenarios covering project management workflows
- Event buffer validation (500 events)
- Multi-monitor support (3+ outputs)
- Test library extensible for future scenarios

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition
**Status**: ✅ PASS

- Test framework will be modular Python package in `home-modules/tools/i3-project-test/`
- Monitor tool enhancements extend existing `home-modules/tools/i3_project_monitor/` modules
- No duplication: builds on Feature 015 (daemon) and Feature 017 (monitor) foundations
- Each display mode (live, events, history, tree, diagnose) remains in separate module

### Principle III: Test-Before-Apply
**Status**: ✅ PASS

- Test framework itself will have unit tests via pytest
- Changes to monitor tool will be tested with existing test script
- NixOS rebuild dry-build required before deployment

### Principle IV: Override Priority Discipline
**Status**: ✅ PASS (N/A)

- No NixOS module options being added (Python application enhancement only)
- Home-manager module updates use existing patterns from Feature 017

### Principle V: Platform Flexibility Through Conditional Features
**Status**: ✅ PASS

- Test framework detects i3wm availability before running i3-specific tests
- Headless mode (FR-003) enables CI/CD usage without terminal UI
- xrandr integration conditional on X11 availability

### Principle VI: Declarative Configuration Over Imperative
**Status**: ✅ PASS

- Test scenarios declaratively defined in Python code/JSON
- No manual setup scripts required
- Tmux session management via Python subprocess calls (standard testing pattern)
- Test framework package declared in home-manager module

### Principle VII: Documentation as Code
**Status**: ✅ PASS

- quickstart.md will document test framework usage
- research.md will capture design decisions
- Python modules will include docstrings
- Integration with existing i3 project documentation

### Principle VIII: Remote Desktop & Multi-Session Standards
**Status**: ✅ PASS

- Test framework compatible with X11-based i3 sessions
- Validates workspace-to-output assignments critical for multi-monitor RDP setup
- Does not interfere with existing xrdp/multi-session functionality

### Principle IX: Tiling Window Manager & Productivity Standards
**Status**: ✅ PASS

- Directly supports i3wm testing and validation
- Uses i3's native IPC API (GET_OUTPUTS, GET_WORKSPACES, GET_TREE, GET_MARKS)
- Validates i3-specific features (window marking, workspace assignments, project switching)
- Ensures i3 integration remains robust and reliable

### Platform Support Standards
**Status**: ✅ PASS

- Primary target: Hetzner i3 workstation (reference implementation)
- Framework will work on any Linux system with i3wm
- CI/CD support enables testing in automated environments

### Security & Authentication Standards
**Status**: ✅ PASS (N/A)

- Test framework does not handle authentication
- Uses existing daemon JSON-RPC IPC (no new security surface)

### Package Management Standards
**Status**: ✅ PASS

- Test framework packages will be in home-manager user packages
- Development profile appropriate for test tooling
- No system-wide package changes required

### Home-Manager Standards
**Status**: ✅ PASS

- New test framework module follows established pattern from Feature 017
- Configuration via home.file for test scenario definitions
- Proper module structure with {config, lib, pkgs, ...} inputs

**OVERALL GATE STATUS**: ✅ PASS - All applicable principles satisfied, proceed to Phase 0

---

**Post-Design Re-evaluation** (2025-10-20 after Phase 1):

All constitution principles remain satisfied after detailed design:
- ✅ Modular structure confirmed in project layout (data-model.md, source tree)
- ✅ Declarative test scenarios using Python classes (research.md)
- ✅ i3 IPC alignment verified (contracts/jsonrpc-api.md)
- ✅ Proper separation of concerns (validators/, scenarios/, assertions/, reporters/)
- ✅ No new NixOS options or breaking changes
- ✅ Documentation complete (quickstart.md, research.md, data-model.md, contracts/)

**Final Gate Status**: ✅ PASS - Ready for Phase 2 (tasks generation)

## Project Structure

### Documentation (this feature)

```
specs/018-create-a-new/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── jsonrpc-api.md  # Extensions to daemon JSON-RPC API
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: Single project enhancement to existing i3-project-monitor tool with new test framework module.

```
home-modules/tools/
├── i3_project_monitor/              # Existing monitor tool (Feature 017)
│   ├── __init__.py
│   ├── __main__.py
│   ├── daemon_client.py
│   ├── models.py
│   ├── displays/
│   │   ├── __init__.py
│   │   ├── base.py
│   │   ├── events.py
│   │   ├── history.py
│   │   ├── live.py                  # ENHANCE: Add output/workspace tracking
│   │   ├── tree.py
│   │   └── diagnose.py              # NEW: Diagnostic capture mode
│   └── validators/                   # NEW: State validation utilities
│       ├── __init__.py
│       ├── workspace_validator.py    # Validate workspace-to-output assignments
│       └── output_validator.py       # Validate monitor configuration
│
├── i3-project-test/                  # NEW: Test framework module
│   ├── __init__.py
│   ├── __main__.py                   # CLI entry point: i3-project-test
│   ├── test_runner.py                # Test execution engine
│   ├── tmux_manager.py               # Tmux session management
│   ├── scenarios/                    # Test scenario library
│   │   ├── __init__.py
│   │   ├── base_scenario.py          # Base test scenario class
│   │   ├── project_lifecycle.py      # Create/delete/switch tests
│   │   ├── window_management.py      # Window marking and visibility tests
│   │   ├── monitor_configuration.py  # NEW: Monitor/output validation tests
│   │   └── event_stream.py           # Event buffer validation tests
│   ├── assertions/                   # Test assertion utilities
│   │   ├── __init__.py
│   │   ├── state_assertions.py       # Daemon state validation
│   │   ├── i3_assertions.py          # i3 IPC state validation
│   │   └── output_assertions.py      # NEW: Monitor/workspace assertions
│   └── reporters/                    # Test result reporting
│       ├── __init__.py
│       ├── terminal_reporter.py      # Human-readable terminal output
│       └── json_reporter.py          # Machine-readable JSON/TAP output
│
└── i3-project-test.nix               # NEW: Home-manager module for test framework

home-modules/desktop/i3-project-event-daemon/  # Existing daemon (Feature 015)
├── daemon.py
├── handlers.py
├── ipc_server.py                     # ENHANCE: Add new JSON-RPC methods
├── models.py
└── event_buffer.py

scripts/
├── i3-project-monitor                # Existing monitor wrapper script
└── i3-project-test                   # NEW: Test framework wrapper script
```

**Key Integration Points**:
1. Monitor tool displays (live.py) enhanced to show GET_OUTPUTS and GET_WORKSPACES data
2. New diagnose.py display mode captures comprehensive diagnostic snapshots
3. Test framework uses daemon_client.py to query daemon state
4. Test framework directly uses i3ipc.aio to query i3's authoritative state
5. Validators compare daemon state against i3 IPC responses

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

No violations - all Constitution principles are satisfied.
