# Project CRUD API Contract

**Feature**: 096-bolster-project-and
**Version**: 1.0
**Date**: 2025-11-26

## Overview

Command-line API for project CRUD operations. Called from Eww shell scripts via `python3 -m i3_project_manager.cli.project_crud_handler`.

## Common Response Format

All operations return single-line JSON to stdout.

### Success Response

```json
{
  "status": "success",
  ...additional fields...
}
```

### Error Response

```json
{
  "status": "error",
  "error": "Human-readable error message",
  "validation_errors": [
    {
      "field": "field.path",
      "message": "Error description",
      "type": "error_type"
    }
  ]
}
```

## Operations

### List Projects

**Command**: `project_crud_handler list`

**Response**:
```json
{
  "status": "success",
  "main_projects": [
    {
      "name": "nixos",
      "display_name": "NixOS",
      "directory": "/etc/nixos",
      "icon": "❄️",
      "scope": "scoped",
      "is_active": true,
      "is_remote": false,
      "worktree": {
        "branch": "main",
        "is_clean": true
      }
    }
  ],
  "worktrees": [
    {
      "name": "nixos-096-bolster",
      "display_name": "Bolster CRUD",
      "directory": "/home/user/nixos-096-bolster",
      "icon": "🌿",
      "parent_project": "nixos",
      "branch_name": "096-bolster-project-and",
      "worktree_path": "/home/user/nixos-096-bolster"
    }
  ]
}
```

---

### Read Project

**Command**: `project_crud_handler read <name>`

**Arguments**:
| Arg | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Project name |

**Success Response**:
```json
{
  "status": "success",
  "project": {
    "name": "nixos",
    "display_name": "NixOS",
    "directory": "/etc/nixos",
    "icon": "❄️",
    "scope": "scoped"
  }
}
```

**Error Codes**:
| Error | Condition |
|-------|-----------|
| `Project 'name' not found` | No JSON file exists |

---

### Edit Project

**Command**: `project_crud_handler edit <name> --updates '<json>'`

**Arguments**:
| Arg | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Project name |
| `--updates` | Yes | JSON object of fields to update |

**Example Updates JSON**:
```json
{
  "display_name": "New Display Name",
  "icon": "🔥",
  "scope": "global",
  "remote": {
    "enabled": true,
    "host": "server.tailnet",
    "user": "user",
    "remote_dir": "/home/user/project",
    "port": 22
  }
}
```

**Success Response**:
```json
{
  "status": "success",
  "conflict": false,
  "path": "/home/user/.config/i3/projects/nixos.json"
}
```

**Error Codes**:
| Error | Condition |
|-------|-----------|
| `Project 'name' not found` | No JSON file exists |
| `Validation failed` | Invalid field values |
| `Invalid JSON in --updates` | Malformed JSON input |

**Conflict Detection** (Fixed in Feature 096):
- `conflict: true` only when file was modified by another process between read and write
- NOT triggered by our own write operation

---

### Create Project

**Command**: `project_crud_handler create --config '<json>'`

**Arguments**:
| Arg | Required | Description |
|-----|----------|-------------|
| `--config` | Yes | Full project configuration JSON |

**Example Config JSON**:
```json
{
  "name": "new-project",
  "display_name": "New Project",
  "directory": "/home/user/new-project",
  "icon": "🆕",
  "scope": "scoped"
}
```

**Success Response**:
```json
{
  "status": "success",
  "path": "/home/user/.config/i3/projects/new-project.json",
  "project_name": "new-project"
}
```

**Error Codes**:
| Error | Condition |
|-------|-----------|
| `Project 'name' already exists` | Duplicate name |
| `Validation failed` | Invalid field values |
| `Directory does not exist` | Specified path not accessible |

---

### Delete Project

**Command**: `project_crud_handler delete <name> [--force]`

**Arguments**:
| Arg | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Project name |
| `--force` | No | Skip worktree dependency check |

**Success Response**:
```json
{
  "status": "success",
  "path": "/home/user/.config/i3/projects/old-project.json",
  "backup": "/home/user/.config/i3/projects/.old-project.json.bak"
}
```

**Error Codes**:
| Error | Condition |
|-------|-----------|
| `Project 'name' not found` | No JSON file exists |
| `Project has active worktrees` | Worktrees depend on this project (requires --force) |

---

### Get File Modification Time

**Command**: `project_crud_handler get-mtime <name>`

**Arguments**:
| Arg | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Project name |

**Success Response**:
```json
{
  "status": "success",
  "mtime": 1732648123.456,
  "project_name": "nixos"
}
```

**Error Codes**:
| Error | Condition |
|-------|-----------|
| `Project 'name' not found` | No JSON file exists |

## Shell Script Integration

### Calling from Eww onclick

```bash
# project-edit-save script (simplified)
PROJECT_NAME="$1"
EWW="eww --config $HOME/.config/eww-monitoring-panel"

# Read form values
DISPLAY_NAME=$($EWW get edit_form_display_name)
ICON=$($EWW get edit_form_icon)

# Build updates JSON
UPDATES="{\"display_name\": \"$DISPLAY_NAME\", \"icon\": \"$ICON\"}"

# Call handler
export PYTHONPATH="..."
RESULT=$(python3 -m i3_project_manager.cli.project_crud_handler edit "$PROJECT_NAME" --updates "$UPDATES")

# Parse response
STATUS=$(echo "$RESULT" | jq -r '.status')
if [ "$STATUS" = "success" ]; then
  # Refresh UI
  $EWW update editing_project_name=''
  PROJECTS_DATA=$(python3 .../monitoring_data.py --mode projects)
  $EWW update projects_data="$PROJECTS_DATA"
fi
```

### Error Handling Best Practices

1. Always check `status` field first
2. Display `error` field for user-friendly message
3. Use `validation_errors` array for inline field errors
4. Non-zero exit code indicates failure
