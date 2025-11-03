/**
 * Daemon command - Query daemon status and events
 * Feature 035: User Story 5 - CLI Monitoring Commands
 */

import { DaemonClient } from "../services/daemon-client.ts";

export async function daemonCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand) {
      case "status":
        return await daemonStatus(flags);
      case "events":
        return await daemonEvents(flags);
      case "ping":
        return await daemonPing(flags);
      case "apps":
        return await daemonApps(args.slice(1), flags);
      default:
        console.error("Usage: i3pm daemon <status|events|ping|apps>");
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }
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
    const output = { ...status };
    if (launchStats) {
      output.launch_stats = launchStats;
    }
    console.log(JSON.stringify(output, null, 2));
  } else {
    console.log("\nDaemon Status:");
    console.log("─".repeat(60));
    console.log(`Status:          ${status.status}`);
    console.log(`PID:             ${status.pid}`);
    console.log(`Uptime:          ${Math.floor(status.uptime / 60)}m ${status.uptime % 60}s`);
    console.log(`Active Project:  ${status.active_project || "none"}`);
    console.log(`Events Processed: ${status.events_processed}`);
    console.log(`Tracked Windows: ${status.tracked_windows}`);

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

  // Follow mode: Subscribe to event stream
  if (flags.follow) {
    try {
      console.error("Subscribing to daemon events... (press Ctrl+C to stop)");

      for await (const event of client.subscribeToEvents()) {
        if (flags.json) {
          console.log(JSON.stringify(event));
        } else {
          console.log(`${event.timestamp} [${event.type}] ${JSON.stringify(event.data)}`);
        }
      }
    } catch (error) {
      console.error(`Subscription error: ${error instanceof Error ? error.message : String(error)}`);
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
    console.log(`\nRecent Daemon Events (last ${limit}):\n`);
    for (const event of events as any[]) {
      console.log(`${event.timestamp} [${event.type}] ${event.message}`);
    }
    console.log();
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
