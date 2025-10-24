/**
 * TypeScript type definitions for the unified application launcher system.
 *
 * Feature: 034-create-a-feature
 * Corresponds to: /etc/nixos/specs/034-create-a-feature/contracts/registry-schema.json
 */

/**
 * Application scope determines visibility across projects
 */
export type ApplicationScope = "scoped" | "global";

/**
 * Fallback behavior when project context is unavailable
 */
export type FallbackBehavior = "skip" | "use_home" | "error";

/**
 * Application registry entry - declarative application definition
 */
export interface ApplicationRegistryEntry {
  /** Unique identifier (kebab-case) */
  name: string;

  /** Human-readable name for launcher display */
  display_name: string;

  /** Base executable command (no arguments) */
  command: string;

  /** Command-line arguments with optional variable templates */
  parameters?: string;

  /** Application scope relative to projects */
  scope?: ApplicationScope;

  /** WM_CLASS pattern for window matching (regex) */
  expected_class?: string;

  /** Window title substring for matching (alternative to expected_class) */
  expected_title_contains?: string;

  /** Target workspace number (1-9) */
  preferred_workspace?: number;

  /** Icon name (from theme) or absolute path */
  icon?: string;

  /** NixOS package reference for documentation */
  nix_package?: string;

  /** Allow multiple windows */
  multi_instance?: boolean;

  /** Behavior when no project context available */
  fallback_behavior?: FallbackBehavior;

  /** Additional XDG desktop entry categories */
  categories?: string[];

  /** Application description for tooltips */
  description?: string;
}

/**
 * Application registry - top-level structure
 */
export interface ApplicationRegistry {
  /** Schema version for compatibility */
  version: string;

  /** List of registered applications */
  applications: ApplicationRegistryEntry[];
}

/**
 * Variable context - runtime environment for variable substitution
 */
export interface VariableContext {
  /** Active project name (from daemon) */
  project_name: string | null;

  /** Active project directory path (from project config) */
  project_dir: string | null;

  /** Session identifier (same as project name) */
  session_name: string | null;

  /** Target workspace number (from registry) */
  workspace: number | null;

  /** User home directory */
  user_home: string;

  /** Project display name (from project config) */
  display_name: string | null;

  /** Project icon (from project config) */
  icon: string | null;
}

/**
 * Launch command - fully resolved command ready for execution
 */
export interface LaunchCommand {
  /** Launch timestamp (ISO 8601) */
  timestamp: string;

  /** Application identifier */
  app_name: string;

  /** Original command template */
  template: string;

  /** After variable substitution */
  resolved_command: string;

  /** Project context snapshot at launch time */
  context_snapshot: VariableContext;

  /** Process exit code (if available) */
  exit_code: number | null;
}

/**
 * Desktop file representation (generated artifact)
 */
export interface DesktopFile {
  /** File path on filesystem */
  file_path: string;

  /** Display name (Name field) */
  name: string;

  /** Exec command including wrapper */
  exec_command: string;

  /** Icon name or path */
  icon: string | null;

  /** XDG categories */
  categories: string[];

  /** StartupWMClass for window matching */
  startup_wm_class: string | null;
}

/**
 * Window rule (generated from registry)
 */
export interface WindowRule {
  /** Pattern matching configuration */
  pattern_rule: {
    /** Regex pattern for window matching */
    pattern: string;

    /** Window scope */
    scope: ApplicationScope;

    /** Rule priority (higher wins) */
    priority: number;

    /** Human-readable description */
    description: string;
  };

  /** Target workspace number */
  workspace: number | null;
}

/**
 * Daemon project response
 */
export interface DaemonProjectResponse {
  /** Project name */
  name: string;

  /** Project directory */
  directory: string;

  /** Project display name */
  display_name: string;

  /** Project icon */
  icon: string;
}

/**
 * CLI command options
 */
export interface GlobalOptions {
  /** Output format */
  format?: "table" | "json";

  /** Enable verbose logging */
  verbose?: boolean;

  /** Help flag */
  help?: boolean;
}

/**
 * List command options
 */
export interface ListOptions extends GlobalOptions {
  /** Filter by scope */
  scope?: ApplicationScope | "all";

  /** Filter by workspace */
  workspace?: number;
}

/**
 * Launch command options
 */
export interface LaunchOptions extends GlobalOptions {
  /** Dry-run mode (show command without executing) */
  "dry-run"?: boolean;

  /** Override active project */
  project?: string;
}

/**
 * Info command options
 */
export interface InfoOptions extends GlobalOptions {
  /** Show resolved variables */
  resolve?: boolean;
}

/**
 * Validate command options
 */
export interface ValidateOptions extends GlobalOptions {
  /** Auto-fix common issues */
  fix?: boolean;

  /** Check commands exist in PATH */
  "check-paths"?: boolean;

  /** Check icons exist */
  "check-icons"?: boolean;
}

/**
 * Add command options
 */
export interface AddOptions extends GlobalOptions {
  /** Non-interactive mode */
  "non-interactive"?: boolean;

  /** Application name */
  name?: string;

  /** Display name */
  "display-name"?: string;

  /** Command */
  command?: string;

  /** Scope */
  scope?: ApplicationScope;

  /** Workspace */
  workspace?: number;

  /** Parameters */
  parameters?: string;

  /** Expected class */
  "expected-class"?: string;

  /** Icon */
  icon?: string;

  /** NixOS package */
  "nix-package"?: string;

  /** Multi-instance */
  "multi-instance"?: boolean;

  /** Fallback behavior */
  fallback?: FallbackBehavior;
}

/**
 * Remove command options
 */
export interface RemoveOptions extends GlobalOptions {
  /** Skip confirmation */
  force?: boolean;
}

/**
 * Validation result
 */
export interface ValidationResult {
  /** Overall validity */
  valid: boolean;

  /** Individual check results */
  checks: {
    json_syntax?: { passed: boolean; error?: string };
    schema_compliance?: { passed: boolean; errors?: string[] };
    unique_names?: { passed: boolean; duplicates?: string[] };
    command_paths?: { passed: boolean; missing?: string[] };
    icon_resolution?: { passed: boolean; missing?: string[] };
    parameter_safety?: { passed: boolean; violations?: string[] };
  };

  /** Summary statistics */
  summary: {
    passed: number;
    warnings: number;
    errors: number;
  };
}

/**
 * Type guard for ApplicationRegistry
 */
export function isApplicationRegistry(obj: unknown): obj is ApplicationRegistry {
  if (typeof obj !== "object" || obj === null) return false;

  const reg = obj as ApplicationRegistry;
  return (
    typeof reg.version === "string" &&
    Array.isArray(reg.applications) &&
    reg.applications.every(isApplicationRegistryEntry)
  );
}

/**
 * Type guard for ApplicationRegistryEntry
 */
export function isApplicationRegistryEntry(obj: unknown): obj is ApplicationRegistryEntry {
  if (typeof obj !== "object" || obj === null) return false;

  const app = obj as ApplicationRegistryEntry;
  return (
    typeof app.name === "string" &&
    typeof app.display_name === "string" &&
    typeof app.command === "string" &&
    // Optional fields
    (app.parameters === undefined || typeof app.parameters === "string") &&
    (app.scope === undefined || ["scoped", "global"].includes(app.scope)) &&
    (app.expected_class === undefined || typeof app.expected_class === "string") &&
    (app.preferred_workspace === undefined ||
      (typeof app.preferred_workspace === "number" &&
        app.preferred_workspace >= 1 &&
        app.preferred_workspace <= 9)) &&
    (app.icon === undefined || typeof app.icon === "string") &&
    (app.nix_package === undefined || typeof app.nix_package === "string") &&
    (app.multi_instance === undefined || typeof app.multi_instance === "boolean") &&
    (app.fallback_behavior === undefined ||
      ["skip", "use_home", "error"].includes(app.fallback_behavior))
  );
}

/**
 * Default values for optional fields
 */
export const DEFAULT_APP_ENTRY: Partial<ApplicationRegistryEntry> = {
  scope: "global",
  multi_instance: true,
  fallback_behavior: "skip",
};
