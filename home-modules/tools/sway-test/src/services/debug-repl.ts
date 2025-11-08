/**
 * Debug REPL Service
 *
 * Interactive REPL for test debugging with commands:
 * - show_diff: Display current expected vs actual state diff
 * - show_tree: Display current Sway tree in readable format
 * - run_ipc: Execute manual IPC commands
 * - continue: Resume test execution
 * - restart: Restart test from beginning
 */

import type { StateSnapshot } from "../models/state-snapshot.ts";
import type { StateDiff } from "../models/test-result.ts";
import { StateComparator } from "../services/state-comparator.ts";
import { SwayClient } from "../services/sway-client.ts";
import { DiffRenderer } from "../ui/diff-renderer.ts";

/**
 * REPL command result
 */
export interface ReplCommandResult {
  shouldContinue: boolean; // Continue test execution
  shouldRestart: boolean; // Restart test from beginning
  error?: string;
}

/**
 * REPL context - state available during debug pause
 */
export interface ReplContext {
  expectedState: StateSnapshot;
  actualState: StateSnapshot;
  diff: StateDiff;
  testName: string;
  testFilePath?: string; // Optional: path to test definition file for hot-reload (T047)
}

/**
 * Interactive REPL for test debugging
 */
export class DebugRepl {
  private swayClient: SwayClient;
  private comparator: StateComparator;
  private diffRenderer: DiffRenderer;
  private context: ReplContext | null = null;
  private fileWatcher: Deno.FsWatcher | null = null;
  private testFileChanged: boolean = false;

  constructor(options: { noColor?: boolean } = {}) {
    this.swayClient = new SwayClient();
    this.comparator = new StateComparator();
    this.diffRenderer = new DiffRenderer(!options.noColor);
  }

  /**
   * Start interactive REPL session (T047, T048)
   */
  async start(context: ReplContext): Promise<ReplCommandResult> {
    this.context = context;

    console.log("\n=== Debug Pause ===");
    console.log(`Test: ${context.testName}`);

    // Setup file watcher if test file path provided (T047)
    if (context.testFilePath) {
      this.setupFileWatcher(context.testFilePath);
      console.log(`Watching: ${context.testFilePath}`);
    }

    console.log("\nAvailable commands:");
    console.log("  show_diff  - Display expected vs actual state diff");
    console.log("  show_tree  - Display current Sway tree");
    console.log("  run_ipc <command> - Execute IPC command");
    console.log("  continue   - Resume test execution");
    console.log("  restart    - Restart test from beginning");
    console.log("  help       - Show this help message");
    console.log("  exit/quit  - Exit REPL (same as continue)");
    console.log("");

    try {
      // REPL loop
      while (true) {
        // Check for test file changes (T048)
        if (this.testFileChanged) {
          console.log("\n🔄 Test file changed!");
          console.log("  [c] Continue with updated test");
          console.log("  [r] Restart test from beginning");
          console.log("  [i] Ignore changes and continue debugging");

          const choice = await this.readLine("Choice: ");

          if (choice.toLowerCase() === "c") {
            return { shouldContinue: true, shouldRestart: false };
          } else if (choice.toLowerCase() === "r") {
            return { shouldContinue: false, shouldRestart: true };
          } else {
            console.log("Ignoring changes, continuing debugging...");
            this.testFileChanged = false;
          }
          console.log("");
        }

        // Read input
        const input = await this.readLine("> ");

        if (!input || input.trim() === "") {
          continue;
        }

        // Parse and execute command
        const result = await this.executeCommand(input.trim());

        if (result.error) {
          console.error(`Error: ${result.error}`);
        }

        // Check if should exit REPL
        if (result.shouldContinue || result.shouldRestart) {
          return result;
        }
      }
    } finally {
      // Cleanup watcher
      this.stopFileWatcher();
    }
  }

  /**
   * Execute REPL command
   */
  private async executeCommand(input: string): Promise<ReplCommandResult> {
    const parts = input.split(/\s+/);
    const command = parts[0].toLowerCase();
    const args = parts.slice(1);

    switch (command) {
      case "show_diff":
        return await this.cmdShowDiff();

      case "show_tree":
        return await this.cmdShowTree();

      case "run_ipc":
        return await this.cmdRunIpc(args);

      case "continue":
      case "exit":
      case "quit":
        return { shouldContinue: true, shouldRestart: false };

      case "restart":
        return { shouldContinue: false, shouldRestart: true };

      case "help":
      case "?":
        return this.cmdHelp();

      default:
        return {
          shouldContinue: false,
          shouldRestart: false,
          error: `Unknown command: ${command}. Type 'help' for available commands.`,
        };
    }
  }

  /**
   * Command: show_diff
   * Display current expected vs actual state diff
   */
  private async cmdShowDiff(): Promise<ReplCommandResult> {
    if (!this.context) {
      return {
        shouldContinue: false,
        shouldRestart: false,
        error: "No context available",
      };
    }

    console.log("\n=== State Diff ===");
    console.log(this.diffRenderer.render(this.context.diff));
    console.log("");

    return { shouldContinue: false, shouldRestart: false };
  }

  /**
   * Command: show_tree
   * Display current Sway tree in readable format
   */
  private async cmdShowTree(): Promise<ReplCommandResult> {
    try {
      // Capture latest state
      const currentState = await this.swayClient.captureState();

      console.log("\n=== Current Sway Tree ===");
      console.log(JSON.stringify(currentState, null, 2));
      console.log("");

      return { shouldContinue: false, shouldRestart: false };
    } catch (error) {
      return {
        shouldContinue: false,
        shouldRestart: false,
        error: `Failed to capture state: ${(error as Error).message}`,
      };
    }
  }

  /**
   * Command: run_ipc <command>
   * Execute manual IPC command
   */
  private async cmdRunIpc(args: string[]): Promise<ReplCommandResult> {
    if (args.length === 0) {
      return {
        shouldContinue: false,
        shouldRestart: false,
        error: "Usage: run_ipc <command>",
      };
    }

    const ipcCommand = args.join(" ");

    try {
      console.log(`\nExecuting IPC command: ${ipcCommand}`);
      await this.swayClient.sendCommand(ipcCommand);

      // Re-capture state and recompute diff
      if (this.context) {
        const newActualState = await this.swayClient.captureState();
        const newDiff = this.comparator.compare(
          this.context.expectedState,
          newActualState,
          "exact",
        );

        // Update context
        this.context = {
          ...this.context,
          actualState: newActualState,
          diff: newDiff,
        };

        console.log("State updated. Use 'show_diff' to see changes.");
      }

      console.log("");

      return { shouldContinue: false, shouldRestart: false };
    } catch (error) {
      return {
        shouldContinue: false,
        shouldRestart: false,
        error: `IPC command failed: ${(error as Error).message}`,
      };
    }
  }

  /**
   * Command: help
   * Show help message
   */
  private cmdHelp(): ReplCommandResult {
    console.log("\nAvailable commands:");
    console.log("  show_diff          - Display expected vs actual state diff");
    console.log("  show_tree          - Display current Sway tree");
    console.log(
      "  run_ipc <command>  - Execute IPC command (e.g., 'run_ipc workspace 2')",
    );
    console.log("  continue           - Resume test execution");
    console.log("  restart            - Restart test from beginning");
    console.log("  help               - Show this help message");
    console.log("  exit/quit          - Exit REPL (same as continue)");
    console.log("");

    return { shouldContinue: false, shouldRestart: false };
  }

  /**
   * Read line from stdin with prompt
   */
  private async readLine(prompt: string): Promise<string> {
    // Write prompt to stdout
    await Deno.stdout.write(new TextEncoder().encode(prompt));

    // Read line from stdin
    const buf = new Uint8Array(1024);
    const n = await Deno.stdin.read(buf);

    if (n === null) {
      return ""; // EOF
    }

    return new TextDecoder().decode(buf.subarray(0, n)).trim();
  }

  /**
   * Setup file watcher for test definition (T047)
   */
  private setupFileWatcher(filePath: string): void {
    try {
      this.fileWatcher = Deno.watchFs(filePath);

      // Start watching in background
      (async () => {
        if (!this.fileWatcher) return;

        for await (const event of this.fileWatcher) {
          // Only react to modify events
          if (event.kind === "modify") {
            this.testFileChanged = true;
          }
        }
      })();
    } catch (error) {
      console.warn(`Failed to setup file watcher: ${(error as Error).message}`);
    }
  }

  /**
   * Stop file watcher
   */
  private stopFileWatcher(): void {
    if (this.fileWatcher) {
      try {
        this.fileWatcher.close();
        this.fileWatcher = null;
      } catch (_error) {
        // Ignore errors during cleanup
      }
    }
  }
}
