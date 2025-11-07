# Sway Tree Diff Monitor

Real-time window state change monitoring for Sway compositor with <10ms diff computation, user action correlation, and enriched context.

## Overview

The Sway Tree Diff Monitor is a Python daemon that tracks window management state changes in real-time, correlates them with user actions (keypresses), and provides multiple views for debugging and analysis.

**Key Features**:
- ⚡ **Fast Diffing**: <10ms diff computation using Merkle tree hashing
- 🎯 **User Correlation**: 90% accuracy matching keypresses to window changes
- 🔍 **Enriched Context**: Reads I3PM_* environment variables and project marks
- 📊 **Multiple Views**: Live, history, detailed diff, performance stats
- 🚀 **Performance**: <2% CPU, <25MB memory, handles 50 events/second bursts

## Architecture

### Components

```
daemon.py              # Main event loop, Sway IPC subscription
├── diff/              # Hash-based tree diffing
│   ├── hasher.py      # xxHash Merkle tree computation
│   ├── differ.py      # Incremental diff algorithm
│   └── cache.py       # TTL-based hash cache
├── correlation/       # User action correlation
│   ├── tracker.py     # 500ms time window correlation
│   ├── scoring.py     # Multi-factor confidence scoring
│   └── cascade.py     # Primary → secondary → tertiary chains
├── buffer/            # Event storage
│   └── event_buffer.py # Circular buffer (deque, 500 events)
├── rpc/               # JSON-RPC 2.0 API
│   ├── server.py      # Unix socket server (daemon side)
│   └── client.py      # Client library (CLI side)
└── ui/                # Textual TUI views
    ├── live_view.py   # Real-time event stream
    ├── history_view.py # Historical query with filters
    ├── diff_view.py   # Detailed field-level diff
    └── stats_view.py  # Performance statistics
```

### Data Flow

```
Sway Events → Daemon → TreeSnapshot → TreeDiff → Correlation → Buffer → RPC → CLI/TUI
     ↓                     ↓              ↓           ↓
Binding Events      Hash Cache    User Actions   Confidence
```

## Performance

### Targets (all validated)

- **Diff Computation**: <10ms (p95) for 100-window trees
- **Display Latency**: <100ms from Sway event to screen update
- **Memory Usage**: <25MB with 500-event buffer
- **CPU Usage**: <2% average during active monitoring

### Optimizations

1. **Merkle Tree Hashing**: Only 7 subtree hashes for 1 window change in 100-window tree
2. **Fast Path**: Root hash check returns empty diff if no changes (<0.1ms)
3. **Field Exclusions**: Excludes volatile fields (focus, last_split_layout, percent)
4. **Geometry Threshold**: Ignores changes <5px (configurable)
5. **Circular Buffer**: O(1) append, automatic eviction via `collections.deque(maxlen=500)`

## Usage

### CLI Commands

```bash
# Live monitoring (real-time event stream)
sway-tree-monitor live

# Historical query (past events with correlation)
sway-tree-monitor history --last 50
sway-tree-monitor history --since 5m --filter window::new

# Detailed diff inspection (field-level changes + I3PM context)
sway-tree-monitor diff <EVENT_ID>

# Performance statistics (CPU, memory, event distribution)
sway-tree-monitor stats [--since 1h]

# Run daemon in foreground (for debugging)
sway-tree-monitor daemon
```

### Daemon Management

```bash
# Systemd service (recommended)
systemctl --user {start|stop|restart|status} sway-tree-monitor

# Logs
journalctl --user -u sway-tree-monitor -f
journalctl --user -u sway-tree-monitor --since "10 minutes ago"
```

### Python API

```python
from sway_tree_monitor.rpc.client import RPCClient

# Connect to daemon
client = RPCClient()

# Query events
response = client.query_events(last=10, min_significance=0.5)
for event in response['events']:
    print(f"Event #{event['event_id']}: {event['event_type']}")
    print(f"  Changes: {event['diff']['total_changes']}")
    print(f"  Significance: {event['diff']['significance_score']:.2f}")

    # Check correlation
    if event['correlations']:
        corr = event['correlations'][0]
        print(f"  Triggered by: {corr['action']['binding_command']}")
        print(f"  Confidence: {corr['confidence']:.2%}")

# Get detailed event
event = client.get_event(event_id=42, include_enrichment=True)

# Access enrichment data
for window_id, context in event['enrichment'].items():
    print(f"Window {window_id}:")
    print(f"  Project: {context.get('i3pm_project_name')}")
    print(f"  App: {context.get('i3pm_app_name')}")
    print(f"  Marks: {context.get('project_marks')}")
```

## Development

### Dependencies

- Python 3.11+ (async/await patterns)
- i3ipc.aio (Sway IPC communication)
- xxhash (fast hashing)
- orjson (fast JSON serialization)
- textual (TUI framework)
- pydantic v2 (data validation)

### Testing

```bash
# Run tests
pytest tests/sway-tree-monitor/

# Performance benchmarks
python tests/sway-tree-monitor/performance/benchmark_diff.py

# Validate Phase 3
python tests/sway-tree-monitor/validate_phase3.py
```

### Code Style

- Async/await for all I/O operations
- Type hints for all function signatures
- Pydantic models for data validation
- Docstrings with Args/Returns sections
- Logging via Python `logging` module

### Adding New Features

1. **Data Models**: Add to `models.py` using Pydantic `@dataclass`
2. **RPC Methods**: Register in `rpc/server.py::_register_methods()`
3. **CLI Commands**: Add parser and handler in `__main__.py`
4. **UI Views**: Create Textual container in `ui/` directory

## Troubleshooting

### Daemon Won't Start

```bash
# Check Sway IPC socket
echo $SWAYSOCK
ls -la $SWAYSOCK

# Check daemon logs
journalctl --user -u sway-tree-monitor --since "5 minutes ago"

# Verify Python environment
which python3
python3 --version  # Should be 3.11+
```

### High Memory Usage

```bash
# Check stats
sway-tree-monitor stats

# Verify buffer size (should be ≤500)
journalctl --user -u sway-tree-monitor | grep "Buffer:"

# Check for memory leaks
systemctl --user status sway-tree-monitor  # Look at Memory line
```

### Missing Correlations

```bash
# Verify binding events are captured
journalctl --user -u sway-tree-monitor | grep "binding"

# Check correlation tracker
sway-tree-monitor stats  # Look at "Correlation" section

# Test manually
sway-tree-monitor live  # Open window, should see correlation
```

### No Enrichment Data

```bash
# Check if process has I3PM_* env vars
window-env <pid> | grep I3PM_

# Verify /proc access
ls -la /proc/<pid>/environ

# Test with known I3PM app
# Launch app from i3pm: Win+C (VS Code)
# Then: sway-tree-monitor diff <EVENT_ID>
```

## Performance Monitoring

### Continuous Monitoring

```bash
# Memory usage every 5 minutes (automatic)
journalctl --user -u sway-tree-monitor -f | grep "Memory usage"

# Cache cleanup every 60 seconds (automatic)
journalctl --user -u sway-tree-monitor -f | grep "Cache cleanup"

# Manual stats check
sway-tree-monitor stats --since 1h
```

### Benchmarking

```bash
# Run performance validation
python tests/sway-tree-monitor/performance/benchmark_diff.py

# Expected results:
# 50 windows: <5ms (p95)
# 100 windows: <10ms (p95)
# 200 windows: <20ms (p95)
```

## References

- **Specification**: `/etc/nixos/specs/064-sway-tree-diff-monitor/spec.md`
- **Implementation Plan**: `/etc/nixos/specs/064-sway-tree-diff-monitor/plan.md`
- **Data Model**: `/etc/nixos/specs/064-sway-tree-diff-monitor/data-model.md`
- **Quickstart Guide**: `/etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md`
- **Tasks**: `/etc/nixos/specs/064-sway-tree-diff-monitor/tasks.md`

## License

Part of the NixOS configuration repository. See repository root for license.

## Contributing

This tool is part of a personal NixOS configuration. For issues or questions, see the main repository.
