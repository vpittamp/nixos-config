# RustDesk Service Module
# Configures RustDesk to auto-start with the desktop session
# Enables direct IP access for Tailscale integration
# Supports pre-configured permanent password for headless VMs
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rustdesk;
in
{
  options.services.rustdesk = {
    enable = mkEnableOption "RustDesk remote desktop service";

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "User to run RustDesk service for";
    };

    enableDirectIpAccess = mkOption {
      type = types.bool;
      default = true;
      description = "Enable direct IP access for Tailscale integration";
    };

    permanentPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Pre-configured permanent password for RustDesk. If null, RustDesk generates random password.";
    };

    enableSystemService = mkOption {
      type = types.bool;
      default = false;
      description = "Enable RustDesk as system service (runs before user login, useful for headless VMs)";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.rustdesk-flutter;
      description = "RustDesk package to use";
    };
  };

  config = mkIf cfg.enable {
    # Ensure RustDesk package is installed
    environment.systemPackages = [ cfg.package ];

    # System-wide service (runs before user login, for headless VMs)
    systemd.services.rustdesk-headless = mkIf cfg.enableSystemService {
      description = "RustDesk Headless Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        ExecStart = "${cfg.package}/bin/rustdesk --service";
        Restart = "always";
        RestartSec = "5s";

        # Environment variables for headless operation with software GL rendering
        Environment = [
          "HOME=${config.users.users.${cfg.user}.home}"
          "PATH=${pkgs.coreutils}/bin:${pkgs.glib}/bin"
          "LIBGL_ALWAYS_SOFTWARE=1"
          "MESA_GL_VERSION_OVERRIDE=3.3"
          "GALLIUM_DRIVER=llvmpipe"
          "DISPLAY=:0"
        ];
      };
    };

    # User service (runs with graphical session)
    systemd.user.services.rustdesk = mkIf (!cfg.enableSystemService) {
      description = "RustDesk Remote Desktop Service";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/rustdesk";
        Restart = "on-failure";
        RestartSec = "5s";

        # Environment variables for Wayland/X11 support and software GL rendering
        Environment = [
          "PATH=${pkgs.coreutils}/bin:${pkgs.glib}/bin"
          "LIBGL_ALWAYS_SOFTWARE=1"
          "MESA_GL_VERSION_OVERRIDE=3.3"
          "GALLIUM_DRIVER=llvmpipe"
        ];
      };
    };

    # Configure RustDesk settings for direct IP access
    # This creates the config file with direct-server enabled
    systemd.user.tmpfiles.rules = mkIf cfg.enableDirectIpAccess [
      "d ${config.users.users.${cfg.user}.home}/.config/rustdesk 0700 ${cfg.user} users -"
      "f ${config.users.users.${cfg.user}.home}/.config/rustdesk/RustDesk2.toml 0600 ${cfg.user} users -"
    ];

    # Create activation script to ensure RustDesk config exists
    system.activationScripts.rustdeskConfig = ''
      # Ensure user config directory exists
      ${pkgs.coreutils}/bin/mkdir -p ${config.users.users.${cfg.user}.home}/.config/rustdesk
      ${pkgs.coreutils}/bin/chown ${cfg.user}:users ${config.users.users.${cfg.user}.home}/.config/rustdesk
      ${pkgs.coreutils}/bin/chmod 700 ${config.users.users.${cfg.user}.home}/.config/rustdesk

      # Create RustDesk2.toml configuration
      config_file="${config.users.users.${cfg.user}.home}/.config/rustdesk/RustDesk2.toml"

      # Build configuration content
      ${pkgs.coreutils}/bin/cat > "$config_file" << 'EOF'
[options]
${optionalString cfg.enableDirectIpAccess ''
direct-server = "Y"
direct-access-port = "21116"
''}
${optionalString (cfg.permanentPassword != null) ''
permanent-password = "${cfg.permanentPassword}"
''}
# Enable unattended access (always allow connections without confirmation)
enable-keyboard = true
enable-clipboard = true
enable-file-transfer = true
enable-audio = true
allow-remote-restart = true
allow-remote-config-modification = false
EOF

      ${pkgs.coreutils}/bin/chown ${cfg.user}:users "$config_file"
      ${pkgs.coreutils}/bin/chmod 600 "$config_file"
    '';

    # Firewall configuration for RustDesk
    networking.firewall = {
      allowedTCPPorts = [ 21115 21116 21117 21118 21119 ];
      allowedUDPPorts = [ 21116 ];
    };
  };
}
