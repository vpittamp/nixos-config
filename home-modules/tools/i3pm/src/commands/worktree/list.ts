// Feature 100: Worktree List Command
// T041: Create `i3pm worktree list [repo]` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { type Worktree, WorktreeSchema } from "../../../models/repository.ts";
import {
  detectRepoPath,
  getDefaultBranch,
  hasGitWorktreeRoot,
  runGitGtr,
} from "./helpers.ts";

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

  const defaultBranch = (await getDefaultBranch(repoPath)) || "main";

  const useGtr = await hasGitWorktreeRoot(repoPath);
  let output: Deno.CommandOutput;
  if (useGtr) {
    // gtr-first workflow: read worktrees through git gtr porcelain output.
    output = await runGitGtr(repoPath, ["list", "--porcelain"]);
  } else {
    const cmd = new Deno.Command("git", {
      args: ["-C", `${repoPath}/.bare`, "worktree", "list", "--porcelain"],
      stdout: "piped",
      stderr: "piped",
    });
    output = await cmd.output();
  }

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    const stdout = new TextDecoder().decode(output.stdout);
    console.error(useGtr ? "Error: git gtr list failed" : "Error: git worktree list failed");
    if (stderr.trim()) console.error(stderr.trim());
    else if (stdout.trim()) console.error(stdout.trim());
    return 1;
  }

  const stdout = new TextDecoder().decode(output.stdout);
  const worktrees = useGtr
    ? parseGtrWorktreeList(stdout, defaultBranch)
    : parseNativeWorktreeList(stdout, defaultBranch, repoPath);

  if (parsed.json) {
    console.log(JSON.stringify(worktrees, null, 2));
    return 0;
  }

  // Get repo name from path
  const parts = repoPath.split("/").filter(Boolean);
  const repoName = parts.slice(-2).join("/");

  console.log(`Worktrees for ${repoName}:`);
  console.log("");

  for (const wt of worktrees) {
    const mainMarker = wt.is_main ? " (main)" : "";
    const cleanStatus = wt.is_clean === false ? " [dirty]" : " [clean]";
    const commitInfo = wt.commit ? ` @ ${wt.commit.substring(0, 7)}` : "";

    console.log(`  ${wt.branch}${mainMarker}${cleanStatus}${commitInfo}`);
    console.log(`    Path: ${wt.path}`);
  }

  return 0;
}

/**
 * Parse git gtr list --porcelain output.
 */
function parseGtrWorktreeList(output: string, defaultBranch: string): Worktree[] {
  const worktrees: Worktree[] = [];
  const lines = output
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  for (const line of lines) {
    const parts = line.split("\t");
    if (parts.length < 2) continue;

    const rawPath = parts[0];
    const path = rawPath.endsWith("/.bare") ? rawPath.slice(0, -"/.bare".length) : rawPath;
    const branch = parts[1];
    const status = (parts[2] || "ok").toLowerCase();

    const isClean = status === "ok";
    const isMain = branch === defaultBranch || branch === "main" || branch === "master";

    const candidate = {
      branch,
      path,
      commit: null,
      is_clean: isClean,
      ahead: 0,
      behind: 0,
      is_main: isMain,
      is_merged: false,
      is_stale: false,
      has_conflicts: status.includes("conflict"),
      staged_count: 0,
      modified_count: isClean ? 0 : 1,
      untracked_count: 0,
      last_commit_timestamp: 0,
      last_commit_message: "",
    };

    const parsed = WorktreeSchema.safeParse(candidate);
    if (parsed.success) {
      worktrees.push(parsed.data);
    }
  }

  return worktrees;
}

/**
 * Parse native git worktree list --porcelain output.
 */
function parseNativeWorktreeList(
  output: string,
  defaultBranch: string,
  repoPath: string,
): Worktree[] {
  const worktrees: Worktree[] = [];
  const entries = output.split("\n\n").filter((entry) => entry.trim());

  for (const entry of entries) {
    const lines = entry.split("\n");
    let path = "";
    let branch = "HEAD";

    for (const line of lines) {
      if (line.startsWith("worktree ")) {
        path = line.slice("worktree ".length);
      } else if (line.startsWith("branch refs/heads/")) {
        branch = line.slice("branch refs/heads/".length);
      }
    }

    if (!path) continue;
    if (path.endsWith("/.bare")) {
      path = repoPath;
      branch = defaultBranch;
    }

    const candidate = {
      branch,
      path,
      commit: null,
      is_clean: true,
      ahead: 0,
      behind: 0,
      is_main: branch === defaultBranch || branch === "main" || branch === "master",
      is_merged: false,
      is_stale: false,
      has_conflicts: false,
      staged_count: 0,
      modified_count: 0,
      untracked_count: 0,
      last_commit_timestamp: 0,
      last_commit_message: "",
    };

    const parsed = WorktreeSchema.safeParse(candidate);
    if (parsed.success) worktrees.push(parsed.data);
  }

  return worktrees;
}
