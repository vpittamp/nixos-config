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

      default:
        throw new Error(`Unknown action type: ${action.type}`);
    }
  }

  /**
   * Execute launch_app action (T033)
   * Launches application using Deno.Command with optional environment variables
   */
  private async executeLaunchApp(action: Action): Promise<void> {
    const { command, args = [], env = {} } = action.params;

    if (!command) {
      throw new Error("launch_app requires 'command' parameter");
    }

    // Build environment (inherit current + custom vars)
    const environment = {
      ...Deno.env.toObject(),
      ...env,
    };

    // Launch subprocess
    const cmd = new Deno.Command(command, {
      args,
      env: environment,
      stdout: "piped",
      stderr: "piped",
    });

    const child = cmd.spawn();

    // Don't wait for process to complete (detached application)
    // Just verify it launched successfully by checking if PID exists
    if (!child.pid) {
      await child.status; // Wait for status to verify failure
      const stderr = new TextDecoder().decode(
        (await child.stderr.getReader().read()).value,
      );
      throw new Error(`Failed to launch ${command}: ${stderr}`);
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
   * Execute wait_event action (T037)
   * Waits for specific Sway event with timeout
   */
  private async executeWaitEvent(action: Action): Promise<void> {
    const { event_type, timeout = TIMEOUTS.WAIT_EVENT_DEFAULT } = action.params;

    if (!event_type) {
      throw new Error("wait_event requires 'event_type' parameter");
    }

    // TODO: Implement event waiting using swaymsg -t subscribe
    // For now, just add a delay as placeholder
    // This will be enhanced when tree-monitor integration is complete
    await this.delay(Math.min(timeout, 1000));

    // Placeholder - actual implementation would subscribe to events
    console.warn(`wait_event for ${event_type} not fully implemented yet`);
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
   * Automatic synchronization after window-modifying actions (T055)
   * Performs I3_SYNC-style synchronization if autoSync is enabled
   */
  private async performAutoSync(timeout: number = TIMEOUTS.SYNC_DEFAULT): Promise<void> {
    if (!this.autoSync) {
      return; // Auto-sync disabled
    }

    try {
      // Send sync marker
      const markerId = await this.treeMonitorClient.sendSyncMarker();

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
}
