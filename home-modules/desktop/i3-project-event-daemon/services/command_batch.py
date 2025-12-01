"""
Command batching service for Feature 091: Optimize i3pm Project Switching Performance.

This service provides async execution of window commands in parallel batches to reduce
project switch latency from 5.3s to under 200ms.

Feature 101 Enhancement: Command execution tracing for debugging.
Feature 102 Enhancement: Publish command events to EventBuffer for Log tab visibility.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import TYPE_CHECKING, Optional, Callable, Awaitable, Any

from ..models.window_command import WindowCommand, CommandBatch, CommandType
from ..models.performance_metrics import OperationMetrics
from datetime import datetime

if TYPE_CHECKING:
    from i3ipc.aio import Connection

logger = logging.getLogger(__name__)

# Feature 102: Type alias for event publishing callback
EventCallback = Callable[[str, dict], Awaitable[None]]

# Feature 102: Module-level event callback for publishing to EventBuffer
_event_callback: Optional[EventCallback] = None


def set_event_callback(callback: EventCallback) -> None:
    """Set the event publishing callback for Feature 102.

    This callback will be invoked for each command event (queued, executed, result, batch)
    to publish events to the EventBuffer for display in the Log tab.

    Args:
        callback: Async function that accepts (event_type: str, context: dict)
    """
    global _event_callback
    _event_callback = callback
    logger.debug("[Feature 102] Event callback set for command events")


async def _trace_command_event(
    window_id: int,
    event_type: str,
    description: str,
    context: dict,
    *,
    correlation_id: Optional[str] = None,
    causality_depth: int = 0,
) -> None:
    """Record a command-related trace event.

    Feature 101 Enhancement: Provides visibility into command execution.
    Uses record_window_event to target only traces watching this specific window.

    Feature 102 Enhancement: Also publishes to EventBuffer for Log tab visibility.
    """
    # Feature 102: Publish to EventBuffer for Log tab (T018-T021)
    if _event_callback:
        try:
            await _event_callback(event_type, {
                "window_id": window_id,
                "description": description,
                "correlation_id": correlation_id,
                "causality_depth": causality_depth,
                **context,
            })
        except Exception as e:
            logger.debug(f"[Feature 102] Event callback error (non-fatal): {e}")

    # Feature 101: Record to window tracer
    try:
        from .window_tracer import get_tracer, TraceEventType

        tracer = get_tracer()
        if not tracer:
            return

        type_map = {
            "command::queued": TraceEventType.COMMAND_QUEUED,
            "command::executed": TraceEventType.COMMAND_EXECUTED,
            "command::result": TraceEventType.COMMAND_RESULT,
            "command::batch": TraceEventType.COMMAND_BATCH,
        }
        trace_type = type_map.get(event_type)
        if not trace_type:
            return

        # Record event only for traces watching this window
        await tracer.record_window_event(window_id, trace_type, description, context)
    except Exception as e:
        # Never let tracing break command execution
        logger.debug(f"[Feature 101] Trace error (non-fatal): {e}")


class CommandResult:
    """Result of a Sway IPC command execution.

    Attributes:
        success: Whether the command succeeded
        command: The original command string
        window_id: Target window ID
        error: Optional error message
        duration_ms: Command execution time in milliseconds
    """

    def __init__(
        self,
        success: bool,
        command: str,
        window_id: int,
        error: Optional[str] = None,
        duration_ms: float = 0.0,
    ):
        self.success = success
        self.command = command
        self.window_id = window_id
        self.error = error
        self.duration_ms = duration_ms

    def __repr__(self) -> str:
        status = "✓" if self.success else "✗"
        return f"CommandResult({status} {self.command[:50]}... {self.duration_ms:.1f}ms)"


class CommandBatchService:
    """Service for batching and executing Sway IPC commands.

    This service provides two primary optimization strategies:
    1. Parallel execution: Independent commands executed via asyncio.gather()
    2. Command batching: Sequential commands chained with semicolons

    Example:
        >>> service = CommandBatchService(connection)
        >>> commands = [
        ...     WindowCommand(window_id=123, command_type=CommandType.MOVE_WORKSPACE, params={"workspace_number": 3}),
        ...     WindowCommand(window_id=456, command_type=CommandType.MOVE_SCRATCHPAD, params={}),
        ... ]
        >>> results = await service.execute_parallel(commands)
    """

    def __init__(self, conn: Connection):
        """Initialize the command batch service.

        Args:
            conn: Active i3ipc Connection instance
        """
        self.conn = conn
        self._execution_count = 0
        self._total_duration_ms = 0.0

    async def execute_parallel(
        self,
        commands: list[WindowCommand],
        operation_type: str = "parallel",
        *,
        correlation_id: Optional[str] = None,
        causality_depth: int = 0,
    ) -> tuple[list[CommandResult], OperationMetrics]:
        """Execute independent commands in parallel using asyncio.gather().

        This is the primary optimization for Feature 091. Commands targeting different
        windows are executed concurrently to minimize total latency.

        Feature 091 US2 (T028): For large window counts (>30), uses chunked execution
        to prevent IPC congestion while maintaining parallel performance.

        Feature 102: Added correlation_id and causality_depth for event tracing.

        Args:
            commands: List of WindowCommand instances to execute
            operation_type: Type of operation for metrics (hide/restore/switch)
            correlation_id: Optional correlation ID for causality tracking
            causality_depth: Current depth in causality chain (default: 0)

        Returns:
            Tuple of (results list, operation metrics)

        Example:
            >>> # Execute 10 window moves in parallel (instead of sequentially)
            >>> commands = [WindowCommand(...) for _ in range(10)]
            >>> results, metrics = await service.execute_parallel(commands)
            >>> assert metrics.duration_ms < 200  # Target: <200ms
        """
        if not commands:
            return [], self._empty_metrics(operation_type)

        start_time = datetime.now()
        start_perf = asyncio.get_event_loop().time()

        # Feature 102: Log command::queued events for each command (T018)
        for cmd in commands:
            await _trace_command_event(
                cmd.window_id,
                "command::queued",
                f"Queued: {cmd.command_type.value}",
                {
                    "command": cmd.to_sway_command(),
                    "command_type": cmd.command_type.value,
                    "operation_type": operation_type,
                },
                correlation_id=correlation_id,
                causality_depth=causality_depth,
            )

        # Feature 091 US2 T028: Adaptive batching for large window counts
        # For >30 windows, execute in chunks to prevent IPC congestion
        chunk_size = 50  # Execute max 50 commands concurrently
        if len(commands) > chunk_size:
            logger.info(
                f"[Feature 091 US2] Large batch ({len(commands)} commands), "
                f"using chunked execution (chunk size: {chunk_size})"
            )

            all_results = []
            for i in range(0, len(commands), chunk_size):
                chunk = commands[i : i + chunk_size]
                logger.debug(
                    f"[Feature 091 US2] Executing chunk {i // chunk_size + 1} "
                    f"({len(chunk)} commands)"
                )

                tasks = [
                    self._execute_single_command(
                        cmd,
                        correlation_id=correlation_id,
                        causality_depth=causality_depth + 1,
                    )
                    for cmd in chunk
                ]
                chunk_results = await asyncio.gather(*tasks, return_exceptions=True)
                all_results.extend(chunk_results)

            results = all_results
        else:
            # Small/medium batches: execute all at once
            tasks = [
                self._execute_single_command(
                    cmd,
                    correlation_id=correlation_id,
                    causality_depth=causality_depth + 1,
                )
                for cmd in commands
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)

        # Convert exceptions to failed results
        processed_results: list[CommandResult] = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                processed_results.append(
                    CommandResult(
                        success=False,
                        command=commands[i].to_sway_command(),
                        window_id=commands[i].window_id,
                        error=str(result),
                    )
                )
            else:
                processed_results.append(result)

        end_perf = asyncio.get_event_loop().time()
        end_time = datetime.now()
        duration_ms = (end_perf - start_perf) * 1000

        # Update service statistics
        self._execution_count += 1
        self._total_duration_ms += duration_ms

        # Create operation metrics
        metrics = OperationMetrics(
            operation_type=operation_type,
            start_time=start_time,
            end_time=end_time,
            duration_ms=duration_ms,
            window_count=len(set(cmd.window_id for cmd in commands)),
            command_count=len(commands),
            parallel_batches=1,  # Single gather() call
            cache_hits=0,  # Set by caller if using tree cache
            cache_misses=0,
        )

        # Log performance
        success_count = sum(1 for r in processed_results if r.success)
        logger.info(
            f"[Feature 091] Parallel execution: {success_count}/{len(commands)} succeeded "
            f"in {duration_ms:.1f}ms ({len(commands)} commands, {metrics.window_count} windows)"
        )

        return processed_results, metrics

    async def execute_batch(
        self,
        batch: CommandBatch,
        *,
        correlation_id: Optional[str] = None,
        causality_depth: int = 0,
    ) -> tuple[CommandResult, OperationMetrics]:
        """Execute a command batch as sequential separate IPC calls.

        IMPORTANT: Changed from semicolon-batched commands to sequential separate calls
        to fix floating window restoration issue (see FLOATING_WINDOW_FIX_RESEARCH.md).

        When restoring windows from scratchpad, semicolon-batched commands like:
            [con_id=X] move workspace 1; floating disable

        Don't work reliably because:
        1. Scratchpad windows are always floating (Sway enforces this)
        2. The 'move workspace' exits scratchpad but window retains floating state
        3. The 'floating disable' executes too quickly (before window settles)
        4. Result: Floating state change is ignored

        Solution: Execute each command as a separate IPC call with proper sequencing.
        Performance impact: +10-20ms per window (still meets <200ms target across all windows).

        Feature 102: Added correlation_id and causality_depth for event tracing.

        Args:
            batch: CommandBatch instance with commands to execute
            correlation_id: Optional correlation ID for causality tracking
            causality_depth: Current depth in causality chain

        Returns:
            Tuple of (result, operation metrics)

        Example:
            >>> # Sequential execution: move, then floating, then resize, then position
            >>> batch = CommandBatch.from_window_state(
            ...     window_id=123,
            ...     workspace_num=3,
            ...     is_floating=False,  # Will execute 'floating disable' separately
            ...     geometry=None
            ... )
            >>> result, metrics = await service.execute_batch(batch)
        """
        if len(batch.commands) == 0:
            raise ValueError("Cannot execute empty command batch")

        start_time = datetime.now()
        start_perf = asyncio.get_event_loop().time()

        # Feature 101/102 Enhancement: Trace batch start with full command list
        command_types = [cmd.command_type.value for cmd in batch.commands]
        await _trace_command_event(
            batch.window_id,
            "command::batch",
            f"Batch: {len(batch.commands)} commands ({', '.join(command_types)})",
            {
                "commands": [cmd.to_sway_command() for cmd in batch.commands],
                "command_types": command_types,
                "batch_count": len(batch.commands),
            },
            correlation_id=correlation_id,
            causality_depth=causality_depth,
        )

        # Execute commands sequentially (separate IPC calls)
        command_results: list[CommandResult] = []
        all_success = True
        combined_error = None

        for cmd in batch.commands:
            cmd_result = await self._execute_single_command(
                cmd,
                correlation_id=correlation_id,
                causality_depth=causality_depth + 1,
            )
            command_results.append(cmd_result)

            if not cmd_result.success:
                all_success = False
                if combined_error is None:
                    combined_error = cmd_result.error
                else:
                    combined_error += f"; {cmd_result.error}"

                logger.warning(
                    f"[Feature 091] Command failed in sequence: {cmd.to_sway_command()} - {cmd_result.error}"
                )

        end_perf = asyncio.get_event_loop().time()
        end_time = datetime.now()
        duration_ms = (end_perf - start_perf) * 1000

        # Create summary result for the entire batch
        command_summary = f"[Sequential: {len(batch.commands)} commands for window {batch.window_id}]"
        result = CommandResult(
            success=all_success,
            command=command_summary,
            window_id=batch.window_id,
            error=combined_error,
            duration_ms=duration_ms,
        )

        metrics = OperationMetrics(
            operation_type="batch_sequential",
            start_time=start_time,
            end_time=end_time,
            duration_ms=duration_ms,
            window_count=1,
            command_count=len(batch.commands),
            parallel_batches=1,
            cache_hits=0,
            cache_misses=0,
        )

        logger.debug(
            f"[Feature 091] Sequential batch complete: {len(batch.commands)} commands "
            f"for window {batch.window_id} in {duration_ms:.1f}ms (success={all_success})"
        )

        return result, metrics

    async def _execute_single_command(
        self,
        cmd: WindowCommand,
        *,
        correlation_id: Optional[str] = None,
        causality_depth: int = 0,
    ) -> CommandResult:
        """Execute a single window command.

        Args:
            cmd: WindowCommand to execute
            correlation_id: Optional correlation ID for causality tracking (Feature 102)
            causality_depth: Current depth in causality chain (Feature 102)

        Returns:
            CommandResult with execution status
        """
        command_str = cmd.to_sway_command()
        start_perf = asyncio.get_event_loop().time()

        # Feature 101/102 Enhancement: Trace command execution
        await _trace_command_event(
            cmd.window_id,
            "command::executed",
            f"Executing: {cmd.command_type.value}",
            {"command": command_str, "command_type": cmd.command_type.value},
            correlation_id=correlation_id,
            causality_depth=causality_depth,
        )

        try:
            await self.conn.command(command_str)
            success = True
            error = None
        except Exception as e:
            success = False
            error = str(e)
            logger.debug(
                f"[Feature 091] Command failed: {command_str[:50]}... Error: {error}"
            )

        end_perf = asyncio.get_event_loop().time()
        duration_ms = (end_perf - start_perf) * 1000

        # Feature 101/102 Enhancement: Trace command result
        await _trace_command_event(
            cmd.window_id,
            "command::result",
            f"{'✓' if success else '✗'} {cmd.command_type.value} ({duration_ms:.1f}ms)",
            {
                "command": command_str,
                "success": success,
                "error": error,
                "duration_ms": duration_ms,
            },
            correlation_id=correlation_id,
            causality_depth=causality_depth,
        )

        return CommandResult(
            success=success,
            command=command_str,
            window_id=cmd.window_id,
            error=error,
            duration_ms=duration_ms,
        )

    def _empty_metrics(self, operation_type: str) -> OperationMetrics:
        """Create empty metrics for zero-command operations."""
        now = datetime.now()
        return OperationMetrics(
            operation_type=operation_type,
            start_time=now,
            end_time=now,
            duration_ms=0.0,
            window_count=0,
            command_count=0,
            parallel_batches=0,
            cache_hits=0,
            cache_misses=0,
        )

    @property
    def avg_execution_time_ms(self) -> float:
        """Calculate average execution time across all operations."""
        if self._execution_count == 0:
            return 0.0
        return self._total_duration_ms / self._execution_count

    def reset_stats(self) -> None:
        """Reset service statistics."""
        self._execution_count = 0
        self._total_duration_ms = 0.0
