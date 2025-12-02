// Feature 100: Discover Command
// T030: Create `i3pm discover` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { AccountsStorageSchema, type AccountsStorage } from "../../../models/account.ts";
import {
  BareRepositorySchema,
  RepositoriesStorageSchema,
  WorktreeSchema,
  type BareRepository,
  type RepositoriesStorage,
  type Worktree,
} from "../../../models/repository.ts";

const ACCOUNTS_FILE = `${Deno.env.get("HOME")}/.config/i3/accounts.json`;
const REPOS_FILE = `${Deno.env.get("HOME")}/.config/i3/repos.json`;

async function loadAccounts(): Promise<AccountsStorage> {
  try {
    const content = await Deno.readTextFile(ACCOUNTS_FILE);
    return AccountsStorageSchema.parse(JSON.parse(content));
  } catch {
    return { version: 1, accounts: [] };
  }
}

async function saveRepos(storage: RepositoriesStorage): Promise<void> {
  const dir = REPOS_FILE.substring(0, REPOS_FILE.lastIndexOf("/"));
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(REPOS_FILE, JSON.stringify(storage, null, 2) + "\n");
}

/**
 * Discover all bare repositories and their worktrees.
 */
export async function discover(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json", "quiet"],
    string: ["account"],
    default: {
      json: false,
      quiet: false,
    },
  });

  const startTime = Date.now();

  // Load configured accounts
  const accountsStorage = await loadAccounts();

  if (accountsStorage.accounts.length === 0) {
    if (!parsed.quiet) {
      console.error("No accounts configured.");
      console.error("");
      console.error("Add an account first:");
      console.error("  i3pm account add <name> <path>");
    }
    return 1;
  }

  // Filter accounts if specified
  let accounts = accountsStorage.accounts;
  if (parsed.account) {
    accounts = accounts.filter(a => a.name === parsed.account);
    if (accounts.length === 0) {
      console.error(`Account not found: ${parsed.account}`);
      return 1;
    }
  }

  const repositories: BareRepository[] = [];
  let totalWorktrees = 0;

  for (const account of accounts) {
    if (!parsed.quiet && !parsed.json) {
      console.log(`Scanning ${account.name}...`);
    }

    // Expand ~ in path
    let accountPath = account.path;
    if (accountPath.startsWith("~/")) {
      accountPath = `${Deno.env.get("HOME")}${accountPath.substring(1)}`;
    }

    // Scan account directory for repos
    try {
      for await (const entry of Deno.readDir(accountPath)) {
        if (!entry.isDirectory) continue;

        const repoPath = `${accountPath}/${entry.name}`;
        const barePath = `${repoPath}/.bare`;

        // Check if this is a bare repository structure
        try {
          const stat = await Deno.stat(barePath);
          if (!stat.isDirectory) continue;
        } catch {
          continue; // Not a bare repo
        }

        // Get remote URL
        const remoteUrl = await getRemoteUrl(barePath);
        if (!remoteUrl) continue;

        // Get default branch
        const defaultBranch = await getDefaultBranch(barePath);

        // Get worktrees
        const worktrees = await getWorktrees(barePath, repoPath, defaultBranch);
        totalWorktrees += worktrees.length;

        const repo: BareRepository = {
          account: account.name,
          name: entry.name,
          path: repoPath,
          remote_url: remoteUrl,
          default_branch: defaultBranch,
          worktrees,
          discovered_at: new Date().toISOString(),
        };

        repositories.push(repo);
      }
    } catch (error: unknown) {
      if (!parsed.quiet) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`Warning: Could not scan ${accountPath}: ${message}`);
      }
    }
  }

  const durationMs = Date.now() - startTime;

  // Save discovery results
  const reposStorage: RepositoriesStorage = {
    version: 1,
    last_discovery: new Date().toISOString(),
    repositories,
  };
  await saveRepos(reposStorage);

  if (parsed.json) {
    console.log(JSON.stringify({
      success: true,
      discovered: repositories.length + totalWorktrees,
      repos: repositories.length,
      worktrees: totalWorktrees,
      duration_ms: durationMs,
    }, null, 2));
    return 0;
  }

  if (!parsed.quiet) {
    console.log("");
    console.log(`Discovery complete!`);
    console.log(`  Repositories: ${repositories.length}`);
    console.log(`  Worktrees: ${totalWorktrees}`);
    console.log(`  Duration: ${durationMs}ms`);
  }

  return 0;
}

async function getRemoteUrl(barePath: string): Promise<string | null> {
  const cmd = new Deno.Command("git", {
    args: ["-C", barePath, "remote", "get-url", "origin"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();
  if (!output.success) return null;

  return new TextDecoder().decode(output.stdout).trim();
}

async function getDefaultBranch(barePath: string): Promise<string> {
  // Try symbolic-ref first
  const cmd = new Deno.Command("git", {
    args: ["-C", barePath, "symbolic-ref", "refs/remotes/origin/HEAD"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();
  if (output.success) {
    const ref = new TextDecoder().decode(output.stdout).trim();
    // Extract branch name from refs/remotes/origin/main
    const match = ref.match(/refs\/remotes\/origin\/(.+)/);
    if (match) return match[1];
  }

  // Fallback: check for main or master
  for (const branch of ["main", "master"]) {
    const checkCmd = new Deno.Command("git", {
      args: ["-C", barePath, "rev-parse", `refs/heads/${branch}`],
      stdout: "piped",
      stderr: "piped",
    });
    const checkOutput = await checkCmd.output();
    if (checkOutput.success) return branch;
  }

  return "main";
}

async function getWorktrees(barePath: string, repoPath: string, defaultBranch: string): Promise<Worktree[]> {
  const cmd = new Deno.Command("git", {
    args: ["-C", barePath, "worktree", "list", "--porcelain"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();
  if (!output.success) return [];

  const stdout = new TextDecoder().decode(output.stdout);
  const worktrees: Worktree[] = [];
  const entries = stdout.split("\n\n").filter(e => e.trim());

  for (const entry of entries) {
    const lines = entry.split("\n");
    const wt: Partial<Worktree> = {
      ahead: 0,
      behind: 0,
      is_clean: true,
      is_main: false,
      // Feature 108: Enhanced status fields
      is_merged: false,
      is_stale: false,
      has_conflicts: false,
      staged_count: 0,
      modified_count: 0,
      untracked_count: 0,
      last_commit_timestamp: 0,
      last_commit_message: "",
    };

    for (const line of lines) {
      if (line.startsWith("worktree ")) {
        wt.path = line.substring("worktree ".length);
      } else if (line.startsWith("HEAD ")) {
        wt.commit = line.substring("HEAD ".length);
      } else if (line.startsWith("branch refs/heads/")) {
        wt.branch = line.substring("branch refs/heads/".length);
      } else if (line === "bare") {
        wt.path = undefined; // Skip bare repo entry
      }
    }

    // Skip bare repo itself
    if (!wt.path || wt.path.endsWith("/.bare")) continue;

    // Skip if no branch (detached HEAD)
    if (!wt.branch) wt.branch = "HEAD";

    // Check if main worktree
    if (wt.branch === defaultBranch || wt.branch === "main" || wt.branch === "master") {
      wt.is_main = true;
    }

    // Feature 108: Get detailed git status for worktree
    const statusOutput = await getWorktreeStatus(wt.path);
    if (statusOutput) {
      wt.staged_count = statusOutput.staged_count;
      wt.modified_count = statusOutput.modified_count;
      wt.untracked_count = statusOutput.untracked_count;
      wt.has_conflicts = statusOutput.has_conflicts;
      wt.is_clean = statusOutput.staged_count === 0 && statusOutput.modified_count === 0;
    }

    // Feature 108: Get last commit info
    const commitInfo = await getLastCommitInfo(wt.path);
    if (commitInfo) {
      wt.last_commit_timestamp = commitInfo.timestamp;
      wt.last_commit_message = commitInfo.message;

      // Stale detection (30+ days since last commit)
      const daysSince = (Date.now() / 1000 - commitInfo.timestamp) / 86400;
      wt.is_stale = daysSince >= 30;
    }

    // Feature 108: Merge detection
    if (wt.branch && !["main", "master", "HEAD"].includes(wt.branch)) {
      wt.is_merged = await checkBranchMerged(barePath, wt.branch, defaultBranch);
    }

    if (wt.path && wt.branch) {
      worktrees.push(wt as Worktree);
    }
  }

  return worktrees;
}

// Feature 108: Get detailed git status
async function getWorktreeStatus(wtPath: string): Promise<{
  staged_count: number;
  modified_count: number;
  untracked_count: number;
  has_conflicts: boolean;
} | null> {
  const cmd = new Deno.Command("git", {
    args: ["-C", wtPath, "status", "--porcelain=v1"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();
  if (!output.success) return null;

  const stdout = new TextDecoder().decode(output.stdout);
  let staged_count = 0;
  let modified_count = 0;
  let untracked_count = 0;
  let has_conflicts = false;

  for (const line of stdout.split("\n")) {
    if (line.length < 2) continue;
    const x = line[0];
    const y = line[1];

    // Conflict detection: UU (both modified), AA (both added), DD (both deleted)
    if (x === "U" || y === "U" || (x === "A" && y === "A") || (x === "D" && y === "D")) {
      has_conflicts = true;
    }
    if (x !== " " && x !== "?") {
      staged_count++;
    }
    if (y === "M") {
      modified_count++;
    }
    if (x === "?" && y === "?") {
      untracked_count++;
    }
  }

  return { staged_count, modified_count, untracked_count, has_conflicts };
}

// Feature 108: Get last commit info
async function getLastCommitInfo(wtPath: string): Promise<{
  timestamp: number;
  message: string;
} | null> {
  const cmd = new Deno.Command("git", {
    args: ["-C", wtPath, "log", "-1", "--format=%ct|%s"],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();
  if (!output.success) return null;

  const stdout = new TextDecoder().decode(output.stdout).trim();
  if (!stdout) return null;

  const parts = stdout.split("|");
  const timestamp = parseInt(parts[0], 10) || 0;
  const message = parts.slice(1).join("|").substring(0, 80);

  return { timestamp, message };
}

// Feature 108: Check if branch is merged into default branch
async function checkBranchMerged(barePath: string, branch: string, defaultBranch: string): Promise<boolean> {
  for (const checkBranch of [defaultBranch, "main", "master"]) {
    const cmd = new Deno.Command("git", {
      args: ["-C", barePath, "branch", "--merged", checkBranch],
      stdout: "piped",
      stderr: "piped",
    });

    const output = await cmd.output();
    if (output.success) {
      const stdout = new TextDecoder().decode(output.stdout);
      const mergedBranches = stdout.split("\n").map(b => b.trim().replace(/^\* /, ""));
      if (mergedBranches.includes(branch)) {
        return true;
      }
    }
  }
  return false;
}
