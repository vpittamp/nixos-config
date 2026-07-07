#!/usr/bin/env -S deno run --allow-net --allow-run=tmux --allow-read=/run/user,/home,/etc/nixos --allow-write=/home,/etc/nixos --allow-env=XDG_RUNTIME_DIR,HOME,USER,FLAKE_ROOT,NH_FLAKE,NH_OS_FLAKE,I3PM_CONFIG_ROOT

/**
 * i3pm Deno CLI - Main Entry Point
 *
 * Description: i3 project management CLI tool
 */

import { parseArgs } from "@std/cli/parse-args";

// Read version from VERSION file at runtime
const VERSION = await Deno.readTextFile(
  new URL("./VERSION", import.meta.url),
).then((v) => v.trim());

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
  context          Active runtime context commands
  launch           Daemon-owned application launch commands
  session          AI session inspection commands
  herdr-proxy      Host-local Herdr proxy for remote dashboard aggregation
  quickshell       QuickShell runtime preflight checks
  post-rebuild     Combined local post-rebuild smoke checks
  window           Daemon-owned window focus/action commands
  workspace        Daemon-owned workspace focus commands
  dashboard        Dashboard snapshot and watch commands
  health           Runtime health and convergence checks
  perf             Runtime latency smoke checks
  display          Display layout snapshot/apply/cycle commands
  run              Smart application launcher with run-raise-hide (Feature 051)
  windows          Window state visualization
  daemon           Daemon status and event monitoring
  tree-monitor     Real-time window state event monitoring (Feature 065)
  trace            Window tracing for debugging (Feature 101)
  rules            Window classification rules
  monitors         Workspace-to-monitor mapping configuration
  monitor          Interactive monitoring dashboard
  apps             Application registry management (Feature 034)

Run 'i3pm <command> --help' for more information on a specific command.

EXAMPLES:
  i3pm context current                 Show active runtime context
  i3pm launch open terminal           Launch an app through the daemon
  i3pm session list --json            Inspect daemon AI session rows
  i3pm herdr-proxy focus <pane_id> --json
  i3pm herdr-proxy snapshot --json    Emit local Herdr proxy snapshot
  i3pm herdr-proxy events --jsonl     Stream typed Herdr proxy events
  i3pm quickshell preflight --json    Check QuickShell source and loader state
  i3pm post-rebuild smoke --json      Run health, perf, and QuickShell preflight
  i3pm window focus <window_id>       Focus a managed window
  i3pm workspace focus 2              Focus a workspace
  i3pm dashboard snapshot             Show dashboard state
  i3pm health                         Validate local runtime convergence
  i3pm perf smoke --json              Validate focus/dashboard latency budgets
  i3pm display snapshot               Show display layout state
  i3pm run firefox                     Toggle Firefox (launch/focus/summon)
  i3pm run alacritty --hide            Toggle terminal visibility
  i3pm windows --live                  Live window visualization
  i3pm daemon status                   Show daemon status
  i3pm rules list                      List classification rules
  i3pm monitors config show            Show workspace distribution config
  i3pm monitors reassign               Redistribute workspaces
  i3pm monitor                         Launch monitoring dashboard
  i3pm apps list                       List all applications
  i3pm launch open code               Launch VS Code
  i3pm trace start --class ghostty     Start tracing Ghostty windows
  i3pm trace list                      List active traces

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
  const commandArgs = args._.slice(1).map(String);

  // Route to command handler
  switch (command) {
    case "context":
      {
        const { contextCommand } = await import("./commands/context.ts");
        const exitCode = await contextCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "launch":
      {
        const { launchCommand } = await import("./commands/launch.ts");
        const exitCode = await launchCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "session":
      {
        const { sessionCommand } = await import("./commands/session.ts");
        const exitCode = await sessionCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "herdr-proxy":
      {
        const { herdrProxyCommand } = await import("./commands/herdr-proxy.ts");
        const exitCode = await herdrProxyCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "quickshell":
      {
        const { quickshellCommand } = await import("./commands/quickshell.ts");
        const exitCode = await quickshellCommand(commandArgs);
        Deno.exit(exitCode);
      }
      break;

    case "post-rebuild":
      {
        const { postRebuildCommand } = await import("./commands/post-rebuild.ts");
        const exitCode = await postRebuildCommand(commandArgs);
        Deno.exit(exitCode);
      }
      break;

    case "window":
      {
        const { windowCommand } = await import("./commands/window.ts");
        const exitCode = await windowCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "workspace":
      {
        const { workspaceCommand } = await import("./commands/workspace.ts");
        const exitCode = await workspaceCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "dashboard":
      {
        const { dashboardCommand } = await import("./commands/dashboard.ts");
        const exitCode = await dashboardCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "health":
      {
        const { healthCommand } = await import("./commands/health.ts");
        const exitCode = await healthCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "perf":
      {
        const { perfCommand } = await import("./commands/perf.ts");
        const exitCode = await perfCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "display":
      {
        const { displayCommand } = await import("./commands/display.ts");
        const exitCode = await displayCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "run":
      {
        const { runCommand } = await import("./commands/run.ts");
        await runCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "windows":
      {
        const { windowsCommand } = await import("./commands/windows.ts");
        const exitCode = await windowsCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "daemon":
      {
        const { daemonCommand } = await import("./commands/daemon.ts");
        const exitCode = await daemonCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
      }
      break;

    case "tree-monitor":
      {
        const { treeMonitorCommand } = await import("./commands/tree-monitor.ts");
        await treeMonitorCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
      }
      break;

    case "trace":
      {
        const { traceCommand } = await import("./commands/trace.ts");
        const exitCode = await traceCommand(commandArgs.map(String));
        Deno.exit(exitCode);
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

    case "apps":
      {
        const { appsCommand } = await import("./commands/apps.ts");
        const exitCode = await appsCommand(commandArgs, {
          verbose: args.verbose,
          debug: args.debug,
        });
        Deno.exit(exitCode);
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
