#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/app-launcher-wrapper.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local needle="$2"
  local message="$3"
  if [[ "$output" != *"$needle"* ]]; then
    fail "${message}. Output: ${output}"
  fi
}

assert_not_contains() {
  local output="$1"
  local needle="$2"
  local message="$3"
  if [[ "$output" == *"$needle"* ]]; then
    fail "${message}. Output: ${output}"
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="${tmpdir}/home"
mock_bin="${tmpdir}/mock-bin"
mkdir -p "${home_dir}/.config/i3" "${home_dir}/.local/state" "${mock_bin}"

cat > "${home_dir}/.config/i3/application-registry.json" <<'EOF'
{
  "version": "1.0",
  "applications": [
    {
      "name": "claude-pwa",
      "display_name": "Claude",
      "command": "launch-pwa-by-name",
      "parameters": ["01JCYF8Z2M7R4N6QW9XKPHVTB5"],
      "scope": "global",
      "expected_class": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
      "preferred_workspace": 52,
      "fallback_behavior": "skip",
      "terminal": false
    },
    {
      "name": "terminal",
      "display_name": "Terminal",
      "command": "ghostty",
      "parameters": ["-e", "sesh", "connect", "$PROJECT_DIR"],
      "scope": "scoped",
      "expected_class": "com.mitchellh.ghostty",
      "preferred_workspace": 1,
      "fallback_behavior": "use_home",
      "terminal": true
    },
    {
      "name": "firefox-scoped",
      "display_name": "Firefox Scoped",
      "command": "firefox",
      "parameters": [],
      "scope": "scoped",
      "expected_class": "firefox",
      "preferred_workspace": 3,
      "fallback_behavior": "skip",
      "terminal": false
    }
  ]
}
EOF

cat > "${home_dir}/.config/i3/active-worktree.json" <<'EOF'
{
  "qualified_name": "PittampalliOrg/stacks:main",
  "directory": "/home/vpittamp/repos/PittampalliOrg/stacks/main",
  "local_directory": "/home/vpittamp/repos/PittampalliOrg/stacks/main",
  "branch": "main",
  "account": "PittampalliOrg",
  "repo_name": "stacks",
  "remote": {
    "enabled": true,
    "host": "ryzen",
    "user": "vpittamp",
    "port": 22,
    "remote_dir": "/home/vpittamp/repos/PittampalliOrg/stacks/main"
  }
}
EOF

cat > "${mock_bin}/swaymsg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-t" && "${2:-}" == "get_tree" ]]; then
  cat <<'JSON'
{"nodes":[],"floating_nodes":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
  cat <<'JSON'
[{"success": true}]
JSON
  exit 0
fi

if [[ "${1:-}" == \[* ]]; then
  cat <<'JSON'
[{"success": false}]
JSON
  exit 0
fi

cat <<'JSON'
[{"success": true}]
JSON
EOF

cat > "${mock_bin}/launch-pwa-by-name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${mock_bin}/ghostty" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${mock_bin}/firefox" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "${mock_bin}/swaymsg" "${mock_bin}/launch-pwa-by-name" "${mock_bin}/ghostty" "${mock_bin}/firefox"

common_env=(
  "HOME=${home_dir}"
  "PATH=${mock_bin}:$PATH"
  "XDG_RUNTIME_DIR=${tmpdir}/runtime"
  "DEBUG=1"
)
mkdir -p "${tmpdir}/runtime"

# Regression guard: global PWAs must launch locally even when remote worktree is active.
pwa_output="$(
  env "${common_env[@]}" bash "${SCRIPT_PATH}" "claude-pwa" 2>&1
)"
assert_contains "$pwa_output" "Scope: global" "PWA launch should run with global scope"
assert_not_contains "$pwa_output" "Cannot launch GUI application 'claude-pwa'" "Global PWA should not be blocked by remote scope guard"
assert_contains "$pwa_output" "Sway exec successful" "Global PWA launch should execute through sway"

# Scoped remote terminal should still use SSH wrapping path.
terminal_output="$(
  env "${common_env[@]}" bash "${SCRIPT_PATH}" "terminal" 2>&1
)"
assert_contains "$terminal_output" "Feature 087: Applying SSH wrapping for remote terminal app" "Scoped terminal should apply SSH wrapping"
assert_contains "$terminal_output" "Sway exec successful" "Scoped terminal launch should still execute successfully"

# Scoped GUI app should remain blocked in remote mode.
set +e
scoped_gui_output="$(
  env "${common_env[@]}" bash "${SCRIPT_PATH}" "firefox-scoped" 2>&1
)"
scoped_gui_status=$?
set -e

if [[ $scoped_gui_status -eq 0 ]]; then
  fail "Scoped GUI app unexpectedly succeeded in remote mode"
fi
assert_contains "$scoped_gui_output" "Cannot launch GUI application 'firefox-scoped'" "Scoped GUI app should still be blocked in remote mode"

echo "PASS: app-launcher remote scope guard regression"
