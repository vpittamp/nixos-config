"""Daemon runtime contract markers used by health and rebuild gates."""

from __future__ import annotations

from typing import Any, Dict

from .dashboard_model import DASHBOARD_EVENT_SCHEMA_VERSION, DASHBOARD_SCHEMA_VERSION
from .focus_service import FOCUS_STATE_SCHEMA_VERSION


DAEMON_CONTRACT_SCHEMA_VERSION = "i3pm.daemon.contract.v1"
DAEMON_VERSION = "1.0.0"
DAEMON_API_VERSION = "1.0.0"


class DaemonContractService:
    """Own the public daemon contract/version payloads."""

    def __init__(
        self,
        *,
        schema_version: str = DAEMON_CONTRACT_SCHEMA_VERSION,
        dashboard_schema_version: str = DASHBOARD_SCHEMA_VERSION,
        dashboard_event_schema_version: str = DASHBOARD_EVENT_SCHEMA_VERSION,
        focus_schema_version: str = FOCUS_STATE_SCHEMA_VERSION,
        version: str = DAEMON_VERSION,
        api_version: str = DAEMON_API_VERSION,
    ) -> None:
        self.schema_version = schema_version
        self.dashboard_schema_version = dashboard_schema_version
        self.dashboard_event_schema_version = dashboard_event_schema_version
        self.focus_schema_version = focus_schema_version
        self.version = version
        self.api_version = api_version

    def contract_payload(self) -> Dict[str, Any]:
        """Return the authoritative daemon/runtime contract marker."""
        return {
            "schema_version": self.schema_version,
            "dashboard_schema_version": self.dashboard_schema_version,
            "dashboard_event_schema_version": self.dashboard_event_schema_version,
            "focus_schema_version": self.focus_schema_version,
            "current_session_authority": "focus_state.current_session_key",
            "required_dashboard_fields": [
                "schema_version",
                "generation",
                "snapshot_version",
                "focus_state",
                "active_ai_sessions",
                "dashboard_invariants",
            ],
            "retired_dashboard_fields": [
                "current_ai_session_key",
                "focus_state.current_ai_session_key",
                "focus_state.focused_window_id",
            ],
            "features": [
                "session-management",
                "mark-based-correlation",
                "auto-save",
                "auto-restore",
                "workspace-focus-tracking",
                "window-focus-tracking",
                "terminal-cwd-tracking",
                "daemon-owned-focus-state",
                "formal-focus-intents",
                "dashboard-delta-events",
                "herdr-native-ai-sessions",
            ],
        }

    def version_payload(self) -> Dict[str, Any]:
        """Return version and contract metadata for clients."""
        contract = self.contract_payload()
        return {
            "version": self.version,
            "api_version": self.api_version,
            "contract": {
                key: value for key, value in contract.items() if key != "features"
            },
            "features": list(contract["features"]),
        }
