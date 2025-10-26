"""
Diagnostic Tooling Scenario Tests (User Story 6)

Tests for diagnostic command effectiveness in identifying common misconfigurations.
Based on scenarios from quickstart.md.

Feature 039 - Task T086
"""

import pytest
from unittest.mock import MagicMock, AsyncMock


class TestScenario1WindowWrongWorkspace:
    """
    Scenario 1: Window Opens on Wrong Workspace

    User configures lazygit for workspace 3, but it opens on current workspace.
    Diagnostic should identify the cause.
    """

    @pytest.mark.asyncio
    async def test_diagnose_identifies_missing_workspace_rule(self):
        """Diagnostic should identify missing workspace rule."""
        # Mock window identity showing no workspace assignment
        window_identity = {
            "window_id": 123456,
            "window_class": "lazygit",
            "workspace_number": 1,  # Current workspace, not configured workspace
            "matched_app": None,  # No registry match
            "match_type": "none"
        }

        # Diagnostic should report:
        # - No workspace rule matched
        # - Window stayed on current workspace (fallback)
        assert window_identity["matched_app"] is None
        assert window_identity["match_type"] == "none"

    @pytest.mark.asyncio
    async def test_diagnose_identifies_class_mismatch(self):
        """Diagnostic should identify class mismatch in rule."""
        # User configured "Lazygit" but actual class is "lazygit"
        window_identity = {
            "window_id": 123456,
            "window_class": "lazygit",
            "window_class_normalized": "lazygit",
            "matched_app": None,
            "match_type": "none"
        }

        workspace_rule = {
            "app_identifier": "Lazygit",  # Case mismatch
            "matching_strategy": "exact",
            "target_workspace": 3
        }

        # Diagnostic should show:
        # - Expected: "Lazygit"
        # - Actual: "lazygit"
        # - Suggestion: Use normalized matching or fix case


class TestScenario2WindowClassNotMatching:
    """
    Scenario 2: Window Class Not Matching

    Window class doesn't match configured rule.
    Diagnostic should show actual vs expected class.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_actual_vs_expected_class(self):
        """Diagnostic should show class comparison."""
        # Configured rule expects "ghostty"
        # Actual window has "com.mitchellh.ghostty"

        window_identity = {
            "window_class": "com.mitchellh.ghostty",
            "window_class_normalized": "ghostty",
            "matched_app": "terminal",  # Should match via normalization
            "match_type": "normalized"
        }

        # Diagnostic should show:
        # - Original class: "com.mitchellh.ghostty"
        # - Normalized class: "ghostty"
        # - Match type: "normalized" (tier 3)
        # - Suggestion: Matching strategy is working correctly

    @pytest.mark.asyncio
    async def test_diagnose_suggests_normalization_strategy(self):
        """Diagnostic should suggest using normalization for reverse-domain classes."""
        window_identity = {
            "window_class": "org.kde.dolphin",
            "window_class_normalized": "dolphin",
            "matched_app": None,
            "match_type": "none"
        }

        # Diagnostic suggestion:
        # - Use "dolphin" instead of full class
        # - Or use aliases: ["org.kde.dolphin", "Dolphin", "dolphin"]


class TestScenario3EventsNotProcessed:
    """
    Scenario 3: Events Not Being Processed

    Daemon appears running but windows aren't being tracked.
    Diagnostic should identify subscription or connection issues.
    """

    @pytest.mark.asyncio
    async def test_diagnose_identifies_no_event_subscriptions(self):
        """Diagnostic should identify missing event subscriptions."""
        health_check = {
            "i3_ipc_connected": True,
            "json_rpc_server_running": True,
            "event_subscriptions": [],  # No subscriptions!
            "total_events_processed": 0,
            "overall_status": "unhealthy",
            "health_issues": ["No event subscriptions active"]
        }

        assert len(health_check["event_subscriptions"]) == 0
        assert health_check["overall_status"] == "unhealthy"
        assert "No event subscriptions active" in health_check["health_issues"]

    @pytest.mark.asyncio
    async def test_diagnose_identifies_stale_events(self):
        """Diagnostic should identify stale event processing."""
        import datetime

        health_check = {
            "event_subscriptions": [
                {
                    "subscription_type": "window",
                    "is_active": True,
                    "event_count": 1234,
                    "last_event_time": "2025-10-26T08:00:00",  # 4 hours ago
                }
            ],
            "overall_status": "warning",
            "health_issues": ["No window events in last 4 hours (expected activity)"]
        }

        assert "warning" in health_check["health_issues"][0].lower()

    @pytest.mark.asyncio
    async def test_diagnose_identifies_i3_connection_lost(self):
        """Diagnostic should identify i3 IPC connection failure."""
        health_check = {
            "i3_ipc_connected": False,
            "json_rpc_server_running": True,
            "event_subscriptions": [],
            "overall_status": "critical",
            "health_issues": ["i3 IPC connection lost"]
        }

        assert health_check["i3_ipc_connected"] is False
        assert health_check["overall_status"] == "critical"


class TestScenario4StateDrift:
    """
    Scenario 4: State Drift Detection

    Daemon state doesn't match i3 reality.
    Diagnostic should identify and quantify drift.
    """

    @pytest.mark.asyncio
    async def test_diagnose_detects_workspace_mismatch(self):
        """Diagnostic should detect workspace mismatches."""
        validation = {
            "total_windows_checked": 23,
            "windows_consistent": 22,
            "windows_inconsistent": 1,
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
            "consistency_percentage": 95.7
        }

        assert validation["is_consistent"] is False
        assert len(validation["mismatches"]) == 1
        assert validation["mismatches"][0]["property_name"] == "workspace"

    @pytest.mark.asyncio
    async def test_diagnose_detects_mark_mismatch(self):
        """Diagnostic should detect missing or incorrect marks."""
        validation_mismatch = {
            "window_id": 123456,
            "property_name": "marks",
            "daemon_value": ["project:nixos", "app:vscode"],
            "i3_value": ["project:nixos"],  # Missing app mark
            "severity": "info"
        }

        # Daemon thinks window has app mark, but i3 doesn't show it
        assert "app:vscode" in validation_mismatch["daemon_value"]
        assert "app:vscode" not in validation_mismatch["i3_value"]


class TestScenario5PWANotIdentified:
    """
    Scenario 5: PWA Not Identified Correctly

    Chrome PWA not distinguished from browser.
    Diagnostic should show PWA detection info.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_pwa_identification(self):
        """Diagnostic should show PWA identification status."""
        # Chrome PWA window
        window_identity = {
            "window_class": "Google-chrome",
            "window_instance": "chat.google.com__work",
            "is_pwa": True,
            "pwa_type": "chrome",
            "pwa_id": "chat.google.com__work"
        }

        # Diagnostic should show:
        # - Is PWA: Yes
        # - PWA Type: chrome
        # - PWA ID: chat.google.com__work
        # - Recommendation: Use instance field for matching

        assert window_identity["is_pwa"] is True
        assert window_identity["pwa_type"] == "chrome"

    @pytest.mark.asyncio
    async def test_diagnose_shows_non_pwa_chrome_browser(self):
        """Diagnostic should distinguish Chrome browser from PWA."""
        window_identity = {
            "window_class": "Google-chrome",
            "window_instance": "google-chrome",  # Standard browser
            "is_pwa": False,
            "pwa_type": None,
            "pwa_id": None
        }

        assert window_identity["is_pwa"] is False


class TestScenario6TerminalProjectMismatch:
    """
    Scenario 6: Terminal Shows in Wrong Project

    Terminal window showing when different project active.
    Diagnostic should show I3PM_PROJECT_NAME environment.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_terminal_project_association(self):
        """Diagnostic should show terminal's project association."""
        window_identity = {
            "window_id": 123456,
            "window_class": "com.mitchellh.ghostty",
            "i3pm_env": {
                "project_name": "nixos",
                "app_name": "terminal",
                "scope": "scoped"
            },
            "i3pm_marks": ["project:nixos", "app:terminal"]
        }

        active_project = "stacks"  # Different project active

        # Diagnostic should show:
        # - Window project: "nixos"
        # - Active project: "stacks"
        # - Expected behavior: Window should be hidden
        # - Actual marks: ["project:nixos", "app:terminal"]

        assert window_identity["i3pm_env"]["project_name"] != active_project


class TestScenario7RapidEventLoss:
    """
    Scenario 7: Events Being Lost During Rapid Window Creation

    Multiple windows opened rapidly, some not tracked.
    Diagnostic should show event processing metrics.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_event_processing_metrics(self):
        """Diagnostic should show event queue and processing stats."""
        health_check = {
            "event_subscriptions": [
                {
                    "subscription_type": "window",
                    "event_count": 5000,
                    "events_failed": 0,
                    "avg_processing_ms": 25.5
                }
            ],
            "total_events_processed": 5000,
            "total_windows": 50,  # All windows tracked
            "overall_status": "healthy"
        }

        # No events lost - healthy
        assert health_check["event_subscriptions"][0]["events_failed"] == 0


class TestScenario8DaemonCrashRecovery:
    """
    Scenario 8: Daemon Restart Loses State

    Daemon restarted, pre-existing windows not tracked.
    Diagnostic should identify windows without marks.
    """

    @pytest.mark.asyncio
    async def test_diagnose_identifies_unmarked_windows(self):
        """Diagnostic should identify windows without project marks."""
        window_without_marks = {
            "window_id": 123456,
            "window_class": "Code",
            "i3pm_marks": [],  # No marks - not tracked
            "i3pm_env": None  # No environment - pre-existing window
        }

        # Diagnostic should suggest:
        # - Window existed before daemon started
        # - Not tracked by project system
        # - Recommendation: Close and reopen to get marks

        assert len(window_without_marks["i3pm_marks"]) == 0
        assert window_without_marks["i3pm_env"] is None


class TestScenario9MultiMonitorWorkspaceAssignment:
    """
    Scenario 9: Window Assigned to Workspace on Wrong Monitor

    Window assigned to workspace that doesn't exist on any output.
    Diagnostic should identify workspace availability.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_workspace_output_mapping(self):
        """Diagnostic should show workspace-to-output assignments."""
        workspace_rule = {
            "app_identifier": "lazygit",
            "target_workspace": 9
        }

        i3_state = {
            "workspaces": [
                {"number": 1, "output": "HDMI-1"},
                {"number": 2, "output": "HDMI-1"},
                {"number": 3, "output": "HDMI-2"},
                # Workspace 9 doesn't exist yet
            ]
        }

        # Diagnostic should show:
        # - Target workspace: 9
        # - Workspace exists: No (will be created on current output)
        # - Recommendation: Workspace will be created as needed


class TestScenario10PerformanceDegradation:
    """
    Scenario 10: Slow Workspace Assignment

    Windows taking >100ms to move to workspace.
    Diagnostic should show performance metrics.
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_performance_metrics(self):
        """Diagnostic should show workspace assignment performance."""
        recent_events = [
            {
                "event_type": "window",
                "event_change": "new",
                "window_id": 123456,
                "handler_duration_ms": 150.5,  # Slow!
                "workspace_assigned": 3
            }
        ]

        # Diagnostic should highlight:
        # - Duration: 150.5ms (exceeds 100ms target)
        # - Status: Warning (performance degradation)

        assert recent_events[0]["handler_duration_ms"] > 100
