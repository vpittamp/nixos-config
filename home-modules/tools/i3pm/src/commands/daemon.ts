/**
 * Daemon command - Query daemon status and events
 * Feature 035: User Story 5 - CLI Monitoring Commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../services/daemon-client.ts";
import { bold, cyan, green, yellow, red, gray, magenta, blue, dim } from "jsr:@std/fmt/colors";

export async function daemonCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "follow", "verbose", "debug"],
    string: ["limit", "type", "scope", "workspace"],
    alias: { h: "help" },
    stopEarly: false,
  });
  const mergedFlags = { ...flags, ...parsed };
  const subcommand = String(parsed._[0] || "");
  const subArgs = parsed._.slice(1).map(String);

  try {
    if (mergedFlags.help || !subcommand) {
      console.error("Usage: i3pm daemon <status|events|ping|apps> [options]");
      console.error("");
      console.error("Common options:");
      console.error("  --json            Output JSON");
      console.error("  --verbose         Verbose output");
      console.error("");
      console.error("Events options:");
      console.error("  --follow          Stream events continuously");
      console.error("  --limit <n>       Number of events (default: 20)");
      console.error("  --type <event>    Filter by event type");
      return 0;
    }

    switch (subcommand) {
      case "status":
        return await daemonStatus(mergedFlags);
      case "events":
        return await daemonEvents(mergedFlags);
      case "ping":
        return await daemonPing(mergedFlags);
      case "apps":
        return await daemonApps(subArgs, mergedFlags);
      default:
        console.error("Usage: i3pm daemon <status|events|ping|apps>");
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
}

/**
 * Format event data in columnar layout (default mode)
 */
function formatEventColumnar(event: any): string {
  const typeInfo = getEventTypeInfo(event.event_type || "unknown");
  const timeStr = formatTimestamp(event.timestamp).padEnd(8);

  // Column 1: Timestamp (8 chars)
  const col1 = dim(timeStr);

  // Column 2: Icon + Type (25 chars)
  const typeLabel = `${typeInfo.icon} ${typeInfo.label}`;
  const col2 = typeInfo.color(typeLabel.padEnd(25));

  // Column 3: Duration (10 chars)
  let col3 = "";
  if (event.processing_duration_ms !== null && event.processing_duration_ms !== undefined) {
    const duration = event.processing_duration_ms;
    const durationStr = duration < 1 ? `${duration.toFixed(2)}ms` : `${Math.round(duration)}ms`;
    const durationColor = duration > 100 ? red : duration > 50 ? yellow : green;
    col3 = durationColor(durationStr.padEnd(10));
  } else {
    col3 = dim("—".padEnd(10));
  }

  // Column 4: Source (8 chars)
  const source = event.source || "—";
  const sourceColor = source === "ipc" ? cyan : source === "proc" ? green : source === "i3" ? blue : dim;
  const col4 = sourceColor(source.padEnd(8));

  // Column 5: Target/Resource (20 chars)
  const target = getEventTarget(event);
  const col5 = target ? magenta(target.padEnd(20).substring(0, 20)) : dim("—".padEnd(20));

  // Column 6: Details (remaining space)
  const details = getEventSummary(event);
  const col6 = details || "";

  // Error indicator
  const errorIndicator = event.error ? ` ${red("✗")}` : "";

  return `${col1} ${col2} ${col3} ${col4} ${col5} ${col6}${errorIndicator}`;
}

/**
 * Get the main target/resource for an event
 */
function getEventTarget(event: any): string {
  if (event.project_name) return event.project_name;
  if (event.query_params?.name) return event.query_params.name;
  if (event.query_params?.active) return event.query_params.active;
  if (event.window_class) return event.window_class;
  if (event.window_title) return event.window_title.substring(0, 20);
  if (event.process_name) return event.process_name;
  if (event.workspace_name) return `WS${event.workspace_name}`;
  if (event.output_name) return event.output_name;
  return "";
}

/**
 * Get a brief summary of the event
 */
function getEventSummary(event: any): string {
  const parts: string[] = [];

  // Results count
  if (event.query_result_count !== null && event.query_result_count !== undefined) {
    parts.push(dim(`${event.query_result_count} results`));
  }

  // Windows affected
  if (event.windows_affected) {
    parts.push(yellow(`${event.windows_affected} windows`));
  }

  // Project switch details
  if (event.old_project || event.new_project) {
    parts.push(`${dim(event.old_project || "none")} ${dim("→")} ${green(event.new_project || "none")}`);
  }

  // Process PID
  if (event.process_pid && !event.process_name) {
    parts.push(dim(`PID ${event.process_pid}`));
  }

  // Workspace number
  if (event.workspace_name && !event.output_name) {
    parts.push(dim(`WS ${event.workspace_name}`));
  }

  // Output changes
  if (event.output_name && event.output_count) {
    parts.push(dim(`${event.output_count} outputs`));
  }

  // Error message
  if (event.error) {
    parts.push(red(event.error.substring(0, 40)));
  }

  return parts.join(dim(" • "));
}

/**
 * Format event data in a human-readable way with colors (verbose mode)
 */
function formatEvent(event: any, verbose: boolean = false): string {
  // Event type with icon and color
  const typeInfo = getEventTypeInfo(event.event_type || "unknown");
  const timeStr = dim(formatTimestamp(event.timestamp));

  // Build header line
  let output = `${timeStr} ${typeInfo.icon} ${typeInfo.color(bold(typeInfo.label))}`;

  // Add duration if present and significant
  if (event.processing_duration_ms !== null && event.processing_duration_ms !== undefined) {
    const duration = event.processing_duration_ms;
    const durationStr = duration < 1 ? `${duration.toFixed(2)}ms` : `${Math.round(duration)}ms`;
    const durationColor = duration > 100 ? red : duration > 50 ? yellow : green;
    output += ` ${dim("•")} ${durationColor(durationStr)}`;
  }

  // Add error if present
  if (event.error) {
    output += `\n  ${red("✗")} ${red(event.error)}`;
    return output;
  }

  // Add event-specific details
  const details = formatEventDetails(event, verbose);
  if (details) {
    output += `\n  ${details}`;
  }

  return output;
}

/**
 * Get icon, color, and label for event type
 */
function getEventTypeInfo(eventType: string): { icon: string; color: (s: string) => string; label: string } {
  const typeMap: Record<string, { icon: string; color: (s: string) => string; label: string }> = {
    // Project events
    "project::create": { icon: "✨", color: green, label: "Project Created" },
    "project::delete": { icon: "🗑️", color: red, label: "Project Deleted" },
    "project::list": { icon: "📋", color: cyan, label: "List Projects" },
    "project::get": { icon: "📁", color: blue, label: "Get Project" },
    "project::get_active": { icon: "🎯", color: magenta, label: "Active Project" },
    "project::set_active": { icon: "🔄", color: yellow, label: "Switch Project" },
    "project::update": { icon: "✏️", color: yellow, label: "Update Project" },

    // Layout events
    "layout::save": { icon: "💾", color: green, label: "Save Layout" },
    "layout::restore": { icon: "📥", color: blue, label: "Restore Layout" },
    "layout::delete": { icon: "🗑️", color: red, label: "Delete Layout" },
    "layout::list": { icon: "📋", color: cyan, label: "List Layouts" },

    // Window events
    "window::new": { icon: "🪟", color: green, label: "Window Opened" },
    "window::close": { icon: "✖️", color: red, label: "Window Closed" },
    "window::focus": { icon: "👁️", color: yellow, label: "Window Focused" },
    "window::mark": { icon: "🏷️", color: magenta, label: "Window Marked" },

    // Process events
    "process::start": { icon: "🚀", color: green, label: "Process Started" },
    "process::query": { icon: "🔍", color: cyan, label: "Process Query" },

    // Tick events
    "tick": { icon: "⏱️", color: gray, label: "Tick Event" },

    // System events
    "output::change": { icon: "🖥️", color: blue, label: "Output Changed" },
    "workspace::init": { icon: "🏗️", color: green, label: "Workspace Init" },

    // IPC events
    "ipc::request": { icon: "📡", color: dim, label: "IPC Request" },
  };

  return typeMap[eventType] || { icon: "•", color: gray, label: eventType };
}

/**
 * Format timestamp in relative or absolute format
 */
function formatTimestamp(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diff = now.getTime() - date.getTime();

  // If within last minute, show relative time
  if (diff < 60000) {
    const seconds = Math.floor(diff / 1000);
    return seconds === 0 ? "now" : `${seconds}s ago`;
  }

  // Otherwise show HH:MM:SS
  return date.toLocaleTimeString('en-US', { hour12: false });
}

/**
 * Format event-specific details
 */
function formatEventDetails(event: any, verbose: boolean): string {
  const details: string[] = [];

  // Project name
  if (event.project_name) {
    details.push(`${cyan("project:")} ${event.project_name}`);
  }

  // Window info
  if (event.window_class || event.window_title) {
    const winInfo = event.window_class || event.window_title;
    details.push(`${blue("window:")} ${winInfo}`);
  }

  // Process info
  if (event.process_name) {
    details.push(`${green("process:")} ${event.process_name}${event.process_pid ? ` (${event.process_pid})` : ""}`);
  }

  // Query params (for project/layout operations)
  if (event.query_params) {
    const params = event.query_params;
    if (params.name) {
      details.push(`${magenta("name:")} ${params.name}`);
    }
    if (params.active) {
      details.push(`${magenta("active:")} ${params.active}`);
    }
  }

  // Result count
  if (event.query_result_count !== null && event.query_result_count !== undefined) {
    details.push(`${dim("results:")} ${event.query_result_count}`);
  }

  // Project switch details
  if (event.old_project || event.new_project) {
    details.push(`${yellow("from:")} ${event.old_project || "none"} ${dim("→")} ${green("to:")} ${event.new_project || "none"}`);
  }

  // Windows affected (for filtering operations)
  if (event.windows_affected) {
    details.push(`${yellow("affected:")} ${event.windows_affected} windows`);
  }

  // In verbose mode, show all non-null fields
  if (verbose) {
    const verboseFields = Object.entries(event)
      .filter(([key, value]) =>
        value !== null &&
        value !== undefined &&
        !["timestamp", "event_type", "processing_duration_ms", "error", "event_id", "source"].includes(key) &&
        !details.some(d => d.includes(key))
      )
      .map(([key, value]) => `${dim(key + ":")} ${JSON.stringify(value)}`);

    if (verboseFields.length > 0) {
      details.push(...verboseFields);
    }
  }

  return details.join(` ${dim("•")} `);
}

async function daemonStatus(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  const status = await client.getStatus();

  // Feature 041: Get launch registry stats
  let launchStats;
  try {
    launchStats = await client.getLaunchStats();
  } catch {
    // Launch stats not available (older daemon version)
    launchStats = null;
  }

  if (flags.json) {
    const output = launchStats ? { ...status, launch_stats: launchStats } : status;
    console.log(JSON.stringify(output, null, 2));
  } else {
    console.log("\nDaemon Status:");
    console.log("─".repeat(60));
    console.log(`Status:          ${status.status}`);
    console.log(`Connected:       ${status.connected ? "yes" : "no"}`);
    console.log(`Uptime:          ${Math.floor(status.uptime / 60)}m ${status.uptime % 60}s`);
    console.log(`Active Project:  ${status.active_project || "none"}`);
    console.log(`Events Processed: ${status.event_count}`);
    console.log(`Tracked Windows: ${status.window_count}`);

    if (launchStats) {
      console.log();
      console.log("Launch Registry (Feature 041):");
      console.log("─".repeat(60));
      console.log(`Pending:         ${launchStats.total_pending} (${launchStats.unmatched_pending} unmatched)`);
      console.log(`Notifications:   ${launchStats.total_notifications}`);
      console.log(`Matched:         ${launchStats.total_matched} (${launchStats.match_rate.toFixed(1)}%)`);
      console.log(`Expired:         ${launchStats.total_expired} (${launchStats.expiration_rate.toFixed(1)}%)`);
      console.log(`Failed:          ${launchStats.total_failed_correlation}`);
    }
    console.log();
  }

  client.disconnect();
  return 0;
}

async function daemonEvents(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  const verbose = !!flags.verbose;

  // Follow mode: Subscribe to event stream
  if (flags.follow) {
    try {
      // Print header with styling
      console.error(bold(cyan("\n╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗")));
      console.error(bold(cyan("║")) + bold("                              i3pm Daemon Event Stream (Live)                                    ") + bold(cyan("║")));
      console.error(bold(cyan("╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝")));

      if (!verbose && !flags.json) {
        // Print column headers
        console.error(dim("TIME     EVENT TYPE                DURATION   SOURCE   TARGET/RESOURCE      DETAILS"));
        console.error(dim("─".repeat(110)));
      } else {
        console.error(dim("Press Ctrl+C to stop\n"));
      }

      for await (const event of client.subscribeToEvents()) {
        if (flags.json) {
          console.log(JSON.stringify(event));
        } else {
          // subscribeToEvents yields { type, data, timestamp }
          // but formatEvent expects the full event data
          const fullEvent = {
            event_type: event.type,
            timestamp: event.timestamp,
            ...(event.data as any),
          };

          // Use columnar format by default, verbose format with --verbose
          if (verbose) {
            console.log(formatEvent(fullEvent, verbose));
          } else {
            console.log(formatEventColumnar(fullEvent));
          }
        }
      }
    } catch (error) {
      console.error(red(`\n✗ Subscription error: ${error instanceof Error ? error.message : String(error)}`));
      client.disconnect();
      return 1;
    }

    client.disconnect();
    return 0;
  }

  // Default mode: Get recent events
  const limit = flags.limit ? Number(flags.limit) : 20;
  const eventType = flags.type ? String(flags.type) : undefined;

  const events = await client.getEvents({ limit, event_type: eventType });

  if (flags.json) {
    console.log(JSON.stringify(events, null, 2));
  } else {
    // Print header
    const typeFilter = eventType ? ` (type: ${cyan(eventType)})` : "";
    console.log(bold(cyan("\n╔═══════════════════════════════════════════════════════════════╗")));
    console.log(bold(cyan("║")) + bold(`     Recent Daemon Events (last ${limit})${typeFilter}`.padEnd(61)) + bold(cyan("║")));
    console.log(bold(cyan("╚═══════════════════════════════════════════════════════════════╝\n")));

    if ((events as any[]).length === 0) {
      console.log(dim("  No events found\n"));
    } else {
      for (const event of events as any[]) {
        console.log(formatEvent(event, verbose));
      }
      console.log();
    }
  }

  client.disconnect();
  return 0;
}

async function daemonPing(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  const isAlive = await client.ping();

  if (flags.json) {
    console.log(JSON.stringify({ alive: isAlive }, null, 2));
  } else {
    if (isAlive) {
      console.log("✓ Daemon is running");
    } else {
      console.error("✗ Daemon is not responding");
      return 1;
    }
  }

  return 0;
}

async function daemonApps(args: string[], flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  // Build query parameters
  const params: Record<string, unknown> = {};

  if (flags.scope) {
    params.scope = String(flags.scope);
  }

  if (flags.workspace) {
    params.workspace = Number(flags.workspace);
  }

  if (args.length > 0) {
    params.name = args[0];
  }

  const result = await client.getDaemonApps(params);

  if (flags.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log(`\nApplications in Daemon Registry (v${result.version}):`);
    console.log("─".repeat(80));
    console.log("NAME".padEnd(25), "DISPLAY NAME".padEnd(30), "WS".padEnd(4), "SCOPE");
    console.log("─".repeat(80));

    for (const app of result.applications as any[]) {
      const ws = app.preferred_workspace ? app.preferred_workspace.toString() : "-";
      console.log(
        app.name.padEnd(25),
        app.display_name.padEnd(30),
        ws.padEnd(4),
        app.scope
      );
    }

    console.log();
    console.log(`Total: ${result.count} applications`);
    console.log(`Registry: ${result.registry_path}`);
    console.log();
  }

  client.disconnect();
  return 0;
}
