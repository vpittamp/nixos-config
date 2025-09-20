# 1Password System Configuration Module
# Provides centralized secret management and desktop integration
{ config, lib, pkgs, ... }:

let
  # Detect if we're in a headless environment (no GUI)
  hasGui = config.services.xserver.enable or false;
in
{
  # 1Password packages - GUI only if desktop is available
  environment.systemPackages = with pkgs; [
    _1password        # CLI tool (always needed)
  ] ++ lib.optionals hasGui [
    _1password-gui    # Desktop application (only with GUI)
  ];

  # Enable 1Password system services with proper NixOS configuration
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = hasGui;  # Only enable GUI program if desktop is available
    # This enables polkit integration for system authentication
    # The user can unlock 1Password with system password/fingerprint
    polkitPolicyOwners = lib.optionals hasGui [ "vpittamp" ];
  };
  
  # Note: polkit rules are automatically configured by polkitPolicyOwners
  # No manual polkit configuration needed - NixOS handles this properly

  # Git configuration - removed as it's handled in home-manager
  # The credential helpers are configured in home-modules/tools/git.nix

  # SSH configuration - disable default agent to use 1Password's
  programs.ssh.startAgent = false;
  
  # Configure SSH client to use 1Password agent (addresses GitHub issue #222991)
  programs.ssh.extraConfig = ''
    # Use 1Password SSH agent for all hosts
    Host *
      IdentityAgent ~/.1password/agent.sock
      # Allow 1Password to handle all SSH keys
      IdentitiesOnly yes
      # Prevent SSH from trying other authentication methods first
      PreferredAuthentications publickey
  '';
  
  # System-wide environment variables for 1Password
  environment.sessionVariables = {
    SSH_AUTH_SOCK = "/home/vpittamp/.1password/agent.sock";
    OP_BIOMETRIC_UNLOCK_ENABLED = if hasGui then "true" else "false";
    # For headless environments, use device mode
    OP_DEVICE = if hasGui then null else "hetzner-server";
  };
  
  # Polkit configuration is merged below with other polkit rules

  # XDG autostart for KDE Plasma and Chromium integration
  environment.etc = lib.mkMerge [
    # Minimal Chromium policy - only enable native messaging, no forced extensions
    {
      "chromium/policies/recommended/1password-support.json" = {
        text = builtins.toJSON {
          # Only configure what's necessary for 1Password to work
          # Using 'recommended' instead of 'managed' to avoid "managed by organization"
          
          # Enable native messaging for 1Password
          NativeMessagingAllowlist = [
            "com.1password.1password"
            "com.1password.browser_support"
          ];
          
          # Disable Chrome's password manager (user can override)
          PasswordManagerEnabled = false;
          
          # Enable autofill
          AutofillEnabled = true;
        };
        mode = "0644";
      };

      # Custom allowed browsers for 1Password
      "1password/custom_allowed_browsers" = {
        text = ''
          chromium
          chromium-browser
          chrome
          google-chrome
        '';
        mode = "0644";
      };

      # System-wide native messaging hosts for Chromium
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
    }
    (lib.mkIf hasGui {
      "xdg/autostart/1password.desktop".text = ''
        [Desktop Entry]
        Name=1Password
        GenericName=Password Manager
        Comment=1Password password manager
        Exec=env QT_SCALE_FACTOR=0.75 GDK_SCALE=1 GDK_DPI_SCALE=1 ${pkgs._1password-gui}/bin/1password --silent --unlock
        Terminal=false
        Type=Application
        Icon=1password
        StartupNotify=false
        Categories=Utility;Security;
        X-GNOME-Autostart-enabled=true
        X-KDE-autostart-after=panel
        X-KDE-autostart-phase=2
      '';
    })
    
    # 1Password SSH agent configuration
    # This enables SSH keys from all vaults to be available
    {
      "1password-ssh-agent.toml" = {
        target = "skel/.config/1Password/ssh/agent.toml";
        text = ''
          # 1Password SSH Agent Configuration
          # This file configures which SSH keys are available through the agent
          
          # Make all SSH keys from Personal vault available
          [[ssh-keys]]
          vault = "Personal"
          
          # Make all SSH keys from Private vault available (if exists)
          [[ssh-keys]]
          vault = "Private"
          
          # You can add specific keys like this:
          # [[ssh-keys]]
          # item = "GitHub SSH Key"
          # vault = "Personal"
        '';
      };
    }
  ];

  # User-specific configuration
  users.users.vpittamp = {
    extraGroups = [ "onepassword" "onepassword-cli" ];
  };

  # Create necessary directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /home/vpittamp/.1password 0700 vpittamp users -"
    "d /home/vpittamp/.config/op 0700 vpittamp users -"
    "d /home/vpittamp/.config/1Password 0700 vpittamp users -"
    "d /home/vpittamp/.config/1Password/ssh 0700 vpittamp users -"
  ];
  
  # Also create the config for the current user
  system.activationScripts.onePasswordSSHConfig = ''
    mkdir -p /home/vpittamp/.config/1Password/ssh
    cat > /home/vpittamp/.config/1Password/ssh/agent.toml << 'EOF'
    # 1Password SSH Agent Configuration
    # This file configures which SSH keys are available through the agent
    
    # Make all SSH keys from Personal vault available
    [[ssh-keys]]
    vault = "Personal"
    
    # Make all SSH keys from Private vault available (if exists)
    [[ssh-keys]]
    vault = "Private"
    EOF
    chown -R vpittamp:users /home/vpittamp/.config/1Password
    chmod 700 /home/vpittamp/.config/1Password
    chmod 700 /home/vpittamp/.config/1Password/ssh
    chmod 600 /home/vpittamp/.config/1Password/ssh/agent.toml
  '';

  # Enable system authentication for 1Password
  # This allows using system password/biometrics instead of master password
  security.polkit.enable = true;
  
  # Polkit rules for 1Password system authentication and SSH agent
  security.polkit.extraConfig = lib.mkIf hasGui ''
    // Allow 1Password to use system authentication service
    polkit.addRule(function(action, subject) {
      if (action.id == "com.1password.1Password.authorizationhelper" ||
          action.id == "com.onepassword.op.authorizationhelper" ||
          action.id == "com.1password.1password.authprompt") {
        if (subject.user == "vpittamp") {
          // Skip extra authentication challenges for trusted local user
          return polkit.Result.YES;
        }
      }
    });
    
    // Allow 1Password to prompt for SSH key usage (addresses GitHub issue #222991)
    polkit.addRule(function(action, subject) {
      if (action.id == "com.1password.1Password.authorizeSshAgent" &&
          subject.user == "vpittamp") {
        return polkit.Result.YES;
      }
    });
  '';


  # Create 1Password directories but DO NOT overwrite settings
  # Settings must be configured through the 1Password GUI and will persist
  system.activationScripts.onePasswordSettings = ''
    # Only create directories, never overwrite the settings file
    mkdir -p /home/vpittamp/.config/1Password/settings
    
    # Fix permissions on directories only
    chown -R vpittamp:users /home/vpittamp/.config/1Password
    chmod 700 /home/vpittamp/.config/1Password
    chmod 700 /home/vpittamp/.config/1Password/settings
    
    # If settings file exists, preserve it with correct permissions
    if [ -f /home/vpittamp/.config/1Password/settings/settings.json ]; then
      chown vpittamp:users /home/vpittamp/.config/1Password/settings/settings.json
      chmod 600 /home/vpittamp/.config/1Password/settings/settings.json
    fi
  '';

  # Systemd service to ensure 1Password starts properly (only with GUI)
  systemd.user.services.onepassword-gui = lib.mkIf hasGui {
    description = "1Password Desktop Application";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    
    serviceConfig = {
      Type = "forking";
      # QT_SCALE_FACTOR=0.75 makes 1Password smaller on HiDPI displays
      # --silent starts minimized, --unlock prompts for unlock immediately
      ExecStart = "${pkgs.bash}/bin/bash -c 'QT_SCALE_FACTOR=0.75 GDK_SCALE=1 GDK_DPI_SCALE=1 ${pkgs._1password-gui}/bin/1password --silent --unlock'";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "DISPLAY=:0"
        "SSH_AUTH_SOCK=/home/vpittamp/.1password/agent.sock"
      ];
    };
  };
}
