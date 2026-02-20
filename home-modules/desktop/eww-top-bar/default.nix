{ config, lib, pkgs, osConfig ? null, ... }:

with lib;

let
  cfg = config.programs.eww-top-bar;

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
    teal = "#94e2d5";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    peach = "#fab387";
    red = "#f38ba8";
    mauve = "#cba6f7";
  };

  # Safely get hostname - osConfig may be null in standalone home-manager
  hostname = if osConfig != null then (osConfig.networking.hostName or "") else "";
  isHeadless = hostname == "hetzner";
  isRyzen = hostname == "ryzen";
  isThinkPad = hostname == "thinkpad";
  isLaptop = isThinkPad;  # Laptops have brightness control

  topBarOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; showTray = true; }
    ] else if isRyzen then [
      { name = "DP-1"; showTray = true; }
      { name = "HDMI-A-1"; showTray = false; }
      { name = "DP-2"; showTray = false; }
      { name = "DP-3"; showTray = false; }
    ] else [
      { name = "eDP-1"; showTray = true; }
    ];

  sanitizeOutputName = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "_" "-"] ["" "" "" "" ""] name
    );

  scripts = import ./scripts.nix { inherit pkgs; };
  inherit (scripts) hardwareDetectScript topbarSpinnerScript topbarSpinnerOpacityScript togglePowermenuScript toggleBadgeShelfScript;

in
{
  options.programs.eww-top-bar = {
    enable = mkEnableOption "Eww-based top bar with system metrics";
    updateIntervals = {
      systemMetrics = mkOption { type = types.int; default = 2; };
      diskNetwork = mkOption { type = types.int; default = 5; };
      dateTime = mkOption { type = types.int; default = 1; };
      daemonHealth = mkOption { type = types.int; default = 5; };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.eww togglePowermenuScript toggleBadgeShelfScript ];

    xdg.configFile."eww/eww-top-bar/scripts/hardware-detect.py" = {
      source = hardwareDetectScript;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/system-metrics.py".source = ./scripts/system-metrics.py;
    xdg.configFile."eww/eww-top-bar/scripts/volume-monitor.py".source = ./scripts/volume-monitor.py;
    xdg.configFile."eww/eww-top-bar/scripts/battery-monitor.py".source = ./scripts/battery-monitor.py;
    xdg.configFile."eww/eww-top-bar/scripts/bluetooth-monitor.py".source = ./scripts/bluetooth-monitor.py;
    xdg.configFile."eww/eww-top-bar/scripts/active-project.py".source = ./scripts/active-project.py;
    xdg.configFile."eww/eww-top-bar/scripts/build-health.sh".source = ./scripts/build-health.sh;
    xdg.configFile."eww/eww-top-bar/scripts/active-outputs-status.sh".source = ./scripts/active-outputs-status.sh;
    xdg.configFile."eww/eww-top-bar/scripts/i3pm-health.sh".source = ./scripts/i3pm-health.sh;
    xdg.configFile."eww/eww-top-bar/scripts/wifi-status.sh".source = ./scripts/wifi-status.sh;
    xdg.configFile."eww/eww-top-bar/scripts/volume-status.sh".source = ./scripts/volume-status.sh;
    xdg.configFile."eww/eww-top-bar/scripts/notification-monitor.py".source = ./scripts/notification-monitor.py;
    xdg.configFile."eww/eww-top-bar/scripts/spinner-frame.sh".source = ./scripts/spinner-frame.sh;
    xdg.configFile."eww/eww-top-bar/scripts/spinner-opacity.sh".source = ./scripts/spinner-opacity.sh;

    xdg.configFile."eww/eww-top-bar/eww.yuck".text = import ./yuck/main.yuck.nix {
      inherit config lib pkgs topBarOutputs sanitizeOutputName topbarSpinnerScript topbarSpinnerOpacityScript isLaptop;
      inherit (pkgs.stdenv.hostPlatform) system;
      osConfig = osConfig;
    };

    xdg.configFile."eww/eww-top-bar/eww.scss".text = import ./scss/main.scss.nix {
      inherit config lib pkgs;
    };

    systemd.user.services.eww-top-bar = {
      Unit = {
        Description = "Eww top bar with system metrics";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" "i3-project-daemon.service" "otel-ai-monitor.service" "home-manager-vpittamp.service" ];
        Wants = [ "i3-project-daemon.service" "otel-ai-monitor.service" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${config.xdg.configHome}/eww/eww-top-bar kill 2>/dev/null || true'";
        ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize --config ${config.xdg.configHome}/eww/eww-top-bar";
        # IMPORTANT: eww open-many can hang indefinitely due to IPC issues
        # Run it with timeout and in background to prevent blocking ExecStartPost
        ExecStartPost = let
          windowIds = lib.concatMapStringsSep " " (output: "top-bar-${sanitizeOutputName output.name}") topBarOutputs;
          ewwCmd = "${pkgs.eww}/bin/eww --config ${config.xdg.configHome}/eww/eww-top-bar";
          timeout = "${pkgs.coreutils}/bin/timeout";
        in "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 50); do ${timeout} 1s ${ewwCmd} ping >/dev/null 2>&1 && break; sleep 0.2; done; ${ewwCmd} close-all 2>/dev/null || true; ${timeout} 5s ${ewwCmd} open-many ${windowIds} & sleep 0.5'";
        ExecStop = "${pkgs.eww}/bin/eww kill --config ${config.xdg.configHome}/eww/eww-top-bar";
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
