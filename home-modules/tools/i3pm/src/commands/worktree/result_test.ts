import {
  buildWorktreeCreateResult,
  buildWorktreeMutationErrorResult,
  buildWorktreeRemoveResult,
  buildWorktreeRenameResult,
} from "./result.ts";

Deno.test("buildWorktreeCreateResult returns stable UI payload", () => {
  const result = buildWorktreeCreateResult({
    repo: "vpittamp/nixos-config",
    branch: "feature/test",
    baseBranch: "main",
    path: "/home/vpittamp/repos/vpittamp/nixos-config/feature/test",
    usedGtr: true,
  });

  if (!result.success) {
    throw new Error("expected success result");
  }

  if (result.action !== "create") {
    throw new Error(`unexpected action: ${result.action}`);
  }

  if (result.qualified_name !== "vpittamp/nixos-config:feature/test") {
    throw new Error(`unexpected qualified_name: ${result.qualified_name}`);
  }

  if (result.base_branch !== "main") {
    throw new Error(`unexpected base_branch: ${result.base_branch}`);
  }
});

Deno.test("buildWorktreeRemoveResult includes cleanup flags", () => {
  const result = buildWorktreeRemoveResult({
    repo: "vpittamp/nixos-config",
    branch: "feature/test",
    force: true,
    remoteProfileRemoved: true,
    contextCleared: false,
    usedGtr: false,
  });

  if (!result.force || !result.remote_profile_removed) {
    throw new Error("expected cleanup flags in remove result");
  }

  if (result.context_cleared) {
    throw new Error("expected context_cleared to remain false");
  }
});

Deno.test("buildWorktreeRenameResult includes previous identity", () => {
  const result = buildWorktreeRenameResult({
    repo: "vpittamp/nixos-config",
    previousBranch: "feature/old",
    newBranch: "feature/new",
    force: false,
    remoteProfileMigrated: true,
    contextUpdated: true,
    usedGtr: true,
  });

  if (result.previous_qualified_name !== "vpittamp/nixos-config:feature/old") {
    throw new Error(`unexpected previous_qualified_name: ${result.previous_qualified_name}`);
  }

  if (!result.context_updated || !result.remote_profile_migrated) {
    throw new Error("expected rename flags");
  }
});

Deno.test("buildWorktreeMutationErrorResult returns uniform failure payload", () => {
  const result = buildWorktreeMutationErrorResult("remove", "Cannot remove main worktree");

  if (result.success) {
    throw new Error("expected failure result");
  }

  if (result.action !== "remove" || result.error !== "Cannot remove main worktree") {
    throw new Error("unexpected failure payload");
  }
});
