# Data Model: Git-Based Project Discovery

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-26

## Entity Relationship Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    ScanConfiguration                             │
│  (User-defined discovery settings)                              │
├─────────────────────────────────────────────────────────────────┤
│  scan_paths: List[Path]                                         │
│  exclude_patterns: List[str]                                    │
│  auto_discover_on_startup: bool                                 │
│  max_depth: int                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ triggers
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DiscoveryResult                               │
│  (Ephemeral result of discovery operation)                      │
├─────────────────────────────────────────────────────────────────┤
│  discovered_repos: List[DiscoveredRepository]                   │
│  discovered_worktrees: List[DiscoveredWorktree]                 │
│  skipped_paths: List[SkippedPath]                               │
│  duration_ms: int                                               │
│  errors: List[DiscoveryError]                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ creates/updates
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Project (Extended)                         │
│  (Persisted in ~/.config/i3/projects/<name>.json)               │
├─────────────────────────────────────────────────────────────────┤
│  name: str                     # Unique identifier              │
│  display_name: str             # Human-readable                 │
│  directory: Path               # Absolute path                  │
│  icon: str                     # Emoji icon                     │
│  source_type: SourceType       # NEW: local | worktree | remote │
│  status: ProjectStatus         # NEW: active | missing          │
│  git_metadata: GitMetadata?    # NEW: Git-specific data         │
│  worktree: WorktreeMetadata?   # Existing: Worktree linkage     │
│  remote: RemoteConfig?         # Existing: SSH config           │
│  scoped_classes: List[str]     # Existing: App classes          │
│  created_at: datetime                                           │
│  updated_at: datetime                                           │
│  discovered_at: datetime?      # NEW: When discovered           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ contains
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       GitMetadata                                │
│  (Git-specific data attached to projects)                       │
├─────────────────────────────────────────────────────────────────┤
│  current_branch: str           # Branch name or "HEAD"          │
│  commit_hash: str              # Short SHA (7 chars)            │
│  is_clean: bool                # No uncommitted changes         │
│  has_untracked: bool           # Untracked files present        │
│  ahead_count: int              # Commits ahead of upstream      │
│  behind_count: int             # Commits behind upstream        │
│  remote_url: str?              # Origin remote URL              │
│  primary_language: str?        # Inferred or from GitHub        │
│  last_commit_date: datetime?   # HEAD commit timestamp          │
└─────────────────────────────────────────────────────────────────┘
```

## Entities

### 1. ScanConfiguration

User-defined settings for repository discovery.

**Storage**: `~/.config/i3/discovery-config.json`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| scan_paths | List[str] | Yes | `["~/projects"]` | Directories to scan for repositories |
| exclude_patterns | List[str] | No | `["node_modules", "vendor", ".cache"]` | Directory names to skip |
| auto_discover_on_startup | bool | No | `false` | Run discovery when daemon starts |
| max_depth | int | No | `3` | Maximum recursion depth for scanning |

**Validation Rules**:
- `scan_paths` must be non-empty
- Each path must be expandable (~ allowed) and absolute after expansion
- `max_depth` must be between 1 and 10
- `exclude_patterns` are case-sensitive glob patterns

### 2. DiscoveryResult

Ephemeral result returned from a discovery operation.

**Storage**: Not persisted (returned from RPC call)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| discovered_repos | List[DiscoveredRepository] | Yes | Repositories found |
| discovered_worktrees | List[DiscoveredWorktree] | Yes | Worktrees found |
| skipped_paths | List[SkippedPath] | Yes | Paths skipped (not git repos) |
| projects_created | int | Yes | Count of new projects |
| projects_updated | int | Yes | Count of updated projects |
| projects_marked_missing | int | Yes | Count of newly missing projects |
| duration_ms | int | Yes | Time taken in milliseconds |
| errors | List[DiscoveryError] | Yes | Non-fatal errors encountered |

### 3. DiscoveredRepository

Intermediate representation of a found repository before project creation.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| path | Path | Yes | Absolute path to repository |
| name | str | Yes | Derived from directory name |
| is_worktree | bool | Yes | True if .git is a file |
| git_metadata | GitMetadata | Yes | Extracted git data |
| parent_repo_path | Path? | No | For worktrees, path to main repo |
| inferred_icon | str | Yes | Emoji based on language |

### 4. Project (Extended)

Extended project entity with new fields for discovery support.

**Storage**: `~/.config/i3/projects/<name>.json`

**New Fields** (additions to existing Project model):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| source_type | SourceType | Yes | `"local"` | How project was created |
| status | ProjectStatus | Yes | `"active"` | Project availability |
| git_metadata | GitMetadata? | No | null | Git-specific data |
| discovered_at | datetime? | No | null | When first discovered |

**Existing Fields** (unchanged):
- `name`, `display_name`, `directory`, `icon`, `scoped_classes`
- `worktree` (WorktreeMetadata), `remote` (RemoteConfig)
- `created_at`, `updated_at`

### 5. GitMetadata

Git-specific metadata attached to discovered projects.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| current_branch | str | Yes | - | Branch name or "HEAD" if detached |
| commit_hash | str | Yes | - | Short SHA (7 characters) |
| is_clean | bool | Yes | - | No uncommitted changes |
| has_untracked | bool | Yes | - | Untracked files present |
| ahead_count | int | Yes | 0 | Commits ahead of upstream |
| behind_count | int | Yes | 0 | Commits behind upstream |
| remote_url | str? | No | null | Origin remote URL |
| primary_language | str? | No | null | Dominant programming language |
| last_commit_date | datetime? | No | null | Most recent commit timestamp |

**Validation Rules**:
- `commit_hash` must be exactly 7 characters (or empty if no commits)
- `ahead_count` and `behind_count` must be non-negative
- `remote_url` should be valid git URL format (https:// or git@)

### 6. SourceType (Enum)

Classification of how a project was created/discovered.

| Value | Description |
|-------|-------------|
| `local` | Standard git repository discovered on filesystem |
| `worktree` | Git worktree linked to parent repository |
| `remote` | GitHub repository not cloned locally (listing only) |
| `manual` | Manually created project (legacy, no discovery) |

### 7. ProjectStatus (Enum)

Current availability status of a project.

| Value | Description |
|-------|-------------|
| `active` | Directory exists and is accessible |
| `missing` | Directory no longer exists or inaccessible |

## State Transitions

### Project Lifecycle

```
                     ┌──────────────────┐
                     │   Not Tracked    │
                     └────────┬─────────┘
                              │
                 discovery or │ manual create
                              ▼
                     ┌──────────────────┐
          ┌─────────│     Active       │◄────────┐
          │         └────────┬─────────┘         │
          │                  │                   │
    user  │     directory    │ deleted    directory
  deletes │     removed      │            restored
          │                  ▼                   │
          │         ┌──────────────────┐         │
          │         │     Missing      │─────────┘
          │         └────────┬─────────┘
          │                  │
          │         user     │ deletes
          │                  ▼
          │         ┌──────────────────┐
          └────────►│     Deleted      │
                    └──────────────────┘
```

### Discovery Flow

```
Start Discovery
       │
       ▼
┌──────────────────┐
│  Load ScanConfig │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     for each
│ Scan Directories │────────────────┐
└────────┬─────────┘                │
         │                          ▼
         │              ┌──────────────────────┐
         │              │ Check .git existence │
         │              └──────────┬───────────┘
         │                         │
         │         ┌───────────────┼───────────────┐
         │         │               │               │
         │    .git dir        .git file       no .git
         │    (repo)          (worktree)      (skip)
         │         │               │               │
         │         ▼               ▼               │
         │  ┌────────────┐  ┌────────────┐         │
         │  │ Extract    │  │ Extract    │         │
         │  │ metadata   │  │ metadata + │         │
         │  │            │  │ find parent│         │
         │  └─────┬──────┘  └─────┬──────┘         │
         │        │               │                │
         │        └───────┬───────┘                │
         │                │                        │
         │                ▼                        │
         │     ┌──────────────────┐               │
         │     │ Check existing   │               │
         │     │ project by path  │               │
         │     └────────┬─────────┘               │
         │              │                          │
         │    ┌─────────┴─────────┐               │
         │    │                   │               │
         │  exists            new repo            │
         │    │                   │               │
         │    ▼                   ▼               │
         │ ┌────────────┐  ┌────────────┐         │
         │ │  Update    │  │  Create    │         │
         │ │  metadata  │  │  project   │         │
         │ └─────┬──────┘  └─────┬──────┘         │
         │       │               │                │
         │       └───────┬───────┘                │
         │               │                        │
         │◄──────────────┴────────────────────────┘
         │
         ▼
┌──────────────────┐
│ Check for missing│
│ (existing projs  │
│ not found)       │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Notify daemon to │
│ refresh state    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Return results   │
└──────────────────┘
```

## Backward Compatibility

### Existing Projects

Projects created before Feature 097 will continue to work:
- `source_type` defaults to `"manual"` if not present
- `status` defaults to `"active"` if not present
- `git_metadata` is optional and can be null

### JSON Schema Migration

No migration required. New fields are optional with sensible defaults. Existing project files remain valid.
