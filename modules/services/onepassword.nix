# 1Password System Configuration Module
# Provides centralized secret management and desktop integration
{ config, lib, pkgs, ... }:

{
  # 1Password desktop application and CLI
  environment.systemPackages = with pkgs; [
    _1password-gui
    _1password
  ];

  # Enable 1Password system services
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "vpittamp" ];
  };

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
    
    # Fix 1Password Qt scaling on Retina display
    # 1Password uses Qt, so we need to set Qt-specific scaling
    QT_SCALE_FACTOR_1PASSWORD = "0.6";  # Scale down 1Password specifically for Retina
  };

  # XDG autostart for KDE Plasma
  environment.etc."xdg/autostart/1password.desktop".text = ''
    [Desktop Entry]
    Name=1Password
    GenericName=Password Manager
    Comment=1Password password manager
    Exec=env QT_AUTO_SCREEN_SCALE_FACTOR=1 ${pkgs._1password-gui}/bin/1password --silent
    Terminal=false
    Type=Application
    Icon=1password
    StartupNotify=false
    Categories=Utility;Security;
    X-GNOME-Autostart-enabled=true
    X-KDE-autostart-after=panel
    X-KDE-autostart-phase=2
  '';

  # User-specific configuration
  users.users.vpittamp = {
    extraGroups = [ "onepassword" "onepassword-cli" ];
  };

  # Create necessary directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /home/vpittamp/.1password 0700 vpittamp users -"
    "d /home/vpittamp/.config/op 0700 vpittamp users -"
  ];

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
        "QT_AUTO_SCREEN_SCALE_FACTOR=1"
      ];
    };
  };
}