/**
 * State Snapshot Model
 *
 * Defines the structure for captured Sway window tree state from `swaymsg -t get_tree`.
 * This matches the actual Sway IPC tree structure.
 */

/**
 * Rectangle geometry
 */
export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Node type in Sway tree
 */
export type NodeType = "root" | "output" | "workspace" | "con" | "floating_con";

/**
 * Window properties
 */
export interface WindowProps {
  class?: string;
  instance?: string;
  title?: string;
  window_role?: string;
}

/**
 * Generic tree node (workspace, container, window)
 */
export interface Node {
  id: number;
  name: string;
  type: NodeType;

  // Layout
  orientation?: "horizontal" | "vertical" | "none";
  layout?: string;
  percent?: number | null;

  // Geometry
  rect: Rect;
  window_rect?: Rect;
  deco_rect?: Rect;

  // State
  focused?: boolean;
  visible?: boolean;
  urgent?: boolean;
  sticky?: boolean;

  // Window-specific
  app_id?: string; // Wayland app_id
  window_properties?: WindowProps; // X11 properties
  pid?: number;

  // Workspace-specific
  num?: number; // Workspace number
  current_workspace?: string; // For outputs

  // Container hierarchy
  nodes: Node[];
  floating_nodes: Node[];
  focus: number[]; // IDs of focused children
}

/**
 * Output (display/monitor)
 */
export interface Output extends Node {
  type: "output";
  active: boolean;
  current_workspace?: string;
  make?: string;
  model?: string;
  serial?: string;
  scale?: number;
  transform?: string;
  current_mode?: {
    width: number;
    height: number;
    refresh: number;
  };
}

/**
 * Complete Sway tree state snapshot
 */
export interface StateSnapshot {
  // Root node containing all outputs
  id: number;
  name: string;
  type: "root";
  orientation: "horizontal" | "vertical";
  rect: Rect;

  nodes: Output[];
  floating_nodes: Node[];
  focus: number[];

  // Metadata added by framework (not from swaymsg)
  capturedAt?: string; // ISO timestamp
  captureLatency?: number; // ms
}

/**
 * Helper type for workspace queries
 */
export interface Workspace extends Node {
  type: "workspace";
  num: number;
  name: string;
  focused: boolean;
  visible: boolean;
  output: string;
}

/**
 * Helper type for window queries
 */
export interface Window extends Node {
  app_id?: string;
  window_properties?: WindowProps;
  pid?: number;
  floating: boolean;
}
