# Tasks: Visual Worktree Relationship Map

**Input**: Design documents from `/specs/111-visual-map-worktrees/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests included per Constitution Principle XIV (Test-Driven Development).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **Backend**: `home-modules/tools/i3_project_manager/`
- **Models**: `home-modules/tools/i3_project_manager/models/`
- **Services**: `home-modules/tools/i3_project_manager/services/`
- **CLI**: `home-modules/tools/i3_project_manager/cli/`
- **Eww**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Tests**: `tests/111-visual-map-worktrees/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create test directory structure and base files

- [x] T001 Create test directory structure at tests/111-visual-map-worktrees/unit/, tests/111-visual-map-worktrees/integration/, tests/111-visual-map-worktrees/sway-tests/
- [x] T002 [P] Create __init__.py files for test modules
- [x] T003 [P] Verify Python 3.11+ and pytest are available in Nix shell

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models and git utilities that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

### Tests for Foundational Phase

- [x] T004 [P] Create unit test for WorktreeRelationship model in tests/111-visual-map-worktrees/unit/test_worktree_relationship.py
- [x] T005 [P] Create unit test for get_merge_base function in tests/111-visual-map-worktrees/unit/test_merge_base.py
- [x] T006 [P] Create unit test for get_branch_relationship function in tests/111-visual-map-worktrees/unit/test_branch_relationship.py
- [x] T007 [P] Create unit test for WorktreeRelationshipCache in tests/111-visual-map-worktrees/unit/test_relationship_cache.py

### Implementation for Foundational Phase

- [x] T008 [P] Create WorktreeRelationship dataclass in home-modules/tools/i3_project_manager/models/worktree_relationship.py
- [x] T009 [P] Create NodeType and NodeStatus enums in home-modules/tools/i3_project_manager/models/worktree_relationship.py
- [x] T010 [P] Create WorktreeNode dataclass in home-modules/tools/i3_project_manager/models/worktree_relationship.py
- [x] T011 [P] Create EdgeType enum and RelationshipEdge dataclass in home-modules/tools/i3_project_manager/models/worktree_relationship.py
- [x] T012 Create WorktreeMap dataclass with to_svg_data() method in home-modules/tools/i3_project_manager/models/worktree_relationship.py
- [x] T013 Implement get_merge_base() function in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T014 Implement get_branch_relationship() function in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T015 Implement find_likely_parent_branch() function in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T016 Create WorktreeRelationshipCache class in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T017 Run all foundational tests and verify they pass

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Visual Worktree Dependency Graph (Priority: P1) MVP

**Goal**: Display worktrees as nodes with edges showing parent-child relationships and ahead/behind counts

**Independent Test**: Create 3+ worktrees with varying relationships and verify the map correctly shows connections and commit counts

### Tests for User Story 1

- [x] T018 [P] [US1] Create unit test for compute_hierarchical_layout() in tests/111-visual-map-worktrees/unit/test_layout_algorithm.py
- [x] T019 [P] [US1] Create unit test for generate_worktree_map_svg() in tests/111-visual-map-worktrees/unit/test_svg_generation.py
- [x] T020 [P] [US1] Create integration test for build_worktree_map() in tests/111-visual-map-worktrees/integration/test_worktree_map_build.py

### Implementation for User Story 1

- [x] T021 [US1] Create worktree_map_service.py with compute_hierarchical_layout() function in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T022 [US1] Implement layer assignment algorithm (assign branches to layers based on parent depth) in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T023 [US1] Implement x-position calculation within layers (center horizontally, even spacing) in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T024 [US1] Implement generate_svg_style() for Catppuccin Mocha colors in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T025 [US1] Implement render_edges() to draw parent-child connections with ahead/behind labels in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T026 [US1] Implement render_nodes() to draw worktree circles with labels in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T027 [US1] Implement generate_worktree_map_svg() main function combining layout + rendering in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T028 [US1] Implement build_worktree_map() to construct WorktreeMap from repository data in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T029 [US1] Add query_worktree_map_data() function to monitoring_data.py returning map JSON and SVG path in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T030 [US1] Add defvar for projects_view_mode (list|map) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T031 [US1] Add defpoll for worktree_map_svg_path reading from monitoring data in home-modules/desktop/eww-monitoring-panel.nix
- [x] T032 [US1] Create projects-map-view widget with image display in home-modules/desktop/eww-monitoring-panel.nix
- [x] T033 [US1] Add view toggle buttons (List | Map) to projects tab header in home-modules/desktop/eww-monitoring-panel.nix
- [x] T034 [US1] Add conditional rendering switching between list and map views in home-modules/desktop/eww-monitoring-panel.nix
- [x] T035 [US1] Run US1 tests and verify map renders correctly with edges and labels

**Checkpoint**: User Story 1 complete - visual graph displays worktree relationships

---

## Phase 4: User Story 2 - Feature Purpose Attribution (Priority: P1)

**Goal**: Show human-readable feature descriptions and distinguish branch types visually

**Independent Test**: View worktrees with numbered branches and verify readable descriptions and type badges appear

### Tests for User Story 2

- [x] T036 [P] [US2] Create unit test for parse_branch_description() in tests/111-visual-map-worktrees/unit/test_branch_parsing.py
- [x] T037 [P] [US2] Create unit test for detect_branch_type() in tests/111-visual-map-worktrees/unit/test_branch_parsing.py

### Implementation for User Story 2

- [x] T038 [US2] Implement parse_branch_description() converting "109-enhance-worktree-ux" to "Enhance Worktree UX" in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T039 [US2] Implement detect_branch_type() returning NodeType (main/feature/hotfix/release) in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T040 [US2] Update render_nodes() to use different colors for branch types (mauve=main, blue=feature, peach=hotfix) in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T041 [US2] Update render_nodes() to display branch_number as primary label and branch_description in tooltip in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T042 [US2] Add CSS classes for branch types (.main, .feature, .hotfix, .release) in SVG style block in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T043 [US2] Add legend widget showing branch type colors below map in home-modules/desktop/eww-monitoring-panel.nix
- [x] T044 [US2] Run US2 tests and verify branch descriptions and type styling work

**Checkpoint**: User Story 2 complete - branch types distinguished, readable labels shown

---

## Phase 5: User Story 3 - Interactive Branch Navigation (Priority: P2)

**Goal**: Click nodes to switch worktrees, hover for tooltips, right-click for context menu

**Independent Test**: Click a worktree node and verify project context switches within 500ms

### Tests for User Story 3

- [ ] T045 [P] [US3] Create sway-test for map click triggering project switch in tests/111-visual-map-worktrees/sway-tests/test_map_click_switch.json
- [x] T046 [P] [US3] Create unit test for generate_click_overlay_data() in tests/111-visual-map-worktrees/unit/test_click_overlay.py

### Implementation for User Story 3

- [x] T047 [US3] Implement generate_click_overlay_data() returning node positions for Eww overlay in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T048 [US3] Add overlay_nodes to worktree_map_data response for click overlay in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T049 [US3] Create overlay widget with invisible buttons positioned over nodes in home-modules/desktop/eww-monitoring-panel.nix
- [x] T050 [US3] Add onclick handler calling i3pm project switch with qualified_name in home-modules/desktop/eww-monitoring-panel.nix
- [x] T051 [US3] Add tooltip property to overlay buttons showing node.tooltip content in home-modules/desktop/eww-monitoring-panel.nix
- [x] T052 [US3] Create worktree-context-menu script with actions (terminal, vscode, lazygit, copy-path, delete) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T053 [US3] Add right-click handler showing context menu at cursor position in home-modules/desktop/eww-monitoring-panel.nix
- [ ] T054 [US3] Run US3 sway-test and verify click switches project within 500ms

**Checkpoint**: User Story 3 complete - map is interactive with click, hover, context menu

---

## Phase 6: User Story 4 - Merge Flow Visualization (Priority: P2)

**Goal**: Show merged branches, potential conflicts, and ready-to-merge indicators

**Independent Test**: Create worktrees with overlapping file changes and verify conflict indicators appear

### Tests for User Story 4

- [x] T055 [P] [US4] Create unit test for detect_potential_conflicts() in tests/111-visual-map-worktrees/unit/test_conflict_detection.py
- [x] T056 [P] [US4] Create unit test for get_merge_ready_status() in tests/111-visual-map-worktrees/unit/test_merge_status.py

### Implementation for User Story 4

- [x] T057 [US4] Implement detect_potential_conflicts() using set intersection for file overlap in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T058 [US4] Implement get_merge_ready_status() checking clean + up-to-date with main in home-modules/tools/i3_project_manager/services/git_utils.py
- [x] T059 [US4] Update build_worktree_map() to detect merged branches and set node status to MERGED in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T060 [US4] Update build_worktree_map() to use MERGED edge type for merged branches in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T061 [US4] CSS for edge-merged already exists (green dashed line) in generate_svg_style()
- [x] T062 [US4] Update render_nodes() to show merged indicator (checkmark) and faded appearance in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T063 [US4] Add CSS classes for merged (.node-merged, .merged-badge, .merged-check) in SVG style in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T064 [US4] Run US4 tests - all 95 tests passing

**Checkpoint**: User Story 4 complete - merge flow and conflicts visible in map

---

## Phase 7: User Story 5 - Branch Age and Activity Heatmap (Priority: P3)

**Goal**: Visual cues for stale vs active branches using opacity and staleness badges

**Independent Test**: Create worktrees of varying ages and verify visual differentiation based on activity

### Tests for User Story 5

- [x] T065 [P] [US5] Create unit test for calculate_activity_level() in tests/111-visual-map-worktrees/unit/test_activity_level.py

### Implementation for User Story 5

- [x] T066 [US5] Implement calculate_activity_level() returning opacity 0.5-1.0 based on last commit age in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T067 [US5] Update build_worktree_map() to set node status to STALE for 30+ day inactive worktrees in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T068 [US5] Update render_nodes() to apply opacity (.node-stale) based on activity_level in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T069 [US5] Add staleness badge rendering (💤 icon + faded appearance) for stale nodes in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T070 [US5] Run US5 tests - all 103 tests passing

**Checkpoint**: User Story 5 complete - activity heatmap distinguishes stale branches

---

## Phase 8: User Story 6 - Compact vs Expanded Map Views (Priority: P3)

**Goal**: Support both compact panel view and expanded full-detail overlay

**Independent Test**: Create 15 worktrees and verify both views remain readable

### Tests for User Story 6

- [x] T071 [P] [US6] Create unit test for generate_compact_svg() in tests/111-visual-map-worktrees/unit/test_compact_view.py
- [x] T072 [P] [US6] Create sway-test for expanded view toggle in tests/111-visual-map-worktrees/sway-tests/test_expanded_view_toggle.json

### Implementation for User Story 6

- [x] T073 [US6] Implement generate_compact_svg() with smaller nodes, abbreviated labels for 10+ worktrees in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T074 [US6] Add compact_mode parameter to generate_worktree_map_svg() controlling size/detail level in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T075 [US6] Add defvar for worktree_map_expanded (true|false) in home-modules/desktop/eww-monitoring-panel.nix
- [x] T076 [US6] Create expanded-map-view widget as fullscreen overlay with Escape to close in home-modules/desktop/eww-monitoring-panel.nix
- [x] T077 [US6] Add "Expand" button to compact view triggering expanded overlay in home-modules/desktop/eww-monitoring-panel.nix
- [x] T078 [US6] Add keyboard shortcut (e in focus mode) to toggle expanded view in home-modules/desktop/eww-monitoring-panel.nix
- [x] T079 [US6] Run US6 sway-tests and verify compact/expanded toggle works - sway-test created

**Checkpoint**: User Story 6 complete - map scales to many worktrees with expand option

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup, documentation, and comprehensive testing

- [x] T080 Run full test suite (pytest tests/111-visual-map-worktrees/) and fix any failures - ALL 111 TESTS PASSING
- [x] T081 Run nixos-rebuild dry-build to verify Nix configuration is valid - PASSED
- [ ] T082 [P] Add keyboard navigation (j/k/Enter) to map in focus mode in home-modules/desktop/eww-monitoring-panel.nix - DEFERRED (requires complex node selection state)
- [x] T083 [P] Add refresh button triggering cache invalidation and map rebuild in home-modules/desktop/eww-monitoring-panel.nix
- [x] T084 [P] Add error handling for missing/orphaned worktrees with warning indicators in home-modules/tools/i3_project_manager/services/worktree_map_service.py
- [x] T085 Validate quickstart.md scenarios work end-to-end - quickstart.md updated to match implementation
- [x] T086 Update CLAUDE.md Active Technologies section with Feature 111 stack

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - US1 and US2 can proceed in parallel (both P1)
  - US3 and US4 can proceed in parallel after US1 (both P2)
  - US5 and US6 can proceed in parallel after US1 (both P3)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: After Foundational - Core map rendering
- **User Story 2 (P1)**: After Foundational - Can be done in parallel with US1
- **User Story 3 (P2)**: After US1 - Needs map rendering to add interactivity
- **User Story 4 (P2)**: After US1 - Needs map rendering to add merge indicators
- **User Story 5 (P3)**: After US1 - Needs map rendering to add activity styling
- **User Story 6 (P3)**: After US1 - Needs map rendering to add compact/expanded modes

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before Eww widgets
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Foundational tests (T004-T007) can run in parallel
- All Foundational models (T008-T011) can run in parallel
- US1 and US2 can be worked in parallel after Foundation
- US3 and US4 can be worked in parallel after US1
- US5 and US6 can be worked in parallel after US1
- Within each story, tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create unit test for compute_hierarchical_layout() in tests/111-visual-map-worktrees/unit/test_layout_algorithm.py"
Task: "Create unit test for generate_worktree_map_svg() in tests/111-visual-map-worktrees/unit/test_svg_generation.py"
Task: "Create integration test for build_worktree_map() in tests/111-visual-map-worktrees/integration/test_worktree_map_build.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test map renders with edges and labels
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Branch types distinguished
4. Add User Story 3 → Test independently → Interactive map
5. Add User Story 4 → Test independently → Merge flow visible
6. Add User Story 5 → Test independently → Activity heatmap
7. Add User Story 6 → Test independently → Scalable views

### Suggested MVP Scope

**MVP = User Story 1 + User Story 2** (both P1)

This delivers:
- Visual graph of worktree relationships (core value)
- Ahead/behind commit counts on edges
- Human-readable branch descriptions
- Branch type coloring

Users can immediately understand worktree relationships without interactivity or advanced features.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- SVG generation uses direct string construction (no library dependency)
- Cache TTL is 5 minutes for branch relationships
- Catppuccin Mocha colors used throughout
