# Data Model: Fix State Comparator Bug in Sway Test Framework

**Date**: 2025-11-08
**Phase**: 1 (Design & Contracts)

## Entity Overview

This feature enhances existing data models in the sway-test framework to fix state comparison bugs. The core entities are already defined in `src/models/` - this document describes the fixes and enhancements.

## Core Entities

### 1. ExpectedState (Existing - No Changes Required)

**Purpose**: Defines what state to expect after test actions execute

**Location**: `src/models/test-case.ts`

**Structure**:
```typescript
export interface ExpectedState {
  // Exact matching - full tree comparison
  tree?: unknown;  // Complete Sway tree structure from `swaymsg -t get_tree`

  // Partial matching - specific field validation
  workspaces?: Array<{
    num?: number;           // Workspace number (1-70)
    name?: string;          // Workspace name
    focused?: boolean;      // Is this workspace focused?
    visible?: boolean;      // Is this workspace visible?
    windows?: Array<{
      app_id?: string;      // Wayland app_id
      class?: string;       // X11 window class
      title?: string;       // Window title
      focused?: boolean;    // Is this window focused?
      floating?: boolean;   // Is window floating?
    }>;
  }>;

  // Simple assertions - most common use case
  windowCount?: number;     // Total number of windows
  focusedWorkspace?: number; // Number of focused workspace

  // Assertion-based matching - advanced queries
  assertions?: Array<{
    path: string;           // JSONPath query (e.g., "workspaces[0].num")
    expected: unknown;      // Expected value
    operator?: "equals" | "contains" | "matches" | "greaterThan" | "lessThan";
  }>;
}
```

**Validation Rules** (from spec.md FR-009):
- At least one field must be present (empty object = match anything)
- Undefined property values = "don't check this field"
- Null property values = "must be null"
- Missing properties = ignored in comparison

**State Transitions**: Immutable (test definition)

---

### 2. StateDiff (Existing - Enhancement Required)

**Purpose**: Represents the result of comparing expected vs actual state

**Location**: `src/models/test-result.ts`

**Current Structure**:
```typescript
export interface StateDiff {
  matches: boolean;           // Do states match?
  differences: DiffEntry[];   // List of differences found
  summary: {                  // Summary statistics
    added: number;
    removed: number;
    modified: number;
  };
}
```

**Enhancement Required** (for FR-006 clear diff output):
```typescript
export interface StateDiff {
  matches: boolean;
  differences: DiffEntry[];
  summary: {
    added: number;
    removed: number;
    modified: number;
  };

  // NEW: Comparison mode metadata
  mode: "exact" | "partial" | "assertions"; // How comparison was performed

  // NEW: Field tracking for partial mode
  comparedFields?: string[];   // Fields that were compared
  ignoredFields?: string[];    // Fields that were ignored
}
```

---

### 3. DiffEntry (Existing - No Changes Required)

**Purpose**: Represents a single difference between expected and actual state

**Location**: `src/models/test-result.ts`

**Structure**:
```typescript
export interface DiffEntry {
  path: string;              // JSONPath to the differing field (e.g., "$.workspaces[0].num")
  type: "added" | "removed" | "modified";
  expected?: unknown;        // Expected value (undefined for "added")
  actual?: unknown;          // Actual value (undefined for "removed")
}
```

**Example Entries**:
```typescript
// Property modified
{ path: "$.focusedWorkspace", type: "modified", expected: 1, actual: 3 }

// Property added (exists in actual but not expected)
{ path: "$.workspaces[2]", type: "added", actual: { num: 5, name: "5" } }

// Property removed (exists in expected but not actual)
{ path: "$.windows[0]", type: "removed", expected: { app_id: "firefox" } }
```

---

### 4. StateSnapshot (Existing - No Changes Required)

**Purpose**: Represents captured state from Sway IPC `get_tree` command

**Location**: `src/models/state-snapshot.ts`

**Type**: `type StateSnapshot = unknown;` (flexible to handle Sway tree structure)

**Actual Structure** (from Sway IPC):
```typescript
// Simplified representation - actual structure is more complex
interface SwayTreeNode {
  id: number;
  name: string;
  type: "root" | "output" | "workspace" | "con" | "floating_con";
  focused: boolean;
  nodes: SwayTreeNode[];
  floating_nodes: SwayTreeNode[];

  // Workspace-specific fields
  num?: number;
  visible?: boolean;

  // Window-specific fields
  app_id?: string | null;
  window_properties?: {
    class?: string;
    title?: string;
  };
  rect?: { x: number; y: number; width: number; height: number };
}
```

**Validation**: No validation required (comes from Sway, assumed valid)

---

### 5. PartialExtractedState (NEW - Internal Type)

**Purpose**: Internal representation of extracted fields from actual state for partial comparison

**Location**: `src/services/state-extractor.ts` (new file)

**Structure**:
```typescript
/**
 * Extracted partial state for comparison
 * Matches the shape of ExpectedState but contains only extracted fields
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
```

**Relationships**:
- Derived from `StateSnapshot` via extraction functions
- Compared against `ExpectedState` (matching fields only)
- Shape matches `ExpectedState` for seamless comparison

---

## Entity Relationships

```
TestCase
  └── expectedState: ExpectedState
        ├── tree? → StateComparator.compare() → StateDiff (exact mode)
        ├── focusedWorkspace? → StateExtractor.extract() → PartialExtractedState → StateDiff (partial mode)
        ├── windowCount? → StateExtractor.extract() → PartialExtractedState → StateDiff (partial mode)
        ├── workspaces? → StateExtractor.extract() → PartialExtractedState → StateDiff (partial mode)
        └── assertions? → StateComparator.compare() → StateDiff (assertion mode)

StateSnapshot (from SwayClient.captureState())
  └── Used as "actual" in comparison
```

## Data Flow

```
1. Test Execution (run.ts):
   TestCase → ActionExecutor → SwayClient.captureState() → StateSnapshot (actual)

2. Comparison Mode Detection (run.ts - FIX):
   ExpectedState → detectComparisonMode() → "exact" | "partial" | "assertions"

3a. Exact Mode:
   ExpectedState.tree + StateSnapshot → StateComparator.compare() → StateDiff

3b. Partial Mode (FIX):
   ExpectedState + StateSnapshot → StateExtractor.extract() → PartialExtractedState
   ExpectedState + PartialExtractedState → StateComparator.compare() → StateDiff

3c. Assertion Mode:
   ExpectedState.assertions + StateSnapshot → StateComparator.compare() → StateDiff

4. Result Reporting:
   StateDiff → DiffRenderer.render() → Terminal output
```

## Validation Rules Summary

| Entity | Validation | Error Handling |
|--------|-----------|----------------|
| ExpectedState | At least one field present | Fail test with "No expected state defined" |
| StateSnapshot | None (from Sway) | Fail test if Sway IPC errors |
| PartialExtractedState | Matches ExpectedState shape | Internal error if shape mismatch |
| StateDiff | None (result object) | N/A |

## State Comparison Semantics

| Expected | Actual | Match? | Reasoning |
|----------|--------|--------|-----------|
| `{ focusedWorkspace: 3 }` | Workspace 3 focused | ✅ Yes | Exact match on compared field |
| `{ focusedWorkspace: 3 }` | Workspace 1 focused | ❌ No | Mismatch on compared field |
| `{ focusedWorkspace: undefined }` | Any workspace | ✅ Yes | undefined = don't check |
| `{}` (empty) | Any state | ✅ Yes | Empty = match anything |
| `{ tree: {...} }` | Full tree | Depends | Exact comparison (current behavior) |

## Performance Characteristics

| Operation | Complexity | Typical Latency | Notes |
|-----------|-----------|-----------------|-------|
| Mode detection | O(1) | <1ms | Simple field presence check |
| Exact comparison | O(n) | <50ms | n = tree nodes (typically <100) |
| Partial extraction | O(n) | <20ms | Single tree traversal |
| Partial comparison | O(m) | <10ms | m = compared fields (typically <5) |
| Assertion evaluation | O(k*n) | <30ms | k = assertions, n = tree nodes |

**Target**: <100ms total comparison time (SC-005 success criteria)

## Edge Cases Documented

1. **Empty expected state**: Matches anything (validates action execution only)
2. **Undefined properties**: Treated as "don't check this field"
3. **Null properties**: Must match null exactly
4. **Missing properties**: Ignored in comparison (not treated as mismatch)
5. **Array length mismatch**: Reported as difference with clear message
6. **Nested object mismatch**: Shows full path to mismatched field
7. **Type mismatch**: Reported as modification with type info in diff
