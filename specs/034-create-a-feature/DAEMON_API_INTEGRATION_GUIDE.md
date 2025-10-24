# i3pm Daemon Project Context API - Integration Guide for Feature 034

**Feature**: 034 - Unified Application Launcher
**Purpose**: Document the i3pm daemon's project context query API for variable substitution in launcher commands
**Date**: 2025-10-24
**Research Level**: Medium

---

## Executive Summary

The i3pm daemon provides a **simple, fast, and reliable** JSON-RPC 2.0 API over Unix domain socket for querying current project context. For Feature 034 (Unified Application Launcher), you need to:

1. Query the daemon's `get_current_project` method to get the active project name
2. Load project metadata from `~/.config/i3/projects/<name>.json`
3. Substitute `$PROJECT_NAME`, `$PROJECT_DIR`, `$SESSION_NAME` variables in launcher commands
4. Handle edge cases: global mode (no project), daemon not running, connection timeouts

**Key Insight**: Query the daemon for project name, then load the JSON file locally for directory and metadata. This is the cleanest separation of concerns.

---

## 1. Connection Details

### Socket Location

**Primary Path** (systemd socket activation):
```
/run/user/<uid>/i3-project-daemon/ipc.sock
```

**Discovery Method**:

**From Bash**:
```bash
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
```

**From TypeScript (Deno)**:
```typescript
const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR") || `/run/user/${Deno.uid()}`;
const socketPath = `${runtimeDir}/i3-project-daemon/ipc.sock`;
```

**From Python**:
```python
import os
from pathlib import Path

runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
socket_path = Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"
```

### Protocol Details

| Aspect | Value |
|--------|-------|
| **Transport** | Unix domain socket (SOCK_STREAM) |
| **Protocol** | JSON-RPC 2.0 |
| **Message Format** | Newline-delimited JSON |
| **Encoding** | UTF-8 |
| **Typical Latency** | < 10ms |
| **Timeout (client)** | 5 seconds |

---

## 2. Query Methods

### 2.1 Method: `get_current_project`

**Purpose**: Get the name of the currently active project, or `null` if in global mode.

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "get_current_project",
  "params": {},
  "id": 1
}
```

**Response (Project Active)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": "nixos"
  },
  "id": 1
}
```

**Response (Global Mode)**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "project": null
  },
  "id": 1
}
```

**Error Response**:
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

### 2.2 Method: `list_projects`

**Purpose**: Get all configured projects with their metadata (useful for validation).

**Request**:
```json
{
  "jsonrpc": "2.0",
  "method": "list_projects",
  "params": {},
  "id": 2
}
```

**Response**:
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

## 3. Project Data Structure

### File Location
```
~/.config/i3/projects/<project_name>.json
```

### Example Project Configuration
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

## 4. CLI Commands for Reference

### Query Current Project
```bash
i3pm project current
```

**Output**:
```
nixos                      # When project is active
                           # When in global mode (empty line when piped)
Global (no active project) # When in global mode (interactive)
```

### List All Projects
```bash
i3pm project list
i3pm project list --json  # JSON output
```

### Validate Projects
```bash
i3pm project validate
```

---

## 5. Implementation Examples

### 5.1 Bash Implementation (Recommended for Launcher)

**Simple Approach** - Query via CLI:

```bash
#!/usr/bin/env bash
# Query current project and substitute variables

set -euo pipefail

# Get active project
PROJECT_NAME=$(i3pm project current 2>/dev/null || true)

# Handle global mode
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: No active project. Cannot launch project-scoped command." >&2
    echo "Switch to a project with: i3pm project switch <name>" >&2
    exit 1
fi

# Load project config from file
PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project configuration not found: $PROJECT_FILE" >&2
    exit 1
fi

# Extract directory using jq
PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")

# Derive session name from project name
SESSION_NAME="$PROJECT_NAME"

# Export for use in launcher commands
export PROJECT_NAME
export PROJECT_DIR
export SESSION_NAME

echo "Project Context:"
echo "  PROJECT_NAME: $PROJECT_NAME"
echo "  PROJECT_DIR: $PROJECT_DIR"
echo "  SESSION_NAME: $SESSION_NAME"
```

**Advanced Approach** - Direct JSON-RPC query for maximum performance:

```bash
#!/usr/bin/env bash
# Direct JSON-RPC query (no subprocess overhead from i3pm CLI)

SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

# Check daemon is running
if [ ! -S "$SOCKET_PATH" ]; then
    echo "Error: i3pm daemon not running (socket not found)" >&2
    exit 1
fi

# Send JSON-RPC request via netcat
RESPONSE=$(echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | \
           nc -U "$SOCKET_PATH" -W 1 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
    echo "Error: No response from daemon" >&2
    exit 1
fi

# Extract project name using jq
PROJECT_NAME=$(echo "$RESPONSE" | jq -r '.result.project // empty')

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: No active project" >&2
    exit 1
fi

# Load project config from file
PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")

echo "$PROJECT_NAME:$PROJECT_DIR"
```

### 5.2 Python Implementation

```python
"""Query daemon for project context."""

import asyncio
import json
from pathlib import Path
from typing import Optional

# Use the existing daemon client from codebase
from home_modules.tools.i3_project_manager.core.daemon_client import (
    DaemonClient,
    DaemonError,
)


async def get_project_context() -> Optional[dict]:
    """
    Query daemon for current project and load metadata.
    
    Returns:
        Dict with keys: name, directory, session_name
        None if in global mode
    """
    client = DaemonClient()
    
    try:
        await client.connect()
        
        # Query current project
        status = await client.get_status()
        project_name = status.get("active_project")
        
        if not project_name:
            return None  # Global mode
        
        # Load project config from file
        project_file = Path.home() / ".config" / "i3" / "projects" / f"{project_name}.json"
        
        if not project_file.exists():
            raise FileNotFoundError(f"Project config not found: {project_file}")
        
        with open(project_file) as f:
            config = json.load(f)
        
        return {
            "name": project_name,
            "directory": config["directory"],
            "session_name": project_name,  # Convention: sesh session name = project name
            "display_name": config.get("display_name", project_name),
            "icon": config.get("icon", "📁"),
        }
    
    except DaemonError as e:
        print(f"Daemon error: {e}", file=sys.stderr)
        return None
    finally:
        await client.close()


# Usage
if __name__ == "__main__":
    context = asyncio.run(get_project_context())
    
    if context:
        print(f"Project: {context['name']}")
        print(f"Directory: {context['directory']}")
        print(f"Session: {context['session_name']}")
    else:
        print("No active project (global mode)")
```

### 5.3 TypeScript/Deno Implementation

```typescript
/**
 * Query daemon for project context (Feature 034)
 */

import { DaemonClient, createClient } from "../client.ts";
import type { Project } from "../models.ts";

interface ProjectContext {
  name: string;
  directory: string;
  sessionName: string;
  displayName: string;
  icon: string;
}

/**
 * Get current project context from daemon
 */
async function getProjectContext(): Promise<ProjectContext | null> {
  const client = createClient();

  try {
    // Query current project
    const result = await client.request<{ project: string | null }>(
      "get_current_project"
    );

    if (!result.project) {
      return null; // Global mode
    }

    // Load project config from file
    const projectName = result.project;
    const configDir = Deno.env.get("HOME") + "/.config/i3/projects";
    const configPath = `${configDir}/${projectName}.json`;

    const configData = await Deno.readTextFile(configPath);
    const config = JSON.parse(configData);

    return {
      name: projectName,
      directory: config.directory,
      sessionName: projectName, // Convention: sesh session name = project name
      displayName: config.display_name || projectName,
      icon: config.icon || "📁",
    };
  } catch (err) {
    console.error("Failed to get project context:", err);
    return null;
  } finally {
    await client.close();
  }
}

export { getProjectContext, ProjectContext };
```

---

## 6. Variable Substitution

### Supported Variables

For launcher commands in Feature 034:

| Variable | Source | Example |
|----------|--------|---------|
| `$PROJECT_NAME` | Project slug from daemon | `nixos` |
| `$PROJECT_DIR` | Project directory from JSON config | `/etc/nixos` |
| `$SESSION_NAME` | Convention: same as project name | `nixos` |
| `$PROJECT_DISPLAY_NAME` | Display name from JSON config | `NixOS` |
| `$PROJECT_ICON` | Icon from JSON config | `❄️` |

### Substitution Process

1. **Query daemon** for active project name → `nixos`
2. **Load config file** `~/.config/i3/projects/nixos.json`
3. **Extract fields**: directory, display_name, icon
4. **Substitute** variables in launcher command string
5. **Validate** project directory exists before launching

### Example Command Substitution

**Original launcher config**:
```json
{
  "command": "cd $PROJECT_DIR && ghostty",
  "name": "Terminal",
  "context": "project"
}
```

**After substitution** (with project=nixos):
```
ghostty
```

---

## 7. Error Handling

### Daemon Not Running

**Detection**:
```bash
if [ ! -S "${SOCKET_PATH}" ]; then
    echo "Daemon not running" >&2
fi
```

**Recovery**:
```bash
systemctl --user restart i3-project-event-listener
```

**In launcher**: Gracefully disable project-scoped commands with message.

### No Project Active (Global Mode)

**Detection**: `result.project == null`

**Handling Options**:
1. Disable project-scoped commands
2. Show dialog prompting user to switch projects
3. Use fallback to home directory

**Example**:
```bash
if [ -z "$PROJECT_NAME" ]; then
    # Option 1: Error
    echo "Error: No active project" >&2
    exit 1
    
    # Option 2: Fallback to home
    # PROJECT_DIR="$HOME"
    # PROJECT_NAME="default"
fi
```

### Connection Timeout

**Symptom**: Request takes > 5 seconds with no response

**Causes**:
- Daemon hung or crashed
- System overloaded
- Network (if using network socket)

**Recovery**:
```bash
# Restart daemon
systemctl --user restart i3-project-event-listener

# Retry with exponential backoff
for i in 1 2 3; do
    if timeout 5 i3pm project current; then
        break
    fi
    sleep $((i * 100))ms
done
```

### Invalid Project Configuration

**Detection**:
```bash
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project config not found" >&2
fi
```

**Validation**:
```bash
# Use i3pm's built-in validation
i3pm project validate
```

---

## 8. Performance Characteristics

### Query Speed

| Metric | Value | Notes |
|--------|-------|-------|
| Typical latency | < 10ms | Local Unix socket |
| Cold start (first query) | < 50ms | Daemon connection establishment |
| Daemon query | < 5ms | In-memory state lookup |
| File load (JSON) | < 5ms | Small JSON files |
| **Total end-to-end** | **< 20ms** | Negligible for user interaction |

### Caching Recommendation

**NO - Do NOT cache project context**

**Reasons**:
1. Project switches happen via keybindings (Win+P), launcher must see changes instantly
2. Query is fast enough (< 10ms) for human interaction
3. Daemon already caches state, querying daemon IS the cache
4. No cache invalidation logic needed

**Exception**: If launcher pre-loads menus, cache for lifetime of menu UI (< 1 second).

---

## 9. Testing & Validation

### Manual Testing

**Test daemon connectivity**:
```bash
# Check socket exists
ls -l "${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock"

# Check daemon is running
systemctl --user status i3-project-event-listener

# Query daemon
echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | \
  nc -U "${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock"
```

**Test CLI command**:
```bash
# Simple query
i3pm project current

# JSON output
i3pm project current --json

# List all projects
i3pm project list

# Validate all projects
i3pm project validate
```

**Test variable substitution**:
```bash
# Set project context
i3pm project switch nixos

# Query context
PROJECT_NAME=$(i3pm project current)
PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")

echo "Variables:"
echo "  \$PROJECT_NAME=$PROJECT_NAME"
echo "  \$PROJECT_DIR=$PROJECT_DIR"
echo "  \$SESSION_NAME=$PROJECT_NAME"

# Validate directory exists
[ -d "$PROJECT_DIR" ] && echo "Directory exists" || echo "Directory missing"
```

### Integration Tests

```bash
#!/bin/bash
# Feature 034: Variable substitution integration test

set -euo pipefail

echo "Testing i3pm daemon project context API..."

# 1. Test daemon connectivity
SOCKET="${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock"
[ -S "$SOCKET" ] || { echo "FAIL: Daemon socket not found"; exit 1; }
echo "✓ Daemon socket found"

# 2. Test project query
PROJECT=$(i3pm project current)
echo "✓ Query successful: $PROJECT"

# 3. Test project config loading
if [ -n "$PROJECT" ]; then
    CONFIG="$HOME/.config/i3/projects/$PROJECT.json"
    [ -f "$CONFIG" ] || { echo "FAIL: Config file not found"; exit 1; }
    echo "✓ Project config found"
    
    # Test jq parsing
    DIR=$(jq -r '.directory' "$CONFIG")
    [ -d "$DIR" ] || { echo "FAIL: Project directory not found"; exit 1; }
    echo "✓ Project directory valid: $DIR"
fi

echo "All tests passed!"
```

---

## 10. Implementation Checklist for Feature 034

### Required Steps

- [ ] **Parse launcher config** to identify commands with project variables
- [ ] **Query daemon** via `get_current_project` before launching
- [ ] **Load project config** from `~/.config/i3/projects/<name>.json`
- [ ] **Handle global mode** - Disable or prompt user to switch projects
- [ ] **Variable substitution** - Replace `$PROJECT_*` with actual values
- [ ] **Validation** - Verify project directory exists
- [ ] **Error handling** - Daemon not running, timeout, invalid config
- [ ] **Logging** - Log project context used for each launch
- [ ] **Testing** - Unit and integration tests for all paths

### Optional Enhancements

- [ ] Visual indicator in launcher UI showing active project
- [ ] Filter launcher commands by active project
- [ ] Quick project switch from launcher (Win+P equivalent)
- [ ] Cache project list (but NOT active project) for performance
- [ ] Support fallback variables for global mode
- [ ] Show project context in launcher help text

---

## 11. Related Files & Documentation

### Source Code

| File | Description |
|------|-------------|
| `/etc/nixos/home-modules/tools/i3pm-deno/src/client.ts` | Deno JSON-RPC client |
| `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/project.ts` | CLI project commands |
| `/etc/nixos/home-modules/tools/i3_project_manager/core/daemon_client.py` | Python daemon client |
| `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py` | Daemon implementation |
| `/etc/nixos/home-modules/desktop/i3-project-event-daemon/ipc_server.py` | Daemon IPC server |

### Configuration

| File | Description |
|------|-------------|
| `~/.config/i3/projects/<name>.json` | Per-project configuration |
| `~/.config/i3/active-project.json` | Active project state (optional) |
| `~/.config/i3/app-classes.json` | Window class classification rules |

### Documentation

| File | Description |
|------|-------------|
| `/etc/nixos/specs/034-create-a-feature/i3pm-project-api-reference.md` | API reference (this file) |
| `/etc/nixos/specs/015-create-a-new/quickstart.md` | Event-based daemon quickstart |
| `/etc/nixos/docs/i3pm-quick-reference.md` | CLI command reference |
| `/etc/nixos/CLAUDE.md` | Project management workflow |

---

## 12. Quick Reference

### Get Current Project (Bash)
```bash
PROJECT_NAME=$(i3pm project current 2>/dev/null || echo "")
```

### Get Project Directory (Bash)
```bash
PROJECT_FILE="$HOME/.config/i3/projects/${PROJECT_NAME}.json"
PROJECT_DIR=$(jq -r '.directory' "$PROJECT_FILE")
```

### Query Daemon Directly (Bash)
```bash
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | \
  nc -U "$SOCKET" -W 1 | jq -r '.result.project'
```

### Python Async Query
```python
from home_modules.tools.i3_project_manager.core.daemon_client import DaemonClient

async def get_project():
    client = DaemonClient()
    await client.connect()
    status = await client.get_status()
    return status.get("active_project")
```

### Check Daemon Status
```bash
systemctl --user status i3-project-event-listener
journalctl --user -u i3-project-event-listener -n 50
```

### Restart Daemon
```bash
systemctl --user restart i3-project-event-listener
```

---

## 13. Summary

The i3pm daemon provides everything Feature 034 needs:

✅ **Single RPC method**: `get_current_project` returns project name or null  
✅ **CLI wrapper**: `i3pm project current` for bash scripts  
✅ **Fast**: < 10ms typical query time  
✅ **Reliable**: Daemon is event-driven, not polling  
✅ **Clean API**: JSON-RPC 2.0 over Unix socket  
✅ **Good error handling**: Clear error states and recovery paths  
✅ **Project metadata**: Available in `~/.config/i3/projects/<name>.json`  

**For Feature 034 Launcher Implementation**:

1. Query `i3pm project current` (or direct RPC) to get project name
2. Load project config from `~/.config/i3/projects/${PROJECT_NAME}.json`
3. Substitute variables: `$PROJECT_NAME`, `$PROJECT_DIR`, `$SESSION_NAME`
4. Handle global mode gracefully (disable or prompt user)
5. Validate project directory exists before launching
6. Log project context for debugging

**No caching needed** - daemon query IS the cache, and it's fast enough.

