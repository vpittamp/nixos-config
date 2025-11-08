# Implementation Plan: Sway Test Framework - App Launch Integration & Sync Fixes

**Branch**: `067-sway-test-app-launch-fix` | **Date**: 2025-11-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/067-sway-test-app-launch-fix/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance sway-test framework to use app-launcher-wrapper for proper I3PM environment variable injection and workspace assignment, implement proper wait_event for window::new events using Sway IPC subscriptions, and fix auto-sync RPC errors with graceful degradation when daemon methods unavailable. This enables realistic testing of production app launch flow, eliminates test flakiness from timeout issues, and removes RPC error noise from test output.

## Technical Context

**Language/Version**: TypeScript/Deno 1.40+ (existing sway-test framework), Shell script (app-launcher-wrapper.sh)
**Primary Dependencies**:
- Deno standard library (@std/cli, @std/fs, @std/path, @std/json)
- Zod for JSON validation
- Sway IPC (swaymsg command-line tool for event subscriptions)
- JSON-RPC over Unix socket for tree-monitor daemon communication

**Storage**:
- In-memory test state and event buffers
- JSON test definition files
- Application registry at `~/.config/i3/application-registry.json` (read-only)

**Testing**:
- Deno.test() for framework unit tests
- Integration tests executing real Sway commands
- Test scenarios validating app launch workflows

**Target Platform**: NixOS with Sway window manager (Linux, Wayland compositor)

**Project Type**: Single project (CLI tool with test framework)

**Performance Goals**:
- Event subscription with <100ms latency from Sway event to detection
- wait_event should complete immediately when event arrives (not after full timeout)
- Test execution within configured timeout (typically 5-15 seconds)

**Constraints**:
- Must work with or without tree-monitor daemon (graceful degradation)
- Must respect user-configured timeouts up to 60 seconds
- Must not spam "Method not found" errors on every test
- Must work with existing test JSON format (backward compatible)

**Scale/Scope**:
- ~25 TypeScript source files in existing framework
- 3 new action types or enhancements (launch_app with via_wrapper, wait_event implementation, RPC introspection)
- Test suite with ~10-20 integration tests
- Support for app registry with 50+ application definitions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle XIII: Deno CLI Development Standards
**Status**: ✅ PASS
- Using Deno 1.40+ with TypeScript (existing framework)
- Using @std/cli parseArgs() for command-line parsing (already in use)
- Strict type checking enabled in deno.json
- Using Zod for schema validation

### Principle XIV: Test-Driven Development & Autonomous Testing
**Status**: ✅ PASS
- This feature IS the test framework enhancement
- Will include integration tests for new functionality
- User flow tests demonstrating wrapper-based launches
- Tests validate via Sway IPC state verification

### Principle VI: Declarative Configuration Over Imperative
**Status**: ✅ PASS
- Test definitions remain JSON declarative format
- Actions are declarative (launch_app, wait_event)
- No imperative post-install scripts

### Principle XII: Forward-Only Development & Legacy Elimination
**Status**: ✅ PASS
- Replacing placeholder wait_event with proper implementation (no dual support)
- Fixing RPC error handling (not preserving broken behavior)
- Enhancing launch_app (backward compatible via optional via_wrapper parameter)

### Principle X: Python Development & Testing Standards
**Status**: N/A
- This feature is pure TypeScript/Deno (CLI tool)
- No Python code modifications required

### Complexity Justification
**Status**: ✅ PASS
- No new complexity introduced
- Enhancement of existing framework
- No new platforms, no new abstraction layers

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
├── deno.json                           # Deno configuration (existing)
├── main.ts                             # CLI entry point (existing)
├── mod.ts                              # Public API (existing)
├── src/
│   ├── models/
│   │   ├── test-case.ts               # Test definition types (existing, may need enhancement)
│   │   └── state-snapshot.ts          # State snapshot types (existing)
│   ├── services/
│   │   ├── action-executor.ts         # ✏️ MODIFY: Enhance wait_event, launch_app
│   │   ├── tree-monitor-client.ts     # ✏️ MODIFY: Add RPC introspection
│   │   ├── sway-client.ts             # ✏️ MODIFY: Add event subscription
│   │   ├── app-registry-reader.ts     # ✨ NEW: Read app registry JSON
│   │   └── event-subscriber.ts        # ✨ NEW: Sway IPC event subscription
│   ├── helpers/
│   │   └── environment-validator.ts   # ✨ NEW: Validate I3PM env vars
│   └── ui/
│       └── reporter.ts                # Existing, no changes
├── tests/
│   ├── framework_test.ts              # Existing framework tests
│   ├── integration/
│   │   ├── test_wrapper_launch.ts     # ✨ NEW: Test wrapper integration
│   │   ├── test_wait_event.ts         # ✨ NEW: Test event subscription
│   │   └── test_rpc_graceful.ts       # ✨ NEW: Test RPC degradation
│   └── sway-tests/
│       ├── basic/
│       │   └── test_walker_app_launch.json  # Existing test (already created)
│       └── integration/
│           ├── test_firefox_workspace.json  # ✨ NEW: Example test
│           └── test_vscode_scoped.json      # ✨ NEW: Example test
├── docs/
│   ├── quickstart.md                  # Existing
│   ├── api-reference.md               # Existing
│   └── WALKER_APP_LAUNCH_TESTING.md   # ✨ NEW: Already created in previous session
└── README.md                          # ✏️ UPDATE: Document new features

scripts/
└── app-launcher-wrapper.sh            # Existing, no changes (read-only dependency)

~/.config/i3/application-registry.json # Existing, read-only dependency
```

**Structure Decision**: Single project structure (Deno CLI tool). This feature enhances the existing sway-test framework at `home-modules/tools/sway-test/`. Key files to modify: `action-executor.ts` (wait_event, launch_app), `tree-monitor-client.ts` (RPC introspection), `sway-client.ts` (event subscription). New modules: `event-subscriber.ts` (Sway IPC subscription), `app-registry-reader.ts` (registry lookup), `environment-validator.ts` (env var validation).

## Complexity Tracking

No constitution violations - complexity tracking not required.

---

## Post-Design Constitution Re-Check

**Status**: ✅ All principles remain satisfied after Phase 1 design

### Design Artifacts Review

**Generated Artifacts**:
- `research.md` - Technology decisions and alternatives evaluation
- `data-model.md` - Entity definitions with Zod schemas
- `contracts/test-actions.json` - JSON Schema for test action definitions
- `contracts/sway-ipc-events.json` - JSON Schema for Sway IPC events
- `contracts/api-functions.md` - TypeScript function signatures and contracts
- `quickstart.md` - User-facing documentation with examples

### Architecture Validation

**No New Complexity**:
- Uses existing Deno/TypeScript stack
- No new dependencies (all Deno std library)
- Enhances existing files (action-executor.ts, tree-monitor-client.ts, sway-client.ts)
- New modules follow existing patterns (services/, helpers/)

**Breaking Changes**:
- launch_app now requires `app_name` parameter (replaces `command`)
- Direct command execution removed entirely (no via_wrapper flag)
- ALL apps must exist in application registry
- wait_event replaced with proper event subscription (no longer sleeps 1 second)
- Existing tests MUST be updated to use new schema

**Test Coverage**:
- Integration tests for wrapper launch, event subscription, RPC introspection
- Example test scenarios demonstrating all new functionality
- Framework tests validate core functions (unit tests)

### Constitution Principles Reconfirmed

✅ **Principle XIII (Deno CLI Standards)**: Design uses Deno.Command for subprocess, @std modules, Promise.race for timeout, Zod for validation

✅ **Principle XIV (Test-Driven Development)**: Quickstart includes comprehensive test examples, integration tests planned for each feature

✅ **Principle VI (Declarative Config)**: Test definitions remain JSON declarative format, actions are declarative

✅ **Principle XII (Forward-Only)**:
- launch_app completely replaced (no dual code path for direct execution)
- wait_event placeholder removed entirely (replaced with optimal event subscription)
- RPC error handling fixed without legacy fallback
- Breaking changes justified by optimal solution (production app launch flow, event-driven waiting)

✅ **Principle I (Modular Composition)**: New services (event-subscriber, app-registry-reader) follow single-responsibility pattern, helpers are reusable

**Conclusion**: Design maintains architectural consistency with existing framework. No constitution violations introduced.
