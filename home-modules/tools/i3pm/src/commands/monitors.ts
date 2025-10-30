/**
 * Monitors command - Query monitor status and reassignment history
 * Feature 049: Intelligent Automatic Workspace-to-Monitor Assignment
 */

import { DaemonClient } from "../services/daemon-client.ts";

export async function monitorsCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const [subcommand] = args;

  try {
    switch (subcommand) {
      case "status":
        return await monitorsStatus(flags);
      default:
        console.error("Usage: i3pm monitors <status>");
        return 1;
    }
  } catch (error) {
    console.error("Error: " + (error instanceof Error ? error.message : String(error)));
    return 1;
  }
}

async function monitorsStatus(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  try {
    const status = await client.sendRequest("monitors.status", {});

    if (flags.json) {
      console.log(JSON.stringify(status, null, 2));
    } else {
      console.log("\nMonitor Status (Feature 049 - Automatic Workspace Assignment):");
      console.log("=".repeat(70));
      console.log("Active Monitors: " + status.monitor_count);
      console.log();

      if (status.active_monitors && status.active_monitors.length > 0) {
        console.log("+-----------------+--------------+--------------------------------+");
        console.log("| Monitor         | Role         | Workspaces                     |");
        console.log("+-----------------+--------------+--------------------------------+");
        
        for (const monitor of status.active_monitors) {
          const workspaces = monitor.workspaces && monitor.workspaces.length > 0
            ? formatWorkspaceList(monitor.workspaces)
            : "none";
          
          console.log(
            "| " + monitor.name.padEnd(15) + " | " + monitor.role.padEnd(12) + " | " + workspaces.padEnd(30) + " |"
          );
        }
        
        console.log("+-----------------+--------------+--------------------------------+");
      }

      console.log();
      
      if (status.last_reassignment) {
        console.log("Last Reassignment: " + status.last_reassignment);
      } else {
        console.log("Last Reassignment: Never");
      }
      
      console.log("Total Reassignments: " + (status.reassignment_count || 0));
      console.log();
    }

    client.disconnect();
    return 0;
  } catch (error) {
    client.disconnect();
    throw error;
  }
}

function formatWorkspaceList(workspaces: number[]): string {
  if (workspaces.length === 0) return "none";
  if (workspaces.length <= 5) return workspaces.join(", ");
  
  // Format as ranges if many workspaces
  const ranges: string[] = [];
  let start = workspaces[0];
  let prev = start;
  
  for (let i = 1; i < workspaces.length; i++) {
    if (workspaces[i] !== prev + 1) {
      // End current range
      if (start === prev) {
        ranges.push(String(start));
      } else {
        ranges.push(start + "-" + prev);
      }
      start = workspaces[i];
    }
    prev = workspaces[i];
  }
  
  // Add final range
  if (start === prev) {
    ranges.push(String(start));
  } else {
    ranges.push(start + "-" + prev);
  }
  
  return ranges.join(", ");
}
