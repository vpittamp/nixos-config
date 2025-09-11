{ config, pkgs, lib, ... }:

{
  # Git credential OAuth - disabled to avoid conflicts
  programs.git-credential-oauth = {
    enable = false;  # We'll use GitHub CLI instead
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Vinod Pittampalli";
    userEmail = "vinod@pittampalli.com";
    
    # SSH signing configuration with 1Password
    signing = {
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
      
      # SSH signing configuration
      gpg = {
        format = "ssh";
        ssh = {
          program = "${pkgs._1password-gui or pkgs._1password}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };
      
      # Credential helpers - simplified configuration
      credential = {
        helper = "cache --timeout=3600";  # Cache credentials for 1 hour
        "https://github.com" = {
          helper = "!gh auth git-credential";  # Use GitHub CLI
        };
        "https://gitlab.com" = {
          helper = "!glab auth git-credential";  # Use GitLab CLI
        };
      };
    };
  };
  
  # Create the allowed signers file for SSH signing verification
  home.file.".config/git/allowed_signers".text = ''
    vinod@pittampalli.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7
  '';
}