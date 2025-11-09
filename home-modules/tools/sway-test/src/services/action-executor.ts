/**
 * Action Executor Service
 *
 * Executes test action sequences (launch_app, send_ipc, switch_workspace, etc.)
 * with proper error handling, timing control, and diagnostic capture.
 */

import type { Action, ActionSequence } from "../models/test-case.ts";
import { SwayClient } from "./sway-client.ts";
import { TreeMonitorClient } from "./tree-monitor-client.ts";
import { DebugRepl, type ReplContext } from "./debug-repl.ts";
import { StateComparator } from "./state-comparator.ts";
import type { StateSnapshot } from "../models/state-snapshot.ts";
import { TIMEOUTS } from "../constants.ts";
import { lookupApp } from "./app-registry-reader.ts";
import { expandPath } from "../helpers/path-utils.ts";
import { waitForEvent } from "./event-subscriber.ts";
import { readWindowEnvironment, validateI3pmEnvironment, EnvironmentValidationError } from "../helpers/environment-validator.ts";

/**
 * Action execution result
 */
export interface ActionResult {
  success: boolean;
  action: Action;
  duration: number; // ms
  error?: string;
  diagnostics?: {
    stdout?: string;
    stderr?: string;
    exitCode?: number;
  };
}

/**
 * Action executor options
 */
export interface ActionExecutorOptions {
  swayClient?: SwayClient;
  defaultTimeout?: number; // Default timeout for actions (ms)
  noColor?: boolean; // Disable colored output in REPL
  autoSync?: boolean; // Automatically sync after window-modifying actions (default: true)
  debugContext?: {
    // Context needed for debug_pause
    testName: string;
    expectedState: StateSnapshot;
  };
  fixtureState?: Record<string, unknown>; // State from fixtures (T061)
}

/**
 * Service for executing test action sequences
 */
export class ActionExecutor {
  private swayClient: SwayClient;
  private treeMonitorClient: TreeMonitorClient;
  private defaultTimeout: number;
  private debugRepl: DebugRepl;
  private comparator: StateComparator;
  private autoSync: boolean;
  private debugContext?: {
    testName: string;
    expectedState: StateSnapshot;
  };
  private fixtureState: Record<string, unknown>;
  private shouldRestart: boolean = false;

  constructor(options: ActionExecutorOptions = {}) {
    this.swayClient = options.swayClient || new SwayClient();
    this.treeMonitorClient = new TreeMonitorClient();
    this.defaultTimeout = options.defaultTimeout || TIMEOUTS.ACTION_DEFAULT;
    this.autoSync = options.autoSync !== undefined ? options.autoSync : true;
    this.debugRepl = new DebugRepl({ noColor: options.noColor });
    this.comparator = new StateComparator();
    this.debugContext = options.debugContext;
    this.fixtureState = options.fixtureState || {};
  }

  /**
   * Get fixture state (T061)
   */
  getFixtureState(): Record<string, unknown> {
    return this.fixtureState;
  }

  /**
   * Update fixture state (T061)
   */
  setFixtureState(state: Record<string, unknown>): void {
    this.fixtureState = state;
  }

  /**
   * Check if test should be restarted (set by debug_pause REPL)
   */
  shouldRestartTest(): boolean {
    return this.shouldRestart;
  }

  /**
   * Reset restart flag
   */
  resetRestartFlag(): void {
    this.shouldRestart = false;
  }

  /**
   * Execute a sequence of actions in order
   */
  async execute(sequence: ActionSequence): Promise<ActionResult[]> {
    const results: ActionResult[] = [];

    for (const action of sequence) {
      const startTime = performance.now();

      try {
        // Execute the action based on type
        await this.executeAction(action);

        // Handle post-action delay
        if (action.params.delay) {
          await this.delay(action.params.delay);
        }

        // Record successful result
        const duration = Math.round(performance.now() - startTime);
        results.push({
          success: true,
          action,
          duration,
        });
      } catch (error) {
        // Record failure
        const duration = Math.round(performance.now() - startTime);
        const err = error as Error;
        results.push({
          success: false,
          action,
          duration,
          error: err.message,
          diagnostics: {
            stderr: (error as { stderr?: string }).stderr,
            exitCode: (error as { code?: number }).code,
          },
        });

        // Stop execution on failure
        throw new Error(
          `Action ${action.type} failed: ${err.message}`,
        );
      }
    }

    return results;
  }

  /**
   * Execute a single action based on its type
   */
  private async executeAction(action: Action): Promise<void> {
    switch (action.type) {
      case "launch_app":
        await this.executeLaunchApp(action);
        break;

      case "send_ipc":
        await this.executeSendIpc(action);
        break;

      case "switch_workspace":
        await this.executeSwitchWorkspace(action);
        break;

      case "focus_window":
        await this.executeFocusWindow(action);
        break;

      case "wait_event":
        await this.executeWaitEvent(action);
        break;

      case "await_sync":
        await this.executeAwaitSync(action);
        break;

      case "debug_pause":
        await this.executeDebugPause(action);
        break;

      case "validate_workspace_assignment":
        await this.executeValidateWorkspaceAssignment(action);
        break;

      case "validate_environment":
        await this.executeValidateEnvironment(action);
        break;

      // Feature 069: Synchronization-Based Test Framework
      case "sync":
        await this.executeSync(action);
        break;

      case "launch_app_sync":
        await this.executeLaunchAppSync(action);
        break;

      case "send_ipc_sync":
        await this.executeSendIpcSync(action);
        break;

      default:
        throw new Error(`Unknown action type: ${action.type}`);
    }
  }

  /**
   * Execute launch_app action (T011-T013)
   * Launches application ALWAYS using app-launcher-wrapper.sh
   *
   * BREAKING CHANGE: app_name parameter required, direct command execution removed
   */
  private async executeLaunchApp(action: Action): Promise<void> {
    const { app_name, args = [], project, workspace } = action.params;

    if (!app_name) {
      throw new Error(
        "launch_app requires 'app_name' parameter (from application registry).\n" +
        "Direct command execution is no longer supported.\n" +
        "Add the app to ~/.config/i3/application-registry.json first."
      );
    }

    // Validate app exists in registry
    const app = await lookupApp(app_name);

    // Build wrapper script path
    const wrapperPath = expandPath("~/.local/bin/app-launcher-wrapper.sh");

    // Verify wrapper exists
    try {
      await Deno.stat(wrapperPath);
    } catch {
      throw new Error(
        `app-launcher-wrapper.sh not found at: ${wrapperPath}\n` +
        `Ensure wrapper script is installed.`
      );
    }

    // Build wrapper command arguments
    const wrapperArgs = [app_name];

    // Add additional arguments if provided
    if (args.length > 0) {
      wrapperArgs.push("--", ...args);
    }

    // Build environment variables for wrapper
    const environment: Record<string, string> = {
      ...Deno.env.toObject(),
    };

    // Inject project context if provided
    if (project) {
      environment.I3PM_PROJECT_NAME = project;
    }

    // Inject workspace override if provided
    if (workspace) {
      environment.I3PM_TARGET_WORKSPACE = workspace.toString();
    }

    // Launch via wrapper
    const cmd = new Deno.Command(wrapperPath, {
      args: wrapperArgs,
      env: environment,
      stdout: "piped",
      stderr: "piped",
    });

    const child = cmd.spawn();

    // Don't wait for process to complete (wrapper spawns detached app)
    // Just verify wrapper started successfully
    if (!child.pid) {
      await child.status; // Wait for status to verify failure
      const stderrReader = child.stderr.getReader();
      const stderrChunk = await stderrReader.read();
      const stderr = stderrChunk.value ? new TextDecoder().decode(stderrChunk.value) : "";
      throw new Error(`Failed to launch ${app_name} via wrapper: ${stderr}`);
    }

    // Give app time to initialize (small delay for window creation)
    await this.delay(TIMEOUTS.APP_LAUNCH_DELAY);

    // Automatic sync after launching app (T055)
    await this.performAutoSync();
  }

  /**
   * Execute send_ipc action (T034)
   * Sends IPC command to Sway via SwayClient
   */
  private async executeSendIpc(action: Action): Promise<void> {
    const { ipc_command } = action.params;

    if (!ipc_command) {
      throw new Error("send_ipc requires 'ipc_command' parameter");
    }

    // Send command via SwayClient
    await this.swayClient.sendCommand(ipc_command);

    // Check if command creates windows (T055)
    const createsWindow = this.isWindowCreatingCommand(ipc_command);
    if (createsWindow) {
      // Give small delay for window creation
      await this.delay(TIMEOUTS.IPC_WINDOW_DELAY);

      // Automatic sync after window-creating IPC command
      await this.performAutoSync();
    }
  }

  /**
   * Detect if IPC command creates windows (T055)
   * Commands that create windows: exec, for_window with exec, etc.
   */
  private isWindowCreatingCommand(command: string): boolean {
    const normalized = command.toLowerCase().trim();

    // Commands that create windows
    const windowCreators = [
      /^exec\s+/i, // exec command
      /\]\s*exec\s+/i, // [criteria] exec
      /for_window.*exec/i, // for_window with exec
    ];

    return windowCreators.some((pattern) => pattern.test(normalized));
  }

  /**
   * Execute switch_workspace action (T035)
   * Switches to specified workspace number or name
   */
  private async executeSwitchWorkspace(action: Action): Promise<void> {
    const { workspace } = action.params;

    if (workspace === undefined) {
      throw new Error("switch_workspace requires 'workspace' parameter");
    }

    // Send workspace switch command
    const cmd = typeof workspace === "number"
      ? `workspace number ${workspace}`
      : `workspace ${workspace}`;

    await this.swayClient.sendCommand(cmd);
  }

  /**
   * Execute focus_window action (T036)
   * Focuses window matching specified criteria
   */
  private async executeFocusWindow(action: Action): Promise<void> {
    const { window_criteria } = action.params;

    if (!window_criteria) {
      throw new Error("focus_window requires 'window_criteria' parameter");
    }

    // Build Sway criteria string
    const criteria: string[] = [];

    if (window_criteria.app_id) {
      criteria.push(`app_id="${window_criteria.app_id}"`);
    }
    if (window_criteria.class) {
      criteria.push(`class="${window_criteria.class}"`);
    }
    if (window_criteria.title) {
      criteria.push(`title="${window_criteria.title}"`);
    }

    if (criteria.length === 0) {
      throw new Error("focus_window requires at least one criterion");
    }

    // Send focus command with criteria
    const criteriaString = criteria.join(" ");
    await this.swayClient.sendCommand(`[${criteriaString}] focus`);
  }

  /**
   * Execute wait_event action (T021 - T024)
   * Waits for specific Sway event with timeout using event subscription
   *
   * BREAKING CHANGE: Properly implemented with event subscription (replaces 1s sleep placeholder)
   */
  private async executeWaitEvent(action: Action): Promise<void> {
    const {
      event_type,
      timeout = TIMEOUTS.WAIT_EVENT_DEFAULT,
      criteria,
    } = action.params;

    if (!event_type) {
      throw new Error("wait_event requires 'event_type' parameter");
    }

    // Validate event type
    const validTypes = ["window", "workspace", "binding", "shutdown", "tick"];
    if (!validTypes.includes(event_type)) {
      throw new Error(
        `Invalid event_type: ${event_type}. ` +
        `Valid types: ${validTypes.join(", ")}`
      );
    }

    // Wait for event using event subscriber
    try {
      await waitForEvent(
        event_type as "window" | "workspace" | "binding" | "shutdown" | "tick",
        criteria,
        timeout
      );
    } catch (error) {
      // Re-throw with additional context
      if (error.name === "WaitEventTimeoutError") {
        // Get current tree state for diagnostics
        const tree = await this.swayClient.getTree();
        throw new Error(
          `${error.message}\n\n` +
          `Last tree state captured at ${tree.capturedAt}\n` +
          `Use debug_pause action to inspect state interactively.`
        );
      }
      throw error;
    }
  }

  /**
   * Execute await_sync action (T054 - User Story 4 - Synchronization)
   * Waits for Sway event loop synchronization using SEND_TICK
   *
   * Implements I3_SYNC-style round-trip synchronization:
   * 1. Send unique marker via SEND_TICK
   * 2. Wait for matching TICK event
   * 3. Guarantees all previous IPC operations completed
   */
  private async executeAwaitSync(action: Action): Promise<void> {
    const timeout = action.params.timeout || TIMEOUTS.SYNC_DEFAULT;

    try {
      // Send sync marker via tree-monitor daemon
      const markerId = await this.treeMonitorClient.sendSyncMarker();

      // Wait for sync marker tick event with timeout
      const success = await this.treeMonitorClient.awaitSyncMarker(markerId, timeout);

      if (!success) {
        throw new Error(`Sync marker timeout after ${timeout}ms`);
      }

      // Sync completed successfully - all previous IPC operations finished
    } catch (error) {
      const err = error as Error;
      throw new Error(`await_sync failed: ${err.message}`);
    }
  }

  /**
   * Execute debug_pause action (T042)
   * Launches interactive REPL for test debugging
   */
  private async executeDebugPause(_action: Action): Promise<void> {
    if (!this.debugContext) {
      throw new Error(
        "debug_pause requires debugContext (testName and expectedState)",
      );
    }

    // Capture current actual state
    const actualState = await this.swayClient.captureState();

    // Compute current diff
    const diff = this.comparator.compare(
      this.debugContext.expectedState,
      actualState,
      "exact",
    );

    // Build REPL context
    const replContext: ReplContext = {
      testName: this.debugContext.testName,
      expectedState: this.debugContext.expectedState,
      actualState,
      diff,
    };

    // Start REPL
    const result = await this.debugRepl.start(replContext);

    // Handle REPL result
    if (result.shouldRestart) {
      this.shouldRestart = true;
      throw new Error("TEST_RESTART_REQUESTED"); // Special error to signal restart
    }

    // If continue, just return and let test proceed
  }

  /**
   * Execute validate_workspace_assignment action (T031)
   * Validates that app window appears on expected workspace
   */
  private async executeValidateWorkspaceAssignment(action: Action): Promise<void> {
    const { app_name, expected_workspace } = action.params;

    if (!app_name) {
      throw new Error("validate_workspace_assignment requires 'app_name' parameter");
    }

    if (expected_workspace === undefined) {
      throw new Error("validate_workspace_assignment requires 'expected_workspace' parameter");
    }

    // Find window with matching app_name (via I3PM_APP_NAME env var)
    // This is a simplified check - would need to enhance to read /proc/<pid>/environ
    // For now, check by app_id matching
    const foundWindow = await this.findWindowByAppId(app_name);

    if (!foundWindow) {
      throw new Error(
        `Window for app "${app_name}" not found in tree.\n` +
        `Expected workspace: ${expected_workspace}`
      );
    }

    if (foundWindow.workspace !== expected_workspace) {
      throw new Error(
        `Workspace assignment validation failed for "${app_name}":\n` +
        `  Expected: workspace ${expected_workspace}\n` +
        `  Actual: workspace ${foundWindow.workspace}`
      );
    }
  }

  /**
   * Execute validate_environment action (T032)
   * Validates that window has correct I3PM_* environment variables
   */
  private async executeValidateEnvironment(action: Action): Promise<void> {
    const { app_name, expected_vars = {} } = action.params;

    if (!app_name) {
      throw new Error("validate_environment requires 'app_name' parameter");
    }

    // Find window by app_id
    const foundWindow = await this.findWindowByAppId(app_name);

    if (!foundWindow) {
      throw new Error(`Window for app "${app_name}" not found in tree`);
    }

    if (!foundWindow.pid) {
      throw new Error(`Window for app "${app_name}" has no PID - cannot read environment`);
    }

    // Read environment variables from /proc/<pid>/environ
    const env = await readWindowEnvironment(foundWindow.pid);

    // Validate expected variables
    const missingVars: string[] = [];
    const mismatchVars: Array<{ key: string; expected: string; actual: string | undefined }> = [];

    for (const [key, expectedValue] of Object.entries(expected_vars)) {
      const actualValue = env[key];

      if (actualValue === undefined) {
        missingVars.push(key);
      } else if (expectedValue.includes("*")) {
        // Wildcard matching (e.g., "firefox-*" matches "firefox-global-123")
        const pattern = new RegExp("^" + expectedValue.replace(/\*/g, ".*") + "$");
        if (!pattern.test(actualValue)) {
          mismatchVars.push({ key, expected: expectedValue, actual: actualValue });
        }
      } else if (actualValue !== expectedValue) {
        mismatchVars.push({ key, expected: expectedValue, actual: actualValue });
      }
    }

    if (missingVars.length > 0 || mismatchVars.length > 0) {
      let errorMsg = `Environment validation failed for "${app_name}" (PID ${foundWindow.pid}):\n`;

      if (missingVars.length > 0) {
        errorMsg += `  Missing variables: ${missingVars.join(", ")}\n`;
      }

      if (mismatchVars.length > 0) {
        errorMsg += "  Mismatched variables:\n";
        for (const { key, expected, actual } of mismatchVars) {
          errorMsg += `    ${key}: expected "${expected}", got "${actual}"\n`;
        }
      }

      throw new EnvironmentValidationError(foundWindow.pid, missingVars, env);
    }
  }

  /**
   * Helper: Find window by app_id and extract workspace number (T033)
   *
   * Uses SwayClient.findWindow() to locate window in tree and extract workspace.
   * Walks up the tree hierarchy to find parent workspace container.
   */
  private async findWindowByAppId(appId: string): Promise<{ pid?: number; workspace?: number } | null> {
    // Use SwayClient helper to find window
    const windowNode = await this.swayClient.findWindow({ app_id: appId });

    if (!windowNode) {
      return null;
    }

    // Extract PID
    const pid = windowNode.pid;

    // Walk up tree to find workspace number
    // Note: In actual implementation, we'd need parent references or tree walking
    // For now, we can get full tree and search for workspace containing this window
    const tree = await this.swayClient.getTree();
    const workspace = this.findWorkspaceForWindow(tree, windowNode.id);

    return { pid, workspace };
  }

  /**
   * Helper: Find workspace number containing a window with given window ID
   */
  private findWorkspaceForWindow(tree: any, windowId: number): number | undefined {
    const findWorkspace = (node: any, currentWorkspace?: number): number | undefined => {
      // Track current workspace as we descend
      const workspaceNum = node.type === "workspace" && node.num !== undefined
        ? node.num
        : currentWorkspace;

      // Check if this is the window we're looking for
      if (node.id === windowId) {
        return workspaceNum;
      }

      // Search children
      if (node.nodes && Array.isArray(node.nodes)) {
        for (const child of node.nodes) {
          const found = findWorkspace(child, workspaceNum);
          if (found !== undefined) return found;
        }
      }

      // Search floating_nodes
      if (node.floating_nodes && Array.isArray(node.floating_nodes)) {
        for (const child of node.floating_nodes) {
          const found = findWorkspace(child, workspaceNum);
          if (found !== undefined) return found;
        }
      }

      return undefined;
    };

    return findWorkspace(tree);
  }

  /**
   * Automatic synchronization after window-modifying actions (T028 - User Story 3)
   * Performs I3_SYNC-style synchronization if autoSync is enabled
   *
   * Uses sendSyncMarkerSafe() for graceful degradation when daemon unavailable
   */
  private async performAutoSync(timeout: number = TIMEOUTS.SYNC_DEFAULT): Promise<void> {
    if (!this.autoSync) {
      return; // Auto-sync disabled
    }

    try {
      // Send sync marker with graceful fallback (T028)
      const markerId = await this.treeMonitorClient.sendSyncMarkerSafe();

      if (markerId === null) {
        // Method unavailable - fall back to timeout-based delay
        await this.delay(500);
        return;
      }

      // Wait for sync marker tick event
      const success = await this.treeMonitorClient.awaitSyncMarker(
        markerId,
        timeout,
      );

      if (!success) {
        // Log warning but don't fail the test
        console.warn(`Auto-sync timeout after ${timeout}ms`);
      }
    } catch (error) {
      // Log error but don't fail the test
      const err = error as Error;
      console.warn(`Auto-sync failed: ${err.message}`);
    }
  }

  /**
   * Delay helper for timing control (T038)
   */
  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Execute sync action (T035)
   * Feature 069: Synchronization-Based Test Framework
   *
   * Explicit synchronization point - guarantees all prior Sway IPC commands
   * have been processed by X11 before continuing.
   */
  private async executeSync(action: Action): Promise<void> {
    const { timeout = 5000, logLatency = false } = action.params;

    const result = await this.swayClient.sync(timeout);

    if (!result.success) {
      throw new Error(
        `Sync failed: ${result.error} (latency: ${result.latencyMs}ms)`,
      );
    }

    if (logLatency || result.latencyMs > 10) {
      console.log(
        `Sync completed in ${result.latencyMs}ms (marker: ${result.marker.marker})`,
      );
    }
  }

  /**
   * Execute launch_app_sync action (Phase 4: User Story 2)
   * Feature 069: Synchronization-Based Test Framework
   *
   * Launches application and automatically synchronizes before continuing.
   */
  private async executeLaunchAppSync(action: Action): Promise<void> {
    // Execute existing launch_app logic
    await this.executeLaunchApp(action);

    // Automatically sync
    await this.swayClient.sync(action.params.timeout);
  }

  /**
   * Execute send_ipc_sync action (Phase 4: User Story 2)
   * Feature 069: Synchronization-Based Test Framework
   *
   * Sends Sway IPC command and automatically synchronizes.
   */
  private async executeSendIpcSync(action: Action): Promise<void> {
    const { ipc_command, timeout = 5000 } = action.params;

    if (!ipc_command) {
      throw new Error("send_ipc_sync requires 'ipc_command' parameter");
    }

    // Send IPC command
    const result = await this.swayClient.sendCommand(ipc_command);
    if (!result.success) {
      throw new Error(`IPC command failed: ${result.error}`);
    }

    // Automatically sync
    await this.swayClient.sync(timeout);
  }
}
