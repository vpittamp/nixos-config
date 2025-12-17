# Tasks: eBPF-Based AI Agent Process Monitor

**Input**: Design documents from `/specs/119-explore-ebpf-monitor/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Includes exact file paths in descriptions

## Path Conventions (per plan.md)

```text
# NixOS Module Structure
modules/services/ebpf-ai-monitor.nix        # System-level NixOS module
home-modules/services/ebpf-ai-monitor.nix   # Optional user-level service

# Python Daemon
home-modules/tools/ebpf_ai_monitor/
├── __init__.py                 # Package initialization
├── __main__.py                 # CLI entry point
├── daemon.py                   # Main daemon loop with eBPF integration
├── models.py                   # Pydantic models (ProcessState, BadgeState)
├── bpf_probes.py               # BCC-based eBPF program definitions
├── process_tracker.py          # Process state tracking and window resolution
├── badge_writer.py             # Badge file management
├── notifier.py                 # Desktop notification integration
└── README.md                   # Module documentation

# Tests
tests/ebpf-ai-monitor/
├── test_models.py              # Data model tests
├── test_process_tracker.py     # Process tracking tests
├── test_badge_writer.py        # Badge file tests
└── fixtures/
    └── mock_bpf_events.py      # Mock eBPF events for testing
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, Python package structure, and NixOS module skeleton

- [x] T001 Create Python package directory structure at `home-modules/tools/ebpf_ai_monitor/`
- [x] T002 Create `home-modules/tools/ebpf_ai_monitor/__init__.py` with package version and exports
- [x] T003 [P] Create `home-modules/tools/ebpf_ai_monitor/__main__.py` with CLI entry point skeleton using argparse
- [x] T004 [P] Create NixOS module skeleton at `modules/services/ebpf-ai-monitor.nix` with basic options structure
- [x] T005 Create test directory structure at `tests/ebpf-ai-monitor/` with `__init__.py` and `conftest.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Create Pydantic models for `ProcessState` enum and `EBPFEvent` ctypes structure in `home-modules/tools/ebpf_ai_monitor/models.py`
- [x] T007 [P] Create Pydantic model for `MonitoredProcess` with state machine logic in `home-modules/tools/ebpf_ai_monitor/models.py`
- [x] T008 [P] Create Pydantic model for `BadgeState` (matching existing JSON schema) in `home-modules/tools/ebpf_ai_monitor/models.py`
- [x] T009 [P] Create Pydantic model for `DaemonState` with process tracking dict in `home-modules/tools/ebpf_ai_monitor/models.py`
- [x] T010 Implement BPF C program string for `sys_enter_read` tracepoint with fd==0 and process name filtering in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T011 [P] Implement BPF C program for `sched_process_exit` tracepoint in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T012 Create `BPFProbeManager` class to load BPF programs and attach to tracepoints in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T013 Add logging configuration with configurable log levels in `home-modules/tools/ebpf_ai_monitor/__init__.py`

**Checkpoint**: Foundation ready - BPF programs defined, data models complete, user story implementation can now begin

---

## Phase 3: User Story 1 - Receive Notification When AI Agent Completes Task (Priority: P1) 🎯 MVP

**Goal**: Detect when Claude Code or Codex CLI transitions from processing to waiting-for-input and send desktop notification within 2 seconds

**Independent Test**: Start Claude Code, submit a prompt, switch away, verify notification appears when AI stops and waits

### Implementation for User Story 1

- [x] T014 [US1] Implement `process_tracker.py` with function to scan `/proc` for existing AI processes on startup in `home-modules/tools/ebpf_ai_monitor/process_tracker.py`
- [x] T015 [US1] Implement process tree walker to find Ghostty parent PID from AI process PID in `home-modules/tools/ebpf_ai_monitor/process_tracker.py`
- [x] T016 [US1] Implement Sway IPC query to resolve window ID from Ghostty PID in `home-modules/tools/ebpf_ai_monitor/process_tracker.py`
- [x] T017 [US1] Implement `/proc/<pid>/environ` reader to extract `I3PM_PROJECT_NAME` in `home-modules/tools/ebpf_ai_monitor/process_tracker.py`
- [x] T018 [US1] Create `ProcessTracker` class that combines PID detection, window resolution, and project name extraction in `home-modules/tools/ebpf_ai_monitor/process_tracker.py`
- [x] T019 [US1] Implement `notifier.py` with D-Bus notification sender using `notify-send` subprocess to user session in `home-modules/tools/ebpf_ai_monitor/notifier.py`
- [x] T020 [US1] Implement main daemon loop in `daemon.py` that polls BPF perf buffer and updates process states in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T021 [US1] Add timing heuristic in daemon loop to transition process to WAITING after 1 second in read syscall in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T022 [US1] Trigger notification on WORKING → WAITING state transition in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T023 [US1] Add CLI argument parsing for `--user`, `--threshold`, `--log-level` in `home-modules/tools/ebpf_ai_monitor/__main__.py`

**Checkpoint**: User Story 1 complete - AI completion detection and notifications working independently

---

## Phase 4: User Story 2 - Visual Indicator Shows Agent Working Status (Priority: P2)

**Goal**: Write badge files to `$XDG_RUNTIME_DIR/i3pm-badges/` compatible with existing eww monitoring panel

**Independent Test**: Start AI session, verify spinner appears in eww panel, verify badge changes to attention icon when stopped

### Implementation for User Story 2

- [x] T024 [US2] Implement `badge_writer.py` with atomic file write using temp file + rename in `home-modules/tools/ebpf_ai_monitor/badge_writer.py`
- [x] T025 [US2] Implement badge file chown to target user after write in `home-modules/tools/ebpf_ai_monitor/badge_writer.py`
- [x] T026 [US2] Create `BadgeWriter` class that manages badge directory creation and file lifecycle in `home-modules/tools/ebpf_ai_monitor/badge_writer.py`
- [x] T027 [US2] Implement badge file deletion on process EXITED state in `home-modules/tools/ebpf_ai_monitor/badge_writer.py`
- [x] T028 [US2] Integrate badge writing into daemon state transitions in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T029 [US2] Add `needs_attention` flag management - set true on WAITING, clear on WORKING in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T030 [US2] Add `count` field incrementing on repeated completions within same session in `home-modules/tools/ebpf_ai_monitor/badge_writer.py`

**Checkpoint**: User Story 2 complete - Badge files written, eww panel can show spinners and attention indicators

---

## Phase 5: User Story 3 - eBPF-Based Detection Replaces Polling (Priority: P3)

**Goal**: Achieve <100ms detection latency and <1% CPU usage via kernel-space event filtering

**Independent Test**: Compare CPU usage and detection latency between current polling approach and eBPF-based detection

### Implementation for User Story 3

- [x] T031 [US3] Add BPF hash map for O(1) process name lookup in kernel space in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T032 [US3] Implement `sys_exit_read` tracepoint to detect when read syscall completes (user resumed) in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T033 [US3] Add per-PID timestamp tracking in BPF hash map for in-kernel timeout detection in `home-modules/tools/ebpf_ai_monitor/bpf_probes.py`
- [x] T034 [US3] Implement lost event handling in perf buffer callback with warning log in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T035 [US3] Add daemon startup state recovery by scanning existing badge files in `home-modules/tools/ebpf_ai_monitor/daemon.py`
- [x] T036 [US3] Implement graceful shutdown with BPF program cleanup in `home-modules/tools/ebpf_ai_monitor/daemon.py`

**Checkpoint**: User Story 3 complete - Efficient kernel-space filtering, low overhead, fast detection

---

## Phase 6: User Story 4 - NixOS Declarative Configuration (Priority: P4)

**Goal**: Enable full feature with `services.ebpf-ai-monitor.enable = true` in NixOS configuration

**Independent Test**: Enable service in configuration.nix, run `nixos-rebuild switch`, verify service running and detecting AI processes

### Implementation for User Story 4

- [x] T037 [US4] Complete NixOS module options: `enable`, `user`, `processes`, `waitThreshold`, `logLevel` in `modules/services/ebpf-ai-monitor.nix`
- [x] T038 [US4] Add `programs.bcc.enable = true` when service is enabled in `modules/services/ebpf-ai-monitor.nix`
- [x] T039 [US4] Define systemd service unit with root privileges, restart policy, and dependencies in `modules/services/ebpf-ai-monitor.nix`
- [x] T040 [US4] Package Python daemon with all dependencies using nixpkgs `python3.pkgs.buildPythonApplication` in `modules/services/ebpf-ai-monitor.nix`
- [x] T041 [US4] Add service to thinkpad and hetzner configurations with test user settings
- [x] T042 [US4] Create README.md with usage instructions and troubleshooting guide in `home-modules/tools/ebpf_ai_monitor/README.md`

**Checkpoint**: User Story 4 complete - Full NixOS declarative configuration working

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T043 [P] Add comprehensive docstrings to all public functions and classes
- [x] T044 [P] Add type hints to all function signatures throughout the codebase
- [ ] T045 Implement systemd journal logging integration (using sd-journal if available)
- [ ] T046 Add health check endpoint or status subcommand (`--status`) to verify service is working
- [x] T047 [P] Create bpftrace script `scripts/ebpf-ai-monitor/stdin-monitor.bt` for manual testing/debugging
- [ ] T048 Run quickstart.md validation scenarios end-to-end
- [ ] T049 Remove tmux-ai-monitor from codebase (clean replacement per migration strategy)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - US1 (P1) → US2 (P2) → US3 (P3) → US4 (P4) in priority order
  - US2 depends on US1 (badge writing integrates with daemon)
  - US3 optimizes US1/US2 (can be done after MVP)
  - US4 packages everything (must be last)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational)
    ↓
Phase 3 (US1: Notification) ← MVP
    ↓
Phase 4 (US2: Badge Files)
    ↓
Phase 5 (US3: eBPF Optimization) ← Performance improvement
    ↓
Phase 6 (US4: NixOS Module) ← Full integration
    ↓
Phase 7 (Polish)
```

### Within Each User Story

- Models before services
- Services before integration
- Core implementation before optimizations
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Within US1: Process tracker functions (T014-T17) can be developed in parallel
- Within US2: Badge writer core (T024-T26) can run in parallel with daemon integration (T28-T30)
- Polish phase tasks marked [P] can run in parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Launch all [P] tasks together:
Task: T007 "Create Pydantic model for MonitoredProcess"
Task: T008 "Create Pydantic model for BadgeState"
Task: T009 "Create Pydantic model for DaemonState"
Task: T011 "Implement BPF C program for sched_process_exit"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Notification on completion)
4. **STOP and VALIDATE**: Test manually with Claude Code
5. Deploy/demo if ready - notifications working!

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test notifications → Deploy (MVP!)
3. Add User Story 2 → Test badge files with eww panel → Deploy
4. Add User Story 3 → Benchmark performance improvement → Deploy
5. Add User Story 4 → Test declarative config → Final deployment
6. Each story adds value without breaking previous stories

### Suggested First Session

Focus on completing through Phase 3 (MVP):
- T001-T005: Setup (5 tasks)
- T006-T013: Foundational (8 tasks)
- T014-T023: User Story 1 (10 tasks)

**Total MVP tasks: 23 tasks**

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Run `sudo nixos-rebuild dry-build` before any configuration changes
- Service runs as root - test carefully with limited scope first
