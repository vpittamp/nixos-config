# i3pm Daemon Project Context Query API Reference

**Feature**: 034 - Unified Application Launcher
**Purpose**: Document the i3pm daemon's project context query API for variable substitution in launcher commands
**Date**: 2025-10-24

---

## Overview

The i3pm daemon exposes a JSON-RPC API over a Unix domain socket that allows querying the current project context. This API is used by the unified application launcher to substitute variables like `$PROJECT_DIR`, `$PROJECT_NAME`, and `$SESSION_NAME` in launch commands.

---

## Connection Details

### Socket Location

**Primary Path** (systemd socket activation):
```
/run/user/<uid>/i3-project-daemon/ipc.sock
```

**Discovery Method** (from TypeScript source):
```typescript
const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR") || `/run/user/${Deno.uid()}`;
const socketPath = `${runtimeDir}/i3-project-daemon/ipc.sock`;
```

**From Bash**:
```bash
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
```

### Protocol

- **Transport**: Unix domain socket (SOCK_STREAM)
- **Protocol**: JSON-RPC 2.0
- **Message Format**: Newline-delimited JSON (`\n` terminated)
- **Encoding**: UTF-8

---

## JSON-RPC Method: `get_current_project`

### Purpose

Returns the name of the currently active project, or `null` if in global mode (no project active).

### Request Format

```json
{
  "jsonrpc": "2.0",
  "method": "get_current_project",
  "params": {},
  "id": 1
}
```

### Response Format

**When project is active**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": "nixos"
  },
  "id": 1
}
```

**When in global mode (no project active)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": null
  },
  "id": 1
}
```

### Error Response

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32603,
    "message": "Internal error"
  },
  "id": 1
}
```

---

## CLI Command: `i3pm project current`

### Output Format

**Terminal Output** (when stdout is a TTY):
```
nixos                     # Project active (colored cyan)
Global (no active project)  # Global mode (colored dim gray)
```

**Piped Output** (when stdout is NOT a TTY):
```
nixos      # Project active (plain text)
           # Global mode (empty string)
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0    | Success (whether project active or not) |
| 1    | Daemon connection failed or other error |

### Performance

- **Typical Response Time**: < 10ms
- **Timeout**: 5 seconds (client-side)

### Source Code Reference

From `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/project.ts`:

```typescript
async function currentProject(options: ProjectCommandOptions): Promise<void> {
  const client = createClient();

  try {
    const result = await client.request<{ project: string | null }>("get_current_project");

    if (result.project === null) {
      // Output plain text when piped, colored when interactive
      if (Deno.stdout.isTerminal()) {
        console.log(dim("Global") + " " + gray("(no active project)"));
      } else {
        console.log("");  // Empty string for "no project" when piped
      }
    } else {
      // Output plain text when piped, colored when interactive
      if (Deno.stdout.isTerminal()) {
        console.log(cyan(result.project));
      } else {
        console.log(result.project);  // Plain text for scripting
      }
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  } finally {
    await client.close();
    Deno.exit(0);
  }
}
```

---

## JSON-RPC Method: `list_projects`

### Purpose

Returns all configured projects with their metadata. Useful for validating a project name exists before launching.

### Request Format

```json
{
  "jsonrpc": "2.0",
  "method": "list_projects",
  "params": {},
  "id": 2
}
```

### Response Format

```json
{
  "jsonrpc": "2.0",
  "result": [
    {
      "name": "nixos",
      "display_name": "NixOS",
      "icon": "❄️",
      "directory": "/etc/nixos",
      "scoped_classes": ["Ghostty", "Code"],
      "created_at": 1698000000,
      "last_used_at": 1698012345
    },
    {
      "name": "stacks",
      "display_name": "Stacks",
      "icon": "📚",
      "directory": "/home/user/stacks",
      "scoped_classes": ["Ghostty", "Code"],
      "created_at": 1698000100,
      "last_used_at": 1698010000
    }
  ],
  "id": 2
}
```

---

## Project Data Model

### Project Configuration File

Projects are stored as JSON files in `~/.config/i3/projects/<name>.json`:

```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS",
  "icon": "❄️",
  "scoped_classes": ["Ghostty", "Code"],
  "workspace_preferences": {},
  "auto_launch": [],
  "saved_layouts": [],
  "created_at": "2025-10-20T10:19:00+00:00",
  "modified_at": "2025-10-20T23:06:30.581936"
}
```

### Available Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Project slug (used in commands) | `"nixos"` |
| `display_name` | string | Human-readable name | `"NixOS"` |
| `icon` | string | Emoji or Unicode icon | `"❄️"` |
| `directory` | string | Absolute path to project directory | `"/etc/nixos"` |
| `scoped_classes` | string[] | Window classes scoped to project | `["Ghostty", "Code"]` |
| `created_at` | string | ISO 8601 timestamp | `"2025-10-20T10:19:00+00:00"` |
| `modified_at` | string | ISO 8601 timestamp | `"2025-10-20T23:06:30.581936"` |

---

## Error Handling

### Daemon Not Running

**Symptom**: Cannot connect to socket

**Error Message**:
```
Failed to connect after 4 attempts:
Connection refused
```

**Detection**:
```bash
if ! systemctl --user is-active --quiet i3-project-event-listener; then
    echo "Error: i3pm daemon not running"
    exit 1
fi
```

**Resolution**:
```bash
systemctl --user restart i3-project-event-listener
```

### No Project Active (Global Mode)

**Detection**: `result.project == null`

**Behavior**:
- CLI prints empty string (when piped) or "Global (no active project)" (interactive)
- Launcher should either:
  1. Disable project-scoped commands
  2. Use fallback/default values
  3. Prompt user to switch to a project

**Example**:
```bash
PROJECT_NAME=$(i3pm project current)
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: No active project. Switch with: i3pm project switch <name>"
    exit 1
fi
```

### Connection Timeout

**Timeout Duration**: 5 seconds (default)

**Error Message**:
```
Timeout connecting to daemon socket at /run/user/1000/i3-project-daemon/ipc.sock.
The daemon may be unresponsive. Try restarting:
  systemctl --user restart i3-project-event-listener
```

---

## Usage Examples for Launcher

### Bash Wrapper Script

```bash
#!/usr/bin/env bash
# Query current project context for variable substitution

set -euo pipefail

# Socket path discovery
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

# Check daemon is running
if [ ! -S "$SOCKET_PATH" ]; then
    echo "Error: i3pm daemon not running (socket not found: $SOCKET_PATH)" >&2
    exit 1
fi

# Query current project using CLI (simplest method)
PROJECT_NAME=$(i3pm project current)

# Handle global mode
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: No active project. Launch a project-scoped command requires an active project." >&2
    echo "Switch to a project with: i3pm project switch <name>" >&2
    exit 1
fi

# Load project metadata from JSON file
PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project configuration not found: $PROJECT_FILE" >&2
    exit 1
fi

# Extract directory using jq
PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
SESSION_NAME="$PROJECT_NAME"  # sesh session name = project name

# Export for use in launcher commands
export PROJECT_NAME
export PROJECT_DIR
export SESSION_NAME

echo "Project Context:"
echo "  PROJECT_NAME: $PROJECT_NAME"
echo "  PROJECT_DIR: $PROJECT_DIR"
echo "  SESSION_NAME: $SESSION_NAME"
```

### Direct JSON-RPC Query (Advanced)

```bash
#!/usr/bin/env bash
# Query daemon via raw JSON-RPC for maximum performance

SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

# Send JSON-RPC request and parse response
RESPONSE=$(echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | nc -U "$SOCKET_PATH")

# Extract project name using jq
PROJECT_NAME=$(echo "$RESPONSE" | jq -r '.result.project // empty')

if [ -z "$PROJECT_NAME" ]; then
    echo "No active project" >&2
    exit 1
fi

echo "$PROJECT_NAME"
```

### Error Recovery

```bash
#!/usr/bin/env bash
# Robust project query with error handling

query_project() {
    local timeout=5
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if PROJECT_NAME=$(timeout "$timeout" i3pm project current 2>&1); then
            if [ -n "$PROJECT_NAME" ]; then
                echo "$PROJECT_NAME"
                return 0
            else
                echo "No active project" >&2
                return 1
            fi
        fi

        retry=$((retry + 1))
        sleep 0.5
    done

    echo "Failed to query project after $max_retries attempts" >&2
    return 1
}

# Usage
if PROJECT_NAME=$(query_project); then
    echo "Project: $PROJECT_NAME"
else
    echo "Defaulting to global mode"
    PROJECT_NAME=""
fi
```

---

## Performance Characteristics

### Query Speed

| Metric | Value | Notes |
|--------|-------|-------|
| Typical latency | < 10ms | Local Unix socket |
| Timeout | 5000ms | Client-side default |
| Connection retry | 3 attempts | Exponential backoff (100ms, 200ms, 400ms) |
| Max delay | 2000ms | Between retries |

### Caching Considerations

**Should the launcher cache project context?**

**Recommendation**: NO - Do NOT cache

**Reasons**:
1. **Real-time accuracy**: Project switches happen via keybindings (Win+P), launcher must see changes instantly
2. **Fast enough**: < 10ms query is negligible for human interaction
3. **Event-driven daemon**: Daemon already caches state, querying daemon IS the cache
4. **Simplicity**: No cache invalidation logic needed

**Exception**: If launcher pre-loads menus, it could cache for the lifetime of the menu UI (< 1 second).

---

## Integration Checklist for Feature 034

### Required Steps

- [ ] **Parse launcher config** to identify commands with project variables (`$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`)
- [ ] **Query daemon** via `i3pm project current` before launching command
- [ ] **Handle global mode** - Either disable project commands or prompt user to switch
- [ ] **Error handling** - Detect daemon not running, connection timeout, invalid project
- [ ] **Variable substitution** - Replace variables with actual values from project config
- [ ] **Validation** - Verify project directory exists before launching
- [ ] **Logging** - Log project context used for each launch (debugging)

### Optional Enhancements

- [ ] **Visual indicator** in launcher UI showing active project
- [ ] **Project filter** - Filter launcher commands by active project
- [ ] **Quick switch** - Allow switching project from launcher (Win+P equivalent)
- [ ] **Session name** - Derive sesh session name from project name (already convention)

---

## Related Files

### Source Code

| File | Description |
|------|-------------|
| `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/project.ts` | CLI command implementation |
| `/etc/nixos/home-modules/tools/i3pm-deno/src/client.ts` | JSON-RPC client implementation |
| `/etc/nixos/home-modules/tools/i3pm-deno/src/utils/socket.ts` | Socket connection utilities |
| `/etc/nixos/home-modules/desktop/i3-project-event-daemon/ipc_server.py` | Daemon IPC server (Python) |

### Configuration

| File | Description |
|------|-------------|
| `~/.config/i3/projects/<name>.json` | Per-project configuration |
| `~/.config/i3/active-project.json` | Active project state (optional) |
| `~/.config/i3/app-classes.json` | Window class classification rules |

### Documentation

| File | Description |
|------|-------------|
| `/etc/nixos/specs/027-update-the-spec/contracts/json-rpc-api.md` | Full JSON-RPC API contract |
| `/etc/nixos/specs/015-create-a-new/quickstart.md` | Event-based daemon quickstart |
| `/etc/nixos/docs/i3pm-quick-reference.md` | CLI command reference |

---

## Appendix: Full API Reference

For complete API documentation including all 27+ JSON-RPC methods, see:
- `/etc/nixos/specs/027-update-the-spec/contracts/json-rpc-api.md`

For daemon architecture and event system, see:
- `/etc/nixos/specs/015-create-a-new/quickstart.md` (Event-driven system)
- `/etc/nixos/CLAUDE.md` (Project Management Workflow section)

---

## Summary

The i3pm daemon provides a **simple, fast, and reliable** project context query API:

✅ **Single RPC method**: `get_current_project` returns project name or null
✅ **CLI wrapper**: `i3pm project current` for bash scripts
✅ **Fast**: < 10ms typical query time
✅ **Reliable**: Automatic retries with exponential backoff
✅ **Error handling**: Clear error states (no project, daemon down, timeout)
✅ **Project metadata**: Available in `~/.config/i3/projects/<name>.json`

**For Feature 034 Launcher**:
1. Query `i3pm project current` before each project-scoped launch
2. Load project config from `~/.config/i3/projects/${PROJECT_NAME}.json`
3. Substitute variables: `$PROJECT_NAME`, `$PROJECT_DIR`, `$SESSION_NAME`
4. Handle global mode gracefully (disable or prompt)

**No caching needed** - daemon query IS the cache.
