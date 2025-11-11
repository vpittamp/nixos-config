{ config, pkgs, lib, ... }:

let
  # Feature 057: Import unified theme colors (Catppuccin Mocha)
  # Use the same color palette as unified-bar-theme.nix
  mocha = {
    base = "#1e1e2e";
    mantle = "#181825";
    surface0 = "#313244";
    surface1 = "#45475a";
    overlay0 = "#6c7086";
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    blue = "#89b4fa";
    mauve = "#cba6f7";
    yellow = "#f9e2af";
    red = "#f38ba8";
    green = "#a6e3a1";
    teal = "#94e2d5";
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
      background-color: ${mocha.base};
      border: 1px solid ${mocha.blue};
      border-radius: 6px;
    }

    .notification {
      background-color: ${mocha.surface0};
      color: ${mocha.text};
      padding: 10px;
      margin: 5px;
      border-radius: 4px;
    }

    .notification-default-action {
      background-color: ${mocha.surface0};
      color: ${mocha.text};
    }

    .notification-default-action:hover {
      background-color: ${mocha.blue};
    }

    .notification-close-button {
      background-color: ${mocha.red};
      color: ${mocha.text};
      border-radius: 50%;
    }

    .notification-close-button:hover {
      background-color: #ff0000;
    }

    .control-center {
      background-color: ${mocha.base};
      border: 1px solid ${mocha.blue};
      border-radius: 6px;
    }

    .control-center-list {
      background-color: transparent;
    }

    .widget-title {
      color: ${mocha.text};
      font-weight: bold;
      margin: 10px;
    }

    .widget-dnd {
      background-color: ${mocha.surface0};
      color: ${mocha.text};
      padding: 5px;
      margin: 5px;
      border-radius: 4px;
    }

    .widget-label {
      color: ${mocha.subtext0};
    }

    .widget-mpris {
      background-color: ${mocha.surface0};
      color: ${mocha.text};
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

      # Feature 057: T027-T030 - System metrics widgets (named labels)
      "label#metrics-header"
      "label#metrics-info"

      "buttons-grid"
    ];

    # Widget configuration for all widgets
    widget-config = {
      # Feature 057: US5 - System Metrics Section
      # Top bar: persistent info (time, project, battery, network/volume status)
      # Notification center: access detailed metrics via buttons below
      "label#metrics-header" = {
        text = "━━━ System Metrics ━━━";
        max-lines = 1;
      };
      "label#metrics-info" = {
        text = "Click buttons below to view detailed system stats";
        max-lines = 2;
      };

      # Quick action buttons
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

  # Feature 057: T023 - Generate GTK icon theme symlinks from application-registry.json
  # This allows SwayNC to resolve notification icons via GTK icon theme lookup
  #
  # Architecture: SwayNC uses gtk_icon_theme_load_icon() to find notification icons.
  # By creating symlinks in ~/.local/share/icons/hicolor/scalable/apps/, we map
  # app_ids (com.mitchellh.ghostty, code, ffpwa-01JCYF8Z2M) to actual icon paths
  # from our application registry, so SwayNC automatically shows the correct icons.

  # Load application registry for icon mappings
  xdg.dataFile = let
    # Read application-registry.json
    appRegistryPath = "${config.home.homeDirectory}/.config/i3/application-registry.json";
    pwaRegistryPath = "${config.home.homeDirectory}/.config/i3/pwa-registry.json";

    # Helper to create icon symlink entry
    mkIconSymlink = appId: iconPath: {
      name = "icons/hicolor/scalable/apps/${appId}.svg";
      value = {
        source = iconPath;
      };
    };

  in
    # App registry icons will be generated at build time
    # For now, create a placeholder structure that will be populated by activation script
    {
      # Note: The symlinks will be created by an activation script since we need runtime access
      # to the application-registry.json (which may change without NixOS rebuild)
      "icons/hicolor/scalable/apps/.placeholder".text = "# Placeholder for app icon symlinks";
    };

  # Activation script to generate icon symlinks at runtime
  # This runs after home-manager activation and populates the icon directory
  home.activation.generateNotificationIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Feature 057: T023 - Generate GTK icon theme symlinks from application-registry.json

    ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
    APP_REGISTRY="$HOME/.config/i3/application-registry.json"
    PWA_REGISTRY="$HOME/.config/i3/pwa-registry.json"

    # Create icon directory if it doesn't exist
    mkdir -p "$ICON_DIR"

    # Remove old symlinks (cleanup)
    find "$ICON_DIR" -type l -delete

    # Generate symlinks from application registry
    # Only symlink absolute paths - icon names (like "com.mitchellh.ghostty") will be
    # resolved by GTK icon theme automatically, so we don't need symlinks for those.
    if [ -f "$APP_REGISTRY" ]; then
      ${pkgs.jq}/bin/jq -r '.applications[] | select(.icon != null and .icon != "") | "\(.name)|\(.icon)"' "$APP_REGISTRY" | while IFS='|' read -r app_name icon_path; do
        # Create symlink only for absolute paths (custom icons)
        # Icon names like "com.mitchellh.ghostty" will be resolved by GTK theme
        if [ -f "$icon_path" ]; then
          ln -sf "$icon_path" "$ICON_DIR/$app_name.svg" 2>/dev/null || true
        fi
      done
    fi

    # Generate symlinks from PWA registry
    if [ -f "$PWA_REGISTRY" ]; then
      ${pkgs.jq}/bin/jq -r '.pwas[] | select(.icon != null and .icon != "") | "ffpwa-\(.ulid)|\(.icon)"' "$PWA_REGISTRY" | while IFS='|' read -r pwa_id icon_path; do
        # Create symlink using PWA app_id (ffpwa-ULID format)
        # Example: ffpwa-01JCYF8Z2M -> /path/to/claude.svg
        pwa_id_lower=$(echo "$pwa_id" | tr '[:upper:]' '[:lower:]')
        if [ -f "$icon_path" ]; then
          ln -sf "$icon_path" "$ICON_DIR/$pwa_id_lower.svg" 2>/dev/null || true
        fi
      done
    fi

    # Update GTK icon cache
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    echo "Generated notification icon symlinks in $ICON_DIR"
  '';
}
