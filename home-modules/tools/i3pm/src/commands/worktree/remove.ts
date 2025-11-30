// Feature 100: Worktree Remove Command
// T048: Create `i3pm worktree remove <branch>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { WorktreeRemoveRequestSchema, type WorktreeRemoveRequest } from "../../../models/repository.ts";

/**
 * Remove a worktree from a repository.
 *
 * Fails if:
 * - Worktree has uncommitted changes (unless --force)
 * - Trying to remove main/master worktree
 */
export async function worktreeRemove(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["repo"],
    boolean: ["force"],
    default: {
      force: false,
    },
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 1) {
    console.error("Usage: i3pm worktree remove <branch> [--force] [--repo <account/repo>]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm worktree remove 100-feature");
    console.error("  i3pm worktree remove 101-bugfix --force");
    console.error("  i3pm worktree remove review --repo vpittamp/nixos");
    return 1;
  }

  const branch = positionalArgs[0];

  // Validate request
  let request: WorktreeRemoveRequest;
  try {
    request = WorktreeRemoveRequestSchema.parse({
      branch,
      repo: parsed.repo,
      force: parsed.force,
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      const zodError = error as unknown as { errors: Array<{ path: string[]; message: string }> };
      console.error("Error: Invalid worktree remove request:");
      for (const issue of zodError.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }
    throw error;
  }

  // Prevent removing main/master
  if (branch === "main" || branch === "master") {
    console.error("Error: Cannot remove main worktree");
    console.error("The main/master worktree must always exist for the bare repository pattern.");
    return 1;
  }

  // Detect repository path
  const repoPath = await detectRepoPath(request.repo);
  if (!repoPath) {
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  const barePath = `${repoPath}/.bare`;
  const worktreePath = `${repoPath}/${branch}`;

  // Check if worktree exists
  try {
    await Deno.stat(worktreePath);
  } catch {
    console.error(`Error: Worktree not found: ${worktreePath}`);
    return 1;
  }

  // Check for uncommitted changes (unless force)
  if (!request.force) {
    const statusCmd = new Deno.Command("git", {
      args: ["-C", worktreePath, "status", "--porcelain"],
      stdout: "piped",
      stderr: "piped",
    });

    const statusOutput = await statusCmd.output();
    const statusStdout = new TextDecoder().decode(statusOutput.stdout).trim();

    if (statusStdout.length > 0) {
      console.error("Error: Worktree has uncommitted changes");
      console.error("");
      console.error("Status:");
      console.error(statusStdout);
      console.error("");
      console.error("Use --force to remove anyway.");
      return 1;
    }
  }

  console.log(`Removing worktree '${branch}'...`);

  // Remove the worktree
  const removeArgs = ["-C", barePath, "worktree", "remove"];
  if (request.force) {
    removeArgs.push("--force");
  }
  removeArgs.push(worktreePath);

  const cmd = new Deno.Command("git", {
    args: removeArgs,
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    console.error(`Error: git worktree remove failed`);
    console.error(stderr);
    return 1;
  }

  console.log(`Removed worktree: ${worktreePath}`);

  // Feature 102: Auto-discover after worktree removal to update repos.json
  // This ensures the monitoring panel and other tools reflect the removal
  const discoverCmd = new Deno.Command("i3pm", {
    args: ["discover"],
    stdout: "piped",
    stderr: "piped",
  });

  const discoverOutput = await discoverCmd.output();
  if (!discoverOutput.success) {
    const stderr = new TextDecoder().decode(discoverOutput.stderr);
    console.error("");
    console.error("Warning: Failed to update repos.json (worktree still removed)");
    console.error(stderr);
  }

  return 0;
}

/**
 * Detect repository path from current directory or --repo flag.
 */
async function detectRepoPath(repo?: string): Promise<string | null> {
  const home = Deno.env.get("HOME") || "";

  if (repo) {
    // Check if it's a full account/repo path
    if (repo.includes("/")) {
      const [account, repoName] = repo.split("/");
      const path = `${home}/repos/${account}/${repoName}`;
      try {
        await Deno.stat(`${path}/.bare`);
        return path;
      } catch {
        return null;
      }
    }

    // Search for repo by name in all account directories
    const reposBase = `${home}/repos`;
    try {
      for await (const entry of Deno.readDir(reposBase)) {
        if (entry.isDirectory) {
          const path = `${reposBase}/${entry.name}/${repo}`;
          try {
            await Deno.stat(`${path}/.bare`);
            return path;
          } catch {
            // Not found in this account, continue
          }
        }
      }
    } catch {
      // repos directory doesn't exist
    }

    return null;
  }

  // Detect from current directory
  const cwd = Deno.cwd();

  // Walk up the directory tree looking for .bare/
  let dir = cwd;
  while (dir !== "/") {
    try {
      const bareStat = await Deno.stat(`${dir}/.bare`);
      if (bareStat.isDirectory) {
        return dir;
      }
    } catch {
      // Not found, continue up
    }

    // Go up one level
    const parent = dir.substring(0, dir.lastIndexOf("/"));
    if (parent === dir || parent === "") {
      break;
    }
    dir = parent;
  }

  return null;
}
