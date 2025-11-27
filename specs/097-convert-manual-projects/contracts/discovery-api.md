# Discovery API Contract

**Feature**: 097-convert-manual-projects
**Protocol**: JSON-RPC 2.0 over Unix Socket
**Socket**: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

## Overview

This document defines the JSON-RPC API extensions for git-based project discovery. These methods extend the existing i3pm daemon IPC interface.

## Methods

### 1. `discover_projects`

Scan configured directories for git repositories and register them as projects.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "discover_projects",
  "params": {
    "paths": ["/home/user/projects", "/etc/nixos"],
    "include_github": false,
    "dry_run": false
  }
}
```

**Parameters**:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| paths | string[] | No | From config | Override scan paths |
| include_github | bool | No | false | Also query GitHub repos |
| dry_run | bool | No | false | Report what would be discovered without creating projects |

**Response (Success)**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "success": true,
    "discovered_repos": [
      {
        "path": "/home/user/projects/my-app",
        "name": "my-app",
        "is_worktree": false,
        "git_metadata": {
          "current_branch": "main",
          "commit_hash": "a1b2c3d",
          "is_clean": true,
          "has_untracked": false,
          "ahead_count": 0,
          "behind_count": 0,
          "remote_url": "https://github.com/user/my-app.git",
          "primary_language": "TypeScript"
        },
        "inferred_icon": "📘"
      }
    ],
    "discovered_worktrees": [
      {
        "path": "/home/user/nixos-097-feature",
        "name": "097-convert-manual-projects",
        "parent_repo_path": "/etc/nixos",
        "git_metadata": {
          "current_branch": "097-convert-manual-projects",
          "commit_hash": "1637a7b",
          "is_clean": true,
          "has_untracked": false,
          "ahead_count": 0,
          "behind_count": 0
        },
        "inferred_icon": "🌿"
      }
    ],
    "projects_created": 5,
    "projects_updated": 2,
    "projects_marked_missing": 1,
    "skipped_paths": [
      {
        "path": "/home/user/projects/not-a-repo",
        "reason": "no_git_directory"
      }
    ],
    "duration_ms": 1250,
    "errors": []
  }
}
```

**Response (Partial Success with Errors)**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "success": true,
    "discovered_repos": [...],
    "errors": [
      {
        "path": "/home/user/projects/corrupted-repo",
        "error": "git_metadata_extraction_failed",
        "message": "Failed to read HEAD: not a valid git repository"
      },
      {
        "source": "github",
        "error": "github_auth_required",
        "message": "gh CLI not authenticated. Run 'gh auth login' to enable GitHub discovery."
      }
    ]
  }
}
```

**Error Codes**:

| Code | Message | Description |
|------|---------|-------------|
| -32001 | `scan_paths_not_configured` | No scan paths in config and none provided |
| -32002 | `path_not_found` | Specified scan path does not exist |
| -32003 | `permission_denied` | Cannot read scan path |
| -32004 | `discovery_timeout` | Discovery exceeded 60 second timeout |

---

### 2. `get_discovery_config`

Retrieve the current discovery configuration.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "get_discovery_config",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "scan_paths": [
      "/home/user/projects",
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
}
```

---

### 3. `update_discovery_config`

Update discovery configuration settings.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "update_discovery_config",
  "params": {
    "scan_paths": ["/home/user/projects", "/etc/nixos", "~/work"],
    "auto_discover_on_startup": true
  }
}
```

**Parameters** (all optional, only provided fields are updated):

| Parameter | Type | Description |
|-----------|------|-------------|
| scan_paths | string[] | Directories to scan |
| exclude_patterns | string[] | Directory names to skip |
| auto_discover_on_startup | bool | Enable startup discovery |
| max_depth | int | Max recursion depth (1-10) |

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "success": true,
    "config": {
      "scan_paths": ["/home/user/projects", "/etc/nixos", "/home/user/work"],
      "exclude_patterns": ["node_modules", "vendor", ".cache"],
      "auto_discover_on_startup": true,
      "max_depth": 3
    }
  }
}
```

**Error Codes**:

| Code | Message | Description |
|------|---------|-------------|
| -32011 | `invalid_scan_path` | Path is not absolute or doesn't exist |
| -32012 | `invalid_max_depth` | max_depth not in range 1-10 |

---

### 4. `refresh_git_metadata`

Refresh git metadata for a specific project or all projects.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "refresh_git_metadata",
  "params": {
    "project_name": "my-app"
  }
}
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| project_name | string | No | Specific project to refresh (all if omitted) |

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "success": true,
    "refreshed_count": 1,
    "projects": [
      {
        "name": "my-app",
        "git_metadata": {
          "current_branch": "feature-x",
          "commit_hash": "b2c3d4e",
          "is_clean": false,
          "has_untracked": true,
          "ahead_count": 2,
          "behind_count": 0
        }
      }
    ]
  }
}
```

---

### 5. `list_github_repos`

List authenticated user's GitHub repositories (without creating projects).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "list_github_repos",
  "params": {
    "limit": 50,
    "include_archived": false,
    "include_forks": false
  }
}
```

**Parameters**:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| limit | int | No | 100 | Maximum repos to return |
| include_archived | bool | No | false | Include archived repos |
| include_forks | bool | No | false | Include forked repos |

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "success": true,
    "repos": [
      {
        "name": "my-app",
        "full_name": "user/my-app",
        "description": "My awesome application",
        "primary_language": "TypeScript",
        "pushed_at": "2025-11-25T10:30:00Z",
        "visibility": "public",
        "is_fork": false,
        "is_archived": false,
        "clone_url": "https://github.com/user/my-app.git",
        "has_local_clone": true,
        "local_project_name": "my-app"
      }
    ],
    "total_count": 45
  }
}
```

**Error Codes**:

| Code | Message | Description |
|------|---------|-------------|
| -32021 | `github_not_authenticated` | gh CLI not logged in |
| -32022 | `github_api_error` | GitHub API returned error |
| -32023 | `github_timeout` | GitHub API request timed out |

---

## Events

The daemon emits events when discovery changes project state.

### `projects_discovered`

Emitted after successful discovery operation.

```json
{
  "event": "projects_discovered",
  "data": {
    "created": ["my-app", "other-repo"],
    "updated": ["nixos"],
    "marked_missing": ["old-project"],
    "timestamp": "2025-11-26T15:30:00Z"
  }
}
```

### `project_status_changed`

Emitted when a project's status changes (active ↔ missing).

```json
{
  "event": "project_status_changed",
  "data": {
    "project_name": "my-app",
    "old_status": "active",
    "new_status": "missing",
    "timestamp": "2025-11-26T15:30:00Z"
  }
}
```

---

## CLI Commands

The CLI wraps these RPC methods with user-friendly interfaces.

### `i3pm project discover`

```bash
# Discover using configured paths
i3pm project discover

# Discover specific paths (override config)
i3pm project discover --path ~/projects --path /etc/nixos

# Include GitHub repositories
i3pm project discover --github

# Dry run (show what would be discovered)
i3pm project discover --dry-run

# Combined
i3pm project discover --path ~/work --github --dry-run
```

### `i3pm project refresh`

```bash
# Refresh git metadata for all projects
i3pm project refresh

# Refresh specific project
i3pm project refresh my-app
```

### `i3pm config discovery`

```bash
# Show current discovery config
i3pm config discovery show

# Add scan path
i3pm config discovery add-path ~/work

# Remove scan path
i3pm config discovery remove-path ~/old-projects

# Enable auto-discovery on startup
i3pm config discovery set --auto-discover=true
```

---

## TypeScript Types

```typescript
// Zod schemas for CLI validation

import { z } from "zod";

export const GitMetadataSchema = z.object({
  current_branch: z.string(),
  commit_hash: z.string().length(7),
  is_clean: z.boolean(),
  has_untracked: z.boolean(),
  ahead_count: z.number().int().nonnegative(),
  behind_count: z.number().int().nonnegative(),
  remote_url: z.string().nullable(),
  primary_language: z.string().nullable(),
  last_commit_date: z.string().datetime().nullable(),
});

export const SourceTypeSchema = z.enum(["local", "worktree", "remote", "manual"]);

export const ProjectStatusSchema = z.enum(["active", "missing"]);

export const DiscoveryConfigSchema = z.object({
  scan_paths: z.array(z.string()).min(1),
  exclude_patterns: z.array(z.string()).default([]),
  auto_discover_on_startup: z.boolean().default(false),
  max_depth: z.number().int().min(1).max(10).default(3),
});

export const DiscoveryResultSchema = z.object({
  success: z.boolean(),
  discovered_repos: z.array(z.object({
    path: z.string(),
    name: z.string(),
    is_worktree: z.boolean(),
    git_metadata: GitMetadataSchema,
    inferred_icon: z.string(),
  })),
  discovered_worktrees: z.array(z.object({
    path: z.string(),
    name: z.string(),
    parent_repo_path: z.string(),
    git_metadata: GitMetadataSchema,
    inferred_icon: z.string(),
  })),
  projects_created: z.number().int(),
  projects_updated: z.number().int(),
  projects_marked_missing: z.number().int(),
  duration_ms: z.number().int(),
  errors: z.array(z.object({
    path: z.string().optional(),
    source: z.string().optional(),
    error: z.string(),
    message: z.string(),
  })),
});

export type GitMetadata = z.infer<typeof GitMetadataSchema>;
export type SourceType = z.infer<typeof SourceTypeSchema>;
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;
export type DiscoveryConfig = z.infer<typeof DiscoveryConfigSchema>;
export type DiscoveryResult = z.infer<typeof DiscoveryResultSchema>;
```

---

## Python Types

```python
# Pydantic models for daemon implementation

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional
from pydantic import BaseModel, Field, field_validator

class SourceType(str, Enum):
    LOCAL = "local"
    WORKTREE = "worktree"
    REMOTE = "remote"
    MANUAL = "manual"

class ProjectStatus(str, Enum):
    ACTIVE = "active"
    MISSING = "missing"

class GitMetadata(BaseModel):
    current_branch: str
    commit_hash: str = Field(min_length=7, max_length=7)
    is_clean: bool
    has_untracked: bool
    ahead_count: int = Field(ge=0, default=0)
    behind_count: int = Field(ge=0, default=0)
    remote_url: Optional[str] = None
    primary_language: Optional[str] = None
    last_commit_date: Optional[datetime] = None

class DiscoveryConfig(BaseModel):
    scan_paths: list[str] = Field(min_length=1)
    exclude_patterns: list[str] = Field(default_factory=lambda: ["node_modules", "vendor", ".cache"])
    auto_discover_on_startup: bool = False
    max_depth: int = Field(ge=1, le=10, default=3)

    @field_validator("scan_paths", mode="before")
    @classmethod
    def expand_paths(cls, v: list[str]) -> list[str]:
        return [str(Path(p).expanduser().resolve()) for p in v]

class DiscoveredRepository(BaseModel):
    path: str
    name: str
    is_worktree: bool
    git_metadata: GitMetadata
    parent_repo_path: Optional[str] = None
    inferred_icon: str

class DiscoveryError(BaseModel):
    path: Optional[str] = None
    source: Optional[str] = None
    error: str
    message: str

class DiscoveryResult(BaseModel):
    success: bool = True
    discovered_repos: list[DiscoveredRepository] = Field(default_factory=list)
    discovered_worktrees: list[DiscoveredRepository] = Field(default_factory=list)
    projects_created: int = 0
    projects_updated: int = 0
    projects_marked_missing: int = 0
    skipped_paths: list[dict] = Field(default_factory=list)
    duration_ms: int = 0
    errors: list[DiscoveryError] = Field(default_factory=list)
```
