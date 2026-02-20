// Feature 100: Worktree Create Command
// T023: Create `i3pm worktree create <branch>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import {
  type WorktreeCreateRequest,
  WorktreeCreateRequestSchema,
} from "../../../models/repository.ts";
import {
  detectRepoPath,
  findWorktreePath,
  getDefaultBranch,
  hasGitWorktreeRoot,
  refreshDiscovery,
  repoQualifiedFromPath,
  runGitGtr,
} from "./helpers.ts";

/**
 * Create a new worktree as sibling to main.
 *
 * Must be run from within a bare repository structure.
 * Creates worktree at: ~/repos/<account>/<repo>/<branch>/
 */
export async function worktreeCreate(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["from", "repo"],
    default: {
      from: "",
    },
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 1) {
    console.error("Usage: i3pm worktree create <branch> [--from <base>] [--repo <account/repo>]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm worktree create 100-feature");
    console.error("  i3pm worktree create feature/auth --from main");
    console.error("  i3pm worktree create 101-bugfix --from develop");
    console.error("  i3pm worktree create review --repo vpittamp/nixos-config");
    return 1;
  }

  const branch = positionalArgs[0];

  // Validate request
  let request: WorktreeCreateRequest;
  try {
    request = WorktreeCreateRequestSchema.parse({
      branch,
      from: parsed.from || "main",
      repo: parsed.repo,
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      const zodError = error as unknown as { errors: Array<{ path: string[]; message: string }> };
      console.error("Error: Invalid worktree create request:");
      for (const issue of zodError.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }
    throw error;
  }

  // Detect repository context
  const repoPath = await detectRepoPath(request.repo);
  if (!repoPath) {
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  // Prefer explicit --from; otherwise use discovered default branch.
  let baseBranch = request.from;
  if (!parsed.from) {
    const discoveredDefault = await getDefaultBranch(repoPath);
    if (discoveredDefault) baseBranch = discoveredDefault;
  }

  console.log(`Creating worktree '${branch}' from '${baseBranch}'...`);

  const useGtr = await hasGitWorktreeRoot(repoPath);
  let output: Deno.CommandOutput;

  if (useGtr) {
    // gtr-first workflow for repositories with a git worktree root.
    const gtrArgs = ["new", branch, "--yes"];
    if (baseBranch) gtrArgs.push("--from", baseBranch);
    output = await runGitGtr(repoPath, gtrArgs);
  } else {
    // Bare-repo fallback: preserve sibling worktree layout (<repo>/<branch>).
    const worktreePath = `${repoPath}/${branch}`;
    const cmd = new Deno.Command("git", {
      args: [
        "-C",
        `${repoPath}/.bare`,
        "worktree",
        "add",
        worktreePath,
        "-b",
        branch,
        baseBranch,
      ],
      stdout: "piped",
      stderr: "piped",
    });
    output = await cmd.output();
  }

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    const stdout = new TextDecoder().decode(output.stdout);
    console.error(useGtr ? "Error: git gtr new failed" : "Error: git worktree add failed");
    if (stderr.trim()) console.error(stderr.trim());
    else if (stdout.trim()) console.error(stdout.trim());
    return 1;
  }

  // Keep repos.json current for panel and project switching.
  await refreshDiscovery();
  const repoQualified = request.repo || repoQualifiedFromPath(repoPath);
  const discoveredPath = await findWorktreePath(repoQualified, branch);
  const outputPath = discoveredPath || `${repoPath}/${branch}`;

  console.log(`Created worktree at: ${outputPath}`);

  console.log("");
  console.log("Next actions:");
  console.log(`  i3pm worktree switch ${repoQualified}:${branch}`);
  console.log(`  i3pm scratchpad toggle ${repoQualified}:${branch}`);
  console.log(`  worktree-lazygit ${outputPath} status`);
  console.log(`  ghostty -e yazi ${outputPath}`);

  return 0;
}
