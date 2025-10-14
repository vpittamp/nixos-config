{ config, pkgs, lib, ... }:

{
  # Git credential OAuth - disabled in favor of 1Password integration
  programs.git-credential-oauth = {
    enable = false;  # We use 1Password git-credential-op instead
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Vinod Pittampalli";
    userEmail = "vinod@pittampalli.com";

    # SSH signing configuration with 1Password
    # All commits will be signed with SSH key from 1Password
    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7";
      signByDefault = true;  # Sign all commits by default for verification
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
          # On Darwin, op-ssh-sign is in the 1Password.app bundle
          # On Linux, it's in the Nix package
          program = if pkgs.stdenv.isDarwin
            then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
            else "${pkgs._1password-gui or pkgs._1password-cli}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };
      
      # Credential helpers - use 1Password for all Git operations
      # This replaces gh/glab credential helpers with unified 1Password integration
      # Note: On Darwin, 1Password CLI doesn't include git-credential helper
      # Use SSH authentication instead (configured above with op-ssh-sign)
      credential = lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
        # Primary credential helper: 1Password (Linux only)
        # This handles GitHub, GitLab, and all other Git remotes
        helper = "${pkgs._1password-gui or pkgs._1password}/libexec/git-credential-1password";
      };
    };
  };
  
  # Create the allowed signers file for SSH signing verification
  home.file.".config/git/allowed_signers".text = ''
    vinod@pittampalli.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7
  '';
}
