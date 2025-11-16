/**
 * Worktree Models and Types
 * Feature 077: Git Worktree Project Management
 *
 * This module defines the data models for git worktree integration with i3pm.
 */

import { z } from "zod";
import type { Project } from "../models.ts";

// ============================================================================
// Worktree Metadata
// ============================================================================

/**
 * Git status and metadata for a worktree
 */
export interface WorktreeMetadata {
  /** Git branch name (e.g., "feature-auth-refactor") */
  branch: string;

  /** Current HEAD commit hash (short or full) */
  commit_hash: string;

  /** Whether working tree has no uncommitted changes */
  is_clean: boolean;

  /** Whether there are untracked files present */
  has_untracked: boolean;

  /** Number of commits ahead of tracking branch */
  ahead_count: number;

  /** Number of commits behind tracking branch */
  behind_count: number;

  /** Absolute path to worktree directory */
  worktree_path: string;

  /** Absolute path to main repository */
  repository_path: string;

  /** ISO 8601 timestamp of most recent git activity */
  last_modified: string;
}

/**
 * Zod schema for WorktreeMetadata validation
 */
export const WorktreeMetadataSchema = z.object({
  branch: z.string().min(1),
  commit_hash: z.string().min(7),
  is_clean: z.boolean(),
  has_untracked: z.boolean(),
  ahead_count: z.number().int().nonnegative(),
  behind_count: z.number().int().nonnegative(),
  worktree_path: z.string().min(1),
  repository_path: z.string().min(1),
  last_modified: z.string().datetime(),
});

// ============================================================================
// Worktree Project
// ============================================================================

/**
 * Project that corresponds to a git worktree
 *
 * Extends the base Project interface with worktree-specific metadata.
 * The presence of the `worktree` field acts as a discriminator to identify
 * worktree-managed projects vs regular directory-based projects.
 */
export interface WorktreeProject extends Project {
  /** Worktree metadata (discriminator - presence indicates worktree project) */
  worktree: WorktreeMetadata;
}

/**
 * Zod schema for WorktreeProject validation
 *
 * NOTE: We don't import ProjectSchema from validation.ts to avoid circular deps.
 * Instead, we define the worktree-specific fields and validate the full object
 * at the usage site.
 */
export const WorktreeProjectFieldsSchema = z.object({
  worktree: WorktreeMetadataSchema,
});

// ============================================================================
// Worktree Discovery
// ============================================================================

/**
 * Entry representing a discovered worktree (from git worktree list)
 *
 * Used during auto-discovery to identify worktrees that may not yet be
 * registered as i3pm projects.
 */
export interface WorktreeDiscoveryEntry {
  /** Absolute path to worktree directory */
  worktree_path: string;

  /** Git branch name associated with worktree */
  branch_name: string;

  /** Whether this worktree is already registered as an i3pm project */
  is_registered: boolean;

  /** ISO 8601 timestamp when worktree was discovered */
  discovered_at: string;
}

/**
 * Zod schema for WorktreeDiscoveryEntry validation
 */
export const WorktreeDiscoveryEntrySchema = z.object({
  worktree_path: z.string().min(1),
  branch_name: z.string().min(1),
  is_registered: z.boolean(),
  discovered_at: z.string().datetime(),
});

// ============================================================================
// Type Guards
// ============================================================================

/**
 * Type guard to check if a project is a worktree project
 *
 * @param project - Project to check
 * @returns True if project has worktree metadata
 *
 * @example
 * ```ts
 * if (isWorktreeProject(project)) {
 *   console.log(`Branch: ${project.worktree.branch}`);
 * }
 * ```
 */
export function isWorktreeProject(project: Project): project is WorktreeProject {
  return "worktree" in project && project.worktree !== undefined;
}

// ============================================================================
// Helper Types
// ============================================================================

/**
 * Options for creating a new worktree project
 */
export interface CreateWorktreeOptions {
  /** Branch name to checkout/create */
  branchName: string;

  /** Optional custom worktree directory name (default: branch name) */
  worktreeName?: string;

  /** Optional base directory for worktrees (default: sibling to main repo) */
  basePath?: string;

  /** Whether to checkout existing branch vs create new (default: auto-detect) */
  checkout?: boolean;

  /** Optional project customization */
  projectOptions?: {
    displayName?: string;
    icon?: string;
    scopedClasses?: string[];
  };
}

/**
 * Result of worktree creation operation
 */
export interface CreateWorktreeResult {
  /** Created worktree project */
  project: WorktreeProject;

  /** Absolute path to created worktree */
  worktree_path: string;

  /** Whether a new branch was created (vs checking out existing) */
  created_branch: boolean;
}

/**
 * Options for deleting a worktree project
 */
export interface DeleteWorktreeOptions {
  /** i3pm project name */
  projectName: string;

  /** Force deletion even with uncommitted changes */
  force?: boolean;

  /** Remove worktree but keep i3pm project registration */
  keepProject?: boolean;
}

/**
 * Options for listing worktrees
 */
export interface ListWorktreesOptions {
  /** Output format */
  format?: "table" | "json" | "names";

  /** Include git status metadata */
  showMetadata?: boolean;

  /** Filter to only dirty worktrees */
  filterDirty?: boolean;
}

/**
 * Options for worktree discovery
 */
export interface DiscoverWorktreesOptions {
  /** Automatically register discovered worktrees (vs prompting) */
  autoRegister?: boolean;

  /** Specific repository path to scan (default: current repo) */
  repositoryPath?: string;
}
