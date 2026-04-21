import { parseArgs } from "@std/cli/parse-args";
import { bold, cyan, dim, green, red, yellow } from "jsr:@std/fmt/colors";
import { getSocketPath } from "../utils/socket.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface UnitStatus {
  name: string;
  scope: "user" | "system";
  load_state: string;
  active_state: string;
  sub_state: string;
  unit_file_state: string;
  fragment_path: string;
  result: string;
  healthy: boolean;
}

interface PathCheck {
  current_path: string;
  expected_path: string;
  matches: boolean;
}

interface RemotePushHealth {
  health: string;
  endpoint_url: string;
  source_connection_key: string;
  last_attempt_at: string;
  last_success_at: string;
  last_error_at: string;
  last_error_summary: string;
  consecutive_failures: number;
}

interface McpBrowserCandidate {
  pid: number;
  ppid: number;
  age_seconds: number;
  cmdline: string;
}

interface McpBrowserHealth {
  healthy: boolean;
  issues: string[];
  endpoint_url: string;
  managed_browser_service: {
    name: string;
    active: boolean;
    profile_dir: string;
    port: number;
  };
  reaper_timer: {
    name: string;
    active: boolean;
  };
  listener: {
    line: string;
    pid: number | null;
    cmdline: string;
    matches_expected_profile: boolean;
  };
  stale_candidates: McpBrowserCandidate[];
}

interface HealthReport {
  timestamp: string;
  overall_status: "ok" | "warn" | "fail";
  core_issues: string[];
  optional_issues: string[];
  core_units: UnitStatus[];
  failed_user_units: string[];
  system_generation: string;
  home_manager_generation: string;
  home_manager_profile_generation: string;
  daemon_socket: {
    path: string;
    exists: boolean;
  };
  quickshell: {
    shell_qml: PathCheck;
    service_unit: PathCheck;
  };
  remote_push: RemotePushHealth | null;
  mcp_browser_runtime: McpBrowserHealth | null;
}

const OPTIONAL_USER_UNIT_PREFIXES = ["wayvnc@"];

function showHelp(): void {
  console.log(`i3pm health [--json]

Checks runtime convergence and service health for the local host.

Examples:
  i3pm health
  i3pm health --json`);
}

function expandHome(path: string): string {
  if (!path.startsWith("~/")) {
    return path;
  }
  return `${Deno.env.get("HOME") || ""}/${path.slice(2)}`;
}

async function runCommand(
  args: string[],
): Promise<{ code: number; stdout: string; stderr: string }> {
  const command = new Deno.Command(args[0], {
    args: args.slice(1),
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout).trim(),
    stderr: new TextDecoder().decode(output.stderr).trim(),
  };
}

async function realPathOrEmpty(path: string): Promise<string> {
  try {
    return await Deno.realPath(expandHome(path));
  } catch {
    return "";
  }
}

function parseSystemctlShow(payload: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of payload.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    const idx = trimmed.indexOf("=");
    if (idx <= 0) {
      continue;
    }
    result[trimmed.slice(0, idx)] = trimmed.slice(idx + 1);
  }
  return result;
}

async function loadUnitStatus(name: string, scope: "user" | "system"): Promise<UnitStatus> {
  const args = scope === "user"
    ? [
      "systemctl",
      "--user",
      "show",
      name,
      "--property=LoadState,ActiveState,SubState,UnitFileState,FragmentPath,Result",
    ]
    : [
      "systemctl",
      "show",
      name,
      "--property=LoadState,ActiveState,SubState,UnitFileState,FragmentPath,Result",
    ];
  const result = await runCommand(args);
  const fields = parseSystemctlShow(result.stdout);
  const activeState = String(fields.ActiveState || "");
  return {
    name,
    scope,
    load_state: String(fields.LoadState || ""),
    active_state: activeState,
    sub_state: String(fields.SubState || ""),
    unit_file_state: String(fields.UnitFileState || ""),
    fragment_path: String(fields.FragmentPath || ""),
    result: String(fields.Result || ""),
    healthy: activeState === "active",
  };
}

async function loadFailedUserUnits(): Promise<string[]> {
  const result = await runCommand([
    "systemctl",
    "--user",
    "list-units",
    "--type=service",
    "--state=failed",
    "--plain",
    "--no-legend",
    "--no-pager",
  ]);
  if (!result.stdout) {
    return [];
  }
  return result.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => line.split(/\s+/, 1)[0]);
}

async function loadRemotePushState(): Promise<RemotePushHealth | null> {
  const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR") || `/run/user/${Deno.uid()}`;
  const statePath = `${runtimeDir}/eww-monitoring-panel/remote-otel-push-state.json`;
  try {
    const raw = await Deno.readTextFile(statePath);
    const payload = JSON.parse(raw);
    return {
      health: String(payload.health || "").trim() || "unknown",
      endpoint_url: String(payload.endpoint_url || "").trim(),
      source_connection_key: String(payload.source_connection_key || "").trim(),
      last_attempt_at: String(payload.last_attempt_at || "").trim(),
      last_success_at: String(payload.last_success_at || "").trim(),
      last_error_at: String(payload.last_error_at || "").trim(),
      last_error_summary: String(payload.last_error_summary || "").trim(),
      consecutive_failures: Number(payload.consecutive_failures || 0),
    };
  } catch {
    return null;
  }
}

async function loadMcpBrowserHealth(): Promise<McpBrowserHealth | null> {
  const result = await runCommand(["mcp-browser-lifecycle", "health"]);
  if (result.code !== 0 || !result.stdout) {
    return null;
  }
  try {
    return JSON.parse(result.stdout) as McpBrowserHealth;
  } catch {
    return null;
  }
}

async function loadHomeManagerGenerationFromService(): Promise<string> {
  const result = await runCommand([
    "systemctl",
    "show",
    "home-manager-vpittamp.service",
    "-p",
    "ExecStart",
    "--no-pager",
  ]);
  if (!result.stdout) {
    return "";
  }
  const match = result.stdout.match(/\/nix\/store\/[^ ;]+-home-manager-generation/);
  return match ? match[0] : "";
}

function makePathCheck(currentPath: string, expectedPath: string): PathCheck {
  return {
    current_path: currentPath,
    expected_path: expectedPath,
    matches: !!(currentPath && expectedPath && currentPath === expectedPath),
  };
}

function statusColor(status: HealthReport["overall_status"]): (text: string) => string {
  if (status === "ok") {
    return green;
  }
  if (status === "warn") {
    return yellow;
  }
  return red;
}

function formatUnitStatus(unit: UnitStatus): string {
  const state = unit.healthy
    ? green(unit.active_state || "active")
    : red(unit.active_state || "unknown");
  return `${unit.name} ${state} ${dim(`${unit.sub_state || "unknown"} / ${unit.result || "n/a"}`)}`;
}

async function collectHealthReport(): Promise<HealthReport> {
  const coreUnits = await Promise.all([
    loadUnitStatus("i3-project-daemon.service", "user"),
    loadUnitStatus("otel-ai-monitor.service", "user"),
    loadUnitStatus("quickshell-runtime-shell.service", "user"),
    loadUnitStatus("mcp-chrome-devtools-browser.service", "user"),
    loadUnitStatus("mcp-browser-orphan-reaper.timer", "user"),
    loadUnitStatus("home-manager-vpittamp.service", "system"),
  ]);

  const failedUserUnits = await loadFailedUserUnits();
  const optionalIssues = failedUserUnits
    .filter((unit) => OPTIONAL_USER_UNIT_PREFIXES.some((prefix) => unit.startsWith(prefix)))
    .map((unit) => `${unit} is failed`);
  const coreFailedUserUnits = failedUserUnits.filter((unit) =>
    !OPTIONAL_USER_UNIT_PREFIXES.some((prefix) => unit.startsWith(prefix))
  );

  const systemGeneration = await realPathOrEmpty("/run/current-system");
  const homeManagerGeneration = await loadHomeManagerGenerationFromService();
  const homeManagerProfileGeneration = await realPathOrEmpty(
    "~/.local/state/nix/profiles/home-manager",
  );
  const currentShellQml = await realPathOrEmpty("~/.config/quickshell/i3pm-shell/shell.qml");
  const expectedShellQml = await realPathOrEmpty(
    `${homeManagerGeneration}/home-files/.config/quickshell/i3pm-shell/shell.qml`,
  );
  const currentShellService = await realPathOrEmpty(
    "~/.config/systemd/user/quickshell-runtime-shell.service",
  );
  const expectedShellService = await realPathOrEmpty(
    `${homeManagerGeneration}/home-files/.config/systemd/user/quickshell-runtime-shell.service`,
  );
  const shellQmlCheck = makePathCheck(currentShellQml, expectedShellQml);
  const shellServiceCheck = makePathCheck(currentShellService, expectedShellService);
  const daemonSocketPath = getSocketPath();
  const daemonSocketExists = await Deno.stat(daemonSocketPath).then(() => true).catch(() => false);
  const remotePush = await loadRemotePushState();
  const mcpBrowserRuntime = await loadMcpBrowserHealth();

  const coreIssues: string[] = [];
  for (const unit of coreUnits) {
    if (!unit.healthy) {
      coreIssues.push(
        `${unit.name} is ${unit.active_state || "unknown"}/${unit.sub_state || "unknown"}`,
      );
    }
  }
  for (const unit of coreFailedUserUnits) {
    coreIssues.push(`${unit} is failed`);
  }
  if (!daemonSocketExists) {
    coreIssues.push(`daemon socket missing at ${daemonSocketPath}`);
  }
  if (currentShellQml && expectedShellQml && !shellQmlCheck.matches) {
    coreIssues.push("quickshell QML path does not match current Home Manager generation");
  }
  if (currentShellService && expectedShellService && !shellServiceCheck.matches) {
    coreIssues.push("quickshell systemd unit does not match current Home Manager generation");
  }
  if (remotePush && (remotePush.health === "degraded" || remotePush.health === "down")) {
    const label = remotePush.health === "down"
      ? "remote OTEL push is down"
      : "remote OTEL push is degraded";
    const detail = remotePush.last_error_summary
      ? `${label}: ${remotePush.last_error_summary}`
      : label;
    optionalIssues.push(detail);
  }
  if (!mcpBrowserRuntime) {
    coreIssues.push("mcp browser health helper unavailable");
  } else if (!mcpBrowserRuntime.healthy) {
    coreIssues.push(...mcpBrowserRuntime.issues.map((issue) => `mcp browsers: ${issue}`));
  }

  const overallStatus: HealthReport["overall_status"] = coreIssues.length > 0
    ? "fail"
    : optionalIssues.length > 0
    ? "warn"
    : "ok";

  return {
    timestamp: new Date().toISOString(),
    overall_status: overallStatus,
    core_issues: coreIssues,
    optional_issues: optionalIssues,
    core_units: coreUnits,
    failed_user_units: failedUserUnits,
    system_generation: systemGeneration,
    home_manager_generation: homeManagerGeneration,
    home_manager_profile_generation: homeManagerProfileGeneration,
    daemon_socket: {
      path: daemonSocketPath,
      exists: daemonSocketExists,
    },
    quickshell: {
      shell_qml: shellQmlCheck,
      service_unit: shellServiceCheck,
    },
    remote_push: remotePush,
    mcp_browser_runtime: mcpBrowserRuntime,
  };
}

function printReport(report: HealthReport): void {
  const color = statusColor(report.overall_status);
  console.log(`${bold("Health")} ${color(report.overall_status.toUpperCase())}`);
  console.log(`${dim(report.timestamp)}`);
  console.log("");

  console.log(bold("Core Services"));
  for (const unit of report.core_units) {
    console.log(`  ${formatUnitStatus(unit)}`);
  }
  console.log(
    `  daemon socket ${report.daemon_socket.exists ? green("present") : red("missing")} ${
      dim(report.daemon_socket.path)
    }`,
  );
  console.log("");

  console.log(bold("Convergence"));
  console.log(`  system ${cyan(report.system_generation || "(missing)")}`);
  console.log(`  home-manager ${cyan(report.home_manager_generation || "(missing)")}`);
  console.log(`  hm profile ${dim(report.home_manager_profile_generation || "(missing)")}`);
  console.log(
    `  quickshell qml ${report.quickshell.shell_qml.matches ? green("matched") : red("mismatch")} ${
      dim(report.quickshell.shell_qml.current_path || "(missing)")
    }`,
  );
  console.log(
    `  quickshell unit ${
      report.quickshell.service_unit.matches ? green("matched") : red("mismatch")
    } ${dim(report.quickshell.service_unit.current_path || "(missing)")}`,
  );
  console.log("");

  if (report.remote_push) {
    const remoteColor = report.remote_push.health === "healthy"
      ? green
      : report.remote_push.health === "degraded"
      ? yellow
      : red;
    console.log(bold("Remote OTEL"));
    console.log(
      `  ${remoteColor(report.remote_push.health || "unknown")} ${
        dim(report.remote_push.endpoint_url || "(no endpoint)")
      }`,
    );
    if (report.remote_push.last_success_at) {
      console.log(`  last success ${report.remote_push.last_success_at}`);
    }
    if (report.remote_push.last_error_summary) {
      console.log(`  last error ${yellow(report.remote_push.last_error_summary)}`);
    }
    console.log("");
  }

  if (report.mcp_browser_runtime) {
    const runtime = report.mcp_browser_runtime;
    console.log(bold("MCP Browsers"));
    console.log(
      `  browser service ${
        runtime.managed_browser_service.active ? green("active") : red("inactive")
      } ${dim(runtime.managed_browser_service.name)}`,
    );
    console.log(
      `  reaper timer ${runtime.reaper_timer.active ? green("active") : red("inactive")} ${
        dim(runtime.reaper_timer.name)
      }`,
    );
    console.log(
      `  endpoint ${
        runtime.listener.pid && runtime.listener.matches_expected_profile
          ? green("matched")
          : red("drift")
      } ${dim(runtime.endpoint_url)}`,
    );
    if (runtime.listener.pid) {
      console.log(`  listener pid ${runtime.listener.pid} ${dim(runtime.listener.cmdline || "(unknown)")}`);
    }
    if (runtime.stale_candidates.length > 0) {
      console.log(`  stale processes ${red(String(runtime.stale_candidates.length))}`);
      for (const candidate of runtime.stale_candidates.slice(0, 5)) {
        console.log(
          `    ${candidate.pid} ${dim(`${candidate.age_seconds}s`)} ${
            dim(candidate.cmdline || "(unknown)")
          }`,
        );
      }
    } else {
      console.log(`  stale processes ${green("0")}`);
    }
    console.log("");
  }

  if (report.core_issues.length > 0) {
    console.log(red(bold("Core Issues")));
    for (const issue of report.core_issues) {
      console.log(`  ${red("•")} ${issue}`);
    }
    console.log("");
  }

  if (report.optional_issues.length > 0) {
    console.log(yellow(bold("Optional Issues")));
    for (const issue of report.optional_issues) {
      console.log(`  ${yellow("•")} ${issue}`);
    }
  }
}

export async function healthCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
    return 0;
  }

  const report = await collectHealthReport();
  if (parsed.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printReport(report);
  }

  if (report.overall_status === "fail") {
    return 1;
  }
  if (report.overall_status === "warn") {
    return 2;
  }
  return 0;
}
