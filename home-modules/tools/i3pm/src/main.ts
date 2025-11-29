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
  worktree         Git worktree project management (Feature 077)
  run              Smart application launcher with run-raise-hide (Feature 051)
  scratchpad       Project-scoped scratchpad terminal management
  windows          Window state visualization
  daemon           Daemon status and event monitoring
  tree-monitor     Real-time window state event monitoring (Feature 065)
  layout           Workspace layout persistence (save/restore)
  rules            Window classification rules
  monitors         Workspace-to-monitor mapping configuration
  monitor          Interactive monitoring dashboard
  app-classes      Application class management
  apps             Application registry management (Feature 034)
  account          GitHub account configuration (Feature 100)
  clone            Clone repository with bare setup (Feature 100)
  discover         Discover bare repositories and worktrees (Feature 100)
  repo             Repository management commands (Feature 100)

Run 'i3pm <command> --help' for more information on a specific command.

EXAMPLES:
  i3pm project list                    List all projects
  i3pm project switch nixos            Switch to nixos project
  i3pm run firefox                     Toggle Firefox (launch/focus/summon)
  i3pm run alacritty --hide            Toggle terminal visibility
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
  const { enableVerbose, enableDebug } = await import("./utils/logger.ts");
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
        const { projectCommand } = await import("./commands/project.ts");
        await projectCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "worktree":
      {
        const { worktreeCommand } = await import("./commands/worktree.ts");
        await worktreeCommand(commandArgs.map(String));
      }
      break;

    case "run":
      {
        const { runCommand } = await import("./commands/run.ts");
        await runCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "scratchpad":
      {
        const { scratchpadCommand } = await import("./commands/scratchpad.ts");
        await scratchpadCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "windows":
      {
        const { windowsCommand } = await import("./commands/windows.ts");
        await windowsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "daemon":
      {
        const { daemonCommand } = await import("./commands/daemon.ts");
        await daemonCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "tree-monitor":
      {
        const { treeMonitorCommand } = await import("./commands/tree-monitor.ts");
        await treeMonitorCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "layout":
      {
        const { layoutCommand } = await import("./commands/layout.ts");
        await layoutCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "rules":
      {
        const { rulesCommand } = await import("./commands/rules.ts");
        await rulesCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "monitors":
      {
        const { monitorsCommand } = await import("./commands/monitors.ts");
        await monitorsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "monitor":
      {
        const { monitorCommand } = await import("./commands/monitor.ts");
        await monitorCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "app-classes":
      {
        const { appClassesCommand } = await import("./commands/app-classes.ts");
        await appClassesCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "apps":
      {
        const { appsCommand } = await import("./commands/apps.ts");
        await appsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    // Feature 100: Structured Git Repository Management
    case "account":
      {
        const subcommand = String(commandArgs[0] || "");
        const subArgs = commandArgs.slice(1).map(String);
        if (subcommand === "add") {
          const { accountAdd } = await import("./commands/account/add.ts");
          const exitCode = await accountAdd(subArgs);
          Deno.exit(exitCode);
        } else if (subcommand === "list") {
          const { accountList } = await import("./commands/account/list.ts");
          const exitCode = await accountList(subArgs);
          Deno.exit(exitCode);
        } else {
          console.error(`Unknown account subcommand: ${subcommand}`);
          console.error("Available subcommands: add, list");
          Deno.exit(1);
        }
      }
      break;

    case "clone":
      {
        const { clone } = await import("./commands/clone/index.ts");
        const exitCode = await clone(commandArgs.map(String));
        Deno.exit(exitCode);
      }
      break;

    case "discover":
      {
        const { discover } = await import("./commands/discover/index.ts");
        const exitCode = await discover(commandArgs.map(String));
        Deno.exit(exitCode);
      }
      break;

    case "repo":
      {
        const subcommand = String(commandArgs[0] || "");
        const subArgs = commandArgs.slice(1).map(String);
        if (subcommand === "list") {
          const { repoList } = await import("./commands/repo/list.ts");
          const exitCode = await repoList(subArgs);
          Deno.exit(exitCode);
        } else if (subcommand === "get") {
          const { repoGet } = await import("./commands/repo/get.ts");
          const exitCode = await repoGet(subArgs);
          Deno.exit(exitCode);
        } else {
          console.error(`Unknown repo subcommand: ${subcommand}`);
          console.error("Available subcommands: list, get");
          Deno.exit(1);
        }
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
    // Don't force exit here - let commands handle their own exit strategy
    // Live/interactive commands need to exit naturally
  } catch (err) {
    console.error("Fatal error:", err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  }
}
