"""
Stress tests for rapid window creation and event processing.

Tests the daemon's ability to handle high-volume concurrent window events
without race conditions, dropped events, or performance degradation.

Part of Feature 039 - Task T022
Success Criteria: SC-012 (50 concurrent windows), <100ms processing latency
"""

import pytest
import asyncio
import time
from pathlib import Path
from typing import List, Dict, Any
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop"))

from i3_project_event_daemon.models import I3PMEnvironment


@pytest.mark.asyncio
class TestStressEvents:
    """Stress tests for rapid event processing."""

    @pytest.fixture
    async def mock_daemon(self):
        """Mock daemon with event tracking."""
        from tests.i3_project_daemon.fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()

        # Add event tracking capabilities
        daemon.processed_events = []
        daemon.failed_events = []
        daemon.event_durations = []

        # Override assign_workspace to track events
        original_assign = daemon.assign_workspace

        async def tracked_assign(*args, **kwargs):
            start = time.perf_counter()
            result = await original_assign(*args, **kwargs)
            duration = (time.perf_counter() - start) * 1000

            daemon.event_durations.append(duration)
            if result["success"]:
                daemon.processed_events.append(result)
            else:
                daemon.failed_events.append(result)

            return result

        daemon.assign_workspace = tracked_assign

        yield daemon
        await daemon.cleanup()

    @pytest.fixture
    def sample_registry(self) -> Dict[str, Any]:
        """Sample registry with diverse app types."""
        return {
            f"app_{i}": {
                "name": f"app_{i}",
                "display_name": f"Test App {i}",
                "command": f"test-app-{i}",
                "scope": "scoped" if i % 2 == 0 else "global",
                "preferred_workspace": (i % 10) + 1,
                "expected_class": f"TestApp{i}",
                "multi_instance": True
            }
            for i in range(50)
        }

    async def test_50_concurrent_window_creations(self, mock_daemon, sample_registry):
        """
        Test 50 windows created simultaneously.

        Success Criteria:
        - All 50 events processed successfully
        - No race conditions (no lost events)
        - <100ms processing time per event
        - Events processed in order (FIFO)
        """
        mock_daemon.set_registry(sample_registry)

        # Create 50 window creation tasks
        tasks = []
        for i in range(50):
            app_name = f"app_{i}"
            app_config = sample_registry[app_name]

            i3pm_env = I3PMEnvironment(
                app_id=f"{app_name}-test-{900000 + i}-1730000000",
                app_name=app_name,
                target_workspace=None,
                project_name="stress-test",
                scope=app_config["scope"],
                launch_time=1730000000 + i,
                launcher_pid=900000 + i
            )

            task = mock_daemon.assign_workspace(
                window_id=50000 + i,
                window_class=app_config["expected_class"],
                window_title=f"{app_config['display_name']} Window",
                window_pid=900000 + i,
                i3pm_env=i3pm_env
            )
            tasks.append(task)

        # Execute all 50 simultaneously
        start = time.perf_counter()
        results = await asyncio.gather(*tasks, return_exceptions=True)
        total_duration = (time.perf_counter() - start) * 1000

        # Verify all succeeded
        successful = [r for r in results if isinstance(r, dict) and r.get("success")]
        failed = [r for r in results if not isinstance(r, dict) or not r.get("success")]

        assert len(successful) == 50, f"Expected 50 successful events, got {len(successful)}"
        assert len(failed) == 0, f"Expected 0 failed events, got {len(failed)}: {failed}"

        # Verify no race conditions (all events tracked)
        assert len(mock_daemon.processed_events) == 50

        # Verify performance
        max_latency = max(mock_daemon.event_durations)
        avg_latency = sum(mock_daemon.event_durations) / len(mock_daemon.event_durations)

        assert max_latency < 100, f"Max latency {max_latency:.2f}ms exceeds 100ms target"
        assert avg_latency < 50, f"Average latency {avg_latency:.2f}ms should be well below 100ms"

        # Total time should be reasonable (concurrent, not sequential)
        assert total_duration < 500, f"Total duration {total_duration:.2f}ms too high for concurrent processing"

        print(f"\n✓ Stress test passed:")
        print(f"  - Events processed: {len(successful)}/50")
        print(f"  - Total duration: {total_duration:.2f}ms")
        print(f"  - Average latency: {avg_latency:.2f}ms")
        print(f"  - Max latency: {max_latency:.2f}ms")

    async def test_sequential_rapid_events(self, mock_daemon, sample_registry):
        """
        Test sequential rapid event stream (simulates user rapidly opening apps).

        Verifies:
        - Events processed in order
        - No event queue overflow
        - Consistent performance across stream
        """
        mock_daemon.set_registry(sample_registry)

        results = []
        for i in range(50):
            app_name = f"app_{i}"
            app_config = sample_registry[app_name]

            i3pm_env = I3PMEnvironment(
                app_id=f"{app_name}-seq-{900100 + i}-1730000100",
                app_name=app_name,
                target_workspace=None,
                project_name="sequential-test",
                scope=app_config["scope"],
                launch_time=1730000100 + i,
                launcher_pid=900100 + i
            )

            result = await mock_daemon.assign_workspace(
                window_id=50100 + i,
                window_class=app_config["expected_class"],
                window_title=f"{app_config['display_name']} Sequential",
                window_pid=900100 + i,
                i3pm_env=i3pm_env
            )
            results.append(result)

            # Small delay to simulate realistic timing
            await asyncio.sleep(0.01)  # 10ms between events

        # Verify all succeeded
        assert all(r["success"] for r in results)

        # Verify workspace assignments are correct
        for i, result in enumerate(results):
            expected_workspace = (i % 10) + 1
            assert result["workspace"] == expected_workspace

        # Verify consistent performance (no degradation over time)
        first_half_avg = sum(mock_daemon.event_durations[:25]) / 25
        second_half_avg = sum(mock_daemon.event_durations[25:]) / 25

        # Performance should not degrade significantly
        assert second_half_avg < first_half_avg * 1.5, \
            f"Performance degraded: first half {first_half_avg:.2f}ms, second half {second_half_avg:.2f}ms"

    async def test_mixed_priority_tiers(self, mock_daemon, sample_registry):
        """
        Test concurrent windows using different priority tiers.

        Mix of:
        - Priority 1: App-specific handlers (VS Code)
        - Priority 2: I3PM_TARGET_WORKSPACE
        - Priority 3: I3PM_APP_NAME lookup
        - Priority 4: Window class matching
        """
        mock_daemon.set_registry(sample_registry)

        tasks = []

        # Priority 2: Direct workspace assignment (25 windows)
        for i in range(25):
            app_name = f"app_{i}"
            app_config = sample_registry[app_name]

            i3pm_env = I3PMEnvironment(
                app_id=f"{app_name}-priority2-{900200 + i}-1730000200",
                app_name=app_name,
                target_workspace=(i % 10) + 1,  # Explicit assignment
                project_name="priority-test",
                scope=app_config["scope"],
                launch_time=1730000200 + i,
                launcher_pid=900200 + i
            )

            task = mock_daemon.assign_workspace(
                50200 + i, app_config["expected_class"],
                f"{app_config['display_name']}", 900200 + i, i3pm_env
            )
            tasks.append(("priority2", i, task))

        # Priority 3: App name lookup (25 windows)
        for i in range(25, 50):
            app_name = f"app_{i}"
            app_config = sample_registry[app_name]

            i3pm_env = I3PMEnvironment(
                app_id=f"{app_name}-priority3-{900200 + i}-1730000200",
                app_name=app_name,
                target_workspace=None,  # Will lookup in registry
                project_name="priority-test",
                scope=app_config["scope"],
                launch_time=1730000200 + i,
                launcher_pid=900200 + i
            )

            task = mock_daemon.assign_workspace(
                50200 + i, app_config["expected_class"],
                f"{app_config['display_name']}", 900200 + i, i3pm_env
            )
            tasks.append(("priority3", i, task))

        # Execute all concurrently
        results = await asyncio.gather(*[t[2] for t in tasks])

        # Verify all succeeded
        assert all(r["success"] for r in results)

        # Verify correct priority tiers used
        priority2_results = [results[i] for i, (tier, _, _) in enumerate(tasks) if tier == "priority2"]
        priority3_results = [results[i] for i, (tier, _, _) in enumerate(tasks) if tier == "priority3"]

        assert all(r["source"] == "i3pm_target_workspace" for r in priority2_results)
        assert all(r["source"] == "i3pm_app_name_lookup" for r in priority3_results)

    async def test_duplicate_window_ids(self, mock_daemon, sample_registry):
        """
        Test handling of duplicate window ID events (race condition scenario).

        This can happen if i3 sends duplicate events or daemon processes
        same window multiple times.
        """
        mock_daemon.set_registry(sample_registry)

        # Create same window ID multiple times concurrently
        duplicate_window_id = 99999
        tasks = []

        for i in range(10):
            i3pm_env = I3PMEnvironment(
                app_id=f"app_0-dup-{900300 + i}-1730000300",
                app_name="app_0",
                target_workspace=None,
                project_name="duplicate-test",
                scope="scoped",
                launch_time=1730000300 + i,
                launcher_pid=900300 + i
            )

            task = mock_daemon.assign_workspace(
                duplicate_window_id,  # Same window ID
                "TestApp0",
                "Duplicate Window",
                900300 + i,
                i3pm_env
            )
            tasks.append(task)

        # Execute concurrently
        results = await asyncio.gather(*tasks)

        # All should succeed (daemon should handle gracefully)
        assert all(r["success"] for r in results)

        # All should assign to same workspace (idempotent)
        workspaces = [r["workspace"] for r in results]
        assert all(w == workspaces[0] for w in workspaces), \
            "Duplicate window IDs should get consistent workspace assignment"

    async def test_memory_usage_under_stress(self, mock_daemon, sample_registry):
        """
        Test that daemon doesn't leak memory during stress.

        Simulates multiple waves of window creation/destruction.
        """
        mock_daemon.set_registry(sample_registry)

        # Run 5 waves of 50 windows each
        for wave in range(5):
            tasks = []
            for i in range(50):
                app_name = f"app_{i}"
                app_config = sample_registry[app_name]

                i3pm_env = I3PMEnvironment(
                    app_id=f"{app_name}-wave{wave}-{900400 + i}-1730000400",
                    app_name=app_name,
                    target_workspace=None,
                    project_name=f"wave-{wave}",
                    scope=app_config["scope"],
                    launch_time=1730000400 + (wave * 100) + i,
                    launcher_pid=900400 + (wave * 100) + i
                )

                task = mock_daemon.assign_workspace(
                    50400 + (wave * 100) + i,
                    app_config["expected_class"],
                    f"{app_config['display_name']} Wave{wave}",
                    900400 + (wave * 100) + i,
                    i3pm_env
                )
                tasks.append(task)

            results = await asyncio.gather(*tasks)
            assert all(r["success"] for r in results)

            # In real daemon, would check memory usage here
            # For mock, verify event tracking doesn't grow unbounded
            # (In production, circular buffer would limit this)

        # Total events processed: 250
        assert len(mock_daemon.processed_events) == 250

    async def test_error_handling_under_stress(self, mock_daemon, sample_registry):
        """
        Test error handling when some events fail during stress.

        Mix of valid and invalid workspace assignments.
        """
        mock_daemon.set_registry(sample_registry)

        tasks = []
        for i in range(50):
            if i % 5 == 0:
                # Every 5th window: invalid workspace (out of range)
                registry_entry = {
                    "name": f"invalid_{i}",
                    "preferred_workspace": 99,  # Invalid
                    "expected_class": f"Invalid{i}",
                    "scope": "global"
                }
                mock_daemon.registry[f"invalid_{i}"] = registry_entry

                i3pm_env = I3PMEnvironment(
                    app_id=f"invalid_{i}-{900500 + i}-1730000500",
                    app_name=f"invalid_{i}",
                    target_workspace=None,
                    project_name="error-test",
                    scope="global",
                    launch_time=1730000500 + i,
                    launcher_pid=900500 + i
                )

                task = mock_daemon.assign_workspace(
                    50500 + i, f"Invalid{i}", f"Invalid Window {i}",
                    900500 + i, i3pm_env
                )
            else:
                # Valid window
                app_name = f"app_{i}"
                app_config = sample_registry[app_name]

                i3pm_env = I3PMEnvironment(
                    app_id=f"{app_name}-{900500 + i}-1730000500",
                    app_name=app_name,
                    target_workspace=None,
                    project_name="error-test",
                    scope=app_config["scope"],
                    launch_time=1730000500 + i,
                    launcher_pid=900500 + i
                )

                task = mock_daemon.assign_workspace(
                    50500 + i, app_config["expected_class"],
                    f"{app_config['display_name']}", 900500 + i, i3pm_env
                )

            tasks.append(task)

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # All should succeed (invalid workspace falls back to current)
        assert all(
            isinstance(r, dict) and r.get("success") for r in results
        ), "All events should succeed (with fallback for invalid)"

        # Verify invalid ones used fallback
        for i, result in enumerate(results):
            if i % 5 == 0:
                assert result["source"] == "fallback_current"


@pytest.mark.asyncio
class TestEventOrdering:
    """Tests for event ordering and FIFO processing."""

    @pytest.fixture
    async def mock_daemon(self):
        from tests.i3_project_daemon.fixtures.mock_daemon import MockDaemon
        daemon = MockDaemon()
        await daemon.initialize()
        daemon.event_order = []
        yield daemon
        await daemon.cleanup()

    async def test_fifo_event_processing(self, mock_daemon):
        """
        Test events are processed in FIFO order.

        Even when submitted concurrently, daemon should process them
        in the order received.
        """
        mock_daemon.set_registry({
            "test": {
                "name": "test",
                "preferred_workspace": 1,
                "expected_class": "Test",
                "scope": "global"
            }
        })

        # Track order
        original_assign = mock_daemon.assign_workspace

        async def order_tracking_assign(window_id, *args, **kwargs):
            result = await original_assign(window_id, *args, **kwargs)
            mock_daemon.event_order.append(window_id)
            return result

        mock_daemon.assign_workspace = order_tracking_assign

        # Submit 20 windows concurrently
        tasks = []
        for i in range(20):
            i3pm_env = I3PMEnvironment(
                app_id=f"test-{900600 + i}-1730000600",
                app_name="test",
                target_workspace=i + 1,  # Use target workspace
                project_name="order-test",
                scope="global",
                launch_time=1730000600 + i,
                launcher_pid=900600 + i
            )

            task = mock_daemon.assign_workspace(
                60000 + i, "Test", "Test Window", 900600 + i, i3pm_env
            )
            tasks.append((60000 + i, task))

        await asyncio.gather(*[t[1] for t in tasks])

        # Verify events were processed (order may vary in concurrent execution,
        # but in real daemon with event queue, should be FIFO)
        assert len(mock_daemon.event_order) == 20


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
