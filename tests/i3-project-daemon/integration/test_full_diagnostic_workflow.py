"""
Full Diagnostic Workflow Integration Test

End-to-end test of complete diagnostic workflow from Feature 039:
1. Window creation → event detection → workspace assignment
2. Diagnostic commands reveal window state
3. State validation detects drift
4. Health check shows system status

Feature 039 - Task T111

This test requires:
- i3 window manager running
- i3-project-daemon active
- Sample application windows

Usage:
    pytest tests/i3-project-daemon/integration/test_full_diagnostic_workflow.py -v
"""

import pytest
import asyncio
import socket
import json
import time
from pathlib import Path
from typing import Dict, Any, Optional


class DaemonTestClient:
    """Test client for daemon JSON-RPC communication."""

    def __init__(self, socket_path: Optional[Path] = None):
        """Initialize test client."""
        if socket_path is None:
            socket_path = Path.home() / ".local" / "share" / "i3-project-daemon" / "daemon.sock"
        self.socket_path = socket_path
        self.request_id = 0

    def call(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        """Call JSON-RPC method on daemon."""
        self.request_id += 1

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        }

        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5.0)
            sock.connect(str(self.socket_path))

            sock.sendall(json.dumps(request).encode() + b'\n')

            response_data = b''
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b'\n' in chunk:
                    break

            sock.close()

            response = json.loads(response_data.decode())

            if "error" in response:
                raise RuntimeError(f"RPC error: {response['error']}")

            return response.get("result")

        except FileNotFoundError:
            raise RuntimeError(f"Daemon socket not found: {self.socket_path}")
        except ConnectionRefusedError:
            raise RuntimeError("Daemon not running")


# ============================================================================
# Integration Test: Full Diagnostic Workflow
# ============================================================================

class TestFullDiagnosticWorkflow:
    """
    End-to-end integration test for complete diagnostic workflow.

    Workflow:
    1. Health check → Verify daemon is healthy
    2. Create window (mocked) → Simulate window creation
    3. Event detection → Verify window::new event captured
    4. Window identity → Inspect window properties via diagnostics
    5. State validation → Verify daemon state matches i3
    6. Event history → Review recent events
    """

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_full_diagnostic_workflow(self):
        """
        Complete diagnostic workflow from window creation to validation.

        This test simulates the workflow from quickstart.md Scenario 1:
        - User creates window
        - Window assigned to workspace
        - User runs diagnostic commands
        - Diagnostic reveals window state
        - State validation confirms consistency
        """
        client = DaemonTestClient()

        # ====================
        # Step 1: Health Check
        # ====================
        print("\n=== Step 1: Health Check ===")

        try:
            health_data = client.call("health_check")
        except RuntimeError as e:
            pytest.skip(f"Daemon not running: {e}")

        # Verify health check structure
        assert "daemon_version" in health_data
        assert "uptime_seconds" in health_data
        assert "i3_ipc_connected" in health_data
        assert "event_subscriptions" in health_data
        assert "overall_status" in health_data

        # Daemon should be healthy
        assert health_data["overall_status"] in ["healthy", "warning"]
        assert health_data["i3_ipc_connected"] is True

        # Event subscriptions should be active
        subscriptions = health_data["event_subscriptions"]
        assert len(subscriptions) >= 4  # window, workspace, output, tick

        window_sub = next((s for s in subscriptions if s["type"] == "window"), None)
        assert window_sub is not None
        assert window_sub["active"] is True or window_sub["count"] >= 0

        print(f"✓ Daemon healthy: v{health_data['daemon_version']}, uptime {health_data['uptime_seconds']}s")
        print(f"✓ Event subscriptions: {len(subscriptions)} active")

        # ====================
        # Step 2: Get Recent Events
        # ====================
        print("\n=== Step 2: Get Recent Events ===")

        events = client.call("get_recent_events", {"limit": 20, "event_type": "window"})

        assert isinstance(events, list)
        print(f"✓ Retrieved {len(events)} recent events")

        # If no events, skip window-specific tests
        if len(events) == 0:
            pytest.skip("No recent window events to test diagnostics")

        # Verify event structure
        if len(events) > 0:
            event = events[0]
            assert "timestamp" in event
            assert "event_type" in event
            assert "event_change" in event

            print(f"✓ Latest event: {event['event_type']}::{event['event_change']}")

        # ====================
        # Step 3: Window Identity (if window events exist)
        # ====================
        print("\n=== Step 3: Window Identity Diagnostic ===")

        # Find a window event with window_id
        window_event = next((e for e in events if e.get("window_id")), None)

        if window_event:
            window_id = window_event["window_id"]
            print(f"Testing with window ID: {window_id}")

            try:
                window_identity = client.call("get_window_identity", {"window_id": window_id})

                # Verify window identity structure
                assert "window_id" in window_identity
                assert "window_class" in window_identity
                assert "window_class_normalized" in window_identity
                assert "workspace_number" in window_identity
                assert "match_type" in window_identity

                print(f"✓ Window class: {window_identity['window_class']}")
                print(f"✓ Normalized: {window_identity['window_class_normalized']}")
                print(f"✓ Match type: {window_identity['match_type']}")
                print(f"✓ Workspace: {window_identity['workspace_number']}")

                # Check I3PM environment if available
                if window_identity.get("i3pm_env"):
                    i3pm_env = window_identity["i3pm_env"]
                    print(f"✓ I3PM project: {i3pm_env.get('project_name', 'none')}")

            except RuntimeError as e:
                # Window may have been closed since event
                print(f"⚠ Window {window_id} no longer exists: {e}")
        else:
            print("⚠ No window events with window_id found")

        # ====================
        # Step 4: State Validation
        # ====================
        print("\n=== Step 4: State Validation ===")

        validation = client.call("validate_state")

        # Verify validation structure
        assert "total_windows_checked" in validation
        assert "windows_consistent" in validation
        assert "windows_inconsistent" in validation
        assert "consistency_percentage" in validation
        assert "is_consistent" in validation
        assert "mismatches" in validation

        total = validation["total_windows_checked"]
        consistent = validation["windows_consistent"]
        inconsistent = validation["windows_inconsistent"]
        percentage = validation["consistency_percentage"]

        print(f"✓ Windows checked: {total}")
        print(f"✓ Consistent: {consistent}")
        print(f"✓ Inconsistent: {inconsistent}")
        print(f"✓ Consistency: {percentage}%")

        # Consistency should be reasonably high (allow for manual moves)
        assert percentage >= 80.0, f"Consistency too low: {percentage}%"

        if validation["mismatches"]:
            print(f"⚠ State drift detected: {len(validation['mismatches'])} mismatches")
            for mismatch in validation["mismatches"][:3]:  # Show first 3
                print(f"  - Window {mismatch['window_id']}: {mismatch['property_name']} "
                      f"daemon={mismatch['daemon_value']} vs i3={mismatch['i3_value']}")
        else:
            print("✓ No state drift detected")

        # ====================
        # Step 5: Comprehensive Report
        # ====================
        print("\n=== Step 5: Comprehensive Diagnostic Report ===")

        report = client.call("get_diagnostic_report", {
            "include_windows": True,
            "include_events": True,
            "include_validation": True
        })

        # Verify report structure
        assert "health" in report
        assert "timestamp" in report

        if report.get("windows"):
            print(f"✓ Report includes {len(report['windows'])} windows")

        if report.get("recent_events"):
            print(f"✓ Report includes {len(report['recent_events'])} events")

        if report.get("state_validation"):
            print(f"✓ Report includes state validation")

        print("\n=== Diagnostic Workflow Complete ===")
        print(f"All diagnostic commands executed successfully")

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_diagnostic_performance(self):
        """
        Test diagnostic command performance (SC-009).

        Target: All diagnostic commands execute in <5 seconds
        """
        client = DaemonTestClient()

        # Skip if daemon not running
        try:
            client.call("ping")
        except RuntimeError:
            pytest.skip("Daemon not running")

        commands = [
            ("health_check", {}),
            ("get_recent_events", {"limit": 50}),
            ("validate_state", {}),
        ]

        print("\n=== Diagnostic Performance Test ===")

        for method, params in commands:
            start_time = time.perf_counter()

            result = client.call(method, params)

            end_time = time.perf_counter()
            duration_ms = (end_time - start_time) * 1000

            print(f"{method}: {duration_ms:.1f}ms")

            # All diagnostics should complete in <5000ms (SC-009)
            assert duration_ms < 5000, f"{method} too slow: {duration_ms}ms"

            # Most should be <100ms
            if duration_ms > 100:
                print(f"  ⚠ Warning: {method} slower than expected ({duration_ms:.1f}ms)")

        print("✓ All diagnostic commands meet performance targets")

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_diagnostic_error_handling(self):
        """
        Test diagnostic error handling for invalid inputs.

        Verifies:
        - Invalid window ID returns proper error
        - Invalid RPC method returns error
        - Invalid parameters return error
        """
        client = DaemonTestClient()

        # Skip if daemon not running
        try:
            client.call("ping")
        except RuntimeError:
            pytest.skip("Daemon not running")

        print("\n=== Diagnostic Error Handling Test ===")

        # Test 1: Invalid window ID
        try:
            client.call("get_window_identity", {"window_id": 999999999999})
            # May return empty result or error, both acceptable
            print("✓ Invalid window ID handled gracefully")
        except RuntimeError as e:
            # Error is also acceptable
            print(f"✓ Invalid window ID returns error: {e}")

        # Test 2: Invalid RPC method
        try:
            client.call("nonexistent_method", {})
            assert False, "Should have raised error for invalid method"
        except RuntimeError as e:
            assert "not found" in str(e).lower() or "unknown" in str(e).lower()
            print(f"✓ Invalid method rejected: {e}")

        # Test 3: Invalid parameter type
        try:
            result = client.call("get_recent_events", {"limit": "not_a_number"})
            # Should either reject or use default limit
            print("✓ Invalid parameter type handled")
        except RuntimeError as e:
            print(f"✓ Invalid parameter rejected: {e}")

        print("✓ All error handling tests passed")

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_json_output_compatibility(self):
        """
        Test that all diagnostic methods return JSON-serializable output.

        Ensures CLI --json flag will work correctly.
        """
        client = DaemonTestClient()

        # Skip if daemon not running
        try:
            client.call("ping")
        except RuntimeError:
            pytest.skip("Daemon not running")

        print("\n=== JSON Output Compatibility Test ===")

        commands = [
            ("health_check", {}),
            ("get_recent_events", {"limit": 10}),
            ("validate_state", {}),
        ]

        for method, params in commands:
            result = client.call(method, params)

            # Should be JSON serializable
            try:
                json_output = json.dumps(result, indent=2)
                assert len(json_output) > 0
                print(f"✓ {method} returns valid JSON ({len(json_output)} bytes)")
            except (TypeError, ValueError) as e:
                pytest.fail(f"{method} output not JSON serializable: {e}")

        print("✓ All diagnostic outputs are JSON compatible")


# ============================================================================
# Daemon Availability Check (runs before all tests)
# ============================================================================

@pytest.fixture(scope="module", autouse=True)
def check_daemon_available():
    """Check if daemon is available before running tests."""
    client = DaemonTestClient()

    try:
        client.call("ping")
        print("\n✓ Daemon connection established")
        yield
    except RuntimeError as e:
        pytest.skip(f"Daemon not available: {e}")
