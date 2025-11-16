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
        # Explicitly use 1Password SSH agent for git operations
        # This ensures SSH auth works even in subprocesses without SSH_AUTH_SOCK
        sshCommand = "ssh -o IdentityAgent=~/.1password/agent.sock";
      };
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      
      # SSH signing configuration
      gpg = {
        format = "ssh";
        ssh = {
          program = "${pkgs._1password-gui or pkgs._1password-cli}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };
      
      # Credential helpers - disabled for SSH-only authentication
      # We use SSH keys via 1Password SSH agent instead of HTTPS credential helpers
      # If you need HTTPS authentication, consider using git-credential-oauth
      # credential = {
      #   helper = "${pkgs.git-credential-oauth}/bin/git-credential-oauth";
      # };
    };
  };
  
  # Create the allowed signers file for SSH signing verification
  home.file.".config/git/allowed_signers".text = ''
    vinod@pittampalli.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7
  '';
}
