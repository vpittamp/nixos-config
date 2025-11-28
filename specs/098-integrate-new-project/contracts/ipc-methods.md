# IPC Method Contracts

**Feature**: 098-integrate-new-project
**Protocol**: JSON-RPC 2.0 over Unix Domain Socket
**Socket**: `/tmp/i3-project-daemon.sock`

## Modified Methods

### project.switch

Switches to a project, updating environment context and window visibility.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "project.switch",
  "params": {
    "name": "nixos-098-integrate-new-project"
  },
  "id": 1
}
```

**Response (Success)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "project": {
      "name": "nixos-098-integrate-new-project",
      "directory": "/home/user/nixos-098-feature",
      "display_name": "098 - Integrate New Project",
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
      }
    },
    "windows_hidden": 5,
    "windows_shown": 3,
    "duration_ms": 185
  },
  "id": 1
}
```

**Response (Error - Missing Project)**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Cannot switch to project 'old-project': directory does not exist at /path/to/old. Either restore the directory or delete the project with: i3pm project delete old-project"
  },
  "id": 1
}
```

**Changes from Feature 097**:
- NEW: Response includes `parent_project` field
- NEW: Response includes `branch_metadata` object
- NEW: Error code -32001 for missing projects (FR-008)

---

### project.current

Returns the currently active project with full metadata.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "project.current",
  "params": {},
  "id": 2
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "name": "nixos-098-integrate-new-project",
    "directory": "/home/user/nixos-098-feature",
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
    }
  },
  "id": 2
}
```

**Response (No Active Project)**:
```json
{
  "jsonrpc": "2.0",
  "result": null,
  "id": 2
}
```

**Changes from Feature 097**:
- NEW: Response includes `parent_project` field
- NEW: Response includes `branch_metadata` object

---

## New Methods

### project.refresh

Re-extracts git and branch metadata for an existing project without full discovery.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "project.refresh",
  "params": {
    "name": "nixos-098-integrate-new-project"
  },
  "id": 3
}
```

**Response (Success)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "project": {
      "name": "nixos-098-integrate-new-project",
      "git_metadata": {
        "branch": "098-integrate-new-project",
        "commit": "abc1234",
        "is_clean": false,
        "ahead": 2,
        "behind": 0
      },
      "branch_metadata": {
        "number": "098",
        "type": "feature",
        "full_name": "098-integrate-new-project"
      }
    },
    "fields_updated": ["git_metadata", "branch_metadata", "updated_at"]
  },
  "id": 3
}
```

**Response (Error - Project Not Found)**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32002,
    "message": "Project 'nonexistent' not found"
  },
  "id": 3
}
```

**Response (Error - Directory Missing)**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Cannot refresh project 'old-project': directory does not exist at /path/to/old"
  },
  "id": 3
}
```

---

### worktree.list

Lists all worktree projects for a given parent project.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "worktree.list",
  "params": {
    "parent_project": "nixos"
  },
  "id": 4
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "parent": {
      "name": "nixos",
      "directory": "/etc/nixos"
    },
    "worktrees": [
      {
        "name": "nixos-097-convert-manual",
        "display_name": "097 - Convert Manual Projects",
        "branch_metadata": {
          "number": "097",
          "type": "feature",
          "full_name": "097-convert-manual-projects"
        },
        "status": "active"
      },
      {
        "name": "nixos-098-integrate-new",
        "display_name": "098 - Integrate New Project",
        "branch_metadata": {
          "number": "098",
          "type": "feature",
          "full_name": "098-integrate-new-project"
        },
        "status": "active"
      }
    ],
    "count": 2
  },
  "id": 4
}
```

---

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32001 | DIRECTORY_MISSING | Project directory does not exist |
| -32002 | PROJECT_NOT_FOUND | Project name not found in registry |
| -32003 | INVALID_PROJECT_STATUS | Operation not allowed for project status |

---

## CLI Mapping

| CLI Command | IPC Method | Notes |
|-------------|------------|-------|
| `i3pm project switch <name>` | `project.switch` | Now validates status |
| `i3pm project current --json` | `project.current` | Returns enhanced JSON |
| `i3pm project refresh <name>` | `project.refresh` | NEW: FR-009 |
| `i3pm worktree list <parent>` | `worktree.list` | NEW: FR-005 |

---

## Environment Variable Contract

When `project.current` returns a worktree project, app-launcher-wrapper.sh MUST inject:

**Required (if worktree)**:
```bash
I3PM_IS_WORKTREE="true"
I3PM_FULL_BRANCH_NAME="<branch_metadata.full_name>"
```

**Conditional (if present)**:
```bash
I3PM_PARENT_PROJECT="<parent_project>"          # if not null
I3PM_BRANCH_NUMBER="<branch_metadata.number>"   # if not null
I3PM_BRANCH_TYPE="<branch_metadata.type>"       # if not null
```

**Git Metadata (if present)**:
```bash
I3PM_GIT_BRANCH="<git_metadata.branch>"         # if not null
I3PM_GIT_COMMIT="<git_metadata.commit>"         # if not null
I3PM_GIT_IS_CLEAN="<git_metadata.is_clean>"     # as "true"/"false"
I3PM_GIT_AHEAD="<git_metadata.ahead>"           # if not null
I3PM_GIT_BEHIND="<git_metadata.behind>"         # if not null
```

**Grace Handling**: Missing fields MUST be omitted from environment (not set to empty string).
