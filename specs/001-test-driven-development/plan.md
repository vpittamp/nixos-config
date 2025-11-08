# Implementation Plan: Test-Driven Development Framework for Sway

**Branch**: `001-test-driven-development` | **Date**: 2025-11-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/001-test-driven-development/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Design a test-driven development framework for Sway window manager that enables comparison of expected vs actual system state from `swaymsg tree` output. The framework uses Deno runtime for CLI tooling and Python backend for daemon enhancements, incorporating I3_SYNC protocol patterns for deterministic synchronization. Build on existing `i3pm tree-monitor` infrastructure to enable testing of project management, workspace assignment, and application launching with environment injection.

**Primary Requirement**: Enable developers to write test cases comparing expected vs actual window tree states with <2s latency for simple tests, 0% flakiness over 1000 runs, and clear diff output when states diverge.

**Technical Approach**: Leverage existing tree-monitor daemon for event capture and diff computation, create Deno-based CLI test runner for user-facing tooling, enhance Python daemon with sync markers and test-scoped event filtering, support headless CI execution via WLR_BACKENDS=headless.

## Technical Context

**Language/Version**: Deno 1.40+ (CLI tooling), Python 3.11+ (daemon enhancements matching existing i3pm daemon)
**Primary Dependencies**:
- Deno std library (`@std/cli`, `@std/fs`, `@std/path`, `@std/json`)
- Python: i3ipc.aio (Sway IPC communication), pytest-asyncio (async testing), Pydantic (data validation)
- Existing: `i3pm tree-monitor` daemon (JSON-RPC over Unix socket)

**Storage**:
- In-memory state: Test execution context, captured snapshots during test runs
- Persistent: Test definitions (JSON/TypeScript), expected state files (JSON), structured test logs (JSON Lines)
- No database required - file-based test definitions

**Testing**:
- Test runner self-testing: Deno.test() for runner logic
- Framework validation: pytest for Python daemon enhancements
- User test execution: Framework's own test execution engine

**Target Platform**:
- Local development: Native Sway session on Hetzner Cloud (headless Wayland), M1 Mac (native Wayland)
- CI/CD: Headless Sway (WLR_BACKENDS=headless) in Docker containers or GitHub Actions

**Project Type**: Hybrid - Deno CLI tool + Python daemon enhancements

**Performance Goals**:
- Test execution latency: <2s for simple tests (launch app + verify), <10s for complex multi-step tests
- Framework overhead: <100ms per test for initialization and cleanup
- State capture latency: <500ms for `swaymsg -t get_tree` parsing
- Selective execution: Run 10 tests from suite of 100 in <20s

**Constraints**:
- 0% flakiness over 1000 consecutive runs (via I3_SYNC-style synchronization)
- Test isolation: No cross-test interference from window rules or workspace assignments
- Headless operation: Full test suite runnable without display server (CI requirement)
- Backwards compatibility: Preserve existing tree-monitor daemon functionality

**Scale/Scope**:
- Support 100+ test cases organized across multiple suites/directories
- Handle complex window trees (50+ windows, 10+ workspaces, 3 monitors)
- 500-event circular buffer for test diagnostics (matching tree-monitor daemon)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Core Principles Alignment

**I. Modular Composition**
- Test framework will be modular: CLI runner (Deno), daemon enhancements (Python), test fixtures (reusable)
- Separate concerns: state capture, comparison logic, action execution, reporting
- ✅ PASS - Design supports composable modules

**III. Test-Before-Apply (NON-NEGOTIABLE)**
- Test framework itself must be tested before deployment
- ✅ PASS - Framework will include self-tests (Deno.test for CLI, pytest for daemon)

**VI. Declarative Configuration Over Imperative**
- Test definitions will be declarative JSON/TypeScript files
- ✅ PASS - Test cases defined as data, not imperative scripts

**VII. Documentation as Code**
- quickstart.md will be generated in Phase 1
- Test framework documentation will live in specs/001/
- ✅ PASS - Documentation deliverable in planning phase

**X. Python Development & Testing Standards**
- Daemon enhancements use Python 3.11+ matching existing i3pm daemon
- Uses i3ipc.aio for async Sway IPC communication
- pytest-asyncio for async test support
- Pydantic models for data validation
- ✅ PASS - Matches established Python standards

**XI. i3 IPC Alignment & State Authority**
- Sway IPC (`swaymsg -t get_tree`) is authoritative source of truth
- Event-driven architecture via existing tree-monitor daemon
- ✅ PASS - Framework queries Sway IPC as authority

**XIII. Deno CLI Development Standards**
- Uses Deno 1.40+ with `@std/cli/parse-args` for argument parsing
- TypeScript with strict type checking
- Compiled standalone executables via `deno compile`
- ✅ PASS - Full Deno standard library usage

**XIV. Test-Driven Development & Autonomous Testing**
- This feature IS test-driven development infrastructure
- Enables autonomous testing of window management features
- Supports test pyramid: unit (test assertions), integration (Sway IPC), end-to-end (full workflows)
- ✅ PASS - Core mission alignment

### ⚠️ Potential Violations / Clarifications Needed

**Performance Complexity**
- Introducing synchronization primitives (I3_SYNC-style markers) adds complexity
- **Justification**: Required for 0% flakiness goal - polling/timeouts cause race conditions
- **Simpler Alternative Rejected**: Timeout-based waiting is unreliable for CI environments

**Dual Technology Stack (Deno + Python)**
- Uses both Deno (CLI) and Python (daemon enhancements)
- **Justification**: Leverages existing tree-monitor Python daemon, avoids rewrite
- **Simpler Alternative Rejected**: Pure Deno would require reimplementing event capture, diff computation, and correlation logic (80% code duplication per SC-007)

✅ **Overall Assessment**: PASS - Violations justified by performance requirements and code reuse goals

## Project Structure

### Documentation (this feature)

```text
specs/001-test-driven-development/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - I3_SYNC patterns, Deno test frameworks, Sway IPC schemas
├── data-model.md        # Phase 1 output - TestCase, StateSnapshot, ExpectedState, etc.
├── quickstart.md        # Phase 1 output - Quick start guide for writing tests
├── contracts/           # Phase 1 output - JSON schemas for test definitions, RPC methods
│   ├── test-definition.schema.json
│   ├── state-snapshot.schema.json
│   └── rpc-extensions.json
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Deno CLI Tool (home-modules/tools/sway-test/)
home-modules/tools/sway-test/
├── deno.json                # Deno configuration (tasks, imports, compiler options)
├── main.ts                  # Entry point with parseArgs() CLI handling
├── mod.ts                   # Public API exports
├── src/
│   ├── commands/
│   │   ├── run.ts          # Execute test cases
│   │   ├── validate.ts     # Validate test definitions
│   │   └── report.ts       # Generate test reports
│   ├── models/
│   │   ├── test-case.ts    # TestCase interface
│   │   ├── state-snapshot.ts # StateSnapshot interface
│   │   └── test-result.ts  # TestResult interface
│   ├── services/
│   │   ├── sway-client.ts  # Wrapper for `swaymsg` commands
│   │   ├── tree-monitor-client.ts # RPC client for tree-monitor daemon
│   │   ├── state-comparator.ts # Expected vs actual comparison logic
│   │   └── action-executor.ts # Execute test action sequences
│   ├── ui/
│   │   ├── reporter.ts     # Human-readable test output
│   │   └── diff-renderer.ts # Visual diff formatting
│   └── fixtures/
│       └── fixture-manager.ts # Reusable setup/teardown logic
├── tests/
│   ├── comparator_test.ts  # Unit tests for state comparison
│   ├── action_test.ts      # Unit tests for action execution
│   └── fixtures/
│       └── sample_trees.json # Sample Sway tree data
└── README.md

# Python Daemon Enhancements (home-modules/tools/i3pm/src/)
home-modules/tools/i3pm/src/
├── test_support/            # New module for test framework support
│   ├── __init__.py
│   ├── sync_marker.py      # I3_SYNC-style synchronization via Sway IPC
│   ├── test_event_filter.py # Test-scoped event filtering
│   └── snapshot_service.py  # Optimized state snapshot API
├── rpc/
│   └── test_methods.py      # New JSON-RPC methods for test framework
└── README.md

# Test Execution Environment
tests/sway-tests/            # Example test suite (reference implementation)
├── fixtures/
│   ├── empty-workspace.json
│   └── three-monitor-layout.json
├── project-management/
│   ├── test_project_switch.json
│   └── test_project_isolation.json
└── workspace-assignment/
    ├── test_pwa_assignment.json
    └── test_multi_monitor.json
```

**Structure Decision**: Hybrid structure with Deno CLI tool in `home-modules/tools/sway-test/` and Python daemon enhancements in existing `home-modules/tools/i3pm/src/test_support/`. Test definitions live in `tests/sway-tests/` as declarative JSON files. This structure:
1. Preserves existing tree-monitor daemon location and structure
2. Follows Deno CLI Development Standards (Constitution XIII)
3. Separates test framework (tooling) from test suites (data)
4. Enables test suite reuse across different projects

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Dual technology stack (Deno + Python) | Leverage existing tree-monitor daemon for event capture, diff computation, and correlation - avoid reimplementing 80% of functionality | Pure Deno implementation would duplicate Python daemon's event streaming, field-level diffs, and user action correlation (violates code reuse principle) |
| I3_SYNC-style synchronization primitive | Achieve 0% flakiness over 1000 runs (SC-004) - deterministic wait for Sway event loop completion | Timeout-based waiting causes race conditions in CI environments with variable load, polling consumes CPU unnecessarily |
| Test isolation via separate Sway configs | Prevent cross-test interference from window rules and workspace assignments (FR-010) | Global config cleanup between tests is unreliable - lingering rules can affect subsequent tests |

## Phase 0: Research & Unknowns

**Research Tasks** (to be executed in Phase 0):

1. **I3_SYNC Protocol Patterns**
   - Research: How does i3 test suite implement I3_SYNC for deterministic synchronization?
   - Research: Can Sway IPC support sync markers via `send_tick` command?
   - Research: What are alternatives if Sway lacks I3_SYNC equivalent?
   - Output: Synchronization strategy decision in research.md

2. **Deno Test Framework Best Practices**
   - Research: Best practices for Deno test runners (custom vs built-in Deno.test)
   - Research: Deno libraries for subprocess management (`Deno.Command` API)
   - Research: Deno JSON schema validation libraries (vs native JSON.parse)
   - Output: Deno architecture decisions in research.md

3. **Sway Tree JSON Schema**
   - Research: Complete schema for `swaymsg -t get_tree` output structure
   - Research: How to handle partial matching (e.g., "workspace 3 has Firefox window")
   - Research: JSON schema validation strategies for expected state definitions
   - Output: State schema documentation in research.md

4. **Headless Sway Testing**
   - Research: How to launch Sway with WLR_BACKENDS=headless in CI
   - Research: Virtual output configuration for headless mode (3 displays for multi-monitor tests)
   - Research: Limitations of headless mode (animations, GPU acceleration, etc.)
   - Output: CI/CD integration strategy in research.md

5. **Tree-Monitor Daemon Extension Points**
   - Research: Existing RPC methods in tree-monitor daemon
   - Research: How to add new RPC methods without breaking existing clients
   - Research: Daemon state management patterns for test-scoped event filtering
   - Output: RPC extension design in research.md

## Phase 1: Design & Contracts

**Prerequisites:** research.md complete with all NEEDS CLARIFICATION resolved

### 1. Data Model (data-model.md)

Extract entities from spec.md and define concrete data structures:

**Core Entities** (from spec.md Key Entities):
- TestCase: Test definition with actions, expected state, assertions
- ActionSequence: Ordered list of actions (launch_app, send_ipc, wait_event, debug_pause)
- StateSnapshot: Parsed Sway tree from `swaymsg -t get_tree`
- ExpectedState: Test author's expected state (exact or partial matching)
- StateDiff: Computed difference showing added/removed/modified nodes
- TestFixture: Reusable setup/teardown logic
- TestSuite: Collection of related test cases with suite-level config
- SyncMarker: I3_SYNC-style synchronization mechanism
- TestExecutionContext: Runtime state during test (connections, buffers, config)
- TestResult: Outcome with status, execution time, logs, diffs
- TreeMonitorEvent: Event from tree-monitor daemon for diagnostics

**Data Model Deliverable**: Document each entity with:
- TypeScript interface definition (for Deno CLI)
- Python Pydantic model (for daemon, if applicable)
- Validation rules from functional requirements
- State transitions (e.g., TestCase: pending → running → passed/failed)
- Relationships between entities

### 2. API Contracts (contracts/)

Generate contracts from functional requirements:

**Test Definition Schema** (`test-definition.schema.json`):
- Based on FR-002 (expected state definitions in JSON)
- Supports exact matching and partial matching
- Includes action sequences (FR-003)

**State Snapshot Schema** (`state-snapshot.schema.json`):
- Based on FR-001 (`swaymsg -t get_tree` structure)
- Documents all relevant fields for comparison
- Includes workspace, container, window properties

**RPC Extensions** (`rpc-extensions.json`):
- New tree-monitor daemon methods:
  - `send_sync_marker(marker_id)` - I3_SYNC-style synchronization
  - `await_sync_marker(marker_id, timeout_ms)` - Wait for sync completion
  - `create_test_scope(test_id)` - Enable test-scoped event filtering
  - `destroy_test_scope(test_id)` - Clean up test scope
  - `get_test_events(test_id, filters)` - Query events for specific test
- Based on FR-004 (tree-monitor integration via JSON-RPC)

### 3. Quickstart Guide (quickstart.md)

Generate user-facing documentation:

**Content Structure**:
```markdown
# Sway Test Framework Quick Start

## Installation
[How to install sway-test CLI tool]

## Writing Your First Test
[Example test case with expected state]

## Running Tests
[Commands: sway-test run, sway-test validate]

## Test Fixtures
[How to create reusable fixtures]

## Debugging Failed Tests
[Using diff output, tree-monitor events]

## CI/CD Integration
[Headless mode, output formats]

## Common Patterns
[Project switching, workspace assignment, window lifecycle]
```

**Examples to Include**:
- Basic state comparison test (User Story 1)
- Multi-step action sequence (User Story 2)
- Using tree-monitor correlation for debugging (User Story 6)

### 4. Agent Context Update

Run `.specify/scripts/bash/update-agent-context.sh claude` to:
- Add new technologies: Deno test framework patterns, Sway IPC sync markers, test definition schemas
- Preserve manual additions in agent-specific context file
- Update only between designated markers

## Phase 2: Task Generation

**Not executed in /speckit.plan** - Defer to `/speckit.tasks` command after Phase 1 completion.

Expected task structure (preview):
1. Implement Deno CLI test runner
2. Implement state comparison logic
3. Enhance Python daemon with sync markers
4. Implement test fixtures system
5. Create example test suite
6. Add CI/CD integration
7. Write comprehensive documentation

## Next Steps After Planning

1. Execute Phase 0 research to resolve all NEEDS CLARIFICATION
2. Generate data-model.md with concrete TypeScript/Python definitions
3. Generate contracts/ with JSON schemas and RPC specifications
4. Generate quickstart.md with user-facing examples
5. Update agent context with new technologies
6. Run `/speckit.tasks` to generate actionable implementation tasks
7. Begin implementation starting with User Story 1 (Basic State Comparison) as MVP

## Success Criteria Verification

From spec.md Success Criteria - Plan must enable these outcomes:

- ✅ SC-001: 5-minute test authoring → quickstart.md provides simple examples
- ✅ SC-002: 100% accuracy → state comparison logic in Deno CLI
- ✅ SC-003: <2s/test latency → direct Sway IPC queries, no unnecessary overhead
- ✅ SC-004: 0% flakiness → I3_SYNC-style sync markers in daemon
- ✅ SC-005: 3-minute debugging → tree-monitor event correlation
- ✅ SC-006: CI pass rate → headless mode support
- ✅ SC-007: 80% code reduction → reuse tree-monitor daemon
- ✅ SC-008: 90% helpful errors → diff rendering in CLI
- ✅ SC-009: <100ms overhead → minimal framework initialization
- ✅ SC-010: 100+ test scalability → selective execution support

All success criteria can be met with planned architecture.
