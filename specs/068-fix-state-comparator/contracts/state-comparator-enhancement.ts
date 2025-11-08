/**
 * State Comparator Enhancement Contract
 *
 * Enhancements to the existing StateComparator class to support
 * partial state comparison with proper undefined handling.
 *
 * This contract defines the changes to the existing StateComparator
 * (src/services/state-comparator.ts) for Feature 068.
 */

import type { StateDiff, DiffEntry } from "../../../home-modules/tools/sway-test/src/models/test-result.ts";
import type { PartialExtractedState } from "./state-extractor-api.ts";

/**
 * Enhanced StateDiff with mode tracking
 *
 * Extension to existing StateDiff interface (backward compatible)
 */
export interface EnhancedStateDiff extends StateDiff {
  // Existing fields (unchanged):
  // matches: boolean;
  // differences: DiffEntry[];
  // summary: { added: number; removed: number; modified: number; }

  /**
   * Comparison mode used
   * Added in Feature 068
   */
  mode: "exact" | "partial" | "assertions" | "empty";

  /**
   * Fields that were compared (partial mode only)
   * Added in Feature 068
   */
  comparedFields?: string[];

  /**
   * Fields that were ignored in comparison (partial mode only)
   * Added in Feature 068
   */
  ignoredFields?: string[];
}

/**
 * Enhanced StateComparator Interface
 *
 * Extends existing StateComparator class with new methods for partial comparison.
 * Existing methods remain unchanged for backward compatibility.
 */
export interface IStateComparatorEnhanced {
  /**
   * Compare two states (ENHANCED - new mode parameter)
   *
   * @param expected - Expected state or partial match queries
   * @param actual - Actual state from Sway
   * @param mode - Comparison mode (exact, partial, assertions, empty)
   * @returns EnhancedStateDiff with matches flag, differences, and metadata
   *
   * Changes from existing implementation:
   * - Add "empty" mode support (always returns matches: true)
   * - Add metadata fields (mode, comparedFields, ignoredFields)
   * - Partial mode now accepts PartialExtractedState (same shape as expected)
   *
   * @example
   * ```typescript
   * // Exact mode (unchanged)
   * const diff = comparator.compare(expectedTree, actualTree, "exact");
   *
   * // Partial mode (NEW)
   * const extracted = extractor.extract(expected, actual);
   * const diff = comparator.compare(expected, extracted, "partial");
   *
   * // Empty mode (NEW)
   * const diff = comparator.compare({}, actual, "empty");
   * // Returns: { matches: true, differences: [], mode: "empty" }
   * ```
   */
  compare(
    expected: unknown,
    actual: unknown,
    mode: "exact" | "partial" | "assertions" | "empty"
  ): EnhancedStateDiff;

  /**
   * Compare objects with undefined-aware semantics
   *
   * CHANGED: Enhanced to treat undefined as "don't check this field"
   *
   * Comparison semantics (Feature 068):
   * - undefined in expected → field not checked (not added to differences)
   * - null in expected → must match null exactly
   * - missing property in expected → ignored in actual
   *
   * @param expected - Expected value (may contain undefined fields)
   * @param actual - Actual value
   * @param path - JSONPath to current field
   * @param differences - Array to collect differences
   *
   * @example
   * ```typescript
   * // Before Feature 068:
   * compareObjects({ foo: undefined }, { foo: 42 }, "$", diffs);
   * // diffs = [{ path: "$.foo", type: "modified", expected: undefined, actual: 42 }]
   *
   * // After Feature 068:
   * compareObjects({ foo: undefined }, { foo: 42 }, "$", diffs);
   * // diffs = []  (undefined = don't check)
   * ```
   */
  compareObjects(
    expected: unknown,
    actual: unknown,
    path: string,
    differences: DiffEntry[]
  ): void;
}

/**
 * Comparison Mode Behavior
 *
 * | Mode | Expected Type | Actual Type | Behavior |
 * |------|--------------|-------------|----------|
 * | exact | StateSnapshot (full tree) | StateSnapshot | Full recursive comparison (current behavior) |
 * | partial | PartialExtractedState | PartialExtractedState | Compare only specified fields, ignore undefined |
 * | assertions | { assertions: [...] } | StateSnapshot | Evaluate JSONPath queries (current behavior) |
 * | empty | {} (empty object) | StateSnapshot | Always match (NEW) |
 */

/**
 * Undefined Handling Semantics
 *
 * | Expected Field | Actual Field | Result | Reasoning |
 * |---------------|--------------|--------|-----------|
 * | `foo: undefined` | `foo: 42` | Match | undefined = don't check |
 * | `foo: undefined` | (missing) | Match | undefined = don't check |
 * | `foo: null` | `foo: null` | Match | Exact match |
 * | `foo: null` | `foo: 42` | Mismatch | Expected null, got 42 |
 * | `foo: null` | (missing) | Mismatch | Expected null, field missing |
 * | (missing) | `foo: 42` | Match | Missing = ignored |
 * | `foo: 42` | `foo: 42` | Match | Exact match |
 * | `foo: 42` | `foo: 99` | Mismatch | Different values |
 * | `foo: 42` | (missing) | Mismatch | Expected 42, field missing |
 */

/**
 * Implementation Notes
 *
 * Changes required to existing StateComparator class:
 *
 * 1. Update compare() method:
 *    - Add "empty" mode case → return { matches: true, differences: [], mode: "empty" }
 *    - Add mode, comparedFields, ignoredFields to return value
 *    - Track compared/ignored fields during comparison
 *
 * 2. Update compareObjects() method:
 *    - Before comparing a field, check if expected value is undefined
 *    - If undefined, skip field (don't add to differences)
 *    - Otherwise, proceed with existing comparison logic
 *
 * 3. Update compareExact() method:
 *    - Add mode: "exact" to return value
 *
 * 4. Update comparePartial() method:
 *    - Add mode: "partial" to return value
 *    - Track compared fields (keys in expected)
 *    - Track ignored fields (keys in actual not in expected)
 *
 * Backward compatibility:
 * - Existing compare() calls work unchanged (mode defaults to "exact")
 * - Existing StateDiff consumers ignore new fields (TypeScript duck typing)
 * - No breaking changes to public API
 */

/**
 * Testing Strategy
 *
 * Unit tests (tests/unit/state_comparator_test.ts):
 * - Test undefined handling in compareObjects()
 * - Test empty mode behavior
 * - Test partial mode with comparedFields/ignoredFields tracking
 * - Edge cases: nested undefined, arrays with undefined elements
 *
 * Integration tests (tests/integration/state_comparison_test.ts):
 * - Test full flow: extract → compare → diff
 * - Validate against real test cases (test_firefox_workspace.json)
 * - Ensure no regressions in exact mode
 * - Verify partial mode fixes the bug
 */

/**
 * Performance Impact
 *
 * | Change | Impact | Mitigation |
 * |--------|--------|-----------|
 * | Undefined check in compareObjects() | +O(1) per field | Negligible (<1ms total) |
 * | Field tracking (comparedFields/ignoredFields) | +O(n) memory | <1KB for typical test |
 * | Empty mode short-circuit | -O(n) time | Faster (0ms vs 50ms) |
 *
 * Net impact: Neutral to positive (empty mode is faster, partial mode same speed)
 * Target: <100ms total comparison time (maintained from SC-005)
 */
