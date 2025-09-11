{ config, pkgs, lib, ... }:

let
  # Detect if 1Password desktop is available
  hasOnePasswordDesktop = builtins.pathExists "/home/vpittamp/.1password/agent.sock";
  
  # Detect if we're on a server (Hetzner)
  isServer = config.networking.hostName or "" == "nixos-hetzner";
  
  # Use 1Password signing on workstations, disable on servers
  enableSigning = !isServer;
in
{
  # Git credential OAuth for seamless authentication
  programs.git-credential-oauth = {
    enable = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Vinod Pittampalli";
    userEmail = "vinod@pittampalli.com";
    
    # SSH signing configuration (only on workstations with 1Password)
    signing = lib.mkIf enableSigning {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7";
      signByDefault = true;
    };
    
    aliases = {
      co = "checkout";
      ci = "commit";
      st = "status";
      br = "branch";
      hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
      type = "cat-file -t";
      dump = "cat-file -p";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      last = "log -1 HEAD";
      unstage = "reset HEAD --";
    };
    
    extraConfig = {
      init.defaultBranch = "main";
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      
      # SSH signing configuration (only on workstations)
      gpg = lib.mkIf enableSigning {
        format = "ssh";
        ssh = {
          program = "${pkgs._1password-gui or pkgs._1password}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };
      
      # Credential helpers - use OAuth for all, 1Password only on workstations
      credential = {
        helper = if enableSigning then [
          "oauth"  # Use OAuth as primary
          "${pkgs._1password-gui or pkgs._1password}/share/1password/op-ssh-sign"
        ] else [
          "oauth"  # OAuth only on servers
        ];
        "https://github.com" = lib.mkIf enableSigning {
          helper = "!${pkgs._1password}/bin/op plugin run -- gh auth git-credential";
        };
        "https://gitlab.com" = lib.mkIf enableSigning {
          helper = "!${pkgs._1password}/bin/op plugin run -- glab auth git-credential";
        };
      };
    };
  };
  
  # Create the allowed signers file for SSH signing verification
  home.file.".config/git/allowed_signers".text = ''
    vinod@pittampalli.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7
  '';
}