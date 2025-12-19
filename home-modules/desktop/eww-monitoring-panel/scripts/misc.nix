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

  # Feature 094 US9: Application delete cancel handler (T095)

in
{
  inherit showSuccessNotificationScript;
}
