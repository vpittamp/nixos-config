# Data Model: Git-Centric Project and Worktree Management

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-28 (Major revision for git-centric architecture)

## Architecture: Git as Source of Truth

The core principle is that `bare_repo_path` (GIT_COMMON_DIR) is the canonical identifier for all project relationships. This eliminates orphaned worktree problems and state synchronization issues.

## Entity Relationship Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Unified Project Model                        │
│      (Persisted in ~/.config/i3/projects/<name>.json)           │
├─────────────────────────────────────────────────────────────────┤
│  name: str                     # Unique i3pm identifier         │
│  display_name: str             # Human-readable name            │
│  directory: Path               # Working directory path         │
│  icon: str                     # Emoji icon                     │
│                                                                 │
│  source_type: SourceType       # repository|worktree|standalone │
│  status: ProjectStatus         # active|missing|orphaned        │
│                                                                 │
│  bare_repo_path: str?          # GIT_COMMON_DIR (canonical ID)  │
│  parent_project: str?          # For worktrees: parent name     │
│                                                                 │
│  git_metadata: GitMetadata?    # Cached git state               │
│  scoped_classes: List[str]     # App window classes             │
│  remote: RemoteConfig?         # SSH config (Feature 087)       │
│                                                                 │
│  created_at: datetime                                           │
│  updated_at: datetime                                           │
└─────────────────────────────────────────────────────────────────┘
         │
         │ grouped by bare_repo_path
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Panel Display Model                          │
│      (Runtime structure for Eww monitoring panel)               │
├─────────────────────────────────────────────────────────────────┤
│  repository_projects: [                                         │
│    {                                                            │
│      project: Project,          # source_type="repository"      │
│      worktree_count: int,       # Count of child worktrees      │
│      has_dirty: bool,           # Any child is dirty            │
│      is_expanded: bool,         # UI expansion state            │
│      worktrees: [Project...]    # source_type="worktree"        │
│    }                                                            │
│  ]                                                              │
│  standalone_projects: [Project...]  # source_type="standalone"  │
│  orphaned_worktrees: [Project...]   # status="orphaned"         │
└─────────────────────────────────────────────────────────────────┘
```

## Relationship Model

```
Bare Repo: /home/user/nixos-config.git
    │
    ├── Repository Project: "nixos" → /etc/nixos (main branch)
    │       │
    │       ├── Worktree Project: "097-feature" → /home/user/nixos-097-feature
    │       ├── Worktree Project: "087-ssh" → /home/user/nixos-087-ssh
    │       └── Worktree Project: "085-widget" → /home/user/nixos-085-widget
    │
Bare Repo: /home/user/other-repo/.git
    │
    └── Standalone Project: "other-repo" → /home/user/other-repo
```

## Entities

### 1. Project (Unified Model)

The core entity representing any project - repository, worktree, or standalone.

**Storage**: `~/.config/i3/projects/<name>.json`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | str | Yes | - | Unique i3pm identifier (e.g., "nixos", "097-feature") |
| display_name | str | Yes | - | Human-readable name |
| directory | Path | Yes | - | Absolute path to working directory |
| icon | str | Yes | "📁" | Emoji icon |
| source_type | SourceType | Yes | - | `repository` \| `worktree` \| `standalone` |
| status | ProjectStatus | Yes | `"active"` | `active` \| `missing` \| `orphaned` |
| bare_repo_path | str? | No | null | GIT_COMMON_DIR - canonical repo identifier |
| parent_project | str? | No | null | For worktrees: parent project name |
| git_metadata | GitMetadata? | No | null | Cached git state |
| scoped_classes | List[str] | Yes | `[]` | App window classes for scoping |
| remote | RemoteConfig? | No | null | SSH config (Feature 087) |
| created_at | datetime | Yes | now | Creation timestamp |
| updated_at | datetime | Yes | now | Last modification timestamp |

**Invariants**:
- Only ONE project with `source_type: "repository"` per unique `bare_repo_path`
- Projects with `source_type: "worktree"` MUST have non-null `parent_project`
- `bare_repo_path` is always computed from git, never user-specified

**Validation Rules**:
- `name` must be unique across all projects
- `directory` must be an absolute path
- If `source_type == "worktree"`, `parent_project` must reference an existing project
- `bare_repo_path` must match parent's `bare_repo_path` for worktrees

### 2. GitMetadata

Cached git state attached to projects.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| current_branch | str | Yes | - | Branch name or "HEAD" if detached |
| commit_hash | str | Yes | - | Short SHA (7 characters) |
| is_clean | bool | Yes | - | No uncommitted changes |
| has_untracked | bool | Yes | - | Untracked files present |
| ahead_count | int | Yes | 0 | Commits ahead of upstream |
| behind_count | int | Yes | 0 | Commits behind upstream |
| remote_url | str? | No | null | Origin remote URL |
| last_modified | datetime? | No | null | Most recent file modification |
| last_refreshed | datetime? | No | null | When metadata was last updated |

**Validation Rules**:
- `commit_hash` must be exactly 7 characters (or empty if no commits)
- `ahead_count` and `behind_count` must be non-negative

### 3. SourceType (Enum)

Classification of project type.

| Value | Description | bare_repo_path | parent_project |
|-------|-------------|----------------|----------------|
| `repository` | Primary entry point for a bare repo (only ONE per bare repo) | Required | null |
| `worktree` | Git worktree linked to a Repository Project | Required (matches parent) | Required |
| `standalone` | Non-git directory OR simple repo with no worktrees | Optional | null |

### 4. ProjectStatus (Enum)

Current availability status.

| Value | Description |
|-------|-------------|
| `active` | Directory exists and is accessible |
| `missing` | Directory no longer exists or inaccessible |
| `orphaned` | Worktree with no matching Repository Project |

### 5. ScanConfiguration

User-defined settings for repository discovery.

**Storage**: `~/.config/i3/discovery-config.json`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| scan_paths | List[str] | Yes | `["~/projects"]` | Directories to scan |
| exclude_patterns | List[str] | No | `["node_modules", "vendor", ".cache"]` | Patterns to skip |
| max_depth | int | No | `3` | Maximum recursion depth |

### 6. DiscoveryResult

Ephemeral result from discovery operation.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| repository_projects | List[Project] | Yes | New repository projects created |
| worktree_projects | List[Project] | Yes | New worktree projects created |
| orphaned_worktrees | List[Project] | Yes | Worktrees with missing parents |
| projects_updated | int | Yes | Count of updated existing projects |
| duration_ms | int | Yes | Time taken |
| errors | List[str] | Yes | Non-fatal errors |

### 7. RepositoryWithWorktrees (Panel Display)

Runtime structure for Eww monitoring panel hierarchy.

| Field | Type | Description |
|-------|------|-------------|
| project | Project | The repository project (source_type="repository") |
| worktree_count | int | Count of child worktrees |
| has_dirty | bool | True if any child has uncommitted changes |
| is_expanded | bool | UI expansion state |
| worktrees | List[Project] | Child worktree projects |

### 8. PanelProjectsData

Complete data structure for monitoring panel.

| Field | Type | Description |
|-------|------|-------------|
| repository_projects | List[RepositoryWithWorktrees] | Grouped repository projects |
| standalone_projects | List[Project] | Standalone projects |
| orphaned_worktrees | List[Project] | Orphaned worktrees |
| active_project | str? | Currently active project name |

## State Transitions

### Project Lifecycle

```
                     ┌──────────────────┐
                     │   Not Tracked    │
                     └────────┬─────────┘
                              │
                 discovery or │ i3pm worktree create
                              ▼
                     ┌──────────────────┐
          ┌─────────│     Active       │◄────────┐
          │         └────────┬─────────┘         │
          │                  │                   │
    user  │     directory    │ removed    directory
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

                     For Worktrees Only:
                     ┌──────────────────┐
                     │     Active       │
                     └────────┬─────────┘
                              │
               parent project │ deleted
                              ▼
                     ┌──────────────────┐
                     │    Orphaned      │◄────── no matching bare_repo_path
                     └────────┬─────────┘
                              │
                     [Recover]│ or [Delete]
                              ▼
              ┌───────────────┴───────────────┐
              ▼                               ▼
   ┌──────────────────┐            ┌──────────────────┐
   │ Re-parented      │            │     Deleted      │
   │ (new repo proj)  │            └──────────────────┘
   └──────────────────┘
```

### Discovery Flow

```
Start Discovery (i3pm project discover --path <dir>)
       │
       ▼
┌──────────────────────┐
│ Get bare_repo_path   │  ← git rev-parse --git-common-dir
└──────────┬───────────┘
           │
           ├────────────────────────────────────────┐
           │                                        │
       not a git repo                          is a git repo
           │                                        │
           ▼                                        ▼
┌──────────────────┐                    ┌──────────────────┐
│ Create standalone│                    │ Check existing   │
│ project          │                    │ repo project for │
└──────────────────┘                    │ this bare_repo   │
                                        └────────┬─────────┘
                                                 │
                              ┌──────────────────┼──────────────────┐
                              │                  │                  │
                         no repo proj       has repo proj     same directory
                              │                  │                  │
                              ▼                  ▼                  ▼
                    ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
                    │ Create         │  │ Create worktree│  │ Update existing│
                    │ repository     │  │ project linked │  │ project        │
                    │ project        │  │ to parent      │  │                │
                    └────────────────┘  └────────────────┘  └────────────────┘
```

### Orphan Detection Flow

```
On Project List Load (monitoring_data.py)
       │
       ▼
┌──────────────────────┐
│ Load all projects    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Group by bare_repo   │
│ - Find all "repository" projects
│ - Get their bare_repo_paths
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ For each "worktree"  │
│ project:             │
│ - Check if its       │
│   bare_repo_path     │
│   matches any repo   │
│   project            │
└──────────┬───────────┘
           │
           ├──────────────────────────────┐
           │                              │
       match found                   no match
           │                              │
           ▼                              ▼
┌──────────────────┐            ┌──────────────────┐
│ Link to parent   │            │ Mark as orphaned │
│ (status: active) │            │ (status: orphaned)
└──────────────────┘            └──────────────────┘
```

## JSON Schema Examples

### Repository Project (source_type: "repository")

```json
{
  "name": "nixos",
  "display_name": "NixOS Config",
  "directory": "/etc/nixos",
  "icon": "🔧",
  "source_type": "repository",
  "status": "active",
  "bare_repo_path": "/home/user/nixos-config.git",
  "parent_project": null,
  "git_metadata": {
    "current_branch": "main",
    "commit_hash": "abc1234",
    "is_clean": true,
    "has_untracked": false,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "https://github.com/user/nixos-config.git",
    "last_refreshed": "2025-11-28T12:00:00Z"
  },
  "scoped_classes": ["Ghostty", "code", "yazi", "lazygit"],
  "created_at": "2025-11-28T10:00:00Z",
  "updated_at": "2025-11-28T12:00:00Z"
}
```

### Worktree Project (source_type: "worktree")

```json
{
  "name": "097-feature",
  "display_name": "097 - Git-Centric Projects",
  "directory": "/home/user/nixos-097-feature",
  "icon": "🌿",
  "source_type": "worktree",
  "status": "active",
  "bare_repo_path": "/home/user/nixos-config.git",
  "parent_project": "nixos",
  "git_metadata": {
    "current_branch": "097-convert-manual-projects",
    "commit_hash": "def5678",
    "is_clean": false,
    "has_untracked": true,
    "ahead_count": 5,
    "behind_count": 0,
    "remote_url": "https://github.com/user/nixos-config.git",
    "last_refreshed": "2025-11-28T12:00:00Z"
  },
  "scoped_classes": ["Ghostty", "code", "yazi", "lazygit"],
  "created_at": "2025-11-28T10:30:00Z",
  "updated_at": "2025-11-28T12:00:00Z"
}
```

### Standalone Project (source_type: "standalone")

```json
{
  "name": "notes",
  "display_name": "Notes",
  "directory": "/home/user/notes",
  "icon": "📝",
  "source_type": "standalone",
  "status": "active",
  "bare_repo_path": null,
  "parent_project": null,
  "git_metadata": null,
  "scoped_classes": ["code"],
  "created_at": "2025-11-28T09:00:00Z",
  "updated_at": "2025-11-28T09:00:00Z"
}
```

## No Backwards Compatibility

Per Constitution Principle XII (Forward-Only Development):
- Old project format is NOT supported
- Existing projects will be recreated via discovery
- No migration scripts or compatibility shims
- `source_type` field is REQUIRED (not optional with default)
