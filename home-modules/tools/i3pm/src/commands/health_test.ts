import { assertEquals } from "jsr:@std/assert";
import { buildHealthReport, type HealthReport, retiredAiSessionUnitIssues } from "./health.ts";

function baseReport(overallStatus: HealthReport["overall_status"]) {
  return {
    timestamp: "2026-06-11T00:00:00.000Z",
    overall_status: overallStatus,
    core_issues: overallStatus === "fail" ? ["core failure"] : [],
    optional_issues: overallStatus === "warn" ? ["optional warning"] : [],
    core_units: [],
    failed_user_units: [],
    system_generation: "",
    home_manager_generation: "",
    home_manager_profile_generation: "",
    daemon_socket: {
      path: "",
      exists: true,
    },
    daemon_contract: null,
    quickshell: {
      shell_qml: {
        current_path: "",
        expected_path: "",
        matches: true,
      },
      service_unit: {
        current_path: "",
        expected_path: "",
        matches: true,
      },
    },
    dashboard: null,
    herdr: null,
    herdr_remotes: [],
    mcp_browser_runtime: null,
  };
}

Deno.test("buildHealthReport exposes status and overall_status aliases", () => {
  const report = buildHealthReport(baseReport("ok"));

  assertEquals(report.status, "ok");
  assertEquals(report.overall_status, "ok");
  assertEquals(report.timestamp, "2026-06-11T00:00:00.000Z");
});

Deno.test("buildHealthReport preserves warning and failure status aliases", () => {
  const warnReport = buildHealthReport(baseReport("warn"));
  const failReport = buildHealthReport(baseReport("fail"));

  assertEquals(warnReport.status, "warn");
  assertEquals(warnReport.overall_status, "warn");
  assertEquals(failReport.status, "fail");
  assertEquals(failReport.overall_status, "fail");
});

Deno.test("retiredAiSessionUnitIssues allows removed otel monitor unit", () => {
  assertEquals(
    retiredAiSessionUnitIssues([{
      name: "otel-ai-monitor.service",
      load_state: "not-found",
      active_state: "inactive",
      unit_file_state: "",
      fragment_path: "",
    }]),
    [],
  );
});

Deno.test("retiredAiSessionUnitIssues flags installed or active otel monitor unit", () => {
  const issues = retiredAiSessionUnitIssues([
    {
      name: "otel-ai-monitor.service",
      load_state: "loaded",
      active_state: "inactive",
      unit_file_state: "enabled",
      fragment_path: "/home/user/.config/systemd/user/otel-ai-monitor.service",
    },
    {
      name: "otel-ai-monitor.service",
      load_state: "not-found",
      active_state: "active",
      unit_file_state: "",
      fragment_path: "",
    },
  ]);

  assertEquals(issues.length, 2);
  assertEquals(issues[0].includes("retired AI session service otel-ai-monitor.service"), true);
  assertEquals(issues[0].includes("Herdr owns AI session UI state"), true);
});
