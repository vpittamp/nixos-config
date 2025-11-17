/**
 * Tests for worktree list command JSON output schema
 * Feature 079: Preview Pane User Experience - US6 - T044
 */

import { assertEquals, assertThrows } from "jsr:@std/assert";
import { z } from "zod";
import { WorktreeListItemSchema } from "../../home-modules/tools/i3pm/src/commands/worktree/list.ts";

// Test valid worktree list item schema (T044)
Deno.test("WorktreeListItemSchema accepts valid worktree data", () => {
  const validItem = {
    name: "079-preview-pane-user-experience",
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      ahead_count: 0,
      behind_count: 0,
      has_untracked: false,
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  const result = WorktreeListItemSchema.parse(validItem);
  assertEquals(result.name, "079-preview-pane-user-experience");
  assertEquals(result.branch, "079-preview-pane-user-experience");
  assertEquals(result.git_status.is_clean, true);
  assertEquals(result.git_status.ahead_count, 0);
  assertEquals(result.git_status.behind_count, 0);
  assertEquals(result.git_status.has_untracked, false);
});

Deno.test("WorktreeListItemSchema accepts dirty worktree with ahead/behind counts", () => {
  const dirtyItem = {
    name: "078-eww-preview-improvement",
    display_name: "Eww Preview",
    branch: "078-eww-preview-improvement",
    path: "/home/user/projects/078-eww-preview-improvement",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: false,
      ahead_count: 3,
      behind_count: 1,
      has_untracked: true,
    },
    created_at: "2025-11-15T08:00:00Z",
    updated_at: "2025-11-16T14:30:00Z",
    icon: "🔧",
  };

  const result = WorktreeListItemSchema.parse(dirtyItem);
  assertEquals(result.git_status.is_clean, false);
  assertEquals(result.git_status.ahead_count, 3);
  assertEquals(result.git_status.behind_count, 1);
  assertEquals(result.git_status.has_untracked, true);
});

Deno.test("WorktreeListItemSchema rejects missing name field", () => {
  const invalidItem = {
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      ahead_count: 0,
      behind_count: 0,
      has_untracked: false,
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  assertThrows(() => {
    WorktreeListItemSchema.parse(invalidItem);
  }, z.ZodError);
});

Deno.test("WorktreeListItemSchema rejects empty name field", () => {
  const invalidItem = {
    name: "",
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      ahead_count: 0,
      behind_count: 0,
      has_untracked: false,
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  assertThrows(() => {
    WorktreeListItemSchema.parse(invalidItem);
  }, z.ZodError);
});

Deno.test("WorktreeListItemSchema rejects missing git_status fields", () => {
  const invalidItem = {
    name: "079-preview-pane-user-experience",
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      // Missing ahead_count, behind_count, has_untracked
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  assertThrows(() => {
    WorktreeListItemSchema.parse(invalidItem);
  }, z.ZodError);
});

Deno.test("WorktreeListItemSchema rejects negative ahead_count", () => {
  const invalidItem = {
    name: "079-preview-pane-user-experience",
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      ahead_count: -1,
      behind_count: 0,
      has_untracked: false,
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  assertThrows(() => {
    WorktreeListItemSchema.parse(invalidItem);
  }, z.ZodError);
});

Deno.test("WorktreeListItemSchema rejects non-integer ahead_count", () => {
  const invalidItem = {
    name: "079-preview-pane-user-experience",
    display_name: "Preview Pane UX",
    branch: "079-preview-pane-user-experience",
    path: "/home/user/projects/079-preview-pane-user-experience",
    parent_repo: "/home/user/projects/nixos-config",
    git_status: {
      is_clean: true,
      ahead_count: 1.5,
      behind_count: 0,
      has_untracked: false,
    },
    created_at: "2025-11-16T10:00:00Z",
    updated_at: "2025-11-16T12:00:00Z",
    icon: "🌿",
  };

  assertThrows(() => {
    WorktreeListItemSchema.parse(invalidItem);
  }, z.ZodError);
});

Deno.test("WorktreeListItemSchema validates array of worktrees", () => {
  const worktrees = [
    {
      name: "079-preview-pane-user-experience",
      display_name: "Preview Pane UX",
      branch: "079-preview-pane-user-experience",
      path: "/home/user/projects/079-preview-pane-user-experience",
      parent_repo: "/home/user/projects/nixos-config",
      git_status: {
        is_clean: true,
        ahead_count: 0,
        behind_count: 0,
        has_untracked: false,
      },
      created_at: "2025-11-16T10:00:00Z",
      updated_at: "2025-11-16T12:00:00Z",
      icon: "🌿",
    },
    {
      name: "078-eww-preview-improvement",
      display_name: "Eww Preview",
      branch: "078-eww-preview-improvement",
      path: "/home/user/projects/078-eww-preview-improvement",
      parent_repo: "/home/user/projects/nixos-config",
      git_status: {
        is_clean: false,
        ahead_count: 2,
        behind_count: 0,
        has_untracked: true,
      },
      created_at: "2025-11-15T08:00:00Z",
      updated_at: "2025-11-16T14:30:00Z",
      icon: "🔧",
    },
  ];

  const arraySchema = z.array(WorktreeListItemSchema);
  const result = arraySchema.parse(worktrees);
  assertEquals(result.length, 2);
  assertEquals(result[0].name, "079-preview-pane-user-experience");
  assertEquals(result[1].name, "078-eww-preview-improvement");
});
