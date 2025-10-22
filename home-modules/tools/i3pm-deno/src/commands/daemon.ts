/**
 * Daemon Status and Event Monitoring Commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { DaemonStatusSchema, EventNotificationSchema } from "../validation.ts";
import type { DaemonStatus, EventNotification } from "../models.ts";
import { z } from "zod";

interface DaemonCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

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
  --limit <n>       Number of events to show (default: 20)
  --type <type>     Filter by event type (window, workspace, output, tick)
  --since-id <id>   Show events since specific event ID

EXAMPLES:
  i3pm daemon status
  i3pm daemon events
  i3pm daemon events --limit=50
  i3pm daemon events --type=window
  i3pm daemon events --since-id=1500
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
  try {
    const response = await client.request("get_status");

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const status = DaemonStatusSchema.parse(response) as DaemonStatus;

    // Format and display status
    console.log("\nDaemon Status:");
    console.log("─".repeat(60));
    console.log(`  Status:           ${status.status}`);
    console.log(`  Connected to i3:  ${status.connected ? "yes" : "no"}`);
    console.log(`  Uptime:           ${formatUptime(status.uptime)}`);
    console.log(
      `  Active Project:   ${status.active_project || "Global (no project)"}`,
    );
    console.log(`  Windows:          ${status.window_count}`);
    console.log(`  Workspaces:       ${status.workspace_count}`);
    console.log(`  Events Processed: ${status.event_count}`);
    console.log(`  Errors:           ${status.error_count}`);
    console.log(`  Version:          ${status.version}`);
    console.log(`  Socket:           ${status.socket_path}`);
    console.log("─".repeat(60));
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
 * T029: Implement `i3pm daemon events` command
 */
async function eventsCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: DaemonCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["limit", "type", "since-id"],
    default: { limit: "20" },
  });

  // Parse parameters
  const limit = parseInt(parsed.limit as string, 10);
  const eventType = parsed.type as string | undefined;
  const sinceId = parsed["since-id"]
    ? parseInt(parsed["since-id"] as string, 10)
    : undefined;

  try {
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
