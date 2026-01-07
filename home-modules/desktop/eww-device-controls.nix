# Unified Eww Device Control Panel
# Feature 116: Unified device controls for bare metal NixOS machines
# Provides quick access via top bar expandable panels and comprehensive
# Devices tab in monitoring panel
{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.eww-device-controls;

  # Feature 057: Import unified theme colors (Catppuccin Mocha)
  mocha = {
    base = "#1e1e2e";      # Background base
    mantle = "#181825";    # Darker background
    surface0 = "#313244";  # Surface layer 1
    surface1 = "#45475a";  # Surface layer 2
    overlay0 = "#6c7086";  # Overlay/border
    text = "#cdd6f4";      # Primary text
    subtext0 = "#a6adc8";  # Dimmed text
    blue = "#89b4fa";      # Focused accent
    sapphire = "#74c7ec";  # Memory
    sky = "#89dceb";       # Disk
    teal = "#94e2d5";      # Network / connected
    green = "#a6e3a1";     # Success/healthy
    yellow = "#f9e2af";    # Warning
    peach = "#fab387";     # Temperature
    red = "#f38ba8";       # Urgent/critical
    mauve = "#cba6f7";     # Border accent
  };

  # Detect host type from hostname
  # Safely get hostname - osConfig may be null in standalone home-manager
  hostname = if osConfig != null then (osConfig.networking.hostName or "") else "";
  isHeadless = hostname == "hetzner";
  isRyzen = hostname == "ryzen";
  isThinkPad = hostname == "thinkpad";

  # Determine if this is a laptop (has battery)
  isLaptop = isThinkPad;

  # Scripts paths
  scriptsDir = "${config.xdg.configHome}/eww/eww-device-controls/scripts";

  # Device backend script
  deviceBackendScript = pkgs.writeTextFile {
    name = "device-backend.py";
    executable = true;
    text = builtins.readFile ./eww-device-controls/scripts/device-backend.py;
  };

  # Volume control script
  volumeControlScript = pkgs.writeTextFile {
    name = "volume-control.sh";
    executable = true;
    text = builtins.readFile ./eww-device-controls/scripts/volume-control.sh;
  };

  # Brightness control script
  brightnessControlScript = pkgs.writeTextFile {
    name = "brightness-control.sh";
    executable = true;
    text = builtins.readFile ./eww-device-controls/scripts/brightness-control.sh;
  };

  # Bluetooth control script
  bluetoothControlScript = pkgs.writeTextFile {
    name = "bluetooth-control.sh";
    executable = true;
    text = builtins.readFile ./eww-device-controls/scripts/bluetooth-control.sh;
  };

  # Power profile control script
  powerProfileControlScript = pkgs.writeTextFile {
    name = "power-profile-control.sh";
    executable = true;
    text = builtins.readFile ./eww-device-controls/scripts/power-profile-control.sh;
  };

in
{
  options.programs.eww-device-controls = {
    enable = lib.mkEnableOption "Eww-based unified device controls";

    # Polling intervals (can be overridden per-host)
    volumeInterval = lib.mkOption {
      type = lib.types.str;
      default = "1s";
      description = "Polling interval for volume state";
    };

    brightnessInterval = lib.mkOption {
      type = lib.types.str;
      default = "2s";
      description = "Polling interval for brightness state";
    };

    bluetoothInterval = lib.mkOption {
      type = lib.types.str;
      default = "3s";
      description = "Polling interval for bluetooth state";
    };

    batteryInterval = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Polling interval for battery state";
    };

    fullStateInterval = lib.mkOption {
      type = lib.types.str;
      default = "2s";
      description = "Polling interval for full device state (Devices tab)";
    };

    # Feature toggles
    showBluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show bluetooth controls";
    };

    showNetwork = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show network status";
    };
  };

  config = lib.mkIf cfg.enable {
    # Required packages for device control
    home.packages = with pkgs; [
      # Audio control (PipeWire/WirePlumber)
      wireplumber

      # Brightness control
      brightnessctl

      # Bluetooth control
      bluez

      # Power management queries
      upower

      # Thermal sensors
      lm_sensors

      # Network tools
      networkmanager
    ];

    # Install backend scripts
    xdg.configFile = {
      "eww/eww-device-controls/scripts/device-backend.py" = {
        source = deviceBackendScript;
        executable = true;
      };

      "eww/eww-device-controls/scripts/volume-control.sh" = {
        source = volumeControlScript;
        executable = true;
      };

      "eww/eww-device-controls/scripts/brightness-control.sh" = {
        source = brightnessControlScript;
        executable = true;
      };

      "eww/eww-device-controls/scripts/bluetooth-control.sh" = {
        source = bluetoothControlScript;
        executable = true;
      };

      "eww/eww-device-controls/scripts/power-profile-control.sh" = {
        source = powerProfileControlScript;
        executable = true;
      };

      # Eww widget definitions
      "eww/eww-device-controls/eww.yuck".text = import ./eww-device-controls/eww.yuck.nix {
        inherit config lib pkgs mocha;
        inherit isLaptop isRyzen isThinkPad isHeadless;
        inherit scriptsDir;
      };

      # Eww styles
      "eww/eww-device-controls/eww.scss".text = import ./eww-device-controls/eww.scss.nix {
        inherit config lib pkgs mocha;
      };
    };

    # Note: Device controls widgets are designed to be included in existing eww-top-bar
    # rather than running as a separate Eww daemon. The widgets and scripts are installed
    # to ~/.config/eww/eww-device-controls/ and can be imported or copied to the top bar config.
    #
    # To use the enhanced device controls:
    # 1. Enable this module: programs.eww-device-controls.enable = true
    # 2. The device-backend.py and control scripts will be available
    # 3. Include the widget definitions from eww.yuck in your Eww configuration
    #
    # Alternatively, these scripts can be used directly via the top bar:
    # - ~/.config/eww/eww-device-controls/scripts/device-backend.py --mode volume
    # - ~/.config/eww/eww-device-controls/scripts/volume-control.sh set 50
  };
}
