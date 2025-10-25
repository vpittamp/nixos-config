/**
 * Error Handling Utilities
 *
 * Provides user-friendly error messages for common failure scenarios.
 */

import { getSocketPath } from "./socket.ts";

/**
 * Format error for daemon unavailable
 */
export function formatDaemonUnavailableError(): string {
  const socketPath = getSocketPath();
  return (
    `Error: Failed to connect to daemon\n` +
    `\n` +
    `Socket path: ${socketPath}\n` +
    `\n` +
    `The daemon may not be running. Try:\n` +
    `  systemctl --user status i3-project-event-listener\n` +
    `  systemctl --user start i3-project-event-listener\n` +
    `\n` +
    `If the daemon is running, check socket permissions:\n` +
    `  ls -l ${socketPath}`
  );
}

/**
 * Format error for socket not found
 */
export function formatSocketNotFoundError(socketPath: string): string {
  return (
    `Error: Socket file not found\n` +
    `\n` +
    `Socket path: ${socketPath}\n` +
    `\n` +
    `The daemon socket does not exist. Ensure the daemon is running:\n` +
    `  systemctl --user start i3-project-event-listener\n` +
    `\n` +
    `If the problem persists, check the daemon logs:\n` +
    `  journalctl --user -u i3-project-event-listener -n 50`
  );
}

/**
 * Format error for permission denied
 */
export function formatPermissionDeniedError(socketPath: string): string {
  return (
    `Error: Permission denied\n` +
    `\n` +
    `Socket path: ${socketPath}\n` +
    `\n` +
    `You do not have permission to access the daemon socket.\n` +
    `Check socket permissions:\n` +
    `  ls -l ${socketPath}\n` +
    `\n` +
    `The socket should be owned by your user with permissions 0600 or 0700.`
  );
}

/**
 * Format error for connection timeout
 */
export function formatTimeoutError(method: string, timeoutMs: number): string {
  return (
    `Error: Request timeout\n` +
    `\n` +
    `Method: ${method}\n` +
    `Timeout: ${timeoutMs}ms\n` +
    `\n` +
    `The daemon did not respond within the timeout period.\n` +
    `The daemon may be overloaded or deadlocked. Try restarting:\n` +
    `  systemctl --user restart i3-project-event-listener`
  );
}

/**
 * Format error for connection refused
 */
export function formatConnectionRefusedError(socketPath: string): string {
  return (
    `Error: Connection refused\n` +
    `\n` +
    `Socket path: ${socketPath}\n` +
    `\n` +
    `The daemon is not accepting connections.\n` +
    `Check if the daemon is running:\n` +
    `  systemctl --user status i3-project-event-listener\n` +
    `\n` +
    `If the daemon is stopped, start it:\n` +
    `  systemctl --user start i3-project-event-listener`
  );
}

/**
 * Format error for project not found
 */
export function formatProjectNotFoundError(projectName: string): string {
  return (
    `Error: Project not found\n` +
    `\n` +
    `Project: ${projectName}\n` +
    `\n` +
    `The specified project does not exist.\n` +
    `List available projects:\n` +
    `  i3pm project list\n` +
    `\n` +
    `Create a new project:\n` +
    `  i3pm project create --name ${projectName} --dir /path/to/project`
  );
}

/**
 * Format error for invalid project name
 */
export function formatInvalidProjectNameError(projectName: string): string {
  return (
    `Error: Invalid project name\n` +
    `\n` +
    `Project: ${projectName}\n` +
    `\n` +
    `Project names must be lowercase alphanumeric with hyphens only.\n` +
    `Valid examples: nixos, my-project, project-123\n` +
    `Invalid examples: NixOS, my_project, project.name`
  );
}

/**
 * Format error for invalid directory path
 */
export function formatInvalidDirectoryError(path: string): string {
  return (
    `Error: Invalid directory path\n` +
    `\n` +
    `Path: ${path}\n` +
    `\n` +
    `Directory paths must be absolute (start with /).\n` +
    `Example: /home/user/projects/myproject`
  );
}

/**
 * Format error for directory not found
 */
export function formatDirectoryNotFoundError(path: string): string {
  return (
    `Warning: Directory not found\n` +
    `\n` +
    `Path: ${path}\n` +
    `\n` +
    `The project directory does not exist.\n` +
    `You can still create the project, but you should create the directory:\n` +
    `  mkdir -p ${path}`
  );
}

/**
 * Format error for directory not accessible
 */
export function formatDirectoryNotAccessibleError(path: string): string {
  return (
    `Warning: Directory not accessible\n` +
    `\n` +
    `Path: ${path}\n` +
    `\n` +
    `The project directory exists but is not accessible.\n` +
    `Check permissions:\n` +
    `  ls -ld ${path}\n` +
    `\n` +
    `You may need to adjust directory permissions.`
  );
}

/**
 * Parse daemon connection error and return user-friendly message
 */
export function parseDaemonConnectionError(err: Error): string {
  const message = err.message.toLowerCase();

  if (message.includes("not found") || message.includes("no such file")) {
    return formatSocketNotFoundError(getSocketPath());
  }

  if (message.includes("permission denied")) {
    return formatPermissionDeniedError(getSocketPath());
  }

  if (message.includes("connection refused")) {
    return formatConnectionRefusedError(getSocketPath());
  }

  if (message.includes("timeout")) {
    return formatTimeoutError("connect", 5000);
  }

  // Generic connection error
  return formatDaemonUnavailableError();
}
