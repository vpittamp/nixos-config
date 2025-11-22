// Feature 087: Remote Project Environment Support
// RemoteConfig Zod schema for SSH-based remote projects
// Created: 2025-11-22

/**
 * RemoteConfig Zod schema for SSH connection parameters.
 *
 * Provides validation for remote project environments accessed via SSH.
 * Supports Tailscale hostnames, custom ports, and absolute remote paths.
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const RemoteConfigSchema = z.object({
  enabled: z.boolean().default(false),
  host: z.string().min(1, "Host is required"),
  user: z.string().min(1, "User is required"),
  working_dir: z.string()
    .min(1, "Working directory is required")
    .refine((val) => val.startsWith("/"), {
      message: "Remote working_dir must be absolute path (starts with '/')",
    }),
  port: z.number().int().min(1).max(65535).default(22),
});

export type RemoteConfig = z.infer<typeof RemoteConfigSchema>;
