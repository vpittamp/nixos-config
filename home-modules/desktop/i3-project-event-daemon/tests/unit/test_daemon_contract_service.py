"""Unit tests for daemon contract/version payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import sys
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


contract_module = importlib.import_module("i3_project_daemon.services.daemon_contract_service")

DaemonContractService = contract_module.DaemonContractService


def test_contract_payload_marks_focus_state_as_current_session_authority() -> None:
    service = DaemonContractService()

    contract = service.contract_payload()

    assert contract["schema_version"] == "i3pm.daemon.contract.v1"
    assert contract["dashboard_schema_version"] == "i3pm.dashboard.v2"
    assert contract["dashboard_event_schema_version"] == "i3pm.dashboard.event.v1"
    assert contract["focus_schema_version"] == "i3pm.focus_state.v2"
    assert contract["current_session_authority"] == "focus_state.current_session_key"
    assert "focus_state" in contract["required_dashboard_fields"]
    assert "active_ai_sessions" in contract["required_dashboard_fields"]
    assert "current_ai_session_key" in contract["retired_dashboard_fields"]
    assert "daemon-owned-focus-state" in contract["features"]
    assert "dashboard-delta-events" in contract["features"]
    assert "herdr-native-ai-sessions" in contract["features"]


def test_version_payload_reuses_contract_without_feature_duplication() -> None:
    service = DaemonContractService()
    contract = service.contract_payload()

    version = service.version_payload()

    assert version["version"] == "1.0.0"
    assert version["api_version"] == "1.0.0"
    assert version["contract"] == {
        key: value for key, value in contract.items() if key != "features"
    }
    assert version["features"] == contract["features"]
