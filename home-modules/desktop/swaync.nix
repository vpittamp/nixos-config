{ config, pkgs, lib, ... }:

let
  # Feature 057: Import unified theme colors from unified-bar-theme.nix
  themeColors = config.wayland.windowManager.sway.config.colors or {
    background = "#1e1e2e";
    focused.background = "#313244";
    focused.text = "#cdd6f4";
    focused.border = "#89b4fa";
    focusedInactive.background = "#181825";
    focusedInactive.text = "#a6adc8";
    urgent.border = "#f38ba8";
  };

  # Catppuccin Mocha CSS for SwayNC
  # Feature 057: User Story 1 - Unified Theming
  swayNcStyle = ''
    /* Feature 057: Unified Bar System - Catppuccin Mocha Theme */

    * {
      font-family: Ubuntu Nerd Font, sans-serif;
      font-size: 10pt;
    }

    .notification-window {
      background-color: ${themeColors.background};
      border: 1px solid ${themeColors.focused.border};
      border-radius: 6px;
    }

    .notification {
      background-color: ${themeColors.focused.background};
      color: ${themeColors.focused.text};
      padding: 10px;
      margin: 5px;
      border-radius: 4px;
    }

    .notification-default-action {
      background-color: ${themeColors.focused.background};
      color: ${themeColors.focused.text};
    }

    .notification-default-action:hover {
      background-color: ${themeColors.focused.border};
    }

    .notification-close-button {
      background-color: ${themeColors.urgent.border};
      color: ${themeColors.focused.text};
      border-radius: 50%;
    }

    .notification-close-button:hover {
      background-color: #ff0000;
    }

    .control-center {
      background-color: ${themeColors.background};
      border: 1px solid ${themeColors.focused.border};
      border-radius: 6px;
    }

    .control-center-list {
      background-color: transparent;
    }

    .widget-title {
      color: ${themeColors.focused.text};
      font-weight: bold;
      margin: 10px;
    }

    .widget-dnd {
      background-color: ${themeColors.focused.background};
      color: ${themeColors.focused.text};
      padding: 5px;
      margin: 5px;
      border-radius: 4px;
    }

    .widget-label {
      color: ${themeColors.focusedInactive.text};
    }

    .widget-mpris {
      background-color: ${themeColors.focused.background};
      color: ${themeColors.focused.text};
      padding: 10px;
      margin: 5px;
      border-radius: 4px;
    }
  '';

in {
  # SwayNC (Notification Center) Configuration
  # Feature 057: Unified Bar System with Enhanced Workspace Mode
  # User Story 1: Unified Theming
  # User Story 4: App-Aware Notification Icons
  # User Story 5: Persistent vs. Transient Information Layout

  # Add SwayNC to home packages
  home.packages = with pkgs; [
    swaynotificationcenter  # SwayNC daemon and client
  ];

  # Generate SwayNC style.css with unified theme colors
  # Feature 057: T016 - Generate SwayNC style.css from appearance.json colors
  xdg.configFile."swaync/style.css".text = swayNcStyle;

  # Feature 057: T027-T031 - SwayNC config.json with widget layout
  # User Story 5: Persistent vs. Transient Information Layout
  # Notification center shows transient info (CPU, memory, network, disk) when toggled open
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    # Core notification settings
    positionX = "right";
    positionY = "top";
    layer = "overlay";
    control-center-layer = "overlay";
    layer-shell = true;
    cssPriority = "user";
    control-center-margin-top = 10;
    control-center-margin-bottom = 10;
    control-center-margin-right = 10;
    control-center-margin-left = 0;
    notification-2fa-action = false;
    notification-inline-replies = false;
    notification-icon-size = 48;
    notification-body-image-height = 100;
    notification-body-image-width = 200;
    timeout = 10;
    timeout-low = 5;
    timeout-critical = 0;  # Never timeout critical notifications
    fit-to-screen = false;
    control-center-width = 500;
    control-center-height = 1000;
    notification-window-width = 400;
    keyboard-shortcuts = true;
    image-visibility = "when-available";
    transition-time = 200;
    hide-on-clear = false;
    hide-on-action = false;
    script-fail-notify = true;

    # Widget layout for control center
    # Feature 057: User Story 5 - Transient information (CPU, memory, network, disk)
    widgets = [
      "title"
      "dnd"
      "notifications"
      "mpris"

      # Feature 057: T027-T030 - System metrics widgets
      # NOTE: These are static labels initially - real-time updates require external script
      # Future enhancement: Poll via SwayNC script hooks or external daemon
      {
        type = "label";
        text = "System Metrics";
      }
      {
        type = "label";
        text = "CPU: Run 'btop' for details";  # T027: CPU gauge placeholder
      }
      {
        type = "label";
        text = "Memory: Run 'btop' for details";  # T028: Memory gauge placeholder
      }
      {
        type = "label";
        text = "Network: Check top bar for WiFi status";  # T029: Network stats placeholder
      }
      {
        type = "label";
        text = "Disk: Run 'df -h /' for details";  # T030: Disk usage placeholder
      }

      "buttons-grid"
    ];

    # Widget configuration for buttons-grid and other widgets
    widget-config = {
      buttons-grid = {
        actions = [
          {
            label = "  System Monitor";
            command = "ghostty -e btop";
          }
          {
            label = "  Network";
            command = "nm-connection-editor";
          }
          {
            label = "  Bluetooth";
            command = "blueman-manager";
          }
          {
            label = "  Volume";
            command = "pavucontrol";
          }
        ];
      };
    };

    # Feature 057: T031 - Configure widget polling intervals (2 seconds for gauges)
    # NOTE: SwayNC doesn't support dynamic widget updates natively
    # This would require external script polling + `swaync-client --reload-config`
    # Deferred to future enhancement (currently showing static placeholders)
  };

  # Future enhancement (T031): Dynamic widget updates via systemd timer
  # systemd.user.timers.swaync-metrics-update = {
  #   Unit.Description = "Update SwayNC metrics widgets";
  #   Timer = {
  #     OnBootSec = "5s";
  #     OnUnitActiveSec = "2s";  # 2 second polling interval
  #   };
  #   Install.WantedBy = [ "timers.target" ];
  # };
  # systemd.user.services.swaync-metrics-update = {
  #   Unit.Description = "Fetch system metrics and update SwayNC widgets";
  #   Service = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.writeShellScript "update-swaync-metrics" ''
  #       # Query system metrics
  #       # Update config.json with new values
  #       # Trigger swaync-client --reload-config
  #     ''}";
  #   };
  # };

  # T024: Future enhancement - Generate GTK icon theme symlinks from application-registry.json
}
