"""
Performance benchmark tests for environment variable queries (User Story 3).

Tests verify that /proc filesystem reads meet <10ms latency target.
"""

import pytest
import time
import subprocess
import os
from pathlib import Path
from typing import List

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from test_utils import read_process_environ


@pytest.mark.performance
def test_single_environ_read_performance():
    """
    T030: Performance benchmark - Single /proc/<pid>/environ read.

    Creates 100 test processes with known environments, measures read_process_environ()
    latency for each, calculates statistics (avg, p50, p95, p99, max).

    Success criteria:
    - Average latency < 1.0ms
    - p95 latency < 10.0ms
    - Total time for 100 queries < 100ms
    """
    # Create 100 test processes with environment variables
    processes: List[subprocess.Popen] = []
    test_env = os.environ.copy()
    test_env.update({
        "I3PM_APP_ID": "test-benchmark-12345",
        "I3PM_APP_NAME": "test-app",
        "I3PM_SCOPE": "global",
    })

    try:
        # Spawn test processes
        for i in range(100):
            proc = subprocess.Popen(
                ["sleep", "30"],
                env=test_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            processes.append(proc)

        # Warm up (let kernel cache settle)
        time.sleep(0.1)

        # Measure latencies
        latencies_ms = []
        start_total = time.perf_counter()

        for proc in processes:
            start = time.perf_counter()
            env_vars = read_process_environ(proc.pid)
            end = time.perf_counter()

            latency_ms = (end - start) * 1000.0
            latencies_ms.append(latency_ms)

            # Verify we actually read the environment
            assert "I3PM_APP_ID" in env_vars, f"Failed to read environment for PID {proc.pid}"

        end_total = time.perf_counter()
        total_time_ms = (end_total - start_total) * 1000.0

        # Calculate statistics
        sorted_latencies = sorted(latencies_ms)
        n = len(sorted_latencies)

        avg_ms = sum(latencies_ms) / n
        p50_ms = sorted_latencies[int(n * 0.50)]
        p95_ms = sorted_latencies[int(n * 0.95)]
        p99_ms = sorted_latencies[int(n * 0.99)]
        max_ms = max(latencies_ms)
        min_ms = min(latencies_ms)

        # Log results
        print(f"\n{'='*60}")
        print(f"Environment Query Performance Benchmark (100 samples)")
        print(f"{'='*60}")
        print(f"Average:   {avg_ms:.3f}ms")
        print(f"p50:       {p50_ms:.3f}ms")
        print(f"p95:       {p95_ms:.3f}ms")
        print(f"p99:       {p99_ms:.3f}ms")
        print(f"Min:       {min_ms:.3f}ms")
        print(f"Max:       {max_ms:.3f}ms")
        print(f"Total:     {total_time_ms:.1f}ms ({total_time_ms/n:.2f}ms per query)")
        print(f"{'='*60}\n")

        # Assert performance targets
        assert avg_ms < 1.0, \
            f"Average latency {avg_ms:.3f}ms exceeds 1.0ms target"

        assert p95_ms < 10.0, \
            f"p95 latency {p95_ms:.3f}ms exceeds 10.0ms target"

        assert total_time_ms < 100.0, \
            f"Total time {total_time_ms:.1f}ms exceeds 100ms target for 100 queries"

        # Status: PASS if all criteria met
        status = "PASS" if (avg_ms < 1.0 and p95_ms < 10.0 and total_time_ms < 100.0) else "FAIL"
        print(f"Benchmark Status: {status}")

        assert status == "PASS", "Performance benchmark failed"

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


@pytest.mark.performance
def test_environ_read_with_large_environment():
    """
    Additional performance test: Large environment variables.

    Tests performance with processes that have large environments (many variables).
    Some applications have 50+ environment variables.
    """
    # Create test process with large environment
    large_env = os.environ.copy()
    large_env.update({
        f"TEST_VAR_{i}": f"value_{i}" * 10  # Add 50 extra variables
        for i in range(50)
    })
    large_env.update({
        "I3PM_APP_ID": "test-large-env",
        "I3PM_APP_NAME": "test-app",
        "I3PM_SCOPE": "global",
    })

    proc = subprocess.Popen(
        ["sleep", "10"],
        env=large_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        # Measure latency
        latencies = []
        for _ in range(50):
            start = time.perf_counter()
            env_vars = read_process_environ(proc.pid)
            end = time.perf_counter()

            latency_ms = (end - start) * 1000.0
            latencies.append(latency_ms)

            assert "I3PM_APP_ID" in env_vars

        avg_ms = sum(latencies) / len(latencies)
        max_ms = max(latencies)

        print(f"\nLarge Environment Performance: avg={avg_ms:.3f}ms, max={max_ms:.3f}ms\n")

        # Should still be fast even with large environment
        assert avg_ms < 2.0, \
            f"Average latency {avg_ms:.3f}ms too slow for large environment"

    finally:
        proc.terminate()
        proc.wait(timeout=1)


@pytest.mark.performance
def test_environ_read_cold_cache():
    """
    Additional performance test: Cold cache performance.

    Tests performance when reading from processes for the first time
    (before kernel page cache is populated).
    """
    latencies_first = []
    latencies_second = []

    for _ in range(20):
        # Create new process
        proc = subprocess.Popen(
            ["sleep", "5"],
            env={
                "I3PM_APP_ID": "test-cold-cache",
                "I3PM_APP_NAME": "test",
                "I3PM_SCOPE": "global",
            },
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        try:
            # First read (cold cache)
            start = time.perf_counter()
            env1 = read_process_environ(proc.pid)
            end = time.perf_counter()
            latencies_first.append((end - start) * 1000.0)

            # Second read (warm cache)
            start = time.perf_counter()
            env2 = read_process_environ(proc.pid)
            end = time.perf_counter()
            latencies_second.append((end - start) * 1000.0)

            assert "I3PM_APP_ID" in env1
            assert "I3PM_APP_ID" in env2

        finally:
            proc.terminate()
            proc.wait(timeout=1)

    avg_cold = sum(latencies_first) / len(latencies_first)
    avg_warm = sum(latencies_second) / len(latencies_second)

    print(f"\nCache Performance: cold={avg_cold:.3f}ms, warm={avg_warm:.3f}ms\n")

    # Cold cache should still be reasonable
    assert avg_cold < 5.0, \
        f"Cold cache average {avg_cold:.3f}ms too slow"

    # Warm cache should be faster
    assert avg_warm < avg_cold, \
        "Warm cache should be faster than cold cache"
