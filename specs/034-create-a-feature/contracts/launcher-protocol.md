# Launcher Wrapper Protocol Specification

**Feature**: 034-create-a-feature
**Version**: 1.0.0
**Date**: 2025-10-24

## Overview

The launcher wrapper script (`app-launcher-wrapper.sh`) is the runtime execution layer that bridges desktop files, the application registry, and the i3pm daemon. It performs variable resolution, validation, and secure command execution.

## Invocation

### Desktop File Integration

**Desktop Entry Exec Line**:
```ini
Exec=/home/user/.local/bin/app-launcher-wrapper.sh <app-name>
```

**Example**:
```ini
Exec=/home/user/.local/bin/app-launcher-wrapper.sh vscode
```

### CLI Integration

**Direct Invocation**:
```bash
~/.local/bin/app-launcher-wrapper.sh <app-name>
```

**Via i3pm CLI**:
```bash
i3pm apps launch <app-name>
```

## Execution Flow

```
1. Input: app-name
      ↓
2. Load registry JSON
      ↓
3. Find application entry
      ↓
4. Query daemon for project
      ↓
5. Load project config
      ↓
6. Create variable context
      ↓
7. Validate directory
      ↓
8. Substitute variables
      ↓
9. Build argument array
      ↓
10. Log launch
      ↓
11. Execute command
      ↓
12. Exit with command status
```

## Input/Output Contract

### Input

**Arguments**:
```bash
$1: Application name (required)
```

**Environment Variables** (optional):
```bash
DRY_RUN=1          # Show resolved command without executing
DEBUG=1            # Enable verbose logging
FALLBACK=skip      # Override fallback behavior
```

### Output

**Stdout** (normal mode):
```
(no output - application launches in background)
```

**Stdout** (DRY_RUN=1):
```
[DRY RUN] Would execute:
  Command: code
  Arguments: /etc/nixos
  Project: nixos (/etc/nixos)
```

**Stderr** (errors):
```
Error: Application 'vscode' not found in registry
Registry: /home/user/.config/i3/application-registry.json
```

### Exit Codes

| Code | Meaning | Recovery Action |
|------|---------|-----------------|
| 0 | Success | - |
| 1 | Application not found in registry | Check application name |
| 2 | Registry file not found/invalid | Run `sudo nixos-rebuild switch` |
| 3 | Project directory validation failed | Check project config |
| 4 | Command not found in PATH | Install package or check spelling |
| 5 | Daemon query failed | Check daemon: `systemctl --user status i3-project-event-listener` |
| 126 | Permission denied | Check execute permission on command |
| 127 | Command not executable | Verify command exists in PATH |

## Variable Substitution

### Supported Variables

| Variable | Source | Example Value | Description |
|----------|--------|---------------|-------------|
| `$PROJECT_NAME` | Daemon query | `"nixos"` | Active project name |
| `$PROJECT_DIR` | Project config | `"/etc/nixos"` | Project directory path |
| `$SESSION_NAME` | project_name | `"nixos"` | Session identifier (same as project name) |
| `$WORKSPACE` | Registry | `1` | Target workspace number |
| `$HOME` | Environment | `"/home/user"` | User home directory |
| `$PROJECT_DISPLAY_NAME` | Project config | `"NixOS"` | Human-readable project name |
| `$PROJECT_ICON` | Project config | `""` | Project icon |

### Substitution Rules

1. **Replace variables left-to-right** (no recursive expansion)
2. **Preserve literal dollar signs** (e.g., `\$` → `$`)
3. **Empty variables substitute to empty string** (unless fallback active)
4. **Unknown variables remain unchanged** (e.g., `$UNKNOWN` → `$UNKNOWN`)

### Examples

**Input**:
```json
{
  "command": "code",
  "parameters": "$PROJECT_DIR"
}
```

**Context**:
```json
{
  "project_dir": "/etc/nixos"
}
```

**Output**:
```bash
exec code "/etc/nixos"
```

---

**Input**:
```json
{
  "command": "ghostty",
  "parameters": "-e lazygit --work-tree=$PROJECT_DIR --git-dir=$PROJECT_DIR/.git"
}
```

**Context**:
```json
{
  "project_dir": "/home/user/My Projects/stacks"
}
```

**Output**:
```bash
exec ghostty "-e" "lazygit" "--work-tree=/home/user/My Projects/stacks" "--git-dir=/home/user/My Projects/stacks/.git"
```

## Validation

### Registry Validation

**Checks**:
1. Registry file exists at `~/.config/i3/application-registry.json`
2. Valid JSON syntax
3. Application entry exists with matching `name`
4. Required fields present: `command`, `display_name`

**Error Messages**:
```bash
Error: Registry file not found
  Path: /home/user/.config/i3/application-registry.json
  Action: Run 'sudo nixos-rebuild switch' to generate registry

Error: Invalid JSON in registry
  Path: /home/user/.config/i3/application-registry.json
  Line: 15
  Action: Validate JSON syntax

Error: Application 'vscode' not found
  Registry contains: firefox, ghostty, lazygit
  Action: Check application name or run 'i3pm apps list'
```

### Directory Validation

**Checks**:
1. Directory is absolute path (starts with `/`)
2. Directory exists on filesystem
3. No newlines, null bytes, or shell metacharacters

**Validation Function**:
```bash
validate_directory() {
    local dir="$1"

    # Must be non-empty
    [[ -n "$dir" ]] || return 1

    # Must be absolute path
    [[ "$dir" = /* ]] || return 1

    # Must exist
    [[ -d "$dir" ]] || return 1

    # Must not contain newlines
    [[ "$dir" != *$'\n'* ]] || return 1

    # Must not contain null bytes
    [[ "$dir" != *$'\0'* ]] || return 1

    return 0
}
```

**Error Messages**:
```bash
Error: Invalid project directory
  Directory: relative/path
  Reason: Not an absolute path
  Action: Project config must use absolute paths

Error: Project directory not found
  Directory: /nonexistent/path
  Project: nixos
  Action: Check project config or directory existence
```

### Command Validation

**Checks**:
1. Command exists in PATH
2. Command is executable

**Validation Function**:
```bash
validate_command() {
    local cmd="$1"

    # Check if command exists
    command -v "$cmd" &>/dev/null || return 1

    return 0
}
```

**Error Messages**:
```bash
Error: Command not found
  Command: code
  Package: pkgs.vscode
  Action: Install package or add to PATH

Error: Command not executable
  Command: /usr/local/bin/custom-tool
  Permissions: -rw-r--r--
  Action: Run 'chmod +x /usr/local/bin/custom-tool'
```

## Security Guarantees

### 1. No Shell Interpretation

**Pattern**: Use argument arrays, not string concatenation

**Safe**:
```bash
ARGS=("$COMMAND" "$ARG1" "$ARG2")
exec "${ARGS[@]}"
```

**Unsafe** (never use):
```bash
eval "$COMMAND $ARG1 $ARG2"  # Command injection risk
sh -c "$COMMAND $ARG1 $ARG2"  # Shell interpretation
```

### 2. Variable Substitution Isolation

**Pattern**: Replace variables before command execution

**Safe**:
```bash
PARAM_RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
ARGS=("$COMMAND")
[[ -n "$PARAM_RESOLVED" ]] && ARGS+=("$PARAM_RESOLVED")
exec "${ARGS[@]}"
```

**Unsafe**:
```bash
PARAM_RESOLVED=$(echo "$PARAMETERS" | envsubst)  # Eval risk
exec $COMMAND $PARAM_RESOLVED  # Word splitting
```

### 3. Metacharacter Blocking

**Blocked Characters** (registry validation, build-time):
- `;` - Command separator
- `|` - Pipe operator
- `&` - Background execution
- `` ` `` - Backtick substitution
- `$()` - Command substitution
- `${}` - Parameter expansion (except whitelisted variables)

**Allowed Patterns**:
- `$PROJECT_DIR` ✅ (whitelisted variable)
- `--flag=$PROJECT_DIR` ✅ (variable in argument)
- `$PROJECT_DIR/subdir` ✅ (path construction)

**Blocked Patterns**:
- `; rm -rf ~` ❌ (command separator)
- `$(malicious)` ❌ (command substitution)
- `| cat /etc/passwd` ❌ (pipe)

## Fallback Behavior

### When Project Context Unavailable

**Conditions**:
- No active project (daemon returns null)
- Daemon not running
- Project config file missing/invalid

**Fallback Options**:

| Option | Behavior | Use Case |
|--------|----------|----------|
| `skip` | Launch without parameter | Terminal (defaults to $HOME) |
| `use_home` | Substitute `$HOME` for `$PROJECT_DIR` | File manager (open home) |
| `error` | Abort launch, show error | Critical project-dependent tools |

**Example (skip)**:
```bash
# Registry: "parameters": "$PROJECT_DIR"
# No project active
# Result: Launch without argument

exec code  # Opens VS Code without directory
```

**Example (use_home)**:
```bash
# Registry: "parameters": "$PROJECT_DIR"
# No project active
# Fallback: use_home

PROJECT_DIR="$HOME"
exec thunar "$HOME"  # Opens file manager in home directory
```

**Example (error)**:
```bash
# Registry: "fallback_behavior": "error"
# No project active
# Result: Error and exit

echo "Error: No project active" >&2
echo "This application requires a project context." >&2
exit 3
```

## Logging

### Log Location

**Path**: `~/.local/state/app-launcher.log`

**Rotation**: Last 1000 lines (manual or logrotate)

### Log Format

```
[<timestamp>] <level> <message>
```

**Example**:
```
[2025-10-24T14:32:45-04:00] INFO Launching: vscode
[2025-10-24T14:32:45-04:00] INFO Project: nixos (/etc/nixos)
[2025-10-24T14:32:45-04:00] INFO Resolved: code /etc/nixos
[2025-10-24T14:32:45-04:00] INFO Executed (PID: 12345)
```

### Log Levels

| Level | Use Case | Example |
|-------|----------|---------|
| `ERROR` | Launch failures, validation errors | `ERROR Command not found: code` |
| `WARN` | Fallback behavior, missing optional data | `WARN No project active, using fallback` |
| `INFO` | Successful launches, project context | `INFO Launching vscode in nixos` |
| `DEBUG` | Variable substitution, path resolution | `DEBUG $PROJECT_DIR → /etc/nixos` |

### Log Entries

**Successful Launch**:
```
[2025-10-24T14:32:45-04:00] INFO App: vscode | Project: nixos | Command: code /etc/nixos | Exit: 0
```

**Launch with Fallback**:
```
[2025-10-24T14:32:50-04:00] WARN No project active for vscode
[2025-10-24T14:32:50-04:00] INFO Fallback: skip
[2025-10-24T14:32:50-04:00] INFO Command: code (no arguments)
```

**Launch Failure**:
```
[2025-10-24T14:32:55-04:00] ERROR Command not found: code
[2025-10-24T14:32:55-04:00] ERROR Package: pkgs.vscode
[2025-10-24T14:32:55-04:00] ERROR Exit: 127
```

## Performance

### Target Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Registry load | < 50ms | `jq` parse time |
| Daemon query | < 10ms | IPC round-trip |
| Variable substitution | < 100ms | Bash string replacement |
| Directory validation | < 50ms | Filesystem check |
| Total overhead | < 500ms | Full wrapper execution |

### Optimization Strategies

1. **Cache daemon socket path** (avoid lookup on each launch)
2. **Minimize jq calls** (load registry once, extract all fields)
3. **Skip validation in production** (enable with `STRICT=1` for debugging)
4. **Use `exec`** (replace wrapper process with application, save memory)

## Testing Interface

### Dry-Run Mode

**Enable**:
```bash
DRY_RUN=1 app-launcher-wrapper.sh vscode
```

**Output**:
```
[DRY RUN] Would execute:
  Command: code
  Arguments: /etc/nixos
  Project: nixos (/etc/nixos)
  Workspace: 1
  Fallback: skip
```

**Behavior**:
- Load registry ✅
- Query daemon ✅
- Substitute variables ✅
- Validate directory ✅
- Show resolved command ✅
- Execute command ❌ (skip)

### Debug Mode

**Enable**:
```bash
DEBUG=1 app-launcher-wrapper.sh vscode
```

**Output**:
```
[DEBUG] Registry: /home/user/.config/i3/application-registry.json
[DEBUG] Application: vscode
[DEBUG] Command: code
[DEBUG] Parameters: $PROJECT_DIR
[DEBUG] Daemon query: get_current_project()
[DEBUG] Project: nixos
[DEBUG] Project config: /home/user/.config/i3/projects/nixos.json
[DEBUG] PROJECT_DIR: /etc/nixos
[DEBUG] Substitution: $PROJECT_DIR → /etc/nixos
[DEBUG] Resolved: code /etc/nixos
[DEBUG] Validation: PASSED
[DEBUG] Executing: code /etc/nixos
```

## Error Recovery

### Registry Corruption

**Detection**:
```bash
jq empty < "$REGISTRY" 2>/dev/null || {
    echo "Error: Invalid JSON in registry" >&2
    exit 2
}
```

**Recovery**:
```
Error: Invalid JSON in registry
  Path: /home/user/.config/i3/application-registry.json

  Try:
    1. Validate JSON: jq empty < ~/.config/i3/application-registry.json
    2. Restore backup: cp ~/.config/i3/application-registry.json.bak ~/.config/i3/application-registry.json
    3. Rebuild: sudo nixos-rebuild switch --flake .#hetzner
```

### Daemon Unavailable

**Detection**:
```bash
PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')
```

**Recovery**:
```bash
if [[ "$PROJECT_JSON" == '{}' ]]; then
    echo "[WARN] Daemon not responding, defaulting to global mode" >&2
    PROJECT_NAME=""
    PROJECT_DIR=""
fi
```

**User Message**:
```
Warning: i3pm daemon not running
  Launching in global mode (no project context)

  To start daemon:
    systemctl --user start i3-project-event-listener
```

### Directory Not Found

**Detection**:
```bash
validate_directory "$PROJECT_DIR" || {
    echo "Error: Project directory not found: $PROJECT_DIR" >&2
    exit 3
}
```

**Recovery** (based on fallback):
```bash
case "$FALLBACK_BEHAVIOR" in
    "skip")
        PROJECT_DIR=""
        ;;
    "use_home")
        PROJECT_DIR="$HOME"
        ;;
    "error")
        echo "Error: Invalid project directory" >&2
        exit 3
        ;;
esac
```

## Integration Points

### Input Sources

1. **Desktop Files** (`~/.local/share/applications/`)
   - Exec line invokes wrapper with app name
   - StartupWMClass aids window matching

2. **CLI** (`i3pm apps launch`)
   - Direct invocation with app name
   - Supports --dry-run and --project overrides

3. **Keybindings** (i3 config)
   - `bindsym $mod+c exec app-launcher-wrapper.sh vscode`

### Output Targets

1. **Application Process**
   - Launched via `exec` (replaces wrapper process)
   - Inherits environment variables
   - Runs in background (detached)

2. **Log File** (`~/.local/state/app-launcher.log`)
   - Execution history
   - Debugging information
   - Audit trail

3. **i3 Window Manager**
   - Application window appears
   - Window rules applied via daemon
   - Workspace assignment enforced

### Data Sources

1. **Registry** (`~/.config/i3/application-registry.json`)
   - Application definitions
   - Command templates
   - Fallback behavior

2. **Daemon** (Unix socket IPC)
   - Active project name
   - Real-time project state

3. **Project Config** (`~/.config/i3/projects/<name>.json`)
   - Project metadata
   - Directory paths
   - Display names

---

**Protocol Status**: ✅ COMPLETE
**Implementation**: Bash script (~200 lines) at `~/.local/bin/app-launcher-wrapper.sh`
**Reference**: Full implementation in `/etc/nixos/specs/034-create-a-feature/secure-substitution-examples.md`
