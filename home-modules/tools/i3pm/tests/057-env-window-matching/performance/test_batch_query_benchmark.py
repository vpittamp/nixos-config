"""
Performance benchmark tests for batch environment queries (User Story 3).

Tests verify that querying multiple windows simultaneously meets performance targets.
"""

import pytest
import asyncio
import time
import subprocess
import os
from pathlib import Path
from typing import List

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import daemon modules
daemon_path = Path(__file__).parent.parent.parent / "daemon"
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))

from window_environment import get_window_environment, read_process_environ


@pytest.mark.asyncio
@pytest.mark.performance
async def test_batch_query_50_windows():
    """
    T032: Performance benchmark - Batch query for 50 windows.

    Launches 50 test applications, measures total time to query all environments.

    Success criteria:
    - Total time < 100ms (avg 2ms per window)
    - No performance degradation with increasing count
    - All queries complete successfully
    """
    # Create 50 test processes
    processes: List[subprocess.Popen] = []
    test_env = os.environ.copy()
    test_env.update({
        "I3PM_APP_NAME": "test-batch",
        "I3PM_SCOPE": "global",
    })

    try:
        # Spawn 50 processes with unique APP_IDs
        for i in range(50):
            env = test_env.copy()
            env["I3PM_APP_ID"] = f"test-batch-{i}"

            proc = subprocess.Popen(
                ["sleep", "30"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            processes.append(proc)

        # Wait for processes to stabilize
        time.sleep(0.5)

        # Measure batch query time - Sequential approach
        print(f"\n{'='*60}")
        print(f"Sequential Batch Query (50 windows)")
        print(f"{'='*60}")

        start_time = time.perf_counter()
        results = []

        for i, proc in enumerate(processes):
            result = await get_window_environment(
                window_id=100000 + i,
                pid=proc.pid,
            )
            results.append(result)

        end_time = time.perf_counter()
        total_time_ms = (end_time - start_time) * 1000.0
        avg_per_window = total_time_ms / len(processes)

        # Verify all queries succeeded
        successful = sum(1 for r in results if r.environment is not None)

        print(f"Total Time:      {total_time_ms:.1f}ms")
        print(f"Per Window:      {avg_per_window:.2f}ms")
        print(f"Successful:      {successful}/{len(processes)}")
        print(f"{'='*60}\n")

        # Assert performance targets
        assert total_time_ms < 100.0, \
            f"Total batch query time {total_time_ms:.1f}ms exceeds 100ms target"

        assert avg_per_window < 2.0, \
            f"Average per-window time {avg_per_window:.2f}ms exceeds 2ms target"

        assert successful == len(processes), \
            f"Not all queries succeeded: {successful}/{len(processes)}"

        status = "PASS" if (total_time_ms < 100.0 and avg_per_window < 2.0) else "FAIL"
        print(f"Benchmark Status: {status}")

        assert status == "PASS", "Batch query performance benchmark failed"

    finally:
        # Cleanup
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
async def test_batch_query_parallel():
    """
    Additional test: Parallel batch queries using asyncio.gather().

    Tests if parallel queries improve performance over sequential.
    """
    # Create 30 test processes
    processes: List[subprocess.Popen] = []
    test_env = os.environ.copy()

    try:
        for i in range(30):
            env = test_env.copy()
            env.update({
                "I3PM_APP_ID": f"test-parallel-{i}",
                "I3PM_APP_NAME": "test-parallel",
                "I3PM_SCOPE": "global",
            })

            proc = subprocess.Popen(
                ["sleep", "20"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            processes.append(proc)

        time.sleep(0.3)

        # Measure parallel query time
        print(f"\n{'='*60}")
        print(f"Parallel Batch Query (30 windows)")
        print(f"{'='*60}")

        start_time = time.perf_counter()

        # Query all windows in parallel
        tasks = [
            get_window_environment(window_id=200000 + i, pid=proc.pid)
            for i, proc in enumerate(processes)
        ]
        results = await asyncio.gather(*tasks)

        end_time = time.perf_counter()
        total_time_ms = (end_time - start_time) * 1000.0
        avg_per_window = total_time_ms / len(processes)

        successful = sum(1 for r in results if r.environment is not None)

        print(f"Total Time:      {total_time_ms:.1f}ms")
        print(f"Per Window:      {avg_per_window:.2f}ms")
        print(f"Successful:      {successful}/{len(processes)}")
        print(f"{'='*60}\n")

        # Parallel should be much faster (I/O can overlap)
        # Target: <50ms total for 30 windows
        assert total_time_ms < 50.0, \
            f"Parallel batch query {total_time_ms:.1f}ms too slow"

        assert successful == len(processes), \
            f"Not all parallel queries succeeded"

    finally:
        for proc in processes:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except ProcessLookupError:
                pass


@pytest.mark.performance
def test_batch_query_scaling():
    """
    Additional test: Test scaling behavior with increasing window counts.

    Verifies that query time scales linearly (not exponentially) with window count.
    """
    window_counts = [10, 20, 30, 50]
    timings = {}

    for count in window_counts:
        # Create processes
        processes = []
        env = os.environ.copy()

        try:
            for i in range(count):
                test_env = env.copy()
                test_env.update({
                    "I3PM_APP_ID": f"test-scaling-{i}",
                    "I3PM_APP_NAME": "test-scaling",
                    "I3PM_SCOPE": "global",
                })

                proc = subprocess.Popen(
                    ["sleep", "15"],
                    env=test_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                processes.append(proc)

            time.sleep(0.2)

            # Measure query time using synchronous approach
            start = time.perf_counter()
            for proc in processes:
                env_vars = read_process_environ(proc.pid)
                assert "I3PM_APP_ID" in env_vars
            end = time.perf_counter()

            total_ms = (end - start) * 1000.0
            per_window = total_ms / count

            timings[count] = {
                "total_ms": total_ms,
                "per_window_ms": per_window,
            }

        finally:
            for proc in processes:
                try:
                    proc.terminate()
                    proc.wait(timeout=1)
                except ProcessLookupError:
                    pass

    # Print scaling results
    print(f"\n{'='*60}")
    print(f"Scaling Behavior Test")
    print(f"{'='*60}")
    for count in window_counts:
        t = timings[count]
        print(f"{count:3d} windows: {t['total_ms']:6.1f}ms total, {t['per_window_ms']:5.2f}ms per window")
    print(f"{'='*60}\n")

    # Verify roughly linear scaling
    # Per-window time should not increase significantly with count
    time_10 = timings[10]["per_window_ms"]
    time_50 = timings[50]["per_window_ms"]

    # Allow up to 2x increase (account for system noise)
    assert time_50 < time_10 * 2.0, \
        f"Query time per window increased too much: {time_10:.2f}ms → {time_50:.2f}ms"

    # Verify 50-window batch completes in reasonable time
    assert timings[50]["total_ms"] < 150.0, \
        f"50-window batch took {timings[50]['total_ms']:.1f}ms (target: <150ms)"


@pytest.mark.performance
def test_synchronous_read_performance():
    """
    Additional test: Pure synchronous /proc reads (no async overhead).

    Baseline performance measurement for comparison with async approach.
    """
    processes = []
    env = os.environ.copy()
    env.update({
        "I3PM_APP_ID": "test-sync",
        "I3PM_APP_NAME": "test",
        "I3PM_SCOPE": "global",
    })

    try:
        # Create 50 processes
        for _ in range(50):
            proc = subprocess.Popen(
                ["sleep", "15"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            processes.append(proc)

        time.sleep(0.2)

        # Measure pure synchronous reads
        start = time.perf_counter()
        for proc in processes:
            env_vars = read_process_environ(proc.pid)
            assert "I3PM_APP_ID" in env_vars
        end = time.perf_counter()

        total_ms = (end - start) * 1000.0
        per_window = total_ms / len(processes)

        print(f"\nSynchronous Read Performance (50 windows):")
        print(f"  Total: {total_ms:.1f}ms, Per window: {per_window:.2f}ms\n")

        # Should complete quickly
        assert total_ms < 50.0, \
            f"Synchronous batch read {total_ms:.1f}ms too slow"

    finally:
        for proc in processes:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except ProcessLookupError:
                pass
