/**
 * i3pm trace - Window tracing for debugging
 * Feature 101: Track per-window state changes
 *
 * Commands:
 *   i3pm trace start --class ghostty     Start tracing windows matching class
 *   i3pm trace start --id 42             Start tracing specific window
 *   i3pm trace start --title "Terminal"  Start tracing by title pattern
 *   i3pm trace start --app terminal      Start pre-launch trace for next app launch
 *   i3pm trace list                      List active traces
 *   i3pm trace show <trace_id>           Show trace timeline
 *   i3pm trace stop <trace_id>           Stop a trace
 */

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { DaemonClient } from "../services/daemon-client.ts";

interface TraceStartResult {
  success: boolean;
  trace_id: string;
  matcher: Record<string, string>;
  window_id: number | null;
  window_found: boolean;
}

interface TraceStartAppResult {
  success: boolean;
  trace_id: string;
  app_name: string;
  status: "pending";
  timeout: number;
}

interface TraceStopResult {
  success: boolean;
  trace_id: string;
  event_count: number;
  duration_seconds: number;
}

interface TraceListResult {
  success: boolean;
  traces: Array<{
    trace_id: string;
    window_id: number;
    matcher: Record<string, string>;
    is_active: boolean;
    event_count: number;
    duration_seconds: number;
    started_at: string;
  }>;
  count: number;
}

interface TraceGetResult {
  success: boolean;
  trace_id: string;
  format: string;
  timeline?: string;
  trace?: Record<string, unknown>;
}

function showHelp(): void {
  console.log(`
i3pm trace - Window tracing for debugging

USAGE:
  i3pm trace <command> [options]

COMMANDS:
  start       Start tracing a window (or pre-launch trace with --app)
  stop        Stop a trace
  list        List all traces
  show        Show trace timeline
  snapshot    Take manual snapshot

START OPTIONS:
  --id <id>         Window ID to trace
  --class <pattern> Window class pattern (regex)
  --title <pattern> Window title pattern (regex)
  --pid <pid>       Process ID
  --app-id <pattern> Wayland app_id pattern (regex)
  --app <name>      Pre-launch trace: wait for app to launch, trace from intent
  --timeout <secs>  Timeout for --app mode (default: 30s, auto-stops if no launch)

EXAMPLES:
  # Start tracing all Ghostty windows
  i3pm trace start --class ghostty

  # Start tracing a specific window by ID
  i3pm trace start --id 42

  # Start tracing by title
  i3pm trace start --title "Scratchpad"

  # Pre-launch trace: wait for terminal to launch, capture full lifecycle
  i3pm trace start --app terminal --timeout 60

  # List active traces
  i3pm trace list

  # Show trace timeline
  i3pm trace show trace-1234567890-1

  # Stop a trace
  i3pm trace stop trace-1234567890-1
`);
  Deno.exit(0);
}

async function startTrace(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["id", "class", "title", "pid", "app-id", "app", "timeout"],
    boolean: ["json"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  const client = new DaemonClient();

  try {
    // Feature 101: Pre-launch trace with --app option
    if (parsed.app) {
      const timeout = parsed.timeout ? parseFloat(parsed.timeout) : 30.0;
      if (isNaN(timeout) || timeout <= 0) {
        console.error("Error: --timeout must be a positive number");
        return 1;
      }

      const result = await client.request<TraceStartAppResult>("trace.start_app", {
        app_name: parsed.app,
        timeout,
      });

      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
      } else {
        console.log(`\n✓ Started pre-launch trace: ${result.trace_id}`);
        console.log(`  App: ${result.app_name}`);
        console.log(`  Status: ${result.status}`);
        console.log(`  Timeout: ${result.timeout}s`);
        console.log();
        console.log(`  Waiting for '${result.app_name}' to launch...`);
        console.log(`  Launch the app, then run: i3pm trace show ${result.trace_id}`);
        console.log();
      }

      return 0;
    }

    // Standard matcher-based trace
    const matcher: Record<string, string> = {};
    if (parsed.id) matcher.id = parsed.id;
    if (parsed.class) matcher.class = parsed.class;
    if (parsed.title) matcher.title = parsed.title;
    if (parsed.pid) matcher.pid = parsed.pid;
    if (parsed["app-id"]) matcher.app_id = parsed["app-id"];

    if (Object.keys(matcher).length === 0) {
      console.error("Error: At least one matcher required (--id, --class, --title, --pid, --app-id, --app)");
      return 1;
    }

    const result = await client.request<TraceStartResult>("trace.start", matcher);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Started trace: ${result.trace_id}`);
      console.log(`  Matcher: ${JSON.stringify(result.matcher)}`);
      if (result.window_found) {
        console.log(`  Window found: ${result.window_id}`);
      } else {
        console.log(`  Waiting for matching window...`);
      }
      console.log();
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function stopTrace(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    alias: { h: "help" },
  });

  const traceId = parsed._[0]?.toString();
  if (!traceId) {
    console.error("Error: trace_id required");
    console.error("Usage: i3pm trace stop <trace_id>");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<TraceStopResult>("trace.stop", { trace_id: traceId });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Stopped trace: ${result.trace_id}`);
      console.log(`  Events recorded: ${result.event_count}`);
      console.log(`  Duration: ${result.duration_seconds.toFixed(2)}s`);
      console.log();
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function listTraces(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    alias: { h: "help" },
  });

  const client = new DaemonClient();
  try {
    const result = await client.request<TraceListResult>("trace.list", {});

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      if (result.count === 0) {
        console.log("\nNo active traces\n");
        console.log("Start a trace with: i3pm trace start --class <pattern>\n");
      } else {
        console.log(`\n${result.count} trace(s):\n`);
        for (const trace of result.traces) {
          const status = trace.is_active ? "ACTIVE" : "STOPPED";
          console.log(`  ${trace.trace_id}`);
          console.log(`    Status: ${status}`);
          console.log(`    Window: ${trace.window_id || "waiting..."}`);
          console.log(`    Matcher: ${JSON.stringify(trace.matcher)}`);
          console.log(`    Events: ${trace.event_count}`);
          console.log(`    Duration: ${trace.duration_seconds.toFixed(2)}s`);
          console.log();
        }
      }
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function showTrace(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    string: ["limit"],
    alias: { h: "help", n: "limit" },
    default: { limit: "50" },
  });

  const traceId = parsed._[0]?.toString();
  if (!traceId) {
    console.error("Error: trace_id required");
    console.error("Usage: i3pm trace show <trace_id>");
    return 1;
  }

  const limit = parseInt(parsed.limit || "50", 10);

  const client = new DaemonClient();
  try {
    const format = parsed.json ? "json" : "timeline";
    const result = await client.request<TraceGetResult>("trace.get", {
      trace_id: traceId,
      format,
      limit,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result.trace, null, 2));
    } else {
      console.log(result.timeline);
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function takeSnapshot(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    alias: { h: "help" },
  });

  const traceId = parsed._[0]?.toString();
  if (!traceId) {
    console.error("Error: trace_id required");
    console.error("Usage: i3pm trace snapshot <trace_id>");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<{ success: boolean; trace_id: string }>("trace.snapshot", {
      trace_id: traceId,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`\n✓ Snapshot taken for trace: ${result.trace_id}\n`);
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

export async function traceCommand(args: string[]): Promise<number> {
  const subcommand = args[0];
  const subArgs = args.slice(1);

  switch (subcommand) {
    case "start":
      return await startTrace(subArgs);
    case "stop":
      return await stopTrace(subArgs);
    case "list":
      return await listTraces(subArgs);
    case "show":
      return await showTrace(subArgs);
    case "snapshot":
      return await takeSnapshot(subArgs);
    case "--help":
    case "-h":
    case undefined:
      showHelp();
      return 0;
    default:
      console.error(`Unknown subcommand: ${subcommand}`);
      console.error("Run 'i3pm trace --help' for usage");
      return 1;
  }
}
