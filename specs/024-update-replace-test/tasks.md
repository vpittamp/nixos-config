# Tasks: Dynamic Window Management System

⚠️ **RECONCILIATION NOTICE**: This file contains the original 52 tasks. After analyzing existing codebase, 28 tasks are duplicates. See [tasks-reconciled.md](./tasks-reconciled.md) for the 24 net-new tasks.

**Status**: ⚠️ **DEPRECATED** - Use tasks-reconciled.md for implementation
**Reconciliation Analysis**: See [OVERLAP_ANALYSIS.md](./OVERLAP_ANALYSIS.md)
**Revised Plan**: See [plan-reconciled.md](./plan-reconciled.md)

---

**Input**: Design documents from `/etc/nixos/specs/024-update-replace-test/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested in spec - focusing on implementation tasks only

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## i3-resurrect Integration Note

**Status**: Analysis completed (2025-10-22) - Pattern extraction approach confirmed

After analyzing i3-resurrect (well-vetted Python project for workspace layout persistence), we determined:
- **DO NOT** use as external dependency (different problem domain: layout save/restore vs dynamic routing)
- **DO** extract proven patterns for window property extraction and swallow criteria matching
- See detailed analysis: `i3-resurrect-analysis.md`

**Impact on Tasks**:
- T004, T009: Window property extraction informed by i3-resurrect/treeutils.py patterns
- T011-T012: Pattern matching (exact/regex/wildcard) informed by i3-resurrect swallow criteria
- No new external dependencies required - already have i3ipc.aio, pydantic (T003 only adds pytest-asyncio for testing)
- No xdotool, Click, or psutil dependencies (i3-resurrect deps not needed for our use case)

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (Setup, Found, US1, US2, US3, US4, Polish)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure preparation

- [ ] T001 [P] [Setup] Create window rules JSON schema file at `home-modules/tools/i3_project_manager/schemas/window_rules.json` (copy from contracts/window-rule-schema.json)
- [ ] T002 [P] [Setup] Create default window rules configuration template at `~/.config/i3/window-rules-default.json` with example rules for common applications
- [ ] T003 [P] [Setup] Add pytest-asyncio dependency to Python development environment in home-manager configuration

**Checkpoint**: Basic project structure ready for foundational implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 [P] [Found] Create WindowProperties dataclass in `home-modules/tools/i3_project_manager/models/window_properties.py` with fields: con_id, window_id, window_class, window_instance, window_title, window_role, window_type, workspace, marks, transient_for (from data-model.md) - **Property coverage informed by i3-resurrect/treeutils.py REQUIRED_ATTRIBUTES**
- [ ] T005 [P] [Found] Create MatchCriteria Pydantic model in `home-modules/tools/i3_project_manager/models/window_rule.py` with PatternMatch nested model supporting exact/regex/wildcard match types (from data-model.md section 2)
- [ ] T006 [P] [Found] Create RuleAction discriminated union types in `home-modules/tools/i3_project_manager/models/rule_action.py`: WorkspaceAction, MarkAction, FloatAction, LayoutAction (from data-model.md section 3)
- [ ] T007 [Found] Create WindowRule Pydantic model in `home-modules/tools/i3_project_manager/models/window_rule.py` with fields: name, match_criteria, actions, priority, focus, enabled (depends on T005, T006)
- [ ] T008 [P] [Found] Create RuleMatchResult dataclass in `home-modules/tools/i3_project_manager/models/window_rule.py` for storing matched rule and actions to apply
- [ ] T009 [P] [Found] Create window property extraction functions in `home-modules/tools/i3_project_manager/core/window_rules.py`: extract_window_properties(container) → WindowProperties, extract_all_windows(conn) → List[WindowProperties] (from contracts/i3-ipc-patterns.md GET_TREE section) - **Async pattern adapted from i3-resurrect/treeutils.py:process_node() using i3ipc.aio**
- [ ] T010 [P] [Found] Add __init__.py exports for all new models in `home-modules/tools/i3_project_manager/models/__init__.py`

**Checkpoint**: Foundation ready - all core data models available, window property extraction working

---

## Phase 3: User Story 1 - Basic Application Launch and Window Detection (Priority: P1) 🎯 MVP

**Goal**: Automatically detect new windows and assign them to configured workspaces based on window class/title matching

**Independent Test**: Launch terminal application → window appears on workspace 1 within 500ms. Launch Firefox → window appears on workspace 3.

### Implementation for User Story 1

- [ ] T011 [P] [US1] Implement pattern matching functions in `home-modules/tools/i3_project_manager/core/window_rules.py`: match_exact(), match_regex(), match_wildcard() for string pattern matching - **Regex escaping pattern informed by i3-resurrect/treeutils.py swallow criteria (re.escape)**
- [ ] T012 [P] [US1] Implement match_criteria_matches() function in `home-modules/tools/i3_project_manager/core/window_rules.py` that evaluates MatchCriteria against WindowProperties (AND logic for multiple criteria) - **First-match semantics like i3-resurrect swallow criteria evaluation**
- [ ] T013 [US1] Implement find_matching_rule() function in `home-modules/tools/i3_project_manager/core/window_rules.py` that evaluates rules in priority order (project→global→default) and returns first match (depends on T011, T012)
- [ ] T014 [P] [US1] Implement load_window_rules() function in `home-modules/tools/i3_project_manager/core/window_rules.py` that loads and validates rules from JSON file using Pydantic models
- [ ] T015 [P] [US1] Create workspace assignment functions in `home-modules/tools/i3_project_manager/core/workspace_manager.py`: move_window_to_workspace(conn, container_id, workspace, focus), validate_target_workspace(conn, workspace) (from contracts/i3-ipc-patterns.md COMMAND section)
- [ ] T016 [P] [US1] Create window marking function mark_window(conn, window_id, mark) in `home-modules/tools/i3_project_manager/core/workspace_manager.py` (from contracts/i3-ipc-patterns.md COMMAND section)
- [ ] T017 [P] [US1] Create floating/layout functions in `home-modules/tools/i3_project_manager/core/workspace_manager.py`: set_window_floating(conn, container_id, enable), set_container_layout(conn, container_id, mode)
- [ ] T018 [US1] Implement apply_rule_actions() function in `home-modules/tools/i3_project_manager/core/window_rules.py` that executes all actions from matched rule (workspace, mark, float, layout) (depends on T015, T016, T017)
- [ ] T019 [US1] Add on_window_new() event handler in `home-modules/desktop/i3-project-event-daemon/daemon.py` that calls extract_window_properties → find_matching_rule → apply_rule_actions (depends on T009, T013, T018)
- [ ] T020 [US1] Subscribe to window::new events in daemon.py main() function (add conn.on("window::new", on_window_new))
- [ ] T021 [P] [US1] Create default rules configuration in ~/.config/i3/window-rules-default.json with rules for: Ghostty→WS1, Code→WS2, Firefox→WS3, YouTube PWA→WS4 (from quickstart.md examples)
- [ ] T022 [US1] Remove ALL static assign and for_window directives from `home-modules/desktop/i3.nix` (lines 39-76) per Constitution Principle XII - complete replacement, no backwards compatibility

**Checkpoint**: At this point, User Story 1 should be fully functional - windows are automatically assigned to workspaces based on configured rules

---

## Phase 4: User Story 2 - Project-Scoped Window Management (Priority: P2)

**Goal**: Windows can be marked as project-scoped and automatically shown/hidden when switching project contexts

**Independent Test**: Create project "NixOS" → launch terminal in project → switch to project "Stacks" → NixOS terminal hidden, Stacks windows visible

### Implementation for User Story 2

- [ ] T023 [P] [US2] Add get_active_project() function in `home-modules/tools/i3_project_manager/core/window_rules.py` that queries current project from existing i3pm state
- [ ] T024 [US2] Extend find_matching_rule() to prioritize project-scoped rules when active project exists (modify priority evaluation to check project first) in `home-modules/tools/i3_project_manager/core/window_rules.py`
- [ ] T025 [P] [US2] Add project mark generation in apply_rule_actions(): if rule.priority=="project" and active_project exists, add mark "project:{project_name}" in `home-modules/tools/i3_project_manager/core/window_rules.py`
- [ ] T026 [US2] Modify on_window_new() handler to query active project and pass to rule evaluation (depends on T023, T024)
- [ ] T027 [P] [US2] Add window visibility management function toggle_project_windows(conn, project_name, visible) in `home-modules/tools/i3_project_manager/core/workspace_manager.py` that finds all windows with mark "project:{project_name}" and shows/hides them
- [ ] T028 [US2] Add on_tick event handler in daemon.py for project switch events that calls toggle_project_windows() to hide old project windows and show new project windows
- [ ] T029 [P] [US2] Create project-scoped rules in window-rules-default.json for Ghostty (terminal), Code (editor), Lazygit, Yazi with priority="project"

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - basic window assignment works AND project-scoped management works

---

## Phase 5: User Story 3 - Multi-Monitor Workspace Distribution (Priority: P3)

**Goal**: Workspaces automatically redistribute across monitors when monitors are connected/disconnected

**Independent Test**: Connect second monitor → workspaces 3-9 move to second monitor within 2 seconds. Disconnect second monitor → all workspaces consolidate to primary monitor.

### Implementation for User Story 3

- [ ] T030 [P] [US3] Create MonitorConfig dataclass in `home-modules/tools/i3_project_manager/models/workspace.py` with fields: name, active, primary, current_workspace, width, height, x, y
- [ ] T031 [P] [US3] Implement get_monitor_configs() function in `home-modules/tools/i3_project_manager/core/monitor_manager.py` that queries GET_OUTPUTS and returns List[MonitorConfig]
- [ ] T032 [US3] Implement get_workspace_distribution_rule() function in `home-modules/tools/i3_project_manager/core/monitor_manager.py` that returns Dict[workspace_num, output_name] based on monitor count (1 monitor: all on primary, 2 monitors: WS 1-2 primary + WS 3-9 secondary, 3+ monitors: WS 1-2 primary + WS 3-5 secondary + WS 6-9 tertiary) (depends on T031)
- [ ] T033 [US3] Implement apply_workspace_distribution() function in `home-modules/tools/i3_project_manager/core/monitor_manager.py` that executes "workspace {num} output {output_name}" commands for each workspace (depends on T032)
- [ ] T034 [US3] Add on_output() event handler in daemon.py that calls get_monitor_configs → get_workspace_distribution_rule → apply_workspace_distribution
- [ ] T035 [US3] Subscribe to output events in daemon.py main() function (add conn.on("output", on_output))
- [ ] T036 [US3] Modify validate_target_workspace() in workspace_manager.py to check if target workspace is on active output before assignment (depends on T031)

**Checkpoint**: All user stories should now be independently functional - basic rules + project-scoped + multi-monitor all working

---

## Phase 6: User Story 4 - Application Rule Configuration (Priority: P3)

**Goal**: Users can define custom rules through JSON configuration files that are hot-reloaded without daemon restart

**Independent Test**: Create new rule for application → save window-rules.json → launch application → window assigned per new rule without restarting daemon

### Implementation for User Story 4

- [ ] T037 [P] [US4] Implement validate_window_rules() function in `home-modules/tools/i3_project_manager/cli/validate_rules.py` that loads rules file and validates against JSON schema, reports errors with line numbers
- [ ] T038 [P] [US4] Implement test_rule_match() function in `home-modules/tools/i3_project_manager/cli/test_rule.py` that takes window properties (class, title) and shows which rule would match
- [ ] T039 [P] [US4] Create CLI command `i3pm validate-rules` that calls validate_window_rules() and displays validation results
- [ ] T040 [P] [US4] Create CLI command `i3pm test-rule --class=Firefox --title="GitHub"` that calls test_rule_match() and shows matched rule + actions
- [ ] T041 [US4] Implement watch_rules_file() function in `home-modules/tools/i3_project_manager/core/window_rules.py` using inotify/watchdog to detect changes to window-rules.json
- [ ] T042 [US4] Add on_rules_file_changed() handler in daemon.py that calls load_window_rules() to reload rules when file changes (depends on T041)
- [ ] T043 [US4] Add rules reload timestamp tracking and logging in daemon to confirm hot-reload working
- [ ] T044 [P] [US4] Update quickstart.md with examples of creating rules, using validate-rules and test-rule commands, and testing hot-reload

**Checkpoint**: All user stories should be complete and independently testable

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final integration

- [ ] T045 [P] [Polish] Add comprehensive error handling with clear error messages for: invalid rule syntax, missing window properties, i3 IPC connection failures in window_rules.py
- [ ] T046 [P] [Polish] Add logging throughout window_rules.py and workspace_manager.py with appropriate log levels (DEBUG: rule evaluation, INFO: window assignment, WARNING: validation failures, ERROR: i3 IPC errors)
- [ ] T047 [P] [Polish] Create state restoration function restore_daemon_state() in daemon.py that calls extract_all_windows() on startup and validates marks against filesystem project state
- [ ] T048 [Polish] Add on_window_close() event handler in daemon.py for cleanup tracking (remove from internal state if maintained)
- [ ] T049 [P] [Polish] Update ~/.config/i3/scripts/launch-*.sh launcher scripts to work with dynamic rules (remove any hardcoded workspace assignments)
- [ ] T050 [P] [Polish] Add performance monitoring: log rule evaluation time, window detection latency, track stats for SC-003 validation (<50ms rule eval, <100ms window detection)
- [ ] T051 [Polish] Run complete workflow validation from quickstart.md: create rules → validate → launch apps → verify assignment → test hot-reload → check multi-monitor
- [ ] T052 [Polish] NixOS dry-build and switch: sudo nixos-rebuild dry-build --flake .#hetzner && sudo nixos-rebuild switch --flake .#hetzner

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion - No dependencies on other stories
- **User Story 2 (Phase 4)**: Depends on Foundational phase completion - Builds on US1 rule engine but can be implemented independently
- **User Story 3 (Phase 5)**: Depends on Foundational phase completion - Fully independent of US1/US2, can be implemented in parallel
- **User Story 4 (Phase 6)**: Depends on Foundational phase completion - Fully independent of US1/US2/US3, can be implemented in parallel
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Reuses US1's rule engine but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Fully independent, can be parallelized
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Fully independent, can be parallelized

### Within Each User Story

- Models before services (dataclasses/Pydantic models first)
- Core logic before integration (rule matching before event handlers)
- Event handlers before subscription (implement handler before conn.on())
- i3.nix changes LAST (remove static config after dynamic is working)

### Parallel Opportunities

- All Setup tasks (T001-T003) can run in parallel
- All Foundational model tasks (T004-T008) can run in parallel
- Window property extraction (T009) can run parallel with models
- Within US1: Pattern matching (T011), match criteria (T012) parallel; workspace functions (T015-T017) all parallel
- Once Foundational complete: US2, US3, US4 can be implemented in parallel by different developers
- All Polish tasks except T051-T052 can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# Launch all foundational model tasks together:
Task: "Create WindowProperties dataclass in models/window_properties.py"
Task: "Create MatchCriteria Pydantic model in models/window_rule.py"
Task: "Create RuleAction discriminated union types in models/rule_action.py"
Task: "Create RuleMatchResult dataclass in models/window_rule.py"
Task: "Create window property extraction functions in core/window_rules.py"
```

## Parallel Example: User Story 1

```bash
# After foundational complete, these US1 tasks can run in parallel:
Task: "Implement pattern matching functions (match_exact, match_regex, match_wildcard)"
Task: "Create workspace assignment functions (move_window_to_workspace, validate_target_workspace)"
Task: "Create window marking function mark_window()"
Task: "Create floating/layout functions"
Task: "Create default rules configuration in window-rules-default.json"
```

## Parallel Example: Multi-Story Development

```bash
# After Foundational phase, multiple stories can be developed in parallel:
Developer A: Implements User Story 2 (Project-Scoped Management) - T023-T029
Developer B: Implements User Story 3 (Multi-Monitor Distribution) - T030-T036
Developer C: Implements User Story 4 (Rule Configuration CLI) - T037-T044
# All three can work independently without blocking each other
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T010) - CRITICAL BLOCKER
3. Complete Phase 3: User Story 1 (T011-T022)
4. **STOP and VALIDATE**: Test basic window assignment independently
5. Deploy/demo if ready - basic functionality working

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (T001-T010)
2. Add User Story 1 → Test independently → Deploy/Demo (T011-T022) - **MVP!**
3. Add User Story 2 → Test independently → Deploy/Demo (T023-T029) - Project-scoped management
4. Add User Story 3 → Test independently → Deploy/Demo (T030-T036) - Multi-monitor support
5. Add User Story 4 → Test independently → Deploy/Demo (T037-T044) - User configuration
6. Polish and finalize → Complete feature (T045-T052)

Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T010)
2. Once Foundational is done:
   - Developer A: User Story 1 (T011-T022) - MVP priority
   - Developer B: User Story 3 (T030-T036) - Can start immediately, independent
   - Developer C: User Story 4 (T037-T044) - Can start immediately, independent
3. After US1 complete:
   - Developer A switches to: User Story 2 (T023-T029) - Builds on US1
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies - can be executed in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Constitution Principle XII: T022 completely removes static i3 config - no backwards compatibility
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Total task count: 52 tasks across 7 phases
- MVP scope: Phases 1-3 (T001-T022) = 22 tasks for basic functionality
- Full feature: All 52 tasks for complete dynamic window management

**Task Distribution by Story**:
- Setup: 3 tasks
- Foundational: 7 tasks (BLOCKS all stories)
- User Story 1 (P1 - MVP): 12 tasks
- User Story 2 (P2): 7 tasks
- User Story 3 (P3): 7 tasks
- User Story 4 (P3): 8 tasks
- Polish: 8 tasks

**Parallel Opportunities**:
- 28 tasks marked [P] can execute in parallel within their phase
- 3 user stories (US2, US3, US4) can be developed in parallel after Foundational
- Estimated parallelization: ~40% reduction in sequential time with 3 developers
