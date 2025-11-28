# Discovery API Contract

**Feature**: 097-convert-manual-projects
**Protocol**: CLI Commands + JSON-RPC 2.0 over Unix Socket
**Date**: 2025-11-28 (Major revision for git-centric architecture)

## Overview

This document defines the CLI commands and JSON-RPC API for git-centric project management. The key change from the previous design is the use of `bare_repo_path` as the canonical identifier for project relationships.

## Architecture: Git as Source of Truth

```
bare_repo_path (GIT_COMMON_DIR) is the CANONICAL identifier
├── Computed via: git rev-parse --git-common-dir
├── Never user-specified
└── Used to:
    ├── Group worktrees under Repository Projects
    ├── Detect orphaned worktrees
    └── Enforce "one Repository Project per bare repo" constraint
```

## CLI Commands

Primary user interface for git-centric project management.

### `i3pm project discover`

Discover and register a git repository as a project.

```bash
# Discover from current directory
i3pm project discover

# Discover specific path
i3pm project discover --path /etc/nixos

# Discover with custom display name
i3pm project discover --path ~/projects/my-app --name "My App" --icon "🚀"
```

**Behavior**:
1. Compute `bare_repo_path` via `git rev-parse --git-common-dir`
2. If `bare_repo_path` already has a Repository Project → create Worktree Project
3. If no Repository Project exists → create Repository Project
4. If not a git repo → create Standalone Project (optional, with `--standalone` flag)

**Output**:
```
✓ Discovered repository at /etc/nixos
  bare_repo_path: /home/user/nixos-config.git
  source_type: repository
  Project "nixos" created successfully
```

---

### `i3pm project refresh`

Refresh git metadata for projects.

```bash
# Refresh all projects
i3pm project refresh --all

# Refresh specific project
i3pm project refresh nixos
```

**Output**:
```
✓ Refreshed 5 projects
  nixos: main (clean, ahead 0, behind 0)
  097-feature: 097-convert-manual-projects (dirty, 3 uncommitted)
  ...
```

---

### `i3pm worktree create`

Create a new git worktree and register as a Worktree Project. (Already exists, update behavior)

```bash
# Create new branch and worktree
i3pm worktree create 098-new-feature

# Checkout existing branch
i3pm worktree create hotfix-payment --checkout

# Custom directory name
i3pm worktree create feature-ui --name ui-work
```

**Behavior** (Updated for 097):
1. Execute `git worktree add`
2. Compute `bare_repo_path` for the worktree
3. Find Repository Project with matching `bare_repo_path`
4. Create Worktree Project with `parent_project` set to Repository Project's name

---

### `i3pm worktree remove`

Delete a git worktree and its project registration. (Already exists)

```bash
# Remove worktree
i3pm worktree remove 097-feature

# Force remove (has uncommitted changes)
i3pm worktree remove 097-feature --force
```

---

### `i3pm project list`

List projects with hierarchy display.

```bash
# List all projects
i3pm project list

# List with hierarchy (new default)
i3pm project list --hierarchy

# JSON output for scripting
i3pm project list --json
```

**Output** (hierarchy):
```
Repository Projects:
▼ 🔧 nixos (5 worktrees)
    ├─ 🌿 097-feature ● (dirty)
    ├─ 🌿 087-ssh-keys
    └─ 🌿 085-widget

Standalone Projects:
  📁 notes

Orphaned Worktrees:
  ⚠️ 042-old-feature (parent missing)
```

---

## JSON-RPC Methods

Internal daemon API for panel and advanced tooling.

### `get_projects_hierarchy`

Get projects grouped by bare_repo_path for panel display.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "get_projects_hierarchy",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "repository_projects": [
      {
        "project": {
          "name": "nixos",
          "display_name": "NixOS Config",
          "directory": "/etc/nixos",
          "source_type": "repository",
          "bare_repo_path": "/home/user/nixos-config.git",
          "git_metadata": { "current_branch": "main", "is_clean": true, ... }
        },
        "worktree_count": 5,
        "has_dirty": true,
        "is_expanded": true,
        "worktrees": [
          {
            "name": "097-feature",
            "display_name": "097 - Git-Centric Projects",
            "directory": "/home/user/nixos-097-feature",
            "source_type": "worktree",
            "bare_repo_path": "/home/user/nixos-config.git",
            "parent_project": "nixos",
            "git_metadata": { "current_branch": "097-convert-manual-projects", "is_clean": false, ... }
          }
        ]
      }
    ],
    "standalone_projects": [
      {
        "name": "notes",
        "source_type": "standalone",
        "bare_repo_path": null
      }
    ],
    "orphaned_worktrees": [
      {
        "name": "042-old-feature",
        "source_type": "worktree",
        "bare_repo_path": "/home/user/deleted-repo.git",
        "parent_project": "deleted-project",
        "status": "orphaned"
      }
    ],
    "active_project": "097-feature"
  }
}
```

---

### `refresh_git_metadata`

Refresh git metadata for a specific project or all projects.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "refresh_git_metadata",
  "params": {
    "project_name": "nixos"
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "success": true,
    "refreshed_count": 1,
    "projects": [
      {
        "name": "nixos",
        "git_metadata": {
          "current_branch": "main",
          "commit_hash": "abc1234",
          "is_clean": true,
          "has_untracked": false,
          "ahead_count": 0,
          "behind_count": 0,
          "last_refreshed": "2025-11-28T12:00:00Z"
        }
      }
    ]
  }
}
```

---

### `recover_orphan`

Create a Repository Project for an orphaned worktree's bare_repo_path.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "recover_orphan",
  "params": {
    "worktree_name": "042-old-feature"
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "success": true,
    "new_repository_project": "recovered-repo",
    "reparented_worktrees": ["042-old-feature"]
  }
}
```

---

## Events

### `projects_changed`

Emitted when project hierarchy changes.

```json
{
  "event": "projects_changed",
  "data": {
    "repository_projects": [...],
    "standalone_projects": [...],
    "orphaned_worktrees": [...],
    "active_project": "097-feature",
    "timestamp": "2025-11-28T12:00:00Z"
  }
}
```

### `worktree_created`

Emitted when a new worktree is created.

```json
{
  "event": "worktree_created",
  "data": {
    "name": "098-new-feature",
    "parent_project": "nixos",
    "bare_repo_path": "/home/user/nixos-config.git",
    "branch": "098-new-feature",
    "timestamp": "2025-11-28T12:00:00Z"
  }
}
```

### `worktree_deleted`

Emitted when a worktree is deleted.

```json
{
  "event": "worktree_deleted",
  "data": {
    "name": "097-feature",
    "parent_project": "nixos",
    "timestamp": "2025-11-28T12:00:00Z"
  }
}
```

---

## TypeScript Types

```typescript
// Zod schemas for CLI validation (Feature 097 - git-centric architecture)

import { z } from "zod";

// Enums
export const SourceTypeSchema = z.enum(["repository", "worktree", "standalone"]);
export const ProjectStatusSchema = z.enum(["active", "missing", "orphaned"]);

// Git Metadata
export const GitMetadataSchema = z.object({
  current_branch: z.string(),
  commit_hash: z.string().length(7),
  is_clean: z.boolean(),
  has_untracked: z.boolean(),
  ahead_count: z.number().int().nonnegative(),
  behind_count: z.number().int().nonnegative(),
  remote_url: z.string().nullable(),
  last_modified: z.string().datetime().nullable(),
  last_refreshed: z.string().datetime().nullable(),
});

// Unified Project Model
export const ProjectSchema = z.object({
  name: z.string(),
  display_name: z.string(),
  directory: z.string(),
  icon: z.string(),
  source_type: SourceTypeSchema,
  status: ProjectStatusSchema.default("active"),
  bare_repo_path: z.string().nullable(),
  parent_project: z.string().nullable(),
  git_metadata: GitMetadataSchema.nullable(),
  scoped_classes: z.array(z.string()),
  remote: z.object({
    enabled: z.boolean(),
    host: z.string(),
    user: z.string(),
    working_dir: z.string(),
    port: z.number().int().min(1).max(65535).default(22),
  }).nullable().optional(),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
});

// Panel Display Models
export const RepositoryWithWorktreesSchema = z.object({
  project: ProjectSchema,
  worktree_count: z.number().int(),
  has_dirty: z.boolean(),
  is_expanded: z.boolean(),
  worktrees: z.array(ProjectSchema),
});

export const PanelProjectsDataSchema = z.object({
  repository_projects: z.array(RepositoryWithWorktreesSchema),
  standalone_projects: z.array(ProjectSchema),
  orphaned_worktrees: z.array(ProjectSchema),
  active_project: z.string().nullable(),
});

// Discovery
export const ScanConfigurationSchema = z.object({
  scan_paths: z.array(z.string()).min(1),
  exclude_patterns: z.array(z.string()).default([]),
  max_depth: z.number().int().min(1).max(10).default(3),
});

// Types
export type SourceType = z.infer<typeof SourceTypeSchema>;
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;
export type GitMetadata = z.infer<typeof GitMetadataSchema>;
export type Project = z.infer<typeof ProjectSchema>;
export type RepositoryWithWorktrees = z.infer<typeof RepositoryWithWorktreesSchema>;
export type PanelProjectsData = z.infer<typeof PanelProjectsDataSchema>;
export type ScanConfiguration = z.infer<typeof ScanConfigurationSchema>;
```

---

## Python Types

```python
# Pydantic models for daemon implementation (Feature 097 - git-centric architecture)

from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field, field_validator

class SourceType(str, Enum):
    REPOSITORY = "repository"
    WORKTREE = "worktree"
    STANDALONE = "standalone"

class ProjectStatus(str, Enum):
    ACTIVE = "active"
    MISSING = "missing"
    ORPHANED = "orphaned"

class GitMetadata(BaseModel):
    current_branch: str
    commit_hash: str = Field(min_length=7, max_length=7)
    is_clean: bool
    has_untracked: bool
    ahead_count: int = Field(ge=0, default=0)
    behind_count: int = Field(ge=0, default=0)
    remote_url: Optional[str] = None
    last_modified: Optional[datetime] = None
    last_refreshed: Optional[datetime] = None

class Project(BaseModel):
    """Unified Project Model - Feature 097"""
    name: str
    display_name: str
    directory: str
    icon: str = "📁"
    source_type: SourceType
    status: ProjectStatus = ProjectStatus.ACTIVE
    bare_repo_path: Optional[str] = None
    parent_project: Optional[str] = None
    git_metadata: Optional[GitMetadata] = None
    scoped_classes: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)

    @field_validator("parent_project")
    @classmethod
    def validate_parent_for_worktree(cls, v, info):
        source_type = info.data.get("source_type")
        if source_type == SourceType.WORKTREE and v is None:
            raise ValueError("Worktree projects must have parent_project set")
        return v

class RepositoryWithWorktrees(BaseModel):
    """Panel display model for repository with children"""
    project: Project
    worktree_count: int
    has_dirty: bool
    is_expanded: bool = True
    worktrees: list[Project] = Field(default_factory=list)

class PanelProjectsData(BaseModel):
    """Complete data structure for monitoring panel"""
    repository_projects: list[RepositoryWithWorktrees] = Field(default_factory=list)
    standalone_projects: list[Project] = Field(default_factory=list)
    orphaned_worktrees: list[Project] = Field(default_factory=list)
    active_project: Optional[str] = None

class ScanConfiguration(BaseModel):
    scan_paths: list[str] = Field(min_length=1)
    exclude_patterns: list[str] = Field(default_factory=lambda: ["node_modules", "vendor", ".cache"])
    max_depth: int = Field(ge=1, le=10, default=3)
```
