---
description: Create a managed i3pm worktree from a task summary and switch into it
---

You are helping the user create a new managed worktree in this NixOS/i3pm environment.

## Workflow

1. Treat the user's command arguments, if any, as the initial task summary.
2. Infer the target repo in this order:
   - the current managed repo from the cwd
   - the active `i3pm` context
   - ask the user only if the repo is still ambiguous
3. Propose a meaningful branch name by running:
   - `i3pm worktree suggest-name "<task summary>" --repo <account/repo> --json`
4. Show the proposed branch name to the user and get explicit confirmation before creating anything.
5. Determine the base branch:
   - prefer the repo default branch from `i3pm`
   - otherwise use `main`
6. After confirmation, run:
   - `i3pm worktree create <branch> --repo <account/repo> --from <base>`
   - `i3pm discover --quiet`
   - `i3pm worktree switch <account/repo:branch>`
7. Report:
   - the created qualified name
   - the created path
   - the base branch used
   - that discovery was refreshed
   - that the active context switched locally

## Rules

- Do not invent branch names manually when `i3pm worktree suggest-name` is available.
- Do not create the worktree until the user confirms the proposed branch name.
- If `i3pm worktree create` succeeds but discovery or switching fails, clearly state that the repo state changed and show the exact recovery command.
- Do not open a shell or SSH variant automatically unless the user asks.
