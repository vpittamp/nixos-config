"""
Performance Metrics Module

Feature 030: Production Readiness
Task T014: Performance metrics tracking

Tracks latency and timing for key operations:
- Project switch latency
- Window marking latency
- Event processing time
"""

import time
import statistics
from dataclasses import dataclass, field
from typing import Optional, List, Dict
from contextlib import contextmanager
import logging

logger = logging.getLogger(__name__)


@dataclass
class OperationMetrics:
    """Metrics for a specific operation type"""
    operation_name: str
    total_count: int = 0
    total_time_ms: float = 0.0
    min_time_ms: float = float('inf')
    max_time_ms: float = 0.0
    recent_times_ms: List[float] = field(default_factory=list)
    max_history: int = 100  # Keep last 100 measurements

    def record(self, duration_ms: float):
        """Record a new operation measurement"""
        self.total_count += 1
        self.total_time_ms += duration_ms
        self.min_time_ms = min(self.min_time_ms, duration_ms)
        self.max_time_ms = max(self.max_time_ms, duration_ms)

        # Add to recent history
        self.recent_times_ms.append(duration_ms)
        if len(self.recent_times_ms) > self.max_history:
            self.recent_times_ms.pop(0)  # Remove oldest

    @property
    def avg_time_ms(self) -> float:
        """Calculate average operation time"""
        if self.total_count == 0:
            return 0.0
        return self.total_time_ms / self.total_count

    @property
    def median_time_ms(self) -> float:
        """Calculate median operation time from recent samples"""
        if not self.recent_times_ms:
            return 0.0
        return statistics.median(self.recent_times_ms)

    @property
    def p95_time_ms(self) -> float:
        """Calculate 95th percentile operation time"""
        if not self.recent_times_ms:
            return 0.0
        sorted_times = sorted(self.recent_times_ms)
        index = int(len(sorted_times) * 0.95)
        return sorted_times[min(index, len(sorted_times) - 1)]

    @property
    def p99_time_ms(self) -> float:
        """Calculate 99th percentile operation time"""
        if not self.recent_times_ms:
            return 0.0
        sorted_times = sorted(self.recent_times_ms)
        index = int(len(sorted_times) * 0.99)
        return sorted_times[min(index, len(sorted_times) - 1)]

    def to_dict(self) -> dict:
        """Convert metrics to dictionary"""
        return {
            "operation": self.operation_name,
            "count": self.total_count,
            "total_time_ms": round(self.total_time_ms, 2),
            "avg_time_ms": round(self.avg_time_ms, 2),
            "median_time_ms": round(self.median_time_ms, 2),
            "min_time_ms": round(self.min_time_ms, 2) if self.min_time_ms != float('inf') else None,
            "max_time_ms": round(self.max_time_ms, 2),
            "p95_time_ms": round(self.p95_time_ms, 2),
            "p99_time_ms": round(self.p99_time_ms, 2),
        }


@dataclass
class PerformanceMetrics:
    """
    Performance metrics tracker

    Tracks timing for key daemon operations to identify bottlenecks
    and ensure performance targets are met.
    """
    operations: Dict[str, OperationMetrics] = field(default_factory=dict)

    # Performance targets (from spec.md success criteria)
    target_switch_latency_ms: float = 100.0  # SC-010: <100ms
    target_mark_latency_ms: float = 100.0  # SC-010: <100ms
    target_event_processing_ms: float = 50.0  # Internal target

    def record_operation(self, operation_name: str, duration_ms: float):
        """
        Record operation timing

        Args:
            operation_name: Name of operation (e.g., "project_switch")
            duration_ms: Duration in milliseconds
        """
        if operation_name not in self.operations:
            self.operations[operation_name] = OperationMetrics(operation_name)

        self.operations[operation_name].record(duration_ms)

        # Log slow operations
        target = self._get_target_latency(operation_name)
        if duration_ms > target * 2:  # More than 2x target
            logger.warning(
                f"Slow operation detected: {operation_name} took {duration_ms:.2f}ms "
                f"(target: {target:.2f}ms)"
            )

    def _get_target_latency(self, operation_name: str) -> float:
        """Get target latency for operation"""
        targets = {
            "project_switch": self.target_switch_latency_ms,
            "window_mark": self.target_mark_latency_ms,
            "event_process": self.target_event_processing_ms,
        }
        return targets.get(operation_name, 100.0)  # Default 100ms

    def get_operation_metrics(self, operation_name: str) -> Optional[OperationMetrics]:
        """Get metrics for specific operation"""
        return self.operations.get(operation_name)

    def is_meeting_targets(self) -> bool:
        """
        Check if all operations are meeting performance targets

        Returns:
            True if p95 latencies are within targets
        """
        checks = [
            ("project_switch", self.target_switch_latency_ms),
            ("window_mark", self.target_mark_latency_ms),
            ("event_process", self.target_event_processing_ms),
        ]

        for operation_name, target_ms in checks:
            metrics = self.get_operation_metrics(operation_name)
            if metrics and metrics.p95_time_ms > target_ms:
                logger.info(
                    f"Performance target missed: {operation_name} p95={metrics.p95_time_ms:.2f}ms "
                    f"(target: {target_ms:.2f}ms)"
                )
                return False

        return True

    def get_summary(self) -> dict:
        """Get summary of all performance metrics"""
        return {
            "meeting_targets": self.is_meeting_targets(),
            "operations": {
                name: metrics.to_dict()
                for name, metrics in self.operations.items()
            },
            "targets": {
                "project_switch_ms": self.target_switch_latency_ms,
                "window_mark_ms": self.target_mark_latency_ms,
                "event_processing_ms": self.target_event_processing_ms,
            },
        }

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization"""
        return self.get_summary()


# Global performance metrics instance
_performance_metrics: Optional[PerformanceMetrics] = None


def get_performance_metrics() -> PerformanceMetrics:
    """
    Get global performance metrics instance

    Returns:
        Singleton PerformanceMetrics instance
    """
    global _performance_metrics
    if _performance_metrics is None:
        _performance_metrics = PerformanceMetrics()
    return _performance_metrics


def reset_performance_metrics():
    """Reset performance metrics (for testing)"""
    global _performance_metrics
    _performance_metrics = None


@contextmanager
def track_operation(operation_name: str):
    """
    Context manager for tracking operation timing

    Usage:
        with track_operation("project_switch"):
            switch_project("nixos")

    Args:
        operation_name: Name of operation to track
    """
    start_time = time.perf_counter()
    try:
        yield
    finally:
        end_time = time.perf_counter()
        duration_ms = (end_time - start_time) * 1000.0
        get_performance_metrics().record_operation(operation_name, duration_ms)


def record_operation_time(operation_name: str, duration_ms: float):
    """
    Manually record operation timing

    Use this when you can't use the context manager.

    Args:
        operation_name: Name of operation
        duration_ms: Duration in milliseconds
    """
    get_performance_metrics().record_operation(operation_name, duration_ms)
