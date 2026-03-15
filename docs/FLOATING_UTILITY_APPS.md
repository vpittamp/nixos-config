# Floating Utility Apps

Last updated: 2026-03-15

## Purpose

This document defines the architecture for launcher-visible floating utility apps.

Examples:
- `fzf-file-search`

These apps are:
- launchable from Walker/Elephant through the normal i3pm app registry
- intentionally excluded from workspace ownership
- intentionally excluded from workspace-targeted launch registration
- expected to open in the current workspace and manage their own floating/popup behavior

## Why This Category Exists

Not every launcher-visible app should behave like a workspace-owning desktop app.

Some apps are better modeled as transient utilities:
- search pickers
- floating dashboards
- project/context switchers
- standalone QuickShell tools

If these apps are given a `preferred_workspace`, the daemon will register a pending launch for that workspace and may move or classify them like normal desktop surfaces. That is the wrong model for transient floating utilities.

The correct model is:
- keep them in `application-registry.json` so they appear in the launcher
- keep them in `.desktop` generation so desktop-app providers can find them
- omit `preferred_workspace` so launch stays on the current workspace
- mark them as `floating = true` in registry metadata for declarative intent

## Source Of Truth

The category is declared in:
- `home-modules/desktop/app-registry-data.nix`

The reusable helper is:
- `mkFloatingUtilityApp`

The exported partition is:
- `floatingUtilityApplications`

The combined launcher-visible non-owning set remains:
- `nonOwningLaunchables`

## Required Rules

Use `mkFloatingUtilityApp` for this category.

Floating utility apps must:
- use `scope = "global"`
- omit `preferred_workspace`
- omit `scratchpad = true`
- set a launcher command that exists on `PATH`
- provide an icon
- provide either a stable `expected_class`, `expected_title_contains`, or both

Recommended defaults from the helper:
- `floating = true`
- `fallback_behavior = "skip"`
- `multi_instance = false`

Override `multi_instance` only when the tool is intentionally multi-window, such as a dedicated search surface.

## Registration Pattern

Add new entries under `floatingUtilityApplications` in:
- `home-modules/desktop/app-registry-data.nix`

Example:

```nix
(mkFloatingUtilityApp {
  name = "example-floating-tool";
  display_name = "Example Floating Tool";
  command = "open-example-floating-tool";
  parameters = "";
  expected_class = "example-tool";
  expected_title_contains = "Example Floating Tool";
  icon = iconPath "example-floating-tool.svg";
  nix_package = "pkgs.example";
  description = "Short description of the floating utility";
})
```

## QuickShell Guidance

For standalone QuickShell apps in this category:
- use a dedicated launcher command, not an ad hoc shell snippet in the registry
- keep the QuickShell config in its own Home Manager module
- let the app own its own popup/floating behavior
- do not force a workspace assignment through the registry
- use daemon-backed actions for project/session/window mutations

The `fzf-file-search` app is the reference implementation for this pattern.

`worktree-manager` used to live in this category, but it now belongs in the
workspace utility category because it is a revisitable management hub rather
than an ephemeral popup.

See:
- `docs/WORKSPACE_UTILITY_APPS.md`

## Interaction With The Launcher

Walker and Elephant only see the curated desktop files generated from the app registry.

That means:
- adding a floating utility to `floatingUtilityApplications` makes it launcher-visible
- no separate `xdg.desktopEntries` module is required
- no hand-written duplicate desktop file should be added elsewhere

## When Not To Use This Category

Do not use `mkFloatingUtilityApp` for:
- normal editors, browsers, terminals, and GUI apps that should land on a preferred workspace
- project-scoped apps
- scratchpad terminals or other one-per-context daemon-managed surfaces

Use:
- `workspaceOwningApplications` for normal workspace-targeted apps
- scratchpad-specific definitions for context-keyed scratchpad surfaces
