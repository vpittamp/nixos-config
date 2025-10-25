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
      default:
        console.error("Usage: i3pm daemon <status|events|ping>");
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

  if (flags.json) {
    console.log(JSON.stringify(status, null, 2));
  } else {
    console.log("\nDaemon Status:");
    console.log("─".repeat(60));
    console.log(`Status:          ${status.status}`);
    console.log(`PID:             ${status.pid}`);
    console.log(`Uptime:          ${Math.floor(status.uptime / 60)}m ${status.uptime % 60}s`);
    console.log(`Active Project:  ${status.active_project || "none"}`);
    console.log(`Events Processed: ${status.events_processed}`);
    console.log(`Tracked Windows: ${status.tracked_windows}`);
    console.log();
  }

  client.disconnect();
  return 0;
}

async function daemonEvents(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

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
