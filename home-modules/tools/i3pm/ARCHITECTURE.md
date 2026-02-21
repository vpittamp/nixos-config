# i3pm Architecture

## Overview

i3pm (i3 Project Manager) follows a **client-server architecture** with clear separation between UI and backend layers.

## Architectural Layers

### Python Backend Layer (Daemon)

**Location**: `home-modules/desktop/i3-project-event-daemon/`

**Responsibilities**:
- All file I/O operations (project files, layout files, configuration)
- Direct i3/Sway IPC communication via i3ipc-python library
- Window environment variable reading from /proc filesystem
- Event-driven state management (window events, workspace events, output events)
- Long-running daemon process with systemd integration
- JSON-RPC IPC server for CLI communication

**Key Components**:
- `ipc_server.py` - JSON-RPC server handling CLI requests
- `services/layout_engine.py` - Layout capture and restore operations
- `services/project_service.py` - Project CRUD and active state management
- `models/layout.py` - Pydantic data models for layout validation
- `models/project.py` - Pydantic data models for project validation
- `window_environment.py` - /proc filesystem access for environment variables
- `handlers.py` - Event handlers for i3/Sway IPC events

**Technologies**:
- Python 3.11+ with asyncio
- i3ipc-python (i3ipc.aio for async Sway/i3 IPC)
- Pydantic (data validation and serialization)
- systemd (daemon management)

---

### TypeScript UI Layer (CLI)

**Location**: `home-modules/tools/i3pm/src/`

**Responsibilities**:
- Command-line argument parsing and validation
- User-facing display formatting (tables, trees, colored output)
- JSON-RPC client communication with daemon
- Interactive TUI components (live monitoring)
- Error handling and user-friendly error messages

**Key Components**:
- `commands/*.ts` - CLI command implementations
- `services/daemon-client.ts` - JSON-RPC client for daemon communication
- `services/registry.ts` - Read-only application registry access
- `utils/format.ts` - Display formatting utilities
- `models/*.ts` - TypeScript type definitions (mirroring Python models)

**Technologies**:
- TypeScript with Deno runtime
- Cliffy (CLI framework for argument parsing)
- Rich terminal UI libraries (colors, tables, trees)

---

## Architectural Boundaries

### What TypeScript SHOULD Do ✅

1. **CLI Parsing**: Parse user commands and arguments
2. **Daemon Communication**: Send JSON-RPC requests to daemon
3. **Display Formatting**: Format daemon responses for terminal display
4. **Error Handling**: Present user-friendly error messages
5. **Read-Only Config Access**: Read application registry (configuration)
6. **Interactive UI**: TUI components, live updates, keyboard input

### What TypeScript SHOULD NOT Do ❌

1. **File I/O**: NO writing to project files, layout files, or state files
2. **Shell Commands**: NO execution of i3-msg, xprop, or other system commands
3. **/proc Access**: NO direct reading of /proc filesystem
4. **State Management**: NO maintaining long-running state (daemon owns state)
5. **i3 IPC**: NO direct i3/Sway IPC communication
6. **Business Logic**: NO project/layout validation or manipulation

---

## Communication Protocol

### JSON-RPC over Unix Socket

**Socket Path**: `${XDG_RUNTIME_DIR}/i3-project-daemon/ipc.sock` (default)

**Request Format**:
```json
{
  "jsonrpc": "2.0",
  "method": "layout_save",
  "params": {
    "project_name": "nixos",
    "layout_name": "default"
  },
  "id": 1
}
```

**Response Format**:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "layout_path": "/home/user/.config/i3/layouts/nixos-default.json",
    "window_count": 12
  },
  "id": 1
}
```

**Error Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": 1001,
    "message": "Project not found: nixos"
  },
  "id": 1
}
```

### Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1001 | PROJECT_NOT_FOUND | Project does not exist |
| 1002 | LAYOUT_NOT_FOUND | Layout file does not exist |
| 1003 | VALIDATION_ERROR | Invalid request parameters |
| 1004 | FILE_IO_ERROR | File system operation failed |
| 1005 | I3_IPC_ERROR | i3/Sway IPC communication failed |

---

## Data Flow Examples

### Example 1: Save Layout

```
User runs: i3pm layout save nixos default
    ↓
TypeScript CLI parses arguments
    ↓
TypeScript sends JSON-RPC request to daemon
    ↓
Python daemon receives request
    ↓
LayoutEngine.capture_layout() queries i3 IPC
    ↓
Read window environments from /proc
    ↓
Create WindowSnapshot Pydantic models
    ↓
Validate and serialize Layout model
    ↓
Write to ~/.config/i3/layouts/nixos-default.json
    ↓
Return success response to TypeScript
    ↓
TypeScript formats and displays result
```

### Example 2: Switch Project

```
User runs: i3pm worktree switch vpittamp/nixos-config:main
    ↓
TypeScript CLI parses arguments
    ↓
TypeScript sends JSON-RPC worktree.switch request
    ↓
Python daemon receives request
    ↓
ProjectService validates worktree exists (repos.json + active context)
    ↓
Save active state to ~/.config/i3/active-worktree.json
    ↓
Trigger window filtering (scoped vs global)
    ↓
Return success response to TypeScript
    ↓
TypeScript displays "Switched to worktree: vpittamp/nixos-config:main"
```

---

## Performance Characteristics

### Before Consolidation (TypeScript-heavy)

- Layout operations: 500-1000ms (shell commands to i3-msg, multiple /proc reads)
- Project operations: 100-200ms (multiple file I/O roundtrips)
- Race conditions from concurrent file access

### After Consolidation (Python daemon)

- Layout operations: <100ms (direct i3ipc library calls, single /proc read)
- Project operations: <50ms (in-memory state with atomic file writes)
- Zero race conditions (daemon serializes all operations)

**Performance Gain**: 10-20x faster for layout operations

---

## Code Size Metrics

**After Feature 058 Consolidation**:

- **TypeScript reduced**: ~1000 lines deleted
  - Deleted files: `layout-engine.ts`, `project-manager.ts`
  - Simplified files: `layout.ts`, `project.ts`

- **Python increased**: ~500 lines added
  - New files: `services/layout_engine.py`, `services/project_service.py`
  - New models: `models/layout.py`, `models/project.py`
  - Enhanced: `ipc_server.py` with new JSON-RPC handlers

**Net Result**: More maintainable codebase with clearer separation of concerns

---

## Design Principles

1. **Single Responsibility**: Daemon handles backend, CLI handles UI
2. **Event-Driven**: Daemon uses i3 IPC event subscriptions (not polling)
3. **Type Safety**: Pydantic models enforce runtime validation
4. **Deterministic Identity**: Context keys include mode + host + qualified worktree
5. **Error Transparency**: Daemon errors propagate to CLI with context
6. **Performance First**: Direct library calls over shell commands
7. **Atomic Operations**: File writes are atomic (write temp, rename)

---

## Testing Strategy

### Unit Tests (Python)
- Model validation (`test_layout_models.py`, `test_project_models.py`)
- Service logic (`test_layout_engine.py`, `test_project_service.py`)
- Mocked i3 IPC connections

### Integration Tests (Python)
- JSON-RPC API contract validation (`test_layout_ipc.py`, `test_project_ipc.py`)
- End-to-end IPC communication
- Error handling and edge cases

### Scenario Tests (Python)
- Complete user workflows (`test_layout_workflow.py`, `test_project_workflow.py`)
- Multi-step operations (create → save → restore)
- Concurrent operation handling

### Manual Tests (CLI)
- User experience validation
- Display formatting
- Error message clarity

---

## Future Architecture Improvements

### Potential Enhancements

1. **Incremental Layout Capture**: Only save changed windows (delta updates)
2. **Layout Templates**: Reusable layout configurations
3. **Project Inheritance**: Child projects inheriting parent settings
4. **Multi-Daemon Support**: Run multiple daemon instances for different users
5. **GraphQL API**: Replace JSON-RPC with GraphQL for richer queries
6. **Web UI**: HTTP server for browser-based project management

### Performance Optimizations

1. **Layout Diffing**: Compare before/after states to minimize i3 commands
2. **Batch Operations**: Group multiple window moves into single transaction
3. **Caching**: Cache i3 window tree queries (invalidate on events)
4. **Parallel Window Moves**: Execute independent window moves concurrently

---

## Migration from Legacy System

**Before Feature 058**:
- TypeScript handled both UI and backend
- Shell commands for i3 interaction (i3-msg)
- Duplicate /proc reading in multiple places
- Race conditions from concurrent file access
- 500-1000ms layout operation latency

**After Feature 058**:
- Clear architectural separation (Python backend, TypeScript UI)
- Direct i3ipc library calls (no shell overhead)
- Centralized /proc reading via window_environment.py
- Atomic operations via daemon serialization
- <100ms layout operation latency

**Migration Path**:
1. ✅ Phase 1-2: Foundation (models, IPC infrastructure)
2. ✅ Phase 3: Eliminate duplicate environment reading (US1)
3. ✅ Phase 4: Consolidate layout operations (US2)
4. ✅ Phase 5: Unify project state management (US3)
5. ✅ Phase 6: Validate architectural boundaries (US4)
6. ⏳ Phase 7: Automated testing
7. ⏳ Phase 8: Documentation and polish

---

## Related Documentation

- **Feature 058 Spec**: `/etc/nixos/specs/058-python-backend-consolidation/spec.md`
- **Data Models**: `/etc/nixos/specs/058-python-backend-consolidation/data-model.md`
- **API Contracts**: `/etc/nixos/specs/058-python-backend-consolidation/contracts/`
- **Quickstart Guide**: `/etc/nixos/specs/058-python-backend-consolidation/quickstart.md`
- **Migration Guide**: `/etc/nixos/specs/058-python-backend-consolidation/MIGRATION.md`

---

_Last Updated: 2025-11-03_
_Feature 058: Python Backend Consolidation_
