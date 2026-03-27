import { assertEquals, assertThrows } from "jsr:@std/assert";
import { routeWindowsCommandArgs } from "./windows.ts";
import { WindowStateSchema } from "../validation.ts";

Deno.test("routeWindowsCommandArgs preserves hidden subcommand flags", () => {
  assertEquals(
    routeWindowsCommandArgs(["hidden", "--json", "--project", "vpittamp/nixos-config:main"]),
    {
      subcommand: "hidden",
      args: ["--json", "--project", "vpittamp/nixos-config:main"],
    },
  );
});

Deno.test("routeWindowsCommandArgs defaults to show without consuming flags", () => {
  assertEquals(
    routeWindowsCommandArgs(["--json", "--project", "vpittamp/nixos-config:main"]),
    {
      subcommand: "show",
      args: ["--json", "--project", "vpittamp/nixos-config:main"],
    },
  );
});

Deno.test("WindowStateSchema accepts canonical host context keys", () => {
  const parsed = WindowStateSchema.parse({
    id: 267,
    pid: 1234,
    app_id: "com.mitchellh.ghostty",
    class: "com.mitchellh.ghostty",
    instance: null,
    title: "nixos-config",
    workspace: "1",
    output: "eDP-1",
    marks: ["project:vpittamp/nixos-config:main"],
    focused: true,
    hidden: false,
    context_key: "vpittamp/nixos-config:main::host::thinkpad",
    floating: false,
    fullscreen: false,
    geometry: {
      x: 0,
      y: 0,
      width: 1200,
      height: 800,
    },
    classification: "scoped",
    project: "vpittamp/nixos-config:main",
  });

  assertEquals(parsed.context_key, "vpittamp/nixos-config:main::host::thinkpad");
});

Deno.test("WindowStateSchema accepts empty context_key for global windows", () => {
  const parsed = WindowStateSchema.parse({
    id: 99,
    pid: 1234,
    app_id: "org.mozilla.firefox",
    class: "org.mozilla.firefox",
    instance: null,
    title: "Firefox",
    workspace: "3",
    output: "DP-1",
    marks: [],
    focused: false,
    hidden: false,
    context_key: "",
    floating: false,
    fullscreen: false,
    geometry: {
      x: 0,
      y: 0,
      width: 1200,
      height: 800,
    },
    classification: "global",
    project: "",
  });

  assertEquals(parsed.context_key, "");
});

Deno.test("WindowStateSchema rejects windows that omit context_key", () => {
  assertThrows(() =>
    WindowStateSchema.parse({
      id: 267,
      pid: 1234,
      app_id: "com.mitchellh.ghostty",
      class: "com.mitchellh.ghostty",
      instance: null,
      title: "nixos-config",
      workspace: "1",
      output: "eDP-1",
      marks: ["project:vpittamp/nixos-config:main"],
      focused: true,
      hidden: false,
      floating: false,
      fullscreen: false,
      geometry: {
        x: 0,
        y: 0,
        width: 1200,
        height: 800,
      },
      classification: "scoped",
      project: "vpittamp/nixos-config:main",
    })
  );
});

Deno.test("WindowStateSchema rejects legacy transport-shaped scoped context keys", () => {
  assertThrows(() =>
    WindowStateSchema.parse({
      id: 267,
      pid: 1234,
      app_id: "com.mitchellh.ghostty",
      class: "com.mitchellh.ghostty",
      instance: null,
      title: "nixos-config",
      workspace: "1",
      output: "eDP-1",
      marks: ["project:vpittamp/nixos-config:main"],
      focused: true,
      hidden: false,
      context_key: "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
      floating: false,
      fullscreen: false,
      geometry: {
        x: 0,
        y: 0,
        width: 1200,
        height: 800,
      },
      classification: "scoped",
      project: "vpittamp/nixos-config:main",
    })
  );
});

Deno.test("WindowStateSchema rejects synthetic context keys for global windows", () => {
  assertThrows(() =>
    WindowStateSchema.parse({
      id: 99,
      pid: 1234,
      app_id: "org.mozilla.firefox",
      class: "org.mozilla.firefox",
      instance: null,
      title: "Firefox",
      workspace: "3",
      output: "DP-1",
      marks: [],
      focused: false,
      hidden: false,
      context_key: "global::host::ryzen",
      floating: false,
      fullscreen: false,
      geometry: {
        x: 0,
        y: 0,
        width: 1200,
        height: 800,
      },
      classification: "global",
      project: "",
    })
  );
});
