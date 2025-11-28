# Data Model: Worktree-Aware Project Environment Integration

**Feature**: 098-integrate-new-project
**Date**: 2025-11-28

## Entity Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Project                                  │
├─────────────────────────────────────────────────────────────────┤
│ name: str                  # Unique identifier                   │
│ directory: str             # Absolute path                       │
│ display_name: str          # Human-readable name                 │
│ icon: str                  # Emoji icon                          │
│ scoped_classes: List[str]  # Window classes to scope             │
│ source_type: SourceType    # LOCAL | WORKTREE | REMOTE           │
│ status: ProjectStatus      # ACTIVE | INACTIVE | MISSING         │
│ git_metadata: GitMetadata? # Git state (Feature 097)             │
│ discovered_at: datetime    # When discovered                     │
│ created_at: datetime       # When created                        │
│ updated_at: datetime       # Last modified                       │
├─────────────────────────────────────────────────────────────────┤
│ parent_project: str?       # NEW: Parent project name (worktrees)│
│ branch_metadata: BranchMeta? # NEW: Parsed branch info           │
└─────────────────────────────────────────────────────────────────┘
                          │ 1
                          │
                          │ 0..1
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BranchMetadata (NEW)                        │
├─────────────────────────────────────────────────────────────────┤
│ number: str?              # Branch number (e.g., "098")          │
│ type: str?                # Branch type (feature, fix, hotfix)   │
│ full_name: str            # Complete branch name                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      GitMetadata (Feature 097)                   │
├─────────────────────────────────────────────────────────────────┤
│ branch: str               # Current branch name                  │
│ commit: str               # Current commit SHA (short)           │
│ is_clean: bool            # No uncommitted changes               │
│ ahead: int                # Commits ahead of upstream            │
│ behind: int               # Commits behind upstream              │
│ remote_url: str?          # Remote origin URL                    │
│ last_commit_message: str? # Most recent commit message           │
│ last_commit_date: datetime? # Most recent commit date            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   WorktreeEnvironment (EXISTS)                   │
├─────────────────────────────────────────────────────────────────┤
│ is_worktree: bool         # True if worktree project             │
│ parent_project: str?      # Parent project name                  │
│ branch_type: str?         # Parsed type                          │
│ branch_number: str?       # Parsed number                        │
│ full_branch_name: str?    # Complete branch name                 │
├─────────────────────────────────────────────────────────────────┤
│ + to_env_dict() -> Dict   # Convert to I3PM_* variables          │
│ + from_project(Project)   # NEW: Factory from Project            │
└─────────────────────────────────────────────────────────────────┘
```

## Entity Definitions

### BranchMetadata (NEW)

Parsed branch name information extracted during discovery and stored in Project JSON.

```python
class BranchMetadata(BaseModel):
    """Parsed branch name metadata.

    Supports patterns:
    - 098-feature-auth → number="098", type="feature"
    - fix-123-broken → number="123", type="fix"
    - 078-eww-preview → number="078", type="feature" (default)
    - hotfix-critical → number=None, type="hotfix"
    - main → number=None, type=None
    """

    number: Optional[str] = Field(
        default=None,
        description="Branch number extracted from name (e.g., '098')",
        pattern=r'^\d+$'
    )

    type: Optional[str] = Field(
        default=None,
        description="Branch type (feature, fix, hotfix, release, etc.)"
    )

    full_name: str = Field(
        ...,
        description="Complete branch name as-is"
    )
```

**Validation Rules**:
- `number` must be digits only if present
- `type` should be from known set: feature, fix, hotfix, release, bug, chore, docs, test, refactor
- `full_name` is required and stored as-is

**State Transitions**: N/A (immutable after parsing)

### Project (MODIFIED)

Extended with worktree-specific fields.

```python
class Project(BaseModel):
    """Project definition with worktree metadata."""

    # Existing fields (unchanged)...

    # NEW: Feature 098 fields
    parent_project: Optional[str] = Field(
        default=None,
        description="Name of parent project (if this is a worktree)"
    )

    branch_metadata: Optional[BranchMetadata] = Field(
        default=None,
        description="Parsed branch metadata (number, type, full_name)"
    )
```

**Validation Rules**:
- `parent_project` must reference an existing project name or be null
- `branch_metadata` populated only when `source_type == WORKTREE` and branch parseable
- `status` must be ACTIVE to allow switching

**State Transitions**:
```
ACTIVE ──[directory deleted]──> MISSING
MISSING ──[directory restored + refresh]──> ACTIVE
ACTIVE ──[manual disable]──> INACTIVE
INACTIVE ──[manual enable]──> ACTIVE
```

### WorktreeEnvironment (ENHANCED)

Factory method to create from Project entity.

```python
class WorktreeEnvironment(BaseModel):
    """Worktree metadata for environment variable injection."""

    # Existing fields (unchanged)...

    @classmethod
    def from_project(cls, project: Project) -> "WorktreeEnvironment":
        """Create WorktreeEnvironment from Project entity.

        Args:
            project: Project with optional branch_metadata and parent_project

        Returns:
            WorktreeEnvironment ready for to_env_dict()
        """
        is_worktree = project.source_type == SourceType.WORKTREE

        branch_metadata = project.branch_metadata
        branch_type = branch_metadata.type if branch_metadata else None
        branch_number = branch_metadata.number if branch_metadata else None
        full_branch_name = branch_metadata.full_name if branch_metadata else None

        return cls(
            is_worktree=is_worktree,
            parent_project=project.parent_project,
            branch_type=branch_type,
            branch_number=branch_number,
            full_branch_name=full_branch_name
        )
```

## JSON Schema

### Project JSON (Enhanced)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Project",
  "type": "object",
  "required": ["name", "directory", "display_name", "source_type", "status"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9_-]+$"
    },
    "directory": {
      "type": "string",
      "description": "Absolute path to project directory"
    },
    "display_name": {
      "type": "string"
    },
    "icon": {
      "type": "string",
      "default": "📁"
    },
    "source_type": {
      "type": "string",
      "enum": ["local", "worktree", "remote"]
    },
    "status": {
      "type": "string",
      "enum": ["active", "inactive", "missing"]
    },
    "parent_project": {
      "type": ["string", "null"],
      "description": "Name of parent project (worktrees only)"
    },
    "branch_metadata": {
      "type": ["object", "null"],
      "properties": {
        "number": {
          "type": ["string", "null"],
          "pattern": "^\\d+$"
        },
        "type": {
          "type": ["string", "null"]
        },
        "full_name": {
          "type": "string"
        }
      },
      "required": ["full_name"]
    },
    "git_metadata": {
      "type": ["object", "null"],
      "properties": {
        "branch": { "type": "string" },
        "commit": { "type": "string" },
        "is_clean": { "type": "boolean" },
        "ahead": { "type": "integer" },
        "behind": { "type": "integer" }
      }
    }
  }
}
```

### Example Project JSON

```json
{
  "name": "nixos-098-integrate-new-project",
  "directory": "/home/vpittamp/nixos-097-convert-manual-projects-098-integrate-new-project",
  "display_name": "098 - Integrate New Project",
  "icon": "❄️",
  "source_type": "worktree",
  "status": "active",
  "parent_project": "nixos",
  "branch_metadata": {
    "number": "098",
    "type": "feature",
    "full_name": "098-integrate-new-project"
  },
  "git_metadata": {
    "branch": "098-integrate-new-project",
    "commit": "330b569",
    "is_clean": true,
    "ahead": 0,
    "behind": 0
  },
  "created_at": "2025-11-28T10:00:00Z",
  "updated_at": "2025-11-28T10:00:00Z",
  "discovered_at": "2025-11-28T10:00:00Z",
  "scoped_classes": []
}
```

## Environment Variables Output

When a worktree project is active, `WorktreeEnvironment.to_env_dict()` produces:

```bash
# Worktree identity (FR-001)
I3PM_IS_WORKTREE=true
I3PM_PARENT_PROJECT=nixos
I3PM_BRANCH_NUMBER=098
I3PM_BRANCH_TYPE=feature
I3PM_FULL_BRANCH_NAME=098-integrate-new-project

# Git metadata (FR-006)
I3PM_GIT_BRANCH=098-integrate-new-project
I3PM_GIT_COMMIT=330b569
I3PM_GIT_IS_CLEAN=true
I3PM_GIT_AHEAD=0
I3PM_GIT_BEHIND=0
```

## Relationships

```
Project (1) ──────────────── (0..1) BranchMetadata
   │                                    │
   │ parent_project                     │ Embedded in Project JSON
   │                                    │
   ▼                                    │
Project (parent)                        │
                                        │
WorktreeEnvironment ◄───────────────────┘
   │                    from_project() factory
   │
   ▼
Environment Variables (Dict[str, str])
   │
   ▼
app-launcher-wrapper.sh → Subprocess environment
```

## Migration Notes

- Existing projects without `parent_project` and `branch_metadata` remain valid (nullable fields)
- Running `i3pm discover` on existing worktrees will populate new fields
- `i3pm project refresh <name>` updates metadata for single project
- No breaking changes to existing Project JSON format
