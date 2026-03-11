{ config, lib, pkgs, inputs, osConfig ? null, ... }:

let
  cfg = config.programs.walker;
  remoteWorktreeHost = "ryzen";
  remoteWorktreeUser = "vpittamp";

  # Detect Wayland mode - if Sway is enabled, we're in Wayland mode
  isWaylandMode = config.wayland.windowManager.sway.enable or false;

  # Create clipboard sync script as a proper nix package
  clipboardSyncScript = pkgs.writeShellScript "clipboard-sync" ''
    #!/usr/bin/env bash
    # Synchronize clipboard contents across Wayland, X11, OSC52 terminals, and auxiliary bridges.
    # Reads stdin into a temporary file to remain binary-safe, then fans out to the
    # available clipboard backends. Designed for use by Elephant/Walker, tmux, and
    # general shell workflows.

    set -euo pipefail

    tmp=$(${pkgs.coreutils}/bin/mktemp -t clipboard-sync-XXXXXX)
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.coreutils}/bin/cat >"$tmp"

    # Exit cleanly on empty input
    if [[ ! -s "$tmp" ]]; then
      exit 0
    fi

    # Detect mimetype when possible (used for Wayland image copies)
    mime=""
    if command -v ${pkgs.file}/bin/file >/dev/null 2>&1; then
      mime=$(${pkgs.file}/bin/file --brief --mime-type "$tmp" 2>/dev/null || true)
    fi

    copy_wayland() {
      # Prefer explicit mime when dealing with images
      if [[ -n "''${WAYLAND_DISPLAY:-}" ]] && command -v ${pkgs.wl-clipboard}/bin/wl-copy >/dev/null 2>&1; then
        if [[ "$mime" =~ ^image/ ]]; then
          ${pkgs.wl-clipboard}/bin/wl-copy --type "$mime" <"$tmp"
          ${pkgs.wl-clipboard}/bin/wl-copy --primary --type "$mime" <"$tmp"
        else
          ${pkgs.wl-clipboard}/bin/wl-copy <"$tmp"
          ${pkgs.wl-clipboard}/bin/wl-copy --primary <"$tmp"
        fi
      elif command -v ${pkgs.wl-clipboard}/bin/wl-copy >/dev/null 2>&1; then
        # Fallback: wl-copy via x11 bridge (e.g., wl-clipboard-x11)
        ${pkgs.wl-clipboard}/bin/wl-copy <"$tmp"
      fi
    }

    copy_x11() {
      if command -v ${pkgs.xclip}/bin/xclip >/dev/null 2>&1; then
        ${pkgs.xclip}/bin/xclip -selection clipboard <"$tmp"
        ${pkgs.xclip}/bin/xclip -selection primary <"$tmp"
      fi
    }

    copy_pbcopy() {
      if command -v pbcopy >/dev/null 2>&1; then
        pbcopy <"$tmp"
      fi
    }

    copy_clip_exe() {
      if command -v clip.exe >/dev/null 2>&1; then
        # clip.exe cannot handle NUL bytes; strip them defensively
        ${pkgs.coreutils}/bin/tr -d '\0' <"$tmp" | clip.exe
      fi
    }

    copy_osc52() {
      if ! command -v ${pkgs.coreutils}/bin/base64 >/dev/null 2>&1; then
        return
      fi

      # Only attempt OSC52 when inside tmux/screen/SSH to avoid polluting local terminals.
      if [[ -z "''${TMUX:-}''${SSH_TTY:-}" ]]; then
        return
      fi

      # Avoid sending excessively large payloads (limit to 1 MiB)
      if [[ $(${pkgs.coreutils}/bin/stat --format='%s' "$tmp" 2>/dev/null || ${pkgs.coreutils}/bin/wc -c <"$tmp") -gt 1048576 ]]; then
        return
      fi

      if payload=$(${pkgs.coreutils}/bin/base64 -w0 "$tmp" 2>/dev/null); then
        osc=$'\e]52;c;'"$payload"$'\a'
        target="/dev/tty"
        if [[ -n "''${TMUX:-}" ]]; then
          target=$(${pkgs.tmux}/bin/tmux display -p '#{client_tty}' 2>/dev/null || echo "/dev/tty")
        elif [[ -n "''${SSH_TTY:-}" ]]; then
          target="''${SSH_TTY}"
        fi
        printf '%b' "$osc" >"$target" 2>/dev/null || true
      fi
    }

    copy_wayland
    copy_x11
    copy_pbcopy
    copy_clip_exe
    copy_osc52
  '';

  # Smart paste script for clipboard provider
  # Copies to clipboard, then auto-pastes for regular apps only.
  # For terminals, content is copied to clipboard but NOT auto-pasted,
  # allowing users to use tmux's prefix+] or terminal's Ctrl+Shift+V.
  # Reference: https://github.com/abenz1267/walker/issues/560
  smartPasteScript = pkgs.writeShellScript "smart-paste" ''
    #!/usr/bin/env bash
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    focused_window_class() {
      local request response
      request=$(${pkgs.jq}/bin/jq -nc '{jsonrpc:"2.0", method:"get_windows", params:{}, id:1}')
      [[ -S "$DAEMON_SOCKET" ]] || return 1
      response=$(${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
      [[ -n "$response" ]] || return 1
      printf '%s\n' "$response" | ${pkgs.jq}/bin/jq -r '
        .result
        | .. | objects
        | select(.focused? == true)
        | .app_id // .class // ""
      ' | head -n1
    }

    # Copy content to clipboard first (reads from stdin)
    ${pkgs.wl-clipboard}/bin/wl-copy

    # Small delay for clipboard to sync and Walker window to close
    sleep 0.15

    # Get focused window app_id or class from daemon state
    focused="$(focused_window_class || true)"

    # Terminal detection - for terminals, DON'T auto-paste
    # This allows users to use their preferred paste method:
    #   - tmux: prefix + ] (backtick + ])
    #   - terminal native: Ctrl+Shift+V
    case "$focused" in
      ghostty|Ghostty|alacritty|Alacritty|kitty|Kitty|konsole|foot|Foot|xterm|XTerm|urxvt|URxvt|termite|gnome-terminal|tilix|wezterm|st|St)
        # Terminal: Don't auto-paste. Content is in clipboard.
        ;;
      *)
        # Regular app: use Ctrl+V for auto-paste
        ${pkgs.wtype}/bin/wtype -M ctrl v
        ;;
    esac
  '';

  walkerOpenInNvim = pkgs.writeShellScriptBin "walker-open-in-nvim" ''
    #!/usr/bin/env bash
    # Launch an Alacritty terminal window with Neovim for a Walker-selected file path
    set -euo pipefail

    if [ $# -eq 0 ]; then
      echo "walker-open-in-nvim: missing file argument" >&2
      exit 1
    fi

    RAW_PATH="$1"

    decode_output="$(${pkgs.python3}/bin/python3 - <<'PY' "$RAW_PATH"
import sys
from urllib.parse import urlsplit, unquote

value = sys.argv[1]

if value.startswith("file://"):
    parsed = urlsplit(value)
    netloc = parsed.netloc
    path = parsed.path or ""
    if netloc and netloc not in ("", "localhost"):
        fs_path = f"/{netloc}{path}"
    else:
        fs_path = path
    fragment = parsed.fragment or ""
else:
    fs_path = value
    fragment = ""

print(unquote(fs_path))
print(fragment)
PY
    )"

    IFS=$'\n' read -r TARGET_PATH TARGET_FRAGMENT <<< "$decode_output"

    if [ -z "$TARGET_PATH" ]; then
      echo "walker-open-in-nvim: unable to parse path from '$RAW_PATH'" >&2
      exit 1
    fi

    case "$TARGET_PATH" in
      "~")
        TARGET_PATH="$HOME"
        ;;
      "~/"*)
        TARGET_PATH="$HOME/''${TARGET_PATH:2}"
        ;;
    esac

    if [[ "$TARGET_PATH" != /* ]]; then
      TARGET_PATH="$PWD/$TARGET_PATH"
    fi

    LINE_ARG=""
    if [ -n "$TARGET_FRAGMENT" ]; then
      if [[ "$TARGET_FRAGMENT" =~ ^L?([0-9]+)$ ]]; then
        LINE_ARG="+''${BASH_REMATCH[1]}"
      fi
    fi

    # Query i3pm daemon for project context (integrates with project management)
    PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')
    PROJECT_NAME=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.name // ""')
    PROJECT_DIR=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.directory // ""')
    PROJECT_DISPLAY_NAME=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.display_name // ""')
    PROJECT_ICON=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.icon // ""')

    # Generate app instance ID (like app-launcher-wrapper does)
    TIMESTAMP=$(date +%s)
    APP_INSTANCE_ID="nvim-''${PROJECT_NAME:-global}-$$-$TIMESTAMP"

    # Export I3PM environment variables for window-to-project association
    export I3PM_APP_ID="$APP_INSTANCE_ID"
    export I3PM_APP_NAME="nvim"
    export I3PM_PROJECT_NAME="''${PROJECT_NAME:-}"
    export I3PM_PROJECT_DIR="''${PROJECT_DIR:-}"
    export I3PM_PROJECT_DISPLAY_NAME="''${PROJECT_DISPLAY_NAME:-}"
    export I3PM_PROJECT_ICON="''${PROJECT_ICON:-}"
    export I3PM_SCOPE="scoped"
    export I3PM_ACTIVE=$(if [[ -n "$PROJECT_NAME" ]]; then echo "true"; else echo "false"; fi)
    export I3PM_LAUNCH_TIME="$(date +%s)"
    export I3PM_LAUNCHER_PID="$$"

    # Build nvim command with line number if present
    if [ -n "$LINE_ARG" ]; then
      NVIM_CMD="${pkgs.neovim-unwrapped}/bin/nvim $LINE_ARG '$TARGET_PATH'"
    else
      NVIM_CMD="${pkgs.neovim-unwrapped}/bin/nvim '$TARGET_PATH'"
    fi

    # Use systemd-run for proper process isolation (like app-launcher-wrapper)
    if command -v systemd-run &>/dev/null; then
      exec systemd-run --user --scope \
        --setenv=I3PM_APP_ID="$I3PM_APP_ID" \
        --setenv=I3PM_APP_NAME="$I3PM_APP_NAME" \
        --setenv=I3PM_PROJECT_NAME="$I3PM_PROJECT_NAME" \
        --setenv=I3PM_PROJECT_DIR="$I3PM_PROJECT_DIR" \
        --setenv=I3PM_PROJECT_DISPLAY_NAME="$I3PM_PROJECT_DISPLAY_NAME" \
        --setenv=I3PM_PROJECT_ICON="$I3PM_PROJECT_ICON" \
        --setenv=I3PM_SCOPE="$I3PM_SCOPE" \
        --setenv=I3PM_ACTIVE="$I3PM_ACTIVE" \
        --setenv=I3PM_LAUNCH_TIME="$I3PM_LAUNCH_TIME" \
        --setenv=I3PM_LAUNCHER_PID="$I3PM_LAUNCHER_PID" \
        --setenv=DISPLAY="''${DISPLAY:-:0}" \
        --setenv=HOME="$HOME" \
        --setenv=PATH="$PATH" \
        ${pkgs.alacritty}/bin/alacritty -e bash -c "$NVIM_CMD"
    else
      # Fallback without systemd-run
      exec ${pkgs.alacritty}/bin/alacritty -e bash -c "$NVIM_CMD"
    fi
  '';

  walkerOpenInNvimCmd = lib.getExe walkerOpenInNvim;

  # Walker project list script - outputs formatted project list for Walker menu
  # Reordered to show inactive projects first, active project last with visual indicator
  # Fixed: Use .active.project_name instead of .active.name to match i3pm JSON structure
  walkerProjectList = pkgs.writeShellScriptBin "walker-project-list" ''
    #!/usr/bin/env bash
    # List projects for Walker menu
    # Feature 101: Uses worktree list and active-worktree.json
    set -euo pipefail

    I3PM="${config.home.profileDirectory}/bin/i3pm"

    # Feature 101: Get worktrees JSON from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"

    if [ ! -f "$REPOS_FILE" ]; then
      exit 0
    fi

    ACTIVE_PROJECT=$("$I3PM" project current --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.name // ""' 2>/dev/null || echo "")

    # Add "Clear Project" option if a project is active
    if [ -n "$ACTIVE_PROJECT" ] && [ "$ACTIVE_PROJECT" != "null" ]; then
      echo "∅ Clear Project (Global Mode)	__CLEAR__"
    fi

    # Build worktree list from repos.json
    ${pkgs.jq}/bin/jq -r '
      .repositories[] |
      . as $repo |
      .worktrees[] |
      {
        qualified_name: ($repo.account + "/" + $repo.name + ":" + .branch),
        display_name: $repo.name,
        branch: .branch,
        directory: .path,
        is_main: .is_main
      } |
      (if .branch == "main" or .branch == "master" then "📦" else "🌿" end) + " " +
      (if (.branch | test("^[0-9]+-")) then (.branch | capture("^(?<num>[0-9]+)-") | .num) + " - " else "" end) +
      .display_name + ":" + .branch +
      " [" + (.directory | gsub("'$HOME'"; "~")) + "]" +
      (if .qualified_name == "'"$ACTIVE_PROJECT"'" then " 🟢 ACTIVE" else "" end) +
      "\t" + .qualified_name
    ' "$REPOS_FILE" | sort -t'	' -k1,1
  '';

  # Walker project switch script - parses selection and switches project
  # Feature 101: Uses worktree switch command
  walkerProjectSwitch = pkgs.writeShellScriptBin "walker-project-switch" ''
    #!/usr/bin/env bash
    # Switch to selected project from Walker
    # Feature 101: Uses worktree switch with qualified names
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    I3PM="${config.home.profileDirectory}/bin/i3pm"
    I3PM_WS_MODE="${config.home.profileDirectory}/bin/i3pm-workspace-mode"
    SELECTED="$1"

    # Feature 072 fix: Close preview window before switching projects
    $I3PM_WS_MODE cancel 2>/dev/null || true

    # Extract qualified name (everything after the tab character)
    QUALIFIED_NAME=$(echo "$SELECTED" | ${pkgs.coreutils}/bin/cut -f2)

    # Handle special cases
    if [ "$QUALIFIED_NAME" = "__CLEAR__" ]; then
      $I3PM project clear >/dev/null 2>&1
    else
      # Feature 101: Local project list should always enter local context.
      $I3PM worktree switch --local "$QUALIFIED_NAME" >/dev/null 2>&1
    fi
  '';

  # Walker SSH worktree list script - discovers remote worktrees via Tailscale SSH
  # Output format: "display\tbase64(payload-json)"
  walkerSshWorktreeList = pkgs.writeShellScriptBin "walker-ssh-worktree-list" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="worktrees"
    if [[ "''${1:-}" == "--repos-only" ]]; then
      MODE="repos"
    fi

    REMOTE_HOST="${remoteWorktreeHost}"
    REMOTE_USER="${remoteWorktreeUser}"
    REMOTE_TARGET="$REMOTE_USER@$REMOTE_HOST"

    CACHE_DIR="$HOME/.cache/i3pm"
    CACHE_FILE="$CACHE_DIR/remote-''${REMOTE_HOST}-repos.json"
    LOCK_FILE="''${CACHE_FILE}.refresh.lock"
    CACHE_TTL_SECONDS=180
    LOCK_STALE_SECONDS=300
    REMOTE_REPOS_FILE="~/.config/i3/repos.json"

    LOCAL_REPOS_FILE="$HOME/.config/i3/repos.json"
    mkdir -p "$CACHE_DIR"

    cleanup_stale_refresh_lock() {
      if [[ ! -e "$LOCK_FILE" ]]; then
        return 0
      fi

      local now mtime age
      now=$(date +%s)
      mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
      if ! [[ "$mtime" =~ ^[0-9]+$ ]]; then
        mtime=0
      fi

      age=$((now - mtime))
      if (( age < 0 )); then
        age=0
      fi

      # If a previous refresh crashed and left a lock behind, clear it so
      # remote index updates can resume automatically.
      if (( age >= LOCK_STALE_SECONDS )); then
        rm -f "$LOCK_FILE" || true
      fi
    }

    emit_error_entry() {
      local msg="$1"
      local payload
      payload=$(${pkgs.jq}/bin/jq -cn --arg action "error" --arg message "$msg" '{action: $action, message: $message}')
      local encoded
      encoded=$(printf '%s' "$payload" | ${pkgs.coreutils}/bin/base64 -w0)
      printf '⚠ %s\t%s\n' "$msg" "$encoded"
    }

    should_refresh_cache() {
      if [[ ! -f "$CACHE_FILE" ]]; then
        return 0
      fi
      local now mtime age
      now=$(date +%s)
      mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
      age=$((now - mtime))
      [[ "$age" -ge "$CACHE_TTL_SECONDS" ]]
    }

    fetch_remote_repos() {
      local tmp
      tmp=$(${pkgs.coreutils}/bin/mktemp "''${CACHE_FILE}.tmp.XXXXXX")

      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_TARGET" "cat $REMOTE_REPOS_FILE" >"$tmp" 2>/dev/null \
        && ${pkgs.jq}/bin/jq -e '.repositories and (.repositories | type == "array")' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$CACHE_FILE"
        return 0
      fi

      rm -f "$tmp"
      return 1
    }

    refresh_remote_repos_async() {
      cleanup_stale_refresh_lock
      (
        if [[ -e "$LOCK_FILE" ]]; then
          exit 0
        fi
        : >"$LOCK_FILE" || exit 0
        trap 'rm -f "$LOCK_FILE"' EXIT
        fetch_remote_repos >/dev/null 2>&1 || true
      ) >/dev/null 2>&1 &
    }

    USING_STALE_CACHE="false"
    if [[ ! -f "$CACHE_FILE" ]]; then
      if ! fetch_remote_repos; then
        emit_error_entry "Remote index unavailable (''${REMOTE_HOST}). Run walker-ssh-worktree-diagnose."
        exit 0
      fi
    elif should_refresh_cache; then
      # Serve cached data immediately to keep Walker responsive, then refresh in background.
      USING_STALE_CACHE="true"
      refresh_remote_repos_async
      if [[ ! -f "$CACHE_FILE" ]]; then
        if ! fetch_remote_repos; then
          emit_error_entry "Remote index unavailable (''${REMOTE_HOST}). Run walker-ssh-worktree-diagnose."
          exit 0
        fi
      fi
    fi

    if [[ ! -f "$CACHE_FILE" ]]; then
      emit_error_entry "No remote cache available for ''${REMOTE_HOST}"
      exit 0
    fi

    ACTIVE_QUALIFIED=$("${config.home.profileDirectory}/bin/i3pm" project current --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.name // ""' 2>/dev/null || echo "")

    LOCAL_REPOS=()
    LOCAL_WORKTREES=()
    if [[ -f "$LOCAL_REPOS_FILE" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && LOCAL_REPOS+=("$line")
      done < <(${pkgs.jq}/bin/jq -r '.repositories[]? | "\(.account)/\(.name)"' "$LOCAL_REPOS_FILE")

      while IFS= read -r line; do
        [[ -n "$line" ]] && LOCAL_WORKTREES+=("$line")
      done < <(${pkgs.jq}/bin/jq -r '.repositories[]? as $r | ($r.worktrees[]? | "\($r.account)/\($r.name):\(.branch)")' "$LOCAL_REPOS_FILE")
    fi

    array_contains() {
      local needle="$1"
      shift || true
      local value
      for value in "$@"; do
        if [[ "$value" == "$needle" ]]; then
          return 0
        fi
      done
      return 1
    }

    compact_path_tail() {
      local path="$1"
      local keep="''${2:-3}"
      if [[ -z "$path" ]]; then
        printf '%s' "-"
        return
      fi

      local normalized="''${path%/}"
      IFS='/' read -r -a segments <<<"$normalized"
      local count="''${#segments[@]}"

      if ! [[ "$keep" =~ ^[0-9]+$ ]]; then
        keep=3
      fi
      if (( keep < 1 )); then
        keep=1
      fi

      if (( count <= keep )); then
        printf '%s' "$normalized"
        return
      fi

      local start=$((count - keep))
      local compact="…"
      local i
      for ((i = start; i < count; i++)); do
        compact="$compact/''${segments[$i]}"
      done
      printf '%s' "$compact"
    }

    if [[ "$MODE" == "repos" ]]; then
      ${pkgs.jq}/bin/jq -r '
        [ .repositories[]? | {
            host: "ryzen",
            account: .account,
            repo: .name,
            qualified_repo: (.account + "/" + .name),
            remote_repo_path: (.path // ""),
            remote_url: (.remote_url // ""),
            default_branch: (.default_branch // "main"),
            action: "create"
          }
        ]
        | sort_by(.account, .repo)
        | .[]
        | [
            .qualified_repo,
            .remote_repo_path,
            .default_branch,
            (@base64)
          ]
        | @tsv
      ' "$CACHE_FILE" | while IFS=$'\t' read -r qualified_repo remote_repo_path default_branch repo_b64; do
        state_label="🟨 base:$default_branch"
        if [[ "$USING_STALE_CACHE" == "true" ]]; then
          state_label="$state_label, stale"
        fi
        short_remote_path=$(echo "$remote_repo_path" | ${pkgs.gnused}/bin/sed "s#^/home/$REMOTE_USER#~#")
        compact_remote_path=$(compact_path_tail "$short_remote_path" 3)
        encoded="$repo_b64"
        printf '%s | %s | %s\t%s\n' "$qualified_repo" "$state_label" "$compact_remote_path" "$encoded"
      done
      exit 0
    fi

    ${pkgs.jq}/bin/jq -r '
      [
        .repositories[]? as $repo |
        ($repo.worktrees // [])[]? |
        {
          host: "ryzen",
          account: $repo.account,
          repo: $repo.name,
          branch: .branch,
          qualified_name: ($repo.account + "/" + $repo.name + ":" + .branch),
          remote_repo_path: ($repo.path // ""),
          remote_worktree_path: (.path // (($repo.path // "") + "/" + .branch)),
          remote_url: ($repo.remote_url // ""),
          default_branch: ($repo.default_branch // "main"),
          is_main: ((.branch == ($repo.default_branch // "main")) or (.branch == "main") or (.branch == "master")),
          action: "switch"
        }
      ]
      | sort_by(.account, .repo, (if .is_main then 0 else 1 end), .branch)
      | .[]
      | [
          .qualified_name,
          (.account + "/" + .repo),
          .remote_worktree_path,
          (.is_main | tostring),
          (@base64)
        ]
      | @tsv
    ' "$CACHE_FILE" | while IFS=$'\t' read -r qualified_name qualified_repo remote_worktree_path is_main item_b64; do

      local_repo_exists="false"
      local_worktree_exists="false"
      if array_contains "$qualified_repo" "''${LOCAL_REPOS[@]:-}"; then
        local_repo_exists="true"
      fi
      if array_contains "$qualified_name" "''${LOCAL_WORKTREES[@]:-}"; then
        local_worktree_exists="true"
      fi

      link_icon="☁"
      if [[ "$local_worktree_exists" == "true" ]]; then
        link_icon="↔"
      fi

      scope_tag="ssh-only"
      scope_color="🟦"
      if [[ "$local_worktree_exists" == "true" ]]; then
        scope_tag="local+ssh"
        scope_color="🟢"
      fi

      short_remote_path=$(echo "$remote_worktree_path" | ${pkgs.gnused}/bin/sed "s#^/home/$REMOTE_USER#~#")
      compact_remote_path=$(compact_path_tail "$short_remote_path" 3)

      state_label="$scope_color $scope_tag"
      if [[ "$qualified_name" == "$ACTIVE_QUALIFIED" ]]; then
        state_label="$state_label, active"
      fi
      if [[ "$USING_STALE_CACHE" == "true" ]]; then
        state_label="$state_label, stale"
      fi

      encoded="$item_b64"

      printf '%s | %s | %s\t%s\n' "$qualified_name" "$state_label" "$compact_remote_path" "$encoded"
    done
  '';

  # Materialize/sync a remote worktree locally, configure SSH profile, then switch.
  walkerSshWorktreeMaterialize = pkgs.writeShellScriptBin "walker-ssh-worktree-materialize" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ $# -eq 0 ]]; then
      echo "Usage: walker-ssh-worktree-materialize <payload-base64>" >&2
      exit 1
    fi

    payload_b64="$1"
    payload_json=$(printf '%s' "$payload_b64" | ${pkgs.coreutils}/bin/base64 -d 2>/dev/null || true)

    if [[ -z "$payload_json" ]]; then
      echo "Invalid payload" >&2
      exit 1
    fi

    notify() {
      local msg="$1"
      if command -v ${pkgs.libnotify}/bin/notify-send >/dev/null 2>&1; then
        ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "$msg"
      fi
      echo "$msg"
    }

    log_step() {
      echo "[walker-ssh-worktree] $1" >&2
    }

    action=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.action // ""')
    if [[ "$action" == "error" ]]; then
      msg=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.message // "Unknown error"')
      notify "$msg"
      exit 1
    fi

    host=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.host // "ryzen"')
    user=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.user // "vpittamp"')
    port=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.port // 22')
    account=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.account // ""')
    repo=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.repo // ""')
    branch=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.branch // ""')
    qualified_name=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.qualified_name // ""')
    remote_repo_path=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.remote_repo_path // ""')
    remote_worktree_path=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.remote_worktree_path // ""')
    remote_url=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.remote_url // ""')
    default_branch=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.default_branch // "main"')

    if [[ -z "$account" || -z "$repo" || -z "$branch" || -z "$qualified_name" ]]; then
      notify "Invalid selection payload (missing repo/branch metadata)"
      exit 1
    fi

    if [[ -z "$remote_worktree_path" && -n "$remote_repo_path" ]]; then
      remote_worktree_path="$remote_repo_path/$branch"
    fi

    local_repo_path="$HOME/repos/$account/$repo"
    local_bare_path="$local_repo_path/.bare"
    local_target_path="$local_repo_path/$branch"
    local_repo_qualified="$account/$repo"
    repos_refreshed="false"

    log_step "ensure-local-repo qualified=$local_repo_qualified"
    if [[ ! -d "$local_bare_path" ]]; then
      if [[ -z "$remote_url" ]]; then
        notify "Cannot materialize $qualified_name: remote_url missing"
        exit 1
      fi
      if ! i3pm clone "$remote_url" --account "$account" >/tmp/walker-ssh-clone.log 2>&1; then
        notify "Clone failed for $local_repo_qualified (see /tmp/walker-ssh-clone.log)"
        exit 1
      fi
      repos_refreshed="false"
    fi

    local_worktree_exists="false"
    if [[ -d "$local_target_path" ]]; then
      local_worktree_exists="true"
    elif [[ -d "$local_bare_path" ]]; then
      if ${pkgs.git}/bin/git -C "$local_bare_path" worktree list --porcelain | ${pkgs.gawk}/bin/awk -v b="$branch" '
        /^branch refs\/heads\// {
          if (substr($0, 18) == b) {
            found=1
          }
        }
        END { exit(found ? 0 : 1) }
      ' >/dev/null 2>&1; then
        local_worktree_exists="true"
      fi
    fi

    if [[ "$local_worktree_exists" != "true" ]]; then
      log_step "create-local-worktree qualified=$qualified_name"
      ${pkgs.git}/bin/git -C "$local_bare_path" fetch --all --prune >/dev/null 2>&1 || true

      if [[ -e "$local_target_path" ]]; then
        notify "Local target path already exists: $local_target_path"
        exit 1
      fi

      if ${pkgs.git}/bin/git -C "$local_bare_path" show-ref --verify --quiet "refs/heads/$branch"; then
        if ! ${pkgs.git}/bin/git -C "$local_bare_path" worktree add "$local_target_path" "$branch" >/tmp/walker-ssh-worktree-add.log 2>&1; then
          notify "Failed to add existing local branch worktree (see /tmp/walker-ssh-worktree-add.log)"
          exit 1
        fi
      elif ${pkgs.git}/bin/git -C "$local_bare_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        if ! ${pkgs.git}/bin/git -C "$local_bare_path" worktree add -b "$branch" "$local_target_path" "origin/$branch" >/tmp/walker-ssh-worktree-add.log 2>&1; then
          notify "Failed to add worktree from origin/$branch (see /tmp/walker-ssh-worktree-add.log)"
          exit 1
        fi
        repos_refreshed="false"
      else
        if ! i3pm worktree create "$branch" --repo "$local_repo_qualified" --from "$default_branch" >/tmp/walker-ssh-worktree-create.log 2>&1; then
          notify "Failed to create local worktree from $default_branch (see /tmp/walker-ssh-worktree-create.log)"
          exit 1
        fi
        repos_refreshed="false"
      fi
    fi

    if [[ -z "$remote_worktree_path" ]]; then
      notify "Remote worktree path missing for $qualified_name"
      exit 1
    fi

    log_step "set-remote-profile qualified=$qualified_name host=$host"
    if ! i3pm worktree remote set "$qualified_name" --host "$host" --user "$user" --port "$port" --dir "$remote_worktree_path" >/tmp/walker-ssh-remote-set.log 2>&1; then
      notify "Failed to set SSH profile for $qualified_name (see /tmp/walker-ssh-remote-set.log)"
      exit 1
    fi

    log_step "switch qualified=$qualified_name"
    if ! i3pm worktree switch "$qualified_name" >/tmp/walker-ssh-switch.log 2>&1; then
      # Fast path: avoid expensive discover unless switch cannot resolve worktree.
      if [[ "$repos_refreshed" != "true" ]]; then
        log_step "refresh-repo-index"
        i3pm discover --quiet >/dev/null 2>&1 || true
        repos_refreshed="true"
      fi
      if ! i3pm worktree switch "$qualified_name" >/tmp/walker-ssh-switch.log 2>&1; then
        notify "Failed to switch to $qualified_name (see /tmp/walker-ssh-switch.log)"
        exit 1
      fi
    fi

    notify "Ready: $qualified_name on $host"
  '';

  # Select script - unwraps Walker line payload and delegates to materialize workflow.
  walkerSshWorktreeSelect = pkgs.writeShellScriptBin "walker-ssh-worktree-select" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ $# -eq 0 ]]; then
      exit 0
    fi

    selected="$1"
    payload=$(printf '%s' "$selected" | ${pkgs.coreutils}/bin/cut -f2-)
    if [[ -z "$payload" || "$payload" == "$selected" ]]; then
      payload="$selected"
    fi

    exec walker-ssh-worktree-materialize "$payload"
  '';

  # Create script - creates remote worktree on ryzen then materializes/switches locally.
  walkerSshWorktreeCreate = pkgs.writeShellScriptBin "walker-ssh-worktree-create" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ $# -eq 0 ]]; then
      exit 0
    fi

    selected="$1"
    payload=$(printf '%s' "$selected" | ${pkgs.coreutils}/bin/cut -f2-)
    if [[ -z "$payload" || "$payload" == "$selected" ]]; then
      payload="$selected"
    fi

    payload_json=$(printf '%s' "$payload" | ${pkgs.coreutils}/bin/base64 -d 2>/dev/null || true)
    if [[ -z "$payload_json" ]]; then
      echo "Invalid payload" >&2
      exit 1
    fi

    host=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.host // "ryzen"')
    user=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.user // "vpittamp"')
    port=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.port // 22')
    account=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.account // ""')
    repo=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.repo // ""')
    remote_repo_path=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.remote_repo_path // ""')
    remote_url=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.remote_url // ""')
    default_branch=$(echo "$payload_json" | ${pkgs.jq}/bin/jq -r '.default_branch // "main"')

    if [[ -z "$account" || -z "$repo" || -z "$remote_repo_path" ]]; then
      echo "Invalid repo payload" >&2
      exit 1
    fi

    prompt="New branch for $account/$repo"
    branch="''${WALKER_SSH_WORKTREE_CREATE_BRANCH:-}"
    if [[ -z "$branch" ]] && command -v ${pkgs.walker}/bin/walker >/dev/null 2>&1; then
      branch=$(printf "%s" "" | ${pkgs.walker}/bin/walker --dmenu -p "$prompt" 2>/dev/null || true)
    fi
    if [[ -z "$branch" ]] && command -v ${pkgs.rofi}/bin/rofi >/dev/null 2>&1; then
      branch=$(printf "%s" "" | ${pkgs.rofi}/bin/rofi -dmenu -p "$prompt" 2>/dev/null || true)
    fi

    branch=$(echo "$branch" | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$branch" ]]; then
      exit 0
    fi

    if ! ${pkgs.git}/bin/git check-ref-format --branch "$branch" >/dev/null 2>&1; then
      ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "Invalid branch name: $branch"
      exit 1
    fi

    remote_worktree_path=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$port" "$user@$host" bash -s -- "$remote_repo_path" "$branch" "$default_branch" <<'REMOTE'
set -euo pipefail

repo_path="$1"
branch="$2"
base_branch="$3"
bare_path="$repo_path/.bare"

if [[ ! -d "$bare_path" ]]; then
  echo "remote bare repo missing: $bare_path" >&2
  exit 2
fi

git -C "$bare_path" fetch --all --prune >/dev/null 2>&1 || true

existing_path=$(git -C "$bare_path" worktree list --porcelain | awk -v b="$branch" '
  BEGIN { path="" }
  /^worktree / { path=substr($0, 10) }
  /^branch refs\/heads\// {
    if (substr($0, 18) == b) {
      print path
      exit
    }
  }
')

if [[ -n "$existing_path" ]]; then
  echo "$existing_path"
  exit 0
fi

target_path="$repo_path/$branch"
if [[ -e "$target_path" ]]; then
  echo "remote target path already exists: $target_path" >&2
  exit 3
fi

if git -C "$bare_path" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$bare_path" worktree add "$target_path" "$branch" >/dev/null 2>&1
elif git -C "$bare_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  git -C "$bare_path" worktree add -b "$branch" "$target_path" "origin/$branch" >/dev/null 2>&1
else
  git -C "$bare_path" worktree add -b "$branch" "$target_path" "$base_branch" >/dev/null 2>&1
fi

echo "$target_path"
REMOTE
    )

    if [[ -z "$remote_worktree_path" ]]; then
      ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "Remote create failed for $account/$repo:$branch"
      exit 1
    fi

    qualified_name="$account/$repo:$branch"

    switch_payload=$(${pkgs.jq}/bin/jq -cn \
      --arg action "switch" \
      --arg host "$host" \
      --arg user "$user" \
      --argjson port "$port" \
      --arg account "$account" \
      --arg repo "$repo" \
      --arg branch "$branch" \
      --arg qualified_name "$qualified_name" \
      --arg remote_repo_path "$remote_repo_path" \
      --arg remote_worktree_path "$remote_worktree_path" \
      --arg remote_url "$remote_url" \
      --arg default_branch "$default_branch" \
      '{
        action: $action,
        host: $host,
        user: $user,
        port: $port,
        account: $account,
        repo: $repo,
        branch: $branch,
        qualified_name: $qualified_name,
        remote_repo_path: $remote_repo_path,
        remote_worktree_path: $remote_worktree_path,
        remote_url: $remote_url,
        default_branch: $default_branch,
        is_main: false
      }')

    switch_payload_b64=$(printf '%s' "$switch_payload" | ${pkgs.coreutils}/bin/base64 -w0)
    exec walker-ssh-worktree-materialize "$switch_payload_b64"
  '';

  # Force cache refresh and print list (useful for diagnostics/manual workflows).
  walkerSshWorktreeRefresh = pkgs.writeShellScriptBin "walker-ssh-worktree-refresh" ''
    #!/usr/bin/env bash
    set -euo pipefail
    cache="$HOME/.cache/i3pm/remote-${remoteWorktreeHost}-repos.json"
    rm -f "$cache"
    walker-ssh-worktree-list >/dev/null
    ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "Refreshed remote index from ${remoteWorktreeHost}"
  '';

  # Connectivity diagnostics for remote ssh worktree workflow.
  walkerSshWorktreeDiagnose = pkgs.writeShellScriptBin "walker-ssh-worktree-diagnose" ''
    #!/usr/bin/env bash
    set -euo pipefail

    host="${remoteWorktreeHost}"
    user="${remoteWorktreeUser}"
    target="$user@$host"
    ok=true

    echo "[ssh-worktree] target=$target"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "echo connected" >/dev/null 2>&1; then
      echo "  ssh: ok"
    else
      echo "  ssh: failed"
      ok=false
    fi

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "test -f ~/.config/i3/repos.json" >/dev/null 2>&1; then
      count=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "jq '.repositories | length' ~/.config/i3/repos.json 2>/dev/null || echo 0" 2>/dev/null || echo 0)
      echo "  remote repos.json: ok (repositories=$count)"
    else
      echo "  remote repos.json: missing/unreadable"
      ok=false
    fi

    if command -v i3pm >/dev/null 2>&1; then
      echo "  local i3pm: $(i3pm --version 2>/dev/null || echo unavailable)"
    else
      echo "  local i3pm: missing"
      ok=false
    fi

    if [[ "$ok" == "true" ]]; then
      ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "Diagnostics passed for $target"
      exit 0
    else
      ${pkgs.libnotify}/bin/notify-send "SSH Worktree" "Diagnostics failed for $target"
      exit 1
    fi
  '';

  walkerProjectListCmd = lib.getExe walkerProjectList;
  walkerProjectSwitchCmd = lib.getExe walkerProjectSwitch;

  walkerOnePasswordCacheRefresh = pkgs.writeShellScriptBin "walker-1password-cache-refresh" ''
    #!/usr/bin/env bash
    set -euo pipefail

    cache_dir="$HOME/.cache/walker-1password"
    lock_file="$cache_dir/refresh.lock"
    last_attempt_file="$cache_dir/last-attempt"
    tmp_dir=$(${pkgs.coreutils}/bin/mktemp -d)
    op_cmd="/run/wrappers/bin/op"

    mkdir -p "$cache_dir"
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp_dir"' EXIT

    if [[ ! -x "$op_cmd" ]]; then
      op_cmd="${pkgs._1password-cli}/bin/op"
    fi

    exec 9>"$lock_file"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    ${pkgs.coreutils}/bin/date +%s >"$last_attempt_file"

    run_op() {
      local script="$1"
      shift

      ${pkgs.systemd}/bin/systemd-run --user --wait --pipe --quiet \
        ${pkgs.bashInteractive}/bin/bash -ilc "$script" _ "$@"
    }

    fetch_vault() {
      local vault="$1"
      local outfile="$2"

      if [[ "$op_cmd" == "/run/wrappers/bin/op" ]]; then
        run_op '/run/wrappers/bin/op item list --vault "$1" --format=json' "$vault" >"$outfile"
      else
        run_op '${pkgs._1password-cli}/bin/op item list --vault "$1" --format=json' "$vault" >"$outfile"
      fi
    }

    fetch_vault "ampm3rvesendx6mvksmu2ydh6e" "$tmp_dir/personal.json"
    fetch_vault "cu4rqh2szvjlrumhepqe2twsmm" "$tmp_dir/employee.json"

    ${pkgs.jq}/bin/jq -s 'add | map({
      id,
      title,
      additional_information: (.additional_information // ""),
      category: ((.category // "LOGIN") | ascii_downcase)
    })' \
      "$tmp_dir/personal.json" \
      "$tmp_dir/employee.json" \
      >"$tmp_dir/items.json"

    ${pkgs.coreutils}/bin/mv "$tmp_dir/items.json" "$cache_dir/items.json"
  '';

  walkerOnePasswordList = pkgs.writeShellScriptBin "walker-1password-list" ''
    #!/usr/bin/env bash
    set -euo pipefail

    cache_dir="$HOME/.cache/walker-1password"
    cache_file="$cache_dir/items.json"
    lock_file="$cache_dir/refresh.lock"
    last_attempt_file="$cache_dir/last-attempt"
    ttl_seconds=900
    retry_delay_seconds=300

    mkdir -p "$cache_dir"

    now=$(${pkgs.coreutils}/bin/date +%s)
    refresh_needed=false
    if [[ ! -f "$cache_file" ]]; then
      refresh_needed=true
    else
      mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$cache_file" 2>/dev/null || echo 0)
      age=$((now - mtime))
      if (( age >= ttl_seconds )); then
        refresh_needed=true
      fi
    fi

    refresh_recently_attempted=false
    if [[ -f "$last_attempt_file" ]]; then
      last_attempt=$(<"$last_attempt_file")
      if [[ "$last_attempt" =~ ^[0-9]+$ ]] && (( now - last_attempt < retry_delay_seconds )); then
        refresh_recently_attempted=true
      fi
    fi

    refresh_running=false
    exec 9>"$lock_file"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      refresh_running=true
    else
      ${pkgs.util-linux}/bin/flock -u 9
    fi

    if [[ "$refresh_needed" == "true" ]]; then
      if [[ "$refresh_running" == "true" || "$refresh_recently_attempted" == "true" ]]; then
        :
      elif [[ -f "$cache_file" ]]; then
        ${pkgs.coreutils}/bin/date +%s >"$last_attempt_file"
        (${lib.getExe walkerOnePasswordCacheRefresh} >/dev/null 2>&1) &
      else
        ${pkgs.coreutils}/bin/date +%s >"$last_attempt_file"
        ${lib.getExe walkerOnePasswordCacheRefresh} >/dev/null 2>&1 || exit 0
      fi
    fi

    [[ -f "$cache_file" ]] || exit 0

    ${pkgs.jq}/bin/jq -r '.[] | [.title, .additional_information, .id, .category] | @tsv' "$cache_file"
  '';

  walkerOnePasswordCopy = pkgs.writeShellScriptBin "walker-1password-copy" ''
    #!/usr/bin/env bash
    set -euo pipefail

    mode="''${1:-password}"
    item_id="''${2:-}"
    op_cmd="/run/wrappers/bin/op"

    if [[ -z "$item_id" ]]; then
      exit 1
    fi

    if [[ ! -x "$op_cmd" ]]; then
      op_cmd="${pkgs._1password-cli}/bin/op"
    fi

    run_op() {
      local script="$1"
      shift

      ${pkgs.systemd}/bin/systemd-run --user --wait --pipe --quiet \
        ${pkgs.bashInteractive}/bin/bash -ilc "$script" _ "$@"
    }

    case "$mode" in
      password)
        if [[ "$op_cmd" == "/run/wrappers/bin/op" ]]; then
          value=$(run_op '/run/wrappers/bin/op item get "$1" --fields password --reveal' "$item_id")
        else
          value=$(run_op '${pkgs._1password-cli}/bin/op item get "$1" --fields password --reveal' "$item_id")
        fi
        label="password"
        ;;
      username)
        if [[ "$op_cmd" == "/run/wrappers/bin/op" ]]; then
          value=$(run_op '/run/wrappers/bin/op item get "$1" --fields username --reveal' "$item_id")
        else
          value=$(run_op '${pkgs._1password-cli}/bin/op item get "$1" --fields username --reveal' "$item_id")
        fi
        label="username"
        ;;
      otp)
        if [[ "$op_cmd" == "/run/wrappers/bin/op" ]]; then
          value=$(run_op '/run/wrappers/bin/op item get "$1" --otp' "$item_id")
        else
          value=$(run_op '${pkgs._1password-cli}/bin/op item get "$1" --otp' "$item_id")
        fi
        label="otp"
        ;;
      *)
        echo "Unsupported mode: $mode" >&2
        exit 1
        ;;
    esac

    [[ -n "$value" ]] || exit 1

    printf '%s' "$value" | ${clipboardSyncScript}
    ${pkgs.libnotify}/bin/notify-send "1Password" "Copied $label"
  '';

  # Walker window action scripts - enhanced window management via Walker
  walkerWindowClose = pkgs.writeShellScriptBin "walker-window-close" ''
    #!/usr/bin/env bash
    # Close/kill the selected window
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    if [ $# -eq 0 ]; then
      exit 0
    fi

    WINDOW_ID="$1"
    REQUEST=$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WINDOW_ID" '{jsonrpc:"2.0", method:"window.action", params:{window_id:$window_id, action:"kill"}, id:1}')
    ${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$REQUEST" >/dev/null
  '';

  walkerWindowFloat = pkgs.writeShellScriptBin "walker-window-float" ''
    #!/usr/bin/env bash
    # Toggle floating mode for the selected window
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    if [ $# -eq 0 ]; then
      exit 0
    fi

    WINDOW_ID="$1"
    REQUEST=$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WINDOW_ID" '{jsonrpc:"2.0", method:"window.action", params:{window_id:$window_id, action:"floating_toggle"}, id:1}')
    ${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$REQUEST" >/dev/null
  '';

  walkerWindowFullscreen = pkgs.writeShellScriptBin "walker-window-fullscreen" ''
    #!/usr/bin/env bash
    # Toggle fullscreen mode for the selected window
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    if [ $# -eq 0 ]; then
      exit 0
    fi

    WINDOW_ID="$1"
    REQUEST=$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WINDOW_ID" '{jsonrpc:"2.0", method:"window.action", params:{window_id:$window_id, action:"fullscreen_toggle"}, id:1}')
    ${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$REQUEST" >/dev/null
  '';

  walkerWindowScratchpad = pkgs.writeShellScriptBin "walker-window-scratchpad" ''
    #!/usr/bin/env bash
    # Move the selected window to scratchpad
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    if [ $# -eq 0 ]; then
      exit 0
    fi

    WINDOW_ID="$1"
    REQUEST=$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WINDOW_ID" '{jsonrpc:"2.0", method:"window.action", params:{window_id:$window_id, action:"move_scratchpad"}, id:1}')
    ${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$REQUEST" >/dev/null
  '';

  walkerWindowInfo = pkgs.writeShellScriptBin "walker-window-info" ''
    #!/usr/bin/env bash
    # Show detailed window information
    set -euo pipefail
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    if [ $# -eq 0 ]; then
      exit 0
    fi

    WINDOW_ID="$1"
    REQUEST=$(${pkgs.jq}/bin/jq -nc '{jsonrpc:"2.0", method:"get_windows", params:{}, id:1}')
    RESPONSE=$(${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$REQUEST" 2>/dev/null || echo '{}')
    WINDOW_INFO=$(printf '%s\n' "$RESPONSE" | ${pkgs.jq}/bin/jq -r --argjson window_id "$WINDOW_ID" '
      .result
      | .. | objects
      | select((.id? // 0) == $window_id)
    ')

    # Display in a notification using our terminal
    echo "$WINDOW_INFO" | ${pkgs.jq}/bin/jq '.' | ${pkgs.rofi}/bin/rofi -dmenu -p "Window Info" -theme-str 'window {width: 800px; height: 600px;}' -no-custom
  '';

  # Walker Window Manager - Two-stage dmenu-based window management
  # Walker Claude Sessions - List and resume Claude Code sessions
  walkerClaudeSessions = pkgs.writeShellScriptBin "walker-claude-sessions" ''
    #!/usr/bin/env bash
    # List and resume Claude Code sessions via Walker
    set -euo pipefail

    # Function to extract session metadata with message preview
    get_session_metadata() {
        local session_file="$1"
        local session_id=$(basename "$session_file" .jsonl)

        # Skip agent files
        if [[ "$session_id" == agent-* ]]; then
            return
        fi

        # Extract first 3 messages (user + assistant exchanges)
        # For assistant messages, extract text from content array
        local messages=$(${pkgs.jq}/bin/jq -r '
            select(.type == "user" or .type == "assistant") |
            {
                type: .type,
                timestamp: .timestamp,
                branch: .gitBranch,
                content: (
                    if .type == "assistant" then
                        (.message.content[] | select(.type == "text") | .text)
                    else
                        .message.content
                    end
                )
            } | @json
        ' "$session_file" 2>/dev/null | head -3)

        if [ -z "$messages" ]; then
            return
        fi

        # Parse first message for metadata
        local first_msg=$(echo "$messages" | head -1)
        local timestamp=$(echo "$first_msg" | ${pkgs.jq}/bin/jq -r '.timestamp')
        local branch=$(echo "$first_msg" | ${pkgs.jq}/bin/jq -r '.branch // "no-branch"')
        local first_content=$(echo "$first_msg" | ${pkgs.jq}/bin/jq -r '.content')

        # Extract first line as title (limit to 50 chars to make room for preview)
        local title=$(echo "$first_content" | head -1 | ${pkgs.coreutils}/bin/cut -c1-50)

        # If it's a command, clean it up
        if [[ "$title" == *"<command-"* ]]; then
            title=$(echo "$title" | ${pkgs.gnused}/bin/sed 's/<command-[^>]*>//g' | ${pkgs.gnused}/bin/sed 's/<\/command-[^>]*>//g')
        fi

        # Build preview from messages
        local preview=""
        local msg_count=0
        while IFS= read -r msg_line; do
            if [ -z "$msg_line" ]; then continue; fi

            local msg_type=$(echo "$msg_line" | ${pkgs.jq}/bin/jq -r '.type')
            local msg_content=$(echo "$msg_line" | ${pkgs.jq}/bin/jq -r '.content')

            # Get first line and limit length (text already extracted from assistant messages)
            msg_content=$(echo "$msg_content" | head -1 | ${pkgs.coreutils}/bin/cut -c1-120)

            # Clean command tags
            if [[ "$msg_content" == *"<command-"* ]]; then
                msg_content=$(echo "$msg_content" | ${pkgs.gnused}/bin/sed 's/<command-[^>]*>//g' | ${pkgs.gnused}/bin/sed 's/<\/command-[^>]*>//g')
            fi

            # Add to preview with prefix
            if [ "$msg_type" = "user" ]; then
                if [ $msg_count -eq 0 ]; then
                    preview="U: ''${msg_content}"
                else
                    preview="''${preview} → U: ''${msg_content}"
                fi
            else
                preview="''${preview} → A: ''${msg_content}"
            fi

            ((msg_count++))
            if [ $msg_count -ge 2 ]; then break; fi
        done <<< "$messages"

        # Trim preview to max 250 chars
        preview=$(echo "$preview" | ${pkgs.coreutils}/bin/cut -c1-250)

        # Convert timestamp to readable format
        local date_str=$(${pkgs.coreutils}/bin/date -d "$timestamp" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")

        # Output format: "date | branch | title | preview | session_id"
        echo "$date_str | $branch | $title | $preview | $session_id"
    }

    # Stage 1: List all sessions
    SESSIONS_DATA=""

    # Scan all project directories
    for project_dir in ~/.claude/projects/*/; do
        if [ -d "$project_dir" ]; then
            # Find all session .jsonl files
            for session_file in "$project_dir"/*.jsonl; do
                if [ -f "$session_file" ]; then
                    session_info=$(get_session_metadata "$session_file")
                    if [ -n "$session_info" ]; then
                        SESSIONS_DATA="$SESSIONS_DATA"$'\n'"$session_info"
                    fi
                fi
            done
        fi
    done

    if [ -z "$SESSIONS_DATA" ]; then
        ${pkgs.libnotify}/bin/notify-send "No Sessions" "No Claude Code sessions found"
        exit 0
    fi

    # Sort by date (most recent first) and show in walker
    SELECTED_SESSION=$(echo "$SESSIONS_DATA" | sort -r | ${pkgs.walker}/bin/walker --dmenu -p "Select Claude Session:")

    if [ -z "$SELECTED_SESSION" ]; then
        exit 0
    fi

    # Extract session ID from selection
    SESSION_ID=$(echo "$SELECTED_SESSION" | ${pkgs.gawk}/bin/awk -F'|' '{print $NF}' | ${pkgs.coreutils}/bin/tr -d ' ')

    # Stage 2: Select action
    ACTIONS="↩️  Resume Session
🔀  Fork Session (New ID)
📋  Copy Session ID
🔍  View Session Info"

    SELECTED_ACTION=$(echo "$ACTIONS" | ${pkgs.rofi}/bin/rofi -dmenu -p "Action on Session:")

    if [ -z "$SELECTED_ACTION" ]; then
        exit 0
    fi

    # Execute action
    case "$SELECTED_ACTION" in
        "↩️  Resume Session")
            ${pkgs.alacritty}/bin/alacritty -e bash -c "claude --resume $SESSION_ID; exec bash"
            ;;
        "🔀  Fork Session (New ID)")
            ${pkgs.alacritty}/bin/alacritty -e bash -c "claude --resume $SESSION_ID --fork-session; exec bash"
            ;;
        "📋  Copy Session ID")
            echo -n "$SESSION_ID" | ${pkgs.wl-clipboard}/bin/wl-copy
            ${pkgs.libnotify}/bin/notify-send "Copied" "Session ID: $SESSION_ID"
            ;;
        "🔍  View Session Info")
            ${pkgs.libnotify}/bin/notify-send "Session Info" "ID: $SESSION_ID"
            ;;
    esac
  '';

  walkerWindowManager = pkgs.writeShellScriptBin "walker-window-manager" ''
    #!/usr/bin/env bash
    # Walker-based window manager - two-stage selection
    set -euo pipefail

    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    daemon_window_action() {
      local window_id="$1"
      local action="$2"
      local request response
      request=$(${pkgs.jq}/bin/jq -nc \
        --arg action "$action" \
        --argjson window_id "$window_id" \
        '{jsonrpc:"2.0", method:"window.action", params:{window_id:$window_id, action:$action}, id:1}')
      response=$(${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
      [[ -n "$response" ]] || return 1
      printf '%s\n' "$response" | ${pkgs.jq}/bin/jq -e '.result.success == true' >/dev/null 2>&1
    }

    # Stage 1: Select a window
    get_windows() {
        local request response
        request=$(${pkgs.jq}/bin/jq -nc '{jsonrpc:"2.0", method:"get_windows", params:{}, id:1}')
        response=$(${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
        printf '%s\n' "$response" | ${pkgs.jq}/bin/jq -r '
            .result
            | .. | objects
            | select((.id? // 0) > 0 and (.pid? != null))
            | "\(.id)|\(.app_id // .class // "unknown")|\(.title // .name // "(untitled)")"
        ' | while IFS='|' read -r id app_id name; do
            # Format: "app_id - name [id]"
            echo "''${id}|''${app_id} - ''${name}"
        done
    }

    # Get list of windows
    WINDOWS=$(get_windows)

    if [ -z "$WINDOWS" ]; then
        ${pkgs.libnotify}/bin/notify-send "No Windows" "No windows found"
        exit 0
    fi

    # Show windows in walker dmenu mode
    SELECTED_WINDOW=$(echo "$WINDOWS" | ${pkgs.coreutils}/bin/cut -d'|' -f2 | ${pkgs.walker}/bin/walker --dmenu -p "Select Window:")

    if [ -z "$SELECTED_WINDOW" ]; then
        exit 0
    fi

    # Extract window ID from the original data
    WINDOW_ID=$(echo "$WINDOWS" | ${pkgs.gnugrep}/bin/grep -F "$SELECTED_WINDOW" | ${pkgs.coreutils}/bin/cut -d'|' -f1)

    # Stage 2: Select an action
    ACTIONS="❌  Close/Kill Window
⬜  Toggle Floating
⛶  Toggle Fullscreen
📦  Move to Scratchpad
⬅️  Move Left
➡️  Move Right
⬆️  Move Up
⬇️  Move Down
🔲  Split Horizontal
⬛  Split Vertical
📊  Layout Stacking
📑  Layout Tabbed
⚡  Layout Toggle Split"

    SELECTED_ACTION=$(echo "$ACTIONS" | ${pkgs.rofi}/bin/rofi -dmenu -p "Window Action:")

    if [ -z "$SELECTED_ACTION" ]; then
        exit 0
    fi

    # Execute the action
    ACTION_KEY=""
    case "$SELECTED_ACTION" in
        "❌  Close/Kill Window") ACTION_KEY="kill" ;;
        "⬜  Toggle Floating") ACTION_KEY="floating_toggle" ;;
        "⛶  Toggle Fullscreen") ACTION_KEY="fullscreen_toggle" ;;
        "📦  Move to Scratchpad") ACTION_KEY="move_scratchpad" ;;
        "⬅️  Move Left") ACTION_KEY="move_left" ;;
        "➡️  Move Right") ACTION_KEY="move_right" ;;
        "⬆️  Move Up") ACTION_KEY="move_up" ;;
        "⬇️  Move Down") ACTION_KEY="move_down" ;;
        "🔲  Split Horizontal") ACTION_KEY="split_h" ;;
        "⬛  Split Vertical") ACTION_KEY="split_v" ;;
        "📊  Layout Stacking") ACTION_KEY="layout_stacking" ;;
        "📑  Layout Tabbed") ACTION_KEY="layout_tabbed" ;;
        "⚡  Layout Toggle Split") ACTION_KEY="layout_toggle_split" ;;
    esac

    if [[ -z "$ACTION_KEY" ]] || ! daemon_window_action "$WINDOW_ID" "$ACTION_KEY"; then
      ${pkgs.libnotify}/bin/notify-send "Window Action Failed" "$SELECTED_ACTION"
      exit 1
    fi

    ${pkgs.libnotify}/bin/notify-send "Window Action" "Executed: $SELECTED_ACTION"
  '';

  # Feature 083: Walker monitor profile list script
  walkerMonitorList = pkgs.writeShellScriptBin "walker-monitor-list" ''
    #!/usr/bin/env bash
    # List monitor profiles for Walker menu
    set -euo pipefail

    PROFILES_DIR="$HOME/.config/sway/monitor-profiles"
    CURRENT_FILE="$HOME/.config/sway/monitor-profile.current"

    # Get current profile
    CURRENT=""
    if [ -f "$CURRENT_FILE" ]; then
      CURRENT=$(cat "$CURRENT_FILE" | tr -d '[:space:]')
    fi

    # List all profiles
    if [ -d "$PROFILES_DIR" ]; then
      for profile_file in "$PROFILES_DIR"/*.json; do
        if [ -f "$profile_file" ]; then
          name=$(basename "$profile_file" .json)
          desc=$(${pkgs.jq}/bin/jq -r '.description // ""' "$profile_file")
          outputs=$(${pkgs.jq}/bin/jq -r '.outputs | length' "$profile_file")

          # Format display with monitor count and active indicator
          if [ "$name" = "$CURRENT" ]; then
            echo "🟢 $name ($outputs monitors) - $desc	$name"
          else
            echo "○ $name ($outputs monitors) - $desc	$name"
          fi
        fi
      done
    fi
  '';

  # Feature 083: Walker monitor profile switch script
  walkerMonitorSwitch = pkgs.writeShellScriptBin "walker-monitor-switch" ''
    #!/usr/bin/env bash
    # Switch to selected monitor profile from Walker
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    SELECTED="$1"

    # Extract profile name (everything after the tab character)
    PROFILE_NAME=$(echo "$SELECTED" | ${pkgs.coreutils}/bin/cut -f2)

    if [ -z "$PROFILE_NAME" ]; then
      exit 0
    fi

    # Switch profile using set-monitor-profile
    set-monitor-profile "$PROFILE_NAME"
  '';

  walkerMonitorListCmd = lib.getExe walkerMonitorList;
  walkerMonitorSwitchCmd = lib.getExe walkerMonitorSwitch;

  # Feature 034/035: Custom application directory for i3pm-managed apps
  # Desktop files are at ~/.local/share/i3pm-applications/applications/
  # Add to XDG_DATA_DIRS so Walker can find them
  i3pmAppsDir = "${config.home.homeDirectory}/.local/share/i3pm-applications";
in

# Walker Application Launcher
#
# Walker is a modern GTK4-based application launcher with:
# - Fast application search with fuzzy matching
# - Built-in calculator (= prefix)
# - File browser (/ prefix)
# - Clipboard history (: prefix)
# - Symbol picker (. prefix)
# - Shell command execution
# - Web search integration
# - Custom menu support
#
# Documentation: https://github.com/abenz1267/walker

{
  imports = [
    inputs.walker.homeManagerModules.default
  ];

  programs.walker = {
    enable = true;

    # Enable service mode for Wayland/Sway (plugins require GApplication service)
    # Disable for X11/XRDP due to GApplication DBus issues
    runAsService = isWaylandMode;

    # NOTE: config generation disabled - we override with xdg.configFile below to add X11 settings
    # Walker configuration with sesh plugin integration (Feature 034)
    config = lib.mkForce {};  # Disable upstream module config generation
    /*
    config = {
      # Enable default Walker/Elephant providers
      # Reference: https://github.com/abenz1267/walker#providers-implemented-by-walker-per-default
      modules = {
        applications = true;    # Desktop applications (primary launcher mode)
        calc = true;            # Calculator (= prefix)
        clipboard = true;       # Clipboard history (: prefix) - text and image support
        files = false;          # File browser (DISABLED - causes segfault in X11)
        menus = true;           # Context menus
        runner = true;          # Shell command execution
        symbols = true;         # Symbol/emoji picker (. prefix)
        websearch = true;       # Web search integration
        # bluetooth = false;    # Bluetooth (disabled - not needed)
        # providerlist = true;  # Provider list (meta-provider)
        # todo = false;         # Todo list (disabled - not configured)
        # unicode = true;       # Unicode character search
      };

      # Provider prefixes - Type these to activate specific providers
      # Reference: https://github.com/abenz1267/walker/wiki/Basic-Configuration#providersprefixes
      providers.prefixes = [
        { prefix = "="; provider = "calc"; }           # Calculator
        { prefix = ":"; provider = "clipboard"; }      # Clipboard history (text + images)
        { prefix = "."; provider = "symbols"; }        # Symbol/emoji picker
        { prefix = "@"; provider = "websearch"; }      # Web search
        { prefix = ">"; provider = "runner"; }         # Shell command execution
        # { prefix = "/"; provider = "files"; }        # File browser (disabled - segfault)
      ];

      # Custom plugins
      plugins = [
        {
          name = "sesh";
          prefix = ";s ";
          src_once = "sesh list -d -c -t -T";
          cmd = "sesh connect --switch %RESULT%";
          keep_sort = false;
          recalculate_score = true;
          show_icon_when_single = true;
          switcher_only = true;
        }
        {
          name = "projects";
          prefix = ";p ";
          src_once = lib.getExe walkerProjectList;
          cmd = "${lib.getExe walkerProjectSwitch} %RESULT%";
          keep_sort = false;
          recalculate_score = true;
          show_icon_when_single = true;
          switcher_only = true;
        }
      ];

      # Provider actions - Custom keybindings and actions for providers
      # Feature 034: Enhanced application launching with project context
      providers.actions = {
        # Desktop applications actions
        # Default action uses .desktop Exec command (already points to app-launcher-wrapper.sh)
        desktopapplications = [
          {
            action = "open";           # Default action: Launch via app-launcher-wrapper
            default = true;
            bind = "Return";
            label = "launch";
            after = "Close";
          }
        ];

        # Runner actions - Execute commands
        runner = [
          {
            action = "run";
            default = true;
            bind = "Return";
            label = "run";
            after = "Close";
          }
          {
            action = "runterminal";
            bind = "shift Return";
            label = "run in terminal";
            after = "Close";
          }
        ];

        # Fallback actions for all providers
        fallback = [
          {
            action = "menus:open";
            label = "open";
            after = "Nothing";
          }
        ];
      };
    };
    */
  };

  home.packages = [
    walkerOpenInNvim
    walkerProjectList
    walkerProjectSwitch
    walkerOnePasswordCacheRefresh
    walkerOnePasswordList
    walkerOnePasswordCopy
    walkerSshWorktreeList
    walkerSshWorktreeMaterialize
    walkerSshWorktreeSelect
    walkerSshWorktreeCreate
    walkerSshWorktreeRefresh
    walkerSshWorktreeDiagnose
    walkerWindowClose
    walkerWindowFloat
    walkerWindowFullscreen
    walkerWindowScratchpad
    walkerWindowInfo
    walkerWindowManager
    walkerClaudeSessions
    walkerMonitorList
    walkerMonitorSwitch

    # Feature 113: Browser history helper scripts
    # walker-history-list: Lists recent browser history entries
    (pkgs.writeShellScriptBin "walker-history-list" ''
      #!/usr/bin/env bash
      # Feature 113: Firefox browser history provider for Walker
      # Outputs tab-separated: icon\ttitle\turl
      set -euo pipefail

      FIREFOX_PROFILE="$HOME/.mozilla/firefox/default"
      PLACES_DB="$FIREFOX_PROFILE/places.sqlite"
      CACHE_DIR="$HOME/.cache/walker-history"
      CACHE_DB="$CACHE_DIR/places_copy.sqlite"
      MAX_ENTRIES="''${1:-100}"

      # Ensure cache directory exists
      mkdir -p "$CACHE_DIR"

      # Copy places.sqlite to avoid locking issues with Firefox
      # Only copy if source is newer than cache (or cache doesn't exist)
      if [[ ! -f "$CACHE_DB" ]] || [[ "$PLACES_DB" -nt "$CACHE_DB" ]]; then
        cp "$PLACES_DB" "$CACHE_DB" 2>/dev/null || {
          echo "ERROR: Cannot access Firefox history database" >&2
          exit 1
        }
      fi

      # Query recent history, excluding:
      # - Internal Firefox pages (about:, moz-extension:)
      # - OAuth/auth redirects (long query strings)
      # - Duplicate Google searches
      ${pkgs.sqlite}/bin/sqlite3 -separator $'\t' "$CACHE_DB" "
        SELECT DISTINCT
          '🌐',
          COALESCE(NULLIF(title, ''''''), url),
          url
        FROM moz_places
        WHERE visit_count > 0
          AND url LIKE 'http%'
          AND url NOT LIKE '%accounts.google.com%'
          AND url NOT LIKE '%oauth%'
          AND url NOT LIKE '%/authorize?%'
          AND length(url) < 500
        ORDER BY last_visit_date DESC
        LIMIT $MAX_ENTRIES
      " 2>/dev/null || echo "ERROR: Query failed" >&2
    '')

    # walker-history-open: Opens a URL via xdg-open (routes to default browser)
    (pkgs.writeShellScriptBin "walker-history-open" ''
      #!/usr/bin/env bash
      # Open browser history URL via xdg-open (routes to default browser)
      set -euo pipefail

      URL="$1"

      if [[ -z "$URL" ]]; then
        echo "Usage: walker-history-open <url>" >&2
        exit 1
      fi

      exec ${pkgs.xdg-utils}/bin/xdg-open "$URL"
    '')
  ];

  # Desktop file for walker-open-in-nvim - manual creation
  xdg.dataFile."applications/walker-open-in-nvim.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Open in Neovim (Alacritty)
    Exec=${lib.getExe walkerOpenInNvim} %U
    MimeType=text/plain;text/markdown;text/x-shellscript;text/x-python;text/x-nix;application/x-shellscript;application/json;application/xml;text/x-c;text/x-c++;text/x-java;text/x-rust;text/x-go;text/x-yaml;text/x-toml;application/toml;application/x-yaml;inode/directory;
    NoDisplay=true
    Terminal=false
  '';

  # Set walker-open-in-nvim as default handler for all common file types
  xdg.mimeApps.defaultApplications = {
    "text/plain" = "walker-open-in-nvim.desktop";
    "text/markdown" = "walker-open-in-nvim.desktop";
    "text/x-shellscript" = "walker-open-in-nvim.desktop";
    "text/x-python" = "walker-open-in-nvim.desktop";
    "text/x-nix" = "walker-open-in-nvim.desktop";
    "text/x-c" = "walker-open-in-nvim.desktop";
    "text/x-c++" = "walker-open-in-nvim.desktop";
    "text/x-java" = "walker-open-in-nvim.desktop";
    "text/x-rust" = "walker-open-in-nvim.desktop";
    "text/x-go" = "walker-open-in-nvim.desktop";
    "text/x-yaml" = "walker-open-in-nvim.desktop";
    "text/x-toml" = "walker-open-in-nvim.desktop";
    "application/x-shellscript" = "walker-open-in-nvim.desktop";
    "application/json" = "walker-open-in-nvim.desktop";
    "application/xml" = "walker-open-in-nvim.desktop";
    "application/toml" = "walker-open-in-nvim.desktop";
    "application/x-yaml" = "walker-open-in-nvim.desktop";
    # Fallback for unknown text files
    "application/octet-stream" = "walker-open-in-nvim.desktop";
  };

  # Override the walker config file to add mode settings not supported by the module
  xdg.configFile."walker/config.toml" = lib.mkForce {
    text = ''
        # Walker Configuration
        # ${if isWaylandMode then "Wayland Mode (headless Sway)" else "X11 Mode (use window instead of Wayland layer shell)"}
        # Using default Walker theme
        as_window = ${if isWaylandMode then "false" else "true"}
        # Force keyboard focus when Walker opens (ensures immediate typing without clicking)
        force_keyboard_focus = true
        close_when_open = true

        [modules]
        applications = true
        calc = true
        # Clipboard: ${if isWaylandMode then "Enabled for Wayland mode" else "Disabled - Elephant's clipboard provider requires Wayland (wl-clipboard), X11 clipboard monitoring not supported"}
        clipboard = ${if isWaylandMode then "true" else "false"}
        # File provider now enabled (Walker ≥v1.5 supports X11 safely when launched as a window)
        files = true
        menus = true
        runner = true
        symbols = true
        websearch = true
        # Feature 050: Additional providers for enhanced productivity
        todo = true              # Todo list management (! prefix)
        windows = true           # Window switcher for fuzzy window navigation
        bookmarks = true         # Quick URL access via bookmarks
        snippets = true          # User-defined command shortcuts ($ prefix)
        providerlist = true      # Help menu - lists all providers and prefixes (? prefix)

        # NOTE: Projects and Sesh menus are defined as Elephant Lua menus
        # See ~/.config/elephant/menus/projects.lua and sesh.lua
        # Activated via provider prefixes below (;p and ;s)

        [[providers.prefixes]]
        prefix = "="
        provider = "calc"

        [[providers.prefixes]]
        prefix = ":"
        provider = "clipboard"

        [[providers.prefixes]]
        prefix = "."
        provider = "symbols"

        [[providers.prefixes]]
        prefix = "@"
        provider = "websearch"

        [[providers.prefixes]]
        prefix = ">"
        provider = "runner"

        [[providers.prefixes]]
        prefix = "/"
        provider = "files"

        [[providers.prefixes]]
        prefix = "//"
        provider = "menus:project-files"

        [[providers.prefixes]]
        prefix = "!"
        provider = "todo"

        [[providers.prefixes]]
        prefix = "$"
        provider = "snippets"

        [[providers.prefixes]]
        prefix = "w "
        provider = "windows"

        [[providers.prefixes]]
        prefix = "b"
        provider = "bookmarks"

        [[providers.prefixes]]
        prefix = "?"
        provider = "providerlist"

        [[providers.prefixes]]
        prefix = ";p "
        provider = "menus:projects"

        [[providers.prefixes]]
        prefix = ";r"
        provider = "menus:ssh-worktrees"

        [[providers.prefixes]]
        prefix = ";r "
        provider = "menus:ssh-worktrees"

        [[providers.prefixes]]
        prefix = ";R"
        provider = "menus:ssh-worktree-create"

        [[providers.prefixes]]
        prefix = ";R "
        provider = "menus:ssh-worktree-create"

        [[providers.prefixes]]
        prefix = ";s "
        provider = "menus:sesh"

        [[providers.prefixes]]
        prefix = ";w "
        provider = "menus:window-actions"

        # Feature 083: Monitor profile switcher
        [[providers.prefixes]]
        prefix = ";m "
        provider = "menus:monitors"

        # Feature 113: Browser history menu
        [[providers.prefixes]]
        prefix = ";h "
        provider = "menus:history"

        # 1Password integration
        # Use a cached custom menu instead of Elephant's built-in 1Password
        # provider. The built-in provider cannot reliably connect to the
        # 1Password desktop app from Elephant's daemon context on this machine.
        [[providers.prefixes]]
        prefix = "* "
        provider = "menus:onepassword"

        [[providers.actions.desktopapplications]]
        action = "open"
        after = "Close"
        bind = "Return"
        default = true
        label = "launch"

        [[providers.actions.fallback]]
        action = "menus:open"
        after = "Nothing"
        label = "open"

        [[providers.actions.runner]]
        action = "run"
        after = "Close"
        bind = "Return"
        default = true
        label = "run"

        [[providers.actions.runner]]
        action = "runterminal"
        after = "Close"
        bind = "shift Return"
        label = "run in terminal"

        # File provider actions
        # Return key uses "open" action which respects MIME handlers (opens text files in Neovim)
        # Ctrl+Return opens parent directory for quick navigation
        [[providers.actions.files]]
        action = "open"
        after = "Close"
        bind = "Return"
        default = true
        label = "open"

        [[providers.actions.files]]
        action = "opendir"
        after = "Close"
        bind = "ctrl Return"
        label = "open directory"

        # Windows provider actions
        # The windows provider only supports "focus" as a built-in action
        # Use Ctrl+M to open the full window actions menu
        [[providers.actions.windows]]
        action = "focus"
        after = "Close"
        bind = "Return"
        default = true
        label = "focus window"

        [[providers.actions.windows]]
        action = "menus:window-actions"
        after = "Nothing"
        bind = "ctrl m"
        label = "window actions"

        # Clipboard provider actions
        # Return: copy selected item back to clipboard
        [[providers.actions.clipboard]]
        action = "copy"
        after = "Close"
        bind = "Return"
        default = true
        label = "copy to clipboard"

        # Delete clipboard entry
        [[providers.actions.clipboard]]
        action = "delete"
        after = "Nothing"
        bind = "ctrl d"
        label = "delete entry"

    '';
  };

  # Elephant clipboard provider configuration
  # Smart clipboard handling:
  # - Regular apps: Auto-paste with Ctrl+V
  # - Terminals: Copy to clipboard only (no auto-paste)
  #   User can then use tmux prefix+] or terminal Ctrl+Shift+V
  # Reference: https://github.com/abenz1267/walker/issues/560
  xdg.configFile."elephant/clipboard.toml".text = ''
    icon = "edit-paste"
    min_score = 30
    max_items = 500
    # Smart paste: auto-pastes for regular apps, clipboard-only for terminals
    command = "${smartPasteScript}"
    recopy = true
    ignore_symbols = false
    auto_cleanup = 0
  '';

  # Elephant websearch provider configuration
  # Feature 050: Enhanced with domain-specific search engines
  xdg.configFile."elephant/websearch.toml".text = ''
    # Elephant Web Search Configuration
    icon = "web-browser"

    [[engines]]
    name = "Google AI"
    url = "https://www.google.com/search?q=%s&udm=14"

    [[engines]]
    name = "Google"
    url = "https://www.google.com/search?q=%s"

    [[engines]]
    name = "DuckDuckGo"
    url = "https://duckduckgo.com/?q=%s"

    [[engines]]
    name = "GitHub"
    url = "https://github.com/search?q=%s"

    [[engines]]
    name = "YouTube"
    url = "https://www.youtube.com/results?search_query=%s"

    [[engines]]
    name = "Wikipedia"
    url = "https://en.wikipedia.org/wiki/Special:Search?search=%s"

    # Feature 050: Domain-specific search engines for development
    [[engines]]
    name = "Stack Overflow"
    url = "https://stackoverflow.com/search?q=%s"

    [[engines]]
    name = "Arch Wiki"
    url = "https://wiki.archlinux.org/index.php?search=%s"

    [[engines]]
    name = "Nix Packages"
    url = "https://search.nixos.org/packages?query=%s"

    [[engines]]
    name = "Rust Docs"
    url = "https://doc.rust-lang.org/std/?search=%s"

    # Default search engine - uses Google AI mode with Gemini
    default = "Google AI"
  '';

  # Providerlist configuration - native help menu
  xdg.configFile."elephant/providerlist.toml".text = ''
    # Elephant Providerlist Configuration
    # Shows all installed providers and configured menus
    # Access: Meta+D → ? → shows all providers with descriptions

    icon = "help-about"
    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Hidden providers (exclude from list)
    # hidden = ["providerlist"]  # Hide the help menu from itself
  '';

  # Feature 050: Bookmarks provider configuration
  # Elephant bookmarks are stored in CSV format, this file only contains configuration
  xdg.configFile."elephant/bookmarks.toml".text = ''
    # Elephant Bookmarks Configuration
    # Bookmarks are stored in CSV: ~/.cache/elephant/bookmarks/bookmarks.csv
    # Use Walker to add bookmarks: Meta+D → b → <url> → Return

    icon = "user-bookmarks"
    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Prefix for creating new bookmarks (optional)
    # If set, use: Meta+D → b → add:github.com GitHub
    # If not set, any non-matching query creates a bookmark
    # create_prefix = "add"

    # Categories for organizing bookmarks
    # Usage: Meta+D → b → dev:github.com → adds to "dev" category

    [[categories]]
    name = "docs"
    prefix = "d:"

    [[categories]]
    name = "dev"
    prefix = "dv:"

    [[categories]]
    name = "ai"
    prefix = "ai:"

    [[categories]]
    name = "nix"
    prefix = "nx:"

    [[categories]]
    name = "work"
    prefix = "w:"

    [[categories]]
    name = "personal"
    prefix = "p:"

    # Browsers for opening bookmarks
    # Usage: Set browser when adding bookmark or edit CSV later

    [[browsers]]
    name = "Firefox"
    command = "firefox"

    [[browsers]]
    name = "Firefox Private"
    command = "firefox --private-window"

    [[browsers]]
    name = "Chromium"
    command = "chromium"

    [[browsers]]
    name = "Firefox App Mode"
    command = "firefox --new-window --kiosk"
  '';

  # Files provider configuration
  # Feature 050: Configure files provider to show hidden files (dotfiles)
  # Default fd_flags: "--ignore-vcs --type file --type directory"
  # Searches from $HOME by default
  xdg.configFile."elephant/files.toml".text = ''
    # Feature 050: Files provider configuration
    # Show hidden files (dotfiles) and search from home directory
    # NOTE: Removed --follow flag - it traverses ALL symlinks (too slow, indexes too much)
    # To search /etc/nixos: Type /etc/nixos in Walker file search
    icon = "system-file-manager"
    fd_flags = "--hidden --ignore-vcs --type file --type directory"

    # Ignore performance-heavy directories
    ignored_dirs = [
      "${config.home.homeDirectory}/.cache",
      "${config.home.homeDirectory}/.local/share/Trash",
      "${config.home.homeDirectory}/.npm",
      "${config.home.homeDirectory}/.cargo",
      "${config.home.homeDirectory}/node_modules",
      "${config.home.homeDirectory}/.nix-profile",
    ]
  '';

  # Windows provider configuration
  # Enhanced with additional window management actions
  xdg.configFile."elephant/windows.toml".text = ''
    # Elephant Windows Provider Configuration
    # Provides fuzzy window switching with enhanced actions

    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Delay in ms before focusing to avoid potential focus issues
    delay = 100

    # Icon for the provider
    icon = "preferences-system-windows"
  '';

  # Bluetooth provider configuration
  xdg.configFile."elephant/bluetooth.toml".text = ''
    # Elephant Bluetooth Provider Configuration
    icon = "preferences-system-bluetooth"
    min_score = 30
  '';

  # Desktop applications provider configuration
  xdg.configFile."elephant/desktopapplications.toml".text = ''
    # Elephant Desktop Applications Provider Configuration
    icon = "applications-all"
    min_score = 20
    history = true

    # Aliases for apps with fuzzy matching issues
    # Format: alias = "desktop-file-id" (without .desktop extension)
    # These aliases are prioritized in search results
    [aliases]
    backstage = "backstage-pwa"
    "backstage talos" = "backstage-pwa"
    "google ai" = "google-ai-pwa"
    gemini = "google-gemini-pwa"
    gmail = "gmail-pwa"
    calendar = "google-calendar-pwa"
  '';

  # Calculator provider configuration
  xdg.configFile."elephant/calc.toml".text = ''
    # Elephant Calculator Provider Configuration
    icon = "accessories-calculator"
    min_score = 30
  '';

  # Runner provider configuration
  xdg.configFile."elephant/runner.toml".text = ''
    # Elephant Runner Provider Configuration
    icon = "utilities-terminal"
    min_score = 30
  '';

  # Todo provider configuration
  xdg.configFile."elephant/todo.toml".text = ''
    # Elephant Todo Provider Configuration
    icon = "view-task"
    min_score = 30
  '';

  # Snippets provider configuration
  xdg.configFile."elephant/snippets.toml".text = ''
    # Elephant Snippets Provider Configuration
    icon = "insert-text"
    min_score = 30
  '';

  # Symbols provider configuration
  xdg.configFile."elephant/symbols.toml".text = ''
    # Elephant Symbols/Emoji Provider Configuration
    icon = "preferences-desktop-font"
    min_score = 30
  '';

  # Unicode provider configuration
  xdg.configFile."elephant/unicode.toml".text = ''
    # Elephant Unicode Provider Configuration
    icon = "accessories-character-map"
    min_score = 30
  '';

  # 1Password provider configuration
  # Access via Walker: Meta+D → * → search for login items
  # Features:
  #   - Return: copy password (clears after 5 seconds)
  #   - Shift+Return: copy username
  #   - Ctrl+Return: copy OTP (if available)
  # Requirements: 1Password GUI + op CLI (installed via onepassword module)
  xdg.configFile."elephant/1password.toml".text = ''
    # Elephant 1Password Provider Configuration
    # Docs: elephant generatedoc 1password
    icon = "1password"
    name_pretty = "1Password"
    hide_from_providerlist = true
    min_score = 30

    # Vaults to index - use IDs to avoid ambiguity (Employee vault has type=PERSONAL
    # which conflicts with the Personal vault name when using name-based lookup)
    # Personal (ampm3rvesendx6mvksmu2ydh6e) - 1 item
    # Employee (cu4rqh2szvjlrumhepqe2twsmm) - 631 items
    vaults = ["ampm3rvesendx6mvksmu2ydh6e", "cu4rqh2szvjlrumhepqe2twsmm"]

    # Notify after copying password
    notify = true

    # Clear clipboard after 5 seconds for security
    clear_after = 5

    # Category icons for visual distinction
    [category_icons]
    login = "dialog-password-symbolic"
    secure_note = "accessories-text-editor-symbolic"
    ssh_key = "utilities-terminal-symbolic"
    credit_card = "auth-smartcard-symbolic"
    identity = "avatar-default-symbolic"
    document = "folder-documents-symbolic"
    password = "dialog-password-symbolic"
    api_credential = "network-server-symbolic"
  '';

  # Feature 083: Monitor profile switcher menu (Elephant Lua menu)
  # Access: Meta+D → ;m → select profile
  xdg.configFile."elephant/menus/monitors.lua".text = ''
    Name = "monitors"
    NamePretty = "Monitor Profiles"
    Icon = "display"
    Cache = false  -- Always refresh profile list
    Action = "walker-monitor-switch '%VALUE%'"
    HideFromProviderlist = false
    Description = "Switch monitor profile (single/dual/triple)"
    SearchName = true
    GlobalSearch = false  -- Keep this local to ;m prefix

    function GetEntries()
        local entries = {}

        -- Get profile list from walker-monitor-list
        local handle = io.popen("walker-monitor-list 2>/dev/null")
        if handle then
            for line in handle:lines() do
                -- Parse tab-separated format: "display\tprofile_name"
                local display, profile_name = line:match("^(.+)\t(.+)$")
                if display and profile_name then
                    -- Determine icon based on current status
                    local icon = "display"
                    if display:match("^🟢") then
                        icon = "display"  -- Current profile
                    end

                    table.insert(entries, {
                        Text = display,
                        Value = line,  -- Pass full line to walker-monitor-switch
                        Icon = icon,
                        Keywords = {"monitor", "profile", "display", profile_name}
                    })
                end
            end
            handle:close()
        end

        return entries
    end
  '';

  # Feature 113: Browser history menu (Elephant Lua menu)
  # Access: Meta+D → ;h → select from recent browser history
  # Opens URLs through pwa-url-router for PWA detection
  xdg.configFile."elephant/menus/history.lua".text = ''
    Name = "history"
    NamePretty = "Browser History"
    Icon = "web-browser"
    Cache = false  -- Always refresh history
    Action = "walker-history-open '%VALUE%'"
    HideFromProviderlist = false
    Description = "Recent browser history (routes to PWAs)"
    SearchName = true
    GlobalSearch = false  -- Keep local to ;h prefix
    FixedOrder = true  -- Keep chronological order (most recent first)

    -- Load PWA domain registry for icon lookup
    local pwa_icons = {}
    local home = os.getenv("HOME")
    local registry_path = home .. "/.config/i3/pwa-domains.json"
    local registry_file = io.open(registry_path, "r")
    if registry_file then
        local content = registry_file:read("*all")
        registry_file:close()
        -- Parse minified JSON: "domain":{"name":"...","pwa":"...-pwa","ulid":"..."}
        -- Pattern matches: "domain":{"name":"Name","pwa":"pwa-name",...}
        for domain, pwa_name in content:gmatch('"([^"]+)":%{"name":"[^"]*","pwa":"([^"]+)"') do
            -- Try multiple icon locations (scalable SVG preferred, then PNG sizes)
            local icon_dirs = {
                home .. "/.local/share/icons/hicolor/scalable/apps/",
                home .. "/.local/share/icons/hicolor/256x256/apps/",
                home .. "/.local/share/icons/hicolor/128x128/apps/",
                home .. "/.local/share/icons/hicolor/64x64/apps/",
            }
            for _, dir in ipairs(icon_dirs) do
                local svg_path = dir .. pwa_name .. ".svg"
                local png_path = dir .. pwa_name .. ".png"
                local f = io.open(svg_path, "r")
                if f then
                    f:close()
                    pwa_icons[domain] = svg_path
                    break
                end
                f = io.open(png_path, "r")
                if f then
                    f:close()
                    pwa_icons[domain] = png_path
                    break
                end
            end
        end
    end

    -- Fallback icons for common domains without PWAs
    local fallback_icons = {
        ["google.com"] = "google",
        ["www.google.com"] = "google",
        ["stackoverflow.com"] = "help-browser",
        ["reddit.com"] = "applications-internet",
        ["www.reddit.com"] = "applications-internet",
        ["wikipedia.org"] = "accessories-dictionary",
        ["en.wikipedia.org"] = "accessories-dictionary",
    }

    function GetEntries()
        local entries = {}

        -- Get history from walker-history-list
        local handle = io.popen("walker-history-list 100 2>/dev/null")
        if handle then
            for line in handle:lines() do
                -- Parse tab-separated format: "icon\ttitle\turl"
                local _, title, url = line:match("^(.+)\t(.+)\t(.+)$")
                if title and url then
                    -- Extract domain for icon lookup and keywords
                    local domain = url:match("https?://([^/]+)")

                    -- Find the best icon for this domain
                    local icon = "web-browser"  -- default

                    if domain then
                        -- Try exact domain match first
                        if pwa_icons[domain] then
                            icon = pwa_icons[domain]
                        -- Try without www prefix
                        elseif domain:match("^www%.") then
                            local bare_domain = domain:gsub("^www%.", "")
                            if pwa_icons[bare_domain] then
                                icon = pwa_icons[bare_domain]
                            end
                        end

                        -- Check fallback icons
                        if icon == "web-browser" and fallback_icons[domain] then
                            icon = fallback_icons[domain]
                        end
                    end

                    table.insert(entries, {
                        Text = title,
                        Subtext = url,  -- Show full URL as subtitle
                        Value = url,
                        Icon = icon,
                        Keywords = {domain or "", "history", "browser", "recent"}
                    })
                end
            end
            handle:close()
        end

        return entries
    end
  '';

  # 1Password menu backed by a cached transient CLI query.
  # Access: Meta+D -> *<space>
  xdg.configFile."elephant/menus/onepassword.lua".text = ''
    Name = "onepassword"
    NamePretty = "1Password"
    Icon = "1password"
    Cache = false
    Action = "walker-1password-copy password '%VALUE%'"
    HideFromProviderlist = false
    Description = "1Password items (cached via transient CLI query)"
    SearchName = true
    GlobalSearch = false

    local icons = {
      login = "dialog-password-symbolic",
      secure_note = "accessories-text-editor-symbolic",
      ssh_key = "utilities-terminal-symbolic",
      credit_card = "auth-smartcard-symbolic",
      identity = "avatar-default-symbolic",
      document = "folder-documents-symbolic",
      password = "dialog-password-symbolic",
      api_credential = "network-server-symbolic",
    }

    function GetEntries()
        local entries = {}
        local handle = io.popen("walker-1password-list 2>/dev/null")

        if handle then
            for line in handle:lines() do
                local title, subtext, item_id, category = line:match("^([^\t]*)\t([^\t]*)\t([^\t]+)\t([^\t]+)$")
                if title and item_id then
                    local icon = icons[category] or "1password"
                    local keywords = {"1password", "password", "secret", category or ""}

                    if subtext and subtext ~= "" then
                        for word in subtext:gmatch("%S+") do
                            table.insert(keywords, word:lower())
                        end
                    end

                    table.insert(entries, {
                        Text = title,
                        Subtext = subtext,
                        Value = item_id,
                        Icon = icon,
                        Keywords = keywords
                    })
                end
            end
            handle:close()
        end

        return entries
    end
  '';

  # Feature 101: Project switcher menu (Elephant Lua menu)
  # Access: Win+P or Meta+D → ;p → select project
  # Uses i3pm worktree switch for bare repository support
  xdg.configFile."elephant/menus/projects.lua".text = ''
    Name = "projects"
    NamePretty = "Projects"
    Icon = "folder-code"
    Cache = false  -- Always refresh project list
    Action = "walker-project-switch '%VALUE%'"
    HideFromProviderlist = false
    Description = "Switch between projects (bare repo worktrees)"
    SearchName = true
    GlobalSearch = false  -- Keep local to ;p prefix

    function GetEntries()
        local entries = {}

        -- Get project list from walker-project-list
        local handle = io.popen("walker-project-list 2>/dev/null")
        if handle then
            for line in handle:lines() do
                -- Parse tab-separated format: "display\tqualified_name"
                local display, qualified_name = line:match("^(.+)\t(.+)$")
                if display and qualified_name then
                    -- Determine icon based on content
                    local icon = "folder"
                    if display:match("^∅") then
                        icon = "edit-clear"  -- Clear project option
                    elseif display:match("ACTIVE") then
                        icon = "folder-open"  -- Active project
                    elseif display:match("^📦") then
                        icon = "folder-code"  -- Main branch
                    elseif display:match("^🌿") then
                        icon = "folder-new"  -- Feature branch
                    end

                    -- Build keywords from display name
                    local keywords = {"project", "worktree", "switch"}
                    table.insert(keywords, qualified_name:lower())
                    for token in qualified_name:gmatch("[^/:]+") do
                        table.insert(keywords, token:lower())
                    end
                    for word in display:gmatch("%S+") do
                        if not word:match("^[%[%]📦🌿∅🟢]") then
                            table.insert(keywords, word:lower())
                        end
                    end

                    table.insert(entries, {
                        Text = display,
                        Value = line,  -- Pass full line to walker-project-switch
                        Icon = icon,
                        Keywords = keywords
                    })
                end
            end
            handle:close()
        end

        return entries
    end
  '';

  # SSH worktree switcher (ryzen) via Tailscale SSH
  # Access: Meta+D -> ;r
  xdg.configFile."elephant/menus/ssh-worktrees.lua".text = ''
    Name = "ssh-worktrees"
    NamePretty = "SSH Worktrees (ryzen)"
    Icon = "network-workgroup"
    Cache = false
    Action = "walker-ssh-worktree-select '%VALUE%'"
    HideFromProviderlist = false
    Description = "Discover and materialize remote worktrees from ryzen"
    SearchName = true
    GlobalSearch = false

    local function trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function parseDisplay(display)
        local name, state, path = display:match("^([^|]+)|([^|]+)|(.+)$")
        if not name then
            return trim(display), "", ""
        end
        return trim(name), trim(state), trim(path)
    end

    function GetEntries()
        local entries = {}
        local handle = io.popen("walker-ssh-worktree-list 2>/dev/null")
        if handle then
            for line in handle:lines() do
                local display, payload = line:match("^(.+)\t(.+)$")
                if display and payload then
                    local name, state, path = parseDisplay(display)

                    local icon = "folder-remote"
                    if name:match("^⚠") then
                        icon = "dialog-warning"
                    elseif state:match("local%+ssh") then
                        icon = "folder-saved-search"
                    elseif state:match("ssh%-only") then
                        icon = "folder-remote"
                    end

                    local keywords = {"ssh", "worktree", "remote", "ryzen", "tailscale"}
                    local keyword_source = table.concat({name, state, path}, " ")
                    for word in keyword_source:gmatch("%S+") do
                        local normalized = word:lower():gsub("[^%w%-%+:/_.]", "")
                        if normalized ~= "" then
                            table.insert(keywords, normalized)
                        end
                    end

                    local subtext = path
                    if state ~= "" and path ~= "" then
                        subtext = state .. " • " .. path
                    elseif state ~= "" then
                        subtext = state
                    end

                    table.insert(entries, {
                        Text = name,
                        Subtext = subtext,
                        Value = line,
                        Icon = icon,
                        Keywords = keywords
                    })
                end
            end
            handle:close()
        end
        return entries
    end
  '';

  # SSH remote worktree create menu (ryzen)
  # Access: Meta+D -> ;rc
  xdg.configFile."elephant/menus/ssh-worktree-create.lua".text = ''
    Name = "ssh-worktree-create"
    NamePretty = "Create SSH Worktree (ryzen)"
    Icon = "folder-new"
    Cache = false
    Action = "walker-ssh-worktree-create '%VALUE%'"
    HideFromProviderlist = false
    Description = "Create worktree on ryzen and materialize locally"
    SearchName = true
    GlobalSearch = false

    local function trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function parseDisplay(display)
        local name, state, path = display:match("^([^|]+)|([^|]+)|(.+)$")
        if not name then
            return trim(display), "", ""
        end
        return trim(name), trim(state), trim(path)
    end

    function GetEntries()
        local entries = {}
        local handle = io.popen("walker-ssh-worktree-list --repos-only 2>/dev/null")
        if handle then
            for line in handle:lines() do
                local display, payload = line:match("^(.+)\t(.+)$")
                if display and payload then
                    local name, state, path = parseDisplay(display)
                    local keywords = {"ssh", "worktree", "create", "remote", "ryzen"}
                    local keyword_source = table.concat({name, state, path}, " ")
                    for word in keyword_source:gmatch("%S+") do
                        local normalized = word:lower():gsub("[^%w%-%+:/_.]", "")
                        if normalized ~= "" then
                            table.insert(keywords, normalized)
                        end
                    end

                    local subtext = path
                    if state ~= "" and path ~= "" then
                        subtext = state .. " • " .. path
                    elseif state ~= "" then
                        subtext = state
                    end

                    table.insert(entries, {
                        Text = name,
                        Subtext = subtext,
                        Value = line,
                        Icon = "folder-new",
                        Keywords = keywords
                    })
                end
            end
            handle:close()
        end
        return entries
    end
  '';

  # Feature 101: Sesh (tmux session) switcher menu (Elephant Lua menu)
  # Access: Meta+D → ;s → select session
  xdg.configFile."elephant/menus/sesh.lua".text = ''
    Name = "sesh"
    NamePretty = "Tmux Sessions"
    Icon = "utilities-terminal"
    Cache = false  -- Always refresh session list
    Action = "sesh connect '%VALUE%'"
    HideFromProviderlist = false
    Description = "Switch between tmux sessions"
    SearchName = true
    GlobalSearch = false  -- Keep local to ;s prefix

    function GetEntries()
        local entries = {}

        -- Get session list from sesh
        local handle = io.popen("sesh list 2>/dev/null")
        if handle then
            for line in handle:lines() do
                local session_name = line:match("^%s*(.+)%s*$")
                if session_name and session_name ~= "" then
                    table.insert(entries, {
                        Text = session_name,
                        Value = session_name,
                        Icon = "utilities-terminal",
                        Keywords = {"tmux", "session", session_name:lower()}
                    })
                end
            end
            handle:close()
        end

        return entries
    end
  '';

  # NOTE: ~/nixos-config symlink removed - the actual git repo lives there
  # If you need /etc/nixos access, cd to ~/nixos-config directly

  # Feature 050: Custom commands provider configuration
  # NOTE: commands.toml is now managed dynamically via walker-cmd CLI tool
  # This allows adding/removing commands without rebuilding NixOS
  # Run 'walker-cmd --help' for usage instructions
  # Initial file will be created with examples on first use

  # Feature 034/035: Isolate Walker/Elephant to show ONLY i3pm registry apps
  # By setting XDG_DATA_DIRS to ONLY the i3pm-applications directory,
  # Walker/Elephant won't see any system applications
  # NOTE: This only affects Walker/Elephant service, not the entire session
  # (Elephant service has its own isolated XDG_DATA_DIRS below)

  # Feature 035/046: Elephant service - conditional for Wayland (Sway) vs X11 (i3)
  # Uses standard Elephant binary instead of isolated wrapper
  systemd.user.services.elephant = lib.mkForce {
    Unit = {
      Description = if isWaylandMode then "Elephant launcher backend (Wayland)" else "Elephant launcher backend (X11)";
      # Wayland/Sway: Use sway-session.target (Feature 046)
      # X11/i3: Use default.target (i3 doesn't activate graphical-session.target)
      PartOf = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
      After = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
      # Note: Removed ConditionEnvironment=DISPLAY/WAYLAND_DISPLAY - PassEnvironment provides it when service runs
      # Condition check was too early (before env set), causing startup failures
    };
    Service = {
      # Feature 034/035: Elephant with isolated XDG environment
      # Set XDG_DATA_DIRS to ONLY i3pm-applications directory
      # This ensures Elephant/Walker only see our curated 21 apps
      # Wait for SWAYSOCK to be available before starting (fixes boot race condition)
      ExecStartPre = pkgs.writeShellScript "wait-for-swaysock" ''
        timeout=10
        while [ $timeout -gt 0 ]; do
          if systemctl --user show-environment | grep -q "^SWAYSOCK="; then
            exit 0
          fi
          sleep 0.5
          timeout=$((timeout - 1))
        done
        echo "Timeout waiting for SWAYSOCK environment variable" >&2
        exit 1
      '';
      ExecStart = "${inputs.elephant.packages.${pkgs.system}.default}/bin/elephant";
      Restart = "on-failure";
      RestartSec = 1;
      # Fix: Add PATH for program launching (GitHub issue #69)
      # Feature 034/035 (Feature 050): XDG_DATA_DIRS set to ONLY curated apps (no system duplicates)
      # NOTE: XDG_DATA_HOME must NOT be overridden - apps like Firefox PWA need default location
      # IMPORTANT: Include ~/.local/bin in PATH so Elephant can find app-launcher-wrapper.sh
      Environment = [
        "PATH=${config.home.homeDirectory}/.local/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        # Elephant's 1Password provider shells out to `op`, which needs the user
        # session bus and SSH agent path to survive service restarts.
        "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus"
        "SSH_AUTH_SOCK=${config.home.homeDirectory}/.1password/agent.sock"
        "LIBSECRET_BACKEND=kwallet"
        # CURATED PRIORITY: Curated apps first, then user profile, then system
        # Directory 1: i3pmAppsDir = ~/.local/share/i3pm-applications (curated registry apps - PRIORITY)
        # Directory 2: ~/.local/share (PWAs + user apps)
        # Directory 3: Per-user Nix profile managed by home-manager (icon themes: Papirus, Breeze, etc.)
        # Directory 4: User's nix-profile share
        # Directory 5: System share (fallback icon themes)
        "XDG_DATA_DIRS=${i3pmAppsDir}:${config.home.homeDirectory}/.local/share:/etc/profiles/per-user/${config.home.username}/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
        "XDG_CACHE_HOME=${config.home.homeDirectory}/.cache"
        "XDG_CONFIG_HOME=${config.home.homeDirectory}/.config"
        "XDG_DATA_HOME=${config.home.homeDirectory}/.local/share"
        "XDG_RUNTIME_DIR=%t"
        "XDG_STATE_HOME=${config.home.homeDirectory}/.local/state"
      ];
      # CRITICAL: Pass compositor environment variables for launched apps
      # X11/i3: DISPLAY
      # Wayland/Sway: WAYLAND_DISPLAY, SWAYSOCK (Feature 046)
      # Note: Also passing SWAYSOCK for proper Sway IPC communication
      PassEnvironment = if isWaylandMode then [ "WAYLAND_DISPLAY" "SWAYSOCK" ] else [ "DISPLAY" ];
    };
    Install = {
      # Wayland/Sway: sway-session.target (Feature 046)
      # X11/i3: default.target
      WantedBy = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
    };
  };

  # Walker service disabled - using direct invocation
  # No service override needed since runAsService = false

  # Feature 034/035 (Feature 050): Set session XDG_DATA_DIRS with curated apps priority
  # This ensures Walker (when invoked directly, not as service) prioritizes curated apps
  # CURATED PRIORITY: Curated apps first, then per-user profile (icon themes), then system
  home.sessionVariables = {
    XDG_DATA_DIRS = "${i3pmAppsDir}:${config.home.homeDirectory}/.local/share:/etc/profiles/per-user/${config.home.username}/share:${config.home.profileDirectory}/share:/run/current-system/sw/share";
  };
}
