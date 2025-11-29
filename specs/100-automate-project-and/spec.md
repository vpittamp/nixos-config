# Feature Specification: Structured Git Repository Management

**Feature Branch**: `100-automate-project-and`
**Created**: 2025-11-29
**Status**: Draft
**Input**: User description: "Automate project and worktree sourcing with structured account-based directory organization optimized for parallel LLM workflows"

## Clarifications

### Session 2025-11-29

- Q: How should repositories be organized? → A: Structured directories by GitHub account (`~/repos/vpittamp/` for personal, `~/repos/PittampalliOrg/` for work)
- Q: Backwards compatibility with existing project logic? → A: None. Replace existing logic with optimal solution. User will re-clone repos into correct structure.
- Q: How should project name collisions be resolved? → A: Not applicable - structured paths eliminate collisions (account/repo-name is unique)
- Q: Should main repo be bare or regular? How should worktrees be structured? → A: Use bare repository pattern with all branches (including main) as worktrees for optimal parallel LLM development

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bare Repository + Worktree Structure (Priority: P1)

A user wants repositories organized using bare repositories with all working directories (including main) as worktrees, enabling clean parallel development with multiple Claude Code instances.

**Why this priority**: Bare repo pattern is optimal for parallel LLM workflows - no "main" working directory to accidentally modify, clean separation between git database and working files, all branches equally accessible.

**Independent Test**: Can be fully tested by cloning a repo and verifying bare structure is created with main worktree alongside feature worktrees.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm clone git@github.com:vpittamp/nixos.git`, **When** clone completes, **Then** structure is:
   - `~/repos/vpittamp/nixos/.bare/` (bare git database)
   - `~/repos/vpittamp/nixos/.git` (pointer file to .bare)
   - `~/repos/vpittamp/nixos/main/` (worktree for main branch)

2. **Given** user creates a feature worktree with `i3pm worktree create 100-feature`, **When** worktree is created, **Then** it exists at `~/repos/vpittamp/nixos/100-feature/` alongside main.

3. **Given** multiple Claude Code instances running on different worktrees, **When** each instance makes changes, **Then** changes are isolated - no interference between instances.

---

### User Story 2 - Account-Based Repository Organization (Priority: P1)

A user wants all repositories organized in a predictable structure based on GitHub account ownership, with automatic discovery within those directories.

**Why this priority**: Structured organization eliminates naming collisions, provides clear ownership context, and enables simple discovery.

**Independent Test**: Can be fully tested by cloning repos into the defined structure and verifying they appear in the project list with correct account association.

**Acceptance Scenarios**:

1. **Given** the directory structure `~/repos/vpittamp/nixos/` and `~/repos/PittampalliOrg/work-api/`, **When** discovery runs, **Then** projects are registered as `vpittamp/nixos` and `PittampalliOrg/work-api` respectively.

2. **Given** the same repo name exists in both accounts, **When** discovery runs, **Then** both are registered without collision as `vpittamp/api` and `PittampalliOrg/api`.

---

### User Story 3 - Worktree Discovery and Linking (Priority: P2)

A user creates worktrees for feature development and wants them automatically discovered and linked to their parent repository.

**Why this priority**: Worktrees are the primary development workflow for parallel LLM sessions. Auto-discovery eliminates manual registration.

**Independent Test**: Can be tested by creating a worktree and verifying it appears linked to the correct parent project.

**Acceptance Scenarios**:

1. **Given** repo `~/repos/vpittamp/nixos/` with worktrees `main/` and `100-feature/`, **When** discovery runs, **Then** worktrees are registered as `vpittamp/nixos:main` and `vpittamp/nixos:100-feature`.

2. **Given** multiple worktrees for the same repo, **When** discovery runs, **Then** all worktrees are discovered and linked to the same parent repository.

3. **Given** a worktree created with `i3pm worktree create`, **When** discovery runs, **Then** existing worktree metadata is preserved.

---

### User Story 4 - Clone Helper with Bare Setup (Priority: P2)

A user wants a simple command to clone repos into the correct directory structure with bare repository setup automatically.

**Why this priority**: Reduces friction of adopting the new structure. Users don't need to remember bare clone commands.

**Independent Test**: Can be tested by running clone command and verifying bare repo + main worktree structure.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm clone git@github.com:vpittamp/dotfiles.git`, **When** clone completes, **Then**:
   - Bare repo at `~/repos/vpittamp/dotfiles/.bare/`
   - Main worktree at `~/repos/vpittamp/dotfiles/main/`
   - Project registered as `vpittamp/dotfiles`

2. **Given** user runs `i3pm clone https://github.com/PittampalliOrg/infra.git`, **When** clone completes, **Then** same bare+main structure in `~/repos/PittampalliOrg/infra/`.

3. **Given** user runs `i3pm clone` for an already-cloned repo, **When** command runs, **Then** error message indicates repo already exists with path.

---

### User Story 5 - Real-time Discovery (Priority: P4)

A user wants new repos and worktrees detected automatically without running manual scans.

**Why this priority**: "Set and forget" experience. Lower priority because manual scans work for MVP.

**Independent Test**: Can be tested by creating a worktree and verifying it appears within the notification window.

**Acceptance Scenarios**:

1. **Given** file monitoring is enabled, **When** user creates a worktree, **Then** the worktree is registered within 30 seconds.

---

### Edge Cases

- What happens when a repo is cloned outside the structured directories?
  - Not discovered. Only `~/repos/<account>/` directories are scanned.

- How are forks handled (same repo name, different account)?
  - Natural handling - `vpittamp/react` and `PittampalliOrg/react` are distinct projects.

- What happens when a `.git` directory is corrupted?
  - Log warning and skip. Does not block discovery of other repos.

- What happens if a worktree is deleted but git metadata remains?
  - Run `git worktree prune` during discovery to clean stale references.

- What happens if account directory doesn't exist yet?
  - Created automatically on first clone to that account.

- How are worktrees created outside the repo directory handled?
  - Supported but discouraged. Discovery scans both `~/repos/` and linked worktree paths from git metadata.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST clone repositories as bare repos into `~/repos/<account>/<repo>/.bare/` with a `.git` pointer file.

- **FR-002**: System MUST create a `main` worktree automatically after bare clone at `~/repos/<account>/<repo>/main/`.

- **FR-003**: System MUST create feature worktrees as siblings to main at `~/repos/<account>/<repo>/<branch-name>/`.

- **FR-004**: System MUST discover all bare repositories and their associated worktrees within configured account directories.

- **FR-005**: System MUST extract git metadata: current branch, commit hash, clean/dirty status, ahead/behind counts, remote URL.

- **FR-006**: System MUST derive account name from remote URL during discovery (parse `github.com:<account>/` or `github.com/<account>/`).

- **FR-007**: System MUST provide `i3pm clone <url>` command that performs bare clone with main worktree setup.

- **FR-008**: System MUST provide `i3pm worktree create <branch>` command that creates worktree as sibling to main.

- **FR-009**: System MUST register projects with qualified names (`<account>/<repo>` for repos, `<account>/<repo>:<branch>` for worktrees).

- **FR-010**: System MUST replace existing manual project registration logic with automatic discovery-based registration.

- **FR-011**: System MUST support multiple configured accounts (personal, work, other orgs).

- **FR-012**: System MUST run `git worktree prune` during discovery to clean stale worktree references.

### Key Entities

- **AccountConfig**: Configured GitHub account/org with associated base directory (e.g., `{name: "vpittamp", path: "~/repos/vpittamp"}`).

- **BareRepository**: Repository stored as bare clone with `.bare/` database and `.git` pointer file.

- **Worktree**: Working directory linked to a bare repository, identified by branch name.

- **DiscoveredProject**: Repository or worktree found during scan with account, name, path, remote_url, and git metadata.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Discovery of 50 repositories with 100 total worktrees completes in under 5 seconds.

- **SC-002**: Project names are globally unique (zero collisions by design via `account/repo:branch` namespacing).

- **SC-003**: 100% of bare repos in configured account directories are discovered.

- **SC-004**: 100% of worktrees linked to discovered bare repos are discovered and linked correctly.

- **SC-005**: Clone command creates correct bare+main structure 100% of the time.

- **SC-006**: Parallel Claude Code instances can work on different worktrees without interference.

- **SC-007**: User can set up structure and run first discovery within 5 minutes.

## Design Decisions

### Directory Structure

```
~/repos/
├── vpittamp/                       # Personal GitHub account
│   ├── nixos/                      # Repository container
│   │   ├── .bare/                  # Bare git database (hidden)
│   │   ├── .git                    # Pointer file: "gitdir: ./.bare"
│   │   ├── main/                   # Worktree for main branch
│   │   ├── 100-automate-project/   # Feature worktree
│   │   ├── 101-fix-bug/            # Another feature worktree
│   │   └── review/                 # Permanent worktree for PR review
│   └── dotfiles/
│       ├── .bare/
│       ├── .git
│       └── main/
├── PittampalliOrg/                 # Work organization
│   └── api/
│       ├── .bare/
│       ├── .git
│       ├── main/
│       └── hotfix-critical/
```

### Project Naming Convention

- Repository projects: `<account>/<repo>` (e.g., `vpittamp/nixos`)
- Worktree projects: `<account>/<repo>:<branch>` (e.g., `vpittamp/nixos:100-automate-project`)
- Main worktree: `<account>/<repo>:main` (e.g., `vpittamp/nixos:main`)

### Why Bare Repository Pattern

Based on research from [Morgan Cugerone](https://morgan.cugerone.com/blog/how-to-use-git-worktree-and-in-a-clean-way/), [Nick Nisi](https://nicknisi.com/posts/git-worktrees/), and [parallel AI development workflows](https://stevekinney.com/courses/ai-development/git-worktrees):

1. **No accidental main modifications**: With regular clones, the main working directory is the repo root - easy to accidentally commit there. Bare repos have no working directory by default.

2. **All branches equal**: Main branch is just another worktree, not special. Switch between branches by changing directories (`cd ../100-feature`), not git commands.

3. **Cleaner backups**: Backup `.bare/` directory only - that's where history lives. Worktrees are disposable working copies.

4. **Optimal for parallel LLM**: Multiple Claude Code instances work in separate worktrees without any risk of conflicts. Each instance has its own isolated working directory.

5. **Matches mental model**: `cd ~/repos/vpittamp/nixos/100-feature` to work on feature 100. No ambiguity about which branch you're on.

6. **Sibling worktrees**: Worktrees as siblings (not in separate `~/worktrees/` directory) keeps related code together. Easy to compare: `diff main/src 100-feature/src`.

### Comparison: Sibling vs Separate Worktrees

| Aspect | Sibling (`~/repos/account/repo/branch/`) | Separate (`~/worktrees/repo-branch/`) |
|--------|------------------------------------------|---------------------------------------|
| Proximity | Related code together | Scattered across filesystem |
| Navigation | `cd ../main` | `cd ~/worktrees/nixos-main` |
| Comparison | Easy `diff main/ feature/` | Requires full paths |
| Cleanup | `rm -rf 100-feature/` in repo | Must find in worktrees dir |
| Discovery | Scan repo dir once | Scan multiple locations |
| Mental model | "Repo has branches" | "Branches are everywhere" |

**Decision**: Sibling worktrees within repo container for better organization and simpler discovery.

## Research Findings

### Parallel LLM Workflow Best Practices

From [incident.io](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees), [Agent Interviews](https://docs.agentinterviews.com/blog/parallel-ai-coding-with-gitworktrees/), and [Steve Kinney](https://stevekinney.com/courses/ai-development/git-worktrees):

1. **Task Specialization**: Each Claude instance works on independent, isolated tasks in separate worktrees.

2. **No Context Switching**: Changing directories (`cd`) is instant; no stashing, no branch switching, no IDE reconfiguration.

3. **Shared Git Database**: All worktrees share commits, stashes, and refs - only working files are duplicated.

4. **CLAUDE.md per Worktree**: Each worktree can have its own context file for the Claude instance working there.

5. **Regular Pruning**: Use `git worktree prune` to clean up stale references from deleted worktrees.

### Existing Tools Evaluated

1. **[ghq](https://github.com/x-motemen/ghq)** - Repository manager (Go)
   - Uses `~/ghq/<host>/<account>/<repo>` structure
   - Does NOT use bare repos - regular clones only
   - Our approach adds bare repo pattern for worktree optimization

2. **[gwq](https://github.com/d-kuro/gwq)** - Worktree manager (Go)
   - Manages worktrees in flat `~/worktrees/` directory
   - Does NOT use bare repos
   - Our approach keeps worktrees as siblings within repo

3. **[agenttools/worktree](https://github.com/agenttools/worktree)** - Claude Code integration
   - Creates worktrees from GitHub issues
   - Does NOT use bare repos
   - Good model for Claude integration, not directory structure

4. **[Nick Nisi's approach](https://nicknisi.com/posts/git-worktrees/)** - Bare repo best practice
   - Recommends bare clone with `.bare/` + `.git` pointer
   - Maintains permanent `main`, `review`, `hotfix` worktrees
   - Our approach follows this pattern exactly

## Assumptions

- User primarily uses GitHub (single host assumption simplifies structure)
- User has 2-3 accounts/orgs (personal + 1-2 work orgs)
- User will re-clone repos into new structure (migration not needed)
- Existing project management code can be replaced wholesale
- Parallel Claude Code development is primary use case
- Worktrees should be siblings, not in separate directory
