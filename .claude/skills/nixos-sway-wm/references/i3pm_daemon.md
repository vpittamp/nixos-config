# i3pm Daemon and CLI Reference

Complete reference for the i3pm project management daemon and CLI.

## Contents

- [Architecture](#architecture)
- [Daemon Services](#daemon-services)
- [IPC Protocol](#ipc-protocol)
- [CLI Commands](#cli-commands)
- [Data Models](#data-models)
- [Configuration Files](#configuration-files)
- [Event Handling](#event-handling)
- [Debugging](#debugging)

## Architecture

### Client-Server Model

```
┌─────────────────┐     JSON-RPC/Unix Socket     ┌──────────────────┐
│   i3pm CLI      │ ◄────────────────────────► │  Python Daemon    │
│   (Deno/TS)     │                              │  (asyncio)       │
└─────────────────┘                              └────────┬─────────┘
                                                          │
                                                          │ i3ipc.aio
                                                          ▼
                                                 ┌──────────────────┐
                                                 │   Sway/i3 IPC    │
                                                 └──────────────────┘
```

### Key Components

| Component | Language | Location | Purpose |
|-----------|----------|----------|---------|
| Daemon | Python 3.11+ | `home-modules/desktop/i3-project-event-daemon/` | State management, Sway events |
| CLI | TypeScript/Deno | `home-modules/tools/i3pm/` | User interface |
| Python CLI | Python | `home-modules/tools/i3_project_manager/` | Extended CLI features |

## Daemon Services

### Core Services

#### StateManager (`state.py`)
Maintains in-memory daemon state:
- `window_map`: All tracked windows
- `workspace_map`: Workspace metadata
- `active_project`: Current project
- `launch_registry`: Pending launch correlations

#### Discovery Service (`services/discovery_service.py`)
Git repository and worktree discovery:
- Scans configured directories
- Identifies bare repos and worktrees
- Extracts git metadata (branch, commit, status)

#### Window Correlator (`services/window_correlator.py`)
Multi-signal window matching:
- App class matching (baseline)
- Time delta correlation
- Workspace verification
- Confidence scoring (threshold: 0.6)

#### Layout Engine (`services/layout_engine.py`)
Layout save/restore:
- Captures window tree with marks
- Persists to JSON
- Mark-based restoration

#### App Launcher (`services/app_launcher.py`)
Application launching:
- Registry lookup
- Environment injection
- Daemon notification

### IPC Server (`ipc_server.py`)
JSON-RPC 2.0 over Unix socket:
- Socket: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- Systemd socket activation support

## IPC Protocol

### Connection

```bash
# Socket location
/run/user/1000/i3-project-daemon/ipc.sock

# Test with socat
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | \
  socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
```

### Request Format

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": {"key": "value"},
  "id": 1
}
```

### Response Format

```json
{
  "jsonrpc": "2.0",
  "result": {"data": "value"},
  "id": 1
}
```

### Error Response

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": 1001,
    "message": "Project not found"
  },
  "id": 1
}
```

### Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32700 | PARSE_ERROR | Invalid JSON |
| -32601 | METHOD_NOT_FOUND | Unknown method |
| -32602 | INVALID_PARAMS | Invalid parameters |
| 1001 | PROJECT_NOT_FOUND | Project doesn't exist |
| 1002 | LAYOUT_NOT_FOUND | Layout doesn't exist |
| 1003 | WINDOW_NOT_FOUND | Window not tracked |

### Available Methods

#### Project Methods

```json
// List all projects
{"method": "project_list", "params": {}}
// Returns: {"projects": [...]}

// Get active project
{"method": "project_get_active", "params": {}}
// Returns: {"project": {...}, "active": true}

// Switch project
{"method": "project_set_active", "params": {"name": "my-project"}}
// Returns: {"success": true}

// Get single project
{"method": "project_get", "params": {"name": "my-project"}}
// Returns: {"project": {...}}
```

#### Worktree Methods

```json
// List worktrees
{"method": "worktree_list", "params": {"repo": "nixos-config"}}
// Returns: {"worktrees": [...]}

// Switch to worktree
{"method": "worktree_switch", "params": {"qualified_name": "account/repo/branch"}}
// Returns: {"success": true}
```

#### Layout Methods

```json
// Save layout
{"method": "layout_save", "params": {"project": "my-project", "name": "default"}}
// Returns: {"success": true, "layout_id": "..."}

// Restore layout
{"method": "layout_restore", "params": {"project": "my-project", "name": "default"}}
// Returns: {"success": true, "restored_count": 5}

// List layouts
{"method": "layout_list", "params": {"project": "my-project"}}
// Returns: {"layouts": ["default", "coding", "review"]}
```

#### Window Methods

```json
// Get window tree
{"method": "window_tree", "params": {}}
// Returns: {"tree": {...}}

// Get windows for project
{"method": "windows_get", "params": {"project": "my-project"}}
// Returns: {"windows": [...]}

// Get window by ID
{"method": "window_get", "params": {"window_id": 12345}}
// Returns: {"window": {...}}
```

#### Daemon Methods

```json
// Health check
{"method": "health", "params": {}}
// Returns: {"status": "healthy", "uptime": 3600, ...}

// Ping
{"method": "ping", "params": {}}
// Returns: {"pong": true}

// Event subscription (for monitoring)
{"method": "events_subscribe", "params": {}}
// Returns stream of events
```

## CLI Commands

### Worktree Commands

```bash
# List all worktrees
i3pm worktree list
i3pm worktree list --json

# Create new worktree
i3pm worktree create nixos-config feature/new-thing
i3pm worktree create nixos-config 135-new-feature  # Auto-branch naming

# Switch to worktree
i3pm worktree switch nixos-config/feature/new-thing
i3pm worktree switch 135-new-feature  # Fuzzy match

# Remove worktree
i3pm worktree remove nixos-config/old-branch

# Show current worktree
i3pm worktree current
```

### Daemon Commands

```bash
# Check daemon status
i3pm daemon status
i3pm daemon status --json

# Watch live events
i3pm daemon events
i3pm daemon events --format=compact

# Ping daemon
i3pm daemon ping

# Restart daemon (via systemd)
systemctl --user restart i3-project-event-listener
```

### Layout Commands

```bash
# Save current layout
i3pm layout save my-layout

# Restore layout
i3pm layout restore my-layout

# List saved layouts
i3pm layout list

# Delete layout
i3pm layout delete my-layout
```

### Run Command (App Launching)

```bash
# Launch app (run-raise-hide)
i3pm run terminal
i3pm run code --summon     # Always bring to front
i3pm run firefox --hide    # Toggle visibility
i3pm run btop --nohide     # Idempotent launch
i3pm run terminal --force  # Always new instance
```

### Diagnose Commands

```bash
# Full health check
i3pm diagnose health

# Window details
i3pm diagnose window 12345
i3pm diagnose window  # Current focused

# Validate configuration
i3pm diagnose validate

# Event log
i3pm diagnose events

# Socket health
i3pm diagnose socket-health
```

### Monitor Commands

```bash
# Monitor status
i3pm monitors status

# Reassign workspaces
i3pm monitors reassign

# Show config
i3pm monitors config
```

### Scratchpad Commands

```bash
# Toggle scratchpad terminal
i3pm scratchpad toggle

# Show status
i3pm scratchpad status

# Cleanup stale scratchpads
i3pm scratchpad cleanup
```

## Data Models

### Project

```python
class Project(BaseModel):
    name: str                    # Unique identifier
    directory: str               # Absolute path
    display_name: str            # Human-readable name
    icon: str                    # Emoji or path
    source_type: SourceType      # LOCAL, WORKTREE, REMOTE
    status: ProjectStatus        # ACTIVE, MISSING
    git_metadata: GitMetadata    # Branch, commit, clean status
    branch_metadata: BranchMetadata  # Worktree-specific
    discovered_at: datetime
```

### Window

```python
class WindowInfo(BaseModel):
    window_id: int
    app_id: str                  # Sway app_id
    title: str
    workspace_num: int
    project_name: Optional[str]
    app_name: Optional[str]      # From I3PM_APP_NAME
    is_floating: bool
    is_focused: bool
    marks: List[str]
    created_at: datetime
    environment: Dict[str, str]  # I3PM_* variables
```

### Layout

```python
class Layout(BaseModel):
    project: str
    name: str
    windows: List[WindowSnapshot]
    created_at: datetime
    workspace_states: Dict[int, WorkspaceState]
```

### Worktree Environment

Environment variables injected into launched processes:

```python
class WorktreeEnvironment(BaseModel):
    I3PM_IS_WORKTREE: bool
    I3PM_PARENT_PROJECT: str
    I3PM_BRANCH_TYPE: str        # feature, fix, docs, etc.
    I3PM_BRANCH_NUMBER: str      # e.g., "135"
    I3PM_FULL_BRANCH_NAME: str   # e.g., "135-new-feature"
    I3PM_GIT_BRANCH: str
    I3PM_GIT_COMMIT: str
    I3PM_GIT_IS_CLEAN: bool
    I3PM_GIT_AHEAD: int
    I3PM_GIT_BEHIND: int
```

## Configuration Files

### Active Project
Location: `~/.config/i3/active-project`
Format: Plain text (project name)

### Active Worktree
Location: `~/.config/i3/active-worktree.json`
```json
{
  "qualified_name": "vpittamp/nixos-config/134-nixos-integration-tests",
  "directory": "/home/user/repos/vpittamp/nixos-config/134-nixos-integration-tests",
  "branch": "134-nixos-integration-tests",
  "account": "vpittamp",
  "repo_name": "nixos-config"
}
```

### Application Registry
Location: `~/.config/i3/application-registry.json`
```json
{
  "applications": [
    {
      "name": "terminal",
      "command": "ghostty",
      "parameters": ["-e", "sesh", "connect", "$PROJECT_DIR"],
      "scope": "scoped",
      "expected_class": "com.mitchellh.ghostty",
      "preferred_workspace": 1
    }
  ]
}
```

### Layouts
Location: `~/.config/i3/layouts/<project>/<name>.json`

### Daemon Socket
Location: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`

## Event Handling

### Sway Events Handled

| Event | Handler | Purpose |
|-------|---------|---------|
| `window::new` | `on_window_new` | Track new window, correlate launch, inject mark |
| `window::focus` | `on_window_focus` | Update focus state, restore tracking |
| `window::close` | `on_window_close` | Cleanup, archive state |
| `window::mark` | `on_window_mark` | Update mark associations |
| `window::move` | `on_window_move` | Track workspace changes |
| `workspace::focus` | `on_workspace_focus` | Track active workspace |
| `output` | `on_output` | Handle monitor connect/disconnect |
| `mode` | `on_mode` | Workspace mode navigation |

### Event Flow

```
1. Sway event received (i3ipc.aio subscription)
   ↓
2. Handler invoked (handlers.py)
   ↓
3. State updated (state.py)
   ↓
4. Subscribers notified (monitoring panel, etc.)
   ↓
5. Window tree cache invalidated
```

### Launch Correlation

When app-launcher-wrapper launches an app:

1. **Pre-launch**: Daemon receives `notify_launch` with expected class, workspace
2. **Window appears**: Daemon correlates using multi-signal algorithm
3. **Match found**: Window marked with project context
4. **No match**: Fallback to environment variable check

Correlation signals:
- App class match (0.5 baseline)
- Time delta < 1s (+0.3), < 2s (+0.2), < 5s (+0.1)
- Workspace match (+0.2)
- Threshold: 0.6

## Debugging

### Check Daemon Status

```bash
# Is daemon running?
systemctl --user status i3-project-event-listener

# Check socket exists
ls -la $XDG_RUNTIME_DIR/i3-project-daemon/

# View logs
journalctl --user -u i3-project-event-listener -f
```

### Test IPC Connection

```bash
# Ping daemon
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | \
  socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock

# Get health
echo '{"jsonrpc":"2.0","method":"health","id":1}' | \
  socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock | jq
```

### Debug Window Matching

```bash
# Check window environment
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM

# View window tree
swaymsg -t get_tree | jq '.. | select(.app_id?) | {app_id, pid, focused}'

# Watch daemon events
i3pm daemon events
```

### Common Issues

**Daemon not responding**:
```bash
systemctl --user restart i3-project-event-listener
```

**Windows not being tracked**:
- Check app launched via `app-launcher-wrapper.sh`
- Verify I3PM_* environment variables in process
- Check daemon logs for correlation failures

**Layout restore fails**:
- Verify layout exists: `i3pm layout list`
- Check all apps are installed
- Ensure project directory exists

**Worktree switch fails**:
- Verify worktree exists: `git worktree list`
- Check bare repo structure
- Verify directory permissions
