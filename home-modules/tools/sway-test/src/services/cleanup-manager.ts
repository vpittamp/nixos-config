/**
 * Cleanup Manager Service for Sway Test Framework
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Task: T020
 *
 * Orchestrates ProcessTracker and WindowTracker for comprehensive cleanup.
 */

import { ProcessTracker } from "./process-tracker.ts";
import { WindowTracker } from "./window-tracker.ts";
import { CleanupReport, createCleanupSummary, CleanupError } from "../models/cleanup-report.ts";

/**
 * Cleanup Manager - orchestrates process and window cleanup
 */
export class CleanupManager {
  private processTracker: ProcessTracker;
  private windowTracker: WindowTracker;

  constructor() {
    this.processTracker = new ProcessTracker();
    this.windowTracker = new WindowTracker();
  }

  /**
   * Register a process for cleanup tracking
   */
  registerProcess(pid: number): void {
    this.processTracker.registerProcess(pid);
  }

  /**
   * Register a window marker for cleanup tracking
   */
  registerWindow(marker: string): void {
    this.windowTracker.registerWindow(marker);
  }

  /**
   * Perform cleanup of all tracked resources
   *
   * Performance Target: <2s for 10 resources (processes + windows)
   *
   * @returns Cleanup report with detailed results
   */
  async cleanup(): Promise<CleanupReport> {
    const startTime = new Date().toISOString();
    const startMs = performance.now();
    const errors: CleanupError[] = [];

    // Track resource counts before cleanup
    const initialState = this.getState();
    const totalResources = initialState.processes + initialState.windows;

    // Cleanup processes and windows concurrently
    let processEntries, windowEntries;
    let processTime = 0;
    let windowTime = 0;

    try {
      const processStart = performance.now();
      const windowStart = performance.now();

      [processEntries, windowEntries] = await Promise.all([
        this.processTracker.terminateAll(),
        this.windowTracker.closeAll(),
      ]);

      processTime = performance.now() - processStart;
      windowTime = performance.now() - windowStart;
    } catch (error) {
      errors.push({
        component: "CleanupManager",
        message: error instanceof Error ? error.message : String(error),
        context: { error_type: error instanceof Error ? error.name : typeof error },
      });

      // Fallback to sequential cleanup with timing
      const fallbackProcessStart = performance.now();
      processEntries = await this.processTracker.terminateAll().catch(() => []);
      processTime = performance.now() - fallbackProcessStart;

      const fallbackWindowStart = performance.now();
      windowEntries = await this.windowTracker.closeAll().catch(() => []);
      windowTime = performance.now() - fallbackWindowStart;
    }

    const endTime = new Date().toISOString();
    const totalDurationMs = performance.now() - startMs;

    const report: CleanupReport = {
      started_at: startTime,
      completed_at: endTime,
      total_duration_ms: Math.round(totalDurationMs),
      processes_terminated: processEntries,
      windows_closed: windowEntries,
      errors,
      summary: "", // Will be filled below
    };

    report.summary = createCleanupSummary(report);

    // Log benchmark if enabled
    if (Deno.env.get("SWAY_TEST_BENCHMARK") === "1") {
      console.error(`[BENCHMARK] Cleanup operation breakdown:`);
      console.error(`  - Processes terminated: ${processEntries.length} (${processTime.toFixed(2)}ms)`);
      console.error(`  - Windows closed: ${windowEntries.length} (${windowTime.toFixed(2)}ms)`);
      console.error(`  - Errors encountered: ${errors.length}`);
      console.error(`  - TOTAL: ${totalDurationMs.toFixed(2)}ms (target: <2000ms for 10 resources)`);

      // Performance warning for heavy cleanups
      if (totalResources >= 10 && totalDurationMs > 2000) {
        console.error(`  ⚠️  WARNING: Cleanup time ${totalDurationMs.toFixed(2)}ms exceeds 2000ms target for ${totalResources} resources`);
      }

      // Calculate per-resource average
      if (totalResources > 0) {
        const avgPerResource = totalDurationMs / totalResources;
        console.error(`  - Average per resource: ${avgPerResource.toFixed(2)}ms`);
      }
    }

    return report;
  }

  /**
   * Get current state (counts of tracked resources)
   */
  getState(): { processes: number; windows: number } {
    return {
      processes: this.processTracker.getCount(),
      windows: this.windowTracker.getCount(),
    };
  }

  /**
   * Clear all tracked resources without cleanup
   */
  clear(): void {
    this.processTracker.clear();
    this.windowTracker.clear();
  }
}

// Global singleton instance for test framework
let globalCleanupManager: CleanupManager | null = null;

/**
 * Get the global cleanup manager instance
 */
export function getCleanupManager(): CleanupManager {
  if (!globalCleanupManager) {
    globalCleanupManager = new CleanupManager();
  }
  return globalCleanupManager;
}

/**
 * Reset the global cleanup manager (useful for testing)
 */
export function resetCleanupManager(): void {
  globalCleanupManager = null;
}
