# 1Password Integration Module
# Provides centralized secret management and authentication
{ config, lib, pkgs, ... }:

{
  # 1Password desktop application and CLI
  home.packages = with pkgs; [
    _1password-gui       # Desktop application
    _1password           # CLI tool (op command)
  ];

  # 1Password SSH agent configuration
  programs.ssh = {
    enable = true;
    extraConfig = ''
      # Use 1Password SSH agent for all hosts
      Host *
        IdentityAgent "~/.1password/agent.sock"
        # Fallback to standard keys if 1Password is unavailable
        AddKeysToAgent yes
        IdentitiesOnly yes
    '';
  };

  # Git configuration to use 1Password for credentials
  programs.git = {
    enable = true;
    
    extraConfig = {
      # Use 1Password for HTTPS authentication
      credential = {
        helper = "${pkgs._1password-gui}/share/1password/op-ssh-sign";
        "https://github.com" = {
          helper = "${pkgs._1password}/bin/op plugin run -- gh auth git-credential";
        };
        "https://gitlab.com" = {
          helper = "${pkgs._1password}/bin/op plugin run -- glab auth git-credential";
        };
      };
      
      # SSH signing with 1Password
      user.signingkey = "op://Personal/SSH Signing Key/public-key";
      commit.gpgsign = true;
      gpg.format = "ssh";
      gpg.ssh.program = "${pkgs._1password-gui}/bin/op-ssh-sign";
    };
  };

  # Environment variables for 1Password CLI
  home.sessionVariables = {
    # Enable biometric unlock for CLI
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
    
    # Set the default account for op commands
    OP_ACCOUNT = "my.1password.com";
    
    # Enable 1Password SSH agent
    SSH_AUTH_SOCK = "~/.1password/agent.sock";
  };

  # 1Password CLI plugins configuration
  home.file.".config/op/plugins.sh" = {
    text = ''
      # 1Password CLI plugins for various tools
      
      # GitHub CLI
      alias gh='op plugin run -- gh'
      
      # GitLab CLI
      alias glab='op plugin run -- glab'
      
      # AWS CLI
      alias aws='op plugin run -- aws'
      
      # Stripe CLI
      alias stripe='op plugin run -- stripe'
      
      # npm/yarn with registry credentials
      alias npm='op plugin run -- npm'
      alias yarn='op plugin run -- yarn'
    '';
    executable = false;
  };

  # Source 1Password plugins in shell
  programs.bash.initExtra = ''
    # Source 1Password CLI plugins
    if [ -f ~/.config/op/plugins.sh ]; then
      source ~/.config/op/plugins.sh
    fi
    
    # Initialize 1Password SSH agent socket
    export SSH_AUTH_SOCK=~/.1password/agent.sock
    
    # Function to unlock 1Password vault
    op-unlock() {
      eval $(op signin)
    }
    
    # Function to get secret from 1Password
    op-get() {
      op item get "$1" --fields "$2"
    }
    
    # Function to inject secrets into environment
    op-env() {
      op run --env-file="$1" -- "$\{@:2\}"
    }
  '';

  # Systemd user service to ensure 1Password is running
  systemd.user.services.onepassword = {
    Unit = {
      Description = "1Password Desktop Application";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    
    Service = {
      Type = "forking";
      ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
      Restart = "on-failure";
      RestartSec = 5;
    };
    
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # XDG autostart for 1Password
  xdg.configFile."autostart/1password.desktop" = {
    text = ''
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
    '';
  };

  # 1Password browser extension native messaging host
  home.file.".mozilla/native-messaging-hosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      path = "${pkgs._1password}/bin/op-browser-support";
      type = "stdio";
      allowed_extensions = [
        "{d634138d-c276-4fc8-924b-40a0ea21d284}"
        "khgocmkkpikpnmmkgmdnfckapcdkgfaf@1password.com"
      ];
    };
  };

  # Chrome/Chromium native messaging host
  home.file.".config/google-chrome/NativeMessagingHosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      path = "${pkgs._1password}/bin/op-browser-support";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
        "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/"
      ];
    };
  };
}