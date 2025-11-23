"""
Unit tests for performance metrics models.
Feature 091: Optimize i3pm Project Switching Performance
"""

import pytest
from datetime import datetime, timedelta
from home_modules.desktop.i3_project_event_daemon.models.performance_metrics import (
    OperationMetrics,
    ProjectSwitchMetrics,
    PerformanceSnapshot,
)


class TestOperationMetrics:
    """Tests for OperationMetrics model."""

    def test_create_operation_metrics(self):
        """Test creating operation metrics."""
        start = datetime.now()
        end = start + timedelta(milliseconds=150)

        metrics = OperationMetrics(
            operation_type="hide",
            start_time=start,
            end_time=end,
            duration_ms=150.0,
            window_count=10,
            command_count=10,
            parallel_batches=1,
            cache_hits=2,
            cache_misses=1,
        )

        assert metrics.operation_type == "hide"
        assert metrics.duration_ms == 150.0
        assert metrics.window_count == 10
        assert metrics.command_count == 10

    def test_avg_duration_per_window(self):
        """Test calculating average duration per window."""
        metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=200.0,
            window_count=10,
            command_count=20,
            parallel_batches=2,
        )

        assert metrics.avg_duration_per_window == 20.0  # 200ms / 10 windows

    def test_avg_duration_zero_windows(self):
        """Test average duration with zero windows."""
        metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            window_count=0,
            command_count=0,
            parallel_batches=0,
        )

        assert metrics.avg_duration_per_window == 0.0

    def test_cache_hit_rate(self):
        """Test calculating cache hit rate."""
        metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            cache_hits=7,
            cache_misses=3,
        )

        assert metrics.cache_hit_rate == 70.0  # 7 / 10 * 100

    def test_cache_hit_rate_zero_queries(self):
        """Test cache hit rate with no queries."""
        metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            cache_hits=0,
            cache_misses=0,
        )

        assert metrics.cache_hit_rate == 0.0

    def test_meets_performance_target(self):
        """Test checking if operation meets performance target."""
        fast_metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=150.0,
        )

        slow_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=250.0,
        )

        assert fast_metrics.meets_performance_target(200.0) is True
        assert slow_metrics.meets_performance_target(200.0) is False


class TestProjectSwitchMetrics:
    """Tests for ProjectSwitchMetrics model."""

    def test_create_switch_metrics(self):
        """Test creating project switch metrics."""
        hide_metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=80.0,
            window_count=5,
            command_count=5,
            parallel_batches=1,
        )

        restore_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            window_count=8,
            command_count=24,
            parallel_batches=2,
        )

        switch_metrics = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=190.0,
            hide_metrics=hide_metrics,
            restore_metrics=restore_metrics,
        )

        assert switch_metrics.project_from == "nixos"
        assert switch_metrics.project_to == "dotfiles"
        assert switch_metrics.total_duration_ms == 190.0

    def test_total_windows_affected(self):
        """Test calculating total windows affected."""
        hide_metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=80.0,
            window_count=5,
            command_count=5,
            parallel_batches=1,
        )

        restore_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            window_count=8,
            command_count=24,
            parallel_batches=2,
        )

        switch_metrics = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=190.0,
            hide_metrics=hide_metrics,
            restore_metrics=restore_metrics,
        )

        assert switch_metrics.total_windows_affected == 13  # 5 + 8

    def test_total_commands_executed(self):
        """Test calculating total commands executed."""
        hide_metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=80.0,
            command_count=5,
            parallel_batches=1,
        )

        restore_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            command_count=24,
            parallel_batches=2,
        )

        switch_metrics = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=190.0,
            hide_metrics=hide_metrics,
            restore_metrics=restore_metrics,
        )

        assert switch_metrics.total_commands_executed == 29  # 5 + 24

    def test_parallelization_efficiency(self):
        """Test calculating parallelization efficiency."""
        hide_metrics = OperationMetrics(
            operation_type="hide",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=80.0,
            command_count=10,
            parallel_batches=1,
        )

        restore_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=100.0,
            command_count=20,
            parallel_batches=2,
        )

        switch_metrics = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=190.0,
            hide_metrics=hide_metrics,
            restore_metrics=restore_metrics,
        )

        # 30 commands / 3 batches = 10.0 efficiency
        assert switch_metrics.parallelization_efficiency == 10.0

    def test_meets_performance_target_default(self):
        """Test checking if switch meets default 200ms target."""
        fast_switch = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=180.0,
        )

        slow_switch = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=250.0,
        )

        assert fast_switch.meets_performance_target() is True
        assert slow_switch.meets_performance_target() is False

    def test_meets_performance_target_custom(self):
        """Test checking if switch meets custom target."""
        switch = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=180.0,
        )

        assert switch.meets_performance_target(150.0) is False
        assert switch.meets_performance_target(200.0) is True

    def test_to_summary_dict(self):
        """Test converting metrics to summary dictionary."""
        switch_metrics = ProjectSwitchMetrics(
            project_from="nixos",
            project_to="dotfiles",
            total_duration_ms=185.5,
            hide_metrics=OperationMetrics(
                operation_type="hide",
                start_time=datetime.now(),
                end_time=datetime.now(),
                duration_ms=80.0,
                command_count=5,
                parallel_batches=1,
            ),
            restore_metrics=OperationMetrics(
                operation_type="restore",
                start_time=datetime.now(),
                end_time=datetime.now(),
                duration_ms=100.0,
                window_count=8,
                command_count=20,
                parallel_batches=2,
            ),
        )

        summary = switch_metrics.to_summary_dict()

        assert summary["switch"] == "nixos → dotfiles"
        assert summary["duration_ms"] == 185.5
        assert summary["windows"] == 8
        assert summary["commands"] == 25
        assert summary["meets_target"] is True
        assert "timestamp" in summary


class TestPerformanceSnapshot:
    """Tests for PerformanceSnapshot model."""

    def test_create_snapshot(self):
        """Test creating performance snapshot."""
        snapshot = PerformanceSnapshot(
            total_switches=100,
            avg_duration_ms=180.0,
            p50_duration_ms=175.0,
            p95_duration_ms=195.0,
            p99_duration_ms=205.0,
            min_duration_ms=120.0,
            max_duration_ms=220.0,
            switches_under_200ms=92,
            switches_under_300ms=98,
            avg_cache_hit_rate=75.5,
        )

        assert snapshot.total_switches == 100
        assert snapshot.avg_duration_ms == 180.0

    def test_target_compliance_rate(self):
        """Test calculating target compliance rate."""
        snapshot = PerformanceSnapshot(
            total_switches=100,
            switches_under_200ms=92,
        )

        assert snapshot.target_compliance_rate == 92.0  # 92 / 100 * 100

    def test_target_compliance_zero_switches(self):
        """Test compliance rate with zero switches."""
        snapshot = PerformanceSnapshot(
            total_switches=0,
            switches_under_200ms=0,
        )

        assert snapshot.target_compliance_rate == 0.0

    def test_performance_summary(self):
        """Test generating performance summary string."""
        snapshot = PerformanceSnapshot(
            total_switches=100,
            avg_duration_ms=180.5,
            p95_duration_ms=195.2,
            switches_under_200ms=92,
        )

        summary = snapshot.performance_summary

        assert "180ms avg" in summary
        assert "195ms p95" in summary
        assert "92% under 200ms target" in summary

    def test_performance_summary_no_data(self):
        """Test summary with no data."""
        snapshot = PerformanceSnapshot(
            total_switches=0,
        )

        assert snapshot.performance_summary == "No data"
