# CLI Commands: Configuration Management

**Feature**: 047-create-a-new
**CLI Tool**: `i3pm` (Deno-based, extends existing CLI)

## Overview

This document defines the command-line interface for dynamic Sway configuration management, extending the existing `i3pm` CLI tool.

## Command Hierarchy

```
i3pm config
├── reload              Hot-reload configuration files
├── validate            Validate configuration syntax/semantics
├── rollback            Rollback to previous version
├── show                Display current configuration
├── list-versions       List available configuration versions
├── conflicts           Show configuration conflicts
├── watch              Enable/disable file watcher
└── edit               Open configuration file in editor
```

---

## Commands

### `i3pm config reload`

Hot-reload configuration files without restarting Sway or daemon.

**Usage**:
```bash
i3pm config reload [OPTIONS]
```

**Options**:
- `--files <list>`: Comma-separated list of files to reload (keybindings, window-rules, workspace-assignments)
  - Default: all files
  - Example: `--files keybindings,window-rules`
- `--validate-only`: Only validate, don't apply changes
  - Boolean flag, default: false
- `--skip-commit`: Skip git commit after successful reload
  - Boolean flag, default: false
- `--json`: Output result in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# Reload all configuration files
i3pm config reload

# Reload only keybindings
i3pm config reload --files keybindings

# Validate without applying
i3pm config reload --validate-only

# Reload with JSON output
i3pm config reload --json
```

**Output (Human-Readable)**:
```
✅ Configuration reloaded successfully

Reload Time: 1.25 seconds
Files Reloaded:
  • keybindings.toml
  • window-rules.json

Validation Summary:
  ✅ 0 syntax errors
  ✅ 0 semantic errors
  ⚠️  1 warning

Warnings:
  keybindings.toml:8
    Keybinding Control+1 defined in both Nix and runtime config
    → Using runtime config (higher precedence)

Commit: a1b2c3d (Auto-generated: Configuration reload)
```

**Output (JSON)**:
```json
{
  "success": true,
  "reload_time_ms": 1250,
  "files_reloaded": ["keybindings", "window-rules"],
  "validation_summary": {
    "syntax_errors": 0,
    "semantic_errors": 0,
    "warnings": 1
  },
  "warnings": [
    {
      "file_path": "~/.config/sway/keybindings.toml",
      "line_number": 8,
      "error_type": "conflict",
      "message": "Keybinding Control+1 defined in both Nix and runtime config"
    }
  ],
  "commit_hash": "a1b2c3d4e5f6"
}
```

**Error Output**:
```
❌ Configuration validation failed

Errors:
  keybindings.toml:15 [Syntax Error]
    Invalid key combo: Mod++Return
    → Suggestion: Use single + between modifiers (e.g., Mod+Return)

  window-rules.json:23 [Semantic Error]
    Referenced workspace 15 does not exist
    → Suggestion: Available workspaces: 1-9

Configuration NOT reloaded. Fix errors and try again.
```

**Exit Codes**:
- `0`: Success
- `1`: Validation failed
- `2`: Reload failed (after validation passed)
- `3`: Daemon not running

---

### `i3pm config validate`

Validate configuration files without applying changes.

**Usage**:
```bash
i3pm config validate [OPTIONS]
```

**Options**:
- `--files <list>`: Comma-separated list of files to validate
  - Default: all files
- `--strict`: Treat warnings as errors
  - Boolean flag, default: false
- `--json`: Output in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# Validate all files
i3pm config validate

# Validate specific file with strict mode
i3pm config validate --files keybindings --strict

# Get JSON output for CI/CD
i3pm config validate --json
```

**Output (Success)**:
```
✅ Configuration valid

Validation Time: 85ms
Files Validated:
  • keybindings.toml
  • window-rules.json
  • workspace-assignments.json

Summary:
  ✅ 0 syntax errors
  ✅ 0 semantic errors
  ⚠️  2 warnings

Warnings:
  window-rules.json [Semantic]
    Window rule for app_id 'nonexistent-app' has never matched
    → Verify app_id is correct or remove unused rule
```

**Exit Codes**:
- `0`: Valid (no errors, warnings allowed unless --strict)
- `1`: Invalid (syntax or semantic errors)
- `3`: Daemon not running

---

### `i3pm config rollback`

Rollback to a previous configuration version.

**Usage**:
```bash
i3pm config rollback <COMMIT_HASH> [OPTIONS]
```

**Arguments**:
- `<COMMIT_HASH>`: Git commit SHA to rollback to (accepts short or long form)

**Options**:
- `--no-reload`: Skip automatic reload after rollback
  - Boolean flag, default: false (auto-reload enabled)
- `--json`: Output in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# Rollback to specific commit
i3pm config rollback a1b2c3d

# Rollback without auto-reload
i3pm config rollback a1b2c3d --no-reload

# Rollback with JSON output
i3pm config rollback a1b2c3d --json
```

**Output**:
```
🔄 Rolling back configuration...

Previous Version: f9e8d7c (Update keybindings for project workflow)
Restored Version: a1b2c3d (Add floating rule for calculator)

Files Restored:
  • window-rules.json

✅ Rollback complete (2.1 seconds)
✅ Configuration reloaded automatically
```

**Exit Codes**:
- `0`: Success
- `1`: Invalid commit hash
- `2`: Git checkout failed
- `3`: Rollback succeeded but reload failed

---

### `i3pm config show`

Display current active configuration with source attribution.

**Usage**:
```bash
i3pm config show [OPTIONS]
```

**Options**:
- `--category <name>`: Filter by category (keybindings, window-rules, workspaces, all)
  - Default: all
- `--sources`: Include source attribution
  - Boolean flag, default: true
- `--project <name>`: Show with specific project context
  - String, default: current active project
- `--json`: Output in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# Show all configuration
i3pm config show

# Show only keybindings
i3pm config show --category keybindings

# Show configuration for specific project
i3pm config show --project nixos

# Get JSON output
i3pm config show --json
```

**Output (Table View)**:
```
═══════════════════════════════════════════════════════════════
                    KEYBINDINGS
═══════════════════════════════════════════════════════════════
Key Combo     Command                Source    File
───────────────────────────────────────────────────────────────
Mod+Return    exec terminal          nix       sway.nix:22
Control+1     workspace number 1     runtime   keybindings.toml:5
Mod+c         exec vscode            runtime   keybindings.toml:12
───────────────────────────────────────────────────────────────

═══════════════════════════════════════════════════════════════
                    WINDOW RULES
═══════════════════════════════════════════════════════════════
ID         Criteria                   Actions              Scope
───────────────────────────────────────────────────────────────
rule-001   app_id: Calculator         floating enable      global
rule-002   title: ^Firefox.*          workspace 3          global
───────────────────────────────────────────────────────────────

Active Project: nixos
Config Version: a1b2c3d (2025-10-29 14:30:00)
```

**Exit Codes**:
- `0`: Success
- `3`: Daemon not running

---

### `i3pm config list-versions`

List available configuration versions from git history.

**Usage**:
```bash
i3pm config list-versions [OPTIONS]
```

**Options**:
- `--limit <num>`: Maximum versions to display
  - Integer, default: 20
- `--since <date>`: Only show versions after this date (ISO 8601 format)
  - String, default: none (all history)
- `--json`: Output in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# List recent versions
i3pm config list-versions

# Limit to 5 most recent
i3pm config list-versions --limit 5

# Show versions since Oct 1, 2025
i3pm config list-versions --since 2025-10-01T00:00:00Z

# JSON output
i3pm config list-versions --json
```

**Output**:
```
═══════════════════════════════════════════════════════════════
              CONFIGURATION VERSIONS
═══════════════════════════════════════════════════════════════
Commit    Date                Message                    Files
───────────────────────────────────────────────────────────────
a1b2c3d * 2025-10-29 14:30    Update keybindings         keybindings.toml
f9e8d7c   2025-10-28 10:15    Add floating rule          window-rules.json
e8d7c6b   2025-10-27 16:45    Workspace assignments      workspace-assignments.json
───────────────────────────────────────────────────────────────

* = Currently active version
Total versions: 47
```

**Exit Codes**:
- `0`: Success
- `3`: Git not available or no version history

---

### `i3pm config conflicts`

Display configuration conflicts across precedence levels.

**Usage**:
```bash
i3pm config conflicts [OPTIONS]
```

**Options**:
- `--json`: Output in JSON format
  - Boolean flag, default: false

**Examples**:
```bash
# Show conflicts
i3pm config conflicts

# JSON output
i3pm config conflicts --json
```

**Output**:
```
═══════════════════════════════════════════════════════════════
                 CONFIGURATION CONFLICTS
═══════════════════════════════════════════════════════════════

⚠️  Keybinding: Control+1

  Source      Value                    File                Active
  ────────────────────────────────────────────────────────────
  nix         workspace number 1       sway.nix:45         ✗
  runtime     workspace number 1       keybindings.toml:5  ✓

  Resolution: Runtime config takes precedence (higher priority)
  Severity: Warning

───────────────────────────────────────────────────────────────

Total Conflicts: 1
```

**Exit Codes**:
- `0`: No conflicts or only warnings
- `1`: Critical conflicts found

---

### `i3pm config watch`

Enable or disable file watcher for automatic reload.

**Usage**:
```bash
i3pm config watch <ACTION> [OPTIONS]
```

**Arguments**:
- `<ACTION>`: start | stop | status

**Options (for `start`)**:
- `--debounce <ms>`: Debounce delay for rapid changes (milliseconds)
  - Integer, default: 500

**Examples**:
```bash
# Start file watcher
i3pm config watch start

# Start with custom debounce
i3pm config watch start --debounce 1000

# Stop file watcher
i3pm config watch stop

# Check watcher status
i3pm config watch status
```

**Output (start)**:
```
✅ File watcher started

Watching:
  • ~/.config/sway/keybindings.toml
  • ~/.config/sway/window-rules.json
  • ~/.config/sway/workspace-assignments.json

Debounce: 500ms

Configuration will reload automatically when files change.
```

**Exit Codes**:
- `0`: Success
- `3`: Daemon not running

---

### `i3pm config edit`

Open configuration file in default editor.

**Usage**:
```bash
i3pm config edit <FILE>
```

**Arguments**:
- `<FILE>`: keybindings | window-rules | workspace-assignments

**Examples**:
```bash
# Edit keybindings
i3pm config edit keybindings

# Edit window rules
i3pm config edit window-rules
```

**Behavior**:
- Opens file in `$EDITOR` (fallback: nano)
- Validates after editor closes
- Prompts to reload if valid
- Displays errors if validation fails

**Output**:
```
Opening ~/.config/sway/keybindings.toml in nvim...

[Editor opens...]

✅ Configuration valid
Reload now? (y/N): y

✅ Configuration reloaded successfully
```

**Exit Codes**:
- `0`: Success
- `1`: Validation failed after edit
- `2`: User declined reload
- `3`: Editor not found

---

## Global Options

These options apply to all `i3pm config` commands:

- `--help`, `-h`: Show help message
- `--version`, `-v`: Show version information
- `--quiet`, `-q`: Suppress non-error output
- `--verbose`: Show detailed debug information

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `I3PM_DAEMON_SOCKET` | Path to daemon Unix socket | `~/.cache/i3pm/daemon.sock` |
| `I3PM_CONFIG_DIR` | Path to configuration directory | `~/.config/sway` |
| `EDITOR` | Text editor for `config edit` | `nano` |

---

## Exit Code Reference

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Validation failed or invalid input |
| `2` | Operation failed after validation |
| `3` | Daemon not running or external tool unavailable |
| `4` | User cancelled operation |

---

## Integration Examples

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit - validate config before commit

if i3pm config validate --strict; then
  echo "✅ Configuration valid"
  exit 0
else
  echo "❌ Configuration validation failed. Fix errors before committing."
  exit 1
fi
```

### Automated Reload on File Save (Vim)

```vim
" In ~/.config/nvim/after/ftplugin/toml.vim
autocmd BufWritePost keybindings.toml silent !i3pm config reload --files keybindings
```

### CI/CD Validation

```yaml
# .github/workflows/validate-config.yml
- name: Validate Sway configuration
  run: |
    i3pm config validate --strict --json > validation-result.json
    if [ $? -ne 0 ]; then
      cat validation-result.json
      exit 1
    fi
```

---

## Success Criteria Mapping

| Success Criteria | Related Commands |
|------------------|------------------|
| SC-001: Reload <5s | `config reload` (target: <2s reload component) |
| SC-002: Reload <3s | `config reload` (window rules reload) |
| SC-006: 100% syntax | `config validate` (validation enforcement) |
| SC-007: Rollback <3s | `config rollback` (target: <3s total) |
| SC-013: Show config | `config show`, `config conflicts` |

---

## Implementation Notes

- All commands use existing `DaemonClient` for IPC communication
- JSON output follows consistent schema across all commands
- Human-readable output uses Rich library for tables and formatting
- Commands fail fast with clear error messages
- Help text generated automatically from command metadata
