from __future__ import annotations

import importlib
import importlib.util
import logging
import sys
from datetime import datetime
from pathlib import Path


PACKAGE_ROOT = Path(__file__).parent.parent.parent


if "i3_project_daemon" not in sys.modules:
    package_spec = importlib.util.spec_from_file_location(
        "i3_project_daemon",
        PACKAGE_ROOT / "__init__.py",
        submodule_search_locations=[str(PACKAGE_ROOT)],
    )
    package_module = importlib.util.module_from_spec(package_spec)
    sys.modules["i3_project_daemon"] = package_module
    assert package_spec.loader is not None
    package_spec.loader.exec_module(package_module)


performance_tracker_module = importlib.import_module(
    "i3_project_daemon.services.performance_tracker"
)
performance_models_module = importlib.import_module(
    "i3_project_daemon.models.performance_metrics"
)

OperationMetrics = performance_models_module.OperationMetrics
PerformanceTrackerService = performance_tracker_module.PerformanceTrackerService
ProjectSwitchMetrics = performance_models_module.ProjectSwitchMetrics


def _operation_metrics(window_count: int) -> OperationMetrics:
    timestamp = datetime.now()
    return OperationMetrics(
        operation_type="hide",
        start_time=timestamp,
        end_time=timestamp,
        duration_ms=100.0,
        window_count=window_count,
        command_count=window_count,
        parallel_batches=1,
    )


def test_record_switch_uses_dynamic_target_for_large_window_sets(caplog):
    tracker = PerformanceTrackerService()
    metrics = ProjectSwitchMetrics(
        project_from="global",
        project_to="vpittamp/nixos-config:main",
        total_duration_ms=250.0,
        hide_metrics=_operation_metrics(21),
        restore_metrics=_operation_metrics(0),
    )

    with caplog.at_level(logging.INFO):
        tracker.record_switch(metrics)

    assert tracker.regression_rate == 0.0
    assert "Performance regression detected" not in caplog.text
    assert "target: 300.0ms" in caplog.text


def test_record_switch_warns_when_dynamic_target_is_missed(caplog):
    tracker = PerformanceTrackerService()
    metrics = ProjectSwitchMetrics(
        project_from="global",
        project_to="PittampalliOrg/workflow-builder:main",
        total_duration_ms=420.8,
        hide_metrics=_operation_metrics(13),
        restore_metrics=_operation_metrics(0),
    )

    with caplog.at_level(logging.WARNING):
        tracker.record_switch(metrics)

    assert tracker.regression_rate == 100.0
    assert "Performance regression detected" in caplog.text
    assert "target: 200.0ms, 13 windows" in caplog.text
