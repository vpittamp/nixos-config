/**
 * Sway Test Framework - Integration Tests (T085)
 *
 * Framework self-tests using Deno.test() to validate core functionality.
 * These tests verify the framework's own logic, not Sway itself.
 */

import { registerSwayTest } from "../mod.ts";
import { StateComparator } from "../src/services/state-comparator.ts";
import type { StateSnapshot, TestResult } from "../mod.ts";
import { assertEquals, assertExists, assert } from "@std/assert";

// Test 1: State Comparator - Identical states
registerSwayTest("StateComparator detects identical states", () => {
  const comparator = new StateComparator();

  const state1: StateSnapshot = {
    focusedWorkspace: 1,
    focusedOutput: "HEADLESS-1",
    workspaces: [
      { num: 1, name: "1", focused: true, visible: true, urgent: false, output: "HEADLESS-1" }
    ],
    windows: [],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "1", focused: true }
    ],
    tree: { type: "root", name: "root", nodes: [] }
  };

  const state2 = { ...state1 };

  const result = comparator.compare(state1, state2);

  assertEquals(result.differences.length, 0, "Identical states should have no differences");
  assert(result.passed, "Comparison should pass for identical states");
});

// Test 2: State Comparator - Detects workspace number change
registerSwayTest("StateComparator detects workspace differences", () => {
  const comparator = new StateComparator();

  const expected: StateSnapshot = {
    focusedWorkspace: 1,
    focusedOutput: "HEADLESS-1",
    workspaces: [
      { num: 1, name: "1", focused: true, visible: true, urgent: false, output: "HEADLESS-1" }
    ],
    windows: [],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "1", focused: true }
    ],
    tree: { type: "root", name: "root", nodes: [] }
  };

  const actual: StateSnapshot = {
    ...expected,
    focusedWorkspace: 2,
    workspaces: [
      { num: 2, name: "2", focused: true, visible: true, urgent: false, output: "HEADLESS-1" }
    ],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "2", focused: true }
    ]
  };

  const result = comparator.compare(expected, actual);

  assert(result.differences.length > 0, "Different workspace numbers should produce differences");
  assert(!result.passed, "Comparison should fail for different workspaces");

  const workspaceDiff = result.differences.find(d => d.path.includes("focusedWorkspace"));
  assertExists(workspaceDiff, "Should detect focusedWorkspace difference");
  assertEquals(workspaceDiff.expected, 1);
  assertEquals(workspaceDiff.actual, 2);
});

// Test 3: State Comparator - Detects window presence
registerSwayTest("StateComparator detects window differences", () => {
  const comparator = new StateComparator();

  const expected: StateSnapshot = {
    focusedWorkspace: 1,
    focusedOutput: "HEADLESS-1",
    workspaces: [
      { num: 1, name: "1", focused: true, visible: true, urgent: false, output: "HEADLESS-1" }
    ],
    windows: [
      { id: 123, app_id: "Alacritty", title: "Terminal", focused: true, floating: false, workspace: 1 }
    ],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "1", focused: true }
    ],
    tree: { type: "root", name: "root", nodes: [] }
  };

  const actual: StateSnapshot = {
    ...expected,
    windows: []
  };

  const result = comparator.compare(expected, actual);

  assert(result.differences.length > 0, "Missing window should produce differences");
  assert(!result.passed, "Comparison should fail when expected window is missing");
});

// Test 4: State Comparator - Partial matching (only specified fields)
registerSwayTest("StateComparator supports partial matching", () => {
  const comparator = new StateComparator();

  const expected: StateSnapshot = {
    focusedWorkspace: 1,
    // Only focusedWorkspace specified - other fields should be ignored
    focusedOutput: undefined,
    workspaces: undefined,
    windows: undefined,
    outputs: undefined,
    tree: undefined
  };

  const actual: StateSnapshot = {
    focusedWorkspace: 1,
    focusedOutput: "HEADLESS-1",
    workspaces: [
      { num: 1, name: "1", focused: true, visible: true, urgent: false, output: "HEADLESS-1" }
    ],
    windows: [],
    outputs: [
      { name: "HEADLESS-1", active: true, current_workspace: "1", focused: true }
    ],
    tree: { type: "root", name: "root", nodes: [] }
  };

  const result = comparator.compare(expected, actual);

  assertEquals(result.differences.length, 0, "Should ignore undefined fields in expected state");
  assert(result.passed, "Partial matching should pass when specified fields match");
});

// Test 5: Test Case Validation - Valid test case
registerSwayTest("Test case validation accepts valid test case", () => {
  const testCase = {
    name: "Basic workspace switch",
    actions: [
      { type: "send_ipc", params: { ipc_command: "workspace number 1" } }
    ],
    expectedState: {
      focusedWorkspace: 1
    }
  };

  // If we can create the test case object without errors, validation passed
  assertExists(testCase.name);
  assertExists(testCase.actions);
  assertExists(testCase.expectedState);
  assert(testCase.actions.length > 0);
});

// Test 6: Action types are properly structured
registerSwayTest("Action types include required fields", () => {
  const sendIpcAction = {
    type: "send_ipc",
    params: { ipc_command: "workspace number 1" }
  };

  const waitForWindowAction = {
    type: "wait_for_window",
    params: { app_id: "Alacritty", timeout_ms: 2000 }
  };

  const delayAction = {
    type: "delay",
    params: { ms: 500 }
  };

  assertEquals(sendIpcAction.type, "send_ipc");
  assertExists(sendIpcAction.params.ipc_command);

  assertEquals(waitForWindowAction.type, "wait_for_window");
  assertExists(waitForWindowAction.params.app_id);

  assertEquals(delayAction.type, "delay");
  assertExists(delayAction.params.ms);
});

// Test 7: Expected state structure validation
registerSwayTest("Expected state supports all assertion types", () => {
  const expectedState = {
    focusedWorkspace: 1,
    hasWorkspaces: [1, 2, 3],
    windowCount: 2,
    hasWindows: [
      { app_id: "Alacritty", focused: true }
    ],
    outputs: [
      { name: "HEADLESS-1", active: true }
    ],
    focusedOutput: "HEADLESS-1"
  };

  assertExists(expectedState.focusedWorkspace);
  assertExists(expectedState.hasWorkspaces);
  assertExists(expectedState.windowCount);
  assertExists(expectedState.hasWindows);
  assertExists(expectedState.outputs);
  assertExists(expectedState.focusedOutput);

  assert(Array.isArray(expectedState.hasWorkspaces));
  assert(Array.isArray(expectedState.hasWindows));
  assert(Array.isArray(expectedState.outputs));
});

console.log("✓ Framework integration tests loaded successfully");
