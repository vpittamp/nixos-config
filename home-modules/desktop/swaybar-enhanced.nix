{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.swaybar-enhanced;

  # Status generator script location
  statusGeneratorScript = "${config.home.homeDirectory}/.config/sway/swaybar/status-generator.py";

  # Default Catppuccin Mocha color theme
  defaultTheme = {
    name = "catppuccin-mocha";
    colors = {
      volume = {
        normal = "#a6e3a1";  # Green
        muted = "#6c7086";   # Gray
      };
      battery = {
        charging = "#a6e3a1";  # Green
        high = "#a6e3a1";      # Green (>50%)
        medium = "#f9e2af";    # Yellow (20-50%)
        low = "#f38ba8";       # Red (<20%)
      };
      network = {
        connected = "#a6e3a1";     # Green
        connecting = "#f9e2af";    # Yellow
        disconnected = "#6c7086";  # Gray
        disabled = "#6c7086";      # Gray
        weak = "#f9e2af";          # Yellow (<40% signal)
      };
      bluetooth = {
        connected = "#89b4fa";   # Blue
        enabled = "#a6e3a1";     # Green
        disabled = "#6c7086";    # Gray
      };
    };
  };

in {
  options.programs.swaybar-enhanced = {
    enable = mkEnableOption "Enhanced swaybar status with rich system indicators";

    iconFont = mkOption {
      type = types.str;
      default = "NerdFont";
      description = "Font to use for Nerd Font icons";
    };

    theme = mkOption {
      type = types.attrs;
      default = defaultTheme;
      description = "Color theme for status blocks (Catppuccin Mocha by default)";
    };

    intervals = mkOption {
      type = types.attrs;
      default = {
        battery = 30;
        volume = 1;
        network = 5;
        bluetooth = 10;
      };
      description = "Update intervals for status blocks (in seconds)";
    };

    clickHandlers = mkOption {
      type = types.attrs;
      default = {
        volume = "${pkgs.pavucontrol}/bin/pavucontrol";
        network = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
        bluetooth = "${pkgs.blueman}/bin/blueman-manager";
        battery = "";  # No default handler
      };
      description = "Click handler commands for status blocks";
    };

    detectBattery = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-detect and show battery indicator if hardware present";
    };

    detectBluetooth = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-detect and show bluetooth indicator if hardware present";
    };
  };

  config = mkIf cfg.enable {
    # Install required packages
    # Note: Python with pydbus and pygobject3 is provided by python-environment.nix (shared environment)
    home.packages = with pkgs; [
      # Nerd Fonts for icons
      nerd-fonts.fira-code
      nerd-fonts.hack

      # Click handler applications
      pavucontrol         # Volume mixer
      networkmanagerapplet  # Network manager GUI
      blueman             # Bluetooth manager
    ];

    # Install status generator script and modules
    xdg.configFile = {
      # Main status generator script
      "sway/swaybar/status-generator.py" = {
        source = ./swaybar/status-generator.py;
        executable = true;
      };

      # Status block modules
      "sway/swaybar/blocks/__init__.py".source = ./swaybar/blocks/__init__.py;
      "sway/swaybar/blocks/models.py".source = ./swaybar/blocks/models.py;
      "sway/swaybar/blocks/config.py".source = ./swaybar/blocks/config.py;
      "sway/swaybar/blocks/click_handler.py".source = ./swaybar/blocks/click_handler.py;

      # Status block implementations
      "sway/swaybar/blocks/volume.py".source = ./swaybar/blocks/volume.py;
      "sway/swaybar/blocks/battery.py".source = ./swaybar/blocks/battery.py;
      "sway/swaybar/blocks/network.py".source = ./swaybar/blocks/network.py;
      "sway/swaybar/blocks/bluetooth.py".source = ./swaybar/blocks/bluetooth.py;
      "sway/swaybar/blocks/system.py".source = ./swaybar/blocks/system.py;
    };

    # Note: To enable enhanced status bar, update home-modules/desktop/swaybar.nix
    # Replace systemMonitorScript with:
    #   enhancedStatusScript = pkgs.writeShellScript "swaybar-enhanced-status" ''
    #     exec ${pkgs.python311.withPackages (ps: [ps.pydbus ps.pygobject3])}/bin/python \
    #       ${config.xdg.configHome}/sway/swaybar/status-generator.py
    #   '';
    # Then use ${enhancedStatusScript} in the top bar's statusCommand
  };
}
