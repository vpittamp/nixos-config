/**
 * Cleanup Command Handler
 *
 * Feature 070 - User Story 2: Graceful Cleanup Commands
 * Task: T022
 *
 * Manual cleanup of test-spawned processes and windows for interrupted test sessions.
 */

import { getCleanupManager } from "../services/cleanup-manager.ts";
import type { CleanupReport } from "../models/cleanup-report.ts";
import { parseArgs } from "@std/cli/parse-args";

/**
 * Cleanup command options
 */
export interface CleanupOptions {
  /** Cleanup everything (default) */
  all?: boolean;

  /** Cleanup only processes */
  processes?: boolean;

  /** Cleanup only windows */
  windows?: boolean;

  /** Specific window markers to cleanup (comma-separated) */
  markers?: string;

  /** Dry run - show what would be cleaned without doing it */
  dryRun?: boolean;

  /** Output JSON format */
  json?: boolean;

  /** Verbose output */
  verbose?: boolean;
}

/**
 * Parse cleanup command arguments
 */
export function parseCleanupArgs(args: string[]): CleanupOptions {
  const parsed = parseArgs(args, {
    boolean: ["all", "processes", "windows", "dry-run", "json", "verbose", "help"],
    string: ["markers"],
    alias: {
      a: "all",
      p: "processes",
      w: "windows",
      m: "markers",
      d: "dry-run",
      j: "json",
      v: "verbose",
      h: "help",
    },
    default: {
      all: false,
      processes: false,
      windows: false,
      "dry-run": false,
      json: false,
      verbose: false,
    },
  });

  return {
    all: parsed.all,
    processes: parsed.processes,
    windows: parsed.windows,
    markers: parsed.markers,
    dryRun: parsed["dry-run"],
    json: parsed.json,
    verbose: parsed.verbose,
  };
}

/**
 * Show cleanup command help
 */
export function showCleanupHelp(): void {
  console.log(`
sway-test cleanup - Clean up test-spawned processes and windows

USAGE:
  sway-test cleanup [OPTIONS]

OPTIONS:
  -a, --all           Cleanup everything (default if no flags specified)
  -p, --processes     Cleanup only tracked processes
  -w, --windows       Cleanup only tracked windows
  -m, --markers=LIST  Cleanup specific window markers (comma-separated)
  -d, --dry-run       Show what would be cleaned without doing it
  -j, --json          Output results in JSON format
  -v, --verbose       Show detailed cleanup information
  -h, --help          Show this help message

EXAMPLES:
  # Clean up all tracked resources
  sway-test cleanup

  # Clean up only processes
  sway-test cleanup --processes

  # Clean up specific window markers
  sway-test cleanup --markers="sway-test-1,sway-test-2"

  # Dry run to see what would be cleaned
  sway-test cleanup --dry-run

  # Get JSON output for scripting
  sway-test cleanup --json

DESCRIPTION:
  The cleanup command provides manual cleanup of processes and windows that were
  spawned during test execution. This is useful for recovering from interrupted
  test sessions where automatic cleanup didn't run.

  By default, all tracked resources are cleaned. Use --processes or --windows
  to cleanup specific resource types, or --markers to cleanup specific windows.

  Cleanup uses graceful termination:
  - Processes: SIGTERM with 500ms timeout, then SIGKILL if needed
  - Windows: Sway IPC kill command via window markers
`);
}

/**
 * Execute cleanup command
 */
export async function cleanupCommand(options: CleanupOptions): Promise<number> {
  const cleanupManager = getCleanupManager();

  // Default to --all if no specific flags provided
  const cleanupAll = !options.processes && !options.windows && !options.markers;

  if (cleanupAll || options.all) {
    // Cleanup everything
    if (options.dryRun) {
      const state = cleanupManager.getState();
      if (options.json) {
        console.log(JSON.stringify({
          dry_run: true,
          processes_to_cleanup: state.processes,
          windows_to_cleanup: state.windows,
        }, null, 2));
      } else {
        console.log(`Dry run: Would cleanup ${state.processes} process(es) and ${state.windows} window(s)`);
      }
      return 0;
    }

    // Perform actual cleanup
    const report: CleanupReport = await cleanupManager.cleanup();

    if (options.json) {
      console.log(JSON.stringify(report, null, 2));
    } else {
      // Import CleanupReporter dynamically to avoid circular dependencies
      const { CleanupReporter } = await import("../ui/cleanup-reporter.ts");
      const reporter = new CleanupReporter();
      console.log(reporter.format(report, options.verbose || false));
    }

    // Return exit code: 0 if no errors, 1 if cleanup had errors
    return report.errors.length > 0 ? 1 : 0;
  }

  if (options.processes) {
    // Cleanup only processes
    if (options.dryRun) {
      const state = cleanupManager.getState();
      if (options.json) {
        console.log(JSON.stringify({
          dry_run: true,
          processes_to_cleanup: state.processes,
        }, null, 2));
      } else {
        console.log(`Dry run: Would cleanup ${state.processes} process(es)`);
      }
      return 0;
    }

    const report: CleanupReport = await cleanupManager.cleanup();

    if (options.json) {
      console.log(JSON.stringify({
        processes_terminated: report.processes_terminated,
        errors: report.errors.filter(e => e.component === "ProcessTracker"),
      }, null, 2));
    } else {
      const { CleanupReporter } = await import("../ui/cleanup-reporter.ts");
      const reporter = new CleanupReporter();
      console.log(reporter.formatProcesses(report.processes_terminated, options.verbose || false));
    }

    return report.errors.filter(e => e.component === "ProcessTracker").length > 0 ? 1 : 0;
  }

  if (options.windows) {
    // Cleanup only windows
    if (options.dryRun) {
      const state = cleanupManager.getState();
      if (options.json) {
        console.log(JSON.stringify({
          dry_run: true,
          windows_to_cleanup: state.windows,
        }, null, 2));
      } else {
        console.log(`Dry run: Would cleanup ${state.windows} window(s)`);
      }
      return 0;
    }

    const report: CleanupReport = await cleanupManager.cleanup();

    if (options.json) {
      console.log(JSON.stringify({
        windows_closed: report.windows_closed,
        errors: report.errors.filter(e => e.component === "WindowTracker"),
      }, null, 2));
    } else {
      const { CleanupReporter } = await import("../ui/cleanup-reporter.ts");
      const reporter = new CleanupReporter();
      console.log(reporter.formatWindows(report.windows_closed, options.verbose || false));
    }

    return report.errors.filter(e => e.component === "WindowTracker").length > 0 ? 1 : 0;
  }

  if (options.markers) {
    // Cleanup specific window markers
    const markers = options.markers.split(",").map(m => m.trim());

    if (options.dryRun) {
      if (options.json) {
        console.log(JSON.stringify({
          dry_run: true,
          markers_to_cleanup: markers,
        }, null, 2));
      } else {
        console.log(`Dry run: Would cleanup windows with markers: ${markers.join(", ")}`);
      }
      return 0;
    }

    // For specific markers, we need to access the WindowTracker directly
    // This is a simplified implementation - in practice, you'd want to expose
    // a method on CleanupManager to cleanup specific markers
    console.error("Error: --markers flag not yet implemented");
    console.error("Use --windows to cleanup all tracked windows");
    return 1;
  }

  // No valid options provided
  console.error("Error: No cleanup target specified");
  showCleanupHelp();
  return 1;
}
