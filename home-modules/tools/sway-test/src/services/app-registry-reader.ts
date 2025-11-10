/**
 * App Registry Reader Service
 *
 * Loads and validates application registry from JSON file.
 * Provides app lookup functionality for test framework.
 *
 * Feature 070 - User Story 1: Clear Error Diagnostics
 * Tasks: T011, T012
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";
import { expandPath } from "../utils/path-utils.ts";
import { PWADefinition, PWADefinitionSchema } from "../models/pwa-definition.ts";
import { StructuredError, ErrorType } from "../models/structured-error.ts";

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
      throw new StructuredError(
        ErrorType.REGISTRY_ERROR,
        "Registry Loader",
        `Application registry file not found at: ${expandedPath}`,
        [
          `Ensure the registry file exists at ~/.config/i3/application-registry.json`,
          `Run: mkdir -p ~/.config/i3 && touch ~/.config/i3/application-registry.json`,
          `Verify Nix configuration generates the registry file correctly`
        ],
        {
          registry_path: expandedPath,
          expected_location: DEFAULT_REGISTRY_PATH
        }
      );
    }

    if (error instanceof z.ZodError) {
      const validationErrors = error.errors.map(e =>
        `${e.path.join(".")}: ${e.message}`
      );

      throw new StructuredError(
        ErrorType.REGISTRY_ERROR,
        "Registry Loader",
        `Invalid application registry format - schema validation failed`,
        [
          `Fix the following validation errors in ${expandedPath}:`,
          ...validationErrors.map(err => `  - ${err}`),
          `Verify registry file matches expected JSON schema`,
          `Check for missing required fields or incorrect data types`
        ],
        {
          registry_path: expandedPath,
          validation_errors: validationErrors
        }
      );
    }

    throw new StructuredError(
      ErrorType.REGISTRY_ERROR,
      "Registry Loader",
      `Failed to load application registry: ${error instanceof Error ? error.message : String(error)}`,
      [
        `Check file permissions for ${expandedPath}`,
        `Verify JSON syntax is valid`,
        `Ensure file is readable by current user`
      ],
      {
        registry_path: expandedPath,
        error_type: error instanceof Error ? error.name : typeof error
      }
    );
  }
}

/**
 * Calculate Levenshtein distance between two strings
 * Used for fuzzy matching suggestions (T043)
 *
 * @param a - First string
 * @param b - Second string
 * @returns Edit distance between strings
 */
function levenshteinDistance(a: string, b: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1, // substitution
          matrix[i][j - 1] + 1,     // insertion
          matrix[i - 1][j] + 1      // deletion
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Find similar app names using fuzzy matching (T043)
 *
 * @param query - User's input app name
 * @param availableApps - List of available app names
 * @param maxDistance - Maximum edit distance to consider (default: 3)
 * @param maxSuggestions - Maximum number of suggestions to return (default: 5)
 * @returns Array of similar app names, sorted by distance
 */
function findSimilarApps(
  query: string,
  availableApps: string[],
  maxDistance: number = 3,
  maxSuggestions: number = 5
): string[] {
  const suggestions: Array<{ app: string; distance: number }> = [];

  for (const app of availableApps) {
    const distance = levenshteinDistance(query.toLowerCase(), app.toLowerCase());

    // Also check if query is a substring of the app name
    const isSubstring = app.toLowerCase().includes(query.toLowerCase());

    if (distance <= maxDistance || isSubstring) {
      suggestions.push({ app, distance: isSubstring ? distance - 1 : distance });
    }
  }

  // Sort by distance (closest first)
  suggestions.sort((a, b) => a.distance - b.distance);

  // Return top suggestions
  return suggestions.slice(0, maxSuggestions).map(s => s.app);
}

/**
 * Lookup a single app entry from registry by name
 * Feature 070: User Story 4 - App Registry Integration (T043)
 *
 * @param appName - App name to lookup (e.g., "firefox", "vscode")
 * @returns AppRegistryEntry for the app
 * @throws AppNotFoundError with fuzzy matching suggestions if app doesn't exist
 */
export async function lookupApp(appName: string): Promise<AppRegistryEntry> {
  const registry = await loadAppRegistry();

  const app = registry.get(appName);

  if (!app) {
    const availableApps = Array.from(registry.keys()).sort();

    // T043: Find similar apps using fuzzy matching
    const similarApps = findSimilarApps(appName, availableApps);

    const remediation: string[] = [];

    if (similarApps.length > 0) {
      remediation.push(`Did you mean one of these? ${similarApps.join(", ")}`);
      remediation.push(`Run: sway-test list-apps --filter ${appName}`);
    } else {
      remediation.push(`Check the app name spelling (available: ${availableApps.slice(0, 10).join(", ")}${availableApps.length > 10 ? ", ..." : ""})`);
      remediation.push(`Run: sway-test list-apps to see all available applications`);
    }

    remediation.push(`Add the app to app-registry-data.nix if it's missing`);
    remediation.push(`Verify the registry was generated correctly: cat ~/.config/i3/application-registry.json`);

    throw new StructuredError(
      ErrorType.APP_NOT_FOUND,
      "App Registry Reader",
      `Application "${appName}" not found in registry`,
      remediation,
      {
        app_name: appName,
        registry_path: DEFAULT_REGISTRY_PATH,
        available_apps: availableApps,
        similar_apps: similarApps,
        app_count: availableApps.length
      }
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
      throw new StructuredError(
        ErrorType.REGISTRY_ERROR,
        "PWA Registry Loader",
        `PWA registry file not found at: ${expandedPath}`,
        [
          `Ensure the PWA registry file exists at ~/.config/i3/pwa-registry.json`,
          `Run: mkdir -p ~/.config/i3 && touch ~/.config/i3/pwa-registry.json`,
          `Verify Nix configuration generates the PWA registry file from pwa-sites.nix`
        ],
        {
          registry_path: expandedPath,
          expected_location: DEFAULT_PWA_REGISTRY_PATH
        }
      );
    }

    if (error instanceof z.ZodError) {
      const validationErrors = error.errors.map(e =>
        `${e.path.join(".")}: ${e.message}`
      );

      throw new StructuredError(
        ErrorType.REGISTRY_ERROR,
        "PWA Registry Loader",
        `Invalid PWA registry format - schema validation failed`,
        [
          `Fix the following validation errors in ${expandedPath}:`,
          ...validationErrors.map(err => `  - ${err}`),
          `Verify registry file matches expected JSON schema`,
          `Check for missing required fields (name, url, ulid, etc.)`
        ],
        {
          registry_path: expandedPath,
          validation_errors: validationErrors
        }
      );
    }

    throw new StructuredError(
      ErrorType.REGISTRY_ERROR,
      "PWA Registry Loader",
      `Failed to load PWA registry: ${error instanceof Error ? error.message : String(error)}`,
      [
        `Check file permissions for ${expandedPath}`,
        `Verify JSON syntax is valid`,
        `Ensure file is readable by current user`
      ],
      {
        registry_path: expandedPath,
        error_type: error instanceof Error ? error.name : typeof error
      }
    );
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
    throw new StructuredError(
      ErrorType.PWA_NOT_FOUND,
      "PWA Registry Reader",
      `PWA "${pwaName}" not found in registry`,
      [
        `Check the PWA name spelling (available: ${availablePWAs.join(", ")})`,
        `Add the PWA to pwa-sites.nix if it's missing`,
        `Verify the registry was generated correctly: cat ~/.config/i3/pwa-registry.json`,
        `Run pwa-list to see all configured PWAs`
      ],
      {
        pwa_name: pwaName,
        registry_path: DEFAULT_PWA_REGISTRY_PATH,
        available_pwas: availablePWAs,
        pwa_count: availablePWAs.length
      }
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
    throw new StructuredError(
      ErrorType.INVALID_ULID,
      "PWA Registry Reader",
      `Invalid ULID format: "${ulid}"`,
      [
        `ULID must be exactly 26 characters long`,
        `ULID must use base32 alphabet: 0-9, A-Z (excluding I, L, O, U)`,
        `Example valid ULID: 01ARZ3NDEKTSV4RRFFQ69G5FAV`,
        `Check PWA registry for correct ULID: cat ~/.config/i3/pwa-registry.json`
      ],
      {
        provided_ulid: ulid,
        ulid_length: ulid.length,
        expected_length: 26,
        valid_pattern: "^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$"
      }
    );
  }

  // Ensure registry is loaded
  await loadPWARegistry();

  if (!pwaRegistryByULID) {
    throw new StructuredError(
      ErrorType.REGISTRY_ERROR,
      "PWA Registry Reader",
      "PWA registry not loaded after loadPWARegistry() call",
      [
        `This is likely an internal error - the registry cache was not initialized`,
        `Try reloading the PWA registry`,
        `Check logs for registry loading errors`
      ],
      {
        cache_state: "null",
        registry_path: DEFAULT_PWA_REGISTRY_PATH
      }
    );
  }

  const pwa = pwaRegistryByULID.get(ulid);

  if (!pwa) {
    const availableULIDs = Array.from(pwaRegistryByULID.keys()).sort();
    throw new StructuredError(
      ErrorType.PWA_NOT_FOUND,
      "PWA Registry Reader",
      `PWA with ULID "${ulid}" not found in registry`,
      [
        `Check if the ULID is correct (available ULIDs: ${availableULIDs.join(", ")})`,
        `Install the PWA using firefoxpwa: firefoxpwa site install <url>`,
        `Add the PWA to pwa-sites.nix with the correct ULID`,
        `Run pwa-list to see all installed PWAs with their ULIDs`
      ],
      {
        requested_ulid: ulid,
        registry_path: DEFAULT_PWA_REGISTRY_PATH,
        available_ulids: availableULIDs,
        pwa_count: availableULIDs.length
      }
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

