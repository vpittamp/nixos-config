# Project System Logging Format Specification

**Version**: 1.0
**Date**: 2025-10-19
**Status**: Phase 1 - Design

## Overview

The i3 project management system uses structured text-based logging for all operations, i3 IPC commands, event subscriptions, and errors. Logs are written to `~/.config/i3/project-system.log` with automatic rotation at 10MB keeping 5 historical files.

## Log Entry Format

### Structure

```
[TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
```

### Field Specifications

| Field | Format | Description | Required | Max Length |
|-------|--------|-------------|----------|-----------|
| TIMESTAMP | `YYYY-MM-DD HH:MM:SS` | Local time (not UTC) | Yes | 19 chars |
| LEVEL | `DEBUG\|INFO\|WARN\|ERROR` | Log severity level | Yes | 5 chars |
| COMPONENT | Alphanumeric + dash | Script or module name | Yes | 30 chars |
| MESSAGE | Free-form text | Log message with context | Yes | 500 chars |

### Regular Expression

```regex
^\[([\d]{4}-[\d]{2}-[\d]{2} [\d]{2}:[\d]{2}:[\d]{2})\] \[(DEBUG|INFO|WARN|ERROR)\] \[([a-zA-Z0-9-]+)\] (.+)$
```

## Log Levels

### DEBUG

**Purpose**: Detailed information for troubleshooting and development

**When to use**:
- i3-msg commands with full arguments
- JSON file reads with file paths
- jq filter expressions
- Timing information for operations
- i3 IPC responses (full JSON in debug mode)

**Examples**:
```
[2025-10-19 14:32:15] [DEBUG] [project-switch] Reading project config: /home/user/.config/i3/projects/nixos.json
[2025-10-19 14:32:15] [DEBUG] [i3-ipc] i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:stacks"]))'
[2025-10-19 14:32:15] [DEBUG] [i3-cmd] i3-msg '[con_mark="project:stacks"] move scratchpad'
[2025-10-19 14:32:16] [DEBUG] [signal] pkill -RTMIN+10 i3blocks
[2025-10-19 14:32:16] [DEBUG] [timing] project-switch completed in 0.823s
```

### INFO

**Purpose**: Normal operation events that indicate system is working correctly

**When to use**:
- Project switches
- Project creation/deletion
- Window marking
- Application launches
- Configuration reloads
- Successful operations

**Examples**:
```
[2025-10-19 14:32:15] [INFO] [project-switch] Switching to project: nixos
[2025-10-19 14:32:15] [INFO] [project-switch] Hiding 8 windows from project: stacks
[2025-10-19 14:32:15] [INFO] [project-switch] Showing 5 windows from project: nixos
[2025-10-19 14:32:16] [INFO] [project-switch] Updated active project file
[2025-10-19 14:32:16] [INFO] [project-switch] Project switch completed
[2025-10-19 14:35:22] [INFO] [launch-code] Launched VS Code in project: nixos
[2025-10-19 14:38:10] [INFO] [project-create] Created project: api-gateway
```

### WARN

**Purpose**: Recoverable errors or unexpected conditions that don't prevent operation

**When to use**:
- Missing project directories (launch proceeds with warning)
- i3blocks not running (signal fails but project switches)
- Slow operations (>2 seconds)
- Orphaned window marks (project deleted but windows still marked)
- Malformed JSON (falls back to defaults)
- Concurrent operations (queueing or debouncing)

**Examples**:
```
[2025-10-19 14:40:15] [WARN] [project-switch] Project directory does not exist: /home/user/deleted-project
[2025-10-19 14:40:16] [WARN] [signal] i3blocks not running or failed to signal (pkill returned non-zero)
[2025-10-19 14:42:30] [WARN] [project-switch] Project switch took 2.3s (expected <1s)
[2025-10-19 14:45:00] [WARN] [validation] Window marked with project:deleted but project config not found
[2025-10-19 14:50:00] [WARN] [active-project] Malformed JSON in active-project file, treating as no active project
```

### ERROR

**Purpose**: Failures that prevent operation from completing

**When to use**:
- Command not found (missing dependencies)
- File write failures (permissions, disk full)
- Invalid JSON that can't be recovered
- i3 IPC socket unavailable
- Required directories missing
- Configuration validation failures

**Examples**:
```
[2025-10-19 14:55:00] [ERROR] [launch-code] Failed to launch VS Code: code command not found in PATH
[2025-10-19 14:55:30] [ERROR] [project-switch] Failed to write active-project file: Permission denied
[2025-10-19 14:56:00] [ERROR] [i3-ipc] i3 IPC socket not found: /run/user/1000/i3/ipc-socket.*
[2025-10-19 14:56:30] [ERROR] [project-create] Project config directory missing: ~/.config/i3/projects/
[2025-10-19 14:57:00] [ERROR] [validation] Project config validation failed: missing required field 'name'
```

## Component Names

### Standard Components

| Component | Description | Scripts |
|-----------|-------------|---------|
| `project-create` | Project creation | project-create.sh |
| `project-delete` | Project deletion | project-delete.sh |
| `project-switch` | Project switching | project-switch.sh |
| `project-clear` | Clear active project | project-clear.sh |
| `project-list` | List all projects | project-list.sh |
| `project-current` | Show current project | project-current.sh |
| `launch-code` | VS Code launcher | launch-code.sh |
| `launch-ghostty` | Ghostty terminal launcher | launch-ghostty.sh |
| `launch-lazygit` | lazygit launcher | launch-lazygit.sh |
| `launch-yazi` | yazi file manager launcher | launch-yazi.sh |
| `project-indicator` | i3blocks status bar | i3blocks/scripts/project.sh |
| `i3-ipc` | i3 IPC queries | All scripts (i3-msg calls) |
| `i3-cmd` | i3 commands | All scripts (i3-msg commands) |
| `validation` | Config validation | project-validate.sh |
| `signal` | Signal delivery | All scripts (pkill calls) |
| `timing` | Performance metrics | All scripts (timing info) |

### Component Naming Rules

- Use lowercase with hyphens
- Match script name (without .sh extension)
- Use specific names (not generic like "script" or "tool")
- Use `i3-ipc` for all `i3-msg -t get_*` queries
- Use `i3-cmd` for all `i3-msg` commands (not queries)

## Message Format Guidelines

### Required Information

Every log message SHOULD include:
- **What happened** (action performed)
- **Context** (project name, file path, window ID)
- **Outcome** (success, failure, warning)

### Optional Information

Log messages MAY include:
- **Why** (rationale for decision)
- **Timing** (how long operation took)
- **Alternatives** (what was tried before this)

### Message Examples

**Good Messages** (informative, actionable):
```
[INFO] [project-switch] Switching to project: nixos
[DEBUG] [project-switch] Reading project config: /home/user/.config/i3/projects/nixos.json
[DEBUG] [i3-ipc] i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:stacks"]))'
[WARN] [signal] i3blocks not running (pkill returned 1)
[ERROR] [launch-code] Failed to launch VS Code: code command not found in PATH
```

**Bad Messages** (too vague, not actionable):
```
[INFO] [script] Operation successful
[DEBUG] [tool] Command executed
[WARN] [system] Something went wrong
[ERROR] [app] Failed
```

## Special Message Formats

### i3 IPC Queries

Format: `i3-msg -t TYPE ARGS | processing`

```
[DEBUG] [i3-ipc] i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'
[DEBUG] [i3-ipc] i3-msg -t get_workspaces | jq '.[] | select(.focused == true)'
```

### i3 Commands

Format: `i3-msg 'COMMAND'`

```
[DEBUG] [i3-cmd] i3-msg '[con_mark="project:stacks"] move scratchpad'
[DEBUG] [i3-cmd] i3-msg '[con_mark="project:nixos"] scratchpad show'
[DEBUG] [i3-cmd] i3-msg '[id=12345] mark --add "project:nixos"'
```

### Timing Information

Format: `Operation completed in Xs` or `Operation took Xs (expected <Ys)`

```
[DEBUG] [timing] project-switch completed in 0.823s
[WARN] [timing] project-switch took 2.3s (expected <1s)
```

### File Operations

Format: `Action: /path/to/file`

```
[DEBUG] [project-switch] Reading project config: /home/user/.config/i3/projects/nixos.json
[DEBUG] [project-switch] Writing active-project: /home/user/.config/i3/active-project
[ERROR] [project-create] Failed to write project config: /home/user/.config/i3/projects/test.json (Permission denied)
```

### Validation Errors

Format: `Validation failed: specific reason`

```
[ERROR] [validation] Project config validation failed: missing required field 'name'
[ERROR] [validation] Invalid project name: 'my project' (spaces not allowed)
[WARN] [validation] Project directory does not exist: /home/user/missing
```

## Debug Mode

When debug mode is enabled (via environment variable `I3_PROJECT_DEBUG=1`):

### Additional Logging

- Full i3 IPC JSON responses (truncated to 1000 chars in normal mode)
- Detailed timing for every operation (not just slow operations)
- State snapshots (current project, window counts, workspace assignments)
- Function entry/exit tracing

### Example Debug Output

```
[DEBUG] [project-switch] === BEGIN project-switch ===
[DEBUG] [project-switch] Current active project: stacks
[DEBUG] [project-switch] Target project: nixos
[DEBUG] [i3-ipc] i3-msg -t get_tree
[DEBUG] [i3-ipc] Response: {"id":123,"type":"root","nodes":[...]} (2048 chars)
[DEBUG] [i3-ipc] Found 8 windows with mark project:stacks
[DEBUG] [timing] i3-msg query took 0.045s
[DEBUG] [i3-cmd] i3-msg '[con_mark="project:stacks"] move scratchpad'
[DEBUG] [timing] i3-msg command took 0.023s
[DEBUG] [project-switch] State snapshot: active=nixos, windows_hidden=8, windows_shown=5
[DEBUG] [project-switch] === END project-switch (total 0.823s) ===
```

## Log Rotation

### Rotation Strategy

- **Trigger**: When log file exceeds 10MB
- **Historical files**: Keep 5 rotated files
- **Naming**: `project-system.log.N` (N=1 to 5, 1 is most recent)

### Rotation Process

```bash
# When project-system.log > 10MB:
mv project-system.log.4 project-system.log.5  # Oldest to delete next rotation
mv project-system.log.3 project-system.log.4
mv project-system.log.2 project-system.log.3
mv project-system.log.1 project-system.log.2
mv project-system.log project-system.log.1    # Current becomes historical
touch project-system.log                       # New empty log
```

### Rotation Log Entry

```
[INFO] [rotation] Log file rotated (size: 10.2MB, kept: 5 historical files)
```

## Log Viewer Usage

### Command: `project-logs`

**Synopsis**:
```bash
project-logs [OPTIONS]
```

**Options**:
- `--tail N` - Show last N lines (default: 50)
- `--level LEVEL` - Filter by log level (DEBUG, INFO, WARN, ERROR)
- `--component NAME` - Filter by component name
- `--follow` - Tail log file in real-time (like `tail -f`)
- `--since TIME` - Show logs since timestamp (YYYY-MM-DD HH:MM:SS)
- `--color` - Enable color coding by log level (default: auto)

**Examples**:
```bash
# Show last 50 lines with color
project-logs

# Follow live logs
project-logs --follow

# Show all errors
project-logs --level ERROR

# Show project-switch component only
project-logs --component project-switch

# Show last 100 lines from project-switch
project-logs --tail 100 --component project-switch

# Show errors and warnings from last hour
project-logs --level WARN --level ERROR --since "2025-10-19 14:00:00"
```

### Color Coding

When color is enabled:
- **DEBUG**: Gray/dim
- **INFO**: White/default
- **WARN**: Yellow
- **ERROR**: Red

## Logging Implementation

### Bash Function Template

```bash
# Common logging function (in i3-project-common.sh)
log() {
  local level="$1"
  local component="$2"
  local message="$3"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo "[$timestamp] [$level] [$component] $message" >> "$LOG_FILE"
}

# Convenience wrappers
log_debug() { log "DEBUG" "$COMPONENT" "$1"; }
log_info()  { log "INFO"  "$COMPONENT" "$1"; }
log_warn()  { log "WARN"  "$COMPONENT" "$1"; }
log_error() { log "ERROR" "$COMPONENT" "$1"; }

# Usage in scripts
COMPONENT="project-switch"
log_info "Switching to project: $project_name"
log_debug "Reading project config: $config_file"
log_error "Failed to write active-project file: $error_message"
```

### Performance Considerations

- Log writes are **non-blocking** (append with `>>`, no locks)
- File rotation is **atomic** (rename operations)
- Debug mode adds ~5-10% overhead (acceptable for troubleshooting)
- Log filtering happens at **display time** (grep/awk), not write time

## Privacy & Security

### Sensitive Information

**Do NOT log**:
- Passwords or secrets
- Full file contents (log paths only)
- Personal identifiable information beyond usernames

**May log with caution**:
- Project names (may be client-confidential)
- Directory paths (may reveal system structure)
- Window titles (may contain sensitive data)

### Log Permissions

- Log file: `600` (user read/write only)
- Log directory: `700` (user access only)
- No world-readable or group-readable logs

## Future Enhancements

### Structured JSON Logging (Version 2.0)

```json
{
  "timestamp": "2025-10-19T14:32:15-04:00",
  "level": "INFO",
  "component": "project-switch",
  "message": "Switching to project: nixos",
  "context": {
    "from_project": "stacks",
    "to_project": "nixos",
    "windows_hidden": 8,
    "windows_shown": 5,
    "duration_ms": 823
  }
}
```

### Remote Logging

- Send logs to centralized logging server (syslog, Loki)
- Useful for multi-user Hetzner deployment

### Log Analysis

- Automated parsing to detect patterns (frequent errors, slow operations)
- Performance dashboards (average switch time, window counts)
- Alert on error rates exceeding threshold

---

**Version**: 1.0
**Last Updated**: 2025-10-19
**Status**: Active
