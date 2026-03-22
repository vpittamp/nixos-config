/**
 * Registry data models
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Type-safe interfaces for the application registry schema.
 * NO TAGS - environment-based filtering replaces tag system.
 */

export type ApplicationScope = "scoped" | "global";
export type FallbackBehavior = "skip" | "use_home" | "error";
export type ScopedTerminalMode = "managed_project_terminal" | "dedicated_scoped_window";
export type PreferredMonitorRole = "primary" | "secondary" | "tertiary";
export type FloatingSize = "scratchpad" | "small" | "medium" | "large";

/**
 * Application registry entry
 * Source: app-registry.nix compiled to ~/.config/i3/application-registry.json
 */
export interface RegistryApplication {
  // Identity
  name: string; // Unique identifier, kebab-case
  display_name: string; // Human-readable name
  icon: string; // Icon identifier

  // Launch configuration
  command: string; // Absolute path to executable
  parameters: string[]; // Command-line arguments with variable substitution
  terminal: boolean; // Launch in terminal emulator
  scoped_terminal_mode?: ScopedTerminalMode; // Special handling for scoped terminal apps

  // Window management
  expected_class: string; // WM_CLASS for window matching
  expected_title_contains?: string; // Optional title-based fallback matching
  preferred_workspace?: number; // Target workspace (1-9) or null for dynamic
  preferred_monitor_role?: PreferredMonitorRole;
  floating?: boolean;
  floating_size?: FloatingSize;
  scratchpad?: boolean;

  // Scope and behavior
  scope: ApplicationScope; // "scoped" or "global"
  fallback_behavior: FallbackBehavior; // Behavior when no project active
  multi_instance: boolean; // Allow multiple windows per project
  aliases?: string[];

  // Metadata
  nix_package?: string; // Nix package reference for debugging
  description?: string; // Help text
  pwa_domain?: string;
  pwa_match_domains?: string[];
}

/**
 * Complete application registry
 */
export interface ApplicationRegistry {
  version: string; // Semantic version (e.g., "1.0.0")
  applications: RegistryApplication[];
}

/**
 * Type guards for runtime validation
 */
export function isApplicationScope(value: unknown): value is ApplicationScope {
  return value === "scoped" || value === "global";
}

export function isFallbackBehavior(value: unknown): value is FallbackBehavior {
  return value === "skip" || value === "use_home" || value === "error";
}

export function isScopedTerminalMode(value: unknown): value is ScopedTerminalMode {
  return value === "managed_project_terminal" || value === "dedicated_scoped_window";
}

export function isPreferredMonitorRole(value: unknown): value is PreferredMonitorRole {
  return value === "primary" || value === "secondary" || value === "tertiary";
}

export function isFloatingSize(value: unknown): value is FloatingSize {
  return value === "scratchpad" || value === "small" || value === "medium" || value === "large";
}

export function isRegistryApplication(value: unknown): value is RegistryApplication {
  if (typeof value !== "object" || value === null) return false;
  const app = value as Record<string, unknown>;

  return (
    typeof app.name === "string" &&
    typeof app.display_name === "string" &&
    typeof app.icon === "string" &&
    typeof app.command === "string" &&
    Array.isArray(app.parameters) &&
    app.parameters.every((p) => typeof p === "string") &&
    typeof app.terminal === "boolean" &&
    (app.scoped_terminal_mode === undefined || isScopedTerminalMode(app.scoped_terminal_mode)) &&
    typeof app.expected_class === "string" &&
    (app.preferred_monitor_role === undefined ||
      app.preferred_monitor_role === null ||
      isPreferredMonitorRole(app.preferred_monitor_role)) &&
    (app.floating === undefined || typeof app.floating === "boolean") &&
    (app.floating_size === undefined ||
      app.floating_size === null ||
      isFloatingSize(app.floating_size)) &&
    (app.scratchpad === undefined || typeof app.scratchpad === "boolean") &&
    isApplicationScope(app.scope) &&
    isFallbackBehavior(app.fallback_behavior) &&
    typeof app.multi_instance === "boolean" &&
    (app.aliases === undefined || (Array.isArray(app.aliases) && app.aliases.every((alias) => typeof alias === "string"))) &&
    (app.pwa_match_domains === undefined ||
      (Array.isArray(app.pwa_match_domains) && app.pwa_match_domains.every((domain) => typeof domain === "string")))
  );
}

export function isApplicationRegistry(value: unknown): value is ApplicationRegistry {
  if (typeof value !== "object" || value === null) return false;
  const registry = value as Record<string, unknown>;

  return (
    typeof registry.version === "string" &&
    Array.isArray(registry.applications) &&
    registry.applications.every(isRegistryApplication)
  );
}
