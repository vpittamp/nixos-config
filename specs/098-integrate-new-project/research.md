# Research: Worktree-Aware Project Environment Integration

**Feature**: 098-integrate-new-project
**Date**: 2025-11-28
**Status**: Complete

## Research Topics

### 1. Branch Name Parsing Patterns

**Decision**: Implement comprehensive regex-based parsing supporting multiple branch patterns.

**Rationale**: The codebase already uses `<number>-<description>` (e.g., `098-integrate-new-project`) as the dominant convention. Feature 079 has partial parsing at `models/project_filter.py:64-88`. Feature 098 extends this to support additional patterns.

**Alternatives Considered**:
- **Simple prefix extraction only**: Rejected - doesn't support `fix-123-xxx` pattern required by spec
- **Git-flow style detection only**: Rejected - codebase doesn't follow strict git-flow

**Supported Patterns**:

| Pattern | Example | number | type |
|---------|---------|--------|------|
| `<number>-<type>-<desc>` | `098-feature-auth` | "098" | "feature" |
| `<type>-<number>-<desc>` | `fix-123-broken` | "123" | "fix" |
| `<number>-<desc>` | `078-eww-preview` | "078" | "feature" (default) |
| `<type>-<desc>` | `hotfix-critical` | null | "hotfix" |
| Standard branches | `main`, `develop` | null | null |

**Implementation**:
```python
def parse_branch_metadata(branch_name: str) -> Optional[BranchMetadata]:
    """Parse branch name to extract number and type.

    Patterns (in priority order):
    1. <number>-<type>-<description>: 098-feature-auth
    2. <type>-<number>-<description>: fix-123-broken-auth
    3. <number>-<description>: 078-eww-preview (type defaults to "feature")
    4. <type>-<description>: hotfix-critical (no number)
    5. Standard branches: main, develop (no metadata)
    """
    KNOWN_TYPES = {"feature", "fix", "hotfix", "release", "bug", "chore", "docs", "test", "refactor"}

    # Pattern 1: <number>-<type>-<description>
    match = re.match(r'^(\d+)-(' + '|'.join(KNOWN_TYPES) + r')-', branch_name)
    if match:
        return BranchMetadata(
            number=match.group(1),
            type=match.group(2),
            full_name=branch_name
        )

    # Pattern 2: <type>-<number>-<description>
    match = re.match(r'^(' + '|'.join(KNOWN_TYPES) + r')-(\d+)-', branch_name)
    if match:
        return BranchMetadata(
            number=match.group(2),
            type=match.group(1),
            full_name=branch_name
        )

    # Pattern 3: <number>-<description> (type defaults to "feature")
    match = re.match(r'^(\d+)-', branch_name)
    if match:
        return BranchMetadata(
            number=match.group(1),
            type="feature",
            full_name=branch_name
        )

    # Pattern 4: Known type prefix without number
    for type_name in KNOWN_TYPES:
        if branch_name.startswith(f"{type_name}-"):
            return BranchMetadata(
                number=None,
                type=type_name,
                full_name=branch_name
            )

    # No metadata (main, develop, etc.)
    return None
```

---

### 2. Parent Project Resolution

**Decision**: Resolve parent project name during discovery phase using path lookup.

**Rationale**: Feature 097 already extracts `parent_repo_path` (filesystem path) during worktree detection. Feature 098 adds resolution to project name via `find_by_directory()`.

**Alternatives Considered**:
- **Runtime resolution**: Rejected - violates SC-006 (zero runtime parsing)
- **Store path and resolve on demand**: Rejected - inconsistent environment variables
- **Require manual linking**: Rejected - poor UX, defeats automation purpose

**Current Flow (Feature 097)**:
```
Worktree at /home/user/nixos-098-feature
  └─ .git file contains: "gitdir: /etc/nixos/.git/worktrees/nixos-098-feature"
      └─ Resolved to: parent_repo_path = "/etc/nixos"
```

**Enhanced Flow (Feature 098)**:
```
Discovery → parent_repo_path = "/etc/nixos"
           ↓
Project Creation → find_by_directory("/etc/nixos")
                  ↓
              Returns: Project(name="nixos")
                  ↓
              Store: parent_project = "nixos"
```

**Key Files**:
| File | Purpose |
|------|---------|
| `discovery_service.py:83-129` | `get_worktree_parent()` - extracts path |
| `project_service.py:246-259` | `find_by_directory()` - path → project |
| `project_service.py:285-329` | `_create_from_discovery()` - needs parent resolution |

**Edge Cases**:
- Parent repo not discovered as project → `parent_project=null`, log warning
- Multiple worktrees same parent → Each resolves independently
- Nested/symlinked paths → `Path.resolve()` handles normalization

---

### 3. Environment Variable Injection Points

**Decision**: Inject worktree and git metadata variables in app-launcher-wrapper.sh from persisted project JSON.

**Rationale**: Environment variables must be available immediately on process launch. Querying the daemon at launch time already happens; extending it to include git/branch metadata is minimal change.

**Alternatives Considered**:
- **Modify daemon to inject via IPC**: Rejected - app-launcher-wrapper already handles injection
- **Use systemd environment.d**: Rejected - not per-project scoped
- **Read git directly at launch**: Rejected - violates SC-006 (runtime parsing)

**Current Environment Variables** (app-launcher-wrapper.sh:270-298):
```bash
I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR,
I3PM_PROJECT_DISPLAY_NAME, I3PM_PROJECT_ICON, I3PM_SCOPE, I3PM_ACTIVE
```

**New Environment Variables** (Feature 098):
```bash
# Worktree identity
I3PM_IS_WORKTREE="true"
I3PM_PARENT_PROJECT="nixos"
I3PM_BRANCH_NUMBER="098"
I3PM_BRANCH_TYPE="feature"
I3PM_FULL_BRANCH_NAME="098-integrate-new-project"

# Git metadata
I3PM_GIT_BRANCH="098-integrate-new-project"
I3PM_GIT_COMMIT="abc1234"
I3PM_GIT_IS_CLEAN="true"
I3PM_GIT_AHEAD="3"
I3PM_GIT_BEHIND="0"
```

**Injection Source**: All values read from `i3pm project current --json` which returns full project JSON including `branch_metadata` and `git_metadata` fields.

---

### 4. Project Status Validation

**Decision**: Add status check in `_switch_project()` IPC handler before any operations.

**Rationale**: Prevents confusing errors when switching to projects with missing directories. Actionable error message directs user to either restore directory or delete project.

**Implementation Location**: `ipc_server.py:180-250` (`_switch_project()` method)

**Error Message Format**:
```
Cannot switch to project '{name}': directory does not exist at {directory}.
Either restore the directory or delete the project with: i3pm project delete {name}
```

---

### 5. Project Refresh Command

**Decision**: Add `i3pm project refresh [name]` command to re-extract git metadata for existing projects.

**Rationale**: Git state changes over time (new commits, branch renames). Users need a way to update metadata without full re-discovery.

**Alternatives Considered**:
- **Automatic refresh on switch**: Rejected - adds latency to switch (>50ms target)
- **Background refresh daemon**: Rejected - over-engineering for this use case
- **Full re-discovery only**: Rejected - loses manual project customizations

**Implementation**:
```python
# services/project_service.py
async def refresh(self, project_name: str) -> Project:
    """Re-extract git metadata for an existing project.

    Updates: git_metadata, branch_metadata (if worktree)
    Preserves: name, directory, display_name, icon, scoped_classes
    """
    project = self.get(project_name)
    if not project:
        raise ProjectNotFoundError(project_name)

    # Re-extract git metadata
    git_metadata = await extract_git_metadata(Path(project.directory))

    # Re-parse branch metadata if worktree
    branch_metadata = None
    if project.source_type == SourceType.WORKTREE and git_metadata:
        branch_metadata = parse_branch_metadata(git_metadata.branch)

    # Update project
    project.git_metadata = git_metadata
    project.branch_metadata = branch_metadata
    project.updated_at = datetime.now()
    project.save_to_file(self.config_dir)

    return project
```

---

## Summary of Decisions

| Topic | Decision | Key Rationale |
|-------|----------|---------------|
| Branch parsing | Regex with 5 pattern types | Codebase convention + spec requirements |
| Parent resolution | Path lookup at discovery time | Zero runtime parsing (SC-006) |
| Environment injection | app-launcher-wrapper from JSON | Existing pattern, minimal change |
| Status validation | Check in _switch_project() | Actionable error messages |
| Refresh command | New CLI command | Incremental update without full discovery |

## Dependencies Identified

- Feature 097 (Git-based discovery) - COMPLETE, provides foundation
- WorktreeEnvironment model - EXISTS at `models/worktree_environment.py`
- find_by_directory() - EXISTS at `project_service.py:246-259`
- app-launcher-wrapper.sh - EXISTS, needs extension
