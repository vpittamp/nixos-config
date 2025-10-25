/**
 * Project configuration models
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Project definitions with directory context and optional saved layouts.
 * NO APPLICATION_TAGS - environment-based filtering replaces tag system.
 */

/**
 * Project configuration
 * Location: ~/.config/i3/projects/<project-name>.json
 */
export interface Project {
  // Identity
  name: string; // Unique project identifier (kebab-case)
  display_name: string; // Human-readable name
  directory: string; // Absolute path to project root
  icon?: string; // Optional icon identifier

  // Layout state
  saved_layout?: string; // Optional: path to layout file (relative to layouts dir)

  // Metadata
  created_at: string; // ISO 8601 timestamp
  updated_at: string; // ISO 8601 timestamp
}

/**
 * Active project state
 * Location: ~/.config/i3/active-project.json
 */
export interface ActiveProject {
  project_name: string | null; // Current project name or null if no project
  activated_at: string | null; // ISO 8601 timestamp of activation or null
}

/**
 * Project creation parameters
 */
export interface CreateProjectParams {
  name: string;
  display_name: string;
  directory: string;
  icon?: string;
}

/**
 * Project update parameters
 */
export interface UpdateProjectParams {
  display_name?: string;
  directory?: string;
  icon?: string;
  saved_layout?: string;
}

/**
 * Type guards for runtime validation
 */
export function isProject(value: unknown): value is Project {
  if (typeof value !== "object" || value === null) return false;
  const project = value as Record<string, unknown>;

  return (
    typeof project.name === "string" &&
    typeof project.display_name === "string" &&
    typeof project.directory === "string" &&
    typeof project.created_at === "string" &&
    typeof project.updated_at === "string"
  );
}

export function isActiveProject(value: unknown): value is ActiveProject {
  if (typeof value !== "object" || value === null) return false;
  const active = value as Record<string, unknown>;

  return (
    (active.project_name === null || typeof active.project_name === "string") &&
    (active.activated_at === null || typeof active.activated_at === "string")
  );
}

/**
 * Validate project name format (kebab-case, 3-64 chars)
 */
export function isValidProjectName(name: string): boolean {
  return /^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$/.test(name);
}

/**
 * Validate directory path (absolute, starts with / or ~)
 */
export function isValidDirectory(path: string): boolean {
  return path.startsWith("/") || path.startsWith("~");
}
