# Data Model - Optimize i3pm Project Switching Performance

**Feature**: 091-optimize-i3pm-project
**Date**: 2025-11-22

## Overview

This document defines the data models used for performance optimization in the i3pm project switching system. All models use Pydantic for validation and type safety.

## Core Models

### 1. WindowCommand

Represents a single Sway IPC command to be executed on a window.

```python
from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum

class CommandType(str, Enum):
    """Type of window command operation."""
    MOVE_WORKSPACE = "move_workspace"
    MOVE_SCRATCHPAD = "move_scratchpad"
    FLOATING_ENABLE = "floating_enable"
    FLOATING_DISABLE = "floating_disable"
    RESIZE = "resize"
    MOVE_POSITION = "move_position"
    FOCUS = "focus"

class WindowCommand(BaseModel):
    """Single Sway IPC command for a window."""
    window_id: int = Field(..., description="Sway container/window ID")
    command_type: CommandType = Field(..., description="Type of command")
    params: dict[str, any] = Field(default_factory=dict, description="Command parameters")

    def to_sway_command(self) -> str:
        """Generate Sway IPC command string."""
        selector = f"[con_id={self.window_id}]"

        match self.command_type:
            case CommandType.MOVE_WORKSPACE:
                workspace_num = self.params["workspace_number"]
                return f"{selector} move workspace number {workspace_num}"

            case CommandType.MOVE_SCRATCHPAD:
                return f"{selector} move scratchpad"

            case CommandType.FLOATING_ENABLE:
                return f"{selector} floating enable"

            case CommandType.FLOATING_DISABLE:
                return f"{selector} floating disable"

            case CommandType.RESIZE:
                width = self.params["width"]
                height = self.params["height"]
                return f"{selector} resize set {width} px {height} px"

            case CommandType.MOVE_POSITION:
                x = self.params["x"]
                y = self.params["y"]
                return f"{selector} move position {x} px {y} px"

            case CommandType.FOCUS:
                return f"{selector} focus"

    class Config:
        frozen = True  # Immutable
```

**Usage Example**:
```python
cmd = WindowCommand(
    window_id=12345,
    command_type=CommandType.MOVE_WORKSPACE,
    params={"workspace_number": 3}
)
sway_cmd = cmd.to_sway_command()  # "[con_id=12345] move workspace number 3"
```

---

### 2. CommandBatch

Represents a batch of related commands that can be executed together.

```python
from pydantic import BaseModel, Field
from typing import List

class CommandBatch(BaseModel):
    """Batch of commands that can be executed together."""
    window_id: int = Field(..., description="Target window ID")
    commands: List[WindowCommand] = Field(..., description="Commands in execution order")
    can_batch: bool = Field(True, description="Whether commands can be batched into single IPC call")

    def to_batched_command(self) -> str:
        """Generate single batched Sway command with semicolons."""
        if not self.can_batch or len(self.commands) == 0:
            raise ValueError("Cannot batch these commands")

        # All commands must target same window
        if not all(cmd.window_id == self.window_id for cmd in self.commands):
            raise ValueError("All commands in batch must target same window")

        # Generate commands without selector (we'll add it once)
        cmd_parts = []
        selector = f"[con_id={self.window_id}]"

        for cmd in self.commands:
            sway_cmd = cmd.to_sway_command()
            # Remove selector prefix if present
            cmd_text = sway_cmd.replace(selector, "").strip()
            cmd_parts.append(cmd_text)

        # Join with semicolons and add selector once
        return f"{selector} {'; '.join(cmd_parts)}"

    @classmethod
    def from_window_state(cls, window_id: int, workspace_num: int, is_floating: bool,
                          geometry: Optional[dict] = None) -> "CommandBatch":
        """Create command batch for restoring a window."""
        commands = [
            WindowCommand(
                window_id=window_id,
                command_type=CommandType.MOVE_WORKSPACE,
                params={"workspace_number": workspace_num}
            )
        ]

        if is_floating:
            commands.append(WindowCommand(
                window_id=window_id,
                command_type=CommandType.FLOATING_ENABLE,
                params={}
            ))

            if geometry:
                commands.append(WindowCommand(
                    window_id=window_id,
                    command_type=CommandType.RESIZE,
                    params={"width": geometry["width"], "height": geometry["height"]}
                ))
                commands.append(WindowCommand(
                    window_id=window_id,
                    command_type=CommandType.MOVE_POSITION,
                    params={"x": geometry["x"], "y": geometry["y"]}
                ))
        else:
            commands.append(WindowCommand(
                window_id=window_id,
                command_type=CommandType.FLOATING_DISABLE,
                params={}
            ))

        return cls(window_id=window_id, commands=commands, can_batch=True)
```

**Usage Example**:
```python
batch = CommandBatch.from_window_state(
    window_id=12345,
    workspace_num=3,
    is_floating=True,
    geometry={"x": 100, "y": 200, "width": 800, "height": 600}
)

batched_cmd = batch.to_batched_command()
# "[con_id=12345] move workspace number 3; floating enable; resize set 800 px 600 px; move position 100 px 200 px"
```

---

### 3. TreeCacheEntry

Represents a cached Sway tree snapshot with TTL expiration.

```python
from pydantic import BaseModel, Field
from typing import Optional
from i3ipc.aio import Con
import time

class TreeCacheEntry(BaseModel):
    """Cached Sway tree snapshot with expiration."""
    tree: Optional[Con] = Field(None, description="Cached tree structure")
    timestamp: float = Field(default_factory=time.perf_counter, description="Cache timestamp (seconds)")
    ttl_seconds: float = Field(0.1, description="Time-to-live in seconds (default 100ms)")

    def is_expired(self) -> bool:
        """Check if cache entry has expired."""
        if self.tree is None:
            return True
        age = time.perf_counter() - self.timestamp
        return age > self.ttl_seconds

    def invalidate(self) -> None:
        """Invalidate cache entry."""
        self.tree = None
        self.timestamp = 0

    class Config:
        arbitrary_types_allowed = True  # Allow i3ipc Con type
```

**Usage Example**:
```python
cache = TreeCacheEntry(tree=await conn.get_tree())

# Check if expired
if cache.is_expired():
    cache.tree = await conn.get_tree()
    cache.timestamp = time.perf_counter()
```

---

### 4. PerformanceMetrics

Tracks performance metrics for project switching operations.

```python
from pydantic import BaseModel, Field
from typing import List, Optional
from statistics import mean, stdev

class PerformanceMetrics(BaseModel):
    """Performance tracking for project switch operations."""
    operation: str = Field(..., description="Operation name")
    duration_ms: float = Field(..., description="Duration in milliseconds")
    window_count: int = Field(..., description="Number of windows processed")
    command_count: int = Field(..., description="Number of Sway commands executed")
    parallel_batches: int = Field(..., description="Number of parallel batches executed")
    cache_hits: int = Field(0, description="Number of tree cache hits")
    cache_misses: int = Field(0, description="Number of tree cache misses")

    @classmethod
    def aggregate(cls, metrics_list: List["PerformanceMetrics"]) -> dict:
        """Calculate aggregate statistics from multiple metrics."""
        if not metrics_list:
            return {}

        durations = [m.duration_ms for m in metrics_list]
        return {
            "count": len(metrics_list),
            "avg_duration_ms": mean(durations),
            "std_duration_ms": stdev(durations) if len(durations) > 1 else 0,
            "min_duration_ms": min(durations),
            "max_duration_ms": max(durations),
            "p95_duration_ms": sorted(durations)[int(len(durations) * 0.95)] if len(durations) >= 20 else None,
            "total_windows": sum(m.window_count for m in metrics_list),
            "total_commands": sum(m.command_count for m in metrics_list),
            "cache_hit_rate": sum(m.cache_hits for m in metrics_list) / max(sum(m.cache_hits + m.cache_misses for m in metrics_list), 1)
        }
```

**Usage Example**:
```python
metrics = PerformanceMetrics(
    operation="project_switch",
    duration_ms=185.3,
    window_count=12,
    command_count=24,
    parallel_batches=2,
    cache_hits=3,
    cache_misses=1
)

# Aggregate multiple runs
runs = [metrics1, metrics2, metrics3, ...]
stats = PerformanceMetrics.aggregate(runs)
# stats["avg_duration_ms"] == 192.4
```

---

## Data Flow

```
User: i3pm project switch <name>
    ↓
filter_windows_for_project()
    ↓
1. Query tree (with caching) → TreeCacheEntry
2. Group windows by operation → List[WindowCommand]
3. Create batches for multi-step ops → List[CommandBatch]
4. Execute hide commands in parallel → asyncio.gather()
5. Execute restore batches → asyncio.gather()
    ↓
Track performance → PerformanceMetrics
    ↓
Log metrics → journalctl
```

## Validation Rules

1. **WindowCommand**: `window_id` must be positive integer, `command_type` must be valid enum, params validated per command type
2. **CommandBatch**: All commands must target same `window_id`, at least one command required
3. **TreeCacheEntry**: `ttl_seconds` must be positive, tree can be None (invalidated state)
4. **PerformanceMetrics**: All counts must be non-negative, duration must be positive

## Migration Notes

- Existing `window_filter.py` uses direct `await conn.command()` calls - will be replaced with `WindowCommand` models
- No database migration required - all models are in-memory only
- Pydantic models provide runtime validation and type safety for free
