# Data Model: Projects Tab CRUD Enhancement

**Feature**: 099-revise-projects-tab
**Date**: 2025-11-28

## Entity Definitions

### RepositoryProject

A git repository that serves as the parent for worktree projects.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Unique identifier (e.g., "nixos") |
| display_name | string | Yes | Human-readable name (e.g., "NixOS Configuration") |
| directory | string | Yes | Absolute path to repository (e.g., "/etc/nixos") |
| icon | string | Yes | Emoji or icon name (default: "📦") |
| source_type | enum | Yes | Always "local" for repository projects |
| status | enum | Yes | "active" or "missing" |
| git_metadata | GitMetadata | No | Git status information |
| worktree_count | integer | Computed | Number of child worktrees |
| has_dirty_worktrees | boolean | Computed | True if any worktree has uncommitted changes |
| is_active | boolean | Computed | True if this is the current project |
| is_expanded | boolean | UI State | Whether worktree list is expanded |

**Validation Rules**:
- `name`: Alphanumeric plus hyphens/underscores, max 50 characters
- `directory`: Must be absolute path, must exist, must be git repository
- `icon`: Single emoji or nerd font icon name

### WorktreeProject

A git worktree created from a parent repository.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Unique identifier (e.g., "099-revise-projects-tab") |
| display_name | string | Yes | Human-readable name |
| directory | string | Yes | Absolute path to worktree |
| icon | string | Yes | Emoji or icon name (default: "🌿") |
| source_type | enum | Yes | Always "worktree" |
| parent_project | string | Yes | Name of parent RepositoryProject |
| branch_metadata | BranchMetadata | Yes | Parsed branch information |
| git_metadata | GitMetadata | No | Git status information |
| status | enum | Yes | "active" or "missing" |
| is_active | boolean | Computed | True if this is the current project |
| is_remote | boolean | Computed | True if remote SSH is enabled |

**Validation Rules**:
- `name`: Must match branch name conventions
- `directory`: Must be absolute path, must exist, must be worktree
- `parent_project`: Must reference existing RepositoryProject

### BranchMetadata

Parsed information from git branch name.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| number | string | No | Extracted number (e.g., "099") |
| type | string | No | Branch type (e.g., "feature", "fix", "hotfix") |
| full_name | string | Yes | Complete branch name |

**Parsing Patterns** (in order of precedence):
1. `<number>-<type>-<description>` → number=098, type=feature
2. `<type>-<number>-<description>` → number=123, type=fix
3. `<number>-<description>` → number=078, type="feature" (default)
4. `<type>-<description>` → number=null, type=hotfix
5. Standard names (main, develop) → number=null, type=null

### GitMetadata

Current git repository/worktree status.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| current_branch | string | Yes | Current branch name |
| commit_hash | string | Yes | Short SHA (7 characters) |
| is_clean | boolean | Yes | True if no uncommitted changes |
| has_untracked | boolean | Yes | True if untracked files exist |
| ahead_count | integer | Yes | Commits ahead of remote |
| behind_count | integer | Yes | Commits behind remote |
| remote_url | string | No | Origin remote URL |

**Computed Fields**:
- `is_dirty`: Inverse of is_clean
- `sync_status`: String representation (e.g., "↑3 ↓2")

### OrphanedWorktree

A worktree whose parent repository is not registered.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Project name |
| directory | string | Yes | Worktree path |
| parent_project | string | Yes | Missing parent reference |
| bare_repo_path | string | No | Path to bare repository (for recovery) |
| status | enum | Yes | "orphaned" |

**Recovery Actions**:
- Discover parent repository and register as RepositoryProject
- Delete orphaned worktree registration

## State Transitions

### Project Lifecycle

```
                    ┌─────────────┐
                    │  Not Found  │
                    └──────┬──────┘
                           │ Create
                           ▼
                    ┌─────────────┐
                    │   Active    │◄────────┐
                    └──────┬──────┘         │
                           │                │
         ┌─────────────────┼─────────────┐  │
         │ Directory       │ Edit        │  │
         │ removed         │             │  │
         ▼                 ▼             │  │
  ┌─────────────┐   ┌─────────────┐      │  │
  │   Missing   │   │   Active    │──────┘  │
  └──────┬──────┘   └─────────────┘         │
         │                                  │
         │ Delete                           │
         ▼                                  │
  ┌─────────────┐                           │
  │  Not Found  │                           │
  └─────────────┘                           │
         │ Restore directory                │
         └──────────────────────────────────┘
```

### Worktree Lifecycle

```
  Repository Project
        │
        │ Create Worktree
        │ (i3pm worktree create)
        ▼
  ┌─────────────┐
  │   Active    │◄────────┐
  │  Worktree   │         │
  └──────┬──────┘         │
         │                │
         │ Edit           │
         │                │
         ▼                │
  ┌─────────────┐         │
  │   Active    │─────────┘
  │  Worktree   │
  └──────┬──────┘
         │
         │ Delete Worktree
         │ (i3pm worktree remove)
         ▼
  ┌─────────────┐
  │  Not Found  │
  └─────────────┘
```

### Orphan States

```
  Worktree Project          Repository Project
        │                         │
        │                         │ Delete
        │                         ▼
        │                   ┌─────────────┐
        └──────────────────►│  Orphaned   │
          Parent not found  │  Worktree   │
                            └──────┬──────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    │ Recover      │ Delete       │
                    ▼              ▼              │
             ┌─────────────┐ ┌─────────────┐     │
             │  Worktree   │ │  Not Found  │◄────┘
             │  (restored) │ └─────────────┘
             └─────────────┘
```

## Relationships

```
                    ┌──────────────────────┐
                    │   RepositoryProject  │
                    │                      │
                    │  - worktree_count    │
                    │  - has_dirty_worktrees│
                    │  - is_expanded       │
                    └──────────┬───────────┘
                               │
                               │ 1:N
                               │ parent_project
                               ▼
                    ┌──────────────────────┐
                    │   WorktreeProject    │
                    │                      │
                    │  - parent_project    │
                    │  - branch_metadata   │
                    └──────────────────────┘
                               │
                               │ (if parent deleted)
                               ▼
                    ┌──────────────────────┐
                    │   OrphanedWorktree   │
                    │                      │
                    │  - bare_repo_path    │
                    └──────────────────────┘
```

## Eww Widget Data Structure

The monitoring panel receives this JSON structure:

```json
{
  "status": "success",
  "main_projects": [
    {
      "name": "nixos",
      "display_name": "NixOS Configuration",
      "directory": "/etc/nixos",
      "icon": "📦",
      "source_type": "local",
      "is_active": true,
      "git_branch": "main",
      "git_is_dirty": false,
      "git_dirty_indicator": "",
      "worktree_count": 5,
      "has_dirty_worktrees": true,
      "is_expanded": true,
      "json_repr": "<pre>...</pre>"
    }
  ],
  "worktrees": [
    {
      "name": "099-revise-projects-tab",
      "display_name": "099 - Revise Projects Tab",
      "directory": "/home/vpittamp/nixos-099-revise-projects-tab",
      "icon": "🌿",
      "source_type": "worktree",
      "parent_project": "nixos",
      "is_active": false,
      "branch_name": "099-revise-projects-tab",
      "git_is_dirty": true,
      "git_dirty_indicator": "●",
      "is_remote": false,
      "worktree_path": "/home/vpittamp/nixos-099-revise-projects-tab"
    }
  ],
  "orphaned_worktrees": [],
  "active_project": "nixos"
}
```

## Form Field Mappings

### Create Worktree Form

| Form Field | Model Field | Validation |
|------------|-------------|------------|
| Branch Name | name, branch_metadata.full_name | Required, alphanumeric+hyphen |
| Worktree Path | directory | Optional (auto-generated), absolute path |
| Display Name | display_name | Optional, max 60 chars |
| Icon | icon | Optional, emoji or icon name |
| Parent Project | parent_project | Auto-set from context |

### Edit Project Form

| Form Field | Model Field | Validation |
|------------|-------------|------------|
| Display Name | display_name | Required, max 60 chars |
| Icon | icon | Required, emoji or icon name |
| Scope | scope | "scoped" or "global" |
| Directory | directory | Read-only |

### Edit Worktree Form

| Form Field | Model Field | Validation |
|------------|-------------|------------|
| Display Name | display_name | Required, max 60 chars |
| Icon | icon | Required, emoji or icon name |
| Branch Name | branch_metadata.full_name | Read-only |
| Worktree Path | directory | Read-only |
| Parent Project | parent_project | Read-only |
