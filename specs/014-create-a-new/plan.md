# Implementation Plan: Consolidate and Validate i3 Project Management System

**Branch**: `014-create-a-new` | **Date**: 2025-10-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-create-a-new/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature consolidates the i3-native project management system (feature 012) with the i3blocks status bar integration (feature 013) to create a complete, validated working system. The goal is to review the overall logic after the polybar→i3blocks migration, ensure alignment with i3's native JSON schema and IPC mechanisms, eliminate code duplication, and thoroughly test the integrated functionality. The system will provide complete project lifecycle management (create, switch, window isolation) with real-time visual feedback in the status bar, comprehensive event logging for debugging, and validation that all implementation uses i3 native features rather than custom logic.

## Technical Context

**Language/Version**: Bash 5.x (shell scripts), Nix 2.x (declarative configuration)
**Primary Dependencies**: i3 window manager (4.15+), i3blocks (1.5+), jq (JSON parsing), rofi (project switcher UI), xdotool (test automation)
**Storage**: JSON files in `~/.config/i3/projects/` (project configurations using i3 schema), `~/.config/i3/active-project` (minimal metadata), `~/.config/i3/project-system.log` (structured logs with rotation)
**Testing**: xdotool for automated UI interaction testing, i3-msg for state verification, manual protocol for lifecycle validation
**Target Platform**: NixOS with i3 window manager on X11, deployed via home-manager
**Project Type**: System integration (window manager + status bar + project management scripts)
**Performance Goals**: <1 second status bar update on project switch, <100ms i3 event logging latency, <5 seconds for full project switch with 10+ windows
**Constraints**: Must use i3 native JSON schema (compatible with `i3-msg -t get_tree`), no custom state tracking beyond i3 marks, automated tests must not close active terminal, log rotation at 10MB with 5 historical files
**Scale/Scope**: Support up to 20 projects per user, 50+ windows across all projects, 3-5 concurrent i3 sessions (multi-user or multi-monitor scenarios)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Review

**I. Modular Composition** - ✅ PASS
- Project management scripts organized as modular components in `home-modules/desktop/i3/` (config), `home-modules/desktop/i3blocks/` (status bar), and shell scripts
- No monolithic configuration files; i3 config, i3blocks config, and project scripts are separate modules
- Each component has single responsibility: project switching, status display, window marking, logging

**II. Reference Implementation Flexibility** - ✅ PASS
- Hetzner configuration with i3wm serves as reference implementation
- Changes will be tested on Hetzner first before applying to WSL or M1 configurations

**III. Test-Before-Apply** - ✅ PASS
- Will use `nixos-rebuild dry-build --flake .#hetzner` before applying changes
- Test suite uses xdotool for non-destructive UI interaction testing
- All tests validate state without breaking active sessions

**VI. Declarative Configuration Over Imperative** - ⚠️ REQUIRES VALIDATION
- GATE: All i3 configuration, i3blocks configuration, and project management scripts MUST be declared in NixOS/home-manager modules
- GATE: No imperative post-install scripts except temporary migration/capture tools
- ACTION REQUIRED (Phase 0): Verify current implementation is fully declarative; identify any imperative scripts that need conversion

**VII. Documentation as Code** - ✅ PASS
- This planning process generates comprehensive documentation (plan.md, research.md, quickstart.md)
- Module structure will include header comments
- Changes will update CLAUDE.md in same commit

**IX. Tiling Window Manager & Productivity Standards** - ✅ PASS
- System uses i3wm as required by constitution
- Keyboard-driven workflows with declarative keybindings
- rofi integration for project switcher
- Dynamic workspace management via project system

### Platform Support Standards

**Multi-Platform Compatibility** - ⚠️ PARTIAL COMPLIANCE
- Primary target is Hetzner (reference implementation with i3)
- WSL and M1 configurations may or may not include i3 (need verification)
- ACTION REQUIRED (Phase 0): Document which platforms will receive this feature

### Home-Manager Standards

**Module Structure** - ⚠️ REQUIRES VALIDATION
- GATE: All i3 and i3blocks configuration MUST use proper home-manager module structure with explicit inputs `{ config, lib, pkgs, ... }:`
- GATE: Configuration files MUST be generated via `xdg.configFile` or `environment.etc`, not copied from external sources
- ACTION REQUIRED (Phase 0): Review existing modules to ensure compliance

**Configuration File Generation** - ⚠️ REQUIRES VALIDATION
- GATE: i3 config MUST be generated via `xdg.configFile."i3/config".text` with Nix string interpolation
- GATE: Scripts MUST use `${pkgs.package}/bin/binary` format for reproducible binary paths
- ACTION REQUIRED (Phase 0): Audit current configuration generation approach

### Critical Gates (MUST RESOLVE BEFORE PROCEEDING)

1. **i3 JSON Schema Alignment** - ⚠️ NEEDS RESEARCH
   - QUESTION: Does current project configuration use i3's native JSON schema (compatible with `i3-msg -t get_tree` output)?
   - QUESTION: What fields are in current project config files? Are they minimal extensions of i3 schema?
   - ACTION REQUIRED (Phase 0): Research i3's JSON schema (`i3-msg -t get_tree`, i3 IPC docs) and compare to current implementation

2. **Native i3 Integration Validation** - ⚠️ NEEDS VALIDATION
   - QUESTION: Do all window queries use `i3-msg -t get_tree` parsing, or is there custom state tracking?
   - QUESTION: Do all window movements use `i3-msg` with criteria syntax `[con_mark="..."]`?
   - ACTION REQUIRED (Phase 0): Audit all project management scripts for i3 IPC usage vs custom logic

3. **Declarative vs Imperative** - ⚠️ NEEDS AUDIT
   - QUESTION: Are there any imperative scripts that modify configuration at runtime?
   - QUESTION: Are all shell scripts properly declared in NixOS modules with generated shebangs?
   - ACTION REQUIRED (Phase 0): Complete audit of configuration generation approach

## Project Structure

### Documentation (this feature)

```
specs/014-create-a-new/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── i3-ipc-schema.json     # i3 IPC JSON schema documentation
│   ├── project-config-schema.json  # Project configuration schema (extends i3)
│   └── logging-format.md      # Log entry format specification
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-modules/
├── desktop/
│   ├── i3/
│   │   ├── default.nix          # Main i3 configuration module
│   │   ├── config.nix           # i3 window manager config with keybindings
│   │   ├── project-manager.nix  # Project management integration
│   │   └── scripts/             # Project management shell scripts
│   │       ├── project-create.sh
│   │       ├── project-switch.sh
│   │       ├── project-list.sh
│   │       ├── project-clear.sh
│   │       ├── project-current.sh
│   │       ├── project-mark-window.sh
│   │       └── project-logs.sh
│   └── i3blocks/
│       ├── default.nix          # i3blocks status bar configuration module
│       ├── config.nix           # i3blocks.conf generation
│       └── scripts/             # Status bar block scripts
│           ├── project.sh       # Project indicator block
│           ├── cpu.sh
│           ├── memory.sh
│           └── datetime.sh
└── shell/
    └── aliases.nix              # Shell aliases for project commands

# Testing infrastructure
tests/
├── i3-project-test.sh           # Automated xdotool-based testing
└── validate-i3-schema.sh        # JSON schema validation

# Reference documentation
docs/
├── i3_man.txt                   # i3 window manager documentation
└── i3-ipc.txt                   # i3 IPC protocol documentation
```

**Structure Decision**: System integration project using NixOS home-manager modules. Configuration is entirely declarative with scripts generated via Nix expressions. No traditional src/ directory because this is infrastructure configuration, not application code. Testing uses shell scripts with xdotool for UI automation and i3-msg for state verification. All logic lives in home-manager modules under `home-modules/desktop/` with proper module structure and explicit imports.

## Complexity Tracking

*No constitutional violations requiring justification. System follows modular composition, declarative configuration, and proper home-manager module patterns.*

---

## Post-Phase 1 Constitutional Re-Evaluation

**Date**: 2025-10-19
**Status**: Phase 1 design artifacts complete (research.md, data-model.md, contracts/, quickstart.md)

### Gate Resolution Status

**Gate 1: i3 JSON Schema Alignment** - ✅ RESOLVED
- **Finding**: System correctly uses i3 native mechanisms for runtime state (marks, IPC queries)
- **Clarification**: "i3 JSON schema alignment" requirement applies to runtime window tracking, not static project metadata files
- **Verdict**: COMPLIANT - Window associations via i3 marks, queries via `i3-msg -t get_tree`, operations via native i3 commands
- **Action Required**: Delete redundant `window-project-map.json` file during implementation

**Gate 2: Native i3 Integration Validation** - ✅ VALIDATED
- **Finding**: 100% of window queries use `i3-msg -t get_tree`, 100% of window movements use `i3-msg` with criteria syntax
- **Evidence**: Confirmed in research.md section 1.3 (Window Association Implementation)
- **Verdict**: COMPLIANT - No custom state tracking beyond marks (except redundant file to be deleted)

**Gate 3: Declarative vs Imperative Configuration** - ❌ FAILED (requires remediation)
- **Finding**: 21 shell scripts use imperative file copying (`source = ./file.sh`) instead of declarative generation (`text = ''...''`)
- **Impact**: Violates Constitution Principle VI - breaks reproducibility guarantee
- **Severity**: CRITICAL - must be fixed during implementation
- **Remediation Plan**: Convert all scripts to declarative generation with `${pkgs.package}/bin/binary` paths
- **Timeline**: Priority 1 task in implementation phase

### Updated Constitution Compliance

| Principle | Pre-Phase 1 Status | Post-Phase 1 Status | Change |
|-----------|-------------------|---------------------|--------|
| I. Modular Composition | ✅ PASS | ✅ PASS | No change - architecture confirmed sound |
| III. Test-Before-Apply | ✅ PASS | ✅ PASS | Test strategy documented in plan |
| VI. Declarative Configuration | ⚠️ REQUIRES VALIDATION | ❌ CRITICAL VIOLATION | Audit revealed imperative script deployment |
| VII. Documentation as Code | ✅ PASS | ✅ PASS | Phase 1 generated comprehensive docs |
| IX. Tiling WM Standards | ✅ PASS | ✅ PASS | i3 native integration validated |

**Overall Grade**: C+ (70%) - Functional system with critical compliance gap requiring remediation

### Critical Path for Implementation

**MUST FIX (Blocks constitutional compliance)**:
1. Convert 16 project management scripts from `source = ./file.sh` to `text = ''...''` syntax
2. Convert 5 i3blocks scripts to inline generation in default.nix
3. Replace all hardcoded binary paths with `${pkgs.package}/bin/binary` format (100+ occurrences)
4. Delete redundant `window-project-map.json` file and associated code

**SHOULD FIX (High value cleanup)**:
5. Remove polybar indicator script and deployment code
6. Remove i3 tick event signals (keep only i3blocks signals)
7. Update documentation comments ("polybar" → "i3bar")

**MAY ENHANCE (Nice to have)**:
8. Improve file write atomicity (atomic rename pattern)
9. Add error logging when signals fail
10. Implement shellcheck validation at build time

### Implementation Phase Readiness

**Prerequisites Complete**:
- ✅ Technical context fully defined
- ✅ i3 JSON schema researched and understood
- ✅ Data model documented with all entities, relationships, validation rules
- ✅ Contracts generated (JSON schemas for project config, active project, app classes)
- ✅ Logging format specification complete
- ✅ Quickstart guide created for end users
- ✅ Agent context updated

**Blockers Identified**:
- ❌ Constitutional compliance violations must be remediated
- ⚠️ Code duplication (polybar remnants) should be removed
- ⚠️ Imperative script deployment violates declarative principles

**Recommendation**: Proceed to implementation phase with **constitutional remediation as Priority 1 work**. System is functionally sound and architecturally correct, but requires compliance fixes for reproducibility guarantees.
