/**
 * User Story 3: Reusable Test Helper Patterns
 *
 * High-level helper functions that encapsulate common test patterns:
 * - Execute command + sync + query state
 * - Reduces test boilerplate from 20+ lines to 3-5 lines
 * - Maintains same correctness as manual sync/query operations
 *
 * These helpers are designed for use in both TypeScript tests and JSON-based tests
 * (via use_helper action type).
 *
 * @file test-helpers.ts
 * @module test-helpers
 */

import type { SwayClient } from "./sway-client.ts";
import type { Node, StateSnapshot } from "../models/state-snapshot.ts";

/**
 * Represents a focused window node from the Sway tree
 */
export type FocusedNode = Node;

/**
 * Execute a command, sync, and return the focused window
 *
 * This helper eliminates boilerplate for focus testing:
 *
 * Before (manual):
 * ```typescript
 * await client.sendCommand("focus left");
 * await client.sync();
 * const tree = await client.getTree();
 * const focused = findFocused(tree);
 * assertEquals(focused?.app_id, "ghostty");
 * ```
 *
 * After (helper):
 * ```typescript
 * const focused = await focusAfter(client, "focus left");
 * assertEquals(focused?.app_id, "ghostty");
 * ```
 *
 * @param client - SwayClient instance
 * @param command - Sway IPC command to execute (e.g., "focus left", "focus parent")
 * @param timeout - Optional sync timeout in milliseconds (default: 5000)
 * @returns The currently focused window node, or null if no window is focused
 *
 * @example
 * ```typescript
 * const focused = await focusAfter(client, "focus left");
 * assertEquals(focused?.app_id, "ghostty");
 * ```
 */
export async function focusAfter(
  client: SwayClient,
  command: string,
  timeout = 5000,
): Promise<FocusedNode | null> {
  // Execute command
  await client.sendCommand(command);

  // Sync to ensure command completion
  const syncResult = await client.sync(timeout);
  if (!syncResult.success) {
    throw new Error(`Sync failed after command "${command}": ${JSON.stringify(syncResult)}`);
  }

  // Query tree and find focused node
  const tree = await client.getTree();
  return findFocused(tree);
}

/**
 * Execute a command, sync, and return the focused workspace number
 *
 * This helper eliminates boilerplate for workspace focus testing:
 *
 * Before (manual):
 * ```typescript
 * await client.sendCommand("workspace 7");
 * await client.sync();
 * const tree = await client.getTree();
 * const focusedWs = findFocusedWorkspace(tree);
 * assertEquals(focusedWs?.num, 7);
 * ```
 *
 * After (helper):
 * ```typescript
 * const workspace = await focusedWorkspaceAfter(client, "workspace 7");
 * assertEquals(workspace, 7);
 * ```
 *
 * @param client - SwayClient instance
 * @param command - Sway IPC command to execute (e.g., "workspace 7")
 * @param timeout - Optional sync timeout in milliseconds (default: 5000)
 * @returns The focused workspace number, or null if no workspace is focused
 *
 * @example
 * ```typescript
 * const workspace = await focusedWorkspaceAfter(client, "workspace 7");
 * assertEquals(workspace, 7);
 * ```
 */
export async function focusedWorkspaceAfter(
  client: SwayClient,
  command: string,
  timeout = 5000,
): Promise<number | null> {
  // Execute command
  await client.sendCommand(command);

  // Sync to ensure command completion
  const syncResult = await client.sync(timeout);
  if (!syncResult.success) {
    throw new Error(`Sync failed after command "${command}": ${JSON.stringify(syncResult)}`);
  }

  // Query tree and find focused workspace
  const tree = await client.getTree();
  const focusedWs = findFocusedWorkspace(tree);
  return focusedWs?.num ?? null;
}

/**
 * Execute a command, sync, and return the window count
 *
 * This helper eliminates boilerplate for window count verification:
 *
 * Before (manual):
 * ```typescript
 * await client.sendCommand("nop");
 * await client.sync();
 * const tree = await client.getTree();
 * const count = countWindows(tree, null);
 * assertEquals(count, 2);
 * ```
 *
 * After (helper):
 * ```typescript
 * const count = await windowCountAfter(client, "nop");
 * assertEquals(count, 2);
 * ```
 *
 * @param client - SwayClient instance
 * @param command - Sway IPC command to execute (e.g., "nop", "focus left")
 * @param workspace - Optional workspace number to count windows in (null = all workspaces)
 * @param timeout - Optional sync timeout in milliseconds (default: 5000)
 * @returns The number of windows (optionally filtered by workspace)
 *
 * @example
 * ```typescript
 * // Count all windows
 * const totalCount = await windowCountAfter(client, "nop");
 * assertEquals(totalCount, 2);
 *
 * // Count windows on workspace 5
 * const ws5Count = await windowCountAfter(client, "nop", 5);
 * assertEquals(ws5Count, 1);
 * ```
 */
export async function windowCountAfter(
  client: SwayClient,
  command: string,
  workspace: number | null = null,
  timeout = 5000,
): Promise<number> {
  // Execute command
  await client.sendCommand(command);

  // Sync to ensure command completion
  const syncResult = await client.sync(timeout);
  if (!syncResult.success) {
    throw new Error(`Sync failed after command "${command}": ${JSON.stringify(syncResult)}`);
  }

  // Query tree and count windows
  const tree = await client.getTree();
  return countWindows(tree, workspace);
}

// ============================================================================
// Internal Helper Functions (Tree Traversal)
// ============================================================================

/**
 * Find the focused window node in the Sway tree
 *
 * @param node - Root node of the Sway tree
 * @returns The focused window node, or null if none found
 */
function findFocused(node: StateSnapshot | Node): FocusedNode | null {
  // Check if this node is focused
  if (node.focused === true && node.type === "con") {
    return node as FocusedNode;
  }

  // Recursively search children
  if (node.nodes) {
    for (const child of node.nodes) {
      const result = findFocused(child);
      if (result) return result;
    }
  }

  // Search floating nodes
  if (node.floating_nodes) {
    for (const child of node.floating_nodes) {
      const result = findFocused(child);
      if (result) return result;
    }
  }

  return null;
}

/**
 * Find the focused workspace in the Sway tree
 *
 * @param node - Root node of the Sway tree
 * @returns The focused workspace node, or null if none found
 */
function findFocusedWorkspace(node: StateSnapshot | Node): { num: number } | null {
  // Check if this node is a focused workspace
  if (node.type === "workspace" && node.focused === true && node.num !== undefined) {
    return { num: node.num };
  }

  // Recursively search children
  if (node.nodes) {
    for (const child of node.nodes) {
      const result = findFocusedWorkspace(child);
      if (result) return result;
    }
  }

  return null;
}

/**
 * Count windows in the Sway tree (optionally filtered by workspace)
 *
 * @param node - Root node of the Sway tree
 * @param workspace - Optional workspace number to filter by (null = all workspaces)
 * @param currentWorkspace - Internal parameter for tracking current workspace during recursion
 * @returns The number of windows
 */
function countWindows(
  node: StateSnapshot | Node,
  workspace: number | null,
  currentWorkspace: number | null = null,
): number {
  let count = 0;

  // Update current workspace if this node is a workspace
  if (node.type === "workspace" && node.num !== undefined) {
    currentWorkspace = node.num;
  }

  // Count this node if it's a window (con type - containers are windows in Sway)
  if (node.type === "con") {
    // If workspace filter is set, only count windows on that workspace
    if (workspace === null || currentWorkspace === workspace) {
      count++;
    }
  }

  // Recursively count children
  if (node.nodes) {
    for (const child of node.nodes) {
      count += countWindows(child, workspace, currentWorkspace);
    }
  }

  // Count floating nodes
  if (node.floating_nodes) {
    for (const child of node.floating_nodes) {
      count += countWindows(child, workspace, currentWorkspace);
    }
  }

  return count;
}
