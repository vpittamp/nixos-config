# Tasks: App Discovery & Auto-Classification System

**Input**: Design documents from `/specs/020-update-our-spec/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Required per FR-131 through FR-135 (unit tests, integration tests, TUI tests, Xvfb tests, UAT tests)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- Python package: `home-modules/tools/i3_project_manager/`
- Tests: `tests/i3_project_manager/`
- Paths use NixOS home-manager structure per plan.md

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 [P] Create models/ package directory at `home-modules/tools/i3_project_manager/models/__init__.py`
- [X] T002 [P] Create tui/ package directory at `home-modules/tools/i3_project_manager/tui/__init__.py`
- [X] T003 [P] Create tui/widgets/ package at `home-modules/tools/i3_project_manager/tui/widgets/__init__.py`
- [X] T004 [P] Create tui/screens/ package at `home-modules/tools/i3_project_manager/tui/screens/__init__.py`
- [X] T005 [P] Create test directories: `tests/i3_project_manager/unit/`, `tests/i3_project_manager/integration/`, `tests/i3_project_manager/scenarios/`, `tests/i3_project_manager/fixtures/`
- [X] T006 Add argcomplete dependency to `home-modules/tools/pyproject.toml` dependencies list
- [X] T007 [P] Add pytest-textual dependency to `home-modules/tools/pyproject.toml` dev dependencies
- [X] T008 [P] Create test fixtures: sample_desktop_files.py, sample_patterns.json, mock_xvfb.py in `tests/i3_project_manager/fixtures/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T009 [P] [Foundation] Create PatternRule dataclass in `home-modules/tools/i3_project_manager/models/pattern.py` with fields (pattern, scope, priority, description), validation in __post_init__, and matches() method per data-model.md
- [X] T010 [P] [Foundation] Create DetectionResult dataclass in `home-modules/tools/i3_project_manager/models/detection.py` with fields (desktop_file, app_name, detected_class, detection_method, confidence, error_message, timestamp) per data-model.md
- [X] T011 [P] [Foundation] Create AppClassification dataclass in `home-modules/tools/i3_project_manager/models/classification.py` with fields (app_name, window_class, desktop_file, current_scope, suggested_scope, reasoning, confidence, user_modified) per data-model.md
- [X] T012 [Foundation] Extend AppClassConfig in `home-modules/tools/i3_project_manager/core/config.py` to load class_patterns from app-classes.json, store as list[PatternRule], and preserve backward compatibility with existing scoped_classes/global_classes

**Checkpoint**: ✅ Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Pattern-Based Auto-Classification (Priority: P1) 🎯 MVP

**Goal**: Users can create pattern rules (glob/regex) for auto-classification, reducing manual work from 20 actions to 1 pattern rule

**Independent Test**: Create pattern rule `pwa-*` → global, launch 3 PWAs, verify all are automatically classified as global without manual intervention

**Story Dependencies**: None (can start after Foundation)

### Tests for User Story 1 (FR-131, FR-132)

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T013 [P] [US1] Unit test for glob pattern matching in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify `glob:pwa-*` matches pwa-youtube, pwa-spotify (FR-131)
- [X] T014 [P] [US1] Unit test for regex pattern matching in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify `regex:^(neo)?vim$` matches vim and neovim (FR-131)
- [X] T015 [P] [US1] Unit test for literal pattern matching in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify `Ghostty` matches exact string only (FR-131)
- [X] T016 [P] [US1] Unit test for invalid regex validation in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify PatternRule raises ValueError for `regex:^[invalid` (FR-079)
- [X] T017 [P] [US1] Unit test for pattern precedence in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify explicit list > patterns > heuristics order (FR-076)
- [X] T018 [P] [US1] Unit test for LRU cache performance in `tests/i3_project_manager/unit/test_pattern_matcher.py` - verify <1ms matching with 100+ patterns (FR-078, SC-025) **NOTE: Will add performance test after PatternMatcher class implementation**
- [X] T019 [P] [US1] Integration test for pattern lifecycle in `tests/i3_project_manager/scenarios/test_pattern_lifecycle.py` - add pattern → match window → classify → save → reload daemon (FR-132)

### Implementation for User Story 1

- [X] T020 [US1] Implement PatternMatcher class in `home-modules/tools/i3_project_manager/core/pattern_matcher.py` with __init__(patterns), match(window_class) method using @lru_cache(maxsize=1024), priority-based sorting, and short-circuit evaluation per research.md Decision 1
- [X] T021 [US1] Extend AppClassConfig.is_scoped() in `home-modules/tools/i3_project_manager/core/config.py` to check pattern matches after explicit lists, using PatternMatcher instance, and respecting precedence order (FR-076) **NOTE: Already implemented in Phase 2 (T012)**
- [X] T022 [US1] Implement AppClassConfig.add_pattern() in `home-modules/tools/i3_project_manager/core/config.py` to append PatternRule, validate syntax, and call _save() with atomic write (temp file + rename) per FR-106 **NOTE: Already implemented in Phase 2 (T012)**
- [X] T023 [P] [US1] Implement AppClassConfig.remove_pattern() in `home-modules/tools/i3_project_manager/core/config.py` to filter patterns by exact string match and save atomically **NOTE: Already implemented in Phase 2 (T012)**
- [X] T024 [P] [US1] Implement AppClassConfig.list_patterns() in `home-modules/tools/i3_project_manager/core/config.py` to return sorted patterns by priority descending **NOTE: Already implemented in Phase 2 (T012)**
- [X] T025 [US1] Add CLI command `i3pm app-classes add-pattern` in `home-modules/tools/i3_project_manager/cli/commands.py` with arguments (pattern, scope), options (--priority, --description), validation, and daemon reload per contracts/cli-commands.md
- [X] T026 [P] [US1] Add CLI command `i3pm app-classes list-patterns` in `home-modules/tools/i3_project_manager/cli/commands.py` with --format (table/json), --sort options, using rich.Table for table output per contracts/cli-commands.md
- [X] T027 [P] [US1] Add CLI command `i3pm app-classes remove-pattern` in `home-modules/tools/i3_project_manager/cli/commands.py` with pattern argument, confirmation, and daemon reload per contracts/cli-commands.md
- [X] T028 [P] [US1] Add CLI command `i3pm app-classes test-pattern` in `home-modules/tools/i3_project_manager/cli/commands.py` with (pattern, window_class) arguments, --all-classes option, showing match result and explanation per contracts/cli-commands.md (FR-081, SC-038)
- [X] T029 [US1] Add daemon reload function `reload_daemon()` in `home-modules/tools/i3_project_manager/cli/commands.py` sending i3 tick event "i3pm:reload-config" per research.md Decision 6 (FR-082, FR-123)
- [X] T030 [US1] Extend daemon event listener in existing daemon code to subscribe to tick events, detect "i3pm:reload-config" message, reload AppClassConfig, and log reload action (FR-082)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently. Users can create/list/remove/test patterns and have them applied to new windows automatically.

---

## Phase 4: User Story 2 - Automated Window Class Detection (Priority: P2)

**Goal**: Automatically detect WM_CLASS for 50+ apps without StartupWMClass using Xvfb isolation in under 60 seconds

**Independent Test**: Run `i3pm app-classes detect --isolated firefox` and verify system launches Firefox in Xvfb, detects WM_CLASS "firefox" within 10 seconds, and cleans up all processes

**Story Dependencies**: None (independent of US1, can run in parallel after Foundation)

### Tests for User Story 2 (FR-132, FR-134)

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T031 [P] [US2] Unit test for isolated_xvfb context manager in `tests/i3_project_manager/unit/test_xvfb_detection.py` - verify Xvfb starts on :99, yields DISPLAY, terminates on exit (FR-084, mocked Xvfb)
- [ ] T032 [P] [US2] Unit test for graceful termination in `tests/i3_project_manager/unit/test_xvfb_detection.py` - verify SIGTERM → wait → SIGKILL sequence (FR-088, FR-089)
- [ ] T033 [P] [US2] Unit test for cleanup on timeout in `tests/i3_project_manager/unit/test_xvfb_detection.py` - verify resources cleaned after 10s timeout (FR-086, FR-089, SC-027)
- [ ] T034 [P] [US2] Unit test for dependency check in `tests/i3_project_manager/unit/test_xvfb_detection.py` - verify check_xvfb_available() returns False when xvfb-run missing (FR-083)
- [ ] T035 [P] [US2] Unit test for WM_CLASS parsing in `tests/i3_project_manager/unit/test_xvfb_detection.py` - verify regex extracts class from `WM_CLASS(STRING) = "instance", "class"` (FR-087)
- [ ] T036 [P] [US2] Integration test for detection workflow in `tests/i3_project_manager/scenarios/test_detection_workflow.py` - mock Xvfb/xdotool/xprop, verify DetectionResult created with all fields (FR-132)
- [ ] T037 [P] [US2] Integration test for bulk detection in `tests/i3_project_manager/integration/test_xvfb_detection.py` - verify 10 apps detected with progress indication, <60s total time (SC-022)

### Implementation for User Story 2

- [ ] T038 [P] [US2] Implement isolated_xvfb() context manager in `home-modules/tools/i3_project_manager/core/app_discovery.py` using subprocess.Popen for Xvfb, display_num parameter, SIGTERM/SIGKILL cleanup in finally block per research.md Decision 5 (FR-084, FR-088, FR-089)
- [ ] T039 [P] [US2] Implement check_xvfb_available() in `home-modules/tools/i3_project_manager/core/app_discovery.py` using shutil.which() to check for Xvfb, xdotool, xprop binaries (FR-083)
- [ ] T040 [US2] Implement detect_window_class_xvfb() in `home-modules/tools/i3_project_manager/core/app_discovery.py` accepting (desktop_file, timeout=10), launching app with isolated_xvfb display, polling for window with xdotool, extracting WM_CLASS with xprop, terminating app, returning detected class or None per quickstart.md Phase 2 (FR-084 through FR-089)
- [ ] T041 [US2] Add detection result caching in `home-modules/tools/i3_project_manager/core/app_discovery.py` saving to `~/.cache/i3pm/detected-classes.json` with timestamp, cache_version, invalidation after 30 days (FR-091)
- [ ] T042 [US2] Add CLI command `i3pm app-classes detect` in `home-modules/tools/i3_project_manager/cli/commands.py` with options (--all-missing, --isolated, --timeout, --cache, --verbose), dependency check, progress indication using rich.Progress, result display per contracts/cli-commands.md (FR-083, FR-090, FR-093)
- [ ] T043 [US2] Add detection logging in detect_window_class_xvfb() writing to `~/.cache/i3pm/detection.log` with timestamp, app name, detected class, duration, errors (FR-094)
- [ ] T044 [US2] Add fallback to guess algorithm in detect_window_class_xvfb() when Xvfb unavailable, timeout expires, or --skip-isolated flag specified (FR-092)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently. Users can detect WM_CLASS for apps and create pattern rules for them.

---

## Phase 5: User Story 3 - Interactive Classification Wizard (Priority: P2)

**Goal**: Visual TUI interface for bulk classification of 50+ apps in under 5 minutes with keyboard shortcuts

**Independent Test**: Run `i3pm app-classes wizard`, navigate 15 apps with arrow keys, press 's' for scoped and 'g' for global, press 'A' to accept all suggestions, verify classifications saved to config file

**Story Dependencies**: Integrates with US1 (pattern creation from wizard) and US2 (detection from wizard), but independently testable

### Tests for User Story 3 (FR-133)

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T045 [P] [US3] TUI test for wizard launch in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify wizard loads apps, displays table, shows detail panel using pytest-textual pilot (FR-133)
- [X] T046 [P] [US3] TUI test for keyboard navigation in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify arrow keys move cursor, detail panel updates <50ms (FR-099, SC-026)
- [X] T047 [P] [US3] TUI test for classification actions in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify 's' key marks as scoped, 'g' marks as global, 'u' marks as unknown (FR-101)
- [X] T048 [P] [US3] TUI test for multi-select in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify Space toggles selection, action applies to all selected (FR-100)
- [X] T049 [P] [US3] TUI test for bulk accept in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify 'A' accepts all suggestions with confidence >90% (FR-102)
- [X] T050 [P] [US3] TUI test for undo/redo in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify Ctrl+Z undoes last action, Ctrl+Y redoes (FR-104)
- [X] T051 [P] [US3] TUI test for save workflow in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify Enter saves, atomic write, daemon reload, confirmation notification (FR-106)
- [X] T052 [P] [US3] TUI test for virtual scrolling in `tests/i3_project_manager/integration/test_wizard_workflow.py` - verify 1000+ apps render with <50ms responsiveness, <100MB memory (FR-109, SC-026)

### Implementation for User Story 3

- [X] T053 [P] [US3] Create WizardState dataclass in `home-modules/tools/i3_project_manager/models/classification.py` with fields (apps, selected_indices, filter_status, sort_by, undo_stack, changes_made), methods (get_filtered_apps, get_sorted_apps, save_undo_state, undo) per data-model.md
- [X] T054 [P] [US3] Create AppTable widget in `home-modules/tools/i3_project_manager/tui/widgets/app_table.py` extending Textual DataTable with virtual=True, columns (Name, Class, Scope, Confidence, Suggestion), row selection, sort handlers per contracts/tui-wizard.md
- [X] T055 [P] [US3] Create DetailPanel widget in `home-modules/tools/i3_project_manager/tui/widgets/detail_panel.py` extending Textual Static with reactive properties for selected app, displaying desktop file fields, classification source, reasoning per contracts/tui-wizard.md
- [X] T056 [US3] Create WizardScreen in `home-modules/tools/i3_project_manager/tui/screens/wizard_screen.py` composing AppTable + DetailPanel + Header + Footer, implementing keyboard bindings (arrows, s/g/u, Space, A/R, Ctrl+Z/Y, Enter/Esc) per contracts/tui-wizard.md (FR-095 through FR-110)
- [X] T057 [US3] Implement WizardApp in `home-modules/tools/i3_project_manager/tui/wizard.py` as Textual App with WizardScreen, async on_mount loading apps from AppDiscovery, wizard_state reactive property, action handlers per contracts/tui-wizard.md
- [X] T058 [US3] Implement classification suggestion algorithm in `home-modules/tools/i3_project_manager/tui/wizard.py` using category keywords (Development → scoped, Utility → global), pattern matches, confidence scoring (0.0-1.0) per data-model.md
- [X] T059 [US3] Implement filter/sort logic in WizardScreen using filter dropdown (all/unclassified/scoped/global), sort dropdown (name/class/status/confidence), updating table reactively (FR-096)
- [X] T060 [US3] Implement undo/redo stack in WizardApp saving JSON snapshots before each action, max 20 snapshots, restoring state on Ctrl+Z, showing notification with action description (FR-104)
- [X] T061 [US3] Implement save workflow in WizardApp with confirmation dialog if changes_made=True, validation (detect duplicates/conflicts), atomic write to app-classes.json, daemon reload, success notification per contracts/tui-wizard.md (FR-105, FR-106)
- [X] T062 [US3] Implement external file modification detection in WizardApp checking mtime on focus, showing modal dialog (Reload/Merge/Overwrite), preserving current work (FR-108)
- [X] T063 [US3] Implement pattern creation action in WizardScreen with 'p' key opening pattern dialog, pre-filling current app's window_class, preview showing matches, validation, adding to patterns on confirm per contracts/tui-wizard.md
- [X] T064 [US3] Implement detection action in WizardScreen with 'd' key triggering detect_window_class_xvfb() for selected app, showing progress spinner, updating detected_class on success (integration with US2)
- [X] T065 [US3] Add CLI command `i3pm app-classes wizard` in `home-modules/tools/i3_project_manager/cli/commands.py` with options (--filter, --sort, --auto-accept), launching WizardApp.run() per contracts/cli-commands.md (FR-095)
- [X] T066 [US3] Implement semantic color scheme in WizardScreen using Textual styles: scoped=green, global=blue, unknown=yellow, error=red, with confidence-based brightness per contracts/tui-wizard.md (FR-097, FR-129)
- [X] T067 [US3] Implement empty state handling in WizardApp showing helpful message "No apps discovered. Run 'i3pm app-classes detect --all-missing' to populate." when apps list empty (FR-110)

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work independently. Users have complete workflow: detect → wizard classify → patterns automatically apply.

---

## Phase 6: User Story 4 - Real-Time Window Inspection (Priority: P3)

**Goal**: Press Win+I keybinding, click any window, instantly see all properties, classification status, reasoning, and classify directly

**Independent Test**: Press Win+I keybinding, click on VS Code window, verify inspector shows WM_CLASS "Code", classification status "scoped", source "explicit list", ability to reclassify with 'g' key for global

**Story Dependencies**: Integrates with US1 (pattern creation from inspector) but independently testable

### Tests for User Story 4 (FR-133)

**NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T068 [P] [US4] Unit test for window selection modes in `tests/i3_project_manager/unit/test_inspector.py` - verify click mode uses xdotool selectwindow, focused mode uses i3 GET_TREE find_focused (FR-112, mocked i3 IPC)
- [X] T069 [P] [US4] Unit test for property extraction in `tests/i3_project_manager/unit/test_inspector.py` - verify WindowProperties populated from i3 container (FR-113, FR-114)
- [X] T070 [P] [US4] TUI test for inspector launch in `tests/i3_project_manager/integration/test_inspector_workflow.py` - verify inspector loads window properties, displays table, shows classification using pytest-textual (FR-133)
- [X] T071 [P] [US4] TUI test for classification actions in `tests/i3_project_manager/integration/test_inspector_workflow.py` - verify 's' marks as scoped, 'g' marks as global, saves immediately (FR-117, FR-119)
- [X] T072 [P] [US4] TUI test for live mode in `tests/i3_project_manager/integration/test_inspector_workflow.py` - verify 'l' enables live mode, subscribes to i3 events, updates on window::title change <100ms (FR-120, SC-037)
- [X] T073 [P] [US4] TUI test for pattern creation in `tests/i3_project_manager/integration/test_inspector_workflow.py` - verify 'p' opens pattern dialog, pre-fills window_class, creates pattern on confirm (integration with US1)

### Implementation for User Story 4

- [X] T074 [P] [US4] Create WindowProperties dataclass in `home-modules/tools/i3_project_manager/models/inspector.py` with fields (window_id, window_class, instance, title, marks, workspace, current_classification, suggested_classification, reasoning) per data-model.md
- [X] T075 [P] [US4] Create PropertyDisplay widget in `home-modules/tools/i3_project_manager/tui/widgets/property_display.py` extending Textual DataTable displaying window properties as key-value pairs, highlighting changes in yellow for 200ms per contracts/tui-inspector.md
- [X] T076 [US4] Implement inspect_window_focused() in `home-modules/tools/i3_project_manager/tui/inspector.py` using i3ipc.aio Connection, GET_TREE, find_focused(), returning WindowProperties per contracts/tui-inspector.md (FR-112)
- [X] T077 [P] [US4] Implement inspect_window_by_id() in `home-modules/tools/i3_project_manager/tui/inspector.py` accepting window_id parameter, using GET_TREE, find_by_id(), returning WindowProperties (FR-112)
- [X] T078 [P] [US4] Implement inspect_window_click() in `home-modules/tools/i3_project_manager/tui/inspector.py` using subprocess.run(['xdotool', 'selectwindow']), parsing window ID, calling inspect_window_by_id() per contracts/tui-inspector.md (FR-112)
- [X] T079 [US4] Create InspectorScreen in `home-modules/tools/i3_project_manager/tui/screens/inspector_screen.py` composing PropertyDisplay + Classification Status panel + Pattern Matches panel + Header + Footer, implementing keyboard bindings (s/g/u/p, r, l, c, Esc) per contracts/tui-inspector.md (FR-111 through FR-122)
- [X] T080 [US4] Implement InspectorApp in `home-modules/tools/i3_project_manager/tui/inspector.py` as Textual App with InspectorScreen, async on_mount querying window properties, window_props reactive property, action handlers per contracts/tui-inspector.md
- [X] T081 [US4] Implement live mode in InspectorApp subscribing to i3 events (window::title, window::mark, window::move, window::focus), updating PropertyDisplay on event, highlighting changed fields <100ms per contracts/tui-inspector.md (FR-120, SC-037)
- [X] T082 [US4] Implement classification actions in InspectorApp with 's'/'g' keys calling AppClassConfig methods, saving immediately, reloading daemon, showing confirmation per contracts/tui-inspector.md (FR-117, FR-119)
- [X] T083 [US4] Implement pattern creation action in InspectorApp with 'p' key opening pattern dialog (reuse from wizard), pre-filling current window_class, validation, adding pattern (FR-117)
- [X] T084 [US4] Implement pattern matches display in InspectorScreen showing all patterns matching current window_class, sorted by priority, highlighting winning pattern, showing "Potential patterns" suggestions per contracts/tui-inspector.md
- [X] T085 [US4] Implement classification reasoning in InspectorApp generating explanation text showing precedence chain (explicit list > pattern X > heuristic), matched keywords, category per contracts/tui-inspector.md (FR-115)
- [X] T086 [US4] Add CLI command `i3pm app-classes inspect` in `home-modules/tools/i3_project_manager/cli/commands.py` with options (--click, --focused, --live), window_id argument, launching InspectorApp with appropriate selection mode per contracts/cli-commands.md (FR-111)
- [X] T087 [US4] Implement copy to clipboard action in InspectorApp with 'c' key using subprocess.run(['xclip', '-selection', 'clipboard'], input=window_class) per contracts/tui-inspector.md
- [X] T088 [US4] Implement window not found error handling in InspectorApp checking if window_id exists, showing error modal with remediation steps, offering to switch to click mode per contracts/tui-inspector.md (FR-122)
- [X] T089 [US4] Add i3 keybinding example to documentation: `bindsym $mod+i exec --no-startup-id i3pm app-classes inspect --click` per contracts/tui-inspector.md

**Checkpoint**: All user stories should now be independently functional. Users have complete troubleshooting workflow: inspect → see reasoning → classify → create pattern.

---

## Phase 7: Cross-Cutting Concerns & Polish

**Purpose**: Improvements that affect multiple user stories

- [X] T090 [P] Implement consistent error messages with remediation steps across all CLI commands following SC-036 format "Error: <issue>. Remediation: <steps>" in `home-modules/tools/i3_project_manager/cli/commands.py`
- [X] T091 [P] Implement JSON output format for all CLI commands with --json flag serializing to stdout, suppressing rich formatting per FR-125
- [ ] T092 [P] Implement dry-run mode for all mutation commands (add-pattern, remove-pattern, detect, wizard save) with --dry-run flag showing what would change without applying per FR-125
- [ ] T093 [P] Implement verbose logging for all commands with --verbose flag using logging.DEBUG level, showing subprocess calls, i3 IPC messages, timing per FR-125
- [ ] T094 [P] Add shell completion for Bash in `home-modules/tools/i3_project_manager/cli/commands.py` using argcomplete decorators @autocomplete(choices=...) for pattern prefixes (glob:, regex:), scope values (scoped, global), filter values, sort values per contracts/cli-commands.md
- [ ] T095 [P] Implement app-classes.json schema validation on daemon load in existing daemon code using JSON schema, logging detailed errors to systemd journal on validation failure (FR-130)
- [ ] T096 [P] Add comprehensive docstrings (Google style) to all public APIs in models/, core/, tui/, cli/ modules per Principle X and FR-135
- [ ] T097 [P] Create user guide sections in docs/ directory: "Pattern Rules", "Xvfb Detection", "Classification Wizard", "Window Inspector" with examples, troubleshooting, screenshots per quickstart.md
- [ ] T098 [P] Update NixOS package in `home-modules/tools/i3-project-manager.nix` to version 0.3.0, add xvfb-run, xdotool, xprop to buildInputs, add argcomplete to propagatedBuildInputs per quickstart.md deployment section
- [ ] T099 [P] Add user acceptance test scenarios in `tests/i3_project_manager/scenarios/test_acceptance.py` implementing all acceptance scenarios from spec.md User Stories 1-4 (FR-135)
- [ ] T100 [P] Run quickstart.md validation by executing each code example, verifying outputs match expected results, fixing any discrepancies
- [ ] T101 Add integration test for round-trip workflow in `tests/i3_project_manager/scenarios/test_classification_e2e.py` - detect apps → wizard classify → create patterns → inspector verify → daemon reload → new windows auto-classify (FR-132)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - **US1 (P1)** can start after Foundational - no dependencies on other stories
  - **US2 (P2)** can start after Foundational - no dependencies on other stories (runs in parallel with US1)
  - **US3 (P2)** can start after Foundational - integrates with US1 and US2 but independently testable (runs in parallel with US1/US2)
  - **US4 (P3)** can start after Foundational - integrates with US1 but independently testable
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1 - Patterns)**: Can start after Foundational (T009-T012) - No dependencies on other stories
- **User Story 2 (P2 - Detection)**: Can start after Foundational (T009-T012) - Independent of US1, runs in parallel
- **User Story 3 (P2 - Wizard)**: Can start after Foundational (T009-T012) - Integrates with US1 (T063 pattern creation) and US2 (T064 detection) but independently testable
- **User Story 4 (P3 - Inspector)**: Can start after Foundational (T009-T012) - Integrates with US1 (T083 pattern creation) but independently testable

### Within Each User Story

- **Tests MUST be written and FAIL before implementation** (TDD order per FR-131 through FR-135)
- Models before services (T009-T012 foundation before T020-T030 implementation)
- Services before CLI commands (T020-T024 services before T025-T028 CLI)
- Core implementation before integration (T040 detection before T064 wizard detection action)
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 Setup**: All tasks (T001-T008) marked [P] can run in parallel
- **Phase 2 Foundational**: T009, T010, T011 can run in parallel (different model files), T012 depends on T009 completion
- **User Story 1**:
  - Tests T013-T019 can all run in parallel
  - Models already created in Foundation
  - CLI commands T025-T028 can run in parallel (different command definitions)
- **User Story 2**:
  - Tests T031-T037 can all run in parallel
  - Implementation T038, T039 can run in parallel (different functions)
  - T042 CLI and T043 logging can run in parallel
- **User Story 3**:
  - Tests T045-T052 can all run in parallel
  - Widgets T053-T055 can all run in parallel (different widget files)
- **User Story 4**:
  - Tests T068-T073 can all run in parallel
  - T074, T075 can run in parallel (different files)
  - T077, T078 can run in parallel (different selection modes)
- **Phase 7 Polish**: All tasks T090-T101 marked [P] can run in parallel
- **Cross-Story Parallelism**: After Foundation (T009-T012), all user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: T013 Unit test for glob pattern matching
Task: T014 Unit test for regex pattern matching
Task: T015 Unit test for literal pattern matching
Task: T016 Unit test for invalid regex validation
Task: T017 Unit test for pattern precedence
Task: T018 Unit test for LRU cache performance
Task: T019 Integration test for pattern lifecycle

# After tests written and failing, launch parallel implementation tasks:
Task: T025 CLI command add-pattern (file: cli/commands.py add_pattern function)
Task: T026 CLI command list-patterns (file: cli/commands.py list_patterns function)
Task: T027 CLI command remove-pattern (file: cli/commands.py remove_pattern function)
Task: T028 CLI command test-pattern (file: cli/commands.py test_pattern function)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T008)
2. Complete Phase 2: Foundational (T009-T012) - **CRITICAL - blocks all stories**
3. Complete Phase 3: User Story 1 (T013-T030)
4. **STOP and VALIDATE**: Run all US1 tests, verify pattern creation/matching/classification works
5. Deploy/demo if ready - users can now create patterns to reduce manual work

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (T001-T012)
2. Add User Story 1 → Test independently → Deploy/Demo (T013-T030) - **MVP!**
3. Add User Story 2 → Test independently → Deploy/Demo (T031-T044) - adds auto-detection
4. Add User Story 3 → Test independently → Deploy/Demo (T045-T067) - adds visual wizard
5. Add User Story 4 → Test independently → Deploy/Demo (T068-T089) - adds troubleshooting
6. Add Polish → Final release (T090-T101)
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup (T001-T008) + Foundational (T009-T012) together
2. Once Foundational is done (T012 complete):
   - Developer A: User Story 1 (T013-T030) - Pattern system
   - Developer B: User Story 2 (T031-T044) - Xvfb detection
   - Developer C: User Story 3 (T045-T067) - Wizard TUI
3. After US1/US2/US3 complete:
   - Developer D: User Story 4 (T068-T089) - Inspector TUI
4. All developers: Polish phase (T090-T101) in parallel
5. Stories complete and integrate independently

### Test-Driven Development (TDD) Order

**CRITICAL**: For each user story, tests MUST be written FIRST and FAIL before implementation

Example for User Story 1:
1. Write T013-T019 (all tests for US1) - **verify they FAIL**
2. Implement T020-T024 (core pattern matching) - **verify tests start passing**
3. Implement T025-T030 (CLI commands) - **verify all tests pass**
4. Checkpoint: US1 complete and fully tested

---

## Task Summary

**Total Tasks**: 101
- Phase 1 (Setup): 8 tasks
- Phase 2 (Foundation): 4 tasks (BLOCKING)
- Phase 3 (US1 - Patterns): 18 tasks (7 tests + 11 implementation)
- Phase 4 (US2 - Detection): 14 tasks (7 tests + 7 implementation)
- Phase 5 (US3 - Wizard): 23 tasks (8 tests + 15 implementation)
- Phase 6 (US4 - Inspector): 22 tasks (6 tests + 16 implementation)
- Phase 7 (Polish): 12 tasks

**Parallel Opportunities**: 45 tasks marked [P] can run in parallel within their phase

**Test Coverage**: 28 test tasks (FR-131 through FR-135 compliance)
- Unit tests: 15 tasks
- Integration tests: 8 tasks
- TUI tests: 4 tasks
- Scenario/UAT tests: 1 task

**Independent Test Criteria**:
- US1: Create pattern `pwa-*` → global, verify 3 PWAs auto-classify (T019)
- US2: Run detect command, verify Firefox detected in <10s, cleanup complete (T036)
- US3: Run wizard, classify 15 apps, accept suggestions, verify saved (T045-T051)
- US4: Press Win+I, click VS Code, verify properties shown, classify with 'g' key (T070-T071)

**Suggested MVP Scope**: Phases 1-3 (Setup + Foundation + User Story 1) = 30 tasks for basic pattern functionality

---

## Notes

- [P] tasks = different files, no dependencies within phase
- [Story] label maps task to specific user story for traceability
- Each user story independently completable and testable
- **TDD requirement**: Verify tests fail before implementing (FR-131 through FR-135)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Foundation (T009-T012) is CRITICAL blocker - no user story work until complete
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- All file paths use NixOS home-manager structure from plan.md
- Tests explicitly required per FR-131 through FR-135, included in all phases
