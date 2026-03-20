import importlib
import importlib.util
import sys
from pathlib import Path

import pytest


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


window_filter_module = importlib.import_module("i3_project_daemon.services.window_filter")
format_switch_performance_label = window_filter_module.format_switch_performance_label
format_switch_phase_breakdown = window_filter_module.format_switch_phase_breakdown
log_restore_workspace_fallback = window_filter_module.log_restore_workspace_fallback
log_tracking_workspace_fallback = window_filter_module.log_tracking_workspace_fallback
read_process_environ = window_filter_module.read_process_environ


def test_read_process_environ_logs_permission_denied_at_debug(monkeypatch, caplog):
    environ_path = Path("/proc/2147/environ")

    def fake_open(*args, **kwargs):
        raise PermissionError("permission denied")

    monkeypatch.setattr("builtins.open", fake_open)

    with caplog.at_level("DEBUG"):
        with pytest.raises(PermissionError):
            read_process_environ(2147)

    assert "Permission denied reading /proc/2147/environ" in caplog.text
    assert "WARNING" not in caplog.text


def test_workspace_fallback_logs_stay_out_of_warning_budget(caplog):
    with caplog.at_level("INFO"):
        log_restore_workspace_fallback(114)
        log_tracking_workspace_fallback(24)

    assert "No saved state for window 114" in caplog.text
    assert "Window 24 has no valid workspace" in caplog.text
    assert "WARNING" not in caplog.text


def test_switch_performance_label_uses_dynamic_target():
    label, target_ms = format_switch_performance_label(206.8, 6)
    assert label == "✗ SLOW"
    assert target_ms == 180.0

    label, target_ms = format_switch_performance_label(250.0, 21)
    assert label == "✓ TARGET MET"
    assert target_ms == 300.0


def test_switch_phase_breakdown_reports_accounted_and_other_time():
    breakdown = format_switch_phase_breakdown(
        total_duration_ms=250.0,
        classification_duration_ms=100.0,
        state_tracking_duration_ms=10.0,
        hide_duration_ms=20.0,
        restore_duration_ms=30.0,
        post_restore_tree_refresh_duration_ms=40.0,
        post_restore_trace_record_duration_ms=5.0,
    )

    assert breakdown == (
        "classify=100.0ms, track=10.0ms, hide=20.0ms, restore=30.0ms, "
        "trace_tree=40.0ms, trace_record=5.0ms, other=45.0ms"
    )
