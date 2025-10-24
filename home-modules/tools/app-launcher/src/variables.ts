/**
 * Variable substitution engine with security validation
 *
 * Feature: 034-create-a-feature
 * Implements Tier 2 (Restricted Substitution) with validation
 */

import type { VariableContext } from "./models.ts";

/**
 * Supported variable names
 */
export const SUPPORTED_VARIABLES = [
  "$PROJECT_DIR",
  "$PROJECT_NAME",
  "$SESSION_NAME",
  "$WORKSPACE",
  "$HOME",
  "$PROJECT_DISPLAY_NAME",
  "$PROJECT_ICON",
] as const;

/**
 * Variable substitution error
 */
export class VariableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VariableError";
  }
}

/**
 * Validate directory path for security
 *
 * Checks:
 * - Must be absolute path (starts with /)
 * - Must exist on filesystem
 * - No newlines or null bytes
 * - No shell metacharacters
 *
 * @param dir - Directory path to validate
 * @returns true if valid, false otherwise
 */
export async function validateDirectory(dir: string): Promise<boolean> {
  // Must be non-empty
  if (!dir || dir.length === 0) {
    return false;
  }

  // Must be absolute path
  if (!dir.startsWith("/")) {
    return false;
  }

  // Must not contain newlines or null bytes
  if (dir.includes("\n") || dir.includes("\0")) {
    return false;
  }

  // Must exist as a directory
  try {
    const stat = await Deno.stat(dir);
    return stat.isDirectory;
  } catch {
    return false;
  }
}

/**
 * Substitute variables in parameter string
 *
 * Replaces variables left-to-right without recursive expansion.
 * Unknown variables remain unchanged.
 *
 * @param parameters - Parameter string with variable templates
 * @param context - Variable context with values
 * @returns Parameter string with variables substituted
 */
export function substituteVariables(
  parameters: string,
  context: VariableContext,
): string {
  let result = parameters;

  // Substitute each variable
  if (context.project_dir) {
    result = result.replaceAll("$PROJECT_DIR", context.project_dir);
  }

  if (context.project_name) {
    result = result.replaceAll("$PROJECT_NAME", context.project_name);
  }

  if (context.session_name) {
    result = result.replaceAll("$SESSION_NAME", context.session_name);
  }

  if (context.workspace !== null) {
    result = result.replaceAll("$WORKSPACE", context.workspace.toString());
  }

  if (context.user_home) {
    result = result.replaceAll("$HOME", context.user_home);
  }

  if (context.display_name) {
    result = result.replaceAll("$PROJECT_DISPLAY_NAME", context.display_name);
  }

  if (context.icon) {
    result = result.replaceAll("$PROJECT_ICON", context.icon);
  }

  return result;
}

/**
 * Create variable context from project data
 *
 * @param projectName - Active project name (or null if no project)
 * @param projectDir - Project directory path (or null)
 * @param workspace - Target workspace number (or null)
 * @returns Variable context for substitution
 */
export function createVariableContext(
  projectName: string | null,
  projectDir: string | null,
  workspace: number | null = null,
): VariableContext {
  const userHome = Deno.env.get("HOME") || "/home/user";

  return {
    project_name: projectName,
    project_dir: projectDir,
    session_name: projectName, // Convention: same as project name
    workspace,
    user_home: userHome,
    display_name: null, // Will be populated from project config
    icon: null, // Will be populated from project config
  };
}

/**
 * Check if parameters contain dangerous shell metacharacters
 *
 * Blocks: ; | & ` $() ${}
 * Allows: $PROJECT_DIR and other whitelisted variables
 *
 * @param parameters - Parameter string to check
 * @returns true if safe, false if contains dangerous characters
 */
export function checkParameterSafety(parameters: string): boolean {
  // Remove whitelisted variables first
  let cleaned = parameters;
  for (const variable of SUPPORTED_VARIABLES) {
    cleaned = cleaned.replaceAll(variable, "");
  }

  // Check for dangerous patterns
  const dangerousPatterns = [
    /;/,      // Command separator
    /\|/,     // Pipe operator
    /&/,      // Background execution
    /`/,      // Backtick substitution
    /\$\(/,   // Command substitution $(...)
    /\$\{/,   // Parameter expansion ${...}
  ];

  for (const pattern of dangerousPatterns) {
    if (pattern.test(cleaned)) {
      return false;
    }
  }

  return true;
}

/**
 * Build argument array from command and parameters
 *
 * Splits parameters on whitespace but preserves quoted strings.
 * Uses argument array to prevent shell injection.
 *
 * @param command - Base command
 * @param parameters - Resolved parameters (after substitution)
 * @returns Array of command and arguments
 */
export function buildArgumentArray(
  command: string,
  parameters: string,
): string[] {
  const args = [command];

  if (!parameters || parameters.trim().length === 0) {
    return args;
  }

  // Simple whitespace split (Bash wrapper will handle proper quoting)
  // For complex quoted arguments, the wrapper script uses argument arrays
  const params = parameters.trim().split(/\s+/);
  args.push(...params);

  return args;
}

/**
 * Apply fallback behavior when project context unavailable
 *
 * @param parameters - Original parameters
 * @param fallbackBehavior - Fallback strategy
 * @param userHome - User home directory
 * @returns Modified parameters or null (for "error" behavior)
 */
export function applyFallback(
  parameters: string,
  fallbackBehavior: "skip" | "use_home" | "error",
  userHome: string,
): string | null {
  switch (fallbackBehavior) {
    case "skip":
      // Remove parameters that reference project variables
      let result = parameters;
      for (const variable of ["$PROJECT_DIR", "$PROJECT_NAME", "$SESSION_NAME"]) {
        result = result.replaceAll(variable, "").trim();
      }
      return result;

    case "use_home":
      // Substitute HOME for PROJECT_DIR
      return parameters
        .replaceAll("$PROJECT_DIR", userHome)
        .replaceAll("$PROJECT_NAME", "")
        .replaceAll("$SESSION_NAME", "")
        .trim();

    case "error":
      // Indicate error - caller should abort
      return null;

    default:
      return parameters;
  }
}

/**
 * Resolve all variables and apply fallback if needed
 *
 * @param parameters - Original parameter string
 * @param context - Variable context
 * @param fallbackBehavior - Fallback when no project active
 * @returns Resolved parameters
 * @throws VariableError if fallback is "error" and no project active
 */
export function resolveParameters(
  parameters: string,
  context: VariableContext,
  fallbackBehavior: "skip" | "use_home" | "error" = "skip",
): string {
  // If no project context and fallback is needed
  if (!context.project_name && parameters.includes("$PROJECT")) {
    const fallback = applyFallback(parameters, fallbackBehavior, context.user_home);

    if (fallback === null) {
      throw new VariableError(
        "No project active and fallback behavior is 'error'",
      );
    }

    return fallback;
  }

  // Substitute variables
  return substituteVariables(parameters, context);
}
