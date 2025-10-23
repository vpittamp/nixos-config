# Implementation Status: i3pm Production Readiness

**Feature**: 030-review-our-i3pm
**Date Started**: 2025-10-23
**Strategy**: MVP Implementation (Option 1)
**Target**: ~50 tasks (Phase 1-2 + US1-2)

---

## Executive Summary

Implementing production readiness for the i3pm (i3 Project Manager) system. This feature brings an 80-85% ready system to full production quality with layout persistence, comprehensive testing, error recovery, and production-scale validation.

**Total Scope**: 118 tasks across 10 phases
**MVP Scope**: 50 tasks (Phases 1-2, User Stories 1-2)
**Current Phase**: Phase 1 - Setup

---

## Progress Overview

### Phase 1: Setup (5 tasks) - IN PROGRESS ⏳
- ✅ **T001**: Added pytest, pytest-asyncio, pytest-cov, pydantic to `home-modules/desktop/i3-project-daemon.nix`
- ✅ **T002**: Verified xdotool installed (system-wide)
- ✅ **T003**: Created test directory structure: `tests/i3pm-production/{unit,integration,scenarios,fixtures}/`
- 🔄 **T004**: Applying NixOS configuration changes (rebuild in progress)
- ⏳ **T005**: Verify baseline functionality

### Phase 2: Foundational (17 tasks) - PENDING
**Purpose**: Core data models and infrastructure that BLOCKS all user stories

**Status**: Not started - blocked by Phase 1 completion

**Key Deliverables**:
- Pydantic data models (Python) + TypeScript interfaces
- IPC authentication (UID-based via SO_PEERCRED)
- Sensitive data sanitization
- Health metrics & diagnostics
- Event buffer persistence
- Test fixtures and mocks

### Phase 3: User Story 1 - Reliability (7 tasks) - PLANNED
**Goal**: Rock-solid project switching with automatic error recovery

**Status**: Not started - blocked by Phase 2

**Key Deliverables**:
- State validator (daemon state vs i3 marks)
- Automatic recovery module
- i3 IPC reconnection logic
- Integration tests for recovery scenarios

### Phase 4: User Story 2 - Layout Persistence (21 tasks) - PLANNED
**Goal**: Save and restore workspace layouts with 15+ windows without flicker

**Status**: Not started - blocked by Phase 2

**Key Deliverables**:
- Layout capture module (via i3 GET_TREE)
- Launch command discovery (desktop files → proc cmdline → user prompt)
- Layout restore with append_layout
- Monitor adaptation for different configs
- Deno CLI commands: `i3pm layout save/restore/list/diff`

---

## Path Corrections

During implementation, discovered actual file paths differ from plan.md:

### Planned Paths (from plan.md)
```
home-modules/tools/i3-project-daemon/     # ← Plan expected here
home-modules/tools/i3pm-cli/              # ← Deno CLI
```

### Actual Paths (reality)
```
home-modules/desktop/i3-project-event-daemon/   # ← Daemon actually here
home-modules/tools/i3pm-deno/                   # ← Deno CLI actually here
```

**Impact**: All task file paths need adjustment. This is normal - plan.md is aspirational, implementation adapts to reality.

---

## Architecture Notes

### Current System (Feature 015/025/029 - Working)
- **Python Event Daemon**: `home-modules/desktop/i3-project-event-daemon/`
  - Real-time i3 event processing via IPC subscriptions
  - Automatic window marking with project context
  - JSON-RPC IPC server for CLI queries
  - Systemd integration with socket activation
  - Multi-source event correlation (i3/systemd/proc)

- **Deno CLI v2.0**: `home-modules/tools/i3pm-deno/`
  - Type-safe CLI (4,439 LOC TypeScript)
  - Commands: project, windows, daemon, rules
  - Visual window state (tree/table/TUI modes)

- **Legacy Python TUI**: `home-modules/tools/i3-project-manager/` (15,445 LOC)
  - **TO BE DELETED** in Phase 9 per Constitution Principle XII
  - No backwards compatibility layers
  - Forward-only development

### Dependencies (Already Installed)
- ✅ **System**: xdotool, xorg.xprop, xvfb-run
- ✅ **Python**: i3ipc, systemd-python, watchdog
- 🔄 **Adding**: pydantic, pytest, pytest-asyncio, pytest-cov (rebuild in progress)
- ✅ **Deno**: @std/cli, @std/fs, @std/json, @std/path

---

## Implementation Decisions

### Why MVP First (Option 1)?
1. **Scope Management**: 118 tasks is massive - MVP delivers value incrementally
2. **Risk Mitigation**: Test foundation before building on it
3. **User Value**: Layout persistence (US2) is the killer feature users want
4. **Forward Progress**: 50 tasks is achievable, validates approach for remaining 68

### What MVP Delivers
- ✅ Rock-solid error recovery and automatic state rebuilding (US1)
- ✅ Complete layout save/restore with launch command discovery (US2)
- ✅ Comprehensive data models with Pydantic validation
- ✅ Security infrastructure (IPC auth, sanitization)
- ✅ Monitoring infrastructure (health metrics, diagnostics)
- ✅ Test infrastructure (fixtures, mocks, test suite foundation)

### Post-MVP Phases (Optional - 68 tasks remaining)
- **Phase 5**: US3 - Real-time monitoring tools (10 tasks)
- **Phase 6**: US4 - Production-scale validation with 500+ windows (12 tasks)
- **Phase 7**: US5 - Multi-user security hardening (7 tasks)
- **Phase 8**: US6 - User onboarding wizards (10 tasks)
- **Phase 9**: Legacy code deletion (10 tasks) - **CRITICAL before commit**
- **Phase 10**: Documentation & polish (19 tasks)

---

## Known Issues & Challenges

### 1. NixOS Build Cache
**Issue**: Modified Python dependencies but NixOS didn't rebuild environment
**Cause**: Derivation caching - NixOS doesn't detect file changes in some cases
**Solution**: Force rebuild with `--rebuild` flag or update flake lock
**Status**: Attempting rebuild now

### 2. File Path Mismatches
**Issue**: Plan.md shows paths that don't match actual codebase
**Impact**: Need to adjust all 118 task descriptions
**Solution**: Update tasks.md with correct paths as we implement
**Priority**: Medium - doesn't block progress

### 3. Scale of Implementation
**Issue**: 118 tasks is 10-20 hours of focused development work
**Mitigation**: MVP-first approach (50 tasks ~5-8 hours)
**Decision**: Implement MVP, pause for validation, continue if successful

---

## Success Criteria (MVP Scope)

From spec.md, these criteria apply to MVP (US1 + US2):

- **SC-010**: Daemon recovery <5s after restart (99% of cases) - US1
- **SC-011**: Clear error messages with recovery guidance (100%) - US1
- **SC-003**: Layout restore 95% position/size accuracy - US2
- **SC-004**: Layout restoration without flicker (90% of cases) - US2

**Deferred to Post-MVP**:
- SC-001-002: Performance at 500+ windows scale (US4)
- SC-005-006: Onboarding and debugging tools (US3, US6)
- SC-007: 80%+ test coverage (accumulated across all phases)
- SC-008-009: CPU usage and monitor reconfig (US4)

---

## Next Steps (After Phase 1 Completes)

1. **Verify Dependencies**: Confirm pytest, pydantic available in daemon environment
2. **Restart Daemon**: `systemctl --user restart i3-project-event-listener`
3. **Baseline Tests**: Run existing tests to verify system still works
4. **Phase 2 Start**: Begin foundational implementation (17 tasks)
   - Core data models (Pydantic + TypeScript)
   - Security modules (auth + sanitization)
   - Monitoring infrastructure
   - Test fixtures

5. **Checkpoint After Phase 2**: Validate foundation before user stories
6. **US1 Implementation**: Error recovery and resilience (7 tasks)
7. **US2 Implementation**: Layout persistence (21 tasks)
8. **MVP Validation**: Test complete system with success criteria

---

## Time Estimates

Based on task complexity:

- **Phase 1**: 0.5-1 hour ✅ (nearly complete)
- **Phase 2**: 3-4 hours (17 foundational tasks)
- **Phase 3 (US1)**: 1-2 hours (7 recovery tasks)
- **Phase 4 (US2)**: 4-5 hours (21 layout tasks)

**Total MVP**: 8.5-12 hours of focused implementation

**Post-MVP**: 12-15 hours for remaining 68 tasks

---

## Git Commit Strategy

Per Constitution Principle XII (Forward-Only Development):

**CRITICAL**: Legacy code deletion (Phase 9 - 10 tasks) MUST happen in the SAME commit as new features. No backwards compatibility, no migration period, no dual code paths.

**Commit Plan**:
1. Complete MVP implementation (Phases 1-4)
2. Test and validate
3. Delete legacy Python TUI (15,445 LOC from `home-modules/tools/i3-project-manager/`)
4. Single commit: New features + legacy deletion
5. Commit message template in tasks.md (T114-T118)

---

## References

- **Specification**: [spec.md](./spec.md) - 42 functional requirements, 6 user stories
- **Implementation Plan**: [plan.md](./plan.md) - Tech stack, architecture decisions
- **Research Decisions**: [research.md](./research.md) - 7 key technical decisions
- **Data Model**: [data-model.md](./data-model.md) - Pydantic models, relationships
- **API Contracts**: [contracts/daemon-ipc.json](./contracts/daemon-ipc.json) - JSON-RPC protocol
- **Layout Format**: [contracts/layout-format.json](./contracts/layout-format.json) - i3 layout schema
- **Quickstart**: [quickstart.md](./quickstart.md) - Implementation walkthrough
- **Task List**: [tasks.md](./tasks.md) - 118 tasks with dependencies

---

**Last Updated**: 2025-10-23 11:47 EDT
**Current Task**: T004 - Applying NixOS configuration (rebuild in progress)
**Next Milestone**: Phase 1 completion, verify dependencies, begin Phase 2
