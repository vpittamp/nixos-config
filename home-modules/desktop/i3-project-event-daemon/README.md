# i3 Project Event Daemon

Event-driven daemon for i3 window manager project management with unified event tracking from multiple sources.

## Features

### Core Functionality
- **i3 Event Integration**: Real-time window and workspace event tracking via i3 IPC subscriptions
- **Project Context Management**: Automatic window marking based on active project
- **Event Buffer**: Circular buffer with 500-event history

## Event Sources

| Source | Description | Example Event Types |
|--------|-------------|---------------------|
| `i3` | i3 window manager events | `window::new`, `workspace::focus` |
| `ipc` | Daemon IPC commands | `project::switch` |
| `daemon` | Internal daemon events | `daemon::startup` |

## Modules

### Existing Modules
- `daemon.py` - Main event loop and initialization
- `handlers.py` - i3 event handlers (window, workspace, tick events)
- `event_buffer.py` - Circular event buffer with history
- `ipc_server.py` - JSON-RPC IPC server
- `models.py` - EventEntry and data models
- `config.py` - Configuration management
- `state.py` - Daemon state tracking

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        i3 IPC Events                        │
│                     (window, workspace)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
                   ┌───────────────┐
                   │   Handlers    │
                   └───────┬───────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ Event Buffer│
                    │  (500 max)  │
                    └──────┬──────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  IPC Server  │
                    │  (JSON-RPC)  │
                    └──────────────┘
```

## Data Model

### EventEntry

```python
@dataclass
class EventEntry:
    event_id: int
    event_type: str
    timestamp: datetime
    source: str  # "i3" | "ipc" | "daemon"

    # Window/workspace event fields
    window_id: Optional[int]
    workspace_name: Optional[str]
    project_name: Optional[str]
```

## Development

### Testing

```bash
# Run unit tests
pytest tests/i3-project-daemon/unit/

# Run integration tests
pytest tests/i3-project-daemon/integration/

# Run all tests
pytest tests/i3-project-daemon/
```

### Python Standards
- Python 3.11+
- Async/await patterns (asyncio)
- Type hints on all public APIs
- Pydantic for data validation
- pytest for testing
