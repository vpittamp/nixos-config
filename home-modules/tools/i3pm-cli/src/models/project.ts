// Feature 087: Remote Project Environment Support
// Project Zod schema with optional remote configuration
// Created: 2025-11-22

/**
 * Project Zod schema for project management.
 *
 * Extends existing project model with optional remote configuration.
 */

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";
import { RemoteConfigSchema } from "./remote-config.ts";

export const ProjectSchema = z.object({
  name: z.string().min(1).regex(/^[a-zA-Z0-9_-]+$/),
  directory: z.string().min(1),
  display_name: z.string().min(1),
  icon: z.string().default("📁"),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
  scoped_classes: z.array(z.string()).default([]),

  // Feature 087: Optional remote configuration
  remote: RemoteConfigSchema.optional(),
});

export type Project = z.infer<typeof ProjectSchema>;
