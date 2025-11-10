/**
 * Cleanup Reporter UI Formatter
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Task: T023
 *
 * Human-readable formatting for cleanup reports with color-coded output.
 */

import type {
  CleanupReport,
  ProcessCleanupEntry,
  WindowCleanupEntry,
} from "../models/cleanup-report.ts";

/**
 * ANSI color codes for terminal output
 */
const colors = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  gray: "\x1b[90m",
  bold: "\x1b[1m",
};

/**
 * Cleanup Reporter - formats cleanup reports for human consumption
 */
export class CleanupReporter {
  /**
   * Format a complete cleanup report
   */
  format(report: CleanupReport, verbose: boolean = false): string {
    const lines: string[] = [];

    // Header
    lines.push(`${colors.bold}Cleanup Report${colors.reset}`);
    lines.push(`${colors.gray}─────────────────────────────────────────────────────${colors.reset}`);
    lines.push("");

    // Summary
    lines.push(this.formatSummary(report));
    lines.push("");

    // Process cleanup details
    if (report.processes_terminated.length > 0) {
      lines.push(this.formatProcesses(report.processes_terminated, verbose));
      lines.push("");
    }

    // Window cleanup details
    if (report.windows_closed.length > 0) {
      lines.push(this.formatWindows(report.windows_closed, verbose));
      lines.push("");
    }

    // Errors
    if (report.errors.length > 0) {
      lines.push(this.formatErrors(report));
      lines.push("");
    }

    // Footer with timing
    lines.push(`${colors.gray}Completed in ${report.total_duration_ms}ms${colors.reset}`);

    return lines.join("\n");
  }

  /**
   * Format cleanup summary
   */
  formatSummary(report: CleanupReport): string {
    const processCount = report.processes_terminated.length;
    const windowCount = report.windows_closed.length;
    const errorCount = report.errors.length;

    const successfulProcesses = report.processes_terminated.filter(p => p.success).length;
    const successfulWindows = report.windows_closed.filter(w => w.success).length;

    const lines: string[] = [];

    // Processes
    if (processCount > 0) {
      const icon = successfulProcesses === processCount ? "✓" : "⚠";
      const color = successfulProcesses === processCount ? colors.green : colors.yellow;
      lines.push(
        `${color}${icon}${colors.reset} Processes: ${successfulProcesses}/${processCount} terminated`
      );
    }

    // Windows
    if (windowCount > 0) {
      const icon = successfulWindows === windowCount ? "✓" : "⚠";
      const color = successfulWindows === windowCount ? colors.green : colors.yellow;
      lines.push(
        `${color}${icon}${colors.reset} Windows: ${successfulWindows}/${windowCount} closed`
      );
    }

    // Errors
    if (errorCount > 0) {
      lines.push(
        `${colors.red}✗${colors.reset} Errors: ${errorCount} encountered`
      );
    }

    // No cleanup message
    if (processCount === 0 && windowCount === 0) {
      lines.push(`${colors.gray}No cleanup actions performed${colors.reset}`);
    }

    return lines.join("\n");
  }

  /**
   * Format process cleanup entries
   */
  formatProcesses(processes: ProcessCleanupEntry[], verbose: boolean = false): string {
    const lines: string[] = [];

    lines.push(`${colors.bold}Processes Terminated:${colors.reset}`);

    for (const process of processes) {
      const icon = process.success ? `${colors.green}✓${colors.reset}` : `${colors.red}✗${colors.reset}`;
      const method = process.method === "SIGTERM" ? "graceful" : "forced";
      const command = process.command ? `${colors.blue}${process.command}${colors.reset}` : "unknown";

      if (verbose) {
        lines.push(`  ${icon} PID ${process.pid} (${command}) - ${method}`);
        if (process.duration_ms !== undefined) {
          lines.push(`    ${colors.gray}Duration: ${process.duration_ms}ms${colors.reset}`);
        }
        if (process.error) {
          lines.push(`    ${colors.red}Error: ${process.error}${colors.reset}`);
        }
      } else {
        const error = process.error ? ` ${colors.red}(${process.error})${colors.reset}` : "";
        lines.push(`  ${icon} PID ${process.pid} (${command})${error}`);
      }
    }

    return lines.join("\n");
  }

  /**
   * Format window cleanup entries
   */
  formatWindows(windows: WindowCleanupEntry[], verbose: boolean = false): string {
    const lines: string[] = [];

    lines.push(`${colors.bold}Windows Closed:${colors.reset}`);

    for (const window of windows) {
      const icon = window.success ? `${colors.green}✓${colors.reset}` : `${colors.red}✗${colors.reset}`;
      const marker = `${colors.blue}${window.marker}${colors.reset}`;

      if (verbose) {
        lines.push(`  ${icon} ${marker}`);
        if (window.window_id !== undefined) {
          lines.push(`    ${colors.gray}Window ID: ${window.window_id}${colors.reset}`);
        }
        if (window.duration_ms !== undefined) {
          lines.push(`    ${colors.gray}Duration: ${window.duration_ms}ms${colors.reset}`);
        }
        if (window.error) {
          lines.push(`    ${colors.red}Error: ${window.error}${colors.reset}`);
        }
      } else {
        const error = window.error ? ` ${colors.red}(${window.error})${colors.reset}` : "";
        lines.push(`  ${icon} ${marker}${error}`);
      }
    }

    return lines.join("\n");
  }

  /**
   * Format cleanup errors
   */
  formatErrors(report: CleanupReport): string {
    const lines: string[] = [];

    lines.push(`${colors.bold}${colors.red}Errors:${colors.reset}`);

    for (const error of report.errors) {
      lines.push(`  ${colors.red}✗${colors.reset} ${error.component}: ${error.message}`);

      if (error.context) {
        lines.push(`    ${colors.gray}Context: ${JSON.stringify(error.context)}${colors.reset}`);
      }
    }

    return lines.join("\n");
  }

  /**
   * Format a simple one-line summary (for non-verbose output)
   */
  formatOneLine(report: CleanupReport): string {
    return report.summary;
  }
}
