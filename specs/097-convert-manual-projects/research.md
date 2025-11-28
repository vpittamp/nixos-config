# Research: Git-Based Project Discovery and Management

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-26
**Status**: Complete

## Research Areas

### 1. Git Repository Detection Pattern

**Decision**: Use `.git` file/directory existence check with `os.path.isdir()` and `os.path.isfile()`.

**Rationale**: A directory is a git repository if it contains:
- `.git/` directory (standard repository)
- `.git` file (worktree or submodule - file contains `gitdir: /path/to/actual/git/dir`)

This is the canonical method used by git itself and avoids subprocess overhead.

**Alternatives Considered**:
- `git rev-parse --is-inside-work-tree`: More accurate but requires subprocess per directory (too slow)
- Walking `.git/HEAD`: Validates git structure but `.git` existence is sufficient for discovery

### 2. Worktree Detection and Parent Linkage

**Decision**: Parse `.git` file content for worktrees; use `git worktree list --porcelain` for comprehensive worktree enumeration.

**Rationale**:
- Worktrees have a `.git` **file** (not directory) containing `gitdir: /path/to/.git/worktrees/<name>`
- The parent repository path can be derived by traversing `gitdir` → `commondir` file
- `git worktree list --porcelain` provides machine-readable output with all worktrees

**Implementation Pattern**:
```python
def is_worktree(path: Path) -> bool:
    git_path = path / ".git"
    return git_path.is_file()  # File = worktree, Directory = repo

def get_worktree_parent(worktree_path: Path) -> Path:
    git_file = worktree_path / ".git"
    content = git_file.read_text().strip()
    # Content: "gitdir: /path/to/repo/.git/worktrees/<name>"
    gitdir = Path(content.replace("gitdir: ", ""))
    commondir_file = gitdir / "commondir"
    if commondir_file.exists():
        commondir = commondir_file.read_text().strip()
        return (gitdir / commondir).resolve().parent
    return gitdir.parent.parent.parent  # Fallback: .git/worktrees/<name> → repo
```

**Alternatives Considered**:
- Only use `git worktree list`: Requires subprocess for every potential parent repo
- Store parent relationship in project JSON: Creates sync issues when worktrees created outside i3pm

### 3. Git Metadata Extraction

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

### 4. GitHub CLI Integration

**Decision**: Use `gh repo list --json` with specific fields for efficient metadata retrieval.

**Rationale**: GitHub CLI provides authenticated access with proper rate limiting and pagination handling built-in.

**Command**:
```bash
gh repo list --json name,nameWithOwner,description,primaryLanguage,pushedAt,isArchived,isFork,visibility --limit 100
```

**Output Parsing**: JSON array of repository objects. Parse with `json.loads()` in Python.

**Error Handling**:
- Exit code 1 + "gh auth login" message: Not authenticated → graceful degradation
- Exit code 0 + empty array: No repos or all filtered out
- Timeout after 10s: GitHub API slow → log warning, continue local discovery

**Alternatives Considered**:
- PyGithub/ghapi: Additional dependency vs using existing `gh` CLI
- Direct GitHub REST API: Requires OAuth token management, pagination handling

### 5. Conflict Resolution (Same Name)

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

### 6. Project Source Type Classification

**Decision**: Add `source_type` enum field to Project model: `local`, `worktree`, `remote`.

**Rationale**: Enables UI grouping and filtering. Mutually exclusive classification.

**Classification Logic**:
- `worktree`: Has `.git` file (not directory) pointing to parent repo
- `remote`: Exists only in GitHub, not on local filesystem (future: after clone becomes `local`)
- `local`: Everything else (standard git repository)

**Alternatives Considered**:
- Boolean flags (`is_worktree`, `is_remote`): Less extensible, potential flag conflicts
- Separate entity types: Over-engineering, all share same base functionality

### 7. Daemon State Synchronization

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

### 8. Default Scan Path Configuration

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

### 9. Icon Inference from Repository

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

### 10. Missing Repository Handling

**Decision**: Add `status` field to Project model: `active`, `missing`.

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

### Key Technology Choices
- **Git detection**: `.git` file/directory check (no subprocess)
- **Worktree detection**: Parse `.git` file + `git worktree list --porcelain`
- **GitHub integration**: `gh repo list --json` CLI
- **Metadata extraction**: Individual git commands via async subprocess
- **Conflict resolution**: Numeric suffix (`-2`, `-3`)
- **State sync**: File-based with daemon refresh RPC
