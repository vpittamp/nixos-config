/**
 * Path utility functions for expanding home directory paths
 */

/**
 * Expands ~ in paths to the user's home directory
 * @param path - Path that may contain ~
 * @returns Expanded absolute path
 */
export function expandPath(path: string): string {
  if (path.startsWith("~/")) {
    const home = Deno.env.get("HOME");
    if (!home) {
      throw new Error("HOME environment variable not set");
    }
    return path.replace("~", home);
  }
  return path;
}
