# Implementation Plan: Sway Test Framework Usability Improvements

**Branch**: `070-sway-test-improvements` | **Date**: 2025-11-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/070-sway-test-improvements/spec.md`

## Summary

Feature 070 enhances the sway-test framework (Feature 069) with five developer experience improvements: structured error diagnostics with remediation steps, automatic cleanup management with manual CLI fallback, first-class PWA testing support, name-based app launches with registry metadata, and CLI discovery commands for apps and PWAs. The implementation extends existing TypeScript/Deno infrastructure with new service layers (ErrorHandler, CleanupManager) and CLI commands (cleanup, list-apps, list-pwas).

## Technical Context

**Language/Version**: TypeScript with Deno 1.40+ runtime
**Primary Dependencies**: Zod 3.22.4 (validation), @std/cli (argument parsing, Unicode width), Sway IPC (window management)
**Storage**: JSON registries (~/.config/i3/application-registry.json, ~/.config/i3/pwa-registry.json), In-memory cleanup state
**Testing**: Deno.test (unit tests), sway-test framework (integration tests), Constitution Principle XV compliance
**Target Platform**: NixOS with Sway compositor, hetzner-sway reference configuration
**Project Type**: Single project (sway-test framework enhancement)
**Performance Goals**: <50ms registry load, <2s cleanup (10 resources), <5s PWA launch
**Constraints**: Zero race conditions (sync protocol), 100% structured errors, <1% test flakiness
**Scale/Scope**: 50+ apps, 15+ PWAs, 5 user stories, 70 implementation tasks (9 phases)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Principle XII - Forward-Only Development
- **Status**: PASS
- **Verification**: No legacy compatibility layers or deprecated code preservation
- **Action**: Extends existing Feature 069 sync protocol without backwards compatibility shims

### ✅ Principle XIII - Deno CLI Development Standards
- **Status**: PASS
- **Verification**: TypeScript/Deno 1.40+, @std/cli for argument parsing, compiled executables
- **Action**: All CLI commands use parseArgs(), unicodeWidth(), and Deno standard library

### ✅ Principle XIV - Test-Driven Development
- **Status**: PASS
- **Verification**: Test pyramid (70% unit, 20% integration, 10% E2E), autonomous execution
- **Action**: Write tests before implementation (per task breakdown in Phase 2)

### ✅ Principle XV - Sway Test Framework Standards
- **Status**: PASS
- **Verification**: Declarative JSON tests, multi-mode comparison, undefined semantics, Sway IPC authority
- **Action**: Extends framework without breaking existing test definitions

### ✅ Principle XI - i3 IPC Alignment
- **Status**: PASS
- **Verification**: Sway IPC as authoritative state source, event-driven cleanup
- **Action**: Window cleanup via Sway IPC close commands, process tracking via PID

### ✅ Principle X - Python Development Standards
- **Status**: N/A (TypeScript/Deno implementation)
- **Verification**: No Python code in this feature
- **Action**: None required

### Re-evaluation After Phase 1 Design
- ✅ All gates remain PASS
- ✅ No complexity violations introduced
- ✅ Data model follows established patterns (PWADefinition, AppDefinition already exist)

## Project Structure

### Documentation (this feature)

```text
specs/070-sway-test-improvements/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (technical clarifications resolved)
├── data-model.md        # Phase 1 output (entities, relations, validation rules)
├── quickstart.md        # Phase 1 output (5-minute tutorial + troubleshooting)
├── contracts/           # Phase 1 output (API contracts and schemas)
│   ├── error-format.schema.json
│   ├── cleanup-report.schema.json
│   └── cli-commands.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/sway-test/
├── deno.json                          # Deno configuration
├── main.ts                            # CLI entry point (extended with new commands)
├── mod.ts                             # Public API exports
├── src/
│   ├── models/
│   │   ├── pwa-definition.ts         # [EXISTING] PWA data model (Phase 1, T001)
│   │   ├── app-definition.ts         # [EXISTING] App data model (Phase 1, T002)
│   │   ├── test-case.ts              # [EXISTING] Extended with launch_pwa_sync (Phase 2, T006)
│   │   ├── structured-error.ts       # [NEW] Error types and StructuredError class (Phase 3)
│   │   └── cleanup-report.ts         # [NEW] CleanupReport and related types (Phase 4)
│   │
│   ├── services/
│   │   ├── app-registry-reader.ts    # [EXISTING] Extended with PWA support (Phase 2, T005)
│   │   ├── action-executor.ts        # [MODIFY] Add launch_pwa_sync handler (Phase 5)
│   │   ├── error-handler.ts          # [NEW] StructuredError formatting and logging (Phase 3)
│   │   ├── cleanup-manager.ts        # [NEW] Process/window cleanup orchestration (Phase 4)
│   │   ├── process-tracker.ts        # [NEW] Process tree tracking and termination (Phase 4)
│   │   ├── window-tracker.ts         # [NEW] Window marker tracking and closing (Phase 4)
│   │   └── sync-manager.ts           # [EXISTING] Sync protocol (Feature 069)
│   │
│   ├── commands/
│   │   ├── run.ts                    # [EXISTING] Test runner
│   │   ├── cleanup.ts                # [NEW] Manual cleanup command (Phase 4)
│   │   ├── list-apps.ts              # [NEW] App registry list command (Phase 7)
│   │   └── list-pwas.ts              # [NEW] PWA registry list command (Phase 7)
│   │
│   └── ui/
│       ├── error-formatter.ts        # [NEW] Human-readable error display (Phase 3)
│       ├── table-formatter.ts        # [NEW] Table formatting for list commands (Phase 7)
│       └── cleanup-reporter.ts       # [NEW] Cleanup report display (Phase 4)
│
└── tests/
    ├── unit/
    │   ├── structured-error_test.ts  # [NEW] Error model validation
    │   ├── cleanup-manager_test.ts   # [NEW] Cleanup orchestration
    │   └── registry-reader_test.ts   # [MODIFY] Add PWA lookup tests
    │
    ├── integration/
    │   ├── launch-pwa_test.ts        # [NEW] PWA launch end-to-end
    │   ├── cleanup_test.ts           # [NEW] Cleanup with real processes
    │   └── registry-loading_test.ts  # [NEW] Registry cache validation
    │
    └── sway-tests/
        ├── basic/
        │   ├── test_pwa_launch.json  # [NEW] Basic PWA launch
        │   └── test_app_launch.json  # [NEW] Registry-based app launch
        └── integration/
            ├── test_pwa_workspace.json  # [NEW] PWA workspace assignment
            └── test_cleanup.json        # [NEW] Cleanup validation
```

**Structure Decision**: Single project enhancement to existing sway-test framework. All new code integrates into established directory structure (models/, services/, commands/, ui/, tests/) following Constitution Principle I (Modular Composition).

## Complexity Tracking

> **No violations - all Constitution gates pass**

## Phase 0: Outline & Research ✅ COMPLETE

### Unknowns Resolved

1. **Error Message Architecture** → Multi-level StructuredError with ErrorType enum
2. **Cleanup Command Implementation** → Hybrid: automatic + manual CLI fallback
3. **PWA Launch Integration** → Subprocess execution with registry-based ULID resolution
4. **App Registry Caching Strategy** → Singleton pattern with lazy loading (already implemented)
5. **CLI Discovery Output Format** → Default table with --json flag

### Research Artifacts

- **research.md**: 5 technical clarifications, best practices integration, dependency analysis, performance targets, risks & mitigations

### Key Decisions

- StructuredError extends Error with type/component/cause/remediation/context fields
- CleanupManager tracks processes via Set<number>, windows via Set<string>
- PWA launches use `firefoxpwa site launch <ULID>` with 5s default timeout
- Registry cache uses module-level singleton (registryCache, pwaRegistryCache, pwaRegistryByULID)
- CLI commands use @std/cli/parse-args and @std/cli/unicode-width for table formatting

## Phase 1: Design & Contracts ✅ COMPLETE

### Data Model

**New Entities**:
1. **StructuredError** - Error with diagnostic context (type, component, cause, remediation, context)
2. **CleanupReport** - Cleanup operation result (processes_terminated, windows_closed, errors, summary)

**Existing Entities** (from Phase 1 & 2):
3. **PWADefinition** - PWA metadata (name, url, ulid, workspace, monitor_role)
4. **AppDefinition** - App metadata (name, command, class, workspace, scope)
5. **AppListEntry** - Display model for list-apps command
6. **PWAListEntry** - Display model for list-pwas command

**Service State Models**:
- **CleanupManager** - Tracks processTree (Set<number>), windowMarkers (Set<string>)
- **RegistryCache** - Singleton maps (registryCache, pwaRegistryCache, pwaRegistryByULID)

### Contracts

1. **error-format.schema.json** - StructuredError JSON schema with 8 ErrorType enum values
2. **cleanup-report.schema.json** - CleanupReport JSON schema with nested definitions
3. **cli-commands.md** - CLI interface specification (cleanup, list-apps, list-pwas)

### Quickstart Guide

- **quickstart.md**: 5-minute tutorial covering all user stories, common use cases, troubleshooting, performance targets

### Agent Context Update

**Action Required**: Run `.specify/scripts/bash/update-agent-context.sh claude` to add:
- TypeScript/Deno 1.40+ (Feature 070 context)
- Zod 3.22.4 schema validation patterns
- @std/cli parse-args and unicode-width utilities
- StructuredError format and cleanup patterns

## Phase 2: Task Generation

**Next Command**: `/speckit.tasks`

This will generate `tasks.md` with detailed breakdown of:
- **Phase 3**: US1 - Clear Error Diagnostics (T007-T015) - 9 tasks
- **Phase 4**: US2 - Graceful Cleanup Commands (T016-T022) - 7 tasks
- **Phase 5**: US3 - PWA Application Support (T023-T034) - 12 tasks
- **Phase 6**: US4 - App Registry Integration (T035-T053) - 19 tasks
- **Phase 7**: US5 - Convenient CLI Access (T054-T061) - 8 tasks
- **Phase 8**: Integration Tests & Validation (T062-T066) - 5 tasks
- **Phase 9**: Polish & Documentation (T067-T076) - 10 tasks

**Total**: 70 tasks across 7 phases

## Implementation Roadmap

### Phase 3: Error Diagnostics (US1)
**Goal**: Implement StructuredError with remediation steps

**Key Tasks**:
- T007: Create ErrorType enum and StructuredError class
- T008: Implement error formatting service
- T009: Extend registry reader with structured errors
- T010: Add error context enrichment
- T011-T015: Comprehensive error scenarios (APP_NOT_FOUND, PWA_NOT_FOUND, INVALID_ULID, etc.)

**Deliverable**: All framework errors use StructuredError format

### Phase 4: Cleanup Commands (US2)
**Goal**: Automatic cleanup + manual CLI command

**Key Tasks**:
- T016: Create CleanupManager service
- T017: Implement ProcessTracker with SIGTERM/SIGKILL escalation
- T018: Implement WindowTracker with Sway IPC close
- T019: Integrate cleanup into test teardown
- T020: Create manual cleanup CLI command
- T021-T022: Cleanup report generation and logging

**Deliverable**: Zero orphaned processes/windows after test completion

### Phase 5: PWA Support (US3)
**Goal**: launch_pwa_sync action with name/ULID resolution

**Key Tasks**:
- T023: Extend ActionExecutor with launch_pwa_sync handler
- T024: Implement PWA lookup (by name)
- T025: Implement PWA lookup (by ULID)
- T026: Integrate with sync protocol
- T027: Add allow_failure parameter
- T028-T034: Error handling, timeout management, integration tests

**Deliverable**: Tests can launch PWAs by friendly name

### Phase 6: Registry Integration (US4)
**Goal**: Name-based app launches with metadata resolution

**Key Tasks**:
- T035: Extend launch_app_sync with registry lookup
- T036: Resolve app command from registry
- T037: Resolve expected_class from registry
- T038: Add workspace validation from registry
- T039: Add monitor role validation from registry
- T040-T053: Floating window config, parameter passing, comprehensive validation

**Deliverable**: Tests use app names only, framework resolves all metadata

### Phase 7: CLI Access (US5)
**Goal**: list-apps and list-pwas commands

**Key Tasks**:
- T054: Create list-apps command with table formatter
- T055: Add filtering (workspace, monitor, scope)
- T056: Add JSON output for list-apps
- T057: Create list-pwas command with table formatter
- T058: Add filtering (workspace, monitor, ULID)
- T059-T061: JSON output, error handling, help text

**Deliverable**: Developers can discover apps/PWAs without reading Nix config

### Phase 8: Integration Tests
**Goal**: End-to-end validation

**Key Tasks**:
- T062: PWA launch workflow test
- T063: Cleanup workflow test
- T064: Error scenario tests
- T065: Registry integration tests
- T066: CLI command tests

**Deliverable**: 100% test coverage for new features

### Phase 9: Polish & Documentation
**Goal**: Production readiness

**Key Tasks**:
- T067: Performance optimization (registry load, cleanup)
- T068: Error message refinement
- T069: CLI help text
- T070-T076: Documentation updates (CLAUDE.md, quickstart.md, error catalog)

**Deliverable**: Feature 070 ready for production use

## Success Criteria Validation

### SC-001: Error messages include remediation steps in 100% of error scenarios
**Validation**: All StructuredError instances must have non-empty remediation array (Zod schema enforcement)

### SC-002: Developers can identify and fix test configuration errors without consulting framework documentation in 90% of cases
**Validation**: User testing with 10 test scenarios, measure documentation lookup rate

### SC-003: Cleanup commands successfully restore clean state in under 2 seconds for tests with up to 10 spawned processes
**Validation**: Performance test with 10 processes + 10 windows, measure cleanup duration

### SC-004: Zero orphaned processes remain after cleanup completes
**Validation**: Process tree inspection via `ps aux | grep <pattern>` after cleanup

### SC-005: PWA tests can be authored using friendly names without manual ULID lookup
**Validation**: Write 5 PWA tests using only pwa_name parameter (no pwa_ulid)

### SC-006: Test authoring time for PWA scenarios reduces by 60% compared to manual ULID management
**Validation**: Measure time to write 10 PWA tests (manual ULID vs friendly name)

### SC-007: Registry-based app launches eliminate hardcoded commands in 100% of test files
**Validation**: Grep test files for hardcoded commands (should find zero)

### SC-008: Test maintenance burden reduces by 40% when app configurations change
**Validation**: Change app command in registry, measure test file modification count (should be zero)

### SC-009: List commands execute in under 200ms and display formatted output without errors
**Validation**: Performance benchmark for list-apps and list-pwas commands

### SC-010: Developers can discover all available apps/PWAs without reading Nix configuration files
**Validation**: User testing with 10 developers, measure Nix file access rate (should be 0%)

## Risk Mitigation

### Risk 1: firefoxpwa binary not available
**Mitigation**: Pre-flight check with clear StructuredError (implemented in research.md)

### Risk 2: Process cleanup fails to terminate processes
**Mitigation**: SIGTERM → SIGKILL escalation with 500ms timeout (implemented in research.md)

### Risk 3: Registry file missing at test runtime
**Mitigation**: Clear StructuredError with setup instructions (implemented in research.md)

### Risk 4: Test flakiness from race conditions
**Mitigation**: Reuse Feature 069 sync protocol (zero new race conditions introduced)

## Next Steps

1. **Run agent context update**:
   ```bash
   .specify/scripts/bash/update-agent-context.sh claude
   ```

2. **Generate task breakdown**:
   ```bash
   /speckit.tasks
   ```

3. **Begin implementation** (Phase 3):
   ```bash
   /speckit.implement
   ```

## Artifacts Generated

- ✅ research.md - Technical research and decision documentation
- ✅ data-model.md - Entity definitions, relationships, validation rules
- ✅ contracts/ - JSON schemas and CLI interface specifications
- ✅ quickstart.md - 5-minute tutorial and troubleshooting guide
- ⏳ tasks.md - Detailed task breakdown (awaiting `/speckit.tasks`)

---

**Planning Status**: Phase 1 Complete | Ready for `/speckit.tasks`
**Branch**: 070-sway-test-improvements (4664219e)
**Last Updated**: 2025-11-10
