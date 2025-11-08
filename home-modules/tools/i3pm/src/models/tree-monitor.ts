/**
 * Tree Monitor Data Models
 *
 * TypeScript interfaces for sway-tree-monitor daemon communication.
 * Based on Feature 065 data-model.md and contracts/rpc-protocol.json.
 */

/**
 * Represents a window or workspace state change captured by the daemon
 */
export interface Event {
  /** Unique event ID (UUID) */
  id: string;

  /** Unix timestamp (milliseconds) when event was captured */
  timestamp: number;

  /** Event type (e.g., "window::new", "workspace::focus") */
  type: string;

  /** Number of field-level changes in this event */
  change_count: number;

  /** Significance score (0.0-1.0): minimal, low, moderate, high, critical */
  significance: number;

  /** User action correlation (if any) */
  correlation?: Correlation;

  /** Field-level diff (only in detailed view via get_event) */
  diff?: Diff[];

  /** Enriched I3PM context (only if window-related event) */
  enrichment?: Enrichment;
}

/**
 * Links an event to a user action (keyboard binding, mouse click, etc.)
 */
export interface Correlation {
  /** Type of user action that triggered this event */
  action_type: string; // e.g., "binding", "mouse_click", "external_command"

  /** Sway binding command that was executed */
  binding_command?: string; // e.g., "exec alacritty", "workspace 2"

  /** Time delta (milliseconds) between user action and event */
  time_delta_ms: number;

  /** Confidence score (0.0-1.0) */
  confidence: number;

  /** Human-readable reasoning for correlation */
  reasoning: string;
}

/**
 * Field-level change within an event (tree node property modification)
 */
export interface Diff {
  /** JSON path to changed field (e.g., "focused", "geometry.width") */
  path: string;

  /** Type of change */
  change_type: "modified" | "added" | "removed";

  /** Old value (null for "added") */
  // deno-lint-ignore no-explicit-any
  old_value: any;

  /** New value (null for "removed") */
  // deno-lint-ignore no-explicit-any
  new_value: any;

  /** Significance score for this specific change (0.0-1.0) */
  significance: number;
}

/**
 * I3PM-specific context for window events
 */
export interface Enrichment {
  /** Process ID of window */
  pid: number;

  /** I3PM environment variables (if present) */
  i3pm_vars?: {
    APP_ID?: string;
    APP_NAME?: string;
    PROJECT_NAME?: string;
    SCOPE?: string; // "scoped" | "global"
    LAUNCH_CONTEXT?: string; // "daemon" | "manual"
  };

  /** Sway window marks (e.g., ["project:nixos", "app:vscode"]) */
  marks?: string[];

  /** Launch context metadata */
  launch_context?: {
    method: string; // "launcher" | "binding" | "scratchpad"
    timestamp: number; // Unix timestamp (ms)
  };
}

/**
 * Daemon performance and health metrics
 */
export interface Stats {
  /** Memory usage (MB) */
  memory_mb: number;

  /** CPU usage percentage */
  cpu_percent: number;

  /** Event buffer utilization */
  buffer: {
    current_size: number; // Number of events currently stored
    max_size: number; // Maximum capacity (500)
    utilization: number; // Percentage (0.0-1.0)
  };

  /** Event distribution by type */
  event_distribution: Record<string, number>; // { "window::new": 45, "workspace::focus": 12, ... }

  /** Diff computation performance */
  diff_stats: {
    avg_compute_time_ms: number;
    max_compute_time_ms: number;
    total_diffs_computed: number;
  };

  /** Daemon uptime (seconds) */
  uptime_seconds: number;

  /** Timestamp when stats were collected */
  timestamp: number;
}

/**
 * JSON-RPC 2.0 Request
 */
export interface RPCRequest {
  jsonrpc: "2.0";
  method: string;
  params?: Record<string, unknown>;
  id: string | number;
}

/**
 * JSON-RPC 2.0 Success Response
 */
export interface RPCSuccessResponse {
  jsonrpc: "2.0";
  // deno-lint-ignore no-explicit-any
  result: any;
  id: string | number;
}

/**
 * JSON-RPC 2.0 Error Object
 */
export interface RPCError {
  code: number;
  message: string;
  // deno-lint-ignore no-explicit-any
  data?: any;
}

/**
 * JSON-RPC 2.0 Error Response
 */
export interface RPCErrorResponse {
  jsonrpc: "2.0";
  error: RPCError;
  id: string | number | null;
}

/**
 * JSON-RPC 2.0 Response (success or error)
 */
export type RPCResponse = RPCSuccessResponse | RPCErrorResponse;

/**
 * Query parameters for query_events RPC method
 */
export interface QueryEventsParams extends Record<string, string | number | undefined> {
  /** Return last N events */
  last?: number;

  /** Return events since timestamp (ISO 8601 or human format "5m") */
  since?: string;

  /** Return events until timestamp (ISO 8601) */
  until?: string;

  /** Filter by event type (exact match or prefix) */
  filter?: string;
}

/**
 * Parameters for get_event RPC method
 */
export interface GetEventParams extends Record<string, string> {
  /** Event ID (UUID) */
  event_id: string;
}

/**
 * Get significance label from score
 */
export function getSignificanceLabel(score: number): string {
  if (score >= 0.8) return "critical";
  if (score >= 0.6) return "high";
  if (score >= 0.4) return "moderate";
  if (score >= 0.2) return "low";
  return "minimal";
}

/**
 * Get confidence indicator emoji from confidence score
 */
export function getConfidenceIndicator(confidence: number): string {
  if (confidence >= 0.90) return "🟢"; // Very Likely
  if (confidence >= 0.70) return "🟡"; // Likely
  if (confidence >= 0.50) return "🟠"; // Possible
  if (confidence >= 0.30) return "🔴"; // Unlikely
  return "⚫"; // Very Unlikely
}

/**
 * Validate Event object structure
 */
export function validateEvent(event: unknown): event is Event {
  if (typeof event !== "object" || event === null) return false;
  const e = event as Record<string, unknown>;

  return (
    typeof e.id === "string" &&
    typeof e.timestamp === "number" &&
    typeof e.type === "string" &&
    typeof e.change_count === "number" &&
    typeof e.significance === "number" &&
    e.significance >= 0.0 &&
    e.significance <= 1.0
  );
}

/**
 * Validate time filter format (5m, 1h, 30s, 2d)
 */
export function validateTimeFilter(input: string): boolean {
  return /^\d+[smhd]$/.test(input);
}

/**
 * Validate event type filter
 */
export function validateEventTypeFilter(input: string): boolean {
  const validPrefixes = ["window::", "workspace::"];
  const validExact = [
    "window::new",
    "window::close",
    "window::focus",
    "window::title",
    "window::move",
    "workspace::focus",
    "workspace::init",
    "workspace::empty",
  ];

  return validExact.includes(input) || validPrefixes.some((p) => input.startsWith(p));
}
