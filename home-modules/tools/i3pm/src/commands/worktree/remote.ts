import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { DaemonClient } from "../../services/daemon-client.ts";

function showHelp(): void {
  console.log(`
i3pm worktree remote - Manage SSH profiles for worktrees

USAGE:
  i3pm worktree remote <subcommand> [options]

SUBCOMMANDS:
  set <qualified_name>   Configure/update SSH profile
  get <qualified_name>   Show SSH profile for worktree
  unset <qualified_name> Remove SSH profile
  test <qualified_name>  Test SSH connectivity and remote directory
  list                   List all configured SSH profiles

OPTIONS:
  --json                 Output JSON
  -h, --help             Show help

SET OPTIONS:
  --host <host>          SSH host (default: ryzen)
  --user <user>          SSH user (default: current user)
  --dir <path>           Remote working directory (absolute path)
  --port <port>          SSH port (default: 22)

EXAMPLES:
  i3pm worktree remote set vpittamp/nixos-config:main --dir /home/vpittamp/repos/vpittamp/nixos-config/main
  i3pm worktree remote set vpittamp/nixos-config:main --host ryzen --user vpittamp --dir /home/vpittamp/repos/vpittamp/nixos-config/main --port 22
  i3pm worktree remote test vpittamp/nixos-config:main
  i3pm worktree remote list
`);
}

function getRequiredQualifiedName(parsed: ReturnType<typeof parseArgs>): string | null {
  const qualifiedName = parsed._[0]?.toString();
  if (!qualifiedName) {
    return null;
  }
  return qualifiedName;
}

export async function worktreeRemote(args: string[]): Promise<number> {
  if (args.length === 0) {
    showHelp();
    return 0;
  }

  const subcommand = args[0];
  const subArgs = args.slice(1);
  const client = new DaemonClient();

  if (subcommand === "--help" || subcommand === "-h" || subcommand === "help") {
    showHelp();
    return 0;
  }

  try {
    switch (subcommand) {
      case "set": {
        const parsed = parseArgs(subArgs, {
          string: ["host", "user", "dir", "port"],
          boolean: ["json", "help"],
          alias: { h: "help" },
          default: {
            host: "ryzen",
            user: Deno.env.get("USER") || "vpittamp",
            port: "22",
          },
        });

        if (parsed.help) {
          showHelp();
          return 0;
        }

        const qualifiedName = getRequiredQualifiedName(parsed);
        if (!qualifiedName) {
          console.error("Error: qualified_name is required");
          console.error(
            "Usage: i3pm worktree remote set <qualified_name> --dir <remote_dir> [--host ryzen] [--user <user>] [--port <port>]",
          );
          return 1;
        }

        const remoteDir = parsed.dir?.toString();
        if (!remoteDir) {
          console.error("Error: --dir is required");
          return 1;
        }

        const port = Number(parsed.port);
        if (!Number.isFinite(port) || port < 1 || port > 65535) {
          console.error("Error: --port must be between 1 and 65535");
          return 1;
        }

        const result = await client.request<{
          success: boolean;
          qualified_name: string;
          remote: {
            enabled: boolean;
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          };
          active_context_updated: boolean;
        }>("worktree.remote.set", {
          qualified_name: qualifiedName,
          host: parsed.host,
          user: parsed.user,
          port,
          remote_dir: remoteDir,
          enabled: true,
        });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`✓ Remote profile set for ${result.qualified_name}`);
          console.log(`  Host: ${result.remote.user}@${result.remote.host}:${result.remote.port}`);
          console.log(`  Remote dir: ${result.remote.remote_dir}`);
          if (result.active_context_updated) {
            console.log("  Active context updated");
          }
        }
        return 0;
      }

      case "get": {
        const parsed = parseArgs(subArgs, {
          boolean: ["json", "help"],
          alias: { h: "help" },
        });
        if (parsed.help) {
          showHelp();
          return 0;
        }
        const qualifiedName = getRequiredQualifiedName(parsed);
        if (!qualifiedName) {
          console.error("Error: qualified_name is required");
          return 1;
        }

        const result = await client.request<{
          success: boolean;
          qualified_name: string;
          configured: boolean;
          remote: {
            enabled: boolean;
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          } | null;
        }>("worktree.remote.get", { qualified_name: qualifiedName });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (!result.configured || !result.remote) {
          console.log(`No remote profile configured for ${result.qualified_name}`);
        } else {
          console.log(`Remote profile for ${result.qualified_name}`);
          console.log(`  Host: ${result.remote.user}@${result.remote.host}:${result.remote.port}`);
          console.log(`  Remote dir: ${result.remote.remote_dir}`);
        }
        return 0;
      }

      case "unset": {
        const parsed = parseArgs(subArgs, {
          boolean: ["json", "help"],
          alias: { h: "help" },
        });
        if (parsed.help) {
          showHelp();
          return 0;
        }
        const qualifiedName = getRequiredQualifiedName(parsed);
        if (!qualifiedName) {
          console.error("Error: qualified_name is required");
          return 1;
        }

        const result = await client.request<{
          success: boolean;
          qualified_name: string;
          removed: boolean;
          active_context_updated: boolean;
        }>("worktree.remote.unset", { qualified_name: qualifiedName });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (result.removed) {
          console.log(`✓ Remote profile removed for ${result.qualified_name}`);
        } else {
          console.log(`No remote profile existed for ${result.qualified_name}`);
        }
        return 0;
      }

      case "list": {
        const parsed = parseArgs(subArgs, {
          boolean: ["json", "help"],
          alias: { h: "help" },
        });
        if (parsed.help) {
          showHelp();
          return 0;
        }

        const result = await client.request<{
          success: boolean;
          count: number;
          profiles: Array<{
            qualified_name: string;
            is_active: boolean;
            remote: {
              enabled: boolean;
              host: string;
              user: string;
              port: number;
              remote_dir: string;
            };
          }>;
        }>("worktree.remote.list", {});

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (result.count === 0) {
          console.log("No remote profiles configured");
        } else {
          console.log(`Remote profiles (${result.count})`);
          for (const item of result.profiles) {
            const active = item.is_active ? " (active)" : "";
            console.log(`  ${item.qualified_name}${active}`);
            console.log(`    ${item.remote.user}@${item.remote.host}:${item.remote.port}`);
            console.log(`    ${item.remote.remote_dir}`);
          }
        }
        return 0;
      }

      case "test": {
        const parsed = parseArgs(subArgs, {
          string: ["host", "user", "dir", "port"],
          boolean: ["json", "help"],
          alias: { h: "help" },
        });
        if (parsed.help) {
          showHelp();
          return 0;
        }
        const qualifiedName = getRequiredQualifiedName(parsed);
        if (!qualifiedName) {
          console.error("Error: qualified_name is required");
          return 1;
        }

        const params: Record<string, unknown> = { qualified_name: qualifiedName };
        if (parsed.host) params.host = parsed.host;
        if (parsed.user) params.user = parsed.user;
        if (parsed.dir) params.remote_dir = parsed.dir;
        if (parsed.port) {
          const port = Number(parsed.port);
          if (!Number.isFinite(port) || port < 1 || port > 65535) {
            console.error("Error: --port must be between 1 and 65535");
            return 1;
          }
          params.port = port;
        }

        const result = await client.request<{
          success: boolean;
          qualified_name: string;
          duration_ms: number;
          message: string;
          stderr: string;
          remote: {
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          };
        }>("worktree.remote.test", params);

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          const status = result.success ? "✓" : "✗";
          console.log(`${status} ${result.message}`);
          console.log(
            `  Target: ${result.remote.user}@${result.remote.host}:${result.remote.port}`,
          );
          console.log(`  Remote dir: ${result.remote.remote_dir}`);
          console.log(`  Duration: ${result.duration_ms}ms`);
          if (result.stderr) {
            console.log(`  Error: ${result.stderr}`);
          }
        }
        return result.success ? 0 : 1;
      }

      default:
        console.error(`Unknown subcommand: ${subcommand}`);
        showHelp();
        return 1;
    }
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    client.disconnect();
  }
}
