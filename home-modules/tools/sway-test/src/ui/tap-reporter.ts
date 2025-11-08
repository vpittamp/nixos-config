/**
 * TAP (Test Anything Protocol) Reporter (T068)
 *
 * Outputs test results in TAP format for CI/CD integration.
 * Specification: https://testanything.org/tap-version-13-specification.html
 */

import type { TestResult } from "../models/test-result.ts";

/**
 * TAP reporter for CI/CD compatibility
 */
export class TapReporter {
  /**
   * Generate TAP output for test results
   */
  report(results: TestResult[]): string {
    const lines: string[] = [];

    // TAP version
    lines.push("TAP version 13");

    // Test plan
    lines.push(`1..${results.length}`);

    // Test results
    results.forEach((result, index) => {
      const testNumber = index + 1;
      const status = result.passed ? "ok" : "not ok";
      const testName = result.testName.replace(/#/g, "-"); // TAP requires escaping #

      // Basic test line
      let line = `${status} ${testNumber} - ${testName}`;

      // Add duration if available
      if (result.duration) {
        line += ` # duration_ms ${result.duration}`;
      }

      lines.push(line);

      // Add diagnostic information for failed tests
      if (!result.passed) {
        if (result.message) {
          lines.push(`  # ${result.message}`);
        }

        // Add diff information if available
        if (result.diff && !result.diff.matches) {
          lines.push("  # Differences found:");
          result.diff.differences.forEach((diff) => {
            lines.push(`  #   ${diff.path}: expected ${JSON.stringify(diff.expected)} but got ${JSON.stringify(diff.actual)}`);
          });
        }

        // Add error details for errored tests
        if (result.status === "error" && result.diagnostics) {
          lines.push("  # Error diagnostics:");
          if (result.diagnostics.failureState) {
            lines.push(`  #   Failure state captured at: ${result.finishedAt}`);
          }
        }

        // Add timeout information
        if (result.status === "timeout") {
          lines.push("  # Test timed out");
        }
      }
    });

    // Add summary as comment
    const passed = results.filter((r) => r.passed).length;
    const failed = results.filter((r) => !r.passed).length;
    lines.push(`# Summary: ${passed} passed, ${failed} failed, ${results.length} total`);

    return lines.join("\n");
  }

  /**
   * Print TAP output to stdout
   */
  print(results: TestResult[]): void {
    console.log(this.report(results));
  }
}
