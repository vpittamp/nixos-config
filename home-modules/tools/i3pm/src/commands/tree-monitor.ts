/**
 * Tree Monitor Command Handler
 *
 * Main entry point for `i3pm tree-monitor` command.
 * Routes to subcommands: live, history, inspect, stats
 *
 * Based on Feature 065 spec.md and plan.md.
 */

import { parseArgs } from "@std/cli/parse-args";

/**
 * Command options
 */
interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

/**
 * Get default socket path from XDG_RUNTIME_DIR
 */
function getDefaultSocketPath(): string {
  const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR");
  if (!runtimeDir) {
    throw new Error("XDG_RUNTIME_DIR environment variable not set");
  }
  return `${runtimeDir}/sway-tree-monitor.sock`;
}

/**
 * Show help text for tree-monitor command
 */
function showHelp(): void {
  console.log(`
i3pm tree-monitor - Real-time window state event monitoring

USAGE:
  i3pm tree-monitor <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  live             Real-time event streaming (full-screen TUI)
  history          Query historical events
  inspect          Inspect detailed event information
  stats            Show daemon performance statistics

OPTIONS:
  -h, --help       Show help information
  --socket-path    Custom daemon socket path (default: $XDG_RUNTIME_DIR/sway-tree-monitor.sock)

EXAMPLES:
  # Real-time event streaming
  i3pm tree-monitor live

  # Query last 10 events
  i3pm tree-monitor history --last 10

  # Events from last 5 minutes
  i3pm tree-monitor history --since 5m

  # Filter by event type
  i3pm tree-monitor history --filter window::new

  # Inspect specific event
  i3pm tree-monitor inspect 550e8400-e29b-41d4-a716-446655440000

  # Show daemon statistics
  i3pm tree-monitor stats

  # Watch mode (refresh every 5 seconds)
  i3pm tree-monitor stats --watch

  # JSON output for scripting
  i3pm tree-monitor history --last 50 --json
  i3pm tree-monitor stats --json

For detailed documentation, see:
  /etc/nixos/specs/065-i3pm-tree-monitor/quickstart.md
`);
}

/**
 * Show subcommand help
 */
function showSubcommandHelp(subcommand: string): void {
  switch (subcommand) {
    case "live":
      console.log(`
i3pm tree-monitor live - Real-time event streaming

USAGE:
  i3pm tree-monitor live [OPTIONS]

OPTIONS:
  --socket-path PATH    Custom daemon socket path

DESCRIPTION:
  Displays a full-screen terminal interface showing window/workspace state changes
  as they happen. Events appear within 100ms of actual window operations.

KEYBOARD SHORTCUTS:
  q         Quit and return to shell
  ↑ / ↓     Navigate events
  Enter     Inspect event details
  r         Refresh display

EXAMPLES:
  i3pm tree-monitor live
  i3pm tree-monitor live --socket-path /custom/path/monitor.sock
`);
      break;

    case "history":
      console.log(`
i3pm tree-monitor history - Query historical events

USAGE:
  i3pm tree-monitor history [OPTIONS]

OPTIONS:
  --last N              Return last N events (max 500)
  --since TIME          Return events since timestamp (5m, 1h, 30s, 2d, or ISO 8601)
  --until TIME          Return events until timestamp (ISO 8601)
  --filter TYPE         Filter by event type (exact or prefix match)
  --json                Output as JSON array
  --socket-path PATH    Custom daemon socket path

TIME FORMATS:
  5m     5 minutes ago
  1h     1 hour ago
  30s    30 seconds ago
  2d     2 days ago

EVENT TYPE FILTERS:
  window::new       Exact match (only "window::new" events)
  window::          Prefix match (all window events)
  workspace::focus  Exact match
  workspace::       Prefix match (all workspace events)

EXAMPLES:
  i3pm tree-monitor history --last 10
  i3pm tree-monitor history --since 5m
  i3pm tree-monitor history --filter window::new
  i3pm tree-monitor history --since 1h --filter workspace::
  i3pm tree-monitor history --last 50 --json
`);
      break;

    case "inspect":
      console.log(`
i3pm tree-monitor inspect - Inspect detailed event information

USAGE:
  i3pm tree-monitor inspect <EVENT_ID> [OPTIONS]

OPTIONS:
  --json                Output as JSON object
  --socket-path PATH    Custom daemon socket path

DESCRIPTION:
  Shows detailed information for a specific event including:
  - Event metadata (ID, timestamp, type, significance)
  - User action correlation (if available)
  - Field-level changes (diff)
  - I3PM enrichment (PID, environment variables, marks)

KEYBOARD SHORTCUTS:
  b         Back to previous view
  q         Quit

EXAMPLES:
  i3pm tree-monitor inspect 550e8400-e29b-41d4-a716-446655440000
  i3pm tree-monitor inspect <id> --json
`);
      break;

    case "stats":
      console.log(`
i3pm tree-monitor stats - Show daemon performance statistics

USAGE:
  i3pm tree-monitor stats [OPTIONS]

OPTIONS:
  --watch               Refresh every 5 seconds
  --json                Output as JSON object
  --socket-path PATH    Custom daemon socket path

DESCRIPTION:
  Displays daemon health metrics:
  - Memory usage (MB)
  - CPU percentage
  - Event buffer utilization
  - Event distribution by type
  - Diff computation performance

EXAMPLES:
  i3pm tree-monitor stats
  i3pm tree-monitor stats --watch
  i3pm tree-monitor stats --json
`);
      break;

    default:
      console.error(`Unknown subcommand: ${subcommand}`);
      console.error("Run 'i3pm tree-monitor --help' for available subcommands");
      Deno.exit(1);
  }
}

/**
 * Main tree-monitor command handler
 */
export async function treeMonitorCommand(
  cmdArgs: (string | number)[],
  _options: CommandOptions = {},
): Promise<void> {
  const args = parseArgs(cmdArgs.map(String), {
    boolean: ["help", "json", "watch"],
    string: ["socket-path", "filter", "since", "until"],
    alias: {
      h: "help",
    },
    stopEarly: false,
  });

  // Show help if no subcommand or --help
  if (args.help || args._.length === 0) {
    showHelp();
    return;
  }

  // Get subcommand
  const subcommand = String(args._[0]);

  // Show subcommand help if requested
  if (args.help) {
    showSubcommandHelp(subcommand);
    return;
  }

  // Route to subcommand handlers
  switch (subcommand) {
    case "live":
      {
        const { runLiveTUI } = await import("../ui/tree-monitor-live.ts");
        const socketPath = String(args["socket-path"] || getDefaultSocketPath());
        await runLiveTUI(socketPath);
      }
      break;

    case "history":
      {
        const { TreeMonitorClient } = await import("../services/tree-monitor-client.ts");
        const { displayEvents } = await import("../ui/tree-monitor-table.ts");
        const { parseTimeToISO } = await import("../utils/time-parser.ts");
        const { validateEventTypeFilter } = await import("../models/tree-monitor.ts");

        const socketPath = String(args["socket-path"] || getDefaultSocketPath());
        const client = new TreeMonitorClient(socketPath);

        try {
          await client.connect();

          // Build query params
          const params: Record<string, string | number> = {};

          if (args.last) {
            params.last = Number(args.last);
            if (isNaN(params.last) || params.last < 1 || params.last > 500) {
              console.error("Error: --last must be a number between 1 and 500");
              Deno.exit(1);
            }
          }

          if (args.since) {
            try {
              params.since = parseTimeToISO(String(args.since));
            } catch (err) {
              console.error(`Error parsing --since: ${err instanceof Error ? err.message : String(err)}`);
              Deno.exit(1);
            }
          }

          if (args.until) {
            params.until = String(args.until);
          }

          if (args.filter) {
            const filter = String(args.filter);
            if (!validateEventTypeFilter(filter)) {
              console.error(`Error: Invalid event type filter "${filter}"`);
              console.error("Use format: window::new, window::, workspace::focus, etc.");
              Deno.exit(1);
            }
            params.event_type = filter;
          }

          // Query events
          const response = await client.queryEvents(params);

          // Display results
          displayEvents(response || [], Boolean(args.json));
        } catch (err) {
          console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
          Deno.exit(1);
        }
      }
      break;

    case "inspect":
      {
        const { TreeMonitorClient } = await import("../services/tree-monitor-client.ts");
        const { displayEventDetail } = await import("../ui/tree-monitor-detail.ts");

        // Get event ID from args
        if (args._.length < 2) {
          console.error("Error: Missing event ID");
          console.error("Usage: i3pm tree-monitor inspect <EVENT_ID>");
          Deno.exit(1);
        }

        const eventId = String(args._[1]);
        const socketPath = String(args["socket-path"] || getDefaultSocketPath());
        const client = new TreeMonitorClient(socketPath);

        try {
          await client.connect();

          // Get event details
          const event = await client.getEvent(eventId);

          // Display event
          displayEventDetail(event, Boolean(args.json));
        } catch (err) {
          console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
          Deno.exit(1);
        }
      }
      break;

    case "stats":
      {
        const { TreeMonitorClient } = await import("../services/tree-monitor-client.ts");
        const { displayStats } = await import("../ui/tree-monitor-stats.ts");

        const socketPath = String(args["socket-path"] || getDefaultSocketPath());
        const client = new TreeMonitorClient(socketPath);
        const watchMode = Boolean(args.watch);

        try {
          await client.connect();

          // Watch mode: refresh every 5 seconds
          if (watchMode) {
            let running = true;

            // Handle Ctrl+C
            const signalHandler = () => {
              running = false;
            };
            Deno.addSignalListener("SIGINT", signalHandler);

            while (running) {
              // Clear screen
              console.clear();

              // Get and display stats
              const stats = await client.getStatistics();
              displayStats(stats, Boolean(args.json));

              // Wait 5 seconds
              await new Promise((resolve) => setTimeout(resolve, 5000));
            }

            Deno.removeSignalListener("SIGINT", signalHandler);
          } else {
            // One-shot mode
            const stats = await client.getStatistics();
            displayStats(stats, Boolean(args.json));
          }
        } catch (err) {
          console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
          Deno.exit(1);
        }
      }
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error("Available subcommands: live, history, inspect, stats");
      console.error("Run 'i3pm tree-monitor --help' for more information");
      Deno.exit(1);
  }
}
