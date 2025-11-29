// Feature 100: Worktree List Command
// T041: Create `i3pm worktree list [repo]` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { WorktreeSchema, type Worktree } from "../../../models/repository.ts";

/**
 * List all worktrees for a repository.
 */
export async function worktreeList(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    default: {
      json: false,
    },
  });

  const positionalArgs = parsed._ as string[];
  const repoArg = positionalArgs[0] as string | undefined;

  // Detect repository path
  const repoPath = await detectRepoPath(repoArg);
  if (!repoPath) {
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify a repo name");
    console.error("");
    console.error("Usage: i3pm worktree list [repo]");
    console.error("Examples:");
    console.error("  i3pm worktree list");
    console.error("  i3pm worktree list nixos");
    console.error("  i3pm worktree list vpittamp/nixos");
    return 1;
  }

  const barePath = `${repoPath}/.bare`;

  // Get worktree list from git
  const cmd = new Deno.Command("git", {
    args: ["-C", barePath, "worktree", "list", "--porcelain"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    console.error(`Error: git worktree list failed`);
    console.error(stderr);
    return 1;
  }

  const stdout = new TextDecoder().decode(output.stdout);
  const worktrees = parseWorktreeList(stdout, repoPath);

  if (parsed.json) {
    console.log(JSON.stringify(worktrees, null, 2));
    return 0;
  }

  // Get repo name from path
  const parts = repoPath.split("/");
  const repoName = parts.slice(-2).join("/");

  console.log(`Worktrees for ${repoName}:`);
  console.log("");

  for (const wt of worktrees) {
    const mainMarker = wt.is_main ? " (main)" : "";
    const cleanStatus = wt.is_clean === false ? " [dirty]" : "";
    const commitInfo = wt.commit ? ` @ ${wt.commit.substring(0, 7)}` : "";

    console.log(`  ${wt.branch}${mainMarker}${cleanStatus}${commitInfo}`);
    console.log(`    Path: ${wt.path}`);
  }

  return 0;
}

/**
 * Parse git worktree list --porcelain output.
 */
function parseWorktreeList(output: string, repoPath: string): Worktree[] {
  const worktrees: Worktree[] = [];
  const entries = output.split("\n\n").filter(e => e.trim());

  for (const entry of entries) {
    const lines = entry.split("\n");
    const worktree: Partial<Worktree> = {
      ahead: 0,
      behind: 0,
      is_clean: true,
      is_main: false,
    };

    for (const line of lines) {
      if (line.startsWith("worktree ")) {
        worktree.path = line.substring("worktree ".length);
      } else if (line.startsWith("HEAD ")) {
        worktree.commit = line.substring("HEAD ".length);
      } else if (line.startsWith("branch refs/heads/")) {
        worktree.branch = line.substring("branch refs/heads/".length);
      } else if (line === "bare") {
        // Skip bare repo entry
        worktree.path = undefined;
      }
    }

    // Skip if this is the bare repo itself
    if (!worktree.path || worktree.path.endsWith("/.bare")) {
      continue;
    }

    // Skip if branch not detected (detached HEAD)
    if (!worktree.branch) {
      worktree.branch = "HEAD";
    }

    // Detect if this is the main worktree
    if (worktree.branch === "main" || worktree.branch === "master") {
      worktree.is_main = true;
    }

    if (worktree.path && worktree.branch) {
      worktrees.push(worktree as Worktree);
    }
  }

  return worktrees;
}

/**
 * Detect repository path from current directory or repo name.
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
