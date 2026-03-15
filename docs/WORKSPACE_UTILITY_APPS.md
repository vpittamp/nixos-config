# Workspace Utility Apps

Last updated: 2026-03-15

## Purpose

This document defines the architecture for launcher-visible utility apps that
should own a dedicated workspace.

Examples:
- `worktree-manager`

These apps are:
- launchable from Walker/Elephant through the normal i3pm app registry
- global rather than project-scoped
- intentionally assigned to a dedicated workspace
- suitable for management hubs, dashboards, and control-center style tools

## Why This Category Exists

Some utility apps are not ephemeral popups.

They are better modeled as stable destinations:
- project/worktree managers
- system dashboards
- runtime control centers
- standalone QuickShell apps that should be revisitable

If these apps are modeled as non-owning floating utilities, they inherit the
current workspace and compete with the user’s active tiled layout. That is the
wrong model for a management surface.

The correct model is:
- keep them in `application-registry.json` so they appear in the launcher
- give them a `preferred_workspace`
- keep them `global`
- optionally keep their own internal window styling, but let the workspace model
  stay explicit and deterministic

## Source Of Truth

The category is declared in:
- `home-modules/desktop/app-registry-data.nix`

The reusable helper is:
- `mkWorkspaceUtilityApp`

The exported partition is:
- `workspaceUtilityApplications`

## Required Rules

Use `mkWorkspaceUtilityApp` for this category.

Workspace utility apps must:
- use `scope = "global"`
- set `preferred_workspace`
- omit `scratchpad = true`
- set a launcher command that exists on `PATH`
- provide an icon
- provide either a stable `expected_class`, `expected_title_contains`, or both

Recommended defaults from the helper:
- `multi_instance = false`
- `fallback_behavior = "skip"`

## Registration Pattern

Add new entries under `workspaceUtilityApplications` in:
- `home-modules/desktop/app-registry-data.nix`

Example:

```nix
(mkWorkspaceUtilityApp {
  name = "example-control-center";
  display_name = "Example Control Center";
  command = "open-example-control-center";
  parameters = "";
  expected_class = "example-control-center";
  expected_title_contains = "Example Control Center";
  preferred_workspace = 23;
  preferred_monitor_role = "primary";
  icon = iconPath "example-control-center.svg";
  nix_package = "pkgs.example";
  description = "Workspace-owned utility app";
})
```

## QuickShell Guidance

For standalone QuickShell apps in this category:
- use a dedicated launcher command
- keep the QuickShell config in its own Home Manager module
- let the registry own workspace placement
- do not treat `FloatingWindow` as equivalent to sway floating mode
- make launcher reopen behavior focus the existing window when the app is already running

The `worktree-manager` app is the reference implementation for this pattern.

## When Not To Use This Category

Do not use `mkWorkspaceUtilityApp` for:
- ordinary editors, browsers, and terminals
- project-scoped apps
- scratchpad terminals
- ephemeral search pickers or transient popups

Use:
- `workspaceOwningApplications` for normal workspace-targeted apps
- `floatingUtilityApplications` for transient non-owning tools
- scratchpad-specific definitions for context-keyed scratchpad surfaces
