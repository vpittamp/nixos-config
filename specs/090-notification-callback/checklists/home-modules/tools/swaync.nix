{ config, lib, pkgs, ... }:

{
  # SwayNC (Sway Notification Center) configuration
  # Feature 090: Enhanced notification callback for Claude Code
  
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    # Notification display settings
    notification-icon-size = 64;
    notification-body-image-height = 100;
    notification-body-image-width = 200;
    
    # Timeout settings
    timeout = 10;              # Default timeout (seconds)
    timeout-low = 5;           # Low urgency timeout
    timeout-critical = 0;      # Critical notifications don't auto-dismiss
    
    # Display settings
    fit-to-screen = true;
    
    # Feature 090: Custom keyboard shortcuts for notification actions
    # Ctrl+R: Return to Window (primary action - focuses Claude Code terminal)
    # Escape: Dismiss notification (secondary action - no focus change)
    keyboard-shortcuts = {
      notification-close = ["Escape"];
      notification-action-0 = ["ctrl+r" "Return"];  # "Return to Window" action
      notification-action-1 = ["Escape"];           # "Dismiss" action
    };
  };
  
  # Ensure SwayNC service restarts on config change
  systemd.user.services.swaync = lib.mkIf (config.services.swaync.enable or false) {
    Service.ExecReload = lib.mkForce "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
  };
}
