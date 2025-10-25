/**
 * Zod Validation Schemas for i3pm Deno CLI
 *
 * Runtime type validation for daemon responses and user input.
 * These schemas ensure data integrity and provide clear error messages.
 */

import { z } from "zod";

// ============================================================================
// Core Window Management Schemas
// ============================================================================

export const WindowGeometrySchema = z.object({
  x: z.number(),
  y: z.number(),
  width: z.number().int().nonnegative(),
  height: z.number().int().nonnegative(),
});

export type WindowGeometryValidated = z.infer<typeof WindowGeometrySchema>;

export const WindowStateSchema = z.object({
  id: z.number().int().positive(),
  class: z.string().min(1),
  instance: z.string().optional(),
  title: z.string(),
  workspace: z.string().regex(/^\d+(:.+)?$/),
  output: z.string().min(1),
  marks: z.array(z.string()),
  focused: z.boolean(),
  hidden: z.boolean(),
  floating: z.boolean(),
  fullscreen: z.boolean(),
  geometry: WindowGeometrySchema,
});

export type WindowStateValidated = z.infer<typeof WindowStateSchema>;

export const WorkspaceSchema = z.object({
  number: z.number().int().min(1).max(999),
  name: z.string().min(1),
  focused: z.boolean(),
  visible: z.boolean(),
  output: z.string().min(1),
  windows: z.array(WindowStateSchema),
});

export type WorkspaceValidated = z.infer<typeof WorkspaceSchema>;

export const OutputGeometrySchema = z.object({
  x: z.number(),
  y: z.number(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
});

export type OutputGeometryValidated = z.infer<typeof OutputGeometrySchema>;

export const OutputSchema = z.object({
  name: z.string().min(1),
  active: z.boolean(),
  primary: z.boolean(),
  geometry: OutputGeometrySchema,
  current_workspace: z.string().min(1),
  workspaces: z.array(WorkspaceSchema),
});

export type OutputValidated = z.infer<typeof OutputSchema>;

// ============================================================================
// Project Management Schemas
// ============================================================================

export const ProjectSchema = z.object({
  name: z
    .string()
    .regex(/^[a-z0-9-]+$/, "Project name must be lowercase alphanumeric with hyphens"),
  display_name: z.string().min(1),
  icon: z.string().max(4), // Unicode emoji typically 1-4 bytes
  directory: z.string().min(1).regex(/^\//, "Directory must be absolute path"),
  scoped_classes: z.array(z.string()),
  created_at: z.number().int().positive(),
  last_used_at: z.number().int().positive(),
});

export type ProjectValidated = z.infer<typeof ProjectSchema>;

// ============================================================================
// Event System Schemas
// ============================================================================

export const EventTypeSchema = z.enum([
  "window",
  "workspace",
  "output",
  "binding",
  "shutdown",
  "tick",
]);

// Unified event schema with source field (Feature: Unified Event System)
// Extended for Feature 029: Linux System Log Integration
export const EventNotificationSchema = z.object({
  event_id: z.number().int().nonnegative(),
  event_type: z.string(), // Now accepts any event type (window::new, daemon::start, query::status, systemd::service::start, process::start, etc.)
  source: z.enum(["i3", "ipc", "daemon", "systemd", "proc"]), // Event source (Feature 029: added systemd, proc)
  timestamp: z.string(), // ISO 8601 timestamp string

  // Legacy fields (for backward compatibility with i3 event stream)
  change: z.string().optional(),
  container: z.union([WindowStateSchema, WorkspaceSchema, OutputSchema, z.null()]).optional(),

  // Window event fields
  window_id: z.number().int().positive().nullable().optional(),
  window_class: z.string().nullable().optional(),
  window_title: z.string().nullable().optional(),
  window_instance: z.string().nullable().optional(),
  workspace_name: z.string().nullable().optional(),

  // Project event fields
  project_name: z.string().nullable().optional(),
  project_directory: z.string().nullable().optional(),
  old_project: z.string().nullable().optional(),
  new_project: z.string().nullable().optional(),
  windows_affected: z.number().int().nonnegative().nullable().optional(),

  // Tick event fields
  tick_payload: z.string().nullable().optional(),

  // Output event fields
  output_name: z.string().nullable().optional(),
  output_count: z.number().int().nonnegative().nullable().optional(),

  // Query event fields
  query_method: z.string().nullable().optional(),
  query_params: z.record(z.any()).nullable().optional(),
  query_result_count: z.number().int().nonnegative().nullable().optional(),

  // Config event fields
  config_type: z.string().nullable().optional(),
  rules_added: z.number().int().nonnegative().nullable().optional(),
  rules_removed: z.number().int().nonnegative().nullable().optional(),

  // Daemon event fields
  daemon_version: z.string().nullable().optional(),
  i3_socket: z.string().nullable().optional(),

  // systemd event fields (Feature 029: Linux System Log Integration - User Story 1)
  systemd_unit: z.string().nullable().optional(), // Service unit name (e.g., "app-firefox-123.service")
  systemd_message: z.string().nullable().optional(), // systemd message (e.g., "Started Firefox Web Browser")
  systemd_pid: z.number().int().positive().nullable().optional(), // Process ID from journal _PID field
  journal_cursor: z.string().nullable().optional(), // Journal cursor for event position

  // Process event fields (Feature 029: Linux System Log Integration - User Story 2)
  process_pid: z.number().int().positive().nullable().optional(), // Process ID
  process_name: z.string().nullable().optional(), // Command name from /proc/{pid}/comm
  process_cmdline: z.string().nullable().optional(), // Full command line (sanitized, truncated)
  process_parent_pid: z.number().int().positive().nullable().optional(), // Parent process ID
  process_start_time: z.number().int().nonnegative().nullable().optional(), // Process start time (jiffies)

  // Processing metadata
  processing_duration_ms: z.number().nonnegative(),
  error: z.string().nullable().optional(),
});

export type EventNotificationValidated = z.infer<typeof EventNotificationSchema>;

// ============================================================================
// Event Correlation Schemas (Feature 029: US3)
// ============================================================================

export const EventCorrelationSchema = z.object({
  correlation_id: z.number().int().nonnegative(),
  created_at: z.string(), // ISO 8601 timestamp
  confidence_score: z.number().min(0.0).max(1.0),

  parent_event_id: z.number().int().nonnegative(),
  child_event_ids: z.array(z.number().int().nonnegative()).min(1),
  correlation_type: z.enum(["window_to_process", "process_to_subprocess"]),

  time_delta_ms: z.number().nonnegative(),
  detection_window_ms: z.number().nonnegative(),

  timing_factor: z.number().min(0.0).max(1.0),
  hierarchy_factor: z.number().min(0.0).max(1.0),
  name_similarity: z.number().min(0.0).max(1.0),
  workspace_match: z.boolean(),
});

export type EventCorrelation = z.infer<typeof EventCorrelationSchema>;

// ============================================================================
// Daemon Status Schemas
// ============================================================================

export const DaemonStatusSchema = z.object({
  status: z.enum(["running", "stopped"]),
  connected: z.boolean(),
  uptime: z.number().nonnegative(),
  active_project: z.string().nullable(),
  window_count: z.number().int().nonnegative(),
  workspace_count: z.number().int().nonnegative(),
  event_count: z.number().int().nonnegative(),
  error_count: z.number().int().nonnegative(),
  version: z.string(),
  socket_path: z.string().min(1),
});

export type DaemonStatusValidated = z.infer<typeof DaemonStatusSchema>;

// ============================================================================
// Window Classification Schemas
// ============================================================================

export const WindowRuleSchema = z.object({
  rule_id: z.string().uuid(),
  class_pattern: z.string().min(1),
  instance_pattern: z.string().optional(),
  scope: z.enum(["scoped", "global"]),
  priority: z.number().int().nonnegative(),
  enabled: z.boolean(),
});

export type WindowRuleValidated = z.infer<typeof WindowRuleSchema>;

export const ApplicationClassSchema = z.object({
  class_name: z.string().min(1),
  display_name: z.string().min(1),
  scope: z.enum(["scoped", "global"]),
  icon: z.string().max(4).optional(),
  description: z.string().optional(),
});

export type ApplicationClassValidated = z.infer<typeof ApplicationClassSchema>;

// ============================================================================
// RPC Response Schemas
// ============================================================================

export const SwitchProjectResultSchema = z.object({
  previous_project: z.string().nullable(),
  new_project: z.string(),
  windows_hidden: z.number().int().nonnegative(),
  windows_shown: z.number().int().nonnegative(),
});

export type SwitchProjectResultValidated = z.infer<typeof SwitchProjectResultSchema>;

export const ClearProjectResultSchema = z.object({
  previous_project: z.string().nullable(),
  windows_shown: z.number().int().nonnegative(),
});

export type ClearProjectResultValidated = z.infer<typeof ClearProjectResultSchema>;

export const ClassifyWindowResultSchema = z.object({
  class: z.string(),
  instance: z.string().optional(),
  scope: z.enum(["scoped", "global"]),
  matched_rule: z
    .object({
      rule_id: z.string().uuid(),
      priority: z.number().int().nonnegative(),
    })
    .optional(),
});

export type ClassifyWindowResultValidated = z.infer<typeof ClassifyWindowResultSchema>;

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Validate and parse daemon response
 */
export function validateResponse<T>(schema: z.ZodSchema<T>, data: unknown): T {
  try {
    return schema.parse(data);
  } catch (err) {
    if (err instanceof z.ZodError) {
      const issues = err.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`);
      throw new Error(
        `Invalid daemon response:\n  ${issues.join("\n  ")}\n\n` +
          "This may indicate a protocol version mismatch between CLI and daemon.",
      );
    }
    throw err;
  }
}

/**
 * Validate project name format
 */
export function validateProjectName(name: string): boolean {
  return /^[a-z0-9-]+$/.test(name);
}

/**
 * Validate directory path format
 */
export function validateDirectory(path: string): boolean {
  return path.startsWith("/");
}

/**
 * Validate workspace name format
 */
export function validateWorkspaceName(name: string): boolean {
  return /^\d+(:.+)?$/.test(name);
}
