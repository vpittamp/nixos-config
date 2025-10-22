# Tasks: Dynamic Window Management System - RECONCILED

**Status**: ⚠️ **RECONCILED** - Removed 28 duplicate tasks, kept 24 net-new tasks
**Original**: 52 tasks → **Reconciled**: 24 tasks
**Input**: Reconciliation analysis from OVERLAP_ANALYSIS.md and plan-reconciled.md

## Reconciliation Summary

After analyzing existing `i3-project-event-daemon` code:
- ✅ **ALREADY IMPLEMENTED**: WindowRule, PatternRule, pattern matching, classification, workspace management, project switching, event handlers
- ❌ **NEEDS IMPLEMENTATION**: Structured actions, schema migration, validation, CLI tools, hot-reload

See [OVERLAP_ANALYSIS.md](./OVERLAP_ANALYSIS.md) for detailed analysis.

## Format: `[ID] [P?] [Phase] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Phase]**: Schema, Actions, Validation, CLI, HotReload, Polish
- Include exact file paths in descriptions

---

## Phase 1: Schema Migration & Structured Actions (3 days)

**Purpose**: Migrate from string commands to typed action objects, maintain backwards compatibility

### Setup & Schema

- [X] R001 [P] [Schema] Copy JSON schema from contracts/window-rule-schema.json to `home-modules/tools/i3_project_manager/schemas/window_rules.json`
- [X] R002 [P] [Schema] Create default window rules template at `~/.config/i3/window-rules-default.json` with new format examples (Ghostty→WS1, Code→WS2, Firefox→WS3, YouTube PWA→WS4)
- [X] R003 [P] [Schema] Add pytest-asyncio to dev dependencies in home-manager config (if not already present)

### Structured Action Types

- [X] R004 [P] [Actions] Create `home-modules/desktop/i3-project-event-daemon/rule_action.py` with:
  - WorkspaceAction(type="workspace", target: int)
  - MarkAction(type="mark", value: str)
  - FloatAction(type="float", enable: bool)
  - LayoutAction(type="layout", mode: str)
  - RuleAction = Union[WorkspaceAction, MarkAction, FloatAction, LayoutAction]

- [X] R005 [Actions] **ENHANCE** existing `window_rules.py` WindowRule class to support:
  - Add `actions: Optional[List[RuleAction]] = None` field
  - Keep existing `workspace` and `command` fields for backwards compatibility
  - Validation: If `actions` is provided, use structured actions; otherwise fall back to old format
  - Update from_json() to detect format version and parse accordingly

### Migration Support

- [X] R006 [P] [Schema] Create `home-modules/tools/i3_project_manager/migration/rules_v1_migration.py` with:
  - migrate_rule_v1_to_v2() - Convert single old-format rule to new format
  - migrate_rules_file() - Convert entire rules file old→new
  - CLI command: `i3pm migrate-rules --input ~/.config/i3/window-rules.json --output ~/.config/i3/window-rules-v2.json`

**Checkpoint**: Schema and action types exist, WindowRule supports both formats, migration script works

---

## Phase 2: Action Execution & Multi-Monitor Validation (2 days)

**Purpose**: Execute structured actions and validate workspace assignments for multi-monitor

### Action Execution

- [X] R007 [P] [Actions] Create `home-modules/desktop/i3-project-event-daemon/action_executor.py` with:
  - async execute_workspace_action(conn, container_id, action: WorkspaceAction, focus: bool) → None
  - async execute_mark_action(conn, window_id, action: MarkAction) → None
  - async execute_float_action(conn, container_id, action: FloatAction) → None
  - async execute_layout_action(conn, container_id, action: LayoutAction) → None

- [X] R008 [Actions] Create action dispatcher in `action_executor.py`:
  - async apply_rule_actions(conn, window: WindowInfo, actions: List[RuleAction], focus: bool) → None
  - Executes each action in order
  - Logs each action execution for debugging
  - Returns list of results/errors

- [X] R009 [Actions] **ENHANCE** existing `handlers.py:on_window_new()` to:
  - After classification, check if matched_rule has `actions` field
  - If yes: call apply_rule_actions() with structured actions
  - If no: fall back to existing workspace/command behavior (backwards compatibility)
  - Log which path was taken (structured vs legacy)

### Multi-Monitor Validation

- [X] R010 [P] [Validation] **ENHANCE** existing `workspace_manager.py` with new function:
  - async validate_target_workspace(conn, workspace: int) → Tuple[bool, str]
  - Queries GET_WORKSPACES and GET_OUTPUTS
  - Checks if target workspace exists on active output
  - Returns (True, "") if valid, (False, error_msg) if invalid

- [X] R011 [Validation] **INTEGRATE** validation into workspace assignment:
  - In execute_workspace_action(), call validate_target_workspace() before move
  - If invalid, log warning and assign to current workspace instead
  - Track validation failures in event buffer

### Output Event Handling

- [X] R012 [P] [Validation] **ADD** output event handler in `handlers.py`:
  - async on_output(conn, event, state_manager, event_buffer)
  - Detects monitor connect/disconnect
  - Re-queries workspace distribution
  - Logs monitor configuration changes

- [X] R013 [Validation] **ENHANCE** `daemon.py` main() to:
  - Subscribe to output events: conn.on(Event.OUTPUT, on_output)
  - Log subscription at startup

**Checkpoint**: Structured actions execute correctly, workspace validation works, output events detected

---

## Phase 3: CLI Tools (1-2 days)

**Purpose**: User-facing validation and testing commands

### Validation CLI

- [X] R014 [P] [CLI] Create `home-modules/tools/i3_project_manager/cli/validate_rules.py`:
  - validate_rules_file(path: Path) → ValidationResult
  - Loads JSON file
  - Validates against schema (window_rules.json)
  - Checks for: duplicate rule names, invalid regex, focus=true without workspace action
  - Returns detailed error messages with line numbers

- [X] R015 [P] [CLI] Add CLI command in `cli/commands.py`:
  - `i3pm validate-rules [--file ~/.config/i3/window-rules.json]`
  - Calls validate_rules_file()
  - Displays validation results with colors (✓/✗)
  - Exits with code 0 (valid) or 1 (invalid)

### Testing CLI

- [X] R016 [P] [CLI] Create `home-modules/tools/i3_project_manager/cli/test_rule.py`:
  - test_rule_match(class: str, title: str, rules: List[WindowRule]) → MatchResult
  - Simulates window properties
  - Evaluates rules in priority order
  - Returns matched rule + actions that would execute

- [X] R017 [P] [CLI] Add CLI command in `cli/commands.py`:
  - `i3pm test-rule --class=Firefox [--title="GitHub"]`
  - Loads current rules from file
  - Calls test_rule_match()
  - Displays: matched rule name, priority, actions, or "No match"

**Checkpoint**: CLI validation and testing tools work correctly

---

## Phase 4: Hot-Reload (1 day)

**Purpose**: Reload rules without daemon restart

### File Watching

- [ ] R018 [HotReload] **ENHANCE** `daemon.py` with file watching:
  - Add inotify watcher for ~/.config/i3/window-rules.json
  - Detect IN_MODIFY and IN_CLOSE_WRITE events
  - Debounce rapid changes (wait 500ms after last change)

- [ ] R019 [HotReload] Add reload handler in `daemon.py`:
  - async on_rules_file_changed()
  - Calls load_window_rules() to reload
  - Validates new rules before applying
  - If validation fails: keep old rules, log error
  - If validation succeeds: swap rules, log success with timestamp

- [ ] R020 [P] [HotReload] Add reload tracking:
  - Track: last_reload_timestamp, reload_count, last_reload_error
  - Include in daemon status output
  - Add to event buffer as "reload" event type

**Checkpoint**: Rules hot-reload without daemon restart

---

## Phase 5: Testing & Polish (1 day)

**Purpose**: Error handling, logging, documentation, testing

### Error Handling & Logging

- [ ] R021 [P] [Polish] Add comprehensive error handling in `action_executor.py`:
  - Wrap each action execution in try/except
  - Log errors with context (window_id, action type, error message)
  - Continue executing remaining actions if one fails
  - Track failed actions in event buffer

- [ ] R022 [P] [Polish] Add performance monitoring:
  - Log action execution time for each action type
  - Track metrics: avg_action_time, max_action_time, action_count
  - Warn if action execution > 25ms
  - Include in daemon status output

### Integration & Documentation

- [ ] R023 [Polish] Integration testing:
  - Test old format rules still work (backwards compatibility)
  - Test new format rules work correctly
  - Test hot-reload with valid and invalid rules
  - Test multi-monitor workspace validation
  - Test all CLI commands

- [ ] R024 [Polish] Update documentation:
  - Update quickstart.md with new format examples
  - Add migration guide section
  - Document CLI commands
  - Add troubleshooting section for new features

**Checkpoint**: All features tested, documented, and polished

---

## Task Mapping: Old → Reconciled

### REMOVED Tasks (Already Implemented)

These 28 tasks are **SKIPPED** because functionality already exists:

- ❌ T004: WindowProperties → Use existing `WindowInfo` in models.py
- ❌ T005: MatchCriteria → Use existing `PatternRule` in pattern.py
- ❌ T007: WindowRule Pydantic → Use existing `WindowRule` in window_rules.py (enhance, not replace)
- ❌ T008: RuleMatchResult → Use existing `Classification` in pattern_resolver.py
- ❌ T009: extract_window_properties() → Already exists in handlers.py
- ❌ T010: __init__.py exports → Already exists
- ❌ T011-T012: Pattern matching → Already exists in pattern.py (exact, glob, regex, pwa, title)
- ❌ T013: find_matching_rule() → Already exists in pattern_resolver.py as classify_window()
- ❌ T014: load_window_rules() → Already exists in window_rules.py
- ❌ T016: mark_window() → Already exists in handlers.py
- ❌ T019-T020: on_window_new() → Already exists in handlers.py, already subscribed in daemon.py
- ❌ T022: Remove static i3 config → Already done (no static assign directives exist)
- ❌ T023: get_active_project() → Already exists in state_manager.py
- ❌ T024: Prioritize project rules → Already implemented in pattern_resolver.py (priority 1000)
- ❌ T025: Project mark generation → Already implemented in handlers.py
- ❌ T026-T028: Project switching → Already implemented in handlers.py (on_tick, _switch_project)
- ❌ T029: Project-scoped rules → Already exist in production
- ❌ T030-T033: Multi-monitor distribution → Already exists in workspace_manager.py
- ❌ T034-T035: Output events → **NEW** (R012-R013)
- ❌ T048: on_window_close() → Already exists in handlers.py
- ❌ T049: Update launcher scripts → Not needed (scripts already use dynamic assignment)

### KEPT Tasks (New Functionality)

These 24 tasks are **RECONCILED** from original plan:

- ✅ R001-R003: Setup (T001-T003) - Same
- ✅ R004: Structured actions (T006) - **NEW**
- ✅ R005: Enhance WindowRule (T007 modified) - **ENHANCE**
- ✅ R006: Migration script (**NEW**) - Not in original plan
- ✅ R007-R008: Action execution (T018 split) - **NEW**
- ✅ R009: Integrate actions into on_window_new (T019 modified) - **ENHANCE**
- ✅ R010-R011: Workspace validation (T015, T036 combined) - **NEW**
- ✅ R012-R013: Output events (T034-T035) - **NEW**
- ✅ R014-R017: CLI tools (T037-T040) - **NEW**
- ✅ R018-R020: Hot-reload (T041-T043) - **NEW**
- ✅ R021-R024: Polish (T045-T047, T050-T051 combined) - **NEW**

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Schema)**: No dependencies - can start immediately
- **Phase 2 (Actions)**: Depends on R004-R005 (action types must exist)
- **Phase 3 (CLI)**: Depends on R001 (schema), R005 (WindowRule format) - can run parallel with Phase 2
- **Phase 4 (HotReload)**: Depends on R005 (load_window_rules enhanced) - can run parallel with Phase 2-3
- **Phase 5 (Polish)**: Depends on all previous phases

### Parallel Opportunities

- R001-R003: All setup tasks parallel
- R004, R006: Action types and migration script parallel
- R007-R008: Action execution functions parallel
- R010, R012: Validation and output handler parallel
- R014, R016: CLI validation and testing parallel
- R021-R022: Error handling and monitoring parallel

### Critical Path

1. R001-R003 (Setup) → 2. R004-R005 (Action types) → 3. R007-R009 (Execution) → 4. R023 (Integration testing)

All other tasks can be parallelized or interleaved.

---

## Implementation Strategy

### MVP Approach (Phases 1-2)

1. Complete Phase 1: Schema + Actions (R001-R006) - **Day 1-2**
2. Complete Phase 2: Execution + Validation (R007-R013) - **Day 3-4**
3. **STOP and VALIDATE**: Test basic structured actions working
4. Deploy if ready - core functionality working

### Full Feature (All Phases)

1. MVP (Phases 1-2) - **Days 1-4**
2. Add CLI tools (Phase 3) - **Day 5-6**
3. Add hot-reload (Phase 4) - **Day 7**
4. Polish and test (Phase 5) - **Day 8**
5. Deploy complete feature

### Parallel Team Strategy

With 2-3 developers:

1. Developer A: Phase 1-2 (Schema + Actions) - Days 1-4
2. Developer B: Phase 3 (CLI tools) - Can start Day 2 (after R001, R005)
3. Developer C: Phase 4 (Hot-reload) - Can start Day 3 (after R005)
4. All: Phase 5 (Polish) - Day 8

**Timeline**: 8 days with 1 developer, 5 days with 3 developers (40% reduction)

---

## Success Criteria

### Functional Requirements

- ✅ Old format rules still work (backwards compatibility)
- ✅ New format rules work with structured actions
- ✅ Migration script converts old→new format correctly
- ✅ Workspace validation prevents assignment to inactive outputs
- ✅ Output events trigger workspace redistribution
- ✅ CLI validation catches all error types
- ✅ CLI testing shows correct rule matches
- ✅ Hot-reload updates rules without daemon restart

### Performance Requirements

- ✅ Action execution < 25ms per action
- ✅ Schema validation < 100ms for 100 rules
- ✅ Hot-reload < 500ms from file change to rules active
- ✅ No regression in window detection time (< 100ms maintained)

### Quality Requirements

- ✅ All existing integration tests still pass
- ✅ New integration tests for all new features
- ✅ Error handling covers all failure modes
- ✅ Logging provides clear debugging information
- ✅ Documentation updated with new format and CLI tools

---

## Notes

- [P] tasks = different files, no dependencies - can be executed in parallel
- **ENHANCE** = Modify existing file, don't create new one
- **ADD** = Add new function to existing file
- **NEW** = Create new file
- Total reconciled tasks: 24 (down from 52)
- Estimated time: 7-9 days solo, 5-6 days with team
- Backwards compatibility is critical - old format must work
- All changes should be in `i3-project-event-daemon/` directory, not `i3_project_manager/`

**Key Principle**: Enhance existing working code, don't replace it

---

**Document Status**: Ready for implementation
**Created**: 2025-10-22
**Version**: 1.0 (Reconciled)
