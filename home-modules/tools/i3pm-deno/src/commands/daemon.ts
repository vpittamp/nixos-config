/**
 * Daemon Status and Event Monitoring Commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { DaemonStatusSchema, EventNotificationSchema, EventCorrelationSchema } from "../validation.ts";
import type {
  DaemonStatus,
  EventNotification,
  EventType,
  Output,
  WindowState,
  Workspace,
} from "../models.ts";
import type { EventCorrelation } from "../validation.ts";
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
  --type <type>     Filter by event type (window, workspace, output, tick, project, query, config, daemon, systemd, process)
  --source <src>    Filter by event source (i3, ipc, daemon, systemd, proc, all)
  --since <time>    Time specification for systemd queries (e.g., "1 hour ago", "today")
  --since-id <id>   Show events since specific event ID
  --follow, -f      📡 Live stream events in real-time (like tail -f)
  --correlate       🔗 Show event correlations (window → process relationships)

EXAMPLES:
  # Show recent events with human-readable descriptions
  i3pm daemon events
  i3pm daemon events --limit=50

  # Filter by event type
  i3pm daemon events --type=window         # Only window events
  i3pm daemon events --type=project        # Only project switches

  # Filter by event source (Feature 029: Linux System Log Integration)
  i3pm daemon events --source=i3           # Only i3 window manager events
  i3pm daemon events --source=ipc          # Only user-initiated operations
  i3pm daemon events --source=daemon       # Only daemon lifecycle events
  i3pm daemon events --source=systemd      # Only systemd service events
  i3pm daemon events --source=proc         # Only process monitoring events
  i3pm daemon events --source=all          # Unified stream from all sources

  # Live streaming (real-time monitoring)
  i3pm daemon events --follow              # Watch all events live
  i3pm daemon events -f --type=window      # Watch only window events live
  i3pm daemon events -f --source=i3        # Watch only i3 events live

  # Systemd journal queries (Feature 029)
  i3pm daemon events --source=systemd --since="1 hour ago"
  i3pm daemon events --source=systemd --since=today --limit=100
  i3pm daemon events --source=all --since="30 minutes ago"

  # Advanced filtering
  i3pm daemon events --since-id=1500
  i3pm daemon events --source=ipc --type=query --limit=50

  # Event correlation (Feature 029: US3)
  i3pm daemon events --correlate              # Show correlated window → process relationships
  i3pm daemon events --correlate --limit=10   # Show last 10 events with correlations
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
 * Format time in relative format (e.g., "2s ago", "5m ago")
 */
function formatRelativeTime(timestamp: string): string {
  const now = Date.now();
  const eventTime = new Date(timestamp).getTime();
  const diffMs = now - eventTime;
  const diffSec = Math.floor(diffMs / 1000);

  // For very recent events (< 2 seconds), show "just now"
  if (diffSec < 2) {
    return `now`;
  } else if (diffSec < 60) {
    return `${diffSec}s ago`;
  } else if (diffSec < 3600) {
    const minutes = Math.floor(diffSec / 60);
    return `${minutes}m ago`;
  } else if (diffSec < 86400) {
    const hours = Math.floor(diffSec / 3600);
    return `${hours}h ago`;
  } else {
    const days = Math.floor(diffSec / 86400);
    return `${days}d ago`;
  }
}

/**
 * Format a single event in a user-readable way
 */
function formatEvent(event: EventNotification, formatter: any, options?: { showAbsoluteTime?: boolean }): void {
  // For live streams, show absolute time (HH:MM:SS) for clarity
  // For historical events, show relative time (2m ago, 5h ago)
  let timeDisplay: string;
  if (options?.showAbsoluteTime) {
    const date = new Date(event.timestamp);
    timeDisplay = date.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  } else {
    timeDisplay = formatRelativeTime(event.timestamp);
  }

  const eventType = event.event_type;
  const source = event.source;

  // Format source badge with color
  let sourceBadge = "";
  if (source === "i3") {
    sourceBadge = formatter.dim("[i3]");
  } else if (source === "ipc") {
    sourceBadge = formatter.info("[ipc]");
  } else if (source === "daemon") {
    sourceBadge = formatter.success("[daemon]");
  } else if (source === "systemd") {
    // Feature 029: T020 - systemd source badge (distinct color)
    sourceBadge = formatter.bold("[systemd]");  // Bold for system events (distinct from others)
  } else if (source === "proc") {
    // Feature 029: T020 - proc source badge (distinct color)
    sourceBadge = formatter.error("[proc]");    // Red/magenta for process events
  }

  // Generate human-readable description based on event type
  let description = "";

  // Window events
  if (eventType === "window::new") {
    const app = event.window_class || "unknown";
    const title = event.window_title ? ` "${event.window_title}"` : "";
    description = `New window opened: ${formatter.bold(app)}${title}`;
  } else if (eventType === "window::close") {
    const app = event.window_class || "unknown";
    description = `Window closed: ${formatter.bold(app)}`;
  } else if (eventType === "window::focus") {
    const app = event.window_class || "unknown";
    const title = event.window_title ? ` "${event.window_title}"` : "";
    description = `Focused window: ${formatter.bold(app)}${title}`;
  } else if (eventType === "window::mark") {
    const app = event.window_class || "unknown";
    description = `Window marked: ${formatter.bold(app)}`;
  } else if (eventType === "window::title") {
    const app = event.window_class || "unknown";
    const title = event.window_title ? ` to "${event.window_title}"` : "";
    description = `Window title changed: ${formatter.bold(app)}${title}`;
  }

  // Workspace events
  else if (eventType === "workspace::init") {
    description = `New workspace created`;
  } else if (eventType === "workspace::empty") {
    description = `Workspace became empty`;
  } else if (eventType === "workspace::move") {
    description = `Workspace moved to different output`;
  }

  // Project events
  else if (eventType === "project::switch") {
    const from = event.old_project || "none";
    const to = event.new_project || "none";
    description = `Switched project: ${formatter.dim(from)} → ${formatter.bold(to)}`;
  } else if (eventType === "project::clear") {
    const from = event.old_project || "unknown";
    description = `Cleared project: ${formatter.dim(from)} → ${formatter.dim("global")}`;
  }

  // Query events
  else if (eventType === "query::status") {
    description = `Daemon status queried`;
  } else if (eventType === "query::projects") {
    const count = event.query_result_count || 0;
    description = `Projects listed (${count} project${count !== 1 ? 's' : ''})`;
  } else if (eventType === "query::windows") {
    const count = event.query_result_count || 0;
    description = `Windows queried (${count} window${count !== 1 ? 's' : ''})`;
  } else if (eventType === "query::events") {
    const count = event.query_result_count || 0;
    description = `Events queried (${count} event${count !== 1 ? 's' : ''})`;
  } else if (eventType === "query::rules") {
    const count = event.query_result_count || 0;
    description = `Window rules queried (${count} rule${count !== 1 ? 's' : ''})`;
  }

  // Config events
  else if (eventType === "config::reload") {
    description = `Configuration reloaded`;
  } else if (eventType === "rules::reload") {
    const count = event.rules_added || 0;
    description = `Window rules reloaded (${count} rule${count !== 1 ? 's' : ''})`;
  }

  // Daemon events
  else if (eventType === "daemon::start") {
    const version = event.daemon_version || "unknown";
    description = `Daemon started (v${version})`;
  } else if (eventType === "daemon::connect") {
    const socket = event.i3_socket || "unknown";
    description = `Connected to i3 (${socket})`;
  }

  // Feature 029: T019 - systemd events
  else if (eventType === "systemd::service::start") {
    const unit = event.systemd_unit || "unknown";
    const message = event.systemd_message || "";
    const pid = event.systemd_pid ? ` (PID ${event.systemd_pid})` : "";
    description = `Service started: ${formatter.bold(unit)}${pid}`;
    if (message && !message.includes(unit)) {
      description += formatter.dim(` - ${message}`);
    }
  } else if (eventType === "systemd::service::stop") {
    const unit = event.systemd_unit || "unknown";
    const message = event.systemd_message || "";
    description = `Service stopped: ${formatter.bold(unit)}`;
    if (message && !message.includes(unit)) {
      description += formatter.dim(` - ${message}`);
    }
  } else if (eventType === "systemd::service::failed") {
    const unit = event.systemd_unit || "unknown";
    const message = event.systemd_message || "";
    description = `Service failed: ${formatter.error(unit)}`;
    if (message) {
      description += formatter.dim(` - ${message}`);
    }
  } else if (eventType === "systemd::unit::event") {
    const unit = event.systemd_unit || "unknown";
    const message = event.systemd_message || "no details";
    description = `Unit event: ${formatter.bold(unit)} - ${formatter.dim(message)}`;
  }

  // Feature 029: Process events (for future US2 implementation)
  else if (eventType === "process::start") {
    const name = event.process_name || "unknown";
    const cmdline = event.process_cmdline || "";
    const pid = event.process_pid ? ` (PID ${event.process_pid})` : "";
    description = `Process started: ${formatter.bold(name)}${pid}`;
    if (cmdline && cmdline !== name) {
      // Truncate long command lines for display
      const truncated = cmdline.length > 60 ? cmdline.substring(0, 57) + "..." : cmdline;
      description += formatter.dim(` - ${truncated}`);
    }
  }

  // Tick events
  else if (eventType === "tick") {
    if (event.tick_payload?.startsWith("project:")) {
      const project = event.tick_payload.split(":")[1];
      if (project === "none") {
        description = `Project cleared via tick event`;
      } else {
        description = `Project switched via tick: ${formatter.bold(project)}`;
      }
    } else {
      description = `Tick event: ${event.tick_payload || "empty"}`;
    }
  }

  // Output events
  else if (eventType === "output") {
    const output = event.output_name || "unknown";
    description = `Monitor configuration changed: ${formatter.bold(output)}`;
  }

  // Fallback for unknown event types
  else {
    description = `${eventType}`;
  }

  // Add workspace context if present
  if (event.workspace_name && !description.includes("workspace")) {
    description += formatter.dim(` [workspace: ${event.workspace_name}]`);
  }

  // Add project context if present
  if (event.project_name && !description.includes("project")) {
    description += formatter.dim(` [project: ${event.project_name}]`);
  }

  // Format duration
  const duration = event.processing_duration_ms
    ? formatter.dim(` ${event.processing_duration_ms.toFixed(1)}ms`)
    : "";

  // Format error if present
  const error = event.error ? formatter.error(` ⚠ ${event.error}`) : "";

  // Output the formatted event
  console.log(
    `${formatter.dim(timeDisplay.padEnd(9))} ${sourceBadge} ${description}${duration}${error}`
  );
}

/**
 * Format correlation in hierarchical display (Feature 029: T055)
 * Shows parent event → child events with confidence scores
 */
function formatCorrelation(
  correlation: EventCorrelation,
  events: EventNotification[],
  formatter: any
): void {
  const eventsById = new Map<number, EventNotification>();
  for (const event of events) {
    eventsById.set(event.event_id, event);
  }

  // Display correlation header with confidence
  const confidence = (correlation.confidence_score * 100).toFixed(0);
  console.log(
    `    ${formatter.dim("└─>")} ${formatter.bold("🔗 Correlated processes")} (confidence: ${formatter.success(confidence + "%")})`
  );

  // Display each child event indented
  for (let i = 0; i < correlation.child_event_ids.length; i++) {
    const childId = correlation.child_event_ids[i];
    const childEvent = eventsById.get(childId);

    if (!childEvent) continue;

    const isLast = i === correlation.child_event_ids.length - 1;
    const prefix = isLast ? "└─" : "├─";

    // Calculate time delta for this child
    const timeDeltaMs = i === 0 ? correlation.time_delta_ms : 0; // Only show delta for first child
    const timeDelta = timeDeltaMs > 0
      ? ` ${formatter.dim(`+${(timeDeltaMs / 1000).toFixed(1)}s`)}`
      : "";

    // Format child process info
    const processName = childEvent.process_name || "unknown";
    const pid = childEvent.process_pid ? ` (PID ${childEvent.process_pid})` : "";

    // Show correlation factors for first child (most relevant)
    let factors = "";
    if (i === 0) {
      const timingPct = (correlation.timing_factor * 100).toFixed(0);
      const namePct = (correlation.name_similarity * 100).toFixed(0);
      factors = ` ${formatter.dim(`[timing: ${timingPct}%, name: ${namePct}%]`)}`;
    }

    console.log(
      `        ${formatter.dim(prefix)} ${formatter.bold(processName)}${pid}${timeDelta}${factors}`
    );
  }
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
    string: ["limit", "type", "source", "since-id", "since"],
    boolean: ["follow", "correlate"],
    alias: { f: "follow" },
    default: { limit: "20" },
  });

  // Parse parameters
  const limit = parseInt(parsed.limit as string, 10);
  const eventType = parsed.type as string | undefined;
  const source = parsed.source as string | undefined;
  const sinceId = parsed["since-id"]
    ? parseInt(parsed["since-id"] as string, 10)
    : undefined;
  const since = parsed.since as string | undefined;  // Feature 029: T018 - Time spec for systemd queries
  const follow = parsed.follow as boolean;
  const correlate = parsed.correlate as boolean;  // Feature 029: T054 - Show correlations

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
      source?: string;
      since_id?: number;
      since?: string;  // Feature 029: T018 - Time spec for systemd queries
    } = { limit };

    if (eventType) {
      params.event_type = eventType;
    }
    if (source) {
      params.source = source;
    }
    if (sinceId !== undefined) {
      params.since_id = sinceId;
    }
    // Feature 029: T018 - Pass since parameter for systemd queries
    if (since) {
      params.since = since;
    }

    // Feature 029: Use longer timeout for systemd queries (can take 5-10s for large time windows)
    const timeout = (source === "systemd" || source === "all") ? 30000 : 5000;
    const response = await client.request("get_events", params, timeout);

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

    // Feature 029: T054-T055 - Query and display correlations if requested
    let correlations: EventCorrelation[] = [];
    if (correlate) {
      try {
        const correlationResponse = await client.request("query_correlations", { limit: 100 }, 5000);
        const CorrelationArraySchema = z.array(EventCorrelationSchema);
        correlations = CorrelationArraySchema.parse(correlationResponse) as EventCorrelation[];
      } catch (err) {
        if (options.debug) {
          console.error("DEBUG: Error fetching correlations:", err);
        }
        // Continue without correlations
      }
    }

    // Build correlation index for quick lookup
    const correlationsByParent = new Map<number, EventCorrelation>();
    for (const corr of correlations) {
      correlationsByParent.set(corr.parent_event_id, corr);
    }

    // Display events in reverse chronological order (newest first)
    console.log(`\nRecent Events (${events.length} shown):`);
    console.log("─".repeat(80));

    for (const event of events.reverse()) {
      formatEvent(event, formatter);

      // Feature 029: T055 - Display correlations hierarchically
      if (correlate && correlationsByParent.has(event.event_id)) {
        const correlation = correlationsByParent.get(event.event_id)!;
        formatCorrelation(correlation, events, formatter);
      }
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
      console.error("Validation errors:");
      for (const error of err.errors) {
        console.error(`  - ${error.path.join('.')}: ${error.message}`);
      }
      if (options.debug) {
        console.error("\nFull error details:", JSON.stringify(err.errors, null, 2));
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
      // The daemon now broadcasts full EventEntry objects with unified schema
      const event = notification.params as EventNotification;

      // Filter by event type if specified
      if (eventTypeFilter && event.event_type !== eventTypeFilter) {
        return;
      }

      // Format and display event using new user-readable format
      // Use absolute time (HH:MM:SS) for live streams since timestamps won't update
      formatEvent(event, formatter, { showAbsoluteTime: true });
    });

    // Keep running until Ctrl+C
    while (running) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  } finally {
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
      console.error(formatter.error(err.message));

      if (err.message.includes("Failed to connect")) {
        console.error(formatter.info("\nThe daemon is not running. Start it with:"));
        console.error(formatter.dim("  systemctl --user start i3-project-event-listener"));
      }
    } else {
      console.error(formatter.error(String(err)));
    }

    Deno.exit(1);
  } finally {
    await client.close();
    // Force exit to avoid event loop blocking from pending read operations
    // See: https://github.com/denoland/deno/issues/4284
    Deno.exit(0);
  }
}
