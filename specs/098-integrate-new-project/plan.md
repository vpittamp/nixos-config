# Implementation Plan: Worktree-Aware Project Environment Integration

**Branch**: `098-integrate-new-project` | **Date**: 2025-11-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/098-integrate-new-project/spec.md`

## Summary

Integrate Feature 097's worktree/project discovery architecture into the Sway project management workflow by:
1. Moving branch metadata parsing from runtime to discovery time (persist in project JSON)
2. Adding parent project resolution during discovery (link worktrees to parent repos)
3. Injecting complete worktree environment context (I3PM_* variables) on project switch
4. Adding git metadata environment variables (branch, commit, clean status)
5. Validating project status before operations (prevent switching to missing projects)

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon standard per Constitution Principle X), Bash 5.0+ (app-launcher-wrapper)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic 2.x (data validation), asyncio (event handling)
**Storage**: JSON files in `~/.config/i3/projects/*.json` (Project definitions with extended worktree fields)
**Testing**: pytest + pytest-asyncio (unit/integration), sway-test framework (window manager tests)
**Target Platform**: Linux with Sway compositor (Hetzner-sway, M1 NixOS)
**Project Type**: Single - extends existing i3-project-event-daemon
**Performance Goals**: <50ms environment injection latency (SC-001), <200ms project switch (SC-005)
**Constraints**: Zero runtime branch parsing (SC-006), graceful degradation for missing metadata
**Scale/Scope**: 50+ worktree projects across multiple parent repositories (SC-005)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| **I. Modular Composition** | Composable modules, single responsibility | ✅ Pass | Extends existing discovery/project modules |
| **III. Test-Before-Apply** | dry-build before switch | ✅ Pass | Standard NixOS workflow applies |
| **VI. Declarative Configuration** | Nix expressions, no imperative scripts | ✅ Pass | All config via JSON + Nix modules |
| **X. Python Standards** | Python 3.11+, async/await, Pydantic, pytest | ✅ Pass | Extends existing daemon architecture |
| **XI. i3 IPC Alignment** | Sway IPC as state authority | ✅ Pass | Environment injection doesn't override IPC |
| **XII. Forward-Only** | Optimal solution, no legacy compatibility | ✅ Pass | Replacing runtime parsing with discovery-time |
| **XIV. Test-Driven Development** | Tests before implementation | ✅ Pass | Unit + integration tests planned |

**Gate Result**: ✅ PASS - All relevant principles satisfied

## Project Structure

### Documentation (this feature)

```text
specs/098-integrate-new-project/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (IPC method contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── models/
│   ├── project.py           # MODIFY: Add branch_metadata, parent_project fields
│   ├── discovery.py         # MODIFY: Add BranchMetadata model
│   └── worktree_environment.py  # EXISTS: WorktreeEnvironment model
├── services/
│   ├── discovery_service.py # MODIFY: Parse branch metadata during discovery
│   ├── project_service.py   # MODIFY: Add refresh method, status validation
│   └── app_launcher.py      # MODIFY: Remove runtime parsing, use persisted data
├── ipc_server.py            # MODIFY: Add status validation to switch_project
└── __main__.py              # No changes expected

scripts/
└── app-launcher-wrapper.sh  # MODIFY: Inject I3PM_GIT_*, I3PM_BRANCH_* variables

tests/098-integrate-new-project/
├── unit/
│   ├── test_branch_metadata_parsing.py
│   └── test_worktree_environment.py
├── integration/
│   ├── test_discovery_with_branch_metadata.py
│   └── test_project_switch_with_worktree_context.py
└── fixtures/
    └── mock_projects.py
```

**Structure Decision**: Single project extending existing i3-project-event-daemon. All changes modify existing files in `home-modules/desktop/i3-project-event-daemon/` and `scripts/`. Tests in dedicated `tests/098-*` directory.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations - all changes extend existing patterns without adding new complexity.*
