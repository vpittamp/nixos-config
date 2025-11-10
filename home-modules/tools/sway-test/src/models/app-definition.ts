/**
 * App Definition Model
 *
 * Data structures for applications loaded from application-registry.json
 * Used by app discovery and launch_app_sync action
 */

import { z } from "npm:zod@^3.22.4";

/**
 * App Definition from application-registry.json
 * Maps app name to metadata including command, workspace preferences, and scope
 */
export interface AppDefinition {
  /** App name (e.g., "firefox", "code", "alacritty") */
  name: string;

  /** Display name for UI (e.g., "Firefox", "VS Code") */
  display_name?: string;

  /** Command to launch the app */
  command: string;

  /** Optional command-line parameters */
  parameters?: string[];

  /** Expected window class or app_id */
  expected_class?: string;

  /** Preferred workspace number (optional) */
  preferred_workspace?: number;

  /** Preferred monitor role: primary, secondary, or tertiary (optional) */
  preferred_monitor_role?: "primary" | "secondary" | "tertiary";

  /** App scope: global or scoped */
  scope: "global" | "scoped";

  /** Description of the app (optional) */
  description?: string;

  /** Icon name or path (optional) */
  icon?: string;

  /** Nix package name (optional) */
  nix_package?: string;

  /** Whether app supports multiple instances */
  multi_instance?: boolean;

  /** Fallback behavior when app already running */
  fallback_behavior?: string;

  /** Whether app should launch in terminal */
  terminal?: boolean;

  /** Floating window configuration (optional) */
  floating?: boolean;

  /** Floating window size preset (optional) */
  floating_size?: "scratchpad" | "small" | "medium" | "large" | null;

  /** Associated PWAs (optional) */
  pwas?: Array<{
    id: string;
    expected_class: string;
  }>;
}

/**
 * Zod schema for AppDefinition
 * Validates app definition structure from application-registry.json
 */
export const AppDefinitionSchema = z.object({
  name: z.string().min(1).regex(/^[a-z0-9-]+$/),
  display_name: z.string().optional(),
  command: z.string().min(1),
  parameters: z.array(z.string()).optional(),
  expected_class: z.string().min(1).optional(),
  preferred_workspace: z.number().int().positive().optional(),
  preferred_monitor_role: z.enum(["primary", "secondary", "tertiary"]).optional(),
  scope: z.enum(["global", "scoped"]),
  description: z.string().optional(),
  icon: z.string().optional(),
  nix_package: z.string().optional(),
  multi_instance: z.boolean().optional(),
  fallback_behavior: z.string().optional(),
  terminal: z.boolean().optional(),
  floating: z.boolean().optional(),
  floating_size: z.enum(["scratchpad", "small", "medium", "large"]).nullable().optional(),
  pwas: z.array(z.object({
    id: z.string().min(1),
    expected_class: z.string().min(1),
  })).optional(),
});

/**
 * List entry for app display in list-apps command
 * Formatted table output
 */
export interface AppListEntry {
  /** App name */
  name: string;

  /** Display name */
  display_name: string;

  /** App command */
  command: string;

  /** Workspace assignment or "none" */
  workspace: string;

  /** Monitor role or "none" */
  monitor: string;

  /** Scope (global or scoped) */
  scope: string;
}

/**
 * Zod schema for AppListEntry
 */
export const AppListEntrySchema = z.object({
  name: z.string(),
  display_name: z.string(),
  command: z.string(),
  workspace: z.string(),
  monitor: z.string(),
  scope: z.string(),
});

/**
 * Collection of app definitions
 */
export interface AppRegistry {
  version: string;
  applications: AppDefinition[];
}

/**
 * Zod schema for AppRegistry
 */
export const AppRegistrySchema = z.object({
  version: z.string(),
  applications: z.array(AppDefinitionSchema),
});
