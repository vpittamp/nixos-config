/**
 * Worktree Command Dispatcher
 * Feature 100: Structured Git Repository Management
 *
 * Main entry point for all worktree-related commands.
 * Operates on bare repository structure: ~/repos/<account>/<repo>/.bare/
 */

import { parseArgs } from "@std/cli/parse-args";
import { cyan, dim, green, magenta, red, yellow } from "jsr:@std/fmt/colors";
import { worktreeCreate } from "./worktree/create.ts";
import { worktreeRemove } from "./worktree/remove.ts";
import { worktreeList } from "./worktree/list.ts";
import { worktreeSwitch } from "./worktree/switch.ts";
import { worktreeHost } from "./worktree/remote.ts";
import { worktreeRename } from "./worktree/rename.ts";
import { worktreeSuggestName } from "./worktree/suggest-name.ts";
import { DaemonClient } from "../services/daemon-client.ts";

/**
 * Show worktree command help
 */
function showHelp(): void {
  console.log(`
i3pm worktree - Git worktree management for bare repositories

USAGE:
  i3pm worktree <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  create <branch>       Create a new worktree (Feature 100)
  remove <branch>       Remove a worktree (Feature 100)
  rename <old> <new>    Rename worktree and branch via git gtr
  suggest-name <task>   Suggest a meaningful branch name for a new worktree
  list [repo]           List worktrees for a repository (Feature 100)
  current               Show active daemon worktree context
  clear                 Clear active daemon worktree context
  ensure <name>         Ensure daemon runtime context
  diagnose [name]       Diagnose SSH/runtime readiness for a worktree
  switch <name>         Switch to a worktree by qualified name (Feature 101)
  host <subcommand>     Manage non-local host profiles for worktrees (Feature 087)

OPTIONS:
  -h, --help            Show this help message

EXAMPLES:
  # Create worktree for new feature branch
  i3pm worktree create 100-feature
  i3pm worktree create 101-bugfix --from develop

  # List worktrees
  i3pm worktree list
  i3pm worktree list vpittamp/nixos

  # Remove a worktree
  i3pm worktree remove 100-feature
  i3pm worktree remove 100-feature --force
  i3pm worktree rename 100-feature 100-feature-v2
  i3pm worktree suggest-name "improve launcher refresh handling"
  i3pm worktree current
  i3pm worktree clear
  i3pm worktree ensure vpittamp/nixos-config:main
  i3pm worktree diagnose vpittamp/nixos-config:main
  i3pm worktree host set vpittamp/nixos-config:main --dir /home/vpittamp/repos/vpittamp/nixos-config/main --host thinkpad

For detailed help on a specific subcommand:
  i3pm worktree <subcommand> --help
`);
  Deno.exit(0);
}

async function worktreeCurrent(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    console.log(`
i3pm worktree current - Show the active daemon worktree context

USAGE:
  i3pm worktree current [OPTIONS]

OPTIONS:
  -h, --help        Show this help message
  --json            Output the raw context payload as JSON
`);
    return 0;
  }

  const client = new DaemonClient();

  try {
    const context = await client.request<{
      qualified_name: string;
      directory: string;
      local_directory: string;
      target_host: string;
      transport_kind: string;
      connection_key: string;
      context_key: string;
      host_profile_configured: boolean;
      host_profile?: {
        host?: string;
        user?: string;
        port?: number;
        directory?: string;
      } | null;
      is_global: boolean;
    }>("worktree.current", {});

    if (parsed.json) {
      console.log(JSON.stringify(context, null, 2));
      return 0;
    }

    if (context.is_global || !context.qualified_name) {
      console.log("No active worktree context. Use 'i3pm worktree switch <name>' to activate one.");
      return 0;
    }

    console.log(`Active Worktree: ${cyan(context.qualified_name)}`);
    console.log(`  Target host: ${magenta(context.target_host || "global")}`);
    console.log(`  Transport: ${magenta(context.transport_kind || "global")}`);
    console.log(`  Directory: ${context.directory || context.local_directory || ""}`);
    console.log(`  Local directory: ${context.local_directory || context.directory || ""}`);
    if (context.connection_key) {
      console.log(`  Connection: ${context.connection_key}`);
    }
    if (context.context_key) {
      console.log(`  Context key: ${dim(context.context_key)}`);
    }
    if (context.host_profile_configured && context.host_profile) {
      const user = context.host_profile.user || "unknown";
      const host = context.host_profile.host || "unknown";
      const port = context.host_profile.port ?? 22;
      console.log(`  Host profile: ${user}@${host}:${port}`);
      if (context.host_profile.directory) {
        console.log(`  Host dir: ${context.host_profile.directory}`);
      }
    }

    return 0;
  } finally {
    client.disconnect();
  }
}

async function worktreeDiagnose(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    console.log(`
i3pm worktree diagnose - Diagnose SSH/project runtime readiness for a worktree

USAGE:
  i3pm worktree diagnose [qualified_name] [OPTIONS]

ARGUMENTS:
  qualified_name    Worktree qualified name (defaults to active worktree)

OPTIONS:
  -h, --help        Show this help message
  --json            Output diagnostics as JSON
`);
    return 0;
  }

  const qualifiedName = parsed._[0]?.toString();
  const client = new DaemonClient();

  try {
    const result = await client.request<{
      success: boolean;
      qualified_name: string;
      host_profile_configured: boolean;
      host_profile?: {
        enabled: boolean;
        host: string;
        user: string;
        port: number;
        remote_dir: string;
      } | null;
      active_context: {
        qualified_name: string;
        target_host: string;
        transport_kind: string;
        connection_key: string;
        context_key: string;
        is_global: boolean;
      };
      target_context: {
        target_host: string;
        transport_kind: string;
        connection_key: string;
        context_key: string;
      };
      host_test?: {
        success: boolean;
        duration_ms: number;
        message: string;
        stderr?: string;
      } | null;
      scratchpad: {
        available: boolean;
        context_key: string;
        count: number;
        terminal?: {
          state?: string;
          window_exists?: boolean;
          process_running?: boolean;
          tmux_session_name?: string;
        } | null;
      };
      launch_support: {
        host_terminal_supported: boolean;
        host_scoped_gui_supported: boolean;
        host_policy: string;
      };
      launch_stats: {
        total_pending: number;
        unmatched_pending: number;
        total_notifications: number;
        total_matched: number;
        total_expired: number;
        match_rate: number;
        expiration_rate: number;
      };
      project_pending_launches: Array<{
        app_name: string;
        matched: boolean;
        age: number;
      }>;
      readiness: {
        host_ready: boolean;
        reasons: string[];
      };
      recommended_commands: string[];
    }>("worktree.diagnose", qualifiedName ? { qualified_name: qualifiedName } : {});

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return result.readiness.host_ready ? 0 : 1;
    }

    console.log(`Worktree Diagnosis: ${cyan(result.qualified_name)}`);
    console.log(
      `  Active context: ${
        result.active_context.qualified_name || "global"
      } (${result.active_context.target_host || "global"})`,
    );
    console.log(`  Target context: ${result.target_context.context_key}`);

    if (result.host_profile_configured && result.host_profile) {
      console.log(
        `  Host profile: ${result.host_profile.user}@${result.host_profile.host}:${result.host_profile.port}`,
      );
      console.log(`  Host dir: ${result.host_profile.remote_dir}`);
    } else {
      console.log(`  Host profile: ${red("not configured")}`);
    }

    if (result.host_test) {
      const status = result.host_test.success ? green("passed") : red("failed");
      console.log(`  Host test: ${status} (${result.host_test.duration_ms}ms)`);
      if (result.host_test.stderr) {
        console.log(`  Host error: ${result.host_test.stderr}`);
      }
    } else {
      console.log(`  Host test: ${dim("skipped")}`);
    }

    if (result.scratchpad.available && result.scratchpad.terminal) {
      const state = result.scratchpad.terminal.state || "unknown";
      const exists = result.scratchpad.terminal.window_exists ? "window-present" : "window-missing";
      const running = result.scratchpad.terminal.process_running
        ? "process-running"
        : "process-missing";
      console.log(`  Scratchpad: ${green("available")} (${state}, ${exists}, ${running})`);
    } else {
      console.log(`  Scratchpad: ${yellow("not running")} for ${result.scratchpad.context_key}`);
    }

    console.log(`  Host launch policy: ${result.launch_support.host_policy}`);
    console.log(
      `  Launch correlation: match ${result.launch_stats.match_rate.toFixed(1)}% / expire ${
        result.launch_stats.expiration_rate.toFixed(1)
      }%`,
    );
    if (result.project_pending_launches.length > 0) {
      console.log(`  Pending launches: ${result.project_pending_launches.length}`);
    }

    if (result.readiness.host_ready) {
      console.log(`  Ready: ${green("yes")}`);
    } else {
      console.log(`  Ready: ${red("no")}`);
      for (const reason of result.readiness.reasons) {
        console.log(`    - ${reason}`);
      }
    }

    if (result.recommended_commands.length > 0) {
      console.log("  Recommended:");
      for (const command of result.recommended_commands) {
        console.log(`    ${dim(command)}`);
      }
    }

    return result.readiness.host_ready ? 0 : 1;
  } finally {
    client.disconnect();
  }
}

async function worktreeEnsure(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["host"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    console.log(`
i3pm worktree ensure - Ensure daemon runtime context for a worktree

USAGE:
  i3pm worktree ensure <qualified_name> [OPTIONS]

OPTIONS:
  -h, --help        Show this help message
  --json            Output the raw result as JSON
  --host <name>     Explicit target host alias
`);
    return 0;
  }

  const qualifiedName = parsed._[0]?.toString() || "";
  if (!qualifiedName) {
    console.error("Error: qualified_name is required");
    return 1;
  }

  const targetHost = String(parsed.host || "").trim().toLowerCase();

  const client = new DaemonClient();
  try {
    const result = await client.request<{
      switched: boolean;
      context: {
        qualified_name: string;
        target_host: string;
        transport_kind: string;
        connection_key: string;
        context_key: string;
      };
    }>("context.ensure", {
      qualified_name: qualifiedName,
      target_host: targetHost,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    console.log(
      `Context ensure: ${result.switched ? green("switched") : yellow("already aligned")}`,
    );
    console.log(`  Worktree: ${cyan(result.context.qualified_name || qualifiedName)}`);
    console.log(`  Target host: ${magenta(result.context.target_host || "unknown")}`);
    console.log(`  Transport: ${magenta(result.context.transport_kind || "unknown")}`);
    if (result.context.connection_key) {
      console.log(`  Connection: ${result.context.connection_key}`);
    }
    if (result.context.context_key) {
      console.log(`  Context key: ${dim(result.context.context_key)}`);
    }
    return 0;
  } finally {
    client.disconnect();
  }
}

async function worktreeClear(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    console.log(`
i3pm worktree clear - Clear the active daemon worktree context

USAGE:
  i3pm worktree clear [OPTIONS]

OPTIONS:
  -h, --help        Show this help message
  --json            Output the raw result as JSON
`);
    return 0;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<{
      success: boolean;
      previous_project: string | null;
      duration_ms?: number;
    }>("worktree.clear", {});

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    console.log(
      `Cleared worktree context${
        result.previous_project ? ` (was ${cyan(result.previous_project)})` : ""
      }`,
    );
    return 0;
  } finally {
    client.disconnect();
  }
}

/**
 * Main worktree command handler
 */
export async function worktreeCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = String(parsed._[0]);
  const subcommandArgs = parsed._.slice(1).map(String);

  let exitCode = 0;

  switch (subcommand) {
    case "create":
      exitCode = await worktreeCreate(subcommandArgs);
      break;

    case "remove":
    case "delete":
      exitCode = await worktreeRemove(subcommandArgs);
      break;

    case "rename":
    case "mv":
      exitCode = await worktreeRename(subcommandArgs);
      break;

    case "suggest-name":
      exitCode = await worktreeSuggestName(subcommandArgs);
      break;

    case "list":
      exitCode = await worktreeList(subcommandArgs);
      break;

    case "current":
      exitCode = await worktreeCurrent(subcommandArgs);
      break;

    case "clear":
      exitCode = await worktreeClear(subcommandArgs);
      break;

    case "ensure":
      exitCode = await worktreeEnsure(subcommandArgs);
      break;

    case "diagnose":
      exitCode = await worktreeDiagnose(subcommandArgs);
      break;

    case "switch":
      exitCode = await worktreeSwitch(subcommandArgs);
      break;

    case "host":
      exitCode = await worktreeHost(subcommandArgs);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error(
        "Available subcommands: create, remove, rename, suggest-name, list, current, clear, ensure, diagnose, switch, host",
      );
      console.error("Run 'i3pm worktree --help' for more information");
      Deno.exit(1);
  }

  Deno.exit(exitCode);
}
