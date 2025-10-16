{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.wayvnc;

  # Generate wayvnc configuration
  wayvncConfig = ''
    address=${cfg.address}
    port=${toString cfg.port}
    enable_auth=${if cfg.enableAuth then "true" else "false"}
    enable_pam=${if cfg.enablePAM then "true" else "false"}
    ${optionalString cfg.enableGPU "enable_gpu_h264=true"}
    max_fps=${toString cfg.maxFPS}

    ${cfg.extraConfig}
  '';

in {
  options.services.wayvnc = {
    enable = mkEnableOption "WayVNC remote desktop server";

    package = mkOption {
      type = types.package;
      default = pkgs.wayvnc;
      description = "WayVNC package to use";
    };

    user = mkOption {
      type = types.str;
      default = config.services.mangowc.user or "vpittamp";
      description = "User to run wayvnc (should match compositor user)";
    };

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "IP address to listen on (0.0.0.0 for all interfaces)";
    };

    port = mkOption {
      type = types.port;
      default = 5900;
      description = "VNC port to listen on";
    };

    enablePAM = mkOption {
      type = types.bool;
      default = true;
      description = "Enable PAM authentication (integrates with 1Password)";
    };

    enableAuth = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable authentication requirement.
        If false, VNC server allows unauthenticated connections (insecure).
      '';
    };

    maxFPS = mkOption {
      type = types.ints.positive;
      default = 120;
      description = ''
        Maximum frame rate for screen capture.
        Note: Effective FPS is typically half of maxFPS setting.
      '';
    };

    enableGPU = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable GPU-accelerated H.264 encoding if available.
        Falls back to CPU encoding if GPU unavailable (common in QEMU VMs).
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional wayvnc configuration (appended to generated config)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.mangowc.enable or false;
        message = "wayvnc requires MangoWC compositor to be enabled (services.mangowc.enable = true)";
      }
      {
        assertion = cfg.user == (config.services.mangowc.user or cfg.user);
        message = "wayvnc user must match MangoWC compositor user";
      }
    ];

    # Install wayvnc package
    environment.systemPackages = [ cfg.package ];

    # PAM configuration for wayvnc authentication
    security.pam.services.wayvnc = mkIf cfg.enablePAM {
      text = ''
        auth    required pam_unix.so
        account required pam_unix.so
        session required pam_unix.so
      '';
    };

    # WayVNC configuration file
    environment.etc."wayvnc/config" = {
      text = wayvncConfig;
      mode = "0644";
    };

    # User systemd service for wayvnc
    systemd.user.services.wayvnc = {
      description = "WayVNC Remote Desktop Server";
      after = [ "mangowc.service" ];
      requires = [ "mangowc.service" ];
      partOf = [ "graphical-session.target" ];

      environment = {
        WAYLAND_DISPLAY = "wayland-1";
        XDG_RUNTIME_DIR = "/run/user/%U";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/wayvnc --config=/etc/wayvnc/config";
        Restart = "on-failure";
        RestartSec = "5s";

        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";

        # Allow writing to runtime directory
        ReadWritePaths = [ "/run/user/%U" ];
      };

      wantedBy = [ "default.target" ];
    };

    # Open firewall port for VNC
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
