# RustDesk Service Module
# Configures RustDesk to auto-start with the desktop session
# Enables direct IP access for Tailscale integration
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

    package = mkOption {
      type = types.package;
      default = pkgs.rustdesk-flutter;
      description = "RustDesk package to use";
    };
  };

  config = mkIf cfg.enable {
    # Ensure RustDesk package is installed
    environment.systemPackages = [ cfg.package ];

    # Create systemd user service for RustDesk
    systemd.user.services.rustdesk = {
      description = "RustDesk Remote Desktop Service";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/rustdesk";
        Restart = "on-failure";
        RestartSec = "5s";

        # Environment variables for Wayland/X11 support
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.glib}/bin";
      };
    };

    # Configure RustDesk settings for direct IP access
    # This creates the config file with direct-server enabled
    systemd.user.tmpfiles.rules = mkIf cfg.enableDirectIpAccess [
      "d ${config.users.users.${cfg.user}.home}/.config/rustdesk 0700 ${cfg.user} users -"
      "f ${config.users.users.${cfg.user}.home}/.config/rustdesk/RustDesk2.toml 0600 ${cfg.user} users -"
    ];

    # Create activation script to ensure RustDesk config exists
    system.activationScripts.rustdeskConfig = mkIf cfg.enableDirectIpAccess ''
      # Ensure user config directory exists
      ${pkgs.coreutils}/bin/mkdir -p ${config.users.users.${cfg.user}.home}/.config/rustdesk
      ${pkgs.coreutils}/bin/chown ${cfg.user}:users ${config.users.users.${cfg.user}.home}/.config/rustdesk
      ${pkgs.coreutils}/bin/chmod 700 ${config.users.users.${cfg.user}.home}/.config/rustdesk

      # Create RustDesk2.toml if it doesn't exist or doesn't have direct-server setting
      config_file="${config.users.users.${cfg.user}.home}/.config/rustdesk/RustDesk2.toml"

      if [ ! -f "$config_file" ] || ! ${pkgs.gnugrep}/bin/grep -q "direct-server" "$config_file"; then
        # Preserve existing config if present
        if [ -f "$config_file" ]; then
          # Check if [options] section exists
          if ${pkgs.gnugrep}/bin/grep -q "^\[options\]" "$config_file"; then
            # Add to existing [options] section if not already present
            if ! ${pkgs.gnugrep}/bin/grep -q "direct-server" "$config_file"; then
              ${pkgs.gnused}/bin/sed -i '/^\[options\]/a direct-server = "Y"\ndirect-access-port = "21116"' "$config_file"
            fi
          else
            # Append [options] section
            ${pkgs.coreutils}/bin/echo "" >> "$config_file"
            ${pkgs.coreutils}/bin/echo "[options]" >> "$config_file"
            ${pkgs.coreutils}/bin/echo 'direct-server = "Y"' >> "$config_file"
            ${pkgs.coreutils}/bin/echo 'direct-access-port = "21116"' >> "$config_file"
          fi
        else
          # Create new config file with minimal settings
          ${pkgs.coreutils}/bin/cat > "$config_file" << 'EOF'
[options]
direct-server = "Y"
direct-access-port = "21116"
EOF
        fi
        ${pkgs.coreutils}/bin/chown ${cfg.user}:users "$config_file"
        ${pkgs.coreutils}/bin/chmod 600 "$config_file"
      fi
    '';

    # Firewall configuration for RustDesk
    networking.firewall = {
      allowedTCPPorts = [ 21115 21116 21117 21118 21119 ];
      allowedUDPPorts = [ 21116 ];
    };
  };
}
