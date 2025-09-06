{ config, pkgs, lib, ... }:

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
    
    aliases = {
      co = "checkout";
      ci = "commit";
      st = "status";
      br = "branch";
      hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
      type = "cat-file -t";
      dump = "cat-file -p";
    };
    
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      
      # Use OAuth as the primary credential helper - works seamlessly without manual auth
      credential.helper = [
        "oauth"  # Primary: git-credential-oauth for all hosts
        "!gh auth git-credential"  # Fallback: GitHub CLI if oauth fails
      ];
      
    };
  };
}