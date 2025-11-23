"""
Command batching service for Feature 091: Optimize i3pm Project Switching Performance.

This service provides async execution of window commands in parallel batches to reduce
project switch latency from 5.3s to under 200ms.
"""

from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Optional

from ..models.window_command import WindowCommand, CommandBatch, CommandType
from ..models.performance_metrics import OperationMetrics
from datetime import datetime

if TYPE_CHECKING:
    from i3ipc.aio import Connection

logger = logging.getLogger(__name__)


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
        self, commands: list[WindowCommand], operation_type: str = "parallel"
    ) -> tuple[list[CommandResult], OperationMetrics]:
        """Execute independent commands in parallel using asyncio.gather().

        This is the primary optimization for Feature 091. Commands targeting different
        windows are executed concurrently to minimize total latency.

        Feature 091 US2 (T028): For large window counts (>30), uses chunked execution
        to prevent IPC congestion while maintaining parallel performance.

        Args:
            commands: List of WindowCommand instances to execute
            operation_type: Type of operation for metrics (hide/restore/switch)

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

                tasks = [self._execute_single_command(cmd) for cmd in chunk]
                chunk_results = await asyncio.gather(*tasks, return_exceptions=True)
                all_results.extend(chunk_results)

            results = all_results
        else:
            # Small/medium batches: execute all at once
            tasks = [self._execute_single_command(cmd) for cmd in commands]
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
        self, batch: CommandBatch
    ) -> tuple[CommandResult, OperationMetrics]:
        """Execute a command batch as single Sway IPC call.

        Combines multiple commands targeting the same window into a single IPC message
        using semicolon chaining. This reduces round-trip latency for sequential operations.

        Args:
            batch: CommandBatch instance with commands to execute

        Returns:
            Tuple of (result, operation metrics)

        Example:
            >>> # Batch: move + floating + resize in single IPC call
            >>> batch = CommandBatch.from_window_state(
            ...     window_id=123,
            ...     workspace_num=3,
            ...     is_floating=True,
            ...     geometry={"x": 100, "y": 200, "width": 800, "height": 600}
            ... )
            >>> result, metrics = await service.execute_batch(batch)
        """
        if not batch.can_batch or len(batch.commands) == 0:
            raise ValueError("Cannot batch these commands")

        start_time = datetime.now()
        start_perf = asyncio.get_event_loop().time()

        batched_command = batch.to_batched_command()

        try:
            await self.conn.command(batched_command)
            success = True
            error = None
        except Exception as e:
            success = False
            error = str(e)
            logger.error(
                f"[Feature 091] Batch execution failed: {batched_command[:100]}... Error: {error}"
            )

        end_perf = asyncio.get_event_loop().time()
        end_time = datetime.now()
        duration_ms = (end_perf - start_perf) * 1000

        result = CommandResult(
            success=success,
            command=batched_command,
            window_id=batch.window_id,
            error=error,
            duration_ms=duration_ms,
        )

        metrics = OperationMetrics(
            operation_type="batch",
            start_time=start_time,
            end_time=end_time,
            duration_ms=duration_ms,
            window_count=1,
            command_count=len(batch.commands),
            parallel_batches=1,
            cache_hits=0,
            cache_misses=0,
        )

        return result, metrics

    async def _execute_single_command(self, cmd: WindowCommand) -> CommandResult:
        """Execute a single window command.

        Args:
            cmd: WindowCommand to execute

        Returns:
            CommandResult with execution status
        """
        command_str = cmd.to_sway_command()
        start_perf = asyncio.get_event_loop().time()

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
