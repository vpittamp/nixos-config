/**
 * TypeScript Type Definitions for i3pm Deno CLI
 *
 * These types serve as contracts between the daemon (via JSON-RPC) and the CLI,
 * ensuring type safety throughout the application.
 */

// ============================================================================
// Core Window Management Entities
// ============================================================================

export interface WindowGeometry {
  /** X coordinate in pixels */
  x: number;

  /** Y coordinate in pixels */
  y: number;

  /** Width in pixels */
  width: number;

  /** Height in pixels */
  height: number;
}

export interface WindowState {
  /** Unique window identifier from i3 */
  id: number;

  /** Process ID of the window */
  pid?: number;

  /** Window class (application identifier) */
  class: string;

  /** Window instance (optional sub-identifier) */
  instance?: string;

  /** Current window title */
  title: string;

  /** Workspace where window resides (e.g., "1", "2:web", "9") */
  workspace: string;

  /** Output (monitor) where workspace is displayed */
  output: string;

  /** i3 marks assigned to window (including project mark like "project:nixos") */
  marks: string[];

  /** Whether window has focus */
  focused: boolean;

  /** Whether window is currently hidden (scoped to inactive project) */
  hidden: boolean;

  /** Whether window is floating (not tiled) */
  floating: boolean;

  /** Whether window is in fullscreen mode */
  fullscreen: boolean;

  /** Window geometry (position and size) */
  geometry: WindowGeometry;
}

export interface Workspace {
  /** Workspace number (1-9 typically) */
  number: number;

  /** Workspace name (e.g., "1:web", "2:code", "3") */
  name: string;

  /** Whether workspace has focus */
  focused: boolean;

  /** Whether workspace is visible on any output */
  visible: boolean;

  /** Output (monitor) where workspace is currently assigned */
  output: string;

  /** Windows contained in this workspace */
  windows: WindowState[];
}

export interface OutputGeometry {
  /** X coordinate in virtual screen space */
  x: number;

  /** Y coordinate in virtual screen space */
  y: number;

  /** Width in pixels (resolution) */
  width: number;

  /** Height in pixels (resolution) */
  height: number;
}

export interface Output {
  /** Output name from i3 (e.g., "eDP-1", "HDMI-1", "Virtual-1") */
  name: string;

  /** Whether output is currently active (connected and enabled) */
  active: boolean;

  /** Whether output is the primary monitor */
  primary: boolean;

  /** Output geometry (position and resolution) */
  geometry: OutputGeometry;

  /** Name of currently visible workspace on this output */
  current_workspace: string;

  /** All workspaces assigned to this output */
  workspaces: Workspace[];
}

// ============================================================================
// Project Management Entities
// ============================================================================

export interface Project {
  /** Unique project identifier (slug) */
  name: string;

  /** Human-readable display name */
  display_name: string;

  /** Emoji or Unicode icon for visual identification */
  icon: string;

  /** Absolute path to project directory */
  directory: string;

  /** List of window classes that are scoped to this project */
  scoped_classes: string[];

  /** Unix timestamp when project was created */
  created_at: number;

  /** Unix timestamp when project was last activated */
  last_used_at: number;
}

// ============================================================================
// Event System Entities
// ============================================================================

export enum EventType {
  Window = "window",
  Workspace = "workspace",
  Output = "output",
  Binding = "binding",
  Shutdown = "shutdown",
  Tick = "tick",
}

export const WindowChangeType = {
  New: "new",
  Close: "close",
  Focus: "focus",
  Title: "title",
  FullscreenMode: "fullscreen_mode",
  Move: "move",
  Floating: "floating",
  Urgent: "urgent",
  Mark: "mark",
} as const;

export const WorkspaceChangeType = {
  Focus: "focus",
  Init: "init",
  Empty: "empty",
  Urgent: "urgent",
  Rename: "rename",
  Move: "move",
  Reload: "reload",
} as const;

export interface EventNotification {
  /** Sequential event ID (monotonically increasing) */
  event_id: number;

  /** Type of i3 event */
  event_type: EventType;

  /** Specific change within event type */
  change: string;

  /** Affected container/window/workspace data */
  container: WindowState | Workspace | Output | null;

  /** Unix timestamp when event occurred (milliseconds) */
  timestamp: number;
}

// ============================================================================
// Daemon Status Entities
// ============================================================================

export interface DaemonStatus {
  /** Status string: "running" or "stopped" */
  status: "running" | "stopped";

  /** Whether daemon is connected to i3 IPC */
  connected: boolean;

  /** Daemon uptime in seconds */
  uptime: number;

  /** Name of currently active project (or null for global mode) */
  active_project: string | null;

  /** Total number of tracked windows */
  window_count: number;

  /** Total number of workspaces */
  workspace_count: number;

  /** Total number of processed events since daemon start */
  event_count: number;

  /** Number of errors encountered since daemon start */
  error_count: number;

  /** Daemon version string */
  version: string;

  /** Unix socket path for IPC */
  socket_path: string;
}

// ============================================================================
// Window Classification Entities
// ============================================================================

export interface WindowRule {
  /** Unique rule identifier */
  rule_id: string;

  /** Window class pattern (regex) */
  class_pattern: string;

  /** Window instance pattern (optional regex) */
  instance_pattern?: string;

  /** Scope assignment: "scoped" or "global" */
  scope: "scoped" | "global";

  /** Rule priority (higher priority wins on conflicts) */
  priority: number;

  /** Whether rule is enabled */
  enabled: boolean;
}

export interface ApplicationClass {
  /** Window class name (from i3) */
  class_name: string;

  /** Human-readable display name */
  display_name: string;

  /** Scope: "scoped" (project-specific) or "global" (always visible) */
  scope: "scoped" | "global";

  /** Icon for visual identification (emoji or Unicode) */
  icon?: string;

  /** Description of application purpose */
  description?: string;
}

// ============================================================================
// JSON-RPC Protocol Types
// ============================================================================

export interface JsonRpcRequest<P = unknown> {
  jsonrpc: "2.0";
  method: string;
  params?: P;
  id: number;
}

export interface JsonRpcResponse<T = unknown> {
  jsonrpc: "2.0";
  result?: T;
  error?: JsonRpcError;
  id: number;
}

export interface JsonRpcNotification<P = unknown> {
  jsonrpc: "2.0";
  method: string;
  params?: P;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

export enum JsonRpcErrorCode {
  ParseError = -32700,
  InvalidRequest = -32600,
  MethodNotFound = -32601,
  InvalidParams = -32602,
  InternalError = -32603,
  ServerError = -32000,
}

// ============================================================================
// Request/Response Parameter Types
// ============================================================================

export interface GetWindowsParams {
  filter?: {
    workspace?: string;
    output?: string;
    project?: string;
    hidden?: boolean;
  };
}

export interface SwitchProjectParams {
  project_name: string;
}

export interface CreateProjectParams {
  name: string;
  directory: string;
  icon?: string;
  display_name?: string;
}

export interface GetProjectParams {
  project_name: string;
}

export interface DeleteProjectParams {
  project_name: string;
}

export interface GetEventsParams {
  limit?: number;
  since_id?: number;
  event_type?: EventType;
}

export interface EventNotificationParams {
  event: EventNotification;
}

export interface ClassifyWindowParams {
  class: string;
  instance?: string;
}

export interface ClassifyWindowResult {
  class: string;
  instance?: string;
  scope: "scoped" | "global";
  matched_rule?: {
    rule_id: string;
    priority: number;
  };
}

export interface SwitchProjectResult {
  previous_project: string | null;
  new_project: string;
  windows_hidden: number;
  windows_shown: number;
}

export interface ClearProjectResult {
  previous_project: string | null;
  windows_shown: number;
}

// ============================================================================
// CLI-Specific Types
// ============================================================================

export interface GlobalOptions {
  help: boolean;
  version: boolean;
  verbose: boolean;
  debug: boolean;
}

export interface WindowsOptions extends GlobalOptions {
  tree: boolean;
  table: boolean;
  json: boolean;
  live: boolean;
  hidden: boolean;
  project?: string;
  output?: string;
}

export interface ProjectOptions extends GlobalOptions {
  name?: string;
  dir?: string;
  icon?: string;
  displayName?: string;
}

export interface DaemonOptions extends GlobalOptions {
  limit?: number;
  type?: EventType;
  sinceId?: number;
}

export interface RulesOptions extends GlobalOptions {
  class?: string;
  instance?: string;
}

// ============================================================================
// Layout Persistence Entities (Feature 030: Production Readiness)
// ============================================================================

export enum LayoutMode {
  SplitH = "splith",
  SplitV = "splitv",
  Tabbed = "tabbed",
  Stacked = "stacked",
}

export interface WindowPlaceholder {
  /** Expected WM_CLASS */
  windowClass?: string;

  /** Expected WM_CLASS instance */
  instance?: string;

  /** Regex pattern for window title */
  titlePattern?: string;

  /** Command to launch application */
  launchCommand: string;

  /** Target position and size */
  geometry: WindowGeometry;

  /** Target floating state */
  floating: boolean;

  /** Marks to apply after swallow */
  marks?: string[];
}

export interface Container {
  /** Container layout mode */
  layout: LayoutMode;

  /** Percent of parent container space (0.0-1.0) */
  percent?: number;

  /** Child containers */
  nodes: Container[];
}

export interface WorkspaceLayout {
  /** Workspace number (1-99) */
  workspaceNum: number;

  /** Workspace name (if named) */
  workspaceName?: string;

  /** Assigned monitor/output */
  output: string;

  /** Container layout mode */
  layoutMode: LayoutMode;

  /** Container tree structure */
  containers: Container[];

  /** Window placeholders for restoration */
  windows: WindowPlaceholder[];
}

export interface Resolution {
  /** Width in pixels */
  width: number;

  /** Height in pixels */
  height: number;
}

export interface Position {
  /** X coordinate */
  x: number;

  /** Y coordinate */
  y: number;
}

export interface Monitor {
  /** Output name (e.g., "eDP-1", "DP-1") */
  name: string;

  /** Output is currently active */
  active: boolean;

  /** Primary display flag */
  primary: boolean;

  /** Currently visible workspace */
  currentWorkspace?: string;

  /** Display resolution */
  resolution?: Resolution;

  /** Display position in multi-monitor setup */
  position: Position;
}

export interface MonitorConfiguration {
  /** Configuration name (e.g., "dual-monitor", "laptop-only") */
  name: string;

  /** Monitor definitions */
  monitors: Monitor[];

  /** Workspace → output mapping */
  workspaceAssignments: Record<number, string>;

  /** Configuration creation time */
  createdAt: Date;
}

export interface LayoutSnapshot {
  /** Unique layout name within project */
  name: string;

  /** Associated project name */
  project: string;

  /** Snapshot timestamp */
  createdAt: Date;

  /** Monitor arrangement at capture time */
  monitorConfig: MonitorConfiguration;

  /** Layouts for each workspace */
  workspaceLayouts: WorkspaceLayout[];

  /** Additional metadata (tags, description) */
  metadata?: Record<string, unknown>;
}

// ============================================================================
// Event System Extensions (Feature 029: Linux System Log Integration)
// ============================================================================

export enum EventSource {
  I3 = "i3",
  Systemd = "systemd",
  Proc = "proc",
}

export interface Event {
  /** Unique event identifier (UUID) */
  eventId: string;

  /** Event origin */
  source: EventSource;

  /** Type of event */
  eventType: string;

  /** Event occurrence time */
  timestamp: Date;

  /** Event-specific payload */
  data: Record<string, unknown>;

  /** Related event ID (UUID) */
  correlationId?: string;

  /** Correlation confidence (0.0-1.0) */
  confidenceScore?: number;
}

// ============================================================================
// Classification System (Feature 030: Production Readiness)
// ============================================================================

export enum ScopeType {
  Scoped = "scoped",
  Global = "global",
}

export enum PatternType {
  Class = "class",
  Instance = "instance",
  Title = "title",
}

export enum RuleSource {
  System = "system",
  User = "user",
}

export interface ClassificationRule {
  /** Regex pattern matching window property */
  pattern: string;

  /** Scoped or global classification */
  scopeType: ScopeType;

  /** Rule precedence (higher wins) */
  priority: number;

  /** What property to match */
  patternType: PatternType;

  /** System-wide or user-defined */
  source: RuleSource;
}

// ============================================================================
// Extended Project Model (Feature 030: Production Readiness)
// ============================================================================

export interface ProjectExtended extends Project {
  /** Saved workspace layouts */
  layoutSnapshots?: LayoutSnapshot[];
}
