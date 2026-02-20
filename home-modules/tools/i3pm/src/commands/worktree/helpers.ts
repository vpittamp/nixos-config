/**
 * Shared helpers for i3pm worktree commands.
 */

const HOME = Deno.env.get("HOME") || "";
const REPOS_FILE = `${HOME}/.config/i3/repos.json`;

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
export async function refreshDiscovery(): Promise<void> {
  const discoverCmd = new Deno.Command("i3pm", {
    args: ["discover"],
    stdout: "piped",
    stderr: "piped",
  });
  await discoverCmd.output();
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
    const content = await Deno.readTextFile(REPOS_FILE);
    const repos = JSON.parse(content);
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
    const content = await Deno.readTextFile(REPOS_FILE);
    const repos = JSON.parse(content);
    const [account, repoName] = repoQualified.split("/");
    for (const repo of repos.repositories || []) {
      if (repo.account !== account || repo.name !== repoName) continue;
      for (const wt of repo.worktrees || []) {
        if (wt.branch === branch && wt.path) return wt.path;
      }
      break;
    }
  } catch {
    // ignore lookup failures
  }
  return null;
}
