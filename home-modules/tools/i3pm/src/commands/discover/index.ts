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

    if (wt.path && wt.branch) {
      worktrees.push(wt as Worktree);
    }
  }

  return worktrees;
}
