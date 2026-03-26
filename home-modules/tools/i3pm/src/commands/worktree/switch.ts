/**
 * i3pm worktree switch - Switch to a worktree by qualified name
 * Feature 101: Click-to-switch for discovered worktrees
 *
 * Switches the active project context to a discovered worktree,
 * enabling app launching with the correct environment.
 */

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { DaemonClient } from "../../services/daemon-client.ts";

/**
 * Show switch command help
 */
function showHelp(): void {
  console.log(`
i3pm worktree switch - Switch to a worktree by qualified name

USAGE:
  i3pm worktree switch [--host <host>] <qualified_name>

ARGUMENTS:
  qualified_name    Worktree qualified name (account/repo:branch)
                    or repository qualified name (account/repo) for main worktree

OPTIONS:
  -h, --help        Show this help message
  --json            Output result as JSON
  --host <host>     Target host alias for this worktree context

EXAMPLES:
  # Switch to specific worktree
  i3pm worktree switch vpittamp/nixos-config:main
  i3pm worktree switch --host thinkpad vpittamp/nixos-config:main
  i3pm worktree switch PittampalliOrg/stacks:feature-branch

  # Switch to repository's main worktree
  i3pm worktree switch vpittamp/nixos-config

NOTES:
  - Sets active project to the qualified name
  - Stores worktree directory for app launcher context
  - Applies window filtering based on new project context
  - Works with Feature 100 bare repository structure
`);
  Deno.exit(0);
}

/**
 * Switch to a worktree
 */
export async function worktreeSwitch(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["host"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    showHelp();
  }

  const qualifiedName = parsed._[0]?.toString();

  if (!qualifiedName) {
    console.error("Error: Qualified name is required");
    console.error("Usage: i3pm worktree switch [--host <host>] <account/repo:branch>");
    return 1;
  }

  try {
    const client = new DaemonClient();
    const result = await client.request<{
      success: boolean;
      qualified_name: string;
      directory: string;
      local_directory?: string;
      host_profile?: {
        enabled: boolean;
        host: string;
        user: string;
        port: number;
        directory: string;
      } | null;
      target_host: string;
      transport_kind: string;
      branch: string;
      previous_project?: string;
      duration_ms?: number;
    }>("worktree.switch", {
      qualified_name: qualifiedName,
      target_host: parsed.host || "",
    });

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`✓ Switched to worktree: ${result.qualified_name}`);
      console.log(`  Directory: ${result.directory}`);
      if (result.local_directory && result.local_directory !== result.directory) {
        console.log(`  Local directory: ${result.local_directory}`);
      }
      console.log(`  Target host: ${result.target_host}`);
      console.log(`  Transport: ${result.transport_kind}`);
      if (result.host_profile?.enabled) {
        console.log(`  Host profile: ${result.host_profile.user}@${result.host_profile.host}:${result.host_profile.port}`);
      }
      console.log(`  Branch: ${result.branch}`);
      if (result.previous_project) {
        console.log(`  Previous: ${result.previous_project}`);
      }
      if (result.duration_ms) {
        console.log(`  Duration: ${result.duration_ms.toFixed(2)}ms`);
      }
    }

    return 0;
  } catch (error) {
    if (parsed.json) {
      console.log(JSON.stringify(
        {
          success: false,
          error: error instanceof Error ? error.message : String(error),
        },
        null,
        2,
      ));
    } else {
      console.error(`Error: ${error instanceof Error ? error.message : error}`);
    }
    return 1;
  }
}
