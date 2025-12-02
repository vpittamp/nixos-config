# Research: Enhanced Worktree User Experience

**Feature**: 109-enhance-worktree-user-experience
**Date**: 2025-12-02

## Research Questions

### 1. Lazygit CLI Arguments for View-Specific Launch

**Question**: How can lazygit be launched to open directly into a specific view (status, branches, log, stash)?

**Decision**: Use positional argument after path flag: `lazygit --path <dir> <view>`

**Rationale**: Lazygit 0.40+ supports:
- `--path <path>` - Equivalent to `--work-tree=path --git-dir=path/.git`
- Positional argument: `status`, `branch`, `log`, `stash` - Opens with that panel focused
- `--filter <path>` - Filter commits by path (useful for file-specific history)

**Alternatives Considered**:
- `--git-dir` + `--work-tree` separately - More verbose, same effect
- Environment variables `GIT_DIR`/`GIT_WORK_TREE` - Issues reported with lazygit (Issue #3010)

**Source**: [Ubuntu Manpages - lazygit](https://manpages.ubuntu.com/manpages/questing/man1/lazygit.1.html)

### 2. Best Practices for Worktree Management UI

**Question**: What patterns do best-in-class worktree tools use for zero-friction workflows?

**Decision**: Adopt patterns from workmux and tmux-sessionizer:
- One-command workflows (create worktree + open environment)
- Parallel instances per worktree (not shared state)
- Status-at-a-glance indicators (dirty, sync, stale)
- Keyboard-first navigation with optional mouse support

**Rationale**: Research revealed three tier-1 tools:

1. **Workmux** (GitHub: raine/workmux)
   - One worktree = one tmux window
   - `workmux add <branch>` creates worktree + tmux window
   - `workmux merge` cleans up everything in one command
   - Configuration as code (`.workmux.yaml`)
   - AI agent integration with parallel instances

2. **Tmux-Sessionizer** (GitHub: jrmoulton/tmux-sessionizer)
   - Fuzzy-find repos, auto-open worktrees as tmux windows
   - Keybinding integration: `bind C-o display-popup -E "tms"`
   - Auto-generate missing worktree windows

3. **Git-Worktree-Switcher** (GitHub: yankeexe/git-worktree-switcher)
   - Tab completion for worktree switching
   - `wt` command for instant directory change
   - No new shell instance on switch

**Alternatives Considered**:
- Manual git worktree commands - Too many steps
- Single-instance shared state - Conflicts in parallel development

**Sources**:
- [Workmux](https://github.com/raine/workmux)
- [Tmux-Sessionizer](https://github.com/jrmoulton/tmux-sessionizer)
- [Git-Worktree-Switcher](https://github.com/yankeexe/git-worktree-switcher)

### 3. Lazygit Worktree Native Features

**Question**: What worktree-specific features does lazygit provide natively?

**Decision**: Leverage lazygit's built-in worktree panel and keybindings:
- `w` in branches view - Create worktree from selected branch
- `n` in worktree panel - Create new worktree
- `Space` - Open/enter selected worktree
- `d` - Detach worktree from branch
- `Shift+Q` - Exit and change directory to selected worktree

**Rationale**: Lazygit has had built-in worktree support since the feature was merged to master. The worktree panel provides:
- List of all worktrees
- Create/delete operations
- Switch between worktrees
- Directory navigation on exit

Our integration should complement these features, not duplicate them. The Eww panel provides:
- Status visibility without opening lazygit
- Keyboard shortcuts from anywhere (not just inside lazygit)
- Integration with i3pm project context

**Alternatives Considered**:
- Reimplement worktree management outside lazygit - Duplicates functionality
- Only use lazygit for everything - Loses i3pm context integration

**Source**: [Lazygit Worktree UX Discussion](https://github.com/jesseduffield/lazygit/discussions/2803)

### 4. Parallel Development Workflow Patterns

**Question**: What is the optimal workflow for managing multiple parallel development streams?

**Decision**: Support "one worktree per branch" pattern as primary workflow:
- 63% of lazygit users prefer this pattern
- Each worktree is an independent development context
- No stashing or WIP commits needed when switching

**Rationale**: Research from lazygit discussion poll:
- 63% - Create worktree for every branch
- 31% - Maintain small reusable worktree set
- 4% - Other approaches

Our target users (power developers using AI for parallel development) align with the 63% pattern.

**Workflow Implementation**:
1. Create worktree for new feature branch
2. Switch projects in i3pm (context switches automatically)
3. Work in isolated environment
4. Use lazygit for git operations within worktree
5. Delete worktree after merge

**Alternatives Considered**:
- Reusable worktree pool - More complex, less intuitive
- Single worktree with branch switching - Requires stashing, loses parallel capability

**Source**: [Git Worktree Best Practices](https://devot.team/blog/git-worktrees)

### 5. Existing Implementation Gaps

**Question**: What's missing in the current implementation that needs to be addressed?

**Decision**: Focus on these enhancement areas:

| Gap | Current State | Target State |
|-----|---------------|--------------|
| Lazygit integration | Basic app launch | View-specific launch with `--path` + positional args |
| Keyboard shortcuts | Limited focus mode | Full keyboard navigation (c/g/d/r keys) |
| Action menu | Delete only | Full menu: Terminal, VS Code, Lazygit, File Manager, Copy Path |
| Status refresh | 5s polling | Event-driven + manual refresh |
| Scrolling | No scroll container | Scrollable list optimized for 5-7 visible |

**Rationale**: Based on codebase exploration:
- `eww-monitoring-panel.nix` has Projects tab but limited actions
- `project_crud_handler.py` supports create/delete but not lazygit
- TypeScript service methods partially implemented (some throw "Not yet implemented")
- No keyboard shortcuts for worktree-specific operations

**Implementation Priority**:
1. P1: Lazygit integration (most value, frequently used)
2. P1: Worktree switching optimization (500ms target)
3. P2: Keyboard shortcuts (power user productivity)
4. P2: Action menu (discoverability)
5. P3: Scrollable list (scalability)

### 6. Eww Widget Patterns for Actions

**Question**: How should worktree actions be implemented in Eww widgets?

**Decision**: Use eventbox with button grid for action menu:

```yuck
(defwidget worktree-actions [worktree]
  (box :class "worktree-actions" :orientation "h" :space-evenly false
    (button :class "action-btn" :onclick "worktree-lazygit ${worktree.path}" "")
    (button :class "action-btn" :onclick "worktree-terminal ${worktree.path}" "")
    (button :class "action-btn" :onclick "worktree-vscode ${worktree.path}" "")
    (button :class "action-btn" :onclick "worktree-delete ${worktree.qualified_name}" "")))
```

**Rationale**: Consistent with existing Eww patterns in the codebase:
- Button-based actions with onclick handlers
- Shell script wrappers for complex operations
- Icons for compact display
- CSS classes for theming

**Alternatives Considered**:
- Popup menu - More complex, harder to keyboard navigate
- Context menu on right-click - Eww doesn't support native right-click menus

## Summary of Decisions

| Area | Decision | Impact |
|------|----------|--------|
| Lazygit launch | `lazygit --path <dir> <view>` | Correct context + view focus |
| Instance model | Always spawn new instance per worktree | Parallel development support |
| Workflow pattern | One worktree per branch | Matches 63% user preference |
| Action implementation | Button grid with shell script handlers | Consistent with existing patterns |
| Keyboard shortcuts | c=create, g=git, d=delete, r=refresh | Vim-like, discoverable |
| List display | Scrollable, 5-7 visible optimized | Scales to 10-20 worktrees |

## Dependencies Confirmed

| Dependency | Version | Purpose |
|------------|---------|---------|
| lazygit | 0.40+ | `--path` and positional args support |
| Eww | 0.4+ | GTK3 widgets, defpoll, deflisten |
| Python | 3.11+ | Daemon backend, asyncio |
| i3ipc.aio | Latest | Sway IPC communication |
| Pydantic | 2.x | Data model validation |
