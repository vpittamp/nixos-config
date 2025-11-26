# Data Model: Project & Worktree CRUD Operations

**Feature**: 096-bolster-project-and
**Date**: 2025-11-26

## Entities

### Project

The core entity representing an i3pm project configuration.

**Storage**: JSON file at `~/.config/i3/projects/<name>.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique identifier (lowercase, hyphens, numbers only) |
| `display_name` | string | No | Human-readable name shown in UI |
| `icon` | string | No | Emoji or icon path |
| `directory` | string | Yes | Absolute path to project working directory |
| `scope` | enum | No | "scoped" (default) or "global" |
| `scoped_classes` | string[] | No | Window classes to filter for this project |
| `created_at` | datetime | No | ISO 8601 creation timestamp |
| `updated_at` | datetime | No | ISO 8601 last update timestamp |
| `remote` | RemoteConfig | No | SSH remote configuration (optional) |
| `worktree` | WorktreeMetadata | No | Git worktree metadata (auto-populated) |

**Validation Rules**:
- `name`: Must match pattern `^[a-z0-9-]+$` (lowercase, hyphens, numbers only)
- `directory`: Must be an absolute path that exists and is accessible
- `name`: Must be unique across all projects (checked before create)

**Identity**: Primary key is `name`. File path is derived as `<projects_dir>/<name>.json`.

### Worktree (extends Project)

A Git worktree that extends Project with branch association.

**Storage**: JSON file at `~/.config/i3/projects/<worktree-name>.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| (all Project fields) | - | - | Inherited from Project |
| `parent_project` | string | Yes | Name of parent project |
| `branch_name` | string | Yes | Git branch name (immutable after creation) |
| `worktree_path` | string | Yes | Git worktree directory path (immutable after creation) |

**Validation Rules**:
- `parent_project`: Must reference an existing project (not another worktree)
- `branch_name`: Read-only after creation (cannot be edited in UI)
- `worktree_path`: Read-only after creation (cannot be edited in UI)
- `worktree_path`: Must be an absolute path

**State Transitions**:
```
[Not Exists] → create → [Active]
[Active] → edit → [Active]
[Active] → delete → [Not Exists]
```

### RemoteConfig

SSH configuration for remote project access.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `enabled` | boolean | Yes | Whether remote access is enabled |
| `host` | string | If enabled | SSH hostname or Tailscale FQDN |
| `user` | string | If enabled | SSH username |
| `remote_dir` | string | If enabled | Absolute path on remote host |
| `port` | integer | No | SSH port (default: 22) |

**Validation Rules**:
- `port`: Must be 1-65535
- `remote_dir`: Must be an absolute path when enabled

### FormState (Eww UI State)

Transient state for form editing (not persisted to disk).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `editing_project_name` | string | "" | Currently editing project name |
| `edit_form_display_name` | string | "" | Form input: display name |
| `edit_form_icon` | string | "" | Form input: icon |
| `edit_form_scope` | string | "scoped" | Form input: scope |
| `edit_form_directory` | string | "" | Form input: directory (read-only) |
| `edit_form_error` | string | "" | Current validation/save error |
| `edit_form_remote_enabled` | boolean | false | Form input: remote enabled |
| `edit_form_remote_host` | string | "" | Form input: remote host |
| `edit_form_remote_user` | string | "" | Form input: remote user |
| `edit_form_remote_dir` | string | "" | Form input: remote directory |
| `edit_form_remote_port` | integer | 22 | Form input: remote port |
| `save_in_progress` | boolean | false | Whether save is in progress |
| `project_creating` | boolean | false | Whether create form is open |
| `worktree_creating` | boolean | false | Whether worktree create form is open |

### ValidationState (Eww UI State)

Validation feedback state.

| Variable | Type | Description |
|----------|------|-------------|
| `validation_state.valid` | boolean | Whether form is valid for submission |
| `validation_state.errors.display_name` | string | Validation error for display_name |
| `validation_state.errors.icon` | string | Validation error for icon |
| `validation_state.errors.name` | string | Validation error for name |
| `validation_state.errors.directory` | string | Validation error for directory |

### NotificationState (Eww UI State)

Toast notification state.

| Variable | Type | Description |
|----------|------|-------------|
| `notification_visible` | boolean | Whether notification is showing |
| `notification_type` | string | "success" or "error" |
| `notification_message` | string | Notification text content |
| `notification_auto_dismiss` | boolean | Whether to auto-dismiss |

## Entity Relationships

```
┌─────────────┐     1:N     ┌───────────┐
│   Project   │────────────▶│ Worktree  │
│  (parent)   │             │  (child)  │
└─────────────┘             └───────────┘
       │
       │ 0:1
       ▼
┌─────────────┐
│RemoteConfig │
└─────────────┘
```

- **Project → Worktree**: One project can have many worktrees
- **Project → RemoteConfig**: One project can have one optional remote configuration
- **Worktree → Project**: Each worktree belongs to exactly one parent project (via `parent_project` field)

## Data Volume Assumptions

| Entity | Typical Count | Max Expected |
|--------|--------------|--------------|
| Main Projects | 5-10 | 20 |
| Worktrees per Project | 1-3 | 10 |
| Total Projects (including worktrees) | 10-30 | 100 |

## Lifecycle Management

### Project Lifecycle

1. **Create**: User fills form, clicks Save
   - Validate all fields
   - Check name uniqueness
   - Verify directory exists
   - Write JSON file
   - Refresh project list

2. **Edit**: User clicks edit button, modifies fields, clicks Save
   - Load current values into form
   - Validate changes
   - Write JSON file (atomic with backup)
   - Refresh project list

3. **Delete**: User clicks delete, confirms in dialog
   - Check for dependent worktrees
   - Create backup of JSON file
   - Remove JSON file
   - Refresh project list

### Worktree Lifecycle

1. **Create**: User fills worktree form, clicks Create
   - Validate branch exists in parent repo
   - Execute `git worktree add <path> <branch>`
   - Generate worktree project name
   - Create JSON file with parent reference
   - Refresh project list

2. **Edit**: Same as Project edit but:
   - `branch_name` and `worktree_path` are read-only
   - Only `display_name`, `icon`, `scope` editable

3. **Delete**: User clicks delete, confirms
   - Execute `git worktree remove <path>`
   - Create backup of JSON file
   - Remove JSON file
   - Refresh project list
