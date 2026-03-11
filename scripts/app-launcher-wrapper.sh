#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${HOME}/.local/state/app-launcher.log"
LOG_MAX_LINES=1000
DAEMON_SOCKET="@DAEMON_SOCKET@"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date -Iseconds)
    echo "[$timestamp] $level $*" >> "$LOG_FILE"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$level] $*" >&2
    fi
}

error() {
    log "ERROR" "$@"
    echo "Error: $*" >&2
    exit 1
}

warn() {
    log "WARN" "$@"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "Warning: $*" >&2
    fi
}

rotate_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    local line_count
    line_count=$(wc -l < "$LOG_FILE")
    if (( line_count <= LOG_MAX_LINES )); then
        return 0
    fi
    tail -n $((LOG_MAX_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

rpc_request() {
    local method="$1"
    local params_json="$2"
    local request response error_json

    request=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params_json" \
        '{jsonrpc:"2.0", method:$method, params:$params, id:1}')

    [[ -S "$DAEMON_SOCKET" ]] || error "Daemon socket not found: $DAEMON_SOCKET"
    response=$(timeout 2s bash -lc "printf '%s' $(printf '%q' "$request") | socat - UNIX-CONNECT:$(printf '%q' "$DAEMON_SOCKET")" 2>/dev/null || true)
    [[ -n "$response" ]] || error "No response from daemon for method '$method'"

    error_json=$(jq -c '.error // empty' <<< "$response" 2>/dev/null || true)
    if [[ -n "$error_json" ]]; then
        error "Daemon error for '$method': $error_json"
    fi

    jq -c '.result' <<< "$response"
}

build_env_exports() {
    local spec_json="$1"
    jq -r '.environment | to_entries[] | @base64' <<< "$spec_json" | while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        local entry key value
        entry=$(printf '%s' "$row" | base64 -d)
        key=$(jq -r '.key' <<< "$entry")
        value=$(jq -r '.value // ""' <<< "$entry")
        printf "export %s=%q\n" "$key" "$value"
    done
}

validate_k9s_kubeconfig() {
    if [[ "$APP_NAME" != "k9s" ]]; then
        return 0
    fi

    if [[ -r "$HOME/.kube/stacks/config" ]]; then
        return 0
    fi

    log "INFO" "Missing ~/.kube/stacks/config; attempting sync for k9s"
    if ! command -v sync-stacks-kubeconfigs >/dev/null 2>&1; then
        error "Expected kubeconfig not found and sync-stacks-kubeconfigs is unavailable"
    fi
    sync-stacks-kubeconfigs >/dev/null 2>&1 || error "sync-stacks-kubeconfigs failed"
    [[ -r "$HOME/.kube/stacks/config" ]] || error "Expected kubeconfig not found after sync"
}

build_remote_terminal_command() {
    local spec_json="$1"
    local script_dir tmux_session_name remote_dir remote_user remote_host remote_port runtime_dir helper_script
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "$script_dir/managed-tmux-session.sh"

    tmux_session_name="$(managed_tmux_session_name "${I3PM_PROJECT_NAME:-project}" "${I3PM_TERMINAL_ANCHOR_ID}")"
    export I3PM_TMUX_SESSION_NAME="$tmux_session_name"

    remote_dir="$(jq -r '.remote_profile.remote_dir // empty' <<< "$spec_json")"
    remote_user="$(jq -r '.remote_profile.user // empty' <<< "$spec_json")"
    remote_host="$(jq -r '.remote_profile.host // empty' <<< "$spec_json")"
    remote_port="$(jq -r '.remote_profile.port // 22' <<< "$spec_json")"

    [[ -n "$remote_dir" && -n "$remote_user" && -n "$remote_host" ]] || error "Remote terminal launch requires a complete SSH profile"
    [[ "$remote_port" =~ ^[0-9]+$ ]] || error "Invalid remote SSH port: $remote_port"

    runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    mkdir -p "$runtime_dir"
    helper_script="$(mktemp "$runtime_dir/i3pm-remote-launch.XXXXXX.sh")"
    chmod 700 "$helper_script"

    {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        echo "remote_cmd=\$(cat <<'EOF_REMOTE'"
        build_env_exports "$spec_json"
        cat <<EOF_REMOTE
if ! command -v tmux >/dev/null 2>&1; then
  echo "[i3pm] tmux is not installed on remote host."
  exit 127
fi
session_name=$(printf '%q' "$tmux_session_name")
remote_dir=$(printf '%q' "$remote_dir")
if tmux has-session -t "$session_name" 2>/dev/null; then
  :
else
  tmux new-session -d -s "$session_name" -c "$remote_dir" -n main "exec \${SHELL:-/bin/bash} -l"
fi
while IFS='=' read -r name value; do
  [[ -n "$name" ]] || continue
  case "$name" in
    I3PM_*) tmux set-environment -t "$session_name" "$name" "$value" ;;
  esac
done < <(env)
tmux set-option -t "$session_name" -q @i3pm_managed 1
tmux set-option -t "$session_name" -q @i3pm_terminal_anchor "$I3PM_TERMINAL_ANCHOR_ID"
tmux set-option -t "$session_name" -q @i3pm_context_key "$I3PM_CONTEXT_KEY"
tmux set-option -t "$session_name" -q @i3pm_project_name "$I3PM_PROJECT_NAME"
tmux set-option -t "$session_name" -q @i3pm_tmux_session_name "$I3PM_TMUX_SESSION_NAME"
exec env TMUX= tmux attach-session -t "$session_name"
EOF_REMOTE
        echo "EOF_REMOTE"
        echo ")"
        echo "ssh_args=("
        printf "  %q\n" ssh -t -o BatchMode=yes -o ConnectTimeout=2
        if [[ "$remote_port" != "22" ]]; then
            printf "  %q\n" -p "$remote_port"
        fi
        printf "  %q\n" "${remote_user}@${remote_host}"
        printf "  %q\n" "bash -lc $(printf '%q' "\$remote_cmd")"
        cat <<'EOF_SCRIPT'
)
if ! "${ssh_args[@]}"; then
  echo
  echo "[i3pm] Remote terminal launch failed."
  echo "[i3pm] Press Enter to close..."
  read -r
fi
rm -f -- "$0" >/dev/null 2>&1 || true
EOF_SCRIPT
    } > "$helper_script"

    printf '%s\n' "$helper_script"
}

if [[ $# -lt 1 ]]; then
    error "Usage: app-launcher-wrapper.sh <app-name>"
fi

APP_NAME="$1"
rotate_log
log "INFO" "Launching app via daemon-prepared spec: $APP_NAME"

PREPARE_PARAMS=$(jq -nc \
    --arg app "$APP_NAME" \
    --arg variant "${I3PM_CONTEXT_VARIANT_OVERRIDE:-}" \
    --arg remote_session "${I3PM_REMOTE_SESSION_NAME_OVERRIDE:-}" \
    --arg restore_mark "${I3PM_RESTORE_MARK:-}" \
    --arg app_id_override "${I3PM_APP_ID_OVERRIDE:-}" \
    --arg pid "$$" \
    --arg dry_run "${DRY_RUN:-0}" \
    '{
        app_name: $app,
        launcher_pid: ($pid | tonumber),
        context_variant_override: $variant,
        remote_session_name_override: $remote_session,
        restore_mark: $restore_mark,
        app_id_override: $app_id_override,
        dry_run: ($dry_run == "1")
    }')
SPEC_JSON="$(rpc_request "prepare_launch" "$PREPARE_PARAMS")"

COMMAND="$(jq -r '.command' <<< "$SPEC_JSON")"
mapfile -t ARGS < <(jq -r '.args[]?' <<< "$SPEC_JSON")
EXECUTION_MODE="$(jq -r '.execution_mode // "local"' <<< "$SPEC_JSON")"
LOCAL_PROJECT_DIR="$(jq -r '.local_project_directory // empty' <<< "$SPEC_JSON")"
PROJECT_NAME="$(jq -r '.project_name // empty' <<< "$SPEC_JSON")"
TERMINAL_MODE="$(jq -r '.terminal // false' <<< "$SPEC_JSON")"
PREFERRED_WORKSPACE="$(jq -r '.preferred_workspace // empty' <<< "$SPEC_JSON")"
EXPECTED_CLASS="$(jq -r '.expected_class // empty' <<< "$SPEC_JSON")"

while IFS= read -r export_line; do
    [[ -n "$export_line" ]] || continue
    eval "$export_line"
done < <(build_env_exports "$SPEC_JSON")

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    jq '{command, args, execution_mode, project_name, project_directory, local_project_directory, terminal_anchor_id, environment}' <<< "$SPEC_JSON"
    exit 0
fi

command -v "$COMMAND" >/dev/null 2>&1 || error "Command not found: $COMMAND"
validate_k9s_kubeconfig

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$APP_NAME" == "terminal" && "$EXECUTION_MODE" == "local" ]]; then
    [[ -n "$LOCAL_PROJECT_DIR" ]] || error "Managed local terminal launch requires local_project_directory"
    if [[ -f "$LOCAL_PROJECT_DIR/devenv.nix" ]]; then
        ARGS=(-e "$SCRIPT_DIR/devenv-terminal-launch.sh" "$LOCAL_PROJECT_DIR")
    else
        ARGS=(-e "$SCRIPT_DIR/project-terminal-launch.sh" "$LOCAL_PROJECT_DIR")
    fi
elif [[ "$APP_NAME" == "terminal" && "$EXECUTION_MODE" == "ssh" ]]; then
    REMOTE_HELPER_SCRIPT="$(build_remote_terminal_command "$SPEC_JSON")"
    ARGS=(-e "$REMOTE_HELPER_SCRIPT")
elif [[ "$EXECUTION_MODE" == "ssh" ]]; then
    error "Remote project execution only supports managed terminal launches"
fi

ENV_STRING="$(build_env_exports "$SPEC_JSON" | paste -sd ';' -)"
if [[ "$APP_NAME" == "k9s" ]]; then
    ENV_STRING="${ENV_STRING};unset KUBECONFIG;export KUBECONFIG='$HOME/.kube/stacks/config'"
fi

APP_CMD="$(printf '%q ' "$COMMAND" "${ARGS[@]}")"
APP_CMD="${APP_CMD% }"
WORKDIR="$HOME"
if [[ "$EXECUTION_MODE" == "local" && -n "$LOCAL_PROJECT_DIR" ]]; then
    WORKDIR="$LOCAL_PROJECT_DIR"
fi
FULL_CMD="${ENV_STRING}; cd $(printf '%q' "$WORKDIR") && ${APP_CMD}"

log "INFO" "Executing app=$APP_NAME anchor=${I3PM_TERMINAL_ANCHOR_ID:-} mode=$EXECUTION_MODE workspace=${PREFERRED_WORKSPACE:-none} class=${EXPECTED_CLASS:-none}"
if command -v swaymsg >/dev/null 2>&1; then
    SWAY_RESULT="$(swaymsg exec "bash -lc $(printf '%q' "$FULL_CMD")" 2>&1)" || true
    jq -e 'type == "array" and any(.[]; .success == true)' <<< "$SWAY_RESULT" >/dev/null 2>&1 || error "Sway exec failed: $SWAY_RESULT"
else
    exec bash -lc "$FULL_CMD"
fi
