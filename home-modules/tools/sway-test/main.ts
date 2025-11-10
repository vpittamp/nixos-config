#!/usr/bin/env -S deno run --allow-all

/**
 * Sway Test Framework - Main Entry Point
 *
 * Test-driven development framework for Sway window manager system testing.
 * Enables comparison of expected vs actual system state from swaymsg tree output.
 *
 * Feature 070 - User Story 1: Clear Error Diagnostics
 * Task: T014
 */

import { parseArgs } from "@std/cli/parse-args";
import { runCommand } from "./src/commands/run.ts";
import { validateCommand } from "./src/commands/validate.ts";
import { cleanupCommand, parseCleanupArgs, showCleanupHelp } from "./src/commands/cleanup.ts";
import { listAppsCommand, parseListAppsArgs, showListAppsHelp } from "./src/commands/list-apps.ts";
import { listPWAsCommand, parseListPWAsArgs, showListPWAsHelp } from "./src/commands/list-pwas.ts";
import { VERSION } from "./src/constants.ts";
import { handleError } from "./src/services/error-handler.ts";

async function main() {
  const args = parseArgs(Deno.args, {
    string: ["command", "config"],
    boolean: ["help", "version", "verbose", "no-color", "fail-fast"],
    alias: { h: "help", v: "version", c: "config" },
  });

  if (args.help) {
    console.log(`
Sway Test Framework v${VERSION}

USAGE:
  sway-test <command> [options]

COMMANDS:
  run         Execute test cases
  validate    Validate test definitions
  cleanup     Clean up test-spawned processes and windows
  list-apps   List available applications from registry
  list-pwas   List available PWAs from registry
  report      Generate test reports

OPTIONS:
  -h, --help     Show this help message
  -v, --version  Show version information

For more information, see: home-modules/tools/sway-test/README.md
    `);
    Deno.exit(0);
  }

  if (args.version) {
    console.log(`Sway Test Framework v${VERSION}`);
    Deno.exit(0);
  }

  const command = args._[0]?.toString() || "help";

  try {
    switch (command) {
      case "run": {
        const testFiles = args._.slice(1).map((f) => f.toString());
        if (testFiles.length === 0) {
          console.error("Error: No test files specified");
          console.error("Usage: sway-test run <file1.json> [file2.json ...]");
          Deno.exit(1);
        }

        const exitCode = await runCommand({
          testFiles,
          verbose: args.verbose,
          noColor: args["no-color"],
          failFast: args["fail-fast"],
          config: args.config,
        });
        Deno.exit(exitCode);
      }

      case "validate": {
        const files = args._.slice(1).map((f) => f.toString());
        const exitCode = await validateCommand(files);
        Deno.exit(exitCode);
      }

      case "cleanup": {
        // T024: Cleanup command for manual resource cleanup
        const cleanupArgs = args._.slice(1).map((a) => a.toString());

        // Check for help flag
        if (args.help) {
          showCleanupHelp();
          Deno.exit(0);
        }

        const options = parseCleanupArgs(cleanupArgs);
        const exitCode = await cleanupCommand(options);
        Deno.exit(exitCode);
      }

      case "list-apps": {
        // T057: List apps command
        const listAppsArgs = args._.slice(1).map((a) => a.toString());

        const options = parseListAppsArgs(listAppsArgs);

        // Check for help flag
        if (options.help) {
          showListAppsHelp();
          Deno.exit(0);
        }

        const exitCode = await listAppsCommand(options);
        Deno.exit(exitCode);
      }

      case "list-pwas": {
        // T057: List PWAs command
        const listPWAsArgs = args._.slice(1).map((a) => a.toString());

        const options = parseListPWAsArgs(listPWAsArgs);

        // Check for help flag
        if (options.help) {
          showListPWAsHelp();
          Deno.exit(0);
        }

        const exitCode = await listPWAsCommand(options);
        Deno.exit(exitCode);
      }

      case "report":
        console.log("Report command - not yet implemented");
        console.log("(Will be implemented in future phases)");
        break;

      case "help":
        console.log(`
Sway Test Framework v${VERSION}

USAGE:
  sway-test <command> [options] [files...]

COMMANDS:
  run <files...>        Execute test cases from JSON files
  validate <files...>   Validate test definition files
  cleanup               Clean up test-spawned processes and windows
  list-apps             List available applications from registry
  list-pwas             List available PWAs from registry
  report                Generate test reports (not yet implemented)

OPTIONS:
  --verbose             Show detailed test output
  --no-color            Disable colored output
  --fail-fast           Stop on first test failure
  -c, --config <path>   Custom Sway config file for test isolation
  -h, --help            Show this help message
  -v, --version         Show version information

EXAMPLES:
  sway-test run tests/basic/test_window_launch.json
  sway-test run --verbose tests/**/*.json
  sway-test validate tests/basic/*.json
  sway-test cleanup --all
  sway-test cleanup --processes --dry-run
  sway-test list-apps --filter firefox
  sway-test list-pwas --workspace 50

For more information, see: home-modules/tools/sway-test/README.md
        `);
        break;

      default:
        console.error(`Unknown command: ${command}`);
        console.error("Run 'sway-test --help' for usage information");
        Deno.exit(1);
    }
  } catch (error) {
    // Use handleError from error-handler service (T014: StructuredError integration)
    // This will format StructuredError instances nicely and log to file
    await handleError(error);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}
