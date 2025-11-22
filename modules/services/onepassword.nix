# Consolidated 1Password System Configuration Module
# Provides centralized secret management with feature flags for different use cases
# Consolidates: onepassword.nix + onepassword-automation.nix + onepassword-password-management.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.onepassword;

  # Detect if we're in a headless environment (no GUI)
  hasGui = (config.services.xserver.enable or false) || (config.services.sway.enable or false);
in
{
  options.services.onepassword = {
    enable = mkEnableOption "1Password integration";

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "User to run 1Password services as";
    };

    gui = {
      enable = mkOption {
        type = types.bool;
        default = hasGui;
        description = ''
          Enable 1Password GUI application.
          Includes desktop app, polkit integration, and browser support.
          Automatically enabled when X11 or Sway is detected.
        '';
      };

      polkitPolicyOwners = mkOption {
        type = types.listOf types.str;
        default = [ cfg.user ];
        description = "Users allowed to use 1Password system authentication";
      };
    };

    automation = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable service account automation for headless operation.
          Provides automated authentication using service account tokens.
        '';
      };

      tokenReference = mkOption {
        type = types.str;
        default = "op://Employee/ja6iykklyslhq7tccnkgaj4joe/credential";
        description = "1Password secret reference for the service account token (using item ID)";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = "/var/lib/onepassword/service-account-token";
        description = "Path to service account token file";
      };
    };

    passwordManagement = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable automatic password sync from 1Password to NixOS.
          Requires automation to be enabled for service account access.
        '';
      };

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

      updateInterval = mkOption {
        type = types.str;
        default = "hourly";
        description = "How often to check for password updates (systemd timer format: hourly, daily, etc.)";
      };
    };

    ssh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable 1Password SSH agent integration";
      };

      vaults = mkOption {
        type = types.listOf types.str;
        default = [ "Personal" "Private" ];
        description = "Vaults to make SSH keys available from";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ========== BASE CONFIGURATION ==========
    # Always applied when 1Password is enabled
    {
      # Core packages - CLI always, GUI conditionally
      environment.systemPackages = with pkgs; [
        _1password-cli
      ] ++ optionals cfg.gui.enable [
        _1password-gui
      ];

      # Enable 1Password system integration
      programs._1password.enable = true;

      # User groups
      users.users.${cfg.user}.extraGroups = [
        "onepassword"
        "onepassword-cli"
      ];

      # Create base directories
      systemd.tmpfiles.rules = [
        "d /home/${cfg.user}/.1password 0700 ${cfg.user} users -"
        "d /home/${cfg.user}/.config/op 0700 ${cfg.user} users -"
        "d /home/${cfg.user}/.config/1Password 0700 ${cfg.user} users -"
        "d /home/${cfg.user}/.config/1Password/ssh 0700 ${cfg.user} users -"
      ];

      # Environment variables
      environment.sessionVariables = {
        SSH_AUTH_SOCK = "/home/${cfg.user}/.1password/agent.sock";
        OP_BIOMETRIC_UNLOCK_ENABLED = if cfg.gui.enable then "true" else "false";
        OP_DEVICE = if cfg.gui.enable then null else "hetzner-server";
      };
    }

    # ========== GUI CONFIGURATION ==========
    # Enabled when GUI is available
    (mkIf cfg.gui.enable {
      # GUI program configuration
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = cfg.gui.polkitPolicyOwners;
      };

      # Chromium integration
      environment.etc = {
        # Chromium policy - minimal configuration
        "chromium/policies/recommended/1password-support.json" = {
          text = builtins.toJSON {
            NativeMessagingAllowlist = [
              "com.1password.1password"
              "com.1password.browser_support"
            ];
            PasswordManagerEnabled = false;
            AutofillEnabled = true;
          };
          mode = "0644";
        };

        # Custom allowed browsers
        "1password/custom_allowed_browsers" = {
          text = ''
            chromium
            chromium-browser
            chrome
            google-chrome
          '';
          mode = "0644";
        };

        # Native messaging hosts for Chromium
        "chromium/native-messaging-hosts/com.1password.1password.json" = {
          text = builtins.toJSON {
            name = "com.1password.1password";
            description = "1Password Native Messaging Host";
            type = "stdio";
            allowed_origins = [
              "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
            ];
            path = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
          };
          mode = "0644";
        };

        "chromium/native-messaging-hosts/com.1password.browser_support.json" = {
          text = builtins.toJSON {
            name = "com.1password.browser_support";
            description = "1Password Browser Support";
            type = "stdio";
            allowed_origins = [
              "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
            ];
            path = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
          };
          mode = "0644";
        };
      };

      # Polkit configuration for system authentication
      security.polkit.enable = true;
      security.polkit.extraConfig = ''
        // Allow 1Password to use system authentication service
        polkit.addRule(function(action, subject) {
          if (action.id == "com.1password.1Password.authorizationhelper" ||
              action.id == "com.onepassword.op.authorizationhelper" ||
              action.id == "com.1password.1password.authprompt") {
            if (subject.user == "${cfg.user}") {
              return polkit.Result.YES;
            }
          }
        });

        // Allow 1Password to prompt for SSH key usage
        polkit.addRule(function(action, subject) {
          if (action.id == "com.1password.1Password.authorizeSshAgent" &&
              subject.user == "${cfg.user}") {
            return polkit.Result.YES;
          }
        });
      '';

      # Create 1Password directories without overwriting settings
      system.activationScripts.onePasswordSettings = ''
        mkdir -p /home/${cfg.user}/.config/1Password/settings
        chown -R ${cfg.user}:users /home/${cfg.user}/.config/1Password
        chmod 700 /home/${cfg.user}/.config/1Password
        chmod 700 /home/${cfg.user}/.config/1Password/settings

        # Preserve existing settings file
        if [ -f /home/${cfg.user}/.config/1Password/settings/settings.json ]; then
          chown ${cfg.user}:users /home/${cfg.user}/.config/1Password/settings/settings.json
          chmod 600 /home/${cfg.user}/.config/1Password/settings/settings.json
        fi
      '';
    })

    # ========== SSH INTEGRATION ==========
    # Enabled by default unless explicitly disabled
    (mkIf cfg.ssh.enable {
      # Disable default SSH agent
      programs.ssh.startAgent = false;

      # Configure SSH client to use 1Password agent
      programs.ssh.extraConfig = ''
        # Use 1Password SSH agent for all hosts
        Host *
          IdentityAgent ~/.1password/agent.sock
          IdentitiesOnly yes
          PreferredAuthentications publickey
      '';

      # SSH agent configuration file
      environment.etc."1password-ssh-agent.toml" = {
        target = "skel/.config/1Password/ssh/agent.toml";
        text = ''
          # 1Password SSH Agent Configuration
          # Make all SSH keys from configured vaults available

          ${concatMapStringsSep "\n" (vault: ''
            [[ssh-keys]]
            vault = "${vault}"
          '') cfg.ssh.vaults}
        '';
      };

      # Ensure SSH agent config exists for current user
      system.activationScripts.onePasswordSSHConfig = ''
        mkdir -p /home/${cfg.user}/.config/1Password/ssh
        cat > /home/${cfg.user}/.config/1Password/ssh/agent.toml << 'EOF'
        # 1Password SSH Agent Configuration
        ${concatMapStringsSep "\n" (vault: ''
          [[ssh-keys]]
          vault = "${vault}"
        '') cfg.ssh.vaults}
        EOF
        chown -R ${cfg.user}:users /home/${cfg.user}/.config/1Password
        chmod 700 /home/${cfg.user}/.config/1Password/ssh
        chmod 600 /home/${cfg.user}/.config/1Password/ssh/agent.toml
      '';
    })

    # ========== AUTOMATION CONFIGURATION ==========
    # Service account token management for headless operation
    (mkIf cfg.automation.enable {
      # Token storage directory
      systemd.tmpfiles.rules = [
        "d /var/lib/onepassword 0700 ${cfg.user} users -"
      ];

      # Environment file for token retrieval
      environment.etc."onepassword/service-token.env" = {
        mode = "0600";
        user = cfg.user;
        text = ''
          # 1Password Service Account Token
          # Dynamically fetch from 1Password using secret reference
          export OP_SERVICE_ACCOUNT_TOKEN="$(op read '${cfg.automation.tokenReference}')"
        '';
      };

      # Setup script
      environment.etc."nixos/scripts/1password-setup-token.sh" = {
        mode = "0755";
        text = ''
          #!/usr/bin/env bash
          set -e

          echo "Setting up 1Password service account token..."

          # Check if already logged in
          if ! op account list | grep -q "vinod@pittampalli.com"; then
            echo "Please sign in to your personal 1Password account first:"
            eval $(op signin)
          fi

          # Fetch token
          echo "Fetching service account token from 1Password..."
          TOKEN=$(op read '${cfg.automation.tokenReference}')

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

      # Token loader script
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

      # Shell aliases for convenience
      programs.bash.shellAliases = {
        "op-auth" = "source /etc/onepassword/load-token.sh";
        "git-push" = "source /etc/onepassword/load-token.sh && git push";
        "git-pull" = "source /etc/onepassword/load-token.sh && git pull";
        "git-fetch" = "source /etc/onepassword/load-token.sh && git fetch";
        "op-setup" = "sudo /etc/nixos/scripts/1password-setup-token.sh";
      };

      # Auto-load token in shell
      environment.interactiveShellInit = ''
        # Auto-load 1Password service account token if available
        if [ -f /var/lib/onepassword/service-account-token ]; then
          export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"
          export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
        fi
      '';

      # Setup activation script
      system.activationScripts.onePasswordServiceAccount = ''
        mkdir -p /var/lib/onepassword
        chmod 700 /var/lib/onepassword
        chown ${cfg.user}:users /var/lib/onepassword
      '';
    })

    # ========== PASSWORD MANAGEMENT ==========
    # Automatic password sync from 1Password to NixOS
    (mkIf cfg.passwordManagement.enable {
      # Ensure automation is enabled (required for service account access)
      assertions = [
        {
          assertion = cfg.automation.enable;
          message = "Password management requires automation to be enabled (services.onepassword.automation.enable = true)";
        }
      ];

      # Password storage directories
      systemd.tmpfiles.rules = [
        "d /run/secrets 0755 root root -"
        "d /var/lib/onepassword-passwords 0700 root root -"
      ];

      # Password sync service
      systemd.services.onepassword-password-sync = {
        description = "Sync user passwords from 1Password";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
        };

        script = ''
          set -e

          # Check for service account token
          if [ ! -f /var/lib/onepassword/service-account-token ]; then
            echo "Error: Service account token not found at /var/lib/onepassword/service-account-token"
            echo "Please run: sudo /etc/nixos/scripts/1password-setup-token.sh"
            exit 1
          fi

          # Load token
          export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"

          # Sync each user's password
          ${concatStringsSep "\n" (mapAttrsToList (username: userCfg: ''
            if [ "${toString userCfg.enable}" = "1" ]; then
              echo "Syncing password for user: ${username}"

              # Fetch password from 1Password
              PASSWORD=$(${pkgs._1password-cli}/bin/op read '${userCfg.passwordReference}' 2>/dev/null || echo "")

              if [ -z "$PASSWORD" ]; then
                echo "Warning: Could not fetch password for ${username} from 1Password"
              else
                # Generate password hash
                PASSWORD_HASH=$(echo -n "$PASSWORD" | ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s)

                # Write to secure location
                echo -n "$PASSWORD_HASH" > /run/secrets/${username}-password
                chmod 600 /run/secrets/${username}-password

                echo "Password hash updated for ${username}"
              fi
            fi
          '') cfg.passwordManagement.users)}

          echo "Password sync completed"
        '';
      };

      # Timer for periodic sync
      systemd.timers.onepassword-password-sync = {
        description = "Timer for 1Password password sync";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.passwordManagement.updateInterval;
          Persistent = true;
        };
      };

      # Configure users to use password files
      users.users = mapAttrs (username: userCfg: {
        hashedPasswordFile = mkIf userCfg.enable "/run/secrets/${username}-password";
      }) cfg.passwordManagement.users;

      # Initial password sync activation script
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
    })
  ]);
}
