# Implementation Plan: Fix State Comparator Bug in Sway Test Framework

**Branch**: `068-fix-state-comparator` | **Date**: 2025-11-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/068-fix-state-comparator/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Fix the state comparison bug in the sway-test framework that causes all tests to fail with "state comparison failed" error after successful action execution. The bug affects the state comparator's ability to correctly identify when actual state matches expected state, resulting in false failures even when actions execute correctly and states match. The fix will enable accurate test pass/fail detection, support partial state matching, and provide clear diff output showing actual differences.

## Technical Context

**Language/Version**: TypeScript/Deno 1.40+ (existing sway-test framework)
**Primary Dependencies**: Deno standard library (@std/cli, @std/fs, @std/path, @std/json), Zod 3.22+ (validation)
**Storage**: N/A (test framework operates in-memory with JSON test files)
**Testing**: Deno.test (Deno native testing framework, @std/assert for assertions)
**Target Platform**: Linux (NixOS) with Sway/Wayland compositor
**Project Type**: Single (CLI tool - sway-test framework)
**Performance Goals**: <100ms state comparison latency, <5% test execution overhead from comparison logic
**Constraints**: Maintain backward compatibility with existing test JSON format, zero false positives/negatives in test results
**Scale/Scope**: ~10-50 test cases currently, comparison handles Sway tree structures with 1-100 windows/workspaces

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle XIII: Deno CLI Development Standards ✅
- Using TypeScript with Deno runtime (existing sway-test framework)
- Follows strict type checking with explicit types
- Uses Deno standard library modules (@std/cli, @std/fs, @std/path, @std/json, @std/assert)
- Compilation to standalone executable via `deno compile`

### Principle XIV: Test-Driven Development & Autonomous Testing ✅
- Fix enables the test framework itself to function correctly
- Will write unit tests for state comparison logic (deepEqual, partial matching)
- Will write integration tests to validate fix against existing test cases
- Test pyramid: Unit tests (state comparator logic) + Integration tests (full test execution)

### Principle XII: Forward-Only Development & Legacy Elimination ✅
- Will fix the root cause bug in state comparison logic
- Will NOT add compatibility layers or feature flags
- Backward compatibility maintained through proper ExpectedState handling (not through dual code paths)
- Existing test JSON format remains unchanged (FR-010 requirement)

### Principle VI: Declarative Configuration Over Imperative ✅
- Test framework is declarative (JSON test definitions)
- No imperative changes required
- State comparison logic is pure functional code

**Status**: ✅ All applicable principles aligned. No violations requiring justification.

---

## Constitution Re-Check (Post-Design)

*Re-evaluation after Phase 1 design artifacts created*

### Principle XIII: Deno CLI Development Standards ✅
- ✅ Pure TypeScript with strict type checking
- ✅ Using Deno standard library exclusively (no new npm dependencies)
- ✅ State extractor functions are pure (no side effects)
- ✅ Follows existing sway-test framework patterns
- ✅ Interface contracts defined in `contracts/` directory
- **No violations** - Design maintains Deno/TypeScript standards

### Principle XIV: Test-Driven Development & Autonomous Testing ✅
- ✅ Unit tests planned for state-extractor.ts (pure functions)
- ✅ Unit tests planned for enhanced state-comparator.ts (undefined handling)
- ✅ Integration tests planned for full extraction → comparison flow
- ✅ Test pyramid: 70% unit (pure functions), 20% integration (real Sway states), 10% e2e (existing test validation)
- ✅ All tests autonomous (use fixture data, no manual intervention)
- **No violations** - Test-first approach maintained

### Principle XII: Forward-Only Development ✅
- ✅ Direct fix to root cause (run.ts lines 470-472)
- ✅ No feature flags or compatibility shims
- ✅ Backward compatible through proper API design (not through dual code paths)
- ✅ Enhanced StateDiff is backward compatible (new fields are optional)
- **No violations** - Clean, forward-only fix

### Principle VI: Declarative Configuration ✅
- ✅ No configuration changes required
- ✅ Test JSON format unchanged (backward compatible)
- ✅ Pure functional code (no imperative state mutations)
- **No violations** - Maintains declarative approach

**Final Status**: ✅ All principles pass post-design evaluation. Design is ready for implementation.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/sway-test/
├── src/
│   ├── models/
│   │   ├── test-case.ts          # ExpectedState interface definition
│   │   ├── test-result.ts        # StateDiff, DiffEntry types
│   │   └── state-snapshot.ts     # StateSnapshot type
│   ├── services/
│   │   ├── state-comparator.ts   # 🔧 PRIMARY FIX - State comparison logic
│   │   └── sway-client.ts        # State capture from Sway IPC
│   ├── commands/
│   │   └── run.ts                # 🔧 SECONDARY FIX - Expected state extraction (line 470-472)
│   └── ui/
│       └── diff-renderer.ts      # 🔧 ENHANCEMENT - Improved diff display
├── tests/
│   ├── unit/
│   │   └── state_comparator_test.ts    # 🆕 Unit tests for state comparison logic
│   ├── integration/
│   │   └── state_comparison_test.ts    # 🆕 Integration tests with real Sway states
│   └── sway-tests/
│       └── integration/                 # Existing test cases (validation targets)
│           ├── test_firefox_workspace.json
│           └── test_window_launch.json
├── deno.json                      # Deno configuration (existing)
└── main.ts                        # CLI entry point (no changes)
```

**Structure Decision**: Using existing sway-test framework structure (single Deno project). This is a bug fix to existing code, not a new feature, so we're modifying files in place rather than adding new directories.

## Complexity Tracking

N/A - No constitution violations requiring justification.

---

## Planning Phase Summary

**Branch**: `068-fix-state-comparator`
**Status**: ✅ Planning Complete - Ready for `/speckit.tasks`

### Artifacts Generated

#### Phase 0: Research & Analysis
- ✅ `research.md` - Root cause analysis, technology decisions, comparison strategies
  - Identified bug in run.ts:470-472 (incorrect expected state extraction)
  - Designed multi-mode comparison dispatch
  - Defined partial matching semantics
  - Documented undefined/null/missing property handling

#### Phase 1: Design & Contracts
- ✅ `data-model.md` - Entity definitions, relationships, validation rules
  - Defined PartialExtractedState interface
  - Enhanced StateDiff with mode tracking
  - Documented state comparison semantics
  - Mapped data flow through comparison pipeline

- ✅ `quickstart.md` - User guide for state comparison
  - Three comparison modes (partial/exact/assertions)
  - Common test patterns and examples
  - Debugging guide for failed comparisons
  - Migration guide from pre-068 tests

- ✅ `contracts/state-extractor-api.ts` - StateExtractor interface contract
  - Pure functional API for state extraction
  - Field extraction functions (focusedWorkspace, windowCount, workspaces)
  - Comparison mode detection logic
  - Performance characteristics documented

- ✅ `contracts/state-comparator-enhancement.ts` - StateComparator enhancement contract
  - Enhanced StateDiff interface (backward compatible)
  - Undefined-aware comparison semantics
  - Empty mode support
  - Implementation notes and testing strategy

- ✅ `CLAUDE.md` - Updated with new technology context
  - TypeScript/Deno 1.40+
  - Deno standard library
  - In-memory test framework

### Constitution Compliance

- ✅ Pre-design check: All principles aligned
- ✅ Post-design check: All principles pass
- ✅ No violations requiring justification
- ✅ Test-driven approach planned
- ✅ Forward-only development (no legacy compatibility shims)

### Key Technical Decisions

1. **Multi-mode dispatch** in run.ts (fix root cause)
2. **Field-based partial matching** (simple, fast, intuitive)
3. **Undefined = "don't check"** semantics (flexible, user-friendly)
4. **Pure functional state extraction** (testable, no side effects)
5. **Backward compatible API** (existing tests work unchanged)

### Performance Targets

- State extraction: <20ms (single tree traversal)
- Partial comparison: <10ms (field-based matching)
- Total overhead: <100ms (SC-005 requirement)

### Next Steps

Run `/speckit.tasks` to generate implementation tasks based on this plan.

**Expected task breakdown**:
- T001-T005: Fix dispatch logic in run.ts
- T006-T015: Implement StateExtractor service
- T016-T025: Enhance StateComparator (undefined handling, empty mode)
- T026-T035: Unit tests (state extractor, comparator enhancements)
- T036-T045: Integration tests (existing test validation)
- T046-T050: Documentation and polish
