"""
Performance metrics models for Feature 091: Optimize i3pm Project Switching Performance.

This module provides Pydantic models for tracking and reporting performance metrics
during project switching operations.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class OperationMetrics(BaseModel):
    """Metrics for a single operation (hide/restore/switch).

    Attributes:
        operation_type: Type of operation (hide, restore, switch)
        start_time: Operation start timestamp
        end_time: Operation end timestamp
        duration_ms: Total duration in milliseconds
        window_count: Number of windows affected
        command_count: Number of Sway IPC commands executed
        parallel_batches: Number of parallel batches executed
        cache_hits: Number of tree cache hits
        cache_misses: Number of tree cache misses
    """

    operation_type: str = Field(..., description="Operation type (hide/restore/switch)")
    start_time: datetime = Field(..., description="Operation start timestamp")
    end_time: datetime = Field(..., description="Operation end timestamp")
    duration_ms: float = Field(..., description="Total duration in milliseconds", ge=0)
    window_count: int = Field(0, description="Number of windows affected", ge=0)
    command_count: int = Field(0, description="Number of Sway IPC commands executed", ge=0)
    parallel_batches: int = Field(0, description="Number of parallel batches executed", ge=0)
    cache_hits: int = Field(0, description="Number of tree cache hits", ge=0)
    cache_misses: int = Field(0, description="Number of tree cache misses", ge=0)

    @property
    def avg_duration_per_window(self) -> float:
        """Calculate average duration per window in milliseconds."""
        if self.window_count == 0:
            return 0.0
        return self.duration_ms / self.window_count

    @property
    def cache_hit_rate(self) -> float:
        """Calculate cache hit rate as percentage."""
        total = self.cache_hits + self.cache_misses
        if total == 0:
            return 0.0
        return (self.cache_hits / total) * 100

    def meets_performance_target(self, target_ms: float) -> bool:
        """Check if operation meets performance target.

        Args:
            target_ms: Target duration in milliseconds

        Returns:
            True if duration is under target
        """
        return self.duration_ms <= target_ms


class ProjectSwitchMetrics(BaseModel):
    """Comprehensive metrics for a project switch operation.

    Attributes:
        project_from: Source project name (or None for global mode)
        project_to: Target project name (or None for global mode)
        total_duration_ms: Total switch duration in milliseconds
        hide_metrics: Metrics for hiding windows from old project
        restore_metrics: Metrics for restoring windows in new project
        timestamp: When the switch occurred
    """

    project_from: Optional[str] = Field(None, description="Source project name")
    project_to: Optional[str] = Field(None, description="Target project name")
    total_duration_ms: float = Field(..., description="Total switch duration in milliseconds", ge=0)
    hide_metrics: Optional[OperationMetrics] = Field(None, description="Hide operation metrics")
    restore_metrics: Optional[OperationMetrics] = Field(None, description="Restore operation metrics")
    timestamp: datetime = Field(default_factory=datetime.now, description="Switch timestamp")

    @property
    def total_windows_affected(self) -> int:
        """Calculate total number of windows affected."""
        total = 0
        if self.hide_metrics:
            total += self.hide_metrics.window_count
        if self.restore_metrics:
            total += self.restore_metrics.window_count
        return total

    @property
    def total_commands_executed(self) -> int:
        """Calculate total number of Sway IPC commands executed."""
        total = 0
        if self.hide_metrics:
            total += self.hide_metrics.command_count
        if self.restore_metrics:
            total += self.restore_metrics.command_count
        return total

    @property
    def parallelization_efficiency(self) -> float:
        """Calculate parallelization efficiency.

        Returns the ratio of commands to batches. Higher is better.
        Example: 60 commands in 10 batches = 6.0 efficiency
        """
        total_batches = 0
        if self.hide_metrics:
            total_batches += self.hide_metrics.parallel_batches
        if self.restore_metrics:
            total_batches += self.restore_metrics.parallel_batches

        if total_batches == 0:
            return 0.0

        return self.total_commands_executed / total_batches

    def meets_performance_target(self, target_ms: float = 200.0) -> bool:
        """Check if switch meets performance target.

        Args:
            target_ms: Target duration in milliseconds (default: 200ms)

        Returns:
            True if total duration is under target
        """
        return self.total_duration_ms <= target_ms

    def to_summary_dict(self) -> dict:
        """Convert metrics to summary dictionary for logging.

        Returns:
            Dictionary with key metrics for logging/debugging
        """
        return {
            "switch": f"{self.project_from or 'global'} → {self.project_to or 'global'}",
            "duration_ms": round(self.total_duration_ms, 2),
            "windows": self.total_windows_affected,
            "commands": self.total_commands_executed,
            "meets_target": self.meets_performance_target(),
            "efficiency": round(self.parallelization_efficiency, 2),
            "timestamp": self.timestamp.isoformat(),
        }


class PerformanceSnapshot(BaseModel):
    """Snapshot of performance statistics over time.

    Used for tracking performance trends and identifying regressions.

    Attributes:
        total_switches: Total number of project switches recorded
        avg_duration_ms: Average switch duration in milliseconds
        p50_duration_ms: Median switch duration
        p95_duration_ms: 95th percentile switch duration
        p99_duration_ms: 99th percentile switch duration
        min_duration_ms: Minimum switch duration
        max_duration_ms: Maximum switch duration
        switches_under_200ms: Count of switches under 200ms target
        switches_under_300ms: Count of switches under 300ms
        avg_cache_hit_rate: Average cache hit rate percentage
        snapshot_time: When this snapshot was taken
    """

    total_switches: int = Field(0, description="Total switches recorded", ge=0)
    avg_duration_ms: float = Field(0.0, description="Average duration", ge=0)
    p50_duration_ms: float = Field(0.0, description="Median duration", ge=0)
    p95_duration_ms: float = Field(0.0, description="95th percentile duration", ge=0)
    p99_duration_ms: float = Field(0.0, description="99th percentile duration", ge=0)
    min_duration_ms: float = Field(0.0, description="Minimum duration", ge=0)
    max_duration_ms: float = Field(0.0, description="Maximum duration", ge=0)
    switches_under_200ms: int = Field(0, description="Switches under 200ms", ge=0)
    switches_under_300ms: int = Field(0, description="Switches under 300ms", ge=0)
    avg_cache_hit_rate: float = Field(0.0, description="Average cache hit rate", ge=0, le=100)
    snapshot_time: datetime = Field(default_factory=datetime.now, description="Snapshot timestamp")

    @property
    def target_compliance_rate(self) -> float:
        """Calculate percentage of switches meeting 200ms target."""
        if self.total_switches == 0:
            return 0.0
        return (self.switches_under_200ms / self.total_switches) * 100

    @property
    def performance_summary(self) -> str:
        """Generate human-readable performance summary."""
        if self.total_switches == 0:
            return "No data"

        target_rate = self.target_compliance_rate
        return (
            f"{self.avg_duration_ms:.0f}ms avg, "
            f"{self.p95_duration_ms:.0f}ms p95, "
            f"{target_rate:.0f}% under 200ms target"
        )
