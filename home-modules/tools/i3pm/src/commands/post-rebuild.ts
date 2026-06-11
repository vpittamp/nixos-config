import { parseArgs } from "@std/cli/parse-args";
import { dim, green, red, yellow } from "jsr:@std/fmt/colors";
import { collectHealthReport } from "./health.ts";
import { collectPerfSmoke } from "./perf.ts";
import { collectQuickShellPreflight } from "./quickshell.ts";

type ReportStatus = "pass" | "warn" | "fail";

interface PostRebuildSmokeReport {
  timestamp: string;
  status: ReportStatus;
  overall_status: ReportStatus;
  checks: {
    health: Awaited<ReturnType<typeof collectHealthReport>>;
    perf: Awaited<ReturnType<typeof collectPerfSmoke>>;
    quickshell: Awaited<ReturnType<typeof collectQuickShellPreflight>>;
  };
}

function showHelp(): void {
  console.log(`i3pm post-rebuild <smoke> [--json] [--since <journalctl time>]

Runs the standard local post-rebuild runtime checks.

Examples:
  i3pm post-rebuild smoke
  i3pm post-rebuild smoke --json
  i3pm post-rebuild smoke --since "10 minutes ago"`);
}

function normalizeStatus(value: string | undefined): ReportStatus {
  if (value === "fail") {
    return "fail";
  }
  if (value === "warn") {
    return "warn";
  }
  return "pass";
}

function combinedStatus(statuses: ReportStatus[]): ReportStatus {
  if (statuses.includes("fail")) {
    return "fail";
  }
  if (statuses.includes("warn")) {
    return "warn";
  }
  return "pass";
}

async function collectPostRebuildSmoke(since: string): Promise<PostRebuildSmokeReport> {
  const health = await collectHealthReport();
  const perf = await collectPerfSmoke();
  const quickshell = await collectQuickShellPreflight(since);
  const status = combinedStatus([
    normalizeStatus(health.overall_status),
    normalizeStatus(perf.overall_status),
    normalizeStatus(quickshell.overall_status),
  ]);
  return {
    timestamp: new Date().toISOString(),
    status,
    overall_status: status,
    checks: { health, perf, quickshell },
  };
}

function printReport(report: PostRebuildSmokeReport): void {
  const color = report.status === "pass" ? green : report.status === "warn" ? yellow : red;
  console.log(`${color(report.status.toUpperCase())} post-rebuild smoke ${dim(report.timestamp)}`);
  console.log(`  ${normalizeStatus(report.checks.health.overall_status)} health`);
  console.log(`  ${normalizeStatus(report.checks.perf.overall_status)} perf`);
  console.log(`  ${normalizeStatus(report.checks.quickshell.overall_status)} quickshell`);
}

export async function postRebuildCommand(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["since"],
    alias: { h: "help" },
    default: { since: "2 minutes ago" },
  });
  const subcommand = String(parsed._[0] || "");
  if (parsed.help || !subcommand) {
    showHelp();
    return 0;
  }
  if (subcommand !== "smoke") {
    showHelp();
    return 1;
  }

  const report = await collectPostRebuildSmoke(String(parsed.since || "2 minutes ago"));
  if (parsed.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printReport(report);
  }
  return report.status === "fail" ? 1 : 0;
}
