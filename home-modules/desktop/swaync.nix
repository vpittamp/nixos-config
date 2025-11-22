{ config, pkgs, lib, osConfig ? null, ... }:

let
  hostname =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "";
  isM1 = hostname == "nixos-m1";
  # Match monitoring widget dimensions (450px width, 90% height)
  # M1: 800px logical height * 0.9 = 720px
  # Hetzner: 1080px height * 0.9 = 972px
  controlCenterHeight = if isM1 then 720 else 972;
  controlCenterWidth = 450;
  arinAssets = builtins.path { path = ../../assets/swaync/arin; name = "swaync-arin-assets"; };
  dashboardAssets = builtins.path { path = ../../assets/swaync/dashboard/images; name = "swaync-dashboard-images"; };
  configDir = "${config.home.homeDirectory}/.config";
  arinAssetUrl = "file://${configDir}/swaync/assets/arin";
  dashboardAssetUrl = "file://${configDir}/swaync/assets/dashboard";

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
    sapphire = "#74c7ec";
    sky = "#89dceb";
    mauve = "#cba6f7";
    yellow = "#f9e2af";
    red = "#f38ba8";
    green = "#a6e3a1";
    teal = "#94e2d5";
  };

  brightnessWidgets = [
    {
      name = "backlight#display-main";
      config = {
        label = "Built-in Display";
        device = "apple-panel-bl";
        min = 5;
      };
    }
  ] ++ lib.optionals isM1 [
    {
      name = "backlight#display-sidecar";
      config = {
        label = "Stage Manager Display";
        device = "228600000.dsi.0";
        min = 5;
      };
    }
  ] ++ [
    {
      name = "backlight#keyboard";
      config = {
        label = "Keyboard Backlight";
        device = "kbd_backlight";
        subsystem = "leds";
        min = 0;
      };
    }
  ];

  brightnessWidgetNames = map (widget: widget.name) brightnessWidgets;
  brightnessWidgetConfig = lib.listToAttrs (map (widget: {
    name = widget.name;
    value = widget.config;
  }) brightnessWidgets);

  systemMonitorButtons = [
    {
      label = "";
      command = "ghostty -e htop";
    }
    {
      label = "";
      command = "ghostty -e btop";
    }
    {
      label = "";
      command = "ghostty -e bmon";
    }
    {
      label = "";
      command = "ghostty -e gdu -d1 /";
    }
  ];

  connectivityButtons = [
    {
      label = "";
      command = "nm-connection-editor";
    }
    {
      label = "";
      command = "blueman-manager";
    }
    {
      label = "";
      command = "pavucontrol";
    }
    {
      label = "";
      command = "ghostty -e tailscale status";
    }
  ];

  appsLauncherButtons = [
    {
      label = "";
      command = "firefox";
    }
    {
      label = "";
      command = "ghostty";
    }
    {
      label = "";
      command = "code";
    }
    {
      label = "";
      command = ''sh -c "xdg-open $HOME"'';
    }
  ];

  sessionButtons = [
    {
      label = "";
      command = "gnome-calendar";
    }
    {
      label = "";
      command = ''sh -c "grim -g \"$(slurp)\" - | wl-copy"'';
    }
    {
      label = "";
      command = "swaylock -f";
    }
    {
      label = "";
      command = "systemctl suspend";
    }
  ];

  buttonWidgets = [
    {
      name = "buttons-grid#system-monitors";
      config = { actions = systemMonitorButtons; };
    }
    {
      name = "buttons-grid#quick-actions";
      config = { actions = connectivityButtons; };
    }
    {
      name = "buttons-grid#apps-launchers";
      config = { actions = appsLauncherButtons; };
    }
    {
      name = "buttons-grid#session-actions";
      config = { actions = sessionButtons; };
    }
  ];

  buttonWidgetNames = map (widget: widget.name) buttonWidgets;
  buttonWidgetConfig = lib.listToAttrs (map (widget: {
    name = widget.name;
    value = widget.config;
  }) buttonWidgets);

  # Catppuccin Mocha CSS for SwayNC
  # Feature 057: User Story 1 - Unified Theming
  # Updated to match eww-monitoring-panel transparency and styling
  swayNcStyle = ''
    /* Feature 057: Unified Bar System - Catppuccin Mocha Theme */
    /* Styled to match eww-monitoring-panel appearance */

    * {
      all: unset;
      font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font", "Ubuntu Nerd Font", sans-serif;
    }

    .notification-window {
      background-color: rgba(30, 30, 46, 0.50);
      border: 2px solid rgba(137, 180, 250, 0.2);
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    }

    .notification {
      background-color: rgba(49, 50, 68, 0.4);
      color: ${mocha.text};
      padding: 10px;
      margin: 5px;
      border-radius: 8px;
      border: 1px solid ${mocha.overlay0};
      transition: all 150ms ease;
    }

    .notification:hover {
      background-color: rgba(69, 71, 90, 0.5);
      border-color: ${mocha.overlay0};
      box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
    }

    .notification-default-action {
      background-color: rgba(49, 50, 68, 0.4);
      color: ${mocha.text};
      transition: all 150ms ease;
    }

    .notification-default-action:hover {
      background-color: rgba(137, 180, 250, 0.6);
      color: ${mocha.base};
      box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
    }

    .notification-close-button {
      background-color: ${mocha.red};
      color: ${mocha.text};
      border-radius: 50%;
      transition: all 150ms ease;
    }

    .notification-close-button:hover {
      background-color: #ff0000;
      box-shadow: 0 0 8px rgba(243, 139, 168, 0.6);
    }

    .control-center {
      background-color: rgba(30, 30, 46, 0.70);
      border: 2px solid rgba(137, 180, 250, 0.2);
      border-radius: 12px;
      padding: 8px;
      margin: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    }

    .control-center-list {
      background-color: transparent;
    }

    .widget-title {
      color: ${mocha.text};
      font-weight: bold;
      font-size: 14px;
      margin: 10px;
    }

    .widget-dnd {
      background-color: rgba(49, 50, 68, 0.4);
      color: ${mocha.text};
      padding: 8px 12px;
      margin: 5px;
      border-radius: 8px;
      border: 1px solid ${mocha.overlay0};
      transition: all 150ms ease;
    }

    .widget-dnd:hover {
      background-color: rgba(69, 71, 90, 0.5);
      border-color: ${mocha.overlay0};
    }

    .widget-label {
      color: ${mocha.subtext0};
      font-size: 12px;
    }

    .widget-mpris {
      background-color: rgba(49, 50, 68, 0.4);
      color: ${mocha.text};
      padding: 10px;
      margin: 5px;
      border-radius: 8px;
      border: 1px solid ${mocha.overlay0};
      transition: all 150ms ease;
    }

    .widget-mpris:hover {
      background-color: rgba(69, 71, 90, 0.5);
      border-color: ${mocha.overlay0};
    }

    .widget-buttons-grid flowboxchild {
      min-width: 48px;
      padding: 0;
      margin: 1px;
    }

    .widget-buttons-grid flowboxchild > button {
      background-color: rgba(49, 50, 68, 0.4);
      color: ${mocha.text};
      border-radius: 8px;
      border: 1px solid ${mocha.overlay0};
      padding: 6px;
      margin: 2px;
      min-width: 44px;
      min-height: 44px;
      font-weight: 600;
      font-size: 1.15em;
      display: flex;
      align-items: center;
      justify-content: center;
      background-image: none;
      box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
      transition: all 150ms ease;
    }

    .widget-buttons-grid flowboxchild > button:hover {
      background-color: rgba(137, 180, 250, 0.6);
      border-color: ${mocha.blue};
      color: ${mocha.base};
      box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
      transform: scale(1.05);
    }

    .widget-backlight slider, .widget-backlight scale {
      min-height: 24px;
    }

    .widget-backlight scale trough {
      background-color: rgba(49, 50, 68, 0.9);
      border-radius: 8px;
    }

    .widget-backlight scale highlight {
      background: linear-gradient(90deg, ${mocha.blue}, ${mocha.sapphire});
      border-radius: 8px;
    }

    .widget-backlight scale slider {
      background-color: ${mocha.text};
      border-radius: 50%;
      min-height: 16px;
      min-width: 16px;
    }

    /* Scrollbar styling to match monitoring widget */
    scrollbar {
      background-color: transparent;
      border-radius: 4px;
    }

    scrollbar slider {
      background-color: ${mocha.overlay0};
      border-radius: 4px;
      min-width: 6px;
    }

    scrollbar slider:hover {
      background-color: ${mocha.surface1};
    }

    /* Section headers */
    .widget-label {
      background-color: rgba(24, 24, 37, 0.4);
      border-bottom: 1px solid ${mocha.overlay0};
      border-radius: 8px;
      padding: 8px 12px;
      margin-bottom: 8px;
      font-size: 12px;
      font-weight: bold;
      color: ${mocha.teal};
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

    # Quick-action dependencies so the buttons always launch a GUI even if
    # other modules (like swaybar-enhanced) are turned off in the future.
    ghostty
    btop
    htop
    bmon
    gdu
    pavucontrol
    networkmanagerapplet
    blueman
    gnome-calendar
    grim
    slurp
    wl-clipboard
  ];

  # Generate SwayNC style.css with unified theme colors
  # Feature 057: T016 - Generate SwayNC style.css from appearance.json colors
  xdg.configFile."swaync/style.css".text = swayNcStyle;

  # Vendor Catppuccin/Arin + dashboard assets for icon-backed buttons
  xdg.configFile."swaync/assets/arin".source = arinAssets;
  xdg.configFile."swaync/assets/dashboard".source = dashboardAssets;

  # Feature 057: T027-T031 - SwayNC config.json with widget layout
  # User Story 5: Persistent vs. Transient Information Layout
  # Notification center shows transient info (CPU, memory, network, disk) when toggled open
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    # Core notification settings
    # Match monitoring widget positioning (right center, 8px margin)
    positionX = "right";
    positionY = "center";
    layer = "overlay";
    control-center-layer = "overlay";
    layer-shell = true;
    cssPriority = "user";
    control-center-margin-top = 8;
    control-center-margin-bottom = 8;
    control-center-margin-right = 8;
    control-center-margin-left = 0;
    notification-2fa-action = false;
    notification-inline-replies = false;
    notification-icon-size = 48;
    notification-body-image-height = 100;
    notification-body-image-width = 200;
    timeout = 10;
    timeout-low = 5;
    timeout-critical = 0;  # Never timeout critical notifications
    control-center-width = controlCenterWidth;
    control-center-height = controlCenterHeight;
    notification-window-width = 400;
    fit-to-screen = true;
    image-visibility = "when-available";
    transition-time = 200;
    hide-on-clear = false;
    hide-on-action = false;
    script-fail-notify = true;

    # Feature 090: Notification callback keybindings
    # Ctrl+R - Return to Claude Code terminal (primary action)
    # Escape - Dismiss notification or close notification center
    keyboard-shortcuts = {
      notification-close = [ "Escape" ];
      notification-action-0 = [ "ctrl+r" "Return" ];
      notification-action-1 = [ "Escape" ];
    };

    # Widget layout for control center
    # Feature 057: User Story 5 - Transient information (CPU, memory, network, disk)
    widgets =
      [
        "title"
        "dnd"
        "label#monitors-header"
      ]
      ++ buttonWidgetNames
      ++ [
        "label#brightness-header"
      ]
      ++ brightnessWidgetNames
      ++ [
        "notifications"
        "mpris"
      ];

    # Widget configuration for all widgets
    widget-config = (
      {
      "label#monitors-header" = {
        text = "━━━ System Monitors & Shortcuts ━━━";
        max-lines = 1;
      };

      "label#brightness-header" = {
        text = "━━━ Brightness Controls ━━━";
        max-lines = 1;
      };
      }
    ) // brightnessWidgetConfig // buttonWidgetConfig;

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

  # Ensure swaync picks up config/style changes immediately after activation
  home.activation.restartSwaync = lib.hm.dag.entryAfter ["generateNotificationIcons"] ''
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user try-restart swaync.service >/dev/null 2>&1 || true
    fi
  '';
}
