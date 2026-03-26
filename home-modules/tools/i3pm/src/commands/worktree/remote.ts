import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { DaemonClient } from "../../services/daemon-client.ts";

function showHelp(): void {
  console.log(`
i3pm worktree host - Manage non-local host profiles for worktrees

USAGE:
  i3pm worktree host <subcommand> [options]

SUBCOMMANDS:
  set <qualified_name>   Configure/update host profile
  get <qualified_name>   Show host profile for worktree
  unset <qualified_name> Remove host profile
  test <qualified_name>  Test host connectivity and directory
  list                   List all configured host profiles

OPTIONS:
  --json                 Output JSON
  -h, --help             Show help

SET OPTIONS:
  --host <host>          Target host alias (default: ryzen)
  --user <user>          SSH user (default: current user)
  --dir <path>           Host working directory (absolute path)
  --port <port>          SSH port (default: 22)

EXAMPLES:
  i3pm worktree host set vpittamp/nixos-config:main --host thinkpad --dir /home/vpittamp/repos/vpittamp/nixos-config/main
  i3pm worktree host test vpittamp/nixos-config:main
  i3pm worktree host list
`);
}

function getRequiredQualifiedName(parsed: ReturnType<typeof parseArgs>): string | null {
  const qualifiedName = parsed._[0]?.toString();
  if (!qualifiedName) {
    return null;
  }
  return qualifiedName;
}

export async function worktreeHost(args: string[]): Promise<number> {
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
            "Usage: i3pm worktree host set <qualified_name> --dir <directory> [--host thinkpad] [--user <user>] [--port <port>]",
          );
          return 1;
        }

        const directory = parsed.dir?.toString();
        if (!directory) {
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
          host_profile: {
            enabled: boolean;
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          };
          active_context_updated: boolean;
        }>("worktree.host.set", {
          qualified_name: qualifiedName,
          host: parsed.host,
          user: parsed.user,
          port,
          remote_dir: directory,
          enabled: true,
        });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`✓ Host profile set for ${result.qualified_name}`);
          console.log(`  Target host: ${result.host_profile.host}`);
          console.log(`  Connection: ${result.host_profile.user}@${result.host_profile.host}:${result.host_profile.port}`);
          console.log(`  Host dir: ${result.host_profile.remote_dir}`);
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
          host_profile: {
            enabled: boolean;
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          } | null;
        }>("worktree.host.get", { qualified_name: qualifiedName });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (!result.configured || !result.host_profile) {
          console.log(`No host profile configured for ${result.qualified_name}`);
        } else {
          console.log(`Host profile for ${result.qualified_name}`);
          console.log(`  Target host: ${result.host_profile.host}`);
          console.log(`  Connection: ${result.host_profile.user}@${result.host_profile.host}:${result.host_profile.port}`);
          console.log(`  Host dir: ${result.host_profile.remote_dir}`);
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
        }>("worktree.host.unset", { qualified_name: qualifiedName });

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (result.removed) {
          console.log(`✓ Host profile removed for ${result.qualified_name}`);
        } else {
          console.log(`No host profile existed for ${result.qualified_name}`);
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
            host_profile: {
              enabled: boolean;
              host: string;
              user: string;
              port: number;
              remote_dir: string;
            };
          }>;
        }>("worktree.host.list", {});

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else if (result.count === 0) {
          console.log("No host profiles configured");
        } else {
          console.log(`Host profiles (${result.count})`);
          for (const item of result.profiles) {
            const active = item.is_active ? " (active)" : "";
            console.log(`  ${item.qualified_name}${active}`);
            console.log(`    ${item.host_profile.host}`);
            console.log(`    ${item.host_profile.user}@${item.host_profile.host}:${item.host_profile.port}`);
            console.log(`    ${item.host_profile.remote_dir}`);
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
          host_profile: {
            host: string;
            user: string;
            port: number;
            remote_dir: string;
          };
        }>("worktree.host.test", params);

        if (parsed.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          const status = result.success ? "✓" : "✗";
          console.log(`${status} ${result.message}`);
          console.log(`  Target host: ${result.host_profile.host}`);
          console.log(`  Connection: ${result.host_profile.user}@${result.host_profile.host}:${result.host_profile.port}`);
          console.log(`  Host dir: ${result.host_profile.remote_dir}`);
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

export const worktreeRemote = worktreeHost;
