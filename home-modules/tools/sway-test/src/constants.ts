/**
 * Framework Constants and Configuration
 *
 * Centralized constants to avoid magic numbers and improve maintainability
 */

/**
 * Framework version (single source of truth)
 *
 * Version 1.1.0 includes Feature 070 improvements:
 * - Clear error diagnostics with structured errors
 * - Graceful cleanup commands for processes/windows
 * - First-class PWA support (launch_pwa_sync)
 * - Registry integration (app_name resolution)
 * - CLI discovery commands (list-apps, list-pwas)
 */
export const VERSION = "1.1.0";

/**
 * Default timeouts (milliseconds)
 */
export const TIMEOUTS = {
  /** Default test execution timeout */
  TEST_EXECUTION: 30000,

  /** Sway headless launch timeout */
  SWAY_HEADLESS_LAUNCH: 5000,

  /** Sway headless polling interval */
  SWAY_HEADLESS_POLL: 100,

  /** Default action timeout */
  ACTION_DEFAULT: 30000,

  /** Default sync timeout */
  SYNC_DEFAULT: 5000,

  /** Default wait_event timeout */
  WAIT_EVENT_DEFAULT: 5000,

  /** App launch initialization delay */
  APP_LAUNCH_DELAY: 100,

  /** IPC command window creation delay */
  IPC_WINDOW_DELAY: 100,

  /** Headless Sway startup delay */
  HEADLESS_SWAY_STARTUP: 500,
} as const;

/**
 * Progress reporting intervals (milliseconds)
 */
export const PROGRESS_INTERVALS = {
  /** CI mode progress output interval */
  CI_PROGRESS: 10000,
} as const;

/**
 * Exit codes
 */
export const EXIT_CODES = {
  /** All tests passed */
  SUCCESS: 0,

  /** One or more tests failed */
  FAILURE: 1,

  /** Configuration error */
  CONFIG_ERROR: 2,

  /** Sway connection error */
  SWAY_ERROR: 3,

  /** Test file parsing error */
  PARSE_ERROR: 4,

  /** Fixture setup error */
  FIXTURE_ERROR: 5,
} as const;

/**
 * Headless Sway configuration
 */
export const HEADLESS_CONFIG = {
  /** WLR backend for headless rendering */
  WLR_BACKENDS: "headless",

  /** Allow Sway to run without input devices */
  WLR_LIBINPUT_NO_DEVICES: "1",

  /** Default output resolution */
  OUTPUT_RESOLUTION: "1920x1080",

  /** Minimal Sway configuration template */
  MINIMAL_CONFIG: `# Minimal Sway config for headless CI testing
output * resolution 1920x1080

# Disable default keybindings that might interfere
set $mod Mod4
bindsym $mod+Return exec true
`,
} as const;

/**
 * Tree monitor configuration
 */
export const TREE_MONITOR = {
  /** Default number of events to query */
  DEFAULT_EVENT_COUNT: 10,
} as const;
