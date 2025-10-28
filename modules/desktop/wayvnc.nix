# wayvnc VNC Server for Wayland Configuration Module
# Provides remote desktop access for Sway (FR-021, FR-022)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.wayvnc;
in {
  options.services.wayvnc = {
    enable = mkEnableOption "wayvnc VNC server for Wayland";

    package = mkOption {
      type = types.package;
      default = pkgs.wayvnc;
      description = "wayvnc package to use";
    };

    port = mkOption {
      type = types.port;
      default = 5900;
      description = "TCP port for VNC server";
    };

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address for VNC server";
    };

    enableAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Enable authentication for VNC connections";
    };

    enablePAM = mkOption {
      type = types.bool;
      default = true;
      description = "Enable PAM authentication";
    };

    enableTLS = mkOption {
      type = types.bool;
      default = false;
      description = "Enable TLS encryption for VNC connections";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to wayvnc configuration file (overrides generated config)";
    };
  };

  config = mkIf cfg.enable {
    # Install wayvnc package
    environment.systemPackages = [ cfg.package ];

    # Enable PAM if authentication is enabled
    security.pam.services.wayvnc.text = mkIf (cfg.enableAuth && cfg.enablePAM) ''
      auth    required pam_unix.so
      account required pam_unix.so
    '';

    # Note: wayvnc runs as user service (configured in home-manager)
    # This module only provides system-level dependencies

    # Firewall: Open VNC port if needed
    # networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
