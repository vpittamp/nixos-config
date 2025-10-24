/**
 * Unit tests for variable substitution
 *
 * Feature: 034-create-a-feature
 */

import { assertEquals, assertThrows } from "@std/assert";
import {
  applyFallback,
  buildArgumentArray,
  checkParameterSafety,
  createVariableContext,
  resolveParameters,
  substituteVariables,
  VariableError,
} from "../../src/variables.ts";

Deno.test("createVariableContext - creates context from project data", () => {
  const context = createVariableContext("nixos", "/etc/nixos", 1);

  assertEquals(context.project_name, "nixos");
  assertEquals(context.project_dir, "/etc/nixos");
  assertEquals(context.session_name, "nixos");
  assertEquals(context.workspace, 1);
  assertEquals(context.user_home.length > 0, true);
});

Deno.test("createVariableContext - handles null project", () => {
  const context = createVariableContext(null, null, null);

  assertEquals(context.project_name, null);
  assertEquals(context.project_dir, null);
  assertEquals(context.session_name, null);
  assertEquals(context.workspace, null);
});

Deno.test("substituteVariables - substitutes PROJECT_DIR", () => {
  const context = createVariableContext("nixos", "/etc/nixos", 1);
  const result = substituteVariables("$PROJECT_DIR", context);

  assertEquals(result, "/etc/nixos");
});

Deno.test("substituteVariables - substitutes multiple variables", () => {
  const context = createVariableContext("stacks", "/home/user/stacks", 2);
  const result = substituteVariables(
    "--dir=$PROJECT_DIR --name=$PROJECT_NAME",
    context,
  );

  assertEquals(result, "--dir=/home/user/stacks --name=stacks");
});

Deno.test("substituteVariables - handles variables in middle of string", () => {
  const context = createVariableContext("nixos", "/etc/nixos", 1);
  const result = substituteVariables(
    "lazygit --work-tree=$PROJECT_DIR/.git",
    context,
  );

  assertEquals(result, "lazygit --work-tree=/etc/nixos/.git");
});

Deno.test("substituteVariables - handles null values", () => {
  const context = createVariableContext(null, null, null);
  const result = substituteVariables("$PROJECT_DIR", context);

  // Should remain unchanged if variable is null
  assertEquals(result, "$PROJECT_DIR");
});

Deno.test("substituteVariables - handles workspace number", () => {
  const context = createVariableContext("nixos", "/etc/nixos", 5);
  const result = substituteVariables("--workspace=$WORKSPACE", context);

  assertEquals(result, "--workspace=5");
});

Deno.test("checkParameterSafety - allows safe parameters", () => {
  assertEquals(checkParameterSafety("$PROJECT_DIR"), true);
  assertEquals(checkParameterSafety("--flag=$PROJECT_DIR"), true);
  assertEquals(checkParameterSafety("-e lazygit $PROJECT_DIR"), true);
});

Deno.test("checkParameterSafety - blocks semicolon", () => {
  assertEquals(checkParameterSafety("; rm -rf ~"), false);
});

Deno.test("checkParameterSafety - blocks pipe", () => {
  assertEquals(checkParameterSafety("| cat /etc/passwd"), false);
});

Deno.test("checkParameterSafety - blocks ampersand", () => {
  assertEquals(checkParameterSafety("& malicious"), false);
});

Deno.test("checkParameterSafety - blocks backticks", () => {
  assertEquals(checkParameterSafety("`malicious`"), false);
});

Deno.test("checkParameterSafety - blocks command substitution", () => {
  assertEquals(checkParameterSafety("$(malicious)"), false);
});

Deno.test("checkParameterSafety - blocks parameter expansion", () => {
  assertEquals(checkParameterSafety("${malicious}"), false);
});

Deno.test("buildArgumentArray - splits command and parameters", () => {
  const args = buildArgumentArray("code", "/etc/nixos");

  assertEquals(args, ["code", "/etc/nixos"]);
});

Deno.test("buildArgumentArray - handles multiple parameters", () => {
  const args = buildArgumentArray("code", "/etc/nixos --reuse-window");

  assertEquals(args, ["code", "/etc/nixos", "--reuse-window"]);
});

Deno.test("buildArgumentArray - handles empty parameters", () => {
  const args = buildArgumentArray("firefox", "");

  assertEquals(args, ["firefox"]);
});

Deno.test("buildArgumentArray - handles whitespace-only parameters", () => {
  const args = buildArgumentArray("firefox", "   ");

  assertEquals(args, ["firefox"]);
});

Deno.test("applyFallback - skip removes project variables", () => {
  const result = applyFallback("$PROJECT_DIR", "skip", "/home/user");

  assertEquals(result, "");
});

Deno.test("applyFallback - skip preserves non-project parameters", () => {
  const result = applyFallback(
    "--reuse-window $PROJECT_DIR",
    "skip",
    "/home/user",
  );

  assertEquals(result, "--reuse-window");
});

Deno.test("applyFallback - use_home substitutes HOME", () => {
  const result = applyFallback("$PROJECT_DIR", "use_home", "/home/user");

  assertEquals(result, "/home/user");
});

Deno.test("applyFallback - error returns null", () => {
  const result = applyFallback("$PROJECT_DIR", "error", "/home/user");

  assertEquals(result, null);
});

Deno.test("resolveParameters - resolves with project context", () => {
  const context = createVariableContext("nixos", "/etc/nixos", 1);
  const result = resolveParameters("$PROJECT_DIR", context, "skip");

  assertEquals(result, "/etc/nixos");
});

Deno.test("resolveParameters - applies skip fallback", () => {
  const context = createVariableContext(null, null, null);
  const result = resolveParameters("$PROJECT_DIR", context, "skip");

  assertEquals(result, "");
});

Deno.test("resolveParameters - applies use_home fallback", () => {
  const context = createVariableContext(null, null, null);
  const result = resolveParameters("$PROJECT_DIR", context, "use_home");

  assertEquals(result.includes("/home"), true);
});

Deno.test("resolveParameters - throws on error fallback", () => {
  const context = createVariableContext(null, null, null);

  assertThrows(
    () => resolveParameters("$PROJECT_DIR", context, "error"),
    VariableError,
    "No project active",
  );
});

Deno.test("resolveParameters - handles non-project variables without fallback", () => {
  const context = createVariableContext(null, null, null);
  const result = resolveParameters("--help", context, "skip");

  assertEquals(result, "--help");
});

Deno.test("substituteVariables - handles paths with spaces", () => {
  const context = createVariableContext(
    "my-project",
    "/home/user/My Projects/stacks",
    1,
  );
  const result = substituteVariables("$PROJECT_DIR", context);

  assertEquals(result, "/home/user/My Projects/stacks");
});

Deno.test("substituteVariables - handles paths with dollar signs", () => {
  const context = createVariableContext(
    "test",
    "/tmp/$dir",
    1,
  );
  const result = substituteVariables("$PROJECT_DIR", context);

  assertEquals(result, "/tmp/$dir");
});
