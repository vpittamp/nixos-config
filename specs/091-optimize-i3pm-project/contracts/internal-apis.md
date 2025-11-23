# Internal Service APIs - Feature 091

**Note**: These are internal Python service APIs, not external HTTP/REST APIs. All services are part of the i3pm daemon process.

## CommandBatchService

**Purpose**: Batch multiple Sway IPC commands for optimized execution

### API

```python
class CommandBatchService:
    """Service for batching and executing Sway IPC commands."""

    async def execute_parallel(
        self,
        conn: Connection,
        commands: List[WindowCommand]
    ) -> List[CommandResult]:
        """Execute independent commands in parallel using asyncio.gather()."""

    async def execute_batch(
        self,
        conn: Connection,
        batch: CommandBatch
    ) -> CommandResult:
        """Execute a command batch as single Sway IPC call."""
```

**Usage**:
```python
service = CommandBatchService()

# Parallel execution (independent commands)
hide_commands = [WindowCommand(...), WindowCommand(...)]
results = await service.execute_parallel(conn, hide_commands)

# Batched execution (dependent commands on same window)
batch = CommandBatch.from_window_state(window_id=123, workspace_num=5, is_floating=True)
result = await service.execute_batch(conn, batch)
```

---

## TreeCacheService

**Purpose**: Cache Sway tree queries with TTL-based expiration

### API

```python
class TreeCacheService:
    """Service for caching Sway tree queries."""

    async def get_tree(self, conn: Connection) -> Con:
        """Get tree from cache or query if expired."""

    def invalidate(self) -> None:
        """Invalidate cache (called on window/workspace events)."""

    def get_stats(self) -> dict:
        """Get cache statistics (hit rate, miss count)."""
```

**Usage**:
```python
cache = TreeCacheService(ttl_ms=100)

# Get tree (cached if available)
tree = await cache.get_tree(conn)

# Invalidate on events
cache.invalidate()  # Called on window close, workspace change

# Monitor performance
stats = cache.get_stats()
# {"hits": 15, "misses": 3, "hit_rate": 0.83}
```

---

## PerformanceTrackerService

**Purpose**: Track and log performance metrics for optimization validation

### API

```python
class PerformanceTrackerService:
    """Service for tracking performance metrics."""

    def start_operation(self, operation: str) -> str:
        """Start tracking an operation, returns operation ID."""

    def end_operation(
        self,
        operation_id: str,
        window_count: int,
        command_count: int,
        parallel_batches: int
    ) -> PerformanceMetrics:
        """End tracking and return metrics."""

    def log_metrics(self, metrics: PerformanceMetrics) -> None:
        """Log metrics to daemon logger."""

    def get_aggregate_stats(self, operation: str, since: datetime) -> dict:
        """Get aggregate statistics for an operation."""
```

**Usage**:
```python
tracker = PerformanceTrackerService()

# Track operation
op_id = tracker.start_operation("filter_windows_for_project")

# ... perform work ...

metrics = tracker.end_operation(
    operation_id=op_id,
    window_count=15,
    command_count=30,
    parallel_batches=2
)

tracker.log_metrics(metrics)
# Logs: "Performance: filter_windows_for_project took 142.35ms (15 windows, 30 commands, 2 batches)"

# Get aggregate stats
stats = tracker.get_aggregate_stats("filter_windows_for_project", since=datetime.now() - timedelta(hours=1))
# {"avg_duration_ms": 155.2, "p95_duration_ms": 198.4, "count": 42}
```

---

## Integration Points

### Modified: window_filter.py

```python
from services.command_batch import CommandBatchService
from services.tree_cache import TreeCacheService
from services.performance_tracker import PerformanceTrackerService

async def filter_windows_for_project(
    conn: Connection,
    windows: List[Con],
    active_project: Optional[str],
    workspace_tracker: Optional[WorkspaceTracker]
) -> None:
    """Filter windows for project with optimized parallel execution."""

    # Initialize services
    batch_service = CommandBatchService()
    tree_cache = TreeCacheService(ttl_ms=100)
    tracker = PerformanceTrackerService()

    op_id = tracker.start_operation("filter_windows_for_project")

    # Get cached tree (eliminates duplicate queries)
    tree = await tree_cache.get_tree(conn)

    # Group windows into hide/restore lists
    windows_to_hide = []
    windows_to_restore = []

    for window in windows:
        # ... existing visibility logic ...
        if should_hide:
            windows_to_hide.append(window)
        else:
            windows_to_restore.append(window)

    # Parallel hide phase
    hide_commands = [
        WindowCommand(window_id=w.id, command_type=CommandType.MOVE_SCRATCHPAD, params={})
        for w in windows_to_hide
    ]
    await batch_service.execute_parallel(conn, hide_commands)

    # Parallel restore phase (with batching for multi-step operations)
    restore_batches = [
        CommandBatch.from_window_state(w.id, get_workspace(w), is_floating(w), get_geometry(w))
        for w in windows_to_restore
    ]

    restore_tasks = [batch_service.execute_batch(conn, batch) for batch in restore_batches]
    await asyncio.gather(*restore_tasks)

    # Track performance
    metrics = tracker.end_operation(
        operation_id=op_id,
        window_count=len(windows),
        command_count=len(hide_commands) + len(restore_batches),
        parallel_batches=2  # hide phase + restore phase
    )
    tracker.log_metrics(metrics)
```

## Error Handling

All services use standard Python exceptions:
- `ValueError`: Invalid parameters or state
- `RuntimeError`: Sway IPC communication errors
- `TimeoutError`: Operation timeout (if implemented)

Services log errors via Python `logging` module:
```python
logger.error(f"Failed to execute command batch: {error}")
```
