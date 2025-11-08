/**
 * Test Case Model
 *
 * Defines the structure for test definitions, action sequences, and expected states.
 */

/**
 * Action types supported in test action sequences
 */
export type ActionType =
  | "launch_app"
  | "send_ipc"
  | "switch_workspace"
  | "focus_window"
  | "wait_event"
  | "debug_pause"
  | "await_sync"
  | "validate_workspace_assignment"
  | "validate_environment";

/**
 * Action parameters based on action type
 */
export interface ActionParams {
  // launch_app params (BREAKING CHANGE: app_name required, command deprecated)
  app_name?: string;       // REQUIRED: App name from registry
  command?: string;        // DEPRECATED: Use app_name instead
  args?: string[];
  env?: Record<string, string>;
  project?: string;        // Optional project context (sets I3PM_PROJECT_NAME)

  // send_ipc params
  ipc_command?: string;

  // switch_workspace and launch_app params
  workspace?: number | string; // Workspace number or name (sets I3PM_TARGET_WORKSPACE for launch_app)

  // focus_window params
  window_criteria?: {
    app_id?: string;
    class?: string;
    title?: string;
  };

  // wait_event params (enhanced with event criteria)
  event_type?: string;
  timeout?: number;
  criteria?: {
    app_id?: string;
    window_class?: string;
    change?: string;
    workspace?: number;
    name?: string;
    payload?: string;
  };

  // await_sync params
  marker?: string;

  // validate_workspace_assignment params
  expected_workspace?: number;

  // validate_environment params
  expected_vars?: Record<string, string>;

  // Common params
  sync?: boolean; // Auto-sync after action
  delay?: number; // Delay in ms before next action
}

/**
 * Single action in a test sequence
 */
export interface Action {
  type: ActionType;
  params: ActionParams;
}

/**
 * Ordered sequence of actions to execute during a test
 */
export type ActionSequence = Action[];

/**
 * Expected state definition - supports both exact and partial matching
 */
export interface ExpectedState {
  // Full tree structure (exact matching)
  tree?: unknown; // Matches swaymsg -t get_tree structure

  // Partial matching queries
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

  // Simple assertions
  windowCount?: number;
  focusedWorkspace?: number;

  // Custom assertions (JSONPath-style queries)
  assertions?: Array<{
    path: string; // e.g., "workspaces[0].num"
    expected: unknown;
    operator?: "equals" | "contains" | "matches" | "greaterThan" | "lessThan";
  }>;
}

/**
 * Complete test case definition
 */
export interface TestCase {
  // Metadata
  name: string;
  description?: string;
  tags?: string[];
  priority?: "P1" | "P2" | "P3";
  timeout?: number; // Per-test timeout in ms (default 30000)

  // Test definition
  setup?: ActionSequence; // Setup actions (run before test)
  actions: ActionSequence; // Main test actions
  teardown?: ActionSequence; // Cleanup actions (run after test)

  expectedState: ExpectedState;

  // Fixtures
  fixtures?: string[]; // Names of fixtures to load

  // Configuration
  config?: {
    swayConfig?: string; // Path to custom Sway config for isolation
    headless?: boolean; // Force headless mode
    skipSync?: boolean; // Disable auto-sync
  };
}

/**
 * Test suite - collection of related test cases
 */
export interface TestSuite {
  name: string;
  description?: string;
  tests: TestCase[];

  // Suite-level config
  config?: {
    defaultTimeout?: number;
    fixtures?: string[];
    headless?: boolean;
  };
}
