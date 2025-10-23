/**
 * Application Class Management Command
 * T034: Implement `i3pm app-classes` command
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { ApplicationClassSchema } from "../validation.ts";
import type { ApplicationClass } from "../models.ts";
import { z } from "zod";

interface AppClassesCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm app-classes - Application class management

USAGE:
  i3pm app-classes [OPTIONS]

OPTIONS:
  -h, --help        Show this help message

DESCRIPTION:
  Shows all configured application classes with their scoping information.
  Scoped applications are project-specific and hidden when switching projects.
  Global applications remain visible across all projects.

EXAMPLE:
  i3pm app-classes
`);
  Deno.exit(0);
}

/**
 * Format application class for display
 */
function formatApp(app: ApplicationClass, index: number): string {
  const icon = app.icon || "";
  const description = app.description ? ` - ${app.description}` : "";
  return `  ${index}. ${icon} ${app.display_name} (${app.class_name})${description}`;
}

export async function appClassesCommand(
  args: (string | number)[],
  options: AppClassesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  // Connect to daemon
  const client = new DaemonClient();

  try {
    await client.connect();

    if (options.verbose) {
      console.error("Connected to daemon");
    }

    // Fetch application classes
    const response = await client.request("get_app_classes");

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Parse response (expecting { scoped: [], global: [] })
    const result = response as {
      scoped: unknown[];
      global: unknown[];
    };

    // Validate with Zod
    const AppArraySchema = z.array(ApplicationClassSchema);
    const scopedApps = AppArraySchema.parse(result.scoped) as ApplicationClass[];
    const globalApps = AppArraySchema.parse(result.global) as ApplicationClass[];

    // Display application classes
    console.log("\n=== Application Classes ===\n");

    // Scoped applications
    console.log("🔸 Scoped Applications (project-specific):");
    console.log("─".repeat(80));

    if (scopedApps.length === 0) {
      console.log("  (none)");
    } else {
      for (let i = 0; i < scopedApps.length; i++) {
        console.log(formatApp(scopedApps[i], i + 1));
      }
    }

    console.log("");

    // Global applications
    console.log("🌐 Global Applications (always visible):");
    console.log("─".repeat(80));

    if (globalApps.length === 0) {
      console.log("  (none)");
    } else {
      for (let i = 0; i < globalApps.length; i++) {
        console.log(formatApp(globalApps[i], i + 1));
      }
    }

    console.log("");
    console.log(`Total: ${scopedApps.length} scoped, ${globalApps.length} global`);
    console.log("─".repeat(80));
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error("Error: Invalid daemon response format");
      if (options.debug) {
        console.error("Validation errors:", err.errors);
      }
      Deno.exit(1);
    } else if (err instanceof Error) {
      console.error(`Error: ${err.message}`);

      if (err.message.includes("Failed to connect")) {
        console.error("\nThe daemon is not running. Start it with:");
        console.error("  systemctl --user start i3-project-event-listener");
      }
    } else {
      console.error("Error:", err);
    }

    Deno.exit(1);
  } finally {
    await client.close();
  }
}
