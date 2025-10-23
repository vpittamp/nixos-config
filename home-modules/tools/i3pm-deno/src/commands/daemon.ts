/**
 * Daemon Status and Event Monitoring Commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { DaemonStatusSchema, EventNotificationSchema } from "../validation.ts";
import type { DaemonStatus, EventNotification } from "../models.ts";
import { z } from "zod";
import { setup, Spinner } from "@cli-ux";

interface DaemonCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

// Initialize CLI-UX formatter for semantic colors
const { formatter } = setup();

function showHelp(): void {
  console.log(`
i3pm daemon - Daemon status and event monitoring

USAGE:
  i3pm daemon <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  status            Show daemon status
  events            Show recent events

OPTIONS:
  -h, --help        Show this help message

STATUS OPTIONS:
  No additional options

EVENTS OPTIONS:
  --limit <n>       Number of events to show (default: 20, ignored with --follow)
  --type <type>     Filter by event type (window, workspace, output, tick)
  --since-id <id>   Show events since specific event ID
  --follow, -f      Follow event stream in real-time (like tail -f)

EXAMPLES:
  i3pm daemon events
  i3pm daemon events --limit=50
  i3pm daemon events --type=window
  i3pm daemon events --since-id=1500
  i3pm daemon events --follow              # Live event stream
  i3pm daemon events -f --type=window      # Follow only window events
`);
  Deno.exit(0);
}

/**
 * Format uptime in human-readable format
 */
function formatUptime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  } else {
    return `${secs}s`;
  }
}

/**
 * Format timestamp as human-readable date/time
 */
function formatTimestamp(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleString();
}

/**
 * T028: Implement `i3pm daemon status` command
 */
async function statusCommand(
  client: DaemonClient,
  options: DaemonCommandOptions,
): Promise<void> {
  const spinner = new Spinner({ message: "Fetching daemon status...", showAfter: 0 });
  spinner.start();

  try {
    const response = await client.request("get_status");
    spinner.stop();

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const status = DaemonStatusSchema.parse(response) as DaemonStatus;

    // Format and display status with colors
    console.log(formatter.bold("\nDaemon Status:"));
    console.log(formatter.dim("─".repeat(60)));

    // Status with color coding
    const statusText = status.status === "running"
      ? formatter.success("running")
      : formatter.error(status.status);
    console.log(`  Status:           ${statusText}`);

    // Connected status
    const connectedText = status.connected
      ? formatter.success("yes")
      : formatter.error("no");
    console.log(`  Connected to i3:  ${connectedText}`);

    console.log(`  Uptime:           ${formatter.dim(formatUptime(status.uptime))}`);

    // Active project
    const projectText = status.active_project
      ? formatter.bold(status.active_project)
      : formatter.dim("Global (no project)");
    console.log(`  Active Project:   ${projectText}`);

    console.log(`  Windows:          ${status.window_count}`);
    console.log(`  Workspaces:       ${status.workspace_count}`);
    console.log(`  Events Processed: ${formatter.dim(status.event_count.toString())}`);

    // Errors with warning color if > 0
    const errorText = status.error_count > 0
      ? formatter.warning(status.error_count.toString())
      : formatter.dim("0");
    console.log(`  Errors:           ${errorText}`);

    console.log(`  Version:          ${formatter.dim(status.version)}`);
    console.log(`  Socket:           ${formatter.dim(status.socket_path)}`);
    console.log(formatter.dim("─".repeat(60)));
  } catch (err) {
    spinner.stop();

    if (err instanceof z.ZodError) {
      console.error(formatter.error("Invalid daemon response format"));
      if (options.debug) {
        console.error(formatter.dim("Validation errors:"), err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T029: Implement `i3pm daemon events` command
 */
async function eventsCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: DaemonCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["limit", "type", "since-id"],
    boolean: ["follow"],
    alias: { f: "follow" },
    default: { limit: "20" },
  });

  // Parse parameters
  const limit = parseInt(parsed.limit as string, 10);
  const eventType = parsed.type as string | undefined;
  const sinceId = parsed["since-id"]
    ? parseInt(parsed["since-id"] as string, 10)
    : undefined;
  const follow = parsed.follow as boolean;

  try {
    // If follow mode only, skip historical events
    if (follow && sinceId === undefined) {
      console.log("Following event stream... (Press Ctrl+C to exit)");
      console.log("─".repeat(80));
      await followEventStream(client, eventType, options);
      return;
    }

    // Fetch historical events
    const params: {
      limit?: number;
      event_type?: string;
      since_id?: number;
    } = { limit };

    if (eventType) {
      params.event_type = eventType;
    }
    if (sinceId !== undefined) {
      params.since_id = sinceId;
    }

    const response = await client.request("get_events", params);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const EventArraySchema = z.array(EventNotificationSchema);
    const events = EventArraySchema.parse(response) as EventNotification[];

    if (events.length === 0) {
      console.log("\nNo events found");
      if (sinceId !== undefined) {
        console.log(`(No events since ID ${sinceId})`);
      }
      return;
    }

    // Display events in reverse chronological order (newest first)
    console.log(`\nRecent Events (${events.length} shown):`);
    console.log("─".repeat(80));

    for (const event of events.reverse()) {
      const timestamp = formatTimestamp(event.timestamp);
      const eventType = event.event_type;
      const change = event.change;

      // Format container info
      let containerInfo = "";
      if (event.container) {
        const container = event.container as {
          class?: string;
          title?: string;
          name?: string;
        };
        if (container.class && container.title) {
          // Window event
          containerInfo = `${container.class} (${container.title})`;
        } else if (container.name) {
          // Workspace or output event
          containerInfo = container.name;
        }
      }

      console.log(
        `[${event.event_id}] ${timestamp} - ${eventType}:${change}${
          containerInfo ? " - " + containerInfo : ""
        }`,
      );
    }

    console.log("─".repeat(80));

    // Show event ID range
    const firstId = events[0].event_id;
    const lastId = events[events.length - 1].event_id;
    console.log(`Event ID range: ${firstId} to ${lastId}`);
    console.log(`Total events shown: ${events.length}`);

    // If follow mode, continue streaming
    if (follow) {
      console.log("");
      console.log("Following event stream... (Press Ctrl+C to exit)");
      console.log("─".repeat(80));

      await followEventStream(client, eventType, options);
    }
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error("Error: Invalid daemon response format");
      if (options.debug) {
        console.error("Validation errors:", err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * Follow event stream in real-time
 */
async function followEventStream(
  client: DaemonClient,
  eventTypeFilter: string | undefined,
  options: DaemonCommandOptions,
): Promise<void> {
  // Setup Ctrl+C handler
  let running = true;
  const sigintHandler = () => {
    running = false;
    console.log("\n\nStopped following events");
  };
  Deno.addSignalListener("SIGINT", sigintHandler);

  try {
    // Subscribe to events
    const eventTypes = eventTypeFilter ? [eventTypeFilter] : ["window", "workspace", "output", "tick"];

    await client.subscribe(eventTypes, async (notification) => {
      if (!running) return;

      // Parse event from notification
      const params = notification.params as {
        event?: EventNotification;
        type?: string;
        event_type?: string;
        change?: string;
        container?: unknown;
        timestamp?: number;
        event_id?: number;
      };

      let event: EventNotification;

      if (params.event) {
        // Full event notification
        event = params.event;
      } else {
        // Construct event from notification params
        const eventType = params.type || params.event_type || "unknown";
        event = {
          event_id: params.event_id || Date.now(),
          event_type: eventType as any,
          change: params.change || notification.method || "unknown",
          container: params.container || null,
          timestamp: params.timestamp || Date.now(),
        };
      }

      // Filter by event type if specified
      if (eventTypeFilter && event.event_type !== eventTypeFilter) {
        return;
      }

      // Format and display event
      const timestamp = formatTimestamp(event.timestamp);
      const eventType = event.event_type;
      const change = event.change;

      // Format container info
      let containerInfo = "";
      if (event.container) {
        const container = event.container as {
          class?: string;
          title?: string;
          name?: string;
        };
        if (container.class && container.title) {
          containerInfo = `${container.class} (${container.title})`;
        } else if (container.name) {
          containerInfo = container.name;
        }
      }

      console.log(
        `[${event.event_id}] ${timestamp} - ${eventType}:${change}${
          containerInfo ? " - " + containerInfo : ""
        }`,
      );
    });

    // Keep running until Ctrl+C
    while (running) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  } finally {
    // Cleanup signal handler
    Deno.removeSignalListener("SIGINT", sigintHandler);
  }
}

/**
 * Daemon command router
 */
export async function daemonCommand(
  args: (string | number)[],
  options: DaemonCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = parsed._[0] as string;
  const subcommandArgs = parsed._.slice(1);

  // Connect to daemon
  const client = new DaemonClient();

  try {
    await client.connect();

    if (options.verbose) {
      console.error("Connected to daemon");
    }

    // Route to subcommand
    switch (subcommand) {
      case "status":
        await statusCommand(client, options);
        break;

      case "events":
        await eventsCommand(client, subcommandArgs, options);
        break;

      default:
        console.error(`Unknown subcommand: ${subcommand}`);
        console.error('Run "i3pm daemon --help" for usage information');
        Deno.exit(1);
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error: ${err.message}`);

      if (err.message.includes("Failed to connect")) {
        console.error("\nThe daemon is not running. Start it with:");
        console.error("  systemctl --user start i3-project-event-listener");
      }
    } else {
      console.error("Error:", err);
    }

    Deno.exit(1);
  } finally {
    client.close();
  }
}
