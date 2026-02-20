/**
 * Feature 100: Repository and Worktree Zod Schemas
 *
 * TypeScript schemas for bare repositories and worktrees.
 */

import { z } from "npm:zod@3.22.0";

/**
 * Git worktree linked to a bare repository.
 */
export const WorktreeSchema = z.object({
  branch: z.string().min(1),
  path: z.string().min(1),
  commit: z.string().nullable().default(null),
  is_clean: z.boolean().nullable().default(null),
  ahead: z.number().default(0),
  behind: z.number().default(0),
  is_main: z.boolean().default(false),
  // Feature 108: Enhanced status fields
  is_merged: z.boolean().default(false),
  is_stale: z.boolean().default(false),
  has_conflicts: z.boolean().default(false),
  staged_count: z.number().default(0),
  modified_count: z.number().default(0),
  untracked_count: z.number().default(0),
  last_commit_timestamp: z.number().default(0),
  last_commit_message: z.string().default(""),
});

export type Worktree = z.infer<typeof WorktreeSchema>;

/**
 * Repository stored as bare clone with .bare/ structure.
 */
export const BareRepositorySchema = z.object({
  account: z.string().min(1),
  name: z.string().min(1),
  path: z.string().min(1),
  remote_url: z.string().min(1),
  default_branch: z.string().default("main"),
  worktrees: z.array(WorktreeSchema).default([]),
  discovered_at: z.string().datetime().optional(),
  last_scanned: z.string().datetime().nullable().optional(),
});

export type BareRepository = z.infer<typeof BareRepositorySchema>;

/**
 * Storage schema for repos.json
 */
export const RepositoriesStorageSchema = z.object({
  version: z.number().default(1),
  last_discovery: z.string().datetime().nullable().optional(),
  repositories: z.array(BareRepositorySchema).default([]),
});

export type RepositoriesStorage = z.infer<typeof RepositoriesStorageSchema>;

/**
 * Project type enum
 */
export const ProjectTypeSchema = z.enum(["repository", "worktree"]);

export type ProjectType = z.infer<typeof ProjectTypeSchema>;

/**
 * Git status for display
 */
export const GitStatusSchema = z.object({
  commit: z.string().nullable().default(null),
  is_clean: z.boolean().default(true),
  ahead: z.number().default(0),
  behind: z.number().default(0),
});

export type GitStatus = z.infer<typeof GitStatusSchema>;

/**
 * Unified view for UI display
 */
export const DiscoveredProjectSchema = z.object({
  id: z.string().min(1),
  account: z.string().min(1),
  repo_name: z.string().min(1),
  branch: z.string().nullable().default(null),
  type: ProjectTypeSchema,
  path: z.string().min(1),
  display_name: z.string().min(1),
  icon: z.string().default("📦"),
  is_active: z.boolean().default(false),
  git_status: GitStatusSchema.nullable().default(null),
  parent_id: z.string().nullable().default(null),
});

export type DiscoveredProject = z.infer<typeof DiscoveredProjectSchema>;

/**
 * Clone request
 */
export const CloneRequestSchema = z.object({
  url: z.string().min(1),
  account: z.string().optional(),
});

export type CloneRequest = z.infer<typeof CloneRequestSchema>;

/**
 * Clone response
 */
export const CloneResponseSchema = z.object({
  success: z.boolean(),
  repository: BareRepositorySchema.optional(),
  path: z.string().optional(),
  main_worktree: z.string().optional(),
});

export type CloneResponse = z.infer<typeof CloneResponseSchema>;

/**
 * Worktree create request
 */
export const WorktreeCreateRequestSchema = z.object({
  branch: z.string().min(1),
  from: z.string().default("main"),
  repo: z.string().optional(),
});

export type WorktreeCreateRequest = z.infer<typeof WorktreeCreateRequestSchema>;

/**
 * Worktree create response
 */
export const WorktreeCreateResponseSchema = z.object({
  success: z.boolean(),
  worktree: WorktreeSchema.optional(),
  path: z.string().optional(),
});

export type WorktreeCreateResponse = z.infer<typeof WorktreeCreateResponseSchema>;

/**
 * Worktree remove request
 */
export const WorktreeRemoveRequestSchema = z.object({
  branch: z.string().min(1),
  repo: z.string().optional(),
  force: z.boolean().default(false),
});

export type WorktreeRemoveRequest = z.infer<typeof WorktreeRemoveRequestSchema>;

/**
 * Discovery response
 */
export const DiscoverResponseSchema = z.object({
  success: z.boolean(),
  discovered: z.number(),
  repos: z.number(),
  worktrees: z.number(),
  duration_ms: z.number(),
});

export type DiscoverResponse = z.infer<typeof DiscoverResponseSchema>;

/**
 * Error codes from contracts
 */
export const ErrorCodeSchema = z.enum([
  "INVALID_URL",
  "REPO_EXISTS",
  "REPO_NOT_FOUND",
  "WORKTREE_EXISTS",
  "WORKTREE_DIRTY",
  "CANNOT_REMOVE_MAIN",
  "ACCOUNT_NOT_FOUND",
]);

export type ErrorCode = z.infer<typeof ErrorCodeSchema>;

/**
 * Error response
 */
export const ErrorResponseSchema = z.object({
  error: z.string(),
  code: ErrorCodeSchema.optional(),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;
