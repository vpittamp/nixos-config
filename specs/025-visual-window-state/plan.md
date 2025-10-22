# Implementation Plan: Visual Window State Management with Layout Integration

**Branch**: `025-visual-window-state` | **Date**: 2025-10-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/025-visual-window-state/spec.md`

## Summary

This feature enhances the i3pm system with real-time visual window state monitoring, improved layout save/restore using i3-resurrect patterns (window unmapping, flexible swallow criteria), layout diff capabilities, and i3-resurrect compatibility. The implementation extends i3's native JSON format with a non-invasive `i3pm` namespace, uses Textual widgets for hierarchical visualization, and maintains i3 IPC as the authoritative source of truth per Constitution XI.

**Primary Goals**:
1. Enable users to visualize current window state across monitors/workspaces in real-time
2. Prevent visual flicker during layout restore using window unmapping
3. Support layout diff to compare current state vs saved layouts
4. Enable migration from i3-resurrect with import/export capabilities

**Technical Approach** (from [research.md](./research.md)):
- Extend existing i3pm codebase with Pydantic models, Textual Tree/DataTable widgets
- Adopt i3-resurrect patterns: window unmapping (xdotool), flexible swallow criteria, workspace layout preservation
- Use psutil for launch command discovery from process tree
- Maintain event-driven architecture via daemon's i3 IPC subscriptions

## Technical Context

**Language/Version**: Python 3.11+
**Primary Dependencies**: i3ipc.aio (async i3 IPC), Textual (TUI framework), psutil (process analysis), Pydantic 2.x (data validation), xdotool (window manipulation)
**Storage**: JSON files (`~/.config/i3pm/projects/<project>/layouts/<name>.json`)
**Testing**: pytest with pytest-asyncio for async tests
**Target Platform**: Linux with i3 window manager, X11 display server
**Project Type**: Single (extending existing i3_project_manager Python package)
**Performance Goals**: <100ms real-time updates, <2s layout save, <30s layout restore, <500ms layout diff
**Constraints**: Constitution X (Python standards), Constitution XI (i3 IPC authority), Constitution XII (forward-only development)
**Scale/Scope**: 10-50 windows per workspace, 5-10 saved layouts per project, 1-3 monitors

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Principle X: Python Development & Testing Standards

- ✅ Python 3.11+ with async/await patterns (i3ipc.aio, asyncio)
- ✅ pytest with pytest-asyncio for testing
- ✅ Type hints for all function signatures and public APIs
- ✅ Pydantic models for data validation (WindowState, SavedLayout, etc.)
- ✅ Rich library for terminal UI (via Textual)
- ✅ Module structure follows single-responsibility (models, services, displays, validators)

### ✅ Principle XI: i3 IPC Alignment & State Authority

- ✅ All window state queries use i3 IPC (GET_TREE, GET_WORKSPACES, GET_OUTPUTS, GET_MARKS)
- ✅ i3 IPC data is authoritative, daemon state is secondary
- ✅ Event-driven updates via daemon's i3 IPC subscriptions
- ✅ Workspace-to-output assignments validated against i3 GET_WORKSPACES
- ✅ Monitor configuration queried via i3 GET_OUTPUTS

### ✅ Principle XII: Forward-Only Development & Legacy Elimination

- ✅ No backwards compatibility with hypothetical "old layout formats"
- ✅ Direct implementation of optimal solution (i3 JSON + i3pm namespace)
- ✅ No feature flags for legacy modes
- ✅ Complete replacement approach, not gradual migration

### ✅ Test-Before-Apply (Principle III)

- ✅ Comprehensive pytest test suite for models, swallow matching, diff computation
- ✅ Integration tests for daemon IPC and i3 IPC interaction
- ✅ Scenario tests for full save/restore workflows

### ✅ Modular Composition (Principle I)

- ✅ Extends existing i3_project_manager modules (core/layout.py, core/models.py, core/daemon_client.py)
- ✅ New modules follow established patterns (visualization/, core/swallow_matcher.py, core/layout_diff.py)
- ✅ Reuses daemon's event-driven architecture

### 📋 Additional Checks

- ✅ Documentation as Code: quickstart.md, data-model.md, research.md, contracts/ schemas
- ✅ Security standards: Launch command validation, environment variable filtering
- ✅ Performance targets: Real-time updates (<100ms), layout operations (<30s)

**Result**: All constitution checks pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```
specs/025-visual-window-state/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (technology decisions, i3-resurrect analysis)
├── data-model.md        # Phase 1 output (entity definitions, Pydantic models)
├── quickstart.md        # Phase 1 output (developer guide, testing workflow)
├── contracts/           # Phase 1 output (JSON schemas)
│   ├── window-rule-schema.json
│   └── rule-action-schema.json (saved layout schema)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT YET CREATED)
```

### Source Code (repository root)

```
home-modules/tools/i3_project_manager/
├── models/
│   ├── layout.py                 # [EXTEND] Add Pydantic models (SwallowCriteria, WindowState, SavedLayout)
│   └── __init__.py               # [EXTEND] Export new models
├── core/
│   ├── layout.py                 # [EXTEND] Add unmapping/remapping, enhanced restore
│   ├── models.py                 # [EXTEND] Add validation to existing models
│   ├── daemon_client.py          # [EXTEND] Add get_window_tree(), subscribe_window_events()
│   ├── swallow_matcher.py        # [NEW] Swallow criteria matching logic
│   ├── layout_diff.py            # [NEW] Diff computation algorithm
│   └── i3_client.py              # [EXISTING] i3 IPC wrapper
├── visualization/
│   ├── __init__.py               # [NEW] Package init
│   ├── tree_view.py              # [NEW] Textual Tree widget for hierarchical display
│   └── table_view.py             # [NEW] Textual DataTable for sortable/filterable display
├── cli/
│   ├── commands.py               # [EXTEND] Add windows, layout diff, layout import/export commands
│   └── formatters.py             # [EXTEND] Add tree/table formatters
├── tui/
│   └── screens/
│       ├── monitor.py            # [EXTEND] Add tree view tab
│       └── layout_manager.py     # [EXISTING] Layout management screen
├── schemas/
│   ├── __init__.py               # [NEW] Package init
│   ├── saved_layout.json         # [NEW] JSON schema for SavedLayout
│   └── swallow_criteria.json    # [NEW] JSON schema for SwallowCriteria
└── testing/
    ├── integration.py            # [EXISTING] Integration test framework
    └── framework.py              # [EXISTING] Test scenarios

tests/i3_project_manager/
├── unit/
│   ├── test_models.py            # [NEW] Test Pydantic models
│   ├── test_swallow_matcher.py   # [NEW] Test swallow matching logic
│   └── test_layout_diff.py       # [NEW] Test diff computation
├── integration/
│   ├── test_layout_save.py       # [NEW] Test layout save with discovery
│   ├── test_layout_restore.py    # [NEW] Test restore with unmapping
│   └── test_daemon_client.py     # [EXTEND] Add window state query tests
└── scenarios/
    ├── test_layout_lifecycle.py  # [NEW] Full save/restore/diff workflow
    └── test_i3_resurrect_compat.py # [NEW] Import/export compatibility

home-modules/desktop/i3-project-event-daemon/
├── handlers.py                   # [EXTEND] Add window state broadcast to subscribers
└── ipc_server.py                 # [EXTEND] Add get_window_state RPC method
```

**Structure Decision**: Extending existing single-project Python package (`i3_project_manager`) with new modules for visualization, enhanced matching, and diff computation. Tests organized by type (unit, integration, scenarios) following existing pattern. Daemon extensions minimal (add RPC methods for window state queries).

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

No violations - section not applicable.

## Implementation Phases

### Phase 0: Research & Design ✅ COMPLETE

**Status**: ✅ Complete (research.md, data-model.md, contracts/, quickstart.md generated)

**Artifacts Created**:
- research.md: Technology stack decisions, i3-resurrect pattern analysis, integration points
- data-model.md: Entity definitions with Pydantic models (WindowState, SwallowCriteria, LayoutWindow, WorkspaceLayout, SavedLayout, WindowDiff)
- contracts/: JSON schemas for validation (window-rule-schema.json, rule-action-schema.json)
- quickstart.md: Developer guide with setup, workflow, testing, debugging

**Key Decisions Made**:
1. Visualization: Textual Tree + DataTable (not Mermaid or custom ASCII)
2. JSON Format: i3 native JSON + non-invasive `i3pm` namespace
3. Window Matching: Adopt i3-resurrect flexible swallow criteria
4. Flicker Prevention: Adopt i3-resurrect window unmapping pattern (xdotool)
5. Launch Discovery: psutil process tree analysis + manual overrides
6. Diff Algorithm: Git-style three-way categorization (added/removed/moved/kept)

### Phase 1: Core Models & Validation 🔄 NEXT

**Estimated Time**: 4-6 hours

**Tasks**:
1. **Implement Pydantic Models** (`models/layout.py`):
   - SwallowCriteria with regex validation and matches() method
   - WindowState with i3 IPC contract validation
   - LayoutWindow with command validation and secret filtering
   - WorkspaceLayout with count validation
   - SavedLayout with version check and export_i3_json() method
   - WindowDiff with count validation and summary() method
   - LaunchCommand with source tracking

2. **Add JSON Schema Validation** (`schemas/`):
   - Copy contracts/*.json to schemas/ directory
   - Implement schema validation utilities
   - Add schema version detection

3. **Unit Tests** (`tests/unit/`):
   - test_models.py: Validate all Pydantic models with edge cases
   - Test validation failures (invalid regex, missing criteria, etc.)
   - Test model serialization (to_json, from_json)
   - Test SwallowCriteria.matches() with sample window data

**Acceptance Criteria**:
- All Pydantic models defined with type hints and validation
- All models serialize to/from JSON correctly
- JSON schemas validate sample layout files
- Unit tests achieve >90% coverage of models
- No test failures

### Phase 2: Window State Visualization 📊

**Estimated Time**: 6-8 hours

**User Stories Addressed**: User Story 1 (Real-Time Window State Monitoring)

**Tasks**:
1. **Implement Tree View** (`visualization/tree_view.py`):
   - Textual Tree widget for hierarchical display (monitor → workspace → window)
   - Real-time updates via daemon IPC subscription
   - Keyboard navigation (arrows, Enter to focus, 'c' to collapse)
   - Search/filter capability

2. **Implement Table View** (`visualization/table_view.py`):
   - Textual DataTable for sortable/filterable display
   - Columns: ID, Class, Instance, Title, Workspace, Output, Project, Hidden
   - Sort by any column
   - Filter by project, workspace, output, hidden status

3. **Extend Monitor Screen** (`tui/screens/monitor.py`):
   - Add "Window Tree" tab with tree view widget
   - Add "Window Table" tab with table view widget
   - Connect to daemon for real-time updates

4. **Add CLI Commands** (`cli/commands.py`):
   - `i3pm windows --tree`: Print ASCII tree
   - `i3pm windows --table`: Print table
   - `i3pm windows --live`: Launch TUI
   - `i3pm windows --json`: Export JSON

5. **Extend Daemon Client** (`core/daemon_client.py`):
   - Add get_window_tree() RPC method
   - Add subscribe_window_events() subscription
   - Handle event stream with async iterator

6. **Integration Tests** (`tests/integration/`):
   - test_daemon_client.py: Test get_window_tree(), subscribe_window_events()
   - Mock daemon responses with sample window data
   - Test real-time update handling

**Acceptance Criteria**:
- Tree view displays all windows organized by monitor/workspace
- Real-time updates appear within 100ms of window events
- Table view supports sorting and filtering
- CLI commands produce correct output
- TUI responds to keyboard navigation
- Integration tests pass

### Phase 3: Enhanced Layout Save/Restore 💾

**Estimated Time**: 8-10 hours

**User Stories Addressed**: User Story 2 (Visual Layout Save and Restore), User Story 4 (Enhanced Window Matching)

**Tasks**:
1. **Implement Swallow Matcher** (`core/swallow_matcher.py`):
   - Load swallow criteria configuration from file
   - Apply per-app overrides (title patterns, window roles)
   - Match window against criteria with priority logic
   - Cache compiled regex patterns

2. **Implement Launch Command Discovery** (`core/layout.py`):
   - Use psutil to walk process tree
   - Extract command line, working directory, environment
   - Apply manual overrides from configuration
   - Filter sensitive environment variables

3. **Enhance Layout Save** (`core/layout.py`):
   - Query i3 IPC for complete window state
   - Discover launch commands for all windows
   - Generate SwallowCriteria from window properties
   - Save as extended i3 JSON format
   - Validate against JSON schema

4. **Implement Window Unmapping** (`core/layout.py`):
   - Use xdotool to unmap existing windows before restore
   - Generate i3 append_layout JSON with placeholders
   - Launch applications with discovered commands
   - Wait for swallow with configurable timeout
   - Remap all windows in try/finally block

5. **Enhance Layout Restore** (`core/layout.py`):
   - Load and validate saved layout
   - Check monitor configuration compatibility
   - Restore workspace-by-workspace with unmapping
   - Match existing windows by swallow criteria
   - Report success/failure details

6. **Unit Tests** (`tests/unit/`):
   - test_swallow_matcher.py: Test criteria matching, priority logic
   - Test launch command discovery with mock psutil data
   - Test environment filtering (secrets removed)

7. **Integration Tests** (`tests/integration/`):
   - test_layout_save.py: Test full save workflow
   - test_layout_restore.py: Test restore with unmapping
   - Mock i3 IPC and xdotool commands
   - Test error handling (app launch failure, timeout)

**Acceptance Criteria**:
- Layout save captures all window properties and launch commands
- Layout restore relaunches missing apps and repositions existing windows
- No visual flicker during restore (verified by user testing)
- Swallow criteria match 95%+ of windows correctly
- Launch command discovery succeeds for 80%+ of apps
- Integration tests pass
- Saved layouts validate against JSON schema

### Phase 4: Layout Diff & Partial Restore 📊

**Estimated Time**: 5-7 hours

**User Stories Addressed**: User Story 3 (Layout Diff and Comparison)

**Tasks**:
1. **Implement Diff Computation** (`core/layout_diff.py`):
   - Load saved layout and query current state
   - Match windows using swallow criteria
   - Categorize as added/removed/moved/kept
   - Compute summary statistics

2. **Add Diff Visualization** (`visualization/diff_view.py`):
   - Side-by-side comparison view (Textual layout)
   - Color coding (green=added, red=removed, yellow=moved)
   - Show workspace assignments for moved windows
   - Interactive actions: restore missing, update layout, discard

3. **Add CLI Commands** (`cli/commands.py`):
   - `i3pm layout diff <name>`: Show diff vs saved layout
   - `i3pm layout diff <name> --restore-missing`: Restore only missing windows
   - `i3pm layout diff <name> --update`: Update saved layout with current state

4. **Implement Partial Restore** (`core/layout.py`):
   - Restore only missing windows from diff
   - Skip existing windows (no unmapping)
   - Use swallow criteria to match missing windows

5. **Unit Tests** (`tests/unit/`):
   - test_layout_diff.py: Test diff computation with sample data
   - Test categorization logic (added/removed/moved/kept)
   - Test edge cases (empty workspace, all windows changed)

6. **Scenario Tests** (`tests/scenarios/`):
   - test_layout_lifecycle.py: Full save/diff/restore workflow
   - Test partial restore (only missing windows)
   - Test layout update after diff

**Acceptance Criteria**:
- Diff computation completes in <500ms for 50 windows
- Diff view shows clear categorization with colors
- Partial restore launches only missing windows
- CLI commands produce correct output
- Unit and scenario tests pass

### Phase 5: i3-resurrect Compatibility 🔄

**Estimated Time**: 4-6 hours

**User Stories Addressed**: User Story 5 (i3-resurrect Layout Migration)

**Tasks**:
1. **Implement Import** (`core/layout.py`):
   - Parse i3-resurrect JSON format
   - Convert swallow patterns to i3pm SwallowCriteria
   - Detect launch commands from configuration or prompt user
   - Save as i3pm extended JSON format

2. **Implement Export** (`core/layout.py`):
   - Load i3pm SavedLayout
   - Strip `i3pm` namespace to produce vanilla i3 JSON
   - Validate exported JSON against i3 append_layout schema
   - Test with vanilla i3-msg append_layout command

3. **Add CLI Commands** (`cli/commands.py`):
   - `i3pm layout import <file> --project=<name>`: Import i3-resurrect layout
   - `i3pm layout export <name> --format=i3-resurrect`: Export as vanilla i3 JSON

4. **Compatibility Tests** (`tests/scenarios/`):
   - test_i3_resurrect_compat.py: Test import/export round-trip
   - Test exported layouts with vanilla i3-msg append_layout
   - Test imported layouts restore correctly

**Acceptance Criteria**:
- i3-resurrect layouts import successfully
- Exported layouts are 100% compatible with vanilla i3
- Import prompts for missing launch commands
- Compatibility tests pass

### Phase 6: Documentation & Polish ✨

**Estimated Time**: 2-3 hours

**Tasks**:
1. **Update CLAUDE.md**:
   - Add new commands (i3pm windows, i3pm layout diff, import/export)
   - Add troubleshooting section for layout issues
   - Add performance metrics

2. **Create User Guide** (`docs/I3PM_LAYOUTS.md`):
   - Getting started with layouts
   - Common workflows (save/restore/diff)
   - Customizing swallow criteria
   - Migrating from i3-resurrect

3. **Add Examples** (`docs/examples/`):
   - Sample layout JSON files
   - Sample swallow criteria configuration
   - CLI command examples

4. **Performance Testing**:
   - Benchmark real-time update latency
   - Benchmark layout save/restore times
   - Verify success criteria metrics

**Acceptance Criteria**:
- CLAUDE.md updated with complete command reference
- User guide covers all workflows
- Example files provided
- Performance targets met per Success Criteria

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| xdotool window unmapping fails on some window types | Medium | High | Add fallback to skip unmapping, document known issues |
| psutil launch command discovery fails for complex apps | High | Medium | Implement manual override configuration, prompt user |
| Swallow criteria too strict (windows not matched) | Medium | High | Start with loose criteria (class+instance), add override config |
| Layout restore timeout with slow-launching apps | Medium | Medium | Make timeout configurable (default 30s), show progress |
| i3-resurrect layouts incompatible edge cases | Low | Medium | Document known incompatibilities, provide migration guide |
| Real-time updates overwhelm TUI (100+ windows) | Low | High | Implement debouncing (100ms), collapsible tree sections |

## Timeline Estimate

**Total Estimated Time**: 29-40 hours (3.5-5 working days)

**Phase Breakdown**:
- Phase 1: Core Models & Validation (4-6h)
- Phase 2: Window State Visualization (6-8h)
- Phase 3: Enhanced Layout Save/Restore (8-10h)
- Phase 4: Layout Diff & Partial Restore (5-7h)
- Phase 5: i3-resurrect Compatibility (4-6h)
- Phase 6: Documentation & Polish (2-3h)

**Critical Path**: Phase 1 → Phase 3 (models required for save/restore) → Phase 4 (diff requires save/restore)

**Parallel Work Possible**: Phase 2 (visualization) can be developed in parallel with Phase 3 (layout operations) after Phase 1 completes.

## Success Metrics

From [spec.md](./spec.md) Success Criteria:

| Metric | Target | How Measured |
|--------|--------|--------------|
| Real-time update latency | <100ms | pytest benchmark with time assertions |
| Tree rendering performance | <100ms for 100 windows | Textual render profiling |
| Layout save time | <2s for 20 windows | pytest integration test timing |
| Layout restore time | <30s for 20 windows | pytest integration test timing |
| Layout restore success rate | 95% windows correct workspace | Integration test validation |
| Layout diff computation | <500ms for 50 windows | pytest benchmark |
| i3 JSON compatibility | 100% | Test with vanilla i3-msg append_layout |
| User comprehension time | <10s to understand window state | User testing feedback |

## Next Steps

**Immediate Actions**:
1. ✅ Review research.md for technology decisions
2. ✅ Review data-model.md for entity definitions
3. ✅ Review quickstart.md for development workflow
4. 🔄 Run `/speckit.tasks` to generate detailed task breakdown (tasks.md)
5. 🔄 Begin Phase 1: Implement Pydantic models

**Command to Proceed**:
```bash
cd /etc/nixos
/speckit.tasks  # Generate tasks.md with detailed implementation tasks
```

## References

- **Spec**: [spec.md](./spec.md) - Complete feature requirements and user stories
- **Research**: [research.md](./research.md) - Technology decisions and i3-resurrect analysis
- **Data Model**: [data-model.md](./data-model.md) - Entity definitions with Pydantic models
- **Quickstart**: [quickstart.md](./quickstart.md) - Developer setup and workflow
- **Contracts**: [contracts/](./contracts/) - JSON schemas for validation
- **i3 IPC Docs**: https://i3wm.org/docs/ipc.html
- **Textual Docs**: https://textual.textualize.io/
- **Pydantic Docs**: https://docs.pydantic.dev/

---

**Planning Phase Complete** ✅

Branch `025-visual-window-state` is ready for implementation. Generated artifacts:
- research.md (technology decisions)
- data-model.md (entity definitions)
- contracts/ (JSON schemas)
- quickstart.md (developer guide)
- plan.md (this file)

**Next Command**: `/speckit.tasks` to generate tasks.md with detailed implementation checklist.
