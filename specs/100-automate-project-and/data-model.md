# Data Model: Structured Git Repository Management

**Feature**: 100-automate-project-and
**Date**: 2025-11-29

## Entity Overview

```
AccountConfig ──1:N──► BareRepository ──1:N──► Worktree
                              │
                              ▼
                     DiscoveredProject (unified view)
```

---

## AccountConfig

Configured GitHub account or organization with base directory path.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ✅ | GitHub account/org name (e.g., "vpittamp") |
| `path` | string | ✅ | Base directory path (e.g., "~/repos/vpittamp") |
| `is_default` | boolean | ❌ | Default account for clone without explicit account |
| `ssh_host` | string | ❌ | SSH host alias (default: "github.com") |

### Validation Rules

- `name`: Non-empty, valid GitHub username pattern `[a-zA-Z0-9-]+`
- `path`: Must be absolute path or start with `~`
- One account may be marked as default

### Example

```json
{
  "name": "vpittamp",
  "path": "~/repos/vpittamp",
  "is_default": true,
  "ssh_host": "github.com"
}
```

### Pydantic Model

```python
from pydantic import BaseModel, Field, field_validator
from pathlib import Path
import re

class AccountConfig(BaseModel):
    name: str = Field(..., min_length=1, max_length=39)
    path: str
    is_default: bool = False
    ssh_host: str = "github.com"

    @field_validator('name')
    @classmethod
    def validate_name(cls, v: str) -> str:
        if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9-]*$', v):
            raise ValueError('Invalid GitHub username format')
        return v

    @field_validator('path')
    @classmethod
    def validate_path(cls, v: str) -> str:
        expanded = Path(v).expanduser()
        if not expanded.is_absolute():
            raise ValueError('Path must be absolute')
        return str(expanded)
```

### Zod Schema (TypeScript)

```typescript
import { z } from "zod";

export const AccountConfigSchema = z.object({
  name: z.string().min(1).max(39).regex(/^[a-zA-Z0-9][a-zA-Z0-9-]*$/),
  path: z.string().min(1),
  is_default: z.boolean().default(false),
  ssh_host: z.string().default("github.com"),
});

export type AccountConfig = z.infer<typeof AccountConfigSchema>;
```

---

## BareRepository

Repository stored as bare clone with `.bare/` structure.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `account` | string | ✅ | Owning GitHub account name |
| `name` | string | ✅ | Repository name |
| `path` | string | ✅ | Full path to repo container directory |
| `remote_url` | string | ✅ | Git remote origin URL |
| `default_branch` | string | ✅ | Default branch name (main/master) |
| `worktrees` | list[Worktree] | ✅ | Associated worktrees |
| `discovered_at` | datetime | ✅ | When repository was discovered |
| `last_scanned` | datetime | ❌ | Last metadata refresh |

### Computed Properties

- `qualified_name`: `{account}/{name}` (e.g., "vpittamp/nixos")
- `bare_path`: `{path}/.bare`
- `git_pointer_path`: `{path}/.git`

### Validation Rules

- `path` must contain `.bare/` directory
- `path` must contain `.git` file (not directory)
- `remote_url` must be valid GitHub URL

### Example

```json
{
  "account": "vpittamp",
  "name": "nixos",
  "path": "/home/vpittamp/repos/vpittamp/nixos",
  "remote_url": "git@github.com:vpittamp/nixos.git",
  "default_branch": "main",
  "worktrees": [
    {"branch": "main", "path": "/home/vpittamp/repos/vpittamp/nixos/main"},
    {"branch": "100-feature", "path": "/home/vpittamp/repos/vpittamp/nixos/100-feature"}
  ],
  "discovered_at": "2025-11-29T09:00:00Z",
  "last_scanned": "2025-11-29T09:30:00Z"
}
```

### Pydantic Model

```python
from pydantic import BaseModel, Field, computed_field
from datetime import datetime
from pathlib import Path

class BareRepository(BaseModel):
    account: str
    name: str
    path: str
    remote_url: str
    default_branch: str = "main"
    worktrees: list["Worktree"] = Field(default_factory=list)
    discovered_at: datetime = Field(default_factory=datetime.utcnow)
    last_scanned: datetime | None = None

    @computed_field
    @property
    def qualified_name(self) -> str:
        return f"{self.account}/{self.name}"

    @computed_field
    @property
    def bare_path(self) -> str:
        return str(Path(self.path) / ".bare")

    @computed_field
    @property
    def git_pointer_path(self) -> str:
        return str(Path(self.path) / ".git")
```

---

## Worktree

Working directory linked to a bare repository.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `branch` | string | ✅ | Branch name (e.g., "main", "100-feature") |
| `path` | string | ✅ | Full path to worktree directory |
| `commit` | string | ❌ | Current commit hash (short) |
| `is_clean` | boolean | ❌ | No uncommitted changes |
| `ahead` | int | ❌ | Commits ahead of remote |
| `behind` | int | ❌ | Commits behind remote |
| `is_main` | boolean | ❌ | Is this the main/master worktree |

### Computed Properties

- `display_name`: Branch name with feature number extracted if present
- `project_name`: `{account}/{repo}:{branch}` (full qualified name)

### Validation Rules

- `path` must exist and contain `.git` file
- `branch` must be valid git branch name

### Example

```json
{
  "branch": "100-automate-project",
  "path": "/home/vpittamp/repos/vpittamp/nixos/100-automate-project",
  "commit": "abc1234",
  "is_clean": false,
  "ahead": 3,
  "behind": 0,
  "is_main": false
}
```

### Pydantic Model

```python
from pydantic import BaseModel, computed_field
import re

class Worktree(BaseModel):
    branch: str
    path: str
    commit: str | None = None
    is_clean: bool | None = None
    ahead: int = 0
    behind: int = 0
    is_main: bool = False

    @computed_field
    @property
    def display_name(self) -> str:
        # Extract feature number if present: "100-feature" → "100 - feature"
        match = re.match(r'^(\d+)-(.+)$', self.branch)
        if match:
            return f"{match.group(1)} - {match.group(2).replace('-', ' ').title()}"
        return self.branch

    @computed_field
    @property
    def feature_number(self) -> int | None:
        match = re.match(r'^(\d+)-', self.branch)
        return int(match.group(1)) if match else None
```

---

## DiscoveredProject

Unified view for UI display - represents either a repository or a worktree.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | ✅ | Unique identifier (qualified name) |
| `account` | string | ✅ | GitHub account name |
| `repo_name` | string | ✅ | Repository name |
| `branch` | string | ❌ | Branch name (null for repo-level) |
| `type` | enum | ✅ | "repository" or "worktree" |
| `path` | string | ✅ | Working directory path |
| `display_name` | string | ✅ | Human-readable name |
| `icon` | string | ❌ | Display icon (📦 for repo, 🌿 for worktree) |
| `is_active` | boolean | ❌ | Currently active project |
| `git_status` | GitStatus | ❌ | Git metadata |
| `parent_id` | string | ❌ | Parent repository ID (for worktrees) |

### GitStatus Submodel

| Field | Type | Description |
|-------|------|-------------|
| `commit` | string | Current commit hash (short) |
| `is_clean` | boolean | No uncommitted changes |
| `ahead` | int | Commits ahead of remote |
| `behind` | int | Commits behind remote |
| `dirty_indicator` | string | "●" if dirty, empty otherwise |
| `sync_indicator` | string | "↑3 ↓2" format |

### Example - Repository

```json
{
  "id": "vpittamp/nixos",
  "account": "vpittamp",
  "repo_name": "nixos",
  "branch": null,
  "type": "repository",
  "path": "/home/vpittamp/repos/vpittamp/nixos",
  "display_name": "nixos",
  "icon": "📦",
  "is_active": false,
  "git_status": null,
  "parent_id": null
}
```

### Example - Worktree

```json
{
  "id": "vpittamp/nixos:100-automate-project",
  "account": "vpittamp",
  "repo_name": "nixos",
  "branch": "100-automate-project",
  "type": "worktree",
  "path": "/home/vpittamp/repos/vpittamp/nixos/100-automate-project",
  "display_name": "100 - Automate Project",
  "icon": "🌿",
  "is_active": true,
  "git_status": {
    "commit": "abc1234",
    "is_clean": false,
    "ahead": 3,
    "behind": 0,
    "dirty_indicator": "●",
    "sync_indicator": "↑3"
  },
  "parent_id": "vpittamp/nixos"
}
```

### Pydantic Model

```python
from pydantic import BaseModel, computed_field
from enum import Enum

class ProjectType(str, Enum):
    REPOSITORY = "repository"
    WORKTREE = "worktree"

class GitStatus(BaseModel):
    commit: str | None = None
    is_clean: bool = True
    ahead: int = 0
    behind: int = 0

    @computed_field
    @property
    def dirty_indicator(self) -> str:
        return "●" if not self.is_clean else ""

    @computed_field
    @property
    def sync_indicator(self) -> str:
        parts = []
        if self.ahead > 0:
            parts.append(f"↑{self.ahead}")
        if self.behind > 0:
            parts.append(f"↓{self.behind}")
        return " ".join(parts)

class DiscoveredProject(BaseModel):
    id: str
    account: str
    repo_name: str
    branch: str | None = None
    type: ProjectType
    path: str
    display_name: str
    icon: str = "📦"
    is_active: bool = False
    git_status: GitStatus | None = None
    parent_id: str | None = None

    @classmethod
    def from_repository(cls, repo: BareRepository) -> "DiscoveredProject":
        return cls(
            id=repo.qualified_name,
            account=repo.account,
            repo_name=repo.name,
            type=ProjectType.REPOSITORY,
            path=repo.path,
            display_name=repo.name,
            icon="📦",
        )

    @classmethod
    def from_worktree(cls, repo: BareRepository, wt: Worktree) -> "DiscoveredProject":
        return cls(
            id=f"{repo.qualified_name}:{wt.branch}",
            account=repo.account,
            repo_name=repo.name,
            branch=wt.branch,
            type=ProjectType.WORKTREE,
            path=wt.path,
            display_name=wt.display_name,
            icon="🌿",
            parent_id=repo.qualified_name,
            git_status=GitStatus(
                commit=wt.commit,
                is_clean=wt.is_clean or True,
                ahead=wt.ahead,
                behind=wt.behind,
            ),
        )
```

---

## Storage Schema

### accounts.json

```json
{
  "version": 1,
  "accounts": [
    {
      "name": "vpittamp",
      "path": "/home/vpittamp/repos/vpittamp",
      "is_default": true
    },
    {
      "name": "PittampalliOrg",
      "path": "/home/vpittamp/repos/PittampalliOrg",
      "is_default": false
    }
  ]
}
```

### repos.json

```json
{
  "version": 1,
  "last_discovery": "2025-11-29T09:00:00Z",
  "repositories": [
    {
      "account": "vpittamp",
      "name": "nixos",
      "path": "/home/vpittamp/repos/vpittamp/nixos",
      "remote_url": "git@github.com:vpittamp/nixos.git",
      "default_branch": "main",
      "worktrees": [
        {"branch": "main", "path": "...", "commit": "..."},
        {"branch": "100-automate-project", "path": "...", "commit": "..."}
      ],
      "discovered_at": "2025-11-29T09:00:00Z"
    }
  ]
}
```

---

## State Transitions

### Repository Lifecycle

```
[Not Cloned] ──clone──► [Cloned] ──discover──► [Registered]
                            │
                            ▼
                    [Worktrees Created]
```

### Worktree Lifecycle

```
[Not Exists] ──create──► [Active] ──remove──► [Pruned]
                  │                               │
                  └──────────discover─────────────┘
```

---

## Relationships

- **AccountConfig → BareRepository**: One-to-many. Each account has multiple repos.
- **BareRepository → Worktree**: One-to-many. Each repo has multiple worktrees.
- **DiscoveredProject**: Flattened view of repos and worktrees for UI consumption.
