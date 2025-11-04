#!/usr/bin/env -S deno run --allow-all
/**
 * i3pm - i3 Project Manager CLI
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Main entry point for the command-line interface
 */

import { parseArgs } from "@std/cli/parse-args";

const VERSION = "2.5.6"; // Updated for Feature 058 Python backend consolidation + comprehensive help

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
╔═══════════════════════════════════════════════════════════════════════════╗
║                      i3pm - i3 Project Manager CLI                        ║
║                           Version ${VERSION}                                    ║
╚═══════════════════════════════════════════════════════════════════════════╝

ARCHITECTURE:
    TypeScript CLI (thin client) → JSON-RPC → Python Daemon (backend)

    After Feature 058, the CLI handles UI/rendering while the Python daemon
    manages all backend operations (projects, layouts, file I/O, window state).

USAGE:
    i3pm [OPTIONS] <COMMAND> [ARGS...]

CORE COMMANDS:
    project     Project lifecycle management (via daemon)
                • create, list, show, current, switch, clear, update, delete
                • All operations execute via Python daemon with <10ms latency

    layout      Window layout save/restore (via daemon)
                • save, restore, list, delete
                • Direct i3ipc operations for 10-20x faster performance

    daemon      Daemon monitoring and event streaming
                • status    - Daemon health, uptime, tracked windows
                • events    - Real-time event stream with columnar output
                • ping      - Connection test
                • apps      - List registered applications via daemon

    windows     Window state visualization and monitoring
                • Default: Tree view (outputs → workspaces → windows)
                • --table   - Sortable table view with all properties
                • --live    - Interactive TUI with real-time updates
                • --json    - Machine-readable JSON output

CONFIGURATION:
    config      Sway configuration management (Feature 047)
                • show              - Display current configuration
                • conflicts         - Detect configuration conflicts
                • validate          - Syntax/semantic validation
                • rollback <hash>   - Rollback to previous version
                • versions          - List version history
                • edit <file>       - Edit keybindings/rules/assignments

    apps        Application registry queries (read-only)
                • list              - List all registered applications
                • show <name>       - Show detailed app information
                • --scope <global|scoped>    - Filter by scope
                • --workspace <num>          - Filter by workspace

    monitors    Multi-monitor workspace distribution (Feature 049)
                • status            - Show monitor config and workspace mapping

GLOBAL OPTIONS:
    -h, --help       Print help information
    -v, --version    Print version information
    -V, --verbose    Enable verbose output with detailed logging
    --json           Output as JSON (for scripting/automation)

COMMON WORKFLOWS:

    Project Management:
        i3pm project create nixos --dir /etc/nixos --display-name "NixOS Config"
        i3pm project switch nixos
        i3pm project current
        i3pm project list

    Layout Operations:
        i3pm layout save nixos          # Capture current window state
        i3pm layout restore nixos       # Restore windows to saved positions
        i3pm layout list                # Show all saved layouts

    Real-Time Monitoring:
        i3pm daemon events --follow                     # Columnar event stream
        i3pm daemon events --follow --type=window       # Filter by event type
        i3pm daemon events --limit=50                   # Recent 50 events
        i3pm windows --live                             # Interactive window TUI

    Debugging:
        i3pm daemon status              # Check daemon health
        i3pm daemon events --verbose    # Detailed multi-line events
        i3pm windows --json | jq        # Query window state
        i3pm config conflicts           # Find configuration issues

EXTERNAL COMMANDS:
    i3pm-diagnose       - Diagnostic tooling (Feature 039)
                          • health, window <id>, events, validate

    i3pm-workspace-mode - Workspace mode navigation (Feature 042)
                          • state, history, digit, execute, cancel

PERFORMANCE:
    • Layout operations: <50ms (10-20x faster than TypeScript)
    • Project CRUD: <10ms per operation
    • Event streaming: <100ms end-to-end latency
    • Daemon memory: ~28MB idle, ~35MB under load

For detailed command help:
    i3pm <COMMAND> --help

Examples:
    i3pm project --help
    i3pm daemon --help
    i3pm windows --help
`);
}

// Run main function and exit with status code
if (import.meta.main) {
  const exitCode = await main();
  Deno.exit(exitCode);
}
