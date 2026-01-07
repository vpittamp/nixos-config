# Cachix Deploy Agent Module
# Provides automated deployment support via Cachix Deploy
#
# Usage:
#   services.cachix-deploy = {
#     enable = true;
#     onePassword = {
#       enable = true;
#       tokenReference = "op://CLI/Cachix Deploy Agent/token";
#     };
#   };
#
# Initial setup:
#   1. Create agent token at https://app.cachix.org/deploy/
#   2. Store in 1Password or manually create /etc/cachix-agent.token
#   3. Rebuild with: sudo nixos-rebuild switch --flake .#<host>
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cachix-deploy;
in
{
  options.services.cachix-deploy = {
    enable = mkEnableOption "Cachix Deploy agent for automated deployments";

    agentName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Agent name registered with Cachix Deploy (defaults to hostname)";
    };

    tokenFile = mkOption {
      type = types.path;
      default = "/etc/cachix-agent.token";
      description = ''
        Path to file containing the agent token.
        File format: CACHIX_AGENT_TOKEN=<token>
      '';
    };

    onePassword = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use 1Password to provision agent token";
      };

      tokenReference = mkOption {
        type = types.str;
        default = "op://CLI/Cachix Deploy Agent/token";
        description = "1Password reference for agent token (e.g., op://vault/item/field)";
      };
    };

    profile = mkOption {
      type = types.str;
      default = "system";
      description = "Nix profile to manage (system for NixOS, or custom profile path)";
    };

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Cachix Deploy host (null for default api.cachix.org)";
    };

    verbose = mkOption {
      type = types.bool;
      default = false;
      description = "Enable verbose logging for debugging";
    };
  };

  config = mkIf cfg.enable {
    # Install cachix package for CLI access
    environment.systemPackages = [ pkgs.cachix ];

    # Cachix agent systemd service
    systemd.services.cachix-agent = {
      description = "Cachix Deploy Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Wait for token file to exist
      unitConfig = {
        ConditionPathExists = cfg.tokenFile;
      };

      # Ensure Nix binaries are in PATH for nix-store commands
      path = [ config.nix.package pkgs.coreutils pkgs.bash ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        # Run as root for system profile management
        User = "root";

        # Load token from environment file
        EnvironmentFile = cfg.tokenFile;

        # Use /var/cache for cachix agent state (writable)
        CacheDirectory = "cachix";
        StateDirectory = "cachix";
        Environment = [
          "HOME=/var/cache/cachix"
          "XDG_CACHE_HOME=/var/cache/cachix"
        ];

        # Security hardening
        NoNewPrivileges = false;  # Need privileges for system activation
        ProtectSystem = false;    # Need to modify system
        ProtectHome = "read-only";
        PrivateTmp = true;

        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "50%";
      };

      script = ''
        exec ${pkgs.cachix}/bin/cachix deploy agent ${cfg.agentName} \
          ${optionalString (cfg.profile != "system") "--profile ${cfg.profile}"} \
          ${optionalString (cfg.host != null) "--host ${cfg.host}"} \
          ${optionalString cfg.verbose "--verbose"}
      '';
    };

    # Token provisioning from 1Password (optional)
    systemd.services.cachix-token-provision = mkIf cfg.onePassword.enable {
      description = "Provision Cachix agent token from 1Password";
      wantedBy = [ "multi-user.target" ];
      before = [ "cachix-agent.service" ];

      # Only run if token doesn't exist
      unitConfig = {
        ConditionPathExists = "!${cfg.tokenFile}";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      path = [ pkgs._1password-cli ];

      script = ''
        set -euo pipefail

        echo "Attempting to provision Cachix agent token from 1Password..."

        # Check if 1Password CLI is available and authenticated
        if ! command -v op &>/dev/null; then
          echo "ERROR: 1Password CLI (op) not found"
          echo "Manually create ${cfg.tokenFile} with: CACHIX_AGENT_TOKEN=<token>"
          exit 1
        fi

        # Try to fetch token (may fail if not authenticated)
        TOKEN=$(op read "${cfg.onePassword.tokenReference}" 2>/dev/null || true)

        if [ -n "$TOKEN" ]; then
          echo "CACHIX_AGENT_TOKEN=$TOKEN" > "${cfg.tokenFile}"
          chmod 600 "${cfg.tokenFile}"
          chown root:root "${cfg.tokenFile}"
          echo "Token provisioned successfully from 1Password"
        else
          echo "WARNING: Could not fetch token from 1Password"
          echo "This is expected on first boot before user login"
          echo "Manually create ${cfg.tokenFile} with: CACHIX_AGENT_TOKEN=<token>"
          echo "Or sign in to 1Password and run: systemctl restart cachix-token-provision"
        fi
      '';
    };

    # Activation script to warn about missing token
    system.activationScripts.cachix-deploy-check = ''
      if [ ! -f "${cfg.tokenFile}" ]; then
        echo ""
        echo "=========================================="
        echo "CACHIX DEPLOY: Agent token not found!"
        echo "=========================================="
        echo "Create token file at: ${cfg.tokenFile}"
        echo "Format: CACHIX_AGENT_TOKEN=<your-token>"
        echo ""
        echo "Get your token from: https://app.cachix.org/deploy/"
        echo "=========================================="
        echo ""
      fi
    '';
  };
}
