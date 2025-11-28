/**
 * Discovery Models for Feature 097: Git-Centric Project and Worktree Management
 *
 * TypeScript/Zod schemas for:
 * - Git metadata extraction
 * - Repository and worktree discovery
 * - Scan configuration
 * - Discovery results
 * - Panel display models
 *
 * Per Constitution Principle XIII: Deno CLI Standards with Zod 3.22+
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

// ============================================================================
// Enums (Feature 097 - Git-centric architecture)
// ============================================================================

/**
 * Classification of project type (Feature 097).
 *
 * - repository: Primary entry point for a bare repo (ONE per bare_repo_path)
 * - worktree: Git worktree linked to a Repository Project
 * - standalone: Non-git directory OR simple repo with no worktrees
 */
export const SourceTypeSchema = z.enum(["repository", "worktree", "standalone"]);
export type SourceType = z.infer<typeof SourceTypeSchema>;

/**
 * Current availability status (Feature 097).
 *
 * - active: Directory exists and is accessible
 * - missing: Directory no longer exists or inaccessible
 * - orphaned: Worktree with no matching Repository Project
 */
export const ProjectStatusSchema = z.enum(["active", "missing", "orphaned"]);
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;

// ============================================================================
// Git Metadata
// ============================================================================

/**
 * Git-specific metadata attached to projects (Feature 097).
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

  /** Most recent file modification timestamp */
  last_modified: z.string().datetime().nullable().default(null),

  /** When metadata was last refreshed */
  last_refreshed: z.string().datetime().nullable().default(null),
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
// Feature 097: Unified Project Schema
// ============================================================================

/**
 * Remote SSH configuration for projects.
 */
export const RemoteConfigSchema = z.object({
  enabled: z.boolean().default(false),
  host: z.string().default(""),
  user: z.string().default(""),
  remote_dir: z.string().default(""),
  port: z.number().int().min(1).max(65535).default(22),
});

export type RemoteConfig = z.infer<typeof RemoteConfigSchema>;

/**
 * Unified Project model for Feature 097 git-centric architecture.
 *
 * This is the single schema for all project types: repository, worktree, standalone.
 */
export const ProjectSchema = z.object({
  /** Unique project identifier (slug) */
  name: z.string().min(1).max(64),

  /** Human-readable display name */
  display_name: z.string().min(1),

  /** Absolute path to project directory */
  directory: z.string().min(1),

  /** Emoji icon for visual identification */
  icon: z.string().default("📁"),

  /** Window hiding behavior */
  scope: z.enum(["scoped", "global"]).default("scoped"),

  /** Remote SSH configuration */
  remote: RemoteConfigSchema.nullable().default(null),

  // Feature 097: Git-centric fields
  /** Project type: repository (primary), worktree (linked), or standalone (non-git) */
  source_type: SourceTypeSchema.default("standalone"),

  /** Availability status: active, missing, or orphaned */
  status: ProjectStatusSchema.default("active"),

  /** GIT_COMMON_DIR - canonical identifier for all worktrees of a repo */
  bare_repo_path: z.string().nullable().default(null),

  /** For worktrees: name of the parent Repository Project */
  parent_project: z.string().nullable().default(null),

  /** Cached git state */
  git_metadata: GitMetadataSchema.nullable().default(null),

  /** App window classes scoped to this project */
  scoped_classes: z.array(z.string()).default([]),

  /** When project was created */
  created_at: z.string().datetime().nullable().default(null),

  /** When project was last modified */
  updated_at: z.string().datetime().nullable().default(null),
}).refine(
  (data) => {
    // Feature 097 T005 equivalent: Worktree projects must have parent_project
    if (data.source_type === "worktree" && !data.parent_project) {
      return false;
    }
    return true;
  },
  { message: "Worktree projects must have parent_project set" }
);

export type Project = z.infer<typeof ProjectSchema>;

// ============================================================================
// Feature 097: Panel Display Models
// ============================================================================

/**
 * Repository project with its child worktrees for panel display (T014 equivalent).
 */
export const RepositoryWithWorktreesSchema = z.object({
  /** The repository project (source_type=repository) */
  project: ProjectSchema,

  /** Number of child worktrees */
  worktree_count: z.number().int().nonnegative().default(0),

  /** True if any worktree has uncommitted changes */
  has_dirty: z.boolean().default(false),

  /** UI expansion state */
  is_expanded: z.boolean().default(true),

  /** Child worktree projects */
  worktrees: z.array(ProjectSchema).default([]),
});

export type RepositoryWithWorktrees = z.infer<typeof RepositoryWithWorktreesSchema>;

/**
 * Complete panel data structure (T013 equivalent).
 */
export const PanelProjectsDataSchema = z.object({
  /** Repository projects with their grouped worktrees */
  repository_projects: z.array(RepositoryWithWorktreesSchema).default([]),

  /** Standalone projects (non-git or simple repos) */
  standalone_projects: z.array(ProjectSchema).default([]),

  /** Worktrees with no matching Repository Project */
  orphaned_worktrees: z.array(ProjectSchema).default([]),

  /** Currently active project name */
  active_project: z.string().nullable().default(null),
});

export type PanelProjectsData = z.infer<typeof PanelProjectsDataSchema>;

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
