/**
 * Discovery Models for Feature 097: Git-Based Project Discovery and Management
 *
 * TypeScript/Zod schemas for:
 * - Git metadata extraction
 * - Repository and worktree discovery
 * - Scan configuration
 * - Discovery results
 *
 * Per Constitution Principle XIII: Deno CLI Standards with Zod 3.22+
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

// ============================================================================
// Enums
// ============================================================================

/**
 * Classification of how a project was created/discovered.
 */
export const SourceTypeSchema = z.enum(["local", "worktree", "remote", "manual"]);
export type SourceType = z.infer<typeof SourceTypeSchema>;

/**
 * Current availability status of a project.
 */
export const ProjectStatusSchema = z.enum(["active", "missing"]);
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;

// ============================================================================
// Git Metadata
// ============================================================================

/**
 * Git-specific metadata attached to discovered projects.
 */
export const GitMetadataSchema = z.object({
  /** Branch name or "HEAD" if detached */
  current_branch: z.string(),

  /** Short SHA (7 characters) */
  commit_hash: z.string().length(7),

  /** No uncommitted changes */
  is_clean: z.boolean(),

  /** Untracked files present */
  has_untracked: z.boolean(),

  /** Commits ahead of upstream */
  ahead_count: z.number().int().nonnegative().default(0),

  /** Commits behind upstream */
  behind_count: z.number().int().nonnegative().default(0),

  /** Origin remote URL */
  remote_url: z.string().nullable().default(null),

  /** Dominant programming language */
  primary_language: z.string().nullable().default(null),

  /** Most recent commit timestamp */
  last_commit_date: z.string().datetime().nullable().default(null),
});

export type GitMetadata = z.infer<typeof GitMetadataSchema>;

// ============================================================================
// Scan Configuration
// ============================================================================

/**
 * User-defined settings for repository discovery.
 */
export const ScanConfigurationSchema = z.object({
  /** Directories to scan for repositories */
  scan_paths: z.array(z.string()).min(1),

  /** Directory names to skip */
  exclude_patterns: z
    .array(z.string())
    .default(["node_modules", "vendor", ".cache"]),

  /** Run discovery when daemon starts */
  auto_discover_on_startup: z.boolean().default(false),

  /** Maximum recursion depth for scanning (1-10) */
  max_depth: z.number().int().min(1).max(10).default(3),
});

export type ScanConfiguration = z.infer<typeof ScanConfigurationSchema>;

// ============================================================================
// Discovery Results
// ============================================================================

/**
 * Intermediate representation of a found repository before project creation.
 */
export const DiscoveredRepositorySchema = z.object({
  /** Absolute path to repository */
  path: z.string(),

  /** Derived from directory name */
  name: z.string(),

  /** True if .git is a file */
  is_worktree: z.boolean(),

  /** Extracted git data */
  git_metadata: GitMetadataSchema,

  /** For worktrees, path to main repo */
  parent_repo_path: z.string().nullable().default(null),

  /** Emoji based on language */
  inferred_icon: z.string().default("📁"),
});

export type DiscoveredRepository = z.infer<typeof DiscoveredRepositorySchema>;

/**
 * Worktree-specific discovery result with guaranteed parent reference.
 */
export const DiscoveredWorktreeSchema = DiscoveredRepositorySchema.extend({
  /** Always True for worktrees */
  is_worktree: z.literal(true),

  /** Path to main repository (required for worktrees) */
  parent_repo_path: z.string(),

  /** Worktree icon */
  inferred_icon: z.string().default("🌿"),
});

export type DiscoveredWorktree = z.infer<typeof DiscoveredWorktreeSchema>;

/**
 * Path that was skipped during discovery with reason.
 */
export const SkippedPathSchema = z.object({
  /** Absolute path that was skipped */
  path: z.string(),

  /** Reason for skipping */
  reason: z.string(),
});

export type SkippedPath = z.infer<typeof SkippedPathSchema>;

/**
 * Non-fatal error encountered during discovery.
 */
export const DiscoveryErrorSchema = z.object({
  /** Path where error occurred (if applicable) */
  path: z.string().optional(),

  /** Error source (e.g., "github", "filesystem") */
  source: z.string().optional(),

  /** Error code */
  error: z.string(),

  /** Human-readable error message */
  message: z.string(),
});

export type DiscoveryError = z.infer<typeof DiscoveryErrorSchema>;

/**
 * Ephemeral result returned from a discovery operation.
 */
export const DiscoveryResultSchema = z.object({
  /** Overall success status */
  success: z.boolean().default(true),

  /** Repositories found */
  discovered_repos: z.array(DiscoveredRepositorySchema).default([]),

  /** Worktrees found */
  discovered_worktrees: z.array(DiscoveredWorktreeSchema).default([]),

  /** Paths skipped (not git repos) */
  skipped_paths: z.array(SkippedPathSchema).default([]),

  /** Count of new projects */
  projects_created: z.number().int().default(0),

  /** Count of updated projects */
  projects_updated: z.number().int().default(0),

  /** Count of newly missing projects */
  projects_marked_missing: z.number().int().default(0),

  /** Time taken in milliseconds */
  duration_ms: z.number().int().default(0),

  /** Non-fatal errors encountered */
  errors: z.array(DiscoveryErrorSchema).default([]),
});

export type DiscoveryResult = z.infer<typeof DiscoveryResultSchema>;

// ============================================================================
// GitHub Integration
// ============================================================================

/**
 * GitHub repository information from gh CLI.
 */
export const GitHubRepoSchema = z.object({
  /** Repository name */
  name: z.string(),

  /** Full name (owner/repo) */
  full_name: z.string(),

  /** Repository description */
  description: z.string().nullable().default(null),

  /** Primary programming language */
  primary_language: z.string().nullable().default(null),

  /** Last push timestamp */
  pushed_at: z.string().datetime().nullable().default(null),

  /** Repository visibility */
  visibility: z.enum(["public", "private"]).default("public"),

  /** Whether repository is a fork */
  is_fork: z.boolean().default(false),

  /** Whether repository is archived */
  is_archived: z.boolean().default(false),

  /** HTTPS clone URL */
  clone_url: z.string(),

  /** Whether repository exists locally */
  has_local_clone: z.boolean().default(false),

  /** Name of local project if cloned */
  local_project_name: z.string().nullable().default(null),
});

export type GitHubRepo = z.infer<typeof GitHubRepoSchema>;

/**
 * Result of listing GitHub repositories.
 */
export const GitHubListResultSchema = z.object({
  /** Whether the listing succeeded */
  success: z.boolean().default(true),

  /** GitHub repositories */
  repos: z.array(GitHubRepoSchema).default([]),

  /** Total number of repositories */
  total_count: z.number().int().default(0),

  /** Errors encountered */
  errors: z.array(DiscoveryErrorSchema).default([]),
});

export type GitHubListResult = z.infer<typeof GitHubListResultSchema>;

// ============================================================================
// Extended Project Model Fields
// ============================================================================

/**
 * Extended fields for Project model to support discovery.
 * These fields are added to the existing Project interface.
 */
export const ProjectDiscoveryFieldsSchema = z.object({
  /** How project was created */
  source_type: SourceTypeSchema.default("manual"),

  /** Project availability */
  status: ProjectStatusSchema.default("active"),

  /** Git-specific data (null for non-git projects) */
  git_metadata: GitMetadataSchema.nullable().default(null),

  /** When first discovered */
  discovered_at: z.string().datetime().nullable().default(null),
});

export type ProjectDiscoveryFields = z.infer<typeof ProjectDiscoveryFieldsSchema>;

// ============================================================================
// RPC Request/Response Types
// ============================================================================

/**
 * Parameters for discover_projects RPC method.
 */
export const DiscoverProjectsParamsSchema = z.object({
  /** Override scan paths from config */
  paths: z.array(z.string()).optional(),

  /** Also query GitHub repos */
  include_github: z.boolean().default(false),

  /** Report without creating projects */
  dry_run: z.boolean().default(false),
});

export type DiscoverProjectsParams = z.infer<typeof DiscoverProjectsParamsSchema>;

/**
 * Parameters for get_discovery_config RPC method.
 */
export const GetDiscoveryConfigParamsSchema = z.object({}).optional();

export type GetDiscoveryConfigParams = z.infer<typeof GetDiscoveryConfigParamsSchema>;

/**
 * Parameters for update_discovery_config RPC method.
 */
export const UpdateDiscoveryConfigParamsSchema = z.object({
  /** Directories to scan */
  scan_paths: z.array(z.string()).optional(),

  /** Directory names to skip */
  exclude_patterns: z.array(z.string()).optional(),

  /** Enable startup discovery */
  auto_discover_on_startup: z.boolean().optional(),

  /** Max recursion depth (1-10) */
  max_depth: z.number().int().min(1).max(10).optional(),
});

export type UpdateDiscoveryConfigParams = z.infer<typeof UpdateDiscoveryConfigParamsSchema>;

/**
 * Parameters for refresh_git_metadata RPC method.
 */
export const RefreshGitMetadataParamsSchema = z.object({
  /** Specific project to refresh (all if omitted) */
  project_name: z.string().optional(),
});

export type RefreshGitMetadataParams = z.infer<typeof RefreshGitMetadataParamsSchema>;

/**
 * Parameters for list_github_repos RPC method.
 */
export const ListGitHubReposParamsSchema = z.object({
  /** Maximum repos to return */
  limit: z.number().int().default(100),

  /** Include archived repos */
  include_archived: z.boolean().default(false),

  /** Include forked repos */
  include_forks: z.boolean().default(false),
});

export type ListGitHubReposParams = z.infer<typeof ListGitHubReposParamsSchema>;
