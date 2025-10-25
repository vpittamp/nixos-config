/**
 * Layout configuration models
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Window position snapshots with application instance IDs for exact
 * window matching during layout restore.
 */

/**
 * Window snapshot
 * Captures window state with application instance ID for deterministic matching
 */
export interface WindowSnapshot {
  // Application reference (registry-based)
  registry_app_id: string; // Must match registry entry name
  app_instance_id: string; // Unique instance ID for exact matching (NEW)

  // Window geometry (absolute coordinates)
  workspace: number; // Workspace number (1-9)
  x: number; // X coordinate in pixels
  y: number; // Y coordinate in pixels
  width: number; // Width in pixels
  height: number; // Height in pixels

  // Window state
  floating: boolean; // Is window floating or tiled
  focused: boolean; // Was this window focused when captured

  // Optional metadata for debugging
  captured_class?: string; // Actual WM_CLASS at capture time
  captured_title?: string; // Actual window title at capture time
  captured_pid?: number; // Process PID at capture time
}

/**
 * Layout configuration
 * Location: ~/.config/i3/layouts/<layout-name>.json
 */
export interface Layout {
  project_name: string; // Project this layout belongs to
  layout_name: string; // Unique layout identifier

  // Window snapshots
  windows: WindowSnapshot[]; // Array of window states

  // Metadata
  captured_at: string; // ISO 8601 timestamp of layout save
  i3_version: string; // i3 version at capture time (for compatibility)
}

/**
 * Layout save parameters
 */
export interface SaveLayoutParams {
  project_name: string;
  layout_name?: string; // Optional: defaults to project name
  overwrite?: boolean; // Allow overwriting existing layout
}

/**
 * Layout restore parameters
 */
export interface RestoreLayoutParams {
  project_name: string;
  layout_name?: string; // Optional: defaults to project's saved_layout
  dry_run?: boolean; // Preview without launching
  timeout?: number; // Timeout per application launch (milliseconds)
}

/**
 * Layout restore progress
 */
export interface RestoreProgress {
  total_windows: number;
  launched: number;
  positioned: number;
  failed: number;
  skipped: number;
  current_app?: string;
}

/**
 * Type guards for runtime validation
 */
export function isWindowSnapshot(value: unknown): value is WindowSnapshot {
  if (typeof value !== "object" || value === null) return false;
  const window = value as Record<string, unknown>;

  return (
    typeof window.registry_app_id === "string" &&
    typeof window.app_instance_id === "string" &&
    typeof window.workspace === "number" &&
    window.workspace >= 1 &&
    window.workspace <= 9 &&
    typeof window.x === "number" &&
    typeof window.y === "number" &&
    typeof window.width === "number" &&
    typeof window.height === "number" &&
    typeof window.floating === "boolean" &&
    typeof window.focused === "boolean"
  );
}

export function isLayout(value: unknown): value is Layout {
  if (typeof value !== "object" || value === null) return false;
  const layout = value as Record<string, unknown>;

  return (
    typeof layout.project_name === "string" &&
    typeof layout.layout_name === "string" &&
    Array.isArray(layout.windows) &&
    layout.windows.every(isWindowSnapshot) &&
    typeof layout.captured_at === "string" &&
    typeof layout.i3_version === "string"
  );
}

/**
 * Validate layout has at most one focused window
 */
export function validateSingleFocus(layout: Layout): boolean {
  const focusedWindows = layout.windows.filter((w) => w.focused);
  return focusedWindows.length <= 1;
}

/**
 * Get focused window from layout
 */
export function getFocusedWindow(layout: Layout): WindowSnapshot | null {
  return layout.windows.find((w) => w.focused) || null;
}
