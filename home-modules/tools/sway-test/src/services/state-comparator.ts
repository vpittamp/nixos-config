/**
 * State Comparator Service
 *
 * Compares expected vs actual Sway window tree states with exact and partial matching.
 */

import type { StateSnapshot } from "../models/state-snapshot.ts";
import type { StateDiff, DiffEntry } from "../models/test-result.ts";

/**
 * Comparison mode
 */
export type ComparisonMode = "exact" | "partial";

/**
 * JSONPath-style query for partial matching
 * Examples:
 * - "$.nodes[*].name" - all node names
 * - "$.nodes[0].focused" - first node's focused state
 * - "$.nodes[?(@.type=='workspace')].name" - workspace names
 */
export type JSONPathQuery = string;

/**
 * Partial match specification
 */
export interface PartialMatch {
  path: JSONPathQuery;
  expected: unknown;
}

/**
 * State Comparator for test framework
 */
export class StateComparator {
  /**
   * Compare two states (exact or partial matching)
   *
   * @param expected Expected state or partial match queries
   * @param actual Actual state from Sway
   * @param mode Comparison mode (exact or partial)
   * @returns StateDiff with matches flag and differences
   */
  compare(
    expected: StateSnapshot | PartialMatch[],
    actual: StateSnapshot,
    mode: ComparisonMode = "exact",
  ): StateDiff {
    if (mode === "exact") {
      return this.compareExact(expected as StateSnapshot, actual);
    } else {
      return this.comparePartial(expected as PartialMatch[], actual);
    }
  }

  /**
   * Exact matching - compare full tree structures
   */
  private compareExact(
    expected: StateSnapshot,
    actual: StateSnapshot,
  ): StateDiff {
    const differences: DiffEntry[] = [];

    // Recursively compare trees
    this.compareObjects(expected, actual, "$", differences);

    return {
      matches: differences.length === 0,
      differences,
      summary: this.summarizeDifferences(differences),
      mode: "exact", // Feature 068: Add mode tracking
    };
  }

  /**
   * Partial matching - compare specific fields via JSONPath queries
   */
  private comparePartial(
    queries: PartialMatch[],
    actual: StateSnapshot,
  ): StateDiff {
    const differences: DiffEntry[] = [];

    for (const query of queries) {
      const actualValue = this.evaluatePath(query.path, actual);

      if (!this.deepEqual(query.expected, actualValue)) {
        differences.push({
          path: query.path,
          type: "modified",
          expected: query.expected,
          actual: actualValue,
        });
      }
    }

    return {
      matches: differences.length === 0,
      differences,
      summary: this.summarizeDifferences(differences),
      mode: "partial", // Feature 068: Add mode tracking
    };
  }

  /**
   * Recursively compare two objects and collect differences
   *
   * Feature 068 Semantics (T043):
   * - undefined in expected = "don't check" (field is ignored, NOT compared)
   * - null in expected = must match null exactly (field IS compared)
   * - missing property in expected = field is ignored in actual (NOT compared)
   */
  private compareObjects(
    expected: unknown,
    actual: unknown,
    path: string,
    differences: DiffEntry[],
  ): void {
    // Feature 068: Treat undefined in expected as "don't check this field"
    // This allows partial state matching where only specified fields are verified.
    // Example: {focusedWorkspace: 1} checks ONLY focusedWorkspace, ignoring all other fields.
    if (expected === undefined) {
      return; // Skip comparison for undefined expected values
    }

    // Handle null
    if (expected === null) {
      if (actual !== expected) {
        differences.push({
          path,
          type: "modified",
          expected,
          actual,
        });
      }
      return;
    }

    // Handle primitives
    if (typeof expected !== "object") {
      if (expected !== actual) {
        differences.push({
          path,
          type: "modified",
          expected,
          actual,
        });
      }
      return;
    }

    // Handle arrays
    if (Array.isArray(expected)) {
      if (!Array.isArray(actual)) {
        differences.push({
          path,
          type: "modified",
          expected,
          actual,
        });
        return;
      }

      // Compare array lengths
      if (expected.length !== actual.length) {
        differences.push({
          path: `${path}.length`,
          type: "modified",
          expected: expected.length,
          actual: actual.length,
        });
      }

      // Compare array elements
      const maxLength = Math.max(expected.length, actual.length);
      for (let i = 0; i < maxLength; i++) {
        if (i >= expected.length) {
          differences.push({
            path: `${path}[${i}]`,
            type: "added",
            actual: actual[i],
          });
        } else if (i >= actual.length) {
          differences.push({
            path: `${path}[${i}]`,
            type: "removed",
            expected: expected[i],
          });
        } else {
          this.compareObjects(expected[i], actual[i], `${path}[${i}]`, differences);
        }
      }
      return;
    }

    // Handle objects
    if (typeof actual !== "object" || actual === null) {
      differences.push({
        path,
        type: "modified",
        expected,
        actual,
      });
      return;
    }

    // Get all unique keys from both objects
    const expectedObj = expected as Record<string, unknown>;
    const actualObj = actual as Record<string, unknown>;
    const allKeys = new Set([
      ...Object.keys(expectedObj),
      ...Object.keys(actualObj),
    ]);

    for (const key of allKeys) {
      const expectedValue = expectedObj[key];
      const actualValue = actualObj[key];
      const keyPath = `${path}.${key}`;

      if (!(key in expectedObj)) {
        differences.push({
          path: keyPath,
          type: "added",
          actual: actualValue,
        });
      } else if (!(key in actualObj)) {
        differences.push({
          path: keyPath,
          type: "removed",
          expected: expectedValue,
        });
      } else {
        this.compareObjects(expectedValue, actualValue, keyPath, differences);
      }
    }
  }

  /**
   * Evaluate JSONPath-style query on object
   * Simple implementation supporting basic patterns
   */
  private evaluatePath(path: string, obj: unknown): unknown {
    // Strip leading $. if present
    const cleanPath = path.replace(/^\$\.?/, "");

    if (!cleanPath) {
      return obj;
    }

    // Split on dots, but handle array brackets
    const parts = cleanPath.split(/\.(?![^\[]*\])/);

    let current: unknown = obj;

    for (const part of parts) {
      if (current === null || current === undefined) {
        return undefined;
      }

      // Handle array indexing like nodes[0]
      const arrayMatch = part.match(/^(\w+)\[(\d+)\]$/);
      if (arrayMatch) {
        const [, prop, index] = arrayMatch;
        current = (current as Record<string, unknown>)[prop];
        if (Array.isArray(current)) {
          current = current[parseInt(index, 10)];
        } else {
          return undefined;
        }
        continue;
      }

      // Handle wildcard array access like nodes[*]
      const wildcardMatch = part.match(/^(\w+)\[\*\]$/);
      if (wildcardMatch) {
        const [, prop] = wildcardMatch;
        current = (current as Record<string, unknown>)[prop];
        // Return array as-is for wildcard
        continue;
      }

      // Regular property access
      current = (current as Record<string, unknown>)[part];
    }

    return current;
  }

  /**
   * Deep equality check
   */
  private deepEqual(a: unknown, b: unknown): boolean {
    if (a === b) return true;

    if (a === null || b === null) return a === b;
    if (a === undefined || b === undefined) return a === b;

    if (typeof a !== typeof b) return false;

    if (typeof a !== "object") return a === b;

    if (Array.isArray(a) && Array.isArray(b)) {
      if (a.length !== b.length) return false;
      return a.every((val, i) => this.deepEqual(val, b[i]));
    }

    if (Array.isArray(a) || Array.isArray(b)) return false;

    const aObj = a as Record<string, unknown>;
    const bObj = b as Record<string, unknown>;

    const aKeys = Object.keys(aObj);
    const bKeys = Object.keys(bObj);

    if (aKeys.length !== bKeys.length) return false;

    return aKeys.every(key => this.deepEqual(aObj[key], bObj[key]));
  }

  /**
   * Summarize differences for reporting
   */
  private summarizeDifferences(differences: DiffEntry[]): {
    added: number;
    removed: number;
    modified: number;
  } {
    const summary = { added: 0, removed: 0, modified: 0 };

    for (const diff of differences) {
      summary[diff.type]++;
    }

    return summary;
  }
}
