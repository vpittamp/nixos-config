/**
 * Interactive Prompts API
 *
 * Provides interactive selection menus and prompts for CLI tools with
 * keyboard navigation, filtering, and accessibility features.
 *
 * @module interactive-prompts
 */

/** Selection menu item */
export interface MenuItem<T = string> {
  /** Internal value returned when selected */
  value: T;
  /** Display label shown to user */
  label: string;
  /** Optional description (shown in expanded mode) */
  description?: string;
  /** Whether item can be selected (default: true) */
  disabled?: boolean;
}

/** Options for single selection prompt */
export interface SelectOptions<T = string> {
  /** Prompt message/question */
  message: string;
  /** Available menu items */
  options: MenuItem<T>[];
  /** Initially selected value (optional) */
  default?: T;
  /** Maximum visible items before scrolling (default: 10) */
  pageSize?: number;
  /** Enable fuzzy search/filtering (default: true) */
  filter?: boolean;
}

/** Options for multiple selection prompt */
export interface MultiSelectOptions<T = string>
  extends Omit<SelectOptions<T>, "default"> {
  /** Initially selected values (optional) */
  default?: T[];
  /** Minimum number of selections required (default: 0) */
  min?: number;
  /** Maximum number of selections allowed (default: unlimited) */
  max?: number;
}

/**
 * Prompts user to select a single item from a list.
 *
 * Features:
 * - Arrow keys to navigate
 * - Type to filter/search
 * - Enter to confirm
 * - Esc to cancel
 *
 * @param {SelectOptions<T>} options - Selection prompt configuration
 * @returns {Promise<T>} Selected value
 * @throws {Error} If stdin is not a TTY or user cancels (Esc/Ctrl+C)
 *
 * @example
 * ```typescript
 * const project = await promptSelect({
 *   message: "Select project:",
 *   options: [
 *     { value: "nixos", label: "NixOS Configuration", description: "/etc/nixos" },
 *     { value: "stacks", label: "Stacks Project", description: "~/projects/stacks" },
 *   ],
 * });
 *
 * console.log(`Selected: ${project}`);
 * ```
 */
export function promptSelect<T = string>(
  options: SelectOptions<T>,
): Promise<T>;

/**
 * Prompts user to select multiple items from a list.
 *
 * Features:
 * - Arrow keys to navigate
 * - Space to toggle selection
 * - Type to filter/search
 * - Enter to confirm
 * - Esc to cancel
 * - All selections shown with checkmarks
 *
 * @param {MultiSelectOptions<T>} options - Multi-selection prompt configuration
 * @returns {Promise<T[]>} Array of selected values
 * @throws {Error} If stdin is not a TTY, user cancels, or selections don't meet min/max constraints
 *
 * @example
 * ```typescript
 * const features = await promptMultipleSelect({
 *   message: "Select features to enable:",
 *   options: [
 *     { value: "colors", label: "Color output" },
 *     { value: "unicode", label: "Unicode symbols" },
 *     { value: "progress", label: "Progress indicators" },
 *   ],
 *   min: 1, // Require at least one selection
 * });
 *
 * console.log(`Enabled: ${features.join(", ")}`);
 * ```
 */
export function promptMultipleSelect<T = string>(
  options: MultiSelectOptions<T>,
): Promise<T[]>;

/**
 * Prompts user for text input with optional validation.
 *
 * @param {object} options - Input prompt configuration
 * @param {string} options.message - Prompt message
 * @param {string} [options.default] - Default value if user presses Enter without typing
 * @param {function} [options.validate] - Validation function (return error message or null)
 * @returns {Promise<string>} User input
 * @throws {Error} If stdin is not a TTY or user cancels
 *
 * @example
 * ```typescript
 * const name = await promptInput({
 *   message: "Enter project name:",
 *   validate: (input) => {
 *     if (!input) return "Name cannot be empty";
 *     if (!/^[a-z0-9-]+$/.test(input)) return "Use only lowercase letters, numbers, and hyphens";
 *     return null; // Valid
 *   },
 * });
 * ```
 */
export function promptInput(options: {
  message: string;
  default?: string;
  validate?: (input: string) => string | null;
}): Promise<string>;

/**
 * Prompts user for confirmation (yes/no).
 *
 * @param {object} options - Confirmation prompt configuration
 * @param {string} options.message - Confirmation question
 * @param {boolean} [options.default] - Default value if user presses Enter (default: false)
 * @returns {Promise<boolean>} True if confirmed, false otherwise
 * @throws {Error} If stdin is not a TTY
 *
 * @example
 * ```typescript
 * const confirmed = await promptConfirm({
 *   message: "Delete all files?",
 *   default: false,
 * });
 *
 * if (confirmed) {
 *   // Proceed with deletion
 * }
 * ```
 */
export function promptConfirm(options: {
  message: string;
  default?: boolean;
}): Promise<boolean>;

/**
 * Prompts user for secret input (password/token) with hidden characters.
 *
 * @param {object} options - Secret prompt configuration
 * @param {string} options.message - Prompt message
 * @param {function} [options.validate] - Validation function
 * @returns {Promise<string>} User input (hidden during typing)
 * @throws {Error} If stdin is not a TTY or user cancels
 *
 * @example
 * ```typescript
 * const token = await promptSecret({
 *   message: "Enter API token:",
 *   validate: (input) => {
 *     if (input.length < 20) return "Token must be at least 20 characters";
 *     return null;
 *   },
 * });
 * ```
 */
export function promptSecret(options: {
  message: string;
  validate?: (input: string) => string | null;
}): Promise<string>;

/**
 * Checks if interactive prompts are supported in current environment.
 *
 * @returns {boolean} True if stdin/stdout are TTY and prompts can be used
 *
 * @example
 * ```typescript
 * if (!canPrompt()) {
 *   console.error("Error: Interactive prompts not supported in non-TTY environment");
 *   Deno.exit(1);
 * }
 * ```
 */
export function canPrompt(): boolean;
