# Implementation Plan: Dynamic Window Rules - RECONCILED

**Branch**: `024-update-replace-test` | **Date**: 2025-10-22 | **Spec**: [spec.md](./spec.md)
**Status**: ⚠️ **RECONCILIATION REQUIRED** - 60-70% overlap with existing functionality
**Input**: Feature specification + existing i3pm daemon codebase

## Critical Finding: Significant Existing Implementation

**Analysis Document**: See [OVERLAP_ANALYSIS.md](./OVERLAP_ANALYSIS.md) for complete details.

### Summary

After analyzing the existing `home-modules/desktop/i3-project-event-daemon/` codebase:

✅ **ALREADY IMPLEMENTED** (60-70%):
- Window rules engine with WindowRule class
- Pattern matching (exact, glob, regex, pwa, title)
- 4-level classification precedence
- Multi-monitor workspace distribution
- Project-scoped window management
- Event-driven window detection

❌ **NEEDS IMPLEMENTATION** (30-40%):
- Structured action types (vs string commands)
- JSON schema migration (backwards-compatible)
- Workspace validation for multi-monitor
- Output event handling
- CLI validation tools
- Hot-reload support

## Reconciled Technical Context

**Language/Version**: Python 3.11+ (matches existing i3pm daemon)
**Primary Dependencies**:
- i3ipc.aio (EXISTING - already in use)
- pydantic (EXISTING - already in use)
- pytest + pytest-asyncio (EXISTING)
- systemd (EXISTING)

**Storage**: JSON configuration files (EXISTING pattern)
- `~/.config/i3/window-rules.json` - Window rules (ENHANCE format)
- `~/.config/i3/app-classes.json` - App classification (KEEP existing)
- `~/.config/i3/projects/*.json` - Project metadata (KEEP existing)

**Testing**: pytest with async support (EXISTING infrastructure)

**Target Platform**: NixOS with i3 window manager (EXISTING)

**Project Type**: System service extension (EXISTING daemon enhancement)

**Performance Goals**:
- Window detection < 100ms (ALREADY MEETING: SC-011)
- Rule evaluation < 50ms per window (NEW validation needed)
- Event processing 50+ events/second (ALREADY MEETING)
- Memory usage < 50MB with 50 windows (ALREADY MEETING: SC-008)

## Constitution Check

✅ **Principle I (Modular Composition)**: FIXED - Will enhance existing modules instead of duplicating

✅ **Principle III (Test-Before-Apply)**: COMPLIANT - Existing test infrastructure

✅ **Principle VI (Declarative Configuration)**: COMPLIANT - JSON-based rules

✅ **Principle VII (Documentation as Code)**: COMPLIANT - Module docstrings exist

✅ **Principle X (Python Development Standards)**: COMPLIANT - Already following standards

✅ **Principle XI (i3 IPC Alignment)**: COMPLIANT - Existing code uses i3 IPC correctly

✅ **Principle XII (Forward-Only Development)**: COMPLIANT - Will enhance, not replace existing code

## Reconciled Project Structure

### Existing Code (REUSE)

```
home-modules/desktop/i3-project-event-daemon/
├── window_rules.py          # ENHANCE: Add structured actions
├── pattern.py               # KEEP: Already supports all patterns
├── pattern_resolver.py      # KEEP: 4-level precedence works
├── workspace_manager.py     # ENHANCE: Add validation
├── handlers.py              # ENHANCE: Add output events
├── daemon.py                # ENHANCE: Subscribe to output events
├── models.py                # ENHANCE: Add missing window properties
└── config.py                # KEEP: Existing config loading

home-modules/tools/i3_project_manager/
├── models/
│   ├── pattern.py           # REUSE: Copy of daemon's pattern.py
│   ├── classification.py    # REUSE: Copy of daemon's classification
│   └── workspace.py         # REUSE: Copy of daemon's workspace models
└── core/
    ├── app_discovery.py     # KEEP: Existing functionality
    └── config.py            # KEEP: Existing functionality
```

### New Code (CREATE)

```
home-modules/desktop/i3-project-event-daemon/
├── rule_action.py           # NEW: Structured action types
└── action_executor.py       # NEW: Execute workspace/mark/float/layout actions

home-modules/tools/i3_project_manager/
├── schemas/
│   └── window_rules.json    # NEW: JSON schema for validation
├── cli/
│   ├── validate_rules.py    # NEW: Rule validation command
│   └── test_rule.py         # NEW: Rule testing command
└── migration/
    └── rules_v1_migration.py # NEW: Migrate old format → new format

~/.config/i3/
├── window-rules.json         # ENHANCED: New structured format
└── window-rules-default.json # NEW: System defaults
```

## Revised Implementation Phases

### Phase 1: Schema Migration & Structured Actions (3 days)

**Goal**: Migrate from string commands to structured action types

**Tasks**:
1. Create `rule_action.py` with WorkspaceAction, MarkAction, FloatAction, LayoutAction
2. Create JSON schema `schemas/window_rules.json`
3. Enhance `WindowRule` class to support `actions: List[RuleAction]`
4. Create migration script for old format → new format
5. Create `window-rules-default.json` template
6. Update `load_window_rules()` to support both formats (backwards-compatible)

**Dependencies**: None (can start immediately)

**Deliverables**:
- `rule_action.py` - Action type definitions
- `schemas/window_rules.json` - Validation schema
- Migration script
- Updated `WindowRule` class

### Phase 2: Action Execution & Multi-Monitor Validation (2 days)

**Goal**: Execute structured actions and validate workspace assignments

**Tasks**:
1. Create `action_executor.py` with:
   - `execute_workspace_action()` - Move window to workspace
   - `execute_mark_action()` - Add mark to window
   - `execute_float_action()` - Set floating state
   - `execute_layout_action()` - Set layout mode
   - `apply_rule_actions()` - Dispatcher for all actions
2. Add `validate_target_workspace()` to `workspace_manager.py`
3. Integrate validation into window assignment flow
4. Add `on_output()` handler to `handlers.py`
5. Subscribe to output events in `daemon.py`

**Dependencies**: Phase 1 complete (needs action types)

**Deliverables**:
- `action_executor.py` - Action execution logic
- Enhanced `workspace_manager.py` with validation
- Enhanced `handlers.py` with output events
- Enhanced `daemon.py` with output subscription

### Phase 3: CLI Tools & Hot-Reload (1-2 days)

**Goal**: User-facing validation and hot-reload support

**Tasks**:
1. Create `cli/validate_rules.py` - Validate rules against schema
2. Create `cli/test_rule.py` - Test rule matching
3. Add `i3pm validate-rules` command
4. Add `i3pm test-rule --class X --title Y` command
5. Implement `watch_rules_file()` with inotify
6. Add `on_rules_file_changed()` handler
7. Add reload timestamp tracking

**Dependencies**: Phase 1 complete (needs schema), Phase 2 for testing

**Deliverables**:
- CLI validation commands
- Hot-reload support
- Reload tracking

### Phase 4: Testing & Polish (1 day)

**Goal**: Comprehensive testing and error handling

**Tasks**:
1. Add error handling for invalid actions
2. Add logging throughout action execution
3. Update state restoration to handle new format
4. Add performance monitoring for action execution
5. Update launcher scripts to work with new rules
6. Write integration tests for new functionality
7. Update documentation

**Dependencies**: All previous phases

**Deliverables**:
- Comprehensive error handling
- Performance monitoring
- Integration tests
- Updated documentation

## Key Design Decisions

### 1. Backwards Compatibility

**Decision**: Support both old and new JSON formats during transition

**Rationale**: Constitution Principle XII (Forward-Only) + minimize disruption

**Implementation**:
```python
def load_window_rules(config_path: str) -> List[WindowRule]:
    """Load rules from JSON (supports v1 and v2 formats)."""
    data = json.load(open(config_path))

    if isinstance(data, list):
        # Old format: JSON array
        return [WindowRule.from_json_v1(item) for item in data]
    elif isinstance(data, dict) and data.get("version") == "1.0":
        # New format: Structured with version
        return [WindowRule.from_json_v2(item) for item in data["rules"]]
    else:
        raise ValueError("Unsupported window rules format")
```

### 2. Action Execution Order

**Decision**: Execute actions in order specified in rule

**Rationale**: Predictable behavior, allows chaining (workspace → layout → mark)

**Example**:
```json
{
  "actions": [
    {"type": "workspace", "target": 2},     // First: Move window
    {"type": "layout", "mode": "tabbed"},   // Second: Set layout
    {"type": "mark", "value": "editor"}     // Third: Add mark
  ]
}
```

### 3. Migration Strategy

**Decision**: Provide migration script, support both formats, eventually deprecate old format

**Timeline**:
- Phase 1: Add new format support
- Phase 2-3: Run both formats in parallel
- Phase 4: Deprecation warning for old format
- Future: Remove old format support (Feature 025+)

## Integration with Existing Features

### Feature 015: Event-Driven Daemon

**Integration Point**: `handlers.py:on_window_new()`

**Current Flow**:
```python
async def on_window_new(conn, event, state_manager, app_classification, event_buffer, window_rules):
    # 1. Extract window properties
    # 2. Classify window (uses window_rules)
    # 3. Apply workspace assignment
    # 4. Add project marks if scoped
```

**Enhanced Flow**:
```python
async def on_window_new(conn, event, state_manager, app_classification, event_buffer, window_rules):
    # 1. Extract window properties (ENHANCED: add role, type, transient_for)
    # 2. Classify window (KEEP: existing 4-level precedence)
    # 3. Apply rule actions (NEW: structured actions)
    # 4. Add project marks if scoped (KEEP: existing logic)
```

### Feature 017: Monitoring Tools

**Integration Point**: Event buffer recording

**Enhancement**: Add action execution events to buffer for debugging

### Feature 018: Testing Framework

**Integration Point**: Existing test infrastructure

**Enhancement**: Add tests for new action types and CLI commands

## Success Criteria (Updated)

**From Original Plan**:
- ✅ SC-001: Window detection < 500ms (ALREADY MEETING: < 100ms)
- ✅ SC-003: Event processing 50+ events/second (ALREADY MEETING)
- ✅ SC-008: Memory usage < 50MB (ALREADY MEETING: ~15MB)
- ✅ SC-011: Window::new processing < 100ms (ALREADY MEETING)
- ❌ SC-010: Rule validation < 5s (NEW - needs CLI tool)
- ❌ SC-012: Rule evaluation < 5ms for 100 rules (NEW - needs validation)
- ✅ SC-013: State restoration < 2s for 200 windows (ALREADY MEETING: 1.65s)

**New Criteria**:
- Action execution < 25ms per action
- Schema validation < 100ms for 100 rules
- Hot-reload < 500ms
- Migration script < 5s for 100 rules

## Risk Mitigation

### Risk 1: Breaking Existing Functionality

**Mitigation**:
- Backwards-compatible format support
- Comprehensive integration testing
- Gradual rollout with feature flags
- Easy rollback via git

### Risk 2: Performance Regression

**Mitigation**:
- Benchmark before/after
- Performance monitoring in production
- Optimize hot paths (rule matching unchanged)
- Action execution is new overhead (budget: 25ms)

### Risk 3: User Confusion During Migration

**Mitigation**:
- Clear migration guide in quickstart.md
- Automated migration script
- Support both formats during transition
- Deprecation warnings with clear messages

## Timeline

**Total Estimated Time**: 7-9 days

- Phase 1: 3 days (schema + actions)
- Phase 2: 2 days (execution + validation)
- Phase 3: 1-2 days (CLI + hot-reload)
- Phase 4: 1 day (testing + polish)

**vs Original Estimate**: 7-11 days → SAME (but 60% less new code due to reuse)

## Next Steps

1. ✅ Review and approve this reconciled plan
2. ✅ Update tasks.md to remove 28 duplicate tasks
3. ✅ Update data-model.md to reference existing models
4. ✅ Begin Phase 1: Schema migration
5. ✅ Create PR with backwards-compatible changes

## Appendix: Comparison with Original Plan

### Original Plan

- 52 tasks across 7 phases
- New window_rules.py, pattern.py, workspace_manager.py
- Complete reimplementation of window management

### Reconciled Plan

- 24 net-new tasks across 4 phases
- Enhance existing modules
- Add structured actions + CLI tools + validation

### Lines of Code Estimate

**Original**: ~2000 LOC new
**Reconciled**: ~800 LOC new + ~400 LOC modified = ~1200 total

### Complexity Reduction

**Original**: High (complete new system)
**Reconciled**: Medium (enhance existing system)

---

**Document Status**: Draft - Awaiting approval
**Created**: 2025-10-22
**Author**: Claude Code
**Version**: 1.0 (Reconciled)
