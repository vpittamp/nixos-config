{ pkgs, ... }:

let
  showSuccessNotificationScript = pkgs.writeShellScriptBin "monitoring-panel-notify" ''
    #!${pkgs.bash}/bin/bash
    # Show success notification toast with auto-dismiss
    # Usage: monitoring-panel-notify "Message text" [timeout_seconds]

    MESSAGE="''${1:-Operation completed}"
    TIMEOUT="''${2:-3}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Show notification
    $EWW update success_notification="$MESSAGE"
    $EWW update success_notification_visible=true

    # Auto-dismiss after timeout
    (sleep "$TIMEOUT" && $EWW update success_notification_visible=false success_notification="") &
  '';

  # Feature 110: Pulsating animation phase toggle (0/1)
  pulsePhaseScript = pkgs.writeShellScriptBin "eww-monitoring-panel-pulse-phase" ''
    #!${pkgs.bash}/bin/bash
    STATE_FILE="/tmp/eww-monitoring-panel-pulse-state"
    CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    
    if [ "$CURRENT" -eq 0 ]; then
      echo 1
      echo 1 > "$STATE_FILE"
    else
      echo 0
      echo 0 > "$STATE_FILE"
    fi
  '';

in
{
  inherit showSuccessNotificationScript pulsePhaseScript;
}
