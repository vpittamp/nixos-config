import { parseArgs } from "@std/cli/parse-args";
import { dim, green, red, yellow } from "jsr:@std/fmt/colors";

type CheckStatus = "pass" | "warn" | "fail" | "skip";

export interface QuickShellPreflightCheck {
  name: string;
  status: CheckStatus;
  message: string;
  details: string[];
}

export interface QuickShellPreflightReport {
  timestamp: string;
  status: "pass" | "warn" | "fail";
  overall_status: "pass" | "warn" | "fail";
  checks: QuickShellPreflightCheck[];
}

function showHelp(): void {
  console.log(`i3pm quickshell <preflight> [--json] [--since <journalctl time>]

Checks QuickShell-specific deploy safety conditions.

Examples:
  i3pm quickshell preflight
  i3pm quickshell preflight --json
  i3pm quickshell preflight --since "10 minutes ago"`);
}

async function runCommand(
  args: string[],
  cwd?: string,
  timeoutMs = 4000,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const command = new Deno.Command(args[0], {
    args: args.slice(1),
    cwd,
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
    signal: AbortSignal.timeout(timeoutMs),
  });
  const output = await command.output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout).trim(),
    stderr: new TextDecoder().decode(output.stderr).trim(),
  };
}

async function gitRoot(): Promise<string> {
  const envRoot = Deno.env.get("FLAKE_ROOT") || Deno.env.get("NH_FLAKE") ||
    Deno.env.get("NH_OS_FLAKE");
  if (envRoot) {
    try {
      const stat = await Deno.stat(envRoot);
      if (stat.isDirectory) {
        return envRoot;
      }
    } catch {
      // Fall through to git discovery.
    }
  }

  const result = await runCommand(["git", "rev-parse", "--show-toplevel"], undefined, 2000);
  if (result.code !== 0 || !result.stdout) {
    throw new Error(result.stderr || "not inside a git worktree");
  }
  return result.stdout;
}

function reportStatus(checks: QuickShellPreflightCheck[]): QuickShellPreflightReport["status"] {
  if (checks.some((check) => check.status === "fail")) {
    return "fail";
  }
  if (checks.some((check) => check.status === "warn")) {
    return "warn";
  }
  return "pass";
}

export function buildQuickShellPreflightReport(
  checks: QuickShellPreflightCheck[],
  timestamp = new Date().toISOString(),
): QuickShellPreflightReport {
  const status = reportStatus(checks);
  return {
    timestamp,
    status,
    overall_status: status,
    checks,
  };
}

async function checkTrackedRuntimeSource(): Promise<QuickShellPreflightCheck> {
  try {
    const root = await gitRoot();
    const result = await runCommand([
      "git",
      "ls-files",
      "--others",
      "--exclude-standard",
      "--",
      "home-modules/desktop/quickshell-runtime-shell",
    ], root, 2000);
    if (result.code !== 0) {
      return {
        name: "quickshell.runtime_source.tracked",
        status: "fail",
        message: result.stderr || "git ls-files failed",
        details: [],
      };
    }
    const untracked = result.stdout.split("\n").map((line) => line.trim()).filter(Boolean);
    return {
      name: "quickshell.runtime_source.tracked",
      status: untracked.length > 0 ? "fail" : "pass",
      message: untracked.length > 0
        ? "QuickShell runtime source has untracked files omitted by Nix flakes"
        : "all QuickShell runtime source files are tracked",
      details: untracked,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("not inside a git worktree") || message.includes("not a git repository")) {
      return {
        name: "quickshell.runtime_source.tracked",
        status: "skip",
        message: "not running inside the nixos-config git checkout",
        details: [],
      };
    }
    return {
      name: "quickshell.runtime_source.tracked",
      status: "fail",
      message,
      details: [],
    };
  }
}

async function checkServiceActive(): Promise<QuickShellPreflightCheck> {
  try {
    const result = await runCommand([
      "systemctl",
      "--user",
      "is-active",
      "quickshell-runtime-shell.service",
    ], undefined, 2000);
    const active = result.code === 0 && result.stdout === "active";
    return {
      name: "quickshell.service.active",
      status: active ? "pass" : "fail",
      message: active
        ? "quickshell-runtime-shell.service is active"
        : `quickshell-runtime-shell.service is ${result.stdout || "not active"}`,
      details: result.stderr ? [result.stderr] : [],
    };
  } catch (error) {
    return {
      name: "quickshell.service.active",
      status: "fail",
      message: error instanceof Error ? error.message : String(error),
      details: [],
    };
  }
}

function quickshellLogFindings(log: string): { fatal: string[]; warnings: string[] } {
  const fatal: string[] = [];
  const warnings: string[] = [];
  for (const line of log.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    if (
      trimmed.includes("Failed to load configuration") ||
      trimmed.includes(" is not a type") ||
      trimmed.includes("File not found") ||
      (trimmed.includes("Type ") && trimmed.includes(" unavailable"))
    ) {
      fatal.push(trimmed);
      continue;
    }
    if (/deprecated|binding loop|upower/i.test(trimmed)) {
      warnings.push(trimmed);
    }
  }
  return { fatal, warnings };
}

async function checkRecentLogs(since: string): Promise<QuickShellPreflightCheck> {
  try {
    const result = await runCommand([
      "journalctl",
      "--user",
      "-u",
      "quickshell-runtime-shell.service",
      "--since",
      since,
      "--no-pager",
    ], undefined, 4000);
    if (result.code !== 0) {
      return {
        name: "quickshell.logs.clean",
        status: "warn",
        message: result.stderr || "journalctl failed",
        details: [],
      };
    }
    const findings = quickshellLogFindings(result.stdout);
    if (findings.fatal.length > 0) {
      return {
        name: "quickshell.logs.clean",
        status: "fail",
        message: "recent QuickShell logs contain loader errors",
        details: findings.fatal,
      };
    }
    if (findings.warnings.length > 0) {
      return {
        name: "quickshell.logs.clean",
        status: "warn",
        message: "recent QuickShell logs contain runtime warnings",
        details: findings.warnings,
      };
    }
    return {
      name: "quickshell.logs.clean",
      status: "pass",
      message: "recent QuickShell logs are clean",
      details: [],
    };
  } catch (error) {
    return {
      name: "quickshell.logs.clean",
      status: "warn",
      message: error instanceof Error ? error.message : String(error),
      details: [],
    };
  }
}

async function collectQuickShellPreflight(since: string): Promise<QuickShellPreflightReport> {
  const checks = await Promise.all([
    checkTrackedRuntimeSource(),
    checkServiceActive(),
    checkRecentLogs(since),
  ]);
  return buildQuickShellPreflightReport(checks);
}

function printTextReport(report: QuickShellPreflightReport): void {
  const color = report.status === "pass" ? green : report.status === "warn" ? yellow : red;
  console.log(`${color(report.status.toUpperCase())} QuickShell preflight ${dim(report.timestamp)}`);
  for (const check of report.checks) {
    const checkColor = check.status === "pass" ? green : check.status === "warn" ? yellow : red;
    console.log(`  ${checkColor(check.status.toUpperCase())} ${check.name}: ${check.message}`);
    for (const detail of check.details.slice(0, 8)) {
      console.log(`    ${dim(detail)}`);
    }
    if (check.details.length > 8) {
      console.log(`    ${dim(`... ${check.details.length - 8} more`)}`);
    }
  }
}

export async function quickshellCommand(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["since"],
    alias: { h: "help" },
    default: { since: "2 minutes ago" },
  });

  if (parsed.help) {
    showHelp();
    return 0;
  }

  const subcommand = String(parsed._[0] || "");
  if (subcommand !== "preflight") {
    showHelp();
    return subcommand ? 1 : 0;
  }

  const report = await collectQuickShellPreflight(String(parsed.since || "2 minutes ago"));
  if (parsed.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printTextReport(report);
  }
  return report.status === "fail" ? 1 : 0;
}
