import { parseArgs } from "@std/cli/parse-args";
import { bold, dim, green, red, yellow } from "jsr:@std/fmt/colors";
import { DaemonClient } from "../services/daemon-client.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface SmokeCheck {
  name: string;
  budget_ms: number;
  duration_ms: number;
  status: "pass" | "fail" | "skip";
  reason: string;
}

interface PerfSmokeReport {
  timestamp: string;
  overall_status: "pass" | "fail";
  checks: SmokeCheck[];
}

function showHelp(): void {
  console.log(`i3pm perf <smoke> [--json]

Runs latency smoke checks against daemon-owned focus and dashboard paths.

Examples:
  i3pm perf smoke
  i3pm perf smoke --json`);
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function boolValue(value: unknown): boolean {
  return value === true;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

async function measure(
  name: string,
  budgetMs: number,
  fn: () => Promise<{ success: boolean; reason?: string; skipped?: boolean }>,
): Promise<SmokeCheck> {
  const started = performance.now();
  try {
    const result = await fn();
    const durationMs = Math.round((performance.now() - started) * 10) / 10;
    if (result.skipped) {
      return {
        name,
        budget_ms: budgetMs,
        duration_ms: durationMs,
        status: "skip",
        reason: result.reason || "not_applicable",
      };
    }
    return {
      name,
      budget_ms: budgetMs,
      duration_ms: durationMs,
      status: result.success && durationMs <= budgetMs ? "pass" : "fail",
      reason: result.reason || (durationMs <= budgetMs ? "ok" : "over_budget"),
    };
  } catch (error) {
    return {
      name,
      budget_ms: budgetMs,
      duration_ms: Math.round((performance.now() - started) * 10) / 10,
      status: "fail",
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}

function dashboardWindows(snapshot: Record<string, unknown>): Record<string, unknown>[] {
  const windows: Record<string, unknown>[] = [];
  for (const project of asArray(snapshot.projects)) {
    const projectRecord = asRecord(project);
    for (const windowData of asArray(projectRecord.windows)) {
      windows.push(asRecord(windowData));
    }
  }
  return windows;
}

function dashboardWorkspaces(snapshot: Record<string, unknown>): Record<string, unknown>[] {
  const workspaces: Record<string, unknown>[] = [];
  for (const output of asArray(snapshot.outputs)) {
    const outputRecord = asRecord(output);
    for (const workspace of asArray(outputRecord.workspaces)) {
      workspaces.push(asRecord(workspace));
    }
  }
  return workspaces;
}

function dashboardSessions(snapshot: Record<string, unknown>): Record<string, unknown>[] {
  return asArray(snapshot.active_ai_sessions).map(asRecord);
}

async function collectPerfSmoke(): Promise<PerfSmokeReport> {
  const client = new DaemonClient();
  try {
    await client.connect();
    await client.request("dashboard.snapshot", {});
    const snapshot = asRecord(await client.request("dashboard.snapshot", {}));
    const focusState = asRecord(snapshot.focus_state);
    const currentWindowId = numberValue(focusState.current_window_id);
    const localWindow = dashboardWindows(snapshot).find((windowData) => {
      const windowId = numberValue(windowData.id || windowData.window_id);
      const mode = stringValue(windowData.execution_mode).toLowerCase();
      return windowId > 0 && (windowId === currentWindowId || currentWindowId <= 0) && mode !== "ssh";
    });
    const focusedWorkspace = dashboardWorkspaces(snapshot).find((workspace) => boolValue(workspace.focused))
      || dashboardWorkspaces(snapshot).find((workspace) => stringValue(workspace.name) !== "");
    const remoteSession = dashboardSessions(snapshot).find((session) => {
      const target = asRecord(session.focus_target);
      return boolValue(session.is_remote_herdr)
        && stringValue(target.method) === "herdr.remote.pane.focus";
    });

    const checks: SmokeCheck[] = [];
    checks.push(await measure("window.focus_fast.local", 100, async () => {
      if (!localWindow) {
        return { success: true, skipped: true, reason: "no_local_window_target" };
      }
      const result = asRecord(await client.request("window.focus_fast", {
        window_id: numberValue(localWindow.id || localWindow.window_id),
        project_name: stringValue(localWindow.project),
        target_variant: stringValue(localWindow.execution_mode) || "local",
        connection_key: stringValue(localWindow.connection_key),
      }));
      return { success: boolValue(result.success), reason: stringValue(result.reason) || "ok" };
    }));

    checks.push(await measure("workspace.focus_fast.local", 100, async () => {
      if (!focusedWorkspace) {
        return { success: true, skipped: true, reason: "no_workspace_target" };
      }
      const workspaceName = stringValue(focusedWorkspace.name || focusedWorkspace.num || focusedWorkspace.number);
      if (!workspaceName) {
        return { success: true, skipped: true, reason: "workspace_missing_name" };
      }
      const result = asRecord(await client.request("workspace.focus_fast", { workspace: workspaceName }));
      return { success: boolValue(result.success), reason: stringValue(result.reason) || "ok" };
    }));

    checks.push(await measure("dashboard.snapshot.warm", 200, async () => {
      const result = asRecord(await client.request("dashboard.snapshot", {}));
      return {
        success: stringValue(result.schema_version) === "i3pm.dashboard.v2",
        reason: stringValue(result.schema_version) || "missing_schema",
      };
    }));

    checks.push(await measure("herdr.snapshot.warm", 300, async () => {
      const result = asRecord(await client.request("herdr.snapshot", {}));
      return { success: Array.isArray(result.sessions), reason: "ok" };
    }));

    checks.push(await measure("herdr.remote.pane.focus", 500, async () => {
      if (!remoteSession) {
        return { success: true, skipped: true, reason: "no_remote_herdr_target" };
      }
      const target = asRecord(remoteSession.focus_target);
      const params = asRecord(target.params);
      const result = asRecord(await client.request("herdr.remote.pane.focus", params));
      return { success: boolValue(result.success), reason: stringValue(result.reason) || "ok" };
    }));

    return {
      timestamp: new Date().toISOString(),
      overall_status: checks.some((check) => check.status === "fail") ? "fail" : "pass",
      checks,
    };
  } finally {
    client.disconnect();
  }
}

function printReport(report: PerfSmokeReport): void {
  console.log(`${bold("Perf Smoke")} ${report.overall_status === "pass" ? green("PASS") : red("FAIL")}`);
  console.log(dim(report.timestamp));
  console.log("");
  for (const check of report.checks) {
    const marker = check.status === "pass" ? green("pass") : check.status === "skip" ? yellow("skip") : red("fail");
    console.log(
      `  ${marker} ${check.name} ${check.duration_ms}ms ${dim(`budget ${check.budget_ms}ms ${check.reason}`)}`,
    );
  }
}

export async function perfCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
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

  const report = await collectPerfSmoke();
  if (parsed.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printReport(report);
  }
  return report.overall_status === "pass" ? 0 : 1;
}
