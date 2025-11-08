/**
 * Performance Benchmark for Sway Test Framework (T087)
 *
 * Measures test initialization and execution overhead to ensure <100ms target
 */

import { SwayClient } from "../src/services/sway-client.ts";
import { StateComparator } from "../src/services/state-comparator.ts";
import { ActionExecutor } from "../src/services/action-executor.ts";
import type { StateSnapshot } from "../models/state-snapshot.ts";

// Performance benchmarks
const benchmarks = {
  swayClient: {
    getTree: [] as number[],
    sendCommand: [] as number[],
  },
  stateComparator: {
    compareIdentical: [] as number[],
    compareDifferent: [] as number[],
  },
  actionExecutor: {
    initializeation: [] as number[],
  },
};

/**
 * Benchmark SwayClient operations
 */
async function benchmarkSwayClient() {
  const client = new SwayClient();

  // Skip if Sway is not available
  const available = await client.isAvailable();
  if (!available) {
    console.log("⚠ Sway not available, skipping SwayClient benchmarks");
    return;
  }

  console.log("\n📊 Benchmarking SwayClient...");

  // Benchmark getTree() - 10 iterations
  for (let i = 0; i < 10; i++) {
    const start = performance.now();
    await client.getTree();
    const duration = performance.now() - start;
    benchmarks.swayClient.getTree.push(duration);
  }

  // Benchmark sendCommand() - 10 iterations
  for (let i = 0; i < 10; i++) {
    const start = performance.now();
    await client.sendCommand("nop");
    const duration = performance.now() - start;
    benchmarks.swayClient.sendCommand.push(duration);
  }
}

/**
 * Benchmark StateComparator operations
 */
function benchmarkStateComparator() {
  const comparator = new StateComparator();

  console.log("\n📊 Benchmarking StateComparator...");

  // Create test states
  const state1: StateSnapshot = {
    focusedWorkspace: 1,
    focusedOutput: "HEADLESS-1",
    workspaces: [
      { num: 1, name: "1", focused: true, visible: true, urgent: false, output: "HEADLESS-1" },
      { num: 2, name: "2", focused: false, visible: false, urgent: false, output: "HEADLESS-1" },
    ],
    windows: [],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "1", focused: true },
    ],
    tree: { type: "root", name: "root", nodes: [] },
  };

  const state2 = JSON.parse(JSON.stringify(state1)); // Deep copy
  const state3 = JSON.parse(JSON.stringify(state1));
  state3.focusedWorkspace = 2; // Make different

  // Benchmark identical state comparison - 100 iterations
  for (let i = 0; i < 100; i++) {
    const start = performance.now();
    comparator.compare(state1, state2, "exact");
    const duration = performance.now() - start;
    benchmarks.stateComparator.compareIdentical.push(duration);
  }

  // Benchmark different state comparison - 100 iterations
  for (let i = 0; i < 100; i++) {
    const start = performance.now();
    comparator.compare(state1, state3, "exact");
    const duration = performance.now() - start;
    benchmarks.stateComparator.compareDifferent.push(duration);
  }
}

/**
 * Benchmark ActionExecutor initialization
 */
function benchmarkActionExecutor() {
  console.log("\n📊 Benchmarking ActionExecutor...");

  // Benchmark initialization - 100 iterations
  for (let i = 0; i < 100; i++) {
    const start = performance.now();
    new ActionExecutor();
    const duration = performance.now() - start;
    benchmarks.actionExecutor.initializeation.push(duration);
  }
}

/**
 * Calculate statistics for benchmark results
 */
function calculateStats(values: number[]): {
  min: number;
  max: number;
  avg: number;
  median: number;
  p95: number;
  p99: number;
} {
  if (values.length === 0) {
    return { min: 0, max: 0, avg: 0, median: 0, p95: 0, p99: 0 };
  }

  const sorted = [...values].sort((a, b) => a - b);
  const sum = values.reduce((a, b) => a + b, 0);

  return {
    min: sorted[0],
    max: sorted[sorted.length - 1],
    avg: sum / values.length,
    median: sorted[Math.floor(sorted.length / 2)],
    p95: sorted[Math.floor(sorted.length * 0.95)],
    p99: sorted[Math.floor(sorted.length * 0.99)],
  };
}

/**
 * Format duration with appropriate unit
 */
function formatDuration(ms: number): string {
  if (ms < 1) {
    return `${(ms * 1000).toFixed(2)}μs`;
  } else if (ms < 1000) {
    return `${ms.toFixed(2)}ms`;
  } else {
    return `${(ms / 1000).toFixed(2)}s`;
  }
}

/**
 * Report benchmark results
 */
function reportResults() {
  console.log("\n" + "=".repeat(80));
  console.log("Performance Benchmark Results (T087)");
  console.log("=".repeat(80));
  console.log("Target: <100ms test initialization overhead\n");

  // SwayClient results
  if (benchmarks.swayClient.getTree.length > 0) {
    console.log("SwayClient.getTree():");
    const stats = calculateStats(benchmarks.swayClient.getTree);
    console.log(`  Min: ${formatDuration(stats.min)}`);
    console.log(`  Avg: ${formatDuration(stats.avg)}`);
    console.log(`  Max: ${formatDuration(stats.max)}`);
    console.log(`  P95: ${formatDuration(stats.p95)}`);
    console.log(`  P99: ${formatDuration(stats.p99)}`);
    console.log(`  Iterations: ${benchmarks.swayClient.getTree.length}\n`);
  }

  if (benchmarks.swayClient.sendCommand.length > 0) {
    console.log("SwayClient.sendCommand():");
    const stats = calculateStats(benchmarks.swayClient.sendCommand);
    console.log(`  Min: ${formatDuration(stats.min)}`);
    console.log(`  Avg: ${formatDuration(stats.avg)}`);
    console.log(`  Max: ${formatDuration(stats.max)}`);
    console.log(`  P95: ${formatDuration(stats.p95)}`);
    console.log(`  P99: ${formatDuration(stats.p99)}`);
    console.log(`  Iterations: ${benchmarks.swayClient.sendCommand.length}\n`);
  }

  // StateComparator results
  console.log("StateComparator.compare() [Identical states]:");
  const statsIdentical = calculateStats(benchmarks.stateComparator.compareIdentical);
  console.log(`  Min: ${formatDuration(statsIdentical.min)}`);
  console.log(`  Avg: ${formatDuration(statsIdentical.avg)}`);
  console.log(`  Max: ${formatDuration(statsIdentical.max)}`);
  console.log(`  P95: ${formatDuration(statsIdentical.p95)}`);
  console.log(`  P99: ${formatDuration(statsIdentical.p99)}`);
  console.log(`  Iterations: ${benchmarks.stateComparator.compareIdentical.length}\n`);

  console.log("StateComparator.compare() [Different states]:");
  const statsDifferent = calculateStats(benchmarks.stateComparator.compareDifferent);
  console.log(`  Min: ${formatDuration(statsDifferent.min)}`);
  console.log(`  Avg: ${formatDuration(statsDifferent.avg)}`);
  console.log(`  Max: ${formatDuration(statsDifferent.max)}`);
  console.log(`  P95: ${formatDuration(statsDifferent.p95)}`);
  console.log(`  P99: ${formatDuration(statsDifferent.p99)}`);
  console.log(`  Iterations: ${benchmarks.stateComparator.compareDifferent.length}\n`);

  // ActionExecutor results
  console.log("ActionExecutor initialization:");
  const statsExecutor = calculateStats(benchmarks.actionExecutor.initializeation);
  console.log(`  Min: ${formatDuration(statsExecutor.min)}`);
  console.log(`  Avg: ${formatDuration(statsExecutor.avg)}`);
  console.log(`  Max: ${formatDuration(statsExecutor.max)}`);
  console.log(`  P95: ${formatDuration(statsExecutor.p95)}`);
  console.log(`  P99: ${formatDuration(statsExecutor.p99)}`);
  console.log(`  Iterations: ${benchmarks.actionExecutor.initializeation.length}\n`);

  // Overall assessment
  console.log("=".repeat(80));
  const totalInitTime = statsExecutor.avg;
  const passesTarget = totalInitTime < 100;

  console.log(`Overall Test Initialization: ${formatDuration(totalInitTime)}`);
  console.log(`Target (<100ms): ${passesTarget ? "✓ PASS" : "✗ FAIL"}`);
  console.log("=".repeat(80));

  if (!passesTarget) {
    console.error("\n⚠ Performance target not met!");
    console.error("Consider optimizing initialization path or lazy loading.");
    Deno.exit(1);
  } else {
    console.log("\n✓ All performance targets met!");
  }
}

/**
 * Main benchmark execution
 */
async function main() {
  console.log("Starting Performance Benchmarks...");

  await benchmarkSwayClient();
  benchmarkStateComparator();
  benchmarkActionExecutor();

  reportResults();
}

if (import.meta.main) {
  main();
}
