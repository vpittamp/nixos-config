/**
 * List PWAs Command
 * Feature 070: User Story 5 - Convenient CLI Access (T050, T052, T054, T055, T056, T058, T060)
 *
 * CLI command to list all PWAs from registry with filtering and formatting options.
 */

import { parseArgs } from "@std/cli/parse-args";
import { loadPWARegistry } from "../services/app-registry-reader.ts";
import { formatTable, formatCSV, type TableColumn } from "../ui/table-formatter.ts";
import type { PWADefinition, PWAListEntry } from "../models/pwa-definition.ts";
import { StructuredError, ErrorType } from "../models/structured-error.ts";
import { expandPath } from "../utils/path-utils.ts";

/**
 * List PWAs command options
 */
export interface ListPWAsOptions {
  /** Filter by PWA name (substring match) */
  filter?: string;

  /** Filter by workspace number */
  workspace?: number;

  /** Filter by monitor role (primary, secondary, tertiary) */
  monitor?: "primary" | "secondary" | "tertiary";

  /** Filter by ULID identifier */
  ulid?: string;

  /** Output format (table, json, csv) */
  format?: "table" | "json" | "csv";

  /** Show verbose metadata (full URLs) */
  verbose?: boolean;

  /** Show help */
  help?: boolean;
}

/**
 * Transform PWADefinition to PWAListEntry for table display
 */
function transformPWAToListEntry(pwa: PWADefinition): PWAListEntry {
  return {
    name: pwa.name,
    url: pwa.url,
    ulid: pwa.ulid,
    workspace: pwa.preferred_workspace ? String(pwa.preferred_workspace) : "none",
    monitor: pwa.preferred_monitor_role || "none",
  };
}

/**
 * Filter PWAs based on criteria
 */
function filterPWAs(
  pwas: Map<string, PWADefinition>,
  options: ListPWAsOptions
): PWADefinition[] {
  const filtered: PWADefinition[] = [];

  for (const pwa of pwas.values()) {
    // Name filter (substring match, case-insensitive)
    if (options.filter) {
      const filterLower = options.filter.toLowerCase();
      const nameLower = pwa.name.toLowerCase();

      if (!nameLower.includes(filterLower)) {
        continue;
      }
    }

    // Workspace filter
    if (options.workspace !== undefined) {
      if (pwa.preferred_workspace !== options.workspace) {
        continue;
      }
    }

    // Monitor role filter
    if (options.monitor) {
      if (pwa.preferred_monitor_role !== options.monitor) {
        continue;
      }
    }

    // ULID filter (exact match)
    if (options.ulid) {
      if (pwa.ulid !== options.ulid) {
        continue;
      }
    }

    filtered.push(pwa);
  }

  // Sort by name
  filtered.sort((a, b) => a.name.localeCompare(b.name));

  return filtered;
}

/**
 * Format PWAs as table
 */
function formatPWAsTable(pwas: PWADefinition[], verbose: boolean): string {
  const entries = pwas.map(transformPWAToListEntry);

  if (entries.length === 0) {
    return "No PWAs found matching criteria.";
  }

  const columns: TableColumn[] = [
    { header: "Name", key: "name", align: "left", minWidth: 10 },
    { header: "URL", key: "url", align: "left", maxWidth: verbose ? undefined : 40 },
    { header: "ULID", key: "ulid", align: "left", minWidth: 26 },
    { header: "Workspace", key: "workspace", align: "right", minWidth: 9 },
    { header: "Monitor", key: "monitor", align: "center", minWidth: 9 },
  ];

  return formatTable(entries, { columns, showHeader: true });
}

/**
 * Format PWAs as verbose table (includes full URLs)
 */
function formatPWAsVerbose(pwas: PWADefinition[]): string {
  if (pwas.length === 0) {
    return "No PWAs found matching criteria.";
  }

  const lines: string[] = [];

  for (const pwa of pwas) {
    lines.push(`\n${"=".repeat(60)}`);
    lines.push(`Name:      ${pwa.name}`);
    lines.push(`URL:       ${pwa.url}`);
    lines.push(`ULID:      ${pwa.ulid}`);
    lines.push(`Workspace: ${pwa.preferred_workspace || "none"}`);
    lines.push(`Monitor:   ${pwa.preferred_monitor_role || "none"}`);
  }

  lines.push(`\n${"=".repeat(60)}`);
  lines.push(`\nTotal: ${pwas.length} PWA${pwas.length === 1 ? "" : "s"}`);

  return lines.join("\n");
}

/**
 * Format PWAs as CSV
 */
function formatPWAsCSV(pwas: PWADefinition[], verbose: boolean): string {
  const entries = pwas.map(transformPWAToListEntry);

  if (entries.length === 0) {
    return "";
  }

  const columns = [
    { header: "name", key: "name" },
    { header: "url", key: "url" },
    { header: "ulid", key: "ulid" },
    { header: "workspace", key: "workspace" },
    { header: "monitor", key: "monitor" },
  ];

  return formatCSV(entries, columns);
}

/**
 * Show help text for list-pwas command (T060)
 */
export function showListPWAsHelp(): void {
  console.log(`
List PWAs Command - Display Progressive Web Apps from registry

USAGE:
  sway-test list-pwas [OPTIONS]

OPTIONS:
  --filter <name>          Filter PWAs by name (substring match)
  --workspace <num>        Filter by workspace number
  --monitor <role>         Filter by monitor role (primary|secondary|tertiary)
  --ulid <ulid>            Filter by ULID identifier (exact match)
  --format <format>        Output format: table (default), json, csv
  --verbose                Show full metadata (complete URLs)
  --help                   Show this help message

EXAMPLES:
  # List all PWAs
  sway-test list-pwas

  # Filter by name
  sway-test list-pwas --filter youtube

  # Filter by workspace
  sway-test list-pwas --workspace 50

  # Filter by monitor role
  sway-test list-pwas --monitor tertiary

  # Filter by ULID
  sway-test list-pwas --ulid 01K666N2V6BQMDSBMX3AY74TY7

  # Show verbose output
  sway-test list-pwas --verbose

  # Export to CSV
  sway-test list-pwas --format csv > pwas.csv

  # JSON output for scripting
  sway-test list-pwas --format json | jq '.[] | select(.workspace == "50")'

FILTERS:
  Multiple filters can be combined:
  sway-test list-pwas --filter claude --workspace 51 --monitor tertiary

REGISTRY:
  PWAs are loaded from: ~/.config/i3/pwa-registry.json
  To add PWAs, edit: /etc/nixos/home-modules/desktop/pwa-sites.nix
  Then rebuild: sudo nixos-rebuild switch

ULID FORMAT:
  ULID identifiers are 26-character base32 strings (0-9, A-Z excluding I, L, O, U)
  Example: 01K666N2V6BQMDSBMX3AY74TY7
`);
}

/**
 * Parse list-pwas command arguments
 */
export function parseListPWAsArgs(args: string[]): ListPWAsOptions {
  const parsed = parseArgs(args, {
    string: ["filter", "monitor", "ulid", "format"],
    boolean: ["verbose", "help"],
    alias: {
      f: "filter",
      w: "workspace",
      m: "monitor",
      u: "ulid",
      v: "verbose",
      h: "help",
    },
  });

  const options: ListPWAsOptions = {
    filter: parsed.filter,
    workspace: parsed.workspace ? Number(parsed.workspace) : undefined,
    monitor: parsed.monitor as "primary" | "secondary" | "tertiary" | undefined,
    ulid: parsed.ulid,
    format: (parsed.format as "table" | "json" | "csv") || "table",
    verbose: parsed.verbose,
    help: parsed.help,
  };

  // Validation
  if (options.format && !["table", "json", "csv"].includes(options.format)) {
    throw new StructuredError(
      ErrorType.MALFORMED_TEST,
      "List PWAs Command",
      `Invalid format: ${options.format}`,
      [
        "Valid formats: table, json, csv",
        "Example: sway-test list-pwas --format json",
      ],
      { provided_format: options.format }
    );
  }

  if (options.monitor && !["primary", "secondary", "tertiary"].includes(options.monitor)) {
    throw new StructuredError(
      ErrorType.MALFORMED_TEST,
      "List PWAs Command",
      `Invalid monitor role: ${options.monitor}`,
      [
        "Valid roles: primary, secondary, tertiary",
        "Example: sway-test list-pwas --monitor primary",
      ],
      { provided_monitor: options.monitor }
    );
  }

  // Validate ULID format if provided
  if (options.ulid) {
    const ulidPattern = /^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/;
    if (!ulidPattern.test(options.ulid)) {
      throw new StructuredError(
        ErrorType.INVALID_ULID,
        "List PWAs Command",
        `Invalid ULID format: ${options.ulid}`,
        [
          "ULID must be 26 characters using base32 alphabet (0-9, A-Z excluding I, L, O, U)",
          "Example: 01K666N2V6BQMDSBMX3AY74TY7",
          "Run: sway-test list-pwas to see valid ULIDs",
        ],
        { provided_ulid: options.ulid }
      );
    }
  }

  return options;
}

/**
 * Execute list-pwas command
 * Returns exit code (0 = success, 1 = error)
 */
export async function listPWAsCommand(options: ListPWAsOptions): Promise<number> {
  try {
    // T058: Add registry file missing error handling
    let registry: Map<string, PWADefinition>;

    try {
      registry = await loadPWARegistry();
    } catch (error) {
      if (error instanceof StructuredError && error.type === ErrorType.REGISTRY_ERROR) {
        // Re-throw with setup instructions
        throw new StructuredError(
          ErrorType.REGISTRY_ERROR,
          "List PWAs Command",
          "PWA registry not found or invalid",
          [
            "Ensure PWA registry is generated during NixOS rebuild",
            "Check file exists: ~/.config/i3/pwa-registry.json",
            "Verify pwa-registry.nix configuration in /etc/nixos/home-modules/desktop/",
            "Rebuild NixOS: sudo nixos-rebuild switch --flake .#<target>",
            "If registry exists, check JSON syntax: cat ~/.config/i3/pwa-registry.json | jq",
          ],
          {
            registry_path: expandPath("~/.config/i3/pwa-registry.json"),
            original_error: error.message,
          }
        );
      }
      throw error;
    }

    // Filter PWAs
    const filtered = filterPWAs(registry, options);

    // Format output
    if (options.format === "json") {
      console.log(JSON.stringify(filtered, null, 2));
    } else if (options.format === "csv") {
      const csv = formatPWAsCSV(filtered, options.verbose || false);
      console.log(csv);
    } else {
      // Table format
      const table = options.verbose
        ? formatPWAsVerbose(filtered)
        : formatPWAsTable(filtered, options.verbose || false);
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
