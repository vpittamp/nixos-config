/**
 * Registry data models
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Type-safe interfaces for the application registry schema.
 * NO TAGS - environment-based filtering replaces tag system.
 */

export type ApplicationScope = "scoped" | "global";
export type FallbackBehavior = "skip" | "use_home" | "error";

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

  // Window management
  expected_class: string; // WM_CLASS for window matching
  expected_title_contains?: string; // Optional title-based fallback matching
  preferred_workspace?: number; // Target workspace (1-9) or null for dynamic

  // Scope and behavior
  scope: ApplicationScope; // "scoped" or "global"
  fallback_behavior: FallbackBehavior; // Behavior when no project active
  multi_instance: boolean; // Allow multiple windows per project

  // Metadata
  nix_package?: string; // Nix package reference for debugging
  description?: string; // Help text
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
    typeof app.expected_class === "string" &&
    isApplicationScope(app.scope) &&
    isFallbackBehavior(app.fallback_behavior) &&
    typeof app.multi_instance === "boolean"
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
