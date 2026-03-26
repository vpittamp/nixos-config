import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { DaemonClient } from "../../services/daemon-client.ts";
import { buildWorktreeMutationErrorResult, buildWorktreeRenameResult } from "./result.ts";
import {
  ensureWorktreeAbsent,
  ensureWorktreePresent,
  getDefaultBranch,
  hasGitWorktreeRoot,
  listNativeWorktrees,
  notifyWorktreeRefresh,
  refreshDiscovery,
  resolveWorktreeTarget,
  runGitBare,
  runGitGtr,
} from "./helpers.ts";

const HOME = Deno.env.get("HOME") || "";
const REMOTE_PROFILES_FILE = `${HOME}/.config/i3/worktree-host-profiles.json`;

function showUsage(): void {
  console.error(
    "Usage: i3pm worktree rename <branch|account/repo:branch> <new-branch> [--repo <account/repo>] [--force]",
  );
  console.error("");
  console.error("Examples:");
  console.error("  i3pm worktree rename 101-old 101-new --repo vpittamp/nixos-config");
  console.error("  i3pm worktree rename vpittamp/nixos-config:101-old 101-new");
}

function isLikelyGitBranch(name: string): boolean {
  if (!name || name.endsWith("/") || name.startsWith(".") || name.includes("..")) return false;
  if (name.includes(" ") || name.includes("~") || name.includes("^") || name.includes(":")) {
    return false;
  }
  if (name.includes("?") || name.includes("*") || name.includes("[")) return false;
  return true;
}

async function moveRemoteProfile(oldQualified: string, newQualified: string): Promise<boolean> {
  try {
    const content = await Deno.readTextFile(REMOTE_PROFILES_FILE);
    const data = JSON.parse(content);
    const profiles = data?.profiles;
    if (!profiles || typeof profiles !== "object") return false;
    if (!(oldQualified in profiles)) return false;
    profiles[newQualified] = profiles[oldQualified];
    delete profiles[oldQualified];
    data.updated_at = Math.floor(Date.now() / 1000);
    await Deno.writeTextFile(REMOTE_PROFILES_FILE, `${JSON.stringify(data, null, 2)}\n`);
    return true;
  } catch {
    // best-effort migration
    return false;
  }
}

async function updateActiveContextIfNeeded(
  oldQualified: string,
  newQualified: string,
): Promise<boolean> {
  const client = new DaemonClient();
  try {
    const active = await client.request<{ qualified_name?: string }>("context.current", {});
    if (active?.qualified_name !== oldQualified) return false;

    const switchCmd = new Deno.Command("i3pm", {
      args: ["worktree", "switch", newQualified],
      stdout: "piped",
      stderr: "piped",
    });
    const output = await switchCmd.output();
    return output.success;
  } catch {
    // best-effort switch for active context
    return false;
  } finally {
    await client.close();
  }
}

export async function worktreeRename(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["repo"],
    boolean: ["force", "json"],
    default: { force: false, json: false },
  });

  const positional = parsed._ as string[];
  if (positional.length < 2) {
    if (parsed.json) {
      console.log(JSON.stringify(
        buildWorktreeMutationErrorResult(
          "rename",
          "Usage: i3pm worktree rename <branch|account/repo:branch> <new-branch> [--repo <account/repo>] [--force]",
        ),
        null,
        2,
      ));
      return 1;
    }
    showUsage();
    return 1;
  }

  const oldTarget = String(positional[0]);
  const newBranch = String(positional[1]);

  if (!isLikelyGitBranch(newBranch)) {
    if (parsed.json) {
      console.log(JSON.stringify(
        buildWorktreeMutationErrorResult("rename", `Invalid new branch name: ${newBranch}`),
        null,
        2,
      ));
      return 1;
    }
    console.error(`Error: invalid new branch name: ${newBranch}`);
    return 1;
  }

  const resolved = await resolveWorktreeTarget(oldTarget, parsed.repo?.toString());
  if (!resolved) {
    if (parsed.json) {
      console.log(JSON.stringify(
        buildWorktreeMutationErrorResult(
          "rename",
          "Not in a bare repository structure. Run from within a repository worktree or specify --repo.",
        ),
        null,
        2,
      ));
      return 1;
    }
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  const newQualified = `${resolved.repoQualified}:${newBranch}`;
  console.log(`Renaming worktree '${resolved.qualifiedName}' -> '${newQualified}'...`);

  const useGtr = await hasGitWorktreeRoot(resolved.repoPath);
  if (useGtr) {
    const gtrArgs = ["mv", resolved.branch, newBranch, "--yes"];
    if (parsed.force) gtrArgs.push("--force");

    const output = await runGitGtr(resolved.repoPath, gtrArgs);
    if (!output.success) {
      const stderr = new TextDecoder().decode(output.stderr);
      const stdout = new TextDecoder().decode(output.stdout);
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult(
            "rename",
            stderr.trim() || stdout.trim() || "git gtr mv failed",
          ),
          null,
          2,
        ));
        return 1;
      }
      console.error("Error: git gtr mv failed");
      if (stderr.trim()) console.error(stderr.trim());
      else if (stdout.trim()) console.error(stdout.trim());
      return 1;
    }
  } else {
    const defaultBranch = (await getDefaultBranch(resolved.repoPath)) || "main";
    if (
      resolved.branch === "main" || resolved.branch === "master" ||
      resolved.branch === defaultBranch
    ) {
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult("rename", "Cannot rename main/default worktree branch."),
          null,
          2,
        ));
        return 1;
      }
      console.error("Error: Cannot rename main/default worktree branch");
      return 1;
    }

    const worktrees = await listNativeWorktrees(resolved.repoPath);
    const targetEntry = worktrees.find((entry) => entry.branch === resolved.branch);

    if (!targetEntry) {
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult(
            "rename",
            `Could not find worktree for branch '${resolved.branch}'`,
          ),
          null,
          2,
        ));
        return 1;
      }
      console.error(`Error: Could not find worktree for branch '${resolved.branch}'`);
      return 1;
    }

    if (targetEntry.isBare) {
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult("rename", "Cannot rename bare root worktree."),
          null,
          2,
        ));
        return 1;
      }
      console.error("Error: Cannot rename bare root worktree");
      return 1;
    }

    const branchExists = await runGitBare(resolved.repoPath, [
      "show-ref",
      "--verify",
      "--quiet",
      `refs/heads/${newBranch}`,
    ]);
    if (branchExists.success) {
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult("rename", `Branch already exists: ${newBranch}`),
          null,
          2,
        ));
        return 1;
      }
      console.error(`Error: Branch already exists: ${newBranch}`);
      return 1;
    }

    const oldPath = targetEntry.path;
    const pathSep = oldPath.lastIndexOf("/");
    const oldDir = pathSep >= 0 ? oldPath.slice(0, pathSep) : resolved.repoPath;
    const oldBase = pathSep >= 0 ? oldPath.slice(pathSep + 1) : oldPath;
    const newPath = oldBase === resolved.branch
      ? `${oldDir}/${newBranch}`
      : `${resolved.repoPath}/${newBranch}`;

    if (newPath !== oldPath) {
      try {
        await Deno.stat(newPath);
        if (parsed.json) {
          console.log(JSON.stringify(
            buildWorktreeMutationErrorResult("rename", `Target path already exists: ${newPath}`),
            null,
            2,
          ));
          return 1;
        }
        console.error(`Error: target path already exists: ${newPath}`);
        return 1;
      } catch {
        // path does not exist: expected
      }

      const moveOutput = await runGitBare(resolved.repoPath, [
        "worktree",
        "move",
        oldPath,
        newPath,
      ]);
      if (!moveOutput.success) {
        const stderr = new TextDecoder().decode(moveOutput.stderr);
        const stdout = new TextDecoder().decode(moveOutput.stdout);
        if (parsed.json) {
          console.log(JSON.stringify(
            buildWorktreeMutationErrorResult(
              "rename",
              stderr.trim() || stdout.trim() || "git worktree move failed",
            ),
            null,
            2,
          ));
          return 1;
        }
        console.error("Error: git worktree move failed");
        if (stderr.trim()) console.error(stderr.trim());
        else if (stdout.trim()) console.error(stdout.trim());
        return 1;
      }
    }

    const branchRename = await runGitBare(resolved.repoPath, [
      "branch",
      "-m",
      resolved.branch,
      newBranch,
    ]);
    if (!branchRename.success) {
      const stderr = new TextDecoder().decode(branchRename.stderr);
      const stdout = new TextDecoder().decode(branchRename.stdout);
      if (parsed.json) {
        console.log(JSON.stringify(
          buildWorktreeMutationErrorResult(
            "rename",
            stderr.trim() || stdout.trim() || "git branch -m failed",
          ),
          null,
          2,
        ));
        return 1;
      }
      console.error("Error: git branch -m failed");
      if (stderr.trim()) console.error(stderr.trim());
      else if (stdout.trim()) console.error(stdout.trim());
      return 1;
    }
  }

  try {
    await refreshDiscovery();
    await ensureWorktreeAbsent(resolved.repoQualified, resolved.branch);
    await ensureWorktreePresent(resolved.repoQualified, newBranch);
    await notifyWorktreeRefresh();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const recovery =
      `Worktree '${resolved.qualifiedName}' was renamed to '${newQualified}', but discovery refresh failed: ${message}. Run: i3pm discover && i3pm worktree switch ${newQualified}`;
    if (parsed.json) {
      console.log(JSON.stringify(
        buildWorktreeMutationErrorResult("rename", recovery),
        null,
        2,
      ));
      return 1;
    }
    console.error(`Error: ${recovery}`);
    return 1;
  }

  const hostProfileMigrated = await moveRemoteProfile(resolved.qualifiedName, newQualified);
  const contextUpdated = await updateActiveContextIfNeeded(resolved.qualifiedName, newQualified);

  if (parsed.json) {
    console.log(JSON.stringify(
      buildWorktreeRenameResult({
        repo: resolved.repoQualified,
        previousBranch: resolved.branch,
        newBranch,
        force: parsed.force,
        hostProfileMigrated,
        contextUpdated,
        usedGtr: useGtr,
      }),
      null,
      2,
    ));
    return 0;
  }

  console.log(`Renamed worktree to: ${newQualified}`);
  return 0;
}
