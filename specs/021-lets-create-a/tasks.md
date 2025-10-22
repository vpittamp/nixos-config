# Tasks: Dynamic Window Management System

**Input**: Design documents from `/specs/021-lets-create-a/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED - Feature spec requests comprehensive testing (pytest, >80% coverage, scenario tests per user story)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Daemon: `home-modules/desktop/i3-project-event-daemon/`
- i3pm CLI/TUI: `home-modules/tools/i3_project_manager/`
- Tests: `tests/i3_project_manager/`
- Configs: `~/.config/i3/` (runtime, not in repo)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and test infrastructure

- [X] T001 [P] Create test directory structure: `tests/i3_project_manager/{unit,integration,scenarios,fixtures}/`
- [X] T002 [P] Create pytest configuration in `tests/pytest.ini` with async support (pytest-asyncio)
- [X] T003 [P] Create test fixtures for mock i3 IPC in `tests/i3_project_manager/fixtures/mock_i3_ipc.py`
- [X] T004 [P] Create test fixtures for mock daemon in `tests/i3_project_manager/fixtures/mock_daemon.py`
- [X] T005 [P] Create sample test data in `tests/i3_project_manager/fixtures/sample_configs.py` (window-rules.json, workspace-config.json examples)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models and infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Data Models (Shared by All Stories)

- [X] T006 [P] [Foundation] Create WorkspaceConfig model in `home-modules/tools/i3_project_manager/models/workspace.py`
  - Fields: number, name, icon, default_output_role
  - Validation: workspace 1-9, output_role enum
  - JSON serialization methods

- [X] T007 [P] [Foundation] Create WindowRule model in `home-modules/desktop/i3-project-event-daemon/window_rules.py`
  - Fields: pattern_rule (PatternRule), workspace, command, modifier, blacklist
  - Reuses existing PatternRule from `models/pattern.py`
  - Validation: workspace 1-9, modifier enum, blacklist only with GLOBAL

- [X] T008 [P] [Foundation] Create Classification model in `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py`
  - Fields: scope, workspace, source, matched_rule
  - Source attribution for debugging (project, window_rule, app_classes, default)

- [X] T009 [P] [Foundation] Create MonitorConfig model in `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
  - Fields: name, rect, active, primary, role
  - from_i3_output() class method for conversion from i3ipc.aio.OutputReply

### Config Loaders (Shared Infrastructure)

- [X] T010 [Foundation] Implement load_window_rules() in `home-modules/desktop/i3-project-event-daemon/window_rules.py`
  - Load from `~/.config/i3/window-rules.json`
  - Parse JSON to list of WindowRule objects
  - Validation with error messages
  - Return empty list if file doesn't exist
  - Depends on T007

- [X] T011 [P] [Foundation] Implement load_workspace_config() in `home-modules/tools/i3_project_manager/models/workspace.py`
  - Load from `~/.config/i3/workspace-config.json`
  - Parse JSON to list of WorkspaceConfig objects
  - Validation with error messages
  - Return defaults if file doesn't exist

- [X] T012 [Foundation] Enhance AppClassification.from_json() in `home-modules/tools/i3_project_manager/core/models.py`
  - Support both Dict[str, str] and List[PatternRule] for class_patterns field
  - Automatic conversion: dict → List[PatternRule] with priority 100
  - Backward compatibility with existing app-classes.json files
  - Unit test for both formats

### Unit Tests for Foundation

- [X] T013 [P] [Foundation] Unit test for WorkspaceConfig in `tests/i3_project_manager/unit/test_workspace_config.py`
  - Test validation (workspace 1-9, output_role enum)
  - Test JSON serialization/deserialization
  - Test default values

- [X] T014 [P] [Foundation] Unit test for WindowRule in `tests/i3_project_manager/unit/test_window_rules.py`
  - Test pattern_rule integration
  - Test validation (workspace 1-9, modifier enum, blacklist logic)
  - Test matches() method
  - Test priority property

- [X] T015 [P] [Foundation] Unit test for Classification in `tests/i3_project_manager/unit/test_classification.py`
  - Test all source types
  - Test workspace validation
  - Test scope validation

- [X] T016 [P] [Foundation] Unit test for AppClassification enhancement in `tests/i3_project_manager/unit/test_app_classification.py`
  - Test dict format loading (backward compatibility)
  - Test List[PatternRule] format loading
  - Test automatic conversion dict → PatternRule list
  - Test priority assignment (100 for converted patterns)

**Checkpoint**: Foundation models ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Pattern-Based Window Classification Without Rebuilds (Priority: P1) 🎯 MVP

**Goal**: Enable dynamic window classification via `~/.config/i3/window-rules.json` without NixOS rebuilds

**Independent Test**: Modify window-rules.json, launch window, verify classification without rebuild (<1 second reload)

### Tests for User Story 1

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T017 [P] [US1] Unit test for classify_window() in `tests/i3_project_manager/unit/test_pattern_resolver.py`
  - Test 4-level precedence: project (1000) > window-rules (200-500) > app-classes patterns (100) > app-classes lists (50)
  - Test source attribution for each level
  - Test short-circuit evaluation (first match wins)

- [X] T018 [P] [US1] Unit test for PatternMatcher reuse in `tests/i3_project_manager/unit/test_pattern_matcher.py`
  - Verify existing PatternMatcher works with WindowRule
  - Test LRU cache with 100+ rules
  - Test performance <1ms cached, <10ms uncached

- [X] T019 [P] [US1] Integration test for config reload in `tests/i3_project_manager/integration/test_config_reload.py`
  - Test file watch detection (watchdog)
  - Test reload trigger <1 second after file modification
  - Test invalid JSON handled gracefully (retain previous config)
  - Test daemon keeps running on config error

- [X] T020 [P] [US1] Scenario test for dynamic reload in `tests/i3_project_manager/scenarios/test_dynamic_reload.py`
  - Test full workflow: modify rule → reload → launch window → verify classification
  - Test no rebuild required
  - Test from quickstart.md US1 scenario

### Implementation for User Story 1

- [X] T021 [US1] Implement classify_window() in `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py`
  - 4-level precedence algorithm (project > window-rules > app-classes patterns > app-classes lists)
  - Short-circuit evaluation (early return)
  - Source attribution (Classification object with source field)
  - Depends on T008

- [X] T022 [P] [US1] Implement file watch for window-rules.json in `home-modules/desktop/i3-project-event-daemon/config.py`
  - Use watchdog library for cross-platform file monitoring
  - Detect modifications to `~/.config/i3/window-rules.json`
  - Trigger reload on modification
  - Debounce rapid changes (100ms timeout)

- [X] T023 [US1] Integrate classify_window() into window event handler in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - Call classify_window() on window::new event
  - Pass active project from daemon state
  - Apply classification result (scope, workspace)
  - Depends on T021

- [X] T024 [US1] Add reload_window_rules() method in `home-modules/desktop/i3-project-event-daemon/config.py`
  - Validate JSON before applying
  - Retain previous config on error
  - Log reload success/failure
  - Desktop notification on error
  - Depends on T010

- [X] T025 [P] [US1] Add daemon IPC method get_window_rules in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - JSON-RPC method: get_window_rules
  - Filter by scope parameter
  - Return rules list + count
  - Contract: `contracts/daemon-ipc-extensions.json`

- [X] T026 [P] [US1] Add daemon IPC method classify_window in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - JSON-RPC method: classify_window
  - Parameters: window_class, window_title, project_name
  - Return Classification object
  - Contract: `contracts/daemon-ipc-extensions.json`

- [X] T027 [P] [US1] Add CLI command `i3pm rules` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - List all window rules
  - Filter by scope (--scoped, --global, --all)
  - Show pattern, priority, workspace
  - Call get_window_rules IPC method

- [X] T028 [P] [US1] Add CLI command `i3pm classify` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - Debug window classification
  - Parameters: --window-class, --window-title, --project
  - Show matched rule, source, priority
  - Call classify_window IPC method

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Firefox PWA Detection and Classification (Priority: P1)

**Goal**: Enable PWA detection via title patterns (FFPWA-* class + title matching)

**Independent Test**: Launch Firefox PWA, verify title-based classification and workspace assignment

### Tests for User Story 2

- [ ] T029 [P] [US2] Unit test for PWA pattern matching in `tests/i3_project_manager/unit/test_pwa_patterns.py`
  - Test `glob:FFPWA-*` pattern matching
  - Test `pwa:YouTube` title pattern (special syntax)
  - Test title pattern priority over class pattern

- [ ] T030 [P] [US2] Scenario test for PWA detection in `tests/i3_project_manager/scenarios/test_pwa_detection.py`
  - Test YouTube PWA classification
  - Test multiple PWAs with different titles
  - Test title change re-evaluation
  - Test from quickstart.md US2 scenario

### Implementation for User Story 2

- [ ] T031 [P] [US2] Add PWA pattern type support in `home-modules/tools/i3_project_manager/models/pattern.py`
  - Extend _parse_pattern() to recognize `pwa:` prefix
  - pwa:YouTube → matches FFPWA-* class AND title contains "YouTube"
  - Keep existing frozen dataclass (add new pattern type handling)

- [ ] T032 [US2] Extend classify_window() for title matching in `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py`
  - Accept window_title parameter
  - Check title patterns when pattern_type is "title" or "pwa"
  - Test title patterns for PWAs and terminal apps
  - Depends on T021

- [ ] T033 [US2] Subscribe to window::title events in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - Handle window::title change events
  - Re-evaluate classification when title changes
  - Debounce rapid title changes (500ms timeout per FR-025)
  - Move window if workspace changes

- [ ] T034 [P] [US2] Add example PWA rules to template in `home-modules/desktop/i3-project-event-daemon/window_rules_template.json`
  - YouTube PWA example
  - Google AI PWA example
  - Generic FFPWA-* pattern

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Terminal Application Detection (Priority: P1)

**Goal**: Enable terminal app detection via title patterns (ghostty with custom titles)

**Independent Test**: Launch ghostty with "Yazi: /path" title, verify different classification than plain ghostty

### Tests for User Story 3

- [ ] T035 [P] [US3] Unit test for title pattern matching in `tests/i3_project_manager/unit/test_title_patterns.py`
  - Test `title:^Yazi:.*` regex pattern
  - Test `title:^lazygit` pattern
  - Test title pattern priority over class pattern

- [ ] T036 [P] [US3] Scenario test for terminal classification in `tests/i3_project_manager/scenarios/test_terminal_classification.py`
  - Test yazi in ghostty (title "Yazi: /path")
  - Test plain ghostty (no custom title)
  - Test lazygit in ghostty
  - Test from quickstart.md US3 scenario

### Implementation for User Story 3

- [ ] T037 [P] [US3] Add title pattern examples to template in `home-modules/desktop/i3-project-event-daemon/window_rules_template.json`
  - Yazi file manager pattern
  - lazygit pattern
  - k9s pattern
  - Plain terminal fallback

- [ ] T038 [P] [US3] Update classify_window() tests in `tests/i3_project_manager/unit/test_pattern_resolver.py`
  - Add test cases for title-based terminal app classification
  - Verify priority ordering (title pattern > class pattern)

**Checkpoint**: All P1 user stories should now be independently functional (MVP complete!)

---

## Phase 6: User Story 4 - Dynamic Workspace-to-Monitor Assignment (Priority: P2)

**Goal**: Auto-redistribute workspaces across 1-3 monitors based on connection/disconnection

**Independent Test**: Connect/disconnect monitor, verify workspace redistribution (<500ms)

### Tests for User Story 4

- [ ] T039 [P] [US4] Unit test for monitor detection in `tests/i3_project_manager/unit/test_workspace_manager.py`
  - Test GET_OUTPUTS query parsing
  - Test monitor role assignment (primary, secondary, tertiary)
  - Test 1/2/3 monitor distribution rules

- [ ] T040 [P] [US4] Unit test for workspace assignment in `tests/i3_project_manager/unit/test_workspace_manager.py`
  - Test 1 monitor: all WS on primary
  - Test 2 monitors: WS 1-2 primary, 3-9 secondary
  - Test 3+ monitors: WS 1-2 primary, 3-5 secondary, 6-9 tertiary

- [ ] T041 [P] [US4] Integration test for i3 IPC queries in `tests/i3_project_manager/integration/test_i3_ipc_workspace.py`
  - Mock i3 GET_OUTPUTS response
  - Mock i3 RUN_COMMAND for workspace assignment
  - Test actual i3 IPC message formats

- [ ] T042 [P] [US4] Scenario test for monitor redistribution in `tests/i3_project_manager/scenarios/test_monitor_redistribution.py`
  - Test 1→2 monitor transition
  - Test 2→1 monitor transition
  - Test performance <500ms
  - Test from quickstart.md US4 scenario

### Implementation for User Story 4

- [ ] T043 [US4] Implement get_monitor_configs() in `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
  - Query i3 GET_OUTPUTS
  - Filter active outputs
  - Assign roles (primary, secondary, tertiary) based on count and primary flag
  - Returns List[MonitorConfig]
  - Depends on T009

- [ ] T044 [US4] Implement assign_workspaces_to_monitors() in `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
  - Distribution logic: 1/2/3 monitor rules
  - Execute i3 RUN_COMMAND: `workspace N output <name>`
  - Performance target <500ms for all 9 workspaces
  - Depends on T043

- [ ] T045 [US4] Subscribe to output events in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - Handle output event (monitor connect/disconnect)
  - Call get_monitor_configs() to detect change
  - Call assign_workspaces_to_monitors() to redistribute
  - Log redistribution activity

- [ ] T046 [US4] Integrate project workspace_preferences in `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
  - Check active project's workspace_preferences
  - Override global assignment for specified workspaces
  - Map output_role to actual output name
  - Depends on T044

- [ ] T047 [P] [US4] Add daemon IPC method get_monitor_config in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - JSON-RPC method: get_monitor_config
  - Query i3 outputs in real-time (no caching)
  - Return List[MonitorConfig] + count
  - Contract: `contracts/daemon-ipc-extensions.json`

- [ ] T048 [P] [US4] Add CLI command `i3pm monitor-config` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - Show current monitor configuration
  - Show workspace assignments per monitor
  - Call get_monitor_config IPC method

**Checkpoint**: Multi-monitor support fully functional

---

## Phase 7: User Story 5 - Workspace Metadata with Names and Icons (Priority: P3)

**Goal**: Add workspace names and icons for display in i3bar

**Independent Test**: Configure workspace with name/icon, verify i3bar displays it

### Tests for User Story 5

- [ ] T049 [P] [US5] Unit test for workspace config loading in `tests/i3_project_manager/unit/test_workspace_config.py`
  - Test workspace-config.json parsing
  - Test defaults if file doesn't exist
  - Test validation (workspace 1-9)

- [ ] T050 [P] [US5] Scenario test for workspace metadata in `tests/i3_project_manager/scenarios/test_workspace_metadata.py`
  - Test workspace name display
  - Test workspace icon display
  - Test from quickstart.md US5 scenario

### Implementation for User Story 5

- [ ] T051 [P] [US5] Add daemon IPC method get_workspace_config in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - JSON-RPC method: get_workspace_config
  - Optional workspace_number filter
  - Return List[WorkspaceConfig] + count
  - Contract: `contracts/daemon-ipc-extensions.json`

- [ ] T052 [P] [US5] Add CLI command `i3pm workspace-config` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - Show workspace names and icons
  - Show default output roles
  - Call get_workspace_config IPC method

- [ ] T053 [P] [US5] Create example workspace-config.json template in `home-modules/desktop/i3-project-event-daemon/workspace_config_template.json`
  - All 9 workspaces with default names and icons
  - Output role assignments
  - Used for initial setup

**Checkpoint**: Workspace metadata available via daemon and CLI

---

## Phase 8: User Story 6 - i3king-Style Rule Syntax with Variables (Priority: P3)

**Goal**: Support advanced rule modifiers (GLOBAL, DEFAULT, ON_CLOSE) and variable substitution

**Independent Test**: Create ON_CLOSE rule with notification, close window, verify notification

### Tests for User Story 6

- [ ] T054 [P] [US6] Unit test for GLOBAL modifier in `tests/i3_project_manager/unit/test_rule_modifiers.py`
  - Test GLOBAL rule matches all windows
  - Test blacklist exclusion logic
  - Test GLOBAL priority

- [ ] T055 [P] [US6] Unit test for DEFAULT modifier in `tests/i3_project_manager/unit/test_rule_modifiers.py`
  - Test DEFAULT rule triggers when no match
  - Test DEFAULT doesn't trigger when rule matches

- [ ] T056 [P] [US6] Unit test for ON_CLOSE modifier in `tests/i3_project_manager/unit/test_rule_modifiers.py`
  - Test ON_CLOSE rule triggers on window::close
  - Test ON_CLOSE doesn't trigger on window::new

- [ ] T057 [P] [US6] Unit test for variable substitution in `tests/i3_project_manager/unit/test_variable_substitution.py`
  - Test $CLASS, $INSTANCE, $TITLE substitution
  - Test $CONID, $WINID, $ROLE, $TYPE substitution
  - Test command execution with substituted variables

### Implementation for User Story 6

- [ ] T058 [US6] Implement GLOBAL modifier logic in `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py`
  - GLOBAL matches all windows
  - Check blacklist before matching
  - Low priority (evaluated last)
  - Depends on T021

- [ ] T059 [US6] Implement DEFAULT modifier logic in `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py`
  - DEFAULT only triggers when no other rule matches
  - Lowest priority
  - Depends on T021

- [ ] T060 [US6] Subscribe to window::close events in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - Handle window::close event
  - Check for ON_CLOSE rules matching closed window
  - Execute rule commands
  - Depends on T059

- [ ] T061 [US6] Implement variable substitution in `home-modules/desktop/i3-project-event-daemon/window_rules.py`
  - substitute_variables() function
  - Replace $CLASS, $INSTANCE, $TITLE, $CONID, $WINID, $ROLE, $TYPE
  - Extract values from i3 window object
  - Used when executing rule commands

- [ ] T062 [US6] Execute rule commands in `home-modules/desktop/i3-project-event-daemon/handlers.py`
  - When rule has command field, execute it
  - Apply variable substitution before execution
  - Use i3 RUN_COMMAND for i3 commands
  - Use subprocess for shell commands
  - Depends on T061

- [ ] T063 [P] [US6] Add advanced rule examples to template in `home-modules/desktop/i3-project-event-daemon/window_rules_template.json`
  - GLOBAL rule example
  - DEFAULT rule example
  - ON_CLOSE rule example
  - Variable substitution examples

**Checkpoint**: All user stories should now be independently functional

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

### CLI Enhancements

- [ ] T064 [P] [Polish] Add daemon IPC method reload_window_rules in `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - JSON-RPC method: reload_window_rules
  - Manual trigger for config reload
  - Return success + rule counts
  - Contract: `contracts/daemon-ipc-extensions.json`

- [ ] T065 [P] [Polish] Add CLI command `i3pm reload-rules` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - Manual trigger for window rules reload
  - Show reload status and rule counts
  - Call reload_window_rules IPC method

- [ ] T066 [P] [Polish] Add CLI command `i3pm migrate-rules` in `home-modules/tools/i3_project_manager/cli/commands.py`
  - Parse existing i3.nix static rules
  - Generate equivalent window-rules.json
  - Backup original i3.nix
  - Validate generated JSON

### Documentation & Examples

- [ ] T067 [P] [Polish] Create window-rules.json template in `home-modules/desktop/i3-project-event-daemon/window_rules_template.json`
  - Basic examples for all pattern types
  - PWA examples (YouTube, Google AI)
  - Terminal app examples (yazi, lazygit)
  - Advanced examples (GLOBAL, DEFAULT, ON_CLOSE)

- [ ] T068 [P] [Polish] Create example configs via home-manager in `home-modules/desktop/i3-project-event-daemon/default.nix`
  - Install window_rules_template.json to `~/.config/i3/window-rules.example.json`
  - Install workspace_config_template.json to `~/.config/i3/workspace-config.example.json`
  - User can copy .example.json to .json to activate

- [ ] T069 [P] [Polish] Create user documentation in `docs/WINDOW_RULES.md`
  - Quick start guide
  - Pattern syntax reference
  - Rule modifiers explanation
  - Migration from static rules
  - Troubleshooting common issues

### Static Rule Removal

- [ ] T070 [Polish] Remove static window rules from `home-modules/desktop/i3.nix` (lines 34-69)
  - Remove all `assign` directives
  - Remove all `for_window` workspace assignments
  - Keep non-rule i3 config (keybindings, workspace names, etc.)
  - Add comment: "Window rules now managed via ~/.config/i3/window-rules.json"

### Performance & Monitoring

- [ ] T071 [P] [Polish] Add performance metrics to daemon in `home-modules/desktop/i3-project-event-daemon/daemon.py`
  - Track classification time per window
  - Track config reload time
  - Track workspace reassignment time
  - Expose via daemon IPC

- [ ] T072 [P] [Polish] Add cache statistics to PatternMatcher in `home-modules/tools/i3_project_manager/core/pattern_matcher.py`
  - Expose get_cache_info() via daemon IPC
  - Show hits, misses, hit rate
  - CLI command to display cache stats

### Additional Unit Tests

- [ ] T073 [P] [Polish] Unit test for config reload with errors in `tests/i3_project_manager/unit/test_config_error_handling.py`
  - Test invalid JSON syntax
  - Test invalid pattern syntax
  - Test previous config retained on error
  - Test desktop notification sent

- [ ] T074 [P] [Polish] Unit test for event debouncing in `tests/i3_project_manager/unit/test_event_debouncing.py`
  - Test title change debouncing (500ms)
  - Test config reload debouncing (100ms)
  - Test rapid events don't cause thrashing

- [ ] T075 [P] [Polish] Unit test for i3 restart handling in `tests/i3_project_manager/unit/test_i3_restart.py`
  - Test event re-subscription after i3 restart
  - Test rules re-applied to existing windows
  - Test daemon continues running

### Integration with Existing Features

- [ ] T076 [P] [Polish] Extend TUI browser screen in `home-modules/tools/i3_project_manager/tui/screens/browser.py`
  - Show window rule count in status bar
  - Show active window rules for selected project
  - Link to rule management (future enhancement)

- [ ] T077 [P] [Polish] Extend TUI monitor screen in `home-modules/tools/i3_project_manager/tui/screens/monitor.py`
  - Show workspace metadata (names, icons)
  - Show workspace-to-monitor assignments
  - Show monitor configuration

### Validation & Testing

- [ ] T078 [P] [Polish] Run quickstart validation in `specs/021-lets-create-a/quickstart.md`
  - Run all US1-US5 test scenarios
  - Verify all acceptance criteria
  - Document any deviations

- [ ] T079 [P] [Polish] Run full test suite with coverage
  - Execute: `pytest tests/i3_project_manager/ --cov --cov-report=html`
  - Verify >80% coverage target
  - Review coverage report, add tests for gaps

- [ ] T080 [P] [Polish] Performance benchmark tests in `tests/i3_project_manager/integration/test_performance.py`
  - Benchmark classification time <1ms (100+ rules)
  - Benchmark config reload time <100ms
  - Benchmark workspace reassignment <500ms
  - Benchmark memory usage <20MB additional

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - US1, US2, US3 (P1 stories) can proceed in parallel after Foundation
  - US4 (P2) can proceed in parallel with P1 stories
  - US5, US6 (P3 stories) can proceed in parallel with earlier stories
- **Polish (Phase 9)**: Depends on desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - Enhances US1 classify_window() but independently testable
- **User Story 3 (P1)**: Can start after Foundational (Phase 2) - Uses same classify_window() as US1/US2, independently testable
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - Independent workspace management, no dependency on US1-3
- **User Story 5 (P3)**: Can start after Foundational (Phase 2) - Adds metadata, no dependency on classification
- **User Story 6 (P3)**: Depends on US1 classify_window() - Extends pattern_resolver.py with modifiers

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before integration
- Core implementation before enhancements
- Story complete before moving to next priority

### Parallel Opportunities

**Setup (Phase 1)**:
- T001, T002, T003, T004, T005 - All parallel (different files)

**Foundational (Phase 2)**:
- T006, T007, T008, T009 - Models parallel (different files)
- T011 parallel with T010
- T013, T014, T015, T016 - Unit tests parallel (different files)

**User Story 1 (Phase 3)**:
- T017, T018, T019, T020 - Tests parallel
- T022, T025, T026, T027, T028 - CLI/IPC parallel (different files)

**User Story 2 (Phase 4)**:
- T029, T030 - Tests parallel
- T031, T034 - Parallel (different files)

**User Story 3 (Phase 5)**:
- T035, T036 - Tests parallel
- T037, T038 - Parallel (different files)

**User Story 4 (Phase 6)**:
- T039, T040, T041, T042 - Tests parallel
- T047, T048 - CLI/IPC parallel

**User Story 5 (Phase 7)**:
- T049, T050 - Tests parallel
- T051, T052, T053 - All parallel (different files)

**User Story 6 (Phase 8)**:
- T054, T055, T056, T057 - Tests parallel
- T063 parallel with other implementation tasks

**Polish (Phase 9)**:
- T064, T065, T066 - CLI parallel
- T067, T068, T069 - Docs parallel
- T071, T072 - Monitoring parallel
- T073, T074, T075 - Tests parallel
- T076, T077 - TUI parallel
- T078, T079, T080 - Validation parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together (write these FIRST):
Task T017: "Unit test for classify_window() in tests/unit/test_pattern_resolver.py"
Task T018: "Unit test for PatternMatcher reuse in tests/unit/test_pattern_matcher.py"
Task T019: "Integration test for config reload in tests/integration/test_config_reload.py"
Task T020: "Scenario test for dynamic reload in tests/scenarios/test_dynamic_reload.py"

# After tests written and failing, launch parallel implementation tasks:
Task T022: "Implement file watch for window-rules.json in config.py"
Task T025: "Add daemon IPC method get_window_rules in ipc_server.py"
Task T026: "Add daemon IPC method classify_window in ipc_server.py"
Task T027: "Add CLI command i3pm rules in commands.py"
Task T028: "Add CLI command i3pm classify in commands.py"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only - All P1)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T016) - CRITICAL, blocks everything
3. Complete Phase 3: User Story 1 (T017-T028)
4. **STOP and VALIDATE**: Test US1 independently via quickstart.md
5. Complete Phase 4: User Story 2 (T029-T034)
6. **STOP and VALIDATE**: Test US2 independently
7. Complete Phase 5: User Story 3 (T035-T038)
8. **STOP and VALIDATE**: Test US3 independently
9. **MVP READY**: All P1 stories complete, deploy/demo possible

### Incremental Delivery

1. Complete Setup + Foundational (T001-T016) → Foundation ready
2. Add User Story 1 (T017-T028) → Test independently → Basic window rules working
3. Add User Story 2 (T029-T034) → Test independently → PWA support added
4. Add User Story 3 (T035-T038) → Test independently → Terminal app support added
5. **MVP Deploy**: All P1 features working
6. Add User Story 4 (T039-T048) → Multi-monitor support
7. Add User Story 5 (T049-T053) → Workspace metadata
8. Add User Story 6 (T054-T063) → Advanced rule syntax
9. **Full Feature Deploy**: All stories complete
10. Polish (T064-T080) → Production-ready

### Parallel Team Strategy

With multiple developers (after Foundation complete):

1. Team completes Setup + Foundational together (T001-T016)
2. Once Foundational is done:
   - **Developer A**: User Story 1 (T017-T028) - Basic classification
   - **Developer B**: User Story 2 (T029-T034) - PWA detection (extends A's work)
   - **Developer C**: User Story 4 (T039-T048) - Multi-monitor (independent)
   - **Developer D**: User Story 5 (T049-T053) - Workspace metadata (independent)
3. Developers integrate and test stories independently
4. User Story 6 starts after US1 complete (T054-T063)
5. All developers collaborate on Polish (T064-T080)

---

## Task Summary

**Total Tasks**: 80

**By Phase**:
- Phase 1 (Setup): 5 tasks
- Phase 2 (Foundational): 11 tasks
- Phase 3 (US1 - P1): 12 tasks
- Phase 4 (US2 - P1): 6 tasks
- Phase 5 (US3 - P1): 4 tasks
- Phase 6 (US4 - P2): 10 tasks
- Phase 7 (US5 - P3): 5 tasks
- Phase 8 (US6 - P3): 10 tasks
- Phase 9 (Polish): 17 tasks

**By User Story**:
- Foundation: 11 tasks (blocking)
- US1: 12 tasks (MVP core)
- US2: 6 tasks (MVP PWA)
- US3: 4 tasks (MVP terminal)
- US4: 10 tasks (multi-monitor)
- US5: 5 tasks (metadata)
- US6: 10 tasks (advanced syntax)

**Parallel Opportunities**: 45 tasks marked [P] can run in parallel with other tasks

**Suggested MVP Scope**: Phases 1-5 (Setup + Foundation + US1 + US2 + US3) = 38 tasks

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Foundation phase (T006-T016) is CRITICAL and blocks all user stories
- Tests are INCLUDED per feature spec requirement (pytest, >80% coverage, scenario tests)
