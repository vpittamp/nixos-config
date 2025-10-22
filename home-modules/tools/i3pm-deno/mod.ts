/**
 * i3pm Deno CLI - Public API Exports
 *
 * This file exports the public API for testing and programmatic usage.
 */

// Export types
export type * from "./src/models.ts";

// Export validation schemas
export * from "./src/validation.ts";

// Export client
export { createClient, DaemonClient } from "./src/client.ts";

// Export utilities
export * from "./src/utils/socket.ts";
export * from "./src/utils/errors.ts";
export * from "./src/utils/signals.ts";

// Export UI utilities
export * from "./src/ui/ansi.ts";

// Export commands (for testing)
export { projectCommand } from "./src/commands/project.ts";
export { windowsCommand } from "./src/commands/windows.ts";
export { daemonCommand } from "./src/commands/daemon.ts";
export { rulesCommand } from "./src/commands/rules.ts";
export { monitorCommand } from "./src/commands/monitor.ts";
export { appClassesCommand } from "./src/commands/app-classes.ts";
