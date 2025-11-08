#!/usr/bin/env -S deno run --allow-all

/**
 * Sway Test Framework - Main Entry Point
 *
 * Test-driven development framework for Sway window manager system testing.
 * Enables comparison of expected vs actual system state from swaymsg tree output.
 */

import { parseArgs } from "@std/cli/parse-args";
import { runCommand } from "./src/commands/run.ts";
import { validateCommand } from "./src/commands/validate.ts";
import { VERSION } from "./src/constants.ts";

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
  run       Execute test cases
  validate  Validate test definitions
  report    Generate test reports

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

For more information, see: home-modules/tools/sway-test/README.md
        `);
        break;

      default:
        console.error(`Unknown command: ${command}`);
        console.error("Run 'sway-test --help' for usage information");
        Deno.exit(1);
    }
  } catch (error) {
    console.error(`Fatal error: ${error.message}`);
    if (error.stack) {
      console.error(error.stack);
    }
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}
