# 1Password System Configuration Module
# Provides centralized secret management and desktop integration
{ config, lib, pkgs, ... }:

{
  # 1Password desktop application and CLI
  environment.systemPackages = with pkgs; [
    _1password-gui    # Desktop application
    _1password        # CLI tool
  ];

  # Enable 1Password system services
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "vpittamp" ];
  };
  
  # Ensure polkit is enabled and running
  security.polkit.enable = true;
  
  # Add polkit rules for 1Password
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "com.1password.1Password.authorizationhelper" &&
          subject.user == "vpittamp") {
        return polkit.Result.YES;
      }
    });
  '';

  # Git configuration with 1Password integration
  programs.git = {
    enable = true;
    config = {
      credential = {
        helper = "${pkgs._1password-gui}/share/1password/op-ssh-sign";
        "https://github.com" = {
          helper = "${pkgs._1password}/bin/op plugin run -- gh auth git-credential";
        };
        "https://gitlab.com" = {
          helper = "${pkgs._1password}/bin/op plugin run -- glab auth git-credential";
        };
      };
    };
  };

  # SSH configuration - disable default agent to use 1Password's
  programs.ssh.startAgent = false;
  
  # System-wide environment variables for 1Password
  environment.sessionVariables = {
    SSH_AUTH_SOCK = "/home/vpittamp/.1password/agent.sock";
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };

  # XDG autostart for KDE Plasma
  environment.etc."xdg/autostart/1password.desktop".text = ''
    [Desktop Entry]
    Name=1Password
    GenericName=Password Manager
    Comment=1Password password manager
    Exec=${pkgs._1password-gui}/bin/1password --silent
    Terminal=false
    Type=Application
    Icon=1password
    StartupNotify=false
    Categories=Utility;Security;
    X-GNOME-Autostart-enabled=true
    X-KDE-autostart-after=panel
    X-KDE-autostart-phase=2
  '';
  
  # Alternative desktop entry for manual scaling control
  environment.etc."applications/1password-scaled.desktop" = {
    text = ''
      [Desktop Entry]
      Name=1Password (Scaled)
      GenericName=Password Manager
      Comment=1Password with custom scaling for HiDPI
      Exec=env QT_SCALE_FACTOR=0.75 ${pkgs._1password-gui}/bin/1password
      Terminal=false
      Type=Application
      Icon=1password
      StartupNotify=true
      Categories=Utility;Security;
      NoDisplay=false
    '';
    mode = "0644";
  };

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
  
  # 1Password SSH agent configuration
  # This enables SSH keys from all vaults to be available
  environment.etc."1password-ssh-agent.toml" = {
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

  # Systemd service to ensure 1Password starts properly
  systemd.user.services.onepassword-gui = {
    description = "1Password Desktop Application";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    
    serviceConfig = {
      Type = "forking";
      ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "DISPLAY=:0"
        "SSH_AUTH_SOCK=/home/vpittamp/.1password/agent.sock"
      ];
    };
  };
}