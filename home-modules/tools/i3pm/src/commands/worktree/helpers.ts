/**
 * Shared helpers for i3pm worktree commands.
 */

import { DaemonClient } from "../../services/daemon-client.ts";

const HOME = Deno.env.get("HOME") || "";
const REPOS_FILE = `${HOME}/.config/i3/repos.json`;

type ReposWorktreeEntry = {
  branch?: string;
  path?: string;
};

type ReposRepositoryEntry = {
  account?: string;
  name?: string;
  default_branch?: string;
  worktrees?: ReposWorktreeEntry[];
};

type ReposStorage = {
  repositories?: ReposRepositoryEntry[];
};

export type DiscoveryRefreshResult = {
  success: boolean;
  discovered: number;
  repos: number;
  worktrees: number;
  duration_ms: number;
};

/**
 * Detect repository path from current directory or --repo flag.
 */
export async function detectRepoPath(repo?: string): Promise<string | null> {
  if (repo) {
    if (repo.includes("/")) {
      const [account, repoName] = repo.split("/");
      const path = `${HOME}/repos/${account}/${repoName}`;
      try {
        await Deno.stat(`${path}/.bare`);
        return path;
      } catch {
        return null;
      }
    }

    const reposBase = `${HOME}/repos`;
    try {
      for await (const entry of Deno.readDir(reposBase)) {
        if (!entry.isDirectory) continue;
        const path = `${reposBase}/${entry.name}/${repo}`;
        try {
          await Deno.stat(`${path}/.bare`);
          return path;
        } catch {
          // continue scanning accounts
        }
      }
    } catch {
      // repos directory missing
    }

    return null;
  }

  const cwd = Deno.cwd();
  let dir = cwd;
  while (dir !== "/") {
    try {
      const bareStat = await Deno.stat(`${dir}/.bare`);
      if (bareStat.isDirectory) return dir;
    } catch {
      // continue walking up
    }

    const parent = dir.substring(0, dir.lastIndexOf("/"));
    if (parent === dir || parent === "") break;
    dir = parent;
  }

  return null;
}

/**
 * Extract account/repo from repository path.
 */
export function repoQualifiedFromPath(repoPath: string): string {
  const match = repoPath.match(/\/repos\/([^/]+)\/([^/]+)$/);
  if (match) return `${match[1]}/${match[2]}`;

  const parts = repoPath.split("/").filter(Boolean);
  if (parts.length >= 2) {
    return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
  }

  return repoPath;
}

/**
 * Parse worktree input that may be either branch or account/repo:branch.
 */
export async function resolveWorktreeTarget(
  target: string,
  repoArg?: string,
): Promise<
  { repoPath: string; repoQualified: string; branch: string; qualifiedName: string } | null
> {
  let resolvedRepoArg = repoArg;
  let branch = target;

  if (target.includes(":")) {
    const idx = target.indexOf(":");
    const repoPart = target.slice(0, idx);
    const branchPart = target.slice(idx + 1);
    if (!repoPart || !branchPart) return null;
    resolvedRepoArg = repoPart;
    branch = branchPart;
  }

  const repoPath = await detectRepoPath(resolvedRepoArg);
  if (!repoPath) return null;

  const repoQualified = resolvedRepoArg && resolvedRepoArg.includes("/")
    ? resolvedRepoArg
    : repoQualifiedFromPath(repoPath);

  return {
    repoPath,
    repoQualified,
    branch,
    qualifiedName: `${repoQualified}:${branch}`,
  };
}

/**
 * Execute `git gtr ...` against a repo path.
 */
export async function runGitGtr(
  repoPath: string,
  gtrArgs: string[],
): Promise<Deno.CommandOutput> {
  const cmd = new Deno.Command("git", {
    args: ["-C", repoPath, "gtr", ...gtrArgs],
    stdout: "piped",
    stderr: "piped",
  });
  return await cmd.output();
}

/**
 * Execute `git ...` against the bare repository directory.
 */
export async function runGitBare(
  repoPath: string,
  gitArgs: string[],
): Promise<Deno.CommandOutput> {
  const cmd = new Deno.Command("git", {
    args: ["-C", `${repoPath}/.bare`, ...gitArgs],
    stdout: "piped",
    stderr: "piped",
  });
  return await cmd.output();
}

/**
 * Whether repo path is a real git worktree root (gtr-compatible mode).
 */
export async function hasGitWorktreeRoot(repoPath: string): Promise<boolean> {
  try {
    const gitEntry = await Deno.stat(`${repoPath}/.git`);
    return gitEntry.isDirectory;
  } catch {
    return false;
  }
}

/**
 * Keep repos.json fresh after worktree mutations.
 */
export async function refreshDiscovery(): Promise<DiscoveryRefreshResult> {
  const discoverCmd = new Deno.Command("i3pm", {
    args: ["discover", "--json"],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await discoverCmd.output();
  const stdout = new TextDecoder().decode(output.stdout).trim();
  const stderr = new TextDecoder().decode(output.stderr).trim();

  let parsed: DiscoveryRefreshResult | null = null;
  if (stdout) {
    try {
      parsed = JSON.parse(stdout) as DiscoveryRefreshResult;
    } catch {
      parsed = null;
    }
  }

  if (!output.success) {
    throw new Error(stderr || stdout || "Discovery refresh failed.");
  }

  if (!parsed || !parsed.success) {
    throw new Error(stderr || stdout || "Discovery refresh returned an invalid response.");
  }

  return parsed;
}

export async function notifyWorktreeRefresh(): Promise<void> {
  const client = new DaemonClient();
  try {
    await client.request("worktree.refresh", {});
  } catch {
    // best-effort daemon invalidation for dashboard consumers
  } finally {
    client.disconnect();
  }
}

export type NativeWorktreeEntry = {
  path: string;
  branch: string | null;
  isBare: boolean;
};

/**
 * Read worktree entries using `git worktree list --porcelain` from .bare.
 */
export async function listNativeWorktrees(repoPath: string): Promise<NativeWorktreeEntry[]> {
  const output = await runGitBare(repoPath, ["worktree", "list", "--porcelain"]);
  if (!output.success) return [];

  const stdout = new TextDecoder().decode(output.stdout);
  const entries = stdout.split("\n\n").filter((entry) => entry.trim().length > 0);
  const parsed: NativeWorktreeEntry[] = [];

  for (const entry of entries) {
    const lines = entry.split("\n");
    let path = "";
    let branch: string | null = null;
    let isBare = false;

    for (const line of lines) {
      if (line.startsWith("worktree ")) {
        path = line.slice("worktree ".length);
      } else if (line.startsWith("branch refs/heads/")) {
        branch = line.slice("branch refs/heads/".length);
      } else if (line === "bare") {
        isBare = true;
      }
    }

    if (!path) continue;
    parsed.push({ path, branch, isBare });
  }

  return parsed;
}

/**
 * Read default branch for a repository from repos.json.
 */
export async function getDefaultBranch(repoPath: string): Promise<string | null> {
  try {
    const repos = await readReposStorage();
    const qualified = repoQualifiedFromPath(repoPath);
    const [account, repoName] = qualified.split("/");
    for (const repo of repos.repositories || []) {
      if (repo.account === account && repo.name === repoName) {
        return repo.default_branch || null;
      }
    }
  } catch {
    // fall back
  }
  return null;
}

/**
 * Find worktree path in repos.json after discovery.
 */
export async function findWorktreePath(
  repoQualified: string,
  branch: string,
): Promise<string | null> {
  try {
    const worktree = await findDiscoveredWorktree(repoQualified, branch);
    if (worktree?.path) return worktree.path;
  } catch {
    // ignore lookup failures
  }
  return null;
}

async function readReposStorage(): Promise<ReposStorage> {
  const content = await Deno.readTextFile(REPOS_FILE);
  return JSON.parse(content) as ReposStorage;
}

function splitRepoQualified(repoQualified: string): { account: string; repoName: string } {
  const [account, repoName] = repoQualified.split("/", 2);
  return {
    account: account || "",
    repoName: repoName || "",
  };
}

export async function findDiscoveredWorktree(
  repoQualified: string,
  branch: string,
): Promise<ReposWorktreeEntry | null> {
  const repos = await readReposStorage();
  const { account, repoName } = splitRepoQualified(repoQualified);

  for (const repo of repos.repositories || []) {
    if (repo.account !== account || repo.name !== repoName) continue;
    for (const wt of repo.worktrees || []) {
      if (wt.branch === branch) return wt;
    }
    break;
  }

  return null;
}

export async function ensureWorktreePresent(
  repoQualified: string,
  branch: string,
): Promise<string> {
  const worktree = await findDiscoveredWorktree(repoQualified, branch);
  if (!worktree?.path) {
    throw new Error(`Discovery did not register ${repoQualified}:${branch}.`);
  }
  return worktree.path;
}

export async function ensureWorktreeAbsent(
  repoQualified: string,
  branch: string,
): Promise<void> {
  const worktree = await findDiscoveredWorktree(repoQualified, branch);
  if (worktree) {
    throw new Error(`Discovery still lists ${repoQualified}:${branch}.`);
  }
}
