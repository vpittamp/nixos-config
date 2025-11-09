/**
 * Sway Test Framework - Public API
 *
 * This module exports the public API for the Sway test framework.
 */

// Re-export models
export type { TestCase, ActionSequence, ExpectedState } from "./src/models/test-case.ts";
export type { StateSnapshot } from "./src/models/state-snapshot.ts";
export type { TestResult, TestStatus, StateDiff, DiffEntry } from "./src/models/test-result.ts";

// Re-export sync models (Feature 069)
export type { SyncMarker, SyncResult, SyncConfig, SyncStats } from "./src/models/sync-marker.ts";
export { generateSyncMarker, validateSyncMarker, validateSyncConfig, DEFAULT_SYNC_CONFIG } from "./src/models/sync-marker.ts";

// Re-export services
export { SwayClient } from "./src/services/sway-client.ts";
export { TreeMonitorClient } from "./src/services/tree-monitor-client.ts";
export { StateComparator } from "./src/services/state-comparator.ts";
export type { ComparisonMode, PartialMatch } from "./src/services/state-comparator.ts";

// Re-export test helpers (User Story 3 - Feature 069)
export { focusAfter, focusedWorkspaceAfter, windowCountAfter } from "./src/services/test-helpers.ts";
export type { FocusedNode } from "./src/services/test-helpers.ts";

// Re-export UI components
export { DiffRenderer } from "./src/ui/diff-renderer.ts";
export { Reporter } from "./src/ui/reporter.ts";

// Re-export commands
export { runCommand } from "./src/commands/run.ts";
export type { RunOptions } from "./src/commands/run.ts";
export { validateCommand } from "./src/commands/validate.ts";

/**
 * Register a Sway test (T014)
 *
 * Wrapper around Deno.test() that provides framework-specific setup/teardown.
 * Used for framework self-tests.
 *
 * @param name Test name
 * @param fn Test function
 */
export function registerSwayTest(name: string, fn: () => Promise<void> | void) {
  Deno.test({
    name: `[Sway Test] ${name}`,
    async fn() {
      // Framework-specific setup
      const startTime = performance.now();

      try {
        await fn();
      } finally {
        // Framework-specific teardown
        const duration = performance.now() - startTime;
        if (duration > 5000) {
          console.warn(`Test "${name}" took ${Math.round(duration)}ms (>5s threshold)`);
        }
      }
    },
  });
}
