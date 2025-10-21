# Implementation Plan: Dynamic Window Management System

**Branch**: `021-lets-create-a` | **Date**: 2025-10-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/021-lets-create-a/spec.md`

## Summary

Replace static home-manager window classification rules with a dynamic Python-based pattern matching system integrated into the existing i3pm event-driven daemon. This eliminates the NixOS rebuild requirement for window rule changes while maintaining full backward compatibility with existing Project and AppClassification schemas. The system uses i3 IPC event subscriptions for real-time window classification, workspace assignment, and multi-monitor support.

**Core Value**: Users can modify window rules in `~/.config/i3/window-rules.json` and see changes applied to new windows within 1 second, without any system rebuild.

## Technical Context

**Language/Version**: Python 3.11+ (matches existing i3-project daemon)
**Primary Dependencies**:
- i3ipc.aio (async i3 IPC communication)
- existing i3pm models (Project, AppClassification, PatternRule)
- asyncio (event loop integration with existing daemon)
- watchdog or inotify (config file change detection)
- Rich (terminal UI consistency)

**Storage**: JSON files in `~/.config/i3/`
- Existing: `projects/{name}.json` (Project model)
- Existing: `app-classes.json` (AppClassification model - enhanced)
- NEW: `window-rules.json` (WindowRule list with patterns)
- NEW: `workspace-config.json` (WorkspaceConfig list with metadata)

**Testing**: pytest with pytest-asyncio (async test support)
- Unit tests: PatternMatcher, rule validation, config parsing
- Integration tests: i3 IPC mock, daemon client mock
- Scenario tests: Window lifecycle, multi-monitor, project switching
- Target: >80% coverage, <10 second execution

**Target Platform**: NixOS with i3 window manager (X11)
- Hetzner reference platform (primary test target)
- Multi-monitor support (1-3 monitors)
- Event-driven daemon architecture (systemd user service)

**Project Type**: Single project - Python daemon extension + CLI tools
- Extends existing i3-project-event-listener daemon
- Reuses existing i3pm CLI commands
- Integrated with existing TUI (monitor, browser screens)

**Performance Goals**:
- Window classification: <1ms (cached), <10ms (uncached)
- Config reload: <100ms for 100+ rules
- Event processing latency: <50ms from i3 event to rule application
- Monitor reassignment: <500ms total for all workspaces
- Memory footprint: <20MB additional beyond base daemon

**Constraints**:
- Zero breaking changes to existing Project JSON files
- Must reuse existing PatternRule dataclass (no duplication)
- AppClassification.class_patterns field must be utilized (currently ignored)
- Project.scoped_classes takes precedence (priority 1000)
- i3 IPC is authoritative source of truth for all state
- Event-driven (subscriptions, not polling)

**Scale/Scope**:
- Support 100+ window rules with <1ms classification time
- Support 50+ active windows with <20MB daemon memory
- Support 3 concurrent monitors with workspace redistribution
- Support 10+ projects with per-project classification overrides

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Required Principles (from Constitution v1.3.0)

#### ✅ I. Modular Composition
- **Compliance**: Extends existing daemon module architecture
- **Justification**: Reuses `home-modules/desktop/i3-project-event-daemon/` structure
- **Action**: Add new modules (window_rules.py, workspace_manager.py) alongside existing handlers

#### ✅ III. Test-Before-Apply
- **Compliance**: Config changes loaded dynamically, no rebuild required
- **Justification**: JSON file changes detected via inotify, daemon reloads without restart
- **Action**: Implement config validation on load with error fallback

#### ✅ VI. Declarative Configuration Over Imperative
- **Compliance**: Window rules declared in JSON files, not runtime commands
- **Justification**: `window-rules.json` is declarative config, daemon reads and applies
- **Action**: Generate example configs via home-manager for initial setup

#### ✅ X. Python Development & Testing Standards
- **Compliance**: Python 3.11+, async/await, pytest, type hints, dataclasses
- **Status**: Fully aligned with constitution requirements
- **Evidence**: Existing daemon uses i3ipc.aio, Feature 018 established patterns
- **Action**: Follow established patterns from existing daemon modules

#### ✅ XI. i3 IPC Alignment & State Authority
- **Compliance**: Uses i3 IPC as authoritative source for all state queries
- **Status**: Fully aligned with constitution requirements
- **Evidence**:
  - Workspace assignment: GET_WORKSPACES for current assignments
  - Monitor config: GET_OUTPUTS for output information
  - Window properties: GET_TREE for window hierarchy and marks
  - Event subscriptions: SUBSCRIBE for window, output, workspace events
- **Action**: Never cache i3 state, always query IPC when needed

#### ✅ IX. Tiling Window Manager & Productivity Standards
- **Impact**: Removes static i3 config rules from home-manager
- **Justification**: Dynamic rules more flexible than static `assign` directives
- **Action**: Migrate existing i3.nix rules to window-rules.json during implementation
- **Benefit**: Users can iterate on workspace assignments without rebuild

### Schema Compatibility Gates

#### ✅ Existing Model Preservation
- **Project model** (core/models.py lines 69-277): No changes required
  - Integration via scoped_classes (priority 1000)
  - Integration via workspace_preferences overrides
- **AppClassification model** (core/models.py lines 448-537): Minor enhancement
  - class_patterns field currently Dict[str, str]
  - Enhancement: Support List[PatternRule] while maintaining dict compatibility
  - Backward compatible: Load both formats, convert dict to PatternRule list
- **PatternRule model** (models/pattern.py lines 10-91): Reuse as-is
  - No changes needed
  - WindowRule references PatternRule as field

#### ✅ Configuration File Backward Compatibility
- All existing `~/.config/i3/projects/{name}.json` files load without modification
- All existing `~/.config/i3/app-classes.json` files continue to work
- New files are additive, not replacements

### Violation Justification

**None** - This feature fully aligns with all constitution principles. No violations to justify.

## Project Structure

### Documentation (this feature)

```
specs/021-lets-create-a/
├── spec.md              # Complete (529 lines) - user stories, requirements, schema alignment
├── plan.md              # This file - implementation approach
├── research.md          # Phase 0 output - pattern matching strategies, i3 IPC patterns
├── data-model.md        # Phase 1 output - WindowRule, WorkspaceConfig schemas
├── quickstart.md        # Phase 1 output - testing scenarios for each user story
├── contracts/           # Phase 1 output - JSON schemas for config files
│   ├── window-rules-schema.json
│   ├── workspace-config-schema.json
│   └── daemon-ipc-extensions.json
├── checklists/
│   └── requirements.md  # Complete (131 lines) - 100% validation
└── tasks.md             # Phase 2 output - NOT created yet (/speckit.tasks)
```

### Source Code (repository root)

```
# Existing daemon architecture (reused)
home-modules/desktop/i3-project-event-daemon/
├── __init__.py
├── __main__.py          # Daemon entry point (systemd service)
├── daemon.py            # Main event loop
├── handlers.py          # Event handlers (extend for window rules)
├── state.py             # Daemon state management
├── models.py            # Daemon data models
├── config.py            # Config loader (enhance for window-rules.json)
├── event_buffer.py      # Event history (existing)
└── ipc_server.py        # JSON-RPC server (extend for rule management)

# NEW: Window rule management (Phase 3+)
home-modules/desktop/i3-project-event-daemon/
├── window_rules.py      # WindowRule model, config loader, pattern matching
├── workspace_manager.py # Workspace assignment logic, monitor detection
└── pattern_resolver.py  # 4-level precedence resolution algorithm

# Existing i3pm CLI/TUI (extend)
home-modules/tools/i3_project_manager/
├── core/
│   ├── models.py        # Project, AppClassification (ENHANCE class_patterns)
│   ├── pattern_matcher.py  # REUSE for window rules
│   └── daemon_client.py # EXTEND for window rule queries
├── models/
│   ├── pattern.py       # PatternRule (REUSE as-is)
│   └── workspace.py     # NEW: WorkspaceConfig model
├── cli/
│   └── commands.py      # EXTEND: i3pm rules, i3pm migrate-rules
└── tui/
    └── screens/
        └── rules.py     # NEW: Window rules management screen (optional P3)

# NEW: Configuration files (runtime, not in repo)
~/.config/i3/
├── projects/            # Existing - no changes
│   └── {name}.json
├── app-classes.json     # Existing - class_patterns enhanced
├── window-rules.json    # NEW: WindowRule list
└── workspace-config.json # NEW: WorkspaceConfig list

# Tests (new + extend existing)
tests/i3_project_manager/
├── unit/
│   ├── test_window_rules.py      # NEW: WindowRule validation
│   ├── test_pattern_resolver.py  # NEW: 4-level resolution
│   ├── test_workspace_manager.py # NEW: Monitor assignment
│   └── test_pattern_matcher.py   # Existing - verify reuse
├── integration/
│   ├── test_daemon_window_rules.py  # NEW: Daemon integration
│   └── test_i3_ipc_workspace.py     # NEW: i3 IPC workspace queries
└── scenarios/
    ├── test_pwa_detection.py         # NEW: User Story 2
    ├── test_terminal_classification.py  # NEW: User Story 3
    └── test_monitor_redistribution.py   # NEW: User Story 4
```

**Structure Decision**: Single project extending existing i3pm daemon architecture.

**Rationale**:
- Reuses established daemon patterns (event loop, IPC server, config loading)
- Extends existing models (Project, AppClassification, PatternRule) without duplication
- Integrates with existing CLI commands (i3pm) and TUI screens (monitor)
- Maintains backward compatibility with all existing JSON files
- Follows Python Development & Testing Standards (Constitution Principle X)
- Aligns with i3 IPC Authority (Constitution Principle XI)

**Key Integration Points**:
1. `handlers.py`: Extend window event handler to call window classification
2. `config.py`: Add window-rules.json and workspace-config.json loaders
3. `ipc_server.py`: Add JSON-RPC methods for rule queries and management
4. `core/models.py`: Enhance AppClassification.class_patterns field
5. `pattern_matcher.py`: Reuse for WindowRule pattern matching

**Migration Path**:
- Phase 1: Parallel implementation (static rules + dynamic rules both active)
- Phase 2: Migration tool (`i3pm migrate-rules` command)
- Phase 3: Deprecation warnings, eventual removal of static rules

## Complexity Tracking

**No violations** - This implementation maintains consistency with existing architecture.

**Complexity Justification (Informational)**:

While no constitution violations exist, the following complexity is inherent to the requirements:

| Complexity | Why Needed | Mitigation |
|------------|------------|------------|
| 4-level precedence hierarchy | Project overrides > window-rules > app-classes patterns > app-classes lists | Clear algorithm with source attribution in Classification object |
| Multiple config files | Separation of concerns: global (app-classes), advanced (window-rules), metadata (workspace-config), projects | Each file has distinct purpose, comprehensive examples provided |
| Schema enhancement (class_patterns) | AppClassification currently ignores class_patterns field - must integrate | Backward compatible dict→PatternRule conversion, no breaking changes |
| Pattern types (glob, regex, literal, title, pwa) | Different use cases require different matching strategies | Reuse existing PatternRule model with proven validation |

**Simpler Alternatives Rejected**:

1. **Single config file for all rules**: Rejected because mixing global defaults, user rules, and project-specific rules would create confusion and merge conflicts
2. **Keep static home-manager rules**: Rejected because rebuild requirement violates core user story (dynamic without rebuild)
3. **New pattern matching system**: Rejected because existing PatternRule model already has validation and LRU caching
4. **Ignore existing Project model**: Rejected because backward compatibility is non-negotiable requirement (FR-026)

**Long-term Maintenance**:
- Comprehensive unit tests for each precedence level (T040-T043)
- Integration tests verify actual precedence in practice (T084-T087)
- Scenario tests validate user stories end-to-end (T088-T094)
- Migration tool reduces manual conversion effort (T104-T105)
- Example configs demonstrate common patterns (T114-T115)
