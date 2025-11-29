# Implementation Plan: Structured Git Repository Management

**Branch**: `100-automate-project-and` | **Date**: 2025-11-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/100-automate-project-and/spec.md`

## Summary

Replace the existing manual project registration system with an automated, discovery-based approach using bare repositories and sibling worktrees. The system organizes repositories by GitHub account (`~/repos/<account>/<repo>/`) with bare clones (`.bare/` + `.git` pointer) and all branches as worktrees (including main). This enables optimal parallel Claude Code development with zero naming collisions and simple discovery.

## Technical Context

**Language/Version**: Python 3.11+ (daemon), TypeScript/Deno 1.40+ (CLI), Bash 5.0+ (scripts)
**Primary Dependencies**: i3ipc.aio (Sway IPC), Pydantic 2.x (validation), Zod 3.22+ (TypeScript schemas)
**Storage**: JSON files at `~/.config/i3/repos.json` and `~/.config/i3/accounts.json`
**Testing**: pytest (Python), Deno.test (TypeScript), sway-test framework (window manager)
**Target Platform**: NixOS (Hetzner Sway, M1 MacBook Pro)
**Project Type**: Single project (extends existing i3pm tooling)
**Performance Goals**: Discovery <5s for 50 repos + 100 worktrees; clone <30s per repo
**Constraints**: <50MB memory during discovery; no backwards compatibility required
**Scale/Scope**: 2-3 GitHub accounts, 50-100 repositories, 100-200 worktrees

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Discovery service as new module in `home-modules/tools/i3_project_manager/` |
| II. Reference Implementation | ✅ PASS | Hetzner Sway remains reference; feature extends existing i3pm |
| III. Test-Before-Apply | ✅ PASS | All changes tested via dry-build before applying |
| X. Python Standards | ✅ PASS | Python 3.11+, async/await, Pydantic, pytest |
| XI. i3 IPC Alignment | ✅ PASS | No i3 IPC needed for git operations |
| XII. Forward-Only Development | ✅ PASS | Replaces existing project logic completely, no backwards compatibility |
| XIII. Deno CLI Standards | ✅ PASS | CLI commands use TypeScript/Deno with Zod validation |
| XIV. Test-Driven Development | ✅ PASS | Tests written before implementation |

## Project Structure

### Documentation (this feature)

```text
specs/100-automate-project-and/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── discovery-api.yaml
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
home-modules/tools/i3_project_manager/
├── models/
│   ├── account.py           # AccountConfig Pydantic model
│   ├── bare_repo.py         # BareRepository model
│   ├── worktree.py          # Worktree model (replaces existing)
│   └── discovered_project.py # DiscoveredProject model
├── services/
│   ├── discovery_service.py # Repository/worktree discovery
│   ├── clone_service.py     # Bare clone with worktree setup
│   ├── worktree_service.py  # Worktree CRUD operations (replaces existing)
│   └── git_utils.py         # Git command wrappers (extended)
├── cli/
│   └── commands.py          # CLI commands (extended)

home-modules/tools/i3pm-cli/              # TypeScript/Deno CLI
├── src/
│   ├── commands/
│   │   ├── clone.ts         # i3pm clone <url>
│   │   ├── worktree.ts      # i3pm worktree create/list/remove
│   │   └── discover.ts      # i3pm discover
│   └── models/
│       ├── account.ts       # AccountConfig Zod schema
│       └── repository.ts    # Repository/Worktree schemas

scripts/
└── i3pm-clone.sh            # Bash wrapper for bare clone

tests/100-automate-project-and/
├── unit/
│   ├── test_account_model.py
│   ├── test_discovery_service.py
│   └── test_clone_service.py
├── integration/
│   └── test_bare_clone_workflow.py
└── fixtures/
    └── mock_repos/
```

**Structure Decision**: Single project extending existing `i3_project_manager` with new discovery-based services. Replaces `project_service.py` and `project_editor.py` with new discovery-oriented architecture.

## Complexity Tracking

> No violations - design follows Constitution principles.

---

## Phase 0: Research

### Research Tasks

1. **Git bare clone + worktree workflow**
   - Verify `git clone --bare` + `git worktree add` produces expected structure
   - Test `.git` pointer file approach with sibling worktrees

2. **Remote URL parsing patterns**
   - Parse `git@github.com:account/repo.git` (SSH)
   - Parse `https://github.com/account/repo.git` (HTTPS)
   - Extract account and repo name reliably

3. **Worktree discovery from bare repos**
   - Use `git worktree list` to enumerate worktrees
   - Handle worktrees outside repo directory (linked paths)

4. **Integration with existing i3pm daemon**
   - IPC methods needed for discovery trigger
   - Project registration via existing `ProjectConfig` or new model

See [research.md](./research.md) for detailed findings.

---

## Phase 1: Design

### Data Models

See [data-model.md](./data-model.md) for complete entity definitions.

**Key Entities**:
- `AccountConfig`: GitHub account with base directory path
- `BareRepository`: Repo with `.bare/` structure, linked worktrees
- `Worktree`: Working directory linked to bare repo
- `DiscoveredProject`: Unified view for UI (repo or worktree)

### API Contracts

See [contracts/discovery-api.yaml](./contracts/discovery-api.yaml) for OpenAPI spec.

**Key Operations**:
- `i3pm clone <url>` - Bare clone with main worktree
- `i3pm worktree create <branch>` - Create sibling worktree
- `i3pm worktree list [repo]` - List worktrees
- `i3pm worktree remove <branch>` - Remove worktree
- `i3pm discover` - Scan and register all repos/worktrees

### Quick Start

See [quickstart.md](./quickstart.md) for user-facing documentation.

---

## Phase 2: Tasks

Generated via `/speckit.tasks` command (not part of `/speckit.plan` output).
