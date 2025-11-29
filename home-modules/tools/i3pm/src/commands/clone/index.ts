// Feature 100: Clone Command
// T020: Create `i3pm clone <url>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { CloneRequestSchema, CloneResponseSchema, type CloneRequest } from "../../../models/repository.ts";

/**
 * Execute clone via the daemon shell script.
 *
 * This wraps the i3pm-clone.sh bash script which handles:
 * 1. Bare clone to .bare/
 * 2. .git pointer file creation
 * 3. Default branch detection
 * 4. Main worktree creation
 */
export async function clone(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["account"],
    default: {},
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 1) {
    console.error("Usage: i3pm clone <url> [--account <name>]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm clone git@github.com:vpittamp/nixos.git");
    console.error("  i3pm clone https://github.com/PittampalliOrg/api.git");
    console.error("  i3pm clone git@github.com:vpittamp/nixos.git --account PittampalliOrg");
    return 1;
  }

  const url = positionalArgs[0];

  // Validate request
  let request: CloneRequest;
  try {
    request = CloneRequestSchema.parse({
      url,
      account: parsed.account,
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      const zodError = error as unknown as { errors: Array<{ path: string[]; message: string }> };
      console.error("Error: Invalid clone request:");
      for (const issue of zodError.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }
    throw error;
  }

  // Find the clone script
  const scriptPath = await findCloneScript();
  if (!scriptPath) {
    console.error("Error: i3pm-clone.sh script not found");
    console.error("Please ensure the script is in your PATH or at ~/scripts/i3pm-clone.sh");
    return 1;
  }

  // Build command arguments
  const cmdArgs = [scriptPath, url];
  if (request.account) {
    cmdArgs.push(request.account);
  }

  // Execute the clone script
  const cmd = new Deno.Command("bash", {
    args: cmdArgs,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });

  const process = cmd.spawn();
  const status = await process.status;

  return status.code;
}

async function findCloneScript(): Promise<string | null> {
  const home = Deno.env.get("HOME") || "";

  // Check common locations
  const locations = [
    `${home}/scripts/i3pm-clone.sh`,
    `${home}/.local/bin/i3pm-clone.sh`,
    "/run/current-system/sw/bin/i3pm-clone.sh",
    "/etc/nixos/scripts/i3pm-clone.sh",
  ];

  for (const loc of locations) {
    try {
      const stat = await Deno.stat(loc);
      if (stat.isFile) {
        return loc;
      }
    } catch {
      // File doesn't exist, continue
    }
  }

  // Try finding in PATH
  const pathEnv = Deno.env.get("PATH") || "";
  for (const dir of pathEnv.split(":")) {
    const scriptPath = `${dir}/i3pm-clone.sh`;
    try {
      const stat = await Deno.stat(scriptPath);
      if (stat.isFile) {
        return scriptPath;
      }
    } catch {
      // Continue searching
    }
  }

  return null;
}
