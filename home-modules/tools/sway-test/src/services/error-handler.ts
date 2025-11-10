/**
 * Error Handler Service for Sway Test Framework
 *
 * Feature 070 - User Story 1: Clear Error Diagnostics
 * Task: T010
 *
 * Provides error formatting and logging functionality for StructuredError instances.
 */

import { StructuredError, isStructuredError } from "../models/structured-error.ts";

/**
 * Format and display error to console
 * @param error - Error to format (StructuredError or generic Error)
 * @returns Formatted error message
 */
export function formatError(error: unknown): string {
  if (isStructuredError(error)) {
    return error.format();
  }

  // Fallback for non-StructuredError instances
  if (error instanceof Error) {
    return `L Error: ${error.message}\n\nStack trace:\n${error.stack || "No stack trace available"}`;
  }

  // Last resort for unknown error types
  return `L Unknown error: ${String(error)}`;
}

/**
 * Log error to console with appropriate formatting
 * @param error - Error to log
 */
export function logError(error: unknown): void {
  console.error(formatError(error));
}

/**
 * Log error to file (for T015 - framework log file)
 * @param error - Error to log
 * @param logPath - Path to log file (default: ~/.config/sway-test/error.log)
 */
export async function logErrorToFile(
  error: unknown,
  logPath?: string
): Promise<void> {
  const defaultLogPath = `${Deno.env.get("HOME")}/.config/sway-test/error.log`;
  const targetPath = logPath || defaultLogPath;

  try {
    // Ensure log directory exists
    const logDir = targetPath.substring(0, targetPath.lastIndexOf("/"));
    await Deno.mkdir(logDir, { recursive: true });

    const timestamp = new Date().toISOString();
    const formattedError = formatError(error);
    const logEntry = `\n[${timestamp}]\n${formattedError}\n${"=".repeat(80)}\n`;

    // Append to log file
    await Deno.writeTextFile(targetPath, logEntry, { append: true });
  } catch (fileError) {
    console.error(`Failed to write error log to ${targetPath}:`, fileError);
  }
}

/**
 * Handle error by logging to both console and file
 * @param error - Error to handle
 * @param logToFile - Whether to log to file (default: true)
 */
export async function handleError(
  error: unknown,
  logToFile = true
): Promise<void> {
  logError(error);
  if (logToFile) {
    await logErrorToFile(error);
  }
}
