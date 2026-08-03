#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/i3pm-project-badge.sh"

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

# Everything happens inside the subshell on purpose. Sourcing a fixture in the
# test shell would overwrite the I3PM_* variables this session already exports,
# leaking one case's remote/ssh flags into every later invocation. The spawned
# process also sits outside any checkout, because these cases exercise the
# pane-env fallback and the badge's git probe reads /proc/<pane_pid>/cwd.
spawn_env_process() {
  local env_file="$1"
  SPAWNED_PID=""
  (
    # shellcheck disable=SC1090
    source "$env_file"
    cd "$tmpdir"
    exec env \
      I3PM_PROJECT_NAME="${I3PM_PROJECT_NAME:-}" \
      I3PM_PROJECT_DISPLAY_NAME="${I3PM_PROJECT_DISPLAY_NAME:-}" \
      I3PM_REMOTE_ENABLED="${I3PM_REMOTE_ENABLED:-false}" \
      I3PM_REMOTE_HOST="${I3PM_REMOTE_HOST:-}" \
      I3PM_REMOTE_USER="${I3PM_REMOTE_USER:-}" \
      I3PM_REMOTE_PORT="${I3PM_REMOTE_PORT:-22}" \
      I3PM_REMOTE_SESSION_KEY="${I3PM_REMOTE_SESSION_KEY:-}" \
      I3PM_REMOTE_SURFACE_KEY="${I3PM_REMOTE_SURFACE_KEY:-}" \
      I3PM_REMOTE_CONNECTION_KEY="${I3PM_REMOTE_CONNECTION_KEY:-}" \
      I3PM_REMOTE_TMUX_PANE="${I3PM_REMOTE_TMUX_PANE:-}" \
      I3PM_CONTEXT_VARIANT="${I3PM_CONTEXT_VARIANT:-}" \
      I3PM_CONNECTION_KEY="${I3PM_CONNECTION_KEY:-}" \
      I3PM_LOCAL_HOST_ALIAS="${I3PM_LOCAL_HOST_ALIAS:-}" \
      I3PM_TERMINAL_ROLE="${I3PM_TERMINAL_ROLE:-}" \
      TMUX_PANE="${TMUX_PANE:-}" \
      sleep 30
  ) &
  SPAWNED_PID="$!"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# A real checkout for the git-derived label cases. The badge must report the
# repository name and the live branch, not a launch-time snapshot.
git init -q -b main "${tmpdir}/demo"
git -C "${tmpdir}/demo" -c user.email=test@example.com -c user.name=test \
  commit -q --allow-empty -m "init"
git -C "${tmpdir}/demo" checkout -q -b feature/badge

cat >"${tmpdir}/pane-local.env" <<'EOF'
I3PM_PROJECT_NAME=vpittamp/nixos-config:main
I3PM_PROJECT_DISPLAY_NAME=main
I3PM_REMOTE_ENABLED=false
I3PM_CONTEXT_VARIANT=local
I3PM_LOCAL_HOST_ALIAS=thinkpad
I3PM_TERMINAL_ROLE=project-main
TMUX_PANE=%7
EOF

cat >"${tmpdir}/pane-ssh.env" <<'EOF'
I3PM_PROJECT_NAME=PittampalliOrg/stacks:main
I3PM_PROJECT_DISPLAY_NAME=stacks_main
I3PM_REMOTE_ENABLED=true
I3PM_REMOTE_HOST=ryzen
I3PM_REMOTE_USER=vpittamp
I3PM_REMOTE_PORT=22
I3PM_CONTEXT_VARIANT=ssh
I3PM_CONNECTION_KEY=vpittamp@ryzen:22
I3PM_TERMINAL_ROLE=project-main
TMUX_PANE=%11
EOF

cat >"${tmpdir}/pane-bridge.env" <<'EOF'
I3PM_PROJECT_NAME=vpittamp/nixos-config:main
I3PM_REMOTE_ENABLED=true
I3PM_CONTEXT_VARIANT=ssh
I3PM_CONNECTION_KEY=vpittamp@thinkpad:22
I3PM_REMOTE_CONNECTION_KEY=local@thinkpad
I3PM_REMOTE_HOST=thinkpad
I3PM_REMOTE_USER=vpittamp
I3PM_REMOTE_PORT=22
I3PM_REMOTE_TMUX_PANE=%0
TMUX_PANE=%9
EOF

spawn_env_process "${tmpdir}/pane-local.env"
local_pid="${SPAWNED_PID}"
spawn_env_process "${tmpdir}/pane-ssh.env"
ssh_pid="${SPAWNED_PID}"
spawn_env_process "${tmpdir}/pane-bridge.env"
bridge_pid="${SPAWNED_PID}"
trap 'kill "${local_pid}" "${ssh_pid}" "${bridge_pid}" 2>/dev/null || true; rm -rf "$tmpdir"' EXIT

sleep 0.1

out_pane_local="$("$SCRIPT_PATH" --tmux --source pane --pane-pid "${local_pid}" --max-len 40)"
assert_contains "$out_pane_local" "󰌽 local thinkpad" "Pane source should render local host/mode from pane env"
assert_contains "$out_pane_local" "◈ T%7" "Pane source should render alias-first local pane identity"
assert_contains "$out_pane_local" "nixos-config:main" "Pane env label should survive when the pane cwd is not a checkout"

out_pane_ssh="$("$SCRIPT_PATH" --tmux --source pane --pane-pid "${ssh_pid}" --max-len 40)"
assert_contains "$out_pane_ssh" "☁ ssh ryzen" "Pane source should render SSH host-only mode chip from pane env"
assert_contains "$out_pane_ssh" "◈ R%11" "Pane source should render alias-first SSH pane identity"
assert_contains "$out_pane_ssh" "stacks:main" "Remote panes keep the pane-env label: their cwd is not local"

out_hybrid="$(
  I3PM_PROJECT_NAME="vpittamp/nixos-config:main" \
  I3PM_PROJECT_DISPLAY_NAME="main" \
  I3PM_CONTEXT_VARIANT="local" \
  I3PM_REMOTE_ENABLED="false" \
  I3PM_LOCAL_HOST_ALIAS="thinkpad" \
    "$SCRIPT_PATH" --tmux --source hybrid --pane-pid "${ssh_pid}" --max-len 40
)"
assert_contains "$out_hybrid" "☁ ssh ryzen" "Hybrid mode should prioritize pane context over shell env context"
assert_contains "$out_hybrid" "◈ R%11" "Hybrid mode should keep pane alias from pane context"

bridge_prompt_out="$(
  env \
    "$SCRIPT_PATH" --prompt --source pane --pane-pid "${bridge_pid}" --max-len 40
)"
assert_contains "$bridge_prompt_out" "T%0" "Prompt mode should prefer remote bridge pane alias over local bridge pane id"
assert_contains "$bridge_prompt_out" "ssh thinkpad" "Prompt mode should describe the remote bridge host"

plain_git_out="$(
  env \
    -u I3PM_PROJECT_NAME \
    -u I3PM_PROJECT_DISPLAY_NAME \
    -u I3PM_REMOTE_ENABLED \
    -u I3PM_REMOTE_HOST \
    -u I3PM_REMOTE_USER \
    -u I3PM_REMOTE_PORT \
    -u I3PM_CONTEXT_VARIANT \
    -u I3PM_CONNECTION_KEY \
    -u TMUX \
    I3PM_PROJECT_BADGE_CWD="${tmpdir}/demo" \
    "$SCRIPT_PATH" --plain --source git --max-len 40
)"
assert_contains "$plain_git_out" "demo:feature/badge" "Plain mode should label the checkout from git"

# The whole point of the migration: a launch-time env snapshot must never
# outrank the directory the pane is actually sitting in.
git_beats_env_out="$(
  I3PM_PROJECT_NAME="vpittamp/nixos-config:main" \
  I3PM_REMOTE_ENABLED="false" \
  I3PM_PROJECT_BADGE_CWD="${tmpdir}/demo" \
    "$SCRIPT_PATH" --plain --source hybrid --max-len 40
)"
assert_contains "$git_beats_env_out" "demo:feature/badge" "Git in the pane cwd should override a stale env label"

# Outside any checkout the badge prints nothing rather than someone else's label.
outside_repo_out="$(
  env \
    -u I3PM_PROJECT_NAME \
    -u I3PM_PROJECT_DISPLAY_NAME \
    -u I3PM_REMOTE_ENABLED \
    -u I3PM_CONTEXT_VARIANT \
    I3PM_PROJECT_BADGE_CWD="${tmpdir}" \
    "$SCRIPT_PATH" --plain --source hybrid --max-len 40
)"
if [[ -n "$outside_repo_out" ]]; then
  fail "Plain mode outside a checkout should print nothing. Output: ${outside_repo_out}"
fi

echo "PASS: i3pm-project-badge context source tests"
