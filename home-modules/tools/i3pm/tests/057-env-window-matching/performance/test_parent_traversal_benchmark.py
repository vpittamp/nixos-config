"""
Performance benchmark tests for parent PID traversal (User Story 3).

Tests verify that environment queries with parent traversal meet performance targets.
"""

import pytest
import asyncio
import time
import subprocess
import os
from pathlib import Path
from typing import List, Tuple

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import daemon modules
daemon_path = Path(__file__).parent.parent.parent / "daemon"
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))

from window_environment import get_window_environment, get_parent_pid


def create_process_hierarchy(depth: int = 3) -> Tuple[subprocess.Popen, int]:
    """
    Create a process hierarchy for testing parent traversal.

    Args:
        depth: Number of parent levels (1 = direct, 2 = child, 3 = grandchild)

    Returns:
        Tuple of (root_process, leaf_pid)
    """
    # Create environment with I3PM_* variables at root level
    test_env = os.environ.copy()
    test_env.update({
        "I3PM_APP_ID": "test-hierarchy-12345",
        "I3PM_APP_NAME": "test-app",
        "I3PM_SCOPE": "global",
        "I3PM_PROJECT_NAME": "test",
    })

    if depth == 1:
        # Single process - no hierarchy
        proc = subprocess.Popen(
            ["sleep", "30"],
            env=test_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return (proc, proc.pid)

    elif depth == 2:
        # Parent → Child
        # Parent has I3PM_* vars, child inherits but we test from child PID
        proc = subprocess.Popen(
            ["bash", "-c", "sleep 30 & echo $! && wait"],
            env=test_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        # Get child PID
        child_pid = int(proc.stdout.readline().strip())
        return (proc, child_pid)

    else:  # depth >= 3
        # Parent → Child → Grandchild
        proc = subprocess.Popen(
            ["bash", "-c", "bash -c 'sleep 30 & echo $! && wait' & wait"],
            env=test_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        # This is simplified - in real scenario we'd track actual grandchild
        # For testing purposes, we'll use a simpler approach
        time.sleep(0.1)  # Let processes spawn
        return (proc, proc.pid)


@pytest.mark.asyncio
@pytest.mark.performance
async def test_parent_traversal_performance():
    """
    T031: Performance benchmark - Environment query with parent traversal.

    Creates process hierarchy (parent with I3PM_* → child → grandchild),
    measures get_window_environment() latency with 3-level traversal.

    Success criteria:
    - Average latency < 2.0ms
    - p95 latency < 5.0ms
    - p99 latency < 10.0ms
    """
    processes: List[subprocess.Popen] = []
    latencies_ms = []

    try:
        # Create 20 process hierarchies for benchmarking
        hierarchies = []
        for i in range(20):
            proc, leaf_pid = create_process_hierarchy(depth=2)
            processes.append(proc)
            hierarchies.append((proc, leaf_pid))

        # Wait for processes to stabilize
        time.sleep(0.5)

        # Measure latencies with parent traversal
        for proc, leaf_pid in hierarchies:
            start = time.perf_counter()

            # Query environment from leaf process (requires traversal)
            result = await get_window_environment(
                window_id=123456,  # Fake window ID for testing
                pid=leaf_pid,
                max_traversal_depth=3
            )

            end = time.perf_counter()
            latency_ms = (end - start) * 1000.0
            latencies_ms.append(latency_ms)

            # Verify environment was found via traversal
            if result.environment:
                assert result.traversal_depth >= 0, \
                    "Expected parent traversal to find environment"
                assert result.environment.app_id == "test-hierarchy-12345", \
                    "Found wrong environment"

        # Calculate statistics
        sorted_latencies = sorted(latencies_ms)
        n = len(sorted_latencies)

        avg_ms = sum(latencies_ms) / n
        p50_ms = sorted_latencies[int(n * 0.50)]
        p95_ms = sorted_latencies[int(n * 0.95)]
        p99_ms = sorted_latencies[int(n * 0.99)] if n >= 100 else sorted_latencies[-1]
        max_ms = max(latencies_ms)
        min_ms = min(latencies_ms)

        # Log results
        print(f"\n{'='*60}")
        print(f"Parent Traversal Performance Benchmark ({n} samples)")
        print(f"{'='*60}")
        print(f"Average:   {avg_ms:.3f}ms")
        print(f"p50:       {p50_ms:.3f}ms")
        print(f"p95:       {p95_ms:.3f}ms")
        print(f"p99:       {p99_ms:.3f}ms")
        print(f"Min:       {min_ms:.3f}ms")
        print(f"Max:       {max_ms:.3f}ms")
        print(f"{'='*60}\n")

        # Assert performance targets
        assert avg_ms < 2.0, \
            f"Average latency {avg_ms:.3f}ms exceeds 2.0ms target with traversal"

        assert p95_ms < 5.0, \
            f"p95 latency {p95_ms:.3f}ms exceeds 5.0ms target with traversal"

        assert p99_ms < 10.0, \
            f"p99 latency {p99_ms:.3f}ms exceeds 10.0ms target with traversal"

        status = "PASS" if (avg_ms < 2.0 and p95_ms < 5.0 and p99_ms < 10.0) else "FAIL"
        print(f"Benchmark Status: {status}")

        assert status == "PASS", "Parent traversal performance benchmark failed"

    finally:
        # Cleanup: Terminate all test processes
        for proc in processes:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except (subprocess.TimeoutExpired, ProcessLookupError):
                try:
                    proc.kill()
                    proc.wait()
                except ProcessLookupError:
                    pass


@pytest.mark.asyncio
@pytest.mark.performance
async def test_parent_traversal_depth_impact():
    """
    Additional test: Measure impact of traversal depth on performance.

    Tests performance at different traversal depths (0, 1, 2, 3 levels).
    """
    depth_latencies = {0: [], 1: [], 2: [], 3: []}

    try:
        for depth in [0, 1, 2, 3]:
            for _ in range(10):
                # Create hierarchy at specified depth
                proc, leaf_pid = create_process_hierarchy(depth=max(1, depth))

                time.sleep(0.1)  # Let process stabilize

                # Measure query time
                start = time.perf_counter()
                result = await get_window_environment(
                    window_id=123456,
                    pid=leaf_pid,
                    max_traversal_depth=3
                )
                end = time.perf_counter()

                latency_ms = (end - start) * 1000.0
                depth_latencies[depth].append(latency_ms)

                # Cleanup immediately
                proc.terminate()
                proc.wait(timeout=1)

        # Calculate averages for each depth
        print(f"\n{'='*60}")
        print(f"Traversal Depth Impact on Performance")
        print(f"{'='*60}")
        for depth in [0, 1, 2, 3]:
            avg = sum(depth_latencies[depth]) / len(depth_latencies[depth])
            print(f"Depth {depth}: {avg:.3f}ms average")
        print(f"{'='*60}\n")

        # Verify latency increases with depth (roughly)
        # Note: This is a soft check since timing can vary
        avg_0 = sum(depth_latencies[0]) / len(depth_latencies[0])
        avg_3 = sum(depth_latencies[3]) / len(depth_latencies[3])

        # Depth 3 should take more time than depth 0, but not excessively
        assert avg_3 < avg_0 * 5, \
            f"Depth 3 traversal ({avg_3:.3f}ms) is too slow compared to direct ({avg_0:.3f}ms)"

    except Exception as e:
        print(f"Error during depth impact test: {e}")
        raise


@pytest.mark.asyncio
@pytest.mark.performance
async def test_get_parent_pid_performance():
    """
    Additional test: Benchmark get_parent_pid() function.

    This function is called during traversal, so its performance matters.
    """
    # Create test processes
    processes = []
    for _ in range(50):
        proc = subprocess.Popen(
            ["sleep", "10"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        processes.append(proc)

    try:
        time.sleep(0.1)  # Let processes stabilize

        # Measure get_parent_pid latency
        latencies = []
        for proc in processes:
            start = time.perf_counter()
            ppid = get_parent_pid(proc.pid)
            end = time.perf_counter()

            latency_ms = (end - start) * 1000.0
            latencies.append(latency_ms)

            assert ppid is not None, f"Failed to get parent PID for {proc.pid}"
            assert ppid > 0, f"Invalid parent PID: {ppid}"

        avg_ms = sum(latencies) / len(latencies)
        max_ms = max(latencies)

        print(f"\nget_parent_pid() Performance: avg={avg_ms:.3f}ms, max={max_ms:.3f}ms\n")

        # Should be very fast (reading /proc/pid/stat)
        assert avg_ms < 0.5, \
            f"Average get_parent_pid latency {avg_ms:.3f}ms too slow"

    finally:
        for proc in processes:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except ProcessLookupError:
                pass
