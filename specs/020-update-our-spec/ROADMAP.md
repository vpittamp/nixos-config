# Implementation Roadmap: Wizard & Inspector TUI (Phases 5-7)

**Feature**: App Discovery & Auto-Classification System
**Branch**: `020-update-our-spec`
**Status**: Phases 1-4 Complete ✅ | Phases 5-7 Pending
**Date**: 2025-10-21

## Executive Summary

This roadmap outlines the implementation strategy for completing the remaining phases of the App Discovery & Auto-Classification System. Phases 1-4 (Pattern-based classification and Xvfb detection) are **complete with 35/36 tests passing**. This document focuses on:

- **Phase 5**: Interactive Classification Wizard TUI (23 tasks, ~8-12 hours)
- **Phase 6**: Real-Time Window Inspector TUI (22 tasks, ~6-10 hours)
- **Phase 7**: Polish & Documentation (12 tasks, ~4-6 hours)

**Total Estimated Effort**: 18-28 hours of focused development

---

## Current Status: Phases 1-4 Complete ✅

### What's Working

✅ **Phase 1**: Setup & Configuration
- NixOS package structure
- Python package with i3pm entry point
- Configuration file handling (app-classes.json)

✅ **Phase 2**: Foundational Components
- Data models: `PatternRule`, `DetectionResult`, `ClassificationResult`
- Configuration management: `AppClassConfig`
- Pattern matching engine with glob/regex support

✅ **Phase 3**: User Story 1 - Pattern-Based Classification (P1)
- Pattern storage in app-classes.json
- Pattern precedence (explicit > pattern > heuristic)
- CLI commands: `add-pattern`, `list-patterns`, `remove-pattern`, `test-pattern`
- Pattern validation and conflict detection
- **Tests**: 17/17 passing

✅ **Phase 4**: User Story 2 - Automated Detection (P2)
- Xvfb-based window class detection
- Detection result caching (30-day TTL)
- Detection logging to ~/.cache/i3pm/detection.log
- CLI command: `i3pm app-classes detect`
- Progress indication with rich.Progress
- **Tests**: 35/36 passing (97% pass rate)

### Implementation Quality Metrics

- **Test Coverage**: 52 total tests, 51 passing (98% pass rate)
- **Code Quality**: Full type hints, comprehensive docstrings
- **Performance**: Detection < 10s per app, caching reduces repeat detections
- **Reliability**: Graceful cleanup with SIGTERM → SIGKILL sequence

---

## Phase 5: Interactive Classification Wizard TUI (US3 - P2)

**Goal**: Visual TUI interface for bulk classification of 50+ apps in under 5 minutes with keyboard shortcuts

**Priority**: P2 (Medium - Dramatically improves UX)

**Estimated Effort**: 8-12 hours

### Independent Test Criteria

Run `i3pm app-classes wizard`, navigate 15 apps with arrow keys, press 's' for scoped and 'g' for global, press 'A' to accept all suggestions, verify classifications saved to config file.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      WizardApp (Textual App)                │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              WizardScreen (Compose Layout)            │ │
│  │  ┌─────────────────────┐  ┌────────────────────────┐ │ │
│  │  │   AppTable Widget   │  │  DetailPanel Widget   │ │ │
│  │  │  (DataTable)        │  │  (Static)             │ │ │
│  │  │  - Virtual scroll   │  │  - App properties     │ │ │
│  │  │  - Multi-select     │  │  - Classification     │ │ │
│  │  │  - Sortable columns │  │  - Suggestion reason  │ │ │
│  │  └─────────────────────┘  └────────────────────────┘ │ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │             Header (Title + Stats)                ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │        Footer (Keybindings + Help)                ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         ↓ State Management
    WizardState (dataclass)
    - apps: List[DesktopApp]
    - selected_indices: Set[int]
    - filter_status: FilterOption
    - sort_by: SortColumn
    - undo_stack: List[StateSnapshot]
    - changes_made: bool
```

### Task Breakdown (23 tasks)

#### Group 1: TUI Tests (T045-T052) - 8 tests
**Effort**: 2-3 hours | **Dependencies**: pytest-textual installed

- [x] T045 [P] Wizard launch test - verify apps load, table displays, detail panel shows
- [x] T046 [P] Keyboard navigation test - arrow keys, detail updates <50ms
- [x] T047 [P] Classification actions test - 's', 'g', 'u' keys mark apps
- [x] T048 [P] Multi-select test - Space toggles, actions apply to all selected
- [x] T049 [P] Bulk accept test - 'A' accepts suggestions >90% confidence
- [x] T050 [P] Undo/redo test - Ctrl+Z/Ctrl+Y with action descriptions
- [x] T051 [P] Save workflow test - Enter saves, atomic write, daemon reload
- [x] T052 [P] Virtual scrolling test - 1000+ apps, <50ms response, <100MB memory

**Implementation Note**: Use pytest-textual's `pilot` fixture for simulating keyboard input and verifying screen state.

#### Group 2: Data Models & Widgets (T053-T055) - 3 tasks
**Effort**: 2-3 hours | **Dependencies**: Textual framework

- [ ] T053 Create WizardState dataclass
  - File: `models/classification.py`
  - Fields: apps, selected_indices, filter_status, sort_by, undo_stack, changes_made
  - Methods: get_filtered_apps(), get_sorted_apps(), save_undo_state(), undo()

- [ ] T054 [P] Create AppTable widget
  - File: `tui/widgets/app_table.py`
  - Extends: Textual DataTable with virtual=True
  - Columns: Name, Class, Scope, Confidence, Suggestion
  - Features: Row selection, sort handlers, multi-select

- [ ] T055 [P] Create DetailPanel widget
  - File: `tui/widgets/detail_panel.py`
  - Extends: Textual Static
  - Reactive properties for selected app
  - Displays: desktop file fields, classification source, reasoning

#### Group 3: Wizard Screen & App (T056-T062) - 7 tasks
**Effort**: 3-4 hours | **Dependencies**: T053-T055 complete

- [ ] T056 Implement WizardScreen
  - File: `tui/screens/wizard_screen.py`
  - Compose: AppTable + DetailPanel + Header + Footer
  - Keyboard bindings: arrows, s/g/u, Space, A/R, Ctrl+Z/Y, Enter/Esc

- [ ] T057 Implement WizardApp
  - File: `tui/wizard.py`
  - Textual App with WizardScreen
  - async on_mount loading apps from AppDiscovery
  - wizard_state reactive property

- [ ] T058 Implement suggestion algorithm
  - File: `tui/wizard.py`
  - Category keywords: Development → scoped, Utility → global
  - Pattern matches with confidence scoring (0.0-1.0)

- [ ] T059 Implement filter/sort logic
  - Filter dropdown: all/unclassified/scoped/global
  - Sort dropdown: name/class/status/confidence
  - Update table reactively

- [ ] T060 Implement undo/redo stack
  - Save JSON snapshots before each action
  - Max 20 snapshots
  - Restore state on Ctrl+Z
  - Show notification with action description

- [ ] T061 Implement save workflow
  - Confirmation dialog if changes_made=True
  - Validation: detect duplicates/conflicts
  - Atomic write to app-classes.json
  - Daemon reload, success notification

- [ ] T062 Implement external file modification detection
  - Check mtime on focus
  - Modal dialog: Reload/Merge/Overwrite
  - Preserve current work

#### Group 4: Advanced Features (T063-T067) - 5 tasks
**Effort**: 2-3 hours | **Dependencies**: T056-T062 complete

- [ ] T063 Pattern creation action
  - 'p' key opens pattern dialog
  - Pre-fill current app's window_class
  - Preview showing matches
  - Validation, add to patterns on confirm

- [ ] T064 Detection action
  - 'd' key triggers detect_window_class_xvfb()
  - Show progress spinner
  - Update detected_class on success

- [ ] T065 Add CLI command `i3pm app-classes wizard`
  - File: `cli/commands.py`
  - Options: --filter, --sort, --auto-accept
  - Launch WizardApp.run()

- [ ] T066 Semantic color scheme
  - Textual styles: scoped=green, global=blue, unknown=yellow, error=red
  - Confidence-based brightness

- [ ] T067 Empty state handling
  - Show helpful message when apps list empty
  - Suggest: "Run 'i3pm app-classes detect --all-missing'"

### Implementation Strategy

**Week 1: Foundation**
1. **Day 1-2**: Write all TUI tests (T045-T052) - Ensure they FAIL
2. **Day 3**: Implement data models (T053)
3. **Day 4**: Implement widgets (T054-T055) in parallel

**Week 2: Core Wizard**
1. **Day 5-6**: Implement WizardScreen and WizardApp (T056-T057)
2. **Day 7**: Add suggestion algorithm and filter/sort (T058-T059)
3. **Day 8**: Add undo/redo and save workflow (T060-T061)

**Week 3: Polish**
1. **Day 9**: External file detection (T062)
2. **Day 10**: Advanced features (T063-T065)
3. **Day 11**: Color scheme and empty state (T066-T067)
4. **Day 12**: Testing and bug fixes

### Success Criteria

- ✅ All 8 TUI tests passing
- ✅ Wizard launches and displays 50+ apps
- ✅ Keyboard navigation responsive (<50ms)
- ✅ Classifications save atomically
- ✅ Undo/redo works correctly
- ✅ Memory usage <100MB with 1000+ apps

---

## Phase 6: Real-Time Window Inspector TUI (US4 - P3)

**Goal**: Press Win+I keybinding, click any window, instantly see all properties, classification status, reasoning, and classify directly

**Priority**: P3 (Lower - Essential for troubleshooting but not basic operation)

**Estimated Effort**: 6-10 hours

### Independent Test Criteria

Press Win+I keybinding, click on VS Code window, verify inspector shows WM_CLASS "Code", classification status "scoped", source "explicit list", ability to reclassify with 'g' key for global.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   InspectorApp (Textual App)                │
│  ┌───────────────────────────────────────────────────────┐ │
│  │           InspectorScreen (Compose Layout)            │ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │         PropertiesPanel (Window Info)             ││ │
│  │  │  - WM_CLASS, title, role, instance                ││ │
│  │  │  - PID, workspace, geometry                       ││ │
│  │  │  - i3 marks, container ID                         ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │     ClassificationPanel (Current Status)          ││ │
│  │  │  - Current scope (scoped/global/unknown)          ││ │
│  │  │  - Source (explicit/pattern/heuristic)            ││ │
│  │  │  - Precedence chain visualization                 ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │      SuggestionPanel (Recommended Action)         ││ │
│  │  │  - Suggested classification with confidence       ││ │
│  │  │  - Reasoning (matched categories, keywords)       ││ │
│  │  │  - Related apps (same WM_CLASS)                   ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  │  ┌───────────────────────────────────────────────────┐│ │
│  │  │           ActionsPanel (Keybindings)              ││ │
│  │  │  s=scoped | g=global | p=pattern | q=quit        ││ │
│  │  └───────────────────────────────────────────────────┘│ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         ↓ Live Updates
    i3 IPC Event Subscriptions
    - window::title (property changes)
    - window::mark (classification changes)
    - window::close (window destruction)
```

### Task Breakdown (22 tasks)

#### Group 1: TUI Tests (T068-T075) - 8 tests
**Effort**: 2-3 hours

- [ ] T068 [P] Inspector launch test
- [ ] T069 [P] Window selection test (click mode)
- [ ] T070 [P] Focused window test (auto-select)
- [ ] T071 [P] Properties display test
- [ ] T072 [P] Classification status test
- [ ] T073 [P] Direct classification test (s/g keys)
- [ ] T074 [P] Related apps test (same WM_CLASS)
- [ ] T075 [P] Live update test (property changes)

#### Group 2: Window Selection & IPC (T076-T078) - 3 tasks
**Effort**: 2 hours

- [ ] T076 Implement window selector
  - File: `core/window_selector.py`
  - Click mode with crosshair cursor (using i3-msg)
  - Focused mode (current window)
  - By-ID mode (specific window)

- [ ] T077 [P] Create InspectorState dataclass
  - File: `models/inspection.py`
  - Fields: window_id, properties, classification, suggestion

- [ ] T078 [P] Implement i3 IPC client wrapper
  - File: `core/i3_inspector.py`
  - Methods: get_window_properties(), subscribe_to_events()

#### Group 3: Inspector Widgets (T079-T082) - 4 tasks
**Effort**: 2-3 hours

- [ ] T079 [P] Create PropertiesPanel widget
  - File: `tui/widgets/properties_panel.py`
  - Display all window properties
  - Highlight changed fields

- [ ] T080 [P] Create ClassificationPanel widget
  - File: `tui/widgets/classification_panel.py`
  - Show current status and source
  - Precedence chain visualization

- [ ] T081 [P] Create SuggestionPanel widget
  - File: `tui/widgets/suggestion_panel.py`
  - Suggested classification with reasoning
  - Related apps list

- [ ] T082 [P] Create ActionsPanel widget
  - File: `tui/widgets/actions_panel.py`
  - Keybindings display
  - Action confirmation dialogs

#### Group 4: Inspector Screen & App (T083-T086) - 4 tasks
**Effort**: 2-3 hours

- [ ] T083 Implement InspectorScreen
  - File: `tui/screens/inspector_screen.py`
  - Compose: Properties + Classification + Suggestion + Actions panels
  - Keyboard bindings: s/g/p/q

- [ ] T084 Implement InspectorApp
  - File: `tui/inspector.py`
  - Textual App with InspectorScreen
  - async window selection on launch
  - Live update subscriptions

- [ ] T085 Implement live monitoring
  - Subscribe to i3 events
  - Update display on property changes
  - Handle window destruction

- [ ] T086 Implement direct classification
  - s/g keys classify current window
  - Option to classify all related windows
  - Confirmation dialog, save, daemon reload

#### Group 5: Integration & CLI (T087-T089) - 3 tasks
**Effort**: 1-2 hours

- [ ] T087 Add CLI command `i3pm window inspect`
  - File: `cli/commands.py`
  - Options: --mode (click/focused/id), --live

- [ ] T088 Add i3 keybinding Win+I
  - File: Home-manager i3 config
  - Bind: bindsym $mod+i exec i3pm window inspect --mode click

- [ ] T089 Implement pattern creation from inspector
  - 'p' key opens pattern dialog
  - Pre-fill from current window's WM_CLASS
  - Preview matches, confirm, save

### Success Criteria

- ✅ All 8 TUI tests passing
- ✅ Win+I keybinding launches inspector
- ✅ Click mode selects window correctly
- ✅ All properties displayed accurately
- ✅ Classification updates in real-time
- ✅ Live monitoring responds to window changes

---

## Phase 7: Polish & Documentation (Cross-Cutting)

**Estimated Effort**: 4-6 hours

### Task Breakdown (12 tasks)

#### Group 1: Error Handling & Edge Cases (T090-T094) - 5 tasks
**Effort**: 2 hours

- [ ] T090 [P] Add comprehensive error handling
  - Pattern validation errors
  - Xvfb detection failures
  - i3 IPC connection errors

- [ ] T091 [P] Add edge case handling
  - Invalid regex patterns
  - Conflicting patterns (same priority)
  - Pattern matching everything (`*`)

- [ ] T092 [P] Add resource cleanup verification
  - No zombie processes after Xvfb
  - Clean Xvfb lock files
  - Clean temporary sockets

- [ ] T093 [P] Add i3 restart resilience
  - Buffer write operations
  - Wait for reconnection
  - Retry daemon reload

- [ ] T094 [P] Add concurrent safety
  - Atomic writes (temp file + rename)
  - File locking where needed

#### Group 2: Documentation (T095-T098) - 4 tasks
**Effort**: 2-3 hours

- [ ] T095 [P] Write user guide: Pattern Rules
  - Glob vs regex syntax
  - Priority and precedence
  - Common patterns

- [ ] T096 [P] Write user guide: Wizard
  - Keyboard shortcuts
  - Workflow walkthrough
  - Tips and tricks

- [ ] T097 [P] Write user guide: Inspector
  - Keybinding Win+I
  - Understanding classification sources
  - Troubleshooting misclassifications

- [ ] T098 [P] Write troubleshooting guide
  - Common issues and solutions
  - Xvfb dependency installation
  - Performance tuning

#### Group 3: Final Integration (T099-T101) - 3 tasks
**Effort**: 1 hour

- [ ] T099 Add shell completions
  - bash-completion for i3pm commands
  - zsh-completion if desired

- [ ] T100 Add man pages
  - i3pm(1) main command
  - i3pm-app-classes(1) subcommand

- [ ] T101 Final integration testing
  - End-to-end workflow test
  - Performance benchmarks
  - Memory profiling

---

## Dependency Graph

```
Phase 1-4 (COMPLETE) ✅
    ↓
Phase 5: Wizard TUI (P2)
    ├─ T045-T052: Tests (parallel) ─────────┐
    ├─ T053: WizardState ────────────────────┤
    ├─ T054-T055: Widgets (parallel) ────────┤
    ├─ T056-T062: Screen & App ──────────────┤
    └─ T063-T067: Advanced Features ─────────┤
                                             ↓
                                   Phase 7: Polish
                                        (T090-T101)
                                             ↑
Phase 6: Inspector TUI (P3)                  │
    ├─ T068-T075: Tests (parallel) ──────────┤
    ├─ T076-T078: Selection & IPC ───────────┤
    ├─ T079-T082: Widgets (parallel) ────────┤
    ├─ T083-T086: Screen & App ──────────────┤
    └─ T087-T089: Integration ───────────────┘
```

**Key Dependencies**:
- Phase 5 and Phase 6 are **independent** and can be developed in parallel
- Phase 7 depends on both Phase 5 and Phase 6 completion
- Within each phase, tests can be written in parallel with implementation

---

## Parallel Execution Opportunities

### Phase 5 (Wizard) - 4 Parallel Tracks

**Track 1: TUI Tests** (T045-T052)
- Can write all 8 tests in parallel
- Estimated: 2-3 hours

**Track 2: Data Models** (T053)
- WizardState dataclass
- Estimated: 1 hour

**Track 3: Widgets** (T054-T055)
- AppTable and DetailPanel in parallel
- Estimated: 2 hours

**Track 4: Advanced Features** (T063-T067)
- Can implement after core wizard works
- Estimated: 2-3 hours

### Phase 6 (Inspector) - 3 Parallel Tracks

**Track 1: TUI Tests** (T068-T075)
- Can write all 8 tests in parallel
- Estimated: 2-3 hours

**Track 2: Widgets** (T079-T082)
- All 4 panels in parallel
- Estimated: 2-3 hours

**Track 3: Integration** (T087-T089)
- CLI command and keybinding
- Estimated: 1 hour

---

## Implementation Recommendations

### MVP Scope (Minimum Viable Product)

**Goal**: Get working wizard and inspector as quickly as possible

**Include**:
- ✅ Phase 5: Wizard with basic navigation and classification (T045-T061)
- ✅ Phase 6: Inspector with click mode and basic display (T068-T084)
- ⏭️ Skip initially: Advanced features (pattern creation from wizard/inspector)
- ⏭️ Skip initially: Live monitoring, external file detection

**Benefits**:
- Delivers 80% of value in 40% of time
- Provides early feedback for UX improvements
- Reduces risk of overengineering

### Incremental Delivery Strategy

**Sprint 1 (Week 1)**: Wizard Foundation
- Write all wizard tests (T045-T052)
- Implement WizardState, AppTable, DetailPanel (T053-T055)
- **Deliverable**: Static wizard that displays apps

**Sprint 2 (Week 2)**: Wizard Interactions
- Implement WizardScreen and WizardApp (T056-T057)
- Add suggestion algorithm and filter/sort (T058-T059)
- Add undo/redo and save (T060-T061)
- **Deliverable**: Fully functional wizard

**Sprint 3 (Week 3)**: Inspector Foundation
- Write all inspector tests (T068-T075)
- Implement window selection and IPC (T076-T078)
- Implement all panels (T079-T082)
- **Deliverable**: Static inspector that displays window info

**Sprint 4 (Week 4)**: Inspector Interactions & Polish
- Implement InspectorScreen and InspectorApp (T083-T084)
- Add live monitoring (T085)
- Add direct classification (T086)
- Integration and CLI (T087-T089)
- **Deliverable**: Fully functional inspector

**Sprint 5 (Week 5)**: Advanced Features & Documentation
- Add pattern creation from wizard/inspector (T063, T089)
- Add detection action from wizard (T064)
- Error handling and edge cases (T090-T094)
- Documentation (T095-T098)
- **Deliverable**: Production-ready system

---

## Risk Mitigation

### Technical Risks

**Risk 1**: Textual TUI framework learning curve
- **Mitigation**: Start with simple widgets, study examples
- **Fallback**: Use rich.Console for simpler non-interactive UI

**Risk 2**: pytest-textual testing complexity
- **Mitigation**: Write simple integration tests first
- **Fallback**: Manual testing with documented test cases

**Risk 3**: i3 IPC event handling performance
- **Mitigation**: Use async/await properly, test with many windows
- **Fallback**: Polling fallback if event subscriptions fail

**Risk 4**: Memory usage with 1000+ apps
- **Mitigation**: Virtual scrolling, lazy loading
- **Validation**: Memory profiling with test data

### Schedule Risks

**Risk**: Underestimated complexity
- **Mitigation**: Track actual time vs estimates, adjust
- **Contingency**: MVP scope reduction (skip advanced features)

**Risk**: Blocked by bugs in dependencies
- **Mitigation**: Test dependencies early, have fallback approaches
- **Contingency**: Workarounds or simplified implementations

---

## Success Metrics

### Functional Requirements

- ✅ All functional requirements (FR-095 through FR-135) implemented
- ✅ All user acceptance scenarios passing
- ✅ Independent test criteria validated for each user story

### Quality Metrics

- **Test Coverage**: >90% for wizard and inspector modules
- **Performance**:
  - Wizard keyboard response <50ms
  - Inspector property display <100ms
  - Memory usage <100MB with 1000+ apps
- **Reliability**:
  - No zombie processes
  - 100% resource cleanup
  - Atomic saves, no corruption

### User Experience

- **Time to Value**: New user completes setup in <5 minutes
- **Ease of Use**: Keyboard shortcuts discoverable, help always visible
- **Error Recovery**: Clear error messages, undo/redo works

---

## Next Steps

1. **Review this roadmap** with team/stakeholders
2. **Validate estimates** based on team velocity
3. **Prioritize MVP scope** if time-constrained
4. **Set up development environment**:
   - Install pytest-textual: `pip install pytest-textual`
   - Verify Textual version: `python -c "import textual; print(textual.__version__)"`
5. **Start with Sprint 1**: Write wizard tests (T045-T052)

---

## Appendix: Task Reference

### Complete Task List

**Phase 5: Wizard TUI (23 tasks)**
- T045-T052: TUI Tests (8 tests)
- T053-T055: Data Models & Widgets (3 tasks)
- T056-T062: Screen & App (7 tasks)
- T063-T067: Advanced Features (5 tasks)

**Phase 6: Inspector TUI (22 tasks)**
- T068-T075: TUI Tests (8 tests)
- T076-T078: Selection & IPC (3 tasks)
- T079-T082: Widgets (4 tasks)
- T083-T086: Screen & App (4 tasks)
- T087-T089: Integration (3 tasks)

**Phase 7: Polish (12 tasks)**
- T090-T094: Error Handling (5 tasks)
- T095-T098: Documentation (4 tasks)
- T099-T101: Final Integration (3 tasks)

**Total: 57 tasks remaining**

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Status**: Ready for Implementation
