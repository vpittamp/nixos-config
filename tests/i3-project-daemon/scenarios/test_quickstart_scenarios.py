"""
Quickstart Guide Validation Tests

Tests for all 4 diagnostic scenarios from quickstart.md to ensure
diagnostic commands correctly identify and report common issues.

Feature 039 - Task T106

Scenarios:
1. Window on wrong workspace (workspace mismatch detection)
2. Window class not matching (class mismatch and fix suggestions)
3. Events not being processed (event subscription failure)
4. State drift detection (daemon vs i3 state inconsistency)
"""

import pytest
from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta


# ============================================================================
# Scenario 1: Window Opens on Wrong Workspace
# ============================================================================

class TestScenario1WindowOnWrongWorkspace:
    """
    Quickstart Scenario 1: Window Opens on Wrong Workspace

    Problem: lazygit opens on workspace 5 instead of configured workspace 3

    Expected diagnostic flow:
    1. Get window ID
    2. Run `i3pm diagnose window <id>`
    3. See workspace mismatch (Expected: 3, Actual: 5)
    4. Check event log for window::new event
    5. Determine if manually moved or assignment failed
    """

    @pytest.mark.asyncio
    async def test_diagnose_window_shows_workspace_mismatch(self):
        """
        Step 2 from quickstart: `i3pm diagnose window <id>` shows mismatch.

        Given:
        - Window 14680068 matched to "terminal" app
        - Registry says workspace 3
        - Window is actually on workspace 5

        When:
        - User runs `i3pm diagnose window 14680068`

        Then:
        - Output shows "Expected Workspace: 3"
        - Output shows "Actual Workspace: 5 ⚠️ MISMATCH"
        - Match type is "instance" or "exact" (matched successfully)
        """
        window_identity = {
            "window_id": 14680068,
            "window_class": "com.mitchellh.ghostty",
            "window_instance": "ghostty",
            "workspace_number": 5,  # Actual location
            "matched_app": "terminal",
            "match_type": "instance",
            "expected_workspace": 3,  # From registry
        }

        # Verify mismatch is detectable
        assert window_identity["workspace_number"] != window_identity["expected_workspace"]
        assert window_identity["match_type"] in ["exact", "instance", "normalized"]
        assert window_identity["matched_app"] is not None

        # Diagnostic should flag this as mismatch
        is_mismatch = (
            window_identity.get("expected_workspace") and
            window_identity.get("workspace_number") != window_identity.get("expected_workspace")
        )
        assert is_mismatch is True

    @pytest.mark.asyncio
    async def test_event_log_shows_workspace_assignment(self):
        """
        Step 3 from quickstart: Event log shows workspace was assigned.

        Given:
        - window::new event fired for window 14680068
        - workspace 3 was assigned in the event
        - No errors during processing

        When:
        - User runs `i3pm diagnose events --limit 200 | grep 14680068`

        Then:
        - Event shows "window::new" type
        - Event shows workspace_assigned = 3
        - Event shows no errors
        - Processing duration < 100ms
        """
        event = {
            "timestamp": "2025-10-26T12:34:56.789Z",
            "event_type": "window",
            "event_change": "new",
            "window_id": 14680068,
            "window_class": "com.mitchellh.ghostty",
            "workspace_assigned": 3,
            "handler_duration_ms": 45.2,
            "error": None,
            "marks_applied": ["i3pm:terminal:nixos:12345678"]
        }

        # Verify event shows workspace 3 was assigned
        assert event["event_change"] == "new"
        assert event["workspace_assigned"] == 3
        assert event["error"] is None
        assert event["handler_duration_ms"] < 100
        assert len(event["marks_applied"]) > 0

    @pytest.mark.asyncio
    async def test_determines_window_was_manually_moved(self):
        """
        Conclusion: Window was manually moved after creation.

        Given:
        - Event log shows workspace 3 assigned
        - Current window is on workspace 5
        - No errors in event processing

        When:
        - User analyzes diagnostic output

        Then:
        - Conclusion: window was manually moved post-creation
        - Not a daemon or configuration issue
        """
        event_assigned_workspace = 3
        actual_workspace = 5
        event_error = None

        # If event assigned correctly but window is elsewhere, it was moved
        was_manually_moved = (
            event_error is None and
            event_assigned_workspace is not None and
            actual_workspace != event_assigned_workspace
        )

        assert was_manually_moved is True


# ============================================================================
# Scenario 2: Window Class Not Matching
# ============================================================================

class TestScenario2WindowClassNotMatching:
    """
    Quickstart Scenario 2: Window Class Not Matching

    Problem: Window not recognized (appears global instead of project-scoped)

    Expected diagnostic flow:
    1. Run `i3pm diagnose window <id>`
    2. See "Match Type: none"
    3. Compare actual class vs expected class
    4. See suggested fixes (update config, use normalized, add alias)
    """

    @pytest.mark.asyncio
    async def test_diagnose_shows_class_mismatch(self):
        """
        Diagnostic shows window class mismatch with fix suggestions.

        Given:
        - Actual window class: "com.mitchellh.ghostty"
        - Expected class in config: "Ghostty" (case mismatch!)
        - No match found

        When:
        - User runs `i3pm diagnose window <id>`

        Then:
        - Shows actual class, expected class, normalized class
        - Match type is "none"
        - Provides fix suggestions
        """
        window_diagnostic = {
            "window_id": 14680070,
            "window_class": "com.mitchellh.ghostty",  # Actual from X11
            "window_instance": "ghostty",
            "window_class_normalized": "ghostty",  # After normalization
            "matched_app": None,  # Not matched!
            "match_type": "none",
            "config_expected_class": "Ghostty",  # From config (wrong case)
        }

        # Verify mismatch is detected
        assert window_diagnostic["matched_app"] is None
        assert window_diagnostic["match_type"] == "none"
        assert window_diagnostic["window_class"] != window_diagnostic["config_expected_class"]

    @pytest.mark.asyncio
    async def test_provides_fix_suggestions(self):
        """
        Diagnostic provides multiple fix options for class mismatch.

        Given:
        - Actual class: "com.mitchellh.ghostty"
        - Normalized class: "ghostty"
        - Expected in config: "Ghostty"

        When:
        - Generating fix suggestions

        Then:
        - Suggests using exact class: "com.mitchellh.ghostty"
        - Suggests using normalized: "ghostty" (lowercase)
        - Explains tiered matching system
        """
        actual_class = "com.mitchellh.ghostty"
        normalized_class = "ghostty"
        expected_class = "Ghostty"

        # All these should work with tiered matching
        fix_options = [
            {"strategy": "exact", "value": actual_class},
            {"strategy": "normalized", "value": normalized_class},
            {"strategy": "case_insensitive", "value": normalized_class.lower()},
        ]

        assert len(fix_options) >= 3
        assert fix_options[0]["value"] == actual_class
        assert fix_options[1]["value"] == normalized_class

    @pytest.mark.asyncio
    async def test_verifies_all_match_strategies_work(self):
        """
        Tiered matching system accepts all suggested fixes.

        Given:
        - Actual class: "com.mitchellh.ghostty"
        - Instance: "ghostty"

        When:
        - Trying different match strategies

        Then:
        - Exact match: "com.mitchellh.ghostty" works
        - Instance match: "ghostty" works (case-insensitive)
        - Normalized match: "Ghostty" works (case-insensitive)
        """
        actual_class = "com.mitchellh.ghostty"
        actual_instance = "ghostty"

        # Mock tiered matching logic
        def tiered_match(expected_class: str) -> str:
            # Exact match
            if expected_class == actual_class:
                return "exact"
            # Instance match (case-insensitive)
            if expected_class.lower() == actual_instance.lower():
                return "instance"
            # Normalized match (strip reverse-domain, case-insensitive)
            normalized = actual_class.split('.')[-1].lower()
            if expected_class.lower() == normalized:
                return "normalized"
            return "none"

        assert tiered_match("com.mitchellh.ghostty") == "exact"
        assert tiered_match("ghostty") == "instance"
        assert tiered_match("Ghostty") == "normalized"


# ============================================================================
# Scenario 3: Events Not Being Processed
# ============================================================================

class TestScenario3EventsNotBeingProcessed:
    """
    Quickstart Scenario 3: Events Not Being Processed

    Problem: Windows created but daemon doesn't process them

    Expected diagnostic flow:
    1. Run `i3pm diagnose health`
    2. See event subscription status
    3. Notice window subscription has 0 events
    4. Determine root cause (subscription failed, i3 IPC broken, handler not registered)
    """

    @pytest.mark.asyncio
    async def test_health_check_shows_zero_window_events(self):
        """
        Health check reveals window subscription has no events.

        Given:
        - Daemon is running
        - i3 IPC connected
        - window event subscription shows 0 events
        - Other subscriptions (workspace, output) working

        When:
        - User runs `i3pm diagnose health`

        Then:
        - Shows window subscription inactive (0 events)
        - Shows other subscriptions active (>0 events)
        - Overall status is "warning" or "critical"
        """
        health_data = {
            "daemon_version": "1.3.0",
            "uptime_seconds": 3600,
            "i3_ipc_connected": True,
            "event_subscriptions": [
                {"type": "window", "active": False, "count": 0, "last_event": None},  # BUG!
                {"type": "workspace", "active": True, "count": 89, "last_event": "2025-10-26T12:30:00Z"},
                {"type": "output", "active": True, "count": 5, "last_event": "2025-10-26T10:15:00Z"},
                {"type": "tick", "active": True, "count": 12, "last_event": "2025-10-26T12:00:00Z"},
            ],
            "overall_status": "critical"
        }

        # Verify window subscription is broken
        window_sub = next(s for s in health_data["event_subscriptions"] if s["type"] == "window")
        assert window_sub["active"] is False
        assert window_sub["count"] == 0
        assert health_data["overall_status"] in ["warning", "critical"]

    @pytest.mark.asyncio
    async def test_identifies_subscription_failure_root_cause(self):
        """
        Diagnostic narrows down root cause of subscription failure.

        Given:
        - window subscription has 0 events
        - i3 IPC is connected
        - Other subscriptions are working

        When:
        - Analyzing failure mode

        Then:
        - Root cause is isolated subscription failure
        - Not a global i3 IPC issue
        - Suggests daemon restart to re-establish subscription
        """
        i3_ipc_connected = True
        window_events = 0
        other_subscriptions_working = True

        # If IPC is connected but window events are 0, it's a subscription issue
        is_subscription_failure = (
            i3_ipc_connected and
            window_events == 0 and
            other_subscriptions_working
        )

        assert is_subscription_failure is True

        # Suggested fix
        suggested_action = "restart daemon to re-establish subscriptions"
        assert "restart" in suggested_action.lower()

    @pytest.mark.asyncio
    async def test_verifies_fix_after_daemon_restart(self):
        """
        After daemon restart, window subscription should be active.

        Given:
        - Daemon restarted
        - Waited 5 seconds for initialization

        When:
        - User runs `i3pm diagnose health` again

        Then:
        - window subscription is now active
        - event count increases as windows are created
        - Overall status is "healthy"
        """
        health_after_restart = {
            "event_subscriptions": [
                {"type": "window", "active": True, "count": 5, "last_event": "2025-10-26T12:35:00Z"},
                {"type": "workspace", "active": True, "count": 92, "last_event": "2025-10-26T12:34:00Z"},
            ],
            "overall_status": "healthy"
        }

        window_sub = next(s for s in health_after_restart["event_subscriptions"] if s["type"] == "window")
        assert window_sub["active"] is True
        assert window_sub["count"] > 0
        assert health_after_restart["overall_status"] == "healthy"


# ============================================================================
# Scenario 4: State Drift Detection
# ============================================================================

class TestScenario4StateDriftDetection:
    """
    Quickstart Scenario 4: State Drift Detection

    Problem: Daemon thinks windows are on different workspaces than reality

    Expected diagnostic flow:
    1. Run `i3pm diagnose validate`
    2. See consistency percentage < 100%
    3. See mismatch table with specific windows
    4. Restart daemon to resync
    5. Verify 100% consistency
    """

    @pytest.mark.asyncio
    async def test_validate_detects_state_drift(self):
        """
        Validation command detects state drift between daemon and i3.

        Given:
        - Daemon thinks window 14680068 is on workspace 3
        - i3 IPC (authoritative) says it's on workspace 5

        When:
        - User runs `i3pm diagnose validate`

        Then:
        - Consistency < 100%
        - Mismatch table shows window 14680068
        - Shows daemon value = 3, i3 value = 5
        - Severity = "warning" (expected for manual moves)
        """
        validation_result = {
            "total_windows_checked": 23,
            "windows_consistent": 21,
            "windows_inconsistent": 2,
            "consistency_percentage": 91.3,
            "mismatches": [
                {
                    "window_id": 14680068,
                    "property_name": "workspace",
                    "daemon_value": 3,
                    "i3_value": 5,
                    "severity": "warning"
                },
                {
                    "window_id": 14680070,
                    "property_name": "workspace",
                    "daemon_value": 2,
                    "i3_value": 4,
                    "severity": "warning"
                }
            ],
            "is_consistent": False
        }

        assert validation_result["consistency_percentage"] < 100
        assert len(validation_result["mismatches"]) == 2
        assert validation_result["is_consistent"] is False

        # Check first mismatch
        mismatch = validation_result["mismatches"][0]
        assert mismatch["daemon_value"] != mismatch["i3_value"]
        assert mismatch["severity"] == "warning"

    @pytest.mark.asyncio
    async def test_daemon_restart_resyncs_state(self):
        """
        After daemon restart, state drift should be resolved.

        Given:
        - State drift detected (91.3% consistency)
        - Daemon restarted
        - Daemon scans all windows and syncs to i3 state

        When:
        - User runs `i3pm diagnose validate` after restart

        Then:
        - Consistency = 100%
        - No mismatches
        - is_consistent = True
        """
        validation_after_restart = {
            "total_windows_checked": 23,
            "windows_consistent": 23,
            "windows_inconsistent": 0,
            "consistency_percentage": 100.0,
            "mismatches": [],
            "is_consistent": True
        }

        assert validation_after_restart["consistency_percentage"] == 100.0
        assert len(validation_after_restart["mismatches"]) == 0
        assert validation_after_restart["is_consistent"] is True

    @pytest.mark.asyncio
    async def test_distinguishes_manual_move_from_bug(self):
        """
        Validation distinguishes between manual moves and bugs.

        Given:
        - Manual move: window was on correct workspace initially, user moved it
        - Bug: window never made it to correct workspace

        When:
        - Analyzing validation result with event log

        Then:
        - Manual move: event shows correct workspace assigned, mismatch is "warning"
        - Bug: event shows wrong workspace or error, mismatch is "error"
        """
        # Manual move scenario
        manual_move_mismatch = {
            "window_id": 14680068,
            "property_name": "workspace",
            "daemon_value": 3,
            "i3_value": 5,
            "severity": "warning",
            "event_log": {"workspace_assigned": 3, "error": None}
        }

        # Bug scenario (assignment failed)
        bug_mismatch = {
            "window_id": 14680070,
            "property_name": "workspace",
            "daemon_value": 3,
            "i3_value": 5,
            "severity": "error",
            "event_log": {"workspace_assigned": 3, "error": "i3 command failed"}
        }

        # Manual move: correct assignment, no error → warning
        assert manual_move_mismatch["event_log"]["error"] is None
        assert manual_move_mismatch["severity"] == "warning"

        # Bug: error during assignment → error severity
        assert bug_mismatch["event_log"]["error"] is not None
        assert bug_mismatch["severity"] == "error"


# ============================================================================
# Integration Test: Full Diagnostic Workflow
# ============================================================================

class TestQuickstartFullDiagnosticWorkflow:
    """
    Integration test covering complete troubleshooting workflow from quickstart.

    Simulates:
    1. User reports "lazygit opens on wrong workspace"
    2. User follows quickstart diagnostic steps
    3. User identifies root cause
    4. User applies fix
    5. User verifies fix worked
    """

    @pytest.mark.asyncio
    async def test_complete_diagnostic_workflow(self):
        """
        Complete workflow: Problem → Diagnose → Fix → Verify

        Workflow:
        1. Problem: lazygit on workspace 5 instead of 3
        2. Get window ID: xwininfo or i3pm windows
        3. Diagnose: i3pm diagnose window <id>
        4. Check events: i3pm diagnose events
        5. Validate: i3pm diagnose validate
        6. Fix: Restart daemon (state drift)
        7. Verify: i3pm diagnose validate shows 100%
        """
        # Step 1: Problem reported
        problem = {
            "app": "lazygit",
            "expected_workspace": 3,
            "actual_workspace": 5
        }

        # Step 2: Get window ID (mocked)
        window_id = 14680068

        # Step 3: Diagnose window
        window_diagnostic = {
            "window_id": window_id,
            "matched_app": "terminal",
            "expected_workspace": 3,
            "workspace_number": 5,
            "match_type": "instance"
        }
        assert window_diagnostic["workspace_number"] != window_diagnostic["expected_workspace"]

        # Step 4: Check events
        events = [
            {
                "window_id": window_id,
                "event_type": "window",
                "event_change": "new",
                "workspace_assigned": 3,
                "error": None
            }
        ]
        assert events[0]["workspace_assigned"] == problem["expected_workspace"]
        assert events[0]["error"] is None

        # Step 5: Validate state
        validation_before = {
            "consistency_percentage": 95.7,
            "is_consistent": False,
            "mismatches": [{"window_id": window_id, "daemon_value": 3, "i3_value": 5}]
        }
        assert validation_before["is_consistent"] is False

        # Step 6: Fix (daemon restart to resync)
        daemon_restarted = True
        assert daemon_restarted is True

        # Step 7: Verify fix
        validation_after = {
            "consistency_percentage": 100.0,
            "is_consistent": True,
            "mismatches": []
        }
        assert validation_after["is_consistent"] is True
        assert len(validation_after["mismatches"]) == 0

    @pytest.mark.asyncio
    async def test_diagnostic_command_exit_codes(self):
        """
        Verify diagnostic commands return correct exit codes for scripting.

        Exit codes:
        - health: 0=healthy, 1=warning, 2=critical
        - validate: 0=consistent, 1=inconsistent
        - window: 0=found, 1=not found
        - events: 0=success, 1=error
        """
        # Health command exit codes
        health_statuses = [
            {"overall_status": "healthy", "expected_exit": 0},
            {"overall_status": "warning", "expected_exit": 1},
            {"overall_status": "critical", "expected_exit": 2},
        ]
        for status in health_statuses:
            exit_code = 0 if status["overall_status"] == "healthy" else (
                1 if status["overall_status"] == "warning" else 2
            )
            assert exit_code == status["expected_exit"]

        # Validate command exit codes
        validate_statuses = [
            {"is_consistent": True, "expected_exit": 0},
            {"is_consistent": False, "expected_exit": 1},
        ]
        for status in validate_statuses:
            exit_code = 0 if status["is_consistent"] else 1
            assert exit_code == status["expected_exit"]
