#!/usr/bin/env bash
# Feature 100: Bare Clone Helper Script
#
# Usage: i3pm-clone.sh <url> [account]
#
# Clones a GitHub repository using the bare clone pattern:
# 1. git clone --bare <url> .bare
# 2. Create .git pointer file
# 3. Detect default branch
# 4. Create main worktree
#
# Directory structure created:
#   ~/repos/<account>/<repo>/
#   ├── .bare/     # Bare git database
#   ├── .git       # Pointer file: "gitdir: ./.bare"
#   └── main/      # Main worktree

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse GitHub URL to extract account and repo
parse_github_url() {
    local url="$1"
    local account=""
    local repo=""

    # SSH format: git@github.com:account/repo.git
    if [[ "$url" =~ ^git@github\.com:([^/]+)/(.+)$ ]]; then
        account="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        # Strip .git suffix if present
        repo="${repo%.git}"
    # HTTPS format: https://github.com/account/repo.git
    elif [[ "$url" =~ ^https://github\.com/([^/]+)/(.+)$ ]]; then
        account="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        # Strip .git suffix if present
        repo="${repo%.git}"
    else
        log_error "Invalid GitHub URL: $url"
        exit 1
    fi

    echo "$account $repo"
}

# Detect default branch from bare repo
get_default_branch() {
    local bare_path="$1"
    local branch

    # Try symbolic-ref first
    branch=$(git -C "$bare_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)

    if [[ -n "$branch" ]]; then
        echo "$branch"
        return
    fi

    # Fallback: try main, then master
    if git -C "$bare_path" rev-parse refs/heads/main &>/dev/null; then
        echo "main"
        return
    fi

    if git -C "$bare_path" rev-parse refs/heads/master &>/dev/null; then
        echo "master"
        return
    fi

    log_error "Could not determine default branch"
    exit 1
}

main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <url> [account]"
        echo
        echo "Examples:"
        echo "  $0 git@github.com:vpittamp/nixos.git"
        echo "  $0 https://github.com/PittampalliOrg/api.git"
        echo "  $0 git@github.com:vpittamp/nixos.git PittampalliOrg"
        exit 1
    fi

    local url="$1"
    local override_account="${2:-}"

    # Parse URL
    read -r detected_account repo <<< "$(parse_github_url "$url")"

    # Use override account if provided
    local account="${override_account:-$detected_account}"

    # Determine base path (default to ~/repos/<account>)
    local base_path="${HOME}/repos/${account}"
    local repo_path="${base_path}/${repo}"
    local bare_path="${repo_path}/.bare"

    # Check if repo already exists
    if [[ -d "$bare_path" ]]; then
        log_error "Repository already exists at ${repo_path}"
        exit 1
    fi

    log_info "Cloning ${url} to ${repo_path}"

    # Create directory structure
    mkdir -p "$repo_path"

    # Step 1: Bare clone
    log_info "Creating bare clone..."
    git clone --bare "$url" "$bare_path"

    # Step 2: Create .git pointer
    log_info "Creating .git pointer file..."
    echo "gitdir: ./.bare" > "${repo_path}/.git"

    # Step 3: Detect default branch
    local default_branch
    default_branch=$(get_default_branch "$bare_path")
    log_info "Default branch: ${default_branch}"

    # Step 4: Create main worktree
    local main_path="${repo_path}/${default_branch}"
    log_info "Creating main worktree at ${main_path}..."
    git -C "$bare_path" worktree add "$main_path" "$default_branch"

    log_info "Clone complete!"
    echo
    echo "Repository structure:"
    echo "  ${repo_path}/"
    echo "  ├── .bare/           # Git database"
    echo "  ├── .git             # Pointer file"
    echo "  └── ${default_branch}/           # Main worktree"
    echo
    echo "To create a feature worktree:"
    echo "  cd ${repo_path}/${default_branch}"
    echo "  i3pm worktree create 100-feature"
}

main "$@"
