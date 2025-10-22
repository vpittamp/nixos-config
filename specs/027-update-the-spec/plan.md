# Implementation Plan: Complete i3pm Deno CLI with Extensible Architecture

**Branch**: `027-update-the-spec` | **Date**: 2025-10-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/027-update-the-spec/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Complete TypeScript/Deno rewrite of the i3pm CLI tool, replacing the existing Python CLI with a type-safe, compiled executable that leverages Deno standard library extensively. The CLI provides project context switching, real-time window state visualization, daemon monitoring, and window classification management through an extensible parent command structure (`i3pm <parent> <subcommand>`). All functionality communicates with the existing Python daemon via JSON-RPC 2.0 over Unix socket, with real-time event subscriptions for live TUI modes. The compiled binary integrates into NixOS/home-manager configuration as a self-contained system package with no runtime dependencies.

## Technical Context

**Language/Version**: TypeScript with Deno 1.40+ runtime (strict type checking enabled)
**Primary Dependencies**:
  - `@std/cli/parse-args` - Command-line argument parsing (minimist-style API)
  - `@std/cli/unstable-ansi` - Terminal ANSI escape codes and formatting
  - `@std/cli/unicode-width` - Unicode string width calculation for table rendering
  - `@std/fs` - File system operations
  - `@std/path` - Path manipulation utilities
  - `@std/json` - JSON utilities (optional runtime validation with Zod)

**Storage**: JSON configuration files in `~/.config/i3/` (read-only from CLI perspective, daemon owns writes)
**Testing**: Deno.test() framework for unit and integration tests (existing Python pytest framework remains for daemon testing)
**Target Platform**: NixOS Linux (x86_64 and ARM64 via Asahi Linux) - compiled to standalone executable via `deno compile`
**Project Type**: Single CLI project with extensible command structure (parent commands: project, windows, daemon, rules, monitor, app-classes)
**Performance Goals**:
  - CLI startup and first output within 300ms
  - Real-time TUI updates within 100ms of window events
  - Memory usage under 50MB during extended live monitoring (>1 hour)
  - Binary size under 20MB (compiled with all dependencies)

**Constraints**:
  - Single compiled executable with zero runtime dependencies
  - Must maintain protocol compatibility with existing Python daemon (JSON-RPC 2.0)
  - Terminal UI must restore state cleanly on exit (cursor visibility, alternate screen buffer)
  - Must support graceful degradation when daemon is unavailable

**Scale/Scope**:
  - 6 parent command namespaces with 20+ subcommands total
  - Real-time event processing for live monitoring (unbounded event stream)
  - Typical deployment: 10-50 windows, 1-4 monitors, 9 workspaces, 3-5 projects
  - Terminal UI rendering for complex nested data structures (outputs → workspaces → windows)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle XIII: Deno CLI Development Standards ✅ PASS

**Check**: Does this feature use Deno runtime 1.40+ with TypeScript and heavy reliance on Deno standard library?

**Evidence**:
- ✅ Deno 1.40+ specified in Technical Context
- ✅ TypeScript with strict type checking enabled
- ✅ `@std/cli/parse-args` for command-line argument parsing (FR-003)
- ✅ `@std/cli/unstable-ansi` for terminal formatting (FR-049)
- ✅ `@std/cli/unicode-width` for string width calculations (FR-050)
- ✅ Compilation to standalone executable via `deno compile` (FR-004)
- ✅ Runtime type validation using TypeScript types + optional Zod (FR-053, FR-055)
- ✅ Distribution via compiled binary with no runtime dependencies (FR-008, SC-008)

**Justification**: This feature is the reference implementation of Principle XIII (Deno CLI Development Standards), which was added to the constitution specifically to establish Deno as the replacement for Python in CLI contexts. The feature specification explicitly requires all Deno std library modules from the principle (parseArgs, ANSI utilities, unicode-width).

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS

**Check**: Does this feature eliminate legacy Python CLI without backwards compatibility?

**Evidence**:
- ✅ Complete replacement of Python CLI with Deno implementation (no dual support)
- ✅ Assumption 10 states: "After Deno CLI is validated, Python CLI will be deprecated and removed to eliminate maintenance burden"
- ✅ No feature flags or compatibility layers for legacy commands
- ✅ Clean break after validation - Python CLI removal in same phase as Deno CLI activation

**Justification**: Following the principle of complete replacement demonstrated in polybar→i3bar and polling→event-driven migrations. Once Deno CLI is validated, Python CLI is immediately removed with no preservation of old code.

### Principle X: Python Development & Testing Standards ⚠️ PARTIAL ALIGNMENT

**Check**: Does this feature maintain Python standards where Python is used?

**Evidence**:
- ✅ Python daemon remains unchanged with existing async/await patterns (Assumption 1)
- ✅ Existing pytest framework remains for daemon testing (Scope: Out of Scope - "Automated testing framework (remains Python-based)")
- ⚠️ New CLI is Deno/TypeScript, not Python - this is the intended transition per Principle XIII
- ✅ Monitoring tools remain Python (Scope: Out of Scope - "Real-time monitoring tools for daemon debugging (remains Python-based)")

**Justification**: Python standards still apply to daemon and testing framework. CLI transition to Deno is aligned with constitutional mandate in Principle XIII to use Deno as "replacement for Python in CLI contexts."

### Principle I: Modular Composition ✅ PASS

**Check**: Is the CLI implemented as reusable modules with clear single responsibilities?

**Evidence**:
- ✅ Extensible parent command structure supports multiple namespaces (FR-001)
- ✅ TypeScript modules for commands, models, client, UI (Project Structure section)
- ✅ Clear separation: commands/, models.ts, client.ts, ui/ (single responsibility)
- ✅ Compiled to standalone executable, integrated via home-manager module (FR-005, FR-059)

**Justification**: Modular TypeScript architecture with proper separation of concerns. NixOS integration follows modular pattern via home-manager package definition.

### Principle VII: Documentation as Code ✅ PASS

**Check**: Is comprehensive documentation provided alongside code?

**Evidence**:
- ✅ quickstart.md deliverable in Phase 1 (FR-006: --help for every command)
- ✅ Module documentation via README.md (Project Structure pattern)
- ✅ TypeScript interfaces serve as executable documentation (FR-053)
- ✅ Comprehensive spec.md with user scenarios, requirements, entities

**Justification**: Documentation deliverables are explicit phase outputs. TypeScript type definitions serve as self-documenting contracts.

### Summary: ALL GATES PASSED ✅

No violations requiring complexity justification. Feature fully aligns with constitutional principles, particularly Principle XIII (Deno CLI Standards) which this feature exemplifies.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-modules/tools/i3pm-deno/
├── deno.json                     # Deno configuration (tasks, imports, compiler options)
├── main.ts                       # Entry point with parseArgs() CLI routing
├── mod.ts                        # Public API exports (if needed for testing)
├── README.md                     # Module documentation
├── src/
│   ├── commands/                # Command implementations
│   │   ├── project.ts           # Project management (switch, clear, current, list, create, show, edit, delete, validate)
│   │   ├── windows.ts           # Window state visualization (tree, table, json, live modes)
│   │   ├── daemon.ts            # Daemon status and events
│   │   ├── rules.ts             # Window classification rules
│   │   ├── monitor.ts           # Interactive monitoring dashboard
│   │   └── app-classes.ts       # Application class management
│   ├── models.ts                # TypeScript type definitions (WindowState, Workspace, Output, Project, Event, etc.)
│   ├── client.ts                # JSON-RPC 2.0 client for daemon communication
│   ├── validation.ts            # Runtime type validation (Zod schemas)
│   ├── ui/                      # Terminal UI components
│   │   ├── tree.ts              # Tree view formatter
│   │   ├── table.ts             # Table view formatter
│   │   ├── live.ts              # Live TUI with event subscriptions
│   │   ├── monitor-dashboard.ts # Multi-pane monitoring dashboard
│   │   └── ansi.ts              # ANSI formatting utilities (@std/cli/unstable-ansi wrappers)
│   └── utils/
│       ├── socket.ts            # Unix socket connection management
│       ├── errors.ts            # Error handling and user-friendly messages
│       └── signals.ts           # Signal handling (Ctrl+C, terminal resize)
└── tests/
    ├── unit/
    │   ├── models_test.ts       # Type validation tests
    │   ├── formatters_test.ts   # Tree/table formatting tests
    │   └── client_test.ts       # JSON-RPC client tests
    ├── integration/
    │   ├── daemon_test.ts       # Daemon communication tests (with mock daemon)
    │   └── commands_test.ts     # End-to-end command tests
    └── fixtures/
        ├── mock_daemon.ts       # Mock JSON-RPC server for testing
        └── sample_data.ts       # Sample window/workspace data
```

**Structure Decision**: Single Deno project with clear separation of concerns following Principle XIII (Deno CLI Development Standards). The structure mirrors Python project patterns from Principle X but adapted for TypeScript/Deno:

- **commands/**: One file per parent command namespace (project, windows, daemon, rules, monitor, app-classes)
- **models.ts**: Centralized TypeScript type definitions for all entities (WindowState, Workspace, Output, Project, EventNotification, etc.)
- **client.ts**: JSON-RPC 2.0 client abstraction for daemon communication via Unix socket
- **validation.ts**: Runtime type validation using Zod schemas (optional - TypeScript compile-time + runtime guards)
- **ui/**: Terminal UI components using `@std/cli` modules (tree formatters, table renderers, live TUI, monitor dashboard)
- **utils/**: Cross-cutting concerns (socket management, error handling, signal handling)
- **tests/**: Deno.test() suites with unit, integration, and fixture separation

This structure enables:
1. Extensible command routing in main.ts using parseArgs()
2. Clear module boundaries for single-responsibility principle
3. Reusable UI components across commands
4. Comprehensive test coverage with mocked daemon
5. Easy compilation to standalone executable via `deno compile main.ts`

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
