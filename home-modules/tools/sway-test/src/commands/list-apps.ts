/**
 * List Apps Command
 * Feature 070: User Story 5 - Convenient CLI Access (T049, T051, T053, T055, T056, T058, T059)
 *
 * CLI command to list all applications from registry with filtering and formatting options.
 */

import { parseArgs } from "@std/cli/parse-args";
import { loadAppRegistry } from "../services/app-registry-reader.ts";
import { formatTable, formatCSV, type TableColumn } from "../ui/table-formatter.ts";
import type { AppDefinition, AppListEntry } from "../models/app-definition.ts";
import { StructuredError, ErrorType } from "../models/structured-error.ts";
import { expandPath } from "../utils/path-utils.ts";

/**
 * List apps command options
 */
export interface ListAppsOptions {
  /** Filter by app name (substring match) */
  filter?: string;

  /** Filter by workspace number */
  workspace?: number;

  /** Filter by monitor role (primary, secondary, tertiary) */
  monitor?: "primary" | "secondary" | "tertiary";

  /** Filter by scope (global, scoped) */
  scope?: "global" | "scoped";

  /** Output format (table, json, csv) */
  format?: "table" | "json" | "csv";

  /** Show verbose metadata (description, nix_package) */
  verbose?: boolean;

  /** Show help */
  help?: boolean;
}

/**
 * Transform AppDefinition to AppListEntry for table display
 */
function transformAppToListEntry(app: AppDefinition): AppListEntry {
  return {
    name: app.name,
    display_name: app.display_name || app.name,
    command: app.command,
    workspace: app.preferred_workspace ? String(app.preferred_workspace) : "none",
    monitor: app.preferred_monitor_role || "none",
    scope: app.scope,
  };
}

/**
 * Filter apps based on criteria
 */
function filterApps(
  apps: Map<string, AppDefinition>,
  options: ListAppsOptions
): AppDefinition[] {
  const filtered: AppDefinition[] = [];

  for (const app of apps.values()) {
    // Name filter (substring match, case-insensitive)
    if (options.filter) {
      const filterLower = options.filter.toLowerCase();
      const nameLower = app.name.toLowerCase();
      const displayLower = (app.display_name || app.name).toLowerCase();

      if (!nameLower.includes(filterLower) && !displayLower.includes(filterLower)) {
        continue;
      }
    }

    // Workspace filter
    if (options.workspace !== undefined) {
      if (app.preferred_workspace !== options.workspace) {
        continue;
      }
    }

    // Monitor role filter
    if (options.monitor) {
      if (app.preferred_monitor_role !== options.monitor) {
        continue;
      }
    }

    // Scope filter
    if (options.scope) {
      if (app.scope !== options.scope) {
        continue;
      }
    }

    filtered.push(app);
  }

  // Sort by name
  filtered.sort((a, b) => a.name.localeCompare(b.name));

  return filtered;
}

/**
 * Format apps as table
 */
function formatAppsTable(apps: AppDefinition[], verbose: boolean): string {
  const entries = apps.map(transformAppToListEntry);

  if (entries.length === 0) {
    return "No apps found matching criteria.";
  }

  const columns: TableColumn[] = [
    { header: "Name", key: "name", align: "left", minWidth: 10 },
    { header: "Display Name", key: "display_name", align: "left", minWidth: 15 },
    { header: "Command", key: "command", align: "left", maxWidth: 30 },
    { header: "Workspace", key: "workspace", align: "right", minWidth: 9 },
    { header: "Monitor", key: "monitor", align: "center", minWidth: 9 },
    { header: "Scope", key: "scope", align: "center", minWidth: 7 },
  ];

  return formatTable(entries, { columns, showHeader: true });
}

/**
 * Format apps as verbose table (includes description and nix_package)
 */
function formatAppsVerbose(apps: AppDefinition[]): string {
  if (apps.length === 0) {
    return "No apps found matching criteria.";
  }

  const lines: string[] = [];

  for (const app of apps) {
    lines.push(`\n${"=".repeat(60)}`);
    lines.push(`Name:        ${app.name}`);
    lines.push(`Display:     ${app.display_name || app.name}`);
    lines.push(`Command:     ${app.command}`);

    if (app.parameters && app.parameters.length > 0) {
      lines.push(`Parameters:  ${app.parameters.join(" ")}`);
    }

    if (app.expected_class) {
      lines.push(`Class:       ${app.expected_class}`);
    }

    lines.push(`Workspace:   ${app.preferred_workspace || "none"}`);
    lines.push(`Monitor:     ${app.preferred_monitor_role || "none"}`);
    lines.push(`Scope:       ${app.scope}`);

    if (app.floating) {
      lines.push(`Floating:    yes (${app.floating_size || "default"})`);
    }

    if (app.description) {
      lines.push(`Description: ${app.description}`);
    }

    if (app.nix_package) {
      lines.push(`Nix Package: ${app.nix_package}`);
    }

    if (app.icon) {
      lines.push(`Icon:        ${app.icon}`);
    }
  }

  lines.push(`\n${"=".repeat(60)}`);
  lines.push(`\nTotal: ${apps.length} app${apps.length === 1 ? "" : "s"}`);

  return lines.join("\n");
}

/**
 * Format apps as CSV
 */
function formatAppsCSV(apps: AppDefinition[], verbose: boolean): string {
  const entries = apps.map(transformAppToListEntry);

  if (entries.length === 0) {
    return "";
  }

  const columns = [
    { header: "name", key: "name" },
    { header: "display_name", key: "display_name" },
    { header: "command", key: "command" },
    { header: "workspace", key: "workspace" },
    { header: "monitor", key: "monitor" },
    { header: "scope", key: "scope" },
  ];

  return formatCSV(entries, columns);
}

/**
 * Show help text for list-apps command (T059)
 */
export function showListAppsHelp(): void {
  console.log(`
List Apps Command - Display applications from registry

USAGE:
  sway-test list-apps [OPTIONS]

OPTIONS:
  --filter <name>          Filter apps by name (substring match)
  --workspace <num>        Filter by workspace number
  --monitor <role>         Filter by monitor role (primary|secondary|tertiary)
  --scope <scope>          Filter by scope (global|scoped)
  --format <format>        Output format: table (default), json, csv
  --verbose                Show full metadata (description, nix_package)
  --help                   Show this help message

EXAMPLES:
  # List all apps
  sway-test list-apps

  # Filter by name
  sway-test list-apps --filter firefox

  # Filter by workspace
  sway-test list-apps --workspace 3

  # Filter by monitor role
  sway-test list-apps --monitor primary

  # Filter by scope
  sway-test list-apps --scope global

  # Show verbose output
  sway-test list-apps --verbose

  # Export to CSV
  sway-test list-apps --format csv > apps.csv

  # JSON output for scripting
  sway-test list-apps --format json | jq '.[] | select(.workspace == "3")'

FILTERS:
  Multiple filters can be combined:
  sway-test list-apps --filter code --scope scoped --workspace 2

REGISTRY:
  Apps are loaded from: ~/.config/i3/application-registry.json
  To add apps, edit: /etc/nixos/home-modules/desktop/app-registry-data.nix
  Then rebuild: sudo nixos-rebuild switch
`);
}

/**
 * Parse list-apps command arguments
 */
export function parseListAppsArgs(args: string[]): ListAppsOptions {
  const parsed = parseArgs(args, {
    string: ["filter", "monitor", "scope", "format"],
    boolean: ["verbose", "help"],
    alias: {
      f: "filter",
      w: "workspace",
      m: "monitor",
      s: "scope",
      v: "verbose",
      h: "help",
    },
  });

  const options: ListAppsOptions = {
    filter: parsed.filter,
    workspace: parsed.workspace ? Number(parsed.workspace) : undefined,
    monitor: parsed.monitor as "primary" | "secondary" | "tertiary" | undefined,
    scope: parsed.scope as "global" | "scoped" | undefined,
    format: (parsed.format as "table" | "json" | "csv") || "table",
    verbose: parsed.verbose,
    help: parsed.help,
  };

  // Validation
  if (options.format && !["table", "json", "csv"].includes(options.format)) {
    throw new StructuredError(
      ErrorType.MALFORMED_TEST,
      "List Apps Command",
      `Invalid format: ${options.format}`,
      [
        "Valid formats: table, json, csv",
        "Example: sway-test list-apps --format json",
      ],
      { provided_format: options.format }
    );
  }

  if (options.monitor && !["primary", "secondary", "tertiary"].includes(options.monitor)) {
    throw new StructuredError(
      ErrorType.MALFORMED_TEST,
      "List Apps Command",
      `Invalid monitor role: ${options.monitor}`,
      [
        "Valid roles: primary, secondary, tertiary",
        "Example: sway-test list-apps --monitor primary",
      ],
      { provided_monitor: options.monitor }
    );
  }

  if (options.scope && !["global", "scoped"].includes(options.scope)) {
    throw new StructuredError(
      ErrorType.MALFORMED_TEST,
      "List Apps Command",
      `Invalid scope: ${options.scope}`,
      [
        "Valid scopes: global, scoped",
        "Example: sway-test list-apps --scope global",
      ],
      { provided_scope: options.scope }
    );
  }

  return options;
}

/**
 * Execute list-apps command
 * Returns exit code (0 = success, 1 = error)
 */
export async function listAppsCommand(options: ListAppsOptions): Promise<number> {
  try {
    // T058: Add registry file missing error handling
    let registry: Map<string, AppDefinition>;

    try {
      registry = await loadAppRegistry();
    } catch (error) {
      if (error instanceof StructuredError && error.type === ErrorType.REGISTRY_ERROR) {
        // Re-throw with setup instructions
        throw new StructuredError(
          ErrorType.REGISTRY_ERROR,
          "List Apps Command",
          "Application registry not found or invalid",
          [
            "Ensure application registry is generated during NixOS rebuild",
            "Check file exists: ~/.config/i3/application-registry.json",
            "Verify app-registry.nix configuration in /etc/nixos/home-modules/desktop/",
            "Rebuild NixOS: sudo nixos-rebuild switch --flake .#<target>",
            "If registry exists, check JSON syntax: cat ~/.config/i3/application-registry.json | jq",
          ],
          {
            registry_path: expandPath("~/.config/i3/application-registry.json"),
            original_error: error.message,
          }
        );
      }
      throw error;
    }

    // Filter apps
    const filtered = filterApps(registry, options);

    // Format output
    if (options.format === "json") {
      console.log(JSON.stringify(filtered, null, 2));
    } else if (options.format === "csv") {
      const csv = formatAppsCSV(filtered, options.verbose || false);
      console.log(csv);
    } else {
      // Table format
      const table = options.verbose
        ? formatAppsVerbose(filtered)
        : formatAppsTable(filtered, options.verbose || false);
      console.log(table);
    }

    return 0;
  } catch (error) {
    console.error(`Error: ${error.message}`);
    if (error instanceof StructuredError) {
      console.error("\nRemediation:");
      for (const step of error.remediation) {
        console.error(`  - ${step}`);
      }
    }
    return 1;
  }
}
