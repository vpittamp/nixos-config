#!/usr/bin/env -S deno run --allow-net --allow-read=/run/user,/home --allow-env=XDG_RUNTIME_DIR,HOME,USER

/**
 * i3pm Deno CLI - Main Entry Point
 *
 * Description: i3 project management CLI tool
 */

import { parseArgs } from "@std/cli/parse-args";

// Read version from VERSION file at runtime
const VERSION = await Deno.readTextFile(
  new URL("./VERSION", import.meta.url)
).then(v => v.trim());

/**
 * Show version information
 */
function showVersion(): void {
  console.log(`i3pm ${VERSION}`);
  Deno.exit(0);
}

/**
 * Show main help text
 */
function showHelp(): void {
  console.log(`
i3pm ${VERSION} - i3 project management CLI tool

USAGE:
  i3pm [OPTIONS] <COMMAND>

GLOBAL OPTIONS:
  -h, --help       Show help information
  -v, --version    Show version information
  --verbose        Enable verbose logging
  --debug          Enable debug logging

COMMANDS:
  project          Project management commands
  scratchpad       Project-scoped scratchpad terminal management
  windows          Window state visualization
  daemon           Daemon status and event monitoring
  layout           Workspace layout persistence (save/restore)
  rules            Window classification rules
  monitors         Workspace-to-monitor mapping configuration
  monitor          Interactive monitoring dashboard
  app-classes      Application class management
  apps             Application registry management (Feature 034)

Run 'i3pm <command> --help' for more information on a specific command.

EXAMPLES:
  i3pm project list                    List all projects
  i3pm project switch nixos            Switch to nixos project
  i3pm scratchpad toggle               Toggle project terminal
  i3pm windows --live                  Live window visualization
  i3pm daemon status                   Show daemon status
  i3pm layout save my-layout           Save current workspace layout
  i3pm layout restore my-layout        Restore saved layout
  i3pm rules list                      List classification rules
  i3pm monitors config show            Show workspace distribution config
  i3pm monitors reassign               Redistribute workspaces
  i3pm monitor                         Launch monitoring dashboard
  i3pm apps list                       List all applications
  i3pm apps launch vscode              Launch VS Code with project context

For detailed documentation, see:
  /etc/nixos/specs/027-update-the-spec/quickstart.md
`);
  Deno.exit(0);
}

/**
 * Show command not found error
 */
function showCommandNotFound(command: string): never {
  console.error(`Error: Unknown command '${command}'`);
  console.error("");
  console.error("Run 'i3pm --help' to see available commands");
  Deno.exit(1);
}

/**
 * Main CLI entry point
 */
async function main(): Promise<void> {
  const args = parseArgs(Deno.args, {
    boolean: ["help", "version", "verbose", "debug"],
    alias: {
      h: "help",
      v: "version",
    },
    stopEarly: true,
  });

  // Handle global flags
  if (args.version) {
    showVersion();
  }

  if (args.help || args._.length === 0) {
    showHelp();
  }

  // Initialize logging
  const { enableVerbose, enableDebug } = await import("./src/utils/logger.ts");
  if (args.debug) {
    enableDebug();
  } else if (args.verbose) {
    enableVerbose();
  }

  // Get command
  const command = String(args._[0]);
  const commandArgs = args._.slice(1);

  // Route to command handler
  switch (command) {
    case "project":
      {
        const { projectCommand } = await import("./src/commands/project.ts");
        await projectCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "scratchpad":
      {
        const { scratchpadCommand } = await import("./src/commands/scratchpad.ts");
        await scratchpadCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "windows":
      {
        const { windowsCommand } = await import("./src/commands/windows.ts");
        await windowsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "daemon":
      {
        const { daemonCommand } = await import("./src/commands/daemon.ts");
        await daemonCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "layout":
      {
        const { layoutCommand } = await import("./src/commands/layout.ts");
        await layoutCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "rules":
      {
        const { rulesCommand } = await import("./src/commands/rules.ts");
        await rulesCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "monitors":
      {
        const { monitorsCommand } = await import("./src/commands/monitors.ts");
        await monitorsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "monitor":
      {
        const { monitorCommand } = await import("./src/commands/monitor.ts");
        await monitorCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "app-classes":
      {
        const { appClassesCommand } = await import("./src/commands/app-classes.ts");
        await appClassesCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "apps":
      {
        const { appsCommand } = await import("./src/commands/apps.ts");
        await appsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    default:
      showCommandNotFound(command);
  }
}

// Run main
if (import.meta.main) {
  try {
    await main();
  } catch (err) {
    console.error("Fatal error:", err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  }
}
