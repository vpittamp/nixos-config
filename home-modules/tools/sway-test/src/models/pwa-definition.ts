/**
 * PWA Definition Model
 *
 * Data structures for Progressive Web Apps loaded from pwa-sites.nix
 * Used by launch_pwa_sync action and list-pwas command
 */

import { z } from "npm:zod@^3.22.4";

/**
 * PWA Definition from pwa-sites.nix
 * Maps friendly name to PWA metadata including ULID identifier
 */
export interface PWADefinition {
  /** Friendly name for PWA (e.g., "youtube", "claude") */
  name: string;

  /** Full URL of the PWA (e.g., "https://www.youtube.com") */
  url: string;

  /** Firefox PWA ULID identifier (26-char base32) */
  ulid: string;

  /** Preferred workspace number (optional) */
  preferred_workspace?: number;

  /** Preferred monitor role: primary, secondary, or tertiary (optional) */
  preferred_monitor_role?: "primary" | "secondary" | "tertiary";
}

/**
 * Zod schema for PWADefinition
 * Validates ULID format (26 characters, base32 alphabet)
 */
export const PWADefinitionSchema = z.object({
  name: z.string().min(1),
  url: z.string().url(),
  ulid: z.string().regex(/^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/, {
    message: "ULID must be 26 characters using base32 alphabet (0-9, A-Z excluding I, L, O, U)",
  }),
  preferred_workspace: z.number().int().positive().optional(),
  preferred_monitor_role: z.enum(["primary", "secondary", "tertiary"]).optional(),
});

/**
 * List entry for PWA display in list-pwas command
 * Formatted table output
 */
export interface PWAListEntry {
  /** Friendly name */
  name: string;

  /** PWA URL */
  url: string;

  /** ULID identifier */
  ulid: string;

  /** Workspace assignment or "none" */
  workspace: string;

  /** Monitor role or "none" */
  monitor: string;
}

/**
 * Zod schema for PWAListEntry
 */
export const PWAListEntrySchema = z.object({
  name: z.string(),
  url: z.string(),
  ulid: z.string(),
  workspace: z.string(),
  monitor: z.string(),
});

/**
 * Collection of PWA definitions
 */
export interface PWARegistry {
  pwas: PWADefinition[];
}

/**
 * Zod schema for PWARegistry
 */
export const PWARegistrySchema = z.object({
  pwas: z.array(PWADefinitionSchema),
});
