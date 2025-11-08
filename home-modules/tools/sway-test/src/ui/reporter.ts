/**
 * Reporter UI Component
 *
 * Generates test execution reports with summary statistics.
 */

import type { TestResult, TestStatus, TestSuiteSummary } from "../models/test-result.ts";
import { ErrorRecoveryFactory } from "../helpers/errors.ts";

/**
 * ANSI color codes for terminal output
 */
const COLORS = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  gray: "\x1b[90m",
  bold: "\x1b[1m",
};

/**
 * Reporter for test framework
 */
export class Reporter {
  private useColor: boolean;

  constructor(useColor = true) {
    this.useColor = useColor && Deno.stdout.isTerminal();
  }

  /**
   * Report individual test result
   */
  reportTest(result: TestResult): string {
    const lines: string[] = [];

    // Test header
    const statusIcon = this.getStatusIcon(result.status);
    const statusColor = this.getStatusColor(result.status);
    const testName = result.suiteName
      ? `${result.suiteName} > ${result.testName}`
      : result.testName;

    lines.push(
      `${this.color(statusIcon, statusColor)} ${this.color(testName, "bold")}`,
    );

    // Duration
    if (result.duration !== undefined) {
      lines.push(`  ${this.color("Duration:", "gray")} ${result.duration}ms`);
    }

    // Message if present
    if (result.message) {
      lines.push(`  ${this.color("Message:", "gray")} ${result.message}`);
    }

    // Capture latency if present
    if (result.actualState?.captureLatency) {
      lines.push(
        `  ${this.color("Capture:", "gray")} ${result.actualState.captureLatency}ms`,
      );
    }

    // T078: Show recovery suggestions for timeout
    if (result.status === "timeout" && result.message) {
      const timeoutMatch = result.message.match(/(\d+)ms/);
      const timeoutMs = timeoutMatch ? parseInt(timeoutMatch[1]) : 30000;
      const recovery = ErrorRecoveryFactory.testTimeout(result.testName, timeoutMs);

      lines.push("");
      lines.push(`  ${this.color("Recovery Suggestions:", "yellow")}`);
      for (const suggestion of recovery.suggestions) {
        lines.push(`    • ${suggestion}`);
      }
    }

    return lines.join("\n");
  }

  /**
   * Report test suite summary
   */
  reportSuite(summary: TestSuiteSummary): string {
    const lines: string[] = [];

    // Suite header
    lines.push("");
    lines.push(this.color(`Test Suite: ${summary.suiteName}`, "bold"));
    lines.push(this.color("=".repeat(50), "gray"));

    // Summary statistics
    const total = summary.totalTests;
    const passed = summary.passed;
    const failed = summary.failed;
    const skipped = summary.skipped;
    const timeout = summary.timeout;
    const error = summary.error;

    lines.push("");
    lines.push(this.color("Results:", "bold"));
    lines.push(`  Total:   ${total}`);
    lines.push(`  ${this.color("✓ Passed:", "green")}  ${passed}`);

    if (failed > 0) {
      lines.push(`  ${this.color("✗ Failed:", "red")}  ${failed}`);
    }
    if (skipped > 0) {
      lines.push(`  ${this.color("○ Skipped:", "yellow")} ${skipped}`);
    }
    if (timeout > 0) {
      lines.push(`  ${this.color("⏱ Timeout:", "yellow")} ${timeout}`);
    }
    if (error > 0) {
      lines.push(`  ${this.color("⚠ Error:", "red")}   ${error}`);
    }

    // Duration
    lines.push("");
    lines.push(`  Duration: ${this.formatDuration(summary.duration)}`);

    if (summary.averageTestDuration) {
      lines.push(`  Average:  ${this.formatDuration(summary.averageTestDuration)} per test`);
    }

    if (summary.overhead) {
      lines.push(`  Overhead: ${this.formatDuration(summary.overhead)}`);
    }

    // Overall status
    lines.push("");
    const allPassed = failed === 0 && timeout === 0 && error === 0;
    if (allPassed) {
      lines.push(this.color("✓ All tests passed", "green"));
    } else {
      lines.push(this.color("✗ Some tests failed", "red"));
    }

    lines.push(this.color("=".repeat(50), "gray"));
    lines.push("");

    return lines.join("\n");
  }

  /**
   * Report compact summary (one line)
   */
  reportCompact(summary: TestSuiteSummary): string {
    const total = summary.totalTests;
    const passed = summary.passed;
    const failed = summary.failed;
    const duration = this.formatDuration(summary.duration);

    if (failed === 0) {
      return this.color(
        `✓ ${passed}/${total} tests passed in ${duration}`,
        "green",
      );
    } else {
      return this.color(
        `✗ ${failed}/${total} tests failed (${passed} passed) in ${duration}`,
        "red",
      );
    }
  }

  /**
   * Report failed tests only
   */
  reportFailures(results: TestResult[]): string {
    const failures = results.filter((r) =>
      r.status === "failed" || r.status === "timeout" || r.status === "error"
    );

    if (failures.length === 0) {
      return this.color("✓ No failures", "green");
    }

    const lines: string[] = [];

    lines.push("");
    lines.push(this.color("Failed Tests:", "bold"));
    lines.push(this.color("=".repeat(50), "gray"));
    lines.push("");

    for (const failure of failures) {
      lines.push(this.reportTest(failure));
      lines.push("");
    }

    return lines.join("\n");
  }

  /**
   * Get status icon for test result
   */
  private getStatusIcon(status: TestStatus): string {
    switch (status) {
      case "passed":
        return "✓";
      case "failed":
        return "✗";
      case "skipped":
        return "○";
      case "timeout":
        return "⏱";
      case "error":
        return "⚠";
      case "running":
        return "▶";
      case "pending":
        return "◯";
      default:
        return "?";
    }
  }

  /**
   * Get color for test status
   */
  private getStatusColor(status: TestStatus): keyof typeof COLORS {
    switch (status) {
      case "passed":
        return "green";
      case "failed":
      case "error":
        return "red";
      case "skipped":
      case "timeout":
        return "yellow";
      case "running":
        return "blue";
      case "pending":
        return "gray";
      default:
        return "reset";
    }
  }

  /**
   * Format duration in human-readable format
   */
  private formatDuration(ms: number): string {
    if (ms < 1000) {
      return `${Math.round(ms)}ms`;
    } else if (ms < 60000) {
      return `${(ms / 1000).toFixed(2)}s`;
    } else {
      const minutes = Math.floor(ms / 60000);
      const seconds = ((ms % 60000) / 1000).toFixed(0);
      return `${minutes}m ${seconds}s`;
    }
  }

  /**
   * Apply color to text
   */
  private color(text: string, colorName: keyof typeof COLORS): string {
    if (!this.useColor) {
      return text;
    }

    const color = COLORS[colorName];
    const reset = COLORS.reset;

    return `${color}${text}${reset}`;
  }

  /**
   * Create summary from test results
   */
  createSummary(
    suiteName: string,
    results: TestResult[],
  ): TestSuiteSummary {
    const summary: TestSuiteSummary = {
      suiteName,
      totalTests: results.length,
      passed: 0,
      failed: 0,
      skipped: 0,
      timeout: 0,
      error: 0,
      duration: 0,
      results,
    };

    let totalDuration = 0;
    let totalOverhead = 0;

    for (const result of results) {
      switch (result.status) {
        case "passed":
          summary.passed++;
          break;
        case "failed":
          summary.failed++;
          break;
        case "skipped":
          summary.skipped++;
          break;
        case "timeout":
          summary.timeout++;
          break;
        case "error":
          summary.error++;
          break;
      }

      totalDuration += result.duration || 0;

      if (result.initializationTime) {
        totalOverhead += result.initializationTime;
      }
      if (result.cleanupTime) {
        totalOverhead += result.cleanupTime;
      }
    }

    summary.duration = totalDuration;
    summary.averageTestDuration = results.length > 0
      ? Math.round(totalDuration / results.length)
      : 0;
    summary.overhead = totalOverhead;

    return summary;
  }
}
