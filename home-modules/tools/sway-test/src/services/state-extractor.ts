/**
 * State Extractor Service
 *
 * Extracts partial state information from Sway tree structures for use in partial state comparison mode.
 * Pure functional service with no side effects - all functions are testable with fixture data.
 *
 * Feature 068 Field Extraction Semantics (T043):
 * - Only fields present in expectedState are extracted from actualState
 * - If a field exists in expected (even with undefined value), it will be extracted
 * - If a field is missing from expected, it will NOT be extracted (ignored)
 * - This allows precise control over which fields are compared vs ignored
 *
 * Example:
 *   Expected: {workspaces: [{num: 1, focused: true}]}
 *   Extracted: {workspaces: [{num: 1, focused: true}]}  // visible, name, etc. NOT extracted
 */

import type { StateSnapshot } from "../models/state-snapshot.ts";
import type { ExpectedState } from "../models/test-case.ts";

/**
 * Extracted partial state matching ExpectedState structure
 */
export interface PartialExtractedState {
  focusedWorkspace?: number;
  windowCount?: number;
  workspaces?: Array<{
    num?: number;
    name?: string;
    focused?: boolean;
    visible?: boolean;
    windows?: Array<{
      app_id?: string;
      class?: string;
      title?: string;
      focused?: boolean;
      floating?: boolean;
    }>;
  }>;
}

/**
 * Comparison mode detection
 */
export type ComparisonMode = "exact" | "partial" | "assertions" | "empty";

/**
 * State Extractor Service
 */
export class StateExtractor {
  /**
   * Extract partial state based on expected state specification
   *
   * @param expected - Expected state specification (defines which fields to extract)
   * @param actual - Actual Sway tree state from `swaymsg -t get_tree`
   * @returns Partial extracted state with only requested fields populated
   */
  extract(expected: ExpectedState, actual: StateSnapshot): PartialExtractedState {
    const partial: PartialExtractedState = {};

    // Extract focusedWorkspace if requested
    if ("focusedWorkspace" in expected) {
      partial.focusedWorkspace = this.findFocusedWorkspace(actual);
    }

    // Extract windowCount if requested
    if ("windowCount" in expected) {
      partial.windowCount = this.countWindows(actual);
    }

    // Extract workspaces if requested
    if ("workspaces" in expected && expected.workspaces) {
      partial.workspaces = this.extractWorkspaces(actual, expected.workspaces);
    }

    return partial;
  }

  /**
   * Find focused workspace number in Sway tree
   *
   * @param tree - Sway tree state
   * @returns Focused workspace number, or undefined if no workspace focused
   */
  findFocusedWorkspace(tree: StateSnapshot): number | undefined {
    const workspaces = this.findWorkspaces(tree);
    const focused = workspaces.find((ws: SwayWorkspace) => ws.focused === true);
    return focused?.num;
  }

  /**
   * Count total windows in Sway tree
   *
   * Counts all windows (tiled and floating) across all workspaces.
   *
   * @param tree - Sway tree state
   * @returns Total window count
   */
  countWindows(tree: StateSnapshot): number {
    const windows = this.findWindows(tree);
    return windows.length;
  }

  /**
   * Extract workspace structures matching expected workspace specification
   *
   * @param tree - Sway tree state
   * @param expectedWorkspaces - Expected workspace structures (defines which fields to extract)
   * @returns Extracted workspace structures with only requested fields
   */
  extractWorkspaces(
    tree: StateSnapshot,
    expectedWorkspaces: ExpectedState["workspaces"],
  ): PartialExtractedState["workspaces"] {
    if (!expectedWorkspaces) {
      return undefined;
    }

    const actualWorkspaces = this.findWorkspaces(tree);
    const extracted: PartialExtractedState["workspaces"] = [];

    for (const expectedWs of expectedWorkspaces) {
      // Find matching workspace by number
      const actualWs = actualWorkspaces.find(
        (ws: SwayWorkspace) => ws.num === expectedWs.num,
      );

      if (!actualWs) {
        // Workspace doesn't exist - add placeholder with requested fields as undefined
        extracted.push({ num: expectedWs.num });
        continue;
      }

      // Extract only requested fields
      const extractedWs: {
        num?: number;
        name?: string;
        focused?: boolean;
        visible?: boolean;
        windows?: Array<{
          app_id?: string;
          class?: string;
          title?: string;
          focused?: boolean;
          floating?: boolean;
        }>;
      } = {};

      if ("num" in expectedWs) {
        extractedWs.num = actualWs.num;
      }

      if ("name" in expectedWs) {
        extractedWs.name = actualWs.name;
      }

      if ("focused" in expectedWs) {
        extractedWs.focused = actualWs.focused;
      }

      if ("visible" in expectedWs) {
        extractedWs.visible = actualWs.visible;
      }

      // Extract windows if requested
      if ("windows" in expectedWs && expectedWs.windows) {
        extractedWs.windows = this.extractWindows(actualWs, expectedWs.windows);
      }

      extracted.push(extractedWs);
    }

    return extracted;
  }

  /**
   * Extract window structures from workspace
   *
   * @param workspace - Sway workspace node
   * @param expectedWindows - Expected window structures
   * @returns Extracted window structures
   */
  private extractWindows(
    workspace: SwayWorkspace,
    expectedWindows: Array<{
      app_id?: string;
      class?: string;
      title?: string;
      focused?: boolean;
      floating?: boolean;
    }>,
  ): Array<{
    app_id?: string;
    class?: string;
    title?: string;
    focused?: boolean;
    floating?: boolean;
  }> {
    const actualWindows = this.findWindowsInNode(workspace);
    const extracted: Array<{
      app_id?: string;
      class?: string;
      title?: string;
      focused?: boolean;
      floating?: boolean;
    }> = [];

    for (const expectedWin of expectedWindows) {
      // Try to find matching window by app_id or class
      const actualWin = actualWindows.find((win: SwayWindow) => {
        if ("app_id" in expectedWin && expectedWin.app_id !== undefined) {
          return win.app_id === expectedWin.app_id;
        }
        if ("class" in expectedWin && expectedWin.class !== undefined) {
          return win.window_properties?.class === expectedWin.class;
        }
        return false;
      });

      if (!actualWin) {
        // Window doesn't exist - add placeholder
        extracted.push({});
        continue;
      }

      // Extract only requested fields
      const extractedWin: {
        app_id?: string;
        class?: string;
        title?: string;
        focused?: boolean;
        floating?: boolean;
      } = {};

      if ("app_id" in expectedWin) {
        extractedWin.app_id = actualWin.app_id ?? undefined;
      }

      if ("class" in expectedWin) {
        extractedWin.class = actualWin.window_properties?.class;
      }

      if ("title" in expectedWin) {
        extractedWin.title = actualWin.name;
      }

      if ("focused" in expectedWin) {
        extractedWin.focused = actualWin.focused;
      }

      if ("floating" in expectedWin) {
        extractedWin.floating = actualWin.type === "floating_con";
      }

      extracted.push(extractedWin);
    }

    return extracted;
  }

  /**
   * Find all workspaces in Sway tree
   *
   * @param tree - Sway tree state
   * @returns Array of workspace nodes
   */
  private findWorkspaces(tree: StateSnapshot): SwayWorkspace[] {
    const workspaces: SwayWorkspace[] = [];

    const traverse = (node: unknown) => {
      const n = node as SwayNode;
      if (n.type === "workspace" && "num" in n && (n as {num?: number}).num !== undefined) {
        workspaces.push(n as SwayWorkspace);
      }

      if (n.nodes) {
        for (const child of n.nodes) {
          traverse(child);
        }
      }

      if (n.floating_nodes) {
        for (const child of n.floating_nodes) {
          traverse(child);
        }
      }
    };

    traverse(tree as unknown as SwayNode);
    return workspaces;
  }

  /**
   * Find all windows in Sway tree
   *
   * @param tree - Sway tree state
   * @returns Array of window nodes
   */
  private findWindows(tree: StateSnapshot): SwayWindow[] {
    const windows: SwayWindow[] = [];

    const traverse = (node: unknown) => {
      const n = node as SwayNode;
      // Window nodes have app_id or window_properties
      if (
        (n.type === "con" || n.type === "floating_con") &&
        (n.app_id !== null || n.window_properties)
      ) {
        windows.push(n as SwayWindow);
      }

      if (n.nodes) {
        for (const child of n.nodes) {
          traverse(child);
        }
      }

      if (n.floating_nodes) {
        for (const child of n.floating_nodes) {
          traverse(child);
        }
      }
    };

    traverse(tree as unknown as SwayNode);
    return windows;
  }

  /**
   * Find windows within a specific node (workspace)
   *
   * @param node - Sway node to search
   * @returns Array of window nodes
   */
  private findWindowsInNode(node: SwayNode): SwayWindow[] {
    const windows: SwayWindow[] = [];

    const traverse = (n: unknown) => {
      const node = n as SwayNode;
      if (
        (node.type === "con" || node.type === "floating_con") &&
        (node.app_id !== null || node.window_properties)
      ) {
        windows.push(node as SwayWindow);
      }

      if (node.nodes) {
        for (const child of node.nodes) {
          traverse(child);
        }
      }

      if (node.floating_nodes) {
        for (const child of node.floating_nodes) {
          traverse(child);
        }
      }
    };

    traverse(node);
    return windows;
  }
}

/**
 * Detect comparison mode from expected state
 *
 * @param expected - Expected state specification
 * @returns Comparison mode to use
 *
 * Mode detection logic:
 * - If `tree` field present → "exact"
 * - If `assertions` field present → "assertions"
 * - If `focusedWorkspace`, `windowCount`, or `workspaces` present → "partial"
 * - If no fields present (empty object) → "empty" (match anything)
 */
export function detectComparisonMode(expected: ExpectedState): ComparisonMode {
  if (expected.tree !== undefined) return "exact";
  if (expected.assertions !== undefined && expected.assertions.length > 0) {
    return "assertions";
  }
  if (
    expected.focusedWorkspace !== undefined ||
    expected.windowCount !== undefined ||
    expected.workspaces !== undefined
  ) {
    return "partial";
  }
  return "empty";
}

// Internal type definitions for Sway tree structure
interface SwayNode {
  id: number;
  name: string;
  type: string;
  focused: boolean;
  nodes?: SwayNode[];
  floating_nodes?: SwayNode[];
  app_id?: string | null;
  window_properties?: {
    class?: string;
    title?: string;
  };
}

interface SwayWorkspace extends SwayNode {
  type: "workspace";
  num: number;
  visible: boolean;
}

interface SwayWindow extends SwayNode {
  type: "con" | "floating_con";
  app_id: string | null;
  window_properties?: {
    class?: string;
    title?: string;
  };
}
