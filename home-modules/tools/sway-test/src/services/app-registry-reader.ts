/**
 * App Registry Reader Service
 *
 * Loads and validates application registry from JSON file.
 * Provides app lookup functionality for test framework.
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";
import { expandPath } from "../helpers/path-utils.ts";

// PWA Entry Schema
const PWAEntrySchema = z.object({
  id: z.string().min(1),
  expected_class: z.string().min(1),
});

// App Registry Entry Schema
export const AppRegistryEntrySchema = z.object({
  name: z.string().min(1).regex(/^[a-z0-9-]+$/),
  command: z.string().min(1),
  preferred_workspace: z.number().int().min(1).max(70).optional(),
  scope: z.enum(["global", "scoped"]),
  expected_class: z.string().min(1).optional(),
  display_name: z.string().optional(),
  description: z.string().optional(),
  icon: z.string().optional(),
  nix_package: z.string().optional(),
  multi_instance: z.boolean().optional(),
  fallback_behavior: z.string().optional(),
  parameters: z.array(z.string()).optional(),
  terminal: z.boolean().optional(),
  pwas: z.array(PWAEntrySchema).optional(),
});

export type AppRegistryEntry = z.infer<typeof AppRegistryEntrySchema>;
export type PWAEntry = z.infer<typeof PWAEntrySchema>;

// App Registry Schema (top-level structure)
const AppRegistrySchema = z.object({
  version: z.string(),
  applications: z.array(AppRegistryEntrySchema),
});

// Default registry path
const DEFAULT_REGISTRY_PATH = "~/.config/i3/application-registry.json";

// Global cache for registry (loaded once per session)
let registryCache: Map<string, AppRegistryEntry> | null = null;

/**
 * Load and validate application registry from JSON file
 *
 * @param registryPath - Optional path to registry file (default: ~/.config/i3/application-registry.json)
 * @returns Map of app_name → AppRegistryEntry
 * @throws Error if registry file not found or invalid
 */
export async function loadAppRegistry(
  registryPath?: string
): Promise<Map<string, AppRegistryEntry>> {
  // Return cached registry if available
  if (registryCache !== null) {
    return registryCache;
  }

  const path = registryPath || DEFAULT_REGISTRY_PATH;
  const expandedPath = expandPath(path);

  try {
    // Read registry file
    const content = await Deno.readTextFile(expandedPath);
    const rawData = JSON.parse(content);

    // Validate with Zod
    const validatedData = AppRegistrySchema.parse(rawData);

    // Convert applications array to Map (indexed by name)
    registryCache = new Map(
      validatedData.applications.map(app => [app.name, app])
    );

    return registryCache;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(
        `Application registry not found at: ${expandedPath}\n` +
        `Expected location: ~/.config/i3/application-registry.json`
      );
    }

    if (error instanceof z.ZodError) {
      throw new Error(
        `Invalid application registry format:\n` +
        error.errors.map(e => `  - ${e.path.join(".")}: ${e.message}`).join("\n")
      );
    }

    throw new Error(`Failed to load application registry: ${error.message}`);
  }
}

/**
 * Lookup a single app entry from registry by name
 *
 * @param appName - App name to lookup (e.g., "firefox", "vscode")
 * @returns AppRegistryEntry for the app
 * @throws AppNotFoundError if app doesn't exist in registry
 */
export async function lookupApp(appName: string): Promise<AppRegistryEntry> {
  const registry = await loadAppRegistry();

  const app = registry.get(appName);

  if (!app) {
    const availableApps = Array.from(registry.keys()).sort();
    throw new AppNotFoundError(
      appName,
      DEFAULT_REGISTRY_PATH,
      availableApps
    );
  }

  return app;
}

/**
 * Clear registry cache (useful for testing)
 */
export function clearRegistryCache(): void {
  registryCache = null;
}

/**
 * Error thrown when app not found in registry
 */
export class AppNotFoundError extends Error {
  constructor(
    public appName: string,
    public registryPath: string,
    public availableApps: string[]
  ) {
    super(
      `App "${appName}" not found in registry at ${registryPath}\n` +
      `Available apps: ${availableApps.join(", ")}`
    );
    this.name = "AppNotFoundError";
  }
}
