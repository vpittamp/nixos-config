/**
 * TypeScript/Zod models for workspace-to-monitor mapping (Feature 033)
 *
 * These models correspond to the Pydantic models in the Python daemon
 * and provide runtime validation for daemon responses.
 */

import { z } from "zod";

// ============================================================================
// Configuration Models
// ============================================================================

export const MonitorRoleSchema = z.enum(["primary", "secondary", "tertiary"]);
export type MonitorRole = z.infer<typeof MonitorRoleSchema>;

export const MonitorDistributionSchema = z.object({
  primary: z.array(z.number().int().positive()).default([]),
  secondary: z.array(z.number().int().positive()).default([]),
  tertiary: z.array(z.number().int().positive()).default([]),
});
export type MonitorDistribution = z.infer<typeof MonitorDistributionSchema>;

export const DistributionRulesSchema = z.object({
  one_monitor: MonitorDistributionSchema,
  two_monitors: MonitorDistributionSchema,
  three_monitors: MonitorDistributionSchema,
});
export type DistributionRules = z.infer<typeof DistributionRulesSchema>;

export const WorkspaceMonitorConfigSchema = z.object({
  version: z.string().default("1.0"),
  distribution: DistributionRulesSchema,
  workspace_preferences: z.record(z.string(), MonitorRoleSchema).default({}),
  output_preferences: z.record(MonitorRoleSchema, z.array(z.string())).default({}),
  debounce_ms: z.number().int().min(0).max(5000).default(1000),
  enable_auto_reassign: z.boolean().default(true),
}).passthrough(); // Allow unknown fields for forward compatibility

export type WorkspaceMonitorConfig = z.infer<typeof WorkspaceMonitorConfigSchema>;

/**
 * Create a default configuration object
 */
export function createDefaultConfig(): WorkspaceMonitorConfig {
  return {
    version: "1.0",
    distribution: {
      one_monitor: {
        primary: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        secondary: [],
        tertiary: [],
      },
      two_monitors: {
        primary: [1, 2],
        secondary: [3, 4, 5, 6, 7, 8, 9, 10],
        tertiary: [],
      },
      three_monitors: {
        primary: [1, 2],
        secondary: [3, 4, 5],
        tertiary: [6, 7, 8, 9, 10],
      },
    },
    workspace_preferences: {},
    output_preferences: {},
    debounce_ms: 1000,
    enable_auto_reassign: true,
  };
}

// ============================================================================
// i3 State Models
// ============================================================================

export const OutputRectSchema = z.object({
  x: z.number().int(),
  y: z.number().int(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
});
export type OutputRect = z.infer<typeof OutputRectSchema>;

export const MonitorConfigSchema = z.object({
  name: z.string().min(1),
  active: z.boolean(),
  primary: z.boolean(),
  role: MonitorRoleSchema.nullable(),
  rect: OutputRectSchema,
  current_workspace: z.string().nullable(),
  make: z.string().nullable().optional(),
  model: z.string().nullable().optional(),
  serial: z.string().nullable().optional(),
});
export type MonitorConfig = z.infer<typeof MonitorConfigSchema>;

export const WorkspaceAssignmentSchema = z.object({
  workspace_num: z.number().int().positive(),
  output_name: z.string().nullable(),
  target_role: MonitorRoleSchema.nullable(),
  target_output: z.string().nullable(),
  source: z.enum(["default", "explicit", "runtime"]),
  visible: z.boolean(),
  window_count: z.number().int().nonnegative().default(0),
});
export type WorkspaceAssignment = z.infer<typeof WorkspaceAssignmentSchema>;

// ============================================================================
// System State Models
// ============================================================================

export const MonitorSystemStateSchema = z.object({
  monitors: z.array(MonitorConfigSchema),
  workspaces: z.array(WorkspaceAssignmentSchema),
  active_monitor_count: z.number().int().nonnegative(),
  primary_output: z.string().nullable(),
  last_updated: z.number(),
});
export type MonitorSystemState = z.infer<typeof MonitorSystemStateSchema>;

export const ValidationIssueSchema = z.object({
  severity: z.enum(["error", "warning"]),
  field: z.string(),
  message: z.string(),
});
export type ValidationIssue = z.infer<typeof ValidationIssueSchema>;

export const ConfigValidationResultSchema = z.object({
  valid: z.boolean(),
  issues: z.array(ValidationIssueSchema).default([]),
  config: WorkspaceMonitorConfigSchema.nullable(),
});
export type ConfigValidationResult = z.infer<typeof ConfigValidationResultSchema>;

// ============================================================================
// JSON-RPC Response Models
// ============================================================================

export const JsonRpcRequestSchema = z.object({
  jsonrpc: z.literal("2.0"),
  method: z.string(),
  params: z.unknown().optional(),
  id: z.number().int(),
});
export type JsonRpcRequest = z.infer<typeof JsonRpcRequestSchema>;

export const JsonRpcErrorSchema = z.object({
  code: z.number().int(),
  message: z.string(),
  data: z.unknown().optional(),
});
export type JsonRpcError = z.infer<typeof JsonRpcErrorSchema>;

export const JsonRpcResponseSchema = z.object({
  jsonrpc: z.literal("2.0"),
  result: z.unknown().optional(),
  error: JsonRpcErrorSchema.optional(),
  id: z.number().int(),
});
export type JsonRpcResponse = z.infer<typeof JsonRpcResponseSchema>;

// Specific Method Responses
export const GetMonitorsResponseSchema = z.array(MonitorConfigSchema);
export type GetMonitorsResponse = z.infer<typeof GetMonitorsResponseSchema>;

export const GetWorkspacesResponseSchema = z.array(WorkspaceAssignmentSchema);
export type GetWorkspacesResponse = z.infer<typeof GetWorkspacesResponseSchema>;

export const GetSystemStateResponseSchema = MonitorSystemStateSchema;
export type GetSystemStateResponse = z.infer<typeof GetSystemStateResponseSchema>;

export const GetConfigResponseSchema = WorkspaceMonitorConfigSchema;
export type GetConfigResponse = z.infer<typeof GetConfigResponseSchema>;

export const ValidateConfigResponseSchema = ConfigValidationResultSchema;
export type ValidateConfigResponse = z.infer<typeof ValidateConfigResponseSchema>;

export const ReassignWorkspacesResponseSchema = z.object({
  success: z.boolean(),
  assignments_made: z.number().int().nonnegative(),
  errors: z.array(z.string()).default([]),
});
export type ReassignWorkspacesResponse = z.infer<typeof ReassignWorkspacesResponseSchema>;

export const MoveWorkspaceResponseSchema = z.object({
  success: z.boolean(),
  workspace_num: z.number().int().positive(),
  from_output: z.string().nullable(),
  to_output: z.string(),
  error: z.string().nullable(),
});
export type MoveWorkspaceResponse = z.infer<typeof MoveWorkspaceResponseSchema>;

export const ReloadConfigResponseSchema = z.object({
  success: z.boolean(),
  changes: z.array(z.string()).default([]),
  error: z.string().nullable(),
});
export type ReloadConfigResponse = z.infer<typeof ReloadConfigResponseSchema>;

// ============================================================================
// Validation Helper
// ============================================================================

/**
 * Validate a response against a Zod schema with user-friendly error messages
 */
export function validateResponse<T>(schema: z.ZodSchema<T>, data: unknown): T {
  try {
    return schema.parse(data);
  } catch (err) {
    if (err instanceof z.ZodError) {
      const issues = err.issues.map((issue) =>
        `${issue.path.join(".")}: ${issue.message}`
      );
      throw new Error(
        `Invalid daemon response:\n  ${issues.join("\n  ")}\n\n` +
        "This may indicate a protocol version mismatch between CLI and daemon."
      );
    }
    throw err;
  }
}
