/**
 * Git Worktree Service
 * Feature 077: Git Worktree Project Management
 *
 * This service provides high-level operations for managing git worktrees,
 * including creation, deletion, listing, and validation.
 */

import {
  branchExists,
  execGit,
  getRepositoryRoot,
  isGitRepository,
  parseWorktreeList,
  type GitWorktreeEntry,
} from "../utils/git.ts";
import { dirname, join } from "@std/path";

// ============================================================================
// GitWorktreeService Class
// ============================================================================

/**
 * Service for managing git worktrees
 *
 * Provides methods for:
 * - Repository validation
 * - Branch existence checking
 * - Worktree path resolution
 * - Worktree creation and deletion
 * - Worktree listing
 */
export class GitWorktreeService {
  /**
   * Validate that a directory is a git repository
   *
   * @param path - Directory path to validate
   * @returns True if valid git repository
   * @throws Error if not a git repository
   */
  async validateRepository(path: string): Promise<boolean> {
    const isRepo = await isGitRepository(path);
    if (!isRepo) {
      throw new Error(`Not a git repository: ${path}`);
    }
    return true;
  }

  /**
   * Check if a branch exists (local or remote)
   *
   * @param branchName - Branch name to check
   * @param repoPath - Repository path
   * @returns True if branch exists
   */
  async checkBranchExists(branchName: string, repoPath: string): Promise<boolean> {
    return await branchExists(branchName, repoPath);
  }

  /**
   * Resolve the base path for worktrees
   *
   * By default, creates worktrees as siblings to the main repository.
   * For example, if main repo is at `/home/user/nixos`, worktrees will be
   * created at `/home/user/nixos-feature1`, `/home/user/nixos-feature2`, etc.
   *
   * @param repoPath - Main repository path
   * @param customBasePath - Optional custom base path
   * @returns Resolved base path for worktrees
   */
  async resolveWorktreeBasePath(
    repoPath: string,
    customBasePath?: string,
  ): Promise<string> {
    if (customBasePath) {
      return customBasePath;
    }

    // Default: use parent directory of main repository
    return dirname(repoPath);
  }

  /**
   * Create a new git worktree
   *
   * Executes: git worktree add <path> <branch>
   *
   * @param branchName - Branch to checkout/create
   * @param worktreePath - Absolute path for the worktree
   * @param repoPath - Main repository path
   * @param createBranch - Whether to create a new branch (vs checkout existing)
   * @returns Path to created worktree
   * @throws Error if worktree creation fails
   */
  async createWorktree(
    branchName: string,
    worktreePath: string,
    repoPath: string,
    createBranch = false,
  ): Promise<string> {
    const args = ["worktree", "add"];

    if (createBranch) {
      // Create new branch from current HEAD
      args.push("-b", branchName, worktreePath);
    } else {
      // Checkout existing branch
      args.push(worktreePath, branchName);
    }

    await execGit(args, repoPath);
    return worktreePath;
  }

  /**
   * Delete a git worktree
   *
   * Executes: git worktree remove <path>
   *
   * @param worktreePath - Path to worktree to remove
   * @param force - Force removal even with uncommitted changes
   * @returns True if deletion successful
   * @throws Error if deletion fails
   */
  async deleteWorktree(worktreePath: string, force = false): Promise<boolean> {
    // Implementation will be added in User Story 4 (Phase 7)
    throw new Error("Not yet implemented");
  }

  /**
   * List all worktrees for a repository
   *
   * @param repoPath - Repository path
   * @returns Array of worktree entries
   */
  async listWorktrees(repoPath: string): Promise<GitWorktreeEntry[]> {
    // Implementation will be added in User Story 2 (Phase 5)
    throw new Error("Not yet implemented");
  }

  /**
   * Check the status of a worktree (clean/dirty, uncommitted changes)
   *
   * @param worktreePath - Path to worktree
   * @returns Status information
   */
  async checkWorktreeStatus(worktreePath: string): Promise<{
    isClean: boolean;
    hasUntracked: boolean;
  }> {
    // Implementation will be added in User Story 4 (Phase 7)
    throw new Error("Not yet implemented");
  }
}
