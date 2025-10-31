# 1Password Password Management Module
# Automatically syncs user passwords from 1Password to NixOS
# Uses 1Password service account for automated secret retrieval
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.onepassword-password-management;
in
{
  options.services.onepassword-password-management = {
    enable = mkEnableOption "1Password password management for system users";

    users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          passwordReference = mkOption {
            type = types.str;
            description = "1Password secret reference for the user's password (e.g., op://Employee/NixOS User Password/password)";
          };

          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable password management for this user";
          };
        };
      });
      default = {};
      description = "User password configurations keyed by username";
    };

    tokenReference = mkOption {
      type = types.str;
      default = "op://Employee/ja6iykklyslhq7tccnkgaj4joe/credential";
      description = "1Password secret reference for the service account token";
    };

    updateInterval = mkOption {
      type = types.str;
      default = "hourly";
      description = "How often to check for password updates (systemd timer format: hourly, daily, etc.)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure 1Password CLI is available
    environment.systemPackages = [ pkgs._1password-cli ];

    # Create directory for password files
    systemd.tmpfiles.rules = [
      "d /run/secrets 0755 root root -"
      "d /var/lib/onepassword-passwords 0700 root root -"
    ];

    # Systemd service to fetch and update passwords
    systemd.services.onepassword-password-sync = {
      description = "Sync user passwords from 1Password";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };

      script = ''
        set -e

        # Check if service account token exists
        if [ ! -f /var/lib/onepassword/service-account-token ]; then
          echo "Error: Service account token not found at /var/lib/onepassword/service-account-token"
          echo "Please run: sudo /etc/nixos/scripts/1password-setup-token.sh"
          exit 1
        fi

        # Load service account token
        export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"

        # Sync each configured user's password
        ${concatStringsSep "\n" (mapAttrsToList (username: userCfg: ''
          if [ "${toString userCfg.enable}" = "1" ]; then
            echo "Syncing password for user: ${username}"

            # Fetch password from 1Password
            PASSWORD=$(${pkgs._1password-cli}/bin/op read '${userCfg.passwordReference}' 2>/dev/null || echo "")

            if [ -z "$PASSWORD" ]; then
              echo "Warning: Could not fetch password for ${username} from 1Password"
            else
              # Generate password hash using mkpasswd
              PASSWORD_HASH=$(echo -n "$PASSWORD" | ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s)

              # Write to secure location
              echo -n "$PASSWORD_HASH" > /run/secrets/${username}-password
              chmod 600 /run/secrets/${username}-password

              echo "Password hash updated for ${username}"
            fi
          fi
        '') cfg.users)}

        echo "Password sync completed"
      '';
    };

    # Timer to run password sync periodically
    systemd.timers.onepassword-password-sync = {
      description = "Timer for 1Password password sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";  # Run 5 minutes after boot
        OnUnitActiveSec = cfg.updateInterval;
        Persistent = true;
      };
    };

    # Configure users to use password files
    users.users = mapAttrs (username: userCfg: {
      hashedPasswordFile = mkIf userCfg.enable "/run/secrets/${username}-password";
    }) cfg.users;

    # Activation script to ensure initial password sync
    system.activationScripts.onepassword-password-initial-sync = {
      text = ''
        # Run initial password sync if service account token exists
        if [ -f /var/lib/onepassword/service-account-token ]; then
          echo "Running initial 1Password password sync..."
          ${config.systemd.package}/bin/systemctl start onepassword-password-sync.service || true
        else
          echo "Skipping 1Password password sync (service account token not configured)"
          echo "Run: sudo /etc/nixos/scripts/1password-setup-token.sh to configure"
        fi
      '';
      deps = [ "users" ];
    };
  };
}
