# i3 Project Event Daemon

Event-driven daemon for i3 window manager project management with unified event tracking from multiple sources.

## Features

### Core Functionality
- **i3 Event Integration**: Real-time window and workspace event tracking via i3 IPC subscriptions
- **Project Context Management**: Automatic window marking based on active project
- **Event Buffer**: Circular buffer with 500-event history

### Linux System Log Integration (Feature 029)

#### systemd Journal Integration (`systemd_query.py`)
Query systemd's user journal for application service events:
- Service start/stop events
- JSON parsing from `journalctl --user --output=json`
- Time-based queries (`--since`, `--until`)
- Application service filtering (app-*.service, *.desktop)
- Graceful degradation when journalctl unavailable

**Usage**:
```bash
i3pm daemon events --source=systemd --since="1 hour ago"
```

#### Process Monitoring (`proc_monitor.py`)
Monitor /proc filesystem for new process spawns:
- 500ms polling interval (configurable)
- Allowlist filtering for development tools
- Sensitive data sanitization in command lines
- Parent PID detection for correlation
- <5% CPU overhead

**Monitored Processes**: rust-analyzer, typescript-language-server, node, python, docker, cargo, etc.

**Usage**:
```bash
i3pm daemon events --source=proc --follow
```

#### Event Correlation (`event_correlator.py`)
Detect relationships between GUI windows and spawned processes:
- Multi-factor scoring (timing, hierarchy, name similarity, workspace)
- Confidence scoring (0.0-1.0 range)
- Parent-child relationship detection via /proc/{pid}/stat
- 80%+ accuracy target

**Usage**:
```bash
i3pm daemon events --correlate --min-confidence=0.6
```

## Event Sources

| Source | Description | Example Event Types |
|--------|-------------|---------------------|
| `i3` | i3 window manager events | `window::new`, `workspace::focus` |
| `ipc` | Daemon IPC commands | `project::switch` |
| `daemon` | Internal daemon events | `daemon::startup` |
| `systemd` | systemd journal events | `systemd::service::start` |
| `proc` | Process monitoring events | `process::start` |

## Modules

### Existing Modules
- `daemon.py` - Main event loop and initialization
- `handlers.py` - i3 event handlers (window, workspace, tick events)
- `event_buffer.py` - Circular event buffer with history
- `ipc_server.py` - JSON-RPC IPC server
- `models.py` - EventEntry and data models
- `config.py` - Configuration management
- `state.py` - Daemon state tracking

### New Modules (Feature 029)
- `systemd_query.py` - systemd journal query functionality
- `proc_monitor.py` - /proc filesystem monitoring
- `event_correlator.py` - Event correlation and scoring

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
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  systemd    │    │ Event Buffer│    │ /proc       │
│  Query      │───▶│  (500 max)  │◀───│ Monitor     │
└─────────────┘    └──────┬──────┘    └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ Correlator   │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  IPC Server  │
                    │  (JSON-RPC)  │
                    └──────────────┘
```

## Data Model

### EventEntry (Extended for Feature 029)

```python
@dataclass
class EventEntry:
    # Core fields (existing)
    event_id: int
    event_type: str
    timestamp: datetime
    source: str  # Extended: "i3" | "ipc" | "daemon" | "systemd" | "proc"

    # systemd fields (new)
    systemd_unit: Optional[str]
    systemd_message: Optional[str]
    systemd_pid: Optional[int]
    journal_cursor: Optional[str]

    # Process fields (new)
    process_pid: Optional[int]
    process_name: Optional[str]
    process_cmdline: Optional[str]  # Sanitized
    process_parent_pid: Optional[int]
    process_start_time: Optional[int]
```

### EventCorrelation (New)

```python
@dataclass
class EventCorrelation:
    correlation_id: int
    parent_event_id: int
    child_event_ids: List[int]
    confidence_score: float  # 0.0-1.0
    time_delta_ms: float
    timing_factor: float
    hierarchy_factor: float
    name_similarity: float
    workspace_match: bool
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

## Performance

- systemd query: <1s response time
- /proc monitoring: <5% CPU usage
- Event stream latency: <2s for all sources
- Memory: <15MB resident

## References

- [Feature 029 Spec](../../../specs/029-linux-system-log/spec.md)
- [Implementation Plan](../../../specs/029-linux-system-log/plan.md)
- [Data Model](../../../specs/029-linux-system-log/data-model.md)
- [Quickstart Guide](../../../specs/029-linux-system-log/quickstart.md)
