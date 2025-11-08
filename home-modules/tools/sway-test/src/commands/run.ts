/**
 * Run Command Handler
 *
 * Orchestrates test execution: load → setup → capture → compare → report
 */

import { SwayClient } from "../services/sway-client.ts";
import { TreeMonitorClient } from "../services/tree-monitor-client.ts";
import { StateComparator } from "../services/state-comparator.ts";
import { ActionExecutor } from "../services/action-executor.ts";
import { DiffRenderer } from "../ui/diff-renderer.ts";
import { Reporter } from "../ui/reporter.ts";
import { TapReporter } from "../ui/tap-reporter.ts";
import { JunitReporter } from "../ui/junit-reporter.ts";
import { FixtureManager } from "../fixtures/fixture-manager.ts";
import type { TestCase } from "../models/test-case.ts";
import type { TestResult, TestStatus } from "../models/test-result.ts";
import type { StateSnapshot } from "../models/state-snapshot.ts";
import type { Fixture } from "../fixtures/types.ts";
import { TIMEOUTS, PROGRESS_INTERVALS, HEADLESS_CONFIG, TREE_MONITOR } from "../constants.ts";
import { SwayTestError, ErrorRecoveryFactory } from "../helpers/errors.ts";

/**
 * Output format for test results (T070)
 */
export type OutputFormat = "human" | "tap" | "junit";

/**
 * Run command options
 */
export interface RunOptions {
  testFiles: string[];
  verbose?: boolean;
  noColor?: boolean;
  failFast?: boolean;
  timeout?: number;
  directory?: string; // Filter tests by directory pattern (T063)
  tags?: string[]; // Filter tests by tags (T064)
  format?: OutputFormat; // Output format: human (default), tap, junit (T070)
  ci?: boolean; // CI mode: enables headless, TAP output, non-zero exit on failures (T071)
  config?: string; // T079: Custom Sway config file path for test isolation
}

/**
 * Test runner orchestrator
 */
export class TestRunner {
  private swayClient: SwayClient;
  private treeMonitorClient: TreeMonitorClient;
  private comparator: StateComparator;
  private actionExecutor: ActionExecutor;
  private diffRenderer: DiffRenderer;
  private reporter: Reporter;
  private fixtureManager: FixtureManager;
  private treeMonitorAvailable: boolean = false;

  constructor(options: { noColor?: boolean } = {}) {
    this.swayClient = new SwayClient();
    this.treeMonitorClient = new TreeMonitorClient();
    this.comparator = new StateComparator();
    this.actionExecutor = new ActionExecutor({ swayClient: this.swayClient });
    this.diffRenderer = new DiffRenderer(!options.noColor);
    this.reporter = new Reporter(!options.noColor);
    this.fixtureManager = new FixtureManager({ swayClient: this.swayClient });
  }

  /**
   * Run tests from file(s)
   */
  async run(options: RunOptions): Promise<number> {
    // T071: Apply CI mode defaults
    if (options.ci) {
      // CI mode: enable TAP output by default, disable colors
      if (!options.format) {
        options.format = "tap";
      }
      if (options.noColor === undefined) {
        options.noColor = true;
      }
    }

    // T066/T067: Check Sway availability and auto-launch in headless mode if needed
    let swayAvailable = await this.swayClient.isAvailable();
    let headlessSwayProcess: Deno.ChildProcess | null = null;

    if (!swayAvailable) {
      // Check if we're in a headless environment (no WAYLAND_DISPLAY)
      const waylandDisplay = Deno.env.get("WAYLAND_DISPLAY");
      const isHeadless = !waylandDisplay || waylandDisplay === "";

      if (isHeadless && options.verbose) {
        console.log("⚠ Sway is not running. Attempting to launch headless Sway for CI testing...");
      }

      if (isHeadless) {
        // T067/T079: Launch Sway in headless mode with WLR_BACKENDS=headless
        try {
          headlessSwayProcess = await this.launchHeadlessSway(options.config);

          // Wait for Sway to become available
          const startTime = Date.now();
          while (Date.now() - startTime < TIMEOUTS.SWAY_HEADLESS_LAUNCH) {
            swayAvailable = await this.swayClient.isAvailable();
            if (swayAvailable) {
              if (options.verbose) {
                console.log("✓ Headless Sway launched successfully");
              }
              break;
            }
            await new Promise(resolve => setTimeout(resolve, TIMEOUTS.SWAY_HEADLESS_POLL));
          }

          if (!swayAvailable) {
            this.reportError(
              `Failed to launch headless Sway (timeout after ${TIMEOUTS.SWAY_HEADLESS_LAUNCH}ms)`,
              ErrorRecoveryFactory.headlessSway(`Sway process did not become available within ${TIMEOUTS.SWAY_HEADLESS_LAUNCH}ms`)
            );
            headlessSwayProcess?.kill();
            return 1;
          }
        } catch (error) {
          this.reportError(
            `Failed to launch headless Sway: ${(error as Error).message}`,
            ErrorRecoveryFactory.headlessSway((error as Error).message)
          );
          return 1;
        }
      } else {
        this.reportError(
          "Sway is not running or not accessible via swaymsg",
          ErrorRecoveryFactory.swayConnection()
        );
        return 1;
      }
    }

    // Check tree-monitor daemon availability (optional, provides rich diagnostics)
    this.treeMonitorAvailable = await this.treeMonitorClient.isAvailable();
    if (!this.treeMonitorAvailable && options.verbose) {
      console.log("⚠ tree-monitor daemon not available - event correlation disabled");
      console.log("  To enable rich diagnostics, ensure sway-tree-monitor is running:");
      console.log("  systemctl --user start sway-tree-monitor");
    }

    // Load test cases
    const testCases: TestCase[] = [];
    for (const file of options.testFiles) {
      try {
        // Apply directory filter (T063)
        if (options.directory && !file.includes(options.directory)) {
          continue; // Skip files not matching directory filter
        }

        const tests = await this.loadTestFile(file);
        testCases.push(...tests);
      } catch (error) {
        this.reportError(
          `Failed to load test file ${file}: ${(error as Error).message}`,
          ErrorRecoveryFactory.testFileParsing(file, (error as Error).message)
        );
        if (options.failFast) {
          return 1;
        }
      }
    }

    // Apply tag filter (T064)
    let filteredTestCases = testCases;
    if (options.tags && options.tags.length > 0) {
      filteredTestCases = testCases.filter((tc) =>
        tc.tags && tc.tags.some((tag) => options.tags!.includes(tag))
      );

      if (options.verbose && filteredTestCases.length < testCases.length) {
        console.log(
          `Filtered ${testCases.length - filteredTestCases.length} test(s) by tags: ${options.tags.join(", ")}`,
        );
      }
    }

    if (filteredTestCases.length === 0) {
      this.reportError("No test cases found after applying filters");
      return 1;
    }

    const format = options.format || "human";

    // Only show progress in human format
    if (format === "human") {
      console.log(`Running ${filteredTestCases.length} test(s)...\n`);
    }

    // T072: Setup progress indicator for CI (prints periodically to prevent timeout)
    let progressInterval: number | null = null;
    const startTime = Date.now();

    if (options.ci || format !== "human") {
      progressInterval = setInterval(() => {
        const elapsed = Math.round((Date.now() - startTime) / 1000);
        const completed = results.length;
        const total = filteredTestCases.length;
        console.error(`[Progress] ${completed}/${total} tests completed (${elapsed}s elapsed)`);
      }, PROGRESS_INTERVALS.CI_PROGRESS);
    }

    // Execute tests
    const results: TestResult[] = [];
    for (const testCase of filteredTestCases) {
      const result = await this.executeTest(testCase, options);
      results.push(result);

      // Report individual test (only in human format)
      if (format === "human") {
        if (options.verbose) {
          console.log(this.reporter.reportTest(result));
          if (!result.passed && result.diff) {
            console.log(this.diffRenderer.render(result.diff));

            // Show tree-monitor event correlation if available (T029)
            if (result.diagnostics?.treeMonitorEvents) {
              console.log(
                this.diffRenderer.renderEventCorrelation(result.diagnostics.treeMonitorEvents)
              );
            }
          }
          console.log("");
        } else {
          // Compact report
          const status = result.passed ? "✓" : "✗";
          console.log(`${status} ${result.testName}`);
        }
      }

      // Fail fast if requested
      if (!result.passed && options.failFast) {
        break;
      }
    }

    // T072: Clear progress indicator
    if (progressInterval !== null) {
      clearInterval(progressInterval);
    }

    // T070: Output results based on format option
    if (format === "tap") {
      // TAP format output
      const tapReporter = new TapReporter();
      tapReporter.print(results);
    } else if (format === "junit") {
      // JUnit XML format output
      const junitReporter = new JunitReporter();
      junitReporter.print(results, "Sway Test Suite");
    } else {
      // Human-readable format (default)
      const summary = this.reporter.createSummary("Test Suite", results);

      // Report summary
      console.log("\n");
      console.log(this.reporter.reportSuite(summary));

      // Report failures if not verbose
      if (!options.verbose && summary.failed > 0) {
        console.log(this.reporter.reportFailures(results));
      }
    }

    // Cleanup headless Sway if we launched it
    if (headlessSwayProcess) {
      if (options.verbose && format === "human") {
        console.log("Cleaning up headless Sway process...");
      }
      try {
        headlessSwayProcess.kill();
        await headlessSwayProcess.status;
      } catch {
        // Ignore cleanup errors
      }
    }

    // Return exit code (0 = success, 1 = failure)
    const failed = results.filter((r) => !r.passed).length;
    const errors = results.filter((r) => r.status === "error").length;
    const timeouts = results.filter((r) => r.status === "timeout").length;

    return failed === 0 && errors === 0 && timeouts === 0
      ? 0
      : 1;
  }

  /**
   * Execute single test case
   */
  private async executeTest(
    testCase: TestCase,
    options: RunOptions,
  ): Promise<TestResult> {
    const startTime = performance.now();
    const result: TestResult = {
      testName: testCase.name,
      status: "running" as TestStatus,
      startedAt: new Date().toISOString(),
      duration: 0,
      passed: false,
    };

    try {
      // Apply timeout if specified
      const timeout = testCase.timeout || options.timeout || TIMEOUTS.TEST_EXECUTION;

      const testPromise = this.runTestWithTimeout(testCase, timeout);
      const testResult = await testPromise;

      // Update result
      Object.assign(result, testResult);
    } catch (error) {
      // Test error
      result.status = "error" as TestStatus;
      result.passed = false;
      result.message = (error as Error).message;
    } finally {
      result.finishedAt = new Date().toISOString();
      result.duration = Math.round(performance.now() - startTime);
    }

    return result;
  }

  /**
   * Run test with timeout
   */
  private async runTestWithTimeout(
    testCase: TestCase,
    timeout: number,
  ): Promise<Partial<TestResult>> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      const result = await this.runTestLogic(testCase, controller.signal);
      clearTimeout(timeoutId);
      return result;
    } catch (error) {
      clearTimeout(timeoutId);
      if ((error as Error).name === "AbortError") {
        // T078: Capture diagnostic state on timeout
        let diagnosticState = null;
        try {
          diagnosticState = await this.swayClient.captureState();
        } catch (_captureError) {
          // Ignore errors during diagnostic capture
        }

        return {
          status: "timeout" as TestStatus,
          passed: false,
          message: `Test exceeded timeout of ${timeout}ms`,
          diagnostics: diagnosticState ? {
            timeoutState: diagnosticState,
          } : undefined,
        };
      }
      throw error;
    }
  }

  /**
   * Core test execution logic
   */
  private async runTestLogic(
    testCase: TestCase,
    signal: AbortSignal,
  ): Promise<Partial<TestResult>> {
    // Load and setup fixtures (T060)
    const fixtures: Fixture[] = [];
    const fixtureState: Record<string, unknown> = {};
    if (testCase.fixtures && testCase.fixtures.length > 0) {
      try {
        // Load fixtures
        for (const fixtureName of testCase.fixtures) {
          const fixture = await this.fixtureManager.loadFixture(fixtureName);
          fixtures.push(fixture);
        }

        // Setup all fixtures in order
        const fixtureResults = await this.fixtureManager.setupAll(fixtures, testCase.name);

        // Collect fixture state (T061)
        for (const result of fixtureResults) {
          Object.assign(fixtureState, result.state);
        }
      } catch (error) {
        return {
          status: "error" as TestStatus,
          passed: false,
          message: `Fixture setup failed: ${(error as Error).message}`,
        };
      }
    }

    // Pass fixture state to action executor (T061)
    this.actionExecutor.setFixtureState(fixtureState);

    // Execute setup actions if present (T039)
    if (testCase.setup && testCase.setup.length > 0) {
      try {
        await this.actionExecutor.execute(testCase.setup);
      } catch (error) {
        // Teardown fixtures on setup failure
        if (fixtures.length > 0) {
          await this.fixtureManager.teardownAll(fixtures, testCase.name);
        }

        return {
          status: "error" as TestStatus,
          passed: false,
          message: `Setup failed: ${(error as Error).message}`,
        };
      }
    }

    // Execute main test actions (T039)
    if (testCase.actions && testCase.actions.length > 0) {
      try {
        await this.actionExecutor.execute(testCase.actions);
      } catch (error) {
        // Teardown fixtures on action failure
        if (fixtures.length > 0) {
          await this.fixtureManager.teardownAll(fixtures, testCase.name);
        }

        // Action execution failed - capture diagnostic state (T040)
        const failureState = await this.swayClient.captureState();

        return {
          status: "error" as TestStatus,
          passed: false,
          message: `Action execution failed: ${(error as Error).message}`,
          actualState: failureState,
          diagnostics: {
            failureState,
          },
        };
      }
    }

    // Capture events before state capture (if tree-monitor is available)
    let capturedEvents;
    if (this.treeMonitorAvailable) {
      try {
        // Query recent events during test execution
        capturedEvents = await this.treeMonitorClient.queryEvents({ last: TREE_MONITOR.DEFAULT_EVENT_COUNT });
      } catch (error) {
        // Non-fatal - continue without event correlation
        if (this.reporter) {
          console.warn(`Warning: Failed to query tree-monitor events: ${(error as Error).message}`);
        }
      }
    }

    // Capture actual state
    const actualState = await this.swayClient.captureState();

    if (signal.aborted) {
      throw new DOMException("Aborted", "AbortError");
    }

    // Compare with expected state
    // Use tree field from expectedState (old format compatibility)
    const expectedState = (testCase.expectedState as { state?: StateSnapshot; tree?: StateSnapshot }).state ||
      (testCase.expectedState as { state?: StateSnapshot; tree?: StateSnapshot }).tree as StateSnapshot;
    const diff = this.comparator.compare(expectedState, actualState, "exact");

    // Determine pass/fail
    const passed = diff.matches;

    // Build diagnostics context if test failed
    const diagnostics = !passed && this.treeMonitorAvailable ? {
      treeMonitorEvents: capturedEvents,
      initialState: expectedState as StateSnapshot,
      failureState: actualState,
    } : undefined;

    // Teardown fixtures after test completion (T060)
    if (fixtures.length > 0) {
      try {
        await this.fixtureManager.teardownAll(fixtures, testCase.name);
      } catch (error) {
        // Log warning but don't fail the test
        console.warn(`Warning: Fixture teardown failed: ${(error as Error).message}`);
      }
    }

    return {
      status: (passed ? "passed" : "failed") as TestStatus,
      passed,
      message: passed ? "Test passed" : "State comparison failed",
      expectedState,
      actualState,
      diff,
      diagnostics,
    };
  }

  /**
   * Load test cases from JSON file
   */
  private async loadTestFile(filePath: string): Promise<TestCase[]> {
    const content = await Deno.readTextFile(filePath);
    const json = JSON.parse(content);

    // Support both single test and array of tests
    if (Array.isArray(json)) {
      return json as TestCase[];
    } else {
      return [json as TestCase];
    }
  }

  /**
   * Launch Sway in headless mode for CI testing (T066/T067/T079)
   */
  private async launchHeadlessSway(customConfigPath?: string): Promise<Deno.ChildProcess> {
    // T067: Set WLR environment for headless rendering
    const env = {
      ...Deno.env.toObject(),
      WLR_BACKENDS: HEADLESS_CONFIG.WLR_BACKENDS,
      WLR_LIBINPUT_NO_DEVICES: HEADLESS_CONFIG.WLR_LIBINPUT_NO_DEVICES,
    };

    // T079: Use custom config if provided, otherwise use minimal default config
    let configPath = customConfigPath;
    if (!configPath) {
      // Write minimal config to temp file
      configPath = await Deno.makeTempFile({ suffix: ".conf" });
      await Deno.writeTextFile(configPath, HEADLESS_CONFIG.MINIMAL_CONFIG);
    }

    // Launch Sway with headless backend
    const cmd = new Deno.Command("sway", {
      args: ["-c", configPath],
      env,
      stdout: "piped",
      stderr: "piped",
    });

    const child = cmd.spawn();

    // Give Sway a moment to start
    await new Promise(resolve => setTimeout(resolve, TIMEOUTS.HEADLESS_SWAY_STARTUP));

    return child;
  }

  /**
   * Report error message (enhanced for T076)
   */
  private reportError(message: string, recovery?: ReturnType<typeof ErrorRecoveryFactory[keyof typeof ErrorRecoveryFactory]>): void {
    if (recovery) {
      const error = new SwayTestError(message, recovery);
      console.error(error.format(this.noColor));
    } else {
      console.error(`Error: ${message}`);
    }
  }
}

/**
 * Run command entry point
 */
export async function runCommand(options: RunOptions): Promise<number> {
  const runner = new TestRunner({ noColor: options.noColor });
  return await runner.run(options);
}
