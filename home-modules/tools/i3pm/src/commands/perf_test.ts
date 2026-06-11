import { assertEquals } from "jsr:@std/assert";
import { buildPerfSmokeReport, type SmokeCheck } from "./perf.ts";

function check(status: SmokeCheck["status"]): SmokeCheck {
  return {
    name: `check.${status}`,
    budget_ms: 100,
    duration_ms: status === "fail" ? 125 : 10,
    status,
    reason: status,
  };
}

Deno.test("buildPerfSmokeReport exposes status and overall_status aliases", () => {
  const report = buildPerfSmokeReport([check("pass"), check("skip")], "2026-06-11T00:00:00.000Z");

  assertEquals(report.status, "pass");
  assertEquals(report.overall_status, "pass");
  assertEquals(report.timestamp, "2026-06-11T00:00:00.000Z");
});

Deno.test("buildPerfSmokeReport fails when any budget check fails", () => {
  const report = buildPerfSmokeReport([check("pass"), check("fail")], "2026-06-11T00:00:00.000Z");

  assertEquals(report.status, "fail");
  assertEquals(report.overall_status, "fail");
});
