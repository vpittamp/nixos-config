---
name: create-worktree
description: Use this skill when the user wants to create a new worktree from a task summary in the managed i3pm repo layout. It suggests a meaningful branch name, creates the worktree, refreshes discovery, and switches local context to the new worktree.
---

# Create Worktree

Use this skill when the user wants to create a new worktree from a task summary in the managed i3pm repo layout.

## Goal

Create a meaningful branch name, create the worktree through `i3pm`, refresh discovery, and switch the active local context to the new worktree.

## Workflow

1. Treat the user's request text as the task summary unless they provide a better summary later.
2. Infer the repo in this order:
   - current managed repo from the cwd
   - active `i3pm` context
   - ask the user only if the repo is still ambiguous
3. Propose a branch name by running:
   - `i3pm worktree suggest-name "<task summary>" --repo <account/repo> --json`
4. Show the proposed branch name to the user and wait for confirmation before mutating anything.
5. Resolve the base branch:
   - prefer the repo default branch from `i3pm`
   - fallback to `main`
6. After confirmation, run:
   - `i3pm worktree create <branch> --repo <account/repo> --from <base>`
   - `i3pm discover --quiet`
   - `i3pm worktree switch <account/repo:branch>`
7. Report:
   - the created qualified name
   - the created path
   - the base branch used
   - whether discovery refresh succeeded
   - whether local context switched successfully

## Rules

- Do not invent a branch name manually when `i3pm worktree suggest-name` is available.
- Do not create the worktree before the user confirms the proposed branch name.
- If creation succeeds but discovery or switching fails, clearly state that repo state changed and give the exact recovery command.
- Do not open shells or switch to SSH automatically unless the user asks.
