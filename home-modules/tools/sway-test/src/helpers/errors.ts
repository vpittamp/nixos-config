/**
 * Error Handling with Recovery Suggestions (T076)
 *
 * Provides comprehensive error messages with actionable recovery suggestions
 * for common failure scenarios in the Sway Test Framework.
 */

/**
 * Error recovery suggestion
 */
export interface ErrorRecovery {
  message: string;
  suggestions: string[];
  diagnostic?: string;
}

/**
 * Enhanced error class with recovery suggestions
 */
export class SwayTestError extends Error {
  public readonly recovery: ErrorRecovery;
  public readonly originalError?: Error;

  constructor(message: string, recovery: ErrorRecovery, originalError?: Error) {
    super(message);
    this.name = "SwayTestError";
    this.recovery = recovery;
    this.originalError = originalError;
  }

  /**
   * Format error with recovery suggestions for display
   */
  format(noColor: boolean = false): string {
    const red = noColor ? "" : "\x1b[31m";
    const yellow = noColor ? "" : "\x1b[33m";
    const cyan = noColor ? "" : "\x1b[36m";
    const reset = noColor ? "" : "\x1b[0m";

    let output = `${red}Error: ${this.message}${reset}\n`;

    if (this.recovery.diagnostic) {
      output += `\n${cyan}Diagnostic: ${this.recovery.diagnostic}${reset}\n`;
    }

    output += `\n${yellow}Recovery Suggestions:${reset}\n`;
    for (const suggestion of this.recovery.suggestions) {
      output += `  • ${suggestion}\n`;
    }

    if (this.originalError) {
      output += `\n${cyan}Original Error: ${this.originalError.message}${reset}\n`;
    }

    return output;
  }
}

/**
 * Error factory functions for common failure scenarios
 */
export const ErrorRecoveryFactory = {
  /**
   * Sway connection failure
   */
  swayConnection(): ErrorRecovery {
    return {
      message: "Failed to connect to Sway IPC",
      suggestions: [
        "Verify Sway is running: systemctl --user status sway",
        "Check SWAYSOCK environment variable: echo $SWAYSOCK",
        "Try running: swaymsg -t get_version",
        "Ensure you are running inside a Sway session",
        "For headless testing, use WLR_BACKENDS=headless sway -c minimal_config",
      ],
      diagnostic: "Cannot establish IPC connection to Sway window manager",
    };
  },

  /**
   * Tree monitor daemon not running
   */
  treeMonitorDaemon(): ErrorRecovery {
    return {
      message: "tree-monitor daemon not running or socket not available",
      suggestions: [
        "Check daemon status: systemctl --user status sway-tree-monitor",
        "Start daemon: systemctl --user start sway-tree-monitor",
        "Check socket: ls -la /run/user/$(id -u)/sway-tree-monitor.sock",
        "View daemon logs: journalctl --user -u sway-tree-monitor -f",
        "Test connection: echo '{}' | nc -U /run/user/$(id -u)/sway-tree-monitor.sock",
      ],
      diagnostic: "Cannot connect to tree-monitor daemon via Unix socket",
    };
  },

  /**
   * Test definition file parsing error
   */
  testFileParsing(filePath: string, parseError: string): ErrorRecovery {
    return {
      message: `Failed to parse test definition file: ${filePath}`,
      suggestions: [
        "Validate JSON syntax: jq . " + filePath,
        "Check for trailing commas, missing quotes, or unescaped characters",
        "Validate against schema: sway-test validate " + filePath,
        "Refer to examples in tests/sway-tests/ directory",
        "See documentation: home-modules/tools/sway-test/docs/test-format.md",
      ],
      diagnostic: parseError,
    };
  },

  /**
   * Schema validation error
   */
  schemaValidation(errors: string[]): ErrorRecovery {
    return {
      message: "Test definition does not match required schema",
      suggestions: [
        "Review validation errors below and fix schema violations",
        "Check required fields: name, description, setup, expected_state",
        "Verify action types: launch_app, send_ipc, switch_workspace, focus_window, wait_event, await_sync",
        "See valid example: tests/sway-tests/basic/test_window_launch.json",
        "Run validation only: sway-test validate <file>",
      ],
      diagnostic: errors.join("\n"),
    };
  },

  /**
   * Test timeout
   */
  testTimeout(testName: string, timeoutMs: number): ErrorRecovery {
    return {
      message: `Test "${testName}" exceeded timeout of ${timeoutMs}ms`,
      suggestions: [
        "Increase timeout in test definition: { \"timeout\": 60000 }",
        "Check if application launch is hanging (missing app binary?)",
        "Verify IPC commands complete: swaymsg -t send_tick -- test",
        "Check for blocking wait_event actions",
        "Add debug_pause action to inspect state when hanging",
        "Run with --verbose to see where test is stuck",
      ],
      diagnostic: "Test execution exceeded maximum allowed time",
    };
  },

  /**
   * Action execution failure
   */
  actionExecution(action: string, error: string): ErrorRecovery {
    const suggestions: string[] = [
      `Check action parameters for "${action}" are correct`,
    ];

    if (action === "launch_app") {
      suggestions.push(
        "Verify application binary exists: which <command>",
        "Check application is executable: ls -la $(which <command>)",
        "Test launch manually: <command> <args>",
        "Verify environment variables are set correctly",
      );
    } else if (action === "send_ipc") {
      suggestions.push(
        "Test IPC command manually: swaymsg <command>",
        "Check command syntax is valid for Sway",
        "For window-creating commands, add delay parameter",
        "Ensure command doesn't require user input",
      );
    } else if (action === "focus_window" || action === "switch_workspace") {
      suggestions.push(
        "Verify window/workspace exists before focusing",
        "Check window criteria matches actual window properties",
        "Use debug_pause to inspect actual vs expected state",
      );
    }

    suggestions.push("Add error handling with try/catch blocks in test definition");

    return {
      message: `Action "${action}" failed during execution`,
      suggestions,
      diagnostic: error,
    };
  },

  /**
   * State comparison mismatch
   */
  stateMismatch(differences: number): ErrorRecovery {
    return {
      message: `Expected state does not match actual state (${differences} differences)`,
      suggestions: [
        "Review diff output above to see specific mismatches",
        "Use partial matching: { \"comparison_mode\": \"partial\" }",
        "Add debug_pause action before assertion to inspect actual state",
        "Verify timing: add await_sync or delay before state capture",
        "Check if animations are interfering (disable with Sway config)",
        "Update expected state to match actual if behavior is correct",
      ],
      diagnostic: `State comparison found ${differences} mismatched fields`,
    };
  },

  /**
   * Fixture not found
   */
  fixtureNotFound(fixtureName: string): ErrorRecovery {
    return {
      message: `Fixture "${fixtureName}" not found`,
      suggestions: [
        "Check fixture name matches exported function name",
        "Verify fixture file exists: ls -la src/fixtures/" + fixtureName + ".ts",
        "Ensure fixture is exported in src/fixtures/mod.ts",
        "Review available fixtures: grep 'export function' src/fixtures/*.ts",
        "See fixture documentation: docs/fixtures.md",
      ],
      diagnostic: "Fixture function not found in fixture registry",
    };
  },

  /**
   * Headless Sway launch failure
   */
  headlessSway(error: string): ErrorRecovery {
    return {
      message: "Failed to launch headless Sway for testing",
      suggestions: [
        "Check WLR_BACKENDS=headless is supported: wlr-randr --help",
        "Verify WLR_LIBINPUT_NO_DEVICES=1 is set",
        "Test manual launch: WLR_BACKENDS=headless sway -c /tmp/test_sway_config",
        "Check Sway is installed: which sway && sway --version",
        "Ensure required dependencies: wlroots, wayland",
        "Try with minimal config (no complex window rules)",
      ],
      diagnostic: error,
    };
  },

  /**
   * Sync timeout
   */
  syncTimeout(timeoutMs: number): ErrorRecovery {
    return {
      message: `Synchronization timeout after ${timeoutMs}ms`,
      suggestions: [
        "Verify tree-monitor daemon is processing events",
        "Increase sync timeout: { \"params\": { \"timeout\": 10000 } }",
        "Check daemon event queue: tree-monitor-cli status",
        "Ensure Sway is not frozen (check CPU usage)",
        "Try manual sync: swaymsg -t send_tick -- test_marker",
        "Check daemon logs for errors",
      ],
      diagnostic: "SEND_TICK marker did not receive corresponding TICK event within timeout",
    };
  },

  /**
   * Missing required dependency
   */
  missingDependency(dependency: string): ErrorRecovery {
    return {
      message: `Required dependency "${dependency}" not found`,
      suggestions: [
        `Install ${dependency}: nix-shell -p ${dependency}`,
        `Check if ${dependency} is in PATH: which ${dependency}`,
        "Verify NixOS configuration includes required packages",
        "Rebuild system: sudo nixos-rebuild switch",
        "Check package availability: nix search nixpkgs ${dependency}",
      ],
      diagnostic: `Command "${dependency}" not found in PATH`,
    };
  },

  /**
   * Generic error with context
   */
  generic(message: string, context?: string): ErrorRecovery {
    return {
      message,
      suggestions: [
        "Run with --verbose flag for detailed logging",
        "Check framework logs for stack trace",
        "Verify test definition syntax",
        "Try running a known-good test to isolate the issue",
        "Report issue with full error log if problem persists",
      ],
      diagnostic: context,
    };
  },
};

/**
 * Wrap an error with recovery suggestions
 */
export function wrapError(
  error: Error,
  recovery: ErrorRecovery,
): SwayTestError {
  return new SwayTestError(
    recovery.message,
    recovery,
    error,
  );
}

/**
 * Create error from factory with original error context
 */
export function createError(
  factoryFn: () => ErrorRecovery,
  originalError?: Error,
): SwayTestError {
  const recovery = factoryFn();
  return new SwayTestError(
    recovery.message,
    recovery,
    originalError,
  );
}
