/**
 * JUnit XML Reporter (T069)
 *
 * Outputs test results in JUnit XML format for CI/CD integration.
 * Compatible with Jenkins, GitLab CI, GitHub Actions, and other CI systems.
 */

import type { TestResult } from "../models/test-result.ts";

/**
 * JUnit XML reporter for CI/CD compatibility
 */
export class JunitReporter {
  /**
   * Escape XML special characters
   */
  private escapeXml(text: string): string {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  }

  /**
   * Generate JUnit XML output for test results
   */
  report(results: TestResult[], suiteName: string = "Sway Test Suite"): string {
    const lines: string[] = [];

    // Calculate summary statistics
    const totalTests = results.length;
    const failures = results.filter((r) => !r.passed && r.status !== "error").length;
    const errors = results.filter((r) => r.status === "error").length;
    const skipped = results.filter((r) => r.status === "skipped").length;
    const totalTime = results.reduce((sum, r) => sum + (r.duration || 0), 0) / 1000; // Convert to seconds

    // XML declaration
    lines.push('<?xml version="1.0" encoding="UTF-8"?>');

    // Testsuites element
    lines.push('<testsuites>');

    // Testsuite element
    lines.push(
      `  <testsuite name="${this.escapeXml(suiteName)}" ` +
      `tests="${totalTests}" ` +
      `failures="${failures}" ` +
      `errors="${errors}" ` +
      `skipped="${skipped}" ` +
      `time="${totalTime.toFixed(3)}">`
    );

    // Test cases
    results.forEach((result) => {
      const className = "SwayTest";
      const testName = this.escapeXml(result.testName);
      const time = ((result.duration || 0) / 1000).toFixed(3); // Convert to seconds

      lines.push(
        `    <testcase classname="${className}" ` +
        `name="${testName}" ` +
        `time="${time}">`
      );

      // Add failure/error elements for failed tests
      if (!result.passed) {
        if (result.status === "error") {
          // Error element for exceptions/errors
          const message = this.escapeXml(result.message || "Test error");
          lines.push(`      <error message="${message}">`);

          // Add error details
          if (result.diagnostics?.failureState) {
            lines.push(`        <![CDATA[`);
            lines.push(`Failed at: ${result.finishedAt}`);
            lines.push(`Failure state captured`);
            lines.push(`        ]]>`);
          }

          lines.push(`      </error>`);
        } else if (result.status === "timeout") {
          // Timeout as error
          const message = this.escapeXml(result.message || "Test timeout");
          lines.push(`      <error message="${message}" type="timeout"/>`);
        } else {
          // Failure element for assertion failures
          const message = this.escapeXml(result.message || "Test failed");
          lines.push(`      <failure message="${message}">`);

          // Add diff information
          if (result.diff && !result.diff.matches) {
            lines.push(`        <![CDATA[`);
            lines.push(`Differences found:`);
            result.diff.differences.forEach((diff) => {
              lines.push(`  ${diff.path}: expected ${JSON.stringify(diff.expected)} but got ${JSON.stringify(diff.actual)}`);
            });
            lines.push(`        ]]>`);
          }

          lines.push(`      </failure>`);
        }
      }

      // Add system-out for additional information
      if (result.diagnostics || result.diff) {
        lines.push(`      <system-out>`);
        lines.push(`        <![CDATA[`);

        if (result.startedAt) {
          lines.push(`Started: ${result.startedAt}`);
        }
        if (result.finishedAt) {
          lines.push(`Finished: ${result.finishedAt}`);
        }
        if (result.duration) {
          lines.push(`Duration: ${result.duration}ms`);
        }

        lines.push(`        ]]>`);
        lines.push(`      </system-out>`);
      }

      lines.push(`    </testcase>`);
    });

    // Close testsuite and testsuites
    lines.push('  </testsuite>');
    lines.push('</testsuites>');

    return lines.join("\n");
  }

  /**
   * Print JUnit XML output to stdout
   */
  print(results: TestResult[], suiteName?: string): void {
    console.log(this.report(results, suiteName));
  }

  /**
   * Write JUnit XML output to file
   */
  async writeToFile(results: TestResult[], filePath: string, suiteName?: string): Promise<void> {
    const xml = this.report(results, suiteName);
    await Deno.writeTextFile(filePath, xml);
  }
}
