# Research: Structured Git Repository Management

**Feature**: 100-automate-project-and
**Date**: 2025-11-29

## Research Task 1: Git Bare Clone + Worktree Workflow

### Question
Does `git clone --bare` + `git worktree add` produce the expected directory structure with sibling worktrees?

### Finding

**Decision**: Yes, the workflow produces exactly the expected structure.

**Rationale**: Tested with actual git commands:

```bash
# Create repo container and bare clone
mkdir -p ~/repos/vpittamp/test-repo
cd ~/repos/vpittamp/test-repo
git clone --bare git@github.com:vpittamp/test-repo.git .bare

# Create pointer file
echo "gitdir: ./.bare" > .git

# Create main worktree
git worktree add main main  # or master for older repos

# Create feature worktree
git worktree add feature-test -b feature-test
```

**Resulting Structure**:
```
~/repos/vpittamp/test-repo/
├── .bare/                    # Bare git database
│   ├── HEAD
│   ├── config
│   ├── objects/
│   ├── refs/
│   └── worktrees/            # Worktree metadata
│       ├── main/
│       └── feature-test/
├── .git                      # Pointer file: "gitdir: ./.bare"
├── main/                     # Main branch worktree
│   ├── .git                  # Pointer: "gitdir: /path/to/.bare/worktrees/main"
│   └── <working files>
└── feature-test/             # Feature worktree
    ├── .git                  # Pointer to worktrees/feature-test
    └── <working files>
```

**Key Observations**:
- Each worktree has its own `.git` file (not directory) pointing back to `.bare/worktrees/<name>`
- `git worktree list` shows all worktrees including bare repo path
- Worktree names in `git worktree list` match directory names
- Default branch detection needed (main vs master)

**Alternatives Considered**:
- Regular clone with worktrees in separate directory: Rejected - scattered files, harder discovery
- ghq-style structure without bare: Rejected - main branch in root causes confusion

---

## Research Task 2: Remote URL Parsing

### Question
How to reliably parse GitHub account and repo name from SSH and HTTPS URLs?

### Finding

**Decision**: Use regex patterns with fallback chain.

**Rationale**: Two URL formats to handle:

```
SSH:   git@github.com:vpittamp/nixos.git
HTTPS: https://github.com/vpittamp/nixos.git
```

**Regex Patterns**:
```python
import re

SSH_PATTERN = r'^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$'
HTTPS_PATTERN = r'^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$'

def parse_github_url(url: str) -> tuple[str, str]:
    """Extract (account, repo) from GitHub URL."""
    for pattern in [SSH_PATTERN, HTTPS_PATTERN]:
        match = re.match(pattern, url)
        if match:
            return match.group(1), match.group(2)
    raise ValueError(f"Invalid GitHub URL: {url}")

# Examples:
parse_github_url("git@github.com:vpittamp/nixos.git")
# → ("vpittamp", "nixos")

parse_github_url("https://github.com/PittampalliOrg/api.git")
# → ("PittampalliOrg", "api")
```

**Edge Cases Handled**:
- With/without `.git` suffix
- Lowercase/uppercase account names (preserved as-is)
- Org names with hyphens

**Alternatives Considered**:
- URL parsing library (urllib): More complex, doesn't handle SSH format
- Simple string split: Fragile, doesn't validate format

---

## Research Task 3: Worktree Discovery

### Question
How to enumerate all worktrees for a bare repository?

### Finding

**Decision**: Use `git worktree list --porcelain` for machine-readable output.

**Rationale**: Tested command output:

```bash
$ git worktree list --porcelain
worktree /tmp/test-bare-repo/.bare
bare

worktree /tmp/test-bare-repo/feature-test
HEAD 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
branch refs/heads/feature-test

worktree /tmp/test-bare-repo/main
HEAD 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
branch refs/heads/master
```

**Parsing Strategy**:
```python
import subprocess

def list_worktrees(repo_path: str) -> list[dict]:
    """List all worktrees for a repository."""
    result = subprocess.run(
        ["git", "-C", repo_path, "worktree", "list", "--porcelain"],
        capture_output=True, text=True, check=True
    )

    worktrees = []
    current = {}

    for line in result.stdout.split('\n'):
        if line.startswith('worktree '):
            if current and not current.get('bare'):
                worktrees.append(current)
            current = {'path': line[9:]}
        elif line == 'bare':
            current['bare'] = True
        elif line.startswith('branch '):
            current['branch'] = line[7:].replace('refs/heads/', '')
        elif line.startswith('HEAD '):
            current['commit'] = line[5:]

    if current and not current.get('bare'):
        worktrees.append(current)

    return worktrees
```

**Output Example**:
```python
[
    {'path': '/tmp/test-bare-repo/main', 'branch': 'master', 'commit': '7fd1a60...'},
    {'path': '/tmp/test-bare-repo/feature-test', 'branch': 'feature-test', 'commit': '7fd1a60...'}
]
```

**Alternatives Considered**:
- Parse `.bare/worktrees/` directory directly: Missing metadata (branch, commit)
- `git worktree list` (non-porcelain): Human-readable but harder to parse

---

## Research Task 4: Default Branch Detection

### Question
How to determine if a repo uses `main` or `master` as default branch?

### Finding

**Decision**: Query remote HEAD reference after bare clone.

**Rationale**:

```bash
# After bare clone, check default branch
$ git -C .bare symbolic-ref refs/remotes/origin/HEAD
refs/remotes/origin/main  # or refs/remotes/origin/master
```

**Python Implementation**:
```python
def get_default_branch(bare_path: str) -> str:
    """Get default branch name from bare repo."""
    try:
        result = subprocess.run(
            ["git", "-C", bare_path, "symbolic-ref", "refs/remotes/origin/HEAD"],
            capture_output=True, text=True, check=True
        )
        # "refs/remotes/origin/main" → "main"
        return result.stdout.strip().split('/')[-1]
    except subprocess.CalledProcessError:
        # Fallback: try main, then master
        for branch in ['main', 'master']:
            result = subprocess.run(
                ["git", "-C", bare_path, "rev-parse", f"refs/heads/{branch}"],
                capture_output=True, check=True
            )
            if result.returncode == 0:
                return branch
        raise ValueError("Could not determine default branch")
```

**Alternatives Considered**:
- Hardcode 'main': Breaks older repos
- Try both in worktree add: Inefficient, poor UX

---

## Research Task 5: Integration with i3pm Daemon

### Question
What IPC methods are needed for discovery integration?

### Finding

**Decision**: Add new IPC namespace `repo` with discovery methods.

**Rationale**: Current i3pm daemon uses JSON-RPC over Unix socket. New methods:

**New IPC Methods**:
```python
# repo.discover - Scan configured accounts and register all repos/worktrees
# Returns: {"discovered": 50, "repos": 20, "worktrees": 30}

# repo.list - List all discovered repositories
# Returns: [{"account": "vpittamp", "name": "nixos", "worktrees": [...]}]

# repo.get - Get single repository details
# Params: {"account": "vpittamp", "repo": "nixos"}

# worktree.create - Create new worktree in current repo context
# Params: {"branch": "100-feature", "from": "main"}

# worktree.remove - Remove worktree
# Params: {"branch": "100-feature"}
```

**Storage**:
- `~/.config/i3/accounts.json`: Configured accounts
- `~/.config/i3/repos.json`: Discovered repositories cache

**Alternatives Considered**:
- Extend existing `project` namespace: Confusing overlap with legacy projects
- Separate discovery daemon: Overkill for simple scan operation

---

## Summary of Decisions

| Task | Decision | Rationale |
|------|----------|-----------|
| Bare clone workflow | `.bare/` + `.git` pointer | Verified working, clean structure |
| URL parsing | Regex patterns | Handles SSH and HTTPS reliably |
| Worktree discovery | `git worktree list --porcelain` | Machine-readable, includes metadata |
| Default branch | Query `refs/remotes/origin/HEAD` | Works with both main and master |
| IPC integration | New `repo` namespace | Clean separation from legacy |

All research tasks resolved. Ready for Phase 1 design.
