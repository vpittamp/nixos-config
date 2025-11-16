/**
 * Worktree Metadata Service
 * Feature 077: Git Worktree Project Management
 *
 * This service extracts and manages git metadata for worktrees,
 * including branch info, commit hashes, git status, and tracking information.
 */

import {
  execGit,
  getCurrentBranch,
  getCurrentCommitHash,
  getLastModifiedTime,
  parseBranchTracking,
  parseGitStatus,
} from "../utils/git.ts";
import type { WorktreeMetadata } from "../models/worktree.ts";

// ============================================================================
// WorktreeMetadataService Class
// ============================================================================

/**
 * Service for extracting and managing worktree metadata
 *
 * Provides methods for:
 * - Extracting complete metadata from a worktree
 * - Enriching worktree lists with git status information
 * - Updating metadata for existing projects
 */
export class WorktreeMetadataService {
  /**
   * Extract complete metadata from a worktree directory
   *
   * Gathers information including:
   * - Current branch name
   * - Commit hash
   * - Git status (clean/dirty, untracked files)
   * - Branch tracking (ahead/behind counts)
   * - Last modification time
   *
   * @param worktreePath - Absolute path to worktree
   * @param repositoryPath - Absolute path to main repository
   * @returns Complete worktree metadata
   * @throws Error if metadata extraction fails
   */
  async extractMetadata(
    worktreePath: string,
    repositoryPath: string,
  ): Promise<WorktreeMetadata> {
    // Get branch name
    const branch = await getCurrentBranch(worktreePath);

    // Get commit hash
    const commit_hash = await getCurrentCommitHash(worktreePath, true);

    // Get git status
    const statusResult = await execGit(["status", "--porcelain"], worktreePath);
    const status = parseGitStatus(statusResult.stdout);

    // Get branch tracking info
    const trackingResult = await execGit(
      ["status", "--porcelain=v2", "--branch"],
      worktreePath,
    );
    const tracking = parseBranchTracking(trackingResult.stdout);

    // Get last modification time
    const last_modified = await getLastModifiedTime(worktreePath);

    return {
      branch,
      commit_hash,
      is_clean: status.isClean,
      has_untracked: status.hasUntracked,
      ahead_count: tracking.aheadCount,
      behind_count: tracking.behindCount,
      worktree_path: worktreePath,
      repository_path: repositoryPath,
      last_modified,
    };
  }

  /**
   * Enrich a list of worktrees with git status metadata
   *
   * Takes basic worktree information and adds detailed git status
   * for each worktree (used by list command and Eww widget)
   *
   * @param worktrees - Array of basic worktree info
   * @param repositoryPath - Main repository path
   * @returns Worktrees enriched with metadata
   */
  async enrichWithMetadata(
    worktrees: Array<{ path: string; branch?: string }>,
    repositoryPath: string,
  ): Promise<WorktreeMetadata[]> {
    // Implementation will be added in User Story 2 (Phase 5)
    throw new Error("Not yet implemented");
  }

  /**
   * Sync/update metadata for an existing worktree project
   *
   * Called when switching to a project or on periodic refresh
   *
   * @param projectName - i3pm project name
   * @returns Updated metadata
   */
  async syncMetadata(projectName: string): Promise<WorktreeMetadata> {
    // Implementation will be added in User Story 5 (Phase 6)
    throw new Error("Not yet implemented");
  }
}
