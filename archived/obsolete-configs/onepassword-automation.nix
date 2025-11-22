# 1Password Service Account Automation Module
# Provides automated authentication using service account tokens
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.onepassword-automation;
in
{
  options.services.onepassword-automation = {
    enable = mkEnableOption "1Password service account automation";

    tokenReference = mkOption {
      type = types.str;
      default = "op://Employee/ja6iykklyslhq7tccnkgaj4joe/credential";
      description = "1Password secret reference for the service account token (using item ID)";
    };

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "User to run the service as";
    };
  };

  config = mkIf cfg.enable {
    # Create directory for token storage
    systemd.tmpfiles.rules = [
      "d /var/lib/onepassword 0700 ${cfg.user} users -"
    ];

    # Create environment file that retrieves token from 1Password
    # Uses 1Password secret reference to fetch the token dynamically
    environment.etc."onepassword/service-token.env" = {
      mode = "0600";
      user = cfg.user;
      text = ''
        # 1Password Service Account Token
        # Dynamically fetch from 1Password using secret reference
        export OP_SERVICE_ACCOUNT_TOKEN="$(op read '${cfg.tokenReference}')"
      '';
    };

    # Setup script to initialize the service account token
    system.activationScripts.onePasswordServiceAccount = ''
      # Create secure directory for token storage
      mkdir -p /var/lib/onepassword
      chmod 700 /var/lib/onepassword
      chown ${cfg.user}:users /var/lib/onepassword

      # Note: The actual token must be manually placed in /var/lib/onepassword/service-account-token
      # Run: op read '${cfg.tokenReference}' > /var/lib/onepassword/service-account-token
      # Or use the provided setup script: /etc/nixos/scripts/1password-setup-token.sh
    '';

    # Create setup script to fetch and store token
    environment.etc."nixos/scripts/1password-setup-token.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -e

        echo "Setting up 1Password service account token..."

        # Check if already logged in to personal account
        if ! op account list | grep -q "vinod@pittampalli.com"; then
          echo "Please sign in to your personal 1Password account first:"
          eval $(op signin)
        fi

        # Fetch the service account token using secret reference
        echo "Fetching service account token from 1Password..."
        TOKEN=$(op read '${cfg.tokenReference}')

        if [ -z "$TOKEN" ]; then
          echo "Error: Could not fetch token from 1Password"
          exit 1
        fi

        # Store securely
        echo "$TOKEN" > /var/lib/onepassword/service-account-token
        chmod 600 /var/lib/onepassword/service-account-token
        chown ${cfg.user}:users /var/lib/onepassword/service-account-token

        echo "Service account token stored successfully!"
        echo ""
        echo "You can now use: source /etc/onepassword/load-token.sh"
        echo "Or simply: git-push, git-pull, git-fetch (aliases configured)"
      '';
    };

    # Create loader script
    environment.etc."onepassword/load-token.sh" = {
      mode = "0644";
      text = ''
        # Load 1Password service account token
        if [ -f /var/lib/onepassword/service-account-token ]; then
          export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"
          export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
        else
          echo "Service account token not found. Run: sudo /etc/nixos/scripts/1password-setup-token.sh"
        fi
      '';
    };

    # Create shell aliases for convenience
    programs.bash.shellAliases = {
      "op-auth" = "source /etc/onepassword/load-token.sh";
      "git-push" = "source /etc/onepassword/load-token.sh && git push";
      "git-pull" = "source /etc/onepassword/load-token.sh && git pull";
      "git-fetch" = "source /etc/onepassword/load-token.sh && git fetch";
      "op-setup" = "sudo /etc/nixos/scripts/1password-setup-token.sh";
    };

    # Add to user's shell profile
    environment.interactiveShellInit = ''
      # Auto-load 1Password service account token if available
      if [ -f /var/lib/onepassword/service-account-token ]; then
        export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"
        export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
      fi
    '';
  };
}