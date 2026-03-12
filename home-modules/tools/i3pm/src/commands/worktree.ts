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
import { worktreeRemote } from "./worktree/remote.ts";
import { worktreeRename } from "./worktree/rename.ts";
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
  list [repo]           List worktrees for a repository (Feature 100)
  current               Show active daemon worktree context
  clear                 Clear active daemon worktree context
  ensure <name>         Ensure daemon runtime context
  diagnose [name]       Diagnose SSH/runtime readiness for a worktree
  switch <name>         Switch to a worktree by qualified name (Feature 101)
  remote <subcommand>   Manage SSH remote profiles for worktrees (Feature 087)

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
  i3pm worktree current
  i3pm worktree clear
  i3pm worktree ensure vpittamp/nixos-config:main
  i3pm worktree diagnose vpittamp/nixos-config:main
  i3pm worktree remote set vpittamp/nixos-config:main --dir /home/vpittamp/repos/vpittamp/nixos-config/main

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
      execution_mode: string;
      connection_key: string;
      context_key: string;
      remote_enabled: boolean;
      remote?: {
        host?: string;
        user?: string;
        port?: number;
        remote_dir?: string;
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
    console.log(`  Mode: ${magenta(context.execution_mode || "local")}`);
    console.log(`  Directory: ${context.directory || context.local_directory || ""}`);
    console.log(`  Local directory: ${context.local_directory || context.directory || ""}`);
    if (context.connection_key) {
      console.log(`  Connection: ${context.connection_key}`);
    }
    if (context.context_key) {
      console.log(`  Context key: ${dim(context.context_key)}`);
    }
    if (context.remote_enabled && context.remote) {
      const user = context.remote.user || "unknown";
      const host = context.remote.host || "unknown";
      const port = context.remote.port ?? 22;
      console.log(`  Remote: ${user}@${host}:${port}`);
      if (context.remote.remote_dir) {
        console.log(`  Remote dir: ${context.remote.remote_dir}`);
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
      remote_profile_configured: boolean;
      remote_profile?: {
        enabled: boolean;
        host: string;
        user: string;
        port: number;
        remote_dir: string;
      } | null;
      active_context: {
        qualified_name: string;
        execution_mode: string;
        connection_key: string;
        context_key: string;
        is_global: boolean;
      };
      target_context: {
        execution_mode: string;
        connection_key: string;
        context_key: string;
      };
      remote_test?: {
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
        ssh_terminal_supported: boolean;
        ssh_scoped_gui_supported: boolean;
        ssh_policy: string;
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
        ssh_ready: boolean;
        reasons: string[];
      };
      recommended_commands: string[];
    }>("worktree.diagnose", qualifiedName ? { qualified_name: qualifiedName } : {});

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return result.readiness.ssh_ready ? 0 : 1;
    }

    console.log(`Worktree Diagnosis: ${cyan(result.qualified_name)}`);
    console.log(
      `  Active context: ${
        result.active_context.qualified_name || "global"
      } (${result.active_context.execution_mode})`,
    );
    console.log(`  Target SSH context: ${result.target_context.context_key}`);

    if (result.remote_profile_configured && result.remote_profile) {
      console.log(
        `  Remote profile: ${result.remote_profile.user}@${result.remote_profile.host}:${result.remote_profile.port}`,
      );
      console.log(`  Remote dir: ${result.remote_profile.remote_dir}`);
    } else {
      console.log(`  Remote profile: ${red("not configured")}`);
    }

    if (result.remote_test) {
      const status = result.remote_test.success ? green("passed") : red("failed");
      console.log(`  Remote test: ${status} (${result.remote_test.duration_ms}ms)`);
      if (result.remote_test.stderr) {
        console.log(`  Remote error: ${result.remote_test.stderr}`);
      }
    } else {
      console.log(`  Remote test: ${dim("skipped")}`);
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

    console.log(`  SSH launch policy: ${result.launch_support.ssh_policy}`);
    console.log(
      `  Launch correlation: match ${result.launch_stats.match_rate.toFixed(1)}% / expire ${
        result.launch_stats.expiration_rate.toFixed(1)
      }%`,
    );
    if (result.project_pending_launches.length > 0) {
      console.log(`  Pending launches: ${result.project_pending_launches.length}`);
    }

    if (result.readiness.ssh_ready) {
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

    return result.readiness.ssh_ready ? 0 : 1;
  } finally {
    client.disconnect();
  }
}

async function worktreeEnsure(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "local"],
    string: ["variant"],
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
  --local           Force local context
  --variant <name>  Explicit variant (local|ssh)
`);
    return 0;
  }

  const qualifiedName = parsed._[0]?.toString() || "";
  if (!qualifiedName) {
    console.error("Error: qualified_name is required");
    return 1;
  }

  let targetVariant = String(parsed.variant || "").trim().toLowerCase();
  if (parsed.local) {
    targetVariant = "local";
  }
  if (targetVariant && !["local", "ssh"].includes(targetVariant)) {
    console.error("Error: --variant must be 'local' or 'ssh'");
    return 1;
  }

  const client = new DaemonClient();
  try {
    const result = await client.request<{
      switched: boolean;
      context: {
        qualified_name: string;
        execution_mode: string;
        connection_key: string;
        context_key: string;
      };
    }>("context.ensure", {
      qualified_name: qualifiedName,
      target_variant: targetVariant,
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return 0;
    }

    console.log(`Context ensure: ${result.switched ? green("switched") : yellow("already aligned")}`);
    console.log(`  Worktree: ${cyan(result.context.qualified_name || qualifiedName)}`);
    console.log(`  Mode: ${magenta(result.context.execution_mode || "local")}`);
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

    console.log(`Cleared worktree context${result.previous_project ? ` (was ${cyan(result.previous_project)})` : ""}`);
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

    case "remote":
      exitCode = await worktreeRemote(subcommandArgs);
      break;

    default:
      console.error(`Error: Unknown subcommand '${subcommand}'`);
      console.error("");
      console.error(
        "Available subcommands: create, remove, rename, list, current, clear, ensure, diagnose, switch, remote",
      );
      console.error("Run 'i3pm worktree --help' for more information");
      Deno.exit(1);
  }

  Deno.exit(exitCode);
}
