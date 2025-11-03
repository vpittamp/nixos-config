#!/usr/bin/env -S deno run --allow-all
/**
 * i3pm - i3 Project Manager CLI
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Main entry point for the command-line interface
 */

import { parseArgs } from "@std/cli/parse-args";

const VERSION = "2.1.0";

/**
 * Main CLI router
 */
async function main(): Promise<number> {
  const args = parseArgs(Deno.args, {
    boolean: ["help", "version", "json", "verbose", "dry-run", "overwrite", "force", "follow", "sources", "table", "tree", "live", "hidden", "legend"],
    string: ["directory", "dir", "display-name", "display", "icon", "scope", "workspace", "limit", "type", "output", "category", "project", "window", "since"],
    alias: {
      h: "help",
      v: "version",
      V: "verbose",
      d: "directory",
      n: "display-name",
      f: "follow",
    },
  });

  // Global flags
  if (args.version) {
    console.log(`i3pm version ${VERSION}`);
    return 0;
  }

  if (args.help || args._.length === 0) {
    printHelp();
    return 0;
  }

  // Extract command and subcommand
  const [command, ...rest] = args._;
  const commandStr = String(command);
  const restArgs = rest.map(String); // Convert to string[] from (string | number)[]

  try {
    switch (commandStr) {
      case "apps":
        const { appsCommand } = await import("./commands/apps.ts");
        return await appsCommand(restArgs, args);

      case "project":
        const { projectCommand } = await import("./commands/project.ts");
        return await projectCommand(restArgs, args);

      case "layout":
        const { layoutCommand } = await import("./commands/layout.ts");
        return await layoutCommand(restArgs, args);

      case "windows":
        const { windowsCommand } = await import("./commands/windows.ts");
        return await windowsCommand(restArgs, args);

      case "daemon":
        const { daemonCommand } = await import("./commands/daemon.ts");
        return await daemonCommand(restArgs, args);

      case "config":
        const { configCommand } = await import("./commands/config.ts");
        return await configCommand(restArgs, args);

      case "monitors":
        const { monitorsCommand } = await import("./commands/monitors.ts");
        return await monitorsCommand(restArgs, args);

      case "events":
        const { eventsCommand } = await import("./commands/events.ts");
        return await eventsCommand(restArgs, args);

      default:
        console.error(`Unknown command: ${commandStr}`);
        console.error("Run 'i3pm --help' for usage information");
        return 1;
    }
  } catch (error) {
    if (args.verbose) {
      console.error("Error:", error);
    } else {
      console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    }
    return 1;
  }
}

/**
 * Print help message
 */
function printHelp(): void {
  console.log(`
i3pm - i3 Project Manager
Version ${VERSION}

USAGE:
    i3pm [OPTIONS] <COMMAND>

COMMANDS:
    apps        List and query registry applications
    project     Manage projects (create, list, switch, etc.)
    layout      Save and restore window layouts
    windows     View and monitor window state
    daemon      Query daemon status and events
    events      Monitor events with rich formatting (Feature 053 Phase 6)
    config      Manage Sway configuration (show, conflicts)
    monitors    View monitor status and workspace distribution (Feature 049)

OPTIONS:
    -h, --help       Print help information
    -v, --version    Print version information
    -V, --verbose    Enable verbose output
    --json           Output as JSON

EXAMPLES:
    # List all registry applications
    i3pm apps list

    # Create a new project
    i3pm project create nixos --directory /etc/nixos --display-name "NixOS Config"

    # Switch to a project
    i3pm project switch nixos

    # Save current window layout
    i3pm layout save nixos

    # Restore layout
    i3pm layout restore nixos

    # Monitor windows in real-time
    i3pm windows --live

    # Check daemon status
    i3pm daemon status

    # Monitor events in real-time (Feature 053)
    i3pm events --follow --verbose

    # View recent workspace assignments
    i3pm events --type workspace::assignment --limit 10

    # Show current configuration
    i3pm config show

    # Check for configuration conflicts
    i3pm config conflicts

For more information on a specific command, run:
    i3pm <COMMAND> --help
`);
}

// Run main function and exit with status code
if (import.meta.main) {
  const exitCode = await main();
  Deno.exit(exitCode);
}
