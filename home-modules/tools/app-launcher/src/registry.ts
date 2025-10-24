/**
 * Registry loading and validation
 *
 * Feature: 034-create-a-feature
 * Provides loading, parsing, and validation of the application registry JSON.
 */

import type {
  ApplicationRegistry,
  ApplicationRegistryEntry,
} from "./models.ts";
import { isApplicationRegistry } from "./models.ts";

/**
 * Default registry path
 */
export const DEFAULT_REGISTRY_PATH = `${Deno.env.get("HOME")}/.config/i3/application-registry.json`;

/**
 * Registry loading error
 */
export class RegistryError extends Error {
  constructor(message: string, public readonly cause?: Error) {
    super(message);
    this.name = "RegistryError";
  }
}

/**
 * Load and parse application registry from file
 *
 * @param path - Path to registry JSON file (default: ~/.config/i3/application-registry.json)
 * @returns Parsed and validated registry
 * @throws RegistryError if file not found, invalid JSON, or schema validation fails
 */
export async function loadRegistry(
  path: string = DEFAULT_REGISTRY_PATH,
): Promise<ApplicationRegistry> {
  try {
    // Read file
    const content = await Deno.readTextFile(path);

    // Parse JSON
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      throw new RegistryError(
        `Invalid JSON in registry file: ${path}`,
        err instanceof Error ? err : new Error(String(err)),
      );
    }

    // Validate structure
    if (!isApplicationRegistry(parsed)) {
      throw new RegistryError(
        `Registry file does not match expected schema: ${path}\n` +
          `Expected: { version: string, applications: [...] }`,
      );
    }

    // Validate unique names
    const names = new Set<string>();
    const duplicates: string[] = [];

    for (const app of parsed.applications) {
      if (names.has(app.name)) {
        duplicates.push(app.name);
      }
      names.add(app.name);
    }

    if (duplicates.length > 0) {
      throw new RegistryError(
        `Duplicate application names found: ${duplicates.join(", ")}`,
      );
    }

    return parsed;
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      throw new RegistryError(
        `Registry file not found: ${path}\n` +
          `Run 'sudo nixos-rebuild switch' to generate the registry.`,
      );
    }

    if (err instanceof RegistryError) {
      throw err;
    }

    throw new RegistryError(
      `Failed to load registry from ${path}`,
      err instanceof Error ? err : new Error(String(err)),
    );
  }
}

/**
 * Find application by name in registry
 *
 * @param registry - Application registry
 * @param name - Application name to find
 * @returns Application entry or null if not found
 */
export function findApplication(
  registry: ApplicationRegistry,
  name: string,
): ApplicationRegistryEntry | null {
  return registry.applications.find((app) => app.name === name) ?? null;
}

/**
 * Filter applications by scope
 *
 * @param registry - Application registry
 * @param scope - Scope to filter by ("scoped", "global", or "all")
 * @returns Filtered applications
 */
export function filterByScope(
  registry: ApplicationRegistry,
  scope: "scoped" | "global" | "all",
): ApplicationRegistryEntry[] {
  if (scope === "all") {
    return registry.applications;
  }

  return registry.applications.filter(
    (app) => (app.scope ?? "global") === scope,
  );
}

/**
 * Filter applications by workspace
 *
 * @param registry - Application registry
 * @param workspace - Workspace number (1-9)
 * @returns Applications assigned to this workspace
 */
export function filterByWorkspace(
  registry: ApplicationRegistry,
  workspace: number,
): ApplicationRegistryEntry[] {
  return registry.applications.filter(
    (app) => app.preferred_workspace === workspace,
  );
}

/**
 * Get all application names
 *
 * @param registry - Application registry
 * @returns Array of application names
 */
export function getApplicationNames(registry: ApplicationRegistry): string[] {
  return registry.applications.map((app) => app.name);
}

/**
 * Validate registry structure and business rules
 *
 * @param registry - Application registry to validate
 * @returns Validation errors (empty array if valid)
 */
export function validateRegistry(registry: ApplicationRegistry): string[] {
  const errors: string[] = [];

  // Check version format
  if (!/^\d+\.\d+\.\d+$/.test(registry.version)) {
    errors.push(
      `Invalid version format: "${registry.version}" (expected: x.y.z)`,
    );
  }

  // Check application names are kebab-case
  const namePattern = /^[a-z0-9-]+$/;
  for (const app of registry.applications) {
    if (!namePattern.test(app.name)) {
      errors.push(
        `Invalid application name: "${app.name}" (must be lowercase, numbers, and hyphens only)`,
      );
    }
  }

  // Check parameter safety (no shell metacharacters)
  const dangerousChars = /[;|&`$(){}]/;
  for (const app of registry.applications) {
    if (app.parameters && dangerousChars.test(app.parameters)) {
      errors.push(
        `Unsafe parameters for "${app.name}": contains shell metacharacters (;|&\`$(){})`,
      );
    }
  }

  // Check command safety
  for (const app of registry.applications) {
    if (dangerousChars.test(app.command)) {
      errors.push(
        `Unsafe command for "${app.name}": contains shell metacharacters`,
      );
    }
  }

  // Check workspace range
  for (const app of registry.applications) {
    if (
      app.preferred_workspace !== undefined &&
      (app.preferred_workspace < 1 || app.preferred_workspace > 9)
    ) {
      errors.push(
        `Invalid workspace for "${app.name}": ${app.preferred_workspace} (must be 1-9)`,
      );
    }
  }

  // Check scoped apps have expected_class or expected_title_contains
  for (const app of registry.applications) {
    if (
      app.scope === "scoped" &&
      !app.expected_class &&
      !app.expected_title_contains
    ) {
      errors.push(
        `Scoped application "${app.name}" should have expected_class or expected_title_contains`,
      );
    }
  }

  return errors;
}

/**
 * Registry statistics
 */
export interface RegistryStats {
  total: number;
  scoped: number;
  global: number;
  by_workspace: Record<number, number>;
}

/**
 * Calculate registry statistics
 *
 * @param registry - Application registry
 * @returns Statistics about the registry
 */
export function getRegistryStats(registry: ApplicationRegistry): RegistryStats {
  const stats: RegistryStats = {
    total: registry.applications.length,
    scoped: 0,
    global: 0,
    by_workspace: {},
  };

  for (const app of registry.applications) {
    const scope = app.scope ?? "global";
    if (scope === "scoped") {
      stats.scoped++;
    } else {
      stats.global++;
    }

    if (app.preferred_workspace) {
      stats.by_workspace[app.preferred_workspace] =
        (stats.by_workspace[app.preferred_workspace] ?? 0) + 1;
    }
  }

  return stats;
}
