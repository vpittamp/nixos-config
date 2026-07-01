{ config, lib, pkgs, inputs, osConfig ? null, ... }:

let
  cfg = config.programs.walker;
  scriptWrappers = import ../../shared/script-wrappers.nix { inherit pkgs lib; };
  remoteWorktreeHost = "ryzen";
  remoteWorktreeUser = "vpittamp";
  onePasswordCacheTtlSeconds = 43200;
  onePasswordRetryDelaySeconds = 1800;
  # Wrapper script for snippet commands: captures output, times execution,
  # and sends a desktop notification with the result.
  #
  # Usage:  snippet-run "Title" -- command args...
  #         snippet-run --no-output "Title" -- command args...
  #
  # --no-output  Only show timing in the notification, suppress command output.
  #              Useful for commands that produce no meaningful stdout (e.g. tmux reload).
  #
  # On success: low-urgency notification (8s timeout) with full output + elapsed time.
  # On failure: critical notification (never auto-dismisses) with full output + exit code + elapsed time.
  snippetRun = pkgs.writeShellScriptBin "snippet-run" ''
    set -uo pipefail

    CAPTURE_OUTPUT=1
    while [ $# -gt 0 ]; do
      case "$1" in
        --no-output) CAPTURE_OUTPUT=0; shift ;;
        --) shift; break ;;
        *)  TITLE="$1"; shift ;;
      esac
    done

    if [ -z "''${TITLE:-}" ] || [ $# -eq 0 ]; then
      echo "Usage: snippet-run [--no-output] \"Title\" -- command args..." >&2
      exit 1
    fi

    SECONDS=0
    if [ "$CAPTURE_OUTPUT" -eq 1 ]; then
      OUT=$("$@" 2>&1) && s=$? || s=$?
    else
      "$@" && s=$? || s=$?
      OUT=""
    fi
    ELAPSED=$SECONDS

    NL=$'\n'
    TIMESTAMP=$(date '+%b %-d at %-I:%M %p')
    if [ $s -eq 0 ]; then
      BODY="Succeeded in ''${ELAPSED}s · $TIMESTAMP"
      [ -n "$OUT" ] && BODY="''${BODY}''${NL}''${NL}''${OUT}"
      ACTION=$(notify-send -u low -t 8000 --action=copy=Copy "$TITLE" "$BODY")
    else
      BODY="Failed (exit $s) in ''${ELAPSED}s · $TIMESTAMP"
      [ -n "$OUT" ] && BODY="''${BODY}''${NL}''${NL}''${OUT}"
      ACTION=$(notify-send -u critical -t 0 --action=copy=Copy "$TITLE" "$BODY")
      STATUS=$s
    fi

    if [ "$ACTION" = "copy" ]; then
      printf '%s' "$BODY" | ${pkgs.wl-clipboard}/bin/wl-copy
    fi

    exit "''${STATUS:-0}"
  '';

  aiCliStatusScript = pkgs.writeShellScriptBin "ai-cli-status" ''
    set -euo pipefail

    AWK=${pkgs.gawk}/bin/awk
    GREP=${pkgs.gnugrep}/bin/grep
    PS=${pkgs.procps}/bin/ps
    SSH=${pkgs.openssh}/bin/ssh

    fmt_mb() { echo "$(( $1 / 1024 ))MB"; }

    scan_host() {
      local host="$1"
      local ps_output

      if [ "$host" = "$(hostname -s)" ]; then
        ps_output=$($PS -eo pid,rss,args --no-headers 2>/dev/null) || return
      else
        ps_output=$($SSH -o ConnectTimeout=3 -o BatchMode=yes "$host" \
          'ps -eo pid,rss,args --no-headers' 2>/dev/null) || {
          echo "[$host]  unreachable"
          return
        }
      fi

      local host_found=0
      for cli in claude codex antigravity; do
        local label pattern
        case "$cli" in
          claude)       label="Claude Code";    pattern='\.claude-unwrapped' ;;
          codex)        label="Codex CLI";      pattern='bin/codex' ;;
          antigravity)  label="Antigravity CLI"; pattern='bin/agy' ;;
        esac

        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local pid rss mem
          pid=$(echo "$line" | $AWK '{print $1}')
          rss=$(echo "$line" | $AWK '{print $2}')
          mem=$(fmt_mb "$rss")
          found=$((found + 1))
          host_found=$((host_found + 1))
          echo "[$host]  $label  PID=$pid  MEM=$mem"
        done < <(echo "$ps_output" | $GREP -E "$pattern" | $GREP -v 'interceptor\|grep' || true)
      done

      if [ "$host_found" -eq 0 ]; then
        echo "[$host]  no AI CLI processes"
      fi
    }

    found=0
    hosts="thinkpad ryzen"

    for host in $hosts; do
      scan_host "$host"
    done

    echo ""
    echo "$found process(es) across $hosts"
  '';

  nixosRebuildScript = pkgs.writeShellScriptBin "nixos-rebuild-snippet" ''
    set -euo pipefail
    H=$(hostname -s)
    cd /home/vpittamp/repos/vpittamp/nixos-config/main
    nh os switch --hostname "$H" -- --option eval-cache false
    GEN=$(readlink /nix/var/nix/profiles/system | ${pkgs.gnused}/bin/sed 's/system-\([0-9]*\)-link/\1/')
    echo "Generation: $GEN"
  '';

  elephantDefaultSnippets = [
    {
      name = "rebuild";
      snippet = "snippet-run \"NixOS Rebuild ($(hostname -s))\" -- nixos-rebuild-snippet";
      description = "Rebuild the current host with nh from this nixos-config checkout";
    }
    {
      name = "reload tmux";
      snippet = "snippet-run --no-output \"tmux\" -- tmux source-file ~/.config/tmux/tmux.conf";
      description = "Reload tmux configuration from ~/.config/tmux/tmux.conf";
    }
    {
      name = "ai status";
      snippet = "snippet-run \"AI CLI Status\" -- ai-cli-status";
      description = "Show AI CLI processes (Claude, Codex, Gemini) across thinkpad and ryzen";
    }
    {
      name = "sync kubeconfigs";
      snippet = "snippet-run \"Sync Kubeconfigs\" -- bash -c 'for svc in k8s-api-hub ryzen-k8s-api; do echo \"Configuring $svc...\"; tailscale configure kubeconfig \"$svc\" || true; done'";
      description = "Configure kubectl contexts for all Tailscale K8s API proxies (hub, ryzen)";
    }
  ];
  elephantSnippetsTemplate = pkgs.writeText "elephant-snippets.toml" ''
    # Elephant Snippets Provider Configuration
    icon = "insert-text"
    min_score = 30

    [[snippets]]
    name = "rebuild"
    snippet = "snippet-run \"NixOS Rebuild ($(hostname -s))\" -- nixos-rebuild-snippet"
    description = "Rebuild the current host with nh from this nixos-config checkout"

    [[snippets]]
    name = "reload tmux"
    snippet = "snippet-run --no-output \"tmux\" -- tmux source-file ~/.config/tmux/tmux.conf"
    description = "Reload tmux configuration from ~/.config/tmux/tmux.conf"

    [[snippets]]
    name = "ai status"
    snippet = "snippet-run \"AI CLI Status\" -- ai-cli-status"
    description = "Show running AI CLI processes (Claude, Codex, Gemini) with memory usage"

    [[snippets]]
    name = "sync kubeconfigs"
    snippet = "snippet-run \"Sync Kubeconfigs\" -- bash -c 'for svc in k8s-api-hub ryzen-k8s-api; do echo \"Configuring $svc...\"; tailscale configure kubeconfig \"$svc\" || true; done'"
    description = "Configure kubectl contexts for all Tailscale K8s API proxies (hub, ryzen)"
  '';

  # Detect Wayland mode - if Sway is enabled, we're in Wayland mode
  isWaylandMode = config.wayland.windowManager.sway.enable or false;

  clipboardSyncScript = "${scriptWrappers.clipboard-sync}/bin/clipboard-sync";

  clipboardHistoryScript = pkgs.writeShellScriptBin "i3pm-clipboard-history" ''
    #!/usr/bin/env bash
    set -euo pipefail

    state_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/i3pm"
    history_file="''${I3PM_CLIPBOARD_HISTORY_FILE:-$state_dir/clipboard-history.json}"
    state_file="$state_dir/clipboard-history.last.sha256"
    max_bytes="''${I3PM_CLIPBOARD_HISTORY_MAX_BYTES:-2097152}"

    ${pkgs.coreutils}/bin/mkdir -p "$state_dir"

    record_clipboard() {
      local tmp hash previous_hash size

      case "''${CLIPBOARD_STATE:-data}" in
        data) ;;
        sensitive|nil|clear)
          ${pkgs.coreutils}/bin/rm -f "$state_file"
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac

      tmp="$(${pkgs.coreutils}/bin/mktemp -t i3pm-clipboard-history-XXXXXX)"
      trap '${pkgs.coreutils}/bin/rm -f "''${tmp:-}"' EXIT

      ${pkgs.coreutils}/bin/cat >"$tmp"

      if [[ ! -s "$tmp" ]]; then
        exit 0
      fi

      size="$(${pkgs.coreutils}/bin/stat --format='%s' "$tmp" 2>/dev/null || ${pkgs.coreutils}/bin/wc -c <"$tmp")"
      if [[ "$size" -gt "$max_bytes" ]]; then
        exit 0
      fi

      hash="$(${pkgs.coreutils}/bin/sha256sum "$tmp" | ${pkgs.gawk}/bin/awk '{print $1}')"
      previous_hash=""
      if [[ -f "$state_file" ]]; then
        previous_hash="$(<"$state_file")"
      fi

      if [[ "$hash" == "$previous_hash" ]]; then
        exit 0
      fi

      printf '%s\n' "$hash" >"$state_file"

      ${pkgs.python3}/bin/python3 - "$history_file" "$tmp" "$hash" <<'PY'
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

history_path = Path(sys.argv[1])
content_path = Path(sys.argv[2])
digest = sys.argv[3]

raw = content_path.read_bytes()
text = raw.decode("utf-8", errors="replace")
if not text.strip():
    raise SystemExit(0)

history_path.parent.mkdir(parents=True, exist_ok=True)
try:
    with history_path.open("r", encoding="utf-8") as handle:
        existing = json.load(handle)
except Exception:
    existing = []

if not isinstance(existing, list):
    existing = []

entry_id = f"i3pm:{digest}"
entry = {
    "id": entry_id,
    "text": text,
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "bytes": len(raw),
}

items = [item for item in existing if isinstance(item, dict) and item.get("id") != entry_id]
items.insert(0, entry)
items = items[:500]

fd, tmp_name = tempfile.mkstemp(prefix=".clipboard-history-", suffix=".json", dir=str(history_path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(items, handle, ensure_ascii=False)
        handle.write("\n")
    os.chmod(tmp_name, 0o600)
    os.replace(tmp_name, history_path)
finally:
    if os.path.exists(tmp_name):
        os.unlink(tmp_name)
PY
    }

    case "''${1:-}" in
      --handle-watch-event)
        record_clipboard
        ;;
      --record-current)
        ${pkgs.wl-clipboard}/bin/wl-paste --type text/plain 2>/dev/null | "$0" --handle-watch-event || true
        ;;
      *)
        "$0" --record-current || true
        exec ${pkgs.wl-clipboard}/bin/wl-paste --type text/plain --watch "$0" --handle-watch-event
        ;;
    esac
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

    # Copy content through the shared fan-out helper so tmux mirrors stay current.
    ${clipboardSyncScript}

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

    # Query daemon-owned worktree context directly.
    CONTEXT_JSON=$(i3pm context current --json 2>/dev/null || echo '{}')
    PROJECT_NAME=$(echo "$CONTEXT_JSON" | ${pkgs.jq}/bin/jq -r '.qualified_name // ""')
    PROJECT_DIR=$(echo "$CONTEXT_JSON" | ${pkgs.jq}/bin/jq -r '.local_directory // .directory // ""')
    PROJECT_DISPLAY_NAME=$(echo "$CONTEXT_JSON" | ${pkgs.jq}/bin/jq -r '
      (.qualified_name // "") as $q
      | if $q == "" then "" else (($q | split("/") | last) | split(":") | if length == 2 then .[1] else .[0] end) end
    ')
    PROJECT_ICON=""

    # Generate app instance ID using the same metadata shape as the managed launcher.
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

    # Use systemd-run for proper process isolation, matching the managed launcher.
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


  walkerOnePasswordCacheRefresh = pkgs.writeShellScriptBin "walker-1password-cache-refresh" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export OP_BIOMETRIC_UNLOCK_ENABLED=true

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

    fetch_vault() {
      local vault="$1"
      local outfile="$2"
      "$op_cmd" item list --vault "$vault" --format=json >"$outfile"
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
    ttl_seconds=${toString onePasswordCacheTtlSeconds}
    retry_delay_seconds=${toString onePasswordRetryDelaySeconds}

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
    export OP_BIOMETRIC_UNLOCK_ENABLED=true

    mode="''${1:-password}"
    item_id="''${2:-}"
    op_cmd="/run/wrappers/bin/op"

    if [[ -z "$item_id" ]]; then
      exit 1
    fi

    if [[ ! -x "$op_cmd" ]]; then
      op_cmd="${pkgs._1password-cli}/bin/op"
    fi

    case "$mode" in
      password)
        value=$("$op_cmd" item get "$item_id" --fields password --reveal)
        label="password"
        ;;
      username)
        value=$("$op_cmd" item get "$item_id" --fields username --reveal)
        label="username"
        ;;
      otp)
        value=$("$op_cmd" item get "$item_id" --otp)
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
      ];

      # Provider actions - Custom keybindings and actions for providers
      # Feature 034: Enhanced application launching with project context
      providers.actions = {
        # Desktop applications actions
        # Default action uses .desktop Exec command, which now routes through i3pm launch.
        desktopapplications = [
          {
            action = "open";           # Default action: Launch via daemon-owned i3pm entrypoint
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
    snippetRun
    nixosRebuildScript
    aiCliStatusScript
    clipboardHistoryScript
    walkerOpenInNvim
    walkerOnePasswordCacheRefresh
    walkerOnePasswordList
    walkerOnePasswordCopy
    walkerWindowClose
    walkerWindowFloat
    walkerWindowFullscreen
    walkerWindowScratchpad
    walkerWindowInfo
    walkerWindowManager
    walkerClaudeSessions

    # Feature 113: Browser history helper scripts
    # walker-history-list: Lists recent browser history entries
    (pkgs.writeShellScriptBin "walker-history-list" ''
      #!/usr/bin/env bash
      # Chrome URL provider for Walker compatibility
      # Outputs tab-separated: icon\ttitle\turl
      set -euo pipefail

      MAX_ENTRIES="''${1:-100}"
      chrome-url-list "" "$MAX_ENTRIES" 2>/dev/null | ${pkgs.jq}/bin/jq -r '
        .[]
        | select((.source // "") == "history" or (.state // [] | index("history")))
        | [
            "🌐",
            (.text // .url // ""),
            (.url // "")
          ]
        | @tsv
      '
    '')

    # walker-history-open: Opens a URL via xdg-open (routes to default browser)
    (pkgs.writeShellScriptBin "walker-history-open" ''
      #!/usr/bin/env bash
      # Open browser history URL with the shared Chrome/PWA router
      set -euo pipefail

      URL="$1"

      if [[ -z "$URL" ]]; then
        echo "Usage: walker-history-open <url>" >&2
        exit 1
      fi

      exec chrome-url-open preferred "$URL"
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
        # Use the cached custom menu below; the built-in provider opens a
        # persistent native-messaging connection from the daemon context.
        "1password" = false

        # NOTE: Sesh menu is defined as an Elephant Lua menu
        # See ~/.config/elephant/menus/sesh.lua
        # Activated via provider prefix below (;s)

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
        prefix = ";s "
        provider = "menus:sesh"

        [[providers.prefixes]]
        prefix = ";w "
        provider = "menus:window-actions"

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

  home.activation.ensureMutableElephantSnippets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    SNIPPETS_PATH="$HOME/.config/elephant/snippets.toml"
    TEMPLATE_PATH="${elephantSnippetsTemplate}"

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/elephant"

    if [ -L "$SNIPPETS_PATH" ]; then
      TARGET="$(${pkgs.coreutils}/bin/readlink -f "$SNIPPETS_PATH" || true)"
      case "$TARGET" in
        /nix/store/*)
          TMP_FILE="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.coreutils}/bin/cp "$SNIPPETS_PATH" "$TMP_FILE"
          ${pkgs.coreutils}/bin/rm -f "$SNIPPETS_PATH"
          ${pkgs.coreutils}/bin/mv "$TMP_FILE" "$SNIPPETS_PATH"
          ;;
      esac
    fi

    if [ ! -e "$SNIPPETS_PATH" ]; then
      ${pkgs.coreutils}/bin/cp "$TEMPLATE_PATH" "$SNIPPETS_PATH"
    fi

    if [ -e "$SNIPPETS_PATH" ]; then
      ${pkgs.coreutils}/bin/chmod u+rw "$SNIPPETS_PATH"
    fi

    export ELEPHANT_SNIPPETS_PATH="$SNIPPETS_PATH"
    export ELEPHANT_DEFAULT_SNIPPETS_JSON=${lib.escapeShellArg (builtins.toJSON elephantDefaultSnippets)}

    ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

path = Path(os.environ["ELEPHANT_SNIPPETS_PATH"])
defaults = json.loads(os.environ.get("ELEPHANT_DEFAULT_SNIPPETS_JSON", "[]"))


def toml_escape(value: str) -> str:
    escaped = (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\b", "\\b")
        .replace("\f", "\\f")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def format_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return toml_escape(value)
    if isinstance(value, list) and all(isinstance(item, (str, bool, int, float)) for item in value):
        return "[" + ", ".join(format_value(item) for item in value) + "]"
    return None


def write_data(data: dict) -> None:
    lines = [
        "# Elephant Snippets Provider Configuration",
        "",
    ]
    top_level_preferred_keys = ["icon", "min_score", "name_pretty", "hide_from_providerlist"]
    for key in top_level_preferred_keys:
        if key in data and key != "snippets":
            rendered = format_value(data.get(key))
            if rendered is not None:
                lines.append(f"{key} = {rendered}")
    for key in sorted(data.keys()):
        if key in top_level_preferred_keys or key == "snippets":
            continue
        rendered = format_value(data.get(key))
        if rendered is not None:
            lines.append(f"{key} = {rendered}")
    if len(lines) > 2:
        lines.append("")
    preferred_keys = ["name", "snippet", "description"]
    entries = [dict(item) for item in data.get("snippets", []) if isinstance(item, dict)]
    for index, entry in enumerate(entries):
        if index > 0:
            lines.append("")
        lines.append("[[snippets]]")
        for key in preferred_keys:
            if key in entry:
                rendered = format_value(entry.get(key))
                if rendered is not None:
                    lines.append(f"{key} = {rendered}")
        for key in sorted(entry.keys()):
            if key in preferred_keys:
                continue
            rendered = format_value(entry.get(key))
            if rendered is not None:
                lines.append(f"{key} = {rendered}")
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


try:
    with path.open("rb") as handle:
        data = tomllib.load(handle)
except Exception:
    raise SystemExit(0)

if not isinstance(data, dict):
    raise SystemExit(0)

entries = [dict(item) for item in data.get("snippets", []) if isinstance(item, dict)]

# Rename map: old default names replaced by new parameterized versions.
# Entries matching an old name are removed so the new default can be added.
rename_map = {
    "rebuild ryzen": "rebuild",
    "rebuild ryzen (nh)": "rebuild",
    "rebuild": "rebuild",
    "reload tmux": "reload tmux",
}
renamed_out = set()
before_len = len(entries)
entries = [
    entry for entry in entries
    if str(entry.get("name", "") or "").strip() not in rename_map
    or str(entry.get("name", "") or "").strip() in renamed_out
]
changed = len(entries) != before_len

existing_names = {
    str(entry.get("name", "") or "").strip()
    for entry in entries
    if str(entry.get("name", "") or "").strip()
}
for item in defaults:
    name = str(item.get("name", "") or "").strip()
    if not name or name in existing_names:
        continue
    entries.append(dict(item))
    existing_names.add(name)
    changed = True

if "icon" not in data:
    data["icon"] = "insert-text"
    changed = True
if "min_score" not in data:
    data["min_score"] = 30
    changed = True

if changed:
    data["snippets"] = entries
    write_data(data)
PY
  '';

  # Feature 035/046: Elephant service - conditional for Wayland (Sway) vs X11 (i3)
  # Uses standard Elephant binary instead of isolated wrapper
  systemd.user.services.i3pm-clipboard-history = lib.mkIf isWaylandMode {
    Unit = {
      Description = "QuickShell clipboard history recorder";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${clipboardHistoryScript}/bin/i3pm-clipboard-history";
      Restart = "on-failure";
      RestartSec = 1;
      Environment = [
        "XDG_CACHE_HOME=${config.home.homeDirectory}/.cache"
        "XDG_RUNTIME_DIR=%t"
      ];
      PassEnvironment = [ "WAYLAND_DISPLAY" ];
    };
    Install.WantedBy = [ "sway-session.target" ];
  };

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
      ExecStart = pkgs.writeShellScript "elephant-launcher-backend" ''
        exec ${lib.escapeShellArg "${inputs.elephant.packages.${pkgs.system}.default}/bin/elephant"}
      '';
      Restart = "on-failure";
      RestartSec = 1;
      # Fix: Add PATH for program launching (GitHub issue #69)
      # Feature 034/035 (Feature 050): XDG_DATA_DIRS set to ONLY curated apps (no system duplicates)
      # NOTE: XDG_DATA_HOME must NOT be overridden - apps like Firefox PWA need default location
      # IMPORTANT: Include the user and profile bin dirs so Elephant can find i3pm helpers.
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
