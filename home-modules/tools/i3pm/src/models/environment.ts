/**
 * Process environment models
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Environment variables injected at application launch for project context
 * and deterministic window identification.
 */

export type EnvironmentScope = "scoped" | "global";

/**
 * I3PM_* environment variables injected by app-launcher-wrapper.sh
 * Read from /proc/<pid>/environ by daemon for window-to-project association
 */
export interface ProcessEnvironment {
  // Application instance identification
  I3PM_APP_ID: string; // Unique instance ID: "${app}-${project}-${pid}-${timestamp}"
  I3PM_APP_NAME: string; // Registry application name (e.g., "vscode")

  // Project context
  I3PM_PROJECT_NAME: string; // Project name (e.g., "nixos") or empty for global
  I3PM_PROJECT_DIR: string; // Absolute path to project directory or empty
  I3PM_PROJECT_DISPLAY_NAME: string; // Human-readable project name or empty
  I3PM_PROJECT_ICON?: string; // Optional project icon

  // Scope and state
  I3PM_SCOPE: EnvironmentScope; // "scoped" or "global"
  I3PM_ACTIVE: "true" | "false"; // Whether a project is active

  // Launch metadata
  I3PM_LAUNCH_TIME: string; // Unix timestamp (seconds since epoch)
  I3PM_LAUNCHER_PID: string; // PID of app-launcher-wrapper.sh
}

/**
 * Partial environment for global applications (no project)
 */
export interface GlobalEnvironment extends Partial<ProcessEnvironment> {
  I3PM_APP_ID: string;
  I3PM_APP_NAME: string;
  I3PM_SCOPE: "global";
  I3PM_ACTIVE: "false";
  I3PM_LAUNCH_TIME: string;
  I3PM_LAUNCHER_PID: string;
}

/**
 * Generate unique application instance ID
 *
 * Format: ${APP_NAME}-${PROJECT_NAME}-${PID}-${TIMESTAMP}
 * Example: "vscode-nixos-12345-1730000000"
 *
 * @param appName - Registry application name
 * @param projectName - Project name or null for global
 * @param pid - Process ID (optional, uses current process if not provided)
 * @returns Unique application instance identifier
 */
export function generateAppInstanceId(
  appName: string,
  projectName: string | null,
  pid?: number,
): string {
  const project = projectName || "global";
  const processId = pid || Deno.pid;
  const timestamp = Math.floor(Date.now() / 1000);
  return `${appName}-${project}-${processId}-${timestamp}`;
}

/**
 * Parse application instance ID into components
 *
 * @param instanceId - Application instance ID
 * @returns Parsed components or null if invalid format
 */
export function parseAppInstanceId(
  instanceId: string,
): { appName: string; projectName: string; pid: number; timestamp: number } | null {
  const parts = instanceId.split("-");
  if (parts.length !== 4) return null;

  const [appName, projectName, pidStr, timestampStr] = parts;
  const pid = parseInt(pidStr, 10);
  const timestamp = parseInt(timestampStr, 10);

  if (isNaN(pid) || isNaN(timestamp)) return null;

  return { appName, projectName, pid, timestamp };
}

/**
 * Type guard for ProcessEnvironment
 */
export function isProcessEnvironment(value: unknown): value is ProcessEnvironment {
  if (typeof value !== "object" || value === null) return false;
  const env = value as Record<string, unknown>;

  return (
    typeof env.I3PM_APP_ID === "string" &&
    typeof env.I3PM_APP_NAME === "string" &&
    typeof env.I3PM_PROJECT_NAME === "string" &&
    typeof env.I3PM_PROJECT_DIR === "string" &&
    typeof env.I3PM_SCOPE === "string" &&
    (env.I3PM_SCOPE === "scoped" || env.I3PM_SCOPE === "global") &&
    typeof env.I3PM_ACTIVE === "string" &&
    (env.I3PM_ACTIVE === "true" || env.I3PM_ACTIVE === "false") &&
    typeof env.I3PM_LAUNCH_TIME === "string" &&
    typeof env.I3PM_LAUNCHER_PID === "string"
  );
}
