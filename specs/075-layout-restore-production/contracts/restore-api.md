# IPC API Contract: Layout Restoration

**Feature**: 075-layout-restore-production
**Phase**: 1 (Design)
**Date**: 2025-11-14
**Related**: [spec.md](../spec.md) | [plan.md](../plan.md) | [data-model.md](../data-model.md)

## Overview

This document defines the IPC API contract for idempotent layout restoration. The daemon exposes a single `restore_layout` method via Unix socket IPC, returning detailed restore metrics.

**Protocol**: JSON-RPC 2.0 over Unix socket (`~/.local/share/i3pm/daemon.sock`)

---

## Method: restore_layout

**Purpose**: Restore saved layout for specified project, skipping already-running apps (idempotent).

**Invocation**: `i3pm layout restore <project> <layout_name>` (CLI) → Daemon IPC

### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "restore_layout",
  "params": {
    "project": "nixos",
    "layout_name": "main"
  }
}
```

**Parameters**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `project` | string | Yes | `^[a-z0-9-]+$` | Project name (lowercase alphanumeric + hyphens) |
| `layout_name` | string | Yes | `^[a-z0-9-]+$` | Layout name (lowercase alphanumeric + hyphens) |

**Parameter Validation**:
- `project`: Must match active project (from daemon state)
- `layout_name`: Must exist in `~/.local/share/i3pm/layouts/{project}/{layout_name}.json`

### Success Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "status": "success",
    "apps_already_running": ["terminal", "chatgpt-pwa"],
    "apps_launched": ["lazygit", "code"],
    "apps_failed": [],
    "elapsed_seconds": 4.2,
    "metadata": {
      "total_apps": 4,
      "success_rate": 100.0,
      "focused_workspace": 5
    }
  }
}
```

**Response Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `status` | enum | Overall status: `"success"`, `"partial"`, or `"failed"` |
| `apps_already_running` | string[] | Apps skipped because already present (idempotent behavior) |
| `apps_launched` | string[] | Apps successfully launched during restore |
| `apps_failed` | string[] | Apps that failed to launch (not in registry, launch error, etc.) |
| `elapsed_seconds` | float | Total restore duration in seconds |
| `metadata.total_apps` | int | Total apps in saved layout |
| `metadata.success_rate` | float | Percentage of apps successfully handled (0-100) |
| `metadata.focused_workspace` | int | Workspace number to focus after restore |

**Status Logic**:
- `"success"`: All apps restored (running or launched), `apps_failed` is empty
- `"partial"`: Some apps restored, some failed (`apps_failed` non-empty)
- `"failed"`: No apps restored, all in `apps_failed`

**Success Rate Calculation**:
```python
success_rate = (len(apps_already_running) + len(apps_launched)) / total_apps * 100
```

### Error Responses

#### Layout Not Found

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "Layout 'main' not found for project 'nixos'",
    "data": {
      "project": "nixos",
      "layout_name": "main",
      "expected_path": "/home/vpittamp/.local/share/i3pm/layouts/nixos/main.json"
    }
  }
}
```

#### Project Mismatch

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32002,
    "message": "Cannot restore layout for project 'dotfiles' (current project: 'nixos')",
    "data": {
      "requested_project": "dotfiles",
      "current_project": "nixos",
      "hint": "Switch to project 'dotfiles' first with: i3pm project switch dotfiles"
    }
  }
}
```

#### Invalid Layout Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32003,
    "message": "Layout file is invalid or corrupted",
    "data": {
      "layout_path": "/home/vpittamp/.local/share/i3pm/layouts/nixos/old-layout.json",
      "validation_errors": [
        "Missing required field: 'focused_workspace'",
        "Window 0: missing 'app_registry_name' field"
      ],
      "hint": "Re-save layout with: i3pm layout save old-layout"
    }
  }
}
```

#### Daemon Not Running

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32004,
    "message": "i3pm daemon is not running",
    "data": {
      "hint": "Start daemon with: systemctl --user start i3-project-event-listener"
    }
  }
}
```

#### App Registry Lookup Failed

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32005,
    "message": "App 'unknown-app' not found in registry",
    "data": {
      "app_name": "unknown-app",
      "hint": "Check app-registry-data.nix for available apps"
    }
  }
}
```

**Error Code Ranges**:
- `-32000` to `-32099`: Custom application errors
- `-32700` to `-32603`: JSON-RPC standard errors (parse error, invalid request, etc.)

---

## Method: get_restore_status

**Purpose**: Get current restore operation status (for progress tracking).

**Note**: Deferred to Phase 4 (Optimization). MVP restores are synchronous (client waits for completion).

**Future Schema**:
```json
{
  "method": "get_restore_status",
  "params": { "operation_id": "uuid" }
}
```

---

## Data Flow

### Happy Path (Success)

```
CLI: i3pm layout restore nixos main
  ↓
TypeScript CLI sends IPC request
  ↓
Python Daemon receives request
  ↓
1. Validate project matches current (from daemon state)
  ↓
2. Load layout JSON from disk
  ↓
3. Detect running apps (read Sway tree + /proc environments)
  ↓
4. Filter saved windows (skip if app already running)
  ↓
5. Launch missing apps (sequential, via AppLauncher)
  ↓
6. Focus saved workspace
  ↓
7. Build RestoreResult
  ↓
Daemon sends success response
  ↓
CLI displays formatted output
```

### Error Path (Layout Not Found)

```
CLI: i3pm layout restore nixos missing
  ↓
TypeScript CLI sends IPC request
  ↓
Python Daemon receives request
  ↓
1. Validate project matches current ✓
  ↓
2. Load layout JSON from disk ✗ (FileNotFoundError)
  ↓
Daemon sends error response (code: -32001)
  ↓
CLI displays error message with hint
```

### Partial Restore Path

```
Layout has 5 apps: [terminal, code, lazygit, chatgpt-pwa, unknown-app]
  ↓
Detection phase: running = {terminal, chatgpt-pwa}
  ↓
Filtering phase:
  - terminal → already running (skip)
  - code → missing (launch)
  - lazygit → missing (launch)
  - chatgpt-pwa → already running (skip)
  - unknown-app → missing (launch attempt fails)
  ↓
Launch phase:
  - code → SUCCESS
  - lazygit → SUCCESS
  - unknown-app → FAILED (not in registry)
  ↓
Result:
  status: "partial"
  apps_already_running: [terminal, chatgpt-pwa]
  apps_launched: [code, lazygit]
  apps_failed: [unknown-app]
  success_rate: 80.0% (4/5)
```

---

## Integration Examples

### TypeScript CLI (Deno)

```typescript
import { type Socket } from "node:net";

interface RestoreParams {
  project: string;
  layout_name: string;
}

interface RestoreResult {
  status: "success" | "partial" | "failed";
  apps_already_running: string[];
  apps_launched: string[];
  apps_failed: string[];
  elapsed_seconds: number;
  metadata: {
    total_apps: number;
    success_rate: number;
    focused_workspace: number;
  };
}

async function restoreLayout(
  project: string,
  layoutName: string
): Promise<RestoreResult> {
  const socket = connect("/home/vpittamp/.local/share/i3pm/daemon.sock");

  const request = {
    jsonrpc: "2.0",
    id: Date.now(),
    method: "restore_layout",
    params: { project, layout_name: layoutName },
  };

  socket.write(JSON.stringify(request) + "\n");

  const response = await readResponse(socket);

  if (response.error) {
    throw new Error(response.error.message);
  }

  return response.result;
}

// Usage
const result = await restoreLayout("nixos", "main");
console.log(`Restored ${result.apps_launched.length} apps`);
console.log(`Already running: ${result.apps_already_running.join(", ")}`);
```

### Python Daemon (Handler)

```python
from pydantic import BaseModel, ValidationError
from typing import Optional

class RestoreLayoutParams(BaseModel):
    """IPC request parameters for restore_layout method."""
    project: str
    layout_name: str

async def handle_restore_layout(params: dict) -> dict:
    """Handle restore_layout IPC request."""
    try:
        # Validate parameters
        request = RestoreLayoutParams(**params)

        # Validate project matches current
        if request.project != daemon_state.current_project:
            raise ProjectMismatchError(
                requested=request.project,
                current=daemon_state.current_project
            )

        # Load layout
        layout = load_layout(request.project, request.layout_name)

        # Detect running apps
        running_apps = await detect_running_apps()

        # Restore workflow
        result = await restore_workflow(layout, running_apps)

        # Return success response
        return {
            "status": result.status,
            "apps_already_running": result.apps_already_running,
            "apps_launched": result.apps_launched,
            "apps_failed": result.apps_failed,
            "elapsed_seconds": result.elapsed_seconds,
            "metadata": {
                "total_apps": result.total_apps,
                "success_rate": result.success_rate,
                "focused_workspace": layout.focused_workspace
            }
        }

    except FileNotFoundError:
        raise LayoutNotFoundError(project=request.project, layout_name=request.layout_name)
    except ValidationError as e:
        raise InvalidLayoutFormatError(errors=e.errors())
```

---

## CLI Output Format

### Success Response

```bash
$ i3pm layout restore nixos main

✓ Layout restored successfully in 4.2s

Already running (2):
  • terminal
  • chatgpt-pwa

Launched (2):
  • lazygit
  • code

Success rate: 100.0% (4/4 apps)
Focused workspace: 5
```

### Partial Response

```bash
$ i3pm layout restore nixos main

⚠ Layout partially restored in 6.1s

Already running (2):
  • terminal
  • chatgpt-pwa

Launched (2):
  • code
  • lazygit

Failed (1):
  • unknown-app (not in registry)

Success rate: 80.0% (4/5 apps)
Focused workspace: 5
```

### Error Response

```bash
$ i3pm layout restore nixos missing

✗ Layout 'missing' not found for project 'nixos'

Expected path: /home/vpittamp/.local/share/i3pm/layouts/nixos/missing.json

Hint: List available layouts with: i3pm layout list
```

---

## Performance Expectations

| Metric | Target | Measured (Research) |
|--------|--------|---------------------|
| Detection latency | <10ms | 7.81ms (16 windows) |
| Filtering latency | <1ms | <1ms (set membership) |
| App launch time | Varies | 0.5-3.0s per app |
| Total restore (5 apps) | <15s | 7.52s (50% under target) |

**Sequential Launch Times**:
- terminal (ghostty): 0.5s
- code (VS Code): 2.0s
- lazygit: 0.5s
- firefox: 1.5s
- claude-pwa: 3.0s

---

## Testing Considerations

### Unit Tests (Python)

```python
@pytest.mark.asyncio
async def test_restore_layout_success(mock_daemon):
    """Test successful layout restore."""
    # Setup: Mock running apps detection
    mock_daemon.detect_running_apps.return_value = {"terminal"}

    # Execute: Restore layout with 3 apps
    result = await handle_restore_layout({
        "project": "nixos",
        "layout_name": "test-layout"
    })

    # Verify: Response structure
    assert result["status"] == "success"
    assert "terminal" in result["apps_already_running"]
    assert len(result["apps_launched"]) == 2
    assert result["metadata"]["success_rate"] == 100.0

@pytest.mark.asyncio
async def test_restore_layout_not_found(mock_daemon):
    """Test layout not found error."""
    with pytest.raises(LayoutNotFoundError) as exc_info:
        await handle_restore_layout({
            "project": "nixos",
            "layout_name": "missing"
        })

    assert exc_info.value.code == -32001
    assert "missing" in exc_info.value.message
```

### Integration Tests (sway-test)

```json
{
  "name": "test_restore_idempotent",
  "description": "Verify idempotent restore (no duplicates)",
  "steps": [
    {
      "action": "launch_app",
      "args": { "app": "terminal", "workspace": 1 }
    },
    {
      "action": "ipc_call",
      "method": "restore_layout",
      "params": { "project": "nixos", "layout_name": "test-single" }
    },
    {
      "action": "assert_workspace",
      "workspace": 1,
      "windowCount": 1,
      "description": "Should not launch duplicate terminal"
    }
  ]
}
```

---

## Error Handling Strategy

### Client-Side (TypeScript CLI)

```typescript
try {
  const result = await restoreLayout(project, layoutName);

  if (result.status === "partial") {
    console.warn(`⚠ Partial restore: ${result.apps_failed.length} apps failed`);
  } else if (result.status === "success") {
    console.log(`✓ Layout restored successfully`);
  }

} catch (error) {
  if (error.code === -32001) {
    console.error(`✗ Layout not found: ${error.message}`);
    console.log(`Hint: ${error.data.hint}`);
  } else if (error.code === -32002) {
    console.error(`✗ Project mismatch: ${error.message}`);
    console.log(`Hint: ${error.data.hint}`);
  } else {
    console.error(`✗ Unexpected error: ${error.message}`);
  }

  Deno.exit(1);
}
```

### Server-Side (Python Daemon)

```python
class LayoutNotFoundError(Exception):
    """Layout file does not exist."""
    code = -32001

    def __init__(self, project: str, layout_name: str):
        self.project = project
        self.layout_name = layout_name
        self.message = f"Layout '{layout_name}' not found for project '{project}'"
        self.data = {
            "project": project,
            "layout_name": layout_name,
            "expected_path": get_layout_path(project, layout_name),
            "hint": "List available layouts with: i3pm layout list"
        }

# Error handler
try:
    result = await restore_workflow(layout, running_apps)
except LayoutNotFoundError as e:
    return {
        "error": {
            "code": e.code,
            "message": e.message,
            "data": e.data
        }
    }
```

---

## Summary

| Aspect | Value |
|--------|-------|
| Protocol | JSON-RPC 2.0 over Unix socket |
| Primary method | `restore_layout(project, layout_name)` |
| Response time | <15s for 5 apps (target) |
| Error codes | -32001 to -32005 (custom), -32700 to -32603 (standard) |
| Status values | success, partial, failed |
| Success rate formula | (running + launched) / total × 100 |

**Key Design Principles**:
- **Idempotent**: Same request produces same result (no duplicates)
- **Informative**: Detailed metrics (what ran, what launched, what failed)
- **Fast**: <15s for typical 5-app restore
- **Actionable errors**: Every error includes hint for user

**Next**: Define user-facing integration guide in [quickstart.md](../quickstart.md)
