/**
 * Window Classification Rules Commands
 */

import { parseArgs } from "@std/cli/parse-args";
import { DaemonClient } from "../client.ts";
import { WindowRuleSchema } from "../validation.ts";
import type { WindowRule } from "../models.ts";
import { z } from "zod";

interface RulesCommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`
i3pm rules - Window classification rules management

USAGE:
  i3pm rules <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
  list              List all classification rules
  classify          Test window classification
  validate          Validate all rules
  test              Test rule matching
  discover          Discover window pattern for application

OPTIONS:
  -h, --help        Show this help message

LIST OPTIONS:
  No additional options

CLASSIFY OPTIONS:
  --class <name>    Window class to classify
  --instance <name> Window instance (optional)

VALIDATE OPTIONS:
  No additional options

TEST OPTIONS:
  --class <name>    Window class to test

DISCOVER OPTIONS:
  --app <name>      Application name to discover (required)
  --workspace <N>   Assign to workspace (1-9)
  --scope <scope>   Classify as 'scoped' or 'global'
  --method <method> Launch method: 'direct' or 'rofi' (default: direct)
  --timeout <secs>  Wait timeout in seconds (default: 10.0)
  --keep-window     Don't close window after discovery
  --json            Output JSON format
  --scan            Scan currently open windows (instant, no launching)
  --compare         Compare discovered patterns with existing rules (use with --scan)
  --verbose         Show detailed output including correct rules (use with --compare)
  --registry        Discover all apps from application-registry.json

EXAMPLES:
  i3pm rules list
  i3pm rules classify --class Ghostty --instance ghostty
  i3pm rules validate
  i3pm rules test --class Firefox
  i3pm rules discover --scan                           # Scan open windows (instant)
  i3pm rules discover --scan --compare                 # Compare with existing rules
  i3pm rules discover --scan --compare --verbose       # Show all rules including correct ones
  i3pm rules discover --app pavucontrol
  i3pm rules discover --app vscode --workspace 1 --scope scoped
  i3pm rules discover --registry
`);
  Deno.exit(0);
}

/**
 * T030: Implement `i3pm rules list` command
 */
async function listCommand(
  client: DaemonClient,
  options: RulesCommandOptions,
): Promise<void> {
  try {
    const response = await client.request("list_rules");

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const RuleArraySchema = z.array(WindowRuleSchema);
    const rules = RuleArraySchema.parse(response) as WindowRule[];

    if (rules.length === 0) {
      console.log("\nNo classification rules found");
      return;
    }

    // Display rules
    console.log(`\nWindow Classification Rules (${rules.length} rules):`);
    console.log("─".repeat(80));

    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      const enabled = rule.enabled ? "✓" : "✗";
      const scope = rule.scope === "scoped" ? "🔸 scoped" : "global";
      const instance = rule.instance_pattern
        ? ` (instance: ${rule.instance_pattern})`
        : "";

      console.log(
        `${i + 1}. ${rule.class_pattern}${instance} → ${scope} ` +
        `(priority: ${rule.priority}, ${enabled} ${rule.enabled ? "enabled" : "disabled"})`,
      );
    }

    console.log("─".repeat(80));
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error("Error: Invalid daemon response format");
      if (options.debug) {
        console.error("Validation errors:", err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T031: Implement `i3pm rules classify` command
 */
async function classifyCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: RulesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["class", "instance"],
  });

  if (!parsed.class) {
    console.error("Error: --class flag is required");
    console.error('Run "i3pm rules classify --help" for usage information');
    Deno.exit(1);
  }

  try {
    const params: { class: string; instance?: string } = {
      class: parsed.class as string,
    };

    if (parsed.instance) {
      params.instance = parsed.instance as string;
    }

    const response = await client.request("classify_window", params);

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Parse classification result
    const result = response as {
      class: string;
      instance?: string;
      scope: "scoped" | "global";
      matched_rule: { rule_id: string; priority: number } | null;
    };

    // Display classification result
    console.log("\nClassification Result:");
    console.log("─".repeat(60));
    console.log(`  Class:        ${result.class}`);
    if (result.instance) {
      console.log(`  Instance:     ${result.instance}`);
    }
    console.log(`  Scope:        ${result.scope}`);

    if (result.matched_rule) {
      console.log(
        `  Matched Rule: ${result.matched_rule.rule_id} (priority ${result.matched_rule.priority})`,
      );
    } else {
      console.log("  Matched Rule: None (default classification)");
    }

    console.log("─".repeat(60));
  } catch (err) {
    if (err instanceof Error) { console.error(`Error: ${err.message}`); } else { console.error("Error:", err); }
    Deno.exit(1);
  }
}

/**
 * T032: Implement `i3pm rules validate` command
 */
async function validateCommand(
  client: DaemonClient,
  options: RulesCommandOptions,
): Promise<void> {
  try {
    const response = await client.request("list_rules");

    if (options.debug) {
      console.error("DEBUG: Raw response:", JSON.stringify(response, null, 2));
    }

    // Validate response with Zod
    const RuleArraySchema = z.array(WindowRuleSchema);
    const rules = RuleArraySchema.parse(response) as WindowRule[];

    if (rules.length === 0) {
      console.log("\nNo rules to validate");
      return;
    }

    // Validate rules
    let hasErrors = false;
    const errors: string[] = [];

    // Check for regex pattern validity
    for (const rule of rules) {
      try {
        new RegExp(rule.class_pattern);
      } catch (err) {
        errors.push(
          `Rule ${rule.rule_id}: Invalid class pattern regex: ${(err instanceof Error ? err.message : String(err))}`,
        );
        hasErrors = true;
      }

      if (rule.instance_pattern) {
        try {
          new RegExp(rule.instance_pattern);
        } catch (err) {
          errors.push(
            `Rule ${rule.rule_id}: Invalid instance pattern regex: ${(err instanceof Error ? err.message : String(err))}`,
          );
          hasErrors = true;
        }
      }
    }

    // Check for rule conflicts (same pattern with different scopes at same priority)
    const patternMap = new Map<string, WindowRule[]>();
    for (const rule of rules) {
      const key = `${rule.class_pattern}:${rule.instance_pattern || ""}`;
      if (!patternMap.has(key)) {
        patternMap.set(key, []);
      }
      patternMap.get(key)!.push(rule);
    }

    for (const [pattern, rulesWithPattern] of patternMap) {
      const samePriorityRules = rulesWithPattern.filter((r) =>
        r.priority === rulesWithPattern[0].priority
      );
      const differentScopes = new Set(samePriorityRules.map((r) => r.scope));

      if (samePriorityRules.length > 1 && differentScopes.size > 1) {
        errors.push(
          `Conflict: Pattern "${pattern}" has multiple rules with same priority ${rulesWithPattern[0].priority} but different scopes`,
        );
        hasErrors = true;
      }
    }

    // Display results
    console.log(`\nRule Validation (${rules.length} rules checked):`);
    console.log("─".repeat(80));

    if (hasErrors) {
      console.log("❌ Validation FAILED\n");
      for (const error of errors) {
        console.log(`  ❌ ${error}`);
      }
      console.log("─".repeat(80));
      Deno.exit(1);
    } else {
      console.log("✅ All rules valid");
      console.log("─".repeat(80));
    }
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error("Error: Invalid daemon response format");
      if (options.debug) {
        console.error("Validation errors:", err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T033: Implement `i3pm rules test` command
 */
async function testCommand(
  client: DaemonClient,
  args: (string | number)[],
  options: RulesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["class"],
  });

  if (!parsed.class) {
    console.error("Error: --class flag is required");
    console.error('Run "i3pm rules test --help" for usage information');
    Deno.exit(1);
  }

  try {
    // Get all rules
    const rulesResponse = await client.request("list_rules");
    const RuleArraySchema = z.array(WindowRuleSchema);
    const allRules = RuleArraySchema.parse(rulesResponse) as WindowRule[];

    // Get classification for window
    const classifyResponse = await client.request("classify_window", {
      class: parsed.class as string,
    });

    const result = classifyResponse as {
      class: string;
      scope: "scoped" | "global";
      matched_rule: { rule_id: string; priority: number } | null;
    };

    // Find all matching rules
    const className = parsed.class as string;
    const matchingRules = allRules.filter((rule) => {
      try {
        const regex = new RegExp(rule.class_pattern);
        return regex.test(className) && rule.enabled;
      } catch {
        return false;
      }
    }).sort((a, b) => b.priority - a.priority); // Sort by priority descending

    // Display results
    console.log(`\nRule Matching Test for: ${className}`);
    console.log("─".repeat(80));

    if (matchingRules.length === 0) {
      console.log("No matching rules found (default classification will apply)\n");
    } else {
      console.log(`Matching Rules (evaluated in priority order):\n`);

      for (let i = 0; i < matchingRules.length; i++) {
        const rule = matchingRules[i];
        const isWinner = rule.rule_id === result.matched_rule?.rule_id;
        const marker = isWinner ? "  👉" : "    ";

        console.log(
          `${marker} ${i + 1}. ${rule.class_pattern} → ${rule.scope} (priority: ${rule.priority})`,
        );
      }

      console.log("");
    }

    console.log(`Final Classification: ${result.scope}`);
    console.log("─".repeat(80));
  } catch (err) {
    if (err instanceof z.ZodError) {
      console.error("Error: Invalid daemon response format");
      if (options.debug) {
        console.error("Validation errors:", err.errors);
      }
      Deno.exit(1);
    }
    throw err;
  }
}

/**
 * T026: Implement `i3pm rules discover` command
 */
async function discoverCommand(
  args: (string | number)[],
  options: RulesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    string: ["app", "workspace", "scope", "method", "timeout"],
    boolean: ["keep-window", "json", "registry", "scan", "compare", "verbose"],
  });

  // Build command for Python CLI
  const pythonCli = "/etc/nixos/home-modules/tools/i3-window-rules-service/i3-window-rules";
  const cmdArgs: string[] = [];

  if (parsed.scan) {
    // Scan open windows (instant discovery)
    cmdArgs.push("scan");
    if (parsed.json) cmdArgs.push("--json");
    if (parsed.compare) cmdArgs.push("--compare");
    if (parsed.verbose) cmdArgs.push("--verbose");
  } else if (parsed.registry) {
    // Bulk discovery from registry
    cmdArgs.push("bulk");
    if (parsed.json) cmdArgs.push("--json");
    if (parsed.timeout) cmdArgs.push("--timeout", String(parsed.timeout));
  } else {
    // Single app discovery
    if (!parsed.app) {
      console.error("Error: --app flag is required (or use --scan/--registry for bulk discovery)");
      console.error('Run "i3pm rules discover --help" for usage information');
      Deno.exit(1);
    }

    cmdArgs.push("discover");
    cmdArgs.push("--app", String(parsed.app));
    if (parsed.workspace) cmdArgs.push("--workspace", String(parsed.workspace));
    if (parsed.scope) cmdArgs.push("--scope", String(parsed.scope));
    if (parsed.method) cmdArgs.push("--method", String(parsed.method));
    if (parsed.timeout) cmdArgs.push("--timeout", String(parsed.timeout));
    if (parsed["keep-window"]) cmdArgs.push("--keep-window");
    if (parsed.json) cmdArgs.push("--json");
  }

  if (options.verbose) {
    console.error(`Executing: ${pythonCli} ${cmdArgs.join(" ")}`);
  }

  try {
    // Execute Python CLI
    const command = new Deno.Command(pythonCli, {
      args: cmdArgs,
      stdout: "inherit",
      stderr: "inherit",
    });

    const { code } = await command.output();

    if (code !== 0) {
      console.error(`\nDiscovery command failed with exit code ${code}`);
      Deno.exit(code);
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`Error executing discovery: ${err.message}`);
    } else {
      console.error("Error executing discovery:", err);
    }
    Deno.exit(1);
  }
}

/**
 * Rules command router
 */
export async function rulesCommand(
  args: (string | number)[],
  options: RulesCommandOptions,
): Promise<void> {
  const parsed = parseArgs(args.map(String), {
    boolean: ["help"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showHelp();
  }

  const subcommand = parsed._[0] as string;
  const subcommandArgs = parsed._.slice(1);

  // Connect to daemon
  const client = new DaemonClient();

  try {
    await client.connect();

    if (options.verbose) {
      console.error("Connected to daemon");
    }

    // Route to subcommand
    switch (subcommand) {
      case "list":
        await listCommand(client, options);
        break;

      case "classify":
        await classifyCommand(client, subcommandArgs, options);
        break;

      case "validate":
        await validateCommand(client, options);
        break;

      case "test":
        await testCommand(client, subcommandArgs, options);
        break;

      case "discover":
        // Discovery doesn't need daemon connection
        await client.close();
        await discoverCommand(subcommandArgs, options);
        return; // Exit early since discover handles its own execution

      default:
        console.error(`Unknown subcommand: ${subcommand}`);
        console.error('Run "i3pm rules --help" for usage information');
        Deno.exit(1);
    }
  } catch (err) {
    if (err instanceof Error) {
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

  // Force exit to avoid event loop blocking from pending read operations
}
