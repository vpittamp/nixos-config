/**
 * Cleanup Report Model for Sway Test Framework
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Tasks: T016, T017
 *
 * Provides structured reporting for cleanup operations tracking processes
 * and windows that were cleaned up during test execution.
 */

import { z } from "zod";

/**
 * Process cleanup entry - tracks a single process termination
 */
export interface ProcessCleanupEntry {
  /** Process ID that was terminated */
  pid: number;

  /** Command name of the process */
  command?: string;

  /** Termination method used (SIGTERM, SIGKILL, etc.) */
  method: "SIGTERM" | "SIGKILL";

  /** Whether termination was successful */
  success: boolean;

  /** Error message if termination failed */
  error?: string;

  /** Time taken to terminate in milliseconds */
  duration_ms?: number;
}

/**
 * Window cleanup entry - tracks a single window closure
 */
export interface WindowCleanupEntry {
  /** Window marker/identifier */
  marker: string;

  /** Window ID (Sway con_id) */
  window_id?: number;

  /** Whether window was successfully closed */
  success: boolean;

  /** Error message if closure failed */
  error?: string;

  /** Time taken to close window in milliseconds */
  duration_ms?: number;
}

/**
 * Cleanup error entry - tracks errors encountered during cleanup
 */
export interface CleanupError {
  /** Component that encountered the error */
  component: "ProcessTracker" | "WindowTracker" | "CleanupManager";

  /** Error message */
  message: string;

  /** Optional error context */
  context?: Record<string, unknown>;
}

/**
 * Cleanup report - comprehensive summary of cleanup operation
 */
export interface CleanupReport {
  /** When the cleanup started */
  started_at: string;

  /** When the cleanup completed */
  completed_at: string;

  /** Total duration in milliseconds */
  total_duration_ms: number;

  /** List of processes that were terminated */
  processes_terminated: ProcessCleanupEntry[];

  /** List of windows that were closed */
  windows_closed: WindowCleanupEntry[];

  /** List of errors encountered during cleanup */
  errors: CleanupError[];

  /** Human-readable summary */
  summary: string;
}

// Zod Schemas for validation

export const ProcessCleanupEntrySchema = z.object({
  pid: z.number().int().positive(),
  command: z.string().optional(),
  method: z.enum(["SIGTERM", "SIGKILL"]),
  success: z.boolean(),
  error: z.string().optional(),
  duration_ms: z.number().nonnegative().optional(),
});

export const WindowCleanupEntrySchema = z.object({
  marker: z.string().min(1),
  window_id: z.number().int().positive().optional(),
  success: z.boolean(),
  error: z.string().optional(),
  duration_ms: z.number().nonnegative().optional(),
});

export const CleanupErrorSchema = z.object({
  component: z.enum(["ProcessTracker", "WindowTracker", "CleanupManager"]),
  message: z.string().min(1),
  context: z.record(z.unknown()).optional(),
});

export const CleanupReportSchema = z.object({
  started_at: z.string().datetime(),
  completed_at: z.string().datetime(),
  total_duration_ms: z.number().nonnegative(),
  processes_terminated: z.array(ProcessCleanupEntrySchema),
  windows_closed: z.array(WindowCleanupEntrySchema),
  errors: z.array(CleanupErrorSchema),
  summary: z.string().min(1),
});

/**
 * Type guard to check if object is a valid CleanupReport
 */
export function isCleanupReport(obj: unknown): obj is CleanupReport {
  try {
    CleanupReportSchema.parse(obj);
    return true;
  } catch {
    return false;
  }
}

/**
 * Validate CleanupReport data against schema
 * @throws {z.ZodError} If validation fails
 */
export function validateCleanupReport(data: unknown): CleanupReport {
  return CleanupReportSchema.parse(data);
}

/**
 * Create a summary string from cleanup report
 */
export function createCleanupSummary(report: CleanupReport): string {
  const processCount = report.processes_terminated.length;
  const windowCount = report.windows_closed.length;
  const errorCount = report.errors.length;

  const successfulProcesses = report.processes_terminated.filter(p => p.success).length;
  const successfulWindows = report.windows_closed.filter(w => w.success).length;

  const parts: string[] = [];

  if (processCount > 0) {
    parts.push(`${successfulProcesses}/${processCount} processes terminated`);
  }

  if (windowCount > 0) {
    parts.push(`${successfulWindows}/${windowCount} windows closed`);
  }

  if (errorCount > 0) {
    parts.push(`${errorCount} errors encountered`);
  }

  if (parts.length === 0) {
    return "No cleanup actions performed";
  }

  return `Cleanup completed: ${parts.join(", ")} in ${report.total_duration_ms}ms`;
}
