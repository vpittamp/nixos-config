/**
 * Unit tests for registry loading and validation
 *
 * Feature: 034-create-a-feature
 */

import { assertEquals, assertRejects } from "@std/assert";
import {
  filterByScope,
  filterByWorkspace,
  findApplication,
  getApplicationNames,
  getRegistryStats,
  loadRegistry,
  RegistryError,
  validateRegistry,
} from "../../src/registry.ts";
import type { ApplicationRegistry } from "../../src/models.ts";

// Sample test registry
const sampleRegistry: ApplicationRegistry = {
  version: "1.0.0",
  applications: [
    {
      name: "vscode",
      display_name: "VS Code",
      command: "code",
      parameters: "$PROJECT_DIR",
      scope: "scoped",
      expected_class: "Code",
      preferred_workspace: 1,
      icon: "vscode",
      nix_package: "pkgs.vscode",
      multi_instance: true,
      fallback_behavior: "skip",
    },
    {
      name: "firefox",
      display_name: "Firefox",
      command: "firefox",
      scope: "global",
      expected_class: "firefox",
      preferred_workspace: 2,
      icon: "firefox",
      nix_package: "pkgs.firefox",
      multi_instance: false,
    },
    {
      name: "ghostty",
      display_name: "Ghostty Terminal",
      command: "ghostty",
      parameters: "-e sesh $SESSION_NAME",
      scope: "scoped",
      expected_class: "ghostty",
      preferred_workspace: 1,
      icon: "terminal",
    },
  ],
};

Deno.test("loadRegistry - loads valid registry from file", async () => {
  const path = "tests/fixtures/sample-registry.json";
  const registry = await loadRegistry(path);

  assertEquals(registry.version, "1.0.0");
  assertEquals(registry.applications.length, 4);
  assertEquals(registry.applications[0].name, "vscode");
});

Deno.test("loadRegistry - throws on missing file", async () => {
  await assertRejects(
    async () => await loadRegistry("/nonexistent/registry.json"),
    RegistryError,
    "Registry file not found",
  );
});

Deno.test("findApplication - finds application by name", () => {
  const app = findApplication(sampleRegistry, "vscode");

  assertEquals(app?.name, "vscode");
  assertEquals(app?.display_name, "VS Code");
  assertEquals(app?.command, "code");
});

Deno.test("findApplication - returns null for unknown application", () => {
  const app = findApplication(sampleRegistry, "nonexistent");

  assertEquals(app, null);
});

Deno.test("filterByScope - filters scoped applications", () => {
  const scoped = filterByScope(sampleRegistry, "scoped");

  assertEquals(scoped.length, 2);
  assertEquals(scoped[0].name, "vscode");
  assertEquals(scoped[1].name, "ghostty");
});

Deno.test("filterByScope - filters global applications", () => {
  const global = filterByScope(sampleRegistry, "global");

  assertEquals(global.length, 1);
  assertEquals(global[0].name, "firefox");
});

Deno.test("filterByScope - returns all when scope is 'all'", () => {
  const all = filterByScope(sampleRegistry, "all");

  assertEquals(all.length, 3);
});

Deno.test("filterByWorkspace - filters by workspace number", () => {
  const ws1 = filterByWorkspace(sampleRegistry, 1);

  assertEquals(ws1.length, 2);
  assertEquals(ws1[0].name, "vscode");
  assertEquals(ws1[1].name, "ghostty");
});

Deno.test("filterByWorkspace - returns empty for unused workspace", () => {
  const ws9 = filterByWorkspace(sampleRegistry, 9);

  assertEquals(ws9.length, 0);
});

Deno.test("getApplicationNames - returns all application names", () => {
  const names = getApplicationNames(sampleRegistry);

  assertEquals(names, ["vscode", "firefox", "ghostty"]);
});

Deno.test("validateRegistry - validates version format", () => {
  const invalidVersion: ApplicationRegistry = {
    version: "invalid",
    applications: [],
  };

  const errors = validateRegistry(invalidVersion);

  assertEquals(errors.length > 0, true);
  assertEquals(
    errors[0].includes("Invalid version format"),
    true,
  );
});

Deno.test("validateRegistry - validates application names are kebab-case", () => {
  const invalidName: ApplicationRegistry = {
    version: "1.0.0",
    applications: [{
      name: "Invalid_Name",
      display_name: "Test",
      command: "test",
    }],
  };

  const errors = validateRegistry(invalidName);

  assertEquals(errors.length > 0, true);
  assertEquals(errors[0].includes("Invalid application name"), true);
});

Deno.test("validateRegistry - detects unsafe parameters", () => {
  const unsafeParams: ApplicationRegistry = {
    version: "1.0.0",
    applications: [{
      name: "malicious",
      display_name: "Malicious",
      command: "test",
      parameters: "; rm -rf ~",
    }],
  };

  const errors = validateRegistry(unsafeParams);

  assertEquals(errors.length > 0, true);
  assertEquals(errors[0].includes("shell metacharacters"), true);
});

Deno.test("validateRegistry - detects out-of-range workspace", () => {
  const invalidWorkspace: ApplicationRegistry = {
    version: "1.0.0",
    applications: [{
      name: "test",
      display_name: "Test",
      command: "test",
      preferred_workspace: 10,
    }],
  };

  const errors = validateRegistry(invalidWorkspace);

  assertEquals(errors.length > 0, true);
  assertEquals(errors[0].includes("Invalid workspace"), true);
});

Deno.test("validateRegistry - warns scoped apps without expected_class", () => {
  const missingClass: ApplicationRegistry = {
    version: "1.0.0",
    applications: [{
      name: "test",
      display_name: "Test",
      command: "test",
      scope: "scoped",
    }],
  };

  const errors = validateRegistry(missingClass);

  assertEquals(errors.length > 0, true);
  assertEquals(errors[0].includes("should have expected_class"), true);
});

Deno.test("validateRegistry - passes valid registry", () => {
  const errors = validateRegistry(sampleRegistry);

  assertEquals(errors.length, 0);
});

Deno.test("getRegistryStats - calculates statistics", () => {
  const stats = getRegistryStats(sampleRegistry);

  assertEquals(stats.total, 3);
  assertEquals(stats.scoped, 2);
  assertEquals(stats.global, 1);
  assertEquals(stats.by_workspace[1], 2);
  assertEquals(stats.by_workspace[2], 1);
});

Deno.test("getRegistryStats - handles empty registry", () => {
  const emptyRegistry: ApplicationRegistry = {
    version: "1.0.0",
    applications: [],
  };

  const stats = getRegistryStats(emptyRegistry);

  assertEquals(stats.total, 0);
  assertEquals(stats.scoped, 0);
  assertEquals(stats.global, 0);
});
