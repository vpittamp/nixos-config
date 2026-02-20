// Feature 100: Worktree Remove Command
// T048: Create `i3pm worktree remove <branch>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import {
  type WorktreeRemoveRequest,
  WorktreeRemoveRequestSchema,
} from "../../../models/repository.ts";
import {
  hasGitWorktreeRoot,
  refreshDiscovery,
  resolveWorktreeTarget,
  runGitGtr,
} from "./helpers.ts";

const HOME = Deno.env.get("HOME") || "";
const REMOTE_PROFILES_FILE = `${HOME}/.config/i3/worktree-remote-profiles.json`;
const ACTIVE_WORKTREE_FILE = `${HOME}/.config/i3/active-worktree.json`;

async function removeRemoteProfile(qualifiedName: string): Promise<boolean> {
  try {
    const content = await Deno.readTextFile(REMOTE_PROFILES_FILE);
    const data = JSON.parse(content);
    if (!data || typeof data !== "object") return false;

    const profiles = (data as Record<string, unknown>).profiles;
    if (!profiles || typeof profiles !== "object") return false;

    const profileMap = profiles as Record<string, unknown>;
    if (!(qualifiedName in profileMap)) return false;

    delete profileMap[qualifiedName];
    (data as Record<string, unknown>).updated_at = Math.floor(Date.now() / 1000);
    await Deno.writeTextFile(REMOTE_PROFILES_FILE, `${JSON.stringify(data, null, 2)}\n`);
    return true;
  } catch {
    // best-effort cleanup
    return false;
  }
}

async function clearActiveContextIfRemoved(qualifiedName: string): Promise<void> {
  try {
    const content = await Deno.readTextFile(ACTIVE_WORKTREE_FILE);
    const active = JSON.parse(content);
    if (active?.qualified_name !== qualifiedName) return;

    const clearCmd = new Deno.Command("i3pm", {
      args: ["worktree", "clear"],
      stdout: "null",
      stderr: "null",
    });
    await clearCmd.output();
  } catch {
    // best-effort active context cleanup
  }
}

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
    console.error(
      "Usage: i3pm worktree remove <branch|account/repo:branch> [--force] [--repo <account/repo>]",
    );
    console.error("");
    console.error("Examples:");
    console.error("  i3pm worktree remove 100-feature");
    console.error("  i3pm worktree remove 101-bugfix --force");
    console.error("  i3pm worktree remove review --repo vpittamp/nixos");
    return 1;
  }

  const branchOrQualified = positionalArgs[0];

  // Validate request
  let request: WorktreeRemoveRequest;
  try {
    const branchCandidate = branchOrQualified.includes(":")
      ? branchOrQualified.slice(branchOrQualified.indexOf(":") + 1)
      : branchOrQualified;
    request = WorktreeRemoveRequestSchema.parse({
      branch: branchCandidate,
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

  const target = await resolveWorktreeTarget(branchOrQualified, request.repo);
  if (!target) {
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  const branch = target.branch;

  if (branch === "main" || branch === "master") {
    console.error("Error: Cannot remove main worktree");
    console.error("The main/master worktree must always exist for the bare repository pattern.");
    return 1;
  }

  console.log(`Removing worktree '${target.qualifiedName}'...`);

  const useGtr = await hasGitWorktreeRoot(target.repoPath);
  let output: Deno.CommandOutput;

  if (useGtr) {
    const gtrArgs = ["rm", branch, "--yes"];
    if (request.force) gtrArgs.push("--force");
    output = await runGitGtr(target.repoPath, gtrArgs);
  } else {
    const removeArgs = ["-C", `${target.repoPath}/.bare`, "worktree", "remove"];
    if (request.force) removeArgs.push("--force");
    removeArgs.push(`${target.repoPath}/${branch}`);
    const cmd = new Deno.Command("git", {
      args: removeArgs,
      stdout: "piped",
      stderr: "piped",
    });
    output = await cmd.output();
  }

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    const stdout = new TextDecoder().decode(output.stdout);
    console.error(useGtr ? "Error: git gtr rm failed" : "Error: git worktree remove failed");
    if (stderr.trim()) console.error(stderr.trim());
    else if (stdout.trim()) console.error(stdout.trim());
    return 1;
  }

  await refreshDiscovery();
  await removeRemoteProfile(target.qualifiedName);
  await clearActiveContextIfRemoved(target.qualifiedName);
  console.log(`Removed worktree: ${target.qualifiedName}`);

  return 0;
}
