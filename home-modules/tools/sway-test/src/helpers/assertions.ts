/**
 * Assertion Helper Library (T062 - User Story 5)
 *
 * Common assertion functions for test case validation.
 */

import { SwayClient } from "../services/sway-client.ts";
import type { StateSnapshot } from "../models/state-snapshot.ts";

/**
 * Assertion result
 */
export interface AssertionResult {
  passed: boolean;
  message: string;
  expected?: unknown;
  actual?: unknown;
}

/**
 * Assert that a workspace is empty (no windows)
 */
export async function assertWorkspaceEmpty(
  workspace: number,
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  // Find the workspace
  const ws = state.workspaces.find((w) => w.num === workspace);

  if (!ws) {
    return {
      passed: false,
      message: `Workspace ${workspace} not found`,
      expected: "Workspace to exist",
      actual: "Workspace not found",
    };
  }

  // Check if workspace has any windows
  const hasWindows = ws.nodes && ws.nodes.length > 0;

  return {
    passed: !hasWindows,
    message: hasWindows
      ? `Workspace ${workspace} is not empty (${ws.nodes?.length} windows)`
      : `Workspace ${workspace} is empty`,
    expected: 0,
    actual: ws.nodes?.length || 0,
  };
}

/**
 * Assert that a window is floating
 */
export async function assertWindowFloating(
  criteria: { app_id?: string; class?: string; title?: string },
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  // Find the window matching criteria
  const window = findWindow(state, criteria);

  if (!window) {
    return {
      passed: false,
      message: `Window not found matching criteria: ${JSON.stringify(criteria)}`,
      expected: "Window to exist",
      actual: "Window not found",
    };
  }

  const isFloating = window.type === "floating_con";

  return {
    passed: isFloating,
    message: isFloating
      ? `Window is floating: ${window.name}`
      : `Window is not floating: ${window.name}`,
    expected: "floating",
    actual: window.type,
  };
}

/**
 * Assert window count on a workspace or globally
 */
export async function assertWindowCount(
  expected: number,
  workspace?: number,
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  let actual: number;

  if (workspace !== undefined) {
    // Count windows on specific workspace
    const ws = state.workspaces.find((w) => w.num === workspace);
    if (!ws) {
      return {
        passed: false,
        message: `Workspace ${workspace} not found`,
        expected: `Workspace ${workspace} to exist`,
        actual: "Workspace not found",
      };
    }
    actual = ws.nodes?.length || 0;
  } else {
    // Count all windows across all workspaces
    actual = state.workspaces.reduce(
      (count, ws) => count + (ws.nodes?.length || 0),
      0,
    );
  }

  return {
    passed: actual === expected,
    message: workspace !== undefined
      ? `Workspace ${workspace} has ${actual} window(s) (expected ${expected})`
      : `Total window count is ${actual} (expected ${expected})`,
    expected,
    actual,
  };
}

/**
 * Assert that a workspace is focused
 */
export async function assertWorkspaceFocused(
  workspace: number,
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  const ws = state.workspaces.find((w) => w.num === workspace);

  if (!ws) {
    return {
      passed: false,
      message: `Workspace ${workspace} not found`,
      expected: `Workspace ${workspace} to exist`,
      actual: "Workspace not found",
    };
  }

  const isFocused = ws.focused === true;

  return {
    passed: isFocused,
    message: isFocused
      ? `Workspace ${workspace} is focused`
      : `Workspace ${workspace} is not focused`,
    expected: true,
    actual: isFocused,
  };
}

/**
 * Assert that a window exists
 */
export async function assertWindowExists(
  criteria: { app_id?: string; class?: string; title?: string },
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  const window = findWindow(state, criteria);

  return {
    passed: window !== null,
    message: window
      ? `Window found: ${window.name}`
      : `Window not found matching criteria: ${JSON.stringify(criteria)}`,
    expected: "Window to exist",
    actual: window ? "Window exists" : "Window not found",
  };
}

/**
 * Assert workspace visible state
 */
export async function assertWorkspaceVisible(
  workspace: number,
  visible: boolean,
  swayClient?: SwayClient,
): Promise<AssertionResult> {
  const client = swayClient || new SwayClient();
  const state = await client.captureState();

  const ws = state.workspaces.find((w) => w.num === workspace);

  if (!ws) {
    return {
      passed: false,
      message: `Workspace ${workspace} not found`,
      expected: `Workspace ${workspace} to exist`,
      actual: "Workspace not found",
    };
  }

  const isVisible = ws.visible === true;

  return {
    passed: isVisible === visible,
    message: isVisible === visible
      ? `Workspace ${workspace} visibility is ${visible} as expected`
      : `Workspace ${workspace} visibility is ${isVisible} (expected ${visible})`,
    expected: visible,
    actual: isVisible,
  };
}

/**
 * Helper: Find window in state snapshot
 */
function findWindow(
  state: StateSnapshot,
  criteria: { app_id?: string; class?: string; title?: string },
  // deno-lint-ignore no-explicit-any
): any | null {
  for (const ws of state.workspaces) {
    if (!ws.nodes) continue;

    for (const node of ws.nodes) {
      // Check if node matches criteria
      if (
        (criteria.app_id && node.app_id === criteria.app_id) ||
        (criteria.class && (node as { window_properties?: { class?: string } }).window_properties?.class === criteria.class) ||
        (criteria.title && node.name?.includes(criteria.title))
      ) {
        return node;
      }

      // Recursively search children if node has them
      if (node.nodes && node.nodes.length > 0) {
        for (const child of node.nodes) {
          if (
            (criteria.app_id && child.app_id === criteria.app_id) ||
            (criteria.class && (child as { window_properties?: { class?: string } }).window_properties?.class === criteria.class) ||
            (criteria.title && child.name?.includes(criteria.title))
          ) {
            return child;
          }
        }
      }
    }
  }

  return null;
}
