/**
 * App Registry Reader Service
 *
 * Loads and validates application registry from JSON file.
 * Provides app lookup functionality for test framework.
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";
import { expandPath } from "../helpers/path-utils.ts";
import { PWADefinition, PWADefinitionSchema } from "../models/pwa-definition.ts";

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
const DEFAULT_PWA_REGISTRY_PATH = "~/.config/i3/pwa-registry.json";

// Global cache for registry (loaded once per session)
let registryCache: Map<string, AppRegistryEntry> | null = null;
let pwaRegistryCache: Map<string, PWADefinition> | null = null;
let pwaRegistryByULID: Map<string, PWADefinition> | null = null;

// PWA Registry Schema (top-level structure)
const PWARegistrySchema = z.object({
  version: z.string(),
  pwas: z.array(PWADefinitionSchema),
});

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
  pwaRegistryCache = null;
  pwaRegistryByULID = null;
}

/**
 * Load and validate PWA registry from JSON file
 *
 * @param registryPath - Optional path to PWA registry file (default: ~/.config/i3/pwa-registry.json)
 * @returns Map of pwa_name → PWADefinition
 * @throws Error if registry file not found or invalid
 */
export async function loadPWARegistry(
  registryPath?: string
): Promise<Map<string, PWADefinition>> {
  // Return cached registry if available
  if (pwaRegistryCache !== null) {
    return pwaRegistryCache;
  }

  const path = registryPath || DEFAULT_PWA_REGISTRY_PATH;
  const expandedPath = expandPath(path);

  try {
    // Read registry file
    const content = await Deno.readTextFile(expandedPath);
    const rawData = JSON.parse(content);

    // Validate with Zod
    const validatedData = PWARegistrySchema.parse(rawData);

    // Convert PWAs array to Map (indexed by name)
    pwaRegistryCache = new Map(
      validatedData.pwas.map(pwa => [pwa.name, pwa])
    );

    // Also create ULID-indexed map for faster lookups
    pwaRegistryByULID = new Map(
      validatedData.pwas.map(pwa => [pwa.ulid, pwa])
    );

    return pwaRegistryCache;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(
        `PWA registry not found at: ${expandedPath}\n` +
        `Expected location: ~/.config/i3/pwa-registry.json`
      );
    }

    if (error instanceof z.ZodError) {
      throw new Error(
        `Invalid PWA registry format:\n` +
        error.errors.map(e => `  - ${e.path.join(".")}: ${e.message}`).join("\n")
      );
    }

    throw new Error(`Failed to load PWA registry: ${error.message}`);
  }
}

/**
 * Lookup a single PWA entry from registry by name
 *
 * @param pwaName - PWA name to lookup (e.g., "youtube", "claude")
 * @returns PWADefinition for the PWA
 * @throws PWANotFoundError if PWA doesn't exist in registry
 */
export async function lookupPWA(pwaName: string): Promise<PWADefinition> {
  const registry = await loadPWARegistry();

  const pwa = registry.get(pwaName);

  if (!pwa) {
    const availablePWAs = Array.from(registry.keys()).sort();
    throw new PWANotFoundError(
      pwaName,
      DEFAULT_PWA_REGISTRY_PATH,
      availablePWAs
    );
  }

  return pwa;
}

/**
 * Lookup a single PWA entry from registry by ULID
 *
 * @param ulid - PWA ULID identifier (26-char base32)
 * @returns PWADefinition for the PWA
 * @throws PWANotFoundError if PWA doesn't exist in registry
 */
export async function lookupPWAByULID(ulid: string): Promise<PWADefinition> {
  // Validate ULID format
  if (!isValidULID(ulid)) {
    throw new Error(
      `Invalid ULID format: ${ulid}\n` +
      `ULID must be 26 characters using base32 alphabet (0-9, A-Z excluding I, L, O, U)`
    );
  }

  // Ensure registry is loaded
  await loadPWARegistry();

  if (!pwaRegistryByULID) {
    throw new Error("PWA registry not loaded");
  }

  const pwa = pwaRegistryByULID.get(ulid);

  if (!pwa) {
    const availableULIDs = Array.from(pwaRegistryByULID.keys()).sort();
    throw new Error(
      `PWA with ULID "${ulid}" not found in registry\n` +
      `Available ULIDs: ${availableULIDs.join(", ")}`
    );
  }

  return pwa;
}

/**
 * Validate ULID format
 *
 * @param ulid - String to validate
 * @returns true if valid ULID format
 */
export function isValidULID(ulid: string): boolean {
  return /^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/.test(ulid);
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

/**
 * Error thrown when PWA not found in registry
 */
export class PWANotFoundError extends Error {
  constructor(
    public pwaName: string,
    public registryPath: string,
    public availablePWAs: string[]
  ) {
    super(
      `PWA "${pwaName}" not found in registry at ${registryPath}\n` +
      `Available PWAs: ${availablePWAs.join(", ")}`
    );
    this.name = "PWANotFoundError";
  }
}
