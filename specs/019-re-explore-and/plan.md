# Implementation Plan: i3 Project Management System Validation & Enhancement

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/019-re-explore-and/spec.md`

## Summary

This feature enhances the i3 project management system with a unified CLI/TUI interface (`i3pm`) that eliminates manual JSON editing, provides interactive project configuration, layout save/restore, and integrates monitoring into project management workflows. The system uses event-driven architecture with i3's IPC protocol for real-time window tracking and project switching.

**Primary Requirement**: Provide intuitive visual interface for managing i3 projects without JSON editing
**Technical Approach**: Unified Python CLI using Textual framework for TUI, argparse for CLI commands, shared core library for project CRUD, i3ipc for window manager integration, Rich for formatted output

## Technical Context

**Language/Version**: Python 3.11+
**Primary Dependencies**:
- Textual 0.47+ (TUI framework built on Rich)
- Rich 13.7+ (terminal formatting, already used in i3-project-monitor)
- i3ipc 2.2+ (async i3 IPC library, already in use)
- argparse (stdlib, CLI parsing)
- asyncio (stdlib, async patterns)

**Storage**: JSON files in `~/.config/i3/projects/{name}.json`, `~/.config/i3/app-classes.json`
**Testing**: pytest with pytest-asyncio, pytest-textual for TUI testing
**Target Platform**: Linux with i3 window manager v4.20+, NixOS (but portable to other Linux distros)
**Project Type**: Single Python package with CLI/TUI modes
**Performance Goals**:
- TUI response <50ms to keyboard input
- Project switch <200ms for 50 windows
- Config validation <500ms
- Layout save/restore <5s for 10 windows

**Constraints**:
- Must integrate with existing event-driven daemon (Feature 015)
- Must maintain i3 IPC as authoritative source (GET_TREE, GET_MARKS, GET_OUTPUTS)
- Must work over SSH/xrdp (terminal-only, no GUI dependencies)
- Backward compatible output format for shell scripts

**Scale/Scope**:
- ~10-20 projects per user
- ~50 windows per project
- 5 TUI screens (Browser, Editor, Monitor, Layout Manager, Wizard)
- ~30 CLI subcommands
- Integration with existing daemon (i3-project-event-listener systemd service)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle X: Python Development & Testing Standards
**Status**: ✅ PASS

- **Python 3.11+**: Using Python 3.11+ as specified ✓
- **Async/await patterns**: Using i3ipc.aio for i3 communication, asyncio for TUI event loop ✓
- **pytest framework**: Using pytest with pytest-asyncio and pytest-textual ✓
- **Type hints**: All public APIs will have type annotations ✓
- **Validation**: Using Pydantic models or dataclasses with validation ✓

### Principle XI: i3 IPC Alignment & State Authority
**Status**: ✅ PASS

- **i3 IPC as authority**: Layout capture/restore uses GET_TREE for current state ✓
- **Required message types**: Uses GET_WORKSPACES (monitor assignment), GET_OUTPUTS (monitor config), GET_TREE (window hierarchy), GET_MARKS (project tracking) ✓
- **State synchronization**: Daemon maintains in-memory state synced with i3 via events ✓
- **Event-driven**: Subscribes to window, workspace, output, tick events (no polling) ✓

### Principle III: Test-Before-Apply
**Status**: ✅ PASS

- Automated test suite (pytest) prevents regressions ✓
- TUI includes "Test Auto-Launch" dry-run mode ✓
- Config validation before save prevents invalid states ✓

### Principle VI: Declarative Configuration Over Imperative
**Status**: ✅ PASS with justification

- Project configs are declarative JSON ✓
- Layout saves are declarative window snapshots ✓
- **Exception justified**: TUI is interactive tool for *creating* declarative configs, not imperative system modification ✓
  - TUI generates JSON configs that are version-controlled
  - No hidden state outside JSON files
  - All operations reversible via config edits

### Principle VII: Documentation as Code
**Status**: ✅ PASS

- Module header comments required ✓
- Quickstart guide (Phase 1 output) ✓
- API contracts (Phase 1 output) ✓
- UNIFIED_UX_DESIGN.md already created ✓

**Overall**: ✅ **PASS** - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```
specs/019-re-explore-and/
├── spec.md              # Feature specification
├── UNIFIED_UX_DESIGN.md # UX design doc (already created)
├── plan.md              # This file
├── research.md          # Phase 0 output (technology decisions)
├── data-model.md        # Phase 1 output (data structures)
├── quickstart.md        # Phase 1 output (user guide)
├── contracts/           # Phase 1 output (API contracts)
│   ├── cli-interface.md     # CLI subcommand contracts
│   ├── tui-screens.md       # TUI screen navigation contracts
│   ├── daemon-ipc.md        # Daemon JSON-RPC protocol
│   └── config-schema.json   # JSON schema for project configs
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created yet)
```

### Source Code (repository root)

```
home-modules/tools/i3_project_manager/    # New unified package
├── __init__.py
├── __main__.py                           # Entry point: i3pm CLI
│
├── core/                                 # Shared core library
│   ├── __init__.py
│   ├── project.py                        # Project CRUD operations
│   ├── daemon_client.py                  # Daemon IPC (migrated from monitor)
│   ├── i3_client.py                      # i3 IPC queries (GET_TREE, etc.)
│   ├── config.py                         # Config loading/validation
│   ├── layout.py                         # Layout save/restore logic
│   └── models.py                         # Shared dataclasses
│
├── cli/                                  # CLI command mode
│   ├── __init__.py
│   ├── commands.py                       # argparse subcommand handlers
│   ├── formatters.py                     # Rich output formatting
│   └── completions.py                    # Shell completion generation
│
├── tui/                                  # TUI interactive mode
│   ├── __init__.py
│   ├── app.py                            # Textual app main
│   ├── screens/                          # TUI screens
│   │   ├── __init__.py
│   │   ├── browser.py                    # Project browser (default)
│   │   ├── editor.py                     # Project editor
│   │   ├── monitor.py                    # Monitor dashboard (migrate from i3-project-monitor)
│   │   ├── layout_manager.py             # Layout save/restore
│   │   └── wizard.py                     # Project creation wizard
│   └── widgets/                          # Custom Textual widgets
│       ├── __init__.py
│       ├── project_table.py              # Project list table
│       ├── window_list.py                # Window tracking table
│       └── event_stream.py               # Live event display
│
└── validators/                           # Configuration validators
    ├── __init__.py
    ├── project_validator.py              # Project JSON validation
    └── layout_validator.py               # Layout JSON validation

scripts/                                  # Shell wrapper (backward compat)
├── i3pm → ../home-modules/tools/i3_project_manager/__main__.py

tests/i3_project_manager/                 # Test suite
├── conftest.py                           # pytest fixtures
├── test_core/                            # Core library tests
│   ├── test_project.py
│   ├── test_layout.py
│   └── test_config.py
├── test_cli/                             # CLI command tests
│   └── test_commands.py
└── test_tui/                             # TUI screen tests (pytest-textual)
    ├── test_browser.py
    └── test_editor.py

home-modules/tools/
├── i3-project-manager.nix                # NixOS module for i3pm
└── i3_project_monitor/ → migrate to i3_project_manager/tui/screens/monitor.py
```

**Structure Decision**: Single Python package with dual entry points (CLI vs TUI based on args). This approach:
- Shares core library between modes (no duplication)
- Maintains separation of concerns (CLI vs TUI vs core)
- Allows gradual migration of existing monitor tool
- Supports testing each layer independently
- Aligns with existing Python project structure (i3-project-monitor, i3-project-test)

## Complexity Tracking

*No constitution violations requiring justification*

## Phase 0: Technology Research & Decisions

**Status**: Research needed for:
1. Textual framework patterns for multi-screen apps
2. pytest-textual best practices for TUI testing
3. Layout serialization format (i3 layout API vs custom)
4. Shell completion generation (argcomplete vs manual)
5. Migration strategy for existing i3-project-monitor code

**Output**: `research.md` with decisions and rationale

## Phase 1: Design Artifacts

### Data Model (`data-model.md`)

**Entities to define**:
1. **Project** - Enhanced with auto_launch, saved_layouts, workspace_preferences
2. **SavedLayout** - Window snapshots with restore instructions
3. **AutoLaunchApp** - Application launch configuration
4. **WindowSnapshot** - Captured window state for restoration
5. **AppClassification** - Scoped vs global app rules
6. **TUIState** - App state for screen navigation

### API Contracts (`contracts/`)

**Files to create**:
1. `cli-interface.md` - All CLI subcommands with args, output formats
2. `tui-screens.md` - Screen navigation, keyboard shortcuts, widget contracts
3. `daemon-ipc.md` - JSON-RPC methods for daemon communication
4. `config-schema.json` - JSON Schema for project config validation

### Quickstart Guide (`quickstart.md`)

**Sections**:
1. Installation (NixOS module)
2. First Run (interactive TUI walkthrough)
3. Common Tasks (create project, save layout, switch projects)
4. CLI Reference (quick command examples)
5. Troubleshooting

## Phase 2: Task Breakdown

**Deferred to `/speckit.tasks` command**

Tasks will be organized by:
1. Core library implementation (project CRUD, layout logic)
2. CLI command implementation (argparse, Rich output)
3. TUI screens (Textual widgets, navigation)
4. Integration (daemon client, i3 client)
5. Testing (pytest suite for all layers)
6. Documentation (docstrings, guides)

## Migration Strategy

### Existing Code to Migrate

**From i3-project-monitor**:
- `daemon_client.py` → core/daemon_client.py (minor refactor)
- `models.py` → core/models.py (extend with new entities)
- `displays/*.py` → tui/screens/monitor.py (consolidate into single screen with mode switching)

**From i3-project-* CLI scripts**:
- `i3-project-switch` → cli/commands.py (switch subcommand)
- `i3-project-list` → cli/commands.py (list subcommand)
- `i3-project-current` → cli/commands.py (current subcommand)
- Keep scripts as thin wrappers calling `i3pm` for backward compat

### Backward Compatibility

**Approach**: Symlinks for existing commands
```bash
/usr/bin/i3-project-switch → i3pm switch "$@"
/usr/bin/i3-project-list → i3pm list "$@"
/usr/bin/i3-project-current → i3pm current "$@"
/usr/bin/i3-project-monitor → i3pm monitor "$@"
```

**Note**: User said "don't worry about backwards compatibility" so this is optional

## Implementation Phases

### Phase 1: Core Library (Week 1)
- Extract and refactor daemon_client, models
- Implement Project class with CRUD
- Implement LayoutManager for save/restore
- Config validation with JSON Schema
- Unit tests for core

### Phase 2: CLI Commands (Week 2)
- argparse subcommand structure
- All CRUD commands (create, edit, delete, list, show)
- Layout commands (save-layout, restore-layout, export, import)
- Rich formatted output
- Shell completions
- Integration tests

### Phase 3: TUI Foundation (Week 3)
- Textual app skeleton
- Mode detection (CLI vs TUI)
- Project Browser screen
- Basic keyboard navigation
- Screen switching

### Phase 4: TUI Features (Week 4)
- Project Editor screen
- Configuration Wizard (4 steps)
- Layout Manager screen
- Monitor Dashboard (migrate from i3-project-monitor)
- TUI tests with pytest-textual

### Phase 5: Integration & Polish (Week 5)
- Integrate all screens
- Real-time validation
- Error handling and user feedback
- Documentation (quickstart, API contracts)
- End-to-end testing

### Phase 6: Deployment (Week 6)
- NixOS module (i3-project-manager.nix)
- Package as Python application
- Update CLAUDE.md with new commands
- Create demo video/screenshots

## Success Criteria Validation

From spec.md success criteria, implementation must achieve:

**Performance**:
- SC-016: TUI <50ms keyboard response → Use Textual's reactive updates
- SC-017: Config validation <500ms → Async validation with JSON Schema
- SC-018: Layout save/restore <5s → Async i3 IPC queries

**UX**:
- SC-015: Project creation <2 min → 4-step wizard with auto-advance
- SC-019: Rich output in 95% of terminals → Use Rich's terminal detection
- SC-020: 90% feature discovery → Footer shortcuts, tooltips, inline help

## Risk Mitigation

### Risk 1: Textual Learning Curve
**Mitigation**: Start with simple screen (browser), gradually add complexity. Use Textual examples as reference.

### Risk 2: Layout Restore Reliability
**Mitigation**: Phase 1 research on i3 layout save/restore API. Test with multiple window managers.

### Risk 3: TUI Testing Complexity
**Mitigation**: Use pytest-textual's snapshot testing. Focus on critical paths first.

### Risk 4: Migration from Existing Tools
**Mitigation**: Keep existing commands working. Phase migration over multiple releases if needed.

## Next Steps

1. **Run research phase**: Create `research.md` with technology decisions
2. **Run design phase**: Create `data-model.md` and `contracts/`
3. **Generate tasks**: Run `/speckit.tasks` to break down implementation
4. **Implement core**: Start with core library (Week 1)
5. **Iterate**: Build CLI, then TUI, then integrate

---

**Plan Status**: ✅ Ready for Phase 0 (Research)
**Constitution Check**: ✅ PASS
**Next Command**: Phase 0 research will be executed next
