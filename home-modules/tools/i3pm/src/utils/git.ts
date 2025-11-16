/**
 * Git CLI Utilities
 * Feature 077: Git Worktree Project Management
 *
 * This module provides utilities for interacting with git CLI commands,
 * specifically for worktree management operations.
 */

import { join } from "@std/path";

// ============================================================================
// Git Command Execution
// ============================================================================

/**
 * Error thrown when a git command fails
 */
export class GitError extends Error {
  constructor(
    message: string,
    public readonly command: string,
    public readonly exitCode: number,
    public readonly stderr: string,
  ) {
    super(message);
    this.name = "GitError";
  }
}

/**
 * Result of a git command execution
 */
export interface GitCommandResult {
  /** Standard output from the command */
  stdout: string;

  /** Standard error from the command */
  stderr: string;

  /** Exit code (0 = success) */
  exitCode: number;

  /** Whether the command succeeded (exitCode === 0) */
  success: boolean;
}

/**
 * Execute a git command and return the result
 *
 * @param args - Git command arguments (e.g., ["worktree", "list", "--porcelain"])
 * @param cwd - Working directory for git command (default: current directory)
 * @returns Command result with stdout, stderr, exitCode
 * @throws GitError if command fails and throwOnError is true
 *
 * @example
 * ```ts
 * const result = await execGit(["worktree", "list", "--porcelain"]);
 * if (result.success) {
 *   console.log(result.stdout);
 * }
 * ```
 */
export async function execGit(
  args: string[],
  cwd?: string,
  throwOnError = true,
): Promise<GitCommandResult> {
  const command = new Deno.Command("git", {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  });

  const { code, stdout, stderr } = await command.output();
  const stdoutText = new TextDecoder().decode(stdout).trim();
  const stderrText = new TextDecoder().decode(stderr).trim();

  const result: GitCommandResult = {
    stdout: stdoutText,
    stderr: stderrText,
    exitCode: code,
    success: code === 0,
  };

  if (throwOnError && !result.success) {
    throw new GitError(
      `Git command failed: ${args.join(" ")}\n${stderrText}`,
      args.join(" "),
      code,
      stderrText,
    );
  }

  return result;
}

// ============================================================================
// Worktree Listing and Parsing
// ============================================================================

/**
 * Parsed worktree entry from git worktree list
 */
export interface GitWorktreeEntry {
  /** Absolute path to worktree directory */
  path: string;

  /** Commit hash (HEAD) of the worktree */
  commit: string;

  /** Branch name (if checked out to a branch) */
  branch?: string;

  /** Whether this is the main repository worktree */
  isMain: boolean;
}

/**
 * Parse git worktree list --porcelain output
 *
 * The porcelain format is structured as:
 * ```
 * worktree /path/to/worktree
 * HEAD <commit-hash>
 * branch refs/heads/<branch-name>
 *
 * worktree /path/to/another
 * ...
 * ```
 *
 * @param porcelainOutput - Output from git worktree list --porcelain
 * @returns Array of parsed worktree entries
 *
 * @example
 * ```ts
 * const result = await execGit(["worktree", "list", "--porcelain"]);
 * const worktrees = parseWorktreeList(result.stdout);
 * console.log(worktrees); // [{ path: "/etc/nixos", commit: "abc123", branch: "main", isMain: true }, ...]
 * ```
 */
export function parseWorktreeList(porcelainOutput: string): GitWorktreeEntry[] {
  if (!porcelainOutput.trim()) {
    return [];
  }

  const worktrees: GitWorktreeEntry[] = [];
  const lines = porcelainOutput.split("\n");

  let current: Partial<GitWorktreeEntry> = {};

  for (const line of lines) {
    if (line.startsWith("worktree ")) {
      // Start of new entry
      if (current.path) {
        // Save previous entry
        worktrees.push({
          path: current.path,
          commit: current.commit || "",
          branch: current.branch,
          isMain: current.isMain || false,
        });
      }
      current = {
        path: line.substring("worktree ".length),
        isMain: false,
      };
    } else if (line.startsWith("HEAD ")) {
      current.commit = line.substring("HEAD ".length);
    } else if (line.startsWith("branch ")) {
      // Format: "branch refs/heads/feature-name"
      const ref = line.substring("branch ".length);
      if (ref.startsWith("refs/heads/")) {
        current.branch = ref.substring("refs/heads/".length);
      }
    } else if (line === "bare") {
      current.isMain = true;
    } else if (line.trim() === "") {
      // Empty line indicates end of entry
      if (current.path) {
        worktrees.push({
          path: current.path,
          commit: current.commit || "",
          branch: current.branch,
          isMain: current.isMain || false,
        });
        current = {};
      }
    }
  }

  // Don't forget the last entry if no trailing newline
  if (current.path) {
    worktrees.push({
      path: current.path,
      commit: current.commit || "",
      branch: current.branch,
      isMain: current.isMain || false,
    });
  }

  return worktrees;
}

// ============================================================================
// Git Status Parsing
// ============================================================================

/**
 * Parsed git status information
 */
export interface GitStatus {
  /** Whether working tree is clean (no changes) */
  isClean: boolean;

  /** Whether there are untracked files */
  hasUntracked: boolean;

  /** Number of staged changes */
  stagedCount: number;

  /** Number of unstaged changes */
  unstagedCount: number;
}

/**
 * Parse git status --porcelain output to determine if worktree is clean
 *
 * Porcelain format: Each line is XY followed by filename
 * - X = index status, Y = worktree status
 * - '?' = untracked file
 * - ' ' = no change
 * - 'M' = modified
 * - 'A' = added
 * - 'D' = deleted
 * - etc.
 *
 * @param porcelainOutput - Output from git status --porcelain
 * @returns Parsed status information
 *
 * @example
 * ```ts
 * const result = await execGit(["status", "--porcelain"], "/path/to/worktree");
 * const status = parseGitStatus(result.stdout);
 * console.log(status.isClean); // false if there are changes
 * ```
 */
export function parseGitStatus(porcelainOutput: string): GitStatus {
  const lines = porcelainOutput.split("\n").filter((l) => l.trim());

  let stagedCount = 0;
  let unstagedCount = 0;
  let hasUntracked = false;

  for (const line of lines) {
    if (line.length < 2) continue;

    const indexStatus = line[0];
    const worktreeStatus = line[1];

    if (indexStatus === "?" && worktreeStatus === "?") {
      hasUntracked = true;
      continue;
    }

    if (indexStatus !== " " && indexStatus !== "?") {
      stagedCount++;
    }

    if (worktreeStatus !== " " && worktreeStatus !== "?") {
      unstagedCount++;
    }
  }

  return {
    isClean: lines.length === 0,
    hasUntracked,
    stagedCount,
    unstagedCount,
  };
}

// ============================================================================
// Branch Tracking Information
// ============================================================================

/**
 * Parsed branch tracking information
 */
export interface BranchTracking {
  /** Local branch name */
  localBranch: string;

  /** Remote tracking branch (e.g., "origin/main") */
  remoteBranch?: string;

  /** Number of commits ahead of remote */
  aheadCount: number;

  /** Number of commits behind remote */
  behindCount: number;
}

/**
 * Parse git status --porcelain=v2 --branch output for tracking info
 *
 * The v2 porcelain format includes branch tracking headers:
 * ```
 * # branch.oid <commit>
 * # branch.head <branch-name>
 * # branch.upstream <remote>/<branch>
 * # branch.ab +<ahead> -<behind>
 * ```
 *
 * @param porcelainV2Output - Output from git status --porcelain=v2 --branch
 * @returns Branch tracking information
 *
 * @example
 * ```ts
 * const result = await execGit(["status", "--porcelain=v2", "--branch"], "/path/to/worktree");
 * const tracking = parseBranchTracking(result.stdout);
 * console.log(tracking.aheadCount); // 3 (commits ahead)
 * ```
 */
export function parseBranchTracking(porcelainV2Output: string): BranchTracking {
  const lines = porcelainV2Output.split("\n");

  let localBranch = "";
  let remoteBranch: string | undefined;
  let aheadCount = 0;
  let behindCount = 0;

  for (const line of lines) {
    if (line.startsWith("# branch.head ")) {
      localBranch = line.substring("# branch.head ".length);
    } else if (line.startsWith("# branch.upstream ")) {
      remoteBranch = line.substring("# branch.upstream ".length);
    } else if (line.startsWith("# branch.ab ")) {
      // Format: "# branch.ab +<ahead> -<behind>"
      const abPart = line.substring("# branch.ab ".length);
      const match = abPart.match(/\+(\d+)\s+-(\d+)/);
      if (match) {
        aheadCount = parseInt(match[1], 10);
        behindCount = parseInt(match[2], 10);
      }
    }
  }

  return {
    localBranch,
    remoteBranch,
    aheadCount,
    behindCount,
  };
}

// ============================================================================
// Repository Validation
// ============================================================================

/**
 * Check if a directory is a git repository
 *
 * @param path - Directory path to check
 * @returns True if directory is a git repository
 *
 * @example
 * ```ts
 * if (await isGitRepository("/etc/nixos")) {
 *   console.log("Valid git repository");
 * }
 * ```
 */
export async function isGitRepository(path: string): Promise<boolean> {
  try {
    const result = await execGit(["rev-parse", "--git-dir"], path, false);
    return result.success;
  } catch {
    return false;
  }
}

/**
 * Get the absolute path to the repository root
 *
 * @param path - Directory path (can be anywhere in the repository)
 * @returns Absolute path to repository root
 * @throws GitError if not in a git repository
 *
 * @example
 * ```ts
 * const root = await getRepositoryRoot("/etc/nixos/home-modules");
 * console.log(root); // "/etc/nixos"
 * ```
 */
export async function getRepositoryRoot(path: string): Promise<string> {
  const result = await execGit(["rev-parse", "--show-toplevel"], path);
  return result.stdout;
}

/**
 * Check if a branch exists (local or remote)
 *
 * @param branchName - Branch name to check (e.g., "feature-name" or "origin/feature-name")
 * @param cwd - Working directory for git command
 * @returns True if branch exists
 *
 * @example
 * ```ts
 * if (await branchExists("feature-auth", "/etc/nixos")) {
 *   console.log("Branch already exists");
 * }
 * ```
 */
export async function branchExists(branchName: string, cwd: string): Promise<boolean> {
  try {
    const result = await execGit(["rev-parse", "--verify", `refs/heads/${branchName}`], cwd, false);
    if (result.success) return true;

    // Try remote branches
    const remoteResult = await execGit(
      ["rev-parse", "--verify", `refs/remotes/${branchName}`],
      cwd,
      false,
    );
    return remoteResult.success;
  } catch {
    return false;
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get the current commit hash
 *
 * @param cwd - Working directory for git command
 * @param short - Whether to return short hash (7 chars) vs full hash
 * @returns Commit hash
 *
 * @example
 * ```ts
 * const hash = await getCurrentCommitHash("/etc/nixos", true);
 * console.log(hash); // "abc1234"
 * ```
 */
export async function getCurrentCommitHash(cwd: string, short = true): Promise<string> {
  const args = short ? ["rev-parse", "--short", "HEAD"] : ["rev-parse", "HEAD"];
  const result = await execGit(args, cwd);
  return result.stdout;
}

/**
 * Get the current branch name
 *
 * @param cwd - Working directory for git command
 * @returns Branch name, or "HEAD" if detached
 *
 * @example
 * ```ts
 * const branch = await getCurrentBranch("/etc/nixos");
 * console.log(branch); // "main"
 * ```
 */
export async function getCurrentBranch(cwd: string): Promise<string> {
  const result = await execGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd);
  return result.stdout;
}

/**
 * Get the last modification time of the git repository (most recent commit)
 *
 * @param cwd - Working directory for git command
 * @returns ISO 8601 timestamp of last commit
 *
 * @example
 * ```ts
 * const lastMod = await getLastModifiedTime("/etc/nixos");
 * console.log(lastMod); // "2025-11-15T10:30:00Z"
 * ```
 */
export async function getLastModifiedTime(cwd: string): Promise<string> {
  const result = await execGit(["log", "-1", "--format=%cI"], cwd);
  return result.stdout;
}
