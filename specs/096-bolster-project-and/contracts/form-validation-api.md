# Form Validation API Contract

**Feature**: 096-bolster-project-and
**Version**: 1.0
**Date**: 2025-11-26

## Overview

Real-time form validation for project/worktree editing. Uses streaming JSON output for responsive UI feedback.

## Validation Stream API

### Start Validation Stream

**Command**: `python3 project_form_validator_stream.py --mode project`

**Modes**:
| Mode | Description |
|------|-------------|
| `project` | Validate project edit form |
| `project-create` | Validate project create form |
| `worktree` | Validate worktree edit form |
| `worktree-create` | Validate worktree create form |

### Input (stdin)

JSON lines with form field values:

```json
{"field": "display_name", "value": "New Name"}
{"field": "icon", "value": "🔥"}
{"field": "name", "value": "invalid name!"}
```

### Output (stdout)

JSON lines with validation results:

```json
{"field": "display_name", "valid": true, "error": null}
{"field": "icon", "valid": true, "error": null}
{"field": "name", "valid": false, "error": "Must contain only lowercase letters, numbers, and hyphens"}
```

### Aggregated Validation State

After all fields validated, summary message:

```json
{
  "type": "summary",
  "valid": false,
  "errors": {
    "name": "Must contain only lowercase letters, numbers, and hyphens"
  }
}
```

## Validation Rules

### Project Name

| Rule | Pattern/Constraint |
|------|-------------------|
| Format | `^[a-z0-9-]+$` |
| Min length | 1 character |
| Max length | 64 characters |
| Reserved | Cannot be "global", "new", "create" |
| Unique | No existing project with same name |

**Error Messages**:
- Empty: "Name is required"
- Invalid chars: "Must contain only lowercase letters, numbers, and hyphens"
- Duplicate: "A project with this name already exists"

### Display Name

| Rule | Pattern/Constraint |
|------|-------------------|
| Required | No (defaults to name if empty) |
| Max length | 100 characters |

**Error Messages**:
- Too long: "Display name must be 100 characters or less"

### Icon

| Rule | Pattern/Constraint |
|------|-------------------|
| Required | No (defaults to 📁) |
| Format | Single emoji or icon path |
| Max length | 10 characters |

**Error Messages**:
- Too long: "Icon must be a single emoji or short path"

### Directory (Working Directory)

| Rule | Pattern/Constraint |
|------|-------------------|
| Required | Yes |
| Format | Absolute path |
| Exists | Path must exist and be accessible |

**Error Messages**:
- Empty: "Directory is required"
- Not absolute: "Directory must be an absolute path"
- Not exists: "Directory does not exist"

### Remote Configuration

When `remote.enabled = true`:

| Field | Rule |
|-------|------|
| `host` | Required, non-empty |
| `user` | Required, non-empty |
| `remote_dir` | Required, absolute path |
| `port` | 1-65535 (default: 22) |

**Error Messages**:
- Host empty: "Remote host is required when remote access is enabled"
- User empty: "Remote user is required when remote access is enabled"
- Dir not absolute: "Remote directory must be an absolute path"
- Port invalid: "Port must be between 1 and 65535"

### Worktree-Specific Rules

| Field | Rule |
|-------|------|
| `branch_name` | Required for create, read-only for edit |
| `worktree_path` | Required for create, read-only for edit |
| `parent_project` | Must reference existing main project (not a worktree) |

**Error Messages**:
- Branch empty: "Branch name is required"
- Parent not found: "Parent project does not exist"
- Parent is worktree: "Parent must be a main project, not a worktree"

## Eww Integration

### Defpoll Validation

```lisp
(defpoll validation_state
  :interval "300ms"
  :run-while editing_project_name != ""
  `validate-project-form`)
```

### Widget Error Display

```lisp
(revealer
  :reveal {validation_state.errors.display_name != ""}
  :transition "slidedown"
  (label
    :class "field-error"
    :text {validation_state.errors.display_name}))
```

### Save Button Sensitivity

```lisp
(button
  :class {validation_state.valid ? "save-button" : "save-button-disabled"}
  :sensitive {validation_state.valid}
  :onclick "project-edit-save ${project.name}"
  "Save")
```

## Visual Feedback Styling

### Error State (Catppuccin Mocha)

```css
.field-error {
  color: #f38ba8;  /* Red */
  font-style: italic;
  font-size: 12px;
}

.save-button-disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
```

### Success State

```css
.notification-success {
  background-color: rgba(166, 227, 161, 0.2);  /* Green */
  border-color: #a6e3a1;
}
```
