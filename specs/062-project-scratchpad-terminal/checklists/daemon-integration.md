# Implementation Checklist: Daemon Integration (Option B)

**Purpose**: Validate requirements quality for migrating scratchpad terminal to daemon-based architecture with unified launcher integration (Features 041/057 alignment)

**Created**: 2025-11-05
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)
**Scope**: Daemon RPC handlers, unified launcher integration, Ghostty terminal, replacing shell script approach

**Focus Areas**: State synchronization, launch notification correlation, environment variable propagation, error handling

---

## Requirement Completeness

### Daemon RPC Integration

- [x] CHK001 - Are JSON-RPC method signatures defined for all scratchpad operations (toggle, launch, status, close, cleanup)? [Completeness, contracts/scratchpad-rpc.json]
- [x] CHK002 - Are parameter validation requirements specified for each RPC method? [Completeness, Gap]
- [x] CHK003 - Are return value schemas documented for success and error cases? [Completeness, contracts/scratchpad-rpc.json]
- [x] CHK004 - Are async/await patterns specified for all daemon operations? [Completeness, Plan §Technical Context]

### Unified Launcher Integration

- [ ] CHK005 - Are requirements defined for launching scratchpad terminals via app-launcher-wrapper.sh? [Completeness, Gap]
- [ ] CHK006 - Are app-registry-data.nix entry requirements specified for scratchpad-terminal? [Completeness, Gap]
- [ ] CHK007 - Are parameter substitution requirements documented ($PROJECT_DIR, $SESSION_NAME)? [Completeness, Gap]
- [ ] CHK008 - Are systemd-run integration requirements specified for process isolation? [Completeness, Gap]

### State Synchronization (Risk Area 1)

- [x] CHK009 - Are state synchronization rules defined between daemon memory and Sway IPC? [Completeness, data-model.md §State Synchronization]
- [x] CHK010 - Are validation requirements specified for every state-mutating operation? [Completeness, data-model.md §Validation Rules]
- [x] CHK011 - Are Sway IPC query requirements (GET_TREE, GET_MARKS) documented for validation? [Completeness, research.md, Plan §Constitution Principle XI]
- [x] CHK012 - Are orphaned terminal cleanup requirements defined? [Completeness, contracts cleanup method]
- [x] CHK013 - Are window close event handling requirements specified for state cleanup? [Completeness, research.md on_window_close]

### Launch Notification Correlation (Risk Area 2)

- [ ] CHK014 - Are pre-launch notification requirements defined for Tier 0 window correlation (Feature 041)? [Completeness, Gap]
- [ ] CHK015 - Are notification payload requirements specified (app_name, project_name, expected_class, timestamp)? [Completeness, Gap]
- [ ] CHK016 - Are correlation timeout requirements defined? [Completeness, Gap]
- [ ] CHK017 - Are fallback correlation requirements specified if notification fails? [Completeness, Gap]

### Environment Variable Propagation (Risk Area 3)

- [x] CHK018 - Are required I3PM_* environment variables documented (APP_ID, APP_NAME, PROJECT_NAME, etc.)? [Completeness, data-model.md §Environment Variables]
- [ ] CHK019 - Are environment variable format requirements specified for Ghostty compatibility? [Completeness, Gap - All docs reference Alacritty]
- [x] CHK020 - Are requirements defined for reading /proc/<pid>/environ for window correlation? [Completeness, data-model.md read_process_environ()]
- [x] CHK021 - Are I3PM_SCRATCHPAD marker variable requirements documented? [Completeness, data-model.md line 321]

### Error Handling (Risk Area 4)

- [ ] CHK022 - Are error handling requirements defined for daemon unavailable scenarios? [Completeness, Gap]
- [x] CHK023 - Are recovery requirements specified for terminal process death detection? [Completeness, data-model.md §Terminal Toggle Errors]
- [ ] CHK024 - Are timeout requirements defined for all async operations? [Completeness, Gap]
- [ ] CHK025 - Are user-facing error message requirements specified? [Completeness, Gap]
- [ ] CHK026 - Are logging requirements documented for diagnostic purposes? [Completeness, Gap]

### Ghostty Terminal Specific

- [ ] CHK027 - Are Ghostty-specific launch parameter requirements defined? [Completeness, Gap]
- [ ] CHK028 - Are Ghostty app_id/class identification requirements specified? [Completeness, Gap]
- [ ] CHK029 - Are Ghostty window configuration requirements documented (floating, size, position)? [Completeness, Gap]
- [ ] CHK030 - Are requirements defined for Ghostty availability fallback to Alacritty? [Completeness, Gap]

---

## Requirement Clarity

### Daemon Architecture

- [x] CHK031 - Is "daemon state" quantified with specific data structures (ScratchpadTerminal model fields)? [Clarity, data-model.md lines 42-133]
- [x] CHK032 - Is "project-to-terminal mapping" format explicitly defined? [Clarity, data-model.md line 152]
- [x] CHK033 - Are window identification criteria clearly specified (marks, env vars, app_id)? [Clarity, research.md lines 20-41]

### Performance Targets

- [ ] CHK034 - Is "<500ms terminal toggle" quantified with measurement methodology? [Clarity, Plan §Performance Goals]
- [ ] CHK035 - Is "<2s initial launch" defined with start/end measurement points? [Clarity, Plan §Performance Goals]
- [ ] CHK036 - Is "<100ms daemon event processing" scoped to specific event types? [Clarity, Plan §Performance Goals]

### Integration Points

- [ ] CHK037 - Is "unified launcher usage" explicitly defined with app-launcher-wrapper.sh invocation pattern? [Clarity, Gap]
- [ ] CHK038 - Are "launch notification" timing requirements clearly specified (before app exec)? [Clarity, Gap]
- [ ] CHK039 - Is "environment variable injection" mechanism explicitly defined (systemd-run --setenv)? [Clarity, Gap]

---

## Requirement Consistency

### Architecture Alignment

- [ ] CHK040 - Are scratchpad RPC patterns consistent with existing i3pm daemon methods? [Consistency, Needs Verification]
- [x] CHK041 - Are environment variables consistent with Feature 057 naming conventions (I3PM_*)? [Consistency, data-model.md uses I3PM_* prefix]
- [ ] CHK042 - Are launch notification requirements consistent with Feature 041 protocol? [Consistency, Gap - Not integrated]
- [ ] CHK043 - Are window correlation requirements consistent with existing daemon window tracking? [Consistency, Partial - Uses /proc but not launch notifications]

### Terminal vs Other Apps

- [ ] CHK044 - Are scratchpad terminal requirements consistent with regular terminal app requirements (app-registry-data.nix)? [Consistency, Needs Verification]
- [x] CHK045 - Are scoped app requirements (scope="scoped") consistently applied? [Consistency, data-model.md line 326, daemon/models.py line 40]

---

## Acceptance Criteria Quality

### Measurability

- [x] CHK046 - Can "state synchronization correctness" be objectively verified via Sway IPC queries? [Measurability, data-model.md validate_terminal()]
- [ ] CHK047 - Can "launch notification correlation success" be measured with timing metrics? [Measurability, Gap - No launch notification requirements]
- [x] CHK048 - Can "environment variable propagation" be validated via /proc inspection? [Measurability, data-model.md read_process_environ(), quickstart.md examples]
- [ ] CHK049 - Can "error recovery success rate" be quantified with test scenarios? [Measurability, Gap - No success rate metrics]

### Testability

- [x] CHK050 - Are test requirements defined for daemon RPC endpoints? [Testability, plan.md §Expected Tasks, research.md §Testing Strategy]
- [ ] CHK051 - Are integration test requirements specified for launcher interaction? [Testability, Gap - No app-launcher-wrapper.sh testing]
- [x] CHK052 - Are E2E test requirements defined for user workflows (ydotool)? [Testability, research.md lines 319-379]

---

## Scenario Coverage

### Primary Flows

- [x] CHK053 - Are requirements defined for first-time terminal launch in a project? [Coverage, spec.md User Story 1, FR-001]
- [x] CHK054 - Are requirements specified for toggle hide/show of existing terminal? [Coverage, spec.md User Story 1 scenarios 2-3, FR-003]
- [x] CHK055 - Are requirements documented for multi-project terminal isolation? [Coverage, spec.md User Story 2, FR-005]
- [x] CHK056 - Are requirements defined for global terminal (no active project)? [Coverage, spec.md Edge Case 4, FR-012]

### Exception Flows

- [x] CHK057 - Are requirements specified for terminal process death scenarios? [Coverage, spec.md Edge Case 3, data-model.md recovery]
- [x] CHK058 - Are requirements defined for Sway window missing from tree? [Coverage, data-model.md validate_terminal() lines 294-300]
- [ ] CHK059 - Are requirements documented for daemon socket unavailable? [Coverage, Gap - daemon-client.ts has error handling but not in spec]
- [ ] CHK060 - Are requirements specified for concurrent toggle requests? [Coverage, Gap - No concurrency handling]

### Recovery Flows

- [x] CHK061 - Are auto-relaunch requirements defined when terminal process dies? [Coverage, spec.md Edge Case 3, contracts toggle "relaunches"]
- [x] CHK062 - Are state cleanup requirements specified for invalid terminals? [Coverage, contracts cleanup method, data-model.md cleanup_invalid_terminals()]
- [x] CHK063 - Are re-correlation requirements defined if window mark is lost? [Coverage, data-model.md validate_terminal() lines 302-306]

---

## Edge Case Coverage

### State Boundary Conditions

- [x] CHK064 - Are requirements defined for zero terminals (initial state)? [Edge Case, spec.md Edge Case 1, contracts toggle method]
- [ ] CHK065 - Are requirements specified for maximum terminals (20-30 projects)? [Edge Case, Gap - Scale mentioned but no max requirements]
- [x] CHK066 - Are requirements documented for Sway restart (state loss)? [Edge Case, spec.md FR-004 lines 142-147]

### Timing Edge Cases

- [ ] CHK067 - Are requirements defined for rapid toggle operations (<100ms apart)? [Edge Case, Gap - No rapid succession handling]
- [ ] CHK068 - Are requirements specified for launch timeout scenarios? [Edge Case, Gap - Performance goal exists but not timeout requirements]
- [ ] CHK069 - Are requirements documented for window appearing before notification processed? [Edge Case, Gap - No launch notification requirements]

### Terminal Identification Edge Cases

- [ ] CHK070 - Are requirements defined for app_id conflicts (multiple Ghostty instances)? [Edge Case, Gap - No conflict resolution]
- [x] CHK071 - Are requirements specified for missing environment variables? [Edge Case, data-model.md WindowEnvironment.from_env_dict() line 84]
- [ ] CHK072 - Are requirements documented for window mark collisions? [Edge Case, Gap - No collision handling]

---

## Dependencies & Assumptions

### External Dependencies

- [ ] CHK073 - Are Ghostty package availability requirements documented? [Dependency, Gap - spec.md mentions Alacritty only]
- [x] CHK074 - Are sesh session manager requirements specified? [Dependency, spec.md line 253 assumption]
- [ ] CHK075 - Are i3ipc.aio version requirements documented? [Dependency, Partial - Mentioned but no version]
- [ ] CHK076 - Are systemd-run availability requirements specified? [Dependency, Gap - No systemd-run requirements]

### Assumptions

- [ ] CHK077 - Is the assumption "Sway IPC is always responsive" validated? [Assumption, Gap - No validation]
- [x] CHK078 - Is the assumption "single terminal per project is sufficient" documented? [Assumption, spec.md Non-Goal line 37, Constraint line 258]
- [x] CHK079 - Is the assumption "terminals don't persist across Sway restarts" acceptable? [Assumption, spec.md FR-004 explicitly states acceptability]

---

## Migration & Replacement Requirements

### Shell Script Replacement

- [ ] CHK080 - Are requirements defined for deprecating ~/.config/sway/scripts/scratchpad-terminal-toggle.sh? [Completeness, Gap]
- [ ] CHK081 - Are keybinding update requirements specified (Mod+Shift+Return → i3pm scratchpad toggle)? [Completeness, Gap]
- [ ] CHK082 - Are requirements documented for removing shell script from Sway config generation? [Completeness, Gap]

### Window Rule Migration

- [ ] CHK083 - Are requirements specified for updating for_window rules to use I3PM_APP_NAME matching? [Completeness, Gap]
- [ ] CHK084 - Are requirements defined for window-rules.json template updates? [Completeness, Gap]

---

## Non-Functional Requirements

### Performance

- [ ] CHK085 - Are daemon memory usage requirements specified for scratchpad state? [NFR, Gap - Overall daemon yes, scratchpad-specific no]
- [ ] CHK086 - Are CPU usage requirements defined for event processing? [NFR, Gap - Overall daemon yes, scratchpad-specific no]

### Reliability

- [x] CHK087 - Are availability requirements specified (95% success rate for toggle)? [NFR, spec.md SC-002 line 213]
- [x] CHK088 - Are data consistency requirements defined for daemon state? [NFR, data-model.md synchronization rules, Sway IPC authoritative]

### Observability

- [ ] CHK089 - Are diagnostic command requirements specified (i3pm diagnose scratchpad)? [NFR, Gap - Status command exists but not i3pm diagnose integration]
- [ ] CHK090 - Are daemon event logging requirements documented? [NFR, Gap - Example calls shown but not comprehensive requirements]

---

## Traceability & Documentation

### Requirements Traceability

- [ ] CHK091 - Are all daemon RPC methods traceable to user stories in spec.md? [Traceability, Partial - toggle/launch traceable, status/close/cleanup not in user stories]
- [ ] CHK092 - Are all error scenarios traceable to exception handling requirements? [Traceability, Partial - Some errors in Edge Cases, many not in spec]

### Implementation Guidance

- [x] CHK093 - Are code location requirements specified for daemon components? [Documentation, plan.md §Project Structure lines 76-105]
- [x] CHK094 - Are CLI command patterns documented (i3pm scratchpad <subcommand>)? [Documentation, quickstart.md lines 28-50, scratchpad.ts matches]
- [ ] CHK095 - Are configuration file update requirements specified? [Documentation, Partial - Keybinding config documented, not comprehensive]

---

## Ambiguities & Conflicts

### Unresolved Questions

- [ ] CHK096 - Is the transition from Alacritty to Ghostty clearly documented with rationale? [Ambiguity, Gap - All docs say Alacritty, user requested Ghostty]
- [ ] CHK097 - Are conflicting requirements between shell script and daemon approach resolved? [Conflict, Gap - Implementation Philosophy mentions replace but no conflict details]
- [x] CHK098 - Is the relationship between scratchpad-terminal and regular terminal apps clarified? [Ambiguity, spec.md FR-010, app-registry-data.nix separate entries]

---

## Summary

**Total Items**: 98
**Completed**: 46 (47%)
**Partially Complete**: 5 (5%) - CHK034-036 (performance targets), CHK091-092 (traceability), CHK095 (config updates)
**Gaps Identified**: 47 (48%)

**Categories**: 11 sections (Completeness, Clarity, Consistency, Acceptance Criteria, Scenario Coverage, Edge Cases, Dependencies, Migration, NFR, Traceability, Ambiguities)
**Focus Areas**: State synchronization (CHK009-013) ✅ COMPLETE, Launch notification (CHK014-017) ❌ ALL GAPS, Environment variables (CHK018-021) ⚠️ 3/4, Error handling (CHK022-026) ⚠️ 1/5

**Section Breakdown**:
- ✅ Daemon RPC Integration: 4/4 complete
- ❌ Unified Launcher Integration: 0/4 complete (critical gap)
- ✅ State Synchronization: 5/5 complete
- ❌ Launch Notification: 0/4 complete (critical gap)
- ⚠️ Environment Variables: 3/4 complete (missing Ghostty)
- ⚠️ Error Handling: 1/5 complete
- ❌ Ghostty Terminal Specific: 0/4 complete (critical gap)
- ⚠️ Scenario Coverage: 9/11 complete (best coverage)
- ⚠️ Edge Cases: 3/9 complete
- ❌ Migration Requirements: 0/5 complete (critical gap)

**Critical Gaps** (must address before implementation):
1. **Ghostty Terminal Requirements** (5 gaps): CHK019, CHK027-030, CHK073, CHK096
2. **Unified Launcher Integration** (4 gaps): CHK005-008
3. **Launch Notification** (4 gaps): CHK014-017, CHK042, CHK047, CHK051, CHK069
4. **Migration Documentation** (5 gaps): CHK080-084
5. **Error Handling** (4 gaps): CHK022, CHK024-026

**High-Quality Areas** (well-documented):
- ✅ Daemon RPC contracts (contracts/scratchpad-rpc.json)
- ✅ State synchronization (data-model.md)
- ✅ User scenario coverage (spec.md User Stories)
- ✅ Test requirements (research.md Testing Strategy)

**Assessment Confidence**: HIGH (47% complete with clear evidence)
**Detailed Analysis**: See `daemon-integration-assessment.md`

**Next Steps**:
1. ✅ Complete checklist assessment (DONE)
2. Address critical gaps (Ghostty, unified launcher, launch notifications, migration)
3. Update spec.md with missing requirements
4. Update plan.md with integration patterns
5. Re-validate against updated requirements
