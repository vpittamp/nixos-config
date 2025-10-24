# CLI API Specification: i3pm apps

**Feature**: 034-create-a-feature
**Version**: 1.0.0
**Date**: 2025-10-24

## Overview

The `i3pm apps` subcommand provides terminal-based management of the application launcher registry. All commands support both human-readable table output and machine-readable JSON output.

## Global Flags

All `i3pm apps` commands support these global flags:

| Flag | Short | Type | Description | Default |
|------|-------|------|-------------|---------|
| `--format` | `-f` | string | Output format: `table`, `json` | `table` |
| `--help` | `-h` | boolean | Show command help | `false` |
| `--version` | `-v` | boolean | Show CLI version | `false` |
| `--verbose` | | boolean | Enable verbose logging | `false` |

## Commands

### 1. `i3pm apps list`

**Description**: List all registered applications

**Usage**:
```bash
i3pm apps list [flags]
```

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--scope` | string | Filter by scope: `scoped`, `global`, `all` | `all` |
| `--workspace` | integer | Filter by preferred workspace (1-9) | none |
| `--format` | string | Output format: `table`, `json` | `table` |

**Examples**:
```bash
# List all applications (table format)
i3pm apps list

# List only scoped applications
i3pm apps list --scope=scoped

# List applications for workspace 1
i3pm apps list --workspace=1

# List all applications (JSON format)
i3pm apps list --format=json
```

**Output (table)**:
```
NAME              DISPLAY NAME       SCOPE     WORKSPACE  PACKAGE
vscode            VS Code            scoped    1          pkgs.vscode
firefox           Firefox            global    2          pkgs.firefox
ghostty-terminal  Ghostty Terminal   scoped    3          pkgs.alacritty
lazygit           Lazygit            scoped    3          pkgs.lazygit
```

**Output (JSON)**:
```json
{
  "version": "1.0.0",
  "count": 4,
  "applications": [
    {
      "name": "vscode",
      "display_name": "VS Code",
      "command": "code",
      "parameters": "$PROJECT_DIR",
      "scope": "scoped",
      "preferred_workspace": 1,
      "nix_package": "pkgs.vscode"
    },
    ...
  ]
}
```

**Exit Codes**:
- `0`: Success
- `1`: Registry not found or invalid JSON
- `2`: Invalid flags

---

### 2. `i3pm apps launch`

**Description**: Launch an application with project context

**Usage**:
```bash
i3pm apps launch <name> [flags]
```

**Arguments**:

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | ✅ | Application name from registry |

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--dry-run` | boolean | Show resolved command without executing | `false` |
| `--project` | string | Override active project (for testing) | current active |

**Examples**:
```bash
# Launch VS Code in active project
i3pm apps launch vscode

# Show resolved command without launching
i3pm apps launch vscode --dry-run

# Launch with specific project context
i3pm apps launch vscode --project=nixos
```

**Output (normal)**:
```
Launching VS Code in project: nixos
Command: code /etc/nixos
```

**Output (dry-run)**:
```
[DRY RUN] Would execute:
  Command: code
  Arguments: /etc/nixos
  Project: nixos (/etc/nixos)
  Workspace: 1
```

**Exit Codes**:
- `0`: Success (application launched)
- `1`: Application not found in registry
- `2`: Daemon not responding
- `3`: Project directory invalid
- `4`: Command not found in PATH
- `5`: Launch failed (other error)

---

### 3. `i3pm apps info`

**Description**: Show detailed information about an application

**Usage**:
```bash
i3pm apps info <name> [flags]
```

**Arguments**:

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | ✅ | Application name from registry |

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--resolve` | boolean | Show resolved variables for current context | `false` |
| `--format` | string | Output format: `table`, `json` | `table` |

**Examples**:
```bash
# Show application info
i3pm apps info vscode

# Show with resolved variables
i3pm apps info vscode --resolve

# JSON output
i3pm apps info vscode --format=json
```

**Output (table, --resolve)**:
```
Application: VS Code
Name: vscode
Command: code
Parameters: $PROJECT_DIR
Scope: scoped
Expected Class: Code
Preferred Workspace: 1
Icon: vscode
Package: pkgs.vscode
Multi-Instance: true
Fallback: skip

Current Context:
  Active Project: nixos
  Project Directory: /etc/nixos
  Session Name: nixos
  Resolved Command: code /etc/nixos
```

**Output (JSON)**:
```json
{
  "application": {
    "name": "vscode",
    "display_name": "VS Code",
    "command": "code",
    "parameters": "$PROJECT_DIR",
    "scope": "scoped",
    "expected_class": "Code",
    "preferred_workspace": 1,
    "icon": "vscode",
    "nix_package": "pkgs.vscode",
    "multi_instance": true,
    "fallback_behavior": "skip"
  },
  "context": {
    "project_name": "nixos",
    "project_dir": "/etc/nixos",
    "session_name": "nixos",
    "resolved_command": "code /etc/nixos"
  }
}
```

**Exit Codes**:
- `0`: Success
- `1`: Application not found
- `2`: Registry invalid

---

### 4. `i3pm apps edit`

**Description**: Open the registry JSON in $EDITOR

**Usage**:
```bash
i3pm apps edit [flags]
```

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--validate-after` | boolean | Validate registry after editing | `true` |

**Examples**:
```bash
# Edit registry (validates after save)
i3pm apps edit

# Edit without validation
i3pm apps edit --validate-after=false
```

**Behavior**:
1. Opens `~/.config/i3/application-registry.json` in `$EDITOR`
2. Waits for editor to close
3. If `--validate-after`, runs schema validation
4. Reports validation errors if found

**Output (success)**:
```
Opening registry in nvim...
Registry saved. Validation passed.
Run 'sudo nixos-rebuild switch' to apply changes.
```

**Output (validation error)**:
```
Opening registry in nvim...
Validation errors found:
  Line 15: Invalid field 'scopee' (did you mean 'scope'?)
  Line 23: preferred_workspace must be 1-9 (got: 10)

Fix errors and save again, or exit to revert.
```

**Exit Codes**:
- `0`: Success (valid changes saved)
- `1`: Validation failed
- `2`: $EDITOR not set
- `3`: Editor exited with error

---

### 5. `i3pm apps validate`

**Description**: Validate registry schema and application settings

**Usage**:
```bash
i3pm apps validate [flags]
```

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--fix` | boolean | Attempt to auto-fix common issues | `false` |
| `--check-paths` | boolean | Verify commands exist in PATH | `true` |
| `--check-icons` | boolean | Verify icon files/names exist | `false` |
| `--format` | string | Output format: `table`, `json` | `table` |

**Examples**:
```bash
# Validate registry
i3pm apps validate

# Validate and auto-fix
i3pm apps validate --fix

# Full validation (paths + icons)
i3pm apps validate --check-paths --check-icons
```

**Validation Checks**:

| Check | Level | Description |
|-------|-------|-------------|
| JSON syntax | ERROR | Valid JSON format |
| Schema compliance | ERROR | Matches registry-schema.json |
| Unique names | ERROR | No duplicate application names |
| Required fields | ERROR | name, display_name, command present |
| Parameter safety | ERROR | No shell metacharacters in parameters |
| Workspace range | ERROR | preferred_workspace is 1-9 |
| Command exists | WARNING | command is in $PATH |
| Icon exists | WARNING | icon resolves to file or theme |
| Expected class set | WARNING | scoped apps should have expected_class |

**Output (table)**:
```
Registry Validation Report

✅ JSON syntax: Valid
✅ Schema compliance: Valid
✅ Unique names: Valid (15 applications)
⚠️  Command paths: 2 warnings
    - 'custom-tool' not found in PATH
    - 'experimental' not found in PATH
✅ Parameter safety: Valid
⚠️  Icon resolution: 1 warning
    - 'custom-icon' not found in icon theme

Summary: 13 passed, 3 warnings, 0 errors
```

**Output (JSON)**:
```json
{
  "valid": true,
  "checks": {
    "json_syntax": { "passed": true },
    "schema_compliance": { "passed": true },
    "unique_names": { "passed": true, "count": 15 },
    "command_paths": {
      "passed": false,
      "warnings": [
        { "app": "custom-tool", "message": "Command not found in PATH" }
      ]
    }
  },
  "summary": {
    "passed": 13,
    "warnings": 3,
    "errors": 0
  }
}
```

**Auto-Fix (--fix)**:
- Removes duplicate applications (keeps first occurrence)
- Clamps out-of-range workspace numbers to 1-9
- Removes unsupported fields
- Formats JSON with consistent indentation

**Exit Codes**:
- `0`: Valid (or fixed if --fix used)
- `1`: Validation errors (unfixable)
- `2`: Registry file not found

---

### 6. `i3pm apps add`

**Description**: Add a new application to the registry interactively

**Usage**:
```bash
i3pm apps add [flags]
```

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--non-interactive` | boolean | Use CLI args instead of prompts | `false` |
| `--name` | string | Application name (kebab-case) | prompted |
| `--display-name` | string | Display name | prompted |
| `--command` | string | Executable command | prompted |
| `--scope` | string | Scope: scoped/global | prompted |
| `--workspace` | integer | Preferred workspace (1-9) | prompted |

**Examples**:
```bash
# Interactive mode (prompts for all fields)
i3pm apps add

# Non-interactive mode (all args provided)
i3pm apps add --non-interactive \
  --name=custom-app \
  --display-name="Custom App" \
  --command=custom-bin \
  --scope=scoped \
  --workspace=5
```

**Interactive Prompts**:
```
Add Application to Registry

Application name (kebab-case): vscode
Display name: VS Code
Executable command: code
Parameters (optional, use $PROJECT_DIR, $PROJECT_NAME, etc.): $PROJECT_DIR
Scope [scoped/global]: scoped
Expected WM_CLASS (optional): Code
Preferred workspace [1-9]: 1
Icon name or path (optional): vscode
NixOS package (optional, e.g., pkgs.vscode): pkgs.vscode
Allow multiple instances [y/N]: y
Fallback behavior [skip/use_home/error]: skip

Summary:
  Name: vscode
  Display: VS Code
  Command: code $PROJECT_DIR
  Scope: scoped
  Workspace: 1

Add this application? [Y/n]: y

✅ Application 'vscode' added successfully.
Run 'sudo nixos-rebuild switch' to apply changes.
```

**Exit Codes**:
- `0`: Success
- `1`: Application already exists
- `2`: Invalid input
- `3`: User cancelled

---

### 7. `i3pm apps remove`

**Description**: Remove an application from the registry

**Usage**:
```bash
i3pm apps remove <name> [flags]
```

**Arguments**:

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | ✅ | Application name to remove |

**Flags**:

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--force` | boolean | Skip confirmation prompt | `false` |

**Examples**:
```bash
# Remove with confirmation
i3pm apps remove vscode

# Remove without confirmation
i3pm apps remove vscode --force
```

**Output**:
```
Remove application 'vscode' (VS Code)?
This will delete the registry entry and desktop file on next rebuild.

Are you sure? [y/N]: y

✅ Application 'vscode' removed from registry.
Run 'sudo nixos-rebuild switch' to apply changes.
```

**Exit Codes**:
- `0`: Success
- `1`: Application not found
- `2`: User cancelled

---

## Error Handling

All commands follow consistent error handling:

1. **Validation Errors**: Clear message with field name and expected format
2. **Daemon Errors**: Indicate daemon not running, suggest systemctl status
3. **File Errors**: Show path and permission issue
4. **Command Not Found**: Suggest package installation or PATH issue

**Error Message Format**:
```
Error: <brief description>
  <detailed explanation>
  <suggested action>

Example:
Error: Application 'vscode' not found in registry
  Registry contains 15 applications.
  Run 'i3pm apps list' to see available applications.
```

---

## Logging

Commands log to `~/.local/state/i3pm-apps.log`:

**Log Format**:
```
[2025-10-24T14:32:45-04:00] INFO Command: i3pm apps launch vscode
[2025-10-24T14:32:45-04:00] INFO Project context: nixos (/etc/nixos)
[2025-10-24T14:32:45-04:00] INFO Resolved: code /etc/nixos
[2025-10-24T14:32:45-04:00] INFO Launched successfully (PID: 12345)
```

**Log Levels**:
- `ERROR`: Command failures, validation errors
- `WARN`: Missing optional fields, deprecated usage
- `INFO`: Command execution, project context
- `DEBUG`: Variable substitution, path resolution (when --verbose)

---

## Integration with Daemon

Commands that query project context:
- `i3pm apps launch` - Queries active project
- `i3pm apps info --resolve` - Shows current context

**IPC Protocol**:
- Method: `get_current_project()`
- Socket: `/run/user/<uid>/i3-project-daemon/ipc.sock`
- Timeout: 5 seconds
- Fallback: Global mode if daemon not available

---

## Testing Commands

All commands support `--dry-run` or equivalent for testing without side effects:

| Command | Testing Flag | Behavior |
|---------|-------------|----------|
| `launch` | `--dry-run` | Show command without executing |
| `add` | `--dry-run` | Show JSON without saving |
| `remove` | `--dry-run` | Show removal without deleting |
| `edit` | `--dry-run` | Show path without opening editor |
| `validate` | `--fix --dry-run` | Show fixes without applying |

---

## Version Compatibility

| Registry Version | CLI Version | Compatibility |
|-----------------|-------------|---------------|
| 1.0.0 | 1.0.x | ✅ Fully compatible |
| 1.1.0 | 1.0.x | ⚠️ New fields ignored |
| 2.0.0 | 1.0.x | ❌ Breaking changes |

**Version Check**:
```bash
i3pm apps validate  # Warns if version mismatch
```

---

**CLI API Status**: ✅ COMPLETE
**Implementation**: Deno/TypeScript with `parseArgs()` from `@std/cli/parse-args`
