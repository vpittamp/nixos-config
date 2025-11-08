/**
 * Environment Validator
 *
 * Read /proc/<pid>/environ and validate I3PM_* variables
 */

/**
 * Window environment variables
 */
export interface WindowEnvironment {
  // I3PM-specific variables
  I3PM_APP_NAME?: string;
  I3PM_APP_ID?: string;
  I3PM_TARGET_WORKSPACE?: string;
  I3PM_PROJECT_NAME?: string;
  I3PM_SCOPE?: string;

  // Generic environment variables
  [key: string]: string | undefined;
}

/**
 * Validation result
 */
export interface ValidationResult {
  valid: boolean;
  missing: string[];
  present: string[];
}

/**
 * Read environment variables from a process via /proc/<pid>/environ
 *
 * @param pid - Process ID to read environment from
 * @returns WindowEnvironment object with all environment variables
 * @throws Error if /proc/<pid>/environ doesn't exist or is not readable
 */
export async function readWindowEnvironment(pid: number): Promise<WindowEnvironment> {
  if (!Number.isInteger(pid) || pid <= 0) {
    throw new Error(`Invalid PID: ${pid} (must be positive integer)`);
  }

  const environPath = `/proc/${pid}/environ`;

  try {
    const content = await Deno.readTextFile(environPath);

    // Parse null-separated key=value pairs
    const env: WindowEnvironment = {};
    const pairs = content.split("\0");

    for (const pair of pairs) {
      if (!pair.trim()) continue;

      const [key, ...valueParts] = pair.split("=");
      if (key) {
        env[key] = valueParts.join("="); // Handle values with = in them
      }
    }

    // Debug log removed (logger instance not available in helper)

    return env;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(
        `Process ${pid} not found (no /proc/${pid}/environ). ` +
        `Process may have exited or PID is invalid.`
      );
    }

    if (error instanceof Deno.errors.PermissionDenied) {
      throw new Error(
        `Permission denied reading /proc/${pid}/environ. ` +
        `Ensure test framework has permission to read process environments.`
      );
    }

    throw new Error(`Failed to read environment for PID ${pid}: ${(error as Error).message}`);
  }
}

/**
 * Validate that required I3PM environment variables are present
 *
 * @param env - WindowEnvironment object from readWindowEnvironment()
 * @param required - Optional array of required variable names
 * @returns ValidationResult with validation status
 */
export function validateI3pmEnvironment(
  env: WindowEnvironment,
  required: string[] = ["I3PM_APP_NAME", "I3PM_APP_ID", "I3PM_TARGET_WORKSPACE"]
): ValidationResult {
  const missing: string[] = [];
  const present: string[] = [];

  for (const key of required) {
    if (env[key]) {
      present.push(key);
    } else {
      missing.push(key);
    }
  }

  return {
    valid: missing.length === 0,
    missing,
    present,
  };
}

/**
 * Error thrown when environment validation fails
 */
export class EnvironmentValidationError extends Error {
  constructor(
    public pid: number,
    public missingVariables: string[],
    public actualEnv: WindowEnvironment
  ) {
    super(
      `Environment validation failed for PID ${pid}\n` +
      `Missing variables: ${missingVariables.join(", ")}\n` +
      `I3PM variables present: ${
        Object.keys(actualEnv)
          .filter(k => k.startsWith("I3PM_"))
          .join(", ") || "none"
      }`
    );
    this.name = "EnvironmentValidationError";
  }
}
