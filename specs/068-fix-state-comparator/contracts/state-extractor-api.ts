/**
 * State Extractor Service API Contract
 *
 * Extracts partial state information from Sway tree structures
 * for use in partial state comparison mode.
 *
 * This contract defines the interface for the StateExtractor service
 * that will be implemented in Feature 068.
 */

import type { StateSnapshot } from "../../../home-modules/tools/sway-test/src/models/state-snapshot.ts";
import type { ExpectedState } from "../../../home-modules/tools/sway-test/src/models/test-case.ts";

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
 * State Extractor Service
 *
 * Pure functional service for extracting partial state from Sway trees.
 * All functions are stateless and testable with fixture data.
 */
export interface IStateExtractor {
  /**
   * Extract partial state based on expected state specification
   *
   * @param expected - Expected state specification (defines which fields to extract)
   * @param actual - Actual Sway tree state from `swaymsg -t get_tree`
   * @returns Partial extracted state with only requested fields populated
   *
   * @example
   * ```typescript
   * const expected = { focusedWorkspace: 3, windowCount: 2 };
   * const actual = await swayClient.captureState();
   * const extracted = extractor.extract(expected, actual);
   * // extracted = { focusedWorkspace: 1, windowCount: 5 }
   * ```
   */
  extract(expected: ExpectedState, actual: StateSnapshot): PartialExtractedState;

  /**
   * Find focused workspace number in Sway tree
   *
   * @param tree - Sway tree state
   * @returns Focused workspace number, or undefined if no workspace focused
   *
   * @example
   * ```typescript
   * const focusedWs = findFocusedWorkspace(tree);
   * // 3 (workspace 3 is focused)
   * ```
   */
  findFocusedWorkspace(tree: StateSnapshot): number | undefined;

  /**
   * Count total windows in Sway tree
   *
   * Counts all windows (tiled and floating) across all workspaces.
   *
   * @param tree - Sway tree state
   * @returns Total window count
   *
   * @example
   * ```typescript
   * const count = countWindows(tree);
   * // 5 (5 windows open across all workspaces)
   * ```
   */
  countWindows(tree: StateSnapshot): number;

  /**
   * Extract workspace structures matching expected workspace specification
   *
   * @param tree - Sway tree state
   * @param expectedWorkspaces - Expected workspace structures (defines which fields to extract)
   * @returns Extracted workspace structures with only requested fields
   *
   * @example
   * ```typescript
   * const expected = [
   *   { num: 1, focused: true },
   *   { num: 3, windows: [{ app_id: "firefox" }] }
   * ];
   * const extracted = extractWorkspaces(tree, expected);
   * // [
   * //   { num: 1, focused: false },  // Workspace 1 exists but not focused
   * //   { num: 3, windows: [{ app_id: "firefox" }] }  // Workspace 3 has Firefox
   * // ]
   * ```
   */
  extractWorkspaces(
    tree: StateSnapshot,
    expectedWorkspaces: ExpectedState["workspaces"]
  ): PartialExtractedState["workspaces"];
}

/**
 * Comparison Mode Detection
 *
 * Determines which comparison mode to use based on ExpectedState fields present.
 */
export type ComparisonMode = "exact" | "partial" | "assertions" | "empty";

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
 *
 * @example
 * ```typescript
 * detectMode({ tree: {...} })  // "exact"
 * detectMode({ focusedWorkspace: 3 })  // "partial"
 * detectMode({ assertions: [...] })  // "assertions"
 * detectMode({})  // "empty"
 * ```
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

/**
 * Performance Characteristics
 *
 * | Function | Complexity | Typical Latency | Notes |
 * |----------|-----------|-----------------|-------|
 * | extract() | O(n) | <20ms | Single tree traversal, n = tree nodes |
 * | findFocusedWorkspace() | O(n) | <5ms | Early exit on first focused workspace |
 * | countWindows() | O(n) | <10ms | Full tree traversal counting windows |
 * | extractWorkspaces() | O(n*m) | <15ms | m = expected workspaces |
 * | detectComparisonMode() | O(1) | <1ms | Simple field presence check |
 *
 * Total partial comparison overhead: <20ms (well under <100ms target from SC-005)
 */

/**
 * Error Handling
 *
 * All functions are pure and do not throw errors. Instead:
 * - Invalid tree structure → returns undefined or empty array
 * - Missing expected fields → returns partial state with available fields only
 * - Type mismatches → returns undefined for that field
 *
 * Validation errors (invalid ExpectedState) should be caught at test load time,
 * not during state extraction.
 */

/**
 * Testing Strategy
 *
 * Unit tests (tests/unit/state_extractor_test.ts):
 * - Test each function with fixture Sway tree data
 * - Edge cases: empty tree, no workspaces, no windows, deeply nested
 * - Validation: undefined handling, null handling, missing properties
 *
 * Integration tests (tests/integration/state_comparison_test.ts):
 * - Test full extraction → comparison → diff flow
 * - Use real Sway tree structures from test environment
 * - Validate against existing test cases (test_firefox_workspace.json, etc.)
 */
