# Implementation Plan: Git-Based Project Discovery and Management

**Branch**: `097-convert-manual-projects` | **Date**: 2025-11-26 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/097-convert-manual-projects/spec.md`

## Summary

Convert i3pm project management from manual JSON creation to automatic git repository discovery. The system will scan configured directories for git repositories, detect worktrees, and optionally query GitHub for remote repositories. Projects will be automatically created with metadata derived from git (branch, commit, remote URL, clean status). The Eww monitoring panel's Projects tab will be enhanced to display git-derived metadata with source type classification.

## Technical Context

**Language/Version**: Python 3.11+ (daemon extensions), TypeScript/Deno 1.40+ (CLI commands)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic 2.x (validation), Zod 3.22+ (TypeScript schemas), gh CLI (GitHub API)
**Storage**: JSON files in `~/.config/i3/projects/`, discovery config in `~/.config/i3/discovery-config.json`
**Testing**: pytest + pytest-asyncio (Python), Deno.test (TypeScript), sway-test framework (E2E)
**Target Platform**: NixOS with Sway compositor (Hetzner, M1)
**Project Type**: Single (extends existing i3pm daemon and CLI)
**Performance Goals**: Discover 10 repositories in <30s, GitHub listing in <5s
**Constraints**: <100ms daemon notification latency, no duplicate projects on repeated discovery
**Scale/Scope**: 10-50 repositories per scan directory (typical)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Extends existing i3pm modules, no duplication |
| III. Test-Before-Apply | PASS | Will include pytest and sway-test validation |
| VI. Declarative Configuration | PASS | Discovery config is declarative JSON |
| X. Python Development Standards | PASS | Uses Python 3.11+, async/await, Pydantic, pytest |
| XI. i3 IPC Alignment | PASS | Daemon notifies state changes via existing IPC |
| XII. Forward-Only Development | PASS | Replaces manual project creation, no backwards compat |
| XIII. Deno CLI Standards | PASS | CLI commands use Deno/TypeScript with Zod |
| XIV. Test-Driven Development | PASS | Tests before implementation |
| XV. Sway Test Framework | PASS | E2E tests use sway-test JSON definitions |

**Gate Status**: PASSED - No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/097-convert-manual-projects/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── discovery-api.md # JSON-RPC contract
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
# Python Daemon Extensions
home-modules/desktop/i3-project-event-daemon/
├── models/
│   ├── project.py              # Extended with source_type, git_metadata
│   └── discovery.py            # NEW: ScanConfiguration, DiscoveryResult
├── services/
│   ├── project_service.py      # Extended with discover(), sync_from_git()
│   ├── discovery_service.py    # NEW: Repository scanner, worktree detector
│   └── github_service.py       # NEW: gh CLI wrapper for remote repos
└── tests/
    ├── unit/
    │   └── test_discovery_service.py
    └── integration/
        └── test_discover_workflow.py

# TypeScript CLI Extensions
home-modules/tools/i3pm-deno/src/
├── commands/
│   └── project.ts              # Extended with 'discover' subcommand
├── services/
│   ├── git-worktree.ts         # Extended with listWorktrees()
│   └── discovery.ts            # NEW: Client-side discovery orchestration
└── models/
    └── discovery.ts            # NEW: Zod schemas for discovery

# Monitoring Panel Updates
home-modules/desktop/eww-monitoring-panel.nix
├── projects-view                # Updated grouping by source_type
├── project-card                 # Updated git metadata display
└── worktree-card               # Updated branch/status indicators

# Monitoring Data Backend
home-modules/tools/i3_project_manager/cli/
└── monitoring_data.py          # Extended --mode projects output

# Tests
tests/097-convert-manual-projects/
├── unit/
│   ├── test_discovery_models.py
│   └── test_github_parser.py
├── integration/
│   ├── test_local_discovery.py
│   └── test_worktree_detection.py
└── e2e/
    └── test_discover_command.json  # sway-test
```

**Structure Decision**: Extends existing i3pm daemon and CLI structure. New services added alongside existing services. No new top-level directories required.

## Complexity Tracking

> No violations to justify - all Constitution checks passed.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
