# API Contract: Form Validation Service

**Feature**: 094-enhance-project-tab
**Service**: `form-validation-service`
**Protocol**: Streaming JSON via stdout (deflisten)
**Date**: 2025-11-24

## Overview

The form validation service provides real-time validation feedback for Projects and Applications forms. It streams validation results to Eww via `deflisten` with 300ms debouncing in the backend (per research.md findings).

---

## Streaming Protocol

### Invocation

```bash
# Projects form validation
form-validation-service --mode projects --listen

# Applications form validation (regular apps)
form-validation-service --mode apps --app-type regular --listen

# Applications form validation (PWAs)
form-validation-service --mode apps --app-type pwa --listen

# Applications form validation (terminal apps)
form-validation-service --mode apps --app-type terminal --listen
```

### Output Format

**Single-line JSON to stdout, flushed immediately after validation**

```json
{
  "valid": false,
  "errors": {
    "project_name": "Project 'nixos' already exists",
    "directory": "Directory does not exist: /invalid/path"
  },
  "warnings": {
    "icon": "Custom icon path not found, will use default"
  }
}
```

### Update Frequency

- **Debouncing**: 300ms delay after last keystroke (per spec.md FR-U-002)
- **Latency**: <100ms from validation completion to stdout output
- **Heartbeat**: Every 5 seconds when no changes (to detect stale connection)

---

## Validation Rules

### Projects Mode (`--mode projects`)

#### Field: `project_name`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Project name is required" | FR-P-007 |
| Not lowercase-hyphen | "Must be lowercase alphanumeric with hyphens only (no spaces)" | FR-P-007 |
| Already exists | "Project '{name}' already exists" | Edge Case: Duplicate project names |
| Too long (>64 chars) | "Project name must be 64 characters or less" | data-model.md |

#### Field: `directory`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Working directory is required" | FR-P-008 |
| Does not exist | "Directory does not exist: {path}" | FR-P-008 |
| Not a directory | "Path is not a directory: {path}" | FR-P-008 |
| Not accessible | "Directory not accessible (check permissions): {path}" | FR-P-008 |

#### Field: `icon`

| Rule | Error/Warning | FR Reference |
|------|---------------|--------------|
| Empty | Warning: "Using default icon 📦" | Edge Case: Icon picker |
| Path doesn't exist | Warning: "Custom icon path not found, will use default" | Edge Case: Icon picker |
| Invalid format | Error: "Icon must be emoji or absolute file path" | Edge Case: Icon picker |

#### Field: `remote.host` (if remote enabled)

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "SSH hostname is required for remote projects" | FR-P-010 |

#### Field: `remote.remote_dir` (if remote enabled)

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Remote directory is required for remote projects" | FR-P-010 |
| Not absolute path | "Remote directory must be absolute path, got: {path}" | data-model.md |

#### Field: `remote.port` (if remote enabled)

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Out of range | "Port must be between 1 and 65535, got: {port}" | Edge Case: Remote SSH validation |

### Applications Mode (Regular, `--mode apps --app-type regular`)

#### Field: `name`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Application name is required" | FR-A-006 |
| Invalid format | "Must be lowercase alphanumeric with hyphens or dots only" | FR-A-006 |
| Already exists | "Application '{name}' already exists in registry" | Edge Case: Duplicate apps |

#### Field: `command`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Command is required" | data-model.md |
| Contains metacharacters | "Command contains dangerous metacharacter '{char}'" | FR-A-009 |

#### Field: `preferred_workspace`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Out of range (regular) | "Regular applications must use workspaces 1-50, got: {num}" | FR-A-007 |
| Invalid number | "Workspace must be a valid number" | FR-A-007 |

### Applications Mode (PWA, `--app-type pwa`)

#### Field: `name`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Doesn't end with `-pwa` | "PWA name must end with '-pwa', got: {name}" | data-model.md |

#### Field: `start_url`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Empty | "Start URL is required for PWAs" | FR-A-015 |
| Invalid URL | "URL must start with http:// or https://, got: {url}" | FR-A-015 |

#### Field: `preferred_workspace`

| Rule | Error Message | FR Reference |
|------|---------------|--------------|
| Below 50 | "PWAs must use workspaces 50 or higher, got: {num}" | FR-A-007 |

#### Field: `ulid` (read-only, not validated in create form)

- **Note**: ULID is auto-generated on save (per FR-A-029), NOT displayed in create form
- Validation only occurs if editing existing PWA (read-only field)

---

## Example Interactions

### Example 1: Valid Project Form

**Input** (form state read from Eww):
```json
{
  "project_name": "my-new-project",
  "directory": "/home/vpittamp/projects/my-new-project",
  "icon": "📦",
  "scope": "scoped"
}
```

**Output** (streamed to stdout):
```json
{
  "valid": true,
  "errors": {},
  "warnings": {}
}
```

### Example 2: Invalid Project Name

**Input**:
```json
{
  "project_name": "My Project",
  "directory": "/home/vpittamp/projects/my-project",
  "icon": "📦",
  "scope": "scoped"
}
```

**Output**:
```json
{
  "valid": false,
  "errors": {
    "project_name": "Must be lowercase alphanumeric with hyphens only (no spaces)"
  },
  "warnings": {}
}
```

### Example 3: Duplicate Project Name

**Input**:
```json
{
  "project_name": "nixos",
  "directory": "/home/vpittamp/projects/nixos-new",
  "icon": "📦",
  "scope": "scoped"
}
```

**Output**:
```json
{
  "valid": false,
  "errors": {
    "project_name": "Project 'nixos' already exists"
  },
  "warnings": {}
}
```

### Example 4: Invalid Directory

**Input**:
```json
{
  "project_name": "test-project",
  "directory": "/invalid/nonexistent/path",
  "icon": "📦",
  "scope": "scoped"
}
```

**Output**:
```json
{
  "valid": false,
  "errors": {
    "directory": "Directory does not exist: /invalid/nonexistent/path"
  },
  "warnings": {}
}
```

### Example 5: Valid PWA Form (with warning)

**Input**:
```json
{
  "name": "notion-pwa",
  "display_name": "Notion",
  "start_url": "https://www.notion.so",
  "scope_url": "https://www.notion.so/",
  "preferred_workspace": 55,
  "icon": "/custom/path/notion.svg"
}
```

**Output**:
```json
{
  "valid": true,
  "errors": {},
  "warnings": {
    "icon": "Custom icon path not found, will use default"
  }
}
```

---

## Implementation Notes

### Debouncing Strategy

Per research.md findings, Eww's `:timeout` property is NOT true debouncing. Backend must implement:

```python
class ValidationDebouncer:
    """True debouncing with 300ms delay"""
    def __init__(self, delay: float = 0.3):
        self.delay = delay
        self.pending_task: Optional[asyncio.Task] = None
        self.last_input = None

    async def debounce(self, input_value: str, callback):
        """Cancel previous validation, wait 300ms, then validate if still latest"""
        self.last_input = input_value

        if self.pending_task:
            self.pending_task.cancel()

        async def delayed_callback():
            await asyncio.sleep(self.delay)
            if self.last_input == input_value:  # Still the latest value
                await callback(input_value)

        self.pending_task = asyncio.create_task(delayed_callback())
```

### Form State Source

Backend reads current form state from:
1. **Eww variables** (via `eww get <var>` subprocess call), OR
2. **State file** (written by Eww onchange handlers to `/tmp/form-state.json`)

Option 2 is recommended for performance (avoid subprocess overhead on every validation).

### Pydantic Integration

```python
async def validate_project_form(form_data: dict) -> FormValidationState:
    """Validate project form using Pydantic models"""
    try:
        validated = ProjectConfig(**form_data)
        return FormValidationState(valid=True, errors={}, warnings={})
    except ValidationError as e:
        errors = {err["loc"][0]: err["msg"] for err in e.errors()}
        return FormValidationState(valid=False, errors=errors, warnings={})
```

---

## Error Codes (Future Extension)

**Not implemented in MVP**, but reserved for future use:

```json
{
  "valid": false,
  "errors": {
    "project_name": {
      "code": "E001",
      "message": "Project 'nixos' already exists",
      "field": "project_name",
      "severity": "error"
    }
  }
}
```

---

## Testing

### Unit Tests

- Test each validation rule independently with valid/invalid inputs
- Test debouncing behavior (ensure only latest value validated)
- Test Pydantic model integration

### Integration Tests

- Test deflisten streaming (subscribe to stdout, verify JSON output)
- Test form state reading from Eww variables or state file
- Test heartbeat mechanism (no updates for 5s → heartbeat emitted)

### Contract Tests

- Verify JSON schema matches FormValidationState Pydantic model
- Test all example interactions above
