{ pkgs, config, ... }:

let
  tailscaleTabActionScript = pkgs.writeShellScriptBin "tailscale-tab-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ACTION="''${1:-}"
    if [[ -z "$ACTION" ]]; then
      echo "Usage: tailscale-tab-action <verb>" >&2
      exit 1
    fi

    export PATH="${config.home.profileDirectory}/bin:$PATH"

    EWW="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    STATE_DIR="$RUNTIME_DIR/eww-monitoring-panel-tailscale"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"
    mkdir -p "$STATE_DIR"

    FLOCK_FILE="$STATE_DIR/tailscale-tab-action.flock"
    exec 9>"$FLOCK_FILE"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    ACTION_LOCK="$STATE_DIR/''${ACTION}.lock"
    NOW=$(${pkgs.coreutils}/bin/date +%s)
    if [[ -f "$ACTION_LOCK" ]]; then
      LAST=$(${pkgs.coreutils}/bin/stat -c %Y "$ACTION_LOCK" 2>/dev/null || echo 0)
      if [[ $((NOW - LAST)) -lt 1 ]]; then
        exit 0
      fi
    fi
    ${pkgs.coreutils}/bin/touch "$ACTION_LOCK"

    sanitize_message() {
      local msg="$1"
      msg="''${msg//$'\n'/ }"
      msg="''${msg//$'\r'/ }"
      msg="''${msg//\'/}"
      echo "$msg"
    }

    update_notification() {
      local level="$1"
      local raw_message="$2"
      local message
      message=$(sanitize_message "$raw_message")

      case "$level" in
        success)
          $EWW update "success_notification=$message" success_notification_visible=true
          (sleep 3 && $EWW update success_notification_visible=false success_notification="") >/dev/null 2>&1 &
          ;;
        warning)
          $EWW update "warning_notification=$message" warning_notification_visible=true
          (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") >/dev/null 2>&1 &
          ;;
        error)
          $EWW update "error_notification=$message" error_notification_visible=true
          (sleep 5 && $EWW update error_notification_visible=false error_notification="") >/dev/null 2>&1 &
          ;;
      esac
    }

    read_eww_var() {
      local key="$1"
      local value
      value=$($EWW get "$key" 2>/dev/null || true)
      value=$(echo "$value" | ${pkgs.coreutils}/bin/tr -d '\r')
      value="''${value#\"}"
      value="''${value%\"}"
      echo "$value"
    }

    require_confirmation() {
      local confirm_key="$1"
      local current
      current=$(read_eww_var "tailscale_confirm_action")
      if [[ "$current" != "$confirm_key" ]]; then
        $EWW update "tailscale_confirm_action=$confirm_key"
        update_notification "warning" "Click again within 5s to confirm: $confirm_key"
        (sleep 5 && $EWW update tailscale_confirm_action="") >/dev/null 2>&1 &
        exit 0
      fi
      $EWW update tailscale_confirm_action=""
    }

    $EWW update tailscale_action_in_progress=true
    cleanup() {
      $EWW update tailscale_action_in_progress=false >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    case "$ACTION" in
      reconnect)
        require_confirmation "reconnect"

        if ! command -v tailscale >/dev/null 2>&1; then
          update_notification "error" "tailscale command is not available."
          exit 1
        fi

        if OUTPUT=$($TIMEOUT --kill-after=2s 8s tailscale debug rebind 2>&1); then
          update_notification "success" "Reconnect signal sent to tailscaled."
        else
          FIRST_LINE=$(echo "$OUTPUT" | ${pkgs.coreutils}/bin/head -n1)
          update_notification "error" "Reconnect failed: ''${FIRST_LINE:-unknown error}"
          exit 1
        fi
        ;;

      restart-service)
        update_notification "warning" "restart-service is disabled in panel policy (requires terminal privileges)."
        exit 1
        ;;

      set-exit-node)
        update_notification "warning" "set-exit-node is disabled in panel policy (requires terminal privileges)."
        exit 1
        ;;

      k8s-rollout-restart)
        require_confirmation "k8s-rollout-restart"

        if ! command -v kubectl >/dev/null 2>&1; then
          update_notification "error" "kubectl command is not available."
          exit 1
        fi

        NAMESPACE=$(read_eww_var "tailscale_action_namespace")
        TARGET=$(read_eww_var "tailscale_action_target")
        [[ -n "$NAMESPACE" ]] || NAMESPACE="default"

        if [[ -z "$TARGET" ]]; then
          update_notification "error" "Set workload name before restarting deployment."
          exit 1
        fi

        if OUTPUT=$($TIMEOUT --kill-after=3s 15s kubectl -n "$NAMESPACE" rollout restart deployment "$TARGET" 2>&1); then
          update_notification "success" "Deployment restarted: $NAMESPACE/$TARGET"
        else
          FIRST_LINE=$(echo "$OUTPUT" | ${pkgs.coreutils}/bin/head -n1)
          update_notification "error" "Deployment restart failed: ''${FIRST_LINE:-unknown error}"
          exit 1
        fi
        ;;

      k8s-restart-daemonset)
        require_confirmation "k8s-restart-daemonset"

        if ! command -v kubectl >/dev/null 2>&1; then
          update_notification "error" "kubectl command is not available."
          exit 1
        fi

        NAMESPACE=$(read_eww_var "tailscale_action_namespace")
        TARGET=$(read_eww_var "tailscale_action_target")
        [[ -n "$NAMESPACE" ]] || NAMESPACE="default"

        if [[ -z "$TARGET" ]]; then
          update_notification "error" "Set workload name before restarting daemonset."
          exit 1
        fi

        if OUTPUT=$($TIMEOUT --kill-after=3s 15s kubectl -n "$NAMESPACE" rollout restart daemonset "$TARGET" 2>&1); then
          update_notification "success" "DaemonSet restarted: $NAMESPACE/$TARGET"
        else
          FIRST_LINE=$(echo "$OUTPUT" | ${pkgs.coreutils}/bin/head -n1)
          update_notification "error" "DaemonSet restart failed: ''${FIRST_LINE:-unknown error}"
          exit 1
        fi
        ;;

      *)
        update_notification "error" "Unknown action: $ACTION"
        exit 1
        ;;
    esac
  '';
in
{
  inherit tailscaleTabActionScript;
}
