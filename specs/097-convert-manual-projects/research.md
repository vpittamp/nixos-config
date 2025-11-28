# Research: Git-Centric Project and Worktree Management

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-28
**Status**: Complete (Major revision for git-centric architecture)

## Architecture Vision Research

### Core Principle: Git is the Source of Truth

The major architectural decision in this revision is that `bare_repo_path` (GIT_COMMON_DIR) becomes the canonical identifier for all project relationships. This eliminates state synchronization issues and orphaned worktree problems.

## Research Areas

### 1. Bare Repository Path as Canonical Identifier

**Decision**: Use `git rev-parse --git-common-dir` as THE canonical identifier for all worktrees.

**Rationale**:
- `--git-common-dir` returns the path that contains the object store shared by all worktrees
- For bare repos: returns the repo path (e.g., `/home/user/nixos-config.git`)
- For worktrees: returns the main repo's `.git` directory
- Already implemented in both TypeScript and Python codebases

**Implementation** (existing):
```python
# project_editor.py:get_bare_repository_path()
def get_bare_repository_path(directory: str) -> Optional[str]:
    result = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"],
        cwd=directory,
        capture_output=True,
        text=True,
        timeout=5
    )
    if result.returncode != 0:
        return None
    common_dir = result.stdout.strip()
    # Resolve relative paths and normalize
    return resolved_absolute_path
```

**Alternatives Considered**:
- `repository_path` pointing to another worktree (previous approach) - causes orphan issues when that worktree is deleted
- Parsing `.git` file content - fragile, `--git-common-dir` is cleaner and handles all edge cases

### 2. Git Repository Detection Pattern

**Decision**: Use `.git` file/directory existence check with `os.path.isdir()` and `os.path.isfile()`.

**Rationale**: A directory is a git repository if it contains:
- `.git/` directory (standard repository)
- `.git` file (worktree or submodule - file contains `gitdir: /path/to/actual/git/dir`)

This is the canonical method used by git itself and avoids subprocess overhead.

**Alternatives Considered**:
- `git rev-parse --is-inside-work-tree`: More accurate but requires subprocess per directory (too slow)
- Walking `.git/HEAD`: Validates git structure but `.git` existence is sufficient for discovery

### 3. Project Type Classification (NEW)

**Decision**: Three types via `source_type` enum: `repository`, `worktree`, `standalone`

**Type Definitions**:

| Type | Criteria | bare_repo_path | parent_project |
|------|----------|----------------|----------------|
| `repository` | First registered project for a bare repo | Set (shared) | null |
| `worktree` | Additional working directory for same bare repo | Set (matches parent) | Required (parent name) |
| `standalone` | Non-git directory OR simple repo with no registered worktrees | Set (if git) or null | null |

**Detection Logic**:
```python
def determine_source_type(directory: str, existing_projects: List[Project]) -> str:
    bare_repo = get_bare_repository_path(directory)
    if bare_repo is None:
        return "standalone"  # Not a git repo

    # Check if any existing project has same bare_repo_path as repository type
    existing_repo_project = find_repository_for_bare_repo(bare_repo, existing_projects)

    if existing_repo_project:
        return "worktree"  # Already has a repository project
    else:
        return "repository"  # First project for this bare repo
```

**Rationale**:
- Three types cover all use cases cleanly
- `standalone` handles both non-git directories and simple repos without worktrees
- Single discriminator field enables polymorphic behavior without inheritance complexity

**Alternatives Considered**:
- Four types (separate `manual` type) - adds complexity, legacy manual projects are `standalone`
- Boolean flags (`is_worktree`, `is_repository`) - leads to invalid combinations

### 4. Worktree Detection and Parent Linkage

**Decision**: Use `bare_repo_path` match instead of parsing `.git` file or worktree name.

**Rationale**:
- Two directories belong to the same repository if they have the same `bare_repo_path`
- `git rev-parse --git-common-dir` handles all edge cases automatically
- No need to parse `.git` file content or traverse directory structures

**Implementation Pattern** (simplified with bare_repo_path):
```python
def link_worktree_to_parent(new_project: Project, existing_projects: List[Project]) -> Optional[str]:
    """Find parent project by matching bare_repo_path"""
    if new_project.source_type != "worktree":
        return None

    for proj in existing_projects:
        if proj.source_type == "repository" and proj.bare_repo_path == new_project.bare_repo_path:
            return proj.name

    return None  # Orphan - no repository project found
```

**Alternatives Considered**:
- Store parent as directory path - fragile if parent directory moves
- Parse `.git` file content - unnecessary complexity when bare_repo_path works

### 5. Git Metadata Extraction

**Decision**: Use `subprocess.run()` with specific git commands for each metadata field.

**Rationale**: Git plumbing commands provide reliable, machine-parseable output. Async subprocess allows non-blocking extraction.

**Commands Used**:
| Metadata | Command | Notes |
|----------|---------|-------|
| Current branch | `git rev-parse --abbrev-ref HEAD` | Returns branch name or "HEAD" if detached |
| Commit hash | `git rev-parse --short HEAD` | 7-char abbreviated hash |
| Is clean | `git status --porcelain` | Empty output = clean |
| Has untracked | `git status --porcelain` | Lines starting with `??` |
| Remote URL | `git remote get-url origin` | May fail if no remote |
| Ahead/behind | `git rev-list --left-right --count @{u}...HEAD` | Requires upstream set |

**Performance**: Batch these commands with `asyncio.gather()` for parallel execution (~50ms total vs ~300ms sequential).

**Alternatives Considered**:
- GitPython library: Heavy dependency, overkill for simple metadata
- dulwich (pure Python git): Good but subprocess is simpler and battle-tested
- libgit2 bindings: Complex C dependency, NixOS packaging challenges

### 6. Orphan Detection and Handling (NEW)

**Decision**: Mark worktrees as `status: orphaned` when parent repository project is missing.

**Definition**: A worktree is orphaned when:
1. `source_type == "worktree"` AND
2. No project with `source_type == "repository"` has matching `bare_repo_path`

**Recovery Options**:
1. **[Recover]**: Discover and create Repository Project for the orphan's bare_repo_path
2. **[Delete Registration]**: Remove the orphan project JSON (keeps git worktree on disk)

**Implementation**:
```python
def detect_orphaned_worktrees(projects: List[Project]) -> List[Project]:
    """Find worktrees with no matching repository project"""
    repo_bare_paths = {
        p.bare_repo_path for p in projects
        if p.source_type == "repository" and p.bare_repo_path
    }

    orphans = []
    for p in projects:
        if p.source_type == "worktree" and p.bare_repo_path not in repo_bare_paths:
            p.status = "orphaned"
            orphans.append(p)

    return orphans
```

**Rationale**:
- Using `bare_repo_path` match is reliable even if parent project was renamed
- Preserves worktree data for recovery rather than auto-deleting
- Clear user action required (recover vs delete)

### 7. Conflict Resolution (Same Name)

**Decision**: Append numeric suffix for conflicts: `my-app`, `my-app-2`, `my-app-3`.

**Rationale**: Simple, predictable, and preserves the original name as the primary project. Users can rename via existing project edit functionality.

**Algorithm**:
```python
def generate_unique_name(base_name: str, existing_names: Set[str]) -> str:
    if base_name not in existing_names:
        return base_name
    counter = 2
    while f"{base_name}-{counter}" in existing_names:
        counter += 1
    return f"{base_name}-{counter}"
```

**Alternatives Considered**:
- Include parent directory in name (`projects-my-app`): Verbose, not user-friendly
- Use full path hash suffix (`my-app-a3f2`): Not human-readable
- Fail on conflict: Bad UX, blocks discovery workflow

### 8. Panel Hierarchy Structure (NEW)

**Decision**: Repository Projects as collapsible containers, Worktrees nested underneath

**Visual Structure**:
```
▼ 🔧 nixos (5 worktrees)  [+ Create] [Refresh]
    ├─ 🌿 097-feature ● (dirty)  [Switch] [Delete]
    ├─ 🌿 087-ssh-keys            [Switch] [Delete]
    └─ 🌿 085-widget              [Switch] [Delete]

► 📁 other-repo (standalone)  [Switch] [Delete]

─── Orphaned Worktrees ───
    ⚠️ 042-orphan (missing parent)  [Recover] [Delete]
```

**Data Structure** (from monitoring_data.py):
```json
{
  "repository_projects": [
    {
      "name": "nixos",
      "source_type": "repository",
      "bare_repo_path": "/home/user/nixos-config.git",
      "is_expanded": true,
      "worktree_count": 5,
      "has_dirty_worktrees": true,
      "worktrees": [
        {"name": "097-feature", "is_clean": false, "branch": "097-feature"},
        {"name": "087-ssh-keys", "is_clean": true, "branch": "087-ssh-keys"}
      ]
    }
  ],
  "standalone_projects": [
    {"name": "other-repo", "source_type": "standalone"}
  ],
  "orphaned_worktrees": [
    {"name": "042-orphan", "parent_project": "deleted-project", "status": "orphaned"}
  ]
}
```

**Rationale**:
- Maps naturally to Eww box containers
- Nested structure shows relationships clearly
- Separate orphan section makes issues visible

### 9. Daemon State Synchronization

**Decision**: Emit `project_discovered` event via existing IPC; daemon reloads projects from disk.

**Rationale**: Existing daemon pattern reads project files from `~/.config/i3/projects/`. Discovery writes files, then signals daemon to refresh.

**Flow**:
1. Discovery service scans directories
2. For each discovered repo, write/update JSON file
3. After all files written, call daemon RPC `projects_refresh()`
4. Daemon re-reads project directory, updates in-memory state
5. Daemon emits `projects_changed` event to subscribers (monitoring panel)

**Alternatives Considered**:
- Direct daemon memory injection: Bypasses file system, creates state drift
- File watcher on projects directory: Additional complexity, race conditions
- Return projects in discovery response: Doesn't update persistent state

### 10. Default Scan Path Configuration

**Decision**: Store in `~/.config/i3/discovery-config.json` with XDG-compliant location.

**Schema**:
```json
{
  "scan_paths": [
    "~/projects",
    "/etc/nixos"
  ],
  "exclude_patterns": [
    "node_modules",
    "vendor",
    ".cache"
  ],
  "auto_discover_on_startup": false,
  "max_depth": 3
}
```

**Rationale**: JSON config aligns with existing i3pm configuration patterns. XDG location is discoverable.

**Alternatives Considered**:
- Environment variables: Less discoverable, harder to persist
- Nix-based config generation: Too coupled to NixOS, limits portability
- CLI-only (no persistence): Forces repeated `--path` arguments

### 11. Icon Inference from Repository

**Decision**: Map primary language to emoji icon using lookup table.

**Lookup Table** (subset):
| Language | Icon |
|----------|------|
| Python | |
| TypeScript/JavaScript | |
| Rust | |
| Go | |
| Nix | |
| Shell/Bash | |
| Default | |

**Rationale**: Provides visual differentiation without user input. Language is reliably available from GitHub API and can be inferred locally via file extension heuristics.

**Alternatives Considered**:
- Repository topics: Often empty, less reliable
- Custom icon in `.i3pm.json`: Requires repo-side configuration
- No inference: All projects get same default icon

### 12. Missing Repository Handling

**Decision**: Add `status` field to Project model: `active`, `missing`, `orphaned`.

**Rationale**: Preserves project configuration when repository is temporarily unavailable (network drive, moved directory). User explicitly deletes to remove.

**Behavior**:
- On discovery: Check if project directory exists
- If missing: Set `status: "missing"`, preserve other metadata
- UI: Show warning badge, disable "open" actions, enable "delete" action
- On next discovery: If directory reappears, set `status: "active"`

**Alternatives Considered**:
- Auto-delete: Data loss risk, bad for network/removable drives
- Separate "archived" list: Over-engineering for edge case
- Ignore missing: Creates stale projects in UI

## Summary

All research areas have clear decisions with rationale. No NEEDS CLARIFICATION items remain. Ready for Phase 1 design.

### Key Architecture Decisions (NEW in this revision)
- **Canonical identifier**: `bare_repo_path` (GIT_COMMON_DIR) - the single source of truth
- **Three project types**: `repository`, `worktree`, `standalone` via `source_type` enum
- **One Repository Project per bare repo**: Enforced constraint, not optional
- **Parent linkage**: Via `bare_repo_path` match, not name or directory path
- **Orphan handling**: `status: orphaned` with recovery/delete options
- **No backwards compatibility**: Fresh implementation per Constitution XII

### Key Technology Choices
- **Git detection**: `.git` file/directory check (no subprocess)
- **Bare repo path**: `git rev-parse --git-common-dir` (already implemented)
- **Metadata extraction**: Individual git commands via async subprocess
- **Conflict resolution**: Numeric suffix (`-2`, `-3`)
- **State sync**: File-based with daemon refresh RPC
- **Panel hierarchy**: Nested JSON structure for Eww containers

### Removed from Scope
- **GitHub CLI integration**: Focus on local filesystem only per spec revision
- **Background daemon discovery**: Manual discovery via CLI command
