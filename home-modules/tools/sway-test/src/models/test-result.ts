/**
 * Test Result Model
 *
 * Defines the structure for test execution results, including status, timing, and diagnostics.
 */

import type { StateSnapshot } from "./state-snapshot.ts";

/**
 * Test execution status
 */
export enum TestStatus {
  Pending = "pending",
  Running = "running",
  Passed = "passed",
  Failed = "failed",
  Skipped = "skipped",
  Timeout = "timeout",
  Error = "error",
}

/**
 * State diff entry showing what changed
 */
export interface DiffEntry {
  path: string; // JSONPath to changed field
  type: "added" | "removed" | "modified";
  expected?: unknown;
  actual?: unknown;
  oldValue?: unknown; // For modified
  newValue?: unknown; // For modified
}

/**
 * Complete state diff result
 */
export interface StateDiff {
  matches: boolean;
  differences: DiffEntry[];
  summary: {
    added: number;
    removed: number;
    modified: number;
  };

  /**
   * Comparison mode used (Feature 068)
   */
  mode?: "exact" | "partial" | "assertions" | "empty";

  /**
   * Fields that were compared (partial mode only, Feature 068)
   */
  comparedFields?: string[];

  /**
   * Fields that were ignored in comparison (partial mode only, Feature 068)
   */
  ignoredFields?: string[];
}

/**
 * Tree-monitor event (from daemon integration)
 */
export interface TreeMonitorEvent {
  event_id: number;
  timestamp_ms: number;
  event_type: string; // window::new, window::focus, workspace::focus, etc.
  sway_change: string; // new, focus, close, move, etc.
  container_id: number | null;

  // Field-level diff computation
  diff: {
    total_changes: number;
    significance_level: "minimal" | "moderate" | "significant" | "critical";
    significance_score: number; // 0.0-1.0
    computation_time_ms: number;
    field_changes?: Array<{
      path: string;
      old_value: unknown;
      new_value: unknown;
    }>;
  };

  // User action correlation
  correlations: Array<{
    type: string;
    keybinding?: string;
    command?: string;
    confidence?: number;
  }>;

  // Raw event data (optional)
  raw_event?: unknown;
}

/**
 * Diagnostic context captured on test failure
 */
export interface DiagnosticContext {
  // Logs
  stdout?: string;
  stderr?: string;
  swayLogs?: string[];

  // State snapshots
  initialState?: StateSnapshot;
  failureState?: StateSnapshot;

  // Events
  treeMonitorEvents?: TreeMonitorEvent[];

  // Environment
  env?: Record<string, string>;
  swayVersion?: string;

  // Timing
  actionTimings?: Array<{
    action: string;
    duration: number; // ms
    timestamp: string;
  }>;
}

/**
 * Complete test execution result
 */
export interface TestResult {
  // Test identification
  testName: string;
  suiteName?: string;

  // Status
  status: TestStatus;

  // Timing
  startedAt: string; // ISO timestamp
  finishedAt?: string; // ISO timestamp
  duration: number; // ms

  // Results
  passed: boolean;
  message?: string; // Human-readable message

  // State comparison
  expectedState?: unknown;
  actualState?: StateSnapshot;
  diff?: StateDiff;

  // Diagnostics
  diagnostics?: DiagnosticContext;

  // Framework overhead
  initializationTime?: number; // ms
  cleanupTime?: number; // ms
}

/**
 * Test suite execution summary
 */
export interface TestSuiteSummary {
  suiteName: string;
  totalTests: number;
  passed: number;
  failed: number;
  skipped: number;
  timeout: number;
  error: number;

  duration: number; // Total ms

  results: TestResult[];

  // Performance stats
  averageTestDuration?: number; // ms
  overhead?: number; // Total framework overhead ms
}
