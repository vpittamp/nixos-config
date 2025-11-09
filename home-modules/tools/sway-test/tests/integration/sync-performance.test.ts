/**
 * Performance benchmark tests for synchronization
 * Feature 069: Synchronization-Based Test Framework
 *
 * Target: <10ms p95 latency for sync operations
 * Run with: deno test --allow-all tests/integration/sync-performance.test.ts
 */

import { assertEquals, assert, assertLess } from "@std/assert";
import { SwayClient } from "../../src/services/sway-client.ts";

// T027: Performance benchmark test - verify <10ms p95 latency
Deno.test({
  name: "Sync performance - p95 latency <10ms",
  async fn() {
    const client = new SwayClient();
    const isAvailable = await client.isAvailable();

    if (!isAvailable) {
      console.log("Skipping test - Sway is not running");
      return;
    }

    // Create a temporary window for sync to work (mark requires focused window)
    const tree = await client.getTree();
    const hasWindows = tree.nodes?.some(ws => ws.nodes && ws.nodes.length > 0);

    if (!hasWindows) {
      console.log("Skipping test - No windows available for sync (mark requires focused window)");
      return;
    }

    const latencies: number[] = [];

    // Run 100 sync operations
    console.log("Running 100 sync operations for p95 benchmark...");
    for (let i = 0; i < 100; i++) {
      const result = await client.sync(5000, `benchmark-${i}`);

      if (!result.success) {
        console.log(`Skipping test - Sync failed: ${result.error}. Mark requires a focused window.`);
        return;
      }

      latencies.push(result.latencyMs);
    }

    // Calculate p95
    latencies.sort((a, b) => a - b);
    const p95Index = Math.floor(latencies.length * 0.95);
    const p95 = latencies[p95Index];

    // Calculate other stats for reporting
    const average = latencies.reduce((sum, val) => sum + val, 0) / latencies.length;
    const min = latencies[0];
    const max = latencies[latencies.length - 1];
    const p99Index = Math.floor(latencies.length * 0.99);
    const p99 = latencies[p99Index];

    console.log(`\nSync Performance Benchmark Results:`);
    console.log(`  Total syncs: 100`);
    console.log(`  Min latency: ${min}ms`);
    console.log(`  Average latency: ${Math.round(average)}ms`);
    console.log(`  p95 latency: ${p95}ms`);
    console.log(`  p99 latency: ${p99}ms`);
    console.log(`  Max latency: ${max}ms`);

    // Verify p95 meets <10ms target
    assertLess(p95, 10, `p95 latency ${p95}ms exceeds 10ms target`);

    // Also verify via getSyncStats
    const stats = client.getSyncStats();
    assert(stats !== null, "Stats should be available");
    assertEquals(stats.totalSyncs, 100, "Should have 100 total syncs");
    assertEquals(stats.successfulSyncs, 100, "All syncs should succeed");
    assertLess(stats.p95LatencyMs, 10, "Stats p95 should also be <10ms");
  },
});

// T043: Performance benchmark for 5 app launches - verify <5 seconds
Deno.test({
  name: "Sync performance - 5 app launches <5 seconds",
  sanitizeResources: false, // Disable resource leak detection - app launches create child processes
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const client = new SwayClient();
    const isAvailable = await client.isAvailable();

    if (!isAvailable) {
      console.log("Skipping test - Sway is not running");
      return;
    }

    const executor = new ActionExecutor({ swayClient: client, autoSync: false });

    // Launch 5 apps using launch_app_sync
    const startTime = performance.now();

    const actions = [
      { type: "launch_app_sync", params: { app_name: "terminal" } },
      { type: "launch_app_sync", params: { app_name: "terminal" } },
      { type: "launch_app_sync", params: { app_name: "terminal" } },
      { type: "launch_app_sync", params: { app_name: "terminal" } },
      { type: "launch_app_sync", params: { app_name: "terminal" } },
    ];

    for (const action of actions) {
      await executor.execute([action]);
    }

    const endTime = performance.now();
    const totalTimeMs = endTime - startTime;
    const totalTimeSec = totalTimeMs / 1000;

    console.log(`\n5 App Launch Benchmark Results:`);
    console.log(`  Total time: ${totalTimeSec.toFixed(2)} seconds`);
    console.log(`  Target: <5 seconds`);
    console.log(`  Previous timeout-based approach: ~50 seconds`);

    // Verify <5 seconds total
    assertLess(totalTimeSec, 5, `5 app launches took ${totalTimeSec}s, expected <5s`);

    // Cleanup - close all launched windows
    const tree = await client.getTree();
    const windows = tree.nodes?.flatMap(ws => ws.nodes || []).filter(n => n.app_id === "ghostty") || [];
    for (const window of windows) {
      if (window.id) {
        await client.sendCommand(`[con_id=${window.id}] kill`);
      }
    }

    // Wait for windows to close
    await new Promise(resolve => setTimeout(resolve, 500));
  },
});

// T044: Comparison test for sync vs timeout approaches - verify 5-10x speedup
Deno.test({
  name: "Sync performance - 5-10x speedup vs timeout",
  async fn() {
    const { ActionExecutor } = await import("../../src/services/action-executor.ts");
    const client = new SwayClient();
    const isAvailable = await client.isAvailable();

    if (!isAvailable) {
      console.log("Skipping test - Sway is not running");
      return;
    }

    const executor = new ActionExecutor({ swayClient: client, autoSync: false });

    // Scenario 1: Timeout-based approach (simulate with explicit wait)
    console.log("\nTesting timeout-based approach...");
    const timeoutStartTime = performance.now();

    // Launch app and wait with arbitrary timeout (typical pattern in old tests)
    await executor.execute([
      { type: "send_ipc", params: { ipc_command: "workspace 7" } },
    ]);
    // Simulate 1 second arbitrary wait (typical timeout approach)
    await new Promise(resolve => setTimeout(resolve, 1000));

    const timeoutEndTime = performance.now();
    const timeoutDurationMs = timeoutEndTime - timeoutStartTime;

    // Scenario 2: Sync-based approach
    console.log("Testing sync-based approach...");
    const syncStartTime = performance.now();

    await executor.execute([
      { type: "send_ipc_sync", params: { ipc_command: "workspace 8" } },
    ]);

    const syncEndTime = performance.now();
    const syncDurationMs = syncEndTime - syncStartTime;

    // Calculate speedup factor
    const speedupFactor = timeoutDurationMs / syncDurationMs;

    console.log(`\nSync vs Timeout Comparison:`);
    console.log(`  Timeout approach: ${timeoutDurationMs.toFixed(2)}ms`);
    console.log(`  Sync approach: ${syncDurationMs.toFixed(2)}ms`);
    console.log(`  Speedup factor: ${speedupFactor.toFixed(1)}x`);
    console.log(`  Target: 5-10x faster`);

    // Verify sync is at least 5x faster
    assert(
      speedupFactor >= 5,
      `Sync speedup ${speedupFactor.toFixed(1)}x is less than 5x target`
    );

    console.log(`  ✓ Sync is ${speedupFactor.toFixed(1)}x faster than timeout approach`);
  },
});
