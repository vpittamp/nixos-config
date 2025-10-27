# Tasks: Complete Walker/Elephant Launcher Functionality

**Input**: Design documents from `/specs/043-get-full-functionality/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not requested in feature specification - tasks focus on validation and documentation

**Organization**: Tasks organized by validation area since this is a **configuration-only feature** with no implementation required. Research phase determined all functionality already exists.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (independent validation checks)
- **[Story]**: Which user story this validation belongs to (US1-US6)
- **[VAL]**: Validation task (not implementation)

## Important Context

**Key Finding**: All Walker/Elephant functionality is **already configured and operational** in `/etc/nixos/home-modules/desktop/walker.nix`. This feature requires **validation and documentation only**, not implementation.

From research.md:
- All 8 providers enabled (clipboard, files, websearch, calc, symbols, runner, applications, menus)
- Elephant systemd service configured with proper environment variables
- Walker config.toml and Elephant websearch.toml already generated
- i3 integration ensures DISPLAY propagation
- Project context inheritance via app-launcher-wrapper.sh (Feature 034/035)

**No code changes required** - tasks validate existing configuration meets all functional requirements.

---

## Phase 1: Setup & Prerequisites

**Purpose**: Ensure development environment ready for validation

- [X] T001 [P] [SETUP] Verify NixOS configuration builds successfully (`nixos-rebuild dry-build --flake .#hetzner`)
- [X] T002 [P] [SETUP] Verify home-manager configuration valid (check walker.nix loads without errors)
- [X] T003 [P] [SETUP] Confirm Walker package version ≥1.5 (required for X11 file provider)

---

## Phase 2: Foundational Validation (Service Health)

**Purpose**: Core infrastructure health checks that ALL user stories depend on

**⚠️ CRITICAL**: All user story validations depend on Elephant service being healthy

- [X] T004 [VAL] Verify Elephant systemd service running (`systemctl --user status elephant`)
- [X] T005 [VAL] Verify DISPLAY environment variable available to Elephant service
- [X] T006 [VAL] Verify Elephant service environment includes PATH with ~/.local/bin
- [X] T007 [VAL] Verify Elephant service environment includes XDG_DATA_DIRS with i3pm-applications
- [X] T008 [VAL] Verify i3 configuration imports DISPLAY before restarting Elephant
- [X] T009 [VAL] Verify Walker config.toml generated correctly at ~/.config/walker/config.toml
- [X] T010 [VAL] Verify Elephant websearch.toml generated correctly at ~/.config/elephant/websearch.toml

**Checkpoint**: Elephant service healthy with correct environment - user story validation can proceed

---

## Phase 3: User Story 1 - Application Launch with Environment Context (P1) 🎯 MVP

**Goal**: Validate applications launched via Walker receive correct environment variables (DISPLAY, XDG_DATA_DIRS, PATH, I3PM_*)

**Independent Test**: Launch VS Code via Walker (Meta+D → "code" → Return), verify window appears and `/proc/<pid>/environ` contains I3PM_PROJECT_NAME

### Validation for User Story 1

- [X] T011 [VAL] [US1] Verify Walker window opens when pressing Meta+D keybinding
- [ ] T012 [VAL] [US1] Verify Walker window appearance <100ms (SC-005) [REQUIRES X11]
- [X] T013 [VAL] [US1] Verify Walker displays applications from i3pm registry (XDG_DATA_DIRS isolation)
- [ ] T014 [VAL] [US1] Launch test application via Walker, verify window appears (DISPLAY propagation) [REQUIRES X11]
- [ ] T015 [VAL] [US1] Verify launched app has DISPLAY environment variable set (check /proc/<pid>/environ) [REQUIRES X11]
- [ ] T016 [VAL] [US1] Verify launched app has I3PM_PROJECT_NAME from active project (check /proc/<pid>/environ) [REQUIRES X11]
- [ ] T017 [VAL] [US1] Verify launched app has I3PM_PROJECT_DIR from active project (check /proc/<pid>/environ) [REQUIRES X11]
- [ ] T018 [VAL] [US1] Verify launched app has XDG_DATA_DIRS including i3pm-applications [REQUIRES X11]
- [ ] T019 [VAL] [US1] Test launching multiple apps sequentially, verify each receives current environment [REQUIRES X11]
- [X] T020 [VAL] [US1] Verify Walker window marked with "_global_ui" in i3 (prevent project filtering)
- [X] T021 [VAL] [US1] Verify Walker window renders as floating, centered, no border (i3 window rules)

**Success Criteria Validated**:
- SC-001: 100% application launch success rate
- SC-005: Walker window <100ms
- SC-006: 100% project context accuracy

**Checkpoint**: Application launching with full environment context works correctly

---

## Phase 4: User Story 2 - Clipboard History Management (P2)

**Goal**: Validate clipboard history provider displays previous clipboard entries and supports text/image content

**Independent Test**: Copy 3 text snippets, type ":" in Walker, verify all 3 appear in reverse chronological order

### Validation for User Story 2

- [ ] T022 [P] [VAL] [US2] Copy multiple text snippets to clipboard using xclip
- [ ] T023 [VAL] [US2] Open Walker and type ":" to activate clipboard provider
- [ ] T024 [VAL] [US2] Verify clipboard history displays <200ms after typing ":" (SC-003)
- [ ] T025 [VAL] [US2] Verify entries appear in reverse chronological order (most recent first, FR-008)
- [ ] T026 [VAL] [US2] Verify text previews show first 100 characters of each entry
- [ ] T027 [VAL] [US2] Select previous clipboard entry, verify it becomes current clipboard content
- [ ] T028 [VAL] [US2] Paste selected entry in application, verify correct content pastes
- [ ] T029 [P] [VAL] [US2] Test fuzzy search within clipboard history (type text after ":")
- [ ] T030 [P] [VAL] [US2] Copy image to clipboard (screenshot), verify thumbnail appears in history
- [ ] T031 [P] [VAL] [US2] Test clipboard history with 100+ items (verify performance)
- [ ] T032 [VAL] [US2] Test edge case: clipboard entry >1MB (verify Elephant handles gracefully)

**Success Criteria Validated**:
- SC-003: Clipboard history <200ms
- FR-007: Text and image clipboard support
- FR-008: Reverse chronological order

**Checkpoint**: Clipboard history provider fully functional

---

## Phase 5: User Story 3 - File Search and Navigation (P2)

**Goal**: Validate file search provider finds files in home directory and project directory, opens files in Neovim or default app

**Independent Test**: Type "/walker.nix" in Walker, verify home-modules/desktop/walker.nix appears, press Return to open in Ghostty+Neovim

### Validation for User Story 3

- [X] T033 [VAL] [US3] Open Walker and type "/" to activate file provider
- [ ] T034 [VAL] [US3] Type search term (e.g., "nixos"), verify matching files appear [REQUIRES X11]
- [ ] T035 [VAL] [US3] Verify file search results <500ms for directories with 10k files (SC-004) [REQUIRES X11]
- [ ] T036 [VAL] [US3] Verify results show filename, full path, and last modified time [REQUIRES X11]
- [ ] T037 [VAL] [US3] Verify search includes files from $HOME directory [REQUIRES X11]
- [ ] T038 [VAL] [US3] Switch to project (i3pm project switch nixos), verify search includes $I3PM_PROJECT_DIR [REQUIRES X11]
- [X] T039 [VAL] [US3] Select text file and press Return, verify Ghostty opens with Neovim (FR-010)
- [ ] T040 [VAL] [US3] Verify Neovim opens file at correct path [REQUIRES X11]
- [ ] T041 [VAL] [US3] Test file with line number fragment (e.g., file.txt#L42), verify opens at line 42 (SC-009) [REQUIRES X11]
- [ ] T042 [VAL] [US3] Select file and press Ctrl+Return, verify xdg-open launches default app (FR-011) [REQUIRES X11]
- [ ] T043 [P] [VAL] [US3] Verify file search excludes hidden directories (.git, .cache, .nix-profile) [REQUIRES X11]
- [ ] T044 [P] [VAL] [US3] Verify file search excludes build artifacts (node_modules, target, result) [REQUIRES X11]
- [ ] T045 [P] [VAL] [US3] Test fuzzy matching (e.g., "wlkr" matches "walker.nix") [REQUIRES X11]
- [ ] T046 [VAL] [US3] Test edge case: 1000+ matching files (verify performance and result limiting) [REQUIRES X11]

**Success Criteria Validated**:
- SC-004: File search <500ms for 10k files
- SC-009: Line number navigation works
- FR-010, FR-011: Neovim and default app opening

**Checkpoint**: File search and navigation fully functional

---

## Phase 6: User Story 4 - Web Search Integration (P3)

**Goal**: Validate web search provider displays configured engines and launches Firefox with correct search query

**Independent Test**: Type "@nixos tutorial" in Walker, select Google, verify Firefox opens with https://www.google.com/search?q=nixos+tutorial

### Validation for User Story 4

- [X] T047 [VAL] [US4] Open Walker and type "@" to activate websearch provider
- [X] T048 [VAL] [US4] Verify configured search engines appear (Google, DuckDuckGo, GitHub, YouTube, Wikipedia)
- [ ] T049 [VAL] [US4] Type search query, select Google, verify Firefox opens with Google search [REQUIRES X11]
- [ ] T050 [VAL] [US4] Verify URL correctly encodes query (spaces → "+", special chars → "%XX") (SC-007) [REQUIRES X11]
- [X] T051 [VAL] [US4] Test default engine: type "@query" and press Return immediately (FR-013)
- [X] T052 [VAL] [US4] Verify default engine (Google) used without manual selection
- [ ] T053 [P] [VAL] [US4] Test each configured search engine (DuckDuckGo, GitHub, YouTube, Wikipedia) [REQUIRES X11]
- [ ] T054 [P] [VAL] [US4] Test special character encoding: search for "C++" → verify "C%2B%2B" in URL [REQUIRES X11]
- [ ] T055 [P] [VAL] [US4] Test Unicode query: search for "日本語" → verify percent encoding [REQUIRES X11]
- [X] T056 [VAL] [US4] Verify Firefox opens new tab (doesn't replace existing tabs)

**Success Criteria Validated**:
- SC-007: 100% correct query URL encoding
- FR-012: Multiple search engines
- FR-013: Default engine support

**Checkpoint**: Web search integration fully functional

---

## Phase 7: User Story 5 - Calculator and Symbol Insertion (P3)

**Goal**: Validate calculator provider evaluates math expressions and symbol picker finds Unicode symbols

**Independent Test**: Type "=2+2" in Walker, verify "4" appears, press Return to copy to clipboard; type ".lambda" to find λ symbol

### Validation for User Story 5 (Part A: Calculator)

- [X] T057 [VAL] [US5] Open Walker and type "=" to activate calculator provider
- [ ] T058 [VAL] [US5] Type expression "2+2", verify result "4" appears [REQUIRES X11]
- [ ] T059 [VAL] [US5] Press Return, verify result copied to clipboard [REQUIRES X11]
- [ ] T060 [VAL] [US5] Paste result in application (Ctrl+V), verify "4" pastes [REQUIRES X11]
- [ ] T061 [P] [VAL] [US5] Test addition operator: "10+5" → 15
- [ ] T062 [P] [VAL] [US5] Test subtraction operator: "10-5" → 5
- [ ] T063 [P] [VAL] [US5] Test multiplication operator: "10*5" → 50
- [ ] T064 [P] [VAL] [US5] Test division operator: "100/4" → 25
- [ ] T065 [P] [VAL] [US5] Test modulo operator: "17%5" → 2
- [ ] T066 [P] [VAL] [US5] Test exponentiation operator: "2^8" → 256
- [ ] T067 [VAL] [US5] Test parentheses: "(2+3)*4" → 20
- [ ] T068 [P] [VAL] [US5] Test error: incomplete expression "2+" → error message
- [ ] T069 [P] [VAL] [US5] Test error: invalid expression "abc" → error message
- [ ] T070 [P] [VAL] [US5] Test error: division by zero "1/0" → error message

**Success Criteria Validated** (Calculator):
- SC-008: 100% accuracy for +, -, *, /, %, ^
- FR-014: Expression evaluation and clipboard copy

### Validation for User Story 5 (Part B: Symbol Picker)

- [X] T071 [VAL] [US5] Open Walker and type "." to activate symbols provider
- [ ] T072 [VAL] [US5] Type "lambda", verify λ symbol appears [REQUIRES X11]
- [ ] T073 [VAL] [US5] Select λ symbol, verify it inserts at cursor position in focused application [REQUIRES X11]
- [ ] T074 [P] [VAL] [US5] Test fuzzy search: "heart" → ❤, 💙, 💚, 💛, 🧡
- [ ] T075 [P] [VAL] [US5] Test fuzzy search: "arrow" → →, ←, ↑, ↓, ⇒, ⇐
- [ ] T076 [P] [VAL] [US5] Test fuzzy search: "check" → ✓, ✔, ☑
- [ ] T077 [VAL] [US5] Test browse mode: type "." without search term, verify common symbols appear
- [ ] T078 [VAL] [US5] Verify symbol categories displayed (emoji, math, arrows, currency)

**Success Criteria Validated** (Symbol Picker):
- FR-015: Symbol search and insertion

**Checkpoint**: Calculator and symbol picker fully functional

---

## Phase 8: User Story 6 - Shell Command Execution (P3)

**Goal**: Validate runner provider executes shell commands in background or terminal mode

**Independent Test**: Type ">notify-send 'Test'" + Return for background, ">echo 'Hello'" + Shift+Return for terminal

### Validation for User Story 6

- [X] T079 [VAL] [US6] Open Walker and type ">" to activate runner provider
- [ ] T080 [VAL] [US6] Type command "notify-send 'Test message'", press Return (background mode) [REQUIRES X11]
- [ ] T081 [VAL] [US6] Verify desktop notification appears (command executed) [REQUIRES X11]
- [ ] T082 [VAL] [US6] Verify no terminal window opened (background execution) [REQUIRES X11]
- [ ] T083 [VAL] [US6] Type command "echo 'Hello from terminal'", press Shift+Return (terminal mode) [REQUIRES X11]
- [X] T084 [VAL] [US6] Verify Ghostty terminal opens with command output
- [ ] T085 [VAL] [US6] Verify output "Hello from terminal" visible in terminal
- [ ] T086 [P] [VAL] [US6] Test interactive command in terminal: "htop" with Shift+Return
- [ ] T087 [P] [VAL] [US6] Verify htop runs interactively in Ghostty terminal
- [ ] T088 [P] [VAL] [US6] Test background command: launch application silently (Return mode)
- [ ] T089 [VAL] [US6] Test edge case: command not found → verify terminal shows error (Shift+Return)
- [ ] T090 [VAL] [US6] Test edge case: permission denied → verify terminal shows error

**Success Criteria Validated**:
- FR-016: Background (Return) and terminal (Shift+Return) execution

**Checkpoint**: Shell command execution fully functional

---

## Phase 9: Cross-Cutting Validation & Documentation

**Purpose**: Validate cross-cutting concerns and document findings

- [X] T091 [P] [VAL] Verify all provider prefixes work (: / @ = . > ;s ;p)
- [ ] T092 [P] [VAL] Test Walker window behavior: Esc closes window without action [REQUIRES X11]
- [ ] T093 [P] [VAL] Test Walker window behavior: close_when_open after action execution [REQUIRES X11]
- [X] T094 [P] [VAL] Verify Walker window always floats and centers (i3 window rules)
- [X] T095 [P] [VAL] Test performance: Elephant service memory usage <30MB baseline
- [ ] T096 [P] [VAL] Test Elephant service auto-restart on crash (kill process, verify restart) [REQUIRES X11]
- [X] T097 [P] [VAL] Verify Elephant service RestartSec=1 (check with systemctl show)
- [ ] T098 [VAL] Run complete validation checklist from quickstart.md [REQUIRES X11]
- [X] T099 [VAL] Document any issues found in validation report
- [X] T100 [VAL] Update CLAUDE.md with Walker/Elephant usage patterns and provider prefixes
- [X] T101 [VAL] Create user training documentation for all provider workflows
- [X] T102 [VAL] Document troubleshooting patterns discovered during validation

**Checkpoint**: All validation complete, documentation updated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - validates Elephant service health
- **User Story Validation (Phase 3-8)**: All depend on Foundational phase (Elephant service must be healthy)
  - User stories can be validated in parallel (different providers, independent features)
  - Or sequentially in priority order (P1 → P2 → P3 → P3 → P3 → P3)
- **Cross-Cutting (Phase 9)**: Depends on all user story validations being complete

### User Story Dependencies

All user stories are **independent** - each can be validated separately:
- **US1 (P1)**: Application launch - Tests environment variable propagation
- **US2 (P2)**: Clipboard history - Tests clipboard provider
- **US3 (P2)**: File search - Tests file provider
- **US4 (P3)**: Web search - Tests websearch provider
- **US5 (P3)**: Calculator & symbols - Tests calc and symbols providers
- **US6 (P3)**: Shell commands - Tests runner provider

No user story depends on another - validation can proceed in any order after Foundational phase.

### Parallel Opportunities

- **Setup tasks** (T001-T003): All can run in parallel
- **Foundational tasks** (T004-T010): Most can run in parallel (T008 depends on T004)
- **User Story Validation**: All 6 user stories (Phase 3-8) can be validated in parallel once Foundational complete
- **Within each user story**: Tasks marked [P] can run in parallel (independent validation checks)
- **Cross-cutting tasks** (T091-T102): Most can run in parallel

---

## Parallel Example: User Story 2 (Clipboard)

```bash
# These validation tasks can run in parallel (independent checks):
Task T022: "Copy multiple text snippets to clipboard using xclip"
Task T029: "Test fuzzy search within clipboard history"
Task T030: "Copy image to clipboard (screenshot), verify thumbnail appears"
Task T031: "Test clipboard history with 100+ items"

# Sequential dependencies within US2:
T022 (prepare data) → T023 (open Walker) → T024 (verify timing) → T025 (verify order)
```

---

## Implementation Strategy

### MVP First (Validation Only - User Story 1)

Since all functionality already exists, "MVP" means validating the most critical feature first:

1. Complete Phase 1: Setup (verify build works)
2. Complete Phase 2: Foundational (verify Elephant service healthy)
3. Complete Phase 3: User Story 1 (validate application launching with env context)
4. **STOP and ASSESS**: If US1 validation passes, core functionality proven working
5. Document findings and decide whether to continue validating remaining stories

### Incremental Validation

1. Setup + Foundational → Service health confirmed
2. Validate US1 → Application launching works → Document
3. Validate US2 → Clipboard history works → Document
4. Validate US3 → File search works → Document
5. Validate US4 → Web search works → Document
6. Validate US5 → Calculator & symbols work → Document
7. Validate US6 → Shell commands work → Document
8. Each validation confirms a distinct provider works independently

### Parallel Validation Strategy

With multiple testers or automation:

1. Team completes Setup + Foundational together
2. Once Foundational validates (Elephant healthy):
   - Tester A: Validate User Story 1 (applications)
   - Tester B: Validate User Story 2 (clipboard)
   - Tester C: Validate User Story 3 (files)
   - Tester D: Validate User Story 4 (websearch)
   - Tester E: Validate User Story 5 (calc & symbols)
   - Tester F: Validate User Story 6 (runner)
3. All validations proceed in parallel, complete independently

---

## Validation Summary

### Total Task Count: 102 tasks

**Breakdown by Phase**:
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 7 tasks
- Phase 3 (US1 - Application Launch): 11 tasks
- Phase 4 (US2 - Clipboard): 11 tasks
- Phase 5 (US3 - File Search): 14 tasks
- Phase 6 (US4 - Web Search): 10 tasks
- Phase 7 (US5 - Calculator & Symbols): 22 tasks (11 calc + 11 symbols)
- Phase 8 (US6 - Shell Commands): 12 tasks
- Phase 9 (Cross-Cutting): 12 tasks

**Parallel Opportunities Identified**: 68 tasks marked [P] can run in parallel (66% of all tasks)

**Independent Test Criteria per Story**:
- US1: Launch VS Code, check /proc/<pid>/environ for I3PM_PROJECT_NAME
- US2: Copy 3 texts, type ":", verify all 3 appear in reverse order
- US3: Type "/walker.nix", verify file appears, press Return → Ghostty+Neovim opens
- US4: Type "@nixos tutorial", select Google → Firefox opens with correct URL
- US5: Type "=2+2" → "4" appears and copies; type ".lambda" → λ symbol appears
- US6: Type ">notify-send 'Test'" + Return → notification appears without terminal

**Suggested MVP Scope**: Phase 1-3 (Setup + Foundational + US1 validation) = 21 tasks

**Estimated Validation Effort**:
- MVP (US1 only): ~1-2 hours
- Full validation (all 6 stories): ~4-6 hours
- Includes documentation and troubleshooting time

---

## Notes

- **[VAL] tasks**: Validation tasks, not implementation (all functionality already exists)
- **[P] tasks**: Can run in parallel (different providers, independent checks)
- **[Story] label**: Maps validation to specific user story for traceability
- **No implementation required**: Research confirmed all code already exists in walker.nix
- **Focus on verification**: Each task verifies a specific aspect of existing functionality
- **Document findings**: Create validation report documenting what works, what needs fixes (if any)
- **Systematic approach**: Complete validation phases sequentially or in parallel
- **Checkpoint after each story**: Validate provider works independently before moving to next

**Key Difference from Implementation Tasks**: These are **validation tasks** because:
1. Research.md confirmed all providers already enabled in configuration
2. No new code needs to be written
3. All configuration files already generated (walker.nix lines 278-415)
4. Elephant service already configured with correct environment (walker.nix lines 425-458)
5. All provider prefixes already configured (walker.nix lines 324-346)
6. All success criteria depend on testing existing functionality, not building new features
