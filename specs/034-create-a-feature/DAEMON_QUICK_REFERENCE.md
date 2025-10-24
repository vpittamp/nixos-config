# i3pm Daemon API - Quick Reference Card

## Socket Path
```bash
# Set this in your script
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
```

## Method: get_current_project

### Request
```json
{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}
```

### Response (Project Active)
```json
{"jsonrpc":"2.0","result":{"project":"nixos"},"id":1}
```

### Response (Global Mode)
```json
{"jsonrpc":"2.0","result":{"project":null},"id":1}
```

---

## Bash: Query via CLI (Recommended)
```bash
#!/bin/bash
PROJECT=$(i3pm project current 2>/dev/null || true)

if [ -z "$PROJECT" ]; then
    echo "No active project" >&2
    exit 1
fi

CONFIG="$HOME/.config/i3/projects/$PROJECT.json"
DIR=$(jq -r '.directory' "$CONFIG")
SESSION="$PROJECT"

echo "Project: $PROJECT"
echo "Directory: $DIR"
echo "Session: $SESSION"
```

## Bash: Query via Direct RPC
```bash
#!/bin/bash
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

[ -S "$SOCKET" ] || { echo "Daemon not running"; exit 1; }

RESPONSE=$(echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | \
           nc -U "$SOCKET" -W 1 2>/dev/null || true)

PROJECT=$(echo "$RESPONSE" | jq -r '.result.project // empty')
[ -n "$PROJECT" ] || { echo "No active project"; exit 1; }

echo "$PROJECT"
```

---

## Python: Query Daemon
```python
import asyncio
from pathlib import Path
import json

# Use existing codebase client:
from home_modules.tools.i3_project_manager.core.daemon_client import DaemonClient

async def get_context():
    client = DaemonClient()
    await client.connect()
    
    try:
        status = await client.get_status()
        project = status.get("active_project")
        
        if not project:
            return None
        
        config_file = Path.home() / ".config" / "i3" / "projects" / f"{project}.json"
        config = json.loads(config_file.read_text())
        
        return {
            "name": project,
            "directory": config["directory"],
            "session_name": project,
        }
    finally:
        await client.close()

# Usage
context = asyncio.run(get_context())
```

---

## TypeScript/Deno: Query Daemon
```typescript
import { createClient } from "../client.ts";

async function getContext() {
  const client = createClient();
  
  try {
    const result = await client.request("get_current_project");
    
    if (!result.project) {
      return null;
    }
    
    const configPath = `${Deno.env.get("HOME")}/.config/i3/projects/${result.project}.json`;
    const config = JSON.parse(await Deno.readTextFile(configPath));
    
    return {
      name: result.project,
      directory: config.directory,
      sessionName: result.project,
    };
  } finally {
    await client.close();
  }
}
```

---

## Project Config File

**Location**: `~/.config/i3/projects/<name>.json`

**Fields**:
- `name` - Project slug (e.g., "nixos")
- `directory` - Absolute path (e.g., "/etc/nixos")
- `display_name` - Human readable (e.g., "NixOS")
- `icon` - Emoji (e.g., "❄️")
- `scoped_classes` - Array of window classes
- `created_at` - ISO 8601 timestamp
- `modified_at` - ISO 8601 timestamp

---

## Variable Substitution

| Variable | Source | Example |
|----------|--------|---------|
| `$PROJECT_NAME` | Daemon query | `nixos` |
| `$PROJECT_DIR` | Config file | `/etc/nixos` |
| `$SESSION_NAME` | Convention = project name | `nixos` |

### Example
```bash
COMMAND="cd $PROJECT_DIR && ghostty"
# After substitution (project=nixos):
# ghostty
```

---

## Error Handling

### Daemon Not Running
```bash
if [ ! -S "$SOCKET" ]; then
    systemctl --user restart i3-project-event-listener
    exit 1
fi
```

### No Active Project (Global Mode)
```bash
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: No active project"
    echo "Switch with: i3pm project switch <name>"
    exit 1
fi
```

### Connection Timeout
```bash
timeout 5 i3pm project current || {
    echo "Daemon timeout"
    systemctl --user restart i3-project-event-listener
    exit 1
}
```

---

## Testing

```bash
# Check daemon is running
systemctl --user is-active i3-project-event-listener

# Check socket exists
ls -l "${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock"

# Query daemon directly
echo '{"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}' | \
  nc -U "${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock"

# Use CLI
i3pm project current
i3pm project list
i3pm project validate

# View logs
journalctl --user -u i3-project-event-listener -n 50 -f
```

---

## Performance

| Metric | Value |
|--------|-------|
| Query latency | < 10ms |
| Timeout | 5 seconds |
| Cold start | < 50ms |
| **Total E2E** | **< 20ms** |

**Caching**: NO - Query is fast, daemon switches happen instantly

---

## Common Commands

```bash
# List all projects
i3pm project list

# Switch to project
i3pm project switch nixos

# Get current project
i3pm project current

# Get as JSON
i3pm project current --json

# Validate all projects
i3pm project validate

# Create project
i3pm project create --name myproject --dir /path/to/dir

# Daemon status
i3pm daemon status

# Daemon logs
journalctl --user -u i3-project-event-listener -f
```

---

## Integration Steps for Feature 034

1. ✅ Query daemon for active project name
2. ✅ Load `~/.config/i3/projects/<name>.json`
3. ✅ Extract `directory` field
4. ✅ Substitute `$PROJECT_*` variables in commands
5. ✅ Validate directory exists
6. ✅ Handle global mode (no active project)
7. ✅ Log project context
8. ✅ Handle errors (daemon down, timeout, invalid config)

