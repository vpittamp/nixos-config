# Implementation Plan: Enhanced CLI User Experience with Real-Time Feedback

**Branch**: `028-add-a-new` | **Date**: 2025-10-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/028-add-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance existing CLI tools with modern UX patterns including live progress indicators, semantic color coding, interactive selection menus, real-time event streaming, structured table output, and Unicode/emoji support. This feature modernizes the i3 project management CLI tools (i3pm, i3-project-*) following Deno CLI best practices and industry standards for terminal applications.

## Technical Context

**Language/Version**: TypeScript with Deno 1.40+ (per Constitution XIII - Deno CLI Development Standards)
**Primary Dependencies**: Deno standard library (@std/cli, @std/fmt, @std/io), NEEDS CLARIFICATION on specific terminal UI library
**Storage**: N/A (CLI presentation layer enhancement, no data storage changes)
**Testing**: Deno.test() with mock terminal capabilities, NEEDS CLARIFICATION on visual regression testing approach
**Target Platform**: Linux (NixOS, WSL, containers), macOS Darwin
**Project Type**: Single CLI enhancement project affecting multiple existing commands
**Performance Goals**: Progress updates 2Hz minimum (500ms), selection filtering <50ms, event streaming <100ms latency
**Constraints**: Terminal width ≥40 columns minimum, must degrade gracefully to ASCII, no ANSI codes in non-TTY output
**Scale/Scope**: ~10 existing CLI commands to enhance, 6 user stories, phased rollout starting with most impactful features (P1)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle XIII - Deno CLI Development Standards ✅

**Requirement**: All new CLI tools must use Deno runtime 1.40+ with TypeScript and Deno std library

**Compliance**:
- This feature enhances existing CLI tools using Deno/TypeScript
- Uses @std/cli for command parsing and interactive prompts
- Uses @std/fmt for ANSI formatting and colors
- Compiles to standalone executables via `deno compile`
- **Status**: PASSES - fully aligned with constitution mandate

### Principle XII - Forward-Only Development ✅

**Requirement**: Optimal solutions without backwards compatibility for legacy code

**Compliance**:
- Existing CLI tools will be enhanced in-place, not duplicated
- No feature flags or compatibility modes for old output styles
- Old output formatting will be replaced, not preserved
- **Status**: PASSES - clean enhancement without legacy support

### Principle X - Python Development Standards ⚠️

**Requirement**: Python 3.11+ for system tooling with async patterns

**Compliance**:
- This feature uses Deno/TypeScript, not Python
- Constitution XIII establishes Deno as replacement for Python in CLI contexts
- Existing i3-project daemon (Python) remains unchanged
- CLI clients (Deno) will communicate with Python daemon via JSON-RPC
- **Status**: PASSES - appropriate technology choice for CLI layer

### Principle VI - Declarative Configuration ✅

**Requirement**: System configuration must be declared in Nix expressions

**Compliance**:
- CLI tools packaged via NixOS derivations
- Dependencies declared in home-modules or system packages
- No imperative post-install scripts
- **Status**: PASSES - standard NixOS packaging approach

### Principle III - Test-Before-Apply ✅

**Requirement**: dry-build before switch, build failures resolved before commit

**Compliance**:
- Changes will be tested with `nixos-rebuild dry-build`
- Deno compilation will be validated before packaging
- **Status**: PASSES - standard development workflow

### Gates Summary

**PROCEED**: All constitution checks pass. No violations requiring justification.

## Project Structure

### Documentation (this feature)

```
specs/028-add-a-new/
├── plan.md              # This file (implementation plan)
├── spec.md              # Feature specification (user stories, requirements)
├── research.md          # Phase 0: Research findings and decisions ✓
├── data-model.md        # Phase 1: Entity definitions and relationships ✓
├── quickstart.md        # Phase 1: Usage guide and examples ✓
├── contracts/           # Phase 1: TypeScript API contracts ✓
│   ├── index.ts                    # Main module exports
│   ├── terminal-capabilities.ts    # TTY/color/Unicode detection
│   ├── output-formatter.ts         # Colors and symbols
│   ├── progress-indicator.ts       # Progress bars and spinners
│   ├── interactive-prompts.ts      # Selection menus and inputs
│   ├── table-renderer.ts           # Table formatting
│   └── event-stream.ts             # Real-time event streaming
└── tasks.md             # Phase 2: Implementation tasks (NOT created yet)
```

### Source Code (repository root)

This is a **library module** that will be used by existing CLI tools, not a standalone application.

```
home-modules/tools/cli-ux/
├── deno.json            # Deno configuration (tasks, imports, compiler options)
├── mod.ts               # Public API exports (re-exports from src/)
├── src/
│   ├── terminal-capabilities.ts    # Implementation of detection APIs
│   ├── output-formatter.ts         # Implementation of formatting APIs
│   ├── progress-indicator.ts       # ProgressBar and Spinner classes
│   ├── interactive-prompts.ts      # Interactive selection/input
│   ├── table-renderer.ts           # Table layout and rendering
│   ├── event-stream.ts             # Event buffering and streaming
│   └── utils/
│       ├── ansi.ts                 # ANSI escape code helpers
│       ├── unicode-width.ts        # Unicode string width calculation
│       └── colors.ts               # Color contrast and theme helpers
├── tests/
│   ├── unit/
│   │   ├── terminal-capabilities_test.ts
│   │   ├── output-formatter_test.ts
│   │   ├── table-renderer_test.ts
│   │   └── event-stream_test.ts
│   ├── integration/
│   │   ├── end-to-end_test.ts      # Full workflow tests
│   │   └── visual_test.ts          # Golden file snapshot tests
│   └── fixtures/
│       ├── table-golden.txt        # Expected table outputs
│       └── mock-terminal.ts        # Mock terminal for testing
└── README.md            # Library documentation

# Integration into existing tools:
home-modules/tools/i3pm/
├── src/
│   ├── commands/
│   │   ├── windows.ts              # Enhanced with renderTable()
│   │   ├── status.ts               # Enhanced with OutputFormatter
│   │   └── ...
│   └── ...
└── ...
```

**Structure Decision**:

We're creating a **reusable library module** (`home-modules/tools/cli-ux/`) that provides UX enhancement APIs, rather than a standalone application. This aligns with the modular composition principle (Constitution I) and enables all existing CLI tools (i3pm, i3-project-*, etc.) to adopt modern UX patterns without code duplication.

The library will be imported by existing tools and gradually integrated into commands based on the phased rollout plan (P1 → P2 → P3).

## Post-Design Constitution Re-Evaluation

*Re-checked after Phase 1 design completion*

### Principle I - Modular Composition ✅

**Status**: PASSES with excellent alignment

The design creates a reusable library module (`home-modules/tools/cli-ux/`) that follows single-responsibility principle with clear module separation:
- `terminal-capabilities.ts` - Detection only
- `output-formatter.ts` - Colors and symbols only
- `progress-indicator.ts` - Progress UI only
- `interactive-prompts.ts` - User input only
- `table-renderer.ts` - Table formatting only
- `event-stream.ts` - Event handling only

Each module has a focused API contract and can be composed into existing CLI tools without tight coupling.

### Principle XIII - Deno CLI Development Standards ✅

**Status**: PASSES - full compliance

All design artifacts confirm:
- TypeScript with Deno 1.40+ runtime
- Heavy use of Deno standard library (@std/cli for prompts, spinners, progress bars)
- Type-safe interfaces with strict TypeScript
- Compilation to standalone executables for distribution
- No Python dependencies (pure Deno/TypeScript)

### Principle XII - Forward-Only Development ✅

**Status**: PASSES - no legacy support

Design includes:
- No feature flags or backward compatibility modes
- Direct enhancement of existing commands (replace, not duplicate)
- Clean migration path documented in quickstart.md
- No preservation of old output formats

### Principle VI - Declarative Configuration ✅

**Status**: PASSES

Library is packaged as a standard NixOS derivation:
- Dependencies declared in `deno.json` and NixOS module
- No imperative installation steps
- Follows existing home-modules pattern

### Additional Validations

**Modular Composition Benefit**: Creating a shared library eliminates need to duplicate UX code across 10+ CLI commands (i3pm, i3-project-switch, i3-project-list, etc.). Follows DRY principle.

**Testing Coverage**: Design includes comprehensive testing strategy (unit, integration, visual regression) aligned with Constitution principle on automated testing.

**No New Violations Introduced**: Post-design review confirms no new constitution violations. All original checks remain passing.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**N/A** - No violations requiring justification.
