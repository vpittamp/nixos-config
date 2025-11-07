"""Performance benchmarks for tree diff computation

Validates:
- <10ms diff computation for 100-window trees (p95)
- <2ms for 50-window trees
- <20ms for 200-window trees (stress test)

Usage:
    pytest tests/sway-tree-monitor/performance/benchmark_diff.py -v
    python -m tests.sway-tree-monitor.performance.benchmark_diff (standalone)
"""

import time
from typing import List, Tuple
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from tests.sway_tree_monitor.fixtures.sample_trees import (
    TREE_50,
    TREE_100,
    TREE_200,
    modify_tree_add_window,
    modify_tree_move_window,
    modify_tree_focus_change,
)

# Import implementation
from home_modules.tools.sway_tree_monitor.models import TreeSnapshot
from home_modules.tools.sway_tree_monitor.diff.hasher import compute_tree_hash
from home_modules.tools.sway_tree_monitor.diff.cache import HashCache
from home_modules.tools.sway_tree_monitor.diff.differ import TreeDiffer


def create_snapshot(tree_data: dict, snapshot_id: int) -> TreeSnapshot:
    """Create TreeSnapshot from test fixture"""
    root_hash = compute_tree_hash(tree_data)
    return TreeSnapshot(
        snapshot_id=snapshot_id,
        timestamp_ms=int(time.time() * 1000),
        tree_data=tree_data,
        enriched_data={},
        root_hash=root_hash,
        event_source="test::benchmark"
    )


def run_benchmark(
    name: str,
    before_tree: dict,
    after_tree: dict,
    iterations: int = 100
) -> Tuple[float, float, float, float]:
    """Run benchmark and return timing statistics

    Returns:
        (min_ms, p50_ms, p95_ms, max_ms)
    """
    differ = TreeDiffer()
    timings: List[float] = []

    for i in range(iterations):
        before = create_snapshot(before_tree, snapshot_id=i * 2)
        after = create_snapshot(after_tree, snapshot_id=i * 2 + 1)

        start = time.perf_counter()
        diff = differ.compute_diff(before, after)
        elapsed_ms = (time.perf_counter() - start) * 1000

        timings.append(elapsed_ms)

    # Calculate statistics
    timings_sorted = sorted(timings)
    min_ms = timings_sorted[0]
    max_ms = timings_sorted[-1]
    p50_idx = len(timings_sorted) // 2
    p95_idx = int(len(timings_sorted) * 0.95)
    p50_ms = timings_sorted[p50_idx]
    p95_ms = timings_sorted[p95_idx]

    return (min_ms, p50_ms, p95_ms, max_ms)


def benchmark_50_windows():
    """Benchmark: 50-window tree, add window"""
    print("\n=== 50 Windows: Add Window ===")
    before = TREE_50
    after = modify_tree_add_window(TREE_50)

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "50w_add_window", before, after, iterations=100
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    # Target: <2ms p95 for 50 windows
    assert p95_ms < 2.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 2ms target for 50 windows"
    print(f"  ✓ PASS: P95 < 2ms")


def benchmark_100_windows_add():
    """Benchmark: 100-window tree, add window"""
    print("\n=== 100 Windows: Add Window ===")
    before = TREE_100
    after = modify_tree_add_window(TREE_100)

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "100w_add_window", before, after, iterations=100
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    # Target: <10ms p95 for 100 windows (PRIMARY TARGET)
    assert p95_ms < 10.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 10ms target for 100 windows"
    print(f"  ✓ PASS: P95 < 10ms (PRIMARY TARGET MET)")


def benchmark_100_windows_move():
    """Benchmark: 100-window tree, move window (geometry change)"""
    print("\n=== 100 Windows: Move Window ===")
    before = TREE_100
    after = modify_tree_move_window(TREE_100)

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "100w_move_window", before, after, iterations=100
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    assert p95_ms < 10.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 10ms target"
    print(f"  ✓ PASS: P95 < 10ms")


def benchmark_100_windows_focus():
    """Benchmark: 100-window tree, focus change"""
    print("\n=== 100 Windows: Focus Change ===")
    before = TREE_100
    after = modify_tree_focus_change(TREE_100)

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "100w_focus_change", before, after, iterations=100
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    assert p95_ms < 10.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 10ms target"
    print(f"  ✓ PASS: P95 < 10ms")


def benchmark_200_windows():
    """Benchmark: 200-window tree (stress test)"""
    print("\n=== 200 Windows: Add Window (Stress Test) ===")
    before = TREE_200
    after = modify_tree_add_window(TREE_200)

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "200w_add_window", before, after, iterations=50  # Fewer iterations for stress test
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    # Target: <20ms p95 for 200 windows (stress test)
    assert p95_ms < 20.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 20ms target for 200 windows"
    print(f"  ✓ PASS: P95 < 20ms (stress test)")


def benchmark_no_change():
    """Benchmark: Identical trees (fast path - should be <1ms)"""
    print("\n=== No Change (Fast Path) ===")
    before = TREE_100
    after = TREE_100  # Same tree

    min_ms, p50_ms, p95_ms, max_ms = run_benchmark(
        "no_change", before, after, iterations=100
    )

    print(f"  Min:  {min_ms:.3f}ms")
    print(f"  P50:  {p50_ms:.3f}ms")
    print(f"  P95:  {p95_ms:.3f}ms")
    print(f"  Max:  {max_ms:.3f}ms")

    # Fast path should be <1ms (just hash comparison)
    assert p95_ms < 1.0, f"FAIL: P95 {p95_ms:.3f}ms exceeds 1ms (fast path broken)"
    print(f"  ✓ PASS: P95 < 1ms (fast path working)")


def main():
    """Run all benchmarks"""
    print("=" * 60)
    print("Sway Tree Diff Monitor - Performance Benchmarks")
    print("=" * 60)
    print("\nTarget: <10ms diff computation (p95) for 100-window trees")
    print("Iterations: 100 per benchmark (50 for stress test)")

    try:
        benchmark_no_change()
        benchmark_50_windows()
        benchmark_100_windows_add()
        benchmark_100_windows_move()
        benchmark_100_windows_focus()
        benchmark_200_windows()

        print("\n" + "=" * 60)
        print("✓ ALL BENCHMARKS PASSED")
        print("=" * 60)
        return 0

    except AssertionError as e:
        print(f"\n✗ BENCHMARK FAILED: {e}")
        return 1
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
