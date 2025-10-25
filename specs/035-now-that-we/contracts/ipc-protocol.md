# i3 IPC Integration Patterns

**Feature**: 035-now-that-we | **Date**: 2025-10-25
**Input**: research.md (Deno i3 IPC Integration section)

## Overview

This document defines how the registry-centric project management system integrates with i3's IPC protocol. Based on research findings, the system uses a **hybrid approach**:

- **Deno CLI**: Shell out to `i3-msg` for simple commands, JSON-RPC to Python daemon for complex queries
- **Python Daemon**: Native i3ipc.aio integration for event subscriptions and window tree queries

## Deno CLI → i3 Integration

### Simple Commands (Shell-out to i3-msg)

```typescript
// Move window to workspace
async function moveWindowToWorkspace(containerId: number, workspace: number): Promise<void> {
  const cmd = ["i3-msg", "-t", "command", `[con_id=${containerId}] move to workspace number ${workspace}`];
  const process = new Deno.Command("i3-msg", { args: cmd.slice(1) });
  const { code } = await process.output();
  if (code !== 0) throw new Error(`i3-msg failed with code ${code}`);
}

// Send tick event (trigger daemon updates)
async function sendTickEvent(payload: string): Promise<void> {
  const process = new Deno.Command("i3-msg", {
    args: ["-t", "send_tick", payload]
  });
  await process.output();
}
```

### Complex Queries (JSON-RPC to Daemon)

```typescript
// Query window tree via daemon
async function getWindowTree(): Promise<I3TreeNode> {
  const response = await jsonRpcCall("get_tree", {});
  return response.result;
}

// Query active windows for layout capture
async function getActiveWindows(): Promise<Window[]> {
  const response = await jsonRpcCall("get_active_windows", {});
  return response.result;
}
```

## Python Daemon → i3 IPC Integration

### Event Subscriptions (i3ipc.aio)

```python
from i3ipc.aio import Connection, Event

async def setup_subscriptions(i3: Connection):
    """Subscribe to i3 IPC events for window management"""
    i3.on(Event.WINDOW_NEW, on_window_new)
    i3.on(Event.WINDOW_CLOSE, on_window_close)
    i3.on(Event.TICK, on_tick_event)

async def on_window_new(i3: Connection, event):
    """Handle new window - match to registry and assign workspace"""
    window_class = event.container.window_class
    app = find_registry_app_by_class(window_class)

    if app and app.scope == "scoped":
        active_project = load_active_project()
        if active_project:
            workspace = determine_workspace(app, active_project)
            await i3.command(f'[con_id={event.container.id}] move to workspace number {workspace}')

async def on_tick_event(i3: Connection, event):
    """Handle tick event - project switch signal from CLI"""
    if event.payload.startswith("project:switch:"):
        project_name = event.payload.split(":", 2)[2]
        await update_window_visibility(i3, project_name)
```

### Window Queries

```python
async def get_window_tree(i3: Connection):
    """Query full window tree"""
    tree = await i3.get_tree()
    return serialize_tree(tree)

async def get_active_windows(i3: Connection):
    """Get all windows with registry app matching"""
    tree = await i3.get_tree()
    windows = []
    for leaf in tree.leaves():
        if leaf.window:  # Has X11 window
            app = find_registry_app_by_class(leaf.window_class)
            windows.append({
                "con_id": leaf.id,
                "window_id": leaf.window,
                "window_class": leaf.window_class,
                "window_title": leaf.window_title,
                "workspace": leaf.workspace().num,
                "rect": {"x": leaf.rect.x, "y": leaf.rect.y, "width": leaf.rect.width, "height": leaf.rect.height},
                "floating": "user_on" in leaf.floating or "auto_on" in leaf.floating,
                "focused": leaf.focused,
                "registry_app_id": app.name if app else None
            })
    return windows
```

## i3 Message Types Used

| Message Type | Purpose | Called By |
|--------------|---------|-----------|
| `COMMAND` (0) | Move windows, send ticks | CLI (via i3-msg), Daemon |
| `GET_TREE` (4) | Query window hierarchy | Daemon (layout capture) |
| `GET_WORKSPACES` (1) | Query workspace list | Daemon (validation) |
| `SUBSCRIBE` (2) | Event subscriptions | Daemon (window events, ticks) |
| `SEND_TICK` (10) | Send custom event | CLI (trigger project switch) |

## Event Flow Diagrams

### Project Switch Flow

```
User runs: i3pm project switch nixos
    ↓
CLI updates: ~/.config/i3/active-project.json
    ↓
CLI sends: i3-msg -t send_tick "project:switch:nixos"
    ↓
Daemon receives: i3::tick event with payload
    ↓
Daemon updates: window visibility (mark scoped windows)
    ↓
Daemon triggers: i3bar status update (via JSON-RPC notification)
    ↓
User sees: i3bar shows "Project: nixos", windows hidden/shown
```

### Layout Restore Flow

```
User runs: i3pm layout restore nixos
    ↓
CLI loads: ~/.config/i3/projects/nixos.json, ~/.config/i3/layouts/nixos-coding.json
    ↓
CLI validates: all layout apps exist in registry
    ↓
CLI sends: JSON-RPC "close_project_windows" to daemon
    ↓
Daemon closes: all scoped windows with project marks
    ↓
CLI switches: i3pm project switch nixos (sets active project)
    ↓
CLI launches: each app via registry protocol (walker/elephant wrapper)
    ↓
App opens window → Daemon receives: i3::window::new event
    ↓
Daemon matches: window class to registry, assigns workspace
    ↓
CLI waits: for window to appear (polls i3-msg -t get_tree, timeout 5s)
    ↓
CLI positions: i3-msg [con_id=...] move to workspace N, resize set W H
    ↓
CLI focuses: final window marked as focused in layout
```

## Error Handling

| Error Scenario | Handler | Recovery |
|----------------|---------|----------|
| i3-msg not found | CLI | Error: "i3-msg not installed or not in PATH" |
| i3-msg command fails | CLI | Parse stderr, show i3 error message to user |
| Daemon not running | CLI | Warning: "Daemon not running, some features unavailable" |
| i3 IPC connection lost | Daemon | Auto-reconnect with exponential backoff |
| Window never appears | CLI | Timeout after 5s, continue with next window |
| Registry app not found | Daemon | Log warning, do not manage window |

## Performance Considerations

- **CLI shell-out overhead**: ~5-20ms per i3-msg call (acceptable for infrequent user commands)
- **JSON-RPC overhead**: ~1-5ms (local Unix socket, negligible)
- **Daemon event latency**: <100ms from i3 event to daemon handler execution
- **Window positioning**: Sequential (one at a time), but acceptable for <10 windows

## Future Optimizations (Out of Scope for MVP)

- Native Deno i3 IPC client (removes i3-msg shell-out, ~200-300 LOC)
- Batch window positioning (parallel instead of sequential)
- Layout diff/merge (restore only changed windows, not full replace)
