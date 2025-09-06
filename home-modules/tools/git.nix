{ config, pkgs, lib, ... }:

{
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
      
      credential = {
        "https://github.com" = {
          helper = "!gh auth git-credential";
        };
        "https://gist.github.com" = {
          helper = "!gh auth git-credential";
        };
      } // lib.optionalAttrs (pkgs.stdenv.isLinux) {
        helper = "/mnt/c/Program\\ Files/Git/mingw64/bin/git-credential-manager.exe";
      };
      
    };
  };
}