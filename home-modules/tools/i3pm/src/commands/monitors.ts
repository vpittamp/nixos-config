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
      case "reassign":
        return await monitorsReassign(flags);
      case "config":
        return await monitorsConfig(flags);
      default:
        console.error("Usage: i3pm monitors <status|reassign|config>");
        console.error("");
        console.error("Subcommands:");
        console.error("  status    - Show current monitor role assignments");
        console.error("  reassign  - Force workspace reassignment to monitors");
        console.error("  config    - Show monitor role configuration");
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

async function monitorsReassign(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  try {
    console.log("Triggering workspace reassignment...");
    const result = await client.sendRequest("monitors.reassign", {});

    if (flags.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log();
      console.log("Reassignment complete!");
      console.log("Workspaces reassigned: " + (result.workspaces_moved || 0));
      console.log("Duration: " + (result.duration_ms || 0) + "ms");
      console.log();

      if (result.monitor_assignments) {
        console.log("Monitor Role Assignments:");
        for (const [role, output] of Object.entries(result.monitor_assignments)) {
          console.log("  " + role + " → " + output);
        }
        console.log();
      }
    }

    client.disconnect();
    return 0;
  } catch (error) {
    client.disconnect();
    throw error;
  }
}

async function monitorsConfig(flags: Record<string, unknown>): Promise<number> {
  const client = new DaemonClient();
  await client.connect();

  try {
    const config = await client.sendRequest("monitors.config", {});

    if (flags.json) {
      console.log(JSON.stringify(config, null, 2));
    } else {
      console.log("\nMonitor Role Configuration (Feature 001):");
      console.log("=".repeat(70));
      console.log();

      if (config.output_preferences && Object.keys(config.output_preferences).length > 0) {
        console.log("Output Preferences (US5):");
        console.log();

        for (const [role, outputs] of Object.entries(config.output_preferences)) {
          console.log("  " + role.padEnd(12) + " → " + (outputs as string[]).join(", "));
        }
        console.log();
      } else {
        console.log("Output Preferences: None (using connection order)");
        console.log();
      }

      if (config.workspace_assignments && config.workspace_assignments.length > 0) {
        console.log("Workspace-to-Monitor Assignments:");
        console.log();
        console.log("+--------------+----------------------+------------------+------------+");
        console.log("| Workspace    | App Name             | Monitor Role     | Source     |");
        console.log("+--------------+----------------------+------------------+------------+");

        for (const assignment of config.workspace_assignments) {
          const ws = String(assignment.preferred_workspace).padEnd(12);
          const app = (assignment.app_name || "default").padEnd(20);
          const role = (assignment.preferred_monitor_role || "inferred").padEnd(16);
          const source = (assignment.source || "unknown").padEnd(10);

          console.log("| " + ws + " | " + app + " | " + role + " | " + source + " |");
        }

        console.log("+--------------+----------------------+------------------+------------+");
        console.log();
        console.log("Total Assignments: " + config.workspace_assignments.length);
        console.log();
      } else {
        console.log("Workspace Assignments: None configured");
        console.log();
      }

      console.log("Monitor Role Inference Rules:");
      console.log("  WS 1-2  → primary");
      console.log("  WS 3-5  → secondary");
      console.log("  WS 6+   → tertiary");
      console.log();

      console.log("Fallback Chain: tertiary → secondary → primary");
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
