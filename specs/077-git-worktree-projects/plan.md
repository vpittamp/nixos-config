# Implementation Plan: Git Worktree Project Management

**Branch**: `077-git-worktree-projects` | **Date**: 2025-11-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/077-git-worktree-projects/spec.md`

## Summary

This feature integrates git worktrees with the i3pm project management system, enabling developers to create isolated workspaces for feature branches that automatically configure project-scoped applications to use the worktree directory. The system provides automated worktree creation/deletion, visual selection via Eww dialogs, automatic discovery on daemon startup, and complete integration with existing i3pm project switching mechanisms.

**Technical Approach**: Extend the existing Deno/TypeScript i3pm CLI with worktree management commands, add Python daemon hooks for worktree discovery, create Eww widget for worktree selection with git status metadata, and leverage existing project directory binding mechanism for scoped application context.

## Technical Context

**Language/Version**:
- TypeScript with Deno 1.40+ (CLI commands, worktree operations)
- Python 3.11+ (daemon integration, discovery service)
- Bash (git worktree wrapper scripts)

**Primary Dependencies**:
- Deno standard library (@std/cli, @std/path, @std/fs, @std/json)
- Zod 3.22+ (runtime type validation for TypeScript)
- Git CLI 2.5+ (git worktree commands)
- Existing i3pm-deno codebase (`home-modules/tools/i3pm-deno/`)
- Existing i3pm daemon (`home-modules/tools/i3pm-diagnostic.nix`, Python-based)
- Eww widget framework (`home-modules/desktop/eww/`)

**Storage**:
- i3pm project JSON files (`~/.config/i3/projects/<name>.json`) - extended with worktree metadata
- Git worktree metadata (`.git/worktrees/`) - read-only, authoritative source
- Worktree discovery cache (`~/.cache/i3pm/worktree-discovery.json`) - ephemeral, regenerated on daemon restart

**Testing**:
- Deno.test() for TypeScript unit/integration tests
- pytest for Python daemon tests
- sway-test framework for end-to-end worktree workflow validation (JSON test definitions)

**Target Platform**: NixOS with Sway window manager, i3pm daemon, Eww widgets

**Project Type**: System tooling extension (i3pm CLI + daemon + Eww widgets)

**Performance Goals**:
- Worktree creation: <5 seconds (includes git worktree add + i3pm project registration)
- Project switching: <500ms (reuse existing i3pm switch performance)
- Worktree discovery: <2 seconds for 20 worktrees
- Eww dialog open: <200ms to display metadata

**Constraints**:
- Must not break existing i3pm project management workflows
- Must handle git worktree failures gracefully (branch conflicts, disk space, permissions)
- Must prevent data loss (no deletion of worktrees with uncommitted changes)
- Must work with existing project-scoped app launcher system
- Must integrate with Feature 076 mark-based app identification

**Scale/Scope**:
- Support 10+ concurrent worktrees per repository
- Handle repositories up to 10GB (NixOS config typical size)
- Support 50+ total i3pm projects (worktree + non-worktree)
- Git operations timeout: 30 seconds for large repositories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Constitution Compliance

✅ **Principle X (Python Development & Testing Standards)**: Python 3.11+ for daemon extension, pytest testing, async patterns via i3ipc.aio

✅ **Principle XIII (Deno CLI Development Standards)**: TypeScript/Deno for new CLI commands, parseArgs() for argument parsing, compiled executables

✅ **Principle XI (i3 IPC Alignment & State Authority)**: Will use i3 IPC for workspace state, not parallel tracking

✅ **Principle XIV (Test-Driven Development)**: Will create comprehensive test suite before implementation (sway-test + pytest + Deno.test)

✅ **Principle XV (Sway Test Framework Standards)**: Will use declarative JSON tests for worktree workflow validation

✅ **Principle XII (Forward-Only Development)**: No legacy compatibility - clean extension of i3pm without backwards compatibility layers

✅ **Principle VI (Declarative Configuration)**: Worktree metadata stored in JSON, project definitions declarative

⚠️ **Potential Concern - Principle I (Modular Composition)**: Must ensure worktree functionality is properly modular (separate commands, services, models) - will validate in Phase 1 design

## Project Structure

### Documentation (this feature)

```text
specs/077-git-worktree-projects/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - git worktree patterns, Eww integration strategies
├── data-model.md        # Phase 1 output - worktree metadata schema, project extensions
├── quickstart.md        # Phase 1 output - user guide for worktree commands
├── contracts/           # Phase 1 output - CLI command interfaces, daemon APIs
│   ├── cli-commands.md  # i3pm worktree create/delete/list/discover
│   ├── daemon-api.md    # Discovery service, state sync
│   └── eww-widget.md    # Worktree selector interface contract
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/tools/i3pm-deno/
├── src/
│   ├── commands/
│   │   ├── worktree.ts              # NEW: Main worktree command dispatcher
│   │   ├── worktree/
│   │   │   ├── create.ts            # NEW: i3pm worktree create
│   │   │   ├── delete.ts            # NEW: i3pm worktree delete
│   │   │   ├── list.ts              # NEW: i3pm worktree list
│   │   │   └── discover.ts          # NEW: i3pm worktree discover
│   │   └── project.ts               # MODIFIED: Add worktree-aware project operations
│   ├── services/
│   │   ├── git-worktree.ts          # NEW: Git worktree operations wrapper
│   │   ├── worktree-metadata.ts     # NEW: Worktree state extraction (git status, branch info)
│   │   └── project-manager.ts       # MODIFIED: Add worktree project type handling
│   ├── models/
│   │   ├── worktree.ts              # NEW: WorktreeProject, WorktreeMetadata types
│   │   └── project.ts               # MODIFIED: Add worktree discriminator
│   └── utils/
│       └── git.ts                   # NEW: Git CLI interaction utilities
├── tests/
│   ├── unit/
│   │   ├── git-worktree_test.ts     # NEW: Git operations unit tests
│   │   └── worktree-metadata_test.ts # NEW: Metadata extraction tests
│   └── integration/
│       └── worktree-lifecycle_test.ts # NEW: Create → switch → delete workflow
└── README.md                        # MODIFIED: Add worktree command documentation

home-modules/tools/i3pm-daemon/      # Python daemon
├── services/
│   └── worktree_discovery.py        # NEW: Auto-discovery service
└── tests/
    └── test_worktree_discovery.py   # NEW: Discovery tests

home-modules/desktop/eww/widgets/
├── worktree-selector.yuck           # NEW: Eww worktree selector widget
└── worktree-selector.scss           # NEW: Widget styling

tests/sway-tests/worktree/           # Sway test framework tests
├── test_worktree_create.json        # NEW: Worktree creation workflow
├── test_worktree_switch.json        # NEW: Project switch with worktree
└── test_app_directory_context.json  # NEW: Apps open in worktree directory
```

**Structure Decision**: Extend existing i3pm-deno CLI with new `worktree` command namespace, add Python discovery service to daemon, create new Eww widget for visual selection. This follows existing patterns (commands/, services/, models/) and maintains modularity.

## Complexity Tracking

*No constitution violations requiring justification.*

## Phase 0: Research & Outline

### Research Tasks

1. **Git Worktree Best Practices**
   - Analyze git worktree CLI patterns (add, remove, list, prune)
   - Research worktree naming conventions and directory structures
   - Identify common failure modes (branch conflicts, locked worktrees, partial deletions)
   - Document error message patterns for user guidance

2. **i3pm Project Extension Patterns**
   - Review existing project.ts model for extension points
   - Analyze project JSON schema for backward-compatible worktree metadata
   - Study existing project directory binding mechanism (how CWD is set for apps)
   - Identify how Feature 076 marks can track worktree-launched apps

3. **Eww Widget Integration**
   - Research existing Eww project switcher widget structure
   - Analyze git status integration patterns (clean/dirty state)
   - Study Eww variable binding for dynamic metadata display
   - Identify performance considerations for git status checks (parallel execution)

4. **Python Daemon Discovery Architecture**
   - Review existing daemon startup sequence for hook points
   - Analyze i3pm project registration API
   - Study file-watching patterns for `.git/worktrees/` changes
   - Research optimal discovery trigger points (daemon start, manual command, periodic)

### Research Deliverables

- `research.md` documenting:
  - Git worktree command patterns with error handling strategies
  - Project model extension schema (backward-compatible)
  - Eww widget architecture for worktree selector
  - Daemon discovery service design (startup hooks, state sync)
  - Performance optimization strategies (parallel git status, caching)

## Phase 1: Design & Contracts

### Data Model Design (`data-model.md`)

**Entities**:

1. **WorktreeProject** (extends i3pm Project)
   - `name`: string (project identifier, unique)
   - `directory`: string (absolute path to worktree)
   - `display_name`: string (human-readable name)
   - `icon`: string (emoji/unicode icon)
   - `created_at`: ISO 8601 timestamp
   - `updated_at`: ISO 8601 timestamp
   - `worktree`: WorktreeMetadata (discriminator - presence indicates worktree project)
   - `scoped_classes`: string[] (app classes to scope)

2. **WorktreeMetadata**
   - `branch`: string (git branch name)
   - `commit_hash`: string (current HEAD commit)
   - `is_clean`: boolean (no uncommitted changes)
   - `has_untracked`: boolean (untracked files present)
   - `ahead_count`: number (commits ahead of remote)
   - `behind_count`: number (commits behind of remote)
   - `worktree_path`: string (absolute path, for validation)
   - `repository_path`: string (main repository path)
   - `last_modified`: ISO 8601 timestamp (most recent git activity)

3. **WorktreeDiscoveryEntry**
   - `worktree_path`: string
   - `branch_name`: string
   - `is_registered`: boolean (exists in i3pm projects)
   - `discovered_at`: ISO 8601 timestamp

**Relationships**:
- WorktreeProject inherits from Project (existing i3pm model)
- WorktreeMetadata is embedded in WorktreeProject (one-to-one)
- WorktreeDiscoveryEntry maps to potential WorktreeProjects (discovery → registration)

**State Transitions**:
- `Unregistered` → `Registered` (via `i3pm worktree create` or `i3pm worktree discover`)
- `Registered` → `Active` (via `i3pm project switch`)
- `Active` → `Registered` (via switch to another project)
- `Registered` → `Deleted` (via `i3pm worktree delete`, git worktree remove)

**Validation Rules**:
- `worktree_path` MUST exist as git worktree (validated via `git worktree list`)
- `branch` MUST match git HEAD in worktree directory
- `name` MUST be unique across all projects (worktree + non-worktree)
- Deletion MUST be blocked if `is_clean` is false and `has_untracked` is true (unless --force)

### API Contracts (`contracts/`)

**1. CLI Command Interface** (`cli-commands.md`):

```typescript
// i3pm worktree create <branch-name> [options]
interface WorktreeCreateCommand {
  branchName: string;              // Required: branch to checkout/create
  worktreeName?: string;           // Optional: custom worktree directory name (default: branch-name)
  basePath?: string;               // Optional: custom base directory (default: sibling to main repo)
  checkout?: boolean;              // Optional: checkout existing branch vs create new (default: auto-detect)
  projectOptions?: {               // Optional: i3pm project customization
    displayName?: string;
    icon?: string;
    scopedClasses?: string[];
  };
}

// i3pm worktree delete <name> [options]
interface WorktreeDeleteCommand {
  projectName: string;             // Required: i3pm project name
  force?: boolean;                 // Optional: delete even with uncommitted changes (default: false)
  keepProject?: boolean;           // Optional: remove worktree but keep i3pm project (default: false)
}

// i3pm worktree list [options]
interface WorktreeListCommand {
  format?: "table" | "json" | "names";  // Optional: output format (default: table)
  showMetadata?: boolean;          // Optional: include git status metadata (default: false)
  filterDirty?: boolean;           // Optional: show only worktrees with uncommitted changes
}

// i3pm worktree discover
interface WorktreeDiscoverCommand {
  autoRegister?: boolean;          // Optional: automatically register discovered worktrees (default: prompt)
  repositoryPath?: string;         // Optional: specific repository to scan (default: current repo)
}
```

**2. Daemon API** (`daemon-api.md`):

```python
# Worktree Discovery Service (Python daemon extension)
class WorktreeDiscoveryService:
    async def discover_worktrees(
        self,
        repository_path: str
    ) -> list[WorktreeDiscoveryEntry]:
        """
        Scan git repository for worktrees, compare against registered i3pm projects.
        Returns list of discovered worktrees with registration status.
        """
        pass

    async def register_worktree_project(
        self,
        worktree_path: str,
        project_options: ProjectOptions
    ) -> WorktreeProject:
        """
        Create i3pm project from discovered worktree.
        Extracts git metadata and writes project JSON.
        """
        pass

    async def sync_worktree_metadata(
        self,
        project_name: str
    ) -> WorktreeMetadata:
        """
        Update worktree metadata for existing project.
        Called on project switch or periodic refresh.
        """
        pass
```

**3. Eww Widget Interface** (`eww-widget.md`):

```lisp
; Eww worktree selector widget
(defwidget worktree-selector []
  (box :class "worktree-selector"
       :orientation "v"
    (label :text "Worktrees" :class "header")
    (scroll :vscroll true
            :hscroll false
      (box :orientation "v"
           :spacing 10
        (for entry in worktree_list
          (worktree-entry :entry entry))))))

(defwidget worktree-entry [entry]
  (eventbox :onclick "i3pm worktree switch ${entry.name}"
    (box :class "worktree-entry ${entry.is_dirty ? 'dirty' : 'clean'}"
         :spacing 8
      (label :text entry.icon)
      (box :orientation "v"
           :spacing 2
        (label :text entry.display_name :class "name")
        (label :text "Branch: ${entry.branch}" :class "branch")
        (label :text "Modified: ${entry.last_modified_relative}" :class "metadata")
        (label :text entry.status_text :class "status ${entry.is_dirty ? 'dirty' : 'clean'}")))))

; Required Eww variables (populated by script)
(defpoll worktree_list :interval "5s"
                        :initial "[]"
  "i3pm worktree list --format json")
```

### Quickstart Guide (`quickstart.md`)

```markdown
# Git Worktree Project Management - Quickstart

## Creating a Worktree Project

```bash
# Create worktree for new feature branch
i3pm worktree create feature-auth-refactor

# Create worktree from existing remote branch
i3pm worktree create hotfix-payment --checkout

# Custom worktree directory and project settings
i3pm worktree create feature-ui --name ui-work --icon 🎨
```

## Switching Worktree Projects

```bash
# Via existing i3pm command
i3pm project switch feature-auth-refactor

# Or use visual selector (Win+P)
# Select worktree from Eww dialog
```

## Viewing Worktrees

```bash
# List all worktrees
i3pm worktree list

# Show detailed metadata
i3pm worktree list --show-metadata

# JSON output for scripting
i3pm worktree list --format json
```

## Deleting Worktrees

```bash
# Safe delete (blocks if uncommitted changes)
i3pm worktree delete feature-auth-refactor

# Force delete (removes even with changes)
i3pm worktree delete old-experiment --force

# Remove worktree but keep project
i3pm worktree delete archived-feature --keep-project
```

## Auto-Discovery

```bash
# Discover manually created worktrees
i3pm worktree discover

# Auto-register all discovered
i3pm worktree discover --auto-register
```

## Troubleshooting

**Apps not opening in worktree directory?**
- Check: `i3pm project current` shows correct directory
- Verify: App is in scoped_classes list
- Test: Launch terminal manually to confirm CWD

**Worktree creation fails?**
- Check: Branch name doesn't already exist
- Verify: Disk space available
- Confirm: No locked worktrees (`git worktree list`)

**Discovery not finding worktrees?**
- Ensure you're in a git repository
- Check `.git/worktrees/` directory exists
- Restart i3pm daemon: `systemctl --user restart i3-project-event-listener`
```

### Post-Design Constitution Re-Check

✅ **Principle I (Modular Composition)**: Design maintains clear separation - commands/, services/, models/ for CLI, Python service for daemon, separate Eww widget. No code duplication.

✅ **Principle X (Python Standards)**: Discovery service follows async patterns, will use pytest, type hints with Pydantic models.

✅ **Principle XIII (Deno Standards)**: CLI commands use parseArgs(), Zod validation, TypeScript strict mode, compiled executables.

✅ **Principle XIV (Test-Driven Development)**: Test pyramid planned - unit (data models, git operations), integration (worktree lifecycle), e2e (sway-test framework).

✅ **All other principles**: No violations introduced by design.

## Next Steps

After completing `/speckit.plan`, proceed with:

1. **Phase 0 Execution**: Generate `research.md` with detailed findings on git worktree patterns, i3pm integration, Eww widgets, daemon discovery

2. **Phase 1 Execution**: Generate `data-model.md` (entity schemas with validation rules), `contracts/` (detailed API specifications), `quickstart.md` (user guide with examples)

3. **Agent Context Update**: Run `.specify/scripts/bash/update-agent-context.sh claude` to add TypeScript/Deno, Zod, git CLI patterns to CLAUDE.md

4. **Phase 2 - Task Generation**: Run `/speckit.tasks` to generate dependency-ordered task list for implementation

5. **Implementation**: Follow test-driven development - write tests first, implement features, iterate until all tests pass

## Notes

- Leverage existing i3pm project switching mechanism - no need to reimplement
- Feature 076 mark-based app identification will automatically work with worktree projects
- Git worktree operations can be slow for large repositories - consider async execution with progress indicators
- Eww widget polling interval (5s) balances freshness vs performance - may need tuning
- Worktree discovery on daemon startup should be opt-in or throttled to avoid startup delays
