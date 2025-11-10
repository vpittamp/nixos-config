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
   * @returns Cleanup report with detailed results
   */
  async cleanup(): Promise<CleanupReport> {
    const startTime = new Date().toISOString();
    const startMs = Date.now();
    const errors: CleanupError[] = [];

    // Cleanup processes and windows concurrently
    let processEntries, windowEntries;

    try {
      [processEntries, windowEntries] = await Promise.all([
        this.processTracker.terminateAll(),
        this.windowTracker.closeAll(),
      ]);
    } catch (error) {
      errors.push({
        component: "CleanupManager",
        message: error instanceof Error ? error.message : String(error),
        context: { error_type: error instanceof Error ? error.name : typeof error },
      });

      // Fallback to sequential cleanup
      processEntries = await this.processTracker.terminateAll().catch(() => []);
      windowEntries = await this.windowTracker.closeAll().catch(() => []);
    }

    const endTime = new Date().toISOString();
    const totalDurationMs = Date.now() - startMs;

    const report: CleanupReport = {
      started_at: startTime,
      completed_at: endTime,
      total_duration_ms: totalDurationMs,
      processes_terminated: processEntries,
      windows_closed: windowEntries,
      errors,
      summary: "", // Will be filled below
    };

    report.summary = createCleanupSummary(report);
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
