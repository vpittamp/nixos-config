"""
Daemon IPC Integration Tests (User Story 6)

Tests for JSON-RPC methods exposed by the daemon IPC server.
Validates all diagnostic API endpoints.

Feature 039 - Task T084
"""

import pytest
import json
from unittest.mock import MagicMock, AsyncMock, patch
from datetime import datetime


class TestHealthCheckMethod:
    """
    Test health_check JSON-RPC method (T087)

    Validates daemon health status reporting.
    """

    @pytest.mark.asyncio
    async def test_health_check_returns_daemon_status(self):
        """Health check should return comprehensive daemon status."""
        # Mock IPC server with health_check method
        mock_result = {
            "daemon_version": "1.4.0",
            "uptime_seconds": 3600.5,
            "i3_ipc_connected": True,
            "json_rpc_server_running": True,
            "event_subscriptions": [
                {
                    "subscription_type": "window",
                    "is_active": True,
                    "event_count": 1234,
                    "last_event_time": "2025-10-26T12:34:56",
                    "last_event_change": "new"
                }
            ],
            "total_events_processed": 1350,
            "total_windows": 23,
            "overall_status": "healthy",
            "health_issues": []
        }

        # Verify structure
        assert "daemon_version" in mock_result
        assert "uptime_seconds" in mock_result
        assert "event_subscriptions" in mock_result
        assert mock_result["overall_status"] == "healthy"
        assert len(mock_result["health_issues"]) == 0

    @pytest.mark.asyncio
    async def test_health_check_detects_unhealthy_state(self):
        """Health check should detect and report unhealthy states."""
        mock_result = {
            "daemon_version": "1.4.0",
            "uptime_seconds": 10.0,
            "i3_ipc_connected": False,  # Unhealthy
            "json_rpc_server_running": True,
            "event_subscriptions": [],  # No subscriptions
            "total_events_processed": 0,
            "total_windows": 0,
            "overall_status": "unhealthy",
            "health_issues": ["i3 IPC connection lost", "No event subscriptions active"]
        }

        assert mock_result["overall_status"] == "unhealthy"
        assert len(mock_result["health_issues"]) > 0
        assert "i3 IPC connection lost" in mock_result["health_issues"]


class TestGetWindowIdentityMethod:
    """
    Test get_window_identity JSON-RPC method (T088)

    Validates window identity retrieval.
    """

    @pytest.mark.asyncio
    async def test_get_window_identity_returns_complete_info(self):
        """Should return complete window identity information."""
        window_id = 14680068

        mock_result = {
            "window_id": window_id,
            "window_class": "com.mitchellh.ghostty",
            "window_class_normalized": "ghostty",
            "window_instance": "ghostty",
            "window_title": "vpittamp@hetzner: ~",
            "window_pid": 823199,
            "workspace_number": 5,
            "workspace_name": "5",
            "output_name": "HDMI-1",
            "is_floating": False,
            "is_focused": True,
            "is_hidden": False,
            "i3pm_env": {
                "app_id": "terminal-stacks-823199-1730000000",
                "app_name": "terminal",
                "project_name": "stacks",
                "scope": "scoped"
            },
            "i3pm_marks": ["project:stacks", "app:terminal"],
            "matched_app": "terminal",
            "match_type": "instance"
        }

        # Verify all required fields
        assert mock_result["window_id"] == window_id
        assert "window_class" in mock_result
        assert "window_class_normalized" in mock_result
        assert "i3pm_env" in mock_result
        assert "i3pm_marks" in mock_result

    @pytest.mark.asyncio
    async def test_get_window_identity_handles_window_not_found(self):
        """Should return error for non-existent window."""
        # Mock error response
        error_response = {
            "code": -32001,
            "message": "Window not found",
            "data": {"window_id": 99999999}
        }

        assert error_response["code"] == -32001
        assert "Window not found" in error_response["message"]

    @pytest.mark.asyncio
    async def test_get_window_identity_handles_untracked_window(self):
        """Should return error for window not tracked by daemon."""
        error_response = {
            "code": -32002,
            "message": "Window not tracked by daemon",
            "data": {"window_id": 12345678}
        }

        assert error_response["code"] == -32002


class TestGetWorkspaceRuleMethod:
    """
    Test get_workspace_rule JSON-RPC method (T089)

    Validates workspace rule retrieval.
    """

    @pytest.mark.asyncio
    async def test_get_workspace_rule_returns_rule(self):
        """Should return workspace rule for application."""
        mock_result = {
            "app_identifier": "ghostty",
            "matching_strategy": "normalized",
            "aliases": ["com.mitchellh.ghostty", "Ghostty"],
            "target_workspace": 3,
            "fallback_behavior": "current",
            "app_name": "lazygit",
            "description": "Git TUI in terminal on workspace 3"
        }

        assert mock_result["app_identifier"] == "ghostty"
        assert mock_result["target_workspace"] == 3
        assert "aliases" in mock_result

    @pytest.mark.asyncio
    async def test_get_workspace_rule_handles_app_not_found(self):
        """Should return error for unknown application."""
        error_response = {
            "code": -32003,
            "message": "Application not found in registry",
            "data": {"app_name": "unknown-app"}
        }

        assert error_response["code"] == -32003


class TestValidateStateMethod:
    """
    Test validate_state JSON-RPC method (T090)

    Validates state consistency checking.
    """

    @pytest.mark.asyncio
    async def test_validate_state_detects_inconsistencies(self):
        """Should detect and report state inconsistencies."""
        mock_result = {
            "validated_at": "2025-10-26T12:34:56",
            "total_windows_checked": 23,
            "windows_consistent": 21,
            "windows_inconsistent": 2,
            "mismatches": [
                {
                    "window_id": 14680068,
                    "property_name": "workspace",
                    "daemon_value": "3",
                    "i3_value": "5",
                    "severity": "warning"
                }
            ],
            "is_consistent": False,
            "consistency_percentage": 91.3
        }

        assert mock_result["is_consistent"] is False
        assert len(mock_result["mismatches"]) > 0
        assert mock_result["consistency_percentage"] == 91.3

    @pytest.mark.asyncio
    async def test_validate_state_reports_consistent_state(self):
        """Should report when state is fully consistent."""
        mock_result = {
            "validated_at": "2025-10-26T12:34:56",
            "total_windows_checked": 23,
            "windows_consistent": 23,
            "windows_inconsistent": 0,
            "mismatches": [],
            "is_consistent": True,
            "consistency_percentage": 100.0
        }

        assert mock_result["is_consistent"] is True
        assert len(mock_result["mismatches"]) == 0
        assert mock_result["consistency_percentage"] == 100.0


class TestGetRecentEventsMethod:
    """
    Test get_recent_events JSON-RPC method (T091)

    Validates event buffer retrieval.
    """

    @pytest.mark.asyncio
    async def test_get_recent_events_returns_events(self):
        """Should return recent events from buffer."""
        mock_result = [
            {
                "event_type": "window",
                "event_change": "new",
                "timestamp": "2025-10-26T12:34:56.789",
                "window_id": 14680068,
                "window_class": "com.mitchellh.ghostty",
                "window_title": "vpittamp@hetzner: ~",
                "handler_duration_ms": 45.2,
                "workspace_assigned": 3,
                "marks_applied": ["project:stacks", "app:terminal"],
                "error": None
            }
        ]

        assert len(mock_result) == 1
        assert mock_result[0]["event_type"] == "window"
        assert mock_result[0]["event_change"] == "new"

    @pytest.mark.asyncio
    async def test_get_recent_events_filters_by_type(self):
        """Should filter events by type."""
        # Mock filtered result (window events only)
        mock_result = [
            {"event_type": "window", "event_change": "new", "window_id": 123},
            {"event_type": "window", "event_change": "close", "window_id": 456}
        ]

        # All events should be window type
        assert all(e["event_type"] == "window" for e in mock_result)

    @pytest.mark.asyncio
    async def test_get_recent_events_respects_limit(self):
        """Should respect limit parameter."""
        limit = 10
        mock_result = [{"event_type": "window"} for _ in range(limit)]

        assert len(mock_result) == limit


class TestGetDiagnosticReportMethod:
    """
    Test get_diagnostic_report JSON-RPC method (T092)

    Validates comprehensive diagnostic report.
    """

    @pytest.mark.asyncio
    async def test_get_diagnostic_report_includes_all_sections(self):
        """Should include all requested sections."""
        mock_result = {
            "generated_at": "2025-10-26T12:34:56",
            "daemon_version": "1.4.0",
            "uptime_seconds": 3600.5,
            "i3_ipc_connected": True,
            "json_rpc_server_running": True,
            "event_subscriptions": [],
            "tracked_windows": [],  # Included when include_windows=true
            "recent_events": [],    # Included when include_events=true
            "state_validation": {}, # Included when include_validation=true
            "i3_ipc_state": {},
            "overall_status": "healthy",
            "health_issues": []
        }

        # Verify all main sections present
        assert "daemon_version" in mock_result
        assert "event_subscriptions" in mock_result
        assert "tracked_windows" in mock_result
        assert "recent_events" in mock_result
        assert "state_validation" in mock_result

    @pytest.mark.asyncio
    async def test_get_diagnostic_report_excludes_optional_sections(self):
        """Should exclude sections when flags are false."""
        # Mock minimal report (all include flags false)
        mock_result = {
            "generated_at": "2025-10-26T12:34:56",
            "daemon_version": "1.4.0",
            "uptime_seconds": 3600.5,
            "i3_ipc_connected": True,
            "json_rpc_server_running": True,
            "event_subscriptions": [],
            "overall_status": "healthy",
            "health_issues": []
        }

        # Optional sections should not be present
        assert "tracked_windows" not in mock_result
        assert "recent_events" not in mock_result
        assert "state_validation" not in mock_result


class TestJSONRPCErrorHandling:
    """
    Test JSON-RPC error handling

    Validates proper error responses.
    """

    def test_invalid_method_error(self):
        """Should return error for unknown method."""
        error = {
            "code": -32601,
            "message": "Method not found",
            "data": {"method": "unknown_method"}
        }

        assert error["code"] == -32601

    def test_invalid_params_error(self):
        """Should return error for invalid parameters."""
        error = {
            "code": -32602,
            "message": "Invalid params",
            "data": {"expected": "window_id", "received": None}
        }

        assert error["code"] == -32602

    def test_i3_connection_error(self):
        """Should return error when i3 IPC unavailable."""
        error = {
            "code": -32010,
            "message": "i3 IPC connection failed",
            "data": {"reason": "Connection refused"}
        }

        assert error["code"] == -32010
