/**
 * Events command - Real-time event monitoring with rich formatting
 * Feature 053 Phase 6: Enhanced event logging with decision tree visualization
 *
 * Replaces basic `i3pm daemon events` with formatted, filterable event stream
 * showing workspace assignment decisions and window matching logic.
 */

import { DaemonClient } from "../services/daemon-client.ts";

interface EventOptions {
  follow?: boolean;
  type?: string;
  window?: number;
  project?: string;
  verbose?: boolean;
  json?: boolean;
  since?: string;
  limit?: number;
}

/**
 * Main events command handler
 */
export async function eventsCommand(args: string[], flags: Record<string, unknown>): Promise<number> {
  const options: EventOptions = {
    follow: Boolean(flags.follow || flags.f),
    type: flags.type ? String(flags.type) : undefined,
    window: flags.window ? Number(flags.window) : undefined,
    project: flags.project ? String(flags.project) : undefined,
    verbose: Boolean(flags.verbose || flags.v),
    json: Boolean(flags.json),
    since: flags.since ? String(flags.since) : undefined,
    limit: flags.limit ? Number(flags.limit) : 20,
  };

  const client = new DaemonClient();

  try {
    await client.connect();

    if (options.follow) {
      return await followEvents(client, options);
    } else {
      return await showRecentEvents(client, options);
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    client.disconnect();
  }
}

/**
 * Follow event stream in real-time
 */
async function followEvents(client: DaemonClient, options: EventOptions): Promise<number> {
  if (!options.json) {
    console.error("Following event stream... (press Ctrl+C to stop)\n");
    printTableHeader();
  }

  try {
    for await (const event of client.subscribeToEvents()) {
      if (shouldShowEvent(event, options)) {
        if (options.json) {
          console.log(JSON.stringify(event));
        } else {
          formatEventRow(event, options);
        }
      }
    }
  } catch (error) {
    console.error(`\nSubscription error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }

  return 0;
}

/**
 * Show recent events from daemon buffer
 */
async function showRecentEvents(client: DaemonClient, options: EventOptions): Promise<number> {
  const events = await client.getEvents({
    limit: options.limit,
    event_type: options.type,
  }) as any[];

  if (options.json) {
    console.log(JSON.stringify(events, null, 2));
    return 0;
  }

  // Filter events
  const filteredEvents = events.filter(event => shouldShowEvent(event, options));

  if (filteredEvents.length === 0) {
    console.log("\nNo events found matching filters.\n");
    return 0;
  }

  // Print table header
  console.log();
  printTableHeader();

  // Print each event as a table row
  for (const event of filteredEvents) {
    formatEventRow(event, options);
  }

  console.log();
  return 0;
}

/**
 * Check if event matches filter criteria
 */
function shouldShowEvent(event: any, options: EventOptions): boolean {
  // Type filter
  const eventType = event.type || event.event_type || "unknown";
  if (options.type && eventType !== options.type) {
    return false;
  }

  // Window ID filter
  if (options.window && event.data?.window_id !== options.window) {
    return false;
  }

  // Project filter
  if (options.project && event.data?.project !== options.project) {
    return false;
  }

  return true;
}

/**
 * Print table header
 */
function printTableHeader(): void {
  const BOLD = "\x1b[1m";
  const RESET = "\x1b[0m";
  const DIM = "\x1b[2m";

  console.log(
    `${BOLD}TIME     TYPE                    WINDOW/APP              WORKSPACE  DETAILS${RESET}`
  );
  console.log(`${DIM}${"─".repeat(85)}${RESET}`);
}

/**
 * Format event as table row with optional verbose details
 */
function formatEventRow(event: any, options: EventOptions): void {
  const eventType = event.type || event.event_type || "unknown";
  const timestamp = event.timestamp || new Date().toISOString();
  const time = timestamp.split("T")[1]?.substring(0, 8) || timestamp.substring(11, 19);

  // Color codes
  const RESET = "\x1b[0m";
  const BOLD = "\x1b[1m";
  const DIM = "\x1b[2m";
  const CYAN = "\x1b[36m";
  const GREEN = "\x1b[32m";
  const YELLOW = "\x1b[33m";
  const RED = "\x1b[31m";

  // Event type color and shortened name
  let typeColor = CYAN;
  let typeShort = eventType;

  if (eventType.includes("window::new")) {
    typeColor = GREEN;
    typeShort = "win:new";
  } else if (eventType.includes("window::close")) {
    typeColor = RED;
    typeShort = "win:close";
  } else if (eventType.includes("window::focus")) {
    typeColor = CYAN;
    typeShort = "win:focus";
  } else if (eventType.includes("window::move")) {
    typeColor = YELLOW;
    typeShort = "win:move";
  } else if (eventType.includes("workspace::assignment")) {
    typeColor = YELLOW;
    typeShort = "ws:assign";
  } else if (eventType.includes("workspace::assignment_failed")) {
    typeColor = RED;
    typeShort = "ws:failed";
  } else if (eventType.includes("workspace::init")) {
    typeColor = GREEN;
    typeShort = "ws:init";
  } else if (eventType.includes("workspace::empty")) {
    typeColor = DIM;
    typeShort = "ws:empty";
  } else if (eventType.includes("project::switch")) {
    typeColor = BOLD + CYAN;
    typeShort = "project:switch";
  } else if (eventType.includes("output")) {
    typeColor = BOLD + GREEN;
    typeShort = "output";
  }

  // Access fields directly from event (EventEntry is flat, not nested)
  // For logged events from handlers.py, some data is in event.data
  const d = event.data || event;

  // Format columns based on event type
  let windowApp = "";
  let workspace = "";
  let details = "";

  if (eventType.includes("window::new")) {
    windowApp = truncate(d.window_class || event.window_class || "unknown", 22);
    workspace = d.workspace_name || event.workspace_name || "?";
    details = `${DIM}#${d.window_id || event.window_id}${RESET}`;
    const output = d.output || event.workspace_name;
    if (output && output !== "?") details += ` ${DIM}${output}${RESET}`;
  } else if (eventType === "workspace::assignment") {
    windowApp = truncate(d.window_class || event.window_class || "unknown", 22);
    // EventEntry stores workspace in workspace_name field
    const targetWs = d.target_workspace || d.workspace_name || event.workspace_name || "?";
    workspace = `${DIM}→${RESET} ${BOLD}${targetWs}${RESET}`;
    // assignment_source not in EventEntry, derive from project_name or show generic
    const project = d.project_name || event.project_name;
    const source = d.assignment_source || (project ? "daemon" : "unknown");
    const sourceShort = source.includes("launch") ? "launch" :
                        source.includes("I3PM_TARGET") ? "env:ws" :
                        source.includes("registry") ? "registry" :
                        source.includes("daemon") ? "daemon" : source.substring(0, 10);
    details = `${GREEN}✓${RESET} ${sourceShort}`;
    if (project) details += ` ${DIM}[${project}]${RESET}`;
  } else if (eventType === "workspace::assignment_failed") {
    windowApp = truncate(d.window_class || event.window_class || "unknown", 22);
    workspace = `${DIM}none${RESET}`;
    // EventEntry stores error summary in error field
    const errorMsg = d.error || event.error;
    details = errorMsg ? `${RED}✗${RESET} ${DIM}${truncate(errorMsg, 30)}${RESET}` : `${RED}✗ no assignment${RESET}`;
  } else if (eventType === "project::switch") {
    const oldProj = d.old_project || event.old_project || "none";
    const newProj = d.new_project || event.new_project || "none";
    windowApp = `${oldProj} → ${BOLD}${newProj}${RESET}`;
    workspace = "";
    details = "";
  } else if (eventType.includes("output")) {
    const count = d.output_count || event.output_count || d.active_outputs || 0;
    windowApp = `${count} outputs`;
    workspace = "";
    const names = d.output_names || d.output_name || event.output_name;
    details = names ? truncate(names, 30) : "";
  } else if (eventType.includes("workspace::")) {
    const wsNum = d.workspace_num || d.num || event.workspace_name || "?";
    windowApp = `workspace ${wsNum}`;
    workspace = "";
    details = d.output ? `${DIM}${d.output}${RESET}` : "";
  } else if (eventType.includes("window::")) {
    windowApp = truncate(d.window_class || event.window_class || "unknown", 22);
    workspace = d.workspace_name || event.workspace_name || "?";
    details = `${DIM}#${d.window_id || event.window_id}${RESET}`;
  }

  // Print table row
  console.log(
    `${time} ${typeColor}${pad(typeShort, 20)}${RESET} ${pad(windowApp, 22)} ${pad(workspace, 10)} ${details}`
  );

  // Verbose mode: Add detailed information below the row
  if (options.verbose) {
    printVerboseDetails(event, eventType);
  }
}

/**
 * Print verbose details below table row
 */
function printVerboseDetails(event: any, eventType: string): void {
  const DIM = "\x1b[2m";
  const RESET = "\x1b[0m";
  const GREEN = "\x1b[32m";
  const RED = "\x1b[31m";
  const CYAN = "\x1b[36m";

  // Access fields from event.data (logged events) or event directly (EventEntry)
  const d = event.data || event;

  if (eventType === "workspace::assignment" && d.decision_tree) {
    try {
      const tree = JSON.parse(d.decision_tree);
      console.log(`  ${DIM}├─ Decision path:${RESET}`);
      for (let i = 0; i < tree.length; i++) {
        const decision = tree[i];
        const isLast = i === tree.length - 1;
        const prefix = isLast ? "└─" : "├─";
        const status = decision.matched ? `${GREEN}✓${RESET}` : `${DIM}✗${RESET}`;

        let line = `  ${DIM}${prefix}${RESET} ${status} P${decision.priority}: ${decision.name}`;

        if (decision.matched && decision.workspace) {
          line += ` ${CYAN}→ ws ${decision.workspace}${RESET}`;
        } else if (!decision.matched && decision.reason) {
          line += ` ${DIM}(${decision.reason})${RESET}`;
        }

        console.log(line);
      }
    } catch (e) {
      // Ignore JSON parse errors
    }
  } else if (eventType === "workspace::assignment_failed" && d.decision_tree) {
    try {
      const tree = JSON.parse(d.decision_tree);
      console.log(`  ${DIM}├─ All priorities failed:${RESET}`);
      for (let i = 0; i < tree.length; i++) {
        const decision = tree[i];
        const isLast = i === tree.length - 1;
        const prefix = isLast ? "└─" : "├─";
        console.log(`  ${DIM}${prefix} ${RED}✗${RESET} P${decision.priority}: ${decision.name} ${DIM}(${decision.reason})${RESET}`);
      }
    } catch (e) {
      // Ignore JSON parse errors
    }
  } else if (eventType === "window::new") {
    const title = d.window_title || event.window_title;
    const pid = d.pid || event.window_instance;
    if (title) console.log(`  ${DIM}├─ Title: ${title}${RESET}`);
    if (pid) console.log(`  ${DIM}└─ PID/Instance: ${pid}${RESET}`);
  }
}

/**
 * Pad string to fixed width
 */
function pad(str: string, width: number): string {
  // Remove ANSI color codes for length calculation
  const cleanStr = str.replace(/\x1b\[[0-9;]*m/g, "");
  if (cleanStr.length >= width) return str;
  return str + " ".repeat(width - cleanStr.length);
}

/**
 * Truncate string to max length
 */
function truncate(str: string, maxLen: number): string {
  if (str.length <= maxLen) return str;
  return str.substring(0, maxLen - 1) + "…";
}

/**
 * Format and display event with rich formatting (DEPRECATED - kept for follow mode)
 */
function formatEvent(event: any, options: EventOptions): void {
  const timestamp = event.timestamp || new Date().toISOString();
  const time = timestamp.split("T")[1]?.substring(0, 12) || timestamp;

  // Color codes
  const RESET = "\x1b[0m";
  const BOLD = "\x1b[1m";
  const DIM = "\x1b[2m";
  const CYAN = "\x1b[36m";
  const GREEN = "\x1b[32m";
  const YELLOW = "\x1b[33m";
  const RED = "\x1b[31m";
  const BLUE = "\x1b[34m";

  // Event type color
  let typeColor = CYAN;
  const eventType = event.type || event.event_type || "unknown";
  if (eventType.includes("::new") || eventType.includes("::init")) {
    typeColor = GREEN;
  } else if (eventType.includes("::close") || eventType.includes("::empty")) {
    typeColor = RED;
  } else if (eventType.includes("::assignment")) {
    typeColor = YELLOW;
  }

  // Print event header
  console.log(`${DIM}[${time}]${RESET} ${typeColor}${eventType}${RESET}`);

  // Format event-specific data
  if (eventType === "window::new" && event.data) {
    const d = event.data;
    console.log(`  Window: ${BOLD}${d.window_class || "unknown"}${RESET} (${d.window_title || "no title"})`);
    console.log(`  ID: ${d.window_id} | Workspace: ${d.workspace_num || "?"} | Output: ${d.output || "?"}`);
    if (d.pid) console.log(`  PID: ${d.pid}`);
  }

  if (eventType === "workspace::assignment" && event.data) {
    const d = event.data;
    console.log(`  Window: ${BOLD}${d.window_class}${RESET} [#${d.window_id}]`);
    console.log(`  ${GREEN}✓${RESET} Assigned to workspace ${BOLD}${d.target_workspace}${RESET} via ${CYAN}${d.assignment_source}${RESET}`);
    if (d.project && d.project !== "none") {
      console.log(`  Project: ${d.project}`);
    }
    if (d.correlation_confidence && d.correlation_confidence !== "n/a") {
      console.log(`  Confidence: ${d.correlation_confidence}`);
    }

    // Show decision tree in verbose mode
    if (options.verbose && d.decision_tree) {
      try {
        const tree = JSON.parse(d.decision_tree);
        console.log(`\n  ${BOLD}Decision Path:${RESET}`);
        for (const decision of tree) {
          const status = decision.matched ? `${GREEN}✓${RESET}` : `${DIM}✗${RESET}`;
          const priority = `Priority ${decision.priority}`;
          console.log(`    ${status} ${priority}: ${decision.name}`);

          if (decision.matched && decision.workspace) {
            console.log(`       ${DIM}→ workspace ${decision.workspace}${RESET}`);
            if (decision.details) {
              const details = Object.entries(decision.details)
                .map(([k, v]) => `${k}=${v}`)
                .join(", ");
              console.log(`       ${DIM}${details}${RESET}`);
            }
          } else if (!decision.matched && decision.reason) {
            console.log(`       ${DIM}${decision.reason}${RESET}`);
          }
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }
  }

  if (eventType === "workspace::assignment_failed" && event.data) {
    const d = event.data;
    console.log(`  Window: ${BOLD}${d.window_class}${RESET} [#${d.window_id}]`);
    console.log(`  ${RED}✗ No workspace assignment found${RESET}`);
    if (d.project && d.project !== "none") {
      console.log(`  Project: ${d.project}`);
    }

    // Always show decision tree for failed assignments
    if (d.decision_tree) {
      try {
        const tree = JSON.parse(d.decision_tree);
        console.log(`\n  ${BOLD}Why assignment failed:${RESET}`);
        for (const decision of tree) {
          console.log(`    ${DIM}✗ Priority ${decision.priority}: ${decision.name}${RESET}`);
          if (decision.reason) {
            console.log(`       ${DIM}${decision.reason}${RESET}`);
          }
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }
  }

  if (eventType === "project::switch" && event.data) {
    const d = event.data;
    const old = d.old_project || "none";
    const newProj = d.new_project || "none";
    console.log(`  ${old} ${DIM}→${RESET} ${BOLD}${newProj}${RESET}`);
  }

  if (eventType === "output" && event.data) {
    const d = event.data;
    console.log(`  Active outputs: ${d.active_outputs || 0}`);
    if (d.output_names) {
      console.log(`  Names: ${d.output_names}`);
    }
  }

  // Print separator
  console.log();
}
