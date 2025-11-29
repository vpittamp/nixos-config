/**
 * Feature 100: AccountConfig - GitHub Account Configuration
 *
 * Zod schema for account configuration.
 */

import { z } from "npm:zod@3.22.0";

/**
 * GitHub account or organization configuration.
 */
export const AccountConfigSchema = z.object({
  name: z
    .string()
    .min(1)
    .max(39)
    .regex(
      /^[a-zA-Z0-9][a-zA-Z0-9-]*$/,
      "Invalid GitHub username format"
    ),
  path: z.string().min(1),
  is_default: z.boolean().default(false),
  ssh_host: z.string().default("github.com"),
});

export type AccountConfig = z.infer<typeof AccountConfigSchema>;

/**
 * Storage schema for accounts.json
 */
export const AccountsStorageSchema = z.object({
  version: z.number().default(1),
  accounts: z.array(AccountConfigSchema).default([]),
});

export type AccountsStorage = z.infer<typeof AccountsStorageSchema>;
