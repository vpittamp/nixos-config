/**
 * Path Utilities
 *
 * Helper functions for path manipulation
 */

/**
 * Expand tilde (~) in path to home directory
 *
 * @param path - Path that may contain ~
 * @returns Expanded path
 */
export function expandPath(path: string): string {
  if (path.startsWith("~/")) {
    const home = Deno.env.get("HOME");
    if (!home) {
      throw new Error("HOME environment variable not set");
    }
    return path.replace(/^~/, home);
  }
  return path;
}
