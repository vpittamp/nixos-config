export type WorktreeMutationAction = "create" | "remove" | "rename";

type WorktreeMutationResultBase = {
  success: boolean;
  action: WorktreeMutationAction;
  repo: string;
  branch: string;
  qualified_name: string;
};

export type WorktreeCreateResult = WorktreeMutationResultBase & {
  action: "create";
  base_branch: string;
  path: string;
  used_gtr: boolean;
};

export type WorktreeRemoveResult = WorktreeMutationResultBase & {
  action: "remove";
  force: boolean;
  host_profile_removed: boolean;
  context_cleared: boolean;
  used_gtr: boolean;
};

export type WorktreeRenameResult = WorktreeMutationResultBase & {
  action: "rename";
  previous_branch: string;
  previous_qualified_name: string;
  force: boolean;
  host_profile_migrated: boolean;
  context_updated: boolean;
  used_gtr: boolean;
};

export type WorktreeMutationErrorResult = {
  success: false;
  action: WorktreeMutationAction;
  error: string;
};

export function buildWorktreeCreateResult(params: {
  repo: string;
  branch: string;
  baseBranch: string;
  path: string;
  usedGtr: boolean;
}): WorktreeCreateResult {
  return {
    success: true,
    action: "create",
    repo: params.repo,
    branch: params.branch,
    qualified_name: `${params.repo}:${params.branch}`,
    base_branch: params.baseBranch,
    path: params.path,
    used_gtr: params.usedGtr,
  };
}

export function buildWorktreeRemoveResult(params: {
  repo: string;
  branch: string;
  force: boolean;
  hostProfileRemoved: boolean;
  contextCleared: boolean;
  usedGtr: boolean;
}): WorktreeRemoveResult {
  return {
    success: true,
    action: "remove",
    repo: params.repo,
    branch: params.branch,
    qualified_name: `${params.repo}:${params.branch}`,
    force: params.force,
    host_profile_removed: params.hostProfileRemoved,
    context_cleared: params.contextCleared,
    used_gtr: params.usedGtr,
  };
}

export function buildWorktreeRenameResult(params: {
  repo: string;
  previousBranch: string;
  newBranch: string;
  force: boolean;
  hostProfileMigrated: boolean;
  contextUpdated: boolean;
  usedGtr: boolean;
}): WorktreeRenameResult {
  return {
    success: true,
    action: "rename",
    repo: params.repo,
    branch: params.newBranch,
    qualified_name: `${params.repo}:${params.newBranch}`,
    previous_branch: params.previousBranch,
    previous_qualified_name: `${params.repo}:${params.previousBranch}`,
    force: params.force,
    host_profile_migrated: params.hostProfileMigrated,
    context_updated: params.contextUpdated,
    used_gtr: params.usedGtr,
  };
}

export function buildWorktreeMutationErrorResult(
  action: WorktreeMutationAction,
  error: string,
): WorktreeMutationErrorResult {
  return {
    success: false,
    action,
    error,
  };
}
