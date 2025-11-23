"""
Performance tracking service for Feature 091: Optimize i3pm Project Switching Performance.

This service tracks project switch performance metrics and provides real-time monitoring
to ensure the <200ms target is consistently met.
"""

from __future__ import annotations

import logging
from typing import Optional
from collections import deque
from datetime import datetime

from ..models.performance_metrics import (
    ProjectSwitchMetrics,
    PerformanceSnapshot,
    OperationMetrics,
)

logger = logging.getLogger(__name__)


class PerformanceTrackerService:
    """Service for tracking and analyzing project switch performance.

    This service maintains a sliding window of recent project switches and provides
    performance analysis to detect regressions and ensure targets are met.

    Attributes:
        max_history: Maximum number of switches to track
        target_ms: Performance target in milliseconds (default: 200ms)

    Example:
        >>> tracker = PerformanceTrackerService(max_history=100)
        >>> metrics = ProjectSwitchMetrics(...)
        >>> tracker.record_switch(metrics)
        >>> snapshot = tracker.get_snapshot()
        >>> print(snapshot.performance_summary)
        "180ms avg, 195ms p95, 92% under 200ms target"
    """

    def __init__(self, max_history: int = 100, target_ms: float = 200.0):
        """Initialize the performance tracker.

        Args:
            max_history: Maximum number of switch records to keep
            target_ms: Performance target in milliseconds
        """
        self.max_history = max_history
        self.target_ms = target_ms
        self._history: deque[ProjectSwitchMetrics] = deque(maxlen=max_history)
        self._total_switches = 0
        self._regression_warnings = 0

    def record_switch(self, metrics: ProjectSwitchMetrics) -> None:
        """Record a project switch operation.

        Args:
            metrics: ProjectSwitchMetrics for the completed switch
        """
        self._history.append(metrics)
        self._total_switches += 1

        # Check for performance regression
        if not metrics.meets_performance_target(self.target_ms):
            self._regression_warnings += 1
            logger.warning(
                f"[Feature 091] Performance regression detected: "
                f"{metrics.total_duration_ms:.1f}ms (target: {self.target_ms}ms) "
                f"for switch {metrics.project_from or 'global'} → {metrics.project_to or 'global'}"
            )
        else:
            logger.info(
                f"[Feature 091] Switch completed: {metrics.total_duration_ms:.1f}ms "
                f"({metrics.total_windows_affected} windows) "
                f"{metrics.project_from or 'global'} → {metrics.project_to or 'global'}"
            )

    def get_snapshot(self) -> PerformanceSnapshot:
        """Get current performance snapshot.

        Returns:
            PerformanceSnapshot with statistics from recent history
        """
        if not self._history:
            return self._empty_snapshot()

        durations = [m.total_duration_ms for m in self._history]
        durations_sorted = sorted(durations)

        # Calculate percentiles
        count = len(durations_sorted)
        p50_idx = int(count * 0.50)
        p95_idx = int(count * 0.95)
        p99_idx = int(count * 0.99)

        avg_duration = sum(durations) / count
        p50_duration = durations_sorted[p50_idx] if p50_idx < count else 0.0
        p95_duration = durations_sorted[p95_idx] if p95_idx < count else 0.0
        p99_duration = durations_sorted[p99_idx] if p99_idx < count else 0.0
        min_duration = min(durations)
        max_duration = max(durations)

        # Count switches meeting targets
        switches_under_200ms = sum(1 for d in durations if d <= 200.0)
        switches_under_300ms = sum(1 for d in durations if d <= 300.0)

        # Calculate average cache hit rate
        cache_hits_total = 0
        cache_misses_total = 0
        for m in self._history:
            if m.hide_metrics:
                cache_hits_total += m.hide_metrics.cache_hits
                cache_misses_total += m.hide_metrics.cache_misses
            if m.restore_metrics:
                cache_hits_total += m.restore_metrics.cache_hits
                cache_misses_total += m.restore_metrics.cache_misses

        total_cache_queries = cache_hits_total + cache_misses_total
        avg_cache_hit_rate = (
            (cache_hits_total / total_cache_queries * 100)
            if total_cache_queries > 0
            else 0.0
        )

        return PerformanceSnapshot(
            total_switches=self._total_switches,
            avg_duration_ms=avg_duration,
            p50_duration_ms=p50_duration,
            p95_duration_ms=p95_duration,
            p99_duration_ms=p99_duration,
            min_duration_ms=min_duration,
            max_duration_ms=max_duration,
            switches_under_200ms=switches_under_200ms,
            switches_under_300ms=switches_under_300ms,
            avg_cache_hit_rate=avg_cache_hit_rate,
            snapshot_time=datetime.now(),
        )

    def get_recent_metrics(self, count: int = 10) -> list[ProjectSwitchMetrics]:
        """Get most recent switch metrics.

        Args:
            count: Number of recent metrics to return

        Returns:
            List of recent ProjectSwitchMetrics (newest first)
        """
        # Convert deque to list and reverse to get newest first
        all_metrics = list(self._history)
        return all_metrics[-count:][::-1]

    def check_performance_target(self, window_count: int) -> float:
        """Get performance target for given window count.

        Args:
            window_count: Number of windows in the switch

        Returns:
            Target duration in milliseconds
        """
        # Performance targets from Feature 091 spec (User Story 2)
        if window_count <= 5:
            return 150.0
        elif window_count <= 10:
            return 180.0
        elif window_count <= 20:
            return 200.0
        elif window_count <= 40:
            return 300.0
        else:
            # For >40 windows, scale linearly (7.5ms per window)
            return 300.0 + ((window_count - 40) * 7.5)

    def get_performance_by_window_count(self) -> dict[str, dict]:
        """Get performance metrics grouped by window count scenario.

        Returns:
            Dictionary mapping scenario names to performance metrics

        Example:
            {
                "5w": {"avg_ms": 145.0, "count": 5, "target_ms": 150.0, "compliance_rate": 100.0},
                "10w": {"avg_ms": 175.0, "count": 12, "target_ms": 180.0, "compliance_rate": 100.0},
                ...
            }
        """
        # Group metrics by window count scenario
        scenarios = {
            "5w": {"min": 0, "max": 5, "target": 150.0, "switches": [], "durations": []},
            "10w": {"min": 6, "max": 10, "target": 180.0, "switches": [], "durations": []},
            "20w": {"min": 11, "max": 20, "target": 200.0, "switches": [], "durations": []},
            "40w": {"min": 21, "max": 40, "target": 300.0, "switches": [], "durations": []},
            "40w+": {"min": 41, "max": 999, "target": 300.0, "switches": [], "durations": []},
        }

        # Categorize switches by window count
        for switch_metrics in self._history:
            window_count = switch_metrics.total_windows_affected

            # Find matching scenario
            for scenario_name, scenario_data in scenarios.items():
                if scenario_data["min"] <= window_count <= scenario_data["max"]:
                    scenario_data["switches"].append(switch_metrics)
                    scenario_data["durations"].append(switch_metrics.total_duration_ms)
                    break

        # Calculate statistics for each scenario
        result = {}
        for scenario_name, scenario_data in scenarios.items():
            if not scenario_data["switches"]:
                continue

            durations = scenario_data["durations"]
            avg_ms = sum(durations) / len(durations)
            target_ms = scenario_data["target"]

            # Calculate compliance rate
            compliant = sum(1 for d in durations if d <= target_ms)
            compliance_rate = (compliant / len(durations)) * 100

            # Calculate p95
            sorted_durations = sorted(durations)
            p95_idx = int(len(sorted_durations) * 0.95)
            p95_ms = sorted_durations[p95_idx] if p95_idx < len(sorted_durations) else 0.0

            result[scenario_name] = {
                "avg_ms": round(avg_ms, 2),
                "min_ms": round(min(durations), 2),
                "max_ms": round(max(durations), 2),
                "p95_ms": round(p95_ms, 2),
                "count": len(durations),
                "target_ms": target_ms,
                "compliance_rate": round(compliance_rate, 2),
                "status": "pass" if compliance_rate >= 95.0 else "fail",
            }

        return result

    def get_regression_analysis(self) -> dict:
        """Analyze recent performance for regressions.

        Returns:
            Dictionary with regression analysis
        """
        if len(self._history) < 10:
            return {
                "status": "insufficient_data",
                "message": "Need at least 10 samples for regression analysis",
            }

        recent_10 = list(self._history)[-10:]
        recent_durations = [m.total_duration_ms for m in recent_10]
        avg_recent = sum(recent_durations) / len(recent_durations)

        # Compare to overall average
        all_durations = [m.total_duration_ms for m in self._history]
        avg_overall = sum(all_durations) / len(all_durations)

        regression_pct = ((avg_recent - avg_overall) / avg_overall) * 100

        if regression_pct > 20.0:
            status = "regression"
            severity = "high"
        elif regression_pct > 10.0:
            status = "regression"
            severity = "medium"
        elif regression_pct < -10.0:
            status = "improvement"
            severity = "significant"
        else:
            status = "stable"
            severity = "none"

        return {
            "status": status,
            "severity": severity,
            "regression_pct": round(regression_pct, 2),
            "avg_recent_ms": round(avg_recent, 2),
            "avg_overall_ms": round(avg_overall, 2),
            "samples_analyzed": len(recent_10),
        }

    def _empty_snapshot(self) -> PerformanceSnapshot:
        """Create empty snapshot for zero data."""
        return PerformanceSnapshot(
            total_switches=0,
            avg_duration_ms=0.0,
            p50_duration_ms=0.0,
            p95_duration_ms=0.0,
            p99_duration_ms=0.0,
            min_duration_ms=0.0,
            max_duration_ms=0.0,
            switches_under_200ms=0,
            switches_under_300ms=0,
            avg_cache_hit_rate=0.0,
            snapshot_time=datetime.now(),
        )

    def reset_stats(self) -> None:
        """Reset tracking statistics (but keep history)."""
        self._regression_warnings = 0

    def reset_all(self) -> None:
        """Reset all tracking data and statistics."""
        self._history.clear()
        self._total_switches = 0
        self._regression_warnings = 0

    @property
    def regression_rate(self) -> float:
        """Calculate percentage of switches that missed target."""
        if self._total_switches == 0:
            return 0.0
        return (self._regression_warnings / self._total_switches) * 100


# Singleton instance (can be initialized by daemon)
_performance_tracker_instance: Optional[PerformanceTrackerService] = None


def get_performance_tracker() -> Optional[PerformanceTrackerService]:
    """Get the global performance tracker instance.

    Returns:
        PerformanceTrackerService instance or None if not initialized
    """
    return _performance_tracker_instance


def initialize_performance_tracker(
    max_history: int = 100, target_ms: float = 200.0
) -> PerformanceTrackerService:
    """Initialize the global performance tracker instance.

    Args:
        max_history: Maximum number of switch records to keep
        target_ms: Performance target in milliseconds

    Returns:
        Initialized PerformanceTrackerService instance
    """
    global _performance_tracker_instance
    _performance_tracker_instance = PerformanceTrackerService(
        max_history=max_history, target_ms=target_ms
    )
    logger.info(
        f"[Feature 091] Performance tracker initialized "
        f"(target: {target_ms}ms, history: {max_history})"
    )
    return _performance_tracker_instance
